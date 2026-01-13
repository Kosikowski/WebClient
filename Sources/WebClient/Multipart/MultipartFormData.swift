import Foundation

/// Represents a multipart/form-data body for file uploads and form submissions.
///
/// Use this type to construct multipart form data with files, data, and text fields.
///
/// ## Example
/// ```swift
/// var formData = MultipartFormData()
///
/// // Add a text field
/// formData.append(name: "description", value: "Profile photo")
///
/// // Add a file from data
/// formData.append(
///     name: "avatar",
///     data: imageData,
///     filename: "avatar.jpg",
///     mimeType: "image/jpeg"
/// )
///
/// // Add a file from URL
/// try formData.append(
///     name: "document",
///     fileURL: documentURL,
///     mimeType: "application/pdf"
/// )
/// ```
public struct MultipartFormData: Sendable {
    /// The boundary string used to separate parts.
    public let boundary: String

    /// The parts that make up this multipart form.
    private var parts: [Part] = []

    /// Creates a new multipart form data with an optional custom boundary.
    /// - Parameter boundary: The boundary string. Defaults to a UUID-based boundary.
    public init(boundary: String = "WebClient-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// The Content-Type header value for this multipart form.
    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// Appends a text field to the form.
    /// - Parameters:
    ///   - name: The field name.
    ///   - value: The text value.
    public mutating func append(name: String, value: String) {
        let data = Data(value.utf8)
        parts.append(Part(
            name: name,
            filename: nil,
            mimeType: "text/plain; charset=utf-8",
            data: data
        ))
    }

    /// Appends raw data to the form.
    /// - Parameters:
    ///   - name: The field name.
    ///   - data: The data to append.
    ///   - filename: Optional filename for the data.
    ///   - mimeType: The MIME type of the data. Defaults to "application/octet-stream".
    public mutating func append(
        name: String,
        data: Data,
        filename: String? = nil,
        mimeType: String = "application/octet-stream"
    ) {
        parts.append(Part(
            name: name,
            filename: filename,
            mimeType: mimeType,
            data: data
        ))
    }

    /// Appends a file from a URL to the form.
    /// - Parameters:
    ///   - name: The field name.
    ///   - fileURL: The URL of the file to append.
    ///   - filename: Optional filename. Defaults to the URL's last path component.
    ///   - mimeType: The MIME type of the file. If not provided, it will be inferred from the file extension.
    /// - Throws: An error if the file cannot be read.
    public mutating func append(
        name: String,
        fileURL: URL,
        filename: String? = nil,
        mimeType: String? = nil
    ) throws {
        let data = try Data(contentsOf: fileURL)
        let resolvedFilename = filename ?? fileURL.lastPathComponent
        let resolvedMimeType = mimeType ?? Self.mimeType(for: fileURL.pathExtension)

        parts.append(Part(
            name: name,
            filename: resolvedFilename,
            mimeType: resolvedMimeType,
            data: data
        ))
    }

    /// Appends an encodable value as JSON to the form.
    /// - Parameters:
    ///   - name: The field name.
    ///   - value: The encodable value.
    ///   - encoder: The JSON encoder to use. Defaults to a new JSONEncoder.
    /// - Throws: An encoding error if the value cannot be encoded.
    public mutating func append<T: Encodable>(
        name: String,
        json value: T,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        let data = try encoder.encode(value)
        parts.append(Part(
            name: name,
            filename: nil,
            mimeType: "application/json",
            data: data
        ))
    }

    /// Encodes the multipart form data to a Data object.
    /// - Returns: The encoded form data.
    public func encode() -> Data {
        var body = Data()

        for part in parts {
            body.append("--\(boundary)\r\n")

            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            body.append("\(disposition)\r\n")
            body.append("Content-Type: \(part.mimeType)\r\n")
            body.append("\r\n")
            body.append(part.data)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")

        return body
    }

    /// Returns the total size of the encoded data without actually encoding it.
    /// Useful for Content-Length header estimation.
    public var estimatedSize: Int {
        var size = 0

        for part in parts {
            // Boundary line
            size += "--\(boundary)\r\n".utf8.count

            // Content-Disposition header
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            size += "\(disposition)\r\n".utf8.count

            // Content-Type header
            size += "Content-Type: \(part.mimeType)\r\n".utf8.count

            // Empty line and data
            size += "\r\n".utf8.count
            size += part.data.count
            size += "\r\n".utf8.count
        }

        // Final boundary
        size += "--\(boundary)--\r\n".utf8.count

        return size
    }

    /// Infers a MIME type from a file extension.
    /// - Parameter fileExtension: The file extension (without the dot).
    /// - Returns: The inferred MIME type, or "application/octet-stream" if unknown.
    public static func mimeType(for fileExtension: String) -> String {
        let ext = fileExtension.lowercased()

        switch ext {
        // Images
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        case "ico":
            return "image/x-icon"
        case "heic", "heif":
            return "image/heic"
        case "tiff", "tif":
            return "image/tiff"
        case "bmp":
            return "image/bmp"
        // Documents
        case "pdf":
            return "application/pdf"
        case "doc":
            return "application/msword"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls":
            return "application/vnd.ms-excel"
        case "xlsx":
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt":
            return "application/vnd.ms-powerpoint"
        case "pptx":
            return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        // Text
        case "txt":
            return "text/plain"
        case "html", "htm":
            return "text/html"
        case "css":
            return "text/css"
        case "js":
            return "text/javascript"
        case "json":
            return "application/json"
        case "xml":
            return "application/xml"
        case "csv":
            return "text/csv"
        case "md":
            return "text/markdown"
        // Archives
        case "zip":
            return "application/zip"
        case "tar":
            return "application/x-tar"
        case "gz", "gzip":
            return "application/gzip"
        case "rar":
            return "application/vnd.rar"
        case "7z":
            return "application/x-7z-compressed"
        // Audio
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "ogg":
            return "audio/ogg"
        case "m4a":
            return "audio/mp4"
        case "flac":
            return "audio/flac"
        // Video
        case "mp4":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "avi":
            return "video/x-msvideo"
        case "webm":
            return "video/webm"
        case "mkv":
            return "video/x-matroska"
        // Other
        default:
            return "application/octet-stream"
        }
    }
}

// MARK: - Part

private extension MultipartFormData {
    struct Part: Sendable {
        let name: String
        let filename: String?
        let mimeType: String
        let data: Data
    }
}

// MARK: - Data Extension

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

// MARK: - MultipartFormData Encoding Conformance

extension MultipartFormData: Encoding {
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        // This encoder is used for endpoint body encoding
        // For multipart, we expect the value to be the MultipartFormData itself
        if let formData = value as? MultipartFormData {
            return formData.encode()
        }

        // For other types, encode as JSON and wrap in form data
        var formData = MultipartFormData(boundary: boundary)
        try formData.append(name: "data", json: value)
        return formData.encode()
    }
}
