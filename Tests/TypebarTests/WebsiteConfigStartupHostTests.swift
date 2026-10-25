import AppKit
import Observation
import SwiftData
import SwiftUI
import Vision
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
    init(saved: Bool?, json: String = #"{"mode":"words","words":4,"theme":"dracula"}"#,
      fetch: @escaping WebsiteConfigExternalContent.Fetch = { _, _ in nil }, feedbackSound: TypingFeedbackSound? = nil) throws {
      try FileManager.default.createDirectory(at: support, withIntermediateDirectories: false)
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = .init(defaults: defaults, feedbackSound: feedbackSound ?? .init(loadSound: { _ in nil }, beep: {}),
        localBackgroundStore: .inMemory())
      settings.reducePracticeMotion = true; settings.showAllPracticeLines = false
      XCTAssertTrue(settings.saveActiveTestSelection(.init(preset: .init(configuration: .words(3)),
        testParameterMemory: .legacyDefaults(configuration: .words(3)))))
      account = .init(defaults: defaults)
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
      let view = Root(state: state, settings: settings, account: account, support: support, defaults: defaults, fetch: fetch)
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
  private struct Root: View {
    let state: HostState, settings: AppSettings, account: AccountSession, support: URL
    let announcements: RemoteAnnouncementCenter
    let fetch: WebsiteConfigExternalContent.Fetch
    let hotkey = GlobalHotkeyMonitor(), keyboard = SystemKeyboardGuideMonitor(observesInputSourceChanges: false)
    let network = NetworkConnectivityMonitor(), appearance = SystemAppearanceMonitor()
    init(state: HostState, settings: AppSettings, account: AccountSession, support: URL, defaults: UserDefaults,
      fetch: @escaping WebsiteConfigExternalContent.Fetch) {
      self.state = state; self.settings = settings; self.account = account; self.support = support
      self.fetch = fetch
      announcements = .init(defaults: defaults)
    }
    var body: some View {
      TypebarApp.practiceContent(settings: settings, account: account, announcements: announcements,
        hotkey: hotkey, systemKeyboardGuide: keyboard, network: network, systemAppearance: appearance,
        liveContentFetch: fetch,
        practiceSessionStore: state.page,
        websiteConfigStartup: .init(accountReady: state.accountReady, applicationSupport: support))
    }
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
    try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
    let legends = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
    XCTAssertTrue(legends.contains("Q") && legends.contains("W"), "Published QWERTY, not legacy custom rows: \(legends)")
    XCTAssertEqual(f.settings.snapshot, legacy)
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: f.support)
    let selection = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: f.account,
      directory: directory, readWindow: { selection }); defer { workflow.stop() }
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
    for noQuit in [false, true] {
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
        try await workflow.runPaceCommand(.customSpeed, input: "120", replacing: XCTUnwrap(f.state.page.state.presentation).publication.applicationID)
      } catch { return XCTFail("Pace command failed: \(String(reflecting: error))") }
      if noQuit {
        try await f.waitAsync { f.state.page.state.session.paceCaretTargetWpm == 80 }
        XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
        XCTAssertEqual(f.state.page.state.session.typed, "x")
        XCTAssertTrue(f.inputs().first === input); XCTAssertTrue(input.hasMarkedText()); XCTAssertEqual(input.markedRange(), marked)
        XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 0)
      } else {
        try await f.waitAsync { f.inputs().first?.insertionAttemptID == f.state.page.state.session.automaticInputAttemptID
          && f.state.page.state.session.paceCaretTargetWpm == 120 }
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
