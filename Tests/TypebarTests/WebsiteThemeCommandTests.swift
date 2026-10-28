import AppKit
import Observation
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteThemeCommandTests: XCTestCase {
  @MainActor fileprivate final class ReadProbe { var action: (() -> Void)? }
  @MainActor fileprivate final class Fixture {
    let suite = "typebar.website-theme.\(UUID())"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-website-theme-\(UUID())")
    let defaults: UserDefaults, settings: AppSettings, account: AccountSession, page: PracticePageSessionStore
    let workflow: WebsiteConfigImportWorkflow
    let probe: ReadProbe
    init(loadQuotes: @escaping @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) }) throws {
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
      let page = PracticePageSessionStore(), account = AccountSession(defaults: defaults)
      self.defaults = defaults; self.settings = settings; self.page = page; self.account = account
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      settings.preferenceConfigurationSaves.register(owner: page.owner, save: { XCTFail("Theme must not save native preferences") })
      page.attach(to: settings.preferenceConfigurationSaves)
      let probe = ReadProbe(); self.probe = probe
      workflow = .init(page: page, settings: settings, account: account, directory: directory,
        readWindow: {
          probe.action?()
          return .published(owner: page.owner, revision: page.state.session.automaticInputAttemptID,
            scope: page.state.sharedReceipt?.scope ?? page.state.practice?.scope ?? .init())
        }, loadQuotes: loadQuotes)
      let workflow = workflow
      settings.preferenceConfigurationSaves.register(owner: page.owner, themes: { page.state.presentation?.publication.draft.themes },
        themeEdit: { edit in
          guard page.ownsConfigurationSelection else { return nil }
          guard let id = page.state.presentation?.publication.applicationID else { return false }
          do { try workflow.runThemeCommand(edit, replacing: id); return true } catch { return false }
        }, save: { XCTFail("Theme must not save native preferences") })
    }
    func publish() async throws {
      try await workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","theme":"dracula"}"#, systemIsDark: false)
    }
    func close() {
      workflow.stop(); page.detach(); settings.preferenceConfigurationSaves.remove(owner: page.owner)
      defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory)
    }
  }
  func testThemeMenuChangesTheActualPublishedThemeWithoutMutatingNativeFallback() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let preferences = f.settings.snapshot, generation = f.page.state.session.generationState
    XCTAssertTrue(ThemeCommandApplication.apply(.builtIn(.serika_dark), to: f.settings))
    XCTAssertEqual(f.page.state.presentation?.appearance.selection, .builtIn(.serika_dark))
    XCTAssertEqual(f.settings.snapshot, preferences)
    XCTAssertEqual(f.page.state.session.generationState, generation)
  }

  func testRandomModePublishesShuffledRuntimeAfterSavingTheUnshuffledSetter() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","favThemes":["nord","serika","dracula"],"customTheme":true,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch(String(state.session.nextExpectedCharacter!)); f.page.replace(state)
    let before = try XCTUnwrap(f.page.state.presentation), generation = f.page.state.session.generationState
    let prefs = f.settings.snapshot, controller = f.page.restartController
    try f.workflow.runThemeCommand(.random(.favorites), replacing: before.publication.applicationID, chooseThemeIndex: { _ in 0 })
    let after = try XCTUnwrap(f.page.state.presentation)
    let old = WebsiteConfigValue.array([.string("nord"), .string("serika"), .string("dracula")])
    let shuffled = WebsiteConfigValue.array([.string("serika"), .string("dracula"), .string("nord")])
    XCTAssertEqual(after.publication.draft.projection.runtime["favThemes"], shuffled)
    XCTAssertEqual(after.publication.draft.settingsStoreValues["favThemes"], old)
    XCTAssertEqual(after.publication.savedDraft.projection.runtime["favThemes"], old)
    let register = WebsiteConfigFileRegister(directory: f.directory)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Missing configuration") }
    XCTAssertEqual(saved["favThemes"], old)
    XCTAssertEqual(after.appearance, before.appearance)
    XCTAssertEqual(f.page.state.session.generationState, generation); XCTAssertEqual(f.settings.snapshot, prefs)
    XCTAssertTrue(f.page.restartController === controller)
    XCTAssertEqual(after.publication.font?.renderingFont, before.publication.font?.renderingFont)
    try f.workflow.runThemeCommand(.followSystem(true), replacing: after.publication.applicationID)
    let next = try XCTUnwrap(f.page.state.presentation)
    XCTAssertEqual(next.publication.draft.settingsStoreValues["favThemes"], old)
    XCTAssertEqual(next.publication.savedDraft.projection.runtime["favThemes"], shuffled)
    guard case .available(let later) = try register.read().state else { return XCTFail("Missing later save") }
    XCTAssertEqual(later["favThemes"], shuffled)
  }

  func testExplicitRandomDrawPublishesVolatileThemeWithoutSavingOrReplacingTheAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","theme":"dracula","favThemes":["nord","serika"],"customTheme":true,"funbox":["no_quit"]}"#, systemIsDark: false)
    try f.workflow.runThemeCommand(.random(.favorites), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { _ in 0 })
    var state = f.page.state; state.session.insertBatch(String(state.session.nextExpectedCharacter!)); f.page.replace(state)
    let before = try XCTUnwrap(f.page.state.presentation), generation = f.page.state.session.generationState
    let preferences = f.settings.snapshot, ledger = f.page.state.priorAttemptLedger, controller = f.page.restartController
    let register = WebsiteConfigFileRegister(directory: f.directory), disk = try register.read()
    let completion = try f.workflow.runRandomThemeCommand(replacing: before.publication.applicationID, chooseThemeIndex: { _ in 0 })
    XCTAssertFalse(completion.disabledSystemFollowing)
    let after = try XCTUnwrap(f.page.state.presentation)
    XCTAssertEqual(after.appearance.selection, .builtIn(.serika))
    XCTAssertEqual(after.randomThemes.active, "serika")
    XCTAssertFalse(after.publication.draft.themes.customEnabled)
    XCTAssertEqual(after.publication.draft.projection.events, [.init(key: "customTheme", previousValue: .bool(true), newValue: .bool(false), nosave: true)])
    XCTAssertEqual(try register.read().revision, disk.revision); XCTAssertEqual(try register.read().state, disk.state)
    XCTAssertEqual(after.publication.savedDraft.projection.runtime, before.publication.savedDraft.projection.runtime)
    XCTAssertEqual(f.page.state.session.generationState, generation); XCTAssertEqual(f.settings.snapshot, preferences)
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger); XCTAssertTrue(f.page.restartController === controller)
    XCTAssertEqual(after.publication.font?.renderingFont, before.publication.font?.renderingFont)
    XCTAssertEqual(after.publication.background?.source, before.publication.background?.source)
  }

  func testResultPageRestartDrawsOnceAfterSuccessfulInitializationIncludingFailureAndRepeat() async throws {
    for failed in [false, true] { for repeated in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let config = #"{"mode":"words","words":2,"fontFamily":"Courier","difficulty":"master","customTheme":true,"theme":"nord","favThemes":["nord","serika","dracula"]}"#
      try await f.workflow.apply(json: failed ? config : config.replacingOccurrences(of: #""difficulty":"master""#, with: #""difficulty":"normal""#), systemIsDark: false)
      try f.workflow.runThemeCommand(.random(.favorites), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { _ in 0 })
      let register = WebsiteConfigFileRegister(directory: f.directory), disk = try register.read().revision
      let preferences = f.settings.snapshot
      func finish() {
        var state = f.page.state
        state.session.insertBatch(failed ? "§" : state.session.prompt + " ")
        XCTAssertEqual(state.session.outcome, failed ? .failed : .completed)
        f.page.replace(state)
      }
      finish(); XCTAssertNil(f.page.state.presentation?.randomThemes.active, "Completion alone must not draw")
      let ledger = f.page.state.priorAttemptLedger, oldAttempt = f.page.state.session.automaticInputAttemptID
      let controller = try XCTUnwrap(f.page.restartController)
      let advanced = try await controller.requestAndWait(requestID: UUID(), repeatingRequested: repeated)
      XCTAssertTrue(advanced); XCTAssertFalse(controller.isPreparing)
      XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, oldAttempt)
      XCTAssertEqual(f.page.state.presentation?.randomThemes.active, "serika")
      XCTAssertEqual(f.page.state.presentation?.appearance.selection, .builtIn(.serika))
      XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
      XCTAssertEqual(try register.read().revision, disk)
      let ordinary = try await controller.requestAndWait(requestID: UUID())
      XCTAssertTrue(ordinary); XCTAssertEqual(f.page.state.presentation?.randomThemes.active, "serika", "A test-page restart must not advance the bag")
      finish()
      let next = try await controller.requestAndWait(requestID: UUID())
      XCTAssertTrue(next); XCTAssertEqual(f.page.state.presentation?.randomThemes.active, "dracula")
      XCTAssertEqual(try register.read().revision, disk); XCTAssertEqual(f.settings.snapshot, preferences)
    } }
  }

  func testFullImportFromResultAppliesItsImplicitRandomRestartAgainstTheActualBus() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned source") }
    struct Save: Decodable { let key: String; let value: [String: WebsiteConfigValue] }
    struct Frame: Decodable {
      let runtime: [String: WebsiteConfigValue], settings: [String: WebsiteConfigValue], saved: [Save]
      let shown: String?, active: String?, drawCount: Int
    }
    struct Sample: Decodable {
      let activePage: String, fromResult: Bool, auto: Bool, oldBag: Bool, mode: String, initialization: String, json: String
      let frames: [Frame]
    }
    struct Output: Decodable { let fixtures: [Sample] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--theme-import-restart"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 96); XCTAssertEqual(output.fixtures.reduce(0) { $0 + $1.frames.count }, 192)
    for sample in output.fixtures {
      XCTAssertEqual(sample.frames.first?.drawCount, 0)
      XCTAssertEqual(sample.frames.first?.saved.last?.key, "full")
      let expectedDraws = sample.activePage == "test" && sample.fromResult && sample.mode != "off" && sample.initialization != "fail" ? 1 : 0
      XCTAssertEqual(sample.frames.last?.drawCount, expectedDraws)
    }
    let samples = output.fixtures.filter { $0.activePage == "test" && $0.initialization == "immediate" }
    XCTAssertEqual(samples.count, 16)
    for sample in samples {
      let f = try Fixture(); defer { f.close() }
      try await f.workflow.apply(json: #"{"mode":"words","words":2,"fontFamily":"Courier","theme":"serika_dark","customTheme":true,"favThemes":["nord","serika","dracula"]}"#, systemIsDark: false)
      if sample.oldBag {
        try f.workflow.runThemeCommand(.random(.favorites), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { _ in 0 })
        try f.workflow.runRandomThemeCommand(replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID))
      }
      if sample.fromResult {
        var state = f.page.state; state.session.insertBatch(state.session.prompt + " "); XCTAssertEqual(state.session.outcome, .completed); f.page.replace(state)
      }
      let preferences = f.settings.snapshot, ledger = f.page.state.priorAttemptLedger
      try await f.workflow.apply(json: sample.json, systemIsDark: false)
      let actual = try XCTUnwrap(f.page.state.presentation), expected = try XCTUnwrap(sample.frames.last)
      for (key, value) in expected.runtime { XCTAssertEqual(actual.publication.draft.projection.runtime[key], value, "runtime \(sample.fromResult) \(sample.auto) \(sample.oldBag) \(key)") }
      for (key, value) in expected.settings { XCTAssertEqual(actual.publication.draft.settingsStoreValues[key], value, "store \(key)") }
      let saved = try XCTUnwrap(expected.saved.last?.value), register = WebsiteConfigFileRegister(directory: f.directory)
      guard case .available(let disk) = try register.read().state else { return XCTFail("Missing imported record") }
      for (key, value) in saved { XCTAssertEqual(disk[key], value, "disk \(key)"); XCTAssertEqual(actual.publication.savedDraft.projection.runtime[key], value) }
      let name: String; switch actual.appearance.selection { case .inlineCustom: name = "custom"; case .builtIn(let theme): name = theme.rawValue }
      XCTAssertEqual(name, expected.shown); XCTAssertEqual(actual.randomThemes.active, expected.active)
      XCTAssertEqual(f.settings.snapshot, preferences); XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
    }
    let failures = output.fixtures.filter { $0.activePage == "test" && $0.initialization == "fail" }
    XCTAssertEqual(failures.count, 16)
    for sample in failures {
      let quotes = RestartQuotes(), f = try Fixture(loadQuotes: quotes.read)
      defer { f.close() }
      try await f.publish(); quotes.fail = true
      // Source initialization is an owned failing adapter. Use the native
      // quote provider as that fault boundary, preserving all theme fields.
      var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(sample.json.utf8)) as? [String: Any])
      json["mode"] = "quote"; json["quoteLength"] = [0, 1, 2, 3]
      do {
        try await f.workflow.apply(json: String(decoding: JSONSerialization.data(withJSONObject: json), as: UTF8.self), systemIsDark: false)
        XCTFail("Initialization must fail")
      } catch { XCTAssertNotNil(f.page.state.savedApplication) }
      let actual = try XCTUnwrap(f.page.state.displayedAppearance), expected = try XCTUnwrap(sample.frames.last)
      let name: String; switch actual.selection { case .inlineCustom: name = "custom"; case .builtIn(let theme): name = theme.rawValue }
      XCTAssertEqual(name, expected.shown)
    }
  }

  func testPendingThemeObservesMediaWhileInitializationIsSuspendedWithoutReplayingOnDelivery() async throws {
    for custom in [false, true] {
      let quotes = RestartQuotes(), f = try Fixture(loadQuotes: quotes.read)
      defer { quotes.release(); f.close() }
      try await f.publish(); quotes.hold = true
      let old = try XCTUnwrap(f.page.state.presentation), generation = f.page.state.session.generationState
      let task = Task { @MainActor in
        try await f.workflow.apply(json: """
          {"mode":"quote","quoteLength":[0,1,2,3],"repeatQuotes":"off","fontFamily":"Courier",
           "theme":"nord","themeLight":"serika","themeDark":"dracula","autoSwitchTheme":true,"customTheme":\(custom)}
          """, systemIsDark: false)
      }
      try await quotes.wait()
      let pending = try XCTUnwrap(f.page.state.savedApplication?.theme)
      XCTAssertEqual(f.page.state.displayedAppearance?.selection, .builtIn(.serika))
      XCTAssertTrue(f.page.state.presentation === old); XCTAssertEqual(f.page.state.session.generationState, generation)
      pending.updateSystemAppearance(isDark: true)
      let expected: WebsiteConfigNativeThemes.Selection = .builtIn(custom ? .serika : .dracula)
      XCTAssertEqual(f.page.state.displayedAppearance?.selection, expected)
      let indicator = WebsiteThemePreview.indicator(themes: pending.themes,
        indicatorOverride: pending.systemIndicator.map(ThemeCommandTarget.builtIn), customThemes: [])
      XCTAssertEqual(indicator.name, custom ? "serika" : "dracula")
      quotes.release(); try await task.value
      XCTAssertNil(f.page.state.savedApplication)
      XCTAssertEqual(f.page.state.displayedAppearance?.selection, expected)
      XCTAssertEqual(f.page.state.presentation?.currentSystemIsDark, true)
    }
  }

  func testFailedImportDisplaysItsThemeBeforeResourcesAndRetainsItOnRecovery() async throws {
    for followsSystem in [false, true] {
      let quotes = RestartQuotes(), f = try Fixture(loadQuotes: quotes.read)
      defer { quotes.release(); f.close() }
      try await f.publish()
      let old = try XCTUnwrap(f.page.state.presentation), generation = f.page.state.session.generationState
      let preferences = f.settings.snapshot, ledger = f.page.state.priorAttemptLedger
      quotes.fail = true
      do {
        try await f.workflow.apply(json: """
          {"mode":"quote","quoteLength":[0,1,2,3],"repeatQuotes":"off","fontFamily":"Courier",
           "theme":"nord","themeLight":"serika","themeDark":"dracula","autoSwitchTheme":\(followsSystem),"customTheme":false}
          """, systemIsDark: false)
        XCTFail("Quote provider must fail after the full import is saved")
      } catch { XCTAssertNotNil(f.page.state.savedApplication) }
      XCTAssertEqual(f.page.state.displayedAppearance?.selection, .builtIn(followsSystem ? .serika : .nord))
      XCTAssertTrue(f.page.state.presentation === old)
      XCTAssertEqual(f.page.state.session.generationState, generation)
      XCTAssertEqual(f.page.state.priorAttemptLedger, ledger); XCTAssertEqual(f.settings.snapshot, preferences)
      let register = WebsiteConfigFileRegister(directory: f.directory), saved = try register.read()
      quotes.fail = false
      try await f.workflow.apply(json: nil, systemIsDark: false)
      XCTAssertNil(f.page.state.savedApplication)
      XCTAssertEqual(f.page.state.displayedAppearance?.selection, .builtIn(followsSystem ? .serika : .nord))
      XCTAssertEqual(try register.read().revision, saved.revision)
    }
  }

  func testColdFailedImportUsesTheActualSchemeAndReplacementRetiresTheOldPendingColors() async throws {
    let quotes = RestartQuotes(), f = try Fixture(loadQuotes: quotes.read)
    defer { f.close() }; quotes.fail = true
    do {
      try await f.workflow.apply(json: #"{"mode":"quote","quoteLength":[0,1,2,3],"fontFamily":"Courier","autoSwitchTheme":true,"themeLight":"serika","themeDark":"dracula"}"#, systemIsDark: true)
      XCTFail("Initialization must fail")
    } catch {}
    XCTAssertNil(f.page.state.presentation)
    XCTAssertEqual(f.page.state.displayedAppearance?.selection, .builtIn(.dracula))
    let retired = try XCTUnwrap(f.page.state.savedApplication?.theme)
    do {
      try await f.workflow.apply(json: #"{"mode":"quote","quoteLength":[0,1,2,3],"fontFamily":"Courier","autoSwitchTheme":false,"theme":"nord"}"#, systemIsDark: false)
      XCTFail("Replacement initialization must fail")
    } catch {}
    let current = try XCTUnwrap(f.page.state.savedApplication?.theme)
    XCTAssertFalse(current === retired)
    retired.updateSystemAppearance(isDark: false)
    XCTAssertEqual(retired.appearance.selection, .builtIn(.serika))
    XCTAssertEqual(f.page.state.displayedAppearance?.selection, .builtIn(.nord))
    XCTAssertNil(f.page.state.presentation)
  }

  private struct PendingBackgroundRoot: View {
    let page: PracticePageSessionStore
    var body: some View {
      if let presentation = page.state.presentation,
        let background = try? presentation.background(fallbackStyle: .solid, reduceMotion: true,
          pendingTheme: page.state.savedApplication?.theme) {
        // ImageRenderer cannot draw the AppKit media surface. Render the
        // production SwiftUI base layer; native media has separate pixel tests.
        background.backdrop.frame(width: 160, height: 100)
      }
    }
  }
  func testBackgroundColorsRenderBeforeTheNewPracticeIsReady() async throws {
    let quotes = RestartQuotes(), f = try Fixture(loadQuotes: quotes.read)
    defer { quotes.release(); f.close() }; try await f.publish()
    let old = try XCTUnwrap(f.page.state.presentation)
    func pixel<V: View>(_ view: V) throws -> NSColor {
      let renderer = ImageRenderer(content: view)
      let data = try XCTUnwrap(renderer.nsImage?.tiffRepresentation)
      let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
      return try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
    }
    func waitForColor(_ color: Color) async throws {
      // Both samples pass through the same renderer and TIFF color profile.
      let expected = try pixel(color.frame(width: 160, height: 100))
      let end = Date().addingTimeInterval(2)
      var actual: NSColor?
      repeat {
        try await Task.sleep(for: .milliseconds(20))
        actual = try pixel(PendingBackgroundRoot(page: f.page))
        if let actual, abs(actual.redComponent - expected.redComponent) < 0.01,
          abs(actual.greenComponent - expected.greenComponent) < 0.01,
          abs(actual.blueComponent - expected.blueComponent) < 0.01 { return }
      } while Date() < end
      XCTFail("Expected background \(expected), got \(String(describing: actual))")
    }
    try await waitForColor(AppTheme.dracula.resolvedTheme.background)
    quotes.hold = true
    let task = Task { @MainActor in
      try await f.workflow.apply(json: #"{"mode":"quote","quoteLength":[0,1,2,3],"repeatQuotes":"off","fontFamily":"Courier","theme":"nord"}"#, systemIsDark: false)
    }
    try await quotes.wait()
    try await waitForColor(AppTheme.nord.resolvedTheme.background)
    XCTAssertTrue(f.page.state.presentation === old)
    task.cancel(); quotes.release()
    do { _ = try await task.value; XCTFail("Cancelled preparation must not deliver") } catch {}
    XCTAssertNotNil(f.page.state.savedApplication)
    try await waitForColor(AppTheme.nord.resolvedTheme.background)
    XCTAssertTrue(f.page.state.presentation === old)
  }

  func testResumingAnImportedProfileAfterFailedInitializationDoesNotReuseTheOldResultSource() async throws {
    let quotes = RestartQuotes(), f = try Fixture(loadQuotes: quotes.read)
    defer { quotes.release(); f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":2,"fontFamily":"Courier","favThemes":["nord","serika"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch(state.session.prompt + " "); XCTAssertEqual(state.session.outcome, .completed); f.page.replace(state)
    let ledger = f.page.state.priorAttemptLedger
    quotes.fail = true
    do {
      try await f.workflow.apply(json: #"{"mode":"quote","quoteLength":[0,1,2,3],"repeatQuotes":"off","fontFamily":"Courier","randomTheme":"fav","favThemes":["nord"],"customTheme":true,"autoSwitchTheme":true}"#, systemIsDark: false)
      XCTFail("Provider failure must retain pending application")
    } catch { XCTAssertNotNil(f.page.state.savedApplication) }
    XCTAssertNil(f.page.state.presentation?.randomThemes.active)
    let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
    guard case .available(let saved) = try register.read().state else { return XCTFail("Import must already be saved") }
    XCTAssertEqual(saved["customTheme"], .bool(true)); XCTAssertEqual(saved["autoSwitchTheme"], .bool(true))
    quotes.fail = false
    try await f.workflow.apply(json: nil, systemIsDark: false)
    XCTAssertNil(f.page.state.savedApplication); XCTAssertNil(f.page.state.presentation?.randomThemes.active)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.themes.customEnabled, true)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.themes.followsSystem, true)
    let resumed = try register.read()
    XCTAssertEqual(resumed.state, .available(saved))
    XCTAssertEqual(resumed.revision, revision); XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
  }

  func testPinnedRestartAndUIOrderOnlyDispatchesRandomAfterResultInitialization() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned source") }
    struct Frame: Decodable { let source: String?, randomCount: Int, resultVisible: Bool, initializations: Int, trace: [String] }
    struct Sample: Decodable { let initialResult: Bool, mode: String, repeated: Bool, failFirst: Bool, guarded: Bool, frames: [Frame] }
    struct Output: Decodable { let fixtures: [Sample] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-random-theme-restart.mjs").path, reference]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    let samples = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(samples.count, 57); XCTAssertEqual(samples.reduce(0) { $0 + $1.frames.count }, 114)
    for sample in samples {
      var draws = 0
      let mode = try XCTUnwrap(RandomThemeMode(rawValue: sample.mode))
      for (index, frame) in sample.frames.enumerated() {
        let source = WebsiteRestartSource.capture(outcome: sample.initialResult ? .completed : .active, alreadyDeparted: index != 0)
        if let actual = frame.source {
          XCTAssertEqual(actual, source.rawValue)
          if source.drawsRandomTheme(mode: mode) { draws += 1 }
        }
        XCTAssertEqual(draws, frame.randomCount)
        XCTAssertFalse(frame.resultVisible && !sample.guarded)
        if sample.guarded { XCTAssertEqual(frame.initializations, 0); XCTAssertNil(frame.source) }
        if sample.failFirst && index == 0 { XCTAssertNil(frame.source) }
      }
    }
    for outcome in [TestOutcome.completed, .failed, .invalidAFK, .bailedOut] {
      XCTAssertEqual(WebsiteRestartSource.capture(outcome: outcome, alreadyDeparted: false), .resultPage)
      XCTAssertEqual(WebsiteRestartSource.capture(outcome: outcome, alreadyDeparted: true), .testPage)
    }
    for outcome in [TestOutcome.active, .abandoned] { XCTAssertEqual(WebsiteRestartSource.capture(outcome: outcome, alreadyDeparted: false), .testPage) }
  }

  @MainActor private final class RestartQuotes {
    enum Failure: Error { case unavailable }
    var fail = false, hold = false
    var waiting: CheckedContinuation<[OfflineQuote], Never>?
    func read(_ language: TypingLanguage) async throws -> [OfflineQuote] {
      if fail { throw Failure.unavailable }
      if hold { return await withCheckedContinuation { waiting = $0 } }
      return OfflineContent.quotes(for: language)
    }
    func release() { let pending = waiting; waiting = nil; hold = false; pending?.resume(returning: OfflineContent.quotes(for: .english)) }
    func wait() async throws {
      let end = Date().addingTimeInterval(3)
      while waiting == nil && Date() < end { try await Task.sleep(for: .milliseconds(5)) }
      XCTAssertNotNil(waiting)
    }
  }

  func testFailedCancelledAndRetiredResultInitializationsDoNotDrawOnTheRetry() async throws {
    for kind in ["failure", "cancel", "owner"] {
      let quotes = RestartQuotes(), f = try Fixture(loadQuotes: quotes.read)
      defer { quotes.release(); f.close() }
      try await f.workflow.apply(json: #"{"mode":"quote","quoteLength":[-2],"repeatQuotes":"off","fontFamily":"Courier","difficulty":"master","customTheme":true,"favThemes":["nord","serika"]}"#, systemIsDark: false)
      try f.workflow.runThemeCommand(.random(.favorites), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { _ in 0 })
      var state = f.page.state; state.session.insertBatch("§"); XCTAssertEqual(state.session.outcome, .failed); f.page.replace(state)
      let controller = try XCTUnwrap(f.page.restartController), ledger = f.page.state.priorAttemptLedger
      let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
      if kind == "failure" {
        quotes.fail = true
        let delivered = try await controller.requestAndWait(requestID: UUID()); XCTAssertFalse(delivered)
        quotes.fail = false
      } else {
        quotes.hold = true
        let requestID = UUID(), task = Task { try await controller.requestAndWait(requestID: requestID) }
        try await quotes.wait()
        let other = UUID()
        if kind == "cancel" { task.cancel(); controller.cancel(requestID: requestID) }
        else { f.settings.preferenceConfigurationSaves.register(owner: other, save: {}); f.settings.preferenceConfigurationSaves.activate(owner: other) }
        quotes.release()
        do { let delivered = try await task.value; XCTAssertFalse(delivered) } catch { XCTAssertTrue(error is CancellationError) }
        if kind == "owner" {
          f.settings.preferenceConfigurationSaves.activate(owner: f.page.owner)
          f.settings.preferenceConfigurationSaves.remove(owner: other)
        }
      }
      XCTAssertNil(f.page.state.presentation?.randomThemes.active)
      XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
      let retry = try await controller.requestAndWait(requestID: UUID()); XCTAssertTrue(retry)
      XCTAssertNil(f.page.state.presentation?.randomThemes.active, "The result page was already left before failed init")
      XCTAssertEqual(try register.read().revision, revision)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.themes.customEnabled, true)
    }
  }

  func testResultRestartInsideSetterAndShareWorkflowsDrainsAfterTheirReservation() async throws {
    for shared in [false, true] {
      let f = try Fixture(); defer { f.close() }
      try await f.workflow.apply(json: #"{"mode":"words","words":2,"fontFamily":"Courier","theme":"dracula","autoSwitchTheme":true,"customTheme":true,"favThemes":["nord","serika"]}"#, systemIsDark: false)
      try f.workflow.runThemeCommand(.random(.favorites), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { _ in 0 })
      var state = f.page.state; state.session.insertBatch(state.session.prompt + " "); XCTAssertEqual(state.session.outcome, .completed); f.page.replace(state)
      let id = try XCTUnwrap(f.page.state.presentation?.publication.applicationID), preferences = f.settings.snapshot
      if shared {
        _ = try await f.workflow.applySharedSettings(json: #"["words","6",null,false,false,null,"normal",null]"#, replacing: id, systemIsDark: false)
      } else { try await f.workflow.editAndBegin(.words(6), replacing: id, systemIsDark: false) }
      let after = try XCTUnwrap(f.page.state.presentation)
      XCTAssertEqual(after.randomThemes.active, "serika")
      XCTAssertFalse(after.publication.draft.themes.followsSystem)
      XCTAssertFalse(after.publication.draft.themes.customEnabled)
      XCTAssertEqual(after.appearance.selection, .builtIn(.dracula))
      XCTAssertEqual(f.page.state.session.configuration.wordLimit, 6)
      XCTAssertEqual(f.settings.snapshot, preferences)
      let register = WebsiteConfigFileRegister(directory: f.directory)
      guard case .available(let saved) = try register.read().state else { return XCTFail("Missing saved config") }
      XCTAssertEqual(saved["customTheme"], .bool(false)); XCTAssertEqual(saved["autoSwitchTheme"], .bool(false))
      XCTAssertTrue(f.account.localNotices.history.contains { $0.message == "已关闭系统外观跟随。" })
    }
  }

  func testCancellationFromTheSuccessfulDeliveryObserverCannotUndoItsRandomRestartEvent() async throws {
    for cancelTask in [false, true] {
    let quotes = RestartQuotes(), f = try Fixture(loadQuotes: quotes.read)
    defer { quotes.release(); f.close() }
    try await f.workflow.apply(json: #"{"mode":"quote","quoteLength":[-2],"repeatQuotes":"off","fontFamily":"Courier","difficulty":"master","customTheme":true,"favThemes":["nord","serika"]}"#, systemIsDark: false)
    try f.workflow.runThemeCommand(.random(.favorites), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { _ in 0 })
    var state = f.page.state; state.session.insertBatch("§"); f.page.replace(state)
    let controller = try XCTUnwrap(f.page.restartController), requestID = UUID()
    quotes.hold = true
    let task = Task { try await controller.requestAndWait(requestID: requestID) }
    try await quotes.wait()
    var cancelled = false
    withObservationTracking { _ = f.page.state.session.automaticInputAttemptID } onChange: {
      MainActor.assumeIsolated {
        cancelled = true; controller.cancel(requestID: requestID)
        if cancelTask { task.cancel() }
      }
    }
    quotes.release()
    let delivered = try await task.value
    let end = Date().addingTimeInterval(2)
    while f.page.state.presentation?.randomThemes.active == nil && Date() < end { try await Task.sleep(for: .milliseconds(5)) }
    XCTAssertTrue(delivered); XCTAssertTrue(cancelled)
    XCTAssertFalse(controller.isPreparing); XCTAssertNil(controller.message)
    XCTAssertEqual(f.page.state.presentation?.randomThemes.active, "serika")
    XCTAssertFalse(f.page.state.session.isFinished)
    }
  }

  func testRandomFailureAfterResultRestartKeepsTheNewAttemptAndReportsTheFault() async throws {
    let f = try Fixture(); defer { f.close() }
    f.account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
    let colors = try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 16, context: .init()).themes
    let custom = try colors.makeCustomTheme(id: UUID(), name: "Owned")
    f.settings.customThemes = [custom]
    try await f.workflow.apply(json: #"{"mode":"words","words":2,"fontFamily":"Courier","difficulty":"master","customTheme":true}"#, systemIsDark: false)
    try f.workflow.runThemeCommand(.random(.custom), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID))
    var state = f.page.state; state.session.insertBatch("§"); f.page.replace(state)
    let before = state.session.automaticInputAttemptID, ledger = state.priorAttemptLedger
    let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
    let controller = try XCTUnwrap(f.page.restartController)
    let delivered = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(delivered); XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, before)
    XCTAssertFalse(f.page.state.session.isFinished); XCTAssertNil(controller.message)
    XCTAssertEqual(f.page.state.presentation?.randomThemes.active, custom.id.uuidString)
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertTrue(f.account.localNotices.history.contains { $0.message == WebsiteRandomThemeSequence.Failure.missingBuiltIn(custom.id.uuidString).errorDescription })
  }

  func testPublishedRandomDrawsAgainstPinnedControllerRealStoreAndDiskCheckpoints() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned source") }
    struct Save: Decodable { let value: [String: WebsiteConfigValue] }
    struct Indicator: Decodable { let text: String; let isFavorite: Bool }
    struct Frame: Decodable {
      let runtime: [String: WebsiteConfigValue], settings: [String: WebsiteConfigValue], saved: [Save]
      let shown: String?, active: String?, indicator: Indicator
    }
    struct Sample: Decodable { let auto: Bool, mode: String, frames: [Frame] }
    struct Output: Decodable { let fixtures: [Sample] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--random-theme-runtime"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    let samples = try JSONDecoder().decode(Output.self, from: data).fixtures.filter { $0.mode == "fav" }
    XCTAssertEqual(samples.count, 2)
    for sample in samples {
      let f = try Fixture(); defer { f.close() }
      var initial = sample.frames[0].runtime; initial["mode"] = .string("words"); initial["words"] = .number(5); initial["fontFamily"] = .string("Courier")
      let config = String(decoding: try JSONEncoder().encode(initial), as: UTF8.self)
      let draft = try WebsiteConfigNativeProfile.prepareDraft(config, pointsPerRem: 16, context: .init())
      f.settings.customThemes = [try draft.themes.makeCustomTheme(id: UUID(), name: "Owned_One")]
      try await f.workflow.apply(json: config, systemIsDark: false)
      let preferences = f.settings.snapshot, generation = f.page.state.session.generationState
      let preview = WebsiteThemePreview(), register = WebsiteConfigFileRegister(directory: f.directory)
      for index in 0..<7 {
        if index == 1 {
          try f.workflow.runThemeCommand(.random(.favorites), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { _ in 0 })
        } else if (2...5).contains(index) {
          let result = try f.workflow.runRandomThemeCommand(replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { _ in 0 })
          XCTAssertEqual(result.disabledSystemFollowing, sample.auto && index == 2)
        } else if index == 6 {
          try f.workflow.runFontCommand(.size(24), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID))
        }
        let actual = try XCTUnwrap(f.page.state.presentation), expected = sample.frames[index]
        for (key, value) in expected.runtime { XCTAssertEqual(actual.publication.draft.projection.runtime[key], value, "runtime \(sample.auto) \(index) \(key)") }
        for (key, value) in expected.settings { XCTAssertEqual(actual.publication.draft.settingsStoreValues[key], value, "store \(sample.auto) \(index) \(key)") }
        let saved = expected.saved.last?.value ?? sample.frames[0].runtime
        guard case .available(let disk) = try register.read().state else { return XCTFail("Missing disk") }
        for (key, value) in saved {
          XCTAssertEqual(disk[key], value, "disk \(sample.auto) \(index) \(key)")
          XCTAssertEqual(actual.publication.savedDraft.projection.runtime[key], value)
        }
        let name: String; switch actual.appearance.selection { case .inlineCustom: name = "custom"; case .builtIn(let theme): name = theme.rawValue }
        XCTAssertEqual(name, expected.shown); XCTAssertEqual(actual.randomThemes.active, expected.active)
        preview.synchronize(actual)
        let indicator = try XCTUnwrap(preview.indicator(for: actual, customThemes: f.settings.customThemes))
        XCTAssertEqual(indicator.name, expected.indicator.text); XCTAssertEqual(indicator.isFavorite, expected.indicator.isFavorite)
        XCTAssertEqual(f.page.state.session.generationState, generation); XCTAssertEqual(f.settings.snapshot, preferences)
      }
      preview.stop()
    }
  }

  func testRandomAutoOffFailureKeepsTheVolatilePrefixWithoutPromotingItIntoTheForeignSave() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","theme":"dracula","autoSwitchTheme":true,"customTheme":true,"favThemes":["nord","serika"]}"#, systemIsDark: false)
    try f.workflow.runThemeCommand(.random(.favorites), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { _ in 0 })
    let register = WebsiteConfigFileRegister(directory: f.directory), preferences = f.settings.snapshot
    var injected = false
    f.probe.action = {
      guard !injected, f.page.state.presentation?.randomThemes.active != nil else { return }
      injected = true
      do {
        let disk = try register.read()
        guard case .available(var foreign) = disk.state else { return XCTFail("Missing disk") }
        foreign["words"] = .number(9)
        guard case .committed = try register.commit(runtime: foreign, lazyMemory: disk.lazyMemory, replacing: XCTUnwrap(disk.revision)) else { return XCTFail("Foreign save failed") }
      } catch { XCTFail("Foreign save: \(error)") }
    }
    XCTAssertThrowsError(try f.workflow.runRandomThemeCommand(replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID))) {
      guard case .interrupted = $0 as? WebsiteRandomThemeCommandError else { return XCTFail("Missing prefix diagnosis") }
    }
    f.probe.action = nil; XCTAssertTrue(injected)
    let after = try XCTUnwrap(f.page.state.presentation)
    XCTAssertFalse(after.publication.draft.themes.customEnabled); XCTAssertTrue(after.publication.draft.themes.followsSystem)
    XCTAssertEqual(after.randomThemes.active, "serika"); XCTAssertEqual(after.appearance.selection, .builtIn(.serika))
    guard case .available(let disk) = try register.read().state else { return XCTFail("Missing foreign disk") }
    XCTAssertEqual(disk["words"], .number(9)); XCTAssertEqual(disk["customTheme"], .bool(true))
    XCTAssertEqual(disk["autoSwitchTheme"], .bool(true)); XCTAssertEqual(f.settings.snapshot, preferences)
  }

  func testRandomPreviewFavoritesAndRestartingSetterUseTheActiveCandidate() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","theme":"dracula","favThemes":["nord","serika"]}"#, systemIsDark: false)
    try f.workflow.runThemeCommand(.random(.favorites), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { _ in 0 })
    try f.workflow.runRandomThemeCommand(replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID))
    let original = try XCTUnwrap(f.page.state.presentation), preferences = f.settings.snapshot
    let preview = WebsiteThemePreview(schedule: { _, action in action(); return {} }); defer { preview.stop() }
    XCTAssertTrue(preview.select(.builtIn(.nord), presentation: original, customThemes: []))
    XCTAssertEqual(preview.prepared(for: original, owner: f.page.owner)?.theme, AppTheme.nord.resolvedTheme)
    preview.clear()
    XCTAssertEqual(preview.prepared(for: original, owner: f.page.owner)?.theme, AppTheme.serika.resolvedTheme)
    XCTAssertEqual(preview.indicator(for: original, customThemes: [])?.name, "serika")
    let register = WebsiteConfigFileRegister(directory: f.directory), revision = try register.read().revision
    let ordinary = try await XCTUnwrap(f.page.restartController).requestAndWait(requestID: UUID())
    XCTAssertTrue(ordinary); XCTAssertEqual(f.page.state.presentation?.publication.applicationID, original.publication.applicationID)
    XCTAssertEqual(f.page.state.presentation?.appearance.selection, .builtIn(.serika)); XCTAssertEqual(try register.read().revision, revision)
    XCTAssertTrue(CurrentThemeFavoriteCommandApplication.apply(.remove, to: f.settings, colorScheme: .light, presentation: original))
    XCTAssertEqual(f.page.state.presentation?.publication.draft.themes.favorites, [.nord])
    try await f.workflow.editAndBegin(.words(6), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), systemIsDark: false)
    let restarted = try XCTUnwrap(f.page.state.presentation)
    XCTAssertEqual(restarted.randomThemes.active, "serika"); XCTAssertEqual(restarted.appearance.selection, .builtIn(.serika))
    try f.workflow.runThemeCommand(.random(.off), replacing: restarted.publication.applicationID)
    let off = try XCTUnwrap(f.page.state.presentation)
    XCTAssertNil(off.randomThemes.active); XCTAssertEqual(off.appearance.selection, .builtIn(.dracula))
    try f.workflow.runThemeCommand(.random(.favorites), replacing: off.publication.applicationID)
    try f.workflow.runRandomThemeCommand(replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID))
    XCTAssertEqual(f.page.state.presentation?.randomThemes.active, "nord")
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","theme":"serika","randomTheme":"fav","favThemes":["dracula"]}"#, systemIsDark: false)
    let imported = try XCTUnwrap(f.page.state.presentation)
    XCTAssertNil(imported.randomThemes.active); XCTAssertEqual(imported.appearance.selection, .builtIn(.serika))
    try f.workflow.runRandomThemeCommand(replacing: imported.publication.applicationID)
    XCTAssertEqual(f.page.state.presentation?.randomThemes.active, "nord", "A full import retains the old bag")
    XCTAssertEqual(f.page.state.presentation?.publication.draft.themes.favorites, [.dracula])
    XCTAssertEqual(f.settings.snapshot, preferences)
  }

  func testEmptyAndDisabledRandomCommandsDoNotPublishAndOpaqueCustomFaultsKeepTheirCursorPrefix() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","randomTheme":"fav","favThemes":[],"customTheme":true}"#, systemIsDark: false)
    let empty = try XCTUnwrap(f.page.state.presentation), register = WebsiteConfigFileRegister(directory: f.directory)
    let emptyDisk = try register.read().revision
    try f.workflow.runRandomThemeCommand(replacing: empty.publication.applicationID)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, empty.publication.applicationID)
    XCTAssertEqual(try register.read().revision, emptyDisk)
    try f.workflow.runThemeCommand(.random(.off), replacing: empty.publication.applicationID)
    let offID = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    XCTAssertThrowsError(try f.workflow.runRandomThemeCommand(replacing: offID))
    XCTAssertThrowsError(try f.workflow.runRandomThemeCommand(replacing: empty.publication.applicationID))
    f.account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
    let colors = try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 16, context: .init()).themes
    let a = try colors.makeCustomTheme(id: UUID(), name: "Owned A"), b = try colors.makeCustomTheme(id: UUID(), name: "Owned B")
    f.settings.customThemes = [a, b]
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","customTheme":true}"#, systemIsDark: false)
    try f.workflow.runThemeCommand(.random(.custom), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { $0 })
    let saved = try register.read(), appearance = f.page.state.presentation?.appearance
    for id in [a.id, b.id] {
      XCTAssertThrowsError(try f.workflow.runRandomThemeCommand(replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { $0 })) {
        XCTAssertEqual($0 as? WebsiteRandomThemeSequence.Failure, .missingBuiltIn(id.uuidString))
      }
      XCTAssertEqual(f.page.state.presentation?.randomThemes.active, id.uuidString)
      XCTAssertEqual(f.page.state.presentation?.appearance, appearance)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.themes.customEnabled, true)
      XCTAssertTrue(try XCTUnwrap(f.page.state.presentation).publication.draft.projection.events.isEmpty,
        "A failed draw must not replay the preceding mode/font/import setters")
      XCTAssertEqual(try register.read().revision, saved.revision); XCTAssertEqual(try register.read().state, saved.state)
    }
  }

  func testRandomPreparationCannotPublishAfterDiskOwnershipOrInputChanges() async throws {
    for kind in ["disk", "owner", "input"] {
      let f = try Fixture(); defer { f.close() }
      try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","randomTheme":"fav","customTheme":true,"favThemes":["nord","serika"]}"#, systemIsDark: false)
      let before = try XCTUnwrap(f.page.state.presentation), register = WebsiteConfigFileRegister(directory: f.directory)
      let disk = try register.read(), preferences = f.settings.snapshot, other = UUID()
      var injected = false
      XCTAssertThrowsError(try f.workflow.runRandomThemeCommand(replacing: before.publication.applicationID, chooseThemeIndex: { _ in
        if !injected {
          injected = true
          if kind == "owner" {
            f.settings.preferenceConfigurationSaves.register(owner: other, save: { XCTFail("No legacy save") })
            f.settings.preferenceConfigurationSaves.activate(owner: other)
          } else if kind == "input" {
            var state = f.page.state; state.session.insertBatch(String(state.session.nextExpectedCharacter!)); f.page.replace(state)
          } else {
            do {
              guard case .available(var foreign) = disk.state else { XCTFail("Missing disk"); return 0 }
              foreign["words"] = .number(9)
              guard case .committed = try register.commit(runtime: foreign, lazyMemory: disk.lazyMemory, replacing: XCTUnwrap(disk.revision)) else { XCTFail("Foreign write failed"); return 0 }
            } catch { XCTFail("Foreign write: \(error)") }
          }
        }
        return 0
      }))
      XCTAssertTrue(injected)
      XCTAssertEqual(f.page.state.presentation?.publication.applicationID, before.publication.applicationID)
      XCTAssertNil(f.page.state.presentation?.randomThemes.active)
      XCTAssertTrue(try XCTUnwrap(f.page.state.presentation).publication.draft.themes.customEnabled)
      XCTAssertEqual(f.settings.snapshot, preferences)
      if kind != "disk" { XCTAssertEqual(try register.read().revision, disk.revision) }
      if kind == "input" { XCTAssertTrue(f.page.state.session.hasStarted) }
      f.settings.preferenceConfigurationSaves.remove(owner: other)
    }
  }

  func testRandomBagSurvivesFontRestartAndFullImportWithoutOverwritingNewFavorites() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","favThemes":["nord","serika","dracula"]}"#, systemIsDark: false)
    try f.workflow.runThemeCommand(.random(.favorites), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { _ in 0 })
    func nextName() throws -> String? {
      let presentation = try XCTUnwrap(f.page.state.presentation)
      var copy = presentation.randomThemes
      let result = try copy.draw(draft: presentation.publication.draft, customIDs: [], systemIsDark: false,
        pointsPerRem: 16, context: .init(), chooseIndex: { $0 })
      return result.draw?.theme
    }
    XCTAssertEqual(try nextName(), "serika")
    try f.workflow.runFontCommand(.size(24), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID))
    XCTAssertEqual(try nextName(), "serika")
    let restarted = try await XCTUnwrap(f.page.restartController).requestAndWait(requestID: UUID())
    XCTAssertTrue(restarted); XCTAssertEqual(try nextName(), "serika")
    try f.workflow.runThemeCommand(.favorites([.serika, .dracula, .nord]), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID))
    let equal = try XCTUnwrap(f.page.state.presentation)
    var equalBag = equal.randomThemes, equalDraft = equal.publication.draft
    for _ in 0..<3 {
      let draw = try equalBag.draw(draft: equalDraft, customIDs: [], systemIsDark: false, pointsPerRem: 16, context: .init(), chooseIndex: { _ in 0 })
      equalDraft = try XCTUnwrap(draw.steps.last)
    }
    XCTAssertEqual(equalDraft.themes.favorites, [.serika, .dracula, .nord], "Equal favorite setters replace the array identity")
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","randomTheme":"fav","favThemes":["dracula"]}"#, systemIsDark: false)
    XCTAssertEqual(try nextName(), "serika", "Full import replaces the favorite array, not the old candidate bag")
    let presentation = try XCTUnwrap(f.page.state.presentation)
    var copy = presentation.randomThemes, runtime = presentation.publication.draft
    for _ in 0..<3 {
      let result = try copy.draw(draft: runtime, customIDs: [], systemIsDark: false, pointsPerRem: 16, context: .init(), chooseIndex: { _ in 0 })
      runtime = try XCTUnwrap(result.steps.last)
    }
    XCTAssertEqual(runtime.themes.favorites, [.dracula], "Old bag wrap must not shuffle the replacement favorites")
  }

  func testRandomPreparationLosingDiskCASDoesNotInstallItsBagOrRuntimeShuffle() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","favThemes":["nord","serika","dracula"]}"#, systemIsDark: false)
    let original = try XCTUnwrap(f.page.state.presentation), register = WebsiteConfigFileRegister(directory: f.directory)
    var injected = false
    XCTAssertThrowsError(try f.workflow.runThemeCommand(.random(.favorites), replacing: original.publication.applicationID, chooseThemeIndex: { _ in
      if !injected {
        injected = true
        do {
          let disk = try register.read()
          guard case .available(var foreign) = disk.state else { XCTFail("Missing disk"); return 0 }
          foreign["words"] = .number(9)
          guard case .committed = try register.commit(runtime: foreign, lazyMemory: disk.lazyMemory, replacing: XCTUnwrap(disk.revision)) else { XCTFail("Foreign save failed"); return 0 }
        } catch { XCTFail("Foreign save failed: \(error)") }
      }
      return 0
    }))
    XCTAssertTrue(injected)
    let after = try XCTUnwrap(f.page.state.presentation)
    XCTAssertEqual(after.publication.applicationID, original.publication.applicationID)
    XCTAssertEqual(after.publication.draft.projection.runtime, original.publication.draft.projection.runtime)
    var state = after.randomThemes
    let draw = try state.draw(draft: after.publication.draft, customIDs: [], systemIsDark: false, pointsPerRem: 16, context: .init())
    XCTAssertNil(draw.draw, "A discarded preparation must not install its candidate bag")
  }

  func testRestartingWordSetterPreservesTheRuntimeFavoriteArrayAlias() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","favThemes":["nord","serika","dracula"]}"#, systemIsDark: false)
    try f.workflow.runThemeCommand(.random(.favorites), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), chooseThemeIndex: { _ in 0 })
    try await f.workflow.editAndBegin(.words(6), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID), systemIsDark: false)
    let presentation = try XCTUnwrap(f.page.state.presentation)
    XCTAssertEqual(presentation.publication.draft.testParameters.wordLimit, 6)
    var random = presentation.randomThemes, runtime = presentation.publication.draft
    for _ in 0..<3 {
      let result = try random.draw(draft: runtime, customIDs: [], systemIsDark: false, pointsPerRem: 16, context: .init(), chooseIndex: { _ in 0 })
      runtime = try XCTUnwrap(result.steps.last)
    }
    XCTAssertEqual(runtime.themes.favorites, [.dracula, .nord, .serika], "A word setter must not detach the favorite array as a full import does")
  }

  func testLiveThemeCommandsAgainstPinnedSettersControllerAndEveryBuiltInName() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned source") }
    struct Field: Decodable { let key: String; let value: WebsiteConfigValue }
    struct Checkpoint: Decodable { let key: String; let value: [String: WebsiteConfigValue] }
    struct Fixture: Decodable {
      let fields: [Field], current: [String: WebsiteConfigValue], runtime: [String: WebsiteConfigValue]
      let active: Bool, authenticated: Bool, count: Int, systemDark: Bool, shown: String
      let events: [WebsiteConfigApplicationEvent], saves: [String], checkpoints: [Checkpoint], notices: [Bool]
    }
    struct Output: Decodable { let fixtures: [Fixture]; let themeCount: Int }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--theme-commands"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 16 * 18 + 3 * output.themeCount + 4)
    XCTAssertEqual(output.themeCount, AppTheme.allCases.filter { $0 != .grove }.count)
    for f in output.fixtures {
      let context = WebsiteConfigRuntimeContext(authenticated: f.authenticated, customThemeCount: f.count)
      let plan = try WebsiteThemeCommand.plan(current: f.current, fields: f.fields.map { .init(key: $0.key, value: $0.value) }, context: context, active: f.active)
      var runtime = f.current, events: [WebsiteConfigApplicationEvent] = []
      var visible = try WebsiteConfigNativeThemes(runtime: runtime).initialSelection(systemIsDark: f.systemDark)
      var checkpoints: [[String: WebsiteConfigValue]] = []
      for step in plan.steps where step.accepted {
        let result = try WebsiteConfigRuntimeProjector.edit(current: runtime, key: step.key, value: step.value,
          defaults: WebsiteConfigNativeProfile.defaultDocument().values, schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs), context: context, testActive: f.active)
        XCTAssertEqual(result.events.count, 1); runtime = result.runtime; events += result.events; checkpoints.append(runtime)
        visible = try WebsiteConfigNativeThemes(runtime: runtime).selectionAfterSaving(key: step.key, visible: visible, systemIsDark: f.systemDark)
      }
      XCTAssertEqual(runtime, f.runtime); XCTAssertEqual(events, f.events)
      XCTAssertEqual(events.map(\.key), f.saves); XCTAssertEqual(checkpoints, f.checkpoints.map(\.value))
      XCTAssertEqual(f.checkpoints.map(\.key), f.saves)
      let name: String; switch visible { case .inlineCustom: name = "custom"; case .builtIn(let theme): name = theme.rawValue }
      XCTAssertEqual(name, f.shown, "\(f.fields.map(\.key)) auto=\(f.current["autoSwitchTheme"]!) custom=\(f.current["customTheme"]!)")
      let customRangeRejected = plan.steps.contains { !$0.accepted && $0.key == "randomTheme" && $0.value == .string("custom") }
      XCTAssertEqual(f.notices, (plan.disablesSystem || customRangeRejected) ? [false] : [])
    }
  }

  func testPreferencesSystemThemesAndFavoritesKeepAttemptAndResourcesDuringNoQuit() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","theme":"dracula","funbox":["no_quit"],"themeLight":"serika","themeDark":"nord"}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch(String(state.session.nextExpectedCharacter!)); f.page.replace(state)
    let original = try XCTUnwrap(f.page.state.presentation), generation = f.page.state.session.generationState
    let prefs = f.settings.snapshot, ledger = f.page.state.priorAttemptLedger, controller = f.page.restartController
    let controls = PracticeThemePreferences(settings: f.settings)
    controls.followsSystem.wrappedValue = true
    XCTAssertEqual(f.page.state.presentation?.appearance.selection, .builtIn(.serika))
    controls.light.wrappedValue = .dracula
    XCTAssertEqual(f.page.state.presentation?.appearance.selection, .builtIn(.dracula))
    controls.dark.wrappedValue = .serika_dark
    XCTAssertEqual(f.page.state.presentation?.appearance.selection, .builtIn(.dracula))
    XCTAssertTrue(try XCTUnwrap(f.page.state.presentation).updateSystemAppearance(isDark: true))
    XCTAssertEqual(f.page.state.presentation?.appearance.selection, .builtIn(.serika_dark))
    controls.toggleFavorite(.nord); XCTAssertTrue(controls.favorites.contains(.nord))
    controls.toggleFavorite(.nord); XCTAssertFalse(controls.favorites.contains(.nord))
    controls.theme.wrappedValue = .nord
    XCTAssertFalse(controls.followsSystem.wrappedValue)
    let after = try XCTUnwrap(f.page.state.presentation)
    XCTAssertEqual(after.appearance.selection, .builtIn(.nord))
    XCTAssertFalse(after.updateSystemAppearance(isDark: false))
    XCTAssertEqual(after.appearance.selection, .builtIn(.nord))
    XCTAssertEqual(f.settings.snapshot, prefs); XCTAssertEqual(f.page.state.session.generationState, generation)
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger); XCTAssertTrue(f.page.restartController === controller)
    XCTAssertEqual(after.publication.font?.renderingFont, original.publication.font?.renderingFont)
    XCTAssertEqual(after.publication.background?.source, original.publication.background?.source)
    guard case .some(.none) = after.publication.background?.state else { return XCTFail("Background changed") }
    guard case .available(let saved) = try WebsiteConfigFileRegister(directory: f.directory).read().state else { return XCTFail("Missing saved theme") }
    XCTAssertEqual(saved["theme"], .string("nord")); XCTAssertEqual(saved["autoSwitchTheme"], .bool(false))
  }

  func testForeignDiskAndNativeOnlyThemeAreRejectedWithoutFallback() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let id = try XCTUnwrap(f.page.state.presentation?.publication.applicationID), prefs = f.settings.snapshot
    XCTAssertFalse(ThemeCommandApplication.apply(.builtIn(.grove), to: f.settings))
    let register = WebsiteConfigFileRegister(directory: f.directory), disk = try register.read()
    guard case .available(var foreign) = disk.state else { return XCTFail("Missing saved profile") }
    foreign["words"] = .number(9)
    guard case .committed = try register.commit(runtime: foreign, lazyMemory: disk.lazyMemory, replacing: XCTUnwrap(disk.revision)) else { return XCTFail("Foreign save failed") }
    let revision = try register.read().revision
    XCTAssertFalse(ThemeCommandApplication.apply(.builtIn(.nord), to: f.settings))
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, id); XCTAssertEqual(f.settings.snapshot, prefs)
    XCTAssertEqual(try register.read().revision, revision)
  }

  func testLosslessCustomSelectionAndSourceSystemDisableUseActualColors() async throws {
    let f = try Fixture(); defer { f.close() }
    let owned = try WebsiteConfigNativeProfile.prepareDraft(##"{"customThemeColors":["#102030","#203040","#304050","#405060","#506070","#607080","#708090","#8090a0","#90a0b0","#a0b0c0"]}"##, pointsPerRem: 16, context: .init())
    let custom = try owned.themes.makeCustomTheme(id: UUID(), name: "Owned theme")
    f.settings.customThemes = [custom]; try await f.publish()
    let prefs = f.settings.snapshot, generation = f.page.state.session.generationState
    XCTAssertTrue(ThemeCommandApplication.apply(.custom(custom.id), to: f.settings))
    let presentation = try XCTUnwrap(f.page.state.presentation)
    XCTAssertEqual(presentation.appearance.selection, .inlineCustom)
    XCTAssertEqual(presentation.appearance.theme, custom.resolvedTheme)
    XCTAssertEqual(presentation.publication.draft.themes.customColorHex, owned.themes.customColorHex)
    let controls = PracticeThemePreferences(settings: f.settings)
    controls.followsSystem.wrappedValue = true
    XCTAssertEqual(f.page.state.presentation?.appearance.selection, .builtIn(.serika))
    XCTAssertTrue(ThemeCommandApplication.apply(.custom(custom.id), to: f.settings))
    XCTAssertFalse(controls.followsSystem.wrappedValue)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.themes.customEnabled, true)
    XCTAssertEqual(f.page.state.presentation?.appearance.selection, .builtIn(.dracula), "The source auto-off listener reapplies the manual built-in even with customTheme true")
    XCTAssertEqual(f.settings.snapshot, prefs); XCTAssertEqual(f.page.state.session.generationState, generation)
    var lossy = custom; lossy.fadedText.opacity = 0.5; f.settings.customThemes = [lossy]
    let before = f.settings.snapshot, id = f.page.state.presentation?.publication.applicationID
    XCTAssertFalse(ThemeCommandApplication.apply(.custom(lossy.id), to: f.settings))
    XCTAssertEqual(f.settings.snapshot, before); XCTAssertEqual(f.page.state.presentation?.publication.applicationID, id)
    lossy = custom; lossy.background.red = 0.12345
    XCTAssertThrowsError(try WebsiteThemeCommand.fields(for: .select(.custom(lossy.id)), customThemes: [lossy]))
    lossy = custom; lossy.prefersDark.toggle()
    XCTAssertThrowsError(try WebsiteThemeCommand.fields(for: .select(.custom(lossy.id)), customThemes: [lossy]),
      "An independent native color scheme cannot be silently replaced by source HSL classification")
  }

  func testRouterOwnsRejectionsReentrancyAndActiveWindowOnly() throws {
    let f = try Fixture(); defer { f.close() }; let router = f.settings.preferenceConfigurationSaves, second = UUID()
    var firstCalls = 0, secondCalls = 0
    router.register(owner: f.page.owner, themeEdit: { _ in firstCalls += 1; return true }, save: {})
    router.register(owner: second, themeEdit: { edit in
      secondCalls += 1; XCTAssertEqual(router.applyThemeEdit(edit), false)
      XCTAssertEqual(router.applyFontEdit(.family("Courier")), false)
      return false
    }, save: {})
    router.activate(owner: second); let before = f.settings.snapshot
    XCTAssertFalse(ThemeCommandApplication.apply(.builtIn(.nord), to: f.settings))
    XCTAssertEqual(firstCalls, 0); XCTAssertEqual(secondCalls, 1); XCTAssertEqual(f.settings.snapshot, before)
    router.remove(owner: second)
    XCTAssertTrue(ThemeCommandApplication.apply(.builtIn(.nord), to: f.settings))
    XCTAssertEqual(firstCalls, 1); XCTAssertEqual(f.settings.snapshot, before)
  }

  func testSystemDisableNoticeComesFromControllerSideEffectNotExplicitToggle() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    func run(_ edit: PracticeThemeEdit) throws -> Bool {
      try f.workflow.runThemeCommand(edit, replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID)).disabledSystemFollowing
    }
    XCTAssertFalse(try run(.followSystem(true)))
    XCTAssertFalse(try run(.followSystem(false)), "An explicit off setter must not claim a controller side effect")
    XCTAssertFalse(try run(.followSystem(true)))
    XCTAssertTrue(try run(.select(.builtIn(.nord))))
    XCTAssertFalse(try run(.followSystem(false)))
    XCTAssertFalse(try run(.followSystem(true)))
    XCTAssertTrue(try run(.customEnabled(false)))
  }

  func testAdmissionRejectsCompoundThemeWritesAndOtherFields() throws {
    let original = try WebsiteConfigNativeProfile.prepareDraft(#"{"theme":"dracula","customTheme":true}"#, pointsPerRem: 16, context: .init())
    let compound = try WebsiteConfigNativeProfile.editDraft(original, key: "theme", value: .string("nord"), pointsPerRem: 16, context: .init())
    XCTAssertFalse(WebsiteThemeCommand.admits(compound, from: original))
    let child = try WebsiteConfigNativeProfile.editDraft(original, key: "customTheme", value: .bool(false), pointsPerRem: 16, context: .init())
    XCTAssertTrue(WebsiteThemeCommand.admits(child, from: original))
    let parent = try WebsiteConfigNativeProfile.editDraft(child, key: "theme", value: .string("nord"), pointsPerRem: 16, context: .init())
    XCTAssertTrue(WebsiteThemeCommand.admits(parent, from: child)); XCTAssertFalse(WebsiteThemeCommand.admits(parent, from: original))
    let unrelated = try WebsiteConfigNativeProfile.editDraft(original, key: "fontFamily", value: .string("Courier"), pointsPerRem: 16, context: .init())
    XCTAssertFalse(WebsiteThemeCommand.admits(unrelated, from: original))
  }

  func testConflictAfterChildSaveKeepsSuccessfulPrefixAndReportsIncompleteCommand() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"theme":"dracula","customTheme":true,"autoSwitchTheme":true}"#, systemIsDark: false)
    let id = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let prefs = f.settings.snapshot, generation = f.page.state.session.generationState
    let register = WebsiteConfigFileRegister(directory: f.directory)
    var interfered = false
    f.probe.action = {
      guard !interfered, f.page.state.presentation?.publication.draft.themes.customEnabled == false else { return }
      interfered = true
      do {
        let disk = try register.read()
        guard case .available(var fields) = disk.state else { return XCTFail("Missing saved prefix") }
        fields["words"] = .number(9)
        guard case .committed = try register.commit(runtime: fields, lazyMemory: disk.lazyMemory, replacing: XCTUnwrap(disk.revision))
        else { return XCTFail("Foreign write failed") }
      } catch { XCTFail("Foreign writer: \(error)") }
    }
    XCTAssertThrowsError(try f.workflow.runThemeCommand(.select(.builtIn(.nord)), replacing: id)) {
      guard case WebsiteThemeCommandError.interrupted(saved: 1, underlying: _) = $0 else { return XCTFail("Wrong prefix outcome: \($0)") }
    }
    f.probe.action = nil; XCTAssertTrue(interfered)
    let after = try XCTUnwrap(f.page.state.presentation)
    XCTAssertFalse(after.publication.draft.themes.customEnabled)
    XCTAssertTrue(after.publication.draft.themes.followsSystem); XCTAssertEqual(after.publication.draft.themes.theme, .dracula)
    XCTAssertEqual(after.appearance.selection, .builtIn(.dracula))
    XCTAssertEqual(f.settings.snapshot, prefs); XCTAssertEqual(f.page.state.session.generationState, generation)
    guard case .available(let saved) = try register.read().state else { return XCTFail("Lost saved prefix") }
    XCTAssertEqual(saved["customTheme"], .bool(false)); XCTAssertEqual(saved["theme"], .string("dracula"))
    XCTAssertEqual(saved["words"], .number(9)); XCTAssertEqual(saved["autoSwitchTheme"], .bool(true))
  }

  @MainActor @Observable fileprivate final class MountedModel {
    let fixture: Fixture
    var ready: [PromptViewportPresentationReady] = []
    let motion = PromptCaretMotionCoordinator()
    init(_ fixture: Fixture) { self.fixture = fixture }
    func prompt() throws -> PromptViewportPracticePrompt {
      let p = try XCTUnwrap(fixture.page.state.presentation), session = fixture.page.state.session
      return try p.wholePreview(session: session, carets: { font, presentation in
        .init(text: AttributedString(session.prompt), mainOffset: nil, paceOffset: nil,
          mainStyle: presentation.caretStyle, paceStyle: presentation.paceCaretStyle, font: font,
          lineSpacing: 12, rightToLeft: false, accent: .blue, motion: presentation.smoothCaretMotion,
          reducesMotion: true, frameRate: 60, attemptID: session.automaticInputAttemptID, coordinator: self.motion)
      }, onFailure: { _ in XCTFail("Published theme rendering failed") }, onReady: { self.ready.append($0) })
    }
  }
  private struct MountedRoot: View {
    let model: MountedModel
    var body: some View {
      ScrollView { if let prompt = try? model.prompt() { prompt } }.frame(width: 600, height: 400)
    }
  }
  func testHiddenTextKitPromptActuallyRepaintsAfterThemeCommandWithoutNewAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":5,"fontFamily":"Courier","showAllLines":true,"theme":"dracula"}"#, systemIsDark: false)
    let generation = f.page.state.session.generationState, model = MountedModel(f)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: MountedRoot(model: model)); window.contentView = host
    defer { window.contentView = nil; window.close() }
    func wait(_ theme: ResolvedTheme) async {
      let deadline = Date().addingTimeInterval(2)
      repeat { host.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded() }
      while model.ready.last?.style.theme != theme && Date() < deadline
    }
    await wait(AppTheme.dracula.resolvedTheme)
    XCTAssertEqual(model.ready.last?.style.theme, AppTheme.dracula.resolvedTheme)
    XCTAssertTrue(ThemeCommandApplication.apply(.builtIn(.nord), to: f.settings))
    await wait(AppTheme.nord.resolvedTheme)
    XCTAssertEqual(model.ready.last?.style.theme, AppTheme.nord.resolvedTheme)
    try f.workflow.runThemeCommand(.favorites([.serika]), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID))
    try f.workflow.runThemeCommand(.random(.favorites), replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID))
    try f.workflow.runRandomThemeCommand(replacing: XCTUnwrap(f.page.state.presentation?.publication.applicationID))
    await wait(AppTheme.serika.resolvedTheme)
    XCTAssertEqual(model.ready.last?.style.theme, AppTheme.serika.resolvedTheme)
    XCTAssertEqual(f.page.state.session.generationState, generation); XCTAssertFalse(window.isVisible)
  }
}
