import Foundation

/// Prepares finite pool-generated words cooperatively without changing their
/// initial-generation bound. Production admission/UI wiring remains separate.
enum WholePreviewWordPreparation {
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
    return TypingSession(configuration: configuration,
      prompt: result.chunks.map(\.transformed).joined(),
      noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(
        for: result.chunks.flatMap(\.noSpaceWordLengths)),
      noSpaceTargetWords: result.chunks.flatMap(\.noSpaceTargetWords),
      weakSpotScores: weakSpotScores, wordDecorationState: result.decorationState)
  }

  @MainActor private static func prepareResult(
    configuration: TestConfiguration, sourceWords: [String]?,
    weakSpotScores: WeakSpotScores, wordDecorationState: PoolWordDecorationState,
    nextRandomWordIndex: () -> Int, nextRandomCaseBit: () -> Bool,
    nextRandomContentUnit: () -> Double, nextRandomPoolShuffleIndex: (Int) -> Int,
    didPrepare: (Int) -> Void
  ) async throws -> (chunks: [GeneratedWordChunk], decorationState: PoolWordDecorationState) {
    try Task.checkCancellation()
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
    return (chunks, generator.decorationState)
  }

  enum PreparationError: Error { case emptyGeneration, unsupportedConfiguration }
}
