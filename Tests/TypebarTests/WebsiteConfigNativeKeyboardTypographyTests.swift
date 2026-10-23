import XCTest
@testable import Typebar

final class WebsiteConfigNativeKeyboardTypographyTests: XCTestCase {
  static func nativeFields(_ s: AppSettingsSnapshot) throws -> [String: WebsiteConfigValue] {
    let input = s.keyboardInputLayout == .system ? "default" :
      try XCTUnwrap(s.keyboardInputLayout.emulatedLayout.flatMap(OfficialLayoutCommandCatalog.name))
    let guide = s.keyboardGuideLayoutSource == .websiteEmulation ? "overrideSync" :
      try XCTUnwrap(OfficialLayoutCommandCatalog.name(for: s.keyboardLayout))
    return ["layout": .string(input), "keymapLayout": .string(guide),
      "keymapMode": .string(s.keyboardGuideMode.rawValue), "keymapStyle": .string(s.keyboardGuideStyle.rawValue),
      "keymapLegendStyle": .string(s.keyboardGuideLegendStyle.rawValue),
      "keymapKeys": .string(s.keyboardGuideKeysMode.rawValue), "keymapSize": .number(s.keyboardGuideScale),
      "fontFamily": .string(s.installedPracticeFontName), "fontSize": .number(s.fontSize),
      "maxLineWidth": .number(s.practiceLineWidth == .fluid ? 0 : Double(s.customPracticeLineColumns))]
  }

  static func assertSourceRuntime(_ runtime: [String: WebsiteConfigValue],
    expected: [String: WebsiteConfigValue]? = nil) throws {
    let expected = expected ?? runtime
    var gaps = Set<String>()
    if case .number(let size) = expected["fontSize"], !(size * 16).isFinite || size * 16 < 1 { gaps.insert("fontSize") }
    if case .number(let width) = expected["maxLineWidth"],
      width != 0 && (width < 30 || width > 140 || width.rounded(.towardZero) != width) { gaps.insert("maxLineWidth") }
    if case .number(let size) = expected["keymapSize"], KeyboardGuideScalePolicy.normalized(size) != size { gaps.insert("keymapSize") }
    if case .string(let name) = expected["fontFamily"], !InputTextIdentity.matches(NativePracticeFont.normalizedName(name), name) {
      gaps.insert("fontFamily")
    }
    if !gaps.isEmpty {
      XCTAssertThrowsError(try WebsiteConfigNativeKeyboardTypography(runtime: runtime, pointsPerRem: 16)) {
        guard case .unrepresentableField(let key) = $0 as? WebsiteConfigNativeKeyboardTypographyError else {
          return XCTFail("Expected explicit native-domain gap, got \($0)")
        }
        XCTAssertTrue(gaps.contains(key), key)
      }
      return
    }
    let snapshot = try WebsiteConfigNativeKeyboardTypography(runtime: runtime, pointsPerRem: 16).applying(to: .init())
    var fields = expected.filter { WebsiteConfigNativeKeyboardTypography.mappedKeys.contains($0.key) }
    if case .number(let rem) = fields["fontSize"] { fields["fontSize"] = .number(rem * 16) }
    XCTAssertEqual(try nativeFields(snapshot), fields)
  }

  @MainActor
  func testPinnedSourceChoicesAndNumericEdges() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    guard env["TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT"] != nil else { return XCTFail("Requires pinned Zod") }
    struct Output: Decodable { var choices: [String: [WebsiteConfigValue]] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--default-profile"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let choices = try JSONDecoder().decode(Output.self, from: data).choices
    var count = 0
    for key in WebsiteConfigNativeKeyboardTypography.mappedKeys {
      let values: [WebsiteConfigValue]
      switch key {
      case "keymapSize": values = (5...35).map { .number(Double($0) / 10) }
      case "fontSize": values = [0.001, 0.0625, 0.5, 1, 3, Double.greatestFiniteMagnitude].map(WebsiteConfigValue.number)
      case "maxLineWidth": values = [0, 20, 30, 30.5, 80, 140, 1000].map(WebsiteConfigValue.number)
      default: values = try XCTUnwrap(choices[key], key)
      }
      XCTAssertFalse(values.isEmpty, key)
      for value in values {
        let prepared = try WebsiteConfigNativeProfile.prepare(WebsiteConfigJSONWriter.write(.object([key: value])), context: .init())
        try Self.assertSourceRuntime(prepared.projection.runtime)
        count += 1
      }
    }
    print("Pinned native keyboard/typography alternatives and numeric edges: \(count)")
  }

