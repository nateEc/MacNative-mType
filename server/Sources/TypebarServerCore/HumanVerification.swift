import Foundation
import Vapor

/// The write action for which a short-lived human-verification proof was made.
/// A proof can never be substituted across these actions.
public enum HumanVerificationPurpose: String, Content, Equatable, Sendable {
  case registration
  case passwordResetRequest
  case profileReport
  case quoteSubmission
  case quoteReport
}

/// A deployment supplies the public Turnstile key and the hostnames for which
/// a completed provider response is acceptable. The provider secret remains in
/// the deployment-specific verifier and never enters this model or a client.
public struct HumanVerificationConfiguration: Equatable, Sendable {
  public let siteKey: String
  public let allowedHostnames: Set<String>

  public init(siteKey: String, allowedHostnames: Set<String>) {
    self.siteKey = siteKey
    self.allowedHostnames = allowedHostnames
  }
}

/// Deployment configuration for the only currently supported external human
/// verification provider. It is all-or-nothing: an incomplete configuration
/// fails at startup instead of leaving a deployment with a misleading partial
/// security control.
public struct TurnstileConfiguration: Sendable {
  public let siteKey: String
  public let allowedHostnames: Set<String>
  private let secret: String

  private init(siteKey: String, secret: String, allowedHostnames: Set<String>) {
    self.siteKey = siteKey
    self.secret = secret
    self.allowedHostnames = allowedHostnames
  }

  public static func fromEnvironment() throws -> TurnstileConfiguration? {
    try from(
      siteKey: Environment.get("TYPEBAR_TURNSTILE_SITE_KEY"),
      secret: Environment.get("TYPEBAR_TURNSTILE_SECRET"),
      allowedHostnames: Environment.get("TYPEBAR_TURNSTILE_ALLOWED_HOSTNAMES"))
  }

