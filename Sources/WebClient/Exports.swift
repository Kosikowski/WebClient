// WebClient - A modern, generic HTTP client for Swift
//
// WebClient provides a protocol-based approach to defining API endpoints
// with type-safe request/response handling, automatic retries, and
// flexible encoding/decoding (JSON, XML, Property Lists).
//
// Usage:
//   struct GetUserEndpoint: Endpoint {
//       typealias Success = User
//       typealias Failure = APIError
//
//       let userId: String
//       var path: String { "/users/\(userId)" }
//       var decoder: any Decoding { JSONDecoder() }
//   }
//
//   let client = WebClient(configuration: .init(baseURL: apiURL))
//   let user = try await client.invoke(GetUserEndpoint(userId: "123"))

@_exported import struct Foundation.Data
@_exported import class Foundation.HTTPURLResponse
@_exported import struct Foundation.URL
@_exported import struct Foundation.URLQueryItem
@_exported import class Foundation.URLResponse
