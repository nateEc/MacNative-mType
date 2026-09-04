import Foundation

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
      guard let quoteID = UUID(uuidString: id) else { return nil }
      return .community(quoteID: quoteID)
    }
    return .builtIn(quoteID: id)
  }

  var communityQuoteID: UUID? {
    guard case let .community(quoteID) = self else { return nil }
    return quoteID
  }
}
