import Foundation

/// Preparation primitive for the factory's ordered live-source contract.
/// Integration must preserve initial-prompt/random-bit ordering; this is not
/// a replacement for arbitrary standalone finite-text transformation.
enum LivePromptTransformation {
  @MainActor static func prepare(_ source: String, configuration: TestConfiguration,
    preservesNoSpaceBoundaries: Bool, wordOffset: Int, wordBound: Int,
    preservesWordOrder: Bool = true,
    nextRandomCaseBit: () -> Bool = { Bool.random() },
    batchCheckpoint: ((Int) async -> Void)? = nil,
    didScanSource: (Int) -> Void = { _ in },
    didTransform: (Int) -> Void = { _ in }) async throws -> TransformedPromptBatch {
    try Task.checkCancellation()
    let modifiers = configuration.modifiers
    let language = configuration.language
    // Swiss German's ß expansion preserves ASCII word boundaries and is
    // applied by transformedWord. Scan the original scalars so cancellation
    // can interrupt long sources before constructing their presented text.
    var words = try await sourceWords(source, didScan: didScanSource)
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
        modifiers: modifiers, language: language, websiteOrder: configuration.websiteTextAlterationOrder,
        wordIndex: wordIndex, wordBound: wordBound,
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
        if let batchCheckpoint { await batchCheckpoint(index + 1) }
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

  @MainActor private static func sourceWords(_ presented: String,
    didScan: (Int) -> Void) async throws -> [String] {
    try Task.checkCancellation()
    var words: [String] = [], field = "", scanned = 0
    for scalar in presented.unicodeScalars {
      if scalar.value == 0x20 {
        words.append(field)
        field = ""
      } else {
        field.unicodeScalars.append(scalar)
      }
      scanned += 1
      if scanned.isMultiple(of: 4096) {
        didScan(scanned)
        await Task.yield()
        try Task.checkCancellation()
      }
    }
    // Like split(omittingEmptySubsequences: false), retain the final empty
    // field after a separator and the sole empty field of an empty source.
    words.append(field)
    if scanned == 0 || !scanned.isMultiple(of: 4096) {
      didScan(scanned)
      await Task.yield()
    }
    try Task.checkCancellation()
    return words
  }
}
