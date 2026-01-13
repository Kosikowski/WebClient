import Foundation

/// A modern, generic HTTP client for invoking API endpoints.
///
/// `WebClient` is an actor that provides thread-safe, async/await based HTTP communication.
/// It supports typed error handling, automatic retries, interceptors, and flexible encoding/decoding.
///
/// ## Features
/// - Type-safe endpoint definitions with `Endpoint` protocol
/// - Automatic decoding of success and failure responses
/// - Configurable retry policy with exponential backoff
/// - Request and response interceptors for cross-cutting concerns
/// - Generic encoding/decoding (JSON, XML, Property Lists)
/// - Full Swift 6 concurrency support with typed throws
///
/// ## Example
/// ```swift
/// // Define an endpoint
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
/// // Create client and invoke
/// let config = WebClientConfiguration(baseURL: URL(string: "https://api.example.com")!)
/// let client = WebClient(configuration: config)
///
/// do {
///     let user = try await client.invoke(GetUserEndpoint(userId: "123"))
///     print("User: \(user.name)")
/// } catch let error as WebClientError<APIError> {
///     if let apiError = error.failure {
///         print("API Error: \(apiError.message)")
///     }
/// }
/// ```
public actor WebClient: EndpointInvoking {
    /// The configuration for this client.
    public let configuration: WebClientConfiguration

    /// The URL session used for requests.
    let session: URLSession

    // MARK: - Initialization

    /// Creates a new WebClient with the given configuration.
    /// - Parameter configuration: The client configuration.
    public init(configuration: WebClientConfiguration) {
        self.configuration = configuration

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = Double(configuration.timeout.components.seconds)
        sessionConfig.timeoutIntervalForResource = Double(configuration.resourceTimeout.components.seconds)
        session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Public API

    /// Invokes an endpoint and returns the success response.
    ///
    /// This method handles the full request lifecycle:
    /// 1. Builds the URL request from the endpoint
    /// 2. Applies request interceptors
    /// 3. Executes the request with automatic retries
    /// 4. Applies response interceptors
    /// 5. Validates the response status code
    /// 6. Decodes either success or failure responses
    ///
    /// - Parameter endpoint: The endpoint to invoke.
    /// - Returns: The decoded success value.
    /// - Throws: `WebClientError<E.Failure>` on failure.
    @discardableResult
    public func invoke<E: Endpoint>(_ endpoint: E) async throws -> E.Success {
        try await invokeWithRetry(endpoint, attemptNumber: 0)
    }

    /// Invokes an endpoint with typed throws.
    ///
    /// This variant uses Swift 6 typed throws for compile-time error type safety.
    ///
    /// - Parameter endpoint: The endpoint to invoke.
    /// - Returns: The decoded success value.
    /// - Throws: `WebClientError<E.Failure>` on failure.
    @discardableResult
    public func invokeTyped<E: Endpoint>(
        _ endpoint: E
    ) async throws(WebClientError<E.Failure>) -> E.Success {
        do {
            return try await invokeWithRetry(endpoint, attemptNumber: 0)
        } catch let error as WebClientError<E.Failure> {
            throw error
        } catch {
            throw .networkError(underlying: error)
        }
    }

    /// Invokes an endpoint and returns a Result.
    ///
    /// This is a non-throwing variant that captures errors in a Result type.
    ///
    /// - Parameter endpoint: The endpoint to invoke.
    /// - Returns: A Result containing either the success value or an error.
    public func send<E: Endpoint>(_ endpoint: E) async -> Result<E.Success, WebClientError<E.Failure>> {
        do {
            let result = try await invoke(endpoint)
            return .success(result)
        } catch let error as WebClientError<E.Failure> {
            return .failure(error)
        } catch {
            return .failure(.networkError(underlying: error))
        }
    }

    // MARK: - Streaming API

    /// Invokes a streaming endpoint and returns an async sequence of elements.
    ///
    /// This method is designed for Server-Sent Events (SSE), newline-delimited JSON (NDJSON),
    /// or any endpoint that returns data incrementally.
    ///
    /// The stream automatically handles:
    /// - Line-by-line parsing
    /// - Task cancellation
    /// - Error propagation
    ///
    /// ## Example
    /// ```swift
    /// for try await event in client.stream(EventStreamEndpoint()) {
    ///     print("Received: \(event)")
    /// }
    /// ```
    ///
    /// - Parameter endpoint: The streaming endpoint to invoke.
    /// - Returns: An async throwing stream of decoded elements.
    public func stream<E: StreamingEndpoint>(
        _ endpoint: E
    ) -> AsyncThrowingStream<E.Element, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performStreamingRequest(endpoint, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Invokes a Server-Sent Events endpoint and returns an async sequence of events.
    ///
    /// This is a convenience method for SSE endpoints that handles the SSE protocol parsing.
    ///
    /// ## Example
    /// ```swift
    /// for try await event in client.streamSSE(NotificationEndpoint()) {
    ///     if event.event == "message" {
    ///         handleMessage(event.data)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter endpoint: The SSE endpoint to invoke.
    /// - Returns: An async throwing stream of Server-Sent Events.
    public func streamSSE<E: SSEStreamingEndpoint>(
        _ endpoint: E
    ) -> AsyncThrowingStream<ServerSentEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await performSSERequest(endpoint, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private Implementation

    /// Returns the effective retry policy for an endpoint.
    ///
    /// Uses the endpoint's retry policy if specified, otherwise falls back to the client's policy.
    private func effectiveRetryPolicy<E: Endpoint>(for endpoint: E) -> RetryPolicy {
        endpoint.retryPolicy ?? configuration.retryPolicy
    }

    /// Generates a request ID if configured, or returns nil.
    private func generateRequestId() -> String? {
        configuration.requestIdGenerator?()
    }

    /// Performs the request with automatic retries based on the retry policy.
    private func invokeWithRetry<E: Endpoint>(
        _ endpoint: E,
        attemptNumber: Int,
        requestId: String? = nil
    ) async throws -> E.Success {
        // Generate request ID on first attempt
        let requestId = requestId ?? generateRequestId()

        // Use endpoint's retry policy if specified, otherwise use client's policy
        let retryPolicy = effectiveRetryPolicy(for: endpoint)
        let maxAttempts = retryPolicy.maxRetries + 1

        // Check for cancellation before starting
        try Task.checkCancellation()

        do {
            return try await performRequest(endpoint, attemptNumber: attemptNumber, requestId: requestId)
        } catch is CancellationError {
            // Task was cancelled - convert to our error type
            throw WebClientError<E.Failure>.cancelled
        } catch is RetryRequestError {
            // Interceptor requested a retry
            if attemptNumber < maxAttempts - 1 {
                // Check for cancellation before retrying
                try Task.checkCancellation()
                return try await invokeWithRetry(endpoint, attemptNumber: attemptNumber + 1, requestId: requestId)
            }
            throw WebClientError<E.Failure>.unexpectedResponse
        } catch let error as WebClientError<E.Failure> {
            // Don't retry if error is not retryable or this is the last attempt
            if !error.isRetryable || attemptNumber >= maxAttempts - 1 {
                throw error
            }

            // Check for cancellation before waiting
            try Task.checkCancellation()

            // Wait before retrying
            let delay = retryPolicy.delay(for: attemptNumber)
            try await Task.sleep(for: delay)

            // Check for cancellation after waiting
            try Task.checkCancellation()

            return try await invokeWithRetry(endpoint, attemptNumber: attemptNumber + 1, requestId: requestId)
        } catch is CancellationError {
            throw WebClientError<E.Failure>.cancelled
        } catch {
            // Unexpected error type - wrap and throw
            throw WebClientError<E.Failure>.networkError(underlying: error)
        }
    }

    /// Performs a single request attempt.
    private func performRequest<E: Endpoint>(
        _ endpoint: E,
        attemptNumber: Int,
        requestId: String?
    ) async throws -> E.Success {
        // Build the URL request
        guard var request = endpoint.urlRequest(
            relativeTo: configuration.baseURL,
            defaultHeaders: configuration.defaultHeaders,
            defaultEncoder: configuration.defaultEncoder
        ) else {
            throw WebClientError<E.Failure>.invalidRequest("Failed to build URL request from endpoint")
        }

        // Add request ID header if provided
        if let requestId {
            request.setValue(requestId, forHTTPHeaderField: configuration.requestIdHeaderName)
        }

        // Create request context for interceptors
        let requestContext = RequestContext(
            path: endpoint.path,
            method: endpoint.method,
            attemptNumber: attemptNumber,
            requestId: requestId
        )

        // Apply request interceptors
        for interceptor in configuration.requestInterceptors {
            do {
                request = try await interceptor.intercept(request, context: requestContext)
            } catch is CancellationError {
                throw WebClientError<E.Failure>.cancelled
            } catch {
                throw WebClientError<E.Failure>.networkError(underlying: error)
            }
        }

        // Record start time for response context
        let startTime = ContinuousClock.now

        // Execute the request
        var data: Data
        var response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw WebClientError<E.Failure>.from(urlError: error)
        } catch is CancellationError {
            throw WebClientError<E.Failure>.cancelled
        } catch {
            throw WebClientError<E.Failure>.networkError(underlying: error)
        }

        // Calculate duration
        let duration = ContinuousClock.now - startTime

        // Validate response type
        guard var httpResponse = response as? HTTPURLResponse else {
            throw WebClientError<E.Failure>.unexpectedResponse
        }

        // Create response context for interceptors
        let responseContext = ResponseContext(
            path: endpoint.path,
            method: endpoint.method,
            attemptNumber: attemptNumber,
            duration: duration,
            requestId: requestId
        )

        // Apply response interceptors
        for interceptor in configuration.responseInterceptors {
            do {
                (data, httpResponse) = try await interceptor.intercept(
                    data,
                    response: httpResponse,
                    context: responseContext
                )
            } catch is CancellationError {
                throw WebClientError<E.Failure>.cancelled
            } catch {
                throw error
            }
        }

        // Check if status code indicates success
        if endpoint.successStatusCodes.contains(httpResponse.statusCode) {
            // Decode success response
            do {
                return try endpoint.decodeSuccess(from: data, response: httpResponse)
            } catch {
                throw WebClientError<E.Failure>.decodingError(underlying: error, data: data)
            }
        } else {
            // Decode failure response (if possible)
            let failure: E.Failure?
            do {
                failure = try endpoint.decodeFailure(from: data, response: httpResponse)
            } catch {
                // Failed to decode error body - that's OK, we'll pass nil
                failure = nil
            }

            throw WebClientError<E.Failure>.serverError(
                statusCode: httpResponse.statusCode,
                failure: failure,
                data: data
            )
        }
    }

    // MARK: - Streaming Implementation

    /// Performs a streaming request and yields elements to the continuation.
    private func performStreamingRequest<E: StreamingEndpoint>(
        _ endpoint: E,
        continuation: AsyncThrowingStream<E.Element, any Error>.Continuation
    ) async throws {
        // Check for cancellation before starting
        try Task.checkCancellation()

        // Build the URL request
        guard var request = endpoint.urlRequest(
            relativeTo: configuration.baseURL,
            defaultHeaders: configuration.defaultHeaders,
            defaultEncoder: configuration.defaultEncoder
        ) else {
            throw WebClientError<E.Failure>.invalidRequest("Failed to build URL request from endpoint")
        }

        // Generate request ID if configured
        let requestId = generateRequestId()
        if let requestId {
            request.setValue(requestId, forHTTPHeaderField: configuration.requestIdHeaderName)
        }

        // Create request context for interceptors
        let requestContext = RequestContext(
            path: endpoint.path,
            method: endpoint.method,
            attemptNumber: 0,
            requestId: requestId
        )

        // Apply request interceptors
        for interceptor in configuration.requestInterceptors {
            request = try await interceptor.intercept(request, context: requestContext)
        }

        // Execute the streaming request
        let (bytes, response) = try await session.bytes(for: request)

        // Validate response type
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebClientError<E.Failure>.unexpectedResponse
        }

        // Check for error status codes
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            // Try to read the error body
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                // Limit error body size to prevent memory issues
                if errorData.count > 1_000_000 { break }
            }

            throw WebClientError<E.Failure>.serverError(
                statusCode: httpResponse.statusCode,
                failure: endpoint.decodeFailure(from: errorData),
                data: errorData
            )
        }

        // Process the stream line by line
        var lineBuffer = ""

        for try await byte in bytes {
            // Check for cancellation periodically
            try Task.checkCancellation()

            let char = Character(UnicodeScalar(byte))

            if char == "\n" {
                // Process complete line
                if let element = try endpoint.decodeElement(from: lineBuffer) {
                    continuation.yield(element)
                }
                lineBuffer = ""
            } else if char != "\r" {
                lineBuffer.append(char)
            }
        }

        // Process any remaining data in the buffer
        if !lineBuffer.isEmpty {
            if let element = try endpoint.decodeElement(from: lineBuffer) {
                continuation.yield(element)
            }
        }

        continuation.finish()
    }

    /// Performs an SSE request and yields events to the continuation.
    private func performSSERequest<E: SSEStreamingEndpoint>(
        _ endpoint: E,
        continuation: AsyncThrowingStream<ServerSentEvent, any Error>.Continuation
    ) async throws {
        // Check for cancellation before starting
        try Task.checkCancellation()

        // Build the URL request
        guard var request = endpoint.urlRequest(
            relativeTo: configuration.baseURL,
            defaultHeaders: configuration.defaultHeaders,
            defaultEncoder: configuration.defaultEncoder
        ) else {
            throw WebClientError<E.Failure>.invalidRequest("Failed to build URL request from endpoint")
        }

        // Add SSE-specific headers
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        // Generate request ID if configured
        let requestId = generateRequestId()
        if let requestId {
            request.setValue(requestId, forHTTPHeaderField: configuration.requestIdHeaderName)
        }

        // Create request context for interceptors
        let requestContext = RequestContext(
            path: endpoint.path,
            method: endpoint.method,
            attemptNumber: 0,
            requestId: requestId
        )

        // Apply request interceptors
        for interceptor in configuration.requestInterceptors {
            request = try await interceptor.intercept(request, context: requestContext)
        }

        // Execute the streaming request
        let (bytes, response) = try await session.bytes(for: request)

        // Validate response type
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebClientError<E.Failure>.unexpectedResponse
        }

        // Check for error status codes
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count > 1_000_000 { break }
            }

            throw WebClientError<E.Failure>.serverError(
                statusCode: httpResponse.statusCode,
                failure: endpoint.decodeFailure(from: errorData),
                data: errorData
            )
        }

        // Parse SSE stream
        var currentEvent: String?
        var currentData: [String] = []
        var currentId: String?
        var currentRetry: Int?
        var lineBuffer = ""

        for try await byte in bytes {
            try Task.checkCancellation()

            let char = Character(UnicodeScalar(byte))

            if char == "\n" {
                let line = lineBuffer
                lineBuffer = ""

                if line.isEmpty {
                    // Empty line = dispatch event
                    if !currentData.isEmpty {
                        let event = ServerSentEvent(
                            event: currentEvent,
                            data: currentData.joined(separator: "\n"),
                            id: currentId,
                            retry: currentRetry
                        )
                        continuation.yield(event)
                    }

                    // Reset for next event (keep id for subsequent events per SSE spec)
                    currentEvent = nil
                    currentData = []
                    currentRetry = nil
                } else if line.hasPrefix(":") {
                    // Comment line - ignore
                } else if line.hasPrefix("event:") {
                    currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("data:") {
                    currentData.append(String(line.dropFirst(5)).trimmingCharacters(in: .init(charactersIn: " ")))
                } else if line.hasPrefix("id:") {
                    currentId = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("retry:") {
                    let retryStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    currentRetry = Int(retryStr)
                }
            } else if char != "\r" {
                lineBuffer.append(char)
            }
        }

        // Dispatch any remaining event
        if !currentData.isEmpty {
            let event = ServerSentEvent(
                event: currentEvent,
                data: currentData.joined(separator: "\n"),
                id: currentId,
                retry: currentRetry
            )
            continuation.yield(event)
        }

        continuation.finish()
    }
}
