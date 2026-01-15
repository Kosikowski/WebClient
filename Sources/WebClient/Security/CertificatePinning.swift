import CryptoKit
import Foundation

/// Configuration for SSL/TLS certificate pinning.
///
/// Certificate pinning provides enhanced security by validating that the server's
/// certificate matches expected values, preventing man-in-the-middle attacks.
///
/// ## Pinning Strategies
/// - **Public Key Pinning**: Pins the public key hash (recommended - survives certificate rotation)
/// - **Certificate Pinning**: Pins the entire certificate hash (stricter but requires updates on renewal)
///
/// ## Example
/// ```swift
/// let pinning = CertificatePinning(
///     pins: [
///         CertificatePin(
///             host: "api.example.com",
///             publicKeyHashes: [
///                 "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
///                 "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="  // Backup pin
///             ]
///         )
///     ]
/// )
///
/// let client = WebClient(configuration: config, certificatePinning: pinning)
/// ```
///
/// ## Getting Certificate Hashes
/// You can get the public key hash of a certificate using OpenSSL:
/// ```bash
/// # Get the certificate
/// openssl s_client -connect api.example.com:443 -servername api.example.com </dev/null 2>/dev/null | \
///   openssl x509 -outform DER > cert.der
///
/// # Extract public key and hash it
/// openssl x509 -in cert.der -inform DER -pubkey -noout | \
///   openssl pkey -pubin -outform DER | \
///   openssl dgst -sha256 -binary | base64
/// ```
public struct CertificatePinning: Sendable {
    /// The certificate pins for different hosts.
    public let pins: [CertificatePin]

    /// Whether to allow connections to hosts without pins.
    public let allowUnpinnedHosts: Bool

    /// Whether to validate the entire certificate chain.
    public let validateChain: Bool

    /// Creates a certificate pinning configuration.
    ///
    /// - Parameters:
    ///   - pins: The certificate pins for different hosts.
    ///   - allowUnpinnedHosts: Whether to allow connections to hosts without pins. Defaults to `true`.
    ///   - validateChain: Whether to validate the entire chain. Defaults to `false` (only leaf certificate).
    public init(
        pins: [CertificatePin],
        allowUnpinnedHosts: Bool = true,
        validateChain: Bool = false
    ) {
        self.pins = pins
        self.allowUnpinnedHosts = allowUnpinnedHosts
        self.validateChain = validateChain
    }

    /// Returns the pin for a given host, if one exists.
    public func pin(for host: String) -> CertificatePin? {
        pins.first { $0.matches(host: host) }
    }

    /// Validates a server trust against the pinned certificates.
    ///
    /// - Parameters:
    ///   - serverTrust: The server trust to validate.
    ///   - host: The host being connected to.
    /// - Returns: `true` if validation passes, `false` otherwise.
    public func validate(serverTrust: SecTrust, host: String) -> Bool {
        guard let pin = pin(for: host) else {
            // No pin for this host
            return allowUnpinnedHosts
        }

        // Perform standard SSL validation first
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            return false
        }

        // Get certificates from the trust
        let certificateCount = SecTrustGetCertificateCount(serverTrust)
        guard certificateCount > 0 else {
            return false
        }

        // Get the certificate chain
        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            return false
        }

        // Determine which certificates to check
        let certificatesToCheck: [SecCertificate]
        if validateChain {
            certificatesToCheck = certificateChain
        } else {
            certificatesToCheck = certificateChain.isEmpty ? [] : [certificateChain[0]] // Only leaf certificate
        }

        // Check if any certificate in the chain matches
        for certificate in certificatesToCheck {
            if pin.matches(certificate: certificate) {
                return true
            }
        }

        return false
    }
}

/// A certificate pin for a specific host.
public struct CertificatePin: Sendable {
    /// The host pattern to match (can include wildcards like "*.example.com").
    public let hostPattern: String

    /// The pinned public key hashes (SHA-256, base64 encoded).
    public let publicKeyHashes: [String]

    /// The pinned certificate hashes (SHA-256, base64 encoded).
    public let certificateHashes: [String]

    /// Whether to include subdomains.
    public let includeSubdomains: Bool