  public static func from(
    siteKey: String?, secret: String?, allowedHostnames: String?
  ) throws -> TurnstileConfiguration? {
    guard siteKey != nil || secret != nil || allowedHostnames != nil else { return nil }
    guard let siteKey = normalized(siteKey), let secret = normalized(secret),
      let rawHostnames = normalized(allowedHostnames)
    else {
      throw TurnstileConfigurationError.incompleteConfiguration
    }

    let hostnames = rawHostnames.split(separator: ",", omittingEmptySubsequences: false).map {
      String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    guard !hostnames.isEmpty, hostnames.allSatisfy(isAllowedHostname) else {
      throw TurnstileConfigurationError.invalidAllowedHostname
    }
    return .init(siteKey: siteKey, secret: secret, allowedHostnames: Set(hostnames))
  }

  /// Production factory. Siteverify accepts URL-encoded input and always
  /// returns JSON; the timeout and response handling mirror this service's
  /// existing OAuth provider requests.
  public func makeHumanVerificationController() -> HumanVerificationController {
    makeHumanVerificationController { [secret] request in
      guard let endpoint = URL(string: "https://challenges.cloudflare.com/turnstile/v0/siteverify") else {
        throw TurnstileConfigurationError.providerUnavailable
      }
      var urlRequest = URLRequest(url: endpoint)
      urlRequest.httpMethod = "POST"
      urlRequest.timeoutInterval = 10
      urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
      urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
      urlRequest.httpBody = Self.formData([("secret", secret), ("response", request.token)])
      let (data, response) = try await URLSession.shared.data(for: urlRequest)
      guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
        let decoded = try? JSONDecoder().decode(TurnstileSiteverifyResponse.self, from: data)
      else {
        throw TurnstileConfigurationError.providerUnavailable
      }
      return decoded
    }
  }

  /// This injection point keeps response-context validation deterministic in
  /// tests without making production requests or exposing the deployment
  /// secret to the client.
  public func makeHumanVerificationController(
    siteverify: @escaping TurnstileSiteverify
  ) -> HumanVerificationController {
    let allowedHostnames = allowedHostnames
    let verifier: HumanVerificationTokenVerifier = { token, action, cData in
      guard !token.isEmpty, token.utf8.count <= 2_048 else { return false }
      let response = try await siteverify(
        .init(token: token, expectedAction: action, expectedCData: cData))
      return response.success
        && response.action == action
        && response.cData == cData
        && allowedHostnames.contains(response.hostname?.lowercased() ?? "")
    }
    return .init(
      configuration: .init(siteKey: siteKey, allowedHostnames: allowedHostnames), verify: verifier)
  }

  private static func normalized(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func isAllowedHostname(_ hostname: String) -> Bool {
    guard !hostname.isEmpty, hostname.count <= 253,
      hostname.rangeOfCharacter(from: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-").inverted) == nil,
      !hostname.hasPrefix("."), !hostname.hasSuffix("."), !hostname.contains("..")
    else { return false }
    return true
  }

  private static func formData(_ pairs: [(String, String)]) -> Data {
    var components = URLComponents()
    components.queryItems = pairs.map { .init(name: $0.0, value: $0.1) }
    return Data((components.percentEncodedQuery ?? "").utf8)
  }
}

public struct TurnstileVerificationRequest: Sendable {
  public let token: String
  public let expectedAction: String
  public let expectedCData: String

  public init(token: String, expectedAction: String, expectedCData: String) {
    self.token = token
    self.expectedAction = expectedAction
    self.expectedCData = expectedCData
  }
}

public struct TurnstileSiteverifyResponse: Decodable, Sendable {
  public let success: Bool
  public let hostname: String?
  public let action: String?
  public let cData: String?

  public init(success: Bool, hostname: String?, action: String?, cData: String?) {
    self.success = success
    self.hostname = hostname
    self.action = action
    self.cData = cData
  }

  private enum CodingKeys: String, CodingKey {
    case success
    case hostname
    case action
    case cData = "cdata"
  }
}

public typealias TurnstileSiteverify = @Sendable (TurnstileVerificationRequest) async throws -> TurnstileSiteverifyResponse

public enum TurnstileConfigurationError: Error, LocalizedError, Sendable {
  case incompleteConfiguration
  case invalidAllowedHostname
  case providerUnavailable

  public var errorDescription: String? {
    switch self {
    case .incompleteConfiguration:
      "TYPEBAR_TURNSTILE_SITE_KEY, TYPEBAR_TURNSTILE_SECRET and TYPEBAR_TURNSTILE_ALLOWED_HOSTNAMES must be configured together."
    case .invalidAllowedHostname:
      "TYPEBAR_TURNSTILE_ALLOWED_HOSTNAMES must contain one or more comma-separated hostnames."
    case .providerUnavailable:
      "Turnstile verification is unavailable."
    }
  }
}

public struct HumanVerificationChallengeStartRequest: Content, Equatable, Sendable {
  public let purpose: HumanVerificationPurpose

  public init(purpose: HumanVerificationPurpose) {
    self.purpose = purpose
  }
}

/// `verificationPath` is deliberately relative to the configured Typebar
/// service. The native client resolves it from its selected endpoint instead
/// of trusting proxy-dependent public URL reconstruction on the server.
public struct HumanVerificationChallengeStartResponse: Content, Equatable, Sendable {
  public let id: UUID
  public let verificationPath: String

  public init(id: UUID, verificationPath: String) {
    self.id = id
    self.verificationPath = verificationPath
  }
}

public struct HumanVerificationChallengeCompletionRequest: Content, Equatable, Sendable {
  public let token: String

  public init(token: String) {
    self.token = token
  }
}

/// The opaque, one-time proof returned to the native authentication session.
/// It is intentionally short-lived and never persisted by the server actor.
public struct HumanVerificationProof: Content, Equatable, Sendable {
  public let challengeID: UUID
  public let value: String

  public init(challengeID: UUID, value: String) {
    self.challengeID = challengeID
    self.value = value
  }

  public init(callbackURL: URL) throws {
    guard callbackURL.scheme == "typebar",
      callbackURL.host == "human-verification",
      callbackURL.path == "/callback",
      let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems,
      let rawID = items.first(where: { $0.name == "id" })?.value,
      let challengeID = UUID(uuidString: rawID),
      let value = items.first(where: { $0.name == "proof" })?.value,
      !value.isEmpty
    else {
      throw HumanVerificationProofError.invalidCallback
    }
    self.init(challengeID: challengeID, value: value)
  }
}

public enum HumanVerificationProofError: Error, LocalizedError, Equatable {
  case invalidCallback

  public var errorDescription: String? {
    switch self {
    case .invalidCallback: "The human-verification callback was invalid."
    }
  }
}

/// This closure is the only provider-specific seam. The production Turnstile
/// adapter validates success, action, cData and hostname before returning
/// true; tests use a deterministic closure without contacting a third party.
public typealias HumanVerificationTokenVerifier = @Sendable (_ token: String, _ action: String, _ cData: String) async throws -> Bool

/// In-memory, single-process challenge authority. It issues an opaque callback
/// proof only after the verifier has accepted the provider token, and atomically
/// consumes that proof before a protected write is allowed.
public actor HumanVerificationController {
  private struct Challenge: Sendable {
    let purpose: HumanVerificationPurpose
    let expiresAt: Date
    var isVerifying = false
    var proof: String?
    var isConsumed = false
  }

  public static let verificationAction = "typebar"
  public static let lifetime: TimeInterval = 5 * 60

  public let configuration: HumanVerificationConfiguration
  private let verify: HumanVerificationTokenVerifier
  private var challenges: [UUID: Challenge] = [:]

  public init(configuration: HumanVerificationConfiguration, verify: @escaping HumanVerificationTokenVerifier) {
    self.configuration = configuration
    self.verify = verify
  }

  public func start(
    _ request: HumanVerificationChallengeStartRequest, now: Date = .now
  ) -> HumanVerificationChallengeStartResponse {
    removeExpired(now: now)
    let id = UUID()
    challenges[id] = Challenge(purpose: request.purpose, expiresAt: now.addingTimeInterval(Self.lifetime))
    return .init(id: id, verificationPath: "v1/human-verification/challenges/\(id.uuidString)/web")
  }

  /// Serves only an independently written Turnstile form. The callback proof
  /// itself remains server-generated and is never supplied by this page.
  public func page(challengeID: UUID, now: Date = .now) throws -> Response {
    removeExpired(now: now)
    guard let challenge = challenges[challengeID], challenge.proof == nil, !challenge.isConsumed else {
      throw Abort(.unprocessableEntity, reason: "That human-verification challenge is unavailable.")
    }
    let siteKey = htmlAttribute(configuration.siteKey)
    let challengeID = challengeID.uuidString
    let formPath = "/v1/human-verification/challenges/\(challengeID)/complete"
    let html = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Typebar verification</title>
        <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
      </head>
      <body>
        <main>
          <p>Complete the verification to continue in Typebar.</p>
          <form id="typebar-verification" method="post" action="\(formPath)">
            <div class="cf-turnstile" data-sitekey="\(siteKey)" data-action="\(Self.verificationAction)" data-cdata="\(challengeID)" data-response-field-name="token" data-callback="submitVerification"></div>
          </form>
        </main>
        <script>
          function submitVerification() {
            document.getElementById('typebar-verification').submit();
          }
        </script>
      </body>
    </html>
    """
    var headers = HTTPHeaders()
    headers.replaceOrAdd(name: .contentType, value: "text/html; charset=utf-8")
    headers.replaceOrAdd(name: "Referrer-Policy", value: "no-referrer")
    headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
    return Response(
      status: .ok,
      headers: headers,
      body: .init(buffer: ByteBufferAllocator().buffer(string: html)))
  }

  public func complete(
    challengeID: UUID,
    request: HumanVerificationChallengeCompletionRequest,
    now: Date = .now
  ) async throws -> URL {
    removeExpired(now: now)
    guard var challenge = challenges[challengeID], challenge.proof == nil, !challenge.isConsumed,
      !challenge.isVerifying
    else {
      throw Abort(.unprocessableEntity, reason: "That human-verification challenge is unavailable.")
    }

    challenge.isVerifying = true
    challenges[challengeID] = challenge
    let cData = challengeID.uuidString
    let isVerified: Bool
    do {
      isVerified = try await verify(request.token, Self.verificationAction, cData)
    } catch {
      clearVerifying(challengeID)
      throw Abort(.serviceUnavailable, reason: "Human verification is temporarily unavailable.")
    }
    guard isVerified else {
      clearVerifying(challengeID)
      throw Abort(.unprocessableEntity, reason: "Human verification was not accepted.")
    }

    guard var verifiedChallenge = challenges[challengeID], verifiedChallenge.isVerifying,
      verifiedChallenge.proof == nil, !verifiedChallenge.isConsumed, verifiedChallenge.expiresAt > now
    else {
      throw Abort(.unprocessableEntity, reason: "That human-verification challenge is unavailable.")
    }
    let proof = randomProof()
    verifiedChallenge.isVerifying = false
    verifiedChallenge.proof = proof
    challenges[challengeID] = verifiedChallenge
    return callbackURL(challengeID: challengeID, proof: proof)
  }

  /// Marks a verified proof consumed before the caller performs its write. A
  /// later validation failure still requires a fresh proof, matching the safe
  /// one-time semantics expected from an external challenge.
  public func consume(
    _ proof: HumanVerificationProof?, for purpose: HumanVerificationPurpose, now: Date = .now
  ) throws {
    removeExpired(now: now)
    guard let proof, var challenge = challenges[proof.challengeID], challenge.purpose == purpose,
      !challenge.isConsumed, !challenge.isVerifying, challenge.proof == proof.value
    else {
      throw Abort(.unprocessableEntity, reason: "A valid human-verification proof is required.")
    }
    challenge.isConsumed = true
    challenges[proof.challengeID] = challenge
  }

  private func clearVerifying(_ challengeID: UUID) {
    guard var challenge = challenges[challengeID], challenge.proof == nil, !challenge.isConsumed else { return }
    challenge.isVerifying = false
    challenges[challengeID] = challenge
  }

  private func removeExpired(now: Date) {
    challenges = challenges.filter { $0.value.expiresAt > now }
  }

  private func callbackURL(challengeID: UUID, proof: String) -> URL {
    var components = URLComponents()
    components.scheme = "typebar"
    components.host = "human-verification"
    components.path = "/callback"
    components.queryItems = [
      .init(name: "id", value: challengeID.uuidString),
      .init(name: "proof", value: proof)
    ]
    // These fixed ASCII scheme, host and path values together with UUID and
    // URLQueryItem values always form a URL; retaining a fallback avoids a
    // force unwrap in this security-sensitive handoff.
    return components.url ?? URL(string: "typebar://human-verification/callback")!
  }

  private func randomProof() -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    var generator = SystemRandomNumberGenerator()
    return String((0..<48).map { _ in alphabet.randomElement(using: &generator)! })
  }

  private func htmlAttribute(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
  }
}
