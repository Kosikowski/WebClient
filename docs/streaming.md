# Streaming Responses

WebClient supports streaming responses including Server-Sent Events (SSE) and newline-delimited JSON (NDJSON).

## Server-Sent Events (SSE)

### Define an SSE Endpoint

```swift
struct NotificationStreamEndpoint: SSEStreamingEndpoint {
    typealias Failure = APIError

    var path: String { "/notifications/stream" }
}
```

### Stream Events

```swift
for try await event in client.streamSSE(NotificationStreamEndpoint()) {
    switch event.event {
    case "message":
        print("Message: \(event.data)")
    case "notification":
        let notification = try JSONDecoder().decode(
            Notification.self,
            from: Data(event.data.utf8)
        )
        handleNotification(notification)
    default:
        break
    }
}
```

### ServerSentEvent Structure

```swift
struct ServerSentEvent {
    let event: String?    // Event type (from "event:" field)
    let data: String      // Event data (from "data:" field)
    let id: String?       // Event ID (from "id:" field)
    let retry: Int?       // Retry interval in ms (from "retry:" field)
}
```

## Newline-Delimited JSON (NDJSON)

### Define an NDJSON Endpoint

```swift
struct LogStreamEndpoint: JSONLinesStreamingEndpoint {
    typealias Element = LogEntry
    typealias Failure = Void

    var path: String { "/logs/stream" }

    var decoder: any Decoding {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct LogEntry: Decodable, Sendable {
    let timestamp: Date
    let level: String
    let message: String
}
```

### Stream JSON Lines

```swift
for try await logEntry in client.stream(LogStreamEndpoint()) {
    print("[\(logEntry.level)] \(logEntry.message)")
}
```

## Custom Streaming Endpoint

For custom line-based protocols:

```swift
struct CustomStreamEndpoint: StreamingEndpoint {
    typealias Element = ParsedLine
    typealias Failure = StreamError

    var path: String { "/custom/stream" }

    func decodeElement(from line: String) throws -> ParsedLine? {
        // Skip empty lines and comments
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") {
            return nil
        }

        // Parse your custom format
        return try parseLine(trimmed)
    }

    func decodeFailure(from data: Data) -> StreamError? {
        try? JSONDecoder().decode(StreamError.self, from: data)
    }
}
```

## Streaming with Request Body

```swift
struct ChatStreamEndpoint: SSEStreamingEndpoint {
    typealias Failure = APIError

    let messages: [ChatMessage]

    var path: String { "/chat/stream" }
    var method: HTTPMethod { .post }
    var body: (any Encodable & Sendable)? {
        ChatRequest(messages: messages)
    }
    var encoder: (any Encoding)? { JSONEncoder() }
}

// Stream the response
for try await event in client.streamSSE(
    ChatStreamEndpoint(messages: conversation)
) {
    if event.event == "delta" {
        appendToResponse(event.data)
    }
}
```

## Cancellation

Streams automatically handle task cancellation:

```swift
let streamTask = Task {
    for try await event in client.streamSSE(endpoint) {
        process(event)
    }
}

// Later: cancel the stream
streamTask.cancel()
```

## Error Handling

```swift
do {
    for try await event in client.streamSSE(endpoint) {
        handle(event)
    }
} catch let error as WebClientError<APIError> {
    switch error {
    case .serverError(let code, let apiError, _):
        print("Stream error \(code): \(apiError?.message ?? "Unknown")")
    case .offline:
        print("Connection lost")
    case .cancelled:
        print("Stream cancelled")
    default:
        print("Error: \(error)")
    }
}
```

## Headers for Streaming

SSE endpoints automatically include appropriate headers:

```swift
Accept: text/event-stream
Cache-Control: no-cache
```

You can add additional headers:

```swift
var headers: [String: String]? {
    ["Last-Event-ID": lastEventId]  // For resuming streams
}
```
