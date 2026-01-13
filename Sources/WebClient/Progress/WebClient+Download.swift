import Foundation

// MARK: - WebClient Download Extension

public extension WebClient {
    /// Downloads data from an endpoint with progress tracking.
    ///
    /// This method streams the response and reports progress as data is received.
    /// Use this for large file downloads where you want to show download progress.
    ///
    /// ## Example
    /// ```swift
    /// let result = try await client.download(
    ///     DownloadFileEndpoint(fileId: "123"),
    ///     progressDelegate: ProgressHandler { progress in
    ///         print("Downloaded: \(progress.bytesTransferredFormatted) / \(progress.totalBytesFormatted ?? "?")")
    ///     }
    /// )
    ///
    /// // Save to file
    /// try result.data.write(to: destinationURL)
    /// ```
    ///
    /// - Parameters:
    ///   - endpoint: The download endpoint.
    ///   - progressDelegate: A delegate that receives progress updates.
    /// - Returns: The download result containing the data and response.
    /// - Throws: `WebClientError<E.Failure>` on failure.
    func download<E: DownloadEndpoint>(
        _ endpoint: E,
        progressDelegate: (any ProgressDelegate)? = nil
    ) async throws -> DownloadResult {
        try await performDownload(endpoint, progressDelegate: progressDelegate)
    }

    /// Downloads data from an endpoint and saves it directly to a file.
    ///
    /// This method streams the response directly to disk, which is more
    /// memory-efficient for very large files.
    ///
    /// ## Example
    /// ```swift
    /// let result = try await client.download(
    ///     DownloadFileEndpoint(fileId: "123"),
    ///     to: destinationURL,
    ///     progressDelegate: ProgressHandler { progress in
    ///         print("Downloaded: \(progress.percentageString ?? "?")")
    ///     }
    /// )
    ///
    /// print("File saved to: \(result.fileURL)")
    /// ```
    ///
    /// - Parameters:
    ///   - endpoint: The download endpoint.
    ///   - fileURL: The URL where the file should be saved.
    ///   - progressDelegate: A delegate that receives progress updates.
    /// - Returns: The file download result.
    /// - Throws: `WebClientError<E.Failure>` on failure.
    func download<E: DownloadEndpoint>(
        _ endpoint: E,
        to fileURL: URL,
        progressDelegate: (any ProgressDelegate)? = nil
    ) async throws -> FileDownloadResult {
        try await performDownloadToFile(endpoint, to: fileURL, progressDelegate: progressDelegate)
    }

    /// Returns an async stream of data chunks for progressive downloads.
    ///
    /// Use this when you want to process data as it arrives, such as
    /// streaming to disk or processing in chunks.
    ///
    /// ## Example
    /// ```swift
    /// let stream = try await client.downloadStream(DownloadFileEndpoint(fileId: "123"))
    ///
    /// var totalBytes: Int64 = 0
    /// for try await chunk in stream.chunks {
    ///     // Write chunk to file or process it
    ///     totalBytes += Int64(chunk.count)
    /// }
    /// ```
    ///
    /// - Parameter endpoint: The download endpoint.
    /// - Returns: A download stream with data chunks.
    /// - Throws: `WebClientError<E.Failure>` on failure to start the download.
    func downloadStream<E: DownloadEndpoint>(
        _ endpoint: E
    ) async throws -> DownloadStream<E.Failure> {
        try await startDownloadStream(endpoint)
    }

    // MARK: - Private Implementation

    private func performDownload<E: DownloadEndpoint>(
        _ endpoint: E,
        progressDelegate: (any ProgressDelegate)?
    ) async throws -> DownloadResult {
        try Task.checkCancellation()

        guard var request = endpoint.urlRequest(
            relativeTo: configuration.baseURL,
            defaultHeaders: configuration.defaultHeaders,
            defaultEncoder: configuration.defaultEncoder
        ) else {
            throw WebClientError<E.Failure>.invalidRequest("Failed to build URL request")
        }

        // Generate request ID if configured
        if let requestId = configuration.requestIdGenerator?() {
            request.setValue(requestId, forHTTPHeaderField: configuration.requestIdHeaderName)
        }

        // Apply request interceptors
        let requestContext = RequestContext(
            path: endpoint.path,
            method: endpoint.method,
            attemptNumber: 0,
            requestId: nil
        )

        for interceptor in configuration.requestInterceptors {
            request = try await interceptor.intercept(request, context: requestContext)
        }

        // Start the download
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            await progressDelegate?.didFail(with: WebClientError<E.Failure>.unexpectedResponse)
            throw WebClientError<E.Failure>.unexpectedResponse
        }

