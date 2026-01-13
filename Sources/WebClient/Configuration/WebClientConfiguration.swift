import Foundation

/// Configuration for a WebClient instance.
///
/// This struct encapsulates all configuration options for a WebClient,
/// including the base URL, timeouts, retry policy, headers, and interceptors.
///
/// ## Example
/// ```swift
/// let config = WebClientConfiguration(
///     baseURL: URL(string: "https://api.example.com/v1")!,
///     timeout: .seconds(30),
///     retryPolicy: .exponentialBackoff(maxRetries: 3),
///     defaultHeaders: [
///         "Accept": "application/json",
///         "User-Agent": "MyApp/1.0"
///     ],
///     requestInterceptors: [AuthInterceptor(), LoggingInterceptor()]
/// )
///
/// let client = WebClient(configuration: config)
/// ```
public struct WebClientConfiguration: Sendable {
    /// The base URL for all requests.
    ///
    /// Endpoint paths are appended to this URL.
    public let baseURL: URL

    /// Request timeout duration.
    ///
    /// The maximum time to wait for a response before timing out.
    public let timeout: Duration

    /// Resource timeout duration.
    ///
    /// The maximum time for the entire resource load (including retries).
    public let resourceTimeout: Duration

    /// Retry policy for failed requests.
    public let retryPolicy: RetryPolicy

    /// Default headers applied to all requests.
    ///
    /// Endpoint-specific headers take precedence over these defaults.
    public let defaultHeaders: [String: String]

    /// Default encoder for request bodies.
    ///
    /// Used when an endpoint doesn't specify its own encoder.
    public let defaultEncoder: any Encoding

    /// Default decoder for response bodies.
    ///
    /// Used when an endpoint doesn't specify its own decoder.
    public let defaultDecoder: any Decoding

    /// Request interceptors applied in order before each request.
    ///
    /// Use interceptors for cross-cutting concerns like authentication,
    /// logging, or request modification.
    public let requestInterceptors: [any RequestInterceptor]

    /// Response interceptors applied in order after each response.
    ///
    /// Use interceptors for cross-cutting concerns like logging,
    /// token refresh, or response modification.
    public let responseInterceptors: [any ResponseInterceptor]

    /// Generator for unique request IDs.
    ///
    /// When set, a unique ID is generated for each request and added
    /// as the `X-Request-ID` header. This is useful for distributed
    /// tracing and debugging.
    ///
    /// The request ID is also included in `RequestContext` and `ResponseContext`
    /// for use in interceptors.
    ///
    /// Defaults to `nil` (no request ID added).
    public let requestIdGenerator: (@Sendable () -> String)?

    /// The header name used for request IDs.
    ///
    /// Defaults to "X-Request-ID".
    public let requestIdHeaderName: String

    /// Creates a WebClient configuration.
    /// - Parameters:
    ///   - baseURL: The base URL for all requests.
    ///   - timeout: Request timeout. Defaults to 30 seconds.
    ///   - resourceTimeout: Resource timeout. Defaults to 60 seconds.
    ///   - retryPolicy: Retry policy. Defaults to exponential backoff with 3 retries.
    ///   - defaultHeaders: Default headers. Defaults to accepting JSON.
    ///   - defaultEncoder: Default encoder. Defaults to `JSONEncoder()`.
    ///   - defaultDecoder: Default decoder. Defaults to `JSONDecoder()`.
    ///   - requestInterceptors: Request interceptors. Defaults to empty.
    ///   - responseInterceptors: Response interceptors. Defaults to empty.
    ///   - requestIdGenerator: Generator for request IDs. Defaults to `nil`.
    ///   - requestIdHeaderName: Header name for request ID. Defaults to "X-Request-ID".
    public init(
        baseURL: URL,
        timeout: Duration = .seconds(30),
        resourceTimeout: Duration = .seconds(60),
        retryPolicy: RetryPolicy = .exponentialBackoff(),
        defaultHeaders: [String: String] = ["Accept": "application/json"],
        defaultEncoder: any Encoding = JSONEncoder(),
        defaultDecoder: any Decoding = JSONDecoder(),
        requestInterceptors: [any RequestInterceptor] = [],
        responseInterceptors: [any ResponseInterceptor] = [],
        requestIdGenerator: (@Sendable () -> String)? = nil,
        requestIdHeaderName: String = "X-Request-ID"
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.resourceTimeout = resourceTimeout
        self.retryPolicy = retryPolicy
        self.defaultHeaders = defaultHeaders
        self.defaultEncoder = defaultEncoder
        self.defaultDecoder = defaultDecoder
        self.requestInterceptors = requestInterceptors
        self.responseInterceptors = responseInterceptors
        self.requestIdGenerator = requestIdGenerator
        self.requestIdHeaderName = requestIdHeaderName
    }

    /// Default request ID generator using UUID.
    ///
    /// Use this when you want unique request IDs without providing a custom generator:
    /// ```swift
    /// let config = WebClientConfiguration(
    ///     baseURL: url,
    ///     requestIdGenerator: WebClientConfiguration.uuidRequestIdGenerator
    /// )
    /// ```
    public static let uuidRequestIdGenerator: @Sendable () -> String = {
        UUID().uuidString
    }
}
