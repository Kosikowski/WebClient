import Foundation

/// A cache entry containing the cached response data and metadata.
public struct CacheEntry: Sendable {
    /// The cached response data.
    public let data: Data

    /// The HTTP response associated with the cached data.
    public let response: HTTPURLResponse

    /// The time when this entry was cached.
    public let cachedAt: Date

    /// The time-to-live for this entry.
    public let ttl: Duration

    /// The ETag header value, if present.
    public let etag: String?

    /// The Last-Modified header value, if present.
    public let lastModified: String?

    /// Whether this cache entry has expired.
    public var isExpired: Bool {
        Date.now.timeIntervalSince(cachedAt) > ttl.timeInterval
    }

    public init(
        data: Data,
        response: HTTPURLResponse,
        cachedAt: Date = .now,
        ttl: Duration,
        etag: String? = nil,
        lastModified: String? = nil
    ) {
        self.data = data
        self.response = response
        self.cachedAt = cachedAt
        self.ttl = ttl
        self.etag = etag
        self.lastModified = lastModified
    }
}

/// Cache policy determining how responses should be cached.
public enum CachePolicy: Sendable {
    /// Never cache responses.
    case never

    /// Cache responses with a specified TTL.
    case ttl(Duration)

    /// Use HTTP cache headers (Cache-Control, Expires, ETag, Last-Modified).
    case httpHeaders

    /// Cache with TTL but also use conditional requests for revalidation.
    case revalidate(maxAge: Duration)
}

/// A protocol for response caching implementations.
public protocol ResponseCaching: Actor {
    /// Retrieves a cached response for the given request.
    /// - Parameter request: The URL request to look up.
    /// - Returns: The cached entry if available and not expired, nil otherwise.
    func get(for request: URLRequest) async -> CacheEntry?

    /// Stores a response in the cache.
    /// - Parameters:
    ///   - entry: The cache entry to store.
    ///   - request: The URL request associated with this response.
    func set(_ entry: CacheEntry, for request: URLRequest) async

    /// Removes a cached response for the given request.
    /// - Parameter request: The URL request to remove from cache.
    func remove(for request: URLRequest) async

    /// Removes all cached responses.
    func removeAll() async

    /// Removes all expired entries from the cache.
    func removeExpired() async
}

/// An in-memory response cache with LRU eviction.
public actor MemoryCache: ResponseCaching {
    private var cache: [String: CacheEntry] = [:]
    private var accessOrder: [String] = []
    private let maxEntries: Int
    private let maxSize: Int
    private var currentSize: Int = 0

    /// Creates a new memory cache.
    /// - Parameters:
    ///   - maxEntries: Maximum number of entries to store. Defaults to 100.
    ///   - maxSize: Maximum total size in bytes. Defaults to 50MB.
    public init(maxEntries: Int = 100, maxSize: Int = 50 * 1024 * 1024) {
        self.maxEntries = maxEntries
        self.maxSize = maxSize
    }

    public func get(for request: URLRequest) async -> CacheEntry? {
        let key = cacheKey(for: request)
        guard let entry = cache[key] else { return nil }

        if entry.isExpired {
            await remove(for: request)
            return nil
        }

        // Update access order for LRU
        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }

        return entry
    }

    public func set(_ entry: CacheEntry, for request: URLRequest) async {
        let key = cacheKey(for: request)
        let entrySize = entry.data.count

        // Remove existing entry if present
        if let existing = cache[key] {
            currentSize -= existing.data.count
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
        }

        // Evict entries if needed
        while currentSize + entrySize > maxSize || cache.count >= maxEntries {
            guard !accessOrder.isEmpty else { break }
            let oldestKey = accessOrder.removeFirst()
            if let removed = cache.removeValue(forKey: oldestKey) {
                currentSize -= removed.data.count
            }
        }

        // Store new entry
        cache[key] = entry
        accessOrder.append(key)
        currentSize += entrySize
    }

    public func remove(for request: URLRequest) async {
        let key = cacheKey(for: request)
        if let removed = cache.removeValue(forKey: key) {
            currentSize -= removed.data.count
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
        }
    }

    public func removeAll() async {
        cache.removeAll()
        accessOrder.removeAll()
        currentSize = 0
    }

    public func removeExpired() async {
        let expiredKeys = cache.filter { $0.value.isExpired }.map { $0.key }
        for key in expiredKeys {
            if let removed = cache.removeValue(forKey: key) {
                currentSize -= removed.data.count
                if let index = accessOrder.firstIndex(of: key) {
                    accessOrder.remove(at: index)
                }
            }
        }
    }

    private func cacheKey(for request: URLRequest) -> String {
        var key = request.url?.absoluteString ?? ""
        if let method = request.httpMethod {
            key = "\(method):\(key)"
        }
        return key
    }
}

