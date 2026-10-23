import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Typebar

@MainActor
final class PolyglotLanguageSelectionTests: XCTestCase {
  func testClearValidatesTheDestinationLanguageInsteadOfTheOldPolyglotState() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("let proposedLanguage = target == .clear"))
    XCTAssertTrue(app.contains("guard acceptsFunboxConfiguration(updated, language: proposedLanguage)"))
    for mode in TestMode.allCases {
      let destination = PolyglotReturnLanguagePolicy.languageAfterDisabling(current: .mixedLanguages, base: .french)
      XCTAssertTrue(TestModifierPolicy.acceptsModeSelection(mode, modifiers: [], language: destination))
      XCTAssertTrue(WebsiteFunboxAdmission.accepts(.array([]), current: [
        "mode": .string(mode.rawValue), "funbox": .array([.string("polyglot")])]))
    }
  }

  func testEntryReselectionAndExitPreserveEveryOrdinaryLanguageWithoutAdoptingStaleState() {
    for language in TypingLanguage.allCases where language != .mixedLanguages {
      let base = PolyglotReturnLanguagePolicy.baseWhenSelecting(.mixedLanguages,
        current: language, previous: .french)
      XCTAssertEqual(base, language)
      XCTAssertEqual(PolyglotReturnLanguagePolicy.baseWhenSelecting(.mixedLanguages,
        current: .mixedLanguages, previous: base), language)
      XCTAssertEqual(PolyglotReturnLanguagePolicy.languageAfterDisabling(current: .mixedLanguages,
        base: base), language)
      XCTAssertEqual(PolyglotReturnLanguagePolicy.languageAfterDisabling(current: language,
        base: .french), language)
      XCTAssertNil(PolyglotReturnLanguagePolicy.baseWhenSelecting(language,
        current: .mixedLanguages, previous: .german))
    }
    XCTAssertNil(PolyglotReturnLanguagePolicy.baseWhenSelecting(.mixedLanguages,
      current: .mixedLanguages, previous: nil), "A legacy missing base is not silently adopted by reselection")
    for invalid: TypingLanguage? in [nil, .mixedLanguages] {
      XCTAssertEqual(PolyglotReturnLanguagePolicy.languageAfterDisabling(current: .mixedLanguages,
        base: invalid), .english)
    }
  }

  func testResolvedDirectionAndFreshStoredSelectionSupplyTheExitLanguage() throws {
    let base = PolyglotReturnLanguagePolicy.baseWhenSelecting(.mixedLanguages,
      current: .german, previous: nil)
    let requested = TestConfiguration.words(3, language: .mixedLanguages,
      mixedLanguageComponents: [.arabic, .hebrew], polyglotBaseLanguage: base)
    let session = TestSessionFactory.make(configuration: requested)
    XCTAssertEqual(session.configuration.polyglotBaseLanguage, .arabic)
    let suite = "typebar.polyglot-language-exit.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let saved = ActiveTestSelectionDocument(preset: .init(configuration: session.configuration),
      testParameterMemory: .defaults, polyglotReturnLanguage: session.configuration.polyglotBaseLanguage)
    XCTAssertTrue(ActiveTestSelectionStore(defaults: defaults).save(saved))
    let restored = try XCTUnwrap(ActiveTestSelectionStore(defaults: defaults).load())
    XCTAssertEqual(PolyglotReturnLanguagePolicy.languageAfterDisabling(current: restored.preset.configuration.language,
      base: restored.polyglotReturnLanguage), .arabic)
    XCTAssertEqual(restored.preset.configuration.wordPoolBaseLanguage, .arabic)
  }

  func testMainMenuCommandAndClearUseTheSameBasePolicy() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertEqual(app.components(separatedBy: "PolyglotReturnLanguagePolicy.baseWhenSelecting(").count - 1, 2)
    XCTAssertEqual(app.components(separatedBy: "PolyglotReturnLanguagePolicy.languageAfterDisabling(").count - 1, 2)
  }

  func testNativeLanguageMenuRetainsPrimaryAcrossEntryReselectionAndPersistence() throws {
    let suite = "typebar.polyglot-language-menu.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.reducePracticeMotion = true
    let initial = ActiveTestSelectionDocument(preset: .init(configuration: .words(3, language: .german)),
      testParameterMemory: .defaults)
    XCTAssertTrue(settings.saveActiveTestSelection(initial))
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let content = TypebarApp.practiceContent(settings: settings,
      account: AccountSession(defaults: defaults), announcements: RemoteAnnouncementCenter(defaults: defaults),
      hotkey: GlobalHotkeyMonitor(), systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
      network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor()).modelContainer(container)
    let host = NSHostingView(rootView: AnyView(content.frame(width: 1000, height: 720)))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    func flush() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      host.layoutSubtreeIfNeeded()
    }
    func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { views(type, in: $0) }
    }
    func waitFor(_ condition: () -> Bool) throws {
      let deadline = Date().addingTimeInterval(15)
      while !condition() && Date() < deadline { flush() }
      guard condition() else { throw XCTUnwrapError.failedCheckpoint }
    }
    defer {
      host.rootView = AnyView(EmptyView())
      flush()
      window.contentView = nil
      window.close()
      withExtendedLifetime(container) {}
    }
    try waitFor { !views(PracticeLanguagePopUp.self, in: host).isEmpty }
    let menu = try XCTUnwrap(views(PracticeLanguagePopUp.self, in: host).first)
    func select(_ language: TypingLanguage) throws {
      let item = try XCTUnwrap(menu.itemArray.first { $0.representedObject as? String == language.rawValue })
      menu.select(item)
      XCTAssertTrue(menu.sendAction(menu.action, to: menu.target))
      try waitFor { settings.activeTestSelection?.preset.configuration.language == language }
    }
    XCTAssertEqual(menu.selectedItem?.representedObject as? String, TypingLanguage.german.rawValue)
    for _ in 0..<2 {
      try select(.mixedLanguages)
      let saved = try XCTUnwrap(ActiveTestSelectionStore(defaults: defaults).load())
      XCTAssertEqual(saved.polyglotReturnLanguage, .german)
      XCTAssertEqual(saved.preset.configuration.wordPoolBaseLanguage, .german)
    }
    try select(.french)
    XCTAssertNil(settings.activeTestSelection?.polyglotReturnLanguage)
    try select(.mixedLanguages)
    let saved = try XCTUnwrap(ActiveTestSelectionStore(defaults: defaults).load())
    XCTAssertEqual(saved.polyglotReturnLanguage, .french)
    XCTAssertEqual(saved.preset.configuration.wordPoolBaseLanguage, .french)
    XCTAssertFalse(window.isVisible)
  }

  private enum XCTUnwrapError: Error { case failedCheckpoint }
}
