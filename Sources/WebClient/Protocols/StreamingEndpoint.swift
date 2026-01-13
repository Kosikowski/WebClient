import Foundation

/// A protocol for endpoints that return streaming responses.
///
/// Use this protocol for Server-Sent Events (SSE), chunked responses,
/// or any endpoint where data arrives incrementally.
///
/// ## Example: Server-Sent Events
/// ```swift
/// struct EventStreamEndpoint: StreamingEndpoint {
///     typealias Element = ServerEvent
///     typealias Failure = APIError
///
///     var path: String { "/events" }
///
///     func decodeElement(from line: String) throws -> ServerEvent? {
///         guard line.hasPrefix("data: ") else { return nil }
///         let json = String(line.dropFirst(6))
///         return try JSONDecoder().decode(ServerEvent.self, from: Data(json.utf8))
///     }
/// }
///
/// // Usage
/// for try await event in client.stream(EventStreamEndpoint()) {
///     print("Received: \(event)")
/// }
/// ```
public protocol StreamingEndpoint: RequestProviding, Sendable {
    /// The type of elements yielded by the stream.
    associatedtype Element: Sendable

    /// The type of error response from the server.
    ///
    /// Use `Void` if the server doesn't return structured error responses.
    associatedtype Failure: Sendable

    /// Decodes a single element from a line of text.
    ///
    /// Called for each line received from the server.
    /// Return `nil` to skip the line (e.g., for comments or empty lines).
    ///
    /// - Parameter line: A single line from the response.
    /// - Returns: The decoded element, or `nil` to skip.
    /// - Throws: A decoding error if the line is malformed.
    func decodeElement(from line: String) throws -> Element?

    /// Decodes a failure response from error data.
    ///
    /// Called when the server returns a non-2xx status code.
    /// The default implementation returns `nil`.
    ///
    /// - Parameter data: The error response body.
    /// - Returns: The decoded failure, or `nil` if decoding fails.
    func decodeFailure(from data: Data) -> Failure?
}

// MARK: - Default Implementations

public extension StreamingEndpoint {
    func decodeFailure(from _: Data) -> Failure? { nil }
}

// MARK: - Line-Delimited Streaming

/// A streaming endpoint that decodes JSON objects from newline-delimited JSON (NDJSON).
///
/// Each line in the response is expected to be a complete JSON object.
///
/// ## Example
/// ```swift
/// struct LogStreamEndpoint: JSONLinesStreamingEndpoint {
///     typealias Element = LogEntry
///     typealias Failure = Void
///
///     var path: String { "/logs/stream" }
///     var decoder: any Decoding { JSONDecoder() }
/// }
/// ```
public protocol JSONLinesStreamingEndpoint: StreamingEndpoint where Element: Decodable {
    /// The decoder to use for JSON lines.
    var decoder: any Decoding { get }
}

public extension JSONLinesStreamingEndpoint {
    var decoder: any Decoding { JSONDecoder() }

    func decodeElement(from line: String) throws -> Element? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try decoder.decode(Element.self, from: Data(trimmed.utf8))
    }
}

// MARK: - Server-Sent Events

/// Represents a Server-Sent Event.
public struct ServerSentEvent: Sendable, Equatable {
    /// The event type (from the `event:` field).
    public let event: String?

    /// The event data (from the `data:` field).
    public let data: String

    /// The event ID (from the `id:` field).
    public let id: String?

    /// The retry interval in milliseconds (from the `retry:` field).
    public let retry: Int?

    public init(event: String? = nil, data: String, id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }
}

/// A streaming endpoint for Server-Sent Events (SSE).
///
/// Automatically parses SSE format and yields `ServerSentEvent` objects.
///
/// ## Example
/// ```swift
/// struct NotificationStreamEndpoint: SSEStreamingEndpoint {
///     typealias Failure = APIError
///
///     var path: String { "/notifications/stream" }
/// }
///
/// for try await event in client.stream(NotificationStreamEndpoint()) {
///     if event.event == "notification" {
///         let notification = try JSONDecoder().decode(Notification.self, from: Data(event.data.utf8))
///         handleNotification(notification)
///     }
/// }
/// ```
public protocol SSEStreamingEndpoint: StreamingEndpoint where Element == ServerSentEvent {}

public extension SSEStreamingEndpoint {
    func decodeElement(from _: String) throws -> ServerSentEvent? {
        // SSE parsing is handled at the stream level, not per-line
        // This is a placeholder - actual SSE parsing happens in WebClient.stream()
        nil
    }
}
