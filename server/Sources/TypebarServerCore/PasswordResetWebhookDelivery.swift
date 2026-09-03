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

/// Builds an opt-in, provider-neutral reset-email handoff from environment
/// settings. The trusted webhook receives `email`, `token`, and `expiresAt`,
/// and is responsible for composing and delivering the actual email. Keeping
/// provider-specific credentials outside this service makes the reset flow
/// usable for self-hosted installations without bundling a mail vendor SDK.
public enum PasswordResetWebhookDelivery {
  public static func fromEnvironment(
    endpoint: String? = Environment.get("TYPEBAR_PASSWORD_RESET_WEBHOOK_URL"),
    bearerToken: String? = Environment.get("TYPEBAR_PASSWORD_RESET_WEBHOOK_TOKEN")
  ) throws -> PasswordResetDeliveryHandler? {
    guard let endpoint, !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https", url.host != nil else {
      throw PasswordResetWebhookConfigurationError.invalidEndpoint
    }
    let authorization = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines)
    return { delivery in
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
      request.httpBody = try encoder.encode(WebhookPayload(delivery: delivery))

      let (_, response) = try await URLSession.shared.data(for: request)
      guard let response = response as? HTTPURLResponse,
        (200..<300).contains(response.statusCode)
      else { throw PasswordResetWebhookDeliveryError.unsuccessfulResponse }
    }
  }

  private struct WebhookPayload: Encodable, Sendable {
    let email: String
    let token: String
    let expiresAt: Date

    init(delivery: PasswordResetDelivery) {
      email = delivery.email
      token = delivery.token
      expiresAt = delivery.expiresAt
    }
  }
}

private enum PasswordResetWebhookDeliveryError: Error {
  case unsuccessfulResponse
}
