import XCTest
@testable import Typebar

final class WeakSpotLiveGenerationTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  private func scores(_ character: Character, _ interval: TimeInterval) -> WeakSpotScores {
    var result = WeakSpotScores()
    result.record(character: character, interval: interval, isCorrect: true)
    return result
  }

  private func drawPair() -> () -> Int {
    var rank = 0
    return { defer { rank += 1 }; return rank % 2 }
  }

  func testLiveInputUpdatesBaselineBeforeWeakspotIsEnabledAndDeletionDoesNotUndoLearning() {
    var session = TypingSession(configuration: .words(2), prompt: "am oak",
      weakSpotScores: scores("m", 1))
    session.insert("a", at: start)
    XCTAssertEqual(session.liveWeakSpotScores.knownAverageScore(for: "a"), nil)
    session.insert("x", at: start.addingTimeInterval(0.2))
    XCTAssertEqual(session.liveWeakSpotScores.averageScore(for: "x"), 5.2, accuracy: 0.000001)
    session.deleteBackward(at: start.addingTimeInterval(0.4))
    session.insert("m", at: start.addingTimeInterval(0.5))
    XCTAssertEqual(session.liveWeakSpotScores.averageScore(for: "m"), 0.65, accuracy: 0.000001)
    XCTAssertEqual(session.liveWeakSpotScores.averageScore(for: "x"), 5.2, accuracy: 0.000001)
    XCTAssertEqual(session.liveWeakSpotInputSamples.count, 2)
  }

  func testLatestScoresAffectNewCodeAndOrdinarySectionsRatherThanTheInitialSnapshot() {
    for language in [TypingLanguage.codeSwift, .arenaStrategy] {
      var cursor = GeneratedCandidateContinuation(configuration: .words(0, language: language)
        .with(modifiers: [.weakSpot]), batchTokenCount: 1, weakSpotScores: scores("a", 1),
        sourceWords: ["aa", "bb"])
      XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: drawPair()).transformed, "aa")
      var current = scores("a", 1)
      current.record(character: "b", interval: 0.2, isCorrect: false)
      XCTAssertEqual(cursor.nextChunk(weakSpotScores: current,
        nextRandomWordIndex: drawPair()).transformed, " bb", language.rawValue)
    }
  }

  func testLearningDoesNotReselectPendingSectionButAffectsTheFollowingSection() {
    var cursor = GeneratedCandidateContinuation(configuration: .words(0, language: .codeSwift)
      .with(modifiers: [.weakSpot]), batchTokenCount: 1, weakSpotScores: scores("a", 1),
      sourceWords: ["aa aa", "bb bb"])
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: drawPair()).transformed, "aa")
    let current = scores("b", 5)
    var draws = 0
    XCTAssertEqual(cursor.nextChunk(weakSpotScores: current,
      nextRandomWordIndex: { draws += 1; return 1 }).transformed, " aa")
    XCTAssertEqual(draws, 1)
    XCTAssertEqual(cursor.nextChunk(weakSpotScores: current,
      nextRandomWordIndex: drawPair()).transformed, " bb")
  }

  func testLearningKeepsCapturedRepeatTargetsButChangesFutureUncachedSections() {
    var cursor = GeneratedCandidateContinuation(configuration: .words(0, language: .codeSwift)
      .with(modifiers: [.weakSpot]), batchTokenCount: 1, weakSpotScores: scores("a", 1),
      sourceWords: ["aa", "bb"])
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: drawPair()).transformed, "aa")
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: drawPair()).transformed, " aa")
    var replay = cursor.replayingContinuation()
    let current = scores("b", 5)
    XCTAssertEqual(replay.nextChunk(weakSpotScores: current,
      nextRandomWordIndex: { XCTFail("Cached target must not draw"); return 0 }).transformed, " aa")
    XCTAssertEqual(replay.nextChunk(weakSpotScores: current,
      nextRandomWordIndex: drawPair()).transformed, " bb")
  }

  func testRepeatedAttemptCarriesScoresExactlyOnceAndResetsFirstInputTiming() {
    var session = TypingSession(configuration: .words(2), prompt: "am oak",
      weakSpotScores: scores("m", 1))
    session.insert("a", at: start)
    session.insert("m", at: start.addingTimeInterval(0.3))
    var replay = session.repeatedAttempt()
    XCTAssertEqual(replay.liveWeakSpotScores.averageScore(for: "m"), 0.65, accuracy: 0.000001)
    XCTAssertTrue(replay.liveWeakSpotInputSamples.isEmpty)
    replay.insert("a", at: start.addingTimeInterval(10))
    XCTAssertEqual(replay.liveWeakSpotScores.knownAverageScore(for: "a"), nil)
    replay.insert("m", at: start.addingTimeInterval(10.6))
    XCTAssertEqual(replay.liveWeakSpotScores.averageScore(for: "m"), 1.9 / 3, accuracy: 0.000001)
    XCTAssertEqual(session.liveWeakSpotScores.averageScore(for: "m"), 0.65, accuracy: 0.000001)
  }

  func testFactoryRetainsBaselineForOrdinaryCodeAndQuoteRepeats() {
    let baseline = scores("x", 5)
    for configuration in [TestConfiguration.words(2), .words(2, language: .codeSwift),
      .words(2, language: .arenaStrategy),
      .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())] {
      let session = TestSessionFactory.make(configuration: configuration, weakSpotScores: baseline)
      XCTAssertEqual(session.liveWeakSpotScores, baseline)
      XCTAssertEqual(session.repeatedAttempt().liveWeakSpotScores, baseline)
    }
  }

  func testOrdinaryWordContinuationUsesLatestScoresWithOwnedRankInputs() throws {
    let lexicon = TypingLanguage.english.ownedPracticeLexicon()
    let amber = try XCTUnwrap(lexicon.firstIndex(of: "amber"))
    let harbor = try XCTUnwrap(lexicon.firstIndex(of: "harbor"))
    var rank = 0
    let draw = { defer { rank += 1 }; return rank % 2 == 0 ? amber : harbor }
    var cursor = GeneratedWordContinuation(configuration: .words(101).with(modifiers: [.weakSpot]),
      weakSpotScores: scores("m", 1), batchWordCount: 1, previousSource: "quiet")
    XCTAssertEqual(cursor.nextChunk(nextRandomWordIndex: draw).transformed, "amber")
    XCTAssertEqual(cursor.nextChunk(weakSpotScores: scores("h", 5),
      nextRandomWordIndex: draw).transformed, "harbor")
  }

  func testNoSpaceRejectedSeparatorDoesNotLearnOrChangeTheNextInputGap() {
    var session = TypingSession(configuration: .words(2).with(modifiers: [.noSpaces]), prompt: "ab",
      noSpaceWordEndIndices: [1, 2], noSpaceTargetWords: ["a", "b"])
    session.insert("a", at: start)
    session.insert(" ", at: start.addingTimeInterval(0.2))
    session.insert("b", at: start.addingTimeInterval(0.5))
    XCTAssertEqual(session.liveWeakSpotScores.averageScore(for: "b"), 0.5, accuracy: 0.000001)
    XCTAssertNil(session.liveWeakSpotScores.knownAverageScore(for: " "))
    XCTAssertEqual(session.liveWeakSpotInputSamples.count, 1)
  }

  func testOlderRepeatCanInheritTheLatestAppBookWithoutMutatingTargetsOrItsSnapshot() {
    let old = TypingSession(configuration: .words(2), prompt: "am oak", weakSpotScores: scores("m", 1))
    var latest = scores("m", 2)
    latest.record(character: "x", interval: 0.2, isCorrect: false)
    let restored = old.withWeakSpotScores(latest)
    XCTAssertEqual(restored.prompt, old.prompt)
    XCTAssertEqual(restored.typed, old.typed)
    XCTAssertEqual(restored.outcome, old.outcome)
    XCTAssertEqual(restored.liveWeakSpotScores, latest)
    XCTAssertEqual(old.liveWeakSpotScores.averageScore(for: "m"), 1)
    XCTAssertNil(old.liveWeakSpotScores.knownAverageScore(for: "x"))
  }
}
