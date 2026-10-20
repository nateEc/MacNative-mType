import SwiftUI
import XCTest
@testable import Typebar

@MainActor
final class RemainingCommandSaveTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) rethrows {
    let suite = "typebar.remaining-commands.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(AppSettings(defaults: defaults), defaults)
  }

  func testLayoutsPreferencesAndThresholdsNotifyOnlyAfterFinalValues() {
    withSettings { settings, _ in
      var calls = 0
      KeyboardGuideLayoutCommandTarget.builtIn(.ansiDvorak).apply(to: settings, onConfigurationSave: {
        XCTAssertEqual(settings.keyboardLayout, .ansiDvorak)
        XCTAssertEqual(settings.keyboardGuideLayoutSource, .builtIn); calls += 1
      })
      OfficialLayoutCommandTarget.system.apply(to: settings, onConfigurationSave: {
        XCTAssertEqual(settings.keyboardInputLayout, .system); calls += 1
      })
      PracticePreferenceCommandTarget.englishVariant(.british).apply(to: settings, onConfigurationSave: {
        XCTAssertEqual(settings.englishVariant, .british); calls += 1
      })
      XCTAssertTrue(PracticeThresholdCommandTarget.minimumWpmOff.applyImmediate(to: settings, onConfigurationSave: { calls += 1 }))
      XCTAssertTrue(PracticeThresholdApplication.apply(44.5, kind: .minimumWpm, to: settings, onConfigurationSave: {
        XCTAssertEqual(settings.minimumWpm, 44.5); calls += 1
      }))
      XCTAssertEqual(calls, 5)
    }
  }

  func testInvalidThresholdInputDoesNotNormalizeIntoAnAcceptedSave() {
    withSettings { settings, defaults in
      settings.minimumAccuracy = 95
      settings.minimumWpm = 40
      let before = defaults.data(forKey: "appSettings.v1")
      var calls = 0
      for value in [Double.nan, .infinity, -1] {
        XCTAssertFalse(PracticeThresholdApplication.apply(value, kind: .minimumWpm, to: settings,
          onConfigurationSave: { calls += 1 }))
      }
      XCTAssertFalse(PracticeThresholdApplication.apply(101, kind: .minimumAccuracy, to: settings,
        onConfigurationSave: { calls += 1 }))
      XCTAssertFalse(PracticeThresholdCommandTarget.minimumAccuracyCustom.applyImmediate(to: settings,
        onConfigurationSave: { calls += 1 }))
      XCTAssertEqual(settings.minimumAccuracy, 95)
      XCTAssertEqual(settings.minimumWpm, 40)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), before)
      XCTAssertEqual(calls, 0)
    }
  }

  func testBackgroundRemovalCommitsAfterFileSuccessButNotAfterFailure() throws {
    enum Failure: Error { case owned }
    try withSettings { settings, _ in
      settings.customBackgroundURL = "https://example.com/owned.png"
      var events: [String] = []
      XCTAssertThrowsError(try CustomBackgroundCommandApplication.removeBackground(from: settings,
        onConfigurationSave: { events.append("unexpected save") }, removeLocal: { throw Failure.owned }))
      XCTAssertEqual(settings.customBackgroundURL, "https://example.com/owned.png")
      XCTAssertTrue(events.isEmpty)
      CustomBackgroundCommandApplication.removeBackground(from: settings, onConfigurationSave: {
        XCTAssertEqual(settings.customBackgroundURL, ""); events.append("save")
      }, removeLocal: { events.append("remove") })
      XCTAssertEqual(events, ["remove", "save"])
    }
  }

  func testBackgroundFitAndFavoriteSaveOnlyWhenApplied() {
    withSettings { settings, _ in
      var calls = 0
      let commit = { calls += 1 }
      XCTAssertTrue(CustomBackgroundCommandApplication.applyImmediate(.fit(.max), to: settings, onConfigurationSave: commit))
      XCTAssertFalse(CustomBackgroundCommandApplication.applyImmediate(.localFile, to: settings, onConfigurationSave: commit))
      settings.followSystemTheme = false
      settings.selectBuiltInTheme(.grove)
      XCTAssertTrue(CurrentThemeFavoriteCommandApplication.apply(.add, to: settings, colorScheme: .dark, onConfigurationSave: commit))
      XCTAssertFalse(CurrentThemeFavoriteCommandApplication.apply(.add, to: settings, colorScheme: .dark, onConfigurationSave: commit))
      XCTAssertTrue(CurrentThemeFavoriteCommandApplication.apply(.remove, to: settings, colorScheme: .dark, onConfigurationSave: commit))
      XCTAssertEqual(calls, 3)
    }
  }
}
