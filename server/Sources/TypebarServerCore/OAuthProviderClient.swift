import Foundation
import Vapor

public typealias OAuthIdentityResolver = @Sendable (
  OAuthProvider, String, String
) async throws -> OAuthProviderIdentity

/// Provider-neutral OAuth authorization-code client. It owns provider secrets
/// only in server memory and returns a narrow, verified identity without
/// retaining access or refresh tokens.
public struct OAuthProviderClient: Sendable {
  public struct Configuration: Sendable {
    fileprivate let clientID: String
    fileprivate let clientSecret: String
    fileprivate let redirectURL: URL

    public init(clientID: String, clientSecret: String, redirectURL: URL) throws {
      let normalizedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
      let normalizedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalizedID.isEmpty, !normalizedSecret.isEmpty, Self.isAllowedRedirectURL(redirectURL) else {
        throw OAuthProviderClientError.invalidConfiguration
      }
      self.clientID = normalizedID
      self.clientSecret = normalizedSecret
      self.redirectURL = redirectURL
    }

    private static func isAllowedRedirectURL(_ url: URL) -> Bool {
      guard url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
        let host = url.host?.lowercased()
      else { return false }
      if url.scheme?.lowercased() == "https" { return true }
      return url.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }
  }

  private let configurations: [OAuthProvider: Configuration]
  private let identityResolver: OAuthIdentityResolver?

  public init(
    configurations: [OAuthProvider: Configuration], identityResolver: OAuthIdentityResolver? = nil
  ) {
    self.configurations = configurations
    self.identityResolver = identityResolver
  }

  public func isConfigured(for provider: OAuthProvider) -> Bool {
    configurations[provider] != nil
  }

  /// Reads all credentials from deployment environment variables. A provider
  /// is disabled when every one of its variables is absent; partial settings
  /// fail startup instead of creating an insecure half-configured flow.
  public static func fromEnvironment() throws -> Self {
    var configurations: [OAuthProvider: Configuration] = [:]
    for provider in OAuthProvider.allCases {
      let prefix: String
      switch provider {
      case .github: prefix = "TYPEBAR_GITHUB_OAUTH"
      case .google: prefix = "TYPEBAR_GOOGLE_OAUTH"
      case .discord: prefix = "TYPEBAR_DISCORD_OAUTH"
      }
      let id = Environment.get("\(prefix)_CLIENT_ID")?.trimmingCharacters(in: .whitespacesAndNewlines)
      let secret = Environment.get("\(prefix)_CLIENT_SECRET")?.trimmingCharacters(in: .whitespacesAndNewlines)
      let redirect = Environment.get("\(prefix)_REDIRECT_URL")?.trimmingCharacters(in: .whitespacesAndNewlines)
      guard id != nil || secret != nil || redirect != nil else { continue }
      guard let id, !id.isEmpty, let secret, !secret.isEmpty, let redirect,
        let redirectURL = URL(string: redirect)
      else { throw OAuthProviderClientError.invalidConfiguration }
      configurations[provider] = try .init(
        clientID: id, clientSecret: secret, redirectURL: redirectURL)
    }
    return .init(configurations: configurations)
  }

  public func authorizationURL(for request: OAuthAuthorizationRequest) throws -> URL {
    let configuration = try configuration(for: request.provider)
    let endpoint: String
    let scope: String
    switch request.provider {
    case .github:
      endpoint = "https://github.com/login/oauth/authorize"
      scope = "read:user user:email"
    case .google:
      endpoint = "https://accounts.google.com/o/oauth2/v2/auth"
      scope = "openid profile email"
    case .discord:
      endpoint = "https://discord.com/oauth2/authorize"
      scope = "identify email"
    }
    guard var components = URLComponents(string: endpoint) else {
      throw OAuthProviderClientError.invalidConfiguration
    }
    components.queryItems = [
      .init(name: "client_id", value: configuration.clientID),
      .init(name: "redirect_uri", value: configuration.redirectURL.absoluteString),
      .init(name: "response_type", value: "code"),
      .init(name: "scope", value: scope),
      .init(name: "state", value: request.state),
      .init(name: "code_challenge", value: request.codeChallenge),
      .init(name: "code_challenge_method", value: "S256"),
    ]
    if request.provider == .google {
      components.queryItems?.append(.init(name: "prompt", value: "select_account"))
    }
    guard let url = components.url else { throw OAuthProviderClientError.invalidConfiguration }
    return url
  }

  /// Exchanges an authorization code and queries only the identity endpoints
  /// required for sign-in. Tokens are neither logged nor persisted.
  public func resolveIdentity(
    provider: OAuthProvider, authorizationCode: String, codeVerifier: String
  ) async throws -> OAuthProviderIdentity {
    if let identityResolver {
      return try await identityResolver(provider, authorizationCode, codeVerifier)
    }
    let configuration = try configuration(for: provider)
    let accessToken = try await exchangeCode(
      provider: provider, code: authorizationCode, verifier: codeVerifier, configuration: configuration)
    switch provider {
    case .github:
      return try await githubIdentity(accessToken: accessToken)
    case .google:
      return try await googleIdentity(accessToken: accessToken)
    case .discord:
      return try await discordIdentity(accessToken: accessToken)
    }
  }

