import XCTest
@testable import Typebar

@MainActor final class LiveSessionPreparationTests: XCTestCase {
  func testInitialTransformationCanCancelBeforeSessionPublicationWithoutContinuation() async {
    var batches: [Int] = []
    let task = Task<Void, Error> { @MainActor in
      _ = try await TestSessionFactory.preparingLiveSession(
        configuration: .words(301).with(modifiers: [.poetryStream]),
        prompt: .init(text: Array(repeating: "harbor", count: 301).joined(separator: " "),
          noSpaceBoundarySource: nil), continuation: nil, showAllLines: true,
        didTransformInitial: {
          batches.append($0)
          withUnsafeCurrentTask { $0?.cancel() }
        })
    }
    do { _ = try await task.value; XCTFail("Initial transformation cancellation must reject publication") }
    catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertEqual(batches, [100])
  }

  func testPreparedSessionMatchesSynchronousWindowRandomSequenceConsumptionAndReplay() async throws {
    for base in [TestConfiguration.words(301), .words(0), .timed(seconds: 30)] {
      for modifiers: [TestModifier] in [[], [.randomCase], [.underscoreSeparators], [.noSpaces],
        [.messagingStyle], [.randomCase, .underscoreSeparators]] {
        let configuration = base.with(modifiers: [.poetryStream] + modifiers)
        let prompt = LivePracticePrompt(text: "north harbor morning", noSpaceBoundarySource: nil)
        let tail = LivePracticePrompt(text: "south river evening\n returning", noSpaceBoundarySource: nil)
        var oldDraws = 0, newDraws = 0
        var expected = TestSessionFactory.make(configuration: configuration, streamPrompt: prompt.text,
          streamContinuation: tail, streamsLiveContent: true,
          nextRandomCaseBit: { oldDraws += 1; return oldDraws.isMultiple(of: 3) })
        var actual = try await TestSessionFactory.preparingLiveSession(configuration: configuration,
          prompt: prompt, continuation: tail,
          nextRandomCaseBit: { newDraws += 1; return newDraws.isMultiple(of: 3) })
        XCTAssertEqual(actual.prompt.utf8.map { $0 }, expected.prompt.utf8.map { $0 })
        XCTAssertEqual(actual.generationNotice, expected.generationNotice)
        XCTAssertEqual(newDraws, oldDraws)
        let input = String(expected.prompt.prefix(16))
        let date = Date(timeIntervalSince1970: 1000)
        expected.insertBatch(input, at: date)
        actual.insertBatch(input, at: date)
        XCTAssertEqual(actual.prompt.utf8.map { $0 }, expected.prompt.utf8.map { $0 })
        XCTAssertEqual(actual.outcome, expected.outcome)
        XCTAssertEqual(actual.preciseAccuracy, expected.preciseAccuracy)
        XCTAssertEqual(actual.repeatedAttempt().prompt, expected.repeatedAttempt().prompt)
      }
    }
  }

  func testInitialCooperativePassPreservesLegacyOrderingBoundsAndRandomDraws() async throws {
    let prompts: [LivePracticePrompt] = [
      .init(text: "  north river \u{301}harbor a\nb  ", noSpaceBoundarySource: nil),
      .init(text: "northharbor", noSpaceBoundarySource: "north harbor"),
      .init(text: "north harbor", noSpaceBoundarySource: "unmatched boundary"),
      .init(text: "", noSpaceBoundarySource: nil),
    ]
    for prompt in prompts {
      for allLines in [false, true] {
        for modifiers: [TestModifier] in [[], [.backwards], [.backwards, .randomCase],
          [.underscoreSeparators, .randomCase], [.messagingStyle, .noSpaces]] {
          let configuration = TestConfiguration.words(301).with(modifiers: [.poetryStream] + modifiers)
          var oldDraws = 0, newDraws = 0
          let expected = TestSessionFactory.make(configuration: configuration, streamPrompt: prompt.text,
            streamNoSpaceBoundarySource: prompt.noSpaceBoundarySource, streamsLiveContent: true,
            showAllLines: allLines, nextRandomCaseBit: { oldDraws += 1; return oldDraws.isMultiple(of: 3) })
          let actual = try await TestSessionFactory.preparingLiveSession(configuration: configuration,
            prompt: prompt, continuation: nil, showAllLines: allLines,
            nextRandomCaseBit: { newDraws += 1; return newDraws.isMultiple(of: 3) })
          XCTAssertEqual(Array(actual.prompt.utf8), Array(expected.prompt.utf8), "\(modifiers), \(prompt)")
          XCTAssertEqual(actual.promptWordPresentations.map(\.range), expected.promptWordPresentations.map(\.range))
          XCTAssertEqual(newDraws, oldDraws, "Initial legacy two-pass draw order must remain unchanged")
        }
      }
    }
  }

