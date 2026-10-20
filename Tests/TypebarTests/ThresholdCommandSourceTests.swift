import XCTest
@testable import Typebar

@MainActor
final class ThresholdCommandSourceTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let suite = "typebar.threshold-command-source.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: 37))
    try raw.apply(.minimumWordBurst(mode: .flex, customValue: 0))
    XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(PracticeThresholdSource(configuration: raw).applying(to: AppSettingsSnapshot())))
    try body(AppSettings(defaults: defaults), defaults)
  }

  func testEditorSubmissionPreservesExplicitZeroModesAndOffCommandKeepsMemory() throws {
    try withSettings { settings, _ in
      var saves = 0
      XCTAssertTrue(PracticeThresholdApplication.apply(0, kind: .minimumWpm, to: settings, onConfigurationSave: { saves += 1 }))
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmMode, .custom)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmCustomValue, 0)
      XCTAssertTrue(PracticeThresholdApplication.apply(0, kind: .minimumWordBurst(.fixed), to: settings, onConfigurationSave: { saves += 1 }))
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstMode, .fixed)
      XCTAssertTrue(PracticeThresholdApplication.apply(22.5, kind: .minimumWpm, to: settings))
      let command = try XCTUnwrap(PracticeThresholdCommandCatalog.target(for: "behavior.minWpm.off"))
      XCTAssertTrue(command.applyImmediate(to: settings, onConfigurationSave: { saves += 1 }))
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmMode, .off)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmCustomValue, 22.5)
      XCTAssertEqual(saves, 3)
    }
  }

  func testFutureStorageFailureDoesNotReportSuccessOrFireSaveCallbacks() throws {
    try withSettings { settings, defaults in
      let before = settings.snapshot
      let future = Data("{\"version\":5}".utf8)
      defaults.set(future, forKey: "appSettings.v4")
      var saves = 0
      XCTAssertFalse(PracticeThresholdApplication.apply(44, kind: .minimumWpm, to: settings, onConfigurationSave: { saves += 1 }))
      let command = try XCTUnwrap(PracticeThresholdCommandCatalog.target(for: "behavior.minWpm.off"))
      XCTAssertFalse(command.applyImmediate(to: settings, onConfigurationSave: { saves += 1 }))
      XCTAssertEqual(saves, 0)
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), future)
    }
  }

  func testLockedSubmissionDoesNotFireCallbacks() throws {
    try withSettings { settings, _ in
      let owner = UUID()
      settings.setNoQuitConfigurationLock(true, for: owner)
      defer { settings.setNoQuitConfigurationLock(false, for: owner) }
      var saves = 0
      XCTAssertFalse(PracticeThresholdApplication.apply(44, kind: .minimumWpm, to: settings, onConfigurationSave: { saves += 1 }))
      XCTAssertEqual(saves, 0)
    }
  }

  func testEditorInitialValueUsesRememberedSourceRatherThanEffectiveOffValue() throws {
    try withSettings { settings, _ in
      XCTAssertEqual(settings.minimumWpm, 0)
      XCTAssertEqual(PracticeThresholdEditorKind.minimumWpm.initialCanonicalValue(in: settings), 37)
      XCTAssertEqual(PracticeThresholdEditorKind.minimumAccuracy.initialCanonicalValue(in: settings), 90)
      XCTAssertTrue(PracticeThresholdApplication.apply(60.2, kind: .minimumWordBurst(.flex), to: settings))
      let off = try XCTUnwrap(PracticeThresholdCommandCatalog.target(for: "behavior.minBurst.off"))
      XCTAssertTrue(off.applyImmediate(to: settings))
      XCTAssertEqual(settings.minimumWordBurstWpm, 0)
      XCTAssertEqual(PracticeThresholdEditorKind.minimumWordBurst(.fixed).initialCanonicalValue(in: settings), 60.2)
    }
  }

  func testAllSourceOffCommandsPreserveIndependentMemories() throws {
    try withSettings { settings, _ in
      XCTAssertTrue(PracticeThresholdApplication.apply(22.5, kind: .minimumWpm, to: settings))
      XCTAssertTrue(PracticeThresholdApplication.apply(98.5, kind: .minimumAccuracy, to: settings))
      XCTAssertTrue(PracticeThresholdApplication.apply(60.2, kind: .minimumWordBurst(.flex), to: settings))
      var saves = 0
      for id in ["behavior.minWpm.off", "behavior.minAcc.off", "behavior.minBurst.off"] {
        XCTAssertTrue(try XCTUnwrap(PracticeThresholdCommandCatalog.target(for: id)).applyImmediate(to: settings, onConfigurationSave: { saves += 1 }))
      }
      XCTAssertEqual(saves, 3)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmCustomValue, 22.5)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumAccuracyCustomValue, 98.5)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstCustomValue, 60.2)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWpmMode, .off)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumAccuracyMode, .off)
      XCTAssertEqual(settings.thresholdConfiguration?.minimumWordBurstMode, .off)
    }
  }

  func testUnknownSourceProfileCannotFallThroughToLegacySuccess() throws {
    try withSettings { _, defaults in
      let future = Data("{\"version\":5}".utf8)
      defaults.set(future, forKey: "appSettings.v4")
      let unreadable = AppSettings(defaults: defaults)
      var saves = 0
      XCTAssertFalse(PracticeThresholdApplication.apply(44, kind: .minimumWpm, to: unreadable, onConfigurationSave: { saves += 1 }))
      XCTAssertFalse(try XCTUnwrap(PracticeThresholdCommandCatalog.target(for: "behavior.minAcc.off"))
        .applyImmediate(to: unreadable, onConfigurationSave: { saves += 1 }))
      XCTAssertEqual(saves, 0)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), future)
      XCTAssertNil(defaults.object(forKey: "appSettings.v1"))
    }
  }

  func testEditorProductionHookKeepsRejectedSubmissionOpen() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let editor = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/PracticeThresholdEditor.swift"), encoding: .utf8)
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let guardRange = try XCTUnwrap(editor.range(of: "guard onApply(value) else"))
    let dismissal = try XCTUnwrap(editor.range(of: "dismiss()", range: guardRange.upperBound..<editor.endIndex))
    XCTAssertLessThan(guardRange.lowerBound, dismissal.lowerBound)
    XCTAssertTrue(editor.contains("applicationFailed = true; return"))
    XCTAssertTrue(app.contains("preservesZeroMode: settings.thresholdConfiguration != nil"))
    XCTAssertTrue(app.contains("kind.initialCanonicalValue(in: settings)"))
    // This is a static hook/order check, not a native button-click assertion.
  }

  func testUneditedFractionalMemoryIsPreservedWithoutRelaxingEditedBurstInput() {
    for unit in [TypingSpeedUnit.wpm, .cpm, .wps] {
      let text = String(unit.converted(wpm: 60.2))
      XCTAssertEqual(PracticeThresholdInput.editorValue(from: text, kind: .wordBurst, unit: unit,
        initialCanonicalValue: 60.2, preserveStoredValue: true), 60.2)
    }
    XCTAssertNil(PracticeThresholdInput.editorValue(from: "60.3", kind: .wordBurst, unit: .wpm,
      initialCanonicalValue: 60.2, preserveStoredValue: true))
    XCTAssertNil(PracticeThresholdInput.editorValue(from: "60.2", kind: .wordBurst, unit: .wpm,
      initialCanonicalValue: 60.2, preserveStoredValue: false))
    XCTAssertNil(PracticeThresholdInput.editorValue(from: "nan", kind: .wordBurst, unit: .wpm,
      initialCanonicalValue: .nan, preserveStoredValue: true))
  }
}
