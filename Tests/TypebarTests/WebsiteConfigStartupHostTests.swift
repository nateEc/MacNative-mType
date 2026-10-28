import AppKit
import Observation
import SwiftData
import SwiftUI
import Vision
import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigStartupHostTests: XCTestCase {
  func testRepeatedCustomSectionCounterRendersInActualHiddenRootAfterWordNavigation() async throws {
    let f = try Fixture(saved: true, json: #"{"mode":"words","words":3,"timerStyle":"text"}"#,
      viewportHeight: 3200)
    defer { f.close() }
    let custom = try WebsiteCustomTextSettings(value: .object([
      "text": .array([.string("Aa Bb"), .string("Cc")]), "mode": .string("repeat"),
      "limit": .object(["mode": .string("section"), "value": .number(5)]), "pipeDelimiter": .bool(false)]))
    XCTAssertTrue(f.settings.saveWebsiteCustomTextState(custom))
    f.state.accountReady = true
    try await f.waitAsync { f.state.page.state.presentation != nil && f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection })
    defer { workflow.stop() }
    // This workflow must first own an application before editing it; an
    // independent coordinator cannot edit the startup coordinator's ticket.
    try await workflow.apply(json: #"{"mode":"words","words":3,"timerStyle":"text"}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
      && f.inputs().first?.acceptsTextInput == true }
    let repeated = try await XCTUnwrap(f.state.page.restartController).requestAndWait(requestID: UUID(), repeatingRequested: true)
    XCTAssertTrue(repeated)
    let old = f.state.page.state.session.prompt
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
    try XCTUnwrap(f.inputs().first).onInsert("x", false)
    try await workflow.editAndBegin(.mode(.custom),
      replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
      && f.inputs().first?.acceptsTextInput == true }
    try XCTUnwrap(f.inputs().first).onInsert(old + " Aa ", false)
    f.wait { f.state.page.state.session.progressText() == "3/5" }
    try f.scrollToInput()
    let text: String
    do { text = try f.renderedText().joined(separator: " ").replacingOccurrences(of: " ", with: "") }
    catch {
      let failure = error as NSError
      XCTFail("Hidden section recognition: \(failure.domain) \(failure.code) \(failure.userInfo)")
      return
    }
    if !text.contains("3/5") {
      let bitmap = try XCTUnwrap(f.host.bitmapImageRepForCachingDisplay(in: f.host.bounds))
      f.host.cacheDisplay(in: f.host.bounds, to: bitmap)
      try bitmap.representation(using: .png, properties: [:])?.write(
        to: URL(fileURLWithPath: "/tmp/typebar-generated-section-host-progress.png"))
    }
    XCTAssertTrue(text.contains("3/5"), text)
    XCTAssertFalse(f.window.isVisible)
    XCTAssertNil(f.window.attachedSheet)
  }

  func testImmediateNoQuitImportLeavesTheActualHostAbleToRestartNormally() async throws {
    let f = try Fixture(saved: true, json: #"{"mode":"words","words":4,"funbox":["no_quit"]}"#)
    defer { f.close() }
    f.state.accountReady = true
    try await f.waitAsync { f.state.page.state.presentation != nil && f.inputs().first?.acceptsTextInput == true }
    try XCTUnwrap(f.inputs().first).onInsert("x", false)
    XCTAssertFalse(f.settings.allowsRestartingConfigurationChange)
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection })
    defer { workflow.stop() }
    _ = try await workflow.apply(json: #"{"mode":"words","words":7}"#, systemIsDark: false)
    XCTAssertTrue(f.settings.allowsRestartingConfigurationChange,
      "Committed inactive page must release its owning No Quit lock synchronously")
    try await f.waitAsync { f.settings.allowsRestartingConfigurationChange
      && f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
      && f.inputs().first?.acceptsTextInput == true }
    let attempt = f.state.page.state.session.automaticInputAttemptID
    let controller = try XCTUnwrap(f.state.page.restartController)
    let advanced = try await controller.requestAndWait(requestID: UUID())
    XCTAssertTrue(advanced, controller.message ?? "Ordinary restart failed after full import")
    XCTAssertNotEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(f.state.page.state.session.configuration.wordLimit, 7)
    XCTAssertFalse(f.window.isVisible)
  }

  func testActiveFullImportRetiresActualInputAndKeepsOneLedgerEntryWithoutShowingAWindow() async throws {
    for noQuit in [false, true] {
      let boxes = noQuit ? #"["no_quit"]"# : "[]"
      let f = try Fixture(saved: true,
        json: "{\"mode\":\"words\",\"words\":4,\"resultSaving\":false,\"funbox\":\(boxes)}")
      defer { f.close() }
      f.state.accountReady = true
      try await f.waitAsync { f.state.page.state.presentation != nil && f.inputs().first?.acceptsTextInput == true }
      let input = try XCTUnwrap(f.inputs().first), oldInsert = input.onInsert
      oldInsert("x", false)
      let attempt = f.state.page.state.session.automaticInputAttemptID
      XCTAssertTrue(f.state.page.state.session.hasStarted)
      let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
      let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
      var continuation: CheckedContinuation<[OfflineQuote], Never>?
      defer { continuation?.resume(returning: []) }
      let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
        directory: directory, readWindow: { selection }, loadQuotes: { _ in
          await withCheckedContinuation { continuation = $0 }
        })
      defer { workflow.stop() }
      var finished = false
      let task = Task {
        defer { finished = true }
        _ = try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"resultSaving":false}"#, systemIsDark: false)
      }
      defer { task.cancel() }
      try await f.waitAsync { continuation != nil || finished }
      if continuation == nil { try await task.value; return XCTFail("Import finished without reaching the controlled reader") }
      XCTAssertEqual(f.state.page.state.session.outcome, .abandoned)
      XCTAssertNotNil(f.state.page.state.savedApplication)
      XCTAssertFalse(f.state.page.acceptsInput(for: attempt))
      oldInsert("stale", false)
      XCTAssertEqual(f.state.page.state.session.typed, "x")
      XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 1)
      let pending = try XCTUnwrap(continuation); continuation = nil
      pending.resume(returning: [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)])
      try await task.value
      try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
        && f.inputs().first?.acceptsTextInput == true }
      oldInsert("late", false)
      XCTAssertEqual(f.state.page.state.session.typed, "")
      XCTAssertEqual(f.state.page.state.session.prompt, "ab cd")
      XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 1)
      XCTAssertEqual(try f.container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
      XCTAssertFalse(f.window.isVisible); XCTAssertNil(f.window.attachedSheet)
    }
  }

  // Match the application's process-owned dataStore. Retired SwiftUI @Query
  // observers can receive later context-save notifications; their contexts
  // must not outlive a weakly referenced container. Keep fixture stores
  // independent while giving them the same lifetime as the actual app store.
  private static var ownedFixtureStores: [ModelContainer] = []
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
    init(saved: Bool?, json: String = #"{"mode":"words","words":4,"theme":"dracula"}"#,
      fetch: @escaping WebsiteConfigExternalContent.Fetch = { _, _ in nil }, feedbackSound: TypingFeedbackSound? = nil,
      clipboardExport: WebsiteConfigClipboardExport? = nil, interruptedArchive: WebsiteProfileArchive? = nil,
      viewportHeight: CGFloat = 760) throws {
      try FileManager.default.createDirectory(at: support, withIntermediateDirectories: false)
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = .init(defaults: defaults, feedbackSound: feedbackSound ?? .init(loadSound: { _ in nil }, beep: {}),
        localBackgroundStore: .inMemory())
      settings.reducePracticeMotion = true; settings.showAllPracticeLines = false
      XCTAssertTrue(settings.saveActiveTestSelection(.init(preset: .init(configuration: .words(3)),
        testParameterMemory: .legacyDefaults(configuration: .words(3)))))
      account = .init(defaults: defaults)
      if let interruptedArchive {
        let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: support)
        let register = WebsiteConfigFileRegister(directory: directory)
        let plan = try register.prepareArchiveRestore(interruptedArchive, customStore: settings.websiteCustomArchiveStore)
        do {
          try register.restoreArchive(plan, customStore: settings.websiteCustomArchiveStore, checkpoint: {
            if $0 == .journalWritten { throw WebsiteProfileArchiveError.pendingRecovery }
          })
          XCTFail("Setup did not interrupt the journal")
        } catch WebsiteProfileArchiveError.pendingRecovery {}
      }
      if let saved {
        let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: support)
        let register = WebsiteConfigFileRegister(directory: directory)
        let draft = try WebsiteConfigNativeProfile.prepareDraft(json,
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
      WebsiteConfigStartupHostTests.ownedFixtureStores.append(container)
      let view = Root(state: state, settings: settings, account: account, support: support, defaults: defaults, fetch: fetch,
        clipboardExport: clipboardExport)
        .modelContainer(container).frame(width: 1000, height: viewportHeight)
      host = NSHostingView(rootView: AnyView(view))
      window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: viewportHeight), styleMask: .borderless,
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = host
    }
    func inputs(_ root: NSView? = nil) -> [TypingInputView] {
      let root = root ?? host
      return (root as? TypingInputView).map { [$0] } ?? root.subviews.flatMap { inputs($0) }
    }
    func renderedText(languages: [String] = ["en-US"]) throws -> [String] {
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate; request.recognitionLanguages = languages
      request.usesLanguageCorrection = false
      try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
      return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
    func scrollToInput() throws {
      func scrolls(_ view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrolls($0) }
      }
      host.layoutSubtreeIfNeeded()
      let input = try XCTUnwrap(inputs().first)
      let scroll = try XCTUnwrap(scrolls(host).filter { scroll in
        scroll.documentView.map { input.isDescendant(of: $0) } ?? false
      }.max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) })
      let document = try XCTUnwrap(scroll.documentView), clip = scroll.contentView
      let rect = input.convert(input.bounds, to: document)
      var bounds = clip.bounds; bounds.origin.y = max(0, rect.minY - 150)
      clip.scroll(to: clip.constrainBoundsRect(bounds).origin); scroll.reflectScrolledClipView(clip)
      host.layoutSubtreeIfNeeded()
    }
    func wait(_ ready: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
      let deadline = Date().addingTimeInterval(10)
      repeat { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
      while !ready() && Date() < deadline
      XCTAssertTrue(ready(), "Startup production host did not settle", file: file, line: line)
    }
    func waitAsync(_ ready: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
      let deadline = ContinuousClock.now.advanced(by: .seconds(10))
      while !ready() && ContinuousClock.now < deadline {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(20))
      }
      XCTAssertTrue(ready(), "Startup production host did not settle", file: file, line: line)
    }
    func close() {
      host.rootView = AnyView(EmptyView()); host.layoutSubtreeIfNeeded()
      window.contentView = nil; window.close()
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: support)
    }
  }
  func testArchiveProfileRetiredHostKeepsItsStoreAcrossLaterSaveNotifications() async throws {
    weak var retired: ModelContainer?
    do {
      let f = try Fixture(saved: nil)
      retired = f.container
      f.state.accountReady = true
      try await f.waitAsync { f.state.page.startupController.state == .finished }
      f.close()
    }
    XCTAssertNotNil(retired)
    let other = try ModelContainer(for: TestResultRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    try other.mainContext.save()
  }

  func testArchiveProfileColdStartupFinishesJournalEvenWithoutAnOldProfileFile() async throws {
    var runtime = try WebsiteConfigNativeProfile.defaultDocument().values
    runtime["mode"] = .string("custom")
    let text = try WebsiteCustomTextSettings(value: .object(["text": .array([.string("aa"), .string("bb")]),
      "mode": .string("repeat"), "limit": .object(["mode": .string("word"), "value": .number(3)]), "pipeDelimiter": .bool(false)]))
    let profile = try WebsiteProfileArchive(runtime: runtime, lazyMemory: .init(remember: true, prefersArabic: false),
      customTextData: XCTUnwrap(WebsiteCustomTextStateStore.encodeDocument(text)))
    let f = try Fixture(saved: nil, interruptedArchive: profile)
    defer { f.close() }
    let directory = try XCTUnwrap(WebsiteConfigStorageDirectory.existing(applicationSupport: f.support))
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename).path))
    f.state.accountReady = true
    try await f.waitAsync { f.state.page.state.practice != nil || f.state.page.startupController.failureMessage != nil }
    XCTAssertNil(f.state.page.startupController.lastFailure, "\(String(describing: f.state.page.startupController.lastFailure))")
    XCTAssertEqual(f.state.page.startupController.state, .finished)
    XCTAssertEqual(f.state.page.state.practice?.scope.websiteCustomText?.value, text.value)
    XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(WebsiteConfigFileRegister.archiveJournalFilename).path))
    // Pinned test-logic.ts restores remembered Lazy Mode during custom-test
    // initialization, then clears remember. Archive storage itself retains both
    // flags exactly; this assertion observes the subsequent live lifecycle.
    let initialized = try WebsiteConfigFileRegister(directory: directory).read()
    guard case .available(let initializedRuntime) = initialized.state else { return XCTFail("Initialized profile is unavailable") }
    XCTAssertEqual(initializedRuntime["lazyMode"], .bool(true))
    XCTAssertEqual(initialized.lazyMemory, .init(remember: false, prefersArabic: false))
  }

  func testArchiveProfileDeliveryUsesRestoredIndependentTextInActualRoot() async throws {
    let f = try Fixture(saved: nil)
    defer { f.close() }
    f.state.accountReady = true
    try await f.waitAsync { f.state.page.startupController.state == .finished && f.inputs().first?.acceptsTextInput == true }
    let text = try WebsiteCustomTextSettings(value: .object(["text": .array([.string("aa"), .string("bb")]),
      "mode": .string("repeat"), "limit": .object(["mode": .string("word"), "value": .number(3.5)]), "pipeDelimiter": .bool(false)]))
    let runtime = try WebsiteConfigNativeProfile.prepare(#"{"mode":"custom","words":17,"time":42}"#, context: .init()).projection.runtime
    let profile = try WebsiteProfileArchive(runtime: runtime, lazyMemory: .init(remember: true, prefersArabic: false),
      customTextData: XCTUnwrap(WebsiteCustomTextStateStore.encodeDocument(text)))
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(settings: f.settings.snapshot,
      results: [], presets: [], websiteProfile: profile))
    let summary = try LocalArchiveImport.apply(archive, settings: f.settings, results: [], presets: [], savedTexts: [],
      resultTombstoneStore: .init(defaults: f.defaults), presetTombstoneStore: .init(defaults: f.defaults),
      savedTextTombstoneStore: .init(defaults: f.defaults), customizationTombstoneStore: .init(defaults: f.defaults),
      tombstoneStore: .init(defaults: f.defaults), websiteProfileApplicationSupport: f.support, modelContext: f.container.mainContext)
    XCTAssertTrue(summary.restoredWebsiteProfile)
    try await f.waitAsync { f.state.page.state.practice != nil && f.inputs().first?.acceptsTextInput == true
      && f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
    XCTAssertEqual(f.state.page.state.session.configuration.mode, .custom)
    XCTAssertEqual(f.state.page.state.session.configuration.wordLimit, 4)
    XCTAssertEqual(f.state.page.state.practice?.scope.websiteCustomText?.value, text.value)
    XCTAssertTrue(f.state.page.state.session.prompt.split(separator: " ").allSatisfy { ["aa", "bb"].contains(String($0)) })
    let input = try XCTUnwrap(f.inputs().first)
    input.onInsert(f.state.page.state.session.prompt, false)
    try await f.waitAsync { f.state.page.state.session.isFinished }
  }

  func testArchiveProfilePreparationRefusalIsVisibleAndKeepsSavedValues() async throws {
    let f = try Fixture(saved: nil)
    defer { f.close() }
    f.state.accountReady = true
    try await f.waitAsync { f.state.page.startupController.state == .finished }
    var runtime = try WebsiteConfigNativeProfile.defaultDocument().values
    runtime["fontSize"] = .number(.infinity)
    let profile = try WebsiteProfileArchive(runtime: runtime, lazyMemory: .init(), customTextData: nil)
    let archive = TypebarArchive(exportedAt: .now, settings: f.settings.snapshot, results: [], presets: [], websiteProfile: profile)
    _ = try LocalArchiveImport.apply(archive, settings: f.settings, results: [], presets: [], savedTexts: [],
      resultTombstoneStore: .init(defaults: f.defaults), presetTombstoneStore: .init(defaults: f.defaults),
      savedTextTombstoneStore: .init(defaults: f.defaults), customizationTombstoneStore: .init(defaults: f.defaults),
      tombstoneStore: .init(defaults: f.defaults), websiteProfileApplicationSupport: f.support, modelContext: f.container.mainContext)
    try await f.waitAsync { f.state.page.startupController.failureMessage != nil }
    XCTAssertNil(f.state.page.state.practice)
    XCTAssertTrue(f.state.page.startupController.isBlocking)
    let saved = try XCTUnwrap(WebsiteProfileArchiveTarget.captureSaved(settings: f.settings, applicationSupport: f.support))
    XCTAssertEqual(saved.runtime["fontSize"], .number(.infinity))
  }

  private struct Root: View {
    let state: HostState, settings: AppSettings, account: AccountSession, support: URL
    let announcements: RemoteAnnouncementCenter
    let fetch: WebsiteConfigExternalContent.Fetch
    let clipboardExport: WebsiteConfigClipboardExport?
    let hotkey = GlobalHotkeyMonitor(), keyboard = SystemKeyboardGuideMonitor(observesInputSourceChanges: false)
    let network = NetworkConnectivityMonitor(), appearance = SystemAppearanceMonitor()
    init(state: HostState, settings: AppSettings, account: AccountSession, support: URL, defaults: UserDefaults,
      fetch: @escaping WebsiteConfigExternalContent.Fetch, clipboardExport: WebsiteConfigClipboardExport?) {
      self.state = state; self.settings = settings; self.account = account; self.support = support
      self.fetch = fetch
      self.clipboardExport = clipboardExport
      announcements = .init(defaults: defaults)
    }
    var body: some View {
      TypebarApp.practiceContent(settings: settings, account: account, announcements: announcements,
        hotkey: hotkey, systemKeyboardGuide: keyboard, network: network, systemAppearance: appearance,
        liveContentFetch: fetch,
        practiceSessionStore: state.page,
        websiteConfigStartup: .init(accountReady: state.accountReady, applicationSupport: support),
        configClipboardExport: clipboardExport)
    }
  }

  func testActualCommandPaletteHandsOffToCurrentConfigurationExportSheet() async throws {
    for noQuit in [false, true] {
      let boxes = noQuit ? #"["no_quit"]"# : "[]"
      let json = "{\"mode\":\"words\",\"words\":17,\"keymapSize\":1.4000000000000001,\"singleListCommandLine\":\"on\",\"minWpmCustomSpeed\":1e999,\"funbox\":\(boxes)}"
      let f = try Fixture(saved: true, json: json)
      defer { f.close() }
      f.state.accountReady = true
      try await f.waitAsync { f.state.page.state.presentation != nil && f.inputs().first?.acceptsTextInput == true }
      let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
      let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
      let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
        directory: directory, readWindow: { selection }); defer { workflow.stop() }
      try await workflow.apply(json: json, systemIsDark: false)
      try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
        && f.inputs().first?.acceptsTextInput == true }
      XCTAssertEqual(f.state.page.state.session.configuration.rules.thresholdSource?.configuration.minimumWpmCustomValue, .infinity)
      func views<T: NSView>(_ root: NSView, of type: T.Type) -> [T] {
        (root as? T).map { [$0] } ?? root.subviews.flatMap { views($0, of: type) }
      }
      f.window.orderFront(nil)
      let input = try XCTUnwrap(f.inputs().first)
      input.onInsert("a", false)
      let before = f.state.page.state.session
      let path = try XCTUnwrap(f.record), disk = try Data(contentsOf: path)
      input.onOpenCommandPalette()
      try await f.waitAsync { f.window.attachedSheet != nil }
      let palette = try XCTUnwrap(f.window.attachedSheet)
      defer { if let sheet = f.window.attachedSheet { f.window.endSheet(sheet) } }
      let search = try XCTUnwrap(views(XCTUnwrap(palette.contentView), of: NSTextField.self).first { $0.isEditable })
      XCTAssertTrue(palette.makeFirstResponder(search))
      let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
      editor.selectAll(nil)
      editor.insertText("exportSettingsJSON", replacementRange: editor.selectedRange())
      editor.insertNewline(nil)
      try await f.waitAsync { f.window.attachedSheet != nil && f.window.attachedSheet !== palette }
      let sheet = try XCTUnwrap(f.window.attachedSheet)
      let expected = try WebsiteConfigExport.json(XCTUnwrap(f.state.page.state.presentation).publication.draft, surface: .command)
      XCTAssertTrue(try views(XCTUnwrap(sheet.contentView), of: NSTextView.self).contains { $0.string.utf8.elementsEqual(expected.utf8) })
      XCTAssertEqual(f.state.page.state.session.configuration.wordLimit, 17)
      XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, before.automaticInputAttemptID)
      XCTAssertEqual(f.state.page.state.session.typed, before.typed)
      XCTAssertEqual(try Data(contentsOf: path), disk)
    }
  }

  func testSettingsExportActionPresentsLatestStoreInProductionManualCopySheet() async throws {
    var copies: [String] = [], delays: [Int] = [], callbacks: [@MainActor () -> Void] = []
    let exporter = WebsiteConfigClipboardExport(write: { copies.append($0); return false },
      schedule: { delays.append($0); callbacks.append($1) })
    let json = #"{"mode":"words","words":17,"keymapSize":1.4000000000000001,"paceCaret":"pb","randomTheme":"custom","tapeMode":"letter","showAllLines":true,"minWpmCustomSpeed":1e999}"#
    let f = try Fixture(saved: true, json: json,
      clipboardExport: exporter)
    defer { f.close() }
    f.state.accountReady = true
    try await f.waitAsync { f.state.page.state.presentation != nil && f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    try await workflow.apply(json: json, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
      && f.inputs().first?.acceptsTextInput == true }
    func views<T: NSView>(_ root: NSView, of type: T.Type) -> [T] {
      (root as? T).map { [$0] } ?? root.subviews.flatMap { views($0, of: type) }
    }
    func clickText(_ text: NSTextView, at point: NSPoint, in window: NSWindow) throws {
      let time = ProcessInfo.processInfo.systemUptime
      let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
        modifierFlags: [], timestamp: time, windowNumber: window.windowNumber, context: nil,
        eventNumber: 1, clickCount: 1, pressure: 1))
      let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
        modifierFlags: [], timestamp: time + 0.01, windowNumber: window.windowNumber, context: nil,
        eventNumber: 2, clickCount: 1, pressure: 0))
      NSApp.postEvent(up, atStart: true)
      text.mouseDown(with: down)
      if let remaining = NSApp.nextEvent(matching: .leftMouseUp, until: .now, inMode: .default, dequeue: true) {
        text.mouseUp(with: remaining)
      }
    }
    f.window.orderFront(nil)
    let path = try XCTUnwrap(f.record), before = try Data(contentsOf: path)
    let attempt = f.state.page.state.session.automaticInputAttemptID
    let initial = try WebsiteConfigExport.json(XCTUnwrap(f.state.page.state.presentation).publication.draft, surface: .settings)
    XCTAssertNotEqual(initial, try WebsiteConfigExport.json(XCTUnwrap(f.state.page.state.presentation).publication.draft, surface: .command))
    WebsiteConfigExport.copySettings(in: f.state.page, using: exporter)
    try await f.waitAsync { copies.count == 1 }
    guard copies.count == 1 else { return }
    XCTAssertEqual(copies, [initial]); XCTAssertEqual(delays, [250]); XCTAssertNil(exporter.manualCopy)
    XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(try Data(contentsOf: path), before)

    try await workflow.editAndBegin(.words(77), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
    let latest = try WebsiteConfigExport.json(XCTUnwrap(f.state.page.state.presentation).publication.draft, surface: .settings)
    XCTAssertNotEqual(latest, initial)
    let current = f.state.page.state.session, currentDisk = try Data(contentsOf: path)
    try XCTUnwrap(callbacks.first)()
    XCTAssertEqual(exporter.manualCopy?.json, latest)
    try await f.waitAsync { f.window.attachedSheet != nil }
    defer { if let sheet = f.window.attachedSheet { f.window.endSheet(sheet) } }
    let sheet = try XCTUnwrap(f.window.attachedSheet)
    let text = try XCTUnwrap(views(XCTUnwrap(sheet.contentView), of: WebsiteConfigCopyTextView.self).first)
    try await f.waitAsync {
      sheet.contentView?.layoutSubtreeIfNeeded()
      return text.string.utf8.elementsEqual(latest.utf8)
    }
    XCTAssertTrue(text.string.utf8.elementsEqual(latest.utf8), "Manual JSON length \(text.string.utf8.count), expected \(latest.utf8.count); prefix \(text.string.prefix(140))")
    XCTAssertFalse(text.isEditable); XCTAssertTrue(text.isSelectable)
    text.setSelectedRange(.init(location: 0, length: 0))
    let visible = text.visibleRect
    XCTAssertGreaterThan(visible.width, 300)
    XCTAssertGreaterThan(visible.height, 100)
    try clickText(text, at: text.convert(.init(x: visible.midX, y: visible.midY), to: nil), in: sheet)
    XCTAssertEqual(text.selectedRange(), NSRange(location: 0, length: text.string.utf16.count))
    XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, current.automaticInputAttemptID)
    XCTAssertEqual(f.state.page.state.session.typed, current.typed)
    XCTAssertEqual(try Data(contentsOf: path), currentDisk)
  }

  func testColdOnlineProfileLoadsAndContinuesThroughProductionPageWithoutLegacyWrites() throws {
    var reads = 0
    let f = try Fixture(saved: true, json: #"{"mode":"words","words":201,"showAllLines":false,"funbox":["wikipedia"]}"#,
      fetch: { source, _ in
        reads += 1
        return .init(source: source, title: "Article \(reads)", byline: nil,
          tokens: reads == 1 ? Array(repeating: "ab", count: 100) : ["cd", "ef", "gh"], separator: " ")
      })
    defer { f.close() }
    let legacy = f.settings.snapshot
    f.state.accountReady = true
    f.wait { f.state.page.state.practice?.external != nil && f.inputs().first?.acceptsTextInput == true }
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.state.page.state.session.configuration.wordLimit, 201)
    let attempt = f.state.page.state.session.automaticInputAttemptID
    try XCTUnwrap(f.inputs().first).onInsert("ab ", false)
    f.wait { reads == 2 && f.state.page.state.session.prompt.contains("cd") }
    XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.state.page.state.session.typed, "ab ")
    XCTAssertEqual(f.settings.snapshot, legacy)
    XCTAssertFalse(f.window.isVisible)
  }

  func testLiveThresholdPublicationKeepsProductionInputViewAndAttemptWithoutLegacyWrites() async throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.state.accountReady = true
    try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10}"#, systemIsDark: false)
    try await f.waitAsync { f.state.page.state.practice != nil && f.inputs().first?.acceptsTextInput == true
      && f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
    let legacy = f.settings.snapshot
    let input = try XCTUnwrap(f.inputs().first)
    input.onInsert(String(f.state.page.state.session.prompt.prefix(1)), false)
    XCTAssertFalse(f.state.page.state.session.typed.isEmpty)
    XCTAssertTrue(f.state.page.state.session.hasStarted)
    let attempt = f.state.page.state.session.automaticInputAttemptID
    let typed = f.state.page.state.session.typed, prompt = f.state.page.state.session.prompt
    try await workflow.editAndBegin(.threshold(.accuracyValue(0)),
      replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
    try await f.waitAsync { f.state.page.state.session.configuration.rules.thresholdSource?.configuration.minimumAccuracyMode == .custom }
    XCTAssertTrue(f.inputs().first === input)
    XCTAssertTrue(input.acceptsTextInput)
    XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.state.page.state.session.typed, typed)
    XCTAssertEqual(f.state.page.state.session.prompt, prompt)
    XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertEqual(f.settings.snapshot, legacy)
    XCTAssertFalse(f.window.isVisible)
  }
  func testFinishedWebsiteResultIsVisibleInThePageWithoutShowingAWindow() async throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.state.accountReady = true
    try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    XCTAssertFalse(try f.renderedText().isEmpty, "The actual hidden page must render recognizable text")
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":2,"typingSpeedUnit":"cpm","liveSpeedStyle":"off","liveAccStyle":"off","liveBurstStyle":"off"}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
      && f.inputs().first?.acceptsTextInput == true }
    try XCTUnwrap(f.inputs().first).onInsert(f.state.page.state.session.prompt + " ", false)
    XCTAssertTrue(f.state.page.state.session.isFinished)
    let before = f.state.page.state.session.generationState
    try await Task.sleep(for: .milliseconds(100)); f.host.layoutSubtreeIfNeeded()
    let text = try f.renderedText().joined(separator: " ")
    XCTAssertTrue(text.contains("CPM"), "Actual rendered result: \(text)")
    XCTAssertEqual(f.state.page.state.session.generationState, before)
    XCTAssertNil(f.window.attachedSheet); XCTAssertFalse(f.window.isVisible)
    for command in [AppearanceCommandTarget.speedUnit(.cps), .alwaysShowDecimalPlaces(true), .startGraphsAtZero(false)] {
      try await workflow.editAndBegin(.appearance(command), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
    }
    try await Task.sleep(for: .milliseconds(100))
    let changed = try f.renderedText().joined(separator: " ")
    XCTAssertTrue(changed.contains("CPS"), "Updated rendered result: \(changed)"); XCTAssertFalse(changed.contains("CPM"))
    XCTAssertEqual(f.state.page.state.session.generationState, before)
    let bitmap = try XCTUnwrap(f.host.bitmapImageRepForCachingDisplay(in: f.host.bounds)); f.host.cacheDisplay(in: f.host.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/typebar-finished-result-host.png"))
    let ended = f.state.page.state.session.automaticInputAttemptID, oldInput = try XCTUnwrap(f.inputs().first)
    let staleInsert = oldInput.onInsert
    oldInput.onRestart()
    try await f.waitAsync { f.state.page.state.session.automaticInputAttemptID != ended
      && f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
      && f.inputs().first?.acceptsTextInput == true }
    let next = f.state.page.state.session.generationState
    staleInsert("stale", false)
    XCTAssertEqual(f.state.page.state.session.generationState, next)
    XCTAssertFalse(try f.renderedText().joined(separator: " ").contains("CPS"), "The previous result must leave the new attempt")
  }

  func testFailedAndBailedOutWebsiteAttemptsShowResultsWithoutALivePrompt() async throws {
    for bailout in [false, true] {
      let f = try Fixture(saved: nil); defer { f.close() }
      f.state.accountReady = true; try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
      let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
      let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
      let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
        directory: directory, readWindow: { selection }); defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"time","time":120,"typingSpeedUnit":"cpm","liveSpeedStyle":"off","liveAccStyle":"off","liveBurstStyle":"off"}"#, systemIsDark: false)
      try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
        && f.inputs().first?.acceptsTextInput == true }
      try XCTUnwrap(f.inputs().first).onInsert(String(f.state.page.state.session.prompt.prefix(1)), false)
      var state = f.state.page.state
      XCTAssertTrue(state.session.hasStarted)
      if bailout { state.session.bailOut() } else { state.session.failForTimerHealth() }
      XCTAssertEqual(state.session.outcome, bailout ? .bailedOut : .failed)
      f.state.page.replace(state)
      let before = f.state.page.state.session.generationState
      try await Task.sleep(for: .milliseconds(100))
      let text = try f.renderedText().joined(separator: " ")
      XCTAssertTrue(text.contains("CPM"), "Terminal rendered result: \(text)")
      XCTAssertEqual(f.state.page.state.session.generationState, before)
      XCTAssertNil(f.window.attachedSheet); XCTAssertFalse(f.window.isVisible)
    }
  }
  func testInlineNoStressResultHasRestartButNoWindowDismissControl() throws {
    for closing in [true, false] {
      let view = NoStressResultView(isNewPersonalBest: false, hasZeroSpeedFeedback: false,
        reducesMotion: true, slowTimer: false, accent: .blue, onRestart: {}, allowsClosing: closing)
        .frame(width: 400, height: 380).background(Color(nsColor: .windowBackgroundColor))
      let host = NSHostingView(rootView: view)
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 380), styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = host
      defer { window.contentView = nil; window.close() }
      host.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
      let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
      request.recognitionLanguages = ["zh-Hans", "en-US"]; request.usesLanguageCorrection = false
      try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
      let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
      XCTAssertTrue(text.contains("再来一次"), "No-stress result: \(text)")
      XCTAssertEqual(text.contains("关闭"), closing, "No-stress close control: \(text)")
      XCTAssertFalse(text.contains("CPM")); XCTAssertFalse(window.isVisible)
    }
  }
  func testUnstartedWebsiteFetchFailureKeepsItsReasonAndCanRestartWithoutAResult() async throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.state.accountReady = true; try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }, loadExternal: { _, _, _, _ in
        .init(source: .encyclopedia, initial: .init(text: "ab cd", noSpaceBoundarySource: nil), continuation: nil)
      }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"typingSpeedUnit":"cpm","funbox":["wikipedia"],"liveSpeedStyle":"off","liveAccStyle":"off","liveBurstStyle":"off"}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
      && f.inputs().first?.acceptsTextInput == true }
    var state = f.state.page.state; XCTAssertFalse(state.session.hasStarted)
    state.session.failLiveContentFetch(); XCTAssertEqual(state.session.outcome, .failed)
    XCTAssertNil(state.session.result()); f.state.page.replace(state)
    let ended = state.session.automaticInputAttemptID, before = state.session.generationState
    try await Task.sleep(for: .milliseconds(100))
    let text = try f.renderedText(languages: ["zh-Hans", "en-US"]).joined().replacingOccurrences(of: " ", with: "")
    XCTAssertTrue(text.contains("无法续取在线内容"), "Actual failure reason: \(text)")
    XCTAssertFalse(text.contains("CPM"), "An unstarted failure must not invent a score")
    XCTAssertEqual(f.state.page.state.session.generationState, before)
    try XCTUnwrap(f.inputs().first).onRestart()
    try await f.waitAsync { f.state.page.state.session.automaticInputAttemptID != ended
      && f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
    XCTAssertFalse(f.window.isVisible); XCTAssertNil(f.window.attachedSheet)
  }

  func testInfinitePaceColdStartupAndWarmImportReachTheActualPracticeHost() async throws {
    let f = try Fixture(saved: true, json: #"{"mode":"words","words":100,"paceCaret":"custom","paceCaretCustomSpeed":1e999}"#)
    defer { f.close() }
    f.settings.paceGuideMode = .off
    let legacy = f.settings.snapshot
    let path = try XCTUnwrap(f.record), before = try Data(contentsOf: path)
    f.state.accountReady = true
    try await f.waitAsync { f.state.page.state.presentation?.publication.draft != nil && f.inputs().first?.acceptsTextInput == true }
    XCTAssertEqual(f.state.page.state.presentation?.publication.draft.behavior.paceGuideCustomWpm, 100)
    XCTAssertEqual(f.state.page.state.session.paceCaretTargetWpm, 100)
    XCTAssertNotEqual(try Data(contentsOf: path), before)

    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":100,"paceCaret":"custom","paceCaretCustomSpeed":1e999}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
      && f.inputs().first?.acceptsTextInput == true }
    XCTAssertEqual(f.state.page.state.presentation?.publication.draft.behavior.paceGuideCustomWpm, .infinity)
    XCTAssertEqual(f.state.page.state.session.paceCaretTargetWpm, .infinity)
    let input = try XCTUnwrap(f.inputs().first)
    input.onInsert(String(f.state.page.state.session.prompt.prefix(1)), false)
    XCTAssertNotNil(f.state.page.state.session.paceCaretPendingTicket)
    XCTAssertTrue(f.state.page.state.session.paceCaretIsVisible)
    try await Task.sleep(for: .milliseconds(40)); f.host.layoutSubtreeIfNeeded()
    XCTAssertEqual(f.state.page.state.session.paceCaretTargetWpm, .infinity)
    XCTAssertEqual(f.settings.snapshot, legacy)
    XCTAssertFalse(f.window.isVisible); XCTAssertNil(f.window.attachedSheet)
  }

  func testInfiniteThresholdColdStartupAndWarmCommandsReachActualPracticeHost() async throws {
    var stage = "fixture"
    do {
      let f = try Fixture(saved: true, json: #"{"mode":"words","words":100,"minWpmCustomSpeed":1e999,"minBurstCustomSpeed":1e999}"#)
      defer { f.close() }
      let legacy = f.settings.snapshot, path = try XCTUnwrap(f.record), before = try Data(contentsOf: path)
      f.state.accountReady = true
      stage = "cold startup"
      try await f.waitAsync { f.state.page.state.presentation?.publication.draft != nil && f.inputs().first?.acceptsTextInput == true }
      let cold = try XCTUnwrap(f.state.page.state.presentation).publication.draft.inputRules.rules.thresholdSource?.configuration
      XCTAssertEqual(cold?.minimumWpmCustomValue, 100); XCTAssertEqual(cold?.minimumWordBurstCustomValue, 100)
      XCTAssertNotEqual(try Data(contentsOf: path), before)
      let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
      let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
      let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
        directory: directory, readWindow: { selection }); defer { workflow.stop() }
      stage = "warm import"
      try await workflow.apply(json: #"{"mode":"words","words":100,"minWpmCustomSpeed":1e999,"minBurstCustomSpeed":1e999}"#, systemIsDark: false)
      try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
        && f.inputs().first?.acceptsTextInput == true }
      let warm = f.state.page.state.session.configuration.rules.thresholdSource?.configuration
      XCTAssertEqual(warm?.minimumWpmCustomValue, .infinity); XCTAssertEqual(warm?.minimumWordBurstCustomValue, .infinity)
      stage = "live commands"
      let input = try XCTUnwrap(f.inputs().first)
      input.onInsert(String(f.state.page.state.session.prompt.prefix(1)), false)
      input.setMarkedText("é", selectedRange: .init(location: 1, length: 0), replacementRange: .init(location: NSNotFound, length: 0))
      let marked = input.markedRange(), generation = f.state.page.state.session.generationState
      var id = try XCTUnwrap(f.state.page.state.presentation).publication.applicationID
      let speed = try workflow.runThresholdCommand(.minimumWpmCustom, input: "Infinity", replacing: id)
      XCTAssertEqual(speed.acceptedSetters, 1); XCTAssertTrue(speed.rejectedKeys.isEmpty)
      XCTAssertEqual(f.state.page.state.session.configuration.rules.minimumWpm, .infinity)
      id = try XCTUnwrap(f.state.page.state.presentation).publication.applicationID
      let burst = try workflow.runThresholdCommand(.minimumWordBurst(.flex), input: String(repeating: "9", count: 400), replacing: id)
      XCTAssertEqual(burst.acceptedSetters, 2); XCTAssertTrue(burst.rejectedKeys.isEmpty)
      XCTAssertEqual(f.state.page.state.session.configuration.rules.minimumWordBurstWpm, .infinity)
      XCTAssertEqual(f.state.page.state.session.configuration.rules.minimumWordBurstMode, .flex)
      let saved = try WebsiteConfigFileRegister(directory: directory).read()
      guard case .available(let values) = saved.state else { return XCTFail("Expected actual file record") }
      XCTAssertEqual(values["minWpmCustomSpeed"], .number(.infinity))
      XCTAssertEqual(values["minBurstCustomSpeed"], .number(.infinity))
      var expectedConfiguration = generation.configuration
      expectedConfiguration.rules.minimumWpm = .infinity
      expectedConfiguration.rules.minimumWordBurstWpm = .infinity
      expectedConfiguration.rules.minimumWordBurstMode = .flex
      expectedConfiguration.rules.thresholdSource = .init(configuration: try .init(
        websiteMinimumWpmMode: .custom, speed: .infinity, accuracyMode: .off, accuracy: 90,
        burstMode: .flex, burst: .infinity))
      XCTAssertEqual(f.state.page.state.session.generationState, .init(
        attempt: generation.attempt, target: generation.target, events: generation.events, attempts: generation.attempts,
        started: generation.started, finished: generation.finished, configuration: expectedConfiguration,
        scores: generation.scores, decoration: generation.decoration, typed: generation.typed))
      XCTAssertTrue(f.inputs().first === input); XCTAssertTrue(input.hasMarkedText()); XCTAssertEqual(input.markedRange(), marked)
      XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 0)
      XCTAssertEqual(f.settings.snapshot, legacy); XCTAssertFalse(f.window.isVisible); XCTAssertNil(f.window.attachedSheet)
    } catch { XCTFail("Threshold host \(stage): \(String(reflecting: error))") }
  }

  func testProfileKeyboardIsRenderedWhenLegacyGuideIsOff() async throws {
    let f = try Fixture(saved: true, json: #"{"mode":"words","words":10,"keymapMode":"static","keymapLegendStyle":"uppercase","keymapKeys":"full","keymapSize":1.5,"keymapLayout":"qwerty"}"#)
    defer { f.close() }
    f.settings.keyboardGuideMode = .off
    f.settings.keyboardGuideLegendStyle = .blank
    let custom = CustomKeyboardGuideLayout(name: "Legacy rows must stay dormant", numberRow: "1111111111",
      topRow: "aaaaaaaaaa", homeRow: "aaaaaaaaa", bottomRow: "aaaaaaa")
    f.settings.customKeyboardLayouts = [custom]; f.settings.customKeyboardLayoutID = custom.id
    f.settings.keyboardGuideLayoutSource = .custom
    let legacy = f.settings.snapshot
    f.state.accountReady = true
    try await f.waitAsync { f.state.page.state.presentation?.publication.draft != nil && f.inputs().first?.acceptsTextInput == true }
    func scrolls(_ view: NSView) -> [NSScrollView] {
      (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrolls($0) }
    }
    func scrollToEnd() {
      for scroll in scrolls(f.host) {
        guard let document = scroll.documentView, document.frame.height > scroll.contentView.bounds.height else { continue }
        let clip = scroll.contentView
        clip.scroll(to: clip.constrainBoundsRect(.init(x: 0, y: document.frame.height, width: clip.bounds.width, height: clip.bounds.height)).origin)
        scroll.reflectScrolledClipView(clip)
      }
    }
    scrollToEnd()
    try await Task.sleep(for: .milliseconds(100)); f.host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(f.host.bitmapImageRepForCachingDisplay(in: f.host.bounds))
    f.host.cacheDisplay(in: f.host.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/typebar-profile-keyboard-host.png"))
    // Individual keycaps are separate text regions, not a single text line.
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .fast; request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false; request.minimumTextHeight = 0.005
    request.regionOfInterest = .init(x: 0.1, y: 0.2, width: 0.8, height: 0.31)
    try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
    let keycaps = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    XCTAssertTrue(keycaps.contains("Esc"), "Keyboard region: \(keycaps)")
    request.recognitionLevel = .accurate
    // At native resolution Vision omitted visible 15px key legends in the
    // saved full-suite raster. Crop the same row and resample it at 2x before
    // detection; keep exact QWERTY and Dvorak order assertions below.
    func recognizedLegends(_ bitmap: NSBitmapImageRep, region: CGRect) throws -> String {
      let original = try XCTUnwrap(bitmap.cgImage)
      let crop = try XCTUnwrap(original.cropping(to: .init(
        x: region.minX * CGFloat(original.width), y: (1 - region.maxY) * CGFloat(original.height),
        width: region.width * CGFloat(original.width), height: region.height * CGFloat(original.height))))
      let context = try XCTUnwrap(CGContext(data: nil, width: crop.width * 2, height: crop.height * 2,
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.interpolationQuality = .high
      context.draw(crop, in: .init(x: 0, y: 0, width: context.width, height: context.height))
      let detector = VNRecognizeTextRequest()
      detector.recognitionLevel = .accurate; detector.recognitionLanguages = ["en-US"]
      detector.usesLanguageCorrection = false
      try VNImageRequestHandler(cgImage: XCTUnwrap(context.makeImage())).perform([detector])
      return (detector.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
    }
    let legends = try recognizedLegends(bitmap, region: .init(x: 0.23, y: 0.38, width: 0.23, height: 0.06))
    XCTAssertEqual(legends.replacingOccurrences(of: " ", with: ""), "QWERT", "Published QWERTY, not legacy custom rows: \(legends)")
    // Calibrate four complete letter keys in the same region in both layouts.
    // Exclude Dvorak's leading punctuation and the following key at the edge.
    let calibrationRegion = CGRect(x: 0.37, y: 0.38, width: 0.20, height: 0.06)
    let calibration = try recognizedLegends(bitmap, region: calibrationRegion)
    XCTAssertEqual(calibration.replacingOccurrences(of: " ", with: ""), "RTYU", "QWERTY calibration: \(calibration)")
    request.regionOfInterest = .init(x: 0.1, y: 0.2, width: 0.8, height: 0.31)
    XCTAssertEqual(f.settings.snapshot, legacy)
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    // Exercise the same detector against an actual alternate published layout;
    // a passing QWERTY crop must not simply reflect dormant legacy settings.
    try await workflow.apply(json: #"{"mode":"words","words":10,"keymapMode":"static","keymapLegendStyle":"uppercase","keymapKeys":"full","keymapSize":1.5,"keymapLayout":"dvorak"}"#, systemIsDark: false)
    try await f.waitAsync { f.state.page.state.presentation?.publication.draft.keyboardTypography.guideLayout == .ansiDvorak
      && f.inputs().first?.acceptsTextInput == true }
    scrollToEnd(); try await Task.sleep(for: .milliseconds(100)); f.host.layoutSubtreeIfNeeded()
    let alternate = try XCTUnwrap(f.host.bitmapImageRepForCachingDisplay(in: f.host.bounds))
    f.host.cacheDisplay(in: f.host.bounds, to: alternate)
    try XCTUnwrap(alternate.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/typebar-profile-keyboard-dvorak-host.png"))
    let alternateLegends = try recognizedLegends(alternate, region: calibrationRegion)
    XCTAssertFalse(alternateLegends.contains("Q") || alternateLegends.contains("W"), "Dvorak first keys: \(alternateLegends)")
    XCTAssertEqual(alternateLegends.replacingOccurrences(of: " ", with: ""), "PYFG",
      "Actual Dvorak letter order: \(alternateLegends)")
    XCTAssertEqual(f.settings.snapshot, legacy)
    request.regionOfInterest = .init(x: 0.1, y: 0.2, width: 0.8, height: 0.31)
    try await workflow.apply(json: #"{"mode":"words","words":10,"keymapMode":"off"}"#, systemIsDark: false)
    try await f.waitAsync { f.state.page.state.presentation?.publication.draft.keyboardTypography.guideMode == .off
      && f.inputs().first?.acceptsTextInput == true }
    f.settings.keyboardGuideMode = .next
    let enabledLegacy = f.settings.snapshot
    scrollToEnd(); try await Task.sleep(for: .milliseconds(100)); f.host.layoutSubtreeIfNeeded()
    let off = try XCTUnwrap(f.host.bitmapImageRepForCachingDisplay(in: f.host.bounds))
    f.host.cacheDisplay(in: f.host.bounds, to: off)
    try VNImageRequestHandler(cgImage: XCTUnwrap(off.cgImage)).perform([request])
    let offKeycaps = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    XCTAssertFalse(offKeycaps.contains("Esc"), "Disabled keyboard region: \(offKeycaps)")
    try await workflow.apply(json: #"{"mode":"words","words":10,"funbox":["simon_says"],"keymapSize":1.5,"keymapKeys":"full","keymapLegendStyle":"uppercase"}"#, systemIsDark: false)
    XCTAssertEqual(f.state.page.state.presentation?.publication.draft.keyboardTypography.guideMode, .next)
    XCTAssertTrue(f.state.page.state.session.configuration.modifiers.contains(.simonSays))
    try await workflow.editAndBegin(.keymap(.display(.mode(.off))), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(f.state.page.state.presentation?.publication.draft.keyboardTypography.guideMode, .off)
    scrollToEnd(); try await Task.sleep(for: .milliseconds(100)); f.host.layoutSubtreeIfNeeded()
    let simon = try XCTUnwrap(f.host.bitmapImageRepForCachingDisplay(in: f.host.bounds))
    scrollToEnd(); try await Task.sleep(for: .milliseconds(50)); f.host.layoutSubtreeIfNeeded()
    f.host.cacheDisplay(in: f.host.bounds, to: simon)
    try XCTUnwrap(simon.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/typebar-keymap-simon-host.png"))
    request.recognitionLevel = .fast
    try VNImageRequestHandler(cgImage: XCTUnwrap(simon.cgImage)).perform([request])
    let simonKeys = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    XCTAssertFalse(simonKeys.contains("Esc"), "Saved off must override Simon's initial next mode: \(simonKeys)")
    XCTAssertEqual(f.settings.snapshot, enabledLegacy)
    XCTAssertFalse(f.window.isVisible); XCTAssertNil(f.window.attachedSheet)
  }

  func testPublishedCapsLockEventsReachNormalAndMirroredPracticeWithoutDoubleTransformation() async throws {
    for mirrored in [false, true] {
      let json = mirrored
        ? #"{"mode":"words","words":10,"layout":"qwerty","funbox":["layout_mirror"]}"#
        : #"{"mode":"words","words":10,"layout":"qwerty"}"#
      let f = try Fixture(saved: true, json: json); defer { f.close() }
      f.state.accountReady = true
      try await f.waitAsync { f.state.page.state.presentation != nil && f.inputs().first?.acceptsTextInput == true }
      let input = try XCTUnwrap(f.inputs().first), attempt = f.state.page.state.session.automaticInputAttemptID
      let keys: [(UInt16, String, String)] = mirrored
        ? [(12, "q", "Pp"), (0, "a", ";:")]
        : [(0, "a", "Aa"), (21, "4", "$4"), (19, "2", "2@")]
      var expected = ""
      for (code, logical, outputs) in keys {
        for (shift, output) in zip([false, true], outputs) {
          let flags: NSEvent.ModifierFlags = shift ? [.capsLock, .shift] : [.capsLock]
          input.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: f.window.windowNumber, context: nil, characters: logical, charactersIgnoringModifiers: logical, isARepeat: false, keyCode: code)))
          expected.append(output)
          XCTAssertEqual(f.state.page.state.session.typed, expected)
          XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
        }
      }
      XCTAssertFalse(f.window.isVisible)
    }
  }

  func testPublishedMirrorShiftComparisonUsesMirroredVisualLayoutAndSyncPhysicalSide() async throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.state.accountReady = true; try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"layout":"qwerty","funbox":["layout_mirror","no_quit"],"oppositeShiftMode":"keymap"}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID && f.inputs().first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.inputs().first), attempt = f.state.page.state.session.automaticInputAttemptID
    input.onInsert("x", false)
    try await f.waitAsync { !f.settings.allowsRestartingConfigurationChange }
    try await Task.sleep(for: .milliseconds(20)); f.host.layoutSubtreeIfNeeded()
    input.flagsChanged(with: try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [.shift], timestamp: 0,
      windowNumber: f.window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56)))
    let p = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0,
      windowNumber: f.window.windowNumber, context: nil, characters: "P", charactersIgnoringModifiers: "p", isARepeat: false, keyCode: 35))
    var flags: [Bool] = [], texts: [String] = []
    input.onInsert = { texts.append($0); flags.append($1) }
    for (layout, expected) in [(KeyboardGuideLayoutCommandTarget.builtIn(.ansiDvorak), false), (.builtIn(.ansiQwerty), true), (.inputSync, false)] {
      try await workflow.editAndBegin(.keymap(.layout(layout)), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
      input.keyDown(with: p); XCTAssertEqual(flags.last, expected)
    }
    XCTAssertEqual(flags.count, 3); XCTAssertEqual(texts, ["Q", "Q", "Q"])
    XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt); XCTAssertFalse(f.window.isVisible)
  }

  func testPublishedMirrorUsesTheSelectedPhysicalLayoutRatherThanASCIISubstitution() async throws {
    for (layout, expected) in [("qwerty", ";"), ("dvorak", "s")] {
      let f = try Fixture(saved: true, json: "{\"mode\":\"words\",\"words\":10,\"layout\":\"\(layout)\",\"funbox\":[\"layout_mirror\"]}")
      defer { f.close() }
      f.state.accountReady = true
      try await f.waitAsync { f.state.page.state.presentation != nil && f.inputs().first?.acceptsTextInput == true }
      let input = try XCTUnwrap(f.inputs().first), attempt = f.state.page.state.session.automaticInputAttemptID
      input.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: f.window.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)))
      XCTAssertEqual(f.state.page.state.session.typed, expected, layout)
      XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertFalse(f.window.isVisible)
    }
  }

  func testLayoutFluidOppositeShiftUsesCurrentVisualLayoutAndModeWithoutWaitingForAFrame() async throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.state.accountReady = true; try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"time","time":120,"funbox":["layoutfluid","no_quit"],"customLayoutfluid":["qwerty","dvorak"],"oppositeShiftMode":"keymap"}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID && f.inputs().first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.inputs().first), attempt = f.state.page.state.session.automaticInputAttemptID
    input.onInsert("x", false)
    try await f.waitAsync { !f.settings.allowsRestartingConfigurationChange }
    try await Task.sleep(for: .milliseconds(20)); f.host.layoutSubtreeIfNeeded()
    let shift = try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: [.shift], timestamp: 0,
      windowNumber: f.window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56))
    input.flagsChanged(with: shift)
    let p = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0,
      windowNumber: f.window.windowNumber, context: nil, characters: "P", charactersIgnoringModifiers: "p", isARepeat: false, keyCode: 35))
    var errors: [Bool] = [], inserted: [String] = []
    input.onInsert = { inserted.append($0); errors.append($1) }
    input.keyDown(with: p); XCTAssertEqual(errors, [false])
    try workflow.advanceLayoutFluid(.time(61), attemptID: attempt)
    input.keyDown(with: p); XCTAssertEqual(errors.last, true, "Dvorak places P on the left, so left Shift must fail immediately")
    try await Task.sleep(for: .milliseconds(20)); f.host.layoutSubtreeIfNeeded()
    input.onInsert = { inserted.append($0); errors.append($1) }
    input.keyDown(with: p); XCTAssertEqual(errors.last, true, "Fluid must not force physical-side comparison after a frame either")
    try await workflow.editAndBegin(.keymap(.layout(.inputSync)), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
    input.keyDown(with: p); XCTAssertEqual(errors.last, false, "Sync uses physical P on the right")
    try await workflow.editAndBegin(.keymap(.layout(.builtIn(.ansiDvorak))), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
    input.keyDown(with: p); XCTAssertEqual(errors.last, true)
    try await workflow.editAndBegin(.inputRule(.oppositeShiftMode(.off)), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
    input.keyDown(with: p); XCTAssertEqual(errors.last, false, "Off must take effect without waiting for the next frame")
    XCTAssertEqual(inserted.count, 6); XCTAssertTrue(inserted.allSatisfy { $0 == "P" })
    XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt); XCTAssertFalse(f.window.isVisible)
  }

  func testLayoutFluidMappingIsCurrentBeforeSwiftUIUpdatesTheNativeInput() async throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.state.accountReady = true; try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"time","time":10,"funbox":["layoutfluid"],"customLayoutfluid":["qwerty","colemak","dvorak"]}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID && f.inputs().first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.inputs().first), attempt = f.state.page.state.session.automaticInputAttemptID
    input.onInsert("x", false)
    try await Task.sleep(for: .milliseconds(20)); f.host.layoutSubtreeIfNeeded()
    XCTAssertEqual(input.keyboardInputMapping, .builtIn(.ansiQwerty))
    let before = f.state.page.state.session.typed
    try workflow.advanceLayoutFluid(.time(4), attemptID: attempt)
    // Deliberately no yield/layout between publication and the physical event.
    let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: f.window.windowNumber, context: nil, characters: "e", charactersIgnoringModifiers: "e", isARepeat: false, keyCode: 14))
    input.keyDown(with: key)
    XCTAssertEqual(f.state.page.state.session.typed, before + "f", "The Colemak mapping must be read at event delivery, not a later view update")
    XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertFalse(f.window.isVisible)
  }

  func testLayoutFluidWordBoundaryKeepsNoQuitInputWhileChangingVisualLayout() async throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.state.accountReady = true; try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"funbox":["layoutfluid","no_quit"],"customLayoutfluid":["qwerty","colemak","dvorak"],"keymapSize":1.5,"keymapLegendStyle":"uppercase","keymapKeys":"full"}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID && f.inputs().first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.inputs().first), attempt = f.state.page.state.session.automaticInputAttemptID
    let legacy = f.settings.snapshot
    let prefix = f.state.page.state.session.prompt.split(separator: " ").prefix(3).joined(separator: " ") + " "
    input.onInsert(prefix, false)
    try await f.waitAsync { f.state.page.state.presentation?.publication.draft.keyboardTypography.guideLayout == .ansiColemak }
    XCTAssertEqual(f.state.page.state.session.completedWordCount, 3)
    XCTAssertEqual(f.state.page.state.presentation?.publication.draft.keyboardTypography.inputLayout.emulatedLayout, .ansiQwerty)
    XCTAssertTrue(f.inputs().first === input); XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
    let before = f.state.page.state.session.typed
    let key = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: f.window.windowNumber, context: nil, characters: "e", charactersIgnoringModifiers: "e", isARepeat: false, keyCode: 14))
    input.keyDown(with: key)
    XCTAssertEqual(f.state.page.state.session.typed, before + "e", "Visual Colemak must not change refused physical QWERTY")
    XCTAssertEqual(f.settings.snapshot, legacy); XCTAssertFalse(f.window.isVisible)
  }

  func testKeymapCommandsPreserveActualMarkedInputAndNoQuitAttempt() async throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.state.accountReady = true; try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"layout":"colemak","funbox":["no_quit"]}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID && f.inputs().first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.inputs().first), legacy = f.settings.snapshot
    input.onInsert(String(f.state.page.state.session.prompt.prefix(1)), false)
    try await f.waitAsync { !f.settings.allowsRestartingConfigurationChange }
    try await Task.sleep(for: .milliseconds(20)); f.host.layoutSubtreeIfNeeded()
    input.setMarkedText("é", selectedRange: .init(location: 1, length: 0), replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertTrue(input.hasMarkedText())
    let marked = input.markedRange(), before = f.state.page.state.session.generationState
    let targets: [WebsiteKeymapCommandTarget] = [.display(.style(.matrix)), .display(.legend(.uppercase)),
      .display(.keys(.full)), .size(1.5), .display(.mode(.next)), .layout(.builtIn(.ansiDvorak)), .layout(.inputSync)]
    for target in targets {
      try await workflow.editAndBegin(.keymap(target), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
      try await Task.sleep(for: .milliseconds(20)); f.host.layoutSubtreeIfNeeded()
      XCTAssertTrue(f.inputs().first === input); XCTAssertTrue(input.hasMarkedText()); XCTAssertEqual(input.markedRange(), marked)
      XCTAssertEqual(f.state.page.state.session.generationState, before)
      XCTAssertEqual(f.inputs().first?.insertionAttemptID, before.attempt)
    }
    XCTAssertEqual(f.settings.snapshot, legacy); XCTAssertFalse(f.window.isVisible); XCTAssertNil(f.window.attachedSheet)
  }

  func testAppearanceCommandsKeepActualMarkedInputAndRenderTheProfileHUD() async throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.state.accountReady = true; try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"],"monkey":true,"showAllLines":true,"theme":"dracula"}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
      && f.inputs().first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.inputs().first), legacy = f.settings.snapshot
    input.onInsert(String(f.state.page.state.session.prompt.prefix(1)), false)
    try await f.waitAsync { !f.settings.allowsRestartingConfigurationChange }
    try await Task.sleep(for: .milliseconds(20)); f.host.layoutSubtreeIfNeeded()
    XCTAssertFalse(f.state.page.state.session.typed.isEmpty, "The actual attempt must have started")
    input.setMarkedText("é", selectedRange: .init(location: 1, length: 0), replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertTrue(input.hasMarkedText(), "Initial marked input must be installed before any command")
    let marked = input.markedRange(), before = f.state.page.state.session.generationState
    for command in [AppearanceCommandTarget.speed(.text), .accuracy(.mini), .burst(.mini), .speedUnit(.cps), .progress(.text),
      .color(.accent), .opacity(.full), .tape(.word), .typedEffect(.hide), .highlight(.word), .smoothLineScroll(true)] {
      do {
        try await workflow.editAndBegin(.appearance(command), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
      } catch { return XCTFail("Appearance command failed: \(String(reflecting: error))") }
      try await Task.sleep(for: .milliseconds(20)); f.host.layoutSubtreeIfNeeded()
      XCTAssertTrue(f.inputs().first === input, "Input identity after \(command)")
      XCTAssertTrue(input.hasMarkedText(), "Marked input after \(command)")
    }
    try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    XCTAssertTrue(f.inputs().first === input, "Final input identity")
    XCTAssertTrue(input.hasMarkedText(), "Final marked input"); XCTAssertEqual(input.markedRange(), marked)
    XCTAssertEqual(f.state.page.state.session.generationState, before); XCTAssertEqual(f.settings.snapshot, legacy)
    f.window.appearance = NSAppearance(named: .darkAqua)
    try f.scrollToInput()
    try await Task.sleep(for: .milliseconds(50))
    f.host.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(f.host.bitmapImageRepForCachingDisplay(in: f.host.bounds)); f.host.cacheDisplay(in: f.host.bounds, to: bitmap)
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/typebar-appearance-live-host.png"))
    XCTAssertFalse(f.window.isVisible)
  }
  func testFinishedProfileAppearanceUpdatesResultSettingsWithoutChangingScoring() async throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.state.accountReady = true; try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":2}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
    try XCTUnwrap(f.inputs().first).onInsert(f.state.page.state.session.prompt + " ", false)
    XCTAssertTrue(f.state.page.state.session.isFinished)
    let before = f.state.page.state.session.generationState, legacy = f.settings.snapshot
    for command in [AppearanceCommandTarget.speedUnit(.cpm), .alwaysShowDecimalPlaces(true), .startGraphsAtZero(false)] {
      try await workflow.editAndBegin(.appearance(command), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
    }
    let draft = try XCTUnwrap(f.state.page.state.presentation).publication.draft
    let display = PracticeAppearanceSelection(draft: draft, settings: f.settings)
    XCTAssertEqual(display.unit, .cpm); XCTAssertTrue(display.alwaysShowDecimalPlaces); XCTAssertFalse(display.startGraphsAtZero)
    XCTAssertEqual(f.state.page.state.session.generationState, before); XCTAssertEqual(f.settings.snapshot, legacy)
    // Scoring invariants are separate from the rendered-page checks above.
    XCTAssertFalse(f.window.isVisible)
  }

  func testPaceCustomCommandRestartsNormallyButKeepsActualMarkedInputDuringNoQuit() async throws {
    for (noQuit, raw, target) in [(false, "120", 120.0), (true, "120", 120.0),
      (false, "Infinity", Double.infinity), (true, "Infinity", Double.infinity)] {
      let f = try Fixture(saved: nil); defer { f.close() }
      f.state.accountReady = true
      try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
      let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
      let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
      let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
        directory: directory, readWindow: { selection }); defer { workflow.stop() }
      let json = noQuit
        ? #"{"mode":"words","words":10,"funbox":["no_quit"],"paceCaret":"off","paceCaretCustomSpeed":80}"#
        : #"{"mode":"words","words":10,"paceCaret":"off","paceCaretCustomSpeed":80}"#
      try await workflow.apply(json: json, systemIsDark: false)
      try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
      let input = try XCTUnwrap(f.inputs().first), legacy = f.settings.snapshot
      input.onInsert("x", false)
      XCTAssertEqual(f.state.page.state.session.typed, "x")
      if noQuit { try await f.waitAsync { !f.settings.allowsRestartingConfigurationChange } }
      input.setMarkedText("é", selectedRange: .init(location: 1, length: 0), replacementRange: .init(location: NSNotFound, length: 0))
      let marked = input.markedRange(), attempt = f.state.page.state.session.automaticInputAttemptID
      do {
        try await workflow.runPaceCommand(.customSpeed, input: raw, replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID)
      } catch { return XCTFail("Pace command failed: \(String(reflecting: error))") }
      if noQuit {
        try await f.waitAsync { f.state.page.state.session.paceCaretTargetWpm == 80 }
        XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
        XCTAssertEqual(f.state.page.state.session.typed, "x")
        XCTAssertTrue(f.inputs().first === input); XCTAssertTrue(input.hasMarkedText()); XCTAssertEqual(input.markedRange(), marked)
        XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 0)
      } else {
        try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
          && f.state.page.state.session.paceCaretTargetWpm == target }
        XCTAssertNotEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
        XCTAssertTrue(f.state.page.state.session.typed.isEmpty)
        XCTAssertFalse(try XCTUnwrap(f.inputs().first).hasMarkedText())
        XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 1)
      }
      XCTAssertEqual(f.settings.snapshot, legacy); XCTAssertFalse(f.window.isVisible)
    }
  }

  func testProfileSoundIsUsedByActualInputAndLiveVolumeWithoutAudibleDevices() async throws {
    let trace = SoundRecordingTrace(), parent = trace.player()
    let f = try Fixture(saved: nil, feedbackSound: parent); defer { f.close() }
    f.state.accountReady = true
    try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    f.settings.soundVolume = 0.9
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"],"soundVolume":0.2,"playSoundOnClick":"1","playSoundOnError":"1"}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
    let input = try XCTUnwrap(f.inputs().first), legacy = f.settings.snapshot
    input.onInsert(String(f.state.page.state.session.prompt.prefix(1)), false)
    XCTAssertEqual(trace.events.count, 1); XCTAssertEqual(trace.events.last?.volume, 0.2)
    let voice = try XCTUnwrap(trace.voices.last?.value)
    try await f.waitAsync { !f.settings.allowsRestartingConfigurationChange }
    let before = f.state.page.state.session.generationState
    do { try await workflow.editAndBegin(.sound(.volume(0.4)), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false) }
    catch { return XCTFail("Sound volume failed: \(String(reflecting: error))") }
    try await f.waitAsync { voice.volume == 0.4 }
    XCTAssertEqual(trace.events.count, 1, "Saving volume does not preview")
    XCTAssertEqual(f.state.page.state.session.generationState, before); XCTAssertTrue(f.inputs().first === input)
    XCTAssertEqual(f.settings.snapshot, legacy); XCTAssertEqual(trace.beeps, 0); XCTAssertFalse(f.window.isVisible)
  }

  func testLiveCaretCommandsKeepActualInputDuringNoQuit() async throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.state.accountReady = true
    try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
    let input = try XCTUnwrap(f.inputs().first), legacy = f.settings.snapshot
    input.onInsert(String(f.state.page.state.session.prompt.prefix(1)), false)
    XCTAssertFalse(f.state.page.state.session.typed.isEmpty)
    try await f.waitAsync { !f.settings.allowsRestartingConfigurationChange }
    let before = f.state.page.state.session.generationState
    for command in [CaretCommandTarget.primary(.block), .smooth(.fast), .pace(.underline), .repeatedPace(false), .primary(.off)] {
      do {
        try await workflow.editAndBegin(.caret(command), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
      } catch { return XCTFail("Caret command failed: \(String(reflecting: error))") }
      try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
      XCTAssertTrue(f.inputs().first === input)
      XCTAssertEqual(f.state.page.state.session.generationState, before)
    }
    XCTAssertEqual(f.settings.snapshot, legacy); XCTAssertFalse(f.window.isVisible)
  }

  func testInputCommandsKeepActualMarkedInputAndControlsWithAndWithoutNoQuit() async throws {
    for noQuit in [false, true] {
      let f = try Fixture(saved: nil); defer { f.close() }
      f.state.accountReady = true
      try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
      let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
      let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
      let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
        directory: directory, readWindow: { selection })
      defer { workflow.stop() }
      try await workflow.apply(json: noQuit ? #"{"mode":"words","words":10,"funbox":["no_quit"]}"# : #"{"mode":"words","words":10}"#, systemIsDark: false)
      try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
      let input = try XCTUnwrap(f.inputs().first), legacy = f.settings.snapshot
      input.onInsert("x", false)
      if noQuit { try await f.waitAsync { !f.settings.allowsRestartingConfigurationChange } }
      input.setMarkedText("é", selectedRange: .init(location: 1, length: 0), replacementRange: .init(location: NSNotFound, length: 0))
      let marked = input.markedRange(), before = f.state.page.state.session.generationState
      XCTAssertTrue(input.hasMarkedText())
      for target in [InputRuleCommandTarget.freedomMode(true), .deleteOnError(.letter), .confidenceMode(.on),
        .hideExtraLetters(true), .indicateTypos(.both), .compositionDisplay(.below)] {
        do {
          try await workflow.editAndBegin(.inputRule(target), replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
        } catch { return XCTFail("Input command failed: \(String(reflecting: error))") }
      }
      try await f.waitAsync { f.inputs().first?.compositionDisplayStyle == .below }
      XCTAssertTrue(f.inputs().first === input); XCTAssertTrue(input.acceptsTextInput)
      XCTAssertTrue(input.hasMarkedText()); XCTAssertEqual(input.markedRange(), marked)
      XCTAssertEqual(f.state.page.state.session.typed, "x")
      XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, before.attempt)
      XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 0)
      XCTAssertEqual(f.settings.snapshot, legacy); XCTAssertFalse(f.window.isVisible)
    }
  }

  func testActualNoQuitLockKeepsThresholdRefusalsAndBothBurstNotices() async throws {
    let f = try Fixture(saved: nil); defer { f.close(); f.account.localNotices.clearAll() }
    f.state.accountReady = true
    try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
    try XCTUnwrap(f.inputs().first).onInsert("x", false)
    try await f.waitAsync { !f.settings.allowsRestartingConfigurationChange }
    let before = f.state.page.state.session.generationState
    let id = try XCTUnwrap(f.state.page.state.presentation).publication.applicationID
    let revision = try WebsiteConfigFileRegister(directory: directory).read().revision
    let count = f.account.localNotices.history.count
    XCTAssertThrowsError(try workflow.runThresholdCommand(.minimumWpmCustom, input: "-1", replacing: id)) {
      guard case WebsiteThresholdCommandError.invalidInput = $0 else { return XCTFail("Unexpected input error: \($0)") }
    }
    XCTAssertEqual(f.account.localNotices.history.count, count, "Prevalidation must run before No Quit setters")
    let receipt: WebsiteThresholdCommandReceipt
    do { receipt = try workflow.runThresholdCommand(.minimumWordBurst(.flex), input: "73tail", replacing: id) }
    catch { return XCTFail("Threshold refused before its setters: \(String(reflecting: error))") }
    XCTAssertEqual(receipt.rejectedKeys, ["minBurst", "minBurstCustomSpeed"])
    XCTAssertEqual(f.account.localNotices.history.count - count, 2)
    XCTAssertTrue(f.account.localNotices.active.allSatisfy(\.important))
    do {
      try await workflow.editAndBegin(.threshold(.accuracyValue(91.5)), replacing: id, systemIsDark: false)
      XCTFail("Threshold saved under No Quit")
    } catch WebsiteConfigNativeDraftError.rejectedEdit {}
    XCTAssertEqual(f.account.localNotices.history.count - count, 3)
    let infiniteSpeed = try workflow.runThresholdCommand(.minimumWpmCustom, input: "Infinity", replacing: id)
    XCTAssertEqual(infiniteSpeed.rejectedKeys, ["minWpmCustomSpeed"])
    let infiniteBurst = try workflow.runThresholdCommand(.minimumWordBurst(.fixed),
      input: String(repeating: "9", count: 400), replacing: id)
    XCTAssertEqual(infiniteBurst.rejectedKeys, ["minBurst", "minBurstCustomSpeed"])
    XCTAssertEqual(f.account.localNotices.history.count - count, 6)
    XCTAssertEqual(f.state.page.state.session.generationState, before)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: directory).read().revision, revision)
    XCTAssertFalse(f.window.isVisible)
  }

  func testActualNoQuitLockSavesFuturePolyglotButRefusesLayoutfluid() async throws {
    let f = try Fixture(saved: nil); defer { f.close(); f.account.localNotices.clearAll() }
    f.state.accountReady = true
    try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
    let input = try XCTUnwrap(f.inputs().first)
    input.onInsert("x", false)
    try await f.waitAsync { !f.settings.allowsRestartingConfigurationChange }
    let before = f.state.page.state.session.generationState
    let old = try XCTUnwrap(f.state.page.state.presentation).publication.applicationID
    let count = f.account.localNotices.history.count
    do { try await workflow.editAndBegin(.polyglotLanguages(["german", "spanish"]), replacing: old, systemIsDark: false) }
    catch { return XCTFail("Future Polyglot save refused: \(String(reflecting: error))") }
    let current = try XCTUnwrap(f.state.page.state.presentation).publication
    XCTAssertNotEqual(current.applicationID, old)
    XCTAssertEqual(current.draft.generators.polyglotLanguages, [.german, .spanish])
    XCTAssertEqual(f.account.localNotices.history.count - count, 1)
    let revision = try WebsiteConfigFileRegister(directory: directory).read().revision
    do {
      try await workflow.editAndBegin(.layoutFluidLayouts(["colemak", "qwerty"]), replacing: current.applicationID, systemIsDark: false)
      XCTFail("Layoutfluid saved under No Quit")
    } catch WebsiteConfigNativeDraftError.rejectedEdit {}
    XCTAssertEqual(f.account.localNotices.history.count - count, 2)
    XCTAssertTrue(f.account.localNotices.active.allSatisfy(\.important))
    XCTAssertEqual(f.state.page.state.session.generationState, before)
    XCTAssertTrue(f.inputs().first === input); XCTAssertFalse(f.window.isVisible)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: directory).read().revision, revision)
    do {
      try await workflow.editAndBegin(.polyglotLanguages(["english", "english"]), replacing: current.applicationID, systemIsDark: false)
      XCTFail("Duplicate-only list saved")
    } catch WebsiteConfigImportWorkflowError.rejectedRestartFailed {}
    XCTAssertEqual(f.account.localNotices.history.count - count, 3)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: directory).read().revision, revision)
    XCTAssertEqual(f.state.page.state.session.generationState, before)
  }

  func testLiveBehaviorKeepsActualInputAndUpdatesItsQuickRestartKeyDuringNoQuit() async throws {
    let f = try Fixture(saved: nil); defer { f.close() }
    f.state.accountReady = true
    try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":10,"funbox":["no_quit"]}"#, systemIsDark: false)
    try await f.waitAsync { f.state.page.state.practice != nil && f.inputs().first?.acceptsTextInput == true
      && f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
    let input = try XCTUnwrap(f.inputs().first), legacy = f.settings.snapshot
    input.onInsert(String(f.state.page.state.session.prompt.prefix(1)), false)
    XCTAssertFalse(f.state.page.state.session.typed.isEmpty)
    let attempt = f.state.page.state.session.automaticInputAttemptID, typed = f.state.page.state.session.typed
    try await f.waitAsync { !f.settings.allowsRestartingConfigurationChange }
    for command in [BehaviorCommandTarget.blindMode(true), .quickRestart(.escape),
      .alwaysShowWordsHistory(true), .commandPaletteListMode(.singleList)] {
      try await workflow.editAndBegin(.behavior(command),
        replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
    }
    try await f.waitAsync { f.inputs().first?.quickRestartKey == .escape }
    XCTAssertTrue(f.inputs().first === input); XCTAssertTrue(input.acceptsTextInput)
    XCTAssertEqual(f.state.page.state.session.typed, typed)
    XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertTrue(f.state.page.state.session.configuration.rules.blindMode)
    XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertEqual(f.settings.snapshot, legacy); XCTAssertFalse(f.window.isVisible)
  }

  func testThresholdChangeDuringOnlinePullKeepsValidSectionAndAllowsTheNextPull() async throws {
    try await assertLiveEditDuringOnlinePull(.threshold(.speedValue(0)))
  }
  func testBlindChangeDuringOnlinePullKeepsValidSectionAndAllowsTheNextPull() async throws {
    try await assertLiveEditDuringOnlinePull(.behavior(.blindMode(true)))
  }
  func testInputRuleChangeDuringOnlinePullKeepsValidSectionAndAllowsTheNextPull() async throws {
    try await assertLiveEditDuringOnlinePull(.inputRule(.confidenceMode(.on)))
  }
  func testTapeAppearanceChangeDuringOnlinePullKeepsValidSectionAndAllowsTheNextPull() async throws {
    try await assertLiveEditDuringOnlinePull(.appearance(.tape(.word)))
  }
  private func assertLiveEditDuringOnlinePull(_ edit: WebsiteConfigPracticeEdit) async throws {
    var reads = 0, returned = false
    var reply: CheckedContinuation<LivePracticeContent?, Never>?
    let fetch: WebsiteConfigExternalContent.Fetch = { source, _ in
      reads += 1
      if reads == 1 {
        return .init(source: source, title: "Opening", byline: nil,
          tokens: Array(repeating: "ab", count: 100), separator: " ")
      }
      if reads == 2 {
        let content = await withCheckedContinuation { reply = $0 }
        returned = true; return content
      }
      return .init(source: source, title: "Next", byline: nil, tokens: ["gh", "ij"], separator: " ")
    }
    let f = try Fixture(saved: nil, fetch: fetch)
    defer { reply?.resume(returning: nil); f.close() }
    f.state.accountReady = true; try await f.waitAsync { f.inputs().first?.acceptsTextInput == true }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }, loadExternal: { source, configuration, allLines, check in
        try await WebsiteConfigExternalContent.prepare(source: source, configuration: configuration,
          showAllLines: allLines, checkCurrent: check, fetch: fetch)
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":201,"showAllLines":false,"funbox":["wikipedia"]}"#,
      systemIsDark: false)
    try await f.waitAsync { f.state.page.state.practice?.external != nil && f.inputs().first?.acceptsTextInput == true
      && f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID }
    let attempt = f.state.page.state.session.automaticInputAttemptID
    try XCTUnwrap(f.inputs().first).onInsert("ab ", false)
    XCTAssertEqual(f.state.page.state.session.typed, "ab ")
    try await f.waitAsync { reply != nil }
    guard reply != nil else {
      let current = f.state.page.state.session
      return XCTFail("No stream request: reads=\(reads), completed=\(current.completedWordCount), generation=\(current.needsLiveContentGeneration), side=\(current.needsLiveContentPrefetch), source=\(String(describing: LivePracticeContentSource.selected(for: current.configuration)))")
    }
    try await workflow.editAndBegin(edit,
      replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID, systemIsDark: false)
    let delayed = try XCTUnwrap(reply); reply = nil
    delayed.resume(returning: .init(source: .encyclopedia, title: "Delayed", byline: nil,
      tokens: ["cd", "ef"], separator: " "))
    try await f.waitAsync { returned }
    try await Task.sleep(for: .milliseconds(50))
    XCTAssertTrue(f.state.page.state.session.prompt.contains("cd"), "Live feedback/scoring changes must not retire valid content")
    try XCTUnwrap(f.inputs().first).onInsert("ab ab ", false)
    try await f.waitAsync { reads >= 3 && f.state.page.state.session.prompt.contains("gh") }
    XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.state.page.state.session.typed, "ab ab ab ")
    XCTAssertFalse(f.window.isVisible)
  }

  func testLateOnlineContinuationCannotMutateNewProfileOrDisableItsSource() throws {
    var reads = 0, returned = false
    var reply: CheckedContinuation<LivePracticeContent?, Never>?
    let f = try Fixture(saved: true, json: #"{"mode":"words","words":201,"funbox":["poetry"]}"#,
      fetch: { source, _ in
        reads += 1
        if reads == 1 {
          return .init(source: source, title: "Owned", byline: nil,
            tokens: Array(repeating: "ab", count: 100), separator: " ")
        }
        let content = await withCheckedContinuation { reply = $0 }
        returned = true
        return content
      })
    defer { reply?.resume(returning: nil); f.close() }
    let legacy = f.settings.snapshot
    f.state.accountReady = true
    f.wait { f.state.page.state.practice?.external != nil && f.inputs().first?.acceptsTextInput == true }
    try XCTUnwrap(f.inputs().first).onInsert("ab ", false)
    f.wait { reply != nil }
    // A provider's obsolete reply may arrive after a different configuration
    // has been accepted. Use the actual page/root and real durable workflow.
    var ended = f.state.page.state
    ended.session.failLiveContentFetch(); f.state.page.replace(ended)
    let directory = try XCTUnwrap(WebsiteConfigStorageDirectory.existing(applicationSupport: f.support))
    var quoteReply: CheckedContinuation<[OfflineQuote], Never>?
    let replacementWindow = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { replacementWindow },
      loadQuotes: { _ in await withCheckedContinuation { quoteReply = $0 } })
    defer { quoteReply?.resume(returning: []); workflow.stop() }
    var finished = false, failure: Error?
    let task = Task { @MainActor in
      do { try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false) }
      catch { failure = error }
      finished = true
    }
    defer { task.cancel() }
    f.wait { quoteReply != nil || finished }
    XCTAssertNil(failure)
    guard quoteReply != nil else { return XCTFail("Replacement did not enter quote initialization: \(String(describing: failure)); startup=\(f.state.page.startupController.state)") }
    XCTAssertNotNil(f.state.page.state.savedApplication)
    let generation = f.state.page.state.session.generationState
    let revision = try WebsiteConfigFileRegister(directory: directory).read().revision
    let late = try XCTUnwrap(reply); reply = nil; late.resume(returning: nil)
    f.wait { returned }
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    XCTAssertEqual(reads, 2)
    XCTAssertEqual(f.state.page.state.session.generationState, generation,
      "Pending accepted configuration must fence the retired stream")
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: directory).read().revision, revision)
    XCTAssertEqual(f.settings.snapshot, legacy)
    let complete = try XCTUnwrap(quoteReply); quoteReply = nil
    complete.resume(returning: [.init(id: "owned", title: "Owned", text: "cd ef", language: .english, length: .short)])
    f.wait { finished }; XCTAssertNil(failure)
    XCTAssertEqual(f.state.page.state.session.configuration.mode, .quote)
    XCTAssertFalse(f.window.isVisible)
  }

  func testPublishedPoetryFailureCorrectsFullProfileInsteadOfLegacySelection() throws {
    var reads = 0
    let f = try Fixture(saved: true, json: #"{"mode":"words","words":201,"funbox":["poetry"]}"#,
      fetch: { source, _ in
        reads += 1
        return reads == 1 ? .init(source: source, title: "Owned poem", byline: nil,
          tokens: Array(repeating: "ab", count: 100), separator: " ") : nil
      })
    defer { f.close() }
    let legacy = f.settings.snapshot
    f.state.accountReady = true
    f.wait { f.state.page.state.practice?.external != nil && f.inputs().first?.acceptsTextInput == true }
    let attempt = f.state.page.state.session.automaticInputAttemptID
    try XCTUnwrap(f.inputs().first).onInsert("ab ", false)
    f.wait { f.state.page.state.session.automaticInputAttemptID != attempt && f.state.page.state.practice?.external == nil }
    XCTAssertEqual(reads, 2)
    XCTAssertFalse(f.state.page.state.session.configuration.modifiers.contains(.poetryStream))
    let directory = try WebsiteConfigStorageDirectory.existing(applicationSupport: f.support)
    guard case .available(let fields) = try WebsiteConfigFileRegister(directory: XCTUnwrap(directory)).read().state else {
      return XCTFail("Published source correction lost its record")
    }
    XCTAssertEqual(fields["funbox"], .array([]))
    XCTAssertEqual(f.settings.snapshot, legacy)
    XCTAssertFalse(f.window.isVisible)
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

  func testNormalWindowActionReturnsToActualTypebarSelectionWithoutDeletingRecord() throws {
    let f = try Fixture(saved: true); defer { f.close() }
    f.state.accountReady = true
    f.wait { f.state.page.state.practice != nil && f.inputs().first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.inputs().first), oldInsert = input.onInsert
    let stored = try Data(contentsOf: XCTUnwrap(f.record)), legacy = f.settings.snapshot
    try f.state.page.useTypebarSettings()
    f.wait { f.state.page.state.practice == nil && input.acceptsTextInput }
    XCTAssertEqual(f.state.page.state.session.configuration.wordLimit, 3)
    XCTAssertNil(f.state.page.state.presentation); XCTAssertNil(f.state.page.restartController)
    XCTAssertTrue(f.inputs().first === input)
    oldInsert("stale", false)
    XCTAssertEqual(f.state.page.state.session.typed, "")
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(f.record)), stored)
    XCTAssertEqual(f.settings.snapshot, legacy)
    input.onInsert("a", false)
    XCTAssertEqual(f.state.page.state.session.typed, "a")
    XCTAssertThrowsError(try f.state.page.useTypebarSettings())
    XCTAssertEqual(f.state.page.state.session.typed, "a")
    XCTAssertFalse(f.window.isVisible)
  }

  func testWindowCanRestoreTheKeptWholeRecordAfterReturningToTypebarSettings() throws {
    let f = try Fixture(saved: true); defer { f.close() }
    f.state.accountReady = true
    f.wait { f.state.page.state.practice != nil && f.inputs().first?.acceptsTextInput == true }
    let saved = try Data(contentsOf: XCTUnwrap(f.record))
    try f.state.page.useTypebarSettings()
    f.wait { f.state.page.state.practice == nil && f.inputs().first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.inputs().first), staleNativeInsert = input.onInsert
    let directory = try XCTUnwrap(f.record).deletingLastPathComponent()
    let window = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { window })
    defer { workflow.stop() }
    var result: Result<String, Error>?
    let task = Task {
      do { result = .success(try await workflow.apply(json: nil, systemIsDark: false)) }
      catch { result = .failure(error) }
    }
    defer { task.cancel() }
    f.wait { result != nil }
    _ = try XCTUnwrap(result).get()
    f.wait { f.state.page.state.practice != nil && input.acceptsTextInput }
    XCTAssertEqual(f.state.page.state.session.configuration.wordLimit, 4)
    XCTAssertFalse(f.state.page.isReturningToTypebarSettings)
    XCTAssertTrue(f.inputs().first === input)
    staleNativeInsert("stale", false)
    XCTAssertEqual(f.state.page.state.session.typed, "")
    XCTAssertEqual(try Data(contentsOf: XCTUnwrap(f.record)), saved)
    XCTAssertFalse(f.window.isVisible)
  }
}
