import XCTest
@testable import Typebar

final class ZenMissedWordCopyTests: XCTestCase {
  private func result(zen: Bool, events: [TypingReplayEvent]) -> CompletedTestResult {
    let start = Date(timeIntervalSince1970: 1000)
    return .init(id: UUID(), configuration: zen
      ? .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())
      : .words(10), outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(3), typedCharacterCount: 10,
      correctCharacterCount: 10, errorCount: 0, wpm: 20, rawWpm: 20,
      accuracy: 100, prompt: "unused future prompt", replayEvents: events)
  }

  func testZenCopiesEditedUnicodeInputInsteadOfMissingTargets() {
    let value = result(zen: true, events: [
      .init(offset: 0, kind: .insert, text: "朝 harborx"),
      .init(offset: 1, kind: .delete, text: ""),
      .init(offset: 2, kind: .insert, text: "\nriver "),
      .init(offset: 4, kind: .insert, text: "late"),
    ])
    XCTAssertEqual(MissedWordCopyText.make(for: value, words: []), "朝 harbor\nriver ")
    XCTAssertEqual(MissedWordCopyText.make(for: value, words: ["not a Zen target"]),
      "朝 harbor\nriver ")
  }

  func testOrdinaryModePreservesMissedTargetOrderAndSpacing() {
    let value = result(zen: false, events: [.init(offset: 0, kind: .insert, text: "typed")])
    XCTAssertEqual(MissedWordCopyText.make(for: value, words: ["晨", "harbor", "晨"]), "晨 harbor 晨")
    XCTAssertNil(MissedWordCopyText.make(for: value, words: []))
  }

  func testMissingOrFullyDeletedZenReplayDoesNotCopyThePrompt() {
    XCTAssertNil(MissedWordCopyText.make(for: result(zen: true, events: []), words: []))
    XCTAssertNil(MissedWordCopyText.make(for: result(zen: true, events: [
      .init(offset: 0, kind: .insert, text: "x"), .init(offset: 1, kind: .delete, text: ""),
    ]), words: []))
  }
}
