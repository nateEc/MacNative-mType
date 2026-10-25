import XCTest
@testable import Typebar

@MainActor final class PracticeKeyboardGuideSelectionTests: XCTestCase {
  func testCompleteProfileOwnsEveryGuideDisplayFieldWithoutWritingLegacyPreferences() throws {
    let suite = "typebar.guide-selection.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults,
      feedbackSound: .init(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    settings.keyboardGuideMode = .off
    settings.keyboardGuideScale = 3.5
    settings.keyboardGuideLegendStyle = .blank
    settings.keyboardGuideKeysMode = .minimal
    settings.keyboardGuideStyle = .staggered
    settings.keyboardInputLayout = .init(emulating: .ansiColemak)
    settings.keyboardGuideLayoutSource = .custom
    let before = settings.snapshot
    let disk = defaults.persistentDomain(forName: suite) ?? [:]
    for mode in KeyboardGuideMode.allCases {
      for style in KeyboardGuideStyle.allCases {
        let draft = try WebsiteConfigNativeProfile.prepareDraft(
          #"{"layout":"dvorak","keymapLayout":"qwerty","keymapMode":"\#(mode.rawValue)","keymapStyle":"\#(style.rawValue)","keymapLegendStyle":"uppercase","keymapKeys":"full","keymapSize":1.6}"#,
          pointsPerRem: 16, context: .init())
        let display = PracticeKeyboardGuideSelection(draft: draft, settings: settings, legacyMode: .next)
        XCTAssertEqual(display.mode, mode); XCTAssertEqual(display.style, style)
        XCTAssertEqual(display.scale, 1.6); XCTAssertEqual(display.legendStyle, .uppercase)
        XCTAssertEqual(display.keysMode, .full); XCTAssertFalse(display.allowsLegacyRows)
        XCTAssertEqual(draft.keyboardTypography.inputLayout.emulatedLayout, .ansiDvorak)
        XCTAssertEqual(draft.keyboardTypography.guideLayout, .ansiQwerty)
      }
    }
    XCTAssertEqual(settings.snapshot, before)
    XCTAssertTrue(NSDictionary(dictionary: disk).isEqual(to: defaults.persistentDomain(forName: suite) ?? [:]))
  }

  func testLegacyGuideRetainsChallengeModeAndAllExistingDisplayPreferences() throws {
    let suite = "typebar.guide-selection-legacy.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults,
      feedbackSound: .init(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    settings.keyboardGuideMode = .react; settings.keyboardGuideScale = 2.1
    settings.keyboardGuideLegendStyle = .dynamic; settings.keyboardGuideKeysMode = .minimalNumberRow
    settings.keyboardGuideStyle = .splitMatrix
    let display = PracticeKeyboardGuideSelection(draft: nil, settings: settings, legacyMode: .next)
    XCTAssertEqual(display.mode, .next); XCTAssertEqual(display.scale, 2.1)
    XCTAssertEqual(display.legendStyle, .dynamic); XCTAssertEqual(display.keysMode, .minimalNumberRow)
    XCTAssertEqual(display.style, .splitMatrix); XCTAssertTrue(display.allowsLegacyRows)
    XCTAssertEqual(PracticeKeyboardGuideSelection(draft: nil, settings: settings).mode, .react)
  }
}
