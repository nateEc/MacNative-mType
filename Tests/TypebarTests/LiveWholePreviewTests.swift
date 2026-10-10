import XCTest
@testable import Typebar

final class LiveWholePreviewTests: XCTestCase {
  func testFinitePoetryDescriptorMaterializesWholeBudgetAndFinalSeparator() throws {
    let content = LivePracticeContent(source: .poetry, title: "Authored fixture", byline: nil,
      tokens: ["quiet", "harbor", "morning"], separator: " ")
    let configuration = TestConfiguration.words(701).with(modifiers: [.underscoreSeparators])
    let descriptor = content.promptDescriptor(for: configuration, showAllLines: true)
    XCTAssertEqual(descriptor.text.split(separator: " ").count, 701)
    let words = (0..<701).map { ["quiet", "harbor", "morning"][$0 % 3] }
    var session = TestSessionFactory.make(configuration: configuration,
      streamPrompt: descriptor.text, showAllLines: true)
    let expected = words.joined(separator: "_")
    XCTAssertEqual(session.prompt, expected)
    XCTAssertNil(session.generationNotice)
    let began = Date(timeIntervalSinceReferenceDate: 916_900_000)
    session.insertBatch(String(expected.dropLast()), at: began)
    XCTAssertFalse(session.isFinished)
    session.insertBatch(String(expected.suffix(1)), at: began.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 701)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), expected)
    try checkPersistenceAndRepeat(session: session, result: result, expected: expected)
  }

  func testUnseparatedDescriptorRetainsEveryAuthoredTokenBoundaryInWholePreview() throws {
    let content = LivePracticeContent(source: .encyclopedia, title: "Authored fixture", byline: nil,
      tokens: ["甲", "乙丙", "丁"], separator: "")
    let configuration = TestConfiguration.words(501, language: .simplifiedChinese)
    let descriptor = content.promptDescriptor(for: configuration, showAllLines: true)
    XCTAssertEqual(descriptor.noSpaceBoundarySource?.split(separator: " ").count, 501)
    var session = TestSessionFactory.make(configuration: configuration,
      streamPrompt: descriptor.text, streamNoSpaceBoundarySource: descriptor.noSpaceBoundarySource,
      showAllLines: true)
    XCTAssertEqual(session.prompt, (0..<501).map { ["甲", "乙丙", "丁"][$0 % 3] }.joined())
    XCTAssertNil(session.generationNotice)
    let expected = session.prompt
    let began = Date(timeIntervalSinceReferenceDate: 916_900_000)
    session.insertBatch(String(expected.dropLast()), at: began)
    XCTAssertFalse(session.isFinished)
    session.insertBatch(String(expected.suffix(1)), at: began.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 501)
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), expected)
    try checkPersistenceAndRepeat(session: session, result: result, expected: expected)
  }

  private func checkPersistenceAndRepeat(session: TypingSession, result: CompletedTestResult,
    expected: String) throws {
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    let archive = try TypebarDataTransfer.importArchive(from:
      TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [],
        at: Date(timeIntervalSinceReferenceDate: 916_900_002)))
    XCTAssertEqual(archive.results, [result])
    let repeated = session.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, expected)
    XCTAssertEqual(repeated.configuration, session.configuration)
    XCTAssertNil(repeated.generationNotice)
    XCTAssertFalse(repeated.hasStarted)
    XCTAssertFalse(repeated.isFinished)
  }

  func testDisabledTimedInfiniteAndOverBudgetDescriptorsRemainBounded() {
    let content = LivePracticeContent(source: .poetry, title: "Authored fixture", byline: nil,
      tokens: ["quiet", "harbor"], separator: " ")
    XCTAssertEqual(content.promptDescriptor(for: .words(701)).text.split(separator: " ").count, 100)
    for configuration in [TestConfiguration.timed(seconds: 30), .words(0), .words(100_001)] {
      XCTAssertEqual(content.promptDescriptor(for: configuration, showAllLines: true)
        .text.split(separator: " ").count, 100)
    }
  }
}