  @MainActor
  func testEveryAuditedLayoutMapsInputAndGuideIndependently() throws {
    let defaults = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    let layouts = KeyboardLayout.allCases.filter(\.isPinnedOfficialLayout)
    XCTAssertEqual(layouts.count, 239)
    for layout in layouts {
      let name = try XCTUnwrap(OfficialLayoutCommandCatalog.name(for: layout))
      var runtime = defaults
      runtime["layout"] = .string(name)
      let sync = try WebsiteConfigNativeKeyboardTypography(runtime: runtime, pointsPerRem: 16)
      XCTAssertEqual(sync.inputLayout.emulatedLayout, layout, name)
      XCTAssertNil(sync.guideLayout)
      XCTAssertEqual(KeyboardGuideLayoutSource.websiteEmulation.resolvedBuiltInLayout(
        selectedLayout: .ansiQwerty, inputLayout: sync.inputLayout), layout, name)
      runtime["layout"] = .string("default")
      runtime["keymapLayout"] = .string(name)
      let explicit = try WebsiteConfigNativeKeyboardTypography(runtime: runtime, pointsPerRem: 16)
      XCTAssertEqual(explicit.inputLayout, .system)
      XCTAssertEqual(explicit.guideLayout, layout, name)
    }
  }

  @MainActor
  func testFinalOffModeDoesNotReplayAppearanceCommandsOrChangeDormantWidth() throws {
    let prepared = try WebsiteConfigNativeProfile.prepare(
      #"{"keymapMode":"off","keymapStyle":"matrix","maxLineWidth":0}"#, context: .init())
    var before = AppSettingsSnapshot()
    before.customPracticeLineColumns = 117
    before.keyboardLayout = .ansiDvorak
    let after = try WebsiteConfigNativeKeyboardTypography(runtime: prepared.projection.runtime,
      pointsPerRem: 16).applying(to: before)
    XCTAssertEqual(after.keyboardGuideMode, .off)
    XCTAssertFalse(after.showKeyboardGuide)
    XCTAssertEqual(after.keyboardGuideStyle, .matrix)
    XCTAssertEqual(after.practiceLineWidth, .fluid)
    XCTAssertEqual(after.customPracticeLineColumns, 117)
    XCTAssertEqual(after.keyboardLayout, .ansiDvorak)
    XCTAssertEqual(after.keyboardGuideLayoutSource, .websiteEmulation)
    XCTAssertEqual(after.practiceFont, before.practiceFont)
    XCTAssertThrowsError(try JSONEncoder().encode(after))
  }

  @MainActor
  func testFontUnitsAndNativeWidthBoundariesAreExplicit() throws {
    let defaults = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    for base in [14.0, 16, 18] {
      var runtime = defaults
      runtime["fontSize"] = .number(2.5)
      for width in [0, 30, 80, 140] {
        runtime["maxLineWidth"] = .number(Double(width))
        let draft = try WebsiteConfigNativeKeyboardTypography(runtime: runtime, pointsPerRem: base)
        XCTAssertEqual(draft.fontSize, 2.5 * base)
        XCTAssertEqual(draft.columns, width == 0 ? nil : width)
      }
    }
    for (key, values): (String, [WebsiteConfigValue]) in [
      ("maxLineWidth", [.number(20), .number(1000), .number(30.5)]),
      ("fontSize", [.number(0.001), .number(.infinity)])
    ] {
      for value in values {
        var runtime = defaults
        runtime[key] = value
        XCTAssertThrowsError(try WebsiteConfigNativeKeyboardTypography(runtime: runtime, pointsPerRem: 16)) {
          XCTAssertEqual($0 as? WebsiteConfigNativeKeyboardTypographyError, .unrepresentableField(key))
        }
      }
    }
    var invalidName = defaults
    invalidName["fontFamily"] = .string("Menlo\n")
    XCTAssertThrowsError(try WebsiteConfigNativeKeyboardTypography(runtime: invalidName, pointsPerRem: 16)) {
      XCTAssertEqual($0 as? WebsiteConfigNativeKeyboardTypographyError, .invalidField("fontFamily"))
    }
    for base in [0.0, -1, .infinity, .nan] {
      XCTAssertThrowsError(try WebsiteConfigNativeKeyboardTypography(runtime: defaults, pointsPerRem: base)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeKeyboardTypographyError, .invalidFontScale)
      }
    }
  }

