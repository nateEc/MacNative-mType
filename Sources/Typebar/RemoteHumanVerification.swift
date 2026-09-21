import Foundation

enum RemoteHumanVerificationPurpose: String, Codable, Sendable {
    case registration
    case passwordResetRequest
    case profileReport
    case quoteSubmission
    case quoteReport
}

struct RemoteHumanVerificationProof: Codable, Equatable, Sendable {
    let challengeID: UUID
    let value: String

    init(callbackURL: URL) throws {
        guard callbackURL.scheme?.lowercased() == "typebar",
              callbackURL.host?.lowercased() == "human-verification",
              callbackURL.path == "/callback",
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let idValue = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let challengeID = UUID(uuidString: idValue),
              let proof = components.queryItems?.first(where: { $0.name == "proof" })?.value,
              !proof.isEmpty
        else {
            throw RemoteAccountError.invalidHumanVerificationCallback
        }

        self.challengeID = challengeID
        value = proof
    }
}

struct RemoteHumanVerificationChallengeStartRequest: Codable, Sendable {
    let purpose: RemoteHumanVerificationPurpose
}

struct RemoteHumanVerificationChallengeStartResponse: Codable, Sendable {
    let id: UUID
    let verificationPath: String
}

enum RemoteHumanVerificationURL {
    static func challengeURL(endpoint: String, relativePath: String) throws -> URL {
        guard let baseURL = URL(string: endpoint),
              baseURL.scheme?.lowercased() == "https",
              baseURL.host != nil,
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.query == nil,
              baseURL.fragment == nil,
              let pathComponents = URLComponents(string: relativePath),
              pathComponents.scheme == nil,
              pathComponents.host == nil,
              pathComponents.user == nil,
              pathComponents.password == nil,
              pathComponents.query == nil,
              pathComponents.fragment == nil,
              !relativePath.isEmpty,
              !relativePath.hasPrefix("/")
        else {
            throw RemoteAccountError.invalidHumanVerificationChallenge
        }

        return baseURL.appendingPathComponent(relativePath)
    }
}
