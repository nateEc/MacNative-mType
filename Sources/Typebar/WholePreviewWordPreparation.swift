import Foundation

/// Prepares finite pool-generated words cooperatively without changing their
/// initial-generation bound. Production admission/UI wiring remains separate.
enum WholePreviewWordPreparation {
  @MainActor static func prepare(
    configuration: TestConfiguration, sourceWords: [String]? = nil,
    nextRandomWordIndex: () -> Int = { Int.random(in: Int.min...Int.max) },
    didPrepare: (Int) -> Void = { _ in }
  ) async throws -> [GeneratedWordChunk] {
    try await prepareResult(configuration: configuration, sourceWords: sourceWords,
      nextRandomWordIndex: nextRandomWordIndex, didPrepare: didPrepare).chunks
  }

  /// Consumes already transformed targets exactly once. No continuation is
  /// needed: repeating the attempt restores the entire prepared opening.
  @MainActor static func prepareSession(
    configuration: TestConfiguration, sourceWords: [String]? = nil,
    nextRandomWordIndex: () -> Int = { Int.random(in: Int.min...Int.max) },
    didPrepare: (Int) -> Void = { _ in }
  ) async throws -> TypingSession {
    let result = try await prepareResult(configuration: configuration, sourceWords: sourceWords,
      nextRandomWordIndex: nextRandomWordIndex, didPrepare: didPrepare)
    try Task.checkCancellation()
    return TypingSession(configuration: configuration,
      prompt: result.chunks.map(\.transformed).joined(),
      noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(
        for: result.chunks.flatMap(\.noSpaceWordLengths)),
      noSpaceTargetWords: result.chunks.flatMap(\.noSpaceTargetWords),
      wordDecorationState: result.decorationState)
  }

  @MainActor private static func prepareResult(
    configuration: TestConfiguration, sourceWords: [String]?,
    nextRandomWordIndex: () -> Int, didPrepare: (Int) -> Void
  ) async throws -> (chunks: [GeneratedWordChunk], decorationState: PoolWordDecorationState) {
    try Task.checkCancellation()
    guard configuration.mode == .words, let limit = configuration.wordLimit, limit > 0,
      configuration.visibleFutureWordCount == nil,
      LivePracticeContentSource.selected(for: configuration) == nil,
      TypebarStreamContent.prompt(configuration: configuration, wordCount: 1) == nil
    else { throw PreparationError.unsupportedConfiguration }
    var generator = GeneratedCodeContinuation(configuration: configuration, batchTokenCount: 100,
      sourceWords: sourceWords)
    var chunks: [GeneratedWordChunk] = []
    var prepared = 0
    while prepared < limit {
      try Task.checkCancellation()
      let count = min(100, limit - prepared)
      let chunk = generator.nextChunk(maximumWordCount: count,
        initialPreparationWordBound: limit, nextRandomWordIndex: nextRandomWordIndex)
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
