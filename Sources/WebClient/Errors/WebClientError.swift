import Foundation

/// Errors that can occur when invoking an endpoint via WebClient.
///
/// This error type is generic over the endpoint's `Failure` type, allowing
/// type-safe access to server error bodies when they can be decoded.
///
/// ## Example
/// ```swift
/// do {
///     let user = try await client.invoke(GetUserEndpoint(userId: "123"))
/// } catch let error as WebClientError<APIError> {
///     switch error {
///     case .serverError(let statusCode, let apiError, _):
///         print("Server error \(statusCode): \(apiError?.message ?? "Unknown")")
///     case .offline:
///         print("No internet connection")
///     default:
///         print("Error: \(error)")
///     }
/// }
/// ```
public enum WebClientError<Failure: Sendable>: Error, Sendable {
    /// A network-level error occurred (no response received).
    ///
    /// This includes DNS failures, connection refused, SSL errors, etc.
    case networkError(underlying: any Error & Sendable)

    /// The request URL could not be constructed from the endpoint.
    case invalidRequest(String)

    /// The request was cancelled.
    case cancelled

    /// The request timed out.
    case timeout

    /// The server returned an error status code.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code.
    ///   - failure: The decoded failure body, if available.
    ///   - data: The raw response data.
    case serverError(statusCode: Int, failure: Failure?, data: Data?)

    /// The response body could not be decoded.
    ///
    /// - Parameters:
    ///   - underlying: The decoding error.
    ///   - data: The raw response data that failed to decode.
    case decodingError(underlying: any Error & Sendable, data: Data?)

    /// The response was not an HTTP response.
    case unexpectedResponse

    /// No internet connection is available.
    case offline
}

// MARK: - Error Properties

public extension WebClientError {
    /// Whether this error indicates a network connectivity issue.
    var isOfflineError: Bool {
        switch self {
        case .offline:
            return true
        case let .networkError(underlying):
            if let urlError = underlying as? URLError {
                switch urlError.code {
                case .notConnectedToInternet,
                     .networkConnectionLost,
                     .cannotFindHost,
                     .cannotConnectToHost,
                     .dnsLookupFailed,
                     .dataNotAllowed:
                    return true
                default:
                    return false
                }
            }
            return false
        default:
            return false
        }
    }

    /// Whether this error is potentially retryable.
    var isRetryable: Bool {
        switch self {
        case .timeout, .networkError:
            return true
        case let .serverError(statusCode, _, _):
            return statusCode >= 500 || statusCode == 429
        default:
            return false
        }
    }

    /// The HTTP status code if this is a server error.
    var statusCode: Int? {
        if case let .serverError(code, _, _) = self {
            return code
        }
        return nil
    }

    /// The typed failure value if this is a server error with a decoded body.
    var failure: Failure? {
        if case let .serverError(_, failure, _) = self {
            return failure
        }
        return nil
    }
}

// MARK: - LocalizedError

extension WebClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .networkError(underlying):
            return "Network error: \(underlying.localizedDescription)"
        case let .invalidRequest(reason):
            return "Invalid request: \(reason)"
        case .cancelled:
            return "Request cancelled"
        case .timeout:
            return "Request timed out"
        case let .serverError(statusCode, _, _):
            return "Server error: HTTP \(statusCode)"
        case let .decodingError(underlying, _):
            return "Decoding error: \(underlying.localizedDescription)"
        case .unexpectedResponse:
            return "Unexpected response type"
        case .offline:
            return "No internet connection"
        }
    }
}

// MARK: - Convenience Initializers

public extension WebClientError {
    /// Creates an appropriate error from a URLError.
    static func from(urlError: URLError) -> WebClientError {
        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timeout
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .dataNotAllowed:
            return .offline
        default:
            return .networkError(underlying: urlError)
        }
    }
}