  @MainActor
  func testAllMappedKeysAreRequiredAndRejectNull() throws {
    let defaults = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    XCTAssertEqual(WebsiteConfigNativeKeyboardTypography.mappedKeys.count, 10)
    for key in WebsiteConfigNativeKeyboardTypography.mappedKeys {
      var runtime = defaults
      runtime.removeValue(forKey: key)
      XCTAssertThrowsError(try WebsiteConfigNativeKeyboardTypography(runtime: runtime, pointsPerRem: 16)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeKeyboardTypographyError, .missingField(key))
      }
      runtime[key] = .null
      XCTAssertThrowsError(try WebsiteConfigNativeKeyboardTypography(runtime: runtime, pointsPerRem: 16)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeKeyboardTypographyError, .invalidField(key))
      }
    }
  }

  @MainActor
  func testNativeLayoutAliasesAreNotWebsiteNames() throws {
    let prepared = try WebsiteConfigNativeProfile.prepare("{}", context: .init())
    for key in ["layout", "keymapLayout"] {
      var runtime = prepared.projection.runtime
      runtime[key] = .string("ansiQwerty")
      XCTAssertThrowsError(try WebsiteConfigNativeKeyboardTypography(runtime: runtime, pointsPerRem: 16)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeKeyboardTypographyError, .invalidField(key))
      }
    }
  }

  @MainActor
  func testUnsupportedSyncAbortsBeforeChangingEitherSettingsGeneration() throws {
    for source in [false, true] {
      let suite = "typebar.website-keyboard.\(UUID().uuidString)"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      if source {
        XCTAssertTrue(ThresholdSettingsStore(defaults: defaults).save(
          PracticeThresholdSource(configuration: .init()).applying(to: AppSettingsSnapshot())))
      }
      let settings = AppSettings(defaults: defaults,
        feedbackSound: TypingFeedbackSound(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
      let before = settings.snapshot
      let stored = defaults.persistentDomain(forName: suite) ?? [:]
      var draft = settings.snapshot
      draft.keyboardGuideLayoutSource = .websiteEmulation
      draft.fontSize = 64
      draft.keyboardGuideMode = .next
      XCTAssertFalse(settings.apply(draft))
      XCTAssertEqual(settings.snapshot, before)
      XCTAssertTrue(NSDictionary(dictionary: stored).isEqual(to: defaults.persistentDomain(forName: suite) ?? [:]))
    }
  }

  func testWebsiteSyncDefaultsToQwertyWithoutChangingLegacyModesOrTransport() throws {
    let website = KeyboardGuideLayoutSource.websiteEmulation
    XCTAssertEqual(website.resolvedBuiltInLayout(selectedLayout: .ansiDvorak, inputLayout: .system), .ansiQwerty)
    XCTAssertFalse(website.usesSystemInputRows(inputLayout: .system))
    XCTAssertEqual(website.resolvedBuiltInLayout(selectedLayout: .ansiDvorak,
      inputLayout: .init(emulating: .ansiColemak)), .ansiColemak)
    XCTAssertTrue(KeyboardGuideLayoutSource.inputEmulation.usesSystemInputRows(inputLayout: .system))
    XCTAssertEqual(KeyboardGuideLayoutSource.allCases, [.builtIn, .inputEmulation, .systemInput, .custom])
    for mode in KeyboardGuideLayoutSource.allCases {
      XCTAssertEqual(try JSONDecoder().decode(KeyboardGuideLayoutSource.self, from: JSONEncoder().encode(mode)), mode)
    }
    XCTAssertThrowsError(try JSONEncoder().encode(website))
    XCTAssertThrowsError(try JSONDecoder().decode(KeyboardGuideLayoutSource.self, from: Data(#""websiteEmulation""#.utf8)))
  }

  @MainActor
  func testFourDraftGroupsComposeAndExplicitGuideSurvivesNativeJSON() throws {
    let runtime = try WebsiteConfigNativeProfile.prepare(
      #"{"keymapLayout":"dvorak","layout":"colemak","fontFamily":"Iosevka","fontSize":3,"maxLineWidth":120,"difficulty":"expert","timerStyle":"flash_text","britishEnglish":true}"#,
      context: .init()).projection.runtime
    let keyboard = try WebsiteConfigNativeKeyboardTypography(runtime: runtime, pointsPerRem: 16)
    let rules = try WebsiteConfigNativeInputRules(runtime: runtime)
    let presentation = try WebsiteConfigNativePresentation(runtime: runtime)
    let behavior = try WebsiteConfigNativeBehavior(runtime: runtime)
    var keys = WebsiteConfigNativeKeyboardTypography.mappedKeys
    for group in [WebsiteConfigNativeInputRules.mappedKeys, WebsiteConfigNativePresentation.mappedKeys,
      WebsiteConfigNativeBehavior.mappedKeys] {
      XCTAssertTrue(keys.isDisjoint(with: group))
      keys.formUnion(group)
    }
    XCTAssertEqual(keys.count, 70)
    var before = AppSettingsSnapshot()
    let custom = CustomKeyboardGuideLayout(name: "Independent test layout", numberRow: "1234567890",
      topRow: "qwertyuiop", homeRow: "asdfghjkl", bottomRow: "zxcvbnm")
    before.customKeyboardLayouts = [custom]
    before.customKeyboardLayoutID = custom.id
    before.globalHotkeyEnabled = true
    let after = keyboard.applying(to: behavior.applying(to: presentation.applying(to: rules.applying(to: before))))
    XCTAssertEqual(after, rules.applying(to: presentation.applying(to: behavior.applying(to: keyboard.applying(to: before)))))
    XCTAssertEqual(after.customKeyboardLayouts, before.customKeyboardLayouts)
    XCTAssertEqual(after.customKeyboardLayoutID, custom.id)
    XCTAssertEqual(after.practiceFont, before.practiceFont)
    XCTAssertTrue(after.globalHotkeyEnabled)
    let configuration = behavior.applying(to: rules.applying(to: TestConfiguration.words(3)))
    let json = try SettingsJSONCommandCodec.export(settings: after, configuration: configuration,
      layoutFluidLayouts: [.ansiQwerty, .ansiDvorak], testParameterMemory: .defaults)
    let restored = try SettingsJSONCommandCodec.decode(json)
    XCTAssertEqual(restored.version, 6)
    XCTAssertEqual(try Self.nativeFields(restored.settings), try Self.nativeFields(after))
    XCTAssertEqual(restored.settings.thresholdSource, after.thresholdSource)
    XCTAssertEqual(restored.settings.customKeyboardLayoutID, custom.id)
    XCTAssertEqual(try WebsiteConfigNativeBehaviorTests.nativeFields(restored.settings),
      try WebsiteConfigNativeBehaviorTests.nativeFields(after))
    var sync = after
    sync.keyboardGuideLayoutSource = .websiteEmulation
    XCTAssertThrowsError(try SettingsJSONCommandCodec.export(settings: sync, configuration: configuration,
      layoutFluidLayouts: [.ansiQwerty, .ansiDvorak], testParameterMemory: .defaults))
  }

  @MainActor
  func testKeyboardInputGuideAndTypographyHaveDistinctNativeMeaning() throws {
    let prepared = try WebsiteConfigNativeProfile.prepare(#"{"layout":"colemak","keymapMode":"react","keymapStyle":"split_matrix","keymapLegendStyle":"uppercase","keymapKeys":"minimal_numrow","keymapSize":1.6,"keymapLayout":"dvorak","fontFamily":"Iosevka","fontSize":3,"maxLineWidth":120}"#, context: .init())
    let mapped = try WebsiteConfigNativeKeyboardTypography(runtime: prepared.projection.runtime, pointsPerRem: 16)
    let snapshot = mapped.applying(to: .init())
    XCTAssertEqual(snapshot.keyboardInputLayout.emulatedLayout, .ansiColemak)
    XCTAssertEqual(snapshot.keyboardGuideLayoutSource, .builtIn)
    XCTAssertEqual(snapshot.keyboardLayout, .ansiDvorak)
    XCTAssertEqual(snapshot.keyboardGuideMode, .react)
    XCTAssertTrue(snapshot.showKeyboardGuide)
    XCTAssertEqual(snapshot.keyboardGuideStyle, .splitMatrix)
    XCTAssertEqual(snapshot.keyboardGuideLegendStyle, .uppercase)
    XCTAssertEqual(snapshot.keyboardGuideKeysMode, .minimalNumberRow)
    XCTAssertEqual(snapshot.keyboardGuideScale, 1.6)
    XCTAssertEqual(snapshot.installedPracticeFontName, "Iosevka")
    XCTAssertEqual(snapshot.fontSize, 48)
    XCTAssertEqual(snapshot.practiceLineWidth, .custom)
    XCTAssertEqual(snapshot.customPracticeLineColumns, 120)
  }
}
