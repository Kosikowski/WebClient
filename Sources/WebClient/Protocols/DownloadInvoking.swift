import Foundation

/// A protocol for types that can perform file downloads.
///
/// This protocol enables dependency injection and testability for download operations.
/// Combined with `EndpointInvoking`, it provides full coverage of WebClient's API.
///
/// ## Example
/// ```swift
/// class DownloadService {
///     private let client: any DownloadInvoking
///
///     init(client: any DownloadInvoking) {
///         self.client = client
///     }
///
///     func downloadModel(to destination: URL) async throws -> URL {
///         let result = try await client.download(
///             ModelDownloadEndpoint(modelId: "example"),
///             to: destination,
///             progressDelegate: nil
///         )
///         return result.fileURL
///     }
/// }
/// ```
public protocol DownloadInvoking: Sendable {
    /// Downloads a file from an endpoint to a destination URL.
    ///
    /// - Parameters:
    ///   - endpoint: The download endpoint.
    ///   - destination: The URL where the file should be saved.
    ///   - progressDelegate: Optional delegate for progress updates.
    /// - Returns: The file download result containing the file URL.
    /// - Throws: An error on failure (typically `WebClientError<E.Failure>`).
    func download<E: DownloadEndpoint>(
        _ endpoint: E,
        to destination: URL,
        progressDelegate: (any ProgressDelegate)?
    ) async throws -> FileDownloadResult

    /// Starts a resumable download that can be paused and resumed.
    ///
    /// - Parameters:
    ///   - endpoint: The download endpoint.
    ///   - destination: The URL where the file should be saved.
    ///   - resumeData: Optional resume data from a previously paused download.
    /// - Returns: A `ResumableDownload` actor for monitoring and controlling the download.
    /// - Throws: An error if the download cannot be started.
    func resumableDownload<E: DownloadEndpoint>(
        _ endpoint: E,
        to destination: URL,
        resumeData: Data?
    ) async throws -> ResumableDownload<E.Failure> where E.Failure: Error
}

/// A combined protocol for types that can both invoke endpoints and perform downloads.
///
/// This is the primary protocol for dependency injection in services that need
/// both API calls and download capabilities.
///
/// ## Example
/// ```swift
/// class ModelService {
///     private let client: any WebClientProtocol
///
///     init(client: any WebClientProtocol) {
///         self.client = client
///     }
///
///     func getModelInfo(id: String) async throws -> ModelInfo {
///         try await client.invoke(GetModelEndpoint(id: id))
///     }
///
///     func downloadModel(id: String, to destination: URL) async throws -> URL {
///         let result = try await client.download(
///             DownloadModelEndpoint(id: id),
///             to: destination,
///             progressDelegate: nil
///         )
///         return result.fileURL
///     }
/// }
/// ```
public typealias WebClientProtocol = EndpointInvoking & DownloadInvoking
