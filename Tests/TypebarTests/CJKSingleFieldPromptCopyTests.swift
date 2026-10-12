import XCTest
@testable import Typebar

final class CJKSingleFieldPromptCopyTests: XCTestCase {
  func testRecordedSingleFieldCopiesFullTargetAcrossCJKCatalogIdentities() {
    let start = Date(timeIntervalSince1970: 1000)
    let languages = TypingLanguage.allCases.filter(\.usesCJKWordStream)
    XCTAssertFalse(languages.isEmpty)
    for language in languages {
      let value = CompletedTestResult(id: UUID(), configuration: .words(1, language: language),
        outcome: .completed, startedAt: start, finishedAt: start.addingTimeInterval(2),
        typedCharacterCount: 1, correctCharacterCount: 1, errorCount: 0,
        wpm: 6, rawWpm: 6, accuracy: 100, prompt: "晴岚海",
        replayEvents: [.init(offset: 0, kind: .insert, text: "晴",
          inputField: .init(index: 0, value: "晴"))])
      XCTAssertEqual(ResultPromptText.make(for: value, reviews: []), "晴岚海", language.rawValue)
    }
  }

  func testActualChineseCustomSessionCopiesUnfinishedWholeField() throws {
    let start = Date(timeIntervalSince1970: 1000)
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), language: .simplifiedChinese)
    var session = TestSessionFactory.make(configuration: configuration, customText: "晴岚海")
    XCTAssertEqual(session.prompt, "晴岚海")
    session.insertBatch("晴", at: start)
    session.bailOut(at: start.addingTimeInterval(2))
    let value = try XCTUnwrap(session.result())
    XCTAssertNil(value.targetWordDirectory)
    XCTAssertTrue(value.replayEvents.allSatisfy { $0.inputField != nil })
    XCTAssertEqual(ResultPromptText.make(for: value, reviews: session.wordReviews), "晴岚海")
  }

  func testLegacyPrimitiveHistoryKeepsFallbackDespiteLateFieldMetadata() {
    let start = Date(timeIntervalSince1970: 1000)
    let value = CompletedTestResult(id: UUID(), configuration: .words(1, language: .simplifiedChinese),
      outcome: .completed, startedAt: start, finishedAt: start.addingTimeInterval(2),
      typedCharacterCount: 1, correctCharacterCount: 1, errorCount: 0,
      wpm: 6, rawWpm: 6, accuracy: 100, prompt: "晴岚海",
      replayEvents: [.init(offset: 0, kind: .insert, text: "晴"),
        .init(offset: 3, kind: .insert, text: "x", inputField: .init(index: 0, value: "x"))])
    XCTAssertEqual(ResultPromptText.make(for: value, reviews: []), "晴")
  }

  func testLatePrimitiveEventDoesNotDowngradeRecordedSingleField() {
    let start = Date(timeIntervalSince1970: 1000)
    let value = CompletedTestResult(id: UUID(), configuration: .words(1, language: .japaneseHiragana),
      outcome: .completed, startedAt: start, finishedAt: start.addingTimeInterval(2),
      typedCharacterCount: 1, correctCharacterCount: 1, errorCount: 0,
      wpm: 6, rawWpm: 6, accuracy: 100, prompt: "あおぞら",
      replayEvents: [.init(offset: 0, kind: .insert, text: "あ",
        inputField: .init(index: 0, value: "あ")),
        .init(offset: 3, kind: .insert, text: "x")])
    XCTAssertEqual(ResultPromptText.make(for: value, reviews: []), "あおぞら")
  }
}
