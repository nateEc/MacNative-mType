import AppKit
import Observation
import SwiftData
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigStartupHostTests: XCTestCase {
  @MainActor @Observable fileprivate final class HostState {
    let page = PracticePageSessionStore()
    var accountReady = false
  }
  @MainActor private final class Fixture {
    let suite = "typebar.startup-host.\(UUID())"
    let support = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-startup-host-\(UUID())")
    let defaults: UserDefaults, settings: AppSettings, account: AccountSession
    let state = HostState(), container: ModelContainer
    let host: NSHostingView<AnyView>, window: NSWindow
    let record: URL?
    /// nil: no directory; true: valid record; false: opaque record.
    init(saved: Bool?) throws {
      try FileManager.default.createDirectory(at: support, withIntermediateDirectories: false)
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = .init(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}),
        localBackgroundStore: .inMemory())
      settings.reducePracticeMotion = true; settings.showAllPracticeLines = false
      XCTAssertTrue(settings.saveActiveTestSelection(.init(preset: .init(configuration: .words(3)),
        testParameterMemory: .legacyDefaults(configuration: .words(3)))))
      account = .init(defaults: defaults)
      if let saved {
        let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: support)
        let register = WebsiteConfigFileRegister(directory: directory)
        let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":4,"theme":"dracula"}"#,
          pointsPerRem: 16, context: .init())
        guard case .committed = try register.commit(draft, replacing: XCTUnwrap(register.read().revision)) else {
          throw WebsiteConfigImportWorkflowError.conflict
        }
        let path = directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
        if !saved { try Data("opaque future record".utf8).write(to: path) }
        record = path
      } else { record = nil }
      container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self, SavedCustomTextRecord.self,
        ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      let view = Root(state: state, settings: settings, account: account, support: support, defaults: defaults)
        .modelContainer(container).frame(width: 1000, height: 760)
      host = NSHostingView(rootView: AnyView(view))
      window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 760), styleMask: .borderless,
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = host
    }
    func inputs(_ root: NSView? = nil) -> [TypingInputView] {
      let root = root ?? host
      return (root as? TypingInputView).map { [$0] } ?? root.subviews.flatMap { inputs($0) }
    }
    func wait(_ ready: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
      let deadline = Date().addingTimeInterval(10)
      repeat { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
      while !ready() && Date() < deadline
      XCTAssertTrue(ready(), "Startup production host did not settle", file: file, line: line)
    }
    func close() {
      host.rootView = AnyView(EmptyView()); host.layoutSubtreeIfNeeded()
      window.contentView = nil; window.close()
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: support)
    }
  }
  private struct Root: View {
    let state: HostState, settings: AppSettings, account: AccountSession, support: URL
    let announcements: RemoteAnnouncementCenter
    let hotkey = GlobalHotkeyMonitor(), keyboard = SystemKeyboardGuideMonitor(observesInputSourceChanges: false)
    let network = NetworkConnectivityMonitor(), appearance = SystemAppearanceMonitor()
    init(state: HostState, settings: AppSettings, account: AccountSession, support: URL, defaults: UserDefaults) {
      self.state = state; self.settings = settings; self.account = account; self.support = support
      announcements = .init(defaults: defaults)
    }
    var body: some View {
      TypebarApp.practiceContent(settings: settings, account: account, announcements: announcements,
        hotkey: hotkey, systemKeyboardGuide: keyboard, network: network, systemAppearance: appearance,
        practiceSessionStore: state.page,
        websiteConfigStartup: .init(accountReady: state.accountReady, applicationSupport: support))
    }
  }

  func testRealPageBlocksInputUntilAccountReadyAndRestoresExactlyOnce() throws {
    let f = try Fixture(saved: true); defer { f.close() }
    let before = try Data(contentsOf: XCTUnwrap(f.record)), legacy = f.settings.snapshot
    f.wait { f.state.page.startupController.state == .waiting && !f.inputs().isEmpty }
    let input = try XCTUnwrap(f.inputs().first)
    XCTAssertFalse(input.acceptsTextInput)
    input.onInsert("unadmitted", false)
    XCTAssertEqual(f.state.page.state.session.typed, "")
    f.state.accountReady = true
    f.wait { !f.state.page.startupController.isBlocking && input.acceptsTextInput
      && f.state.page.state.practice != nil }
    XCTAssertEqual(f.state.page.state.session.configuration.wordLimit, 4)
    XCTAssertNotNil(f.state.page.restartController)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(f.record)), before)
    XCTAssertEqual(f.settings.snapshot, legacy)
    let attempt = f.state.page.state.session.automaticInputAttemptID
    f.state.accountReady = false
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    f.state.accountReady = true
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertFalse(f.window.isVisible)
  }

  func testMissingRecordKeepsLegacyPracticeAndCreatesNothingEvenBeforeAccountReady() throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.wait { f.inputs().first?.acceptsTextInput == true }
    XCTAssertNil(f.state.page.state.practice)
    XCTAssertEqual(f.state.page.state.session.configuration.wordLimit, 3)
    XCTAssertFalse(FileManager.default.fileExists(atPath: f.support.appendingPathComponent("Typebar").path))
    XCTAssertFalse(f.window.isVisible)
  }

  func testBadRecordRequiresExplicitChoiceAndThenResumesActualLegacyInput() throws {
    let f = try Fixture(saved: false); defer { f.close() }
    let opaque = try Data(contentsOf: XCTUnwrap(f.record))
    f.state.accountReady = true
    f.wait { f.state.page.startupController.failureMessage != nil && !f.inputs().isEmpty }
    let input = try XCTUnwrap(f.inputs().first)
    XCTAssertFalse(input.acceptsTextInput)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(f.record)), opaque)
    f.state.page.startupController.continueUsingLegacy()
    f.wait { input.acceptsTextInput }
    input.onInsert("a", false)
    XCTAssertEqual(f.state.page.state.session.typed, "a")
    XCTAssertNil(f.state.page.state.practice)
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(f.record)), opaque)
    XCTAssertFalse(f.window.isVisible)
  }

  func testRecoveryNoticeLayoutDoesNotAutomaticallyChooseOrShowAWindow() throws {
    var choices = 0
    let view = WebsiteConfigStartupNotice(state: .failed("保存的配置未能恢复，原记录未被重置。请检查配置后重试，或明确选择使用 Typebar 设置继续。"),
      recover: { choices += 1 }, continueUsingLegacy: { choices += 1 })
      .frame(width: 760, height: 160).background(Color(nsColor: .windowBackgroundColor))
      .environment(\.colorScheme, .light)
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 760, height: 160), styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentView = host
    defer { window.contentView = nil; window.close() }
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      .write(to: URL(fileURLWithPath: "/tmp/typebar-startup-recovery-notice.png"))
    XCTAssertEqual(choices, 0); XCTAssertFalse(window.isVisible)
  }
}
