import Foundation
import Testing
@testable import WebClient

@Suite("ResumableDownload Tests")
struct ResumableDownloadTests {
    // MARK: - State Tests

    @Test("Initial state is downloading")
    func initialState() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        let state = await download.state
        if case .downloading = state {
            // Expected
        } else {
            Issue.record("Expected downloading state, got \(state)")
        }
    }

    @Test("Initial progress is zero")
    func initialProgress() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        let progress = await download.progress
        #expect(progress.bytesTransferred == 0)
        #expect(progress.totalBytes == nil)
    }

    @Test("Destination is set correctly")
    func destinationSet() async {
        let destination = URL(filePath: "/tmp/download/file.bin")
        let download = ResumableDownload<TestError>(destination: destination)

        let downloadDest = await download.destination
        #expect(downloadDest == destination)
    }

    // MARK: - Progress Update Tests

    @Test("Progress updates are reflected")
    func progressUpdates() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        let newProgress = TransferProgress(bytesTransferred: 1024, totalBytes: 2048)
        await download.updateProgress(newProgress)

        let currentProgress = await download.progress
        #expect(currentProgress.bytesTransferred == 1024)
        #expect(currentProgress.totalBytes == 2048)
    }

    @Test("Multiple progress updates accumulate")
    func multipleProgressUpdates() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        await download.updateProgress(TransferProgress(bytesTransferred: 100, totalBytes: 1000))
        await download.updateProgress(TransferProgress(bytesTransferred: 500, totalBytes: 1000))
        await download.updateProgress(TransferProgress(bytesTransferred: 750, totalBytes: 1000))

        let currentProgress = await download.progress
        #expect(currentProgress.bytesTransferred == 750)
    }

    // MARK: - Completion Tests

    @Test("Complete updates state")
    func completeUpdatesState() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        let completedURL = URL(filePath: "/tmp/completed.txt")
        await download.complete(with: completedURL)

        let state = await download.state
        if case let .completed(url) = state {
            #expect(url == completedURL)
        } else {
            Issue.record("Expected completed state, got \(state)")
        }
    }

    @Test("Result returns completed URL")
    func resultReturnsCompletedURL() async throws {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        let completedURL = URL(filePath: "/tmp/completed.txt")

        // Complete in a separate task
        Task {
            try? await Task.sleep(for: .milliseconds(10))
            await download.complete(with: completedURL)
        }

        let result = try await download.result
        #expect(result == completedURL)
    }

    // MARK: - Failure Tests

    @Test("Fail updates state")
    func failUpdatesState() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        let error = TestError.someError
        await download.fail(with: error)

        let state = await download.state
        if case .failed = state {
            // Expected
        } else {
            Issue.record("Expected failed state, got \(state)")
        }
    }

    @Test("Result throws on failure")
    func resultThrowsOnFailure() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        await download.fail(with: TestError.someError)

        do {
            _ = try await download.result
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected
        }
    }

    // MARK: - Cancellation Tests

    @Test("Cancel updates state to cancelled")
    func cancelUpdatesState() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        await download.cancel()

        let state = await download.state
        if case .cancelled = state {
            // Expected
        } else {
            Issue.record("Expected cancelled state, got \(state)")
        }
    }

    @Test("Result throws on cancellation")
    func resultThrowsOnCancellation() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        await download.cancel()

        do {
            _ = try await download.result
            Issue.record("Expected error to be thrown")
        } catch let error as WebClientError<TestError> {
            if case .cancelled = error {
                // Expected
            } else {
                Issue.record("Expected cancelled error, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - State Transition Tests

    @Test("Cannot cancel when completed")
    func cannotCancelWhenCompleted() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        await download.complete(with: URL(filePath: "/tmp/done.txt"))
        await download.cancel()

        let state = await download.state
        if case .completed = state {
            // Expected - state should still be completed
        } else {
            Issue.record("Expected completed state, got \(state)")
        }
    }

    @Test("Cannot pause when completed")
    func cannotPauseWhenCompleted() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        await download.complete(with: URL(filePath: "/tmp/done.txt"))
        let resumeData = await download.pause()

        #expect(resumeData == nil)

        let state = await download.state
        if case .completed = state {
            // Expected - state should still be completed
        } else {
            Issue.record("Expected completed state, got \(state)")
        }
    }

    // MARK: - Progress Stream Tests

    @Test("Progress stream yields updates")
    func progressStreamYieldsUpdates() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        // Get the progress stream first (inside actor context)
        let progressStream = await download.progressUpdates

        // Start collecting progress in a task
        let collectTask = Task {
            var updates: [TransferProgress] = []
            for await progress in progressStream {
                updates.append(progress)
                if updates.count >= 3 {
                    break
                }
            }
            return updates
        }

        // Send progress updates
        await download.updateProgress(TransferProgress(bytesTransferred: 100, totalBytes: 1000))
        await download.updateProgress(TransferProgress(bytesTransferred: 200, totalBytes: 1000))
        await download.updateProgress(TransferProgress(bytesTransferred: 300, totalBytes: 1000))

        let updates = await collectTask.value
        #expect(updates.count == 3)
        #expect(updates[0].bytesTransferred == 100)
        #expect(updates[1].bytesTransferred == 200)
        #expect(updates[2].bytesTransferred == 300)
    }

    @Test("Progress stream finishes on completion")
    func progressStreamFinishesOnCompletion() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        // Get the progress stream first (inside actor context)
        let progressStream = await download.progressUpdates

        // Start collecting progress
        let collectTask = Task {
            var count = 0
            for await _ in progressStream {
                count += 1
            }
            return count
        }

        // Send one update then complete
        await download.updateProgress(TransferProgress(bytesTransferred: 100, totalBytes: 100))
        await download.complete(with: URL(filePath: "/tmp/done.txt"))

        let count = await collectTask.value
        #expect(count >= 1)
    }

    @Test("Progress stream finishes on cancellation")
    func progressStreamFinishesOnCancellation() async {
        let download = ResumableDownload<TestError>(destination: URL(filePath: "/tmp/test.txt"))

        // Get the progress stream first (inside actor context)
        let progressStream = await download.progressUpdates

        // Start collecting progress
        let collectTask = Task {
            var count = 0
            for await _ in progressStream {
                count += 1
            }
            return count
        }

        // Cancel the download
        await download.cancel()

        let count = await collectTask.value
        #expect(count == 0) // Should finish immediately
    }

    // MARK: - TransferProgress Tests

    @Test("TransferProgress fraction completed calculation")
    func transferProgressFractionCompleted() {
        let progress = TransferProgress(bytesTransferred: 500, totalBytes: 1000)

        #expect(progress.fractionCompleted == 0.5)
    }

    @Test("TransferProgress fraction completed nil when total unknown")
    func transferProgressFractionCompletedNil() {
        let progress = TransferProgress(bytesTransferred: 500, totalBytes: nil)

        #expect(progress.fractionCompleted == nil)
    }

    @Test("TransferProgress percentage string")
    func transferProgressPercentageString() {
        let progress = TransferProgress(bytesTransferred: 250, totalBytes: 1000)

        #expect(progress.percentageString == "25%")
    }

    @Test("TransferProgress percentage string nil when total unknown")
    func transferProgressPercentageStringNil() {
        let progress = TransferProgress(bytesTransferred: 500, totalBytes: nil)

        #expect(progress.percentageString == nil)
    }

    @Test("TransferProgress formatted bytes")
    func transferProgressFormattedBytes() {
        let progress = TransferProgress(bytesTransferred: 1024 * 1024, totalBytes: 10 * 1024 * 1024)

        #expect(!progress.bytesTransferredFormatted.isEmpty)
        #expect(progress.totalBytesFormatted != nil)
        #expect(!progress.totalBytesFormatted!.isEmpty)
    }

    @Test("TransferProgress formatted total bytes nil when unknown")
    func transferProgressFormattedTotalBytesNil() {
        let progress = TransferProgress(bytesTransferred: 1024, totalBytes: nil)

        #expect(progress.totalBytesFormatted == nil)
    }
}

// MARK: - Test Helpers

enum TestError: Error, Sendable {
    case someError
    case anotherError
}
