import XCTest
@testable import Typebar

@MainActor final class WebsiteAppearanceCommandTests: XCTestCase {
  func testPinnedAppearanceCommandsOverridesNoticesAndPresentationEvents() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference") }
    struct Fixture: Decodable {
      let key: String, value: WebsiteConfigValue, current: [String:WebsiteConfigValue], active: Bool
      let runtime: [String:WebsiteConfigValue], events: [WebsiteConfigApplicationEvent], saves: [String], notices: [Bool]
      let resizes: Int, restarts: Int, ui: [String], visible: Bool
    }
    struct Output: Decodable { let keys: [String]; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--appearance-commands"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 1176); XCTAssertEqual(output.keys.count, 14)
    let targets = AppearanceCommandCatalog.items.compactMap { AppearanceCommandCatalog.target(for: $0.id) } + [.speedUnit(.wph)]
    XCTAssertEqual(targets.count, 49)
    for f in output.fixtures {
      let target = try XCTUnwrap(targets.first { $0.websiteKey == f.key && $0.websiteValue == f.value })
      let plan = try WebsiteAppearanceCommand.plan(current: f.current, target: target, context: .init(), active: f.active)
      XCTAssertFalse(plan.failedOverride)
      var runtime = f.current, events: [WebsiteConfigApplicationEvent] = []
      for step in plan.steps where step.accepted {
        let result = try WebsiteConfigRuntimeProjector.edit(current: runtime, key: step.key, value: step.value,
          defaults: WebsiteConfigNativeProfile.defaultDocument().values, schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs), context: .init(), testActive: f.active)
        XCTAssertEqual(result.events.count, 1, "Each child setter must remain a separate save")
        runtime = result.runtime; events += result.events
      }
      XCTAssertEqual(runtime, f.runtime); XCTAssertEqual(events, f.events); XCTAssertEqual(events.map(\.key), f.saves)
      XCTAssertEqual(f.notices, plan.steps.contains { !$0.accepted } ? [false] : [])
      XCTAssertEqual(f.restarts, 0); XCTAssertEqual(f.visible, target != .speedUnit(.wph))
      XCTAssertEqual(f.resizes, events.filter { $0.key == "tapeMode" }.count)
      XCTAssertEqual(f.ui.filter { $0 == "letters" }.count, events.filter { $0.key == "highlightMode" }.count)
      XCTAssertEqual(f.ui.filter { $0 == "joining:typedEffect" }.count, events.filter { $0.key == "typedEffect" }.count)
    }
  }
  func testAppearanceCapabilityRejectsCompoundEditsUnrelatedFieldsAndCompanionEnable() throws {
    let original = try WebsiteConfigNativeProfile.prepareDraft(#"{"timerColor":"black","liveSpeedStyle":"mini","liveAccStyle":"mini"}"#, pointsPerRem: 16, context: .init())
    let color = try WebsiteConfigNativeProfile.editDraft(original, key: "timerColor", value: .string("main"), pointsPerRem: 16, context: .init())
    XCTAssertTrue(WebsiteAppearanceCommand.admits(color, from: original))
    let compound = try WebsiteConfigNativeProfile.editDraft(color, key: "typingSpeedUnit", value: .string("cpm"), pointsPerRem: 16, context: .init())
    XCTAssertFalse(WebsiteAppearanceCommand.admits(compound, from: original)); XCTAssertTrue(WebsiteAppearanceCommand.admits(compound, from: color))
    let unrelated = try WebsiteConfigNativeProfile.editDraft(original, key: "blindMode", value: .bool(true), pointsPerRem: 16, context: .init())
    XCTAssertFalse(WebsiteAppearanceCommand.admits(unrelated, from: original))
    let enabled = try WebsiteConfigNativeProfile.editDraft(original, key: "monkey", value: .bool(true), pointsPerRem: 16, context: .init())
    XCTAssertFalse(WebsiteAppearanceCommand.admits(enabled, from: original))
  }
  func testWindowDisplayUsesProfileAndOwnedThemeWithoutChangingLegacyPreferences() throws {
    let suite = "appearance-selection-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    let before = settings.snapshot
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"typingSpeedUnit":"cps","liveSpeedStyle":"mini","liveAccStyle":"off","liveBurstStyle":"mini","timerStyle":"text","timerColor":"text","timerOpacity":"0.5","alwaysShowDecimalPlaces":true,"startGraphsAtZero":false}"#, pointsPerRem: 16, context: .init())
    let selection = PracticeAppearanceSelection(draft: draft, settings: settings), theme = AppTheme.dracula.resolvedTheme
    XCTAssertEqual(selection.unit, .cps); XCTAssertEqual(selection.speed, .mini); XCTAssertEqual(selection.accuracy, .off)
    XCTAssertEqual(selection.opacity, .half); XCTAssertEqual(selection.progress, .text)
    XCTAssertTrue(selection.alwaysShowDecimalPlaces); XCTAssertFalse(selection.startGraphsAtZero)
    XCTAssertEqual(selection.foreground(theme: theme), theme.text)
    let secondary = try WebsiteConfigNativeProfile.editDraft(draft, key: "timerColor", value: .string("sub"), pointsPerRem: 16, context: .init())
    XCTAssertEqual(PracticeAppearanceSelection(draft: secondary, settings: settings).foreground(theme: theme), theme.secondaryText)
    XCTAssertEqual(PracticeAppearanceSelection(draft: nil, settings: settings).unit, settings.typingSpeedUnit)
    XCTAssertEqual(settings.snapshot, before)
  }
}
