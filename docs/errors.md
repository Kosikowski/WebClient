# Error Handling

WebClient uses a generic `WebClientError<Failure>` type that provides type-safe access to server error bodies.

## WebClientError Cases

```swift
enum WebClientError<Failure: Sendable>: Error {
    /// Network-level error (DNS, connection, SSL, etc.)
    case networkError(underlying: any Error & Sendable)

    /// Could not construct URL from endpoint
    case invalidRequest(String)

    /// Request was cancelled
    case cancelled

    /// Request timed out
    case timeout

    /// Server returned an error status (4xx, 5xx)
    case serverError(statusCode: Int, failure: Failure?, data: Data?)

    /// Could not decode response body
    case decodingError(underlying: any Error & Sendable, data: Data?)

    /// Response was not HTTP
    case unexpectedResponse

    /// No network connection
    case offline
}
```

## Basic Error Handling

```swift
do {
    let user = try await client.invoke(GetUserEndpoint(userId: "123"))
} catch let error as WebClientError<APIError> {
    switch error {
    case .serverError(let code, let apiError, _):
        if let apiError = apiError {
            print("API Error [\(code)]: \(apiError.message)")
        } else {
            print("Server error: \(code)")
        }
    case .offline:
        showOfflineMessage()
    case .timeout:
        showRetryOption()
    case .cancelled:
        // User cancelled, no action needed
        break
    case .networkError(let underlying):
        print("Network error: \(underlying.localizedDescription)")
    case .decodingError(let underlying, let data):
        print("Decoding failed: \(underlying)")
        // data contains raw response for debugging
    case .invalidRequest(let reason):
        print("Invalid request: \(reason)")
    case .unexpectedResponse:
        print("Unexpected response type")
    }
}
```

## Typed Throws (Swift 6)

Use `invokeTyped` for compile-time error type safety:

```swift
do {
    let user = try await client.invokeTyped(GetUserEndpoint(userId: "123"))
} catch {
    // error is guaranteed to be WebClientError<APIError>
    if let apiError = error.failure {
        handleAPIError(apiError)
    }
}
```

## Result-Based API

Avoid throwing with the `send` method:

```swift
let result = await client.send(GetUserEndpoint(userId: "123"))

switch result {
case .success(let user):
    display(user)
case .failure(let error):
    handle(error)
}
```

## Error Properties

### Accessing the Failure

```swift
if let apiError = error.failure {
    print("Error code: \(apiError.code)")
    print("Message: \(apiError.message)")
}
```

### Status Code

```swift
if let statusCode = error.statusCode {
    print("HTTP \(statusCode)")
}
```

### Checking Error Types

```swift
// Is it a connectivity issue?
if error.isOfflineError {
    showOfflineUI()
}

// Can we retry?
if error.isRetryable {
    scheduleRetry()
}
```

Retryable errors:
- Timeout
- Network errors
- Server errors (5xx)
- Rate limiting (429)

## Defining Failure Types

### Structured API Errors

```swift
struct APIError: Decodable, Sendable {
    let code: String
    let message: String
    let details: [String: String]?

    var isRateLimited: Bool { code == "RATE_LIMITED" }
    var isNotFound: Bool { code == "NOT_FOUND" }
}
```

### No Error Body

Use `Void` when the server doesn't return error details:

```swift
struct SimpleEndpoint: Endpoint {
    typealias Success = Data
    typealias Failure = Void  // No error body
    // ...
}
```

### Raw Error Data

Use `Data` to access the raw error response:

```swift
struct DebugEndpoint: Endpoint {
    typealias Success = Response
    typealias Failure = Data  // Raw error bytes
    // ...
}

// Usage
if case .serverError(_, let errorData, _) = error,
   let errorData = errorData {
    print(String(data: errorData, encoding: .utf8) ?? "")
}
```

## URLError Mapping

`URLError` codes are automatically mapped:

| URLError | WebClientError |
|----------|----------------|
| `.cancelled` | `.cancelled` |
| `.timedOut` | `.timeout` |
| `.notConnectedToInternet` | `.offline` |
| `.networkConnectionLost` | `.offline` |
| `.cannotFindHost` | `.offline` |
| `.cannotConnectToHost` | `.offline` |
| `.dnsLookupFailed` | `.offline` |
| `.dataNotAllowed` | `.offline` |
| Other | `.networkError(underlying:)` |

## Logging Errors

```swift
extension WebClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .invalidRequest(let reason):
            return "Invalid request: \(reason)"
        case .cancelled:
            return "Request cancelled"
        case .timeout:
            return "Request timed out"
        case .serverError(let code, _, _):
            return "Server error: HTTP \(code)"
        case .decodingError(let underlying, _):
            return "Decoding error: \(underlying.localizedDescription)"
        case .unexpectedResponse:
            return "Unexpected response type"
        case .offline:
            return "No internet connection"
        }
    }
}
```
