# Interceptors

Interceptors allow you to modify requests and responses for cross-cutting concerns like authentication, logging, and metrics.

## Request Interceptors

Implement `RequestInterceptor` to modify outgoing requests:

```swift
struct AuthInterceptor: RequestInterceptor {
    let tokenProvider: @Sendable () async -> String

    func intercept(
        _ request: URLRequest,
        context: RequestContext
    ) async throws -> URLRequest {
        var request = request
        let token = await tokenProvider()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
}
```

### RequestContext

Context provided to request interceptors:

```swift
struct RequestContext {
    let path: String           // Endpoint path
    let method: HTTPMethod     // HTTP method
    let attemptNumber: Int     // Retry attempt (0 = first)
    let requestId: String?     // Request ID if enabled
}
```

## Response Interceptors

Implement `ResponseInterceptor` to process responses:

```swift
struct LoggingInterceptor: ResponseInterceptor {
    func intercept(
        _ data: Data,
        response: HTTPURLResponse,
        context: ResponseContext
    ) async throws -> (Data, HTTPURLResponse) {
        print("[\(response.statusCode)] \(context.path) - \(data.count) bytes in \(context.duration)")
        return (data, response)
    }
}
```

### ResponseContext

Context provided to response interceptors:

```swift
struct ResponseContext {
    let path: String           // Endpoint path
    let method: HTTPMethod     // HTTP method
    let attemptNumber: Int     // Retry attempt
    let duration: Duration     // Request duration
    let requestId: String?     // Request ID if enabled
}
```

## Token Refresh Pattern

Handle 401 responses with automatic token refresh:

```swift
struct TokenRefreshInterceptor: ResponseInterceptor {
    let refreshToken: @Sendable () async throws -> Void

    func intercept(
        _ data: Data,
        response: HTTPURLResponse,
        context: ResponseContext
    ) async throws -> (Data, HTTPURLResponse) {
        // Only attempt refresh on first try
        if response.statusCode == 401 && context.attemptNumber == 0 {
            try await refreshToken()
            throw RetryRequestError()  // Trigger retry with new token
        }
        return (data, response)
    }
}
```

## Configuration

Add interceptors when creating the client:

```swift
let config = WebClientConfiguration(
    baseURL: apiURL,
    requestInterceptors: [
        AuthInterceptor(tokenProvider: tokenService.getToken),
        LoggingRequestInterceptor()
    ],
    responseInterceptors: [
        LoggingResponseInterceptor(),
        TokenRefreshInterceptor(refreshToken: tokenService.refresh),
        MetricsInterceptor(recorder: metricsService)
    ]
)
```

## Common Interceptor Examples

### Request Logging

```swift
struct RequestLoggingInterceptor: RequestInterceptor {
    func intercept(
        _ request: URLRequest,
        context: RequestContext
    ) async throws -> URLRequest {
        print("[\(context.method.rawValue)] \(request.url?.absoluteString ?? "")")
        if let body = request.httpBody {
            print("Body: \(String(data: body, encoding: .utf8) ?? "")")
        }
        return request
    }
}
```

### Response Metrics

```swift
struct MetricsInterceptor: ResponseInterceptor {
    let recorder: MetricsRecorder

    func intercept(
        _ data: Data,
        response: HTTPURLResponse,
        context: ResponseContext
    ) async throws -> (Data, HTTPURLResponse) {
        await recorder.record(
            path: context.path,
            method: context.method.rawValue,
            statusCode: response.statusCode,
            duration: context.duration,
            responseSize: data.count
        )
        return (data, response)
    }
}
```

### Request ID

Enable automatic request IDs for distributed tracing:

```swift
let config = WebClientConfiguration(
    baseURL: apiURL,
    requestIdGenerator: { UUID().uuidString },
    requestIdHeaderName: "X-Request-ID"  // Default
)
```

The request ID is available in both `RequestContext` and `ResponseContext`.

### Error Transformation

```swift
struct ErrorEnrichmentInterceptor: ResponseInterceptor {
    func intercept(
        _ data: Data,
        response: HTTPURLResponse,
        context: ResponseContext
    ) async throws -> (Data, HTTPURLResponse) {
        if response.statusCode >= 500 {
            // Log server errors with context
            print("Server error on \(context.path): \(response.statusCode)")
        }
        return (data, response)
    }
}
```

## Interceptor Order

Interceptors are executed in the order they're added:

- **Request interceptors**: First to last, before sending
- **Response interceptors**: First to last, after receiving

```swift
// Request flow: Auth → Logging → [Send]
// Response flow: [Receive] → Metrics → TokenRefresh → ErrorHandler
```
