import Foundation
import XCTest

@testable import Typebar

final class CustomSequentialStreamingTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  func testCustomWordChallengeEndsAtHourBeforeWordLimit() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 3_600, wordLimit: 10_000, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .random)
    var session = TestSessionFactory.make(configuration: configuration, customText: "amber bay")
    session.insert(String(session.nextExpectedCharacter!), at: start)
    session.tick(at: start.addingTimeInterval(3_599))
    XCTAssertFalse(session.isFinished)
    session.insert(String(session.nextExpectedCharacter!), at: start.addingTimeInterval(3_599))
    session.tick(at: start.addingTimeInterval(3_600))
    XCTAssertEqual(session.result()?.outcome, .completed)
    XCTAssertLessThan(session.completedWordCount, 10_000)
  }

  func testLongOrderedCustomTextStartsWithOneHundredWordsAndContinuesInOrder() {
    let source = (0..<105).map { "word\($0)" }.joined(separator: " ")
    let configuration = TestConfiguration(
      mode: .custom, duration: 120, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .time, customTextOrdering: .inOrder)
    var session = TestSessionFactory.make(configuration: configuration, customText: source)
    let initial = session.prompt
    XCTAssertEqual(initial.split(separator: " ").count, 100)
    XCTAssertEqual(initial.split(separator: " ").last, "word99")

    session.insert(initial + " ", at: start)
    let words = session.prompt.split(separator: " ").map(String.init)
    XCTAssertGreaterThanOrEqual(words.count, 200)
    XCTAssertEqual(Array(words[100..<105]), (100..<105).map { "word\($0)" })
    XCTAssertEqual(words[105], "word0")
    XCTAssertEqual(words[199], "word94")
  }

  func testOrderedCustomTextPreservesNewlinesAndRepeatedAttempt() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 120, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .time, customTextOrdering: .inOrder)
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber\nharbor  quiet")
    let initial = session.prompt
    XCTAssertTrue(initial.hasPrefix("amber\nharbor  quiet amber\nharbor  quiet"))
    XCTAssertEqual(initial.split(whereSeparator: \.isWhitespace).count, 100)
    session.insert(initial + " ", at: start)
    XCTAssertGreaterThan(session.prompt.count, initial.count)
    XCTAssertEqual(session.repeatedAttempt().prompt, initial)
  }

  func testShuffledCustomTextUsesOneCompletePermutationPerCycle() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 120, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .time, customTextOrdering: .shuffled)
    let session = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor quiet lake")
    let words = session.prompt.split(separator: " ").map(String.init)
    XCTAssertEqual(words.count, 100)
    guard words.count == 100 else { return }
    for start in stride(from: 0, to: 100, by: 4) {
      XCTAssertEqual(Set(words[start..<(start + 4)]), Set(["amber", "harbor", "quiet", "lake"]))
    }
    XCTAssertTrue(session.usesIncrementalPromptExtension)
  }

  func testShuffleDrawsASecondPermutationWhenFirstCycleIsExhausted() throws {
    var stream = try XCTUnwrap(CustomSequentialWordStream(
      source: "amber harbor quiet lake", ordering: .shuffled))
    var draws = 0
    let output = stream.nextWords(count: 8, random: {
      defer { draws += 1 }
      return draws < 3 ? 0 : 1
    })
    let words = output.split(separator: " ").map(String.init)
    XCTAssertEqual(words.count, 8)
    guard words.count == 8 else { return }
    XCTAssertEqual(Set(words[0..<4]), Set(words[4..<8]))
    XCTAssertNotEqual(Array(words[0..<4]), Array(words[4..<8]))
    XCTAssertEqual(draws, 6)
  }

  func testFiniteShuffledCustomTextEndsAtConfiguredWordRatherThanEndOfCycle() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 5, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .shuffled)
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor quiet lake")
    let words = session.prompt.split(separator: " ").map(String.init)
    XCTAssertEqual(words.count, 5)
    guard words.count == 5 else { return }
    XCTAssertEqual(Set(words[0..<4]), Set(["amber", "harbor", "quiet", "lake"]))
    session.insert(session.prompt, at: start)
    XCTAssertEqual(session.result()?.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 5)
  }

  func testFiniteOrderedCustomTextCompletesAfterOneWordInSecondBatch() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 101, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .inOrder)
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor quiet lake")
    let firstBatch = session.prompt
    XCTAssertEqual(firstBatch.split(separator: " ").count, 100)
    session.insert(firstBatch + " ", at: start)
    XCTAssertEqual(session.completedWordCount, 100)
    XCTAssertFalse(session.isFinished)
    let finalWord = session.prompt.dropFirst(firstBatch.count)
      .split(separator: " ").first.map(String.init)
    XCTAssertEqual(finalWord, "amber")
    session.insert(finalWord ?? "", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.result()?.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 101)
  }

  func testFiniteNoSpaceCustomWordsCompleteAtHiddenWordBoundaryForEveryOrdering() {
    for ordering in [CustomTextOrdering.inOrder, .shuffled, .random] {
      let configuration = TestConfiguration(
        mode: .custom, duration: nil, wordLimit: 3, difficulty: .normal,
        rules: .init(), customTextCompletion: .words,
        customTextOrdering: ordering, modifiers: [.noSpaces])
      var session = TestSessionFactory.make(
        configuration: configuration, customText: "amber harbor quiet lake")
      let prompt = session.prompt
      XCTAssertFalse(prompt.contains(" "), String(describing: ordering))
      session.insert(String(prompt.dropLast()), at: start)
      XCTAssertEqual(session.completedWordCount, 2, String(describing: ordering))
      XCTAssertFalse(session.isFinished, String(describing: ordering))
      session.insert(String(prompt.suffix(1)), at: start.addingTimeInterval(1))
      XCTAssertEqual(session.completedWordCount, 3, String(describing: ordering))
      XCTAssertEqual(session.result()?.outcome, .completed, String(describing: ordering))
    }
  }

  func testFiniteNoSpaceCustomWordsFinishMidwayThroughNextBatch() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 101, difficulty: .normal,
      rules: .init(), customTextCompletion: .words,
      customTextOrdering: .inOrder, modifiers: [.noSpaces])
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor quiet lake")
    let firstBatch = session.prompt
    session.insert(firstBatch, at: start)
    XCTAssertEqual(session.completedWordCount, 100)
    XCTAssertFalse(session.isFinished)
    XCTAssertTrue(session.prompt.dropFirst(firstBatch.count).hasPrefix("amber"))
    session.insert("amber", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 101)
    XCTAssertEqual(session.result()?.outcome, .completed)
  }

  func testFiniteOrderedCustomTextStreamsThreeThousandWordsWithoutLosingPosition() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 3_000, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .inOrder)
    var session = TestSessionFactory.make(configuration: configuration, customText: "typebar")
    for word in 0..<3_000 {
      session.insert(word == 2_999 ? "typebar" : "typebar ", at: start)
    }
    XCTAssertEqual(session.completedWordCount, 3_000)
    XCTAssertEqual(session.result()?.outcome, .completed)
  }

  func testFiniteOrderedCustomTextStreamsTenThousandWordsWithoutLosingPosition() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 3_600, wordLimit: 10_000, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .inOrder)
    var session = TestSessionFactory.make(configuration: configuration, customText: "typebar")
    for word in 0..<10_000 {
      session.insert(word == 9_999 ? "typebar" : "typebar ", at: start)
    }
    XCTAssertEqual(session.completedWordCount, 10_000)
    XCTAssertEqual(session.result()?.outcome, .completed)
  }

  func testTenThousandWordProgressRemainsCorrectWhenReadAfterEveryWord() throws {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 10_000, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .inOrder)
    var session = TestSessionFactory.make(configuration: configuration, customText: "typebar")
    for word in 0..<10_000 {
      session.insert(word == 9_999 ? "typebar" : "typebar ", at: start)
      XCTAssertEqual(
        try XCTUnwrap(session.progressFraction(at: start)), Double(word + 1) / 10_000,
        accuracy: 0.000_000_1)
    }
    XCTAssertEqual(session.completedWordCount, 10_000)
    XCTAssertEqual(session.result()?.outcome, .completed)
  }

  func testWordProgressRollsBackEarlyCommitAndWordDeletion() {
    var session = TypingSession(
      configuration: .words(3, rules: .init(freedomMode: true)),
      prompt: "amber bay cedar")
    session.insert("am ", at: start)
    XCTAssertEqual(session.completedWordCount, 1)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 0)
    session.insert("ber bay ", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.completedWordCount, 2)
    session.deleteWordBackward(at: start.addingTimeInterval(3))
    XCTAssertEqual(session.completedWordCount, 1)
  }

  func testWordProgressFallsBackAfterNonASCIIInput() {
    var session = TypingSession(
      configuration: .words(3, rules: .init(freedomMode: true)),
      prompt: "café bay cedar")
    session.insert("café ", at: start)
    XCTAssertEqual(session.completedWordCount, 1)
    session.deleteWordBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 0)
    session.insert("café ", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.completedWordCount, 1)
  }

  func testNoSpaceHiddenWordProgressTracksEachBoundary() throws {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 1_000, difficulty: .normal,
      rules: .init(), customTextCompletion: .words,
      customTextOrdering: .inOrder, modifiers: [.noSpaces])
    var session = TestSessionFactory.make(configuration: configuration, customText: "ab cd")
    for word in 0..<1_000 {
      session.insert(word.isMultiple(of: 2) ? "ab" : "cd", at: start)
      XCTAssertEqual(
        try XCTUnwrap(session.progressFraction(at: start)), Double(word + 1) / 1_000,
        accuracy: 0.000_000_1)
    }
    XCTAssertEqual(session.result()?.outcome, .completed)
  }

  func testOptionalHundredThousandWordEndurance() throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["TYPEBAR_ENDURANCE_TESTS"] == "1",
      "Run explicitly with TYPEBAR_ENDURANCE_TESTS=1")
    let challenge = try XCTUnwrap(
      TypebarChallengeLibrary.challenge(id: "single-word-hundred-thousand"))
    let configuration = challenge.preset.configuration.with(challengeID: challenge.id)
    var session = TestSessionFactory.make(
      configuration: configuration,
      customText: try XCTUnwrap(challenge.preset.customText))
    XCTAssertEqual(session.prompt.split(separator: " ").count, 100)
    let target = Array(repeating: "typebar", count: 100_000).joined(separator: " ")
    for word in 0..<100_000 {
      session.insert(word == 99_999 ? "typebar" : "typebar ",
        at: start.addingTimeInterval(Double(word) * 0.5))
      if (word + 1).isMultiple(of: 1_000) {
        XCTAssertEqual(session.completedWordCount, word + 1)
      }
      if word == 99_998 { XCTAssertFalse(session.isFinished) }
    }
    XCTAssertEqual(session.completedWordCount, 100_000)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertTrue(ChallengeEvaluator.evaluate(result, challenge: challenge).passed)
    XCTAssertEqual(result.elapsedDuration, 49_999.5)
    XCTAssertEqual(result.afkDuration, 0)
    XCTAssertEqual(result.typedCharacterCount, 799_999)
    XCTAssertEqual(result.correctCharacterCount, 799_999)
    XCTAssertEqual(result.errorCount, 0)
    XCTAssertEqual(result.preciseAccuracy, 100)
    XCTAssertEqual(result.inputMetrics, .init(version: 1, correctAttempts: 799_999,
      totalAttempts: 799_999, creditedUnits: 799_999, retainedUnits: 799_999))
    let expectedSpeed = 799_999.0 / 5 / result.elapsedDuration * 60
    XCTAssertEqual(result.preciseWpm, expectedSpeed, accuracy: 0.000_000_1)
    XCTAssertEqual(result.preciseRawWpm, expectedSpeed, accuracy: 0.000_000_1)
    XCTAssertTrue(result.prompt == target)
    XCTAssertEqual(result.replayEvents.count, 799_999)
    XCTAssertEqual(result.replayEvents.first?.offset, 0)
    XCTAssertEqual(result.replayEvents.last?.offset, result.elapsedDuration)
    XCTAssertTrue(TypingReplay.typedText(events: result.replayEvents,
      through: 24_999.5) == String(target.prefix(400_000)))
    XCTAssertTrue(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration) == target)
    let reviews = session.wordReviews
    XCTAssertEqual(reviews.count, 100_000)
    XCTAssertTrue(reviews.allSatisfy(\.isCorrect))
    XCTAssertEqual(reviews.last?.typed, "typebar")
    do {
      let record = try XCTUnwrap(TestResultRecord(result: result).portableResult)
      XCTAssertTrue(record == result, "十万词内存记录必须完整保留结果和回放")
    }
    do {
      let encoded = try JSONEncoder().encode(result)
      let decoded = try JSONDecoder().decode(CompletedTestResult.self, from: encoded)
      XCTAssertTrue(decoded == result, "十万词 JSON 往返不能丢失精度、提示或事件")
    }
    let row = ResultCSVExport.csvString(for: [result]).components(separatedBy: "\r\n")[1]
    let fields = Dictionary(uniqueKeysWithValues: zip(ResultCSVExport.columns,
      row.components(separatedBy: ",")))
    XCTAssertEqual(fields["word_limit"], "100000")
    XCTAssertEqual(fields["typed_characters"], "799999")
    XCTAssertEqual(fields["correct_characters"], "799999")
    XCTAssertEqual(fields["accuracy_percent"], "100")
    XCTAssertEqual(Double(try XCTUnwrap(fields["elapsed_seconds"])), result.elapsedDuration)
    let archiveData = try TypebarDataTransfer.exportArchive(settings: .init(), results: [result],
      presets: [], at: result.finishedAt)
    let archive = try TypebarDataTransfer.importArchive(from: archiveData)
    XCTAssertEqual(archive.exportedAt, result.finishedAt)
    XCTAssertTrue(archive.results.first == result, "正式归档必须完整保留十万词结果")
  }

  func testPromptCacheResegmentsCombiningCharacterAcrossRepeatedChunk() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 120, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .time, modifiers: [.noSpaces])
    var session = TypingSession(
      configuration: configuration, prompt: "a", repeatingPrompt: "\u{301}b")
    session.insert("a", at: start)
    XCTAssertEqual(session.prompt, "a\u{301}b")
    XCTAssertEqual(session.nextExpectedCharacter, "b")
  }

  func testPromptCacheAppendsSeparatorThenCombiningCharacter() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 120, wordLimit: nil, difficulty: .normal,
      rules: .init(), customTextCompletion: .time)
    var session = TypingSession(
      configuration: configuration, prompt: "a", repeatingPrompt: "b\u{301}")
    session.insert("a", at: start)
    session.insert(" ", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.prompt, "a b\u{301}")
    XCTAssertEqual(session.nextExpectedCharacter, "b\u{301}")
  }

}
