import XCTest
@testable import Typebar

final class CodePromptStreamingTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 3_000)

  private func assertOwnedPool(_ prompt: String, language: TypingLanguage,
    file: StaticString = #filePath, line: UInt = #line) {
    let pool = Set(CodePracticeContent.polyglotTokens(for: language).map {
      language == .dockerFile ? $0.lowercased() : $0
    })
    XCTAssertTrue(prompt.split(separator: " ").allSatisfy { pool.contains(String($0)) },
      language.rawValue, file: file, line: line)
  }

  func testEveryCodePoolContinuesWithOwnedCandidatesInsteadOfProgramOrder() {
    for language in TypingLanguage.allCases.filter(\.isCodeLanguage) {
      var session = TestSessionFactory.make(configuration: .words(0, language: language))
      let opening = session.prompt
      XCTAssertEqual(opening.split(separator: " ").count, 100, language.rawValue)
      assertOwnedPool(opening, language: language)
      session.insertBatch(opening + " ", at: start)
      XCTAssertFalse(session.isFinished)
      XCTAssertEqual(session.errors, 0, language.rawValue)
      XCTAssertEqual(session.completedWordCount, 100, language.rawValue)
      XCTAssertTrue(session.prompt.hasPrefix(opening))
      XCTAssertEqual(session.prompt.split(separator: " ").count, 200, language.rawValue)
      assertOwnedPool(session.prompt, language: language)
    }
  }

  func testTimedAndLargeFiniteCodePracticeSampleAnotherBoundedChunk() {
    for configuration in [TestConfiguration.timed(seconds: 30, language: .codeSwift),
      .words(10_000, language: .codeSwift)] {
      var session = TestSessionFactory.make(configuration: configuration)
      let opening = session.prompt
      session.insertBatch(opening + " ", at: start)
      XCTAssertFalse(session.isFinished)
      XCTAssertEqual(session.errors, 0)
      XCTAssertEqual(session.completedWordCount, 100)
      XCTAssertTrue(session.prompt.hasPrefix(opening))
      XCTAssertEqual(session.prompt.split(separator: " ").count, 200)
      assertOwnedPool(session.prompt, language: .codeSwift)
    }
  }

  func testRestartRestoresTheOpeningAndAlreadyGeneratedCodeTargets() {
    for language in [TypingLanguage.codeSwift, .codePython] {
      var session = TestSessionFactory.make(configuration: .words(0, language: language))
      let opening = session.prompt
      session.insertBatch(opening + " ", at: start)
      let extensionPrompt = session.prompt
      session.insertBatch(String(extensionPrompt.dropFirst(session.typed.count)) + " ", at: start)
      let thirdPrompt = session.prompt
      var restarted = session.repeatedAttempt()
      XCTAssertEqual(restarted.prompt, opening)
      XCTAssertFalse(restarted.hasStarted)
      restarted.insertBatch(opening + " ", at: start)
      XCTAssertEqual(restarted.prompt, extensionPrompt)
      restarted.insertBatch(String(extensionPrompt.dropFirst(restarted.typed.count)) + " ", at: start)
      XCTAssertEqual(restarted.prompt, thirdPrompt)
      XCTAssertEqual(restarted.errors, 0)
    }
  }

  func testNoSpaceCodeContinuationKeepsActualTargetsAndWordBoundaries() {
    let configuration = TestConfiguration.words(0, language: .codeSwift).with(modifiers: [.noSpaces])
    var session = TestSessionFactory.make(configuration: configuration)
    let opening = session.prompt
    session.insertBatch(opening, at: start)
    XCTAssertEqual(session.completedWordCount, 100)
    let extensionText = String(session.prompt.dropFirst(opening.count))
    XCTAssertFalse(extensionText.isEmpty)
    session.insertBatch(extensionText, at: start.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 200)
    XCTAssertFalse(session.isFinished)
    XCTAssertEqual(session.errors, 0)
    XCTAssertFalse(session.prompt.contains(" "))
    XCTAssertFalse(session.prompt.contains("\n"))
    XCTAssertEqual(session.wordReviews.prefix(200).map(\.target).joined(), opening + extensionText)
    var replay = session.repeatedAttempt()
    replay.insertBatch(opening, at: start)
    XCTAssertTrue(replay.prompt.hasPrefix(opening + extensionText))
    replay.insertBatch(extensionText, at: start.addingTimeInterval(1))
    XCTAssertEqual(replay.completedWordCount, 200)
    XCTAssertEqual(replay.errors, 0)
    XCTAssertEqual(replay.wordReviews.prefix(200).map(\.target), session.wordReviews.prefix(200).map(\.target))
  }

  func testExternalStreamsAndFunboxesRetainTheirOwnPolicyAndAuthoredProgramsRemainAvailable() {
    let configuration = TestConfiguration.words(0, language: .codeSwift)
    let external = TestSessionFactory.make(configuration: configuration, streamPrompt: "let custom = 1")
    XCTAssertEqual(external.prompt, "let custom = 1 let custom = 1")
    let document = TestSessionFactory.make(configuration: .words(0, language: .codeLaTeX))
    XCTAssertEqual(document.prompt.split(separator: " ").count, 100)
    assertOwnedPool(document.prompt, language: .codeLaTeX)
    XCTAssertTrue(CodePracticeContent.prompt(language: .codeSwift, targetTokenCount: 24)
      .contains("func practiceUnit0("))
    let funbox = TestSessionFactory.make(configuration: configuration.with(modifiers: [.binaryStream]))
    XCTAssertFalse(funbox.prompt.contains("func practiceUnit"))
    XCTAssertEqual(funbox.prompt.split(separator: " ").count, 100)
  }
}
