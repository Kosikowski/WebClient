import Foundation

/// A policy for retrying failed requests.
///
/// Retry policies control how many times a failed request should be retried
/// and how long to wait between attempts.
///
/// ## Example
/// ```swift
/// // Exponential backoff with 3 retries
/// let policy = RetryPolicy.exponentialBackoff(maxRetries: 3)
///
/// // No retries
/// let noRetry = RetryPolicy.none
///
/// // Custom policy
/// let custom = RetryPolicy(
///     maxRetries: 5,
///     baseDelay: .milliseconds(500),
///     maxDelay: .seconds(10),
///     useExponentialBackoff: true
/// )
/// ```
public struct RetryPolicy: Sendable, Equatable {
    /// Maximum number of retry attempts.
    ///
    /// A value of 0 means no retries (the request is attempted only once).
    public let maxRetries: Int

    /// Base delay between retries.
    ///
    /// For exponential backoff, this is the delay after the first failure.
    /// Subsequent delays are multiplied by powers of 2.
    public let baseDelay: Duration

    /// Maximum delay between retries.
    ///
    /// The delay will never exceed this value, even with exponential backoff.
    public let maxDelay: Duration

    /// Whether to use exponential backoff.
    ///
    /// When `true`, the delay doubles after each retry (up to `maxDelay`).
    /// When `false`, the delay is always `baseDelay`.
    public let useExponentialBackoff: Bool

    /// Creates a retry policy.
    /// - Parameters:
    ///   - maxRetries: Maximum retry attempts. Defaults to 3.
    ///   - baseDelay: Initial delay between retries. Defaults to 1 second.
    ///   - maxDelay: Maximum delay cap. Defaults to 30 seconds.
    ///   - useExponentialBackoff: Whether to increase delay exponentially. Defaults to `true`.
    public init(
        maxRetries: Int = 3,
        baseDelay: Duration = .seconds(1),
        maxDelay: Duration = .seconds(30),
        useExponentialBackoff: Bool = true
    ) {
        self.maxRetries = max(0, maxRetries)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.useExponentialBackoff = useExponentialBackoff
    }

    /// Default exponential backoff policy.
    /// - Parameter maxRetries: Maximum retry attempts. Defaults to 3.
    /// - Returns: A retry policy with exponential backoff.
    public static func exponentialBackoff(maxRetries: Int = 3) -> RetryPolicy {
        RetryPolicy(maxRetries: maxRetries)
    }

    /// A policy that never retries.
    public static let none = RetryPolicy(maxRetries: 0)

    /// Calculates the delay for a given attempt number.
    /// - Parameter attempt: The attempt number (0-indexed, where 0 is the first retry).
    /// - Returns: The delay duration before the next attempt.
    public func delay(for attempt: Int) -> Duration {
        guard useExponentialBackoff else {
            return baseDelay
        }

        // 2^attempt multiplier: 1, 2, 4, 8, ...
        let multiplier = Double(1 << min(attempt, 10)) // Cap at 1024x to prevent overflow
        let baseSeconds = Double(baseDelay.components.seconds)
        let baseAttoseconds = Double(baseDelay.components.attoseconds)
        let totalNanoseconds = (baseSeconds * 1_000_000_000 + baseAttoseconds / 1_000_000_000) * multiplier

        let delayNanoseconds = Int64(totalNanoseconds)
        let maxNanoseconds = Int64(maxDelay.components.seconds) * 1_000_000_000

        return .nanoseconds(min(delayNanoseconds, maxNanoseconds))
    }
}
