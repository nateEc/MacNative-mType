import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class FontFamilyCommandPreviewTests: XCTestCase {
  func testEverySelectableFontRowPreviewsButFileAndNavigationActionsDoNot() {
    let items = FontFamilyCommandCatalog.items(hasLocalFont: false, availableKnownFontIDs: [])
    for item in items {
      let target = FontFamilyCommandCatalog.target(for: item.id)
      switch target {
      case .systemDesign, .knownIdentifier:
        XCTAssertEqual(FontFamilyCommandPreviewPolicy.target(for: item), target, item.id)
      default: XCTAssertNil(FontFamilyCommandPreviewPolicy.target(for: item), item.id)
      }
    }
    for id in ["useLocalFont", "removeLocalFont", "customFontName", "customLocalFont", "browseInstalledFonts", "setFontFamilyunknown"] {
      let item = CommandPaletteItem(id: id, title: id, subtitle: "", systemImage: "textformat", keywords: [], group: .appearance)
      XCTAssertNil(FontFamilyCommandPreviewPolicy.target(for: item))
    }
    XCTAssertNil(FontFamilyCommandPreviewPolicy.target(for: nil))
  }

  func testPreviewBypassesLocalOverrideWithoutReadingOrChangingIt() throws {
    var lookups = 0
    let georgia = try XCTUnwrap(NSFont(name: "Georgia", size: 28))
    let resolver = NativePracticeFont.Resolver(localFontName: { lookups += 1; return "Courier" },
      installedFontName: { NSFont(name: $0, size: 28)?.fontName })
    let font = try XCTUnwrap(FontFamilyCommandPreviewPolicy.font(for: .knownIdentifier("Georgia"),
      size: 28, fallback: .monospaced, resolver: resolver))
    XCTAssertEqual(font.fontName, georgia.fontName)
    XCTAssertEqual(lookups, 0)
    XCTAssertEqual(resolver.postScriptName(for: "Georgia"), "Courier")
    XCTAssertEqual(lookups, 1)
  }

  func testNativeDesignPreviewAndMissingNameUseTheRequestedDesignAndSize() throws {
    let resolver = NativePracticeFont.Resolver(localFontName: { XCTFail("Preview must not resolve local font"); return "Courier" },
      installedFontName: { _ in nil })
    let system = try XCTUnwrap(FontFamilyCommandPreviewPolicy.font(for: .systemDesign(.defaultSystem),
      size: 31, fallback: .serif, resolver: resolver))
    XCTAssertEqual(system, NSFont.systemFont(ofSize: 31, weight: .medium))
    let fallback = try XCTUnwrap(FontFamilyCommandPreviewPolicy.font(for: .knownIdentifier("Roboto_Mono"),
      size: 31, fallback: .monospaced, resolver: resolver))
    XCTAssertEqual(fallback, NSFont.monospacedSystemFont(ofSize: 31, weight: .medium))
    for target: FontFamilyCommandTarget? in [nil, .customName, .localFile, .useLocalFile, .removeLocalFile, .browseInstalled, .knownIdentifier("invalid")] {
      XCTAssertNil(FontFamilyCommandPreviewPolicy.font(for: target, size: 31, fallback: .serif, resolver: resolver))
    }
  }

  func testProductionPreviewAndDismissalAreConnectedToSharedPromptFont() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("commandFontPreview.select(item, savedFont: settings.practiceFont"))
    XCTAssertTrue(app.contains("clearCommandFontPreview()"))
    XCTAssertTrue(app.contains("for: commandFontPreview.target, size: size"))
    XCTAssertTrue(app.contains("commandFontPreview.appliedFontFamily()"))
    XCTAssertTrue(app.contains(".onChange(of: activeChallengeID) { _, _ in commandFontPreview.appliedFontFamily() }"))
  }

  private func item(_ id: String) -> CommandPaletteItem {
    .init(id: id, title: id, subtitle: "", systemImage: "textformat", keywords: [], group: .appearance)
  }

  func testClearUsesLatestSavedFamilyWithoutReapplyingLocalCascadeAndRepeatedClearIsInert() throws {
    var state = FontFamilyCommandPreviewState()
    state.select(item("setFontFamilyGeorgia"), savedFont: .monospaced, savedName: "Courier")
    XCTAssertTrue(state.isPreviewing)
    XCTAssertEqual(state.target, .knownIdentifier("Georgia"))
    state.clear(savedFont: .serif, savedName: "Menlo")
    XCTAssertFalse(state.isPreviewing)
    XCTAssertEqual(state.target, .installedName("Menlo"))
    state.clear(savedFont: .defaultSystem, savedName: "Courier")
    XCTAssertEqual(state.target, .installedName("Menlo"))
    let resolver = NativePracticeFont.Resolver(localFontName: { XCTFail("Clear must use saved family only"); return "Courier" },
      installedFontName: NativePracticeFont.postScriptName)
    XCTAssertEqual(try XCTUnwrap(FontFamilyCommandPreviewPolicy.font(for: state.target,
      size: 28, fallback: .monospaced, resolver: resolver)).fontName, NSFont(name: "Menlo", size: 28)?.fontName)
    state.appliedFontFamily()
    XCTAssertNil(state.target)
  }

  func testNonFontEmptyResultsAndSavedApplicationDuringPreviewPreserveSourceFlagSemantics() {
    var state = FontFamilyCommandPreviewState()
    state.select(item("setFontFamilyGeorgia"), savedFont: .monospaced, savedName: "")
    state.select(item("history"), savedFont: .serif, savedName: "")
    XCTAssertEqual(state.target, .systemDesign(.serif)); XCTAssertFalse(state.isPreviewing)
    state.select(nil, savedFont: .monospaced, savedName: "")
    XCTAssertEqual(state.target, .systemDesign(.serif))
    state.select(item("setFontFamilyCourier"), savedFont: .monospaced, savedName: "Georgia")
    state.appliedFontFamily()
    XCTAssertNil(state.target); XCTAssertTrue(state.isPreviewing)
    state.clear(savedFont: .monospaced, savedName: "Georgia")
    XCTAssertEqual(state.target, .installedName("Georgia"))
    state.select(nil, savedFont: .monospaced, savedName: "Menlo")
    XCTAssertEqual(state.target, .installedName("Georgia"))
  }

  func testChallengeLocalWingdingsIsTheSavedFamilyWhenPreviewIsCleared() {
    for challenge: String? in [nil, "other", "ten-words-of-pain"] {
      let name = FontFamilyCommandPreviewPolicy.savedName(challengeID: challenge, installedName: "Georgia")
      XCTAssertEqual(name, challenge == "ten-words-of-pain" ? "Wingdings" : "Georgia")
      var state = FontFamilyCommandPreviewState()
      state.select(item("setFontFamilyCourier"), savedFont: .monospaced, savedName: name)
      state.clear(savedFont: .monospaced, savedName: name)
      XCTAssertEqual(state.target, .installedName(name))
    }
  }

  func testPreviewAndClearNeverPersistSettingsOrMutateAttemptInputOrWrapperEvents() throws {
    let name = "TypebarTests.FontPreview.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = AppSettings(defaults: defaults)
    settings.installedPracticeFontName = "Courier"
    var session = TypingSession(configuration: .words(3), prompt: "amber birch cedar")
    let time = Date(timeIntervalSinceReferenceDate: 913_000_000)
    session.insertBatch("amber ", at: time)
    let attempt = session.automaticInputAttemptID, revision = settings.practiceWrapperRevision
    let persisted = defaults.persistentDomain(forName: name) as NSDictionary?
    var state = FontFamilyCommandPreviewState()
    for id in ["setFontFamilyGeorgia", "fontFamily.native.serif", "history", "setFontFamilyCourier"] {
      state.select(item(id), savedFont: settings.practiceFont, savedName: settings.installedPracticeFontName)
      _ = FontFamilyCommandPreviewPolicy.font(for: state.target, size: 28, fallback: settings.practiceFont)
    }
    state.clear(savedFont: settings.practiceFont, savedName: settings.installedPracticeFontName)
    XCTAssertEqual(defaults.persistentDomain(forName: name) as NSDictionary?, persisted)
    XCTAssertEqual(settings.installedPracticeFontName, "Courier")
    XCTAssertEqual(settings.practiceWrapperRevision, revision)
    XCTAssertEqual(session.automaticInputAttemptID, attempt)
    XCTAssertEqual(session.typed, "amber "); XCTAssertEqual(session.prompt, "amber birch cedar")
    XCTAssertEqual(session.firstRetainedPromptWordIndex, 0)
    session.insertBatch("birch cedar", at: time.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), session.typed)
  }

  func testRepeatedAndNormalizedSavedFontApplicationsHaveEphemeralEventsSeparateFromWrapper() throws {
    let name = "TypebarTests.FontApplication.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = AppSettings(defaults: defaults)
    let fontRevision = settings.practiceFontApplicationRevision, wrapperRevision = settings.practiceWrapperRevision
    settings.practiceFont = .monospaced
    settings.installedPracticeFontName = "Georgia"
    settings.installedPracticeFontName = "  Georgia  "
    settings.installedPracticeFontName = "Georgia"
    XCTAssertEqual(settings.practiceFontApplicationRevision, fontRevision + 4)
    XCTAssertEqual(settings.practiceWrapperRevision, wrapperRevision)
    for key in [AppSettings.legacyStorageKey, AppSettings.expandedPaceStorageKey, AppSettings.accountPaceStorageKey] {
      if let data = defaults.data(forKey: key) {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["practiceFontApplicationRevision"])
      }
    }
  }

  func testPinnedCompletePreviewAndDismissalSourceTrajectories() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Requires pinned reference checkout") }
    struct Fixture: Decodable { let local: Bool, preferred: Bool, hideRoute: String, restored: String }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), out = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-font-command-preview.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = out; try process.run()
    let data = out.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let fixtures = try JSONDecoder().decode(Output.self, from: data).fixtures
    XCTAssertEqual(fixtures.count, 12)
    for value in fixtures {
      var state = FontFamilyCommandPreviewState()
      state.select(item("setFontFamilyGeorgia"), savedFont: .monospaced, savedName: "Courier")
      state.clear(savedFont: .monospaced, savedName: "Menlo")
      XCTAssertEqual(state.target, .installedName("Menlo"))
      XCTAssertTrue(value.restored.hasPrefix("\"Menlo\""))
      XCTAssertFalse(value.restored.contains("LOCALCUSTOM")); XCTAssertFalse(value.restored.contains("Noto Sans Lao"))
    }
  }

  @MainActor @Observable final class Model {
    let settings: AppSettings
    var preview = FontFamilyCommandPreviewState()
    var showsPalette = false
    let session = TypingSession(configuration: .words(6), prompt: "iiii iiii iiii iiii iiii iiii")
    init(settings: AppSettings) { self.settings = settings }
    var font: NSFont {
      FontFamilyCommandPreviewPolicy.font(for: preview.target, size: 28, fallback: settings.practiceFont)
        ?? settings.practiceFont.nsFont(size: 28, installedFontName: settings.installedPracticeFontName,
          resolver: .init(localFontName: { nil }))
    }
  }

  private struct Root: View {
    let model: Model
    var body: some View {
      VStack {
        Text(model.session.prompt).font(Font(model.font)).lineSpacing(12)
          .frame(width: 240).fixedSize(horizontal: false, vertical: true)
        if model.showsPalette {
          CommandPaletteView(items: [CommandPaletteItem(id: "fontFamily.native.monospaced", title: "等宽字体", subtitle: "临时预览", systemImage: "textformat", keywords: [], group: .appearance)],
            listMode: .singleList, onSelect: { _ in },
            onPreview: { model.preview.select($0, savedFont: model.settings.practiceFont, savedName: model.settings.installedPracticeFontName) })
        }
      }.foregroundStyle(.black).background(.white).frame(width: 500, height: 540)
    }
  }

  func testActualPaletteAppearanceAndDisappearancePreviewAndRestoreWithoutActivatingWindow() throws {
    let name = "TypebarTests.FontPreviewMounted.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = AppSettings(defaults: defaults); settings.practiceFont = .defaultSystem
    let model = Model(settings: settings), attempt = model.session.automaticInputAttemptID
    let persisted = defaults.persistentDomain(forName: name) as NSDictionary?
    let original = model.font
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 500, height: 540), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: Root(model: model)); window.contentView = host
    defer { window.contentView = nil; window.close() }
    @MainActor func pump() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.06)); host.layoutSubtreeIfNeeded() }
    @MainActor func capture(_ phase: String) throws {
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("font-command-preview-\(phase).png"))
      }
    }
    pump(); try capture("initial")
    model.showsPalette = true; pump(); pump()
    XCTAssertTrue(model.preview.isPreviewing)
    XCTAssertEqual(model.font, NSFont.monospacedSystemFont(ofSize: 28, weight: .medium))
    XCTAssertNotEqual(model.font, original); try capture("active")
    model.showsPalette = false; pump(); pump()
    XCTAssertFalse(model.preview.isPreviewing); XCTAssertEqual(model.font, original)
    try capture("restored")
    XCTAssertEqual(defaults.persistentDomain(forName: name) as NSDictionary?, persisted)
    XCTAssertEqual(model.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(model.session.prompt, "iiii iiii iiii iiii iiii iiii")
    XCTAssertEqual(model.session.typed, ""); XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    XCTAssertFalse(window.isVisible)
  }
}
