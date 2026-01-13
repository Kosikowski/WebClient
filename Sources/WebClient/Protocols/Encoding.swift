import Foundation

/// A protocol for types that can encode `Encodable` values to `Data`.
///
/// This abstraction allows WebClient to work with different encoding formats
/// (JSON, XML, Property Lists, etc.) without being tied to a specific implementation.
///
/// ## Conforming Types
/// - `JSONEncoder` conforms automatically
/// - `PropertyListEncoder` conforms automatically
/// - Custom XML encoders can conform for SOAP support
public protocol Encoding: Sendable {
    /// Encodes the given value to `Data`.
    /// - Parameter value: The value to encode.
    /// - Returns: The encoded data.
    /// - Throws: An error if encoding fails.
    func encode<T: Encodable>(_ value: T) throws -> Data
}

// MARK: - Default Conformances

extension JSONEncoder: Encoding {}

extension PropertyListEncoder: Encoding {}
