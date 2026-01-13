import Foundation

/// A component of a URL path for type-safe path building.
///
/// Use `PathComponent` to construct URL paths in a type-safe manner,
/// avoiding string interpolation errors and improving code clarity.
///
/// ## Example
/// ```swift
/// struct GetUserPostEndpoint: RequestProviding {
///     let userId: String
///     let postId: String
///
///     var pathComponents: [PathComponent] {
///         [
///             .literal("users"),
///             .value(userId),
///             .literal("posts"),
///             .value(postId)
///         ]
///     }
///     // Produces: /users/123/posts/456
/// }
/// ```
public enum PathComponent: Sendable, Equatable {
    /// A literal path segment that is used as-is.
    ///
    /// Example: `.literal("users")` produces `/users`
    case literal(String)

    /// A dynamic value that will be URL-encoded.
    ///
    /// Example: `.value("john doe")` produces `/john%20doe`
    case value(String)

    /// A dynamic integer value.
    ///
    /// Example: `.int(123)` produces `/123`
    case int(Int)

    /// An optional value that is only included if non-nil.
    ///
    /// Example: `.optional(maybeId)` produces `/123` or is skipped if nil
    case optional(String?)

    /// The string representation of this component.
    ///
    /// Values are returned as-is. URL encoding is handled by URLComponents
    /// when building the final URL, avoiding double-encoding issues.
    public var stringValue: String {
        switch self {
        case let .literal(string):
            return string
        case let .value(string):
            return string
        case let .int(number):
            return String(number)
        case let .optional(string):
            return string ?? ""
        }
    }

    /// Whether this component should be included in the path.
    ///
    /// Optional components with nil values are excluded.
    public var isIncluded: Bool {
        switch self {
        case .optional(nil):
            return false
        default:
            return true
        }
    }
}

// MARK: - Path Building

public extension Array where Element == PathComponent {
    /// Builds a URL path string from the components.
    ///
    /// Components are joined with `/` and prefixed with `/`.
    /// Optional components with nil values are excluded.
    ///
    /// - Returns: The constructed path string.
    ///
    /// ## Example
    /// ```swift
    /// let components: [PathComponent] = [.literal("api"), .literal("v1"), .value("users")]
    /// let path = components.buildPath() // "/api/v1/users"
    /// ```
    func buildPath() -> String {
        let parts = filter(\.isIncluded)
            .map(\.stringValue)
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else { return "/" }
        return "/" + parts.joined(separator: "/")
    }
}

// MARK: - ExpressibleByStringLiteral

extension PathComponent: ExpressibleByStringLiteral {
    /// Creates a literal path component from a string literal.
    ///
    /// This allows using string literals directly in path component arrays:
    /// ```swift
    /// var pathComponents: [PathComponent] { ["users", .value(userId), "posts"] }
    /// ```
    public init(stringLiteral value: String) {
        self = .literal(value)
    }
}

// MARK: - ExpressibleByIntegerLiteral

extension PathComponent: ExpressibleByIntegerLiteral {
    /// Creates an integer path component from an integer literal.
    ///
    /// This allows using integer literals directly in path component arrays:
    /// ```swift
    /// var pathComponents: [PathComponent] { ["api", "v1", "users"] }
    /// ```
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}
