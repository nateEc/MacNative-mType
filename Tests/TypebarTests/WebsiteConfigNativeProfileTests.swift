import XCTest
@testable import Typebar

final class WebsiteConfigNativeProfileTests: XCTestCase {
  func testEveryLanguageIdentityIsExactReversibleAndExcludesNativeMixedModes() throws {
    struct Fixture: Decodable { var nativeIndependent: [String: String] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let fixture = try JSONDecoder().decode(Fixture.self,
      from: Data(contentsOf: root.appendingPathComponent("Compatibility/official-languages.json")))
    XCTAssertEqual(WebsiteLanguageIdentity.byWebsiteName.mapValues(\.rawValue), fixture.nativeIndependent)
    let expected = Set(TypingLanguage.allCases).subtracting([.mixedLanguages, .mixedEnglishChinese])
    XCTAssertEqual(WebsiteLanguageIdentity.byWebsiteName.count, 446)
    XCTAssertEqual(Set(WebsiteLanguageIdentity.byWebsiteName.values), expected)
    for (name, language) in WebsiteLanguageIdentity.byWebsiteName {
      XCTAssertEqual(WebsiteLanguageIdentity.language(for: name), language)
      XCTAssertEqual(WebsiteLanguageIdentity.name(for: language), name)
    }
    XCTAssertEqual(WebsiteLanguageIdentity.language(for: "english_1k"), .english1k)
    XCTAssertEqual(WebsiteLanguageIdentity.language(for: "code_c++"), .codeCPP)
    for invalid in ["English", "english1k", "english_1K", "code_cpp", "mixedLanguages", "english ", ""] {
      XCTAssertNil(WebsiteLanguageIdentity.language(for: invalid), invalid)
    }
    XCTAssertNil(WebsiteLanguageIdentity.name(for: .mixedLanguages))
    XCTAssertNil(WebsiteLanguageIdentity.name(for: .mixedEnglishChinese))
  }

  @MainActor
  func testOfflineNativeProfileUsesOwnedPaletteAndCompletePreparation() throws {
    let defaults = try WebsiteConfigNativeProfile.defaultDocument()
    XCTAssertEqual(defaults.values.count, 94)
    guard case .array(let colors) = defaults.values["customThemeColors"] else { return XCTFail("Missing native palette") }
    XCTAssertEqual(colors.count, 10)
    XCTAssertEqual(colors[0], .string("#252c33"))
    XCTAssertEqual(colors[1], .string("#e7c99d"))
    XCTAssertEqual(colors[4], .string("#39464e"))
    XCTAssertEqual(colors[2], colors[1])
    let schema = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs)
    XCTAssertTrue(defaults.values.allSatisfy { schema.accepts($0.value, for: $0.key) })
    let prepared = try WebsiteConfigNativeProfile.prepare("{\"language\":\"english_1k\",\"layout\":\"colemak\",\"numbers\":true}", context: .init())
    XCTAssertEqual(prepared.projection.runtime["language"], .string("english_1k"))
    XCTAssertEqual(prepared.projection.runtime["layout"], .string("colemak"))
    XCTAssertEqual(prepared.projection.runtime["numbers"], .bool(true))
    XCTAssertEqual(prepared.projection.runtime["time"], .number(30))
    XCTAssertEqual(prepared.projection.runtime["customThemeColors"], .array(colors))
    XCTAssertTrue(prepared.projection.rejectedKeys.isEmpty)
    let fallback = try WebsiteConfigNativeProfile.prepare("{\"language\":\"english1k\"}", context: .init())
    XCTAssertEqual(fallback.projection.runtime["language"], .string("english"))
    XCTAssertThrowsError(try WebsiteConfigNativeProfile.prepare("[]", context: .init()))
    XCTAssertThrowsError(try WebsiteConfigNativeProfile.prepare("{\"numbers\":true,}", context: .init()))
  }

  @MainActor
  func testLayoutNamesRoundTripWithoutUIOrTypebarOnlyAliases() {
    let layouts = KeyboardLayout.allCases.filter(\.isPinnedOfficialLayout)
    XCTAssertEqual(layouts.count, 239)
    let names = layouts.compactMap(OfficialLayoutCommandCatalog.name)
    XCTAssertEqual(Set(names).count, layouts.count)
    for layout in layouts {
      guard let name = OfficialLayoutCommandCatalog.name(for: layout) else { return XCTFail("Missing layout identity") }
      XCTAssertEqual(OfficialLayoutCommandCatalog.target(for: "input.layout.\(name)"), .builtIn(layout))
    }
    XCTAssertNil(OfficialLayoutCommandCatalog.name(for: .nordicQwerty))
    XCTAssertFalse(WebsiteConfigNativeProfile.catalogs.themes.contains("grove"))
    XCTAssertFalse(WebsiteConfigNativeProfile.catalogs.layouts.contains("default"))
  }

  @MainActor
  func testProductCatalogsMatchPinnedSchemaWithoutReferenceResources() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Output: Decodable {
      struct Catalogs: Decodable {
        var languages: Set<String>, themes: Set<String>, layouts: Set<String>, fonts: Set<String>, funboxes: Set<String>
      }
      var catalogs: Catalogs
    }
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
    let expected = try JSONDecoder().decode(Output.self, from: data).catalogs
    let actual = WebsiteConfigNativeProfile.catalogs
    XCTAssertEqual(actual.languages, expected.languages)
    XCTAssertEqual(actual.themes, expected.themes)
    XCTAssertEqual(actual.layouts, expected.layouts)
    XCTAssertEqual(actual.fonts, expected.fonts)
    XCTAssertEqual(actual.funboxes, expected.funboxes)
  }
}
