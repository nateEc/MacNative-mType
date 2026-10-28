import XCTest
@testable import Typebar

@MainActor final class GeneratedSectionProgressTests: XCTestCase {
  private struct Snapshot: Decodable {
    let active: Int, started: Bool, terminal: Bool, bailout: Bool, text: String, fraction: Double, duration: Double
  }
  private struct Fixture: Decodable { let indices: [Int], total: String, snapshots: [Snapshot] }
  private struct Generation: Decodable { let first: [Int], repeated: [Int] }
  private struct Output: Decodable { let fixtures: [Fixture], generation: Generation }

  private func source() throws -> Output {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-generated-section-progress.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    return try JSONDecoder().decode(Output.self, from: data)
  }

  func testCounterBarAndMemoUpdatesAgainstCompletePinnedLiveStatsAndActualSolid() throws {
    let fixtures = try source().fixtures
    XCTAssertEqual(fixtures.count, 21)
    var compared = 0
    for item in fixtures {
      var history = GeneratedWordReplayHistory(noSpace: false)
      item.indices.forEach { history.append(source: "owned", target: "owned", sectionIndex: $0) }
      history.append(source: "unpublished", target: "unpublished", sectionIndex: 999)
      let total = try XCTUnwrap(item.total == "Infinity" ? .infinity : Double(item.total))
      for sample in item.snapshots {
        let progress = GeneratedSectionProgress(history: history, publishedWords: item.indices.count,
          activeWord: sample.active, total: total)
        let bar = progress.bar(hasElapsed: sample.started, calculating: sample.terminal, bailedOut: sample.bailout)
        XCTAssertEqual(progress.text, sample.text)
        XCTAssertEqual(bar.fraction, sample.fraction, accuracy: 0.000000001)
        XCTAssertEqual(bar.duration * 1000, sample.duration)
        compared += 1
      }
    }
    XCTAssertGreaterThan(compared, 7_000)
  }

  func testStoredSectionIndicesSurviveRepeatedMultiwordHistoryAndFreshSuffix() throws {
    let expected = try source().generation
    var ranks = [0, 1, 2, 0]
    var cursor = GeneratedCandidateContinuation(configuration: .words(4), batchTokenCount: 4,
      sourceWords: ["ab cd", "ef gh", "ij kl"])
    _ = cursor.nextChunk(nextRandomWordIndex: { ranks.removeFirst() })
    XCTAssertTrue(ranks.isEmpty)
    XCTAssertEqual((0..<4).map { cursor.replayHistory.word(at: $0)?.sectionIndex }, expected.first.map(Optional.some))
    cursor.synchronizeConfiguration(.words(6))
    var repeated = cursor.replayingContinuation()
    ranks = [0, 0]
    _ = repeated.nextChunk(maximumWordCount: 2, nextRandomWordIndex: { ranks.removeFirst() })
    XCTAssertTrue(ranks.isEmpty)
    XCTAssertEqual((0..<6).map { repeated.replayHistory.word(at: $0)?.sectionIndex }, expected.repeated.map(Optional.some))
  }

  func testCachedSectionCounterTracksCurrentFieldAndFillsBarWithoutInventingFinalCount() async throws {
    var history = GeneratedWordReplayHistory(noSpace: false)
    ["ab", "cd", "ef"].forEach { history.append(source: $0, target: $0) }
    let custom = try WebsiteCustomTextSettings(value: .object([
      "text": .array([.string("Aa Bb"), .string("Cc")]), "mode": .string("repeat"),
      "limit": .object(["mode": .string("section"), "value": .number(5)]), "pipeDelimiter": .bool(false)]))
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom"}"#, pointsPerRem: 16, context: .init())
    var session = try await WebsiteConfigSessionBuilder.prepare(draft: draft,
      scope: .init(websiteCustomText: custom), attemptSource: .repeatedWords(history, repeatedPace: false),
      random: .init(wordIndex: { 0 })).session
    let start = Date(timeIntervalSince1970: 100)
    XCTAssertEqual(session.progressText(at: start), "0/5")
    XCTAssertEqual(session.progressFraction(at: start), 0)
    session.insertBatch("ab cd ef Aa ", at: start)
    XCTAssertEqual(session.progressText(at: start), "3/5")
    XCTAssertEqual(session.progressFraction(at: start), 0.6)
    session.insertBatch("Bb ", at: start)
    XCTAssertEqual(session.progressText(at: start), "4/5")
    session.insertBatch("Cc", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.progressText(at: start), "4/5")
    XCTAssertEqual(session.progressFraction(at: start), 1)
    let repeated = try await WebsiteConfigSessionBuilder.prepare(draft: draft,
      scope: .init(websiteCustomText: custom),
      attemptSource: .repeatedWords(try XCTUnwrap(session.generatedWordReplayHistory), repeatedPace: false))
    XCTAssertEqual(repeated.session.prompt, "ab cd ef Aa Bb")
    XCTAssertEqual(repeated.session.progressText(at: start), "0/5")
  }

