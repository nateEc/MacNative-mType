import SwiftData
import XCTest
@testable import Typebar

final class OrdinaryTargetDirectoryTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 918_100_000)

  private func ordinaryResult() throws -> CompletedTestResult {
    var session = TypingSession(configuration: .words(2), prompt: "oak elm")
    session.insertBatch("oak elm", at: start)
    XCTAssertEqual(session.outcome, .completed)
    return try XCTUnwrap(session.result())
  }

  func testOrdinaryASCIICaptureKeepsLiteralCommitWithoutChangingTheInputPath() throws {
    let result = try ordinaryResult()
    let directory = try XCTUnwrap(result.targetWordDirectory)
    XCTAssertFalse(directory.noSpace)
    XCTAssertEqual(directory.words, ["oak ", "elm"])
    XCTAssertTrue(directory.matches(prompt: result.prompt, noSpace: false))
    XCTAssertFalse(result.replayEvents.contains(where: \.hasRawUTF16Metadata))
  }

  func testRealCustomFactoryPersistsFusedSourceFieldsForHistoryAndReplay() throws {
    var session = TestSessionFactory.make(configuration: .init(mode: .custom, duration: nil,
      wordLimit: 2, difficulty: .normal, rules: .init(), customTextCompletion: .words),
      customText: "a \u{301}b")
    session.insertBatch("a \u{301}x ", at: start)
    XCTAssertEqual(session.outcome, .completed)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.targetWordDirectory?.words, ["a ", "\u{301}b"])
    XCTAssertEqual(result.errorCount, 1)
    XCTAssertEqual(WeakSpotPractice.characterScores(results: [result], language: .english), ["b": 1])
    let plan = try XCTUnwrap(FieldReplayPlan.make(prompt: result.prompt, events: result.replayEvents,
      configuration: result.configuration, targetWordDirectory: result.targetWordDirectory))
    XCTAssertEqual(plan.initialFrame.fields.count, 2)
  }

  func testCopiedPromptAcceptsAnExplicitOrdinaryDirectoryInsteadOfAssumingNoSpace() throws {
    let result = try ordinaryResult()
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
    object["targetWordDirectory"] = ["words": ["oak ", "elm"], "noSpace": false]
    let captured = try JSONDecoder().decode(CompletedTestResult.self,
      from: JSONSerialization.data(withJSONObject: object))
    XCTAssertEqual(ResultPromptText.make(for: captured, reviews: []), "oak elm")
  }

  func testPortableAndArchiveRoundTripsPreserveTheActualDirectoryAndSavedMetrics() throws {
    let result = try ordinaryResult()
    let restored = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start)).results[0]
    XCTAssertNotNil(restored.targetWordDirectory)
    XCTAssertEqual(restored, result)
    XCTAssertEqual(TestResultRecord(result: result).portableResult, result)
  }

  func testProviderCatalogKeepsAnInternalNewlineInsteadOfResplittingIt() throws {
    let fields = ["north\nsouth ", "harbor ", "tail"]
    var session = TypingSession(configuration: .words(3), prompt: fields.joined(), sourceFields: fields)
    session.insert("n", at: start)
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.targetWordDirectory?.words, fields)
    XCTAssertEqual(ResultPromptText.make(for: result, reviews: []), fields[0])
  }

  func testLiteralReturnsTabsAndCombiningUnitsSurviveWithoutNormalization() throws {
    let prompt = "a\r\n\tb e\u{301}"
    var session = TypingSession(configuration: .words(3), prompt: prompt)
    session.insert("a", at: start)
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    let expected = ["a\r\n", "\tb ", "e\u{301}"]
    XCTAssertEqual(result.targetWordDirectory?.words.map { Array($0.utf16) }, expected.map { Array($0.utf16) })
    XCTAssertEqual(Array(try XCTUnwrap(result.targetWordDirectory).words.joined().utf16), Array(prompt.utf16))
  }

  func testQuoteGrowthAndPartialRepeatOnlyCaptureTheirOwnGeneratedTargets() throws {
    let words = (0..<205).map { "owned\($0)" }
    let quote = OfflineQuote(id: "owned-ordinary-directory-growth", title: "Owned targets",
      text: words.joined(separator: " "), language: .english, length: .long)
    var session = TestSessionFactory.make(configuration: .init(mode: .quote, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init()), quote: quote)
    session.insertBatch(quote.text, at: start)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.targetWordDirectory?.words.count, 205)
    XCTAssertEqual(result.targetWordDirectory?.words.joined(), session.prompt)
    var repeated = session.repeatedAttempt()
    repeated.insert(String(repeated.prompt.prefix(1)), at: start.addingTimeInterval(2))
    repeated.bailOut(at: start.addingTimeInterval(3))
    let partial = try XCTUnwrap(repeated.result())
    let partialDirectory = try XCTUnwrap(partial.targetWordDirectory)
    XCTAssertLessThan(partialDirectory.words.count, 205)
    XCTAssertEqual(partialDirectory.words.joined(), repeated.prompt)
  }

  func testLargeUntypedTailIsCapturedOnceWithoutChangingTheAttempt() throws {
    let prompt = String(repeating: "a ", count: 100_000) + "z"
    var session = TypingSession(configuration: .words(100_001), prompt: prompt)
    session.insert("a", at: start)
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    let directory = try XCTUnwrap(result.targetWordDirectory)
    XCTAssertEqual(directory.words.count, 100_001)
    XCTAssertEqual(directory.words.first, "a ")
    XCTAssertEqual(directory.words.last, "z")
    XCTAssertEqual(directory.words.joined(), prompt)
    XCTAssertEqual(session.typed, "a")
    XCTAssertEqual(result.replayEvents.count, 1)
  }

  func testGenuineLegacyOrdinaryArchivesKeepTheirMetricsWithoutBackfillingTargets() throws {
    let legacy = CompletedTestResult(id: UUID(), configuration: .words(2), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 7,
      correctCharacterCount: 6, errorCount: 1, wpm: 17, rawWpm: 29, accuracy: 77,
      prompt: "oak elm", replayEvents: [.init(offset: 0, kind: .insert, text: "xak elm")])
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    for version in 1...14 {
      let archive = TypebarArchive(version: version, exportedAt: start, settings: .init(), results: [legacy], presets: [])
      let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive)).results[0]
      XCTAssertNil(restored.targetWordDirectory)
      XCTAssertEqual(restored, legacy)
    }
  }

  func testOrdinaryDirectoryUsesExistingVersionFifteenMinimumAndRejectsMislabeledPayloads() throws {
    let fixture = CompletedTestResult(id: UUID(), configuration: .words(2), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 7,
      correctCharacterCount: 7, errorCount: 0, wpm: 17, rawWpm: 29, accuracy: 100,
      prompt: "oak elm", targetWordDirectory: .init(words: ["oak ", "elm"], noSpace: false))
    let archive = TypebarArchive(version: 1, exportedAt: start, settings: .init(), results: [fixture], presets: [])
    XCTAssertEqual(archive.version, 15)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(archive)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: data).results[0], fixture)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for version in 1...14 {
      object["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object)))
    }
  }

  func testZenStillHasNoInventedTargetDirectory() throws {
    var session = TypingSession(configuration: .init(mode: .zen, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()), prompt: "")
    session.insert("🙂", at: start)
    session.finishZen(at: start.addingTimeInterval(2))
    XCTAssertNil(try XCTUnwrap(session.result()).targetWordDirectory)
  }
}
