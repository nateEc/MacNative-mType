import XCTest

@testable import Typebar

@MainActor
final class LiveThresholdRulesTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 100)

  private func withSettings(source: Bool, _ body: (AppSettings) throws -> Void) throws {
    let suite = "typebar.live-threshold.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    if source {
      XCTAssertTrue(
        ThresholdSettingsStore(defaults: defaults).save(
          PracticeThresholdSource(configuration: .init()).applying(to: AppSettingsSnapshot())))
    }
    try body(AppSettings(defaults: defaults, localBackgroundStore: .inMemory()))
  }

  func testEnablingAccuracyDuringAnAttemptUsesTheNextTimerSampleWithoutRestart() throws {
    for source in [false, true] {
      try withSettings(source: source) { settings in
        var session = TypingSession(
          configuration: .words(6, rules: settings.inputRules),
          prompt: "amber bay cedar delta ember fjord")
        session.insert("ax", at: start)
        let controls = PracticeThresholdPreferences(settings: settings)
        controls.accuracyEnabled.wrappedValue = true
        controls.accuracy.wrappedValue = 50.1
        session.synchronizeLiveInputRules(settings.inputRules)
        XCTAssertEqual(session.typed, "ax")
        XCTAssertEqual(session.startedAt, start)
        session.enforceLivePracticeThresholds(at: start.addingTimeInterval(1))
        XCTAssertEqual(session.failureReason, .minimumAccuracy)
      }
    }
  }

  func testLoweringAccuracyBeforeTheNextSampleUsesTheNewStrictBoundary() throws {
    for source in [false, true] {
      try withSettings(source: source) { settings in
        let controls = PracticeThresholdPreferences(settings: settings)
        controls.accuracyEnabled.wrappedValue = true
        controls.accuracy.wrappedValue = 80
        var session = TypingSession(
          configuration: .words(6, rules: settings.inputRules),
          prompt: "amber bay cedar delta ember fjord")
        session.insert("ax", at: start)
        controls.accuracy.wrappedValue = 50
        session.synchronizeLiveInputRules(settings.inputRules)
        session.enforceLivePracticeThresholds(at: start.addingTimeInterval(1))
        XCTAssertEqual(session.outcome, .active)
        XCTAssertNil(session.failureReason)
      }
    }
  }

  func testLiveWpmStillWaitsForFourCompletedWords() throws {
    for source in [false, true] {
      try withSettings(source: source) { settings in
        var session = TypingSession(
          configuration: .words(6, rules: settings.inputRules),
          prompt: "aaaa aaaa aaaa aaaa aaaa aaaa")
        session.insert("aaaa aaaa aaaa ", at: start)
        let controls = PracticeThresholdPreferences(settings: settings)
        controls.wpmEnabled.wrappedValue = true
        controls.wpm.wrappedValue = 5
        session.synchronizeLiveInputRules(settings.inputRules)
        session.enforceLivePracticeThresholds(at: start.addingTimeInterval(60))
        XCTAssertEqual(session.outcome, .active)
        session.insert("aaaa ", at: start.addingTimeInterval(60))
        session.enforceLivePracticeThresholds(at: start.addingTimeInterval(60))
        XCTAssertEqual(session.failureReason, .minimumWpm)
      }
    }
  }

  func testBurstEnableAndDisableAffectTheCurrentWordCommit() throws {
    for source in [false, true] {
      for initiallyEnabled in [false, true] {
        try withSettings(source: source) { settings in
          let controls = PracticeThresholdPreferences(settings: settings)
          if initiallyEnabled {
            controls.burstMode.wrappedValue = .fixed
            controls.burst.wrappedValue = 100
          }
          var session = TypingSession(
            configuration: .words(3, rules: settings.inputRules),
            prompt: "amber bay cedar")
          session.insert("a", at: start)
          controls.burstMode.wrappedValue = initiallyEnabled ? .off : .fixed
          if !initiallyEnabled { controls.burst.wrappedValue = 100 }
          session.synchronizeLiveInputRules(settings.inputRules)
          session.insert("mber ", at: start.addingTimeInterval(10))
          XCTAssertEqual(session.outcome, initiallyEnabled ? .active : .failed)
          XCTAssertEqual(session.isFinished, !initiallyEnabled)
        }
      }
    }
  }

  func testSourceZeroAndOffMemoryTravelTogetherWithoutReplacingRestartOnlyRules() throws {
    try withSettings(source: true) { settings in
      var initial = settings.inputRules
      initial.strictSpace = true
      initial.stopOnError = true
      initial.stopOnErrorMode = .word
      initial.codeUnindentOnBackspace = true
      var session = TypingSession(
        configuration: .words(3, rules: initial), prompt: "amber bay cedar")
      session.insert("a", at: start)
      let controls = PracticeThresholdPreferences(settings: settings)
      controls.wpmEnabled.wrappedValue = true
      controls.wpm.wrappedValue = 0
      controls.burstMode.wrappedValue = .flex
      controls.burst.wrappedValue = 0
      session.synchronizeLiveInputRules(settings.inputRules)
      XCTAssertEqual(
        session.configuration.rules.thresholdSource, settings.inputRules.thresholdSource)
      XCTAssertEqual(
        session.configuration.rules.thresholdSource?.configuration.minimumWordBurstMode, .flex)
      XCTAssertEqual(session.configuration.rules.minimumWordBurstMode, .off)
      XCTAssertTrue(
        try XCTUnwrap(session.configuration.rules.thresholdSource).matches(
          session.configuration.rules))
      XCTAssertTrue(session.configuration.rules.strictSpace)
      XCTAssertEqual(session.configuration.rules.stopOnErrorMode, .word)
      XCTAssertTrue(session.configuration.rules.codeUnindentOnBackspace)
      controls.wpmEnabled.wrappedValue = false
      controls.wpm.wrappedValue = 37
      session.synchronizeLiveInputRules(settings.inputRules)
      XCTAssertEqual(session.configuration.rules.minimumWpm, 0)
      XCTAssertEqual(
        session.configuration.rules.thresholdSource?.configuration.minimumWpmCustomValue, 37)
      XCTAssertEqual(
        session.configuration.rules.thresholdSource?.configuration.minimumWpmMode, .off)
      XCTAssertEqual(session.typed, "a")
      XCTAssertEqual(session.startedAt, start)
    }
  }

  func testFinishedResultsAndRepeatsRetainTheirFinalLiveSource() throws {
    try withSettings(source: true) { settings in
      var session = TypingSession(
        configuration: .timed(seconds: 1, rules: settings.inputRules),
        prompt: "amber bay cedar")
      session.insert("a", at: start)
      let controls = PracticeThresholdPreferences(settings: settings)
      controls.wpmEnabled.wrappedValue = true
      controls.wpm.wrappedValue = 37
      session.synchronizeLiveInputRules(settings.inputRules)
      session.tick(at: start.addingTimeInterval(1))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.configuration.rules.minimumWpm, 37)
      XCTAssertEqual(
        TestResultRecord(result: result).portableResult?.configuration, result.configuration)
      controls.wpm.wrappedValue = 53
      session.synchronizeLiveInputRules(settings.inputRules)
      XCTAssertEqual(session.configuration, result.configuration)
      XCTAssertEqual(session.repeatedAttempt().configuration, result.configuration)
      XCTAssertNotEqual(
        session.configuration.rules.thresholdSource, settings.inputRules.thresholdSource)
    }
  }

  func testMalformedThresholdsPreserveTheirWholeGroupButDoNotBlockOtherLiveRules() throws {
    try withSettings(source: true) { settings in
      let controls = PracticeThresholdPreferences(settings: settings)
      controls.wpmEnabled.wrappedValue = true
      controls.wpm.wrappedValue = 37
      let original = settings.inputRules
      var conflicting = original
      conflicting.minimumWpm = 38
      var invalidLegacy = InputRules()
      invalidLegacy.minimumWpm = .nan
      var invalidAccuracy = InputRules()
      invalidAccuracy.minimumAccuracy = 101
      for candidate in [conflicting, invalidLegacy, invalidAccuracy] {
        var session = TypingSession(
          configuration: .words(3, rules: original), prompt: "amber bay cedar")
        var live = candidate
        live.blindMode = true
        session.synchronizeLiveInputRules(live)
        XCTAssertTrue(session.configuration.rules.blindMode)
        XCTAssertEqual(session.configuration.rules.thresholdSource, original.thresholdSource)
        XCTAssertEqual(session.configuration.rules.minimumWpm, original.minimumWpm)
        XCTAssertEqual(session.configuration.rules.minimumAccuracy, original.minimumAccuracy)
        XCTAssertEqual(
          session.configuration.rules.minimumWordBurstWpm, original.minimumWordBurstWpm)
        XCTAssertEqual(
          session.configuration.rules.minimumWordBurstMode, original.minimumWordBurstMode)
      }
    }
  }

  func testAnExplicitValidLegacyRuleUpdateClearsSourceWithoutInventingMemory() throws {
    try withSettings(source: true) { settings in
      var session = TypingSession(
        configuration: .words(3, rules: settings.inputRules), prompt: "amber bay cedar")
      session.synchronizeLiveInputRules(.init(minimumWpm: 12, minimumWordBurstWpm: 25))
      XCTAssertNil(session.configuration.rules.thresholdSource)
      XCTAssertEqual(session.configuration.rules.minimumWpm, 12)
      XCTAssertEqual(session.configuration.rules.minimumWordBurstMode, .fixed)
      XCTAssertEqual(session.configuration.rules.minimumWordBurstWpm, 25)
    }
  }

  private var projectRoot: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  func testProductionClockAndInputRefreshBeforeThresholdEnforcement() throws {
    let app = try String(
      contentsOf: projectRoot.appendingPathComponent("Sources/Typebar/TypebarApp.swift"),
      encoding: .utf8)
    let clockStart = try XCTUnwrap(app.range(of: "private func advanceClock("))
    let clock = app[clockStart.lowerBound...]
    XCTAssertLessThan(
      try XCTUnwrap(clock.range(of: "synchronizeLiveInputRules()")).lowerBound,
      try XCTUnwrap(clock.range(of: "session.enforceLivePracticeThresholds")).lowerBound)
    let inputStart = try XCTUnwrap(app.range(of: "private func handleInsertedText("))
    let input = app[inputStart.lowerBound...]
    XCTAssertLessThan(
      try XCTUnwrap(input.range(of: "synchronizeLiveInputRules()")).lowerBound,
      try XCTUnwrap(input.range(of: "TypingLiveInputFeedback.insertBatch")).lowerBound)
  }

  func testPinnedTimerAndWordCommitReadCurrentConfigurationAfterStart() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [
      "node", "--experimental-vm-modules",
      projectRoot.appendingPathComponent("Scripts/check-source-session-clock.mjs").path, reference,
    ]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: data, as: UTF8.self))
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("21 owned fixtures"))
  }
}
