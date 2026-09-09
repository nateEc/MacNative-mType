import Foundation

enum ResultQuoteSourceKind: String, Codable, Equatable {
  case typebar
  case community

  var displayName: String {
    switch self {
    case .typebar: "Typebar 自有"
    case .community: "社区审核"
    }
  }

  var systemImage: String {
    switch self {
    case .typebar: "text.quote"
    case .community: "person.2"
    }
  }
}

/// Minimal, local-only source metadata captured when a quote session starts.
/// It deliberately excludes quote text, author account IDs and network state.
struct ResultQuoteSource: Codable, Equatable {
  static let maximumTitleLength = 80

  let kind: ResultQuoteSourceKind
  let title: String

  init?(kind: ResultQuoteSourceKind, title: String) {
    let normalized = title
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    guard !normalized.isEmpty else { return nil }
    self.kind = kind
    self.title = String(normalized.prefix(Self.maximumTitleLength))
  }

  private enum CodingKeys: String, CodingKey { case kind, title }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try values.decode(ResultQuoteSourceKind.self, forKey: .kind)
    let title = try values.decode(String.self, forKey: .title)
    guard let normalized = Self(kind: kind, title: title) else {
      throw DecodingError.dataCorruptedError(
        forKey: .title, in: values, debugDescription: "Quote source title is empty")
    }
    self = normalized
  }

  static func make(
    mode: TestMode, sourceIsCommunity: Bool, title: String?
  ) -> ResultQuoteSource? {
    guard mode == .quote, let title else { return nil }
    return .init(kind: sourceIsCommunity ? .community : .typebar, title: title)
  }

  var displayText: String { "\(kind.displayName) · \(title)" }
}

/// Identifies the quote that produced a completed result. This is captured
/// when the session starts so result actions cannot affect a later selection.
enum QuoteResultFeedbackTarget: Equatable {
  case builtIn(quoteID: String)
  case community(quoteID: UUID)

  static func make(
    mode: TestMode, sourceIsCommunity: Bool, selectedQuoteID: String
  ) -> QuoteResultFeedbackTarget? {
    guard mode == .quote else { return nil }
    let id = selectedQuoteID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return nil }

    if sourceIsCommunity {
      let rawID = id.hasPrefix("community-") ? String(id.dropFirst("community-".count)) : id
      guard let quoteID = UUID(uuidString: rawID) else { return nil }
      return .community(quoteID: quoteID)
    }
    return .builtIn(quoteID: id)
  }

  var communityQuoteID: UUID? {
    guard case let .community(quoteID) = self else { return nil }
    return quoteID
  }
}
