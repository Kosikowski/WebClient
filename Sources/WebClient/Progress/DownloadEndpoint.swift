import Foundation

/// A protocol for endpoints that support download progress tracking.
///
/// Use this protocol for endpoints that download large files where you want
/// to track and display download progress.
///
/// ## Example
/// ```swift
/// struct DownloadFileEndpoint: DownloadEndpoint {
///     typealias Failure = APIError
///
///     let fileId: String
///
///     var path: String { "/files/\(fileId)/download" }
/// }
///
/// // Usage with progress tracking
/// let (data, _) = try await client.download(
///     DownloadFileEndpoint(fileId: "123"),
///     progressDelegate: ProgressHandler { progress in
///         print("Downloaded: \(progress.percentageString ?? "?")")
///     }
/// )
/// ```
public protocol DownloadEndpoint: RequestProviding, Sendable {
    /// The type of error response from the server.
    associatedtype Failure: Sendable

    /// Decodes a failure response from error data.
    func decodeFailure(from data: Data) -> Failure?
}

public extension DownloadEndpoint {
    func decodeFailure(from _: Data) -> Failure? { nil }
}

public extension DownloadEndpoint where Failure: Decodable {
    func decodeFailure(from data: Data) -> Failure? {
        try? JSONDecoder().decode(Failure.self, from: data)
    }
}

// MARK: - Download Response

/// The result of a download with progress tracking.
public struct DownloadResult: Sendable {
    /// The downloaded data.
    public let data: Data

    /// The HTTP response.
    public let response: HTTPURLResponse

    /// The total bytes downloaded.
    public var bytesDownloaded: Int64 {
        Int64(data.count)
    }

    public init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }
}

// MARK: - Download to File Response

/// The result of downloading to a file.
public struct FileDownloadResult: Sendable {
    /// The URL where the file was saved.
    public let fileURL: URL

    /// The HTTP response.
    public let response: HTTPURLResponse

    /// The total bytes downloaded.
    public let bytesDownloaded: Int64

    public init(fileURL: URL, response: HTTPURLResponse, bytesDownloaded: Int64) {
        self.fileURL = fileURL
        self.response = response
        self.bytesDownloaded = bytesDownloaded
    }
}
