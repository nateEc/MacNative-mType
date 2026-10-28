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
    init() throws {
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
        })
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
    XCTAssertEqual(f.page.state.session.generationState, generation); XCTAssertFalse(window.isVisible)
  }
}
