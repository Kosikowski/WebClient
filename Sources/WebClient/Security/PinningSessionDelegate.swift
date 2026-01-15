import Foundation

/// A URLSession delegate that performs certificate pinning validation.
///
/// This delegate intercepts the authentication challenge and validates the server's
/// certificate against the pinned values before allowing the connection.
///
/// ## Usage
/// This delegate is automatically used when you create a `WebClient` with a
/// `CertificatePinning` configuration:
///
/// ```swift
/// let pinning = CertificatePinning(pins: [...])
/// let client = WebClient(configuration: config, certificatePinning: pinning)
/// ```
public final class PinningSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    /// The certificate pinning configuration.
    private let pinning: CertificatePinning

    /// A callback invoked when pinning validation fails.
    private let onPinningFailure: (@Sendable (String, String) -> Void)?

    /// Creates a pinning session delegate.
    ///
    /// - Parameters:
    ///   - pinning: The certificate pinning configuration.
    ///   - onPinningFailure: Optional callback when pinning fails (host, reason).
    public init(
        pinning: CertificatePinning,
        onPinningFailure: (@Sendable (String, String) -> Void)? = nil
    ) {
        self.pinning = pinning
        self.onPinningFailure = onPinningFailure
        super.init()
    }

    // MARK: - URLSessionDelegate

    public func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    // MARK: - Private

    private func handleChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only handle server trust challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Validate against pinning configuration
        if pinning.validate(serverTrust: serverTrust, host: host) {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            onPinningFailure?(host, "Certificate does not match pinned value")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

/// A URLSession task delegate that performs per-task certificate pinning.
///
/// Use this when you need different pinning configurations for different requests
/// within the same session.
public final class PinningTaskDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    /// The certificate pinning configuration.
    private let pinning: CertificatePinning

    /// A callback invoked when pinning validation fails.
    private let onPinningFailure: (@Sendable (String, String) -> Void)?

    /// Creates a pinning task delegate.
    ///
    /// - Parameters:
    ///   - pinning: The certificate pinning configuration.
    ///   - onPinningFailure: Optional callback when pinning fails (host, reason).
    public init(
        pinning: CertificatePinning,
        onPinningFailure: (@Sendable (String, String) -> Void)? = nil
    ) {
        self.pinning = pinning
        self.onPinningFailure = onPinningFailure
        super.init()
    }

    // MARK: - URLSessionTaskDelegate

    public func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only handle server trust challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Validate against pinning configuration
        if pinning.validate(serverTrust: serverTrust, host: host) {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            onPinningFailure?(host, "Certificate does not match pinned value")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
