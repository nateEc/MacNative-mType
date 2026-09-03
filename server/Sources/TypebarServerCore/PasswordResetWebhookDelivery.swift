import Foundation
import Vapor

public enum PasswordResetWebhookConfigurationError: LocalizedError {
  case invalidEndpoint

  public var errorDescription: String? {
    switch self {
    case .invalidEndpoint:
      "TYPEBAR_PASSWORD_RESET_WEBHOOK_URL must be an absolute HTTPS URL."
    }
  }
}

/// Builds an opt-in, provider-neutral account-email handoff from environment
/// settings. Password-reset delivery keeps its established `email`, opaque
/// `token`, and `expiresAt` payload; email verification adds a `kind` field.
/// The webhook is responsible for composing and delivering the email.
public enum PasswordResetWebhookDelivery {
  public static func fromEnvironment(
    endpoint: String? = Environment.get("TYPEBAR_PASSWORD_RESET_WEBHOOK_URL"),
    bearerToken: String? = Environment.get("TYPEBAR_PASSWORD_RESET_WEBHOOK_TOKEN")
  ) throws -> PasswordResetDeliveryHandler? {
    guard let handler = try makeAuthEmailWebhookHandler(
      endpoint: endpoint, bearerToken: bearerToken)
    else { return nil }
    return { delivery in
      try await handler(nil, delivery.email, delivery.token, delivery.expiresAt)
    }
  }
}

public enum EmailVerificationWebhookDelivery {
  public static func fromEnvironment(
    endpoint: String? = Environment.get("TYPEBAR_PASSWORD_RESET_WEBHOOK_URL"),
    bearerToken: String? = Environment.get("TYPEBAR_PASSWORD_RESET_WEBHOOK_TOKEN")
  ) throws -> EmailVerificationDeliveryHandler? {
    guard let handler = try makeAuthEmailWebhookHandler(
      endpoint: endpoint, bearerToken: bearerToken)
    else { return nil }
    return { delivery in
      try await handler(.emailVerification, delivery.email, delivery.token, delivery.expiresAt)
    }
  }
}

private enum AuthEmailWebhookKind: String, Encodable, Sendable {
  case emailVerification
}

private typealias AuthEmailWebhookHandler = @Sendable (
  AuthEmailWebhookKind?, String, String, Date
) async throws -> Void

private func makeAuthEmailWebhookHandler(
  endpoint: String?, bearerToken: String?
) throws -> AuthEmailWebhookHandler? {
  guard let endpoint, !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    return nil
  }
  guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https", url.host != nil else {
    throw PasswordResetWebhookConfigurationError.invalidEndpoint
  }
  let authorization = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines)
  return { kind, email, token, expiresAt in
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 10
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let authorization, !authorization.isEmpty {
      request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    request.httpBody = try encoder.encode(
      AuthEmailWebhookPayload(kind: kind, email: email, token: token, expiresAt: expiresAt))

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse,
      (200..<300).contains(response.statusCode)
    else { throw AuthEmailWebhookDeliveryError.unsuccessfulResponse }
  }
}

private struct AuthEmailWebhookPayload: Encodable, Sendable {
  let kind: AuthEmailWebhookKind?
  let email: String
  let token: String
  let expiresAt: Date
}

private enum AuthEmailWebhookDeliveryError: Error {
  case unsuccessfulResponse
}
