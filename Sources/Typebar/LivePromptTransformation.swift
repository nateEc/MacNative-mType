import Foundation

/// Preparation primitive for the factory's ordered live-source contract.
/// Integration must preserve initial-prompt/random-bit ordering; this is not
/// a replacement for arbitrary standalone finite-text transformation.
enum LivePromptTransformation {
  @MainActor static func prepare(_ source: String, configuration: TestConfiguration,
    preservesNoSpaceBoundaries: Bool, wordOffset: Int, wordBound: Int,
    preservesWordOrder: Bool = true,
    nextRandomCaseBit: () -> Bool = { Bool.random() },
    didTransform: (Int) -> Void = { _ in }) async throws -> TransformedPromptBatch {
    try Task.checkCancellation()
    let modifiers = configuration.modifiers
    let language = configuration.language
    let presented = language.presentationText(source)
    var words = presented.unicodeScalars.split(separator: " ", omittingEmptySubsequences: false)
      .map { String(String.UnicodeScalarView($0)) }
    if modifiers.contains(.backwards), !preservesWordOrder { words.reverse() }
    let capturesTargets = TestModifierPolicy.usesNoSpaceInput(modifiers) || preservesNoSpaceBoundaries
    let britishEnglish = BritishEnglishPolicy.Context(configuration: configuration, authoredQuoteAlternate: false)
    var output = ""
    var targets: [String] = []
    var fields: [String] = []
    var wordIndex = wordOffset
    var previousBritishWord: String?
    for (index, word) in words.enumerated() {
      try Task.checkCancellation()
      let altered = word.isEmpty ? "" : TestModifierPolicy.transformedWord(word,
        modifiers: modifiers, language: language, wordIndex: wordIndex, wordBound: wordBound,
        britishEnglish: britishEnglish, previousBritishWord: previousBritishWord,
        nextRandomCaseBit: nextRandomCaseBit)
      if !word.isEmpty, britishEnglish.isQuote {
        previousBritishWord = BritishEnglishPolicy.previousWordKey(altered)
      }
      if !word.isEmpty { wordIndex += 1 }
      var field = altered
      output += altered
      if capturesTargets, !word.isEmpty { targets.append(altered) }
      if index < words.count - 1, !capturesTargets, altered.unicodeScalars.last != "\n" {
        output.append(" ")
        field.append(" ")
      }
      if !field.isEmpty { fields.append(field) }
      if (index + 1).isMultiple(of: 100) || index == words.count - 1 {
        didTransform(index + 1)
        await Task.yield()
      }
    }
    try Task.checkCancellation()
    if modifiers.contains(.messagingStyle), output.hasSuffix("\n") {
      output.removeLast()
      if capturesTargets, targets.last?.hasSuffix("\n") == true {
        targets[targets.count - 1].removeLast()
      }
      if fields.last?.hasSuffix("\n") == true {
        fields[fields.count - 1].removeLast()
        if fields.last?.isEmpty == true { fields.removeLast() }
      }
    }
    let result = TransformedPromptBatch(text: output, noSpaceTargetWords: targets, sourceFields: fields)
    try Task.checkCancellation()
    return result
  }
}