    /// Creates a certificate pin with public key hashes.
    ///
    /// - Parameters:
    ///   - host: The host to pin.
    ///   - publicKeyHashes: SHA-256 hashes of the public keys (base64 encoded).
    ///   - includeSubdomains: Whether to include subdomains. Defaults to `false`.
    public init(host: String, publicKeyHashes: [String], includeSubdomains: Bool = false) {
        hostPattern = host
        self.publicKeyHashes = publicKeyHashes
        certificateHashes = []
        self.includeSubdomains = includeSubdomains
    }

    /// Creates a certificate pin with certificate hashes.
    ///
    /// - Parameters:
    ///   - host: The host to pin.
    ///   - certificateHashes: SHA-256 hashes of the certificates (base64 encoded).
    ///   - includeSubdomains: Whether to include subdomains. Defaults to `false`.
    public init(host: String, certificateHashes: [String], includeSubdomains: Bool = false) {
        hostPattern = host
        publicKeyHashes = []
        self.certificateHashes = certificateHashes
        self.includeSubdomains = includeSubdomains
    }

    /// Creates a certificate pin with both public key and certificate hashes.
    ///
    /// - Parameters:
    ///   - host: The host to pin.
    ///   - publicKeyHashes: SHA-256 hashes of the public keys (base64 encoded).
    ///   - certificateHashes: SHA-256 hashes of the certificates (base64 encoded).
    ///   - includeSubdomains: Whether to include subdomains. Defaults to `false`.
    public init(
        host: String,
        publicKeyHashes: [String] = [],
        certificateHashes: [String] = [],
        includeSubdomains: Bool = false
    ) {
        hostPattern = host
        self.publicKeyHashes = publicKeyHashes
        self.certificateHashes = certificateHashes
        self.includeSubdomains = includeSubdomains
    }

    /// Checks if this pin matches a host.
    public func matches(host: String) -> Bool {
        let lowercasedHost = host.lowercased()
        let lowercasedPattern = hostPattern.lowercased()

        // Exact match
        if lowercasedHost == lowercasedPattern {
            return true
        }

        // Wildcard match (e.g., *.example.com)
        // Only matches one level of subdomain (api.example.com) but not nested (sub.api.example.com)
        if lowercasedPattern.hasPrefix("*.") {
            let baseDomain = String(lowercasedPattern.dropFirst(2)) // "example.com"
            let expectedSuffix = "." + baseDomain // ".example.com"

            if lowercasedHost.hasSuffix(expectedSuffix) {
                let subdomain = String(lowercasedHost.dropLast(expectedSuffix.count))
                // Subdomain should not contain dots (no nested subdomains)
                if !subdomain.isEmpty && !subdomain.contains(".") {
                    return true
                }
            }
        }

        // Subdomain match (includes all subdomains at any depth)
        if includeSubdomains && lowercasedHost.hasSuffix("." + lowercasedPattern) {
            return true
        }

        return false
    }

    /// Checks if a certificate matches this pin.
    public func matches(certificate: SecCertificate) -> Bool {
        // Check public key hashes
        if !publicKeyHashes.isEmpty {
            if let publicKeyHash = Self.publicKeyHash(for: certificate),
               publicKeyHashes.contains(publicKeyHash)
            {
                return true
            }
        }

        // Check certificate hashes
        if !certificateHashes.isEmpty {
            if let certHash = Self.certificateHash(for: certificate),
               certificateHashes.contains(certHash)
            {
                return true
            }
        }

        return false
    }

    /// Extracts and hashes the public key from a certificate.
    public static func publicKeyHash(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as? Data else {
            return nil
        }

        let hash = SHA256.hash(data: publicKeyData)
        return Data(hash).base64EncodedString()
    }

    /// Hashes the entire certificate.
    public static func certificateHash(for certificate: SecCertificate) -> String? {
        let data = SecCertificateCopyData(certificate) as Data
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
    }
}

/// Error thrown when certificate pinning validation fails.
public struct CertificatePinningError: Error, Sendable {
    /// The host that failed validation.
    public let host: String

    /// A description of the failure.
    public let reason: String

    /// Creates a certificate pinning error.
    public init(host: String, reason: String) {
        self.host = host
        self.reason = reason
    }
}

extension CertificatePinningError: LocalizedError {
    public var errorDescription: String? {
        "Certificate pinning failed for \(host): \(reason)"
    }
}
