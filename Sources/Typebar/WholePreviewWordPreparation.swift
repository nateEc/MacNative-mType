import Foundation

/// Cooperatively prepares finite pool-generated words with their full initial
/// bound. Display admission stays explicit; other sources keep separate paths.
enum WholePreviewWordPreparation {
  /// Finite pool previews prepare their actual target, including above the
  /// legacy synchronous ceiling. Preparation remains cancellable, not memory-bounded.
  static func usesAsyncPreparation(configuration: TestConfiguration, showAllLines: Bool) -> Bool {
    showAllLines && configuration.mode == .words && !configuration.isInfinite
      && (configuration.wordLimit ?? 0) > GeneratedPromptChunkPolicy.maximumInitialWordCount
      && configuration.visibleFutureWordCount == nil
      && LivePracticeContentSource.selected(for: configuration) == nil
      && TypebarStreamContent.prompt(configuration: configuration, wordCount: 1) == nil
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
    return TypingSession(configuration: result.configuration,
      prompt: result.chunks.map(\.transformed).joined(),
      noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(
        for: result.chunks.flatMap(\.noSpaceWordLengths)),
      noSpaceTargetWords: result.chunks.flatMap(\.noSpaceTargetWords),
      generationNotice: result.notice,
      weakSpotScores: weakSpotScores, wordDecorationState: result.decorationState)
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
      LivePracticeContentSource.selected(for: configuration) == nil,
      TypebarStreamContent.prompt(configuration: configuration, wordCount: 1) == nil
    else { throw PreparationError.unsupportedConfiguration }
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
}
