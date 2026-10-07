import XCTest
@testable import Typebar

final class PracticeLineModeTests: XCTestCase {
  func testTimedCustomKeepsTheScrollingViewportWhenWholeLinesAreEnabled() {
    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, configuration: custom(.time, limit: 30)))
  }

  func testZenCanExpandItsEnteredLinesWithoutChangingItsCompletionRule() {
    XCTAssertTrue(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, configuration: .init(
        mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())))
  }

  private func custom(_ completion: CustomTextCompletion, limit: Int) -> TestConfiguration {
    .init(mode: .custom, duration: completion == .time ? Double(limit) : nil,
      wordLimit: completion == .words ? limit : nil, difficulty: .normal, rules: .init(),
      customTextCompletion: completion, customTextSectionLimit: completion == .sections ? limit : nil)
  }

  func testInfiniteCustomWordTimeAndSectionModesKeepTheScrollingViewport() {
    for completion: CustomTextCompletion in [.words, .time, .sections] {
      XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
        settingEnabled: true, tapeMode: .off, configuration: custom(completion, limit: 0)), completion.rawValue)
    }
  }

  func testFiniteCustomWordSectionAndFinishModesCanExpand() {
    for completion: CustomTextCompletion in [.words, .sections, .finish] {
      XCTAssertTrue(PracticeLineDisplayPolicy.shouldShowAllLines(
        settingEnabled: true, tapeMode: .off, configuration: custom(completion, limit: 25)), completion.rawValue)
    }
  }

  func testInfiniteOrdinaryWordsAreNotMistakenForInfiniteCustom() {
    XCTAssertTrue(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, configuration: .words(0)))
    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, configuration: .timed(seconds: 0)))
  }

  func testDisabledSettingAndTapeNeverExpandAnyNativeMode() {
    let configurations = [TestConfiguration.words(25), .words(0), .timed(seconds: 30),
      .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())]
      + CustomTextCompletion.allCases.map { custom($0, limit: 25) }
    for configuration in configurations {
      XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
        settingEnabled: false, tapeMode: .off, configuration: configuration))
      for tape: PracticeTapeMode in [.word, .letter] {
        XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
          settingEnabled: true, tapeMode: tape, configuration: configuration))
      }
    }
  }

  func testPinnedWrapperHeightModeDecisionsMatchNativeConfiguration() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Fixture: Decodable {
      let mode: String, limit: Int, completion: String?
      let enabled: Bool, tape: String, expands: Bool
    }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", project.appendingPathComponent("Scripts/check-source-line-display.mjs").path,
      reference, "--emit-fixtures"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 52)
    for fixture in fixtures {
      let mode = try XCTUnwrap(TestMode(rawValue: fixture.mode))
      let configuration: TestConfiguration
      if mode == .custom {
        configuration = custom(try XCTUnwrap(CustomTextCompletion(rawValue: fixture.completion ?? "")), limit: fixture.limit)
      } else {
        configuration = .init(mode: mode, duration: mode == .time ? Double(fixture.limit) : nil,
          wordLimit: mode == .words ? fixture.limit : nil, difficulty: .normal, rules: .init())
      }
      XCTAssertEqual(PracticeLineDisplayPolicy.shouldShowAllLines(
        settingEnabled: fixture.enabled, tapeMode: try XCTUnwrap(PracticeTapeMode(rawValue: fixture.tape)),
        configuration: configuration), fixture.expands,
        "\(fixture.mode) / \(fixture.completion ?? "") / \(fixture.limit) / \(fixture.enabled) / \(fixture.tape)")
    }
  }
}
