import Foundation

/// A request interceptor that enforces rate limiting before requests are sent.
///
/// This interceptor uses a `RateLimiter` to throttle requests, waiting if necessary
/// until a token is available before allowing the request to proceed.
///
/// ## Example
/// ```swift
/// let rateLimiter = RateLimiter(requestsPerMinute: 60)
/// let interceptor = RateLimitInterceptor(rateLimiter: rateLimiter)
///
/// let config = WebClientConfiguration(
///     baseURL: url,
///     requestInterceptors: [interceptor]
/// )
/// ```
///
/// ## Error Handling
/// If rate limiting fails (e.g., due to task cancellation), the interceptor can either:
/// - Throw an error to abort the request (default)
/// - Allow the request to proceed anyway (lenient mode)
public struct RateLimitInterceptor: RequestInterceptor, Sendable {
    /// The rate limiter used to throttle requests.
    private let rateLimiter: RateLimiter

    /// Whether to allow requests when rate limiting fails.
    private let allowOnFailure: Bool

    /// Optional scoped rate limiter for path-based throttling.
    private let scopedRateLimiter: ScopedRateLimiter?

    /// Creates a rate limit interceptor with a single rate limiter.
    ///
    /// - Parameters:
    ///   - rateLimiter: The rate limiter to use for all requests.
    ///   - allowOnFailure: Whether to allow requests if rate limiting fails. Defaults to `false`.
    public init(rateLimiter: RateLimiter, allowOnFailure: Bool = false) {
        self.rateLimiter = rateLimiter
        self.allowOnFailure = allowOnFailure
        scopedRateLimiter = nil
    }

    /// Creates a rate limit interceptor with scoped rate limiters.
    ///
    /// - Parameters:
    ///   - scopedRateLimiter: The scoped rate limiter for path-based throttling.
    ///   - allowOnFailure: Whether to allow requests if rate limiting fails. Defaults to `false`.
    public init(scopedRateLimiter: ScopedRateLimiter, allowOnFailure: Bool = false) {
        rateLimiter = RateLimiter(tokensPerSecond: 1000) // Fallback, won't be used
        self.allowOnFailure = allowOnFailure
        self.scopedRateLimiter = scopedRateLimiter
    }

    public func intercept(
        _ request: URLRequest,
        context: RequestContext
    ) async throws -> URLRequest {
        do {
            if let scopedLimiter = scopedRateLimiter {
                try await scopedLimiter.acquire(for: context.path)
            } else {
                try await rateLimiter.acquire()
            }
        } catch {
            if !allowOnFailure {
                throw error
            }
            // In lenient mode, allow the request to proceed
        }

        return request
    }
}

/// A response interceptor that handles rate limit responses (HTTP 429).
///
/// When the server returns a 429 status code, this interceptor can parse the
/// `Retry-After` header and wait before signaling a retry.
///
/// ## Example
/// ```swift
/// let config = WebClientConfiguration(
///     baseURL: url,
///     responseInterceptors: [RateLimitResponseInterceptor()]
/// )
/// ```
public struct RateLimitResponseInterceptor: ResponseInterceptor, Sendable {
    /// The maximum time to wait when rate limited.
    private let maxRetryAfter: Duration

    /// Whether to automatically wait and retry on 429 responses.
    private let autoRetry: Bool

    /// Creates a rate limit response interceptor.
    ///
    /// - Parameters:
    ///   - maxRetryAfter: The maximum time to wait. Defaults to 60 seconds.
    ///   - autoRetry: Whether to automatically retry. Defaults to `true`.
    public init(maxRetryAfter: Duration = .seconds(60), autoRetry: Bool = true) {
        self.maxRetryAfter = maxRetryAfter
        self.autoRetry = autoRetry
    }

    public func intercept(
        _ data: Data,
        response: HTTPURLResponse,
        context _: ResponseContext
    ) async throws -> (Data, HTTPURLResponse) {
        guard response.statusCode == 429, autoRetry else {
            return (data, response)
        }

        // Parse Retry-After header
        let retryAfter = parseRetryAfter(from: response)

        // Cap the retry delay
        let waitDuration = min(retryAfter ?? .seconds(1), maxRetryAfter)

        // Wait before retrying
        try await Task.sleep(for: waitDuration)

        // Signal to retry the request
        throw RetryRequestError()
    }

    /// Parses the Retry-After header value.
    ///
    /// The header can be either:
    /// - A number of seconds (e.g., "120")
    /// - An HTTP date (e.g., "Wed, 21 Oct 2015 07:28:00 GMT")
    private func parseRetryAfter(from response: HTTPURLResponse) -> Duration? {
        guard let retryAfterValue = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        // Try parsing as seconds
        if let seconds = Int(retryAfterValue) {
            return .seconds(seconds)
        }

        // Try parsing as HTTP date
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        if let date = formatter.date(from: retryAfterValue) {
            let seconds = max(0, Int(date.timeIntervalSinceNow))
            return .seconds(seconds)
        }

        return nil
    }
}

/// Error thrown when a request is rate limited.
public struct RateLimitedError: Error, Sendable {
    /// The retry-after duration, if provided by the server.
    public let retryAfter: Duration?

    /// The remaining requests, if provided by the server.
    public let remaining: Int?

    /// The rate limit reset time, if provided by the server.
    public let resetTime: Date?

    /// Creates a rate limited error.
    public init(retryAfter: Duration? = nil, remaining: Int? = nil, resetTime: Date? = nil) {
        self.retryAfter = retryAfter
        self.remaining = remaining
        self.resetTime = resetTime
    }
}
