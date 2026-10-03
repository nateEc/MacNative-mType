import Foundation

/// Whole owned candidates: first occurrence owns order, last occurrence owns
/// language metadata. UTF-16 keys deliberately keep canonically equivalent
/// spellings distinct, just like the reference's string-keyed word map.
struct NativePolyglotCandidates {
  private(set) var lexicon: IndexedLexicon
  private let languages: [[UInt16]: TypingLanguage]

  init(sources: [(TypingLanguage, IndexedLexicon)],
    reversingPrimaryLanguage: TypingLanguage? = nil,
    nextShuffleIndex: (Int) -> Int = { Int.random(in: 0..<$0) }) {
    var words: [String] = [], owners: [[UInt16]: TypingLanguage] = [:]
    for (language, source) in sources {
      for word in IndexedLexicon.ordered(source, reversed: language == reversingPrimaryLanguage) {
        let key = Array(word.utf16)
        if owners[key] == nil { words.append(word) }
        owners[key] = language
      }
    }
    if words.count > 1 {
      for index in stride(from: words.count - 1, through: 1, by: -1) {
        words.swapAt(index, nextShuffleIndex(index + 1))
      }
    }
    lexicon = IndexedLexicon(words)
    languages = owners
  }

  init(configuration: TestConfiguration, nextShuffleIndex: (Int) -> Int) {
    self.init(sources: configuration.mixedLanguageComponents.map { language in
      let words = OrdinaryEntryContent.pool(for: language)
        ?? (language.isCodeLanguage ? IndexedLexicon(CodePracticeContent.wordCandidates(for: language))
          : language.ownedPracticeLexicon(englishVariant: .american))
      return (language, words)
    }, reversingPrimaryLanguage: configuration.modifiers.contains(.backwards) ? configuration.wordPoolBaseLanguage : nil,
      nextShuffleIndex: nextShuffleIndex)
  }

  func reshuffled(nextShuffleIndex: (Int) -> Int) -> Self {
    var copy = self
    var words = lexicon.materialized()
    if words.count > 1 {
      for index in stride(from: words.count - 1, through: 1, by: -1) {
        words.swapAt(index, nextShuffleIndex(index + 1))
      }
    }
    copy.lexicon = IndexedLexicon(words)
    return copy
  }

  func language(for word: String) -> TypingLanguage? { languages[Array(word.utf16)] }

  /// A split or lowercased word absent from the original whole-candidate map
  /// has no Lazy properties; it must not inherit the pool's primary language.
  func lazyWord(_ word: String) -> String {
    guard let language = language(for: word) else { return word }
    return TypingTextNormalizer.lazyLatin(word, language: language)
  }
}
