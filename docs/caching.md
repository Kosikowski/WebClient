# Caching Guide

WebClient provides a flexible caching system with memory, disk, and hybrid cache implementations.

## Cache Types

### Memory Cache

Fast, in-memory LRU cache:

```swift
let cache = MemoryCache(
    maxEntries: 100,           // Maximum number of entries
    maxSize: 50 * 1024 * 1024  // 50MB maximum size
)
```

### Disk Cache

Persistent file-based cache:

```swift
let cache = DiskCache(
    directory: customURL,       // Optional custom directory
    maxSize: 100 * 1024 * 1024  // 100MB maximum size
)
```

### Hybrid Cache

Two-level cache with memory as L1 and disk as L2:

```swift
let cache = HybridCache(
    memoryMaxEntries: 50,
    memoryMaxSize: 25 * 1024 * 1024,    // 25MB memory
    diskDirectory: nil,                   // Use default
    diskMaxSize: 100 * 1024 * 1024       // 100MB disk
)
```

## Cache Policies

### Never Cache

```swift
CachePolicy.never
```

### TTL-Based Caching

Cache for a fixed duration:

```swift
CachePolicy.ttl(.seconds(300))  // 5 minutes
CachePolicy.ttl(.hours(1))      // 1 hour
```

### HTTP Headers

Respect Cache-Control and Expires headers:

```swift
CachePolicy.httpHeaders
```

### Revalidation

Cache with conditional requests (If-None-Match, If-Modified-Since):

```swift
CachePolicy.revalidate(maxAge: .minutes(5))
```

## Setting Up Caching

Add cache interceptors to your client configuration:

```swift
let cache = HybridCache()
let cachePolicy = CachePolicy.ttl(.minutes(5))

let config = WebClientConfiguration(
    baseURL: apiURL,
    requestInterceptors: [
        CacheRequestInterceptor(cache: cache, policy: cachePolicy)
    ],
    responseInterceptors: [
        CacheResponseInterceptor(cache: cache, policy: cachePolicy),
        CacheNotModifiedInterceptor(cache: cache)  // Handle 304 responses
    ]
)
```

## Cache Management

### Clear All Cached Data

```swift
await cache.removeAll()
```

### Remove Expired Entries

```swift
await cache.removeExpired()
```

### Remove Specific Entry

```swift
let request = URLRequest(url: someURL)
await cache.remove(for: request)
```

## CacheEntry Structure

Each cached response includes:

```swift
struct CacheEntry {
    let data: Data                  // Response body
    let response: HTTPURLResponse   // HTTP response
    let cachedAt: Date              // When it was cached
    let ttl: Duration               // Time-to-live
    let etag: String?               // ETag for revalidation
    let lastModified: String?       // Last-Modified for revalidation

    var isExpired: Bool             // Whether TTL has passed
}
```

## Per-Endpoint Caching

Use `CacheableEndpoint` for endpoint-specific cache policies:

```swift
struct GetConfigEndpoint: CacheableEndpoint {
    typealias Success = Config
    typealias Failure = APIError

    var path: String { "/config" }
    var decoder: any Decoding { JSONDecoder() }

    var cachePolicy: CachePolicy { .ttl(.hours(24)) }
}
```
