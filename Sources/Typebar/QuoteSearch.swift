import Foundation

/// Device-local search over Typebar-owned or already-loaded quote text.
/// The query never leaves the process and searches every whitespace-separated
/// term so a narrow search remains predictable for multilingual content.
enum QuoteSearch {
  static func filtered(_ quotes: [OfflineQuote], query: String) -> [OfflineQuote] {
    let terms = normalizedTerms(in: query)
    guard !terms.isEmpty else { return quotes }
    return quotes.filter { quote in
      let haystack = normalized(quote.title + " " + quote.text)
      return terms.allSatisfy(haystack.contains)
    }
  }

  private static func normalizedTerms(in query: String) -> [String] {
    query.split(whereSeparator: \Character.isWhitespace).map { normalized(String($0)) }
      .filter { !$0.isEmpty }
  }

  private static func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
  }
}