  func testLargeInitialPromptTransformsEveryFieldInBatchesWithoutContinuation() async throws {
    var batches: [Int] = []
    let source = Array(repeating: "harbor", count: 100_001).joined(separator: " ")
    let actual = try await TestSessionFactory.preparingLiveSession(
      configuration: .words(100_001).with(modifiers: [.poetryStream]),
      prompt: .init(text: source, noSpaceBoundarySource: nil), continuation: nil, showAllLines: true,
      didTransformInitial: { batches.append($0) })
    XCTAssertEqual(batches.count, 1001)
    XCTAssertEqual(batches.last, 100_001)
    XCTAssertEqual(actual.prompt.trimmingCharacters(in: .whitespaces), source)
  }

  func testCancelledTailPreparationDoesNotReturnPublishableSession() async {
    let task = Task<Void, Error> { @MainActor in
      _ = try await TestSessionFactory.preparingLiveSession(
        configuration: .words(1001).with(modifiers: [.poetryStream]),
        prompt: .init(text: "north", noSpaceBoundarySource: nil),
        continuation: .init(text: Array(repeating: "harbor", count: 1000).joined(separator: " "),
          noSpaceBoundarySource: nil), didTransform: { _ in withUnsafeCurrentTask { $0?.cancel() } })
    }
    do { _ = try await task.value; XCTFail("Cancelled session preparation must not publish") }
    catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
  }

  func testUnseparatedSourceAndEmptyContinuationPreserveSynchronousSemantics() async throws {
    for continuation: LivePracticePrompt? in [nil,
      .init(text: "", noSpaceBoundarySource: nil),
      .init(text: "riversouth", noSpaceBoundarySource: "river south")] {
      let configuration = TestConfiguration.words(0).with(modifiers: [.poetryStream])
      let prompt = LivePracticePrompt(text: "northharbor", noSpaceBoundarySource: "north harbor")
      var expected = TestSessionFactory.make(configuration: configuration, streamPrompt: prompt.text,
        streamNoSpaceBoundarySource: prompt.noSpaceBoundarySource, streamContinuation: continuation,
        streamsLiveContent: true)
      var actual = try await TestSessionFactory.preparingLiveSession(configuration: configuration,
        prompt: prompt, continuation: continuation)
      XCTAssertEqual(actual.prompt, expected.prompt)
      expected.insertBatch("north", at: Date(timeIntervalSince1970: 1000))
      actual.insertBatch("north", at: Date(timeIntervalSince1970: 1000))
      XCTAssertEqual(actual.prompt, expected.prompt)
      XCTAssertEqual(actual.preciseAccuracy, expected.preciseAccuracy)
      XCTAssertEqual(actual.repeatedAttempt().prompt, expected.repeatedAttempt().prompt)
    }
  }

  func testLargeFactoryTailIsPreparedInCooperativeBatches() async throws {
    let configuration = TestConfiguration.words(100_101).with(modifiers: [.poetryStream])
    let prompt = LivePracticePrompt(text: Array(repeating: "start", count: 100).joined(separator: " "),
      noSpaceBoundarySource: nil)
    let tail = LivePracticePrompt(text: (0..<100_001).map { "owned\($0)" }.joined(separator: " "),
      noSpaceBoundarySource: nil)
    var batches: [Int] = []
    var actual = try await TestSessionFactory.preparingLiveSession(configuration: configuration,
      prompt: prompt, continuation: tail, didTransform: { batches.append($0) })
    XCTAssertEqual(batches.count, 1001)
    XCTAssertEqual(batches.last, 100_001)
    XCTAssertEqual(actual.prompt.trimmingCharacters(in: .whitespaces), prompt.text)
    actual.insertBatch("start ", at: Date(timeIntervalSince1970: 1000))
    XCTAssertTrue(actual.prompt.contains("owned0"))
    XCTAssertFalse(actual.prompt.contains("owned100000"))
  }
}
