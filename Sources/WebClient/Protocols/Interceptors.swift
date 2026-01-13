import Foundation

/// A protocol for intercepting outgoing requests before they are sent.
///
/// Request interceptors can modify requests, add headers, log requests,
/// or perform other cross-cutting concerns.
///
/// ## Example: Authentication
/// ```swift
/// struct AuthInterceptor: RequestInterceptor {
///     let tokenProvider: @Sendable () async -> String
///
///     func intercept(
///         _ request: URLRequest,
///         context: RequestContext
///     ) async throws -> URLRequest {
///         var request = request
///         let token = await tokenProvider()
///         request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
///         return request
///     }
/// }
/// ```
///
/// ## Example: Logging
/// ```swift
/// struct LoggingInterceptor: RequestInterceptor {
///     func intercept(
///         _ request: URLRequest,
///         context: RequestContext
///     ) async throws -> URLRequest {
///         print("[\(request.httpMethod ?? "?")] \(request.url?.absoluteString ?? "")")
///         return request
///     }
/// }
/// ```
public protocol RequestInterceptor: Sendable {
    /// Intercepts a request before it is sent.
    ///
    /// - Parameters:
    ///   - request: The URL request to intercept.
    ///   - context: Additional context about the request.
    /// - Returns: The (possibly modified) request to send.
    /// - Throws: An error to abort the request.
    func intercept(_ request: URLRequest, context: RequestContext) async throws -> URLRequest
}

/// Context information passed to request interceptors.
public struct RequestContext: Sendable {
    /// The endpoint's path.
    public let path: String

    /// The HTTP method.
    public let method: HTTPMethod

    /// The retry attempt number (0 for the first attempt).
    public let attemptNumber: Int

    /// The unique request ID, if request ID generation is enabled.
    ///
    /// This is the same ID added to the request's `X-Request-ID` header
    /// (or custom header name if configured).
    public let requestId: String?

    /// Creates a new request context.
    public init(path: String, method: HTTPMethod, attemptNumber: Int, requestId: String? = nil) {
        self.path = path
        self.method = method
        self.attemptNumber = attemptNumber
        self.requestId = requestId
    }
}

/// A protocol for intercepting incoming responses before they are returned.
///
/// Response interceptors can inspect responses, log them, handle token refresh,
/// or perform other cross-cutting concerns.
///
/// ## Example: Response Logging
/// ```swift
/// struct ResponseLoggingInterceptor: ResponseInterceptor {
///     func intercept(
///         _ data: Data,
///         response: HTTPURLResponse,
///         context: ResponseContext
///     ) async throws -> (Data, HTTPURLResponse) {
///         print("Response: \(response.statusCode) (\(data.count) bytes)")
///         return (data, response)
///     }
/// }
/// ```
///
/// ## Example: Token Refresh
/// ```swift
/// struct TokenRefreshInterceptor: ResponseInterceptor {
///     let refreshToken: @Sendable () async throws -> Void
///
///     func intercept(
///         _ data: Data,
///         response: HTTPURLResponse,
///         context: ResponseContext
///     ) async throws -> (Data, HTTPURLResponse) {
///         if response.statusCode == 401 && context.attemptNumber == 0 {
///             try await refreshToken()
///             throw RetryRequestError() // Signal to retry
///         }
///         return (data, response)
///     }
/// }
/// ```
public protocol ResponseInterceptor: Sendable {
    /// Intercepts a response before it is processed.
    ///
    /// - Parameters:
    ///   - data: The response body data.
    ///   - response: The HTTP response.
    ///   - context: Additional context about the response.
    /// - Returns: The (possibly modified) data and response.
    /// - Throws: An error to fail the request or signal a retry.
    func intercept(
        _ data: Data,
        response: HTTPURLResponse,
        context: ResponseContext
    ) async throws -> (Data, HTTPURLResponse)
}

/// Context information passed to response interceptors.
public struct ResponseContext: Sendable {
    /// The endpoint's path.
    public let path: String

    /// The HTTP method.
    public let method: HTTPMethod

    /// The retry attempt number (0 for the first attempt).
    public let attemptNumber: Int

    /// The time taken for the request.
    public let duration: Duration

    /// The unique request ID, if request ID generation is enabled.
    ///
    /// This is the same ID added to the request's `X-Request-ID` header
    /// (or custom header name if configured).
    public let requestId: String?

    /// Creates a new response context.
    public init(path: String, method: HTTPMethod, attemptNumber: Int, duration: Duration, requestId: String? = nil) {
        self.path = path
        self.method = method
        self.attemptNumber = attemptNumber
        self.duration = duration
        self.requestId = requestId
    }
}

/// An error that signals the request should be retried.
///
/// Throw this from a response interceptor to trigger a retry,
/// for example after refreshing an authentication token.
public struct RetryRequestError: Error, Sendable {
    public init() {}
}
