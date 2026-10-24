import XCTest
@testable import Typebar

@MainActor final class WebsiteArrowChartTests: XCTestCase {
  func testCompletePinnedChartSequencesIncludingLaterFirstWords() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Word: Decodable { let first: Bool; let word: String; let draws: Int }
    struct Scenario: Decodable { let samples: [Double]; let words: [Word] }
    struct Emulation: Decodable { let key: String; let output: String? }
    struct Output: Decodable { let scenarios: [Scenario]; let emulation: [Emulation] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-arrow-chart.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.scenarios.count, 20)
    for scenario in output.scenarios {
      var chart = WebsiteArrowChart(), draws = 0
      XCTAssertEqual(scenario.words.count, 40)
      for expected in scenario.words {
        let before = draws
        let actual = chart.word(first: expected.first) {
          defer { draws += 1 }; return scenario.samples[draws % scenario.samples.count]
        }
        XCTAssertEqual(actual, expected.word)
        XCTAssertEqual(draws - before, expected.draws)
      }
    }
    XCTAssertEqual(output.emulation.count, 26)
    for fixture in output.emulation {
      XCTAssertEqual(ArrowKeyInputPolicy.character(forKey: fixture.key).map(String.init), fixture.output)
    }
  }

  func testInvalidEntropyCannotInstallPartialChartState() {
    for position in 0..<10 {
      var chart = WebsiteArrowChart(), draws = 0
      let before = chart
      XCTAssertNil(chart.word(first: true) {
        defer { draws += 1 }; return draws == position ? .nan : 0
      })
      XCTAssertEqual(chart, before)
    }
  }

  func testWebsiteAttemptsCarryFacingStateAndReplayDoesNotAdvanceIt() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"mode":"words","words":17,"funbox":["arrows"]}"#, pointsPerRem: 16, context: .init(authenticated: true))
    let first = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: .init(), random: .init(contentUnit: { 0.5 }))
    let history = try XCTUnwrap(first.session.generatedWordReplayHistory)
    let repeated = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: first.scope,
      attemptSource: .repeatedWords(history, repeatedPace: false),
      random: .init(contentUnit: { XCTFail("Replay must not change choreography"); return 0 }))
    XCTAssertEqual(repeated.session.prompt, first.session.prompt)
    XCTAssertEqual(repeated.scope.arrowChart, first.scope.arrowChart)
    var expected = first.scope.arrowChart
    let nextWords = (0..<17).map { expected.word(first: $0 == 0, randomUnit: { 0.5 })! }.joined()
    let next = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: repeated.scope,
      random: .init(contentUnit: { 0.5 }))
    XCTAssertEqual(next.session.prompt, nextWords)
    XCTAssertEqual(next.scope.arrowChart, expected)
  }

  func testLegacyNativeArrowsStillUseTheirIndexedSingleSymbols() {
    let configuration = TestConfiguration.words(3).with(modifiers: [.arrowStream])
    XCTAssertFalse(WebsiteArrowChart.isSelected(configuration))
    XCTAssertEqual(TestSessionFactory.make(configuration: configuration).prompt, "↑→↓")
  }

  func testWholePreviewCarriesEveryChartAndCancellationDoesNotMutateOwningScope() async throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"mode":"words","words":1001,"showAllLines":true,"funbox":["arrows"]}"#,
      pointsPerRem: 16, context: .init(authenticated: true))
    let scope = WebsiteConfigSessionBuilder.Scope()
    let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: scope,
      random: .init(contentUnit: { 0.5 }))
    var expected = WebsiteArrowChart()
    let words = (0..<1001).map { expected.word(first: $0 == 0, randomUnit: { 0.5 })! }
    XCTAssertEqual(ready.session.prompt, words.joined())
    XCTAssertEqual(ready.session.generatedWordReplayHistory?.count, 1001)
    XCTAssertEqual(ready.scope.arrowChart, expected)
    let task = Task { @MainActor in
      do {
        _ = try await WholePreviewWordPreparation.prepareSession(configuration: ready.session.configuration,
          arrowChart: ready.scope.arrowChart, nextRandomContentUnit: { 0.5 }, didPrepare: { count in
            if count == 100 { withUnsafeCurrentTask { $0?.cancel() } }
          })
        XCTFail("Cancelled preview was published")
      } catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
    }
    await task.value
    XCTAssertEqual(ready.scope.arrowChart, expected)
    XCTAssertEqual(scope.arrowChart, WebsiteArrowChart())
  }
}
