import Foundation

/// A protocol for types that can invoke endpoints.
///
/// This protocol enables dependency injection and testability by allowing
/// mock implementations to be substituted for the real `WebClient`.
///
/// ## Example
/// ```swift
/// class UserService {
///     private let client: any EndpointInvoking
///
///     init(client: any EndpointInvoking) {
///         self.client = client
///     }
///
///     func getUser(id: String) async throws -> User {
///         try await client.invoke(GetUserEndpoint(userId: id))
///     }
/// }
///
/// // In production
/// let service = UserService(client: WebClient(configuration: config))
///
/// // In tests
/// let mockClient = MockWebClient()
/// await mockClient.stub(GetUserEndpoint.self, response: User(id: "123", name: "Test"))
/// let service = UserService(client: mockClient)
/// ```
public protocol EndpointInvoking: Sendable {
    /// Invokes an endpoint and returns the success response.
    ///
    /// - Parameter endpoint: The endpoint to invoke.
    /// - Returns: The decoded success value.
    /// - Throws: An error on failure (typically `WebClientError<E.Failure>`).
    @discardableResult
    func invoke<E: Endpoint>(_ endpoint: E) async throws -> E.Success
}
