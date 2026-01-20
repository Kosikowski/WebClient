import Foundation

/// Internal delegate that bridges URLSessionDownloadDelegate callbacks to the ResumableDownload actor.
final class ResumableDownloadDelegate<Failure: Sendable & Error>: NSObject, URLSessionDownloadDelegate, Sendable {
    private let download: ResumableDownload<Failure>
    private let destination: URL
    private let endpoint: any DownloadEndpoint
    private let completion: @Sendable (Result<URL, any Error>) -> Void

    init(
        download: ResumableDownload<Failure>,
        destination: URL,
        endpoint: any DownloadEndpoint,
        completion: @escaping @Sendable (Result<URL, any Error>) -> Void
    ) {
        self.download = download
        self.destination = destination
        self.endpoint = endpoint
        self.completion = completion
        super.init()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let totalBytes: Int64? = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let progress = TransferProgress(
            bytesTransferred: totalBytesWritten,
            totalBytes: totalBytes
        )

        Task {
            await download.updateProgress(progress)
        }
    }

    func urlSession(_: URLSession, downloadTask _: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move the downloaded file to the destination
        let fileManager = FileManager.default

        do {
            // Ensure parent directory exists
            let parentDirectory = destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

            // Remove existing file if present
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            // Move the downloaded file
            try fileManager.moveItem(at: location, to: destination)

            Task {
                await download.complete(with: destination)
            }
            completion(.success(destination))
        } catch {
            Task {
                await download.fail(with: error)
            }
            completion(.failure(error))
        }
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }

        // Handle cancellation with resume data specially
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == NSURLErrorCancelled,
           nsError.userInfo[NSURLSessionDownloadTaskResumeData] != nil
        {
            // This is a pause, not an error - handled by pause() method
            return
        }

        // Map the error appropriately
        let webClientError: WebClientError<Failure>
        if let urlError = error as? URLError {
            webClientError = .from(urlError: urlError)
        } else if (error as NSError).code == NSURLErrorCancelled {
            webClientError = .cancelled
        } else {
            webClientError = .networkError(underlying: error)
        }

        // Check for HTTP error response
        if let httpResponse = task.response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode)
        {
            let failure = endpoint.decodeFailure(from: Data()) as? Failure
            let serverError = WebClientError<Failure>.serverError(
                statusCode: httpResponse.statusCode,
                failure: failure,
                data: nil
            )
            Task {
                await download.fail(with: serverError)
            }
            completion(.failure(serverError))
            return
        }

        Task {
            await download.fail(with: webClientError)
        }
        completion(.failure(webClientError))
    }
}

/// A session configuration holder for resumable downloads.
final class ResumableDownloadSession<Failure: Sendable & Error>: Sendable {
    let session: URLSession
    let delegate: ResumableDownloadDelegate<Failure>

    init(session: URLSession, delegate: ResumableDownloadDelegate<Failure>) {
        self.session = session
        self.delegate = delegate
    }

    deinit {
        session.invalidateAndCancel()
    }
}
