import AppKit
import Observation
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteThemePreviewTests: XCTestCase {
  @MainActor final class Fixture {
    let suite = "typebar.theme-preview.\(UUID())"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-theme-preview-\(UUID())")
    let settings: AppSettings, defaults: UserDefaults, page: PracticePageSessionStore, account: AccountSession
    let workflow: WebsiteConfigImportWorkflow
    init() throws {
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), page = PracticePageSessionStore()
      let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory()), account = AccountSession(defaults: defaults)
      self.defaults = defaults; self.settings = settings; self.page = page; self.account = account
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      settings.preferenceConfigurationSaves.register(owner: page.owner, save: { XCTFail("Preview cannot save native preferences") })
      page.attach(to: settings.preferenceConfigurationSaves)
      workflow = .init(page: page, settings: settings, account: account, directory: directory,
        readWindow: { .published(owner: page.owner, revision: page.state.session.automaticInputAttemptID, scope: page.state.practice?.scope ?? .init()) })
      let workflow = workflow
      settings.preferenceConfigurationSaves.register(owner: page.owner, themes: { page.state.presentation?.publication.draft.themes },
        themeEdit: { edit in
          guard page.ownsConfigurationSelection else { return nil }
          guard let id = page.state.presentation?.publication.applicationID else { return false }
          do { try workflow.runThemeCommand(edit, replacing: id); return true } catch { return false }
        }, save: { XCTFail("Preview cannot save native preferences") })
    }
    func publish(_ json: String = #"{"mode":"words","words":5,"theme":"dracula","fontFamily":"Courier","showAllLines":true}"#, systemIsDark: Bool = false) async throws {
      try await workflow.apply(json: json, systemIsDark: systemIsDark)
    }
    func close() {
      workflow.stop(); page.detach(); settings.preferenceConfigurationSaves.remove(owner: page.owner)
      defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory)
    }
  }
  @MainActor final class Clock {
    var now = 0
    var pending: [UUID: (Int, @MainActor () -> Void)] = [:]
    func schedule(_ delay: Int, _ action: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
      let id = UUID(); pending[id] = (now + delay, action)
      return { self.pending.removeValue(forKey: id) }
    }
    func advance(_ delta: Int) {
      let end = now + delta
      while let first = pending.min(by: { $0.value.0 < $1.value.0 }), first.value.0 <= end {
        now = first.value.0; pending.removeValue(forKey: first.key); first.value.1()
      }
      now = end
    }
  }

  func testFullPinnedPreviewClearMediaAndSetterTrajectoriesWithLockedDebounce() async throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"],
      ProcessInfo.processInfo.environment["TYPEBAR_THEME_DEBOUNCE_ARCHIVE"] != nil else { throw XCTSkip("Requires pinned source and debounce archive") }
    struct Action: Decodable { let kind: String; let name: String?; let key: String?; let value: WebsiteConfigValue?; let ms: Int? }
    struct Indicator: Decodable { let text: String; let isFavorite: Bool }
    struct Shown: Decodable {
      let name: String, bg: String
      let main: String?, caret: String?, sub: String?, subAlt: String?, text: String?
      let error: String?, errorExtra: String?, colorfulError: String?, colorfulErrorExtra: String?
    }
    struct Frame: Decodable { let shown: Shown; let indicator: Indicator; let isPreviewing: Bool; let runtime: [String: WebsiteConfigValue] }
    struct Sample: Decodable { let initial: [String: WebsiteConfigValue]; let systemDark: Bool; let actions: [Action]; let frames: [Frame] }
    struct Custom: Decodable { let _id: String, name: String; let colors: [String] }
    struct Footer: Decodable { let custom: Bool, authenticated: Bool, count: Int, shift: Bool, enabled: Bool, subgroup: String?, notices: Int, saves: Int }
    struct Output: Decodable { let customThemes: [Custom]; let fixtures: [Sample]; let footerCases: [Footer] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path, reference, "--theme-preview"]
    process.standardOutput = pipe; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 160); XCTAssertEqual(output.fixtures.reduce(0) { $0 + $1.frames.count }, 864)
    XCTAssertEqual(output.footerCases.count, 16)
    for sample in output.footerCases {
      switch WebsiteThemeFooterAction.action(shift: sample.shift, customEnabled: sample.custom, authenticated: sample.authenticated, libraryCount: sample.count) {
      case .custom(let enabled, let notice):
        XCTAssertEqual(enabled, sample.enabled); XCTAssertEqual(notice ? 1 : 0, sample.notices); XCTAssertEqual(sample.saves, 1)
      case .picker(let scope):
        XCTAssertEqual(scope == .custom ? "customTheme" : "themes", sample.subgroup); XCTAssertEqual(sample.saves, 0)
      }
    }
    func custom(_ colors: [String], name: String) throws -> CustomThemeDefinition {
      var runtime = try WebsiteConfigNativeProfile.defaultDocument().values
      runtime["customThemeColors"] = .array(colors.map(WebsiteConfigValue.string))
      return try WebsiteConfigNativeThemes(runtime: runtime).makeCustomTheme(id: UUID(), name: name)
    }
    func json(_ values: [String: WebsiteConfigValue]) throws -> String {
      var runtime = values
      runtime["mode"] = .string("words"); runtime["words"] = .number(5)
      runtime["fontFamily"] = .string("Courier"); runtime["showAllLines"] = .bool(true)
      return String(decoding: try JSONEncoder().encode(runtime), as: UTF8.self)
    }
    for (index, sample) in output.fixtures.enumerated() {
      let f = try Fixture(); defer { f.close() }
      let library = try Dictionary(uniqueKeysWithValues: output.customThemes.map { ($0._id, try custom($0.colors, name: $0.name)) })
      f.settings.customThemes = output.customThemes.compactMap { library[$0._id] }
      try await f.publish(json(sample.initial), systemIsDark: sample.systemDark)
      let clock = Clock(), preview = WebsiteThemePreview(schedule: clock.schedule)
      preview.synchronize(f.page.state.presentation)
      let preferences = f.settings.snapshot
      var dark = sample.systemDark
      func check(_ frame: Frame) throws {
        let p = try XCTUnwrap(f.page.state.presentation), token = preview.prepared(for: p, owner: f.page.owner)
        let actual = try p.background(fallbackStyle: .solid, reduceMotion: true, themePreview: token)
        let expected: ResolvedTheme
        if frame.shown.name == "custom" {
          let s = frame.shown
          expected = try custom([s.bg, XCTUnwrap(s.main), XCTUnwrap(s.caret), XCTUnwrap(s.sub), XCTUnwrap(s.subAlt),
            XCTUnwrap(s.text), XCTUnwrap(s.error), XCTUnwrap(s.errorExtra), XCTUnwrap(s.colorfulError), XCTUnwrap(s.colorfulErrorExtra)], name: "Expected").resolvedTheme
        } else { expected = try XCTUnwrap(AppTheme(rawValue: frame.shown.name)).resolvedTheme }
        XCTAssertEqual(actual.theme, expected, "fixture \(index)")
        let indicator = try XCTUnwrap(preview.indicator(for: p, customThemes: f.settings.customThemes))
        XCTAssertEqual(indicator.name, frame.indicator.text, "fixture \(index)")
        XCTAssertEqual(indicator.isFavorite, frame.indicator.isFavorite, "fixture \(index)")
        XCTAssertEqual(preview.isPreviewing, frame.isPreviewing, "fixture \(index)")
        for (key, value) in frame.runtime { XCTAssertEqual(p.publication.draft.projection.runtime[key], value, "fixture \(index): \(key)") }
        XCTAssertEqual(f.settings.snapshot, preferences)
      }
      try check(XCTUnwrap(sample.frames.first))
      for (offset, action) in sample.actions.enumerated() {
        let old = try XCTUnwrap(f.page.state.presentation), generation = f.page.state.session.generationState
        let register = WebsiteConfigFileRegister(directory: f.directory), disk = try register.read().revision
        switch action.kind {
        case "preview":
          let name = try XCTUnwrap(action.name)
          let target: ThemeCommandTarget
          if let custom = library[name] { target = .custom(custom.id) }
          else { target = .builtIn(try XCTUnwrap(AppTheme(rawValue: name))) }
          XCTAssertTrue(preview.select(target, presentation: old, customThemes: f.settings.customThemes))
        case "clear": preview.clear()
        case "tick": clock.advance(try XCTUnwrap(action.ms))
        case "media": dark.toggle(); preview.systemAppearanceChanged(old, isDark: dark)
        case "footerShift":
          guard case .custom(let enabled, _) = WebsiteThemeFooterAction.action(shift: true, customEnabled: old.publication.draft.themes.customEnabled,
            authenticated: false, libraryCount: library.count) else { return XCTFail("Wrong footer action") }
          try f.workflow.runThemeCommand(.customEnabled(enabled), replacing: old.publication.applicationID)
          preview.synchronize(f.page.state.presentation)
        case "favoriteAdd", "favoriteRemove":
          _ = CurrentThemeFavoriteCommandApplication.apply(action.kind == "favoriteAdd" ? .add : .remove,
            to: f.settings, colorScheme: dark ? .dark : .light, onConfigurationSave: { XCTFail("Cannot save native favorites") })
          preview.synchronize(f.page.state.presentation)
        case "full": try await f.publish(json(sample.frames[offset + 1].runtime), systemIsDark: dark); preview.synchronize(f.page.state.presentation)
        case "custom":
          try f.workflow.runThemeCommand(.select(.custom(XCTUnwrap(library[XCTUnwrap(action.name)]).id)), replacing: old.publication.applicationID)
          preview.synchronize(f.page.state.presentation)
        case "field":
          let value = try XCTUnwrap(action.value), key = try XCTUnwrap(action.key)
          if key == "fontSize", case .number(let scale) = value {
            try f.workflow.runFontCommand(.size(scale * 16), replacing: old.publication.applicationID)
          } else {
            let edit: PracticeThemeEdit
            switch (key, value) {
            case ("theme", .string(let name)): edit = .select(.builtIn(try XCTUnwrap(AppTheme(rawValue: name))))
            case ("themeLight", .string(let name)): edit = .light(try XCTUnwrap(AppTheme(rawValue: name)))
            case ("themeDark", .string(let name)): edit = .dark(try XCTUnwrap(AppTheme(rawValue: name)))
            case ("autoSwitchTheme", .bool(let flag)): edit = .followSystem(flag)
            case ("customTheme", .bool(let flag)): edit = .customEnabled(flag)
            case ("randomTheme", .string(let mode)): edit = .random(try XCTUnwrap(RandomThemeMode(rawValue: mode)))
            case ("favThemes", .array(let names)): edit = .favorites(try names.map { item in
              guard case .string(let name) = item else { throw WebsiteThemeCommandError.unsupported }
              return try XCTUnwrap(AppTheme(rawValue: name))
            })
            default: throw WebsiteThemeCommandError.unsupported
            }
            try f.workflow.runThemeCommand(edit, replacing: old.publication.applicationID)
          }
          preview.synchronize(f.page.state.presentation)
        default: XCTFail("Unknown source action")
        }
        if ["preview", "clear", "tick", "media"].contains(action.kind) {
          XCTAssertEqual(try register.read().revision, disk); XCTAssertEqual(f.page.state.session.generationState, generation)
          XCTAssertEqual(f.page.state.presentation?.publication.applicationID, old.publication.applicationID)
        }
        try check(sample.frames[offset + 1])
      }
    }
  }
  func testPublishedBackgroundDoesNotDiscardTheThemeHoveredInTheMenu() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let p = try XCTUnwrap(f.page.state.presentation)
    let menu = ThemePreviewPresentation(settings: f.settings, systemColorScheme: .light, previewTarget: .builtIn(.serika))
    var pending: [@MainActor () -> Void] = []
    let preview = WebsiteThemePreview(schedule: { delay, action in XCTAssertEqual(delay, 250); pending.append(action); return {} })
    XCTAssertTrue(preview.select(.builtIn(.serika), presentation: p, customThemes: []))
    XCTAssertNil(preview.prepared(for: p, owner: f.page.owner))
    try XCTUnwrap(pending.last)()
    let token = try XCTUnwrap(preview.prepared(for: p, owner: f.page.owner))
    let background = try p.background(fallbackStyle: .solid, reduceMotion: true, themePreview: token)
    XCTAssertEqual(background.theme, menu.theme)
    XCTAssertEqual(p.appearance.theme, AppTheme.dracula.resolvedTheme)
  }

  func testNonThemePublicationKeepsHoverBeforeTheViewObserverRuns() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let first = try XCTUnwrap(f.page.state.presentation), clock = Clock()
    let display = WebsiteThemePreview(schedule: clock.schedule)
    display.select(.builtIn(.nord), presentation: first, customThemes: []); clock.advance(250)
    try f.workflow.runFontCommand(.size(30), replacing: first.publication.applicationID)
    let next = try XCTUnwrap(f.page.state.presentation)
    XCTAssertEqual(next.themeChanges, first.themeChanges)
    let background = try next.background(fallbackStyle: .solid, reduceMotion: true,
      themePreview: display.prepared(for: next, owner: f.page.owner))
    XCTAssertEqual(background.theme, AppTheme.nord.resolvedTheme, "A font publication cannot expose the base theme while the observer is queued")
    display.synchronize(next)
    XCTAssertEqual(display.prepared(for: next, owner: f.page.owner)?.theme, AppTheme.nord.resolvedTheme)
  }

  func testEveryBuiltInPreviewLeavesSavedProfileAndNativePreferencesUntouched() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let p = try XCTUnwrap(f.page.state.presentation), clock = Clock()
    let preview = WebsiteThemePreview(schedule: clock.schedule)
    let preferences = f.settings.snapshot, disk = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    for theme in AppTheme.allCases where theme != .grove {
      XCTAssertTrue(preview.select(.builtIn(theme), presentation: p, customThemes: [])); clock.advance(249)
      clock.advance(1)
      let token = try XCTUnwrap(preview.prepared(for: p, owner: f.page.owner))
      XCTAssertEqual(try p.background(fallbackStyle: .solid, reduceMotion: true, themePreview: token).theme, theme.resolvedTheme)
      XCTAssertEqual(preview.indicator(for: p, customThemes: [])?.name, theme.rawValue.replacingOccurrences(of: "_", with: " "))
      preview.clear()
    }
    XCTAssertEqual(f.settings.snapshot, preferences); XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, disk)
  }

  func testLateCancelledCallbacksAndClosedWindowCannotRestoreAnOldHover() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let p = try XCTUnwrap(f.page.state.presentation)
    var queued: [@MainActor () -> Void] = []
    let preview = WebsiteThemePreview(schedule: { _, action in queued.append(action); return {} })
    preview.select(.builtIn(.serika), presentation: p, customThemes: [])
    preview.select(.builtIn(.nord), presentation: p, customThemes: [])
    queued[0](); XCTAssertFalse(preview.isPreviewing)
    queued[1](); XCTAssertEqual(preview.prepared(for: p, owner: f.page.owner)?.theme, AppTheme.nord.resolvedTheme)
    preview.select(.builtIn(.serika), presentation: p, customThemes: [])
    preview.stop(); preview.synchronize(p); queued[2]()
    XCTAssertFalse(preview.isPreviewing); XCTAssertNil(preview.prepared(for: p, owner: f.page.owner))
    preview.select(.builtIn(.serika), presentation: p, customThemes: []); preview.clear(); queued[3]()
    XCTAssertNil(preview.prepared(for: p, owner: f.page.owner))
  }

  func testForeignWindowOldPublicationAndSystemApplicationRejectOldTokens() async throws {
    let f = try Fixture(), other = try Fixture(); defer { f.close(); other.close() }
    try await f.publish(#"{"mode":"words","words":5,"theme":"dracula","autoSwitchTheme":true,"themeLight":"serika","themeDark":"serika","fontFamily":"Courier"}"#)
    try await other.publish()
    let p = try XCTUnwrap(f.page.state.presentation), foreign = try XCTUnwrap(other.page.state.presentation)
    let clock = Clock(), preview = WebsiteThemePreview(schedule: clock.schedule)
    preview.select(.builtIn(.nord), presentation: p, customThemes: []); clock.advance(250)
    let token = try XCTUnwrap(preview.prepared(for: p, owner: f.page.owner))
    XCTAssertNil(preview.prepared(for: foreign, owner: other.page.owner))
    XCTAssertThrowsError(try foreign.background(fallbackStyle: .solid, reduceMotion: true, themePreview: token))
    // Same base theme for light/dark: source apply still supersedes a hover.
    XCTAssertFalse(p.updateSystemAppearance(isDark: true))
    XCTAssertNil(preview.prepared(for: p, owner: f.page.owner))
    XCTAssertThrowsError(try p.background(fallbackStyle: .solid, reduceMotion: true, themePreview: token))
    preview.synchronize(p); XCTAssertTrue(preview.isPreviewing)
    XCTAssertNil(preview.prepared(for: p, owner: f.page.owner))
    preview.clear(); XCTAssertEqual(preview.prepared(for: p, owner: f.page.owner)?.theme, AppTheme.dracula.resolvedTheme)
    let restored = try XCTUnwrap(preview.prepared(for: p, owner: f.page.owner))
    try f.workflow.runFontCommand(.size(30), replacing: p.publication.applicationID)
    let next = try XCTUnwrap(f.page.state.presentation)
    XCTAssertThrowsError(try next.background(fallbackStyle: .solid, reduceMotion: true, themePreview: restored))
    XCTAssertEqual(preview.prepared(for: next, owner: f.page.owner)?.theme, AppTheme.dracula.resolvedTheme)
  }

  private static func carets(_ font: NSFont, _ p: WebsiteConfigNativePresentation,
    session: TypingSession, motion: PromptCaretMotionCoordinator) -> PromptCaretNativeView.Configuration {
    .init(text: AttributedString(session.prompt), mainOffset: nil, paceOffset: nil,
      mainStyle: p.caretStyle, paceStyle: p.paceCaretStyle, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .blue, motion: p.smoothCaretMotion, reducesMotion: true, frameRate: 60,
      attemptID: session.automaticInputAttemptID, coordinator: motion)
  }

  @MainActor @Observable final class MountedModel {
    let fixture: Fixture
    let preview = WebsiteThemePreview(), motion = PromptCaretMotionCoordinator()
    var ready: [PromptViewportPresentationReady] = []
    var fontState = FontFamilyCommandPreviewState()
    let fontCache = WebsiteConfigFontPreview()
    init(_ fixture: Fixture) { self.fixture = fixture; preview.synchronize(fixture.page.state.presentation) }
    func prompt() throws -> PromptViewportPracticePrompt {
      let p = try XCTUnwrap(fixture.page.state.presentation), session = fixture.page.state.session
      return try p.wholePreview(session: session,
        fontPreview: fontCache.prepare(fontState, publication: p.publication, owner: fixture.page.owner),
        themePreview: preview.prepared(for: p, owner: fixture.page.owner),
        carets: { font, preferences in WebsiteThemePreviewTests.carets(font, preferences, session: session, motion: self.motion) },
        onFailure: { _ in XCTFail("Theme preview drawing failed") }, onReady: { self.ready.append($0) })
    }
  }
  private struct MountedRoot: View {
    let model: MountedModel
    var body: some View { ScrollView { if let prompt = try? model.prompt() { prompt } }.frame(width: 600, height: 400) }
  }
  func testHiddenTextKitRealDelayAndCloseRestoreManualThemeWhileKeepingFontAndTypedNoQuit() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":5,"theme":"nord","autoSwitchTheme":true,"themeLight":"serika","fontFamily":"Courier","showAllLines":true,"funbox":["no_quit"]}"#)
    var state = f.page.state; state.session.insertBatch(String(try XCTUnwrap(state.session.nextExpectedCharacter))); f.page.replace(state)
    let p = try XCTUnwrap(f.page.state.presentation), model = MountedModel(f)
    let disk = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    let generation = f.page.state.session.generationState, preferences = f.settings.snapshot
    model.fontState.select(.init(id: "setFontFamilyGeorgia", title: "Georgia", subtitle: "", systemImage: "textformat", keywords: [], group: .appearance),
      savedFont: .monospaced, savedName: "Courier")
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: MountedRoot(model: model)); window.contentView = host
    defer { model.preview.stop(); window.contentView = nil; window.close() }
    func wait(_ theme: ResolvedTheme) async {
      let deadline = Date().addingTimeInterval(2)
      repeat { host.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(20)); host.layoutSubtreeIfNeeded() }
      while model.ready.last?.style.theme != theme && Date() < deadline
    }
    await wait(AppTheme.serika.resolvedTheme)
    XCTAssertEqual(model.ready.last?.style.theme, AppTheme.serika.resolvedTheme)
    XCTAssertTrue(model.preview.select(.builtIn(.dracula), presentation: p, customThemes: [])); XCTAssertFalse(model.preview.isPreviewing)
    await wait(AppTheme.dracula.resolvedTheme)
    XCTAssertEqual(model.ready.last?.style.theme, AppTheme.dracula.resolvedTheme)
    let token = try XCTUnwrap(model.preview.prepared(for: p, owner: f.page.owner))
    XCTAssertEqual(try p.background(fallbackStyle: .solid, reduceMotion: true, themePreview: token).theme, AppTheme.dracula.resolvedTheme)
    let font = try XCTUnwrap(model.fontCache.prepare(model.fontState, publication: p.publication, owner: f.page.owner))
    var seen: NSFont?
    _ = try p.inline(session: f.page.state.session, fontPreview: font, themePreview: token,
      carets: { _, supplied, preferences in seen = supplied; return Self.carets(supplied, preferences, session: f.page.state.session, motion: model.motion) },
      retirement: { rendering, preferences in
        let session = f.page.state.session, field = session.promptCompositionField
        return .init(attemptID: session.automaticInputAttemptID, activeWordID: field?.index,
          characterOffsets: rendering.compositionTextMap?.fieldCharacterOffsets ?? [:],
          smoothScroll: preferences.smoothPracticeLineScroll, reducesMotion: true, words: PromptLineScrollWord.compositionFields(field),
          firstRetainedWordIndex: session.firstRetainedPromptWordIndex, caretMotion: model.motion, centersActiveLine: !preferences.showAllPracticeLines)
      })
    XCTAssertEqual(seen?.fontName, NSFont(name: "Georgia", size: 32)?.fontName)
    model.preview.clear(); await wait(AppTheme.nord.resolvedTheme)
    XCTAssertEqual(model.ready.last?.style.theme, AppTheme.nord.resolvedTheme)
    XCTAssertEqual(model.ready.last?.font.fontName, NSFont(name: "Georgia", size: 32)?.fontName)
    XCTAssertEqual(p.appearance.selection, .builtIn(.serika)); XCTAssertEqual(f.page.state.session.generationState, generation)
    XCTAssertTrue(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
    XCTAssertEqual(f.settings.snapshot, preferences); XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, disk)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, p.publication.applicationID); XCTAssertFalse(window.isVisible)
  }
}
