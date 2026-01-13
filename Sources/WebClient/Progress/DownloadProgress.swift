import Foundation

/// Represents the progress of a download or upload operation.
public struct TransferProgress: Sendable {
    /// The number of bytes transferred so far.
    public let bytesTransferred: Int64

    /// The total expected bytes, if known.
    public let totalBytes: Int64?

    /// The fraction completed (0.0 to 1.0), if total is known.
    public var fractionCompleted: Double? {
        guard let total = totalBytes, total > 0 else { return nil }
        return Double(bytesTransferred) / Double(total)
    }

    /// A formatted string representation of bytes transferred.
    public var bytesTransferredFormatted: String {
        ByteCountFormatter.string(fromByteCount: bytesTransferred, countStyle: .file)
    }

    /// A formatted string representation of total bytes.
    public var totalBytesFormatted: String? {
        guard let total = totalBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    /// A percentage string (e.g., "45%").
    public var percentageString: String? {
        guard let fraction = fractionCompleted else { return nil }
        return "\(Int(fraction * 100))%"
    }

    public init(bytesTransferred: Int64, totalBytes: Int64?) {
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
    }
}

/// A protocol for receiving progress updates during downloads.
public protocol ProgressDelegate: Sendable {
    /// Called when download progress is updated.
    /// - Parameter progress: The current progress.
    func didUpdateProgress(_ progress: TransferProgress) async

    /// Called when the download completes.
    func didComplete() async

    /// Called when the download fails.
    /// - Parameter error: The error that occurred.
    func didFail(with error: any Error) async
}

/// Default implementations for ProgressDelegate.
public extension ProgressDelegate {
    func didComplete() async {}
    func didFail(with _: any Error) async {}
}

/// A closure-based progress handler for simple use cases.
public struct ProgressHandler: ProgressDelegate, Sendable {
    private let onProgress: @Sendable (TransferProgress) async -> Void
    private let onComplete: (@Sendable () async -> Void)?
    private let onError: (@Sendable (any Error) async -> Void)?

    public init(
        onProgress: @escaping @Sendable (TransferProgress) async -> Void,
        onComplete: (@Sendable () async -> Void)? = nil,
        onError: (@Sendable (any Error) async -> Void)? = nil
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
    }

    public func didUpdateProgress(_ progress: TransferProgress) async {
        await onProgress(progress)
    }

    public func didComplete() async {
        await onComplete?()
    }

    public func didFail(with error: any Error) async {
        await onError?(error)
    }
}

/// An observable progress tracker that publishes updates.
@MainActor
public final class ProgressTracker: ObservableObject, Sendable {
    /// The current progress.
    @Published public private(set) var progress: TransferProgress = .init(bytesTransferred: 0, totalBytes: nil)

    /// Whether the transfer is in progress.
    @Published public private(set) var isTransferring: Bool = false

    /// Whether the transfer completed successfully.
    @Published public private(set) var isCompleted: Bool = false

    /// The error if the transfer failed.
    @Published public private(set) var error: (any Error)?

    public init() {}

    /// Updates the current progress.
    public func update(_ progress: TransferProgress) {
        self.progress = progress
        isTransferring = true
    }

    /// Marks the transfer as complete.
    public func complete() {
        isTransferring = false
        isCompleted = true
    }

    /// Marks the transfer as failed.
    public func fail(with error: any Error) {
        self.error = error
        isTransferring = false
    }

    /// Resets the tracker for a new transfer.
    public func reset() {
        progress = TransferProgress(bytesTransferred: 0, totalBytes: nil)
        isTransferring = false
        isCompleted = false
        error = nil
    }
}

/// A delegate that forwards progress updates to a ProgressTracker.
public struct TrackerProgressDelegate: ProgressDelegate, Sendable {
    private let tracker: ProgressTracker

    public init(tracker: ProgressTracker) {
        self.tracker = tracker
    }

    public func didUpdateProgress(_ progress: TransferProgress) async {
        await MainActor.run {
            tracker.update(progress)
        }
    }

    public func didComplete() async {
        await MainActor.run {
            tracker.complete()
        }
    }

    public func didFail(with error: any Error) async {
        await MainActor.run {
            tracker.fail(with: error)
        }
    }
}
