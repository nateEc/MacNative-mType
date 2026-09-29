import Foundation
import XCTest

@testable import Typebar

final class CustomSequentialStreamingTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

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

}