/// A disk-based response cache using the file system.
public actor DiskCache: ResponseCaching {
    private let cacheDirectory: URL
    private let maxSize: Int
    private let fileManager = FileManager.default

    /// Creates a new disk cache.
    /// - Parameters:
    ///   - directory: The directory to store cached files. Defaults to system caches directory.
    ///   - maxSize: Maximum total size in bytes. Defaults to 100MB.
    public init(
        directory: URL? = nil,
        maxSize: Int = 100 * 1024 * 1024
    ) {
        if let directory {
            cacheDirectory = directory
        } else {
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            cacheDirectory = caches.appendingPathComponent("WebClientCache", isDirectory: true)
        }
        self.maxSize = maxSize

        // Ensure cache directory exists
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func get(for request: URLRequest) async -> CacheEntry? {
        let fileURL = cacheFileURL(for: request)
        let metadataURL = metadataFileURL(for: request)

        guard fileManager.fileExists(atPath: fileURL.path),
              fileManager.fileExists(atPath: metadataURL.path)
        else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let metadataData = try Data(contentsOf: metadataURL)
            let metadata = try JSONDecoder().decode(CacheMetadata.self, from: metadataData)

            guard let url = URL(string: metadata.urlString),
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: metadata.statusCode,
                      httpVersion: nil,
                      headerFields: metadata.headers
                  )
            else {
                return nil
            }

            let entry = CacheEntry(
                data: data,
                response: response,
                cachedAt: metadata.cachedAt,
                ttl: .seconds(metadata.ttlSeconds),
                etag: metadata.etag,
                lastModified: metadata.lastModified
            )

            if entry.isExpired {
                await remove(for: request)
                return nil
            }

            // Update access time
            try? fileManager.setAttributes(
                [.modificationDate: Date.now],
                ofItemAtPath: fileURL.path
            )

            return entry
        } catch {
            return nil
        }
    }

    public func set(_ entry: CacheEntry, for request: URLRequest) async {
        let fileURL = cacheFileURL(for: request)
        let metadataURL = metadataFileURL(for: request)

        // Evict if needed
        await evictIfNeeded(requiredSpace: entry.data.count)

        do {
            try entry.data.write(to: fileURL)

            let metadata = CacheMetadata(
                urlString: entry.response.url?.absoluteString ?? "",
                statusCode: entry.response.statusCode,
                headers: entry.response.allHeaderFields as? [String: String] ?? [:],
                cachedAt: entry.cachedAt,
                ttlSeconds: Int(entry.ttl.timeInterval),
                etag: entry.etag,
                lastModified: entry.lastModified
            )

            let metadataData = try JSONEncoder().encode(metadata)
            try metadataData.write(to: metadataURL)
        } catch {
            // Silently fail - caching is best-effort
        }
    }

    public func remove(for request: URLRequest) async {
        let fileURL = cacheFileURL(for: request)
        let metadataURL = metadataFileURL(for: request)

        try? fileManager.removeItem(at: fileURL)
        try? fileManager.removeItem(at: metadataURL)
    }

    public func removeAll() async {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func removeExpired() async {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let metadataFiles = contents.filter { $0.pathExtension == "metadata" }

        for metadataURL in metadataFiles {
            guard let metadataData = try? Data(contentsOf: metadataURL),
                  let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metadataData)
            else {
                continue
            }

            let ttl = Duration.seconds(metadata.ttlSeconds)
            let isExpired = Date.now.timeIntervalSince(metadata.cachedAt) > ttl.timeInterval

            if isExpired {
                let dataURL = metadataURL.deletingPathExtension().appendingPathExtension("data")
                try? fileManager.removeItem(at: dataURL)
                try? fileManager.removeItem(at: metadataURL)
            }
        }
    }

    private func cacheFileURL(for request: URLRequest) -> URL {
        let key = cacheKey(for: request)
        return cacheDirectory.appendingPathComponent("\(key).data")
    }

    private func metadataFileURL(for request: URLRequest) -> URL {
        let key = cacheKey(for: request)
        return cacheDirectory.appendingPathComponent("\(key).metadata")
    }

    private func cacheKey(for request: URLRequest) -> String {
        var key = request.url?.absoluteString ?? ""
        if let method = request.httpMethod {
            key = "\(method):\(key)"
        }
        // Create a safe filename using hash
        return String(key.hash, radix: 16)
    }

    private func evictIfNeeded(requiredSpace: Int) async {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        var totalSize = 0
        var files: [(url: URL, size: Int, date: Date)] = []

        for url in contents where url.pathExtension == "data" {
            if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
               let size = values.fileSize,
               let date = values.contentModificationDate
            {
                totalSize += size
                files.append((url, size, date))
            }
        }

        // Sort by access date (oldest first)
        files.sort { $0.date < $1.date }

        // Evict until we have enough space
        while totalSize + requiredSpace > maxSize, !files.isEmpty {
            let oldest = files.removeFirst()
            try? fileManager.removeItem(at: oldest.url)
            let metadataURL = oldest.url.deletingPathExtension().appendingPathExtension("metadata")
            try? fileManager.removeItem(at: metadataURL)
            totalSize -= oldest.size
        }
    }
}

