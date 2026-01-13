import Foundation

/// A protocol that defines how an endpoint constructs its HTTP request.
///
/// Conforming types specify the HTTP method, path, headers, query parameters,
/// and optional body for their requests.
///
/// ## Path Definition
/// You can define the path using either:
/// - `path`: A simple string path (traditional approach)
/// - `pathComponents`: A type-safe array of path components (recommended for dynamic paths)
///
/// If you implement `pathComponents`, the `path` property is automatically derived from it.
///
/// ## Example (String Path)
/// ```swift
/// struct GetUserEndpoint: RequestProviding {
///     let userId: String
///
///     var path: String { "/users/\(userId)" }
/// }
/// ```
///
/// ## Example (Type-Safe Path)
/// ```swift
/// struct GetUserPostEndpoint: RequestProviding {
///     let userId: String
///     let postId: String
///
///     var pathComponents: [PathComponent] {
///         ["users", .value(userId), "posts", .value(postId)]
///     }
///     // Produces: /users/123/posts/456
/// }
/// ```
public protocol RequestProviding: Sendable {
    /// The HTTP method for this request.
    ///
    /// Defaults to `.get`.
    var method: HTTPMethod { get }

    /// The path relative to the base URL.
    ///
    /// This will be appended to the WebClient's base URL.
    ///
    /// You can either implement this directly, or implement `pathComponents`
    /// and this will be automatically derived.
    var path: String { get }

    /// Type-safe path components for building the URL path.
    ///
    /// Use this instead of `path` for dynamic paths with parameters.
    /// The components are joined with `/` and URL-encoded as needed.
    ///
    /// Defaults to `nil` (uses `path` instead).
    ///
    /// ## Example
    /// ```swift
    /// var pathComponents: [PathComponent] {
    ///     ["api", "v1", "users", .value(userId), "posts", .value(postId)]
    /// }
    /// // Produces: /api/v1/users/123/posts/456
    /// ```
    var pathComponents: [PathComponent]? { get }

    /// Query parameters to include in the URL.
    ///
    /// Defaults to `nil`.
    var queryItems: [URLQueryItem]? { get }

    /// HTTP headers specific to this endpoint.
    ///
    /// These are merged with the WebClient's default headers.
    /// Endpoint headers take precedence over default headers.
    /// Defaults to `nil`.
    var headers: [String: String]? { get }

    /// The request body data.
    ///
    /// For endpoints that need to send data (POST, PUT, etc.),
    /// provide the encodable body here.
    /// Defaults to `nil`.
    var body: (any Encodable & Sendable)? { get }

    /// The encoder to use for the request body.
    ///
    /// If `body` is provided, this encoder will be used to encode it.
    /// Defaults to `nil` (uses JSON encoding if body is present).
    var encoder: (any Encoding)? { get }

    /// Optional retry policy override for this endpoint.
    ///
    /// When set, this policy takes precedence over the client's default policy.
    /// Use this to disable retries for non-idempotent operations or customize
    /// retry behavior for specific endpoints.
    ///
    /// Defaults to `nil` (uses client's retry policy).
    ///
    /// ## Example
    /// ```swift
    /// struct CreateOrderEndpoint: Endpoint {
    ///     // Disable retries for non-idempotent POST
    ///     var retryPolicy: RetryPolicy? { .none }
    /// }
    /// ```
    var retryPolicy: RetryPolicy? { get }
}

// MARK: - Default Implementations

public extension RequestProviding {
    var method: HTTPMethod { .get }
    var pathComponents: [PathComponent]? { nil }
    var queryItems: [URLQueryItem]? { nil }
    var headers: [String: String]? { nil }
    var body: (any Encodable & Sendable)? { nil }
    var encoder: (any Encoding)? { nil }
    var retryPolicy: RetryPolicy? { nil }

    /// The resolved path, using `pathComponents` if available, otherwise `path`.
    var resolvedPath: String {
        if let pathComponents {
            return pathComponents.buildPath()
        }
        return path
    }
}

// MARK: - URL Request Building

public extension RequestProviding {
    /// Builds a `URLRequest` from this endpoint's configuration.
    /// - Parameters:
    ///   - baseURL: The base URL to build upon.
    ///   - defaultHeaders: Default headers to include.
    ///   - defaultEncoder: Default encoder to use if none specified.
    /// - Returns: A configured `URLRequest`, or `nil` if the URL couldn't be constructed.
    func urlRequest(
        relativeTo baseURL: URL,
        defaultHeaders: [String: String] = [:],
        defaultEncoder: any Encoding = JSONEncoder()
    ) -> URLRequest? {
        // Build URL with path and query items
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        components?.path = resolvedPath

        if let queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            return nil
        }

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // Apply default headers first, then endpoint headers (endpoint takes precedence)
        for (key, value) in defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Encode body if present
        if let body {
            let encoderToUse = encoder ?? defaultEncoder
            do {
                request.httpBody = try encoderToUse.encode(body)

                // Set Content-Type if not already set
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    if encoderToUse is JSONEncoder {
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    }
                }
            } catch {
                // Body encoding failed - return nil to signal error
                return nil
            }
        }

        return request
    }
}
