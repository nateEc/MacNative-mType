import XCTest
@testable import Typebar

@MainActor
final class EditorConfigurationSaveTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) rethrows {
    let suite = "typebar.editor-save.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(AppSettings(defaults: defaults), defaults)
  }

  func testValidEditorCommitsNotifyAfterApplyingTheirFinalValues() {
    withSettings { settings, _ in
      var calls = 0
      XCTAssertTrue(PaceCustomSpeedPolicy.apply(123.5, to: settings, activateCustom: true,
        onConfigurationSave: {
          XCTAssertEqual(settings.paceGuideCustomWpm, 123.5)
          XCTAssertEqual(settings.paceGuideMode, .custom)
          calls += 1
        }))
      XCTAssertTrue(KeyboardGuideScalePolicy.apply(1.4, to: settings, onConfigurationSave: {
        XCTAssertEqual(settings.keyboardGuideScale, 1.4); calls += 1
      }))
      XCTAssertTrue(FontFamilyNameCommandPolicy.apply("Independent Font", to: settings,
        onConfigurationSave: {
          XCTAssertEqual(settings.installedPracticeFontName, "Independent Font"); calls += 1
        }))
      XCTAssertTrue(FontFamilyCommandApplication.apply(.systemDesign(.monospaced), to: settings,
        onConfigurationSave: {
          XCTAssertEqual(settings.installedPracticeFontName, "")
          XCTAssertEqual(settings.practiceFont, .monospaced); calls += 1
        }))
      XCTAssertTrue(CustomBackgroundCommandEditorPolicy.apply("3", kind: .blur, to: settings,
        onConfigurationSave: {
          XCTAssertEqual(settings.customBackgroundFilter.blur, 3); calls += 1
        }))
      XCTAssertEqual(calls, 5)
    }
  }

  func testRejectedValuesAndNavigationTargetsNeverDeactivateFontsOrCommit() {
    withSettings { settings, defaults in
      let before = defaults.data(forKey: "appSettings.v1")
      var commits = 0
      let commit = { commits += 1 }
      XCTAssertFalse(PaceCustomSpeedPolicy.apply(.infinity, to: settings, activateCustom: true, onConfigurationSave: commit))
      for value in [Double.nan, -1, 1.25, 3.6] {
        XCTAssertFalse(KeyboardGuideScalePolicy.apply(value, to: settings, onConfigurationSave: commit))
      }
      XCTAssertFalse(FontFamilyNameCommandPolicy.apply("\n", to: settings, onConfigurationSave: commit))
      for target: FontFamilyCommandTarget in [.installedName("Absent Font"), .customName, .browseInstalled] {
        XCTAssertFalse(FontFamilyCommandApplication.apply(target, to: settings,
          isFontAvailable: { _ in false }, onConfigurationSave: commit))
      }
      XCTAssertFalse(CustomBackgroundCommandEditorPolicy.apply("NaN", kind: .blur, to: settings, onConfigurationSave: commit))
      XCTAssertEqual(commits, 0)
      XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), before)
    }
  }

  func testAnUnchangedConfirmedValueStillCommitsButRejectedInputDoesNotAdvanceSelection() throws {
    try withSettings { settings, defaults in
      let original = ActiveTestSelectionDocument(preset: .init(configuration: .words(17)),
        testParameterMemory: .init(duration: 30, wordLimit: 17,
          customTextDuration: 45, customTextWordLimit: 9, customTextSectionLimit: 5))
      let practice = try XCTUnwrap(WordPracticeText.sectionedPractice(segments: ["a|b"], selectedTargetCount: 1))
      var navigation = try XCTUnwrap(WordPracticeTransition.begin(previous: nil, practice: practice,
        currentPreset: { original.preset }, currentSelection: { _ in original }, selectCustomMode: { true }))
      let current = ActiveTestSelectionDocument(preset: .init(configuration: .init(mode: .custom,
        duration: nil, wordLimit: nil, difficulty: .normal, rules: settings.inputRules,
        customTextCompletion: .sections, customTextSectionLimit: 5,
        customTextOrdering: practice.ordering, customTextPipeDelimiter: true), customText: practice.text),
        testParameterMemory: original.testParameterMemory)
      let store = ActiveTestSelectionStore(defaults: defaults)
      XCTAssertTrue(store.save(original))
      var commits = 0
      let commit = {
        commits += 1
        XCTAssertTrue(navigation.persistSelection(current: current, cause: .configurationSave, save: store.save))
      }
      XCTAssertFalse(KeyboardGuideScalePolicy.apply(.nan, to: settings, onConfigurationSave: commit))
      XCTAssertEqual(store.load(), original)
      XCTAssertTrue(KeyboardGuideScalePolicy.apply(settings.keyboardGuideScale, to: settings, onConfigurationSave: commit))
      XCTAssertEqual(store.load(), current)
      XCTAssertEqual(commits, 1)
    }
  }

  func testInstalledFontAdmissionPrecedesTheFinalCommitWithoutChangingFileSelection() {
    withSettings { settings, _ in
      var events: [String] = []
      XCTAssertTrue(FontFamilyCommandApplication.apply(.installedName("Available Font"), to: settings,
        isFontAvailable: { $0 == "Available Font" },
        onConfigurationSave: {
          XCTAssertEqual(settings.installedPracticeFontName, "Available Font")
          events.append("save")
        }))
      XCTAssertEqual(events, ["save"])
      XCTAssertFalse(FontFamilyCommandApplication.apply(.installedName("Removed Font"), to: settings,
        isFontAvailable: { _ in false },
        onConfigurationSave: { events.append("unexpected save") }))
      XCTAssertEqual(settings.installedPracticeFontName, "Available Font")
      XCTAssertEqual(events, ["save"])
    }
  }
}
