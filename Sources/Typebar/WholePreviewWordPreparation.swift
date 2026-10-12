import Foundation

/// Cooperatively prepares finite native-generated words with their full initial
/// bound. Display admission stays explicit; other sources keep separate paths.
enum WholePreviewWordPreparation {
  /// Finite native previews prepare their actual target, including above the
  /// legacy synchronous ceiling. Preparation remains cancellable, not memory-bounded.
  static func usesAsyncPreparation(configuration: TestConfiguration, showAllLines: Bool) -> Bool {
    showAllLines && configuration.mode == .words && !configuration.isInfinite
      && (configuration.wordLimit ?? 0) > GeneratedPromptChunkPolicy.maximumInitialWordCount
      && configuration.visibleFutureWordCount == nil
      && LivePracticeContentSource.selected(for: configuration) == nil
  }

  @MainActor static func prepare(
    configuration: TestConfiguration, sourceWords: [String]? = nil,
    weakSpotScores: WeakSpotScores = .init(), wordDecorationState: PoolWordDecorationState = .init(),
    nextRandomWordIndex: () -> Int = { Int.random(in: Int.min...Int.max) },
    nextRandomCaseBit: () -> Bool = { Bool.random() },
    nextRandomContentUnit: () -> Double = { Double.random(in: 0..<1) },
    nextRandomPoolShuffleIndex: (Int) -> Int = { Int.random(in: 0..<$0) },
    didPrepare: (Int) -> Void = { _ in }
  ) async throws -> [GeneratedWordChunk] {
    try await prepareResult(configuration: configuration, sourceWords: sourceWords,
      weakSpotScores: weakSpotScores, wordDecorationState: wordDecorationState,
      nextRandomWordIndex: nextRandomWordIndex, nextRandomCaseBit: nextRandomCaseBit,
      nextRandomContentUnit: nextRandomContentUnit, nextRandomPoolShuffleIndex: nextRandomPoolShuffleIndex,
      didPrepare: didPrepare).chunks
  }

  /// Consumes already transformed targets exactly once. No continuation is
  /// needed: repeating the attempt restores the entire prepared opening.
  @MainActor static func prepareSession(
    configuration: TestConfiguration, sourceWords: [String]? = nil,
    weakSpotScores: WeakSpotScores = .init(), wordDecorationState: PoolWordDecorationState = .init(),
    nextRandomWordIndex: () -> Int = { Int.random(in: Int.min...Int.max) },
    nextRandomCaseBit: () -> Bool = { Bool.random() },
    nextRandomContentUnit: () -> Double = { Double.random(in: 0..<1) },
    nextRandomPoolShuffleIndex: (Int) -> Int = { Int.random(in: 0..<$0) },
    didPrepare: (Int) -> Void = { _ in }
  ) async throws -> TypingSession {
    let result = try await prepareResult(configuration: configuration, sourceWords: sourceWords,
      weakSpotScores: weakSpotScores, wordDecorationState: wordDecorationState,
      nextRandomWordIndex: nextRandomWordIndex, nextRandomCaseBit: nextRandomCaseBit,
      nextRandomContentUnit: nextRandomContentUnit, nextRandomPoolShuffleIndex: nextRandomPoolShuffleIndex,
      didPrepare: didPrepare)
    try Task.checkCancellation()
    let assembled = try await WholePreviewChunkAssembly.assemble(result.chunks)
    try Task.checkCancellation()
    let session = TypingSession(configuration: result.configuration,
      prompt: assembled.prompt,
      noSpaceWordEndIndices: assembled.endIndices,
      noSpaceTargetWords: assembled.targetWords,
      generationNotice: result.notice,
      weakSpotScores: weakSpotScores, wordDecorationState: result.decorationState)
    try Task.checkCancellation()
    return session
  }

