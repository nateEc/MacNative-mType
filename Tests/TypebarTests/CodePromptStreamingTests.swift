import XCTest
@testable import Typebar

final class CodePromptStreamingTests: XCTestCase {
  func testInfiniteIndexedCodeChoicesPrimeFreshContentInsteadOfReplayingTheOpening() {
    let openings: [(TypingLanguage, String)] = [
      (.codeSwift, "func practiceUnit0("),
      (.codePython, "def practice_unit_0("),
      (.codePython1k, "def practice_unit_0("),
      (.codePython2k, "def practice_unit_0("),
      (.codePython5k, "def practice_unit_0("),
      (.codeJavaScript, "function practiceUnit0("),
      (.codeJavaScript1k, "function practiceUnit0("),
      (.codeCSharp, "internal static class Practice0 "),
      (.codeC, "int practice_unit_0("),
      (.codeCPP, "int practice_unit_0("),
      (.codeGo, "func practiceUnit0("),
      (.codeJava, "class PracticeUnit0 "),
      (.codeRuby, "def practice_unit_0("),
      (.codePerl, "sub practice_unit_0 "),
      (.codeSQL, "SUM(value) AS total_0"),
      (.codeBash, "practice_unit_0()"),
      (.codeCSS, ".practice-unit-0 "),
      (.codeDart, "int practiceUnit0("),
      (.codeRust, "fn practice_unit0("),
      (.codeKotlin, "fun practiceUnit0("),
      (.codeTypeScript, "function practiceUnit0("),
      (.codeVimscript, "function! PracticeUnit0("),
      (.codeR, "practice_unit_0 <-"),
      (.codeR2k, "practice_unit_0 <-"),
      (.codeLua, "local function practice_unit_0("),
      (.codeLuau, "local function practice_unit_0("),
      (.codePHP, "function practice_unit_0("),
    ]
    XCTAssertEqual(Set(openings.map(\.0)), Set(TypingLanguage.allCases.filter {
      CodePracticeContent.supportsIndexedContinuation(for: $0)
    }))
    for (language, opening) in openings {
      var session = TestSessionFactory.make(configuration: .words(0, language: language))
      XCTAssertEqual(session.prompt.components(separatedBy: opening).count - 1, 1,
        "Opening repeated for \(language.displayName)")
      // A 100-token batch has 13 whole units; infinite practice primes two.
      XCTAssertEqual(session.prompt, CodePracticeContent.prompt(
        language: language, targetTokenCount: 26 * 8), language.displayName)
      session.insert(session.prompt + "\n", at: Date(timeIntervalSince1970: 3_000))
      XCTAssertFalse(session.isFinished)
      XCTAssertEqual(session.errors, 0, language.displayName)
      XCTAssertEqual(session.prompt, CodePracticeContent.prompt(
        language: language, targetTokenCount: 39 * 8), language.displayName)
    }
  }

  func testTimedAndLargeFiniteCodePracticeExtendToTheNextUnit() {
    let start = Date(timeIntervalSince1970: 3_000)
    for configuration in [TestConfiguration.timed(seconds: 30, language: .codeSwift),
      .words(10_000, language: .codeSwift)] {
      var session = TestSessionFactory.make(configuration: configuration)
      let initial = session.prompt
      session.insert(initial + "\n", at: start)
      XCTAssertFalse(session.isFinished)
      XCTAssertEqual(session.errors, 0)
      XCTAssertGreaterThan(session.prompt.count, initial.count)
      XCTAssertEqual(session.prompt.components(separatedBy: "import Foundation").count - 1, 1)
      XCTAssertEqual(session.prompt.components(separatedBy: "func practiceUnit0(").count - 1, 1)
      let units = CodePracticeContent.unitCount(
        forTargetTokenCount: GeneratedPromptChunkPolicy.wordCount(for: configuration))
      XCTAssertEqual(session.prompt, CodePracticeContent.prompt(
        language: .codeSwift, targetTokenCount: units * 2 * 8))
    }
  }

  func testRestartRestoresThePrimedCodeCursorAsWellAsTheInitialPrompt() {
    let start = Date(timeIntervalSince1970: 3_000)
    for language in [TypingLanguage.codeSwift, .codePython] {
      var session = TestSessionFactory.make(configuration: .words(0, language: language))
      let initial = session.prompt
      session.insert(initial + "\n", at: start)
      let firstExtension = session.prompt
      session.insert(String(firstExtension.dropFirst(session.typed.count)) + "\n", at: start)
      XCTAssertGreaterThan(session.prompt.count, firstExtension.count)
      var restarted = session.repeatedAttempt()
      XCTAssertEqual(restarted.prompt, initial)
      XCTAssertFalse(restarted.hasStarted)
      restarted.insert(initial + "\n", at: start)
      XCTAssertEqual(restarted.prompt, firstExtension)
      XCTAssertEqual(restarted.errors, 0)
    }
  }

  func testNoSpaceCodeContinuationKeepsTransformedContentAndWordBoundaries() {
    let configuration = TestConfiguration.words(0, language: .codeSwift)
      .with(modifiers: [.noSpaces])
    var session = TestSessionFactory.make(configuration: configuration)
    let initial = session.prompt
    let start = Date(timeIntervalSince1970: 3_000)
    session.insert(initial, at: start)
    let completedBeforeExtension = session.completedWordCount
    session.insert("\nf", at: start)
    XCTAssertEqual(session.completedWordCount, completedBeforeExtension)
    session.insert("unc", at: start)
    XCTAssertEqual(session.completedWordCount, completedBeforeExtension + 1)
    XCTAssertFalse(session.isFinished)
    XCTAssertEqual(session.errors, 0)
    XCTAssertGreaterThan(session.completedWordCount, 0)
    XCTAssertFalse(session.prompt.contains(" "))
    XCTAssertTrue(session.prompt.contains("\nfuncpracticeUnit26("))
    let source = CodePracticeContent.prompt(language: .codeSwift, targetTokenCount: 39 * 8)
    XCTAssertEqual(session.prompt, TestModifierPolicy.transformed(
      source, modifiers: configuration.modifiers, language: configuration.language))
  }

  func testExternalStreamsStaticCorporaAndFunboxesKeepTheirOwnContinuationPolicy() {
    let configuration = TestConfiguration.words(0, language: .codeSwift)
    let external = TestSessionFactory.make(configuration: configuration, streamPrompt: "let custom = 1")
    XCTAssertEqual(external.prompt, "let custom = 1 let custom = 1")
    let document = TestSessionFactory.make(configuration: .words(0, language: .codeLaTeX))
    let first = CodePracticeContent.prompt(language: .codeLaTeX, targetTokenCount: 100)
    XCTAssertEqual(document.prompt, first + " " + first)
    let funbox = TestSessionFactory.make(configuration: configuration.with(modifiers: [.binaryStream]))
    XCTAssertFalse(funbox.prompt.contains("func practiceUnit"))
    XCTAssertEqual(funbox.prompt.split(separator: " ").count, 200)
  }
}
