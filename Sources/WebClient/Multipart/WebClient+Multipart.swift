import Foundation

// MARK: - WebClient Multipart Extension

public extension WebClient {
    /// Invokes a multipart form data endpoint and returns the success response.
    ///
    /// This method handles file uploads with multipart/form-data encoding.
    ///
    /// ## Example
    /// ```swift
    /// struct UploadDocumentEndpoint: MultipartEndpoint {
    ///     typealias Success = UploadResponse
    ///     typealias Failure = APIError
    ///
    ///     let documentData: Data
    ///     let fileName: String
    ///
    ///     var path: String { "/documents/upload" }
    ///     var decoder: any Decoding { JSONDecoder() }
    ///
    ///     var formData: MultipartFormData {
    ///         var form = MultipartFormData()
    ///         form.append(name: "file", data: documentData, filename: fileName, mimeType: "application/pdf")
    ///         return form
    ///     }
    /// }
    ///
    /// let response = try await client.invoke(UploadDocumentEndpoint(
    ///     documentData: pdfData,
    ///     fileName: "report.pdf"
    /// ))
    /// ```
    ///
    /// - Parameter endpoint: The multipart endpoint to invoke.
    /// - Returns: The decoded success value.
    /// - Throws: `WebClientError<E.Failure>` on failure.
    @discardableResult
    func invoke<E: MultipartEndpoint>(_ endpoint: E) async throws -> E.Success {
        try await performMultipartRequest(endpoint, attemptNumber: 0)
    }

    /// Invokes a multipart endpoint with typed throws.
    ///
    /// - Parameter endpoint: The multipart endpoint to invoke.
    /// - Returns: The decoded success value.
    /// - Throws: `WebClientError<E.Failure>` on failure.
    @discardableResult
    func invokeTyped<E: MultipartEndpoint>(
        _ endpoint: E
    ) async throws(WebClientError<E.Failure>) -> E.Success {
        do {
            return try await performMultipartRequest(endpoint, attemptNumber: 0)
        } catch let error as WebClientError<E.Failure> {
            throw error
        } catch {
            throw .networkError(underlying: error)
        }
    }

    /// Invokes a multipart endpoint and returns a Result.
    ///
    /// - Parameter endpoint: The multipart endpoint to invoke.
    /// - Returns: A Result containing either the success value or an error.
    func send<E: MultipartEndpoint>(_ endpoint: E) async -> Result<E.Success, WebClientError<E.Failure>> {
        do {
            let result = try await invoke(endpoint)
            return .success(result)
        } catch let error as WebClientError<E.Failure> {
            return .failure(error)
        } catch {
            return .failure(.networkError(underlying: error))
        }
    }

    /// Invokes a multipart endpoint with upload progress tracking.
    ///
    /// Note: Progress tracking for uploads requires streaming, which is handled
    /// at the URLSession level. This method provides a way to track when the
    /// upload is complete.
    ///
    /// - Parameters:
    ///   - endpoint: The multipart endpoint to invoke.
    ///   - progressDelegate: A delegate that receives progress updates.
    /// - Returns: The decoded success value.
    /// - Throws: `WebClientError<E.Failure>` on failure.
    @discardableResult
    func invoke<E: MultipartEndpoint>(
        _ endpoint: E,
        progressDelegate: (any ProgressDelegate)?
    ) async throws -> E.Success {
        let result = try await performMultipartRequest(endpoint, attemptNumber: 0)
        await progressDelegate?.didComplete()
        return result
    }

    // MARK: - Private Implementation

    private func performMultipartRequest<E: MultipartEndpoint>(
        _ endpoint: E,
        attemptNumber: Int
    ) async throws -> E.Success {
        try Task.checkCancellation()

        guard var request = endpoint.urlRequest(
            relativeTo: configuration.baseURL,
            defaultHeaders: configuration.defaultHeaders
        ) else {
            throw WebClientError<E.Failure>.invalidRequest("Failed to build URL request from endpoint")
        }

        // Generate request ID if configured
        let requestId = configuration.requestIdGenerator?()
        if let requestId {
            request.setValue(requestId, forHTTPHeaderField: configuration.requestIdHeaderName)
        }

        // Create request context for interceptors
        let requestContext = RequestContext(
            path: endpoint.path,
            method: .post,
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
            method: .post,
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
                failure = nil
            }

            throw WebClientError<E.Failure>.serverError(
                statusCode: httpResponse.statusCode,
                failure: failure,
                data: data
            )
        }
    }
}
