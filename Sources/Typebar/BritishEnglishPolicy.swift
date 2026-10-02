import Foundation

/// A native word-stage spelling policy. Independently authored spelling
/// families extend Typebar's British vocabulary without importing a table.
/// Unknown words deliberately remain unchanged; this is not dictionary parity.
enum BritishEnglishPolicy {
  struct Context {
    let enabled: Bool
    let isQuote: Bool

    init(configuration: TestConfiguration, authoredQuoteAlternate: Bool = false) {
      isQuote = configuration.mode == .quote
      enabled = configuration.englishVariant == .british && supportsWordConversion(in: configuration.language)
        && configuration.mode != .zen && !(isQuote && authoredQuoteAlternate)
    }
  }

  static func supportsWordConversion(in language: TypingLanguage) -> Bool {
    switch language {
    case .english, .english1k, .english5k, .english10k, .english25k, .english450k,
      .englishCommonlyMisspelled, .englishContractions, .englishDoubleLetter,
      .englishLegal, .englishMedical, .englishShakespearean, .oldEnglish:
      return true
    default:
      // Wordle and Pig Latin have English-derived content but their source
      // identities do not enable the reference English conversion stage.
      return false
    }
  }

  static func transformed(_ word: String, context: Context?, previousWord: String? = nil) -> String {
    guard let context, context.enabled else { return word }
    let quoted = word.replacingOccurrences(of: "\"", with: "'")
    // Empty hyphen components carry punctuation, not missing-word errors.
    return quoted.unicodeScalars.split(separator: "-", omittingEmptySubsequences: false)
      .map { component in
        transformComponent(String(String.UnicodeScalarView(component)),
          isQuote: context.isQuote, previousWord: previousWord)
      }.joined(separator: "-")
  }

  static func previousWordKey(_ word: String) -> String {
    // A single quote, newline or other Unicode scalar is not in this set.
    String(String.UnicodeScalarView(word.unicodeScalars.filter {
      ![0x2E, 0x3F, 0x21, 0x22, 0x3A, 0x2D, 0x2C].contains($0.value)
    })).lowercased()
  }

  private static func transformComponent(_ word: String, isQuote: Bool, previousWord: String?) -> String {
    let scalars = Array(word.unicodeScalars)
    func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
      let value = scalar.value
      return (65...90).contains(value) || (97...122).contains(value)
        || (48...57).contains(value) || value == 95
    }
    guard let start = scalars.firstIndex(where: isWordScalar),
      let end = scalars.lastIndex(where: isWordScalar) else { return word }
    let body = String(String.UnicodeScalarView(scalars[start...end]))
    let key = body.lowercased()
    guard !(isQuote && key == "tire" && previousWord == "will"),
      let spelling = ownedSpelling(key) else { return word }
    let replacement: String
    if body == body.uppercased() {
      replacement = spelling.uppercased()
    } else if let first = body.first, first.isUppercase {
      replacement = String(spelling.prefix(1)).uppercased() + spelling.dropFirst()
    } else {
      replacement = spelling
    }
    return String(String.UnicodeScalarView(scalars[..<start])) + replacement
      + String(String.UnicodeScalarView(scalars[(end + 1)...]))
  }

  private static func ownedSpelling(_ word: String) -> String? {
    // Whole-word allowlists avoid general suffix guesses (for example, not
    // every -or gains a u, nor does every -er become -re). These ordinary
    // spelling families are independent of the reference dictionary corpus.
    switch word {
    case "color", "favor", "labor", "neighbor": return word.dropLast() + "ur"
    case "center", "theater": return word.dropLast(2) + "re"
    case "catalog": return word + "ue"
    case "organize", "realize", "recognize": return word.dropLast(2) + "se"
    case "traveler": return word.dropLast(2) + "ler"
    case "license": return word.dropLast(2) + "ce"
    case "gray": return word.dropLast(2) + "ey"
    case "tire": return "tyre"
    default: return nil
    }
  }
}
