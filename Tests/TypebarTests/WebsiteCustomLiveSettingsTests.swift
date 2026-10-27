import XCTest
@testable import Typebar

@MainActor final class WebsiteCustomLiveSettingsTests: XCTestCase {
  private func raw(mode: String = "repeat", limitMode: String = "word", limit: Double) throws -> WebsiteCustomTextSettings {
    try .init(value: .object(["text": .array([.string("replacement")]), "mode": .string(mode),
      "limit": .object(["mode": .string(limitMode), "value": .number(limit)]), "pipeDelimiter": .bool(false)]))
  }
  private func configuration() -> TestConfiguration {
    .init(mode: .custom, duration: nil, wordLimit: 100, difficulty: .normal, rules: .init(),
      customTextCompletion: .words, customTextOrdering: .inOrder, customTextPipeDelimiter: false, modifiers: [.noQuit])
  }
  func testLiveSettingsContinueOldWordsetAgainstCompletePinnedGeneratorAndTimer() throws {
    struct Output: Decodable {
      struct Fixture: Decodable {
        struct Chunk: Decodable { let words: [String], remaining: Bool }
        struct TimeCheck: Decodable { let elapsed: Double, finished: Bool }
        let mode: String, limitMode: String, limit: Double, initial: [String], chunks: [Chunk], timeChecks: [TimeCheck]
      }
      let pool: [String], fixtures: [Fixture]
    }
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires the complete pinned wordset/generator and timer source")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-custom-live-settings.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let bytes = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { return XCTFail("Pinned generator/timer probe failed") }
    let output = try JSONDecoder().decode(Output.self, from: bytes)
    XCTAssertEqual(output.fixtures.count, 9)
    for fixture in output.fixtures {
      var stream = try XCTUnwrap(CustomSectionWordStream(preparedSections: output.pool, configuration: configuration()))
      let opening = stream.nextChunk(random: { 0 })
      XCTAssertEqual(opening.text.split(separator: " ").map(String.init), fixture.initial)
      let settings = try raw(mode: fixture.mode, limitMode: fixture.limitMode, limit: fixture.limit)
      var next = configuration()
      next.customTextCompletion = fixture.limitMode == "word" ? .words : fixture.limitMode == "time" ? .time : .sections
      next.customTextOrdering = fixture.mode == "repeat" ? .inOrder : fixture.mode == "shuffle" ? .shuffled : .random
      next = try settings.applyingLimit(to: next)
      stream.synchronizeConfiguration(next)
      for chunk in fixture.chunks {
        XCTAssertEqual(stream.nextChunk(random: { 0 }).text.split(separator: " ").map(String.init), chunk.words,
          "\(fixture.mode)/\(fixture.limitMode)")
        XCTAssertEqual(stream.hasRemaining, chunk.remaining)
      }
      for check in fixture.timeChecks {
        let start = Date(timeIntervalSince1970: 100)
        var session = TestSessionFactory.make(configuration: configuration(), preparedCustomSections: output.pool)
        session.insertBatch("o", at: start)
        XCTAssertTrue(try session.synchronizeWebsiteCustomText(settings))
        session.tick(at: start.addingTimeInterval(check.elapsed))
        XCTAssertEqual(session.isFinished, check.finished, "\(fixture.limitMode) at \(check.elapsed)")
      }
    }
  }

  func testSectionProgressRetainsPreviouslyGeneratedBoundariesAndInput() throws {
    let start = Date(timeIntervalSince1970: 100)
    for noSpace in [false, true] {
      let config = configuration().with(modifiers: noSpace ? [.noQuit, .noSpaces] : [.noQuit])
      var session = TestSessionFactory.make(configuration: config, preparedCustomSections: ["aa", "bb"])
      session.insertBatch(noSpace ? "aa" : "aa ", at: start)
      let attempt = session.automaticInputAttemptID, target = session.promptTargetID, text = session.typed
      XCTAssertTrue(try session.synchronizeWebsiteCustomText(raw(limitMode: "section", limit: 101.5)))
      XCTAssertEqual(session.sectionProgress?.total, 102)
      XCTAssertEqual(session.sectionProgress?.completed, 1)
      XCTAssertEqual(session.automaticInputAttemptID, attempt); XCTAssertEqual(session.promptTargetID, target)
      XCTAssertEqual(session.typed, text)
    }
  }

  func testUnrepresentableLimitDoesNotPartiallyChangeLiveConfiguration() throws {
    var session = TestSessionFactory.make(configuration: configuration(), preparedCustomSections: ["aa", "bb"])
    session.insertBatch("a")
    let before = session.generationState
    XCTAssertThrowsError(try session.synchronizeWebsiteCustomText(raw(mode: "shuffle", limit: 1e30)))
    XCTAssertEqual(session.generationState, before)
  }
}
