import XCTest
@testable import Typebar

final class WebsiteConfigNativeThemesTests: XCTestCase {
  static func assertSourceRuntime(_ runtime: [String: WebsiteConfigValue], expected: [String: WebsiteConfigValue]) throws {
    let draft = try WebsiteConfigNativeThemes(runtime: runtime)
    let fields: [String: WebsiteConfigValue] = [
      "theme": .string(draft.theme.rawValue), "themeLight": .string(draft.lightTheme.rawValue),
      "themeDark": .string(draft.darkTheme.rawValue), "autoSwitchTheme": .bool(draft.followsSystem),
      "customTheme": .bool(draft.customEnabled), "randomTheme": .string(draft.randomMode.rawValue),
      "favThemes": .array(draft.favorites.map { .string($0.rawValue) }),
      "customThemeColors": .array(draft.customColorHex.map(WebsiteConfigValue.string))]
    XCTAssertEqual(fields, expected.filter { WebsiteConfigNativeThemes.mappedKeys.contains($0.key) })
  }

  @MainActor
  func testActualSourceEventsAndAllLightnessBoundaries() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Event: Decodable { let followsSystem: Bool, customEnabled: Bool, systemIsDark: Bool; let initial: String; let change: String? }
    struct Color: Decodable { let hex: String; let dark: Bool }
    struct Output: Decodable { let events: [Event]; let colors: [Color] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-theme-state.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.events.count, 8)
    XCTAssertEqual(output.colors.count, 4863)
    var runtime = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    runtime["theme"] = .string("serika_dark"); runtime["themeLight"] = .string("serika")
    runtime["themeDark"] = .string("dracula")
    func selection(_ name: String) -> WebsiteConfigNativeThemes.Selection {
      name == "custom" ? .inlineCustom : .builtIn(AppTheme(rawValue: name)!)
    }
    for event in output.events {
      runtime["autoSwitchTheme"] = .bool(event.followsSystem)
      runtime["customTheme"] = .bool(event.customEnabled)
      let draft = try WebsiteConfigNativeThemes(runtime: runtime)
      XCTAssertEqual(draft.initialSelection(systemIsDark: event.systemIsDark), selection(event.initial))
      XCTAssertEqual(draft.systemAppearanceChange(systemIsDark: event.systemIsDark), event.change.map(selection))
    }
    let id = UUID()
    for color in output.colors {
      guard case .array(var colors) = runtime["customThemeColors"] else { return XCTFail("Missing palette") }
      colors[0] = .string(color.hex); runtime["customThemeColors"] = .array(colors)
      let draft = try WebsiteConfigNativeThemes(runtime: runtime)
      XCTAssertEqual(try draft.makeCustomTheme(id: id, name: "Owned preview").prefersDark, color.dark, color.hex)
    }
  }

  @MainActor
  func testPaletteLexemesRolesAndExplicitPreviewRoundTrip() throws {
    var runtime = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    let hex = ["#f00", "#123456", "#abc", "#ABC", "#ffffff", "#fff", "#010203", "#102030", "#789", "#987"]
    runtime["customThemeColors"] = .array(hex.map(WebsiteConfigValue.string))
    let draft = try WebsiteConfigNativeThemes(runtime: runtime)
    XCTAssertEqual(draft.customColorHex, hex)
    XCTAssertEqual(draft.customColors[2], draft.customColors[3])
    XCTAssertEqual(draft.customColors[4], draft.customColors[5])
    let id = UUID(), theme = try draft.makeCustomTheme(id: id, name: "Owned preview")
    XCTAssertEqual(theme.id, id)
    XCTAssertFalse(theme.prefersDark, "Pure red has HSL lightness 50%, not luminance darkness")
    XCTAssertEqual([theme.background, theme.accent, theme.caret, theme.secondaryText, theme.panel,
      theme.text, theme.error, theme.extraInput, theme.colorfulError, theme.colorfulExtraInput], draft.customColors)
    XCTAssertEqual(theme.fadedText, theme.panel, "Native extra role is derived, not an eleventh source slot")
    XCTAssertEqual(try JSONDecoder().decode(CustomThemeDefinition.self, from: JSONEncoder().encode(theme)), theme)
    for name in ["", " leading", "trailing ", String(repeating: "a", count: 41)] {
      XCTAssertThrowsError(try draft.makeCustomTheme(id: id, name: name))
    }
    XCTAssertNoThrow(try draft.makeCustomTheme(id: id, name: String(repeating: "a", count: 40)))
    let input = ##"{"customThemeColors":["#abc","#ABC","#abc","#ABC","#abc","#ABC","#abc","#ABC","#abc","#ABC"]}"##
    let mixed = try WebsiteConfigNativeThemes(runtime: WebsiteConfigNativeProfile.prepare(input, context: .init()).projection.runtime)
    XCTAssertEqual(mixed.customColorHex[0], "#abc")
    XCTAssertEqual(mixed.customColorHex[1], "#ABC")
    XCTAssertEqual(Set(mixed.customColors.map { $0.red }).count, 1)
  }

  @MainActor
  func testCatalogAndMalformedFieldsDoNotSilentlyFallback() throws {
    let defaults = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    let earlier = WebsiteConfigNativeInputRules.mappedKeys.union(WebsiteConfigNativePresentation.mappedKeys)
      .union(WebsiteConfigNativeBehavior.mappedKeys).union(WebsiteConfigNativeKeyboardTypography.mappedKeys)
      .union(WebsiteConfigNativeTestParameters.mappedKeys).union(WebsiteConfigNativeQuoteSelection.mappedKeys)
      .union(WebsiteConfigNativeGenerators.mappedKeys)
    XCTAssertTrue(earlier.isDisjoint(with: WebsiteConfigNativeThemes.mappedKeys))
    XCTAssertEqual(earlier.union(WebsiteConfigNativeThemes.mappedKeys).count, 89)
    for key in WebsiteConfigNativeThemes.mappedKeys {
      var runtime = defaults; runtime.removeValue(forKey: key)
      XCTAssertThrowsError(try WebsiteConfigNativeThemes(runtime: runtime)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeThemesError, .missingField(key))
      }
      runtime[key] = .null
      XCTAssertThrowsError(try WebsiteConfigNativeThemes(runtime: runtime)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeThemesError, .invalidField(key))
      }
    }
    for key in ["theme", "themeLight", "themeDark"] {
      for theme in AppTheme.allCases where theme != .grove {
        var runtime = defaults; runtime[key] = .string(theme.rawValue)
        XCTAssertNoThrow(try WebsiteConfigNativeThemes(runtime: runtime))
      }
      for invalid in ["grove", "custom", "SERIKA", UUID().uuidString] {
        var runtime = defaults; runtime[key] = .string(invalid)
        XCTAssertThrowsError(try WebsiteConfigNativeThemes(runtime: runtime))
      }
    }
    for mode in ["off", "on", "fav", "light", "dark", "auto", "custom"] {
      var runtime = defaults; runtime["randomTheme"] = .string(mode)
      XCTAssertEqual(try WebsiteConfigNativeThemes(runtime: runtime).randomMode.rawValue, mode)
    }
    for invalid in ["#abcd", "#12345678", "red", " #fff", "#fff\n"] {
      var runtime = defaults
      guard case .array(var colors) = runtime["customThemeColors"] else { return XCTFail("Missing palette") }
      colors[0] = .string(invalid); runtime["customThemeColors"] = .array(colors)
      XCTAssertThrowsError(try WebsiteConfigNativeThemes(runtime: runtime), invalid)
    }
  }

  @MainActor
  func testThemeDraftRetainsIndependentFlagsFavoritesAndEventPriority() throws {
    let runtime = try WebsiteConfigNativeProfile.prepare(
      #"{"theme":"serika_dark","themeLight":"serika","themeDark":"dracula","autoSwitchTheme":true,"customTheme":true,"favThemes":["dracula","serika","dracula"],"randomTheme":"fav"}"#,
      context: .init()).projection.runtime
    let draft = try WebsiteConfigNativeThemes(runtime: runtime)
    XCTAssertEqual(draft.theme, .serika_dark)
    XCTAssertEqual(draft.lightTheme, .serika)
    XCTAssertEqual(draft.darkTheme, .dracula)
    XCTAssertTrue(draft.followsSystem)
    XCTAssertTrue(draft.customEnabled)
    XCTAssertEqual(draft.favorites, [.dracula, .serika, .dracula])
    XCTAssertEqual(draft.randomMode, .favorites)
    XCTAssertEqual(draft.initialSelection(systemIsDark: false), .builtIn(.serika))
    XCTAssertEqual(draft.initialSelection(systemIsDark: true), .builtIn(.dracula))
    XCTAssertNil(draft.systemAppearanceChange(systemIsDark: false))
  }
}
