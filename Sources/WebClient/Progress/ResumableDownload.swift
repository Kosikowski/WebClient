import Foundation

/// Actor wrapping URLSessionDownloadTask for resumable downloads.
///
/// `ResumableDownload` provides a framework-agnostic way to perform downloads that can be
/// paused, resumed, and cancelled. It uses `URLSessionDownloadTask` under the hood for
/// native resume data support.
///
/// ## Example
/// ```swift
/// let download = try await client.resumableDownload(
///     MyDownloadEndpoint(fileId: "123"),
///     to: destinationURL
/// )
///
/// // Monitor progress
/// for await progress in download.progressUpdates {
///     print("\(progress.percentageString ?? "?")")
/// }
///
/// // Or pause and resume later
/// let resumeData = await download.pause()
///
/// // Resume with the data
/// let newDownload = try await client.resumableDownload(
///     MyDownloadEndpoint(fileId: "123"),
///     to: destinationURL,
///     resumeData: resumeData
/// )
///
/// let url = try await newDownload.result
/// ```
public actor ResumableDownload<Failure: Sendable & Error>: Sendable {
    /// The state of a resumable download.
    public enum State: Sendable {
        /// The download is actively in progress.
        case downloading
        /// The download is paused with resume data available.
        case paused(resumeData: Data)
        /// The download completed successfully.
        case completed(URL)
        /// The download failed with an error.
        case failed(any Error & Sendable)
        /// The download was cancelled (without resume data).
        case cancelled
    }

    /// The current state of the download.
    public private(set) var state: State = .downloading

    /// The current progress of the download.
    public private(set) var progress: TransferProgress = .init(bytesTransferred: 0, totalBytes: nil)

    /// The destination URL for the downloaded file.
    public let destination: URL

    // Internal state
    private var downloadTask: URLSessionDownloadTask?
    private var progressContinuation: AsyncStream<TransferProgress>.Continuation?
    private var resultContinuation: CheckedContinuation<URL, any Error>?
    private var hasSetupResultContinuation = false

    // For tracking the progress stream
    private let progressStream: AsyncStream<TransferProgress>

    /// Stream of progress updates - iterate with `for await`.
    ///
    /// This stream yields progress updates as the download proceeds.
    /// The stream completes when the download finishes, fails, or is cancelled.
    public var progressUpdates: AsyncStream<TransferProgress> {
        progressStream
    }

    /// Initializes a new resumable download.
    init(destination: URL) {
        self.destination = destination
        var continuation: AsyncStream<TransferProgress>.Continuation!
        progressStream = AsyncStream { cont in
            continuation = cont
        }
        progressContinuation = continuation
    }

    /// Sets the download task for this download.
    func setDownloadTask(_ task: URLSessionDownloadTask) {
        downloadTask = task
    }

    /// Pauses the download and returns resume data if available.
    ///
    /// After pausing, the download can be resumed by creating a new `ResumableDownload`
    /// with the resume data.
    ///
    /// - Returns: Resume data that can be used to continue the download, or nil if
    ///   resume data couldn't be generated.
    public func pause() async -> Data? {
        guard case .downloading = state else { return nil }

        return await withCheckedContinuation { continuation in
            downloadTask?.cancel { [weak self] resumeData in
                Task { [weak self] in
                    guard let self else {
                        continuation.resume(returning: resumeData)
                        return
                    }
                    if let resumeData {
                        await self.updateState(.paused(resumeData: resumeData))
                    } else {
                        await self.updateState(.cancelled)
                    }
                    continuation.resume(returning: resumeData)
                }
            }
        }
    }

    /// Cancels the download without producing resume data.
    ///
    /// After cancelling, the download cannot be resumed.
    public func cancel() async {
        guard case .downloading = state else { return }

        downloadTask?.cancel()
        updateState(.cancelled)
    }

    /// Awaits the final result of the download.
    ///
    /// - Returns: The URL of the downloaded file.
    /// - Throws: The error if the download failed.
    public var result: URL {
        get async throws {
            // Check if already completed or failed
            switch state {
            case let .completed(url):
                return url
            case let .failed(error):
                throw error
            case .cancelled:
                throw WebClientError<Failure>.cancelled
            case .paused:
                throw WebClientError<Failure>.cancelled
            case .downloading:
                break
            }

            // Wait for completion
            return try await withCheckedThrowingContinuation { continuation in
                if hasSetupResultContinuation {
                    // Already have a waiter, this is a programming error
                    continuation.resume(throwing: WebClientError<Failure>.invalidRequest("Multiple concurrent result waiters not supported"))
                    return
                }
                hasSetupResultContinuation = true
                resultContinuation = continuation
            }
        }
    }

    // MARK: - Internal Updates (called by delegate)

    /// Updates the progress. Called by the delegate.
    func updateProgress(_ newProgress: TransferProgress) {
        progress = newProgress
        progressContinuation?.yield(newProgress)
    }

    /// Marks the download as completed. Called by the delegate.
    func complete(with url: URL) {
        updateState(.completed(url))
        resultContinuation?.resume(returning: url)
        resultContinuation = nil
    }

    /// Marks the download as failed. Called by the delegate.
    func fail(with error: any Error & Sendable) {
        updateState(.failed(error))
        resultContinuation?.resume(throwing: error)
        resultContinuation = nil
    }

    /// Updates the state and finishes the progress stream if needed.
    private func updateState(_ newState: State) {
        state = newState
        switch newState {
        case .downloading:
            break
        case .paused, .completed, .failed, .cancelled:
            progressContinuation?.finish()
            progressContinuation = nil
        }
    }
}
