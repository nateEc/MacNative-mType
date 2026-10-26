import AppKit
import ImageIO
import Observation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigPracticeHostTests: XCTestCase {
  @MainActor @Observable fileprivate final class HostState {
    let page = PracticePageSessionStore()
    var presentation: WebsiteConfigPublishedPresentation
    var usesPublished = true
    var generations = 0
    init(_ presentation: WebsiteConfigPublishedPresentation) { self.presentation = presentation }
  }
  @MainActor private final class Fixture {
    let suite = "typebar.published-practice.\(UUID())", owner = UUID()
    let directory: URL, defaults: UserDefaults, settings: AppSettings
    let register: WebsiteConfigFileRegister, coordinator: WebsiteConfigCommitCoordinator
    let router = PreferenceConfigurationSaveRouter()
    let container: ModelContainer, state: HostState
    let host: NSHostingView<AnyView>, window: NSWindow
    let prompt = Array(repeating: "000", count: 201).joined(separator: " ")
    init(followsSystem: Bool = false, legacyNoQuit: Bool = true) throws {
      directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-practice-publication-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = AppSettings(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}),
        localBackgroundStore: .inMemory())
      settings.reducePracticeMotion = true; settings.showAllPracticeLines = true
      settings.testModifiers = legacyNoQuit ? [.noQuit] : []
      let config = TestConfiguration.words(201).with(modifiers: legacyNoQuit ? [.noQuit] : [])
      XCTAssertTrue(settings.saveActiveTestSelection(.init(preset: .init(configuration: config),
        testParameterMemory: .legacyDefaults(configuration: config))))
      register = .init(directory: directory)
      router.register(owner: owner, save: { XCTFail("Published presentation must not apply legacy configuration") })
      let epoch = UUID()
      coordinator = .init(router: router, register: register,
        environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
      let first = try Self.publish(coordinator, width: 600, followsSystem: followsSystem)
      let state = HostState(try .init(publication: first, owner: owner,
        systemIsDark: SystemAppearancePolicy.colorScheme(for: NSApplication.shared.effectiveAppearance) == .dark))
      self.state = state
      container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self, SavedCustomTextRecord.self,
        ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      let content = Root(state: state, settings: settings, defaults: defaults, prompt: prompt).modelContainer(container)
      host = NSHostingView(rootView: AnyView(content.frame(width: 1000, height: 720)))
      window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720), styleMask: .borderless,
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = host
    }
    static func publish(_ coordinator: WebsiteConfigCommitCoordinator, width: Int,
      tape: Bool = false, followsSystem: Bool = false) throws -> WebsiteConfigCommitCoordinator.Publication {
      let ticket = try coordinator.prepare("{\"showAllLines\":true,\"fontSize\":1.75,\"maxLineWidth\":30.5,\"tapeMode\":\"\(tape ? "letter" : "off")\",\"compositionDisplay\":\"replace\",\"theme\":\"dracula\",\"themeLight\":\"serika\",\"themeDark\":\"dracula\",\"customTheme\":false,\"autoSwitchTheme\":\(followsSystem)}")
      let name = "TypebarHostQA" // Same private name, different owned bytes.
      let resource = try coordinator.prepareResources(for: ticket,
        localFont: .data(OwnedTestFontFixture.make(postScriptName: name, advanceWidth: width, character: 48)),
        localBackground: .data(png()))
      guard case .committed(let value) = try coordinator.commit(resource) else { throw Failure.commit }
      return value
    }
    static func png() throws -> Data {
      let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data([32, 64, 96, 255]) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
      let data = NSMutableData(), output = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(output, image, nil); XCTAssertTrue(CGImageDestinationFinalize(output))
      return data as Data
    }
    func views<T: NSView>(_ type: T.Type, in root: NSView? = nil) -> [T] {
      let root = root ?? host
      return (root as? T).map { [$0] } ?? root.subviews.flatMap { views(type, in: $0) }
    }
    func wait(_ ready: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
      let deadline = Date().addingTimeInterval(15)
      repeat { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
      while !ready() && Date() < deadline
      XCTAssertTrue(ready(), "Published production host did not settle", file: file, line: line)
    }
    func close() {
      host.rootView = AnyView(EmptyView()); host.layoutSubtreeIfNeeded()
      window.contentView = nil; window.close(); router.remove(owner: owner)
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
      withExtendedLifetime(container) {}
    }
  }
  private enum Failure: Error { case commit }
  private struct Root: View {
    let state: HostState, settings: AppSettings, defaults: UserDefaults, prompt: String
    let account: AccountSession
    let announcements: RemoteAnnouncementCenter
    let hotkey = GlobalHotkeyMonitor()
    let keyboardGuide = SystemKeyboardGuideMonitor(observesInputSourceChanges: false)
    let network = NetworkConnectivityMonitor()
    let appearance = SystemAppearanceMonitor()
    init(state: HostState, settings: AppSettings, defaults: UserDefaults, prompt: String) {
      self.state = state; self.settings = settings; self.defaults = defaults; self.prompt = prompt
      account = .init(defaults: defaults); announcements = .init(defaults: defaults)
    }
    var body: some View {
      TypebarApp.practiceContent(settings: settings, account: account,
        announcements: announcements, hotkey: hotkey, systemKeyboardGuide: keyboardGuide,
        network: network, systemAppearance: appearance,
        wholePreviewPrepare: { configuration, _, _ in
          state.generations += 1; return TypingSession(configuration: configuration, prompt: prompt)
        }, wholePreviewViewportEnabled: !state.usesPublished,
        publishedPresentation: state.usesPublished ? state.presentation : nil,
        practiceSessionStore: state.page)
    }
  }

  func testProductionPageConsumesPublicationAndKeepsNativeInputAcrossFontAndCompositionUpdates() throws {
    let f = try Fixture(); defer { f.close() }
    f.wait { !f.views(WebsiteConfigPublishedBackgroundView.self).isEmpty
      && f.views(PromptViewportPracticeNativeView.self).first?.viewport.canvas.hasCompleteHeight == true
      && f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    let viewport = try XCTUnwrap(f.views(PromptViewportPracticeNativeView.self).first)
    XCTAssertEqual(try XCTUnwrap(f.state.presentation.publication.font).chAdvance * 30.5, 512.4, accuracy: 0.000001)
    // NSHostingView rounds its native frame to backing pixels, unlike the raw metric.
    XCTAssertEqual(viewport.viewport.layoutWidth, 512.4, accuracy: 1)
    input.onInsert("0", false)
    f.wait { !f.settings.allowsRestartingConfigurationChange }
    let attempt = try XCTUnwrap(input.insertionAttemptID)
    let second = try Fixture.publish(f.coordinator, width: 900)
    f.state.presentation = try .init(publication: second, owner: f.owner, systemIsDark: false)
    XCTAssertEqual(try XCTUnwrap(second.font).chAdvance * 30.5, 768.6, accuracy: 0.000001)
    f.wait { abs(viewport.viewport.layoutWidth - 768.6) < 1 }
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    XCTAssertEqual(input.insertionAttemptID, attempt); XCTAssertEqual(f.state.generations, 1)
    guard case .ready(let image) = second.background?.state else { return XCTFail("Prepared image missing") }
    XCTAssertTrue(f.views(WebsiteConfigPublishedBackgroundView.self).first?.surface.player.currentSample?.frame.image === image.frames[0].image)
    input.setMarkedText("中", selectedRange: .init(location: 1, length: 0), replacementRange: .init(location: NSNotFound, length: 0))
    f.wait { f.views(PromptViewportPracticeNativeView.self).isEmpty
      && f.views(PromptFieldNativeView.self).contains { ($0.accessibilityValue() as? String)?.contains("中") == true } }
    XCTAssertTrue(input.hasMarkedText()); XCTAssertTrue(f.views(TypingInputView.self).first === input)
    XCTAssertEqual(input.insertionAttemptID, attempt); XCTAssertEqual(f.state.generations, 1)
    let third = try Fixture.publish(f.coordinator, width: 600)
    guard case .ready(let thirdImage) = third.background?.state else { return XCTFail("Third owned image missing") }
    f.state.presentation = try .init(publication: third, owner: f.owner, systemIsDark: false)
    let range = NSRange(location: 0, length: 1)
    f.wait { input.hasMarkedText()
      && f.views(WebsiteConfigPublishedBackgroundView.self).first?.surface.player.currentSample?.frame.image === thirdImage.frames[0].image
      && f.views(PromptFieldNativeView.self).contains { ($0.accessibilityValue() as? String)?.contains("中") == true }
      && input.insertionAnchor?.markedScreenRect(attemptID: attempt, in: f.window,
        range: range, markedText: "中", style: .replace) != nil }
    let candidate = try XCTUnwrap(input.insertionAnchor?.markedScreenRect(attemptID: attempt, in: f.window,
      range: range, markedText: "中", style: .replace))
    var actual = NSRange()
    XCTAssertEqual(input.firstRect(forCharacterRange: range, actualRange: &actual), candidate.rect)
    XCTAssertEqual(actual, candidate.actualRange); XCTAssertGreaterThan(candidate.rect.height, 0)
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    XCTAssertEqual(input.insertionAttemptID, attempt); XCTAssertEqual(f.state.generations, 1)
    XCTAssertFalse(f.window.isVisible)
  }

  func testPublishedTapeAndDisplayRollbackKeepTheExistingAttemptAndNativeInput() throws {
    let f = try Fixture(); defer { f.close() }
    f.wait { f.views(PromptViewportPracticeNativeView.self).first?.viewport.canvas.hasCompleteHeight == true
      && f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first), attempt = input.insertionAttemptID
    input.onInsert("0", false)
    f.wait { !f.settings.allowsRestartingConfigurationChange }
    f.state.presentation = try .init(publication: Fixture.publish(f.coordinator, width: 900, tape: true),
      owner: f.owner, systemIsDark: false)
    f.wait { f.views(TapePromptNativeView.self).first?.bounds.width ?? 0 > 800 }
    XCTAssertTrue(f.views(PromptViewportPracticeNativeView.self).isEmpty)
    XCTAssertTrue(f.views(TypingInputView.self).first === input); XCTAssertEqual(input.insertionAttemptID, attempt)
    let record = try f.register.read().state
    f.state.usesPublished = false
    f.wait { f.views(TapePromptNativeView.self).isEmpty
      && f.views(WebsiteConfigPublishedBackgroundView.self).isEmpty
      && f.views(PromptViewportPracticeNativeView.self).first?.viewport.canvas.hasCompleteHeight == true }
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    XCTAssertEqual(input.insertionAttemptID, attempt); XCTAssertEqual(f.state.generations, 1)
    XCTAssertFalse(f.settings.allowsRestartingConfigurationChange)
    XCTAssertEqual(try f.register.read().state, record); XCTAssertFalse(f.window.isVisible)
  }

  func testProductionSystemAppearanceBridgeDoesNotReadItsOwnForcedWindowTheme() throws {
    let app = NSApplication.shared, previous = app.appearance
    defer { app.appearance = previous }
    app.appearance = NSAppearance(named: .aqua)
    let f = try Fixture(followsSystem: true); defer { f.close() }
    f.wait { f.views(PromptViewportPracticeNativeView.self).first?.viewport.canvas.hasCompleteHeight == true
      && f.views(TypingInputView.self).first?.acceptsTextInput == true }
    XCTAssertEqual(f.state.presentation.appearance.selection, .builtIn(.serika))
    let input = try XCTUnwrap(f.views(TypingInputView.self).first), attempt = input.insertionAttemptID
    let viewport = try XCTUnwrap(f.views(PromptViewportPracticeNativeView.self).first)
    let publication = f.state.presentation.publication, record = try f.register.read().state
    app.appearance = NSAppearance(named: .darkAqua)
    f.wait { f.state.presentation.appearance.selection == .builtIn(.dracula) }
    XCTAssertTrue(f.views(PromptViewportPracticeNativeView.self).first === viewport)
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    XCTAssertEqual(input.insertionAttemptID, attempt); XCTAssertEqual(f.state.generations, 1)
    XCTAssertEqual(f.state.presentation.publication.applicationID, publication.applicationID)
    XCTAssertEqual(try f.register.read().state, record)
    app.appearance = NSAppearance(named: .aqua)
    f.wait { f.state.presentation.appearance.selection == .builtIn(.serika) }
    XCTAssertFalse(f.window.isVisible)
  }

  func testCompletePublicationInstallsItsActualAttemptAndKeepsSourceRulesOnNativeInput() throws {
    let f = try Fixture(); defer { f.close() }
    f.wait { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    let owner = try XCTUnwrap(f.settings.preferenceConfigurationSaves.captureLease()?.owner)
    let epoch = UUID()
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves, register: f.register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    let ticket = try coordinator.prepare(#"{"mode":"custom","difficulty":"expert","stopOnError":"letter","layout":"dvorak","keymapLayout":"dvorak","oppositeShiftMode":"keymap","quickRestart":"off","funbox":["ddoouubblleedd","ddoouubblleedd","rot13"],"theme":"dracula","fontSize":1.75,"maxLineWidth":30.5}"#)
    let resources = try coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .data(Fixture.png()))
    let ready = try awaitResult(coordinator, resources: resources)
    guard case .committed(let publication) = try coordinator.commit(ready) else { throw Failure.commit }
    let seed = try XCTUnwrap(publication.session)
    XCTAssertEqual(seed.prompt, "nnnnoooo")
    let previous = f.settings.snapshot
    f.state.presentation = try .init(publication: publication, owner: owner, systemIsDark: false)
    for _ in 0..<4 { f.host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    XCTAssertEqual(input.insertionAttemptID, seed.automaticInputAttemptID)
    XCTAssertEqual(input.keyboardInputMapping, publication.draft.keyboardTypography.inputLayout.inputMapping(for: nil))
    XCTAssertEqual(input.oppositeShiftMode, .keymap)
    XCTAssertEqual(input.quickRestartKey, .off)
    let before = try XCTUnwrap(input.insertionAnchor?.screenRect(attemptID: seed.automaticInputAttemptID, in: f.window))
    input.onInsert("x", false)
    for _ in 0..<3 { f.host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    let stopped = try XCTUnwrap(input.insertionAnchor?.screenRect(attemptID: seed.automaticInputAttemptID, in: f.window))
    XCTAssertEqual(stopped.minX, before.minX, accuracy: 1, "Source letter-stop must not be replaced by legacy rules")
    input.onInsert("n", false)
    f.wait { (input.insertionAnchor?.screenRect(attemptID: seed.automaticInputAttemptID, in: f.window)?.minX ?? 0) > before.minX + 1 }
    XCTAssertEqual(f.settings.snapshot, previous)
    f.settings.stopOnErrorMode = .word
    for _ in 0..<3 { f.host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    let advanced = try XCTUnwrap(input.insertionAnchor?.screenRect(attemptID: seed.automaticInputAttemptID, in: f.window))
    input.onInsert("x", false)
    for _ in 0..<3 { f.host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertEqual(try XCTUnwrap(input.insertionAnchor?.screenRect(attemptID: seed.automaticInputAttemptID, in: f.window)).minX,
      advanced.minX, accuracy: 1, "Legacy change observers must also leave source rules intact")
    XCTAssertEqual(f.state.generations, 1, "Installing an already prepared attempt must not generate again")
    f.state.usesPublished = false
    for _ in 0..<3 { f.host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertEqual(input.insertionAttemptID, seed.automaticInputAttemptID,
      "Removing a delivery parameter is not an instruction to undo a committed attempt")
    XCTAssertFalse(f.views(WebsiteConfigPublishedBackgroundView.self).isEmpty)
    XCTAssertFalse(f.window.isVisible)
  }

  func testForeignCompletePublicationCannotReplaceActualWindowAttemptOrItsDisplay() throws {
    let f = try Fixture(); defer { f.close() }
    f.wait { f.views(PromptViewportPracticeNativeView.self).first?.viewport.canvas.hasCompleteHeight == true
      && f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first), attempt = input.insertionAttemptID
    let viewport = try XCTUnwrap(f.views(PromptViewportPracticeNativeView.self).first)
    let resources = try f.coordinator.prepareResources(for: f.coordinator.prepare(#"{"mode":"custom","fontSize":1}"#),
      localFont: .absent, localBackground: .data(Fixture.png()))
    let ready = try awaitResult(f.coordinator, resources: resources)
    guard case .committed(let publication) = try f.coordinator.commit(ready) else { throw Failure.commit }
    XCTAssertNotEqual(publication.owner, f.settings.preferenceConfigurationSaves.captureLease()?.owner)
    f.state.presentation = try .init(publication: publication, owner: f.owner, systemIsDark: false)
    for _ in 0..<4 { f.host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertEqual(input.insertionAttemptID, attempt)
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    XCTAssertTrue(f.views(PromptViewportPracticeNativeView.self).first === viewport,
      "An incoming foreign font/mode must not appear before ownership admission")
    XCTAssertEqual(f.state.generations, 1)
    XCTAssertFalse(f.window.isVisible)
  }

  private func awaitResult(_ coordinator: WebsiteConfigCommitCoordinator,
    resources: WebsiteConfigCommitCoordinator.ResourcesPrepared, customText: String = "ab") throws -> WebsiteConfigCommitCoordinator.SessionPrepared {
    var result: Result<WebsiteConfigCommitCoordinator.SessionPrepared, Error>?
    let task = Task { @MainActor in
      do { result = .success(try await coordinator.preparePractice(for: resources, scope: .init(customText: customText))) }
      catch { result = .failure(error) }
    }
    defer { task.cancel() }
    let deadline = Date().addingTimeInterval(10)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return try XCTUnwrap(result).get()
  }

  func testActualPageNextHighlightUsesSourceScalarThenAcceptedInputUnitsAndDeletion() throws {
    let f = try Fixture(legacyNoQuit: false); defer { f.close() }
    f.wait { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    let epoch = UUID()
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves, register: f.register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    let resources = try coordinator.prepareResources(for: coordinator.prepare(#"{"mode":"custom","keymapMode":"next","keymapLayout":"qwerty","blindMode":true}"#), localFont: .absent, localBackground: .data(Fixture.png()))
    // The custom-text preparation path normalizes NFC. Use a combining mark
    // without a precomposed form so this remains a multi-scalar real prompt.
    let ready = try awaitResult(coordinator, resources: resources, customText: "e\u{35c}x tail")
    XCTAssertEqual(Array(ready.session.prompt.utf16), Array("e\u{35c}x tail".utf16))
    guard case .committed = try coordinator.commit(ready, to: f.state.page, systemIsDark: false) else { return XCTFail("Expected page installation") }
    f.wait { input.insertionAttemptID == ready.session.automaticInputAttemptID && input.acceptsTextInput }
    XCTAssertEqual(f.state.page.state.session.websiteKeymapHighlightUnits, [101])
    input.onInsert("e", false)
    XCTAssertEqual(f.state.page.state.session.websiteKeymapHighlightUnits, [860])
    input.onInsert("\u{35c}", false)
    XCTAssertEqual(f.state.page.state.session.websiteKeymapHighlightUnits, [120])
    input.onDelete()
    XCTAssertEqual(f.state.page.state.session.websiteKeymapHighlightUnits, [860])
    XCTAssertEqual(input.insertionAttemptID, ready.session.automaticInputAttemptID)
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    XCTAssertFalse(f.window.isVisible)
  }

  func testActualPageHiddenFieldsSwitchLayoutAtTheLoadedWordBoundary() async throws {
    let f = try Fixture(legacyNoQuit: false); defer { f.close() }
    func settle(_ ready: () -> Bool) async throws {
      let deadline = ContinuousClock.now.advanced(by: .seconds(15))
      while !ready(), ContinuousClock.now < deadline {
        f.host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10))
      }
      XCTAssertTrue(ready())
    }
    try await settle { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    let account = AccountSession(defaults: f.defaults)
    let window = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: account,
      directory: f.directory, readWindow: { window })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"blindMode":true,"keymapMode":"static","funbox":["layoutfluid","nospace"],"customLayoutfluid":["qwerty","colemak"]}"#, systemIsDark: false)
    let attempt = f.state.page.state.session.automaticInputAttemptID
    try await settle { input.insertionAttemptID == attempt && input.acceptsTextInput }
    XCTAssertEqual(f.state.page.state.session.layoutFluidWordCount, 4)
    XCTAssertEqual(f.state.page.layoutFluidCountdown, .init())
    for completed in 1...2 {
      let field = try XCTUnwrap(f.state.page.state.session.promptCompositionField)
      input.onInsert(String(decoding: field.targetUTF16, as: UTF16.self), false)
      XCTAssertEqual(f.state.page.state.session.completedWordCount, completed)
      XCTAssertEqual(f.state.page.state.presentation?.publication.draft.keyboardTypography.guideLayout,
        completed == 1 ? .ansiQwerty : .ansiColemak)
      XCTAssertEqual(f.state.page.state.presentation?.publication.draft.keyboardTypography.inputLayout.emulatedLayout,
        completed == 1 ? .ansiQwerty : .ansiColemak)
      XCTAssertEqual(f.state.page.layoutFluidCountdown.visible, completed == 1)
      XCTAssertEqual(f.state.page.layoutFluidCountdown.text, "Colemak starting next word")
      XCTAssertTrue(f.state.page.state.session.websiteWordNavigationEvents.isEmpty)
      XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertTrue(f.views(TypingInputView.self).first === input)
    }
    XCTAssertFalse(f.state.page.state.session.isFinished)
    XCTAssertEqual(f.state.page.state.session.errors, 0)
    XCTAssertFalse(f.window.isVisible)
  }

  func testActualPageFinishedPasteDeliversOnlyOwnedNavigationAndKeepsNoQuitAtHookTime() async throws {
    for trailingCommit in [false, true] {
      let f = try Fixture(legacyNoQuit: false); defer { f.close() }
      func settle(_ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while !ready(), ContinuousClock.now < deadline { f.host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(ready())
      }
      try await settle { f.views(TypingInputView.self).first?.acceptsTextInput == true }
      let input = try XCTUnwrap(f.views(TypingInputView.self).first)
      let account = AccountSession(defaults: f.defaults)
      let window = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
      var delays: [Int] = []
      let workflow = WebsiteConfigImportWorkflow(page: f.state.page, settings: f.settings, account: account,
        directory: f.directory, readWindow: { window }, dispatchKeymapHighlight: { delay, _ in delays.append(delay) })
      defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"words","words":2,"blindMode":true,"keymapMode":"static","funbox":["layoutfluid","no_quit"],"customLayoutfluid":["qwerty","colemak"]}"#, systemIsDark: false)
      let attempt = f.state.page.state.session.automaticInputAttemptID
      try await settle { input.insertionAttemptID == attempt && input.acceptsTextInput }
      let prompt = f.state.page.state.session.prompt
      input.onInsert(prompt + (trailingCommit ? " " : ""), false)
      XCTAssertEqual(f.state.page.state.session.outcome, .completed)
      XCTAssertEqual(delays, Array(repeating: 1, count: trailingCommit ? 2 : 1))
      XCTAssertEqual(f.state.page.state.presentation?.publication.draft.keyboardTypography.inputLayout.emulatedLayout, .ansiQwerty)
      XCTAssertEqual(f.state.page.state.presentation?.publication.draft.keyboardTypography.guideLayout, .ansiColemak)
      XCTAssertTrue(f.state.page.state.session.websiteWordNavigationEvents.isEmpty)
      XCTAssertTrue(f.views(TypingInputView.self).first === input)
      XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertFalse(f.window.isVisible)
    }
  }

  func testSynchronousCommitTargetsActualPageAndRejectsOldInputCallbacks() throws {
    let f = try Fixture(); defer { f.close() }
    f.wait { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    let actualOwner = try XCTUnwrap(f.settings.preferenceConfigurationSaves.captureLease()?.owner)
    XCTAssertEqual(actualOwner, f.state.page.owner, "The destination must belong to the real page, not a detached test store")
    XCTAssertEqual(input.insertionAttemptID, f.state.page.state.session.automaticInputAttemptID)
    let staleInsert = input.onInsert, staleDelete = input.onDelete, staleComposition = input.onCompositionChanged
    let staleCompositionStart = input.onCompositionStarted, staleDeleteWord = input.onDeleteWord, staleBailout = input.onBailout
    let epoch = UUID()
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves, register: f.register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    let resources = try coordinator.prepareResources(for: coordinator.prepare(#"{"mode":"custom","stopOnError":"letter"}"#),
      localFont: .absent, localBackground: .data(Fixture.png()))
    let ready = try awaitResult(coordinator, resources: resources)
    do {
      guard case .committed(let publication) = try coordinator.commit(ready, to: f.state.page, systemIsDark: false) else {
        return XCTFail("Expected synchronous page installation")
      }
      XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, ready.session.automaticInputAttemptID)
      XCTAssertEqual(f.state.page.state.presentation?.publication.applicationID, publication.applicationID)
    } catch { return XCTFail("The actual page destination must admit its prepared attempt: \(error)") }
    let currentCapture = try f.state.page.captureGeneration(router: f.settings.preferenceConfigurationSaves)
    // Do not run the loop before these calls: the native view still carries
    // callbacks from the previous attempt while the authoritative state is new.
    staleCompositionStart()
    XCTAssertFalse(f.state.page.state.session.hasStarted, "Old composition must not start a replacement attempt")
    staleInsert("a", false)
    XCTAssertEqual(f.state.page.state.session.typed, "", "Cached insertion must not reach the replacement attempt")
    staleDelete(); staleComposition("stale")
    XCTAssertEqual(f.state.page.state.session.typed, "")
    XCTAssertTrue(f.state.page.isCurrent(currentCapture, router: f.settings.preferenceConfigurationSaves),
      "Callbacks from the old attempt must not retire a capture for the replacement")
    f.wait { input.insertionAttemptID == ready.session.automaticInputAttemptID && input.acceptsTextInput }
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    input.onInsert("a", false)
    XCTAssertEqual(f.state.page.state.session.typed, "a")
    staleDelete(); staleInsert("b", false)
    XCTAssertEqual(f.state.page.state.session.typed, "a")
    staleDeleteWord(); staleBailout()
    XCTAssertEqual(f.state.page.state.session.typed, "a")
    XCTAssertFalse(f.state.page.state.session.isFinished, "Old bailout must not finish a replacement attempt")
    XCTAssertFalse(f.window.isVisible)
  }

  func testActualCompositionCallbacksRetirePageBoundEditWithoutCommittedInputOrDiskWrite() throws {
    let f = try Fixture(legacyNoQuit: false); defer { f.close() }
    f.wait { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    let router = f.settings.preferenceConfigurationSaves, epoch = UUID()
    let coordinator = WebsiteConfigCommitCoordinator(router: router, register: f.register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    let resources = try coordinator.prepareResources(for: coordinator.prepare(#"{"mode":"custom"}"#),
      localFont: .absent, localBackground: .absent)
    let ready = try awaitResult(coordinator, resources: resources)
    guard case .committed(let publication) = try coordinator.commit(ready, to: f.state.page, systemIsDark: true) else {
      return XCTFail("Initial full publication failed")
    }
    f.wait { input.insertionAttemptID == ready.session.automaticInputAttemptID && input.acceptsTextInput }
    input.onInsert("a", false)
    let before = f.state.page.state.session.generationState
    let startCapture = try f.state.page.captureGeneration(router: router)
    input.onCompositionStarted()
    XCTAssertEqual(f.state.page.state.session.generationState, before)
    XCTAssertFalse(f.state.page.isCurrent(startCapture, router: router))
    let edit = try coordinator.prepareEdit(key: "difficulty", value: .string("expert"), for: f.state.page)
    let markedCapture = try f.state.page.captureGeneration(router: router)
    input.onCompositionChanged("中")
    XCTAssertEqual(f.state.page.state.session.generationState, before,
      "This exercises uncommitted candidate activity, not a replay/input counter change")
    XCTAssertFalse(f.state.page.isCurrent(markedCapture, router: router))
    XCTAssertThrowsError(try coordinator.prepareResources(for: edit, localFont: .absent, localBackground: .absent))
    XCTAssertEqual(try f.register.read().revision, publication.disk)
    XCTAssertEqual(f.state.page.state.session.typed, "a")
    XCTAssertFalse(f.window.isVisible)
  }

  func testSynchronousAttemptTransitionDiscardsNativeMarkedTextWithoutCommittingIt() throws {
    let f = try Fixture(legacyNoQuit: false); defer { f.close() }
    f.wait { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    input.setMarkedText("中", selectedRange: .init(location: 1, length: 0), replacementRange: .init(location: NSNotFound, length: 0))
    f.wait { input.hasMarkedText() }
    let epoch = UUID()
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves, register: f.register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    let resources = try coordinator.prepareResources(for: coordinator.prepare(#"{"mode":"custom"}"#),
      localFont: .absent, localBackground: .data(Fixture.png()))
    let ready = try awaitResult(coordinator, resources: resources)
    guard case .committed = try coordinator.commit(ready, to: f.state.page, systemIsDark: false) else {
      return XCTFail("Expected replacement of the unprotected composition attempt")
    }
    XCTAssertEqual(f.state.page.state.session.typed, "")
    f.wait { input.insertionAttemptID == ready.session.automaticInputAttemptID && input.acceptsTextInput }
    XCTAssertFalse(input.hasMarkedText(), "The same native input must not carry marked text into another attempt")
    XCTAssertEqual(input.markedRange().location, NSNotFound)
    XCTAssertEqual(f.state.page.state.session.typed, "")
    XCTAssertFalse(f.state.page.state.session.hasStarted)
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    input.insertText("a", replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertEqual(f.state.page.state.session.typed, "a", "The new attempt must remain usable")
    XCTAssertFalse(f.window.isVisible)
  }

  private func awaitNext(_ coordinator: WebsiteConfigCommitCoordinator, page: PracticePageSessionStore,
    restartRequested: Bool? = nil) throws
    -> WebsiteConfigCommitCoordinator.NextPrepared {
    var result: Result<WebsiteConfigCommitCoordinator.NextPrepared, Error>?
    let task = Task { @MainActor in
      do {
        if let restartRequested {
          result = .success(try await coordinator.prepareRestart(for: page, repeatingRequested: restartRequested))
        } else { result = .success(try await coordinator.prepareNext(for: page)) }
      }
      catch { result = .failure(error) }
    }
    defer { task.cancel() }
    let deadline = Date().addingTimeInterval(10)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return try XCTUnwrap(result).get()
  }

  func testOrdinaryNextClearsCompositionWithoutReapplyingTheConfiguration() throws {
    let f = try Fixture(legacyNoQuit: false); defer { f.close() }
    f.wait { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let epoch = UUID()
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves, register: f.register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    let resources = try coordinator.prepareResources(for: coordinator.prepare(#"{"mode":"custom"}"#),
      localFont: .absent, localBackground: .data(Fixture.png()))
    let ready = try awaitResult(coordinator, resources: resources)
    guard case .committed = try coordinator.commit(ready, to: f.state.page, systemIsDark: false) else {
      return XCTFail("Initial page installation failed")
    }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    f.wait { input.insertionAttemptID == ready.session.automaticInputAttemptID && input.acceptsTextInput }
    let presentation = try XCTUnwrap(f.state.page.state.presentation)
    let disk = try f.register.read().revision
    input.setMarkedText("中", selectedRange: .init(location: 1, length: 0), replacementRange: .init(location: NSNotFound, length: 0))
    f.wait { input.hasMarkedText() }
    let staleInsert = input.onInsert
    let next = try awaitNext(coordinator, page: f.state.page)
    guard case .advanced = try coordinator.advance(next, to: f.state.page) else { return XCTFail("Next did not install") }
    staleInsert("old", false)
    XCTAssertEqual(f.state.page.state.session.typed, "")
    let nextID = f.state.page.state.session.automaticInputAttemptID
    f.wait { input.insertionAttemptID == nextID && input.acceptsTextInput }
    XCTAssertFalse(input.hasMarkedText())
    XCTAssertFalse(f.views(PromptFieldNativeView.self).contains { ($0.accessibilityValue() as? String)?.contains("中") == true },
      "The page's composition state must retire even when the configuration publication is unchanged")
    XCTAssertTrue(f.state.page.state.presentation === presentation)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    input.insertText("a", replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertEqual(f.state.page.state.session.typed, "a")
    XCTAssertFalse(f.window.isVisible)
  }

  func testRepeatedWordsetKeepsActualInputAndConfigurationWhileRetiringOldCallbacks() throws {
    let f = try Fixture(legacyNoQuit: false); defer { f.close() }
    f.wait { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let epoch = UUID()
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves, register: f.register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    let resources = try coordinator.prepareResources(for: coordinator.prepare(#"{"mode":"custom","repeatedPace":true}"#),
      localFont: .absent, localBackground: .data(Fixture.png()))
    let ready = try awaitResult(coordinator, resources: resources)
    guard case .committed = try coordinator.commit(ready, to: f.state.page, systemIsDark: false) else {
      return XCTFail("Initial page installation failed")
    }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    f.wait { input.insertionAttemptID == ready.session.automaticInputAttemptID && input.acceptsTextInput }
    input.onInsert("a", false)
    let staleInsert = input.onInsert
    let presentation = f.state.page.state.presentation
    let disk = try f.register.read().revision
    let repeated = try awaitNext(coordinator, page: f.state.page, restartRequested: true)
    guard case .advanced(let old) = try coordinator.advance(repeated, to: f.state.page) else { return XCTFail("Repeat did not install") }
    XCTAssertEqual(old.session.typed, "a")
    staleInsert("old", false)
    XCTAssertEqual(f.state.page.state.session.typed, "")
    let newID = f.state.page.state.session.automaticInputAttemptID
    f.wait { input.insertionAttemptID == newID && input.acceptsTextInput }
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    XCTAssertTrue(f.state.page.state.presentation === presentation)
    XCTAssertEqual(f.state.page.state.practice?.repetition, .sameWordset(repeatedPace: true))
    XCTAssertEqual(f.state.page.state.session.prompt, "ab")
    XCTAssertEqual(try f.register.read().revision, disk)
    input.insertText("a", replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertEqual(f.state.page.state.session.typed, "a")
    XCTAssertFalse(f.window.isVisible)
  }

  func testBoundControllerReceivesNativeRestartAndUsesPublishedSavingAndPaceRules() throws {
    let f = try Fixture(legacyNoQuit: false); defer { f.close() }
    f.settings.saveCompletedResults = false
    f.settings.paceGuideMode = .off
    f.wait { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let epoch = UUID()
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves, register: f.register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    let resources = try coordinator.prepareResources(for: coordinator.prepare(
      #"{"mode":"custom","resultSaving":true,"paceCaret":"custom","paceCaretCustomSpeed":80}"#),
      localFont: .absent, localBackground: .data(Fixture.png()))
    let ready = try awaitResult(coordinator, resources: resources)
    guard case .committed = try coordinator.commit(ready, to: f.state.page, systemIsDark: false) else { return XCTFail("Initial commit failed") }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    f.wait { input.insertionAttemptID == ready.session.automaticInputAttemptID && input.acceptsTextInput }
    let controller = try f.state.page.bindRestartController(using: coordinator)
    XCTAssertTrue(f.window.makeFirstResponder(input))
    input.onInsert("a", false)
    XCTAssertNotNil(f.state.page.state.session.paceCaretFrame(), "Published custom pace must not read legacy off")
    let oldRestart = input.onRestart, oldInsert = input.onInsert
    let disk = try f.register.read().revision
    input.onRestart()
    oldRestart()
    XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 1)
    let oldID = ready.session.automaticInputAttemptID
    f.wait { !controller.isPreparing && input.insertionAttemptID != oldID && input.acceptsTextInput }
    XCTAssertNil(controller.message)
    XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try f.register.read().revision, disk)
    oldInsert("old", false); oldRestart()
    XCTAssertEqual(f.state.page.state.session.typed, "")
    XCTAssertFalse(controller.isPreparing)
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    XCTAssertTrue(f.window.firstResponder === input)
    input.onInsert("a", false)
    XCTAssertNotNil(f.state.page.state.session.paceCaretFrame())
    XCTAssertFalse(f.window.isVisible)
  }

  func testLegacyNativeRestartUsesTheSamePageLedgerWithoutDoubleCounting() throws {
    let f = try Fixture(legacyNoQuit: false); defer { f.close() }
    f.wait { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    input.onInsert("0", false)
    let oldID = input.insertionAttemptID
    input.onRestart()
    f.wait { input.insertionAttemptID != oldID && input.acceptsTextInput }
    XCTAssertEqual(f.state.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(f.state.page.state.priorAttemptLedger.incompletePractice?.attempts.count, 1)
    XCTAssertFalse(f.window.isVisible)
  }

  func testFirstApplicationCaptureRejectsActualUncommittedNativeComposition() throws {
    let f = try Fixture(legacyNoQuit: false); defer { f.close() }
    f.wait { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    XCTAssertNil(f.state.page.state.practice, "This must exercise the initial page, not an existing profile")
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    let attempt = input.insertionAttemptID
    // Starting composition starts the legacy timer. Capture only after that
    // legitimate transition so the next candidate update is composition-only.
    input.setMarkedText("中", selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    f.wait { input.hasMarkedText() }
    XCTAssertTrue(f.state.page.state.session.hasStarted)
    let environment = WebsiteConfigEnvironmentSource(settings: f.settings, account: .init(defaults: f.defaults),
      pointsPerRem: 16, documentComplete: true, development: false)
    defer { environment.stop() }
    let window = WebsiteConfigPracticeScopeSource.Window(owner: f.state.page.owner, customRecoveryBlocked: false)
    let source = WebsiteConfigPracticeScopeSource(environment: environment, readWindow: { window })
    defer { source.stop() }
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves,
      register: f.register, environment: { environment.read() })
    let ticket = try coordinator.prepare(#"{"mode":"words","words":10}"#,
      for: f.state.page, refreshingWith: source)
    let before = f.state.page.state.session.generationState
    let disk = try f.register.read().revision
    input.setMarkedText("中文", selectedRange: .init(location: 2, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    f.wait { input.hasMarkedText() && input.markedRange().length == 2 }
    XCTAssertEqual(f.state.page.state.session.generationState, before)
    XCTAssertThrowsError(try coordinator.prepareResources(for: ticket,
      localFont: .absent, localBackground: .absent)) { error in
      guard case WebsiteConfigCommitCoordinatorError.stale = error else { return XCTFail("Unexpected: \(error)") }
    }
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(input.insertionAttemptID, attempt)
    XCTAssertTrue(input.hasMarkedText())
    XCTAssertTrue(f.views(TypingInputView.self).first === input)
    XCTAssertFalse(f.window.isVisible)
  }

  func testSynchronousCommitChecksActualStartedNoQuitPageBeforeWriting() throws {
    let f = try Fixture(); defer { f.close() }
    f.wait { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first)
    input.insertText("0", replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertTrue(f.state.page.state.session.hasStarted)
    XCTAssertEqual(f.state.page.state.session.typed, "0")
    let old = f.state.page.state.session.automaticInputAttemptID
    let epoch = UUID()
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves, register: f.register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    let resource = try coordinator.prepareResources(for: coordinator.prepare(#"{"mode":"custom"}"#),
      localFont: .absent, localBackground: .data(Fixture.png()))
    let ready = try awaitResult(coordinator, resources: resource), disk = try f.register.read().revision
    XCTAssertThrowsError(try coordinator.commit(ready, to: f.state.page, systemIsDark: false))
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.state.page.state.session.automaticInputAttemptID, old)
    XCTAssertEqual(f.state.page.state.session.typed, "0")
    XCTAssertEqual(input.insertionAttemptID, old)
    XCTAssertFalse(f.window.isVisible)
  }

  func testRetiredActualPageRejectsPendingCommitAndCachedInput() throws {
    let f = try Fixture(legacyNoQuit: false); defer { f.close() }
    f.wait { f.views(TypingInputView.self).first?.acceptsTextInput == true }
    let input = try XCTUnwrap(f.views(TypingInputView.self).first), staleInsert = input.onInsert
    let epoch = UUID()
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves, register: f.register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    let resource = try coordinator.prepareResources(for: coordinator.prepare(#"{"mode":"custom"}"#),
      localFont: .absent, localBackground: .data(Fixture.png()))
    let ready = try awaitResult(coordinator, resources: resource), disk = try f.register.read().revision
    f.host.rootView = AnyView(EmptyView())
    f.wait { f.settings.preferenceConfigurationSaves.captureLease() == nil }
    let typed = f.state.page.state.session.typed
    staleInsert("stale", false)
    XCTAssertEqual(f.state.page.state.session.typed, typed)
    guard case .stale = try coordinator.commit(ready, to: f.state.page, systemIsDark: false) else {
      return XCTFail("A retired actual page cannot receive the pending commit")
    }
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertFalse(f.window.isVisible)
  }
}