  private func sectionSession(history: GeneratedWordReplayHistory, limit: Double, noSpace: Bool = false,
    freedom: Bool = false) async throws -> TypingSession {
    let custom = try WebsiteCustomTextSettings(value: .object([
      "text": .array([.string("unused")]), "mode": .string("repeat"),
      "limit": .object(["mode": .string("section"), "value": .number(limit)]), "pipeDelimiter": .bool(false)]))
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      "{\"mode\":\"custom\",\"freedomMode\":\(freedom),\"funbox\":\(noSpace ? "[\"nospace\"]" : "[]")}", pointsPerRem: 16, context: .init())
    return try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(websiteCustomText: custom),
      attemptSource: .repeatedWords(history, repeatedPace: false), random: .init(wordIndex: { 0 })).session
  }

  func testRawFractionZeroAndInfinityRemainDistinctAcrossInputAndRepeat() async throws {
    var history = GeneratedWordReplayHistory(noSpace: false)
    for index in 0..<200 { history.append(source: "a", target: "a", sectionIndex: index / 2 + 1) }
    let start = Date(timeIntervalSince1970: 100)
    var finite = try await sectionSession(history: history, limit: 4.5)
    XCTAssertEqual(finite.sectionProgress?.total, 4.5)
    XCTAssertEqual(finite.progressText(at: start), "0/4.5")
    finite.insertBatch("a a a a ", at: start)
    XCTAssertEqual(finite.progressText(at: start), "2/4.5")
    XCTAssertEqual(finite.progressFraction(at: start), 0.44)
    finite.insertBatch("a", at: start)
    XCTAssertEqual(finite.outcome, .completed)
    XCTAssertEqual(finite.progressText(at: start), "2/4.5")
    XCTAssertEqual(finite.progressFraction(at: start), 1)
    XCTAssertEqual(finite.repeatedAttempt().progressText(at: start), "0/4.5")

    var zero = try await sectionSession(history: history, limit: 0)
    zero.insertBatch("a ", at: start)
    XCTAssertEqual(zero.progressText(at: start), "1", "Zero uses active word index, not stored section index")
    XCTAssertEqual(zero.sectionProgress?.completed, 0)
    XCTAssertEqual(zero.progressLabel, "词数")
    XCTAssertEqual(zero.progressFraction(at: start), 0)

    var infinite = try await sectionSession(history: history, limit: .infinity)
    infinite.insertBatch(String(repeating: "a ", count: 200) + String(repeating: "unused ", count: 5), at: start)
    XCTAssertEqual(infinite.outcome, .active)
    XCTAssertEqual(infinite.errors, 0)
    XCTAssertEqual(infinite.progressText(at: start), "205/Infinity")
    XCTAssertEqual(infinite.sectionProgress?.total, .infinity)
    XCTAssertEqual(infinite.progressFraction(at: start), 0)
    infinite.bailOut(at: start.addingTimeInterval(1))
    XCTAssertEqual(infinite.outcome, .bailedOut)
    XCTAssertEqual(infinite.progressFraction(at: start), 0)
  }

  func testNoSpaceFieldIdentityAndWordDeletionRewindTheStoredSectionCounter() async throws {
    var history = GeneratedWordReplayHistory(noSpace: true)
    for (index, word) in ["🇺", "🇸", "e\u{301}", "界"].enumerated() {
      history.append(source: word, target: word, sectionIndex: index / 2 + 1)
    }
    var session = try await sectionSession(history: history, limit: 4, noSpace: true, freedom: true)
    let start = Date(timeIntervalSince1970: 100)
    session.insertBatch("🇺", at: start)
    XCTAssertEqual(session.progressText(at: start), "0/4")
    session.insertBatch("🇸e\u{301}", at: start)
    XCTAssertEqual(session.progressText(at: start), "1/4")
    session.deleteWordBackward(at: start)
    session.deleteWordBackward(at: start)
    XCTAssertEqual(session.progressText(at: start), "0/4")
    session.insertBatch("🇸e\u{301}界", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.progressText(at: start), "1/4")
    XCTAssertEqual(session.progressFraction(at: start), 1)
  }
}
