import Foundation

/// A protocol for types that can decode `Decodable` values from `Data`.
///
/// This abstraction allows WebClient to work with different decoding formats
/// (JSON, XML, Property Lists, etc.) without being tied to a specific implementation.
///
/// ## Conforming Types
/// - `JSONDecoder` conforms automatically
/// - `PropertyListDecoder` conforms automatically
/// - Custom XML decoders can conform for SOAP support
public protocol Decoding: Sendable {
    /// Decodes a value of the given type from `Data`.
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - data: The data to decode from.
    /// - Returns: The decoded value.
    /// - Throws: An error if decoding fails.
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

// MARK: - Default Conformances

extension JSONDecoder: Decoding {}

extension PropertyListDecoder: Decoding {}
