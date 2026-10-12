import Foundation

/// Prepares finite pool-generated words cooperatively without changing their
/// initial-generation bound. Production admission/UI wiring remains separate.
enum WholePreviewWordPreparation {
  @MainActor static func prepare(
    configuration: TestConfiguration, sourceWords: [String]? = nil,
    nextRandomWordIndex: () -> Int = { Int.random(in: Int.min...Int.max) },
    didPrepare: (Int) -> Void = { _ in }
  ) async throws -> [GeneratedWordChunk] {
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
    return chunks
  }

  enum PreparationError: Error { case emptyGeneration, unsupportedConfiguration }
}
