import XCTest
@testable import Typebar

final class GeneratedLiveSettingsTests: XCTestCase {
  private let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india"]
  private let start = Date(timeIntervalSince1970: 100)
  private func opening(_ configuration: TestConfiguration = .words(5)) -> TypingSession {
    var cursor = GeneratedCandidateContinuation(configuration: configuration, batchTokenCount: 5,
      sourceWords: [words.joined(separator: " ")])
    let chunk = cursor.nextChunk(nextRandomWordIndex: { 0 })
    return .init(configuration: configuration, prompt: chunk.transformed + (cursor.hasRemaining ? " " : ""),
      generatedCodeContinuation: cursor.hasRemaining ? cursor : nil,
      retainedCandidateContinuation: cursor.hasRemaining ? nil : cursor)
  }
  private func finish(_ session: inout TypingSession) {
    for _ in 0..<600 where !session.isFinished {
      session.insertBatch(session.nextExpectedCharacter.map(String.init) ?? " ", at: start.addingTimeInterval(1))
    }
  }
  func testExhaustedOpeningResumesItsPendingSectionInsteadOfRebuildingPool() {
    var session = opening()
    session.insertBatch("a", at: start)
    let before = session.generationState, prompt = session.prompt
    XCTAssertFalse(session.usesIncrementalPromptExtension)
    XCTAssertTrue(session.synchronizeWebsiteGeneratedConfiguration(.words(17).with(modifiers: [.noQuit])))
    XCTAssertEqual(session.prompt, prompt); XCTAssertEqual(session.typed, before.typed)
    XCTAssertEqual(session.automaticInputAttemptID, before.attempt); XCTAssertEqual(session.promptTargetID, before.target)
    finish(&session)
    XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.completedWordCount, 17)
    XCTAssertEqual(session.prompt.split(separator: " ").map(String.init), (words + words).prefix(17).map { $0 })
    XCTAssertTrue(session.prompt.contains("echo foxtrot golf"))
  }
  func testLowerLimitStillConsumesAllAlreadyGeneratedTargets() {
    var session = opening()
    session.insertBatch("alpha ", at: start)
    XCTAssertTrue(session.synchronizeWebsiteGeneratedConfiguration(.words(3).with(modifiers: [.noQuit])))
    session.insertBatch("bravo charlie", at: start.addingTimeInterval(1))
    XCTAssertFalse(session.isFinished)
    finish(&session)
    XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.completedWordCount, 5)
    XCTAssertEqual(session.configuration.wordLimit, 3)
  }
  func testSwitchToTimedModeRetainsStartAndFinishesAtNewLimit() {
    var session = opening()
    session.insertBatch("a", at: start)
    var next = TestConfiguration.words(5).with(modifiers: [.noQuit])
    next.mode = .time; next.wordLimit = nil; next.duration = 2.5
    XCTAssertTrue(session.synchronizeWebsiteGeneratedConfiguration(next))
    session.tick(at: start.addingTimeInterval(2.49)); XCTAssertFalse(session.isFinished)
    session.tick(at: start.addingTimeInterval(2.5)); XCTAssertEqual(session.outcome, .completed)
  }
  func testSwitchFromTimeToWordsDoesNotTruncateLoadedQueue() {
    var timed = TestConfiguration.words(5)
    timed.mode = .time; timed.wordLimit = nil; timed.duration = 30
    var session = opening(timed)
    session.insertBatch("a", at: start)
    XCTAssertTrue(session.synchronizeWebsiteGeneratedConfiguration(.words(3).with(modifiers: [.noQuit])))
    session.insertBatch("lpha bravo charlie delta echo", at: start.addingTimeInterval(1))
    XCTAssertFalse(session.isFinished, "The retained timed field still requires its commit")
    session.insertBatch(" ", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed); XCTAssertEqual(session.completedWordCount, 5)
  }
  func testUnrelatedGeneratorChangesCannotReplaceInitializedPool() {
    var session = opening()
    session.insertBatch("a", at: start)
    let before = session.generationState
    var next = TestConfiguration.words(17).with(modifiers: [.noQuit]); next.language = .spanish
    XCTAssertFalse(session.synchronizeWebsiteGeneratedConfiguration(next))
    XCTAssertEqual(session.generationState, before)
    XCTAssertFalse(session.synchronizeWebsiteGeneratedConfiguration(.words(17).with(modifiers: [.noQuit, .backwards])))
    XCTAssertEqual(session.generationState, before)
    var noSpace = opening(.words(5).with(modifiers: [.noSpaces]))
    XCTAssertFalse(noSpace.synchronizeWebsiteGeneratedConfiguration(.words(17).with(modifiers: [.noSpaces, .noQuit])))
  }

  func testInfiniteLimitKeepsGeneratingWithoutCompletingHeldQueue() {
    var session = opening()
    session.insertBatch("a", at: start)
    XCTAssertTrue(session.synchronizeWebsiteGeneratedConfiguration(.words(0).with(modifiers: [.noQuit])))
    for _ in 0..<200 {
      session.insertBatch(session.nextExpectedCharacter.map(String.init) ?? " ", at: start.addingTimeInterval(1))
    }
    XCTAssertFalse(session.isFinished); XCTAssertGreaterThan(session.completedWordCount, 5)
    XCTAssertEqual(session.configuration.wordLimit, 0)
  }

  func testOrdinaryLiveCursorAndTimerAgainstCompletePinnedGenerator() throws {
    try compareGeneratorWithSource(noSpace: false)
    try compareGeneratorWithSource(noSpace: true)
    try compareGeneratorWithSource(noSpace: true, unicode: true)
  }

  private func compareGeneratorWithSource(noSpace: Bool, unicode: Bool = false) throws {
    struct Output: Decodable {
      struct Fixture: Decodable {
        struct Chunk: Decodable { let words: [String], remaining: Bool }
        struct TimeCheck: Decodable { let elapsed: Double, finished: Bool }
        let mode: String, limitMode: String, limit: Double, initialCount: Int
        let initial: [String], chunks: [Chunk], timeChecks: [TimeCheck]
      }
      let pool: [String], fixtures: [Fixture]
    }
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires complete pinned wordset/generator and timer")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-custom-live-settings.mjs").path,
      reference, unicode ? "--ordinary-unicode" : noSpace ? "--ordinary-no-space" : "--ordinary"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { return XCTFail("Pinned ordinary generator probe failed") }
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 9)
    for fixture in output.fixtures {
      var config = TestConfiguration.words(fixture.initialCount)
      if noSpace { config = config.with(modifiers: [.noSpaces]) }
      if fixture.mode == "time" { config.mode = .time; config.wordLimit = nil; config.duration = 30 }
      var cursor = GeneratedCandidateContinuation(configuration: config, batchTokenCount: fixture.initialCount,
        sourceWords: output.pool)
      let chunk = cursor.nextChunk(nextRandomWordIndex: { 0 })
      XCTAssertEqual(noSpace ? chunk.noSpaceTargetWords : chunk.transformed.split(separator: " ").map(String.init), fixture.initial)
      let hadFuture = cursor.hasRemaining
      var next = TestConfiguration.words(Int(fixture.limit.rounded(.up)))
        .with(modifiers: noSpace ? [.noSpaces, .noQuit] : [.noQuit])
      if fixture.limitMode == "time" { next.mode = .time; next.wordLimit = nil; next.duration = fixture.limit }
      cursor.synchronizeConfiguration(next)
      for chunk in fixture.chunks {
        let generated = cursor.nextChunk(maximumWordCount: 100, nextRandomWordIndex: { 0 })
        XCTAssertEqual(noSpace ? generated.noSpaceTargetWords : generated.transformed.split(separator: " ").map(String.init), chunk.words,
          "\(fixture.mode) → \(fixture.limitMode)/\(fixture.limit)")
        XCTAssertEqual(cursor.hasRemaining, chunk.remaining)
      }
      for check in fixture.timeChecks {
        var retained = GeneratedCandidateContinuation(configuration: config, batchTokenCount: fixture.initialCount,
          sourceWords: output.pool)
        _ = retained.nextChunk(nextRandomWordIndex: { 0 })
        var session = TypingSession(configuration: config, prompt: chunk.transformed + (hadFuture && !noSpace ? " " : ""),
          generatedCodeContinuation: hadFuture ? retained : nil, retainedCandidateContinuation: hadFuture ? nil : retained,
          noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(for: chunk.noSpaceWordLengths),
          noSpaceTargetWords: chunk.noSpaceTargetWords)
        session.insertBatch("a", at: start)
        XCTAssertFalse(session.isFinished, "The live receipt requires an active attempt")
        XCTAssertTrue(session.synchronizeWebsiteGeneratedConfiguration(next))
        session.tick(at: start.addingTimeInterval(check.elapsed))
        XCTAssertEqual(session.isFinished, check.finished)
      }
    }
  }

  func testGrowthAtOldFinalWordKeepsSourceEventPositionsUntilCommit() throws {
    try compareLiveInputWithSource(noSpace: false)
  }

  func testNoSpaceLiveLimitsKeepSourceWordBoundariesAndInputOutcomes() throws {
    try compareLiveInputWithSource(noSpace: true)
  }

  func testNoSpaceLiveGrowthKeepsUTF16FieldsAcrossJoinedGlyphs() {
    let config = TestConfiguration.words(2).with(modifiers: [.noSpaces])
    var cursor = GeneratedCandidateContinuation(configuration: config, batchTokenCount: 2,
      sourceWords: ["e \u{301} 🙂 x"])
    let chunk = cursor.nextChunk(nextRandomWordIndex: { 0 })
    XCTAssertEqual(chunk.noSpaceTargetWords, ["e", "\u{301}"])
    var session = TypingSession(configuration: config, prompt: chunk.transformed,
      retainedCandidateContinuation: cursor,
      noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(for: chunk.noSpaceWordLengths),
      noSpaceTargetWords: chunk.noSpaceTargetWords)
    session.insertBatch("e", at: start)
    let before = session.generationState
    guard session.synchronizeWebsiteGeneratedConfiguration(.words(4).with(modifiers: [.noSpaces, .noQuit])) else {
      return XCTFail("Complete UTF-16 field catalog was refused because its glyph boundaries join")
    }
    XCTAssertEqual(session.automaticInputAttemptID, before.attempt)
    XCTAssertEqual(session.promptTargetID, before.target)
    XCTAssertEqual(session.typed, before.typed)
    session.insertBatch("\u{301}🙂x", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.prompt, "e\u{301}🙂x")
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 4)
    XCTAssertEqual(session.preciseAccuracy, 100)
    XCTAssertEqual(Array(session.typed.utf16), Array("e\u{301}🙂x".utf16))
  }

  private func compareLiveInputWithSource(noSpace: Bool) throws {
    struct Output: Decodable {
      struct Fixture: Decodable {
        struct Event: Decodable, Equatable { let wordIndex: Int, charIndex: Int, lastWord: Bool, correct: Bool }
        let count: Int, prefix: String, suffix: String, initialMode: String, nextCount: Int
        let pool: [String], difficulty: String, stop: String, finished: Bool, failed: Bool, events: [Event]
      }
      let fixtures: [Fixture]
    }
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires complete pinned input and navigation modules")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-input-position.mjs").path,
      reference, noSpace ? "--no-space-live-fixtures" : "--ordinary-live-growth-fixtures"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { return XCTFail("Pinned ordinary input probe failed") }
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, noSpace ? 40 : 35)
    for fixture in fixtures {
      var config = TestConfiguration.words(fixture.count)
      if noSpace { config = config.with(modifiers: [.noSpaces]) }
      config.difficulty = try XCTUnwrap(Difficulty(rawValue: fixture.difficulty))
      config.rules.stopOnErrorMode = try XCTUnwrap(StopOnErrorMode(rawValue: fixture.stop))
      if fixture.initialMode == "time" { config.mode = .time; config.wordLimit = nil; config.duration = 30 }
      var cursor = GeneratedCandidateContinuation(configuration: config, batchTokenCount: fixture.count,
        sourceWords: [fixture.pool.joined(separator: " ")])
      let chunk = cursor.nextChunk(nextRandomWordIndex: { 0 })
      var session = TypingSession(configuration: config, prompt: chunk.transformed + (cursor.hasRemaining && !noSpace ? " " : ""),
        generatedCodeContinuation: cursor.hasRemaining ? cursor : nil,
        retainedCandidateContinuation: cursor.hasRemaining ? nil : cursor,
        noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(for: chunk.noSpaceWordLengths),
        noSpaceTargetWords: chunk.noSpaceTargetWords)
      for char in fixture.prefix { session.insertBatch(String(char), at: start) }
      var next = config.with(modifiers: noSpace ? [.noSpaces, .noQuit] : [.noQuit])
      next.mode = .words; next.duration = nil; next.wordLimit = fixture.nextCount
      guard session.synchronizeWebsiteGeneratedConfiguration(next) else {
        return XCTFail("Active live settings were refused: noSpace=\(noSpace)")
      }
      for char in fixture.suffix { session.insertBatch(String(char), at: start.addingTimeInterval(1)) }
      XCTAssertEqual(session.outcome == .completed, fixture.finished, "\(fixture.count): \(session.typed) / \(session.prompt)")
      XCTAssertEqual(session.outcome == .failed, fixture.failed)
      if !session.isFinished { session.bailOut(at: start.addingTimeInterval(2)) }
      let events = try XCTUnwrap(session.result()).replayEvents.filter { $0.kind == .insert }
      let native = try events.map { event in
        let field = try XCTUnwrap(event.inputField), position = try XCTUnwrap(event.inputPosition)
        return Output.Fixture.Event(wordIndex: field.index, charIndex: position.charIndex, lastWord: position.lastWord,
          correct: try XCTUnwrap(event.inputCorrectness?.last))
      }
      XCTAssertEqual(native, fixture.events, "\(fixture.count): \(fixture.prefix)|\(fixture.suffix)")
    }
  }
}