/// A combined cache that uses memory as L1 and disk as L2.
public actor HybridCache: ResponseCaching {
    private let memoryCache: MemoryCache
    private let diskCache: DiskCache

    /// Creates a new hybrid cache.
    /// - Parameters:
    ///   - memoryMaxEntries: Maximum entries in memory cache.
    ///   - memoryMaxSize: Maximum size of memory cache in bytes.
    ///   - diskDirectory: Directory for disk cache.
    ///   - diskMaxSize: Maximum size of disk cache in bytes.
    public init(
        memoryMaxEntries: Int = 50,
        memoryMaxSize: Int = 25 * 1024 * 1024,
        diskDirectory: URL? = nil,
        diskMaxSize: Int = 100 * 1024 * 1024
    ) {
        memoryCache = MemoryCache(maxEntries: memoryMaxEntries, maxSize: memoryMaxSize)
        diskCache = DiskCache(directory: diskDirectory, maxSize: diskMaxSize)
    }

    public func get(for request: URLRequest) async -> CacheEntry? {
        // Try memory first
        if let entry = await memoryCache.get(for: request) {
            return entry
        }

        // Fall back to disk
        if let entry = await diskCache.get(for: request) {
            // Promote to memory
            await memoryCache.set(entry, for: request)
            return entry
        }

        return nil
    }

    public func set(_ entry: CacheEntry, for request: URLRequest) async {
        await memoryCache.set(entry, for: request)
        await diskCache.set(entry, for: request)
    }

    public func remove(for request: URLRequest) async {
        await memoryCache.remove(for: request)
        await diskCache.remove(for: request)
    }

    public func removeAll() async {
        await memoryCache.removeAll()
        await diskCache.removeAll()
    }

    public func removeExpired() async {
        await memoryCache.removeExpired()
        await diskCache.removeExpired()
    }
}

// MARK: - Private Types

private struct CacheMetadata: Codable {
    let urlString: String
    let statusCode: Int
    let headers: [String: String]
    let cachedAt: Date
    let ttlSeconds: Int
    let etag: String?
    let lastModified: String?
}

// MARK: - Duration Extension

private extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
