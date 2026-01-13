# Endpoints Guide

Endpoints are the core abstraction in WebClient. Each endpoint defines how to construct a request and how to handle the response.

## Basic Endpoint

An endpoint conforms to `Endpoint`, which combines `RequestProviding` and `ResponseHandling`:

```swift
struct GetUserEndpoint: Endpoint {
    typealias Success = User
    typealias Failure = APIError

    let userId: String

    var path: String { "/users/\(userId)" }
    var decoder: any Decoding { JSONDecoder() }
}
```

## Request Configuration

### HTTP Methods

```swift
var method: HTTPMethod { .post }  // .get, .post, .put, .patch, .delete, .head, .options
```

### Path Components (Type-Safe)

Use `pathComponents` for dynamic paths with automatic URL encoding:

```swift
var pathComponents: [PathComponent]? {
    ["users", .value(userId), "posts", .value(postId)]
}
// Produces: /users/123/posts/456
```

### Query Parameters

```swift
var queryItems: [URLQueryItem]? {
    [
        URLQueryItem(name: "page", value: "\(page)"),
        URLQueryItem(name: "limit", value: "\(limit)")
    ]
}
```

### Headers

```swift
var headers: [String: String]? {
    ["X-Custom-Header": "value"]
}
```

### Request Body

```swift
var body: (any Encodable & Sendable)? { myRequestObject }
var encoder: (any Encoding)? { JSONEncoder() }  // Optional, defaults to JSON
```

## Response Handling

### Success Types

The `Success` type is automatically decoded from successful responses:

```swift
typealias Success = User           // Decodable type
typealias Success = Data           // Raw data
typealias Success = Void           // No body expected
```

### Failure Types

The `Failure` type is decoded from error responses (4xx, 5xx):

```swift
typealias Failure = APIError       // Decodable error type
typealias Failure = Void           // No error body
typealias Failure = Data           // Raw error data
```

### Custom Status Codes

```swift
var successStatusCodes: ClosedRange<Int> { 200...299 }  // Default
var successStatusCodes: ClosedRange<Int> { 200...204 }  // Custom
```

### Custom Decoding

Override default decoding for special cases:

```swift
func decodeSuccess(from data: Data, response: HTTPURLResponse) throws -> Success {
    // Custom decoding logic
}

func decodeFailure(from data: Data, response: HTTPURLResponse) throws -> Failure {
    // Custom error decoding
}
```

## Retry Policy

Override the client's default retry policy per-endpoint:

```swift
// Disable retries for non-idempotent operations
var retryPolicy: RetryPolicy? { .none }

// Custom retry configuration
var retryPolicy: RetryPolicy? {
    .exponentialBackoff(maxRetries: 5, baseDelay: .seconds(2))
}
```

## Complete Example

```swift
struct SearchUsersEndpoint: Endpoint {
    typealias Success = SearchResponse
    typealias Failure = APIError

    let query: String
    let page: Int
    let limit: Int

    var path: String { "/users/search" }
    var method: HTTPMethod { .get }

    var queryItems: [URLQueryItem]? {
        [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
    }

    var headers: [String: String]? {
        ["X-Search-Version": "2"]
    }

    var decoder: any Decoding {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    var retryPolicy: RetryPolicy? { .none }  // Don't retry searches
}
```
