import XCTest
@testable import Typebar

@MainActor final class GeneratedReplayFramingTests: XCTestCase {
  func testRepeatedWordsKeepTheirOwnCommitCharactersWhenNoSpaceChanges() async throws {
    for oldNoSpace in [false, true] { for newNoSpace in [false, true] where oldNoSpace != newNoSpace {
      let old = TestConfiguration.words(3).with(modifiers: oldNoSpace ? [.noSpaces] : [])
      let original = TestSessionFactory.make(configuration: old, nextRandomWordIndex: { 0 })
      let history = try XCTUnwrap(original.generatedWordReplayHistory)
      let incoming = try WebsiteConfigNativeProfile.prepareDraft(
        "{\"mode\":\"words\",\"words\":3,\"funbox\":\(newNoSpace ? "[\"nospace\"]" : "[]")}", pointsPerRem: 16, context: .init())
      let ready = try await WebsiteConfigSessionBuilder.prepare(draft: incoming, scope: .init(),
        attemptSource: .repeatedWords(history, repeatedPace: false))
      var session = ready.session
      XCTAssertEqual(session.prompt, original.prompt)
      let targets = try (0..<3).map { try XCTUnwrap(history.word(at: $0)).target }
      let tape = targets.enumerated().map { index, word in
        word + (index == 2 ? "" : oldNoSpace ? " " : "x")
      }.joined()
      if newNoSpace {
        session.insertBatch(" ", at: Date(timeIntervalSince1970: 9))
        XCTAssertEqual(session.errors, 0, "Current No Space still blocks spaces")
      }
      session.insertBatch(tape, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.completedWordCount, 3)
      XCTAssertEqual(session.errors, 2)
      XCTAssertEqual(session.repeatedAttempt().prompt, session.prompt)
    }}
  }

  func testMixedReplayFramingAgainstPinnedGeneratorAndInputHelpers() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Event: Decodable { let blocked: Bool; let correct: Bool? }
    struct Fixture: Decodable {
      let pool: [String], oldNoSpace: Bool, newNoSpace: Bool
      let fields: [String], returnedFields: [String], tape: String, events: [Event]
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-generated-backwards-order.mjs").path, reference, "--replay-framing"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 8)
    for item in fixtures {
      let configuration = TestConfiguration.words(5).with(modifiers: item.newNoSpace ? [.noSpaces] : [])
      var history = GeneratedWordReplayHistory(noSpace: item.oldNoSpace)
      item.pool.forEach { history.append(source: $0, target: $0) }
      var cursor = GeneratedCandidateContinuation(configuration: configuration, batchTokenCount: 5,
        sourceWords: item.pool, replayHistory: history)
      var ranks = [0, 1]
      let chunk = cursor.nextChunk(maximumWordCount: 5,
        nextRandomWordIndex: { ranks.removeFirst() }, nextRandomCaseBit: { false }, nextRandomContentUnit: { 0.5 })
      XCTAssertTrue(ranks.isEmpty)
      let batch = FinitePromptCommitPolicy.finalized(TransformedPromptBatch(text: chunk.transformed,
        noSpaceTargetWords: chunk.noSpaceTargetWords, sourceFields: chunk.sourceFields))
      XCTAssertEqual(batch.text, item.fields.joined())
      if item.oldNoSpace != item.newNoSpace { XCTAssertEqual(batch.sourceFields, item.fields) }
      var session = TypingSession(configuration: configuration, prompt: item.fields.joined(),
        sourceFields: item.fields, noSpaceTargetWords: item.newNoSpace ? item.fields : [])
      session.insertBatch(item.tape, at: Date(timeIntervalSince1970: 10))
      XCTAssertEqual(session.outcome, .completed, "\(item)")
      XCTAssertEqual(session.completedWordCount, 5)
      XCTAssertEqual(session.errors, item.events.filter { !$0.blocked && $0.correct == false }.count)
      let returnedConfig = TestConfiguration.words(7).with(modifiers: item.oldNoSpace ? [.noSpaces] : [])
      var returned = GeneratedCandidateContinuation(configuration: returnedConfig, batchTokenCount: 7,
        sourceWords: item.pool, replayHistory: cursor.replayHistory)
      ranks = [2, 0]
      let returnedChunk = returned.nextChunk(maximumWordCount: 7,
        nextRandomWordIndex: { ranks.removeFirst() }, nextRandomCaseBit: { false }, nextRandomContentUnit: { 0.5 })
      XCTAssertTrue(ranks.isEmpty)
      let returnedBatch = FinitePromptCommitPolicy.finalized(TransformedPromptBatch(text: returnedChunk.transformed,
        noSpaceTargetWords: returnedChunk.noSpaceTargetWords, sourceFields: returnedChunk.sourceFields))
      XCTAssertEqual(returnedBatch.text, item.returnedFields.joined())
      if item.oldNoSpace != item.newNoSpace { XCTAssertEqual(returnedBatch.sourceFields, item.returnedFields) }
    }
  }

  func testChangedFramingSurvivesLookaheadRefillAndASecondRepeat() async throws {
    for oldNoSpace in [false, true] {
      var history = GeneratedWordReplayHistory(noSpace: oldNoSpace)
      let words = (0..<103).map { $0.isMultiple(of: 2) ? "ab" : "cd" }
      words.forEach { history.append(source: $0, target: $0) }
      let draft = try WebsiteConfigNativeProfile.prepareDraft(
        "{\"mode\":\"words\",\"words\":103,\"funbox\":\(oldNoSpace ? "[]" : "[\"nospace\"]")}",
        pointsPerRem: 16, context: .init())
      var session = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(),
        attemptSource: .repeatedWords(history, repeatedPace: false)).session
      let opening = words.prefix(100).map { $0 + (oldNoSpace ? "" : " ") }.joined()
      XCTAssertEqual(session.prompt, opening)
      let tape = words.enumerated().map { index, word in
        word + (index == words.count - 1 ? "" : oldNoSpace ? " " : "x")
      }.joined()
      for attempt in 0..<2 {
        session.insertBatch(tape, at: Date(timeIntervalSince1970: Double(10 + attempt)))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.completedWordCount, 103)
        XCTAssertEqual(session.errors, 102)
        XCTAssertEqual(session.prompt, words.joined(separator: oldNoSpace ? "" : " "))
        XCTAssertEqual(session.wordReviews.count, 103)
        if attempt == 0 { session = session.repeatedAttempt() }
      }
    }
  }
}