  private func configuration(for provider: OAuthProvider) throws -> Configuration {
    guard let configuration = configurations[provider] else {
      throw OAuthProviderClientError.notConfigured
    }
    return configuration
  }

  private func exchangeCode(
    provider: OAuthProvider, code: String, verifier: String, configuration: Configuration
  ) async throws -> String {
    let endpoint: String
    switch provider {
    case .github: endpoint = "https://github.com/login/oauth/access_token"
    case .google: endpoint = "https://oauth2.googleapis.com/token"
    case .discord: endpoint = "https://discord.com/api/oauth2/token"
    }
    guard let url = URL(string: endpoint) else { throw OAuthProviderClientError.invalidConfiguration }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 10
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    var parameters = [
      ("client_id", configuration.clientID),
      ("client_secret", configuration.clientSecret),
      ("code", code),
      ("redirect_uri", configuration.redirectURL.absoluteString),
      ("code_verifier", verifier),
    ]
    if provider != .github { parameters.append(("grant_type", "authorization_code")) }
    request.httpBody = Self.formData(parameters)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw OAuthProviderClientError.providerRejected
    }
    let token = try? JSONDecoder().decode(TokenResponse.self, from: data)
    guard let accessToken = token?.accessToken, !accessToken.isEmpty else {
      throw OAuthProviderClientError.providerRejected
    }
    return accessToken
  }

  private func githubIdentity(accessToken: String) async throws -> OAuthProviderIdentity {
    let user: GitHubUser = try await authorizedJSON(
      url: "https://api.github.com/user", accessToken: accessToken)
    let emails: [GitHubEmail] = try await authorizedJSON(
      url: "https://api.github.com/user/emails", accessToken: accessToken)
    guard let email = emails.first(where: { $0.primary && $0.verified })
      ?? emails.first(where: { $0.verified })
    else { throw OAuthProviderClientError.unverifiedEmail }
    return .init(
      provider: .github, subject: String(user.id), email: email.email,
      suggestedDisplayName: user.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? user.name : user.login)
  }

  private func googleIdentity(accessToken: String) async throws -> OAuthProviderIdentity {
    let user: GoogleUserInfo = try await authorizedJSON(
      url: "https://openidconnect.googleapis.com/v1/userinfo", accessToken: accessToken)
    guard user.emailVerified else { throw OAuthProviderClientError.unverifiedEmail }
    return .init(
      provider: .google, subject: user.subject, email: user.email, suggestedDisplayName: user.name)
  }

  private func discordIdentity(accessToken: String) async throws -> OAuthProviderIdentity {
    let user: DiscordUser = try await authorizedJSON(
      url: "https://discord.com/api/users/@me", accessToken: accessToken)
    guard let email = user.email, user.verified == true else {
      throw OAuthProviderClientError.unverifiedEmail
    }
    let globalName = user.globalName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return .init(
      provider: .discord, subject: user.id, email: email,
      suggestedDisplayName: globalName?.isEmpty == false ? globalName : user.username)
  }

  private func authorizedJSON<Response: Decodable>(
    url rawURL: String, accessToken: String
  ) async throws -> Response {
    guard let url = URL(string: rawURL) else { throw OAuthProviderClientError.invalidConfiguration }
    var request = URLRequest(url: url)
    request.timeoutInterval = 10
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      let decoded = try? JSONDecoder().decode(Response.self, from: data)
    else { throw OAuthProviderClientError.providerRejected }
    return decoded
  }

  private static func formData(_ pairs: [(String, String)]) -> Data {
    var components = URLComponents()
    components.queryItems = pairs.map { .init(name: $0.0, value: $0.1) }
    return Data((components.percentEncodedQuery ?? "").utf8)
  }
}

public enum OAuthProviderClientError: LocalizedError, Sendable {
  case invalidConfiguration
  case notConfigured
  case providerRejected
  case unverifiedEmail

  public var errorDescription: String? {
    switch self {
    case .invalidConfiguration: "Typebar OAuth configuration is invalid."
    case .notConfigured: "This Typebar service does not have that OAuth provider configured."
    case .providerRejected: "The OAuth provider did not complete authentication."
    case .unverifiedEmail: "The OAuth provider did not supply a verified email address."
    }
  }
}

private struct TokenResponse: Decodable {
  let accessToken: String?

  private enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
}

private struct GitHubUser: Decodable {
  let id: Int64
  let login: String
  let name: String?
}

private struct GitHubEmail: Decodable {
  let email: String
  let primary: Bool
  let verified: Bool
}

private struct GoogleUserInfo: Decodable {
  let subject: String
  let email: String
  let emailVerified: Bool
  let name: String?

  private enum CodingKeys: String, CodingKey {
    case subject = "sub"
    case email
    case emailVerified = "email_verified"
    case name
  }
}

private struct DiscordUser: Decodable {
  let id: String
  let username: String
  let globalName: String?
  let email: String?
  let verified: Bool?

  private enum CodingKeys: String, CodingKey {
    case id
    case username
    case globalName = "global_name"
    case email
    case verified
  }
}
