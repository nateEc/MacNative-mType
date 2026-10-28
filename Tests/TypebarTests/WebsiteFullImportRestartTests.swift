import XCTest
@testable import Typebar

@MainActor final class WebsiteFullImportRestartTests: XCTestCase {
  func testCommittedDepartureReleasesOnlyItsOwnBoundNoQuitLock() throws {
    let suite = "typebar.full-import-lock.\(UUID())", ownLock = UUID(), otherLock = UUID()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
    let page = PracticePageSessionStore(), router = settings.preferenceConfigurationSaves
    router.register(owner: page.owner, save: { XCTFail("No preference save") })
    page.attach(to: router); defer { page.detach(); router.remove(owner: page.owner) }
    var state = page.state
    state.session = TypingSession(configuration: .words(3).with(modifiers: [.noQuit]), prompt: "ab cd ef")
    state.session.insertBatch("a"); page.replace(state)
    page.bindNoQuitConfigurationLock(settings: settings, owner: ownLock)
    XCTAssertFalse(settings.allowsRestartingConfigurationChange)
    settings.setNoQuitConfigurationLock(true, for: otherLock)
    let capture = try page.captureFullJSONImport(router: router)
    try page.beginFullJSONImportCommit(owner: XCTUnwrap(router.captureLease()), router: router, capture: capture)
    _ = state.session.abandonAndMeasure(); page.installCommitted(state); page.endCommit()
    XCTAssertFalse(settings.allowsRestartingConfigurationChange, "Another window's lock must survive")
    settings.setNoQuitConfigurationLock(false, for: otherLock)
    XCTAssertTrue(settings.allowsRestartingConfigurationChange)
    page.unbindNoQuitConfigurationLock(owner: ownLock)
  }

  func testExplicitImportReadIgnoresOnlyItsLockTransitionAndRearmsNormalAdmission() async throws {
    let suite = "typebar.full-import-read.\(UUID())", lock = UUID()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
    let account = AccountSession(defaults: defaults)
    let environment = WebsiteConfigEnvironmentSource(settings: settings, account: account,
      pointsPerRem: 16, documentComplete: true, development: false)
    defer { environment.stop() }
    settings.setNoQuitConfigurationLock(true, for: lock)
    XCTAssertNil(environment.read())
    let token = environment.beginFullJSONImportRead()
    let first = try XCTUnwrap(environment.read())
    settings.setNoQuitConfigurationLock(false, for: lock)
    XCTAssertEqual(environment.read(), first)
    settings.fontSize += 1
    XCTAssertNil(environment.read(), "Full import does not bypass a real model invalidation")
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while environment.read() == nil && ContinuousClock.now < deadline { await Task.yield() }
    let changed = try XCTUnwrap(environment.read())
    XCTAssertNotEqual(changed.revision, first.revision)
    environment.endFullJSONImportRead(token)
    XCTAssertEqual(environment.read(), changed)
    settings.setNoQuitConfigurationLock(true, for: lock)
    XCTAssertNil(environment.read(), "Normal No Quit admission must be restored")
  }

  func testFirstRestartStateAgainstPinnedLifecycleSettersSubscriberAndCompleteRestart() throws {
    struct Snapshot: Decodable {
      let starts: [[String: WebsiteConfigValue]]
      let incomplete: [[String: Double]]
      let active: Bool, repeated: Bool
    }
    struct Fixture: Decodable {
      let active: Bool, oldNoQuit: Bool, oldSaving: Bool, newNoQuit: Bool, newSaving: Bool
      let wasBusy: Bool, wasRepeated: Bool, json: String, beforeFinish: Snapshot
    }
    struct Output: Decodable { let fixtures: [Fixture] }
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference, Zod and Solid dependencies")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--active-config-import"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 128)
    for fixture in fixtures {
      let draft = try WebsiteConfigNativeProfile.prepareDraft(fixture.json, pointsPerRem: 16, context: .init())
      let restart = try WebsiteFullImportRestart(projection: draft.projection,
        defaults: WebsiteConfigNativeProfile.defaultDocument().values)
      if let source = fixture.beforeFinish.starts.first {
        for key in ["resultSaving", "funbox", "mode", "language", "repeatedPace"] {
          XCTAssertEqual(restart.runtime[key], source[key], key)
        }
        XCTAssertEqual(fixture.beforeFinish.incomplete.count, fixture.active ? 1 : 0)
        XCTAssertFalse(fixture.beforeFinish.active)
        XCTAssertEqual(fixture.beforeFinish.repeated, fixture.active && fixture.wasRepeated)
      } else {
        XCTAssertTrue(fixture.wasBusy); XCTAssertTrue(fixture.beforeFinish.incomplete.isEmpty)
        XCTAssertEqual(fixture.beforeFinish.active, fixture.active)
      }
      XCTAssertTrue(restart.savesIncomplete)
      XCTAssertEqual(draft.behavior.saveCompletedResults, fixture.newSaving)
    }
  }
}
