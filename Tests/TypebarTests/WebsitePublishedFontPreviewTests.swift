import AppKit
import CoreText
import Observation
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WebsitePublishedFontPreviewTests: XCTestCase {
  @MainActor fileprivate final class Fixture {
    let suite = "typebar.published-font-preview.\(UUID())"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-published-font-preview-\(UUID())")
    let defaults: UserDefaults, settings: AppSettings, account: AccountSession, page: PracticePageSessionStore
    let workflow: WebsiteConfigImportWorkflow
    init(local: Data? = nil) throws {
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory(),
        localPracticeFontResources: .inMemory(data: local))
      let page = PracticePageSessionStore(), account = AccountSession(defaults: defaults)
      self.defaults = defaults; self.settings = settings; self.page = page; self.account = account
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      settings.preferenceConfigurationSaves.register(owner: page.owner, save: { XCTFail("Preview saved native preferences") })
      page.attach(to: settings.preferenceConfigurationSaves)
      workflow = .init(page: page, settings: settings, account: account, directory: directory,
        readWindow: { .published(owner: page.owner, revision: page.state.session.automaticInputAttemptID,
          scope: page.state.practice?.scope ?? .init()) })
    }
    func publish(showAllLines: Bool = false, noQuit: Bool = false) async throws {
      try await workflow.apply(json: noQuit
        ? #"{"mode":"words","words":5,"fontFamily":"Courier","fontSize":2,"maxLineWidth":20,"funbox":["no_quit"]}"#
        : #"{"mode":"words","words":5,"fontFamily":"Courier","fontSize":2,"maxLineWidth":20}"#,
        systemIsDark: false)
      if showAllLines, let id = page.state.presentation?.publication.applicationID {
        _ = try await workflow.editAndBegin(.appearance(.showAllLines(true)), replacing: id, systemIsDark: false)
      }
    }
    func close() {
      workflow.stop(); page.detach(); settings.preferenceConfigurationSaves.remove(owner: page.owner)
      defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory)
    }
  }
  private func item(_ id: String) -> CommandPaletteItem {
    .init(id: id, title: id, subtitle: "", systemImage: "textformat", keywords: [], group: .appearance)
  }
  func testHoverActuallyChangesPublishedPromptInputsWithoutChangingThePublication() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let publication = try XCTUnwrap(f.page.state.presentation?.publication)
    let disk = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    let generation = f.page.state.session.generationState, preferences = f.settings.snapshot
    var state = FontFamilyCommandPreviewState()
    state.select(item("setFontFamilyGeorgia"), savedFont: f.settings.practiceFont,
      savedName: publication.draft.keyboardTypography.fontFamily)
    let preview = try XCTUnwrap(WebsiteConfigFontPreview().prepare(state, publication: publication, owner: f.page.owner))
    let inputs = try WebsiteConfigPublishedPromptInputs(publication: publication, owner: f.page.owner, fontPreview: preview)
    XCTAssertEqual(inputs.font.fontName, NSFont(name: "Georgia", size: 32)?.fontName)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    XCTAssertEqual(f.page.state.session.generationState, generation)
    XCTAssertEqual(f.settings.snapshot, preferences)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, disk)
  }

  func testPreviewAndDismissalBypassLocalFileWhileApplyReturnsToTheOwnedResource() async throws {
    let data = OwnedTestFontFixture.make(postScriptName: "TypebarBasePreviewFont")
    let f = try Fixture(local: data); defer { f.close() }; try await f.publish()
    let p = try XCTUnwrap(f.page.state.presentation?.publication), cache = WebsiteConfigFontPreview()
    XCTAssertEqual(p.font?.ownedLocalData, data)
    let disk = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    var state = FontFamilyCommandPreviewState()
    state.select(item("setFontFamilyGeorgia"), savedFont: .monospaced, savedName: "Courier")
    let hovered = try XCTUnwrap(cache.prepare(state, publication: p, owner: f.page.owner))
    XCTAssertEqual(hovered.font.fontName, NSFont(name: "Georgia", size: 32)?.fontName)
    XCTAssertEqual(hovered.candidates, [.family("Georgia"), .family("Roboto_Mono"), .family("Vazirharf"), .monospace])
    state.clear(savedFont: .monospaced, savedName: p.draft.keyboardTypography.fontFamily)
    let restored = try XCTUnwrap(cache.prepare(state, publication: p, owner: f.page.owner))
    XCTAssertFalse(state.isPreviewing)
    XCTAssertEqual(restored.font.fontName, NSFont(name: "Courier", size: 32)?.fontName)
    state.appliedFontFamily()
    XCTAssertNil(cache.prepare(state, publication: p, owner: f.page.owner))
    let applied = try WebsiteConfigPublishedPromptInputs(publication: p, owner: f.page.owner)
    XCTAssertEqual(applied.font.fontName, "TypebarBasePreviewFont")
    XCTAssertEqual(p.font?.ownedLocalData, data)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, disk)
  }

  func testPreviewMetricsAndCacheFollowSizeButDoNotDependOnUnrelatedPublicationChanges() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let cache = WebsiteConfigFontPreview(); var state = FontFamilyCommandPreviewState()
    state.select(item("setFontFamilyGeorgia"), savedFont: .monospaced, savedName: "Courier")
    let firstPublication = try XCTUnwrap(f.page.state.presentation?.publication)
    let first = try XCTUnwrap(cache.prepare(state, publication: firstPublication, owner: f.page.owner))
    let inputs = try WebsiteConfigPublishedPromptInputs(publication: firstPublication, owner: f.page.owner, fontPreview: first)
    XCTAssertEqual(try XCTUnwrap(inputs.maximumTextWidth), 20 * first.chAdvance, accuracy: 0.001)
    _ = try await f.workflow.editAndBegin(.numbers(true), replacing: firstPublication.applicationID, systemIsDark: false)
    let next = try XCTUnwrap(f.page.state.presentation?.publication)
    let same = try XCTUnwrap(cache.prepare(state, publication: next, owner: f.page.owner))
    XCTAssertTrue(first.font === same.font)
    _ = try f.workflow.runFontCommand(.size(37.5), replacing: next.applicationID)
    let resizedPublication = try XCTUnwrap(f.page.state.presentation?.publication)
    XCTAssertThrowsError(try WebsiteConfigPublishedPromptInputs(publication: resizedPublication, owner: f.page.owner, fontPreview: first)) {
      guard case WebsiteConfigPublishedPromptError.invalidGeometry = $0 else { return XCTFail("Wrong stale-size rejection") }
    }
    let resized = try XCTUnwrap(cache.prepare(state, publication: resizedPublication, owner: f.page.owner))
    XCTAssertEqual(resized.font.pointSize, 37.5)
    XCTAssertEqual(resized.font.fontName, first.font.fontName)
    XCTAssertFalse(resized.font === first.font)
  }

  func testAnotherWindowCannotBorrowThePreviewToken() async throws {
    let first = try Fixture(), second = try Fixture(); defer { first.close(); second.close() }
    try await first.publish(); try await second.publish()
    var state = FontFamilyCommandPreviewState()
    state.select(item("setFontFamilyGeorgia"), savedFont: .monospaced, savedName: "Courier")
    let a = try XCTUnwrap(first.page.state.presentation?.publication), b = try XCTUnwrap(second.page.state.presentation?.publication)
    let cache = WebsiteConfigFontPreview(), token = try XCTUnwrap(cache.prepare(state, publication: a, owner: first.page.owner))
    XCTAssertNil(cache.prepare(state, publication: a, owner: second.page.owner))
    XCTAssertThrowsError(try WebsiteConfigPublishedPromptInputs(publication: b, owner: second.page.owner, fontPreview: token)) {
      guard case WebsiteConfigPublishedPromptError.wrongOwner = $0 else { return XCTFail("Wrong preview owner rejection") }
    }
  }

  func testDismissalKeepsAllFourNativeSystemDesignsWithoutExposingPrivateNames() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let p = try XCTUnwrap(f.page.state.presentation?.publication), cache = WebsiteConfigFontPreview()
    for design in PracticeFont.allCases {
      var state = FontFamilyCommandPreviewState()
      state.select(item("setFontFamilyGeorgia"), savedFont: .monospaced, savedName: "Courier")
      state.clear(savedFont: .monospaced, savedName: NativeSystemPracticeFont.identifier(for: design))
      let restored = try XCTUnwrap(cache.prepare(state, publication: p, owner: f.page.owner))
      let native = design.nsFont(size: 32, resolver: .init(localFont: { _ in nil }))
      let resource = try WebsiteConfigFontResource.preview(family: NativeSystemPracticeFont.identifier(for: design), size: 32)
      XCTAssertEqual(resource.primary.font.fontName, native.fontName)
      func width(_ font: NSFont) -> Double {
        CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: "Hamburgefonstiv 0123456789",
          attributes: [.font: font]) as CFAttributedString), nil, nil, nil)
      }
      XCTAssertEqual(width(restored.font), width(native), accuracy: 0.001)
      XCTAssertEqual(restored.font.pointSize, 32)
    }
  }

  func testPreviewResourceRejectsInvalidSizesAndRetainsOnlyItsOwnFallbackChain() throws {
    for value in [0, -1, Double.infinity, .nan] {
      XCTAssertThrowsError(try WebsiteConfigFontResource.preview(family: "Courier", size: value)) {
        XCTAssertEqual($0 as? WebsiteConfigFontResourceError, .invalidSize)
      }
    }
    let resource = try WebsiteConfigFontResource.preview(family: "Typebar_Absent_Preview_Face", size: 31.25)
    XCTAssertEqual(resource.primary.font.pointSize, 31.25)
    XCTAssertEqual(resource.faces.last?.candidate, .monospace)
    XCTAssertNil(resource.ownedLocalData); XCTAssertNil(resource.localFailure)
  }

  func testPreviewCannotMaskAnUnpreparedPublication() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let p = try XCTUnwrap(f.page.state.presentation?.publication)
    var state = FontFamilyCommandPreviewState()
    state.select(item("setFontFamilyGeorgia"), savedFont: .monospaced, savedName: "Courier")
    let token = try XCTUnwrap(WebsiteConfigFontPreview().prepare(state, publication: p, owner: f.page.owner))
    let epoch = UUID(), coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves,
      register: .init(directory: f.directory), environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    guard case .committed(let unprepared) = try coordinator.commit(coordinator.prepare(#"{"mode":"words","words":5}"#))
    else { return XCTFail("Unprepared fixture not committed") }
    XCTAssertThrowsError(try WebsiteConfigPublishedPromptInputs(publication: unprepared, owner: f.page.owner, fontPreview: token)) {
      guard case WebsiteConfigPublishedPromptError.unprepared = $0 else { return XCTFail("Preview bypassed resource admission") }
    }
  }

  func testActiveNoQuitPreviewKeepsInputLeaseAndSavedValues() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish(noQuit: true)
    var active = f.page.state; active.session.insertBatch(String(try XCTUnwrap(active.session.nextExpectedCharacter)))
    f.page.replace(active)
    let p = try XCTUnwrap(f.page.state.presentation?.publication)
    let generation = f.page.state.session.generationState, disk = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    var state = FontFamilyCommandPreviewState()
    state.select(item("setFontFamilyGeorgia"), savedFont: .monospaced, savedName: "Courier")
    let token = try XCTUnwrap(WebsiteConfigFontPreview().prepare(state, publication: p, owner: f.page.owner))
    XCTAssertEqual(try WebsiteConfigPublishedPromptInputs(publication: p, owner: f.page.owner, fontPreview: token).font.fontName,
      NSFont(name: "Georgia", size: 32)?.fontName)
    XCTAssertTrue(f.page.acceptsInput(for: active.session.automaticInputAttemptID))
    XCTAssertEqual(f.page.state.session.generationState, generation)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, p.applicationID)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, disk)
  }

  private static func carets(_ font: NSFont, _ p: WebsiteConfigNativePresentation,
    _ session: TypingSession, motion: PromptCaretMotionCoordinator) -> PromptCaretNativeView.Configuration {
    .init(text: AttributedString(session.prompt), mainOffset: nil, paceOffset: nil,
      mainStyle: p.caretStyle, paceStyle: p.paceCaretStyle, font: font,
      lineSpacing: session.configuration.usesJoiningScriptPrompt ? 8 : 12,
      rightToLeft: session.configuration.usesRightToLeftPrompt, accent: .blue,
      motion: p.smoothCaretMotion, reducesMotion: true, frameRate: 60,
      attemptID: session.automaticInputAttemptID, coordinator: motion)
  }
  func testWholeAndInlineConsumersShareThePreviewFontAndCaretGeometry() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish(showAllLines: true)
    let p = try XCTUnwrap(f.page.state.presentation), session = f.page.state.session, motion = PromptCaretMotionCoordinator()
    var state = FontFamilyCommandPreviewState(), seen: [NSFont] = []
    state.select(item("setFontFamilyGeorgia"), savedFont: .monospaced, savedName: "Courier")
    let token = try XCTUnwrap(WebsiteConfigFontPreview().prepare(state, publication: p.publication, owner: f.page.owner))
    _ = try p.wholePreview(session: session, fontPreview: token, carets: { font, presentation in
      seen.append(font); return Self.carets(font, presentation, session, motion: motion)
    }, onFailure: { _ in XCTFail("Unmounted viewport failed") })
    _ = try p.inline(session: session, fontPreview: token, carets: { _, font, presentation in
      seen.append(font); return Self.carets(font, presentation, session, motion: motion)
    }, retirement: { rendering, presentation in
      let field = session.promptCompositionField
      return .init(attemptID: session.automaticInputAttemptID, activeWordID: field?.index,
        characterOffsets: rendering.compositionTextMap?.fieldCharacterOffsets ?? [:],
        smoothScroll: presentation.smoothPracticeLineScroll, reducesMotion: true,
        words: PromptLineScrollWord.compositionFields(field), firstRetainedWordIndex: session.firstRetainedPromptWordIndex,
        followsWordReflow: PromptWordReflowPolicy.isEnabled(mode: session.configuration.mode, slowTimer: false,
          showAllLines: presentation.showAllPracticeLines), caretMotion: motion, centersActiveLine: !presentation.showAllPracticeLines)
    })
    XCTAssertEqual(seen.count, 2); XCTAssertTrue(seen.allSatisfy { $0 === token.font })
  }

  @MainActor @Observable fileprivate final class MountedModel {
    let fixture: Fixture
    var state = FontFamilyCommandPreviewState()
    var showing = false
    var ready: [PromptViewportPresentationReady] = []
    let cache = WebsiteConfigFontPreview(), motion = PromptCaretMotionCoordinator()
    init(_ fixture: Fixture) { self.fixture = fixture }
    func select(_ item: CommandPaletteItem?) {
      state.select(item, savedFont: fixture.settings.practiceFont,
        savedName: fixture.page.state.presentation?.publication.draft.keyboardTypography.fontFamily ?? "")
    }
    func clear() {
      state.clear(savedFont: fixture.settings.practiceFont,
        savedName: fixture.page.state.presentation?.publication.draft.keyboardTypography.fontFamily ?? "")
    }
    func prompt() throws -> PromptViewportPracticePrompt {
      let p = try XCTUnwrap(fixture.page.state.presentation), session = fixture.page.state.session
      return try p.wholePreview(session: session, fontPreview: cache.prepare(state, publication: p.publication, owner: fixture.page.owner),
        carets: { font, presentation in WebsitePublishedFontPreviewTests.carets(font, presentation, session, motion: self.motion) },
        onFailure: { _ in XCTFail("Mounted published preview failed") }, onReady: { self.ready.append($0) })
    }
  }
  private struct MountedRoot: View {
    let model: MountedModel
    var body: some View {
      ZStack {
        ScrollView {
          if let prompt = try? model.prompt() { prompt }
        }
        if model.showing {
          CommandPaletteView(items: [.init(id: "setFontFamilyGeorgia", title: "Georgia", subtitle: "", systemImage: "textformat", keywords: [], group: .appearance)],
            listMode: .singleList, onSelect: { _ in }, onPreview: { model.select($0) })
        }
      }.frame(width: 600, height: 500)
        .onChange(of: model.showing) { _, showing in if !showing { model.clear() } }
    }
  }
  func testActualHiddenPaletteUpdatesTextKitAndRestoresSavedFamilyWithoutPublishing() async throws {
    let data = OwnedTestFontFixture.make(postScriptName: "TypebarMountedPreviewBase")
    let f = try Fixture(local: data); defer { f.close() }; try await f.publish(showAllLines: true)
    let p = try XCTUnwrap(f.page.state.presentation?.publication), model = MountedModel(f)
    _ = try model.prompt()
    let disk = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    let generation = f.page.state.session.generationState, preferences = f.settings.snapshot
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: MountedRoot(model: model)); window.contentView = host
    defer { window.contentView = nil; window.close() }
    func wait(_ condition: () -> Bool) async {
      let deadline = Date().addingTimeInterval(2)
      repeat {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(20))
        host.layoutSubtreeIfNeeded()
      } while !condition() && Date() < deadline
    }
    await wait { model.ready.last?.font == p.font?.renderingFont }
    XCTAssertEqual(model.ready.last?.font.fontName, "TypebarMountedPreviewBase")
    model.showing = true
    await wait { model.ready.last?.font.fontName == NSFont(name: "Georgia", size: 32)?.fontName }
    XCTAssertTrue(model.state.isPreviewing)
    XCTAssertEqual(model.ready.last?.font.fontName, NSFont(name: "Georgia", size: 32)?.fontName)
    model.showing = false
    await wait { model.ready.last?.font.fontName == NSFont(name: "Courier", size: 32)?.fontName }
    XCTAssertFalse(model.state.isPreviewing)
    XCTAssertEqual(model.ready.last?.font.fontName, NSFont(name: "Courier", size: 32)?.fontName)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, p.applicationID)
    XCTAssertEqual(f.page.state.session.generationState, generation)
    XCTAssertEqual(f.settings.snapshot, preferences)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, disk)
    XCTAssertFalse(window.isVisible)
  }
}
