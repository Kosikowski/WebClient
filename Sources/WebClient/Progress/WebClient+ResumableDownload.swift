import Foundation

// MARK: - WebClient Resumable Download Extension

public extension WebClient {
    /// Starts a resumable download that can be paused and resumed.
    ///
    /// This method creates a download that uses `URLSessionDownloadTask` under the hood,
    /// providing native support for pause/resume with resume data.
    ///
    /// ## Example
    /// ```swift
    /// let download = try await client.resumableDownload(
    ///     MyDownloadEndpoint(fileId: "123"),
    ///     to: destinationURL
    /// )
    ///
    /// // Monitor progress
    /// Task {
    ///     for await progress in download.progressUpdates {
    ///         print("\(progress.percentageString ?? "?")")
    ///     }
    /// }
    ///
    /// // Await result
    /// let url = try await download.result
    /// ```
    ///
    /// ## Pause and Resume
    /// ```swift
    /// // Pause the download
    /// let resumeData = await download.pause()
    ///
    /// // Resume later with the data
    /// let newDownload = try await client.resumableDownload(
    ///     MyDownloadEndpoint(fileId: "123"),
    ///     to: destinationURL,
    ///     resumeData: resumeData
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - endpoint: The download endpoint.
    ///   - destination: The URL where the file should be saved.
    ///   - resumeData: Optional resume data from a previously paused download.
    /// - Returns: A `ResumableDownload` actor that can be used to monitor progress and control the download.
    /// - Throws: `WebClientError<E.Failure>` if the download cannot be started.
    func resumableDownload<E: DownloadEndpoint>(
        _ endpoint: E,
        to destination: URL,
        resumeData: Data? = nil
    ) async throws -> ResumableDownload<E.Failure> where E.Failure: Error {
        try await startResumableDownload(endpoint, to: destination, resumeData: resumeData)
    }

    // MARK: - Private Implementation

    private func startResumableDownload<E: DownloadEndpoint>(
        _ endpoint: E,
        to destination: URL,
        resumeData: Data?
    ) async throws -> ResumableDownload<E.Failure> where E.Failure: Error {
        try Task.checkCancellation()

        // Create the ResumableDownload actor
        let download = ResumableDownload<E.Failure>(destination: destination)

        // Build the request (only needed if not resuming)
        var request: URLRequest?
        if resumeData == nil {
            guard var req = endpoint.urlRequest(
                relativeTo: configuration.baseURL,
                defaultHeaders: configuration.defaultHeaders,
                defaultEncoder: configuration.defaultEncoder
            ) else {
                throw WebClientError<E.Failure>.invalidRequest("Failed to build URL request")
            }

            // Generate request ID if configured
            if let requestId = configuration.requestIdGenerator?() {
                req.setValue(requestId, forHTTPHeaderField: configuration.requestIdHeaderName)
            }

            // Apply request interceptors
            let requestContext = RequestContext(
                path: endpoint.path,
                method: endpoint.method,
                attemptNumber: 0,
                requestId: nil
            )

            for interceptor in configuration.requestInterceptors {
                req = try await interceptor.intercept(req, context: requestContext)
            }

            request = req
        }

        // Create a dedicated session with our delegate
        // We need to use a separate session because URLSessionDownloadDelegate
        // requires being the session's delegate
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = Double(configuration.timeout.components.seconds)
        sessionConfig.timeoutIntervalForResource = Double(configuration.resourceTimeout.components.seconds)

        // Use a continuation to bridge the delegate callback to async/await
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ResumableDownload<E.Failure>, any Error>) in
            // Create delegate with completion handler
            let delegate = ResumableDownloadDelegate<E.Failure>(
                download: download,
                destination: destination,
                endpoint: endpoint,
                completion: { _ in
                    // Completion is handled by the delegate updating the download actor
                }
            )

            let downloadSession = URLSession(
                configuration: sessionConfig,
                delegate: delegate,
                delegateQueue: nil
            )

            // Create the download task
            let downloadTask: URLSessionDownloadTask
            if let resumeData {
                downloadTask = downloadSession.downloadTask(withResumeData: resumeData)
            } else if let request {
                downloadTask = downloadSession.downloadTask(with: request)
            } else {
                continuation.resume(throwing: WebClientError<E.Failure>.invalidRequest("No request or resume data"))
                return
            }

            // Store the task in the download actor
            Task {
                await download.setDownloadTask(downloadTask)
                downloadTask.resume()
                continuation.resume(returning: download)
            }
        }
    }
}