  @MainActor private static func prepareResult(
    configuration: TestConfiguration, sourceWords: [String]?,
    weakSpotScores: WeakSpotScores, wordDecorationState: PoolWordDecorationState,
    nextRandomWordIndex: () -> Int, nextRandomCaseBit: () -> Bool,
    nextRandomContentUnit: () -> Double, nextRandomPoolShuffleIndex: (Int) -> Int,
    didPrepare: (Int) -> Void
  ) async throws -> (chunks: [GeneratedWordChunk], decorationState: PoolWordDecorationState,
    configuration: TestConfiguration, notice: String?) {
    try Task.checkCancellation()
    let preparation = PolyglotGenerationPreparation(configuration)
    var configuration = preparation.configuration
    // Fresh generation uses literal Dockerfile indentation; replay keeps the
    // captured configuration rather than preparing a historical attempt again.
    if configuration.language == .dockerFile { configuration.dockerfileUsesLiteralIndentation = true }
    guard configuration.mode == .words, let limit = configuration.wordLimit, limit > 0,
      configuration.visibleFutureWordCount == nil,
      LivePracticeContentSource.selected(for: configuration) == nil
    else { throw PreparationError.unsupportedConfiguration }
    if TypebarStreamContent.prompt(configuration: configuration, wordCount: 1) != nil {
      let chunks = try await prepareStream(configuration: configuration, limit: limit,
        nextRandomCaseBit: nextRandomCaseBit, didPrepare: didPrepare)
      return (chunks, wordDecorationState, configuration, preparation.notice)
    }
    var generator = GeneratedCodeContinuation(configuration: configuration, batchTokenCount: 100,
      weakSpotScores: weakSpotScores, sourceWords: sourceWords, decorationState: wordDecorationState,
      nextRandomPoolShuffleIndex: nextRandomPoolShuffleIndex)
    var chunks: [GeneratedWordChunk] = []
    var prepared = 0
    while prepared < limit {
      try Task.checkCancellation()
      let count = min(100, limit - prepared)
      let chunk = generator.nextChunk(maximumWordCount: count,
        initialPreparationWordBound: limit, nextRandomWordIndex: nextRandomWordIndex,
        nextRandomCaseBit: nextRandomCaseBit, nextRandomContentUnit: nextRandomContentUnit)
      guard !chunk.source.isEmpty else { throw PreparationError.emptyGeneration }
      chunks.append(chunk)
      prepared += count
      didPrepare(prepared)
      await Task.yield()
    }
    try Task.checkCancellation()
    return (chunks, generator.decorationState, configuration, preparation.notice)
  }

  enum PreparationError: Error { case emptyGeneration, unsupportedConfiguration }

  @MainActor private static func prepareStream(configuration: TestConfiguration, limit: Int,
    nextRandomCaseBit: () -> Bool, didPrepare: (Int) -> Void) async throws -> [GeneratedWordChunk] {
    let noSpace = TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
    var chunks: [GeneratedWordChunk] = []
    var prepared = 0
    var previousTarget: String?
    while prepared < limit {
      try Task.checkCancellation()
      let count = min(100, limit - prepared)
      guard let source = TypebarStreamContent.prompt(configuration: configuration,
        wordCount: count, startIndex: prepared) else { throw PreparationError.emptyGeneration }
      var output = ""
      var targets: [String] = []
      for (offset, word) in source.split(separator: " ").enumerated() {
        if previousTarget != nil, !noSpace, previousTarget?.hasSuffix("\n") != true { output.append(" ") }
        var target = TestModifierPolicy.transformedWord(configuration.language.presentationText(String(word)),
          modifiers: configuration.modifiers, language: configuration.language,
          wordIndex: prepared + offset, wordBound: limit, nextRandomCaseBit: nextRandomCaseBit)
        // Match the complete-prompt transform: only its final message commit
        // is removed, never a chunk boundary's newline.
        if prepared + offset == limit - 1, configuration.modifiers.contains(.messagingStyle),
          target.hasSuffix("\n") { target.removeLast() }
        output += target
        targets.append(target)
        previousTarget = target
      }
      chunks.append(.init(source: (prepared > 0 ? " " : "") + source,
        batch: .init(text: output, noSpaceTargetWords: noSpace ? targets : [])))
      prepared += count
      didPrepare(prepared)
      await Task.yield()
    }
    try Task.checkCancellation()
    return chunks
  }
}

/// Keeps the final merge cooperative too; the complete result still occupies
/// memory, and TypingSession construction remains a separate synchronous stage.
enum WholePreviewChunkAssembly {
  struct Result {
    let prompt: String
    let endIndices: [Int]
    let targetWords: [String]
  }

  @MainActor static func assemble(_ chunks: [GeneratedWordChunk],
    didAssemble: (Int) -> Void = { _ in }) async throws -> Result {
    try Task.checkCancellation()
    var prompt = "", endIndices: [Int] = [], targetWords: [String] = []
    var end = 0
    for (index, chunk) in chunks.enumerated() {
      try Task.checkCancellation()
      prompt += chunk.transformed
      for length in chunk.noSpaceWordLengths {
        end += length
        endIndices.append(end)
      }
      targetWords.append(contentsOf: chunk.noSpaceTargetWords)
      didAssemble(index + 1)
      await Task.yield()
    }
    try Task.checkCancellation()
    return .init(prompt: prompt, endIndices: endIndices, targetWords: targetWords)
  }
}
