import Foundation

/// A protocol that defines how an endpoint handles HTTP responses.
///
/// Conforming types specify the expected success and failure types,
/// which status codes indicate success, and how to decode responses.
///
/// ## Example
/// ```swift
/// struct GetUserEndpoint: ResponseHandling {
///     typealias Success = User
///     typealias Failure = APIError
///
///     var decoder: any Decoding { JSONDecoder() }
/// }
/// ```
public protocol ResponseHandling: Sendable {
    /// The type returned on successful responses.
    associatedtype Success: Sendable

    /// The type decoded from error response bodies.
    ///
    /// Use `Void` if the server doesn't return structured error bodies.
    associatedtype Failure: Sendable

    /// HTTP status codes that indicate a successful response.
    ///
    /// Defaults to `200...299`.
    var successStatusCodes: ClosedRange<Int> { get }

    /// The decoder to use for response bodies.
    var decoder: any Decoding { get }

    /// Decodes a successful response.
    /// - Parameters:
    ///   - data: The response body data.
    ///   - response: The HTTP response.
    /// - Returns: The decoded success value.
    func decodeSuccess(from data: Data, response: HTTPURLResponse) throws -> Success

    /// Decodes a failure response (error body from server).
    /// - Parameters:
    ///   - data: The response body data.
    ///   - response: The HTTP response.
    /// - Returns: The decoded failure value.
    func decodeFailure(from data: Data, response: HTTPURLResponse) throws -> Failure
}

// MARK: - Default Implementations

public extension ResponseHandling {
    var successStatusCodes: ClosedRange<Int> { 200 ... 299 }
}

// MARK: - Success Decoding

public extension ResponseHandling where Success: Decodable {
    func decodeSuccess(from data: Data, response _: HTTPURLResponse) throws -> Success {
        try decoder.decode(Success.self, from: data)
    }
}

public extension ResponseHandling where Success == Void {
    func decodeSuccess(from _: Data, response _: HTTPURLResponse) throws -> Success {
        ()
    }
}

public extension ResponseHandling where Success == Data {
    func decodeSuccess(from data: Data, response _: HTTPURLResponse) throws -> Success {
        data
    }
}

// MARK: - Failure Decoding

public extension ResponseHandling where Failure: Decodable {
    func decodeFailure(from data: Data, response _: HTTPURLResponse) throws -> Failure {
        try decoder.decode(Failure.self, from: data)
    }
}

public extension ResponseHandling where Failure == Void {
    func decodeFailure(from _: Data, response _: HTTPURLResponse) throws -> Failure {
        ()
    }
}

public extension ResponseHandling where Failure == Data {
    func decodeFailure(from data: Data, response _: HTTPURLResponse) throws -> Failure {
        data
    }
}
