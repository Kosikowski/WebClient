import Foundation

/// A complete endpoint definition that can both construct requests and handle responses.
///
/// `Endpoint` combines `RequestProviding` (how to build the request) with
/// `ResponseHandling` (how to decode responses). This is the primary protocol
/// that endpoint types should conform to.
///
/// ## Example
/// ```swift
/// struct GetUserEndpoint: Endpoint {
///     typealias Success = User
///     typealias Failure = APIError
///
///     let userId: String
///
///     var path: String { "/users/\(userId)" }
///     var decoder: any Decoding { JSONDecoder() }
/// }
///
/// // Usage
/// let user = try await client.invoke(GetUserEndpoint(userId: "123"))
/// ```
public typealias Endpoint = RequestProviding & ResponseHandling
