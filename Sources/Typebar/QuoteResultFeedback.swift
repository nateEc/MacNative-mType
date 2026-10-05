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

/// Minimal source metadata captured when a quote session starts.
/// It deliberately excludes quote text, author account IDs and network state.
struct ResultQuoteSource: Codable, Equatable {
  static let maximumTitleLength = 80

  let kind: ResultQuoteSourceKind
  let title: String
  let quoteID: String?
  var mode2: String? { quoteID.flatMap { ResultMode2Policy.quoteKey(kind: kind, id: $0) } }

  init?(kind: ResultQuoteSourceKind, title: String, quoteID: String? = nil) {
    let normalized = title
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    guard !normalized.isEmpty else { return nil }
    guard quoteID.map({ ResultMode2Policy.quoteKey(kind: kind, id: $0) != nil }) ?? true else { return nil }
    self.kind = kind
    self.title = String(normalized.prefix(Self.maximumTitleLength))
    self.quoteID = quoteID
  }

  enum CodingKeys: String, CodingKey { case kind, title, quoteID }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try values.decode(ResultQuoteSourceKind.self, forKey: .kind)
    let title = try values.decode(String.self, forKey: .title)
    let id = values.contains(.quoteID) ? try values.decode(String.self, forKey: .quoteID) : nil
    guard let normalized = Self(kind: kind, title: title, quoteID: id) else {
      throw DecodingError.dataCorruptedError(
        forKey: .title, in: values, debugDescription: "Quote source title or identity is invalid")
    }
    self = normalized
  }

  static func make(
    mode: TestMode, sourceIsCommunity: Bool, title: String?, selectedQuoteID: String? = nil
  ) -> ResultQuoteSource? {
    guard mode == .quote, let title else { return nil }
    let kind: ResultQuoteSourceKind = sourceIsCommunity ? .community : .typebar
    if let selectedQuoteID {
      guard let target = QuoteResultFeedbackTarget.make(mode: mode, sourceIsCommunity: sourceIsCommunity,
        selectedQuoteID: selectedQuoteID) else { return nil }
      let id: String
      switch target {
      case .builtIn(let quoteID): id = quoteID
      case .community(let quoteID): id = quoteID.uuidString.lowercased()
      }
      return .init(kind: kind, title: title, quoteID: id)
    }
    return .init(kind: kind, title: title)
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
