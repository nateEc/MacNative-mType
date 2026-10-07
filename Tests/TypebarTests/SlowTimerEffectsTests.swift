import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class SlowTimerEffectsTests: XCTestCase {
  func testSlowTimerRemainsLatchedAfterFPSRestorationAndNormalDelivery() {
    var health = TimerHealthState()
    health.observe(drift: 0.125, configuration: .words(25))
    XCTAssertFalse(health.usesSlowTimer)
    health.observe(drift: 0.126, configuration: .words(25))
    XCTAssertTrue(health.usesSlowTimer)
    health.restoreAnimationFrameRate()
    health.observe(drift: 0, configuration: .words(25))
    XCTAssertTrue(health.usesSlowTimer)
    XCTAssertEqual(health.animationFrameRate(requested: 60), 60)
    XCTAssertEqual(health.severeDriftCount, 0)
    health = .init()
    XCTAssertFalse(health.usesSlowTimer)
  }

  func testSlowTimerSuppressesNewPowerAndConfettiWithoutChangingUserMotionPreference() {
    for slow in [false, true] {
      XCTAssertEqual(TypingPowerPolicy.shouldEmit(mode: .mellow, acceptedCharacters: 1,
        reducesMotion: false, slowTimer: slow), !slow)
      XCTAssertEqual(ResultCelebrationPolicy.shouldEmit(isNewPersonalBest: true,
        hasZeroSpeedFeedback: false, reducesMotion: false, slowTimer: slow), !slow)
      XCTAssertEqual(ResultCelebrationPolicy.shouldEmit(isNewPersonalBest: false,
        hasZeroSpeedFeedback: true, reducesMotion: false, slowTimer: slow), !slow)
    }
  }

  func testWordsFinishKeepsSlowTimerButTimedExpiryAndThresholdFailureClearIt() {
    var health = TimerHealthState()
    health.observe(drift: 0.26, configuration: .words(25))
    XCTAssertTrue(health.suppressesResultCelebration(configuration: .words(25),
      outcome: .completed, failureReason: nil))
    XCTAssertTrue(health.suppressesResultCelebration(configuration: .timed(seconds: 15),
      outcome: .bailedOut, failureReason: nil))
    XCTAssertFalse(health.suppressesResultCelebration(configuration: .timed(seconds: 15),
      outcome: .completed, failureReason: nil))
    for reason: TestFailureReason in [.minimumWpm, .minimumAccuracy] {
      XCTAssertFalse(health.suppressesResultCelebration(configuration: .words(25),
        outcome: .failed, failureReason: reason))
    }
  }

  func testIneligibleLimitsDoNotLatchAndSettingRevisionDoesNotClearSlowTimer() {
    for configuration in [TestConfiguration.timed(seconds: 0), .timed(seconds: 130),
      .words(0), .words(250), .init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())] {
      var health = TimerHealthState()
      health.observe(drift: 0.26, configuration: configuration)
      XCTAssertFalse(health.usesSlowTimer)
    }
    var health = TimerHealthState()
    health.observe(drift: 0.26, configuration: .words(25), animationSettingsRevision: 1)
    XCTAssertEqual(health.animationFrameRate(requested: 60, settingsRevision: 2), 60)
    XCTAssertTrue(health.usesSlowTimer)
    XCTAssertEqual(health.severeDriftCount, 1)
    let suppression = health.suppressesResultCelebration(configuration: .words(25),
      outcome: .completed, failureReason: nil)
    health = .init()
    XCTAssertTrue(suppression, "Completion snapshot must survive practice health reset")
    XCTAssertFalse(health.usesSlowTimer)
  }

  func testRuntimeSlowTimerDoesNotMutatePreferencesOrCompletedResultArchive() throws {
    let suite = "TypebarTests.slow-effects.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.animationFrameRate = 15
    let before = try JSONEncoder().encode(settings.snapshot)
    var health = TimerHealthState()
    health.observe(drift: 0.26, configuration: .words(25))
    settings.animationFrameRate = 60
    XCTAssertTrue(health.usesSlowTimer)
    XCTAssertFalse(settings.reducePracticeMotion)
    XCTAssertEqual(AppSettings(defaults: defaults).animationFrameRate, 60)
    settings.animationFrameRate = 15
    let restored = try JSONDecoder().decode(AppSettingsSnapshot.self, from: before)
    XCTAssertEqual(settings.snapshot, restored)
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    let start = Date(timeIntervalSinceReferenceDate: 913_100_000)
    session.insertBatch("ab ", at: start)
    session.insertBatch("cd", at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: settings.snapshot, results: [result], presets: [], at: start))
    XCTAssertEqual(archive.results, [result])
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testFullPinnedSlowStateAndEffectGatesMatchNativePolicies() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Power: Decodable { let level: String, scheduled: Bool }
    struct Step: Decodable { let action: String, slowTimer: Bool, frameRate: Int, power: [Power], confetti: Bool }
    struct Ending: Decodable { let ending: String, slowTimer: Bool }
    struct Fixture: Decodable { let mode: String, limit: Int, steps: [Step], endings: [Ending] }
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      project.appendingPathComponent("Scripts/check-source-slow-timer-effects.mjs").path,
      reference, "--emit-fixtures"]
    process.standardOutput = output; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode([Fixture].self, from: data)
    XCTAssertEqual(fixtures.count, 10)
    XCTAssertEqual(fixtures.reduce(0) { $0 + $1.endings.count }, 47)
    for fixture in fixtures {
      let mode = try XCTUnwrap(TestMode(rawValue: fixture.mode))
      let configuration = TestConfiguration(mode: mode,
        duration: mode == .time || mode == .custom ? Double(fixture.limit) : nil,
        wordLimit: mode == .words ? fixture.limit : nil, difficulty: .normal, rules: .init())
      var health = TimerHealthState()
      XCTAssertEqual(fixture.steps.count, 7)
      for step in fixture.steps {
        switch step.action {
        case "start", "restart": health = .init()
        case "boundary": health.observe(drift: 0.125, configuration: configuration)
        case "late": health.observe(drift: 0.126, configuration: configuration)
        case "clear": health.restoreAnimationFrameRate()
        case "normal": health.observe(drift: 0, configuration: configuration)
        default: XCTFail("Unknown source action")
        }
        XCTAssertEqual(health.usesSlowTimer, step.slowTimer)
        XCTAssertEqual(health.animationFrameRate(requested: 60), step.frameRate)
        for power in step.power {
          let powerMode = try XCTUnwrap(TypingPowerMode.allCases.first { $0.compatibilityValue == power.level })
          XCTAssertEqual(TypingPowerPolicy.shouldEmit(mode: powerMode, acceptedCharacters: 1,
            reducesMotion: false, slowTimer: health.usesSlowTimer), power.scheduled)
        }
        XCTAssertEqual(ResultCelebrationPolicy.shouldEmit(isNewPersonalBest: true,
          hasZeroSpeedFeedback: false, reducesMotion: false, slowTimer: health.usesSlowTimer), step.confetti)
      }
      XCTAssertEqual(fixture.endings.count, 4 + (mode == .words ? 1 : 0)
        + ((mode == .time || mode == .custom) && fixture.limit > 0 ? 1 : 0))
      for ending in fixture.endings {
        health = .init(); health.observe(drift: 0.126, configuration: configuration)
        if ending.ending == "timerHealth" { health.observe(drift: 0.501, configuration: configuration) }
        let reason: TestFailureReason? = ending.ending == "minimumWpm" ? .minimumWpm
          : ending.ending == "minimumAccuracy" ? .minimumAccuracy
          : ending.ending == "timerHealth" ? .timerHealth : nil
        let outcome: TestOutcome = reason != nil ? .failed : ending.ending == "clear-only" ? .bailedOut : .completed
        XCTAssertEqual(health.suppressesResultCelebration(configuration: configuration,
          outcome: outcome, failureReason: reason), ending.slowTimer)
      }
    }
  }

  func testProductionCelebrationDrawsNormallyButNotForSlowTimerSnapshot() throws {
    for slow in [false, true] {
      let view = ResultCelebrationView(isNewPersonalBest: true, hasZeroSpeedFeedback: false,
        reducesMotion: false, slowTimer: slow, accent: .red, text: .green, subduedText: .blue)
        .frame(width: 360, height: 180).background(.black)
      let host = NSHostingView(rootView: view)
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 360, height: 180),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = host
      defer { window.contentView = nil }
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.08))
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      var colored = 0
      for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
          if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
            max(color.redComponent, color.greenComponent, color.blueComponent) > 0.2 { colored += 1 }
        }
      }
      if slow { XCTAssertEqual(colored, 0) } else { XCTAssertGreaterThan(colored, 0) }
      XCTAssertFalse(window.isVisible)
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_SLOW_TIMER_QA_IMAGE_DIRECTORY"] {
        try bitmap.representation(using: .png, properties: [:])?.write(
          to: URL(fileURLWithPath: directory).appendingPathComponent(slow ? "slow-suppressed.png" : "normal-celebration.png"))
      }
    }
  }
}