        // Check for error status codes
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count > 1_000_000 { break }
            }

            let error = WebClientError<E.Failure>.serverError(
                statusCode: httpResponse.statusCode,
                failure: endpoint.decodeFailure(from: errorData),
                data: errorData
            )
            await progressDelegate?.didFail(with: error)
            throw error
        }

        // Get expected content length
        let expectedLength = httpResponse.expectedContentLength
        let totalBytes: Int64? = expectedLength > 0 ? expectedLength : nil

        // Stream the data and track progress
        var downloadedData = Data()
        var bytesReceived: Int64 = 0

        for try await byte in bytes {
            try Task.checkCancellation()

            downloadedData.append(byte)
            bytesReceived += 1

            // Report progress periodically (every ~4KB)
            if bytesReceived % 4096 == 0 {
                let progress = TransferProgress(
                    bytesTransferred: bytesReceived,
                    totalBytes: totalBytes
                )
                await progressDelegate?.didUpdateProgress(progress)
            }
        }

        // Final progress update
        let finalProgress = TransferProgress(
            bytesTransferred: bytesReceived,
            totalBytes: totalBytes
        )
        await progressDelegate?.didUpdateProgress(finalProgress)
        await progressDelegate?.didComplete()

        return DownloadResult(data: downloadedData, response: httpResponse)
    }

    private func performDownloadToFile<E: DownloadEndpoint>(
        _ endpoint: E,
        to fileURL: URL,
        progressDelegate: (any ProgressDelegate)?
    ) async throws -> FileDownloadResult {
        try Task.checkCancellation()

        guard var request = endpoint.urlRequest(
            relativeTo: configuration.baseURL,
            defaultHeaders: configuration.defaultHeaders,
            defaultEncoder: configuration.defaultEncoder
        ) else {
            throw WebClientError<E.Failure>.invalidRequest("Failed to build URL request")
        }

        // Generate request ID if configured
        if let requestId = configuration.requestIdGenerator?() {
            request.setValue(requestId, forHTTPHeaderField: configuration.requestIdHeaderName)
        }

        // Apply request interceptors
        let requestContext = RequestContext(
            path: endpoint.path,
            method: endpoint.method,
            attemptNumber: 0,
            requestId: nil
        )

        for interceptor in configuration.requestInterceptors {
            request = try await interceptor.intercept(request, context: requestContext)
        }

        // Start the download
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            await progressDelegate?.didFail(with: WebClientError<E.Failure>.unexpectedResponse)
            throw WebClientError<E.Failure>.unexpectedResponse
        }

        // Check for error status codes
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
                if errorData.count > 1_000_000 { break }
            }

            let error = WebClientError<E.Failure>.serverError(
                statusCode: httpResponse.statusCode,
                failure: endpoint.decodeFailure(from: errorData),
                data: errorData
            )
            await progressDelegate?.didFail(with: error)
            throw error
        }

        // Get expected content length
        let expectedLength = httpResponse.expectedContentLength
        let totalBytes: Int64? = expectedLength > 0 ? expectedLength : nil

        // Create file handle for writing
        let fileManager = FileManager.default

        // Ensure parent directory exists
        let parentDirectory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        // Create the file
        fileManager.createFile(atPath: fileURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: fileURL)

        defer {
            try? fileHandle.close()
        }

        // Stream to file and track progress
        var bytesReceived: Int64 = 0
        var buffer = Data()
        let bufferSize = 64 * 1024 // 64KB buffer

        do {
            for try await byte in bytes {
                try Task.checkCancellation()

                buffer.append(byte)
                bytesReceived += 1

                // Write buffer when full
                if buffer.count >= bufferSize {
                    try fileHandle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)

                    let progress = TransferProgress(
                        bytesTransferred: bytesReceived,
                        totalBytes: totalBytes
                    )
                    await progressDelegate?.didUpdateProgress(progress)
                }
            }

            // Write remaining buffer
            if !buffer.isEmpty {
                try fileHandle.write(contentsOf: buffer)
            }

            // Final progress update
            let finalProgress = TransferProgress(
                bytesTransferred: bytesReceived,
                totalBytes: totalBytes
            )
            await progressDelegate?.didUpdateProgress(finalProgress)
            await progressDelegate?.didComplete()

            return FileDownloadResult(
                fileURL: fileURL,
                response: httpResponse,
                bytesDownloaded: bytesReceived
            )
        } catch {
            // Clean up partial file on error
            try? fileManager.removeItem(at: fileURL)
            await progressDelegate?.didFail(with: error)
            throw error
        }
    }

    private func startDownloadStream<E: DownloadEndpoint>(
        _ endpoint: E
    ) async throws -> DownloadStream<E.Failure> {
        try Task.checkCancellation()

        guard var request = endpoint.urlRequest(
            relativeTo: configuration.baseURL,
            defaultHeaders: configuration.defaultHeaders,
            defaultEncoder: configuration.defaultEncoder
        ) else {
            throw WebClientError<E.Failure>.invalidRequest("Failed to build URL request")
        }

        // Generate request ID if configured
        if let requestId = configuration.requestIdGenerator?() {
            request.setValue(requestId, forHTTPHeaderField: configuration.requestIdHeaderName)
        }

        // Apply request interceptors
        let requestContext = RequestContext(
            path: endpoint.path,
            method: endpoint.method,
            attemptNumber: 0,
            requestId: nil
        )

        for interceptor in configuration.requestInterceptors {
            request = try await interceptor.intercept(request, context: requestContext)
        }

        // Start the download
        let (bytes, response) = try await session.bytes(for: request)

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

        let expectedLength = httpResponse.expectedContentLength
        let totalBytes: Int64? = expectedLength > 0 ? expectedLength : nil

        return DownloadStream(
            response: httpResponse,
            totalBytes: totalBytes,
            bytes: bytes
        )
    }
}

