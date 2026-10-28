import XCTest
@testable import Typebar

final class IntervalCaptureSourceTests: XCTestCase {
  private struct Fixture: Decodable {
    let words: [String]
    let suffix, stop, mode: String
    let noSpace: Bool
    let duration: Double
    let boundaries, burst, wpm, raw: [Double]
    let errors: [Int]
  }
  private struct Output: Decodable { let fixtures: [Fixture] }

  func testFreshIntervalSeriesAgainstCompletePinnedInputAndStatistics() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-input-position.mjs").path,
      reference, "--interval-capture-fixtures"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 326)
    for (index, fixture) in fixtures.enumerated() {
      let rules = InputRules(stopOnErrorMode: fixture.stop == "word" ? .word : fixture.stop == "letter" ? .letter : .off)
      let config = (fixture.mode == "time" ? TestConfiguration.timed(seconds: 30, rules: rules)
        : .words(fixture.words.count, rules: rules)).with(modifiers: fixture.noSpace ? [.noSpaces] : [])
      var session = fixture.noSpace
        ? TypingSession(configuration: config, prompt: fixture.words.joined(), noSpaceTargetWords: fixture.words)
        : TypingSession(configuration: config, prompt: fixture.words.joined(), sourceFields: fixture.words)
      // A zero calendar origin preserves the exact controlled fractional
      // seconds instead of adding epoch-size Date subtraction noise.
      let start = Date(timeIntervalSinceReferenceDate: 0)
      session.insertBatch("a", at: start)
      session.insertBatch(fixture.suffix, at: start.addingTimeInterval(fixture.duration))
      session.bailOut(at: start.addingTimeInterval(fixture.duration))
      let result = try XCTUnwrap(session.result())
      let points = ResultPerformanceTrace.points(prompt: result.prompt, events: result.replayEvents,
        duration: fixture.duration, configuration: config, targetWordDirectory: result.targetWordDirectory,
        sourceScoringBasis: result.characterStats.sourceUnitBasis)
      XCTAssertEqual(points.map(\.elapsed), fixture.boundaries, "boundaries \(index)")
      XCTAssertEqual(points.map(\.burstWpm), fixture.burst, "burst \(index)")
      XCTAssertEqual(points.map(\.errorCount), fixture.errors, "errors \(index)")
      XCTAssertEqual(points.map { Double($0.wpm) }, fixture.wpm, "WPM \(index)")
      XCTAssertEqual(points.map { Double($0.rawWpm) }, fixture.raw, "Raw \(index)")
      XCTAssertEqual(result.chartDuration, fixture.duration, "saved clock \(index)")
      let account = try XCTUnwrap(AccountResultChartInput(result).calculate())
      XCTAssertEqual(account.samples.map(\.elapsed), fixture.boundaries, "account boundaries \(index)")
      XCTAssertEqual(account.samples.map(\.burst), fixture.burst, "account burst \(index)")
      XCTAssertEqual(account.samples.map(\.errors), fixture.errors, "account errors \(index)")
      XCTAssertEqual(account.samples.map(\.wpm), fixture.wpm, "account WPM \(index)")
    }
  }

  func testLegacyIntervalArithmeticRetainsItsPriorValueWithoutSourceContext() throws {
    let events = try JSONDecoder().decode([TypingReplayEvent].self, from: Data(#"[{"offset":0,"kind":"insert","text":"a","inputField":{"index":0,"value":"a"}},{"offset":2.96,"kind":"insert","text":"bbbbbbb","inputField":{"index":0,"value":"abbbbbbb"}}]"#.utf8))
    let points = ResultPerformanceTrace.points(prompt: "abbbbbbbq", events: events, duration: 2.96)
    XCTAssertEqual(points.map(\.burstWpm), [12, 0, 88])
    XCTAssertEqual(ResultPerformanceTrace.point(prompt: "abbbbbbbq", events: events, elapsed: 2.96).burstWpm, 88)
    XCTAssertTrue(events.allSatisfy { $0.commitsWord == nil })
    XCTAssertEqual(try JSONDecoder().decode([TypingReplayEvent].self, from: JSONEncoder().encode(events)), events)
  }
}
