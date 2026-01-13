# WebClient

A modern, type-safe HTTP client for Swift with protocol-based endpoint definitions, automatic retries, response caching, and full Swift 6 concurrency support.

## Inspiration

This library is inspired by [Bricolage](https://github.com/rcharlton/Bricolage) by Robert Charlton. Like Bricolage, WebClient embraces a protocol-oriented approach where endpoints define both their request construction and response handling in a unified, type-safe manner. A key characteristic is the **generic handling of server response bodies** - both success and failure responses are decoded into strongly-typed values, giving you compile-time safety for your entire API surface.

## Features

- **Type-safe endpoint definitions** - Define request and response types together
- **Generic error handling** - Server error bodies are decoded into typed `Failure` values
- **Automatic retries** - Configurable exponential backoff with jitter
- **Request/Response interceptors** - For authentication, logging, and cross-cutting concerns
- **Response caching** - Memory and disk cache with TTL support
- **Multipart form uploads** - Easy file upload support
- **Download progress tracking** - Progress callbacks for large downloads
- **Streaming support** - Server-Sent Events (SSE) and NDJSON
- **Swift 6 ready** - Full `Sendable` conformance and typed throws

## Requirements

- iOS 17.0+ / macOS 14.0+ / watchOS 10.0+ / tvOS 17.0+
- Swift 6.0+

## Installation

### Swift Package Manager

Add WebClient to your `Package.swift`:

```swift
dependencies: [
    .package(path: "../Packages/WebClient")
]
```

Or add it via Xcode: File → Add Package Dependencies → Enter the repository URL.

## Quick Start

### 1. Define an Endpoint

```swift
import WebClient

struct GetUserEndpoint: Endpoint {
    typealias Success = User
    typealias Failure = APIError

    let userId: String

    var path: String { "/users/\(userId)" }
    var decoder: any Decoding { JSONDecoder() }
}

struct User: Decodable, Sendable {
    let id: String
    let name: String
    let email: String
}

struct APIError: Decodable, Sendable {
    let code: String
    let message: String
}
```

### 2. Create a Client

```swift
let config = WebClientConfiguration(
    baseURL: URL(string: "https://api.example.com/v1")!,
    timeout: .seconds(30),
    defaultHeaders: ["Accept": "application/json"]
)

let client = WebClient(configuration: config)
```

### 3. Make Requests

```swift
// Simple invocation
let user = try await client.invoke(GetUserEndpoint(userId: "123"))
print("User: \(user.name)")

// With typed error handling
do {
    let user = try await client.invoke(GetUserEndpoint(userId: "123"))
} catch let error as WebClientError<APIError> {
    if let apiError = error.failure {
        print("API Error: \(apiError.message)")
    }
}

// Result-based (non-throwing)
let result = await client.send(GetUserEndpoint(userId: "123"))
switch result {
case .success(let user):
    print("Got user: \(user.name)")
case .failure(let error):
    print("Error: \(error)")
}
```

### 4. POST with Body

```swift
struct CreateUserEndpoint: Endpoint {
    typealias Success = User
    typealias Failure = APIError

    let request: CreateUserRequest

    var path: String { "/users" }
    var method: HTTPMethod { .post }
    var body: (any Encodable & Sendable)? { request }
    var decoder: any Decoding { JSONDecoder() }
}

struct CreateUserRequest: Encodable, Sendable {
    let name: String
    let email: String
}

let newUser = try await client.invoke(CreateUserEndpoint(
    request: CreateUserRequest(name: "Jane", email: "jane@example.com")
))
```

## Documentation

For detailed documentation, see:

- [Endpoints Guide](docs/endpoints.md) - Defining and customizing endpoints
- [Caching Guide](docs/caching.md) - Response caching with TTL
- [Multipart Uploads](docs/multipart.md) - File uploads
- [Download Progress](docs/downloads.md) - Progress tracking for downloads
- [Interceptors](docs/interceptors.md) - Request/response interceptors
- [Streaming](docs/streaming.md) - SSE and streaming responses
- [Error Handling](docs/errors.md) - Working with typed errors

## License

WebClient is available under the MIT License. See the [LICENSE](LICENSE) file for details.
