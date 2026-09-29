import Foundation

/// Reads only the `challenge` query item from a historical web URL. The host
/// is transport text, never a service endpoint: this type performs no I/O.
enum LegacyChallengeLinkImporter {
  enum ImportError: Error, Equatable, LocalizedError {
    case invalidLink
    case invalidPayload
    case unknownChallenge

    var errorDescription: String? {
      switch self {
      case .invalidLink: "挑战链接无效。"
      case .invalidPayload: "挑战链接必须只包含一个有效的挑战标识。"
      case .unknownChallenge: "此挑战尚未映射到本机 Typebar 挑战。"
      }
    }
  }

  private static let maximumLinkLength = 16_384
  private static let maximumIdentifierLength = 128
  private static let identifierLocale = Locale(identifier: "en_US_POSIX")

  /// Returns nil when the URL does not name a challenge, so callers can try
  /// another offline-only URL format such as testSettings.
  static func challenge(from link: String, challenges: [TypebarChallenge]) throws -> TypebarChallenge? {
    let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= maximumLinkLength,
      let components = URLComponents(string: trimmed),
      let scheme = components.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      components.host?.isEmpty == false
    else { throw ImportError.invalidLink }

    let values = (components.queryItems ?? []).filter { $0.name == "challenge" }
    guard !values.isEmpty else { return nil }
    // The fixed reference parser walks the query string from left to right and
    // keeps the final occurrence, so retain that observable URL behavior.
    guard let value = values.last?.value else { throw ImportError.invalidPayload }
    let identifier = normalizedIdentifier(value)
    guard !identifier.isEmpty, identifier.count <= maximumIdentifierLength else {
      throw ImportError.invalidPayload
    }

    guard let challenge = challenges.first(where: { candidate in
      normalizedIdentifier(candidate.id) == identifier
        || candidate.legacyURLNames.contains { normalizedIdentifier($0) == identifier }
    }) else { throw ImportError.unknownChallenge }
    return challenge
  }

  private static func normalizedIdentifier(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: identifierLocale)
  }
}
