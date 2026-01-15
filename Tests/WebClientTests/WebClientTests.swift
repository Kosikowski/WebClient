import Foundation
import Testing
@testable import WebClient

@Suite("WebClient Tests")
struct WebClientTests {
    // MARK: - RetryPolicy Tests

    @Test("Retry policy exponential backoff delays")
    func retryPolicyDelays() {
        let policy = RetryPolicy.exponentialBackoff(maxRetries: 3)

        // First retry: 1 second
        let delay0 = policy.delay(for: 0)
        #expect(delay0 >= .milliseconds(900) && delay0 <= .milliseconds(1100))

        // Second retry: 2 seconds
        let delay1 = policy.delay(for: 1)
        #expect(delay1 >= .milliseconds(1900) && delay1 <= .milliseconds(2100))

        // Third retry: 4 seconds
        let delay2 = policy.delay(for: 2)
        #expect(delay2 >= .milliseconds(3900) && delay2 <= .milliseconds(4100))
    }

    @Test("Retry policy none has zero retries")
    func retryPolicyNone() {
        let policy = RetryPolicy.none
        #expect(policy.maxRetries == 0)
    }

    @Test("Retry policy max delay cap")
    func retryPolicyMaxDelay() {
        let policy = RetryPolicy(
            maxRetries: 10,
            baseDelay: .seconds(1),
            maxDelay: .seconds(5),
            useExponentialBackoff: true
        )

        // Even after many retries, delay should not exceed maxDelay
        let delay = policy.delay(for: 10)
        #expect(delay <= .seconds(5))
    }

    // MARK: - WebClientConfiguration Tests

    @Test("Configuration initialization")
    func configurationInit() {
        let url = URL(string: "https://api.example.com")!
        let config = WebClientConfiguration(
            baseURL: url,
            timeout: .seconds(15),
            retryPolicy: .none
        )

        #expect(config.baseURL == url)
        #expect(config.timeout == .seconds(15))
        #expect(config.retryPolicy.maxRetries == 0)
    }

    @Test("Configuration default values")
    func configurationDefaults() {
        let url = URL(string: "https://api.example.com")!
        let config = WebClientConfiguration(baseURL: url)

        #expect(config.timeout == .seconds(30))
        #expect(config.resourceTimeout == .seconds(60))
        #expect(config.retryPolicy.maxRetries == 3)
        #expect(config.defaultHeaders["Accept"] == "application/json")
        #expect(config.requestInterceptors.isEmpty)
        #expect(config.responseInterceptors.isEmpty)
    }

    @Test("Configuration with interceptors")
    func configurationWithInterceptors() {
        let url = URL(string: "https://api.example.com")!

        struct TestRequestInterceptor: RequestInterceptor {
            func intercept(_ request: URLRequest, context _: RequestContext) async throws -> URLRequest {
                request
            }
        }

        struct TestResponseInterceptor: ResponseInterceptor {
            func intercept(_ data: Data, response: HTTPURLResponse, context _: ResponseContext) async throws -> (Data, HTTPURLResponse) {
                (data, response)
            }
        }

        let config = WebClientConfiguration(
            baseURL: url,
            requestInterceptors: [TestRequestInterceptor()],
            responseInterceptors: [TestResponseInterceptor()]
        )

        #expect(config.requestInterceptors.count == 1)
        #expect(config.responseInterceptors.count == 1)
    }

    // MARK: - WebClientError Tests

    @Test("WebClientError offline detection")
    func errorOfflineDetection() {
        let offlineError = WebClientError<Void>.offline
        #expect(offlineError.isOfflineError == true)

        let timeoutError = WebClientError<Void>.timeout
        #expect(timeoutError.isOfflineError == false)

        let serverError = WebClientError<Void>.serverError(statusCode: 500, failure: nil, data: nil)
        #expect(serverError.isOfflineError == false)
    }

    @Test("WebClientError retryable detection")
    func errorRetryableDetection() {
        let timeoutError = WebClientError<Void>.timeout
        #expect(timeoutError.isRetryable == true)

        let serverError500 = WebClientError<Void>.serverError(statusCode: 500, failure: nil, data: nil)
        #expect(serverError500.isRetryable == true)

        let serverError429 = WebClientError<Void>.serverError(statusCode: 429, failure: nil, data: nil)
        #expect(serverError429.isRetryable == true)

        let serverError404 = WebClientError<Void>.serverError(statusCode: 404, failure: nil, data: nil)
        #expect(serverError404.isRetryable == false)

        let cancelledError = WebClientError<Void>.cancelled
        #expect(cancelledError.isRetryable == false)
    }

