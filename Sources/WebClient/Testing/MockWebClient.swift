import Foundation

/// A mock web client for testing that returns pre-configured responses.
///
/// `MockWebClient` allows you to stub responses for specific endpoint types,
/// making it easy to write unit tests without making real network requests.
///
/// ## Example
/// ```swift
/// @Test func testUserFetching() async throws {
///     let mockClient = MockWebClient()
///
///     // Stub a successful response
///     await mockClient.stub(
///         GetUserEndpoint.self,
///         response: User(id: "123", name: "Test User")
///     )
///
///     // Use the mock in your service
///     let service = UserService(client: mockClient)
///     let user = try await service.getUser(id: "123")
///
///     #expect(user.name == "Test User")
///
///     // Verify the endpoint was called
///     let callCount = await mockClient.callCount(for: GetUserEndpoint.self)
///     #expect(callCount == 1)
/// }
///
/// @Test func testErrorHandling() async throws {
///     let mockClient = MockWebClient()
///
///     // Stub an error
///     await mockClient.stubError(
///         GetUserEndpoint.self,
///         error: WebClientError<APIError>.serverError(
///             statusCode: 404,
///             failure: APIError(message: "User not found"),
///             data: nil
///         )
///     )
///
///     let service = UserService(client: mockClient)
///
///     await #expect(throws: Error.self) {
///         try await service.getUser(id: "123")
///     }
/// }
/// ```
public actor MockWebClient: EndpointInvoking {
    /// Storage for stubbed responses, keyed by endpoint type name.
    private var stubs: [String: AnySendable] = [:]

    /// Storage for stubbed errors, keyed by endpoint type name.
    private var errors: [String: any Error] = [:]

    /// Call counts for each endpoint type.
    private var calls: [String: Int] = [:]

    /// Captured endpoints for verification.
    private var capturedEndpoints: [String: [AnySendable]] = [:]

    /// Creates a new mock web client.
    public init() {}

    // MARK: - Stubbing

    /// Stubs a successful response for an endpoint type.
    ///
    /// When `invoke` is called with an endpoint of the given type,
    /// it will return this response instead of making a network request.
    ///
    /// - Parameters:
    ///   - endpointType: The endpoint type to stub.
    ///   - response: The response to return.
    public func stub<E: Endpoint>(_ endpointType: E.Type, response: E.Success) {
        let key = endpointKey(for: endpointType)
        stubs[key] = AnySendable(response)
        errors[key] = nil
    }

    /// Stubs an error for an endpoint type.
    ///
    /// When `invoke` is called with an endpoint of the given type,
    /// it will throw this error instead of making a network request.
    ///
    /// - Parameters:
    ///   - endpointType: The endpoint type to stub.
    ///   - error: The error to throw.
    public func stubError<E: Endpoint>(_ endpointType: E.Type, error: any Error) {
        let key = endpointKey(for: endpointType)
        errors[key] = error
        stubs[key] = nil
    }

    /// Removes all stubs and recorded calls.
    public func reset() {
        stubs.removeAll()
        errors.removeAll()
        calls.removeAll()
        capturedEndpoints.removeAll()
    }

    // MARK: - Verification

    /// Returns the number of times an endpoint type was invoked.
    ///
    /// - Parameter endpointType: The endpoint type to check.
    /// - Returns: The number of invocations.
    public func callCount<E: Endpoint>(for endpointType: E.Type) -> Int {
        let key = endpointKey(for: endpointType)
        return calls[key] ?? 0
    }

    /// Returns whether an endpoint type was ever invoked.
    ///
    /// - Parameter endpointType: The endpoint type to check.
    /// - Returns: `true` if the endpoint was invoked at least once.
    public func wasCalled<E: Endpoint>(_ endpointType: E.Type) -> Bool {
        callCount(for: endpointType) > 0
    }

    // MARK: - EndpointInvoking

    @discardableResult
    public func invoke<E: Endpoint>(_ endpoint: E) async throws -> E.Success {
        let key = endpointKey(for: type(of: endpoint))

        // Record the call
        calls[key, default: 0] += 1

        // Capture the endpoint for later verification
        if capturedEndpoints[key] == nil {
            capturedEndpoints[key] = []
        }
        capturedEndpoints[key]?.append(AnySendable(endpoint))

        // Check for stubbed error first
        if let error = errors[key] {
            throw error
        }

        // Check for stubbed response
        guard let stub = stubs[key], let response = stub.value as? E.Success else {
            fatalError(
                """
                MockWebClient: No stub registered for endpoint type '\(key)'.
                Call `stub(\(key).self, response: ...)` before invoking this endpoint.
                """
            )
        }

        return response
    }

    // MARK: - Private

    private func endpointKey<E: Endpoint>(for _: E.Type) -> String {
        String(describing: E.self)
    }
}

// MARK: - AnySendable Wrapper

/// Type-erased Sendable wrapper for storing heterogeneous values.
private struct AnySendable: @unchecked Sendable {
    let value: Any

    init<T: Sendable>(_ value: T) {
        self.value = value
    }
}
