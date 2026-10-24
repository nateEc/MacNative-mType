/// Attempt-local lifecycle state, never a configuration field or archive key.
enum WebsitePracticeRepetition: Equatable {
  case none
  case sameWordset(repeatedPace: Bool)

  var repeatsWordset: Bool {
    if case .sameWordset = self { return true }
    return false
  }
  var repeatsPace: Bool {
    if case .sameWordset(let value) = self { return value }
    return false
  }
}

/// Selection after admission/entry guards, not a complete restart lifecycle.
enum WebsiteConfigRestartPolicy {
  static func resolve(requested: Bool, active: Bool, previouslyRepeated: Bool,
    failed: Bool, mode: TestMode, language: String, quoteLanguage: String?,
    repeatQuotes: Bool, repeatedPace: Bool) -> WebsitePracticeRepetition {
    let matchingQuote = quoteLanguage.map { language.utf16.starts(with: $0.utf16) } ?? false
    let repeatQuote = mode == .quote && matchingQuote && repeatQuotes && (active || failed)
    return requested || active && previouslyRepeated || repeatQuote
      ? .sameWordset(repeatedPace: repeatedPace) : .none
  }
}
