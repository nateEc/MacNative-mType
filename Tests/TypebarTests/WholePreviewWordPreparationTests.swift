import XCTest
@testable import Typebar

@MainActor final class WholePreviewWordPreparationTests: XCTestCase {
  func testPreparedSessionPreservesExactTargetsAndRepeatWithoutRegeneration() async throws {
    for modifiers: [TestModifier] in [[], [.underscoreSeparators], [.noSpaces]] {
      let configuration = TestConfiguration.words(201, language: .codeSwift).with(modifiers: modifiers)
      var generator = GeneratedCodeContinuation(configuration: configuration, batchTokenCount: 201,
        showAllLines: true, sourceWords: ["north", "harbor"])
      let expected = generator.nextChunk(nextRandomWordIndex: { 0 })
      var draws = 0
      var session = try await WholePreviewWordPreparation.prepareSession(configuration: configuration,
        sourceWords: ["north", "harbor"], nextRandomWordIndex: { draws += 1; return 0 })
      XCTAssertEqual(session.prompt, expected.transformed)
      XCTAssertEqual(session.configuration, configuration)
      XCTAssertFalse(session.hasStarted)
      XCTAssertNil(session.generationNotice)
      let drawsAfterPreparation = draws
      var repeated = session.repeatedAttempt()
      XCTAssertEqual(repeated.prompt, expected.transformed)
      XCTAssertEqual(draws, drawsAfterPreparation)
      let start = Date(timeIntervalSince1970: 100)
      for character in expected.transformed.dropLast() {
        session.insertBatch(String(character), at: start)
      }
      XCTAssertFalse(session.isFinished)
      session.insertBatch(String(expected.transformed.suffix(1)), at: start.addingTimeInterval(2))
      XCTAssertTrue(session.isFinished)
      repeated.insertBatch(expected.transformed, at: start)
      XCTAssertTrue(repeated.isFinished)
    }
  }

  func testNonPoolConfigurationsAreRejectedBeforeAnyDraw() async {
    for configuration in [TestConfiguration.timed(seconds: 30), .words(0),
      .words(3).with(modifiers: [.binaryStream]), .words(3).with(modifiers: [.poetryStream])] {
      var draws = 0
      do {
        _ = try await WholePreviewWordPreparation.prepare(configuration: configuration,
          nextRandomWordIndex: { draws += 1; return 0 })
        XCTFail("Unsupported preparation must not substitute pool words")
      } catch {}
      XCTAssertEqual(draws, 0)
    }
  }

  func testBatchedPreparationMatchesSingleInitialGenerationAcrossCommitBoundaries() async throws {
    for modifiers: [TestModifier] in [[], [.underscoreSeparators], [.noSpaces]] {
      let configuration = TestConfiguration.words(701, language: .codeSwift).with(modifiers: modifiers)
      var reference = GeneratedCodeContinuation(configuration: configuration, batchTokenCount: 701,
        showAllLines: true, sourceWords: ["north", "harbor"])
      let expected = reference.nextChunk(nextRandomWordIndex: { 0 })
      var counts: [Int] = []
      let chunks = try await WholePreviewWordPreparation.prepare(configuration: configuration,
        sourceWords: ["north", "harbor"], nextRandomWordIndex: { 0 },
        didPrepare: { counts.append($0) })
      XCTAssertEqual(counts, [100, 200, 300, 400, 500, 600, 700, 701])
      XCTAssertEqual(chunks.map(\.source).joined(), expected.source)
      XCTAssertEqual(chunks.map(\.transformed).joined(), expected.transformed)
      XCTAssertEqual(chunks.flatMap(\.noSpaceTargetWords), expected.noSpaceTargetWords)
    }
  }

  func testAboveOldCeilingPreparesTheEntireTarget() async throws {
    let configuration = TestConfiguration.words(100_001, language: .codeSwift)
      .with(modifiers: [.underscoreSeparators])
    let chunks = try await WholePreviewWordPreparation.prepare(configuration: configuration,
      sourceWords: ["north"], nextRandomWordIndex: { 0 })
    XCTAssertEqual(chunks.count, 1001)
    let targets = chunks.map(\.transformed).joined()
    XCTAssertEqual(targets, String(repeating: "north_", count: 100_000) + "north")
  }

  func testCancellationStopsHugePreparationAtTheNextBatchBoundary() async throws {
    var counts: [Int] = []
    let task = Task { @MainActor in
      try await WholePreviewWordPreparation.prepare(
        configuration: .words(OfficialTestLimitInput.maximumValue, language: .codeSwift),
        sourceWords: ["north"], nextRandomWordIndex: { 0 }, didPrepare: {
          counts.append($0)
          withUnsafeCurrentTask { $0?.cancel() }
        })
    }
    do {
      _ = try await task.value
      XCTFail("Cancelled preparation must not publish a partial result")
    } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertEqual(counts, [100])
  }
}
