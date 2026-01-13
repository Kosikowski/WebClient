import Foundation

/// A protocol for endpoints that upload multipart form data.
///
/// Use this protocol for file upload endpoints. It automatically sets the correct
/// Content-Type header and handles form data encoding.
///
/// ## Example
/// ```swift
/// struct UploadAvatarEndpoint: MultipartEndpoint {
///     typealias Success = UploadResponse
///     typealias Failure = APIError
///
///     let userId: String
///     let imageData: Data
///     let imageName: String
///
///     var path: String { "/users/\(userId)/avatar" }
///     var decoder: any Decoding { JSONDecoder() }
///
///     var formData: MultipartFormData {
///         var form = MultipartFormData()
///         form.append(
///             name: "avatar",
///             data: imageData,
///             filename: imageName,
///             mimeType: "image/jpeg"
///         )
///         return form
///     }
/// }
///
/// // Usage
/// let response = try await client.invoke(UploadAvatarEndpoint(
///     userId: "123",
///     imageData: avatarData,
///     imageName: "profile.jpg"
/// ))
/// ```
public protocol MultipartEndpoint: ResponseHandling, Sendable {
    /// The path relative to the base URL.
    var path: String { get }

    /// Type-safe path components for building the URL path.
    var pathComponents: [PathComponent]? { get }

    /// Query parameters to include in the URL.
    var queryItems: [URLQueryItem]? { get }

    /// Additional HTTP headers for this endpoint.
    var headers: [String: String]? { get }

    /// Optional retry policy override for this endpoint.
    var retryPolicy: RetryPolicy? { get }

    /// The multipart form data to upload.
    var formData: MultipartFormData { get }
}

// MARK: - Default Implementations

public extension MultipartEndpoint {
    var pathComponents: [PathComponent]? { nil }
    var queryItems: [URLQueryItem]? { nil }
    var headers: [String: String]? { nil }
    var retryPolicy: RetryPolicy? { nil }
}

// MARK: - RequestProviding Conformance

public extension MultipartEndpoint {
    /// Multipart endpoints always use POST.
    var method: HTTPMethod { .post }

    /// The resolved path.
    var resolvedPath: String {
        if let pathComponents {
            return pathComponents.buildPath()
        }
        return path
    }
}

// MARK: - URL Request Building

public extension MultipartEndpoint {
    /// Builds a URLRequest for this multipart endpoint.
    /// - Parameters:
    ///   - baseURL: The base URL.
    ///   - defaultHeaders: Default headers to include.
    /// - Returns: A configured URLRequest, or nil if the URL couldn't be constructed.
    func urlRequest(
        relativeTo baseURL: URL,
        defaultHeaders: [String: String] = [:]
    ) -> URLRequest? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
        components?.path = resolvedPath

        if let queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue

        // Apply default headers
        for (key, value) in defaultHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Apply endpoint headers
        if let headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Set multipart content type and body
        request.setValue(formData.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = formData.encode()

        return request
    }
}

// MARK: - Streaming Multipart Upload

/// A part of a streaming multipart upload.
public struct MultipartPart: Sendable {
    /// The name of the form field.
    public let name: String

    /// The filename, if this is a file upload.
    public let filename: String?

    /// The MIME type of the content.
    public let mimeType: String

    /// The data for this part.
    public let data: Data

    public init(name: String, filename: String? = nil, mimeType: String = "application/octet-stream", data: Data) {
        self.name = name
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

/// A stream that yields multipart data chunks for memory-efficient uploads.
///
/// Use this for large file uploads where you don't want to load the entire file into memory.
public struct MultipartInputStream: Sendable {
    private let boundary: String
    private let parts: [MultipartPart]
    private let chunkSize: Int

    /// Creates a new multipart input stream.
    /// - Parameters:
    ///   - boundary: The multipart boundary string.
    ///   - parts: The parts to stream.
    ///   - chunkSize: The size of data chunks to yield. Defaults to 64KB.
    public init(
        boundary: String = "WebClient-\(UUID().uuidString)",
        parts: [MultipartPart],
        chunkSize: Int = 64 * 1024
    ) {
        self.boundary = boundary
        self.parts = parts
        self.chunkSize = chunkSize
    }

    /// The Content-Type header value.
    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// The total content length in bytes.
    public var contentLength: Int {
        var length = 0

        for part in parts {
            length += "--\(boundary)\r\n".utf8.count

            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            length += "\(disposition)\r\n".utf8.count
            length += "Content-Type: \(part.mimeType)\r\n".utf8.count
            length += "\r\n".utf8.count
            length += part.data.count
            length += "\r\n".utf8.count
        }

        length += "--\(boundary)--\r\n".utf8.count

        return length
    }

    /// Returns an async stream of data chunks.
    public func makeAsyncStream() -> AsyncStream<Data> {
        AsyncStream { continuation in
            Task {
                for part in parts {
                    // Boundary
                    continuation.yield(Data("--\(boundary)\r\n".utf8))

                    // Headers
                    var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
                    if let filename = part.filename {
                        disposition += "; filename=\"\(filename)\""
                    }
                    continuation.yield(Data("\(disposition)\r\n".utf8))
                    continuation.yield(Data("Content-Type: \(part.mimeType)\r\n".utf8))
                    continuation.yield(Data("\r\n".utf8))

                    // Data in chunks
                    var offset = 0
                    while offset < part.data.count {
                        let end = min(offset + chunkSize, part.data.count)
                        let chunk = part.data[offset ..< end]
                        continuation.yield(chunk)
                        offset = end
                    }

                    continuation.yield(Data("\r\n".utf8))
                }

                // Final boundary
                continuation.yield(Data("--\(boundary)--\r\n".utf8))
                continuation.finish()
            }
        }
    }
}
