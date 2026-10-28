import XCTest
@testable import Typebar

@MainActor final class WebsiteRandomThemeConfigurationTests: XCTestCase {
  func testPinnedRandomControllerWithRealSolidStoreAndSavedConfiguration() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned source") }
    struct Save: Decodable { let key: String; let value: [String: WebsiteConfigValue] }
    struct Frame: Decodable {
      let runtime: [String: WebsiteConfigValue], settings: [String: WebsiteConfigValue]
      let saved: [Save], events: [WebsiteConfigApplicationEvent], shown: String?, active: String?
    }
    struct Fixture: Decodable { let auto: Bool, mode: String, frames: [Frame] }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--random-theme-runtime"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 4)
    for fixture in output.fixtures {
      XCTAssertEqual(fixture.frames.count, 7)
      let initial = fixture.frames[0]
      let json = try JSONEncoder().encode(initial.runtime)
      var draft = try WebsiteConfigNativeProfile.prepareDraft(String(decoding: json, as: UTF8.self), pointsPerRem: 16, context: .init())
      var random = try WebsiteRandomThemeConfiguration(entries: ["serika_dark", "serika", "dracula", "nord"].map { .init(name: $0, isDark: true) }, draft: draft)
      var saved: [Save] = [], events: [WebsiteConfigApplicationEvent] = []
      var visible = initial.shown
      func compare(_ index: Int) {
        let expected = fixture.frames[index]
        for (key, value) in expected.runtime { XCTAssertEqual(draft.projection.runtime[key], value, "runtime \(fixture.mode) \(index) \(key)") }
        for (key, value) in expected.settings { XCTAssertEqual(draft.settingsStoreValues[key], value, "store \(fixture.mode) \(index) \(key)") }
        XCTAssertEqual(saved.map(\.key), expected.saved.map(\.key))
        for (actual, wanted) in zip(saved, expected.saved) {
          for (key, value) in wanted.value { XCTAssertEqual(actual.value[key], value, "save \(actual.key) \(key)") }
        }
        XCTAssertEqual(events, expected.events.filter { $0.key != "fullConfigChangeFinished" })
        XCTAssertEqual(random.active, expected.active); XCTAssertEqual(visible, expected.shown)
      }
      compare(0)
      draft = try WebsiteConfigNativeProfile.editDraft(draft, key: "randomTheme", value: .string(fixture.mode), pointsPerRem: 16, context: .init())
      saved.append(.init(key: "randomTheme", value: draft.projection.runtime)); events += draft.projection.events
      draft = try random.modeChanged(draft: draft, customIDs: [], pointsPerRem: 16, chooseIndex: { _ in 0 })
      compare(1)
      for index in 2...5 {
        let result = try random.draw(draft: draft, customIDs: [], systemIsDark: false, pointsPerRem: 16, context: .init(), chooseIndex: { _ in 0 })
        for step in result.steps {
          events += step.projection.events
          if step.projection.events.first?.nosave == false { saved.append(.init(key: try XCTUnwrap(step.projection.events.first?.key), value: step.projection.runtime)) }
          draft = step
        }
        visible = result.disablesSystemFollowing ? draft.themes.theme.rawValue : result.draw?.theme
        XCTAssertEqual(result.disablesSystemFollowing, fixture.auto && index == 2)
        compare(index)
      }
      draft = try WebsiteConfigNativeProfile.editDraft(draft, key: "fontSize", value: .number(1.5), pointsPerRem: 16, context: .init())
      events += draft.projection.events; saved.append(.init(key: "fontSize", value: draft.projection.runtime))
      compare(6)
    }
  }

  func testPreparedDrawKeepsPublishedAndSavedDraftsUntouchedUntilCommit() throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"randomTheme":"fav","favThemes":["nord","serika"],"customTheme":true}"#, pointsPerRem: 16, context: .init())
    var original = try WebsiteRandomThemeConfiguration(entries: [.init(name: "nord", isDark: true), .init(name: "serika", isDark: false)], draft: draft)
    let afterMode = try original.modeChanged(draft: draft, customIDs: [], pointsPerRem: 16, chooseIndex: { $0 })
    var prepared = original
    let result = try prepared.draw(draft: afterMode, customIDs: [], systemIsDark: false, pointsPerRem: 16, context: .init(), chooseIndex: { _ in 0 })
    XCTAssertNil(original.active); XCTAssertEqual(prepared.active, "nord")
    XCTAssertTrue(draft.themes.customEnabled); XCTAssertTrue(afterMode.themes.customEnabled)
    let flag = try XCTUnwrap(result.steps.first)
    XCTAssertFalse(flag.themes.customEnabled)
    XCTAssertEqual(flag.projection.events, [.init(key: "customTheme", previousValue: .bool(true), newValue: .bool(false), nosave: true)])
    XCTAssertEqual(draft.projection.runtime["customTheme"], .bool(true))
    XCTAssertTrue(prepared.clearActive()); XCTAssertFalse(prepared.clearActive())
  }

  func testEqualFavoriteReplacementDetachesOldBagBeforeWrapShuffle() throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"randomTheme":"fav","favThemes":["nord","serika"]}"#, pointsPerRem: 16, context: .init())
    var state = try WebsiteRandomThemeConfiguration(entries: [.init(name: "nord", isDark: true), .init(name: "serika", isDark: false)], draft: draft)
    var runtime = try state.modeChanged(draft: draft, customIDs: [], pointsPerRem: 16, chooseIndex: { $0 })
    runtime = try WebsiteConfigNativeProfile.editDraft(runtime, key: "favThemes", value: runtime.projection.runtime["favThemes"]!, pointsPerRem: 16, context: .init())
    state.favoritesReplaced(draft: runtime)
    for _ in 0..<2 {
      let result = try state.draw(draft: runtime, customIDs: [], systemIsDark: false, pointsPerRem: 16, context: .init(), chooseIndex: { _ in 0 })
      runtime = try XCTUnwrap(result.steps.last)
    }
    XCTAssertEqual(runtime.themes.favorites, [.nord, .serika])
    XCTAssertEqual(runtime.settingsStoreValues["favThemes"], .array([.string("nord"), .string("serika")]))
  }
}
