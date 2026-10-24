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
    init(followsSystem: Bool = false) throws {
      directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-practice-publication-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = AppSettings(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}),
        localBackgroundStore: .inMemory())
      settings.reducePracticeMotion = true; settings.showAllPracticeLines = true
      settings.testModifiers = [.noQuit]
      let config = TestConfiguration.words(201).with(modifiers: [.noQuit])
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
        publishedPresentation: state.usesPublished ? state.presentation : nil)
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
    resources: WebsiteConfigCommitCoordinator.ResourcesPrepared) throws -> WebsiteConfigCommitCoordinator.SessionPrepared {
    var result: Result<WebsiteConfigCommitCoordinator.SessionPrepared, Error>?
    let task = Task { @MainActor in
      do { result = .success(try await coordinator.preparePractice(for: resources, scope: .init(customText: "ab"))) }
      catch { result = .failure(error) }
    }
    defer { task.cancel() }
    let deadline = Date().addingTimeInterval(10)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return try XCTUnwrap(result).get()
  }
}
