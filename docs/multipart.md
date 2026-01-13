# Multipart Uploads

WebClient provides comprehensive support for multipart/form-data uploads.

## Building Multipart Form Data

### Text Fields

```swift
var formData = MultipartFormData()
formData.append(name: "title", value: "My Document")
formData.append(name: "description", value: "A sample document")
```

### File from Data

```swift
formData.append(
    name: "avatar",
    data: imageData,
    filename: "profile.jpg",
    mimeType: "image/jpeg"
)
```

### File from URL

```swift
try formData.append(
    name: "document",
    fileURL: documentURL,
    filename: "report.pdf",      // Optional, defaults to URL filename
    mimeType: "application/pdf"  // Optional, auto-detected from extension
)
```

### JSON Data

```swift
try formData.append(
    name: "metadata",
    json: MetadataObject(author: "John", version: 1)
)
```

## MultipartEndpoint Protocol

Define upload endpoints using `MultipartEndpoint`:

```swift
struct UploadAvatarEndpoint: MultipartEndpoint {
    typealias Success = UploadResponse
    typealias Failure = APIError

    let userId: String
    let imageData: Data
    let imageName: String

    var path: String { "/users/\(userId)/avatar" }
    var decoder: any Decoding { JSONDecoder() }

    var formData: MultipartFormData {
        var form = MultipartFormData()
        form.append(
            name: "avatar",
            data: imageData,
            filename: imageName,
            mimeType: "image/jpeg"
        )
        return form
    }
}
```

## Invoking Multipart Endpoints

```swift
let response = try await client.invoke(UploadAvatarEndpoint(
    userId: "123",
    imageData: avatarData,
    imageName: "profile.jpg"
))
```

## Multiple Files

```swift
struct UploadDocumentsEndpoint: MultipartEndpoint {
    typealias Success = UploadResponse
    typealias Failure = APIError

    let files: [(data: Data, name: String, mimeType: String)]
    let category: String

    var path: String { "/documents/upload" }
    var decoder: any Decoding { JSONDecoder() }

    var formData: MultipartFormData {
        var form = MultipartFormData()

        // Add category field
        form.append(name: "category", value: category)

        // Add all files
        for (index, file) in files.enumerated() {
            form.append(
                name: "file[\(index)]",
                data: file.data,
                filename: file.name,
                mimeType: file.mimeType
            )
        }

        return form
    }
}
```

## MIME Type Detection

WebClient automatically detects MIME types for common file extensions:

```swift
MultipartFormData.mimeType(for: "jpg")   // "image/jpeg"
MultipartFormData.mimeType(for: "pdf")   // "application/pdf"
MultipartFormData.mimeType(for: "mp4")   // "video/mp4"
MultipartFormData.mimeType(for: "json")  // "application/json"
```

Supported categories:
- **Images**: jpg, png, gif, webp, svg, heic, tiff, bmp
- **Documents**: pdf, doc, docx, xls, xlsx, ppt, pptx
- **Text**: txt, html, css, js, json, xml, csv, md
- **Archives**: zip, tar, gz, rar, 7z
- **Audio**: mp3, wav, ogg, m4a, flac
- **Video**: mp4, mov, avi, webm, mkv

## Streaming Uploads

For large files, use `MultipartInputStream` to stream data:

```swift
let parts = [
    MultipartPart(
        name: "file",
        filename: "large-video.mp4",
        mimeType: "video/mp4",
        data: videoData
    )
]

let stream = MultipartInputStream(parts: parts, chunkSize: 64 * 1024)

// Access content type and length
let contentType = stream.contentType
let contentLength = stream.contentLength

// Stream chunks
for await chunk in stream.makeAsyncStream() {
    // Process chunk
}
```
