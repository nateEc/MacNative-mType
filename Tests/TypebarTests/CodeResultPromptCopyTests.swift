import XCTest
@testable import Typebar

final class CodeResultPromptCopyTests: XCTestCase {
  private func result(language: TypingLanguage, prompt: String, input: String) -> CompletedTestResult {
    let start = Date(timeIntervalSince1970: 1000)
    return .init(id: UUID(), configuration: .timed(seconds: 30, language: language),
      outcome: .completed, startedAt: start, finishedAt: start.addingTimeInterval(3),
      typedCharacterCount: input.count, correctCharacterCount: input.count,
      errorCount: 0, wpm: 20, rawWpm: 20, accuracy: 100, prompt: prompt,
      replayEvents: [.init(offset: 0, kind: .insert, text: input,
        inputField: .init(index: 0, value: input))])
  }

  func testPartialCodeInputCopiesWholeReachedTargetIncludingNewlineCommit() {
    let languages = TypingLanguage.allCases.filter(\.isCodeLanguage)
    XCTAssertFalse(languages.isEmpty)
    XCTAssertTrue(languages.contains(.dockerFile))
    XCTAssertTrue(languages.contains(.codePython))
    XCTAssertTrue(languages.contains(.codeJavaScript))
    for language in languages {
      let value = result(language: language, prompt: "emit(value)\nfuture", input: "em")
      XCTAssertEqual(ResultPromptText.make(for: value, reviews: [
        .init(index: 0, target: "emit(value)", typed: "em"),
      ]), "emit(value)\n", language.rawValue)
    }
  }

  func testCodeTargetKeepsIndentationAndDoesNotCopyTheTypedMisspelling() {
    let value = result(language: .codePython, prompt: "\temit(value) next", input: "\tx")
    XCTAssertEqual(ResultPromptText.make(for: value, reviews: [
      .init(index: 0, target: "\temit(value)", typed: "\tx", hasInputError: true),
    ]), "\temit(value) ")
  }
}
