import Foundation
import XCTest
@testable import Typebar

final class CustomThemeShareTests: XCTestCase {
  private func sampleTheme() -> CustomThemeDefinition {
    .init(
      name: "Harbour", background: .init(red: 0.1, green: 0.2, blue: 0.3),
      panel: .init(red: 0.2, green: 0.3, blue: 0.4),
      accent: .init(red: 0.3, green: 0.4, blue: 0.5),
      text: .init(red: 0.9, green: 0.8, blue: 0.7),
      secondaryText: .init(red: 0.7, green: 0.6, blue: 0.5),
      error: .init(red: 1, green: 0, blue: 0),
      extraInput: .init(red: 0.8, green: 0.1, blue: 0.2),
      caret: .init(red: 0.2, green: 0.9, blue: 0.3),
      fadedText: .init(red: 0.3, green: 0.5, blue: 0.7),
      colorfulError: .init(red: 1, green: 0.2, blue: 0.1),
      colorfulExtraInput: .init(red: 0.6, green: 0.3, blue: 0.1),
      prefersDark: true)
  }

  func testShareLinkRoundTripsEveryNativeColorWithoutBackground() throws {
    let original = sampleTheme()
    let link = try NativeCustomThemeShare.link(for: original)
    XCTAssertTrue(link.hasPrefix("typebar://theme?"))
    let imported = try NativeCustomThemeShare.theme(from: link)
    XCTAssertNotEqual(imported.theme.id, original.id)
    XCTAssertEqual(imported.theme.name, original.name)
    XCTAssertEqual(imported.theme.background, original.background)
    XCTAssertEqual(imported.theme.panel, original.panel)
    XCTAssertEqual(imported.theme.accent, original.accent)
    XCTAssertEqual(imported.theme.text, original.text)
    XCTAssertEqual(imported.theme.secondaryText, original.secondaryText)
    XCTAssertEqual(imported.theme.error, original.error)
    XCTAssertEqual(imported.theme.extraInput, original.extraInput)
    XCTAssertEqual(imported.theme.caret, original.caret)
    XCTAssertEqual(imported.theme.fadedText, original.fadedText)
    XCTAssertEqual(imported.theme.colorfulError, original.colorfulError)
    XCTAssertEqual(imported.theme.colorfulExtraInput, original.colorfulExtraInput)
    XCTAssertEqual(imported.theme.prefersDark, original.prefersDark)
    XCTAssertNil(imported.remoteBackgroundURL)
    XCTAssertFalse(imported.skippedBackground)
  }

  @MainActor func testShareLinkIncludesBackgroundOnlyByExplicitChoiceAndPreservesSettings() throws {
    let original = sampleTheme()
    let link = try NativeCustomThemeShare.link(
      for: original, backgroundURL: "https://images.example.test/sky.png",
      backgroundFit: .contain,
      backgroundFilter: .init(blur: 3, brightness: 1.2, saturation: 0.7, opacity: 0.6))
    let imported = try NativeCustomThemeShare.theme(from: link)
    XCTAssertEqual(imported.remoteBackgroundURL, "https://images.example.test/sky.png")
    XCTAssertEqual(imported.backgroundFit, .contain)
    XCTAssertEqual(imported.backgroundFilter, .init(blur: 3, brightness: 1.2, saturation: 0.7, opacity: 0.6))

    let suite = "TypebarTests.theme-share-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    XCTAssertNotNil(settings.applyImportedWebTheme(imported))
    XCTAssertEqual(settings.activeCustomThemeID, imported.theme.id)
    XCTAssertEqual(settings.customBackgroundURL, imported.remoteBackgroundURL)
    XCTAssertEqual(settings.customBackgroundFit, .contain)
  }

  func testShareLinkRejectsInsecureBackgroundAndMalformedInput() throws {
    let original = sampleTheme()
    XCTAssertThrowsError(try NativeCustomThemeShare.link(
      for: original, backgroundURL: "http://images.example.test/sky.png",
      backgroundFit: .cover, backgroundFilter: .init()))
    XCTAssertThrowsError(try NativeCustomThemeShare.theme(from: "https://example.test/?data=abc"))
    XCTAssertThrowsError(try NativeCustomThemeShare.theme(from: "typebar://theme?data=abc"))
    XCTAssertThrowsError(try NativeCustomThemeShare.theme(from: "typebar://theme?data=abc&data=def"))
  }

  @MainActor func testIncomingInsecureImageSkipsBackgroundWithoutLosingColors() throws {
    let original = sampleTheme()
    let safeLink = try NativeCustomThemeShare.link(
      for: original, backgroundURL: "https://images.example.test/sky.png",
      backgroundFit: .cover, backgroundFilter: .init())
    var parts = try XCTUnwrap(URLComponents(string: safeLink))
    let token = try XCTUnwrap(parts.queryItems?.first?.value)
    var base64 = token.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    let data = try XCTUnwrap(Data(base64Encoded: base64))
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))
    let insecureJSON = json.replacingOccurrences(of: "\"https:", with: "\"http:")
    XCTAssertNotEqual(insecureJSON, json)
    let insecureToken = Data(insecureJSON.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    parts.queryItems = [.init(name: "data", value: insecureToken)]
    let imported = try NativeCustomThemeShare.theme(from: try XCTUnwrap(parts.string))
    XCTAssertEqual(imported.theme.accent, original.accent)
    XCTAssertTrue(imported.skippedBackground)
    XCTAssertNil(imported.remoteBackgroundURL)

    let suite = "TypebarTests.theme-share-insecure-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.customBackgroundURL = "https://images.example.test/original.png"
    XCTAssertNotNil(settings.applyImportedWebTheme(imported))
    XCTAssertEqual(settings.customBackgroundURL, "https://images.example.test/original.png")
  }
}
