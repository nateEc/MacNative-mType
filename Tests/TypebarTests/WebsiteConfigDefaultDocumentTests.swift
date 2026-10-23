import XCTest
@testable import Typebar

final class WebsiteConfigDefaultDocumentTests: XCTestCase {
  private var ownedAppearance: WebsiteConfigDefaultAppearance {
    .init(theme: "owned_dark", lightTheme: "owned_light", darkTheme: "owned_dark",
      fontFamily: "Menlo", customThemeColors: (0..<10).map { String(format: "#%06x", 0x102030 + $0 * 0x010101) })
  }

  private var ownedCatalogs: WebsiteConfigCatalogs {
    .init(languages: ["english", "spanish", "french", "german"], themes: ["owned_dark", "owned_light"],
      layouts: ["qwerty", "dvorak", "colemak"], fonts: [], funboxes: [])
  }

  func testOwnedAppearanceAndDefaultsHaveNoSharedMutationOrCurrentSettings() throws {
    let document = try WebsiteConfigDefaultDocument(appearance: ownedAppearance, catalogs: ownedCatalogs)
    XCTAssertEqual(document.values["theme"], .string("owned_dark"))
    XCTAssertEqual(document.values["themeLight"], .string("owned_light"))
    XCTAssertEqual(document.values["themeDark"], .string("owned_dark"))
    XCTAssertEqual(document.values["fontFamily"], .string("Menlo"))
    XCTAssertEqual(document.values["customThemeColors"], .array(ownedAppearance.customThemeColors.map(WebsiteConfigValue.string)))
    var changed = document.values
    changed["time"] = .number(900)
    changed["funbox"] = .array([.string("no_quit")])
    changed["customThemeColors"] = .array([])
    XCTAssertNotEqual(changed, document.values)
    XCTAssertEqual(try WebsiteConfigDefaultDocument(appearance: ownedAppearance, catalogs: ownedCatalogs).values, document.values)
    XCTAssertEqual(try WebsiteConfigJSONReader.read(WebsiteConfigJSONWriter.write(.object(document.values))), .object(document.values))
    let prepared = try WebsiteConfigImportPreparation.prepare("{\"numbers\":true}", defaultDocument: document,
      schema: .init(catalogs: ownedCatalogs), context: .init())
    XCTAssertEqual(prepared.projection.runtime["time"], .number(30))
    XCTAssertEqual(prepared.projection.runtime["numbers"], .bool(true))
    XCTAssertEqual(prepared.projection.runtime["funbox"], .array([]))
    XCTAssertEqual(document.values["numbers"], .bool(false))
    XCTAssertEqual(document.orderedKeys.count, Set(document.orderedKeys).count)
  }

  func testInvalidAppearanceOrIncompleteCatalogDoesNotPublishPartialDefaults() throws {
    for colors in [[], Array(repeating: "#123456", count: 9), Array(repeating: "#123456", count: 11),
      Array(repeating: "not-a-color", count: 10)] {
      var appearance = ownedAppearance
      appearance.customThemeColors = colors
      XCTAssertThrowsError(try WebsiteConfigDefaultDocument(appearance: appearance, catalogs: ownedCatalogs))
    }
    var unknownTheme = ownedAppearance
    unknownTheme.lightTheme = "unknown"
    XCTAssertThrowsError(try WebsiteConfigDefaultDocument(appearance: unknownTheme, catalogs: ownedCatalogs))
    var invalidFont = ownedAppearance
    invalidFont.fontFamily = ""
    XCTAssertThrowsError(try WebsiteConfigDefaultDocument(appearance: invalidFont, catalogs: ownedCatalogs))
    var incomplete = ownedCatalogs
    incomplete.languages.remove("spanish")
    XCTAssertThrowsError(try WebsiteConfigDefaultDocument(appearance: ownedAppearance, catalogs: incomplete))
    incomplete = ownedCatalogs
    incomplete.layouts.remove("dvorak")
    XCTAssertThrowsError(try WebsiteConfigDefaultDocument(appearance: ownedAppearance, catalogs: incomplete))
  }

  func testNativeDefaultsAgainstPinnedBehaviorAndOrderedApplication() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Output: Decodable {
      var defaults: [String: WebsiteConfigValue]
      var orderedKeys: [String]
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
    let source = try JSONDecoder().decode(Output.self, from: data)
    let catalogs = WebsiteConfigCatalogs(languages: source.catalogs.languages, themes: source.catalogs.themes,
      layouts: source.catalogs.layouts, fonts: source.catalogs.fonts, funboxes: source.catalogs.funboxes)
    // Owned colors, deliberately distinct from the reference visual asset.
    let colors = (0..<10).map { String(format: "#%06x", 0x102030 + $0 * 0x010101) }
    func name(_ key: String) throws -> String {
      guard case .string(let value) = source.defaults[key] else { throw WebsiteConfigSchemaError.invalidDefaults }
      return value
    }
    let appearance = try WebsiteConfigDefaultAppearance(theme: name("theme"), lightTheme: name("themeLight"),
      darkTheme: name("themeDark"), fontFamily: name("fontFamily"), customThemeColors: colors)
    let document = try WebsiteConfigDefaultDocument(appearance: appearance, catalogs: catalogs)
    var expected = source.defaults
    expected["customThemeColors"] = .array(colors.map(WebsiteConfigValue.string))
    XCTAssertEqual(document.values, expected)
    XCTAssertEqual(document.orderedKeys, source.orderedKeys)
    XCTAssertEqual(document.values.count, 94)
    let schema = WebsiteConfigSchema(catalogs: catalogs)
    let prepared = try WebsiteConfigImportPreparation.prepare("{}", defaultDocument: document,
      schema: schema, context: .init())
    let baseline = try WebsiteConfigImportPreparation.prepare("{}", defaults: expected,
      orderedKeys: source.orderedKeys, schema: schema, context: .init())
    XCTAssertEqual(prepared.projection.runtime, baseline.projection.runtime)
    XCTAssertEqual(prepared.projection.events, baseline.projection.events)
    XCTAssertEqual(prepared.projection.rejectedKeys, baseline.projection.rejectedKeys)
  }
}
