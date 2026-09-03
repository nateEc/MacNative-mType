import AppKit
import AuthenticationServices

@MainActor
final class OAuthWebAuthenticationSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize(url: URL) async throws -> URL {
        guard session == nil else { throw RemoteAccountError.oauthAuthorizationInProgress }

        return try await withCheckedThrowingContinuation { continuation in
            let authorizationSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "typebar"
            ) { [weak self] callbackURL, error in
                self?.session = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                    return
                }
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: RemoteAccountError.oauthAuthorizationCancelled)
                    return
                }
                continuation.resume(throwing: error ?? RemoteAccountError.unexpectedResponse)
            }
            authorizationSession.presentationContextProvider = self
            session = authorizationSession
            guard authorizationSession.start() else {
                session = nil
                continuation.resume(throwing: RemoteAccountError.unexpectedResponse)
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
