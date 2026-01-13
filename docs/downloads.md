# Download Progress

WebClient provides progress tracking for large file downloads.

## DownloadEndpoint Protocol

Define download endpoints:

```swift
struct DownloadFileEndpoint: DownloadEndpoint {
    typealias Failure = APIError

    let fileId: String

    var path: String { "/files/\(fileId)/download" }
}
```

## Basic Download with Progress

```swift
let result = try await client.download(
    DownloadFileEndpoint(fileId: "123"),
    progressDelegate: ProgressHandler { progress in
        print("Downloaded: \(progress.bytesTransferredFormatted)")
        if let percentage = progress.percentageString {
            print("Progress: \(percentage)")
        }
    }
)

// Use the downloaded data
try result.data.write(to: destinationURL)
```

## Download to File

For large files, stream directly to disk:

```swift
let destinationURL = documentsDirectory.appendingPathComponent("video.mp4")

let result = try await client.download(
    DownloadFileEndpoint(fileId: "large-video"),
    to: destinationURL,
    progressDelegate: ProgressHandler(
        onProgress: { progress in
            print("\(progress.percentageString ?? "?") complete")
        },
        onComplete: {
            print("Download complete!")
        },
        onError: { error in
            print("Download failed: \(error)")
        }
    )
)

print("File saved to: \(result.fileURL)")
print("Total bytes: \(result.bytesDownloaded)")
```

## TransferProgress

Progress information includes:

```swift
struct TransferProgress {
    let bytesTransferred: Int64      // Bytes downloaded so far
    let totalBytes: Int64?           // Total expected (if known)

    var fractionCompleted: Double?   // 0.0 to 1.0
    var bytesTransferredFormatted: String  // e.g., "45.2 MB"
    var totalBytesFormatted: String?       // e.g., "100 MB"
    var percentageString: String?          // e.g., "45%"
}
```

## Progress Delegates

### Closure-Based Handler

```swift
let handler = ProgressHandler(
    onProgress: { progress in
        updateUI(progress.fractionCompleted ?? 0)
    },
    onComplete: {
        showSuccess()
    },
    onError: { error in
        showError(error)
    }
)
```

### SwiftUI Integration

Use `ProgressTracker` for SwiftUI:

```swift
@StateObject private var tracker = ProgressTracker()

var body: some View {
    VStack {
        if tracker.isTransferring {
            ProgressView(value: tracker.progress.fractionCompleted ?? 0)
            Text(tracker.progress.percentageString ?? "Downloading...")
        }

        if tracker.isCompleted {
            Text("Download complete!")
        }

        if let error = tracker.error {
            Text("Error: \(error.localizedDescription)")
        }
    }
    .task {
        do {
            _ = try await client.download(
                endpoint,
                progressDelegate: TrackerProgressDelegate(tracker: tracker)
            )
        } catch {
            // Error is already in tracker.error
        }
    }
}
```

## Streaming Download

For maximum control, use `downloadStream`:

```swift
let stream = try await client.downloadStream(DownloadFileEndpoint(fileId: "123"))

print("Total size: \(stream.totalBytes ?? 0) bytes")
print("Status: \(stream.response.statusCode)")

// Process chunks as they arrive
var totalReceived: Int64 = 0
for try await chunk in stream.chunks {
    // Write chunk to file or process it
    totalReceived += Int64(chunk.count)
    print("Received \(totalReceived) bytes")
}
```

## Custom Progress Delegate

Implement `ProgressDelegate` for custom behavior:

```swift
struct LoggingProgressDelegate: ProgressDelegate {
    let logger: Logger

    func didUpdateProgress(_ progress: TransferProgress) async {
        logger.info("Progress: \(progress.bytesTransferredFormatted)")
    }

    func didComplete() async {
        logger.info("Download completed")
    }

    func didFail(with error: any Error) async {
        logger.error("Download failed: \(error)")
    }
}
```