    @Test("WebClientError status code extraction")
    func errorStatusCode() {
        let serverError = WebClientError<String>.serverError(statusCode: 404, failure: "Not found", data: nil)
        #expect(serverError.statusCode == 404)
        #expect(serverError.failure == "Not found")

        let timeoutError = WebClientError<String>.timeout
        #expect(timeoutError.statusCode == nil)
        #expect(timeoutError.failure == nil)
    }

    @Test("WebClientError from URLError")
    func errorFromURLError() {
        let cancelled = WebClientError<Void>.from(urlError: URLError(.cancelled))
        if case .cancelled = cancelled {
            // Expected
        } else {
            Issue.record("Expected cancelled error")
        }

        let timeout = WebClientError<Void>.from(urlError: URLError(.timedOut))
        if case .timeout = timeout {
            // Expected
        } else {
            Issue.record("Expected timeout error")
        }

        let offline = WebClientError<Void>.from(urlError: URLError(.notConnectedToInternet))
        if case .offline = offline {
            // Expected
        } else {
            Issue.record("Expected offline error")
        }
    }

    // MARK: - HTTPMethod Tests

    @Test("HTTP method raw values")
    func httpMethodRawValues() {
        #expect(HTTPMethod.get.rawValue == "GET")
        #expect(HTTPMethod.post.rawValue == "POST")
        #expect(HTTPMethod.put.rawValue == "PUT")
        #expect(HTTPMethod.patch.rawValue == "PATCH")
        #expect(HTTPMethod.delete.rawValue == "DELETE")
    }

    // MARK: - RequestProviding Tests

    @Test("Request building with query items")
    func requestBuildingWithQueryItems() {
        struct TestEndpoint: RequestProviding {
            var path: String { "/test" }
            var queryItems: [URLQueryItem]? {
                [URLQueryItem(name: "foo", value: "bar")]
            }
        }

        let baseURL = URL(string: "https://api.example.com")!
        let endpoint = TestEndpoint()
        let request = endpoint.urlRequest(relativeTo: baseURL)

        #expect(request != nil)
        #expect(request?.url?.absoluteString == "https://api.example.com/test?foo=bar")
        #expect(request?.httpMethod == "GET")
    }

    @Test("Request building with headers")
    func requestBuildingWithHeaders() {
        struct TestEndpoint: RequestProviding {
            var path: String { "/test" }
            var headers: [String: String]? {
                ["X-Custom": "value"]
            }
        }

        let baseURL = URL(string: "https://api.example.com")!
        let endpoint = TestEndpoint()
        let request = endpoint.urlRequest(
            relativeTo: baseURL,
            defaultHeaders: ["Accept": "application/json"]
        )

        #expect(request != nil)
        #expect(request?.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request?.value(forHTTPHeaderField: "X-Custom") == "value")
    }

