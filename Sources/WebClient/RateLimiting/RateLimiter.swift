import Foundation

/// A thread-safe rate limiter using the token bucket algorithm.
///
/// The token bucket algorithm allows requests up to a certain limit with the ability
/// to handle bursts while maintaining a long-term average rate.
///
/// ## Example
/// ```swift
/// // Allow 10 requests per second with burst of 20
/// let limiter = RateLimiter(tokensPerSecond: 10, maxTokens: 20)
///
/// // In your request interceptor:
/// try await limiter.acquire()
/// // Make request...
/// ```
///
/// ## Algorithm
/// - Tokens are added at a constant rate (tokensPerSecond)
/// - Each request consumes one token
/// - If no tokens available, the request waits until a token becomes available
/// - The bucket has a maximum capacity to allow controlled bursts
public actor RateLimiter: Sendable {
    /// The rate at which tokens are replenished (tokens per second).
    public let tokensPerSecond: Double

    /// The maximum number of tokens that can be stored.
    public let maxTokens: Double

    /// The current number of available tokens.
    private var availableTokens: Double

    /// The last time tokens were replenished.
    private var lastRefillTime: ContinuousClock.Instant

    /// Creates a new rate limiter.
    ///
    /// - Parameters:
    ///   - tokensPerSecond: The rate at which tokens are replenished.
    ///   - maxTokens: The maximum number of tokens (burst capacity). Defaults to tokensPerSecond.
    public init(tokensPerSecond: Double, maxTokens: Double? = nil) {
        self.tokensPerSecond = tokensPerSecond
        self.maxTokens = maxTokens ?? tokensPerSecond
        availableTokens = self.maxTokens
        lastRefillTime = .now
    }

    /// Convenience initializer using requests per minute.
    ///
    /// - Parameters:
    ///   - requestsPerMinute: The maximum requests allowed per minute.
    ///   - burstSize: The maximum burst size. Defaults to requestsPerMinute / 6.
    public init(requestsPerMinute: Int, burstSize: Int? = nil) {
        let rps = Double(requestsPerMinute) / 60.0
        tokensPerSecond = rps
        maxTokens = Double(burstSize ?? max(requestsPerMinute / 6, 1))
        availableTokens = maxTokens
        lastRefillTime = .now
    }

    /// Acquires a token, waiting if necessary.
    ///
    /// This method blocks until a token is available. Use this before making a request
    /// to ensure you don't exceed the rate limit.
    ///
    /// - Parameter tokens: The number of tokens to acquire. Defaults to 1.
    /// - Throws: `CancellationError` if the task is cancelled while waiting.
    public func acquire(tokens: Double = 1) async throws {
        while true {
            try Task.checkCancellation()

            refillTokens()

            if availableTokens >= tokens {
                availableTokens -= tokens
                return
            }

            // Calculate wait time for tokens to become available
            let tokensNeeded = tokens - availableTokens
            let waitSeconds = tokensNeeded / tokensPerSecond
            let waitDuration = Duration.milliseconds(Int(waitSeconds * 1000) + 1)

            try await Task.sleep(for: waitDuration)
        }
    }

    /// Attempts to acquire a token without waiting.
    ///
    /// - Parameter tokens: The number of tokens to acquire. Defaults to 1.
    /// - Returns: `true` if the token was acquired, `false` if rate limited.
    public func tryAcquire(tokens: Double = 1) -> Bool {
        refillTokens()

        if availableTokens >= tokens {
            availableTokens -= tokens
            return true
        }

        return false
    }

    /// Returns the current number of available tokens.
    public var currentTokens: Double {
        // Note: This doesn't refill, it's just for inspection
        availableTokens
    }

    /// Returns the estimated wait time for the next token.
    ///
    /// - Returns: The duration until a token will be available, or zero if available now.
    public func estimatedWaitTime(for tokens: Double = 1) -> Duration {
        refillTokens()

        if availableTokens >= tokens {
            return .zero
        }

        let tokensNeeded = tokens - availableTokens
        let waitSeconds = tokensNeeded / tokensPerSecond
        return .milliseconds(Int(waitSeconds * 1000))
    }

    /// Refills tokens based on elapsed time.
    private func refillTokens() {
        let now = ContinuousClock.now
        let elapsed = now - lastRefillTime
        let elapsedSeconds = Double(elapsed.components.seconds) +
            Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

        let tokensToAdd = elapsedSeconds * tokensPerSecond
        availableTokens = min(availableTokens + tokensToAdd, maxTokens)
        lastRefillTime = now
    }

    /// Resets the rate limiter to full capacity.
    public func reset() {
        availableTokens = maxTokens
        lastRefillTime = .now
    }
}

/// A rate limiter that applies different limits based on the request path or domain.
///
/// Use this when different API endpoints have different rate limits.
///
/// ## Example
/// ```swift
/// let limiter = ScopedRateLimiter(
///     defaultLimiter: RateLimiter(requestsPerMinute: 60),
///     scopedLimiters: [
///         "/api/search": RateLimiter(requestsPerMinute: 10),
///         "/api/upload": RateLimiter(requestsPerMinute: 5)
///     ]
/// )
/// ```
public actor ScopedRateLimiter: Sendable {
    /// The default rate limiter for unspecified paths.
    private let defaultLimiter: RateLimiter

    /// Rate limiters for specific path prefixes.
    private let scopedLimiters: [String: RateLimiter]

    /// Creates a scoped rate limiter.
    ///
    /// - Parameters:
    ///   - defaultLimiter: The default limiter for paths without specific limits.
    ///   - scopedLimiters: A dictionary mapping path prefixes to their rate limiters.
    public init(
        defaultLimiter: RateLimiter,
        scopedLimiters: [String: RateLimiter] = [:]
    ) {
        self.defaultLimiter = defaultLimiter
        self.scopedLimiters = scopedLimiters
    }

    /// Acquires a token for the given path.
    ///
    /// - Parameters:
    ///   - path: The request path to rate limit.
    ///   - tokens: The number of tokens to acquire.
    /// - Throws: `CancellationError` if cancelled while waiting.
    public func acquire(for path: String, tokens: Double = 1) async throws {
        let limiter = limiterForPath(path)
        try await limiter.acquire(tokens: tokens)
    }

    /// Attempts to acquire a token for the given path without waiting.
    ///
    /// - Parameters:
    ///   - path: The request path to rate limit.
    ///   - tokens: The number of tokens to acquire.
    /// - Returns: `true` if acquired, `false` if rate limited.
    public func tryAcquire(for path: String, tokens: Double = 1) async -> Bool {
        let limiter = limiterForPath(path)
        return await limiter.tryAcquire(tokens: tokens)
    }

    /// Returns the limiter for a given path.
    private func limiterForPath(_ path: String) -> RateLimiter {
        // Find the most specific matching limiter
        for (prefix, limiter) in scopedLimiters {
            if path.hasPrefix(prefix) {
                return limiter
            }
        }
        return defaultLimiter
    }
}