// MARK: - Download Stream

/// A stream of download data chunks.
public struct DownloadStream<Failure: Sendable>: Sendable {
    /// The HTTP response.
    public let response: HTTPURLResponse

    /// The total expected bytes, if known.
    public let totalBytes: Int64?

    /// The underlying byte stream.
    private let bytes: URLSession.AsyncBytes

    init(response: HTTPURLResponse, totalBytes: Int64?, bytes: URLSession.AsyncBytes) {
        self.response = response
        self.totalBytes = totalBytes
        self.bytes = bytes
    }

    /// An async sequence of data chunks.
    public var chunks: AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                var buffer = Data()
                let chunkSize = 64 * 1024 // 64KB chunks

                do {
                    for try await byte in bytes {
                        buffer.append(byte)

                        if buffer.count >= chunkSize {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }

                    // Yield remaining data
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// An async sequence of individual bytes with progress tracking.
    public func bytesWithProgress(
        progressDelegate: any ProgressDelegate
    ) -> AsyncThrowingStream<UInt8, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                var bytesReceived: Int64 = 0

                do {
                    for try await byte in bytes {
                        bytesReceived += 1
                        continuation.yield(byte)

                        // Report progress periodically
                        if bytesReceived % 4096 == 0 {
                            let progress = TransferProgress(
                                bytesTransferred: bytesReceived,
                                totalBytes: totalBytes
                            )
                            await progressDelegate.didUpdateProgress(progress)
                        }
                    }

                    let finalProgress = TransferProgress(
                        bytesTransferred: bytesReceived,
                        totalBytes: totalBytes
                    )
                    await progressDelegate.didUpdateProgress(finalProgress)
                    await progressDelegate.didComplete()
                    continuation.finish()
                } catch {
                    await progressDelegate.didFail(with: error)
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