    @Test("Request building with POST body")
    func requestBuildingWithBody() {
        struct RequestBody: Encodable, Sendable {
            let name: String
        }

        struct TestEndpoint: RequestProviding {
            var method: HTTPMethod { .post }
            var path: String { "/test" }
            var body: (any Encodable & Sendable)? { RequestBody(name: "test") }
        }

        let baseURL = URL(string: "https://api.example.com")!
        let endpoint = TestEndpoint()
        let request = endpoint.urlRequest(relativeTo: baseURL)

        #expect(request != nil)
        #expect(request?.httpMethod == "POST")
        #expect(request?.httpBody != nil)
        #expect(request?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    // MARK: - WebClient Tests

    @Test("WebClient initialization")
    func webClientInit() async {
        let config = WebClientConfiguration(
            baseURL: URL(string: "https://api.example.com")!
        )
        let client = WebClient(configuration: config)

        let clientConfig = await client.configuration
        #expect(clientConfig.baseURL.absoluteString == "https://api.example.com")
    }

    // MARK: - MockWebClient Tests

    @Test("MockWebClient stub response")
    func mockWebClientStubResponse() async throws {
        struct TestEndpoint: Endpoint {
            typealias Success = String
            typealias Failure = Void

            var path: String { "/test" }
            var decoder: any Decoding { JSONDecoder() }
        }

        let mockClient = MockWebClient()
        await mockClient.stub(TestEndpoint.self, response: "Hello, World!")

        let result = try await mockClient.invoke(TestEndpoint())
        #expect(result == "Hello, World!")
    }

    @Test("MockWebClient stub error")
    func mockWebClientStubError() async throws {
        struct TestEndpoint: Endpoint {
            typealias Success = String
            typealias Failure = String

            var path: String { "/test" }
            var decoder: any Decoding { JSONDecoder() }
        }

        let mockClient = MockWebClient()
        let expectedError = WebClientError<String>.serverError(
            statusCode: 404,
            failure: "Not found",
            data: nil
        )
        await mockClient.stubError(TestEndpoint.self, error: expectedError)

        do {
            _ = try await mockClient.invoke(TestEndpoint())
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected
        }
    }

    @Test("MockWebClient call counting")
    func mockWebClientCallCounting() async throws {
        struct TestEndpoint: Endpoint {
            typealias Success = String
            typealias Failure = Void

            var path: String { "/test" }
            var decoder: any Decoding { JSONDecoder() }
        }

        let mockClient = MockWebClient()
        await mockClient.stub(TestEndpoint.self, response: "OK")

        // Initially not called
        var wasCalled = await mockClient.wasCalled(TestEndpoint.self)
        #expect(wasCalled == false)

        // Call once
        _ = try await mockClient.invoke(TestEndpoint())
        var callCount = await mockClient.callCount(for: TestEndpoint.self)
        #expect(callCount == 1)

        wasCalled = await mockClient.wasCalled(TestEndpoint.self)
        #expect(wasCalled == true)

        // Call again
        _ = try await mockClient.invoke(TestEndpoint())
        callCount = await mockClient.callCount(for: TestEndpoint.self)
        #expect(callCount == 2)
    }

    @Test("MockWebClient reset")
    func mockWebClientReset() async throws {
        struct TestEndpoint: Endpoint {
            typealias Success = String
            typealias Failure = Void

            var path: String { "/test" }
            var decoder: any Decoding { JSONDecoder() }
        }

        let mockClient = MockWebClient()
        await mockClient.stub(TestEndpoint.self, response: "OK")
        _ = try await mockClient.invoke(TestEndpoint())

        var callCount = await mockClient.callCount(for: TestEndpoint.self)
        #expect(callCount == 1)

        await mockClient.reset()

        callCount = await mockClient.callCount(for: TestEndpoint.self)
        #expect(callCount == 0)
    }

    // MARK: - Interceptor Tests

    @Test("Request context creation")
    func requestContextCreation() {
        let context = RequestContext(
            path: "/users/123",
            method: .get,
            attemptNumber: 0
        )

        #expect(context.path == "/users/123")
        #expect(context.method == .get)
        #expect(context.attemptNumber == 0)
    }

    @Test("Response context creation")
    func responseContextCreation() {
        let context = ResponseContext(
            path: "/users/123",
            method: .post,
            attemptNumber: 1,
            duration: .seconds(2)
        )

        #expect(context.path == "/users/123")
        #expect(context.method == .post)
        #expect(context.attemptNumber == 1)
        #expect(context.duration == .seconds(2))
    }

    @Test("RetryRequestError creation")
    func retryRequestErrorCreation() {
        let error = RetryRequestError()
        #expect(error is Error)
    }

    // MARK: - Per-Endpoint Retry Policy Override Tests

    @Test("Endpoint retry policy override")
    func endpointRetryPolicyOverride() {
        struct NoRetryEndpoint: RequestProviding {
            var path: String { "/test" }
            var retryPolicy: RetryPolicy? { RetryPolicy.none }
        }

        struct CustomRetryEndpoint: RequestProviding {
            var path: String { "/test" }
            var retryPolicy: RetryPolicy? { RetryPolicy(maxRetries: 5) }
        }

        struct DefaultRetryEndpoint: RequestProviding {
            var path: String { "/test" }
        }

        let noRetryEndpoint = NoRetryEndpoint()
        let customRetryEndpoint = CustomRetryEndpoint()
        let defaultEndpoint = DefaultRetryEndpoint()

        #expect(noRetryEndpoint.retryPolicy?.maxRetries == 0)
        #expect(customRetryEndpoint.retryPolicy?.maxRetries == 5)
        #expect(defaultEndpoint.retryPolicy == nil)
    }

    // MARK: - Request ID Tests

    @Test("Configuration with request ID generator")
    func configurationWithRequestIdGenerator() {
        let url = URL(string: "https://api.example.com")!
        let config = WebClientConfiguration(
            baseURL: url,
            requestIdGenerator: WebClientConfiguration.uuidRequestIdGenerator
        )

        #expect(config.requestIdGenerator != nil)
        #expect(config.requestIdHeaderName == "X-Request-ID")

        // Generate a request ID and verify it's a valid UUID
        let requestId = config.requestIdGenerator!()
        #expect(UUID(uuidString: requestId) != nil)
    }

    @Test("Configuration with custom request ID header name")
    func configurationWithCustomRequestIdHeaderName() {
        let url = URL(string: "https://api.example.com")!
        let config = WebClientConfiguration(
            baseURL: url,
            requestIdGenerator: { "test-id-123" },
            requestIdHeaderName: "X-Correlation-ID"
        )

        #expect(config.requestIdHeaderName == "X-Correlation-ID")
        #expect(config.requestIdGenerator!() == "test-id-123")
    }

    @Test("Request context with request ID")
    func requestContextWithRequestId() {
        let context = RequestContext(
            path: "/users/123",
            method: .get,
            attemptNumber: 0,
            requestId: "req-abc-123"
        )

        #expect(context.requestId == "req-abc-123")
    }

    @Test("Response context with request ID")
    func responseContextWithRequestId() {
        let context = ResponseContext(
            path: "/users/123",
            method: .post,
            attemptNumber: 1,
            duration: .seconds(2),
            requestId: "req-xyz-789"
        )

        #expect(context.requestId == "req-xyz-789")
    }

    // MARK: - Server-Sent Event Tests

    @Test("ServerSentEvent creation")
    func serverSentEventCreation() {
        let event = ServerSentEvent(
            event: "message",
            data: "Hello, World!",
            id: "123",
            retry: 5000
        )

        #expect(event.event == "message")
        #expect(event.data == "Hello, World!")
        #expect(event.id == "123")
        #expect(event.retry == 5000)
    }

    @Test("ServerSentEvent with minimal data")
    func serverSentEventMinimal() {
        let event = ServerSentEvent(data: "Just data")

        #expect(event.event == nil)
        #expect(event.data == "Just data")
        #expect(event.id == nil)
        #expect(event.retry == nil)
    }

    @Test("ServerSentEvent equality")
    func serverSentEventEquality() {
        let event1 = ServerSentEvent(event: "update", data: "data1", id: "1", retry: nil)
        let event2 = ServerSentEvent(event: "update", data: "data1", id: "1", retry: nil)
        let event3 = ServerSentEvent(event: "update", data: "data2", id: "1", retry: nil)

        #expect(event1 == event2)
        #expect(event1 != event3)
    }

    // MARK: - Streaming Endpoint Tests

    @Test("StreamingEndpoint default implementations")
    func streamingEndpointDefaults() {
        struct TestStreamingEndpoint: StreamingEndpoint {
            typealias Element = String
            typealias Failure = Void

            var path: String { "/stream" }

            func decodeElement(from line: String) throws -> String? {
                line.isEmpty ? nil : line
            }
        }

        let endpoint = TestStreamingEndpoint()
        #expect(endpoint.path == "/stream")
        #expect(endpoint.method == .get)
        #expect(endpoint.decodeFailure(from: Data()) == nil)
    }

    @Test("JSONLinesStreamingEndpoint decoding")
    func jsonLinesStreamingEndpointDecoding() throws {
        struct LogEntry: Codable, Sendable, Equatable {
            let level: String
            let message: String
        }

        struct LogStreamEndpoint: JSONLinesStreamingEndpoint {
            typealias Element = LogEntry
            typealias Failure = Void

            var path: String { "/logs" }
        }

        let endpoint = LogStreamEndpoint()

        // Test decoding a valid JSON line
        let line = "{\"level\":\"info\",\"message\":\"Hello\"}"
        let element = try endpoint.decodeElement(from: line)
        #expect(element == LogEntry(level: "info", message: "Hello"))

        // Test skipping empty lines
        let emptyElement = try endpoint.decodeElement(from: "")
        #expect(emptyElement == nil)

        let whitespaceElement = try endpoint.decodeElement(from: "   ")
        #expect(whitespaceElement == nil)
    }

    // MARK: - PathComponent Tests

    @Test("PathComponent literal")
    func pathComponentLiteral() {
        let component = PathComponent.literal("users")
        #expect(component.stringValue == "users")
        #expect(component.isIncluded == true)
    }

    @Test("PathComponent value")
    func pathComponentValue() {
        // Values are stored as-is; URL encoding is handled by URLComponents
        let simple = PathComponent.value("john")
        #expect(simple.stringValue == "john")

        let withSpace = PathComponent.value("john doe")
        #expect(withSpace.stringValue == "john doe")

        let withSpecialChars = PathComponent.value("test/path")
        #expect(withSpecialChars.stringValue == "test/path")
    }

    @Test("PathComponent int")
    func pathComponentInt() {
        let component = PathComponent.int(123)
        #expect(component.stringValue == "123")
        #expect(component.isIncluded == true)
    }

    @Test("PathComponent optional")
    func pathComponentOptional() {
        let withValue = PathComponent.optional("present")
        #expect(withValue.stringValue == "present")
        #expect(withValue.isIncluded == true)

        let nilValue = PathComponent.optional(nil)
        #expect(nilValue.stringValue == "")
        #expect(nilValue.isIncluded == false)
    }

    @Test("PathComponent string literal")
    func pathComponentStringLiteral() {
        let component: PathComponent = "users"
        #expect(component == .literal("users"))
    }

    @Test("PathComponent integer literal")
    func pathComponentIntegerLiteral() {
        let component: PathComponent = 42
        #expect(component == .int(42))
    }

    @Test("PathComponent array buildPath")
    func pathComponentBuildPath() {
        let components: [PathComponent] = [
            .literal("api"),
            .literal("v1"),
            .literal("users"),
        ]
        #expect(components.buildPath() == "/api/v1/users")
    }

    @Test("PathComponent buildPath with values")
    func pathComponentBuildPathWithValues() {
        let userId = "123"
        let postId = "456"

        let components: [PathComponent] = [
            "users",
            .value(userId),
            "posts",
            .value(postId),
        ]
        #expect(components.buildPath() == "/users/123/posts/456")
    }

    @Test("PathComponent buildPath with optionals")
    func pathComponentBuildPathWithOptionals() {
        let category: String? = "tech"
        let subcategory: String? = nil

        let components: [PathComponent] = [
            "articles",
            .optional(category),
            .optional(subcategory),
            "list",
        ]
        #expect(components.buildPath() == "/articles/tech/list")
    }

    @Test("PathComponent buildPath empty")
    func pathComponentBuildPathEmpty() {
        let components: [PathComponent] = []
        #expect(components.buildPath() == "/")
    }

    @Test("PathComponent equality")
    func pathComponentEquality() {
        #expect(PathComponent.literal("test") == PathComponent.literal("test"))
        #expect(PathComponent.literal("test") != PathComponent.literal("other"))
        #expect(PathComponent.value("123") == PathComponent.value("123"))
        #expect(PathComponent.int(42) == PathComponent.int(42))
        #expect(PathComponent.optional("x") == PathComponent.optional("x"))
        #expect(PathComponent.optional(nil) == PathComponent.optional(nil))
    }

    // MARK: - RequestProviding PathComponents Tests

    @Test("RequestProviding with pathComponents")
    func requestProvidingWithPathComponents() {
        struct UserPostEndpoint: RequestProviding {
            let userId: String
            let postId: String

            var path: String { "" } // Required but unused when pathComponents is set

            var pathComponents: [PathComponent]? {
                ["users", .value(userId), "posts", .value(postId)]
            }
        }

        let endpoint = UserPostEndpoint(userId: "abc", postId: "xyz")
        #expect(endpoint.resolvedPath == "/users/abc/posts/xyz")

        let baseURL = URL(string: "https://api.example.com")!
        let request = endpoint.urlRequest(relativeTo: baseURL)
        #expect(request?.url?.path == "/users/abc/posts/xyz")
    }

    @Test("RequestProviding falls back to path when pathComponents is nil")
    func requestProvidingFallbackToPath() {
        struct SimpleEndpoint: RequestProviding {
            var path: String { "/simple/path" }
        }

        let endpoint = SimpleEndpoint()
        #expect(endpoint.pathComponents == nil)
        #expect(endpoint.resolvedPath == "/simple/path")
    }

    @Test("RequestProviding with URL encoding in pathComponents")
    func requestProvidingPathComponentsURLEncoding() {
        struct SearchEndpoint: RequestProviding {
            let query: String

            var path: String { "" }

            var pathComponents: [PathComponent]? {
                ["search", .value(query)]
            }
        }

        let endpoint = SearchEndpoint(query: "hello world")
        // resolvedPath returns the unencoded path
        #expect(endpoint.resolvedPath == "/search/hello world")

        // URLComponents handles the encoding when building the URL
        let baseURL = URL(string: "https://api.example.com")!
        let request = endpoint.urlRequest(relativeTo: baseURL)
        #expect(request?.url?.absoluteString == "https://api.example.com/search/hello%20world")
    }

    // MARK: - Rate Limiter Tests

    @Test("RateLimiter token bucket initialization")
    func rateLimiterInit() async {
        let limiter = RateLimiter(tokensPerSecond: 10, maxTokens: 20)

        let currentTokens = await limiter.currentTokens
        #expect(currentTokens == 20)
    }

    @Test("RateLimiter requests per minute initialization")
    func rateLimiterRequestsPerMinute() async {
        let limiter = RateLimiter(requestsPerMinute: 60, burstSize: 10)

        let currentTokens = await limiter.currentTokens
        #expect(currentTokens == 10)
    }

    @Test("RateLimiter tryAcquire consumes tokens")
    func rateLimiterTryAcquire() async {
        let limiter = RateLimiter(tokensPerSecond: 10, maxTokens: 5)

        // Should succeed - we have 5 tokens
        let success1 = await limiter.tryAcquire()
        #expect(success1 == true)

        let success2 = await limiter.tryAcquire()
        #expect(success2 == true)

        // After consuming some tokens, count should decrease
        let remaining = await limiter.currentTokens
        #expect(remaining < 5)
    }

    @Test("RateLimiter tryAcquire fails when no tokens")
    func rateLimiterTryAcquireNoTokens() async {
        let limiter = RateLimiter(tokensPerSecond: 1, maxTokens: 2)

        // Consume all tokens
        _ = await limiter.tryAcquire()
        _ = await limiter.tryAcquire()

        // Should fail - no tokens left
        let success = await limiter.tryAcquire()
        #expect(success == false)
    }

    @Test("RateLimiter acquire waits for tokens")
    func rateLimiterAcquireWaits() async throws {
        let limiter = RateLimiter(tokensPerSecond: 100, maxTokens: 1)

        // Consume the only token
        _ = await limiter.tryAcquire()

        // This should wait and then succeed
        let startTime = ContinuousClock.now
        try await limiter.acquire()
        let elapsed = ContinuousClock.now - startTime

        // Should have waited at least a few milliseconds
        #expect(elapsed >= .milliseconds(5))
    }

    @Test("RateLimiter estimated wait time")
    func rateLimiterEstimatedWaitTime() async {
        let limiter = RateLimiter(tokensPerSecond: 10, maxTokens: 1)

        // Initially should be zero (we have a token)
        let initialWait = await limiter.estimatedWaitTime()
        #expect(initialWait == .zero)

        // Consume the token
        _ = await limiter.tryAcquire()

        // Now should have a wait time
        let waitTime = await limiter.estimatedWaitTime()
        #expect(waitTime > .zero)
    }

    @Test("RateLimiter reset")
    func rateLimiterReset() async {
        let limiter = RateLimiter(tokensPerSecond: 10, maxTokens: 5)

        // Consume all tokens
        for _ in 0 ..< 5 {
            _ = await limiter.tryAcquire()
        }

        let emptyTokens = await limiter.currentTokens
        #expect(emptyTokens < 1)

        // Reset
        await limiter.reset()

        let fullTokens = await limiter.currentTokens
        #expect(fullTokens == 5)
    }

    @Test("ScopedRateLimiter path matching")
    func scopedRateLimiterPathMatching() async throws {
        let searchLimiter = RateLimiter(tokensPerSecond: 1, maxTokens: 1)
        let defaultLimiter = RateLimiter(tokensPerSecond: 100, maxTokens: 100)

        let scopedLimiter = ScopedRateLimiter(
            defaultLimiter: defaultLimiter,
            scopedLimiters: ["/api/search": searchLimiter]
        )

        // Should use search limiter (strict)
        let searchSuccess1 = await scopedLimiter.tryAcquire(for: "/api/search")
        #expect(searchSuccess1 == true)

        let searchSuccess2 = await scopedLimiter.tryAcquire(for: "/api/search")
        #expect(searchSuccess2 == false) // Rate limited

        // Should use default limiter (more lenient)
        let otherSuccess = await scopedLimiter.tryAcquire(for: "/api/users")
        #expect(otherSuccess == true)
    }

    // MARK: - Rate Limit Interceptor Tests

    @Test("RateLimitInterceptor initialization")
    func rateLimitInterceptorInit() {
        let limiter = RateLimiter(requestsPerMinute: 60)
        let interceptor = RateLimitInterceptor(rateLimiter: limiter)

        #expect(interceptor is RequestInterceptor)
    }

    @Test("RateLimitInterceptor with scoped limiter")
    func rateLimitInterceptorScoped() {
        let scopedLimiter = ScopedRateLimiter(
            defaultLimiter: RateLimiter(requestsPerMinute: 60),
            scopedLimiters: ["/search": RateLimiter(requestsPerMinute: 10)]
        )
        let interceptor = RateLimitInterceptor(scopedRateLimiter: scopedLimiter)

        #expect(interceptor is RequestInterceptor)
    }

    @Test("RateLimitResponseInterceptor initialization")
    func rateLimitResponseInterceptorInit() {
        let interceptor = RateLimitResponseInterceptor(maxRetryAfter: .seconds(30))
        #expect(interceptor is ResponseInterceptor)
    }

    @Test("RateLimitedError creation")
    func rateLimitedErrorCreation() {
        let error = RateLimitedError(
            retryAfter: .seconds(60),
            remaining: 0,
            resetTime: Date()
        )

        #expect(error.retryAfter == .seconds(60))
        #expect(error.remaining == 0)
        #expect(error.resetTime != nil)
    }

    // MARK: - Certificate Pinning Tests

    @Test("CertificatePin host matching exact")
    func certificatePinHostMatchingExact() {
        let pin = CertificatePin(host: "api.example.com", publicKeyHashes: ["hash1"])

        #expect(pin.matches(host: "api.example.com") == true)
        #expect(pin.matches(host: "API.EXAMPLE.COM") == true) // Case insensitive
        #expect(pin.matches(host: "other.example.com") == false)
        #expect(pin.matches(host: "example.com") == false)
    }

    @Test("CertificatePin host matching wildcard")
    func certificatePinHostMatchingWildcard() {
        let pin = CertificatePin(host: "*.example.com", publicKeyHashes: ["hash1"])

        #expect(pin.matches(host: "api.example.com") == true)
        #expect(pin.matches(host: "www.example.com") == true)
        #expect(pin.matches(host: "example.com") == false)
        #expect(pin.matches(host: "sub.api.example.com") == false) // No nested subdomains
    }

    @Test("CertificatePin host matching with subdomains")
    func certificatePinHostMatchingSubdomains() {
        let pin = CertificatePin(
            host: "example.com",
            publicKeyHashes: ["hash1"],
            includeSubdomains: true
        )

        #expect(pin.matches(host: "example.com") == true)
        #expect(pin.matches(host: "api.example.com") == true)
        #expect(pin.matches(host: "sub.api.example.com") == true)
        #expect(pin.matches(host: "other.com") == false)
    }

    @Test("CertificatePinning configuration")
    func certificatePinningConfiguration() {
        let pinning = CertificatePinning(
            pins: [
                CertificatePin(host: "api.example.com", publicKeyHashes: ["hash1", "hash2"]),
                CertificatePin(host: "cdn.example.com", certificateHashes: ["cert1"]),
            ],
            allowUnpinnedHosts: false,
            validateChain: true
        )

        #expect(pinning.pins.count == 2)
        #expect(pinning.allowUnpinnedHosts == false)
        #expect(pinning.validateChain == true)
    }

    @Test("CertificatePinning pin lookup")
    func certificatePinningPinLookup() {
        let pinning = CertificatePinning(pins: [
            CertificatePin(host: "api.example.com", publicKeyHashes: ["hash1"]),
            CertificatePin(host: "cdn.example.com", publicKeyHashes: ["hash2"]),
        ])

        let apiPin = pinning.pin(for: "api.example.com")
        #expect(apiPin != nil)
        #expect(apiPin?.publicKeyHashes == ["hash1"])

        let cdnPin = pinning.pin(for: "cdn.example.com")
        #expect(cdnPin != nil)
        #expect(cdnPin?.publicKeyHashes == ["hash2"])

        let unknownPin = pinning.pin(for: "unknown.example.com")
        #expect(unknownPin == nil)
    }

    @Test("CertificatePinning defaults")
    func certificatePinningDefaults() {
        let pinning = CertificatePinning(pins: [])

        #expect(pinning.allowUnpinnedHosts == true)
        #expect(pinning.validateChain == false)
    }

    @Test("CertificatePinningError creation")
    func certificatePinningErrorCreation() {
        let error = CertificatePinningError(
            host: "api.example.com",
            reason: "Certificate mismatch"
        )

        #expect(error.host == "api.example.com")
        #expect(error.reason == "Certificate mismatch")
        #expect(error.errorDescription?.contains("api.example.com") == true)
    }

    @Test("PinningSessionDelegate initialization")
    func pinningSessionDelegateInit() {
        let pinning = CertificatePinning(pins: [
            CertificatePin(host: "api.example.com", publicKeyHashes: ["hash1"]),
        ])

        let delegate = PinningSessionDelegate(pinning: pinning) { _, _ in
            // Callback for pinning failures
        }

        // Verify delegate is created successfully
        #expect(delegate is URLSessionDelegate)
    }

    @Test("PinningTaskDelegate initialization")
    func pinningTaskDelegateInit() {
        let pinning = CertificatePinning(pins: [])
        let delegate = PinningTaskDelegate(pinning: pinning)

        #expect(delegate is URLSessionTaskDelegate)
    }

    // MARK: - WebClient with Certificate Pinning Tests

    @Test("WebClient initialization with certificate pinning")
    func webClientWithCertificatePinning() async {
        let config = WebClientConfiguration(
            baseURL: URL(string: "https://api.example.com")!
        )

        let pinning = CertificatePinning(pins: [
            CertificatePin(
                host: "api.example.com",
                publicKeyHashes: ["AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="]
            ),
        ])

        let client = WebClient(
            configuration: config,
            certificatePinning: pinning
        ) { _, _ in
            // Callback for pinning failures
        }

        let clientConfig = await client.configuration
        #expect(clientConfig.baseURL.absoluteString == "https://api.example.com")
    }

    @Test("CertificatePin public key hash initializer")
    func certificatePinPublicKeyHashInit() {
        let pin = CertificatePin(
            host: "example.com",
            publicKeyHashes: ["hash1", "hash2"],
            includeSubdomains: true
        )

        #expect(pin.hostPattern == "example.com")
        #expect(pin.publicKeyHashes == ["hash1", "hash2"])
        #expect(pin.certificateHashes.isEmpty)
        #expect(pin.includeSubdomains == true)
    }

    @Test("CertificatePin certificate hash initializer")
    func certificatePinCertificateHashInit() {
        let pin = CertificatePin(
            host: "example.com",
            certificateHashes: ["cert1", "cert2"],
            includeSubdomains: false
        )

        #expect(pin.hostPattern == "example.com")
        #expect(pin.publicKeyHashes.isEmpty)
        #expect(pin.certificateHashes == ["cert1", "cert2"])
        #expect(pin.includeSubdomains == false)
    }

    @Test("CertificatePin combined initializer")
    func certificatePinCombinedInit() {
        let pin = CertificatePin(
            host: "example.com",
            publicKeyHashes: ["key1"],
            certificateHashes: ["cert1"]
        )

        #expect(pin.publicKeyHashes == ["key1"])
        #expect(pin.certificateHashes == ["cert1"])
    }
}
