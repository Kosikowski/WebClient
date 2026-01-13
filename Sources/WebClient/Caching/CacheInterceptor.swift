import Foundation

/// A request interceptor that handles cache lookups and conditional requests.
public actor CacheRequestInterceptor: RequestInterceptor {
    private let cache: any ResponseCaching
    private let policy: CachePolicy

    /// Creates a new cache request interceptor.
    /// - Parameters:
    ///   - cache: The cache to use for lookups.
    ///   - policy: The caching policy to apply.
    public init(cache: any ResponseCaching, policy: CachePolicy) {
        self.cache = cache
        self.policy = policy
    }

    public nonisolated func intercept(
        _ request: URLRequest,
        context _: RequestContext
    ) async throws -> URLRequest {
        guard case .revalidate = policy else {
            return request
        }

        // Add conditional headers if we have a cached response
        guard let entry = await cache.get(for: request) else {
            return request
        }

        var modifiedRequest = request

        if let etag = entry.etag {
            modifiedRequest.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        if let lastModified = entry.lastModified {
            modifiedRequest.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        return modifiedRequest
    }
}

/// A response interceptor that handles caching responses.
public actor CacheResponseInterceptor: ResponseInterceptor {
    private let cache: any ResponseCaching
    private let policy: CachePolicy

    /// Creates a new cache response interceptor.
    /// - Parameters:
    ///   - cache: The cache to store responses in.
    ///   - policy: The caching policy to apply.
    public init(cache: any ResponseCaching, policy: CachePolicy) {
        self.cache = cache
        self.policy = policy
    }

    public nonisolated func intercept(
        _ data: Data,
        response: HTTPURLResponse,
        context: ResponseContext
    ) async throws -> (Data, HTTPURLResponse) {
        // Don't cache error responses
        guard (200 ..< 300).contains(response.statusCode) else {
            return (data, response)
        }

        // Only cache GET requests
        guard context.method == .get else {
            return (data, response)
        }

        switch policy {
        case .never:
            break

        case let .ttl(duration):
            let entry = CacheEntry(
                data: data,
                response: response,
                ttl: duration,
                etag: response.value(forHTTPHeaderField: "ETag"),
                lastModified: response.value(forHTTPHeaderField: "Last-Modified")
            )

            // Create a minimal request for cache key
            if let url = response.url {
                let request = URLRequest(url: url)
                await cache.set(entry, for: request)
            }

        case .httpHeaders:
            if let ttl = extractTTLFromHeaders(response) {
                let entry = CacheEntry(
                    data: data,
                    response: response,
                    ttl: ttl,
                    etag: response.value(forHTTPHeaderField: "ETag"),
                    lastModified: response.value(forHTTPHeaderField: "Last-Modified")
                )

                if let url = response.url {
                    let request = URLRequest(url: url)
                    await cache.set(entry, for: request)
                }
            }

        case let .revalidate(maxAge):
            let entry = CacheEntry(
                data: data,
                response: response,
                ttl: maxAge,
                etag: response.value(forHTTPHeaderField: "ETag"),
                lastModified: response.value(forHTTPHeaderField: "Last-Modified")
            )

            if let url = response.url {
                let request = URLRequest(url: url)
                await cache.set(entry, for: request)
            }
        }

        return (data, response)
    }

    private nonisolated func extractTTLFromHeaders(_ response: HTTPURLResponse) -> Duration? {
        // Check Cache-Control max-age
        if let cacheControl = response.value(forHTTPHeaderField: "Cache-Control") {
            let directives = cacheControl.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces).lowercased()
            }

            // Don't cache if no-store is present
            if directives.contains("no-store") {
                return nil
            }

            // Extract max-age
            for directive in directives {
                if directive.hasPrefix("max-age=") {
                    let valueString = String(directive.dropFirst(8))
                    if let seconds = Int(valueString) {
                        return .seconds(seconds)
                    }
                }
            }
        }

        // Check Expires header
        if let expires = response.value(forHTTPHeaderField: "Expires"),
           let expiresDate = parseHTTPDate(expires)
        {
            let interval = expiresDate.timeIntervalSinceNow
            if interval > 0 {
                return .seconds(Int(interval))
            }
        }

        return nil
    }

    private nonisolated func parseHTTPDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Try RFC 7231 format
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: dateString) {
            return date
        }

        // Try RFC 850 format
        formatter.dateFormat = "EEEE, dd-MMM-yy HH:mm:ss zzz"
        if let date = formatter.date(from: dateString) {
            return date
        }

        // Try ANSI C format
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        if let date = formatter.date(from: dateString) {
            return date
        }

        return nil
    }
}

/// A response interceptor that handles 304 Not Modified responses.
public actor CacheNotModifiedInterceptor: ResponseInterceptor {
    private let cache: any ResponseCaching

    /// Creates a new cache not-modified interceptor.
    /// - Parameter cache: The cache to retrieve original responses from.
    public init(cache: any ResponseCaching) {
        self.cache = cache
    }

    public nonisolated func intercept(
        _ data: Data,
        response: HTTPURLResponse,
        context _: ResponseContext
    ) async throws -> (Data, HTTPURLResponse) {
        // Handle 304 Not Modified
        guard response.statusCode == 304 else {
            return (data, response)
        }

        // Return cached data instead
        if let url = response.url {
            let request = URLRequest(url: url)
            if let cachedEntry = await cache.get(for: request) {
                return (cachedEntry.data, cachedEntry.response)
            }
        }

        return (data, response)
    }
}

// MARK: - Cacheable Endpoint Protocol

/// A protocol for endpoints that support caching.
public protocol CacheableEndpoint: Endpoint {
    /// The cache policy for this endpoint.
    var cachePolicy: CachePolicy { get }
}

public extension CacheableEndpoint {
    /// Default cache policy is to never cache.
    var cachePolicy: CachePolicy { .never }
}
