import XCTest
import SwiftData
@testable import Typebar

final class TargetWordDirectoryTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 908_900_000)

  func testFusedGenerationRetainsWordsWithoutInventingGraphemeOffsets() {
    for words in [["a", "\u{301}"], ["ᄀ", "ᅡ"], ["🇫", "🇷"], ["👩", "‍", "💻"]] {
      let batch = TransformedPromptBatch(text: words.joined(), noSpaceTargetWords: words)
      XCTAssertEqual(batch.noSpaceTargetWords.map { Array($0.utf16) }, words.map { Array($0.utf16) })
      XCTAssertEqual(batch.noSpaceWordLengths, [])
    }
  }

  func testCanonicalEquivalenceCannotSubstituteForActualGeneratedUnits() {
    let batch = TransformedPromptBatch(text: "éx", noSpaceTargetWords: ["e\u{301}", "x"])
    XCTAssertEqual(batch.noSpaceTargetWords, [])
    XCTAssertEqual(batch.noSpaceWordLengths, [])
  }

  private func savedWords(_ result: CompletedTestResult) throws -> [String]? {
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
    return (object["targetWordDirectory"] as? [String: Any])?["words"] as? [String]
  }

  func testActualEmptyTransformedWordSurvivesBothResultCodecs() throws {
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.morseStream])
    var session = TestSessionFactory.make(configuration: configuration, customText: "e 中 t")
    session.insertBatch("./-/", at: start)
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    for restored in [result, try XCTUnwrap(TestResultRecord(result: result).portableResult),
      try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
        settings: .init(), results: [result], presets: [], at: start)).results[0]] {
      XCTAssertEqual(try savedWords(restored), ["./", "", "-/"])
      XCTAssertEqual(restored.wpm, result.wpm)
    }
  }

  func testActualFusedQuoteGrowthSavesAllDrawsAndRepeatSavesItsOwnInitialDraws() throws {
    let words = ["a", "\u{301}"] + Array(repeating: "b", count: 203)
    let configuration = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces])
    var session = TestSessionFactory.make(configuration: configuration,
      quote: .init(id: "owned-directory-probe", title: "Directory", text: words.joined(separator: " "),
        language: .english, length: .long))
    session.insertBatch(words.joined(), at: start)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(try savedWords(result)?.map { Array($0.utf16) }, words.map { Array($0.utf16) })
    var repeated = session.repeatedAttempt()
    repeated.insert("a\u{301}", at: start)
    repeated.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(try savedWords(try XCTUnwrap(repeated.result()))?.count, 102)
  }

  private func noSpaceResult() throws -> CompletedTestResult {
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces])
    var session = TestSessionFactory.make(configuration: configuration, customText: "ab cd")
    session.insertBatch("xb", at: start)
    session.insertBatch("cd", at: start.addingTimeInterval(2))
    return try XCTUnwrap(session.result())
  }

  func testActualNoSpaceResultAndRestoredChartsCreditLaterCorrectWord() throws {
    let result = try noSpaceResult()
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [result], presets: [], at: start))
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    for restored in [result, archive.results[0], try XCTUnwrap(TestResultRecord(result: result).portableResult)] {
      XCTAssertEqual(restored.targetWordDirectory?.words, ["ab", "cd"])
      XCTAssertEqual(restored.wpm, 12)
      XCTAssertEqual(restored.inputMetrics?.creditedUnits, 2)
      let points = ResultPerformanceTrace.points(prompt: restored.prompt, events: restored.replayEvents,
        duration: 2, configuration: restored.configuration, targetWordDirectory: restored.targetWordDirectory)
      XCTAssertEqual(points.map(\.wpm), [0,12])
      XCTAssertEqual(points.map(\.rawWpm), [24,24])
      XCTAssertEqual(points.last, ResultPerformanceTrace.point(prompt: restored.prompt,
        events: restored.replayEvents, elapsed: 2, configuration: restored.configuration,
        targetWordDirectory: restored.targetWordDirectory))
    }
  }

  func testDirectoryKeepsCommitUnitsEmptySlotsAndNonGlyphRangesExactly() {
    let directory = ResultTargetWordDirectory(words: ["a", "\u{301}", "", "\r\n", "🙂"], noSpace: true)
    XCTAssertEqual(directory.unitRanges, [0..<1,1..<2,2..<2,2..<4,4..<6])
    XCTAssertEqual(directory.words.map { Array($0.utf16) }, [[97],[769],[],[13,10],[55357,56898]])
    XCTAssertTrue(directory.matches(prompt: "a\u{301}\r\n🙂", noSpace: true))
    XCTAssertFalse(directory.matches(prompt: "á\r\n🙂", noSpace: true))
    XCTAssertFalse(directory.matches(prompt: "a\u{301}\r\n🙂", noSpace: false))
    XCTAssertNotEqual(ResultTargetWordDirectory(words: ["é"], noSpace: true),
      ResultTargetWordDirectory(words: ["e\u{301}"], noSpace: true))
  }

  func testNoSpaceFieldChartUsesCapturedUTF16TargetsIncludingFusedAndEmptyFields() {
    let configuration = TestConfiguration(mode: .time, duration: 2, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces])
    let directory = ResultTargetWordDirectory(words: ["a", "\u{301}", "", "🙂"], noSpace: true)
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, units: [120], inputField: .init(index: 0, units: [120]), inputCorrectness: [false]),
      .init(offset: 1, kind: .insert, units: [769], inputField: .init(index: 1, units: [769]), inputCorrectness: [true]),
      .init(offset: 2, kind: .insert, units: [55357], inputField: .init(index: 3, units: [55357]), inputCorrectness: [true])]
    let point = ResultPerformanceTrace.point(prompt: directory.words.joined(), events: events,
      elapsed: 2, configuration: configuration, targetWordDirectory: directory)
    XCTAssertEqual(point.wpm, 12)
    XCTAssertEqual(point.rawWpm, 18)
    XCTAssertEqual(point.burstWpm, 12)
    XCTAssertEqual(point.errorCount, 0)
  }

  func testAllEmptyActualTargetsCanKeepAnErrorActivityChartWithoutWordCredit() throws {
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.morseStream])
    var session = TestSessionFactory.make(configuration: configuration, customText: "中 Ａ")
    session.insert(".", at: start)
    session.bailOut(at: start.addingTimeInterval(2))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.targetWordDirectory?.words, ["", ""])
    let points = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
      duration: 2, configuration: result.configuration, targetWordDirectory: result.targetWordDirectory)
    XCTAssertEqual(points.map(\.wpm), [0,0])
    XCTAssertEqual(points.map(\.rawWpm), [12,6])
    XCTAssertEqual(points.map(\.errorCount), [1,0])
  }

  @MainActor func testInMemorySwiftDataSaveFetchPreservesDirectoryWithoutRescoring() throws {
    let result = try noSpaceResult()
    let container = try ModelContainer(for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    context.insert(TestResultRecord(result: result))
    try context.save()
    let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(fetched.targetWordDirectory, result.targetWordDirectory)
    XCTAssertEqual(fetched.portableResult, result)
  }

  func testArchiveWithTargetsCannotBeMislabeledAsOneThroughFourteen() throws {
    let result = try noSpaceResult()
    let data = try TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: start)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for version in 1...14 {
      XCTAssertEqual(TypebarArchive(version: version, exportedAt: start, settings: .init(),
        results: [result], presets: []).version, 16)
      object["version"] = version
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: object))) {
        XCTAssertEqual($0 as? DataTransferError, .unsupportedVersion(version))
      }
    }
  }

  func testInvalidDirectoryCannotBeImportedAsTrustedGenerationMetadata() throws {
    let result = try noSpaceResult()
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
    for directory in [ResultTargetWordDirectory(words: ["ab", "cx"], noSpace: true),
      .init(words: ["ab", "cd"], noSpace: false), .init(words: [], noSpace: true)] {
      object["targetWordDirectory"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(directory))
      XCTAssertThrowsError(try JSONDecoder().decode(CompletedTestResult.self,
        from: JSONSerialization.data(withJSONObject: object)))
    }
  }

  func testGenuineLegacyArchivesDoNotBackfillWordsOrRecomputeMetrics() throws {
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces])
    let old = CompletedTestResult(id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(2), typedCharacterCount: 4,
      correctCharacterCount: 3, errorCount: 1, wpm: 17, rawWpm: 29, accuracy: 75,
      prompt: "abcd", replayEvents: [.init(offset: 0, kind: .insert, text: "xbcd")])
    for version in 1...14 {
      let archive = TypebarArchive(version: version, exportedAt: start, settings: .init(), results: [old], presets: [])
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      let restored = try TypebarDataTransfer.importArchive(from: encoder.encode(archive)).results[0]
      XCTAssertNil(restored.targetWordDirectory)
      XCTAssertEqual(restored, old)
      XCTAssertEqual(TestResultRecord(result: restored).portableResult, old)
    }
  }

  func testSavedDirectoryDoesNotInventMissingFieldsOrAcceptOutOfRangeIndices() {
    let configuration = TestConfiguration(mode: .time, duration: 2, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces])
    let directory = ResultTargetWordDirectory(words: ["ab", "cd"], noSpace: true)
    for event in [TypingReplayEvent(offset: 0, kind: .insert, text: "xbcd"),
      .init(offset: 0, kind: .insert, text: "xbcd", inputField: .init(index: Int.max, value: "xbcd")),
      .init(offset: 0, kind: .insert, text: "xbcd", inputField: .init(index: -1, value: "xbcd"))] {
      let legacy = ResultPerformanceTrace.point(prompt: "abcd", events: [event], elapsed: 2,
        configuration: configuration)
      XCTAssertEqual(ResultPerformanceTrace.point(prompt: "abcd", events: [event], elapsed: 2,
        configuration: configuration, targetWordDirectory: directory), legacy)
    }
  }

  func testDirectoryChartComparesLiteralCommitAndKeepsLaterCredit() {
    let configuration = TestConfiguration(mode: .time, duration: 2, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces])
    let directory = ResultTargetWordDirectory(words: ["é\n", "beta", ""], noSpace: true)
    let events: [TypingReplayEvent] = [
      .init(offset: 0, kind: .insert, units: [233], inputField: .init(index: 0, units: [233]), inputCorrectness: [true]),
      .init(offset: 0, kind: .insert, units: [32], inputField: .init(index: 0, units: [233,32]), inputCorrectness: [false]),
      .init(offset: 2, kind: .insert, units: [98,101,116,97], inputField: .init(index: 1, units: [98,101,116,97]),
        inputCorrectness: [true,true,true,true])]
    let point = ResultPerformanceTrace.point(prompt: directory.words.joined(), events: events,
      elapsed: 2, configuration: configuration, targetWordDirectory: directory)
    XCTAssertEqual(point.wpm, 24)
    XCTAssertEqual(point.rawWpm, 36)
    XCTAssertEqual(point.burstWpm, 48)
    XCTAssertEqual(point.errorCount, 0)
  }

  func testQuoteThatFusesDuringRefillStillSavesEveryActualWord() throws {
    let words = Array(repeating: "a", count: 100) + ["\u{301}"] + Array(repeating: "b", count: 104)
    let configuration = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces])
    var session = TestSessionFactory.make(configuration: configuration,
      quote: .init(id: "owned-late-directory-probe", title: "Late directory", text: words.joined(separator: " "),
        language: .english, length: .long))
    session.insertBatch(words.joined(), at: start)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.targetWordDirectory?.words.map { Array($0.utf16) }, words.map { Array($0.utf16) })
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), words)
    XCTAssertEqual(session.wordReviews.map(\.typed), words)
  }

  func testEqualGlyphCountsDoNotProveARegionalIndicatorWordBoundary() {
    let words = ["🇫", "🇷🇨"]
    XCTAssertEqual(words.map(\.count), [1,1])
    XCTAssertEqual(words.joined().count, 2)
    let batch = TransformedPromptBatch(text: words.joined(), noSpaceTargetWords: words)
    XCTAssertEqual(batch.noSpaceTargetWords, words)
    XCTAssertEqual(batch.noSpaceWordLengths, [])
    let aligned = ["🇫🇷", "🇨🇱"]
    XCTAssertEqual(TransformedPromptBatch(text: aligned.joined(), noSpaceTargetWords: aligned)
      .noSpaceWordLengths, [1,1], "Actual aligned flag boundaries remain eligible")
  }

  func testEqualCountFlagFusionUsesActualUnitFieldsInsteadOfWrongGlyphSlices() throws {
    let words = ["🇫", "🇷🇨"]
    let configuration = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces])
    var session = TestSessionFactory.make(configuration: configuration,
      quote: .init(id: "owned-ri-directory-probe", title: "RI directory", text: words.joined(separator: " "),
        language: .english, length: .short), showAllLines: true)
    let glyphs = Array(words.joined())
    session.insert(String(glyphs[0]), at: start)
    session.insert(String(glyphs[1]), at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.inputMetrics?.creditedUnits, 6)
    XCTAssertEqual(result.wpm, 72)
    XCTAssertEqual(result.targetWordDirectory?.words, words)
    XCTAssertEqual(session.wordReviews.map(\.target), words)
    XCTAssertEqual(session.wordReviews.map(\.typed), words)
  }

  func testEqualCountFlagFusionDuringRefillKeepsActualUnitNavigation() throws {
    let words = Array(repeating: "a", count: 99) + ["🇫", "🇷🇨", "b"]
    let configuration = TestConfiguration(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), modifiers: [.noSpaces])
    var session = TestSessionFactory.make(configuration: configuration,
      quote: .init(id: "owned-late-ri-directory-probe", title: "Late RI directory", text: words.joined(separator: " "),
        language: .english, length: .long))
    session.insert("a", at: start)
    XCTAssertEqual(Array(session.prompt.utf16), Array(words.prefix(101).joined().utf16))
    session.bailOut(at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.targetWordDirectory?.words, Array(words.prefix(101)))
    XCTAssertEqual(session.wordReviews.map(\.target), ["a"])
  }
}
