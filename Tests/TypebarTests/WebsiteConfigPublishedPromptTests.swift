import AppKit
import CoreText
import ImageIO
import Observation
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigPublishedPromptTests: XCTestCase {
  @MainActor private final class Fixture {
    let directory: URL
    let owner = UUID(), router = PreferenceConfigurationSaveRouter()
    let register: WebsiteConfigFileRegister
    let coordinator: WebsiteConfigCommitCoordinator
    init() throws {
      directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-published-prompt-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: owner, save: { XCTFail("No legacy apply or save") })
      let epoch = UUID()
      coordinator = .init(router: router, register: register,
        environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    }
    func close() { router.remove(owner: owner); try? FileManager.default.removeItem(at: directory) }
    func publish(_ json: String = #"{"showAllLines":true,"fontSize":1.75}"#, font: WebsiteConfigFontResource.Local = .absent,
      background: WebsiteConfigBackgroundResource.Local = .empty,
      resources: Bool = true) throws -> WebsiteConfigCommitCoordinator.Publication {
      let ticket = try coordinator.prepare(json)
      let outcome = resources
        ? try coordinator.commit(coordinator.prepareResources(for: ticket, localFont: font, localBackground: background))
        : try coordinator.commit(ticket)
      guard case .committed(let value) = outcome else { throw Failure.notCommitted }
      return value
    }
  }
  private enum Failure: Error { case notCommitted }
  @MainActor @Observable fileprivate final class Model {
    var publication: WebsiteConfigCommitCoordinator.Publication {
      didSet { presentation = try! .init(publication: publication, owner: owner, systemIsDark: systemIsDark) }
    }
    var presentation: WebsiteConfigPublishedPresentation
    var systemIsDark = false {
      didSet { presentation.updateSystemAppearance(isDark: systemIsDark) }
    }
    let owner: UUID
    var session: TypingSession
    var ready: [PromptViewportPresentationReady] = []
    var composition = ""
    var reducesMotion = true
    let motion = PromptCaretMotionCoordinator()
    var retirements: [PromptWordRetirement] = []
    var removals: [PromptTapeWordRemoval] = []
    init(_ publication: WebsiteConfigCommitCoordinator.Publication, owner: UUID) {
      self.publication = publication; self.owner = owner
      presentation = try! .init(publication: publication, owner: owner, systemIsDark: false)
      var session = TypingSession(configuration: .words(40).with(modifiers: [.noQuit]),
        prompt: Array(repeating: "xxx", count: 40).joined(separator: " "))
      session.insertBatch("x", at: Date(timeIntervalSince1970: 4000))
      self.session = session
    }
  }
  private struct Root: View {
    let model: Model
    var width: CGFloat = 220
    var body: some View {
      ScrollView {
        makePrompt().frame(width: width)
      }.frame(width: width, height: 400)
        .background(try! model.presentation.background(fallbackStyle: .solid, reduceMotion: true))
    }
    private func makePrompt() -> some View {
      // Test fixtures are known admitted; a production importer must surface rejection.
      try! model.presentation.wholePreview(session: model.session,
        carets: { font, presentation in
          Self.carets(font: font, presentation: presentation, session: model.session)
        }, onFailure: { _ in XCTFail("Published prompt failed") },
        onReady: { model.ready.append($0) })
    }
    static func carets(font: NSFont, presentation: WebsiteConfigNativePresentation,
      session: TypingSession, attempt: UUID? = nil) -> PromptCaretNativeView.Configuration {
      .init(text: AttributedString(session.prompt), mainOffset: nil, paceOffset: nil,
        mainStyle: presentation.caretStyle, paceStyle: presentation.paceCaretStyle,
        font: font, lineSpacing: session.configuration.usesJoiningScriptPrompt ? 8 : 12,
        rightToLeft: session.configuration.usesRightToLeftPrompt, accent: .blue,
        motion: presentation.smoothCaretMotion, reducesMotion: true, frameRate: 60,
        attemptID: attempt ?? session.automaticInputAttemptID, coordinator: .init())
    }
  }
  private func find(_ root: NSView) -> PromptViewportPracticeNativeView? {
    if let found = root as? PromptViewportPracticeNativeView { return found }
    return root.subviews.lazy.compactMap { self.find($0) }.first
  }
  private struct InlineRoot: View {
    let model: Model
    var maximumTextWidth: CGFloat? = nil
    var width: CGFloat = 220
    var body: some View {
      try! Self.prompt(model, maximumTextWidth: maximumTextWidth).frame(width: width)
    }
    static func prompt(_ model: Model, maximumTextWidth: CGFloat? = nil) throws -> WebsiteConfigPublishedInlinePrompt {
      try model.presentation.inline(session: model.session, composition: model.composition,
        carets: { rendering, font, p in
          var config = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
            mainStyle: p.caretStyle, paceStyle: p.paceCaretStyle, font: font,
            lineSpacing: model.session.configuration.usesJoiningScriptPrompt ? 8 : 12,
            rightToLeft: model.session.configuration.usesRightToLeftPrompt, accent: .blue,
            motion: p.smoothCaretMotion, reducesMotion: model.reducesMotion, frameRate: 60,
            attemptID: model.session.automaticInputAttemptID, coordinator: model.motion,
            mainGlyphID: model.session.promptCaretGlyphIndex)
          config.latestInput = { .init(attemptID: model.session.automaticInputAttemptID,
            typed: model.session.typed, composition: model.composition, glyphID: model.session.promptCaretGlyphIndex) }
          return config
        }, retirement: { rendering, p in Self.context(model, rendering, p) },
        maximumTextWidth: maximumTextWidth,
        onTapeWordsRemoved: { model.removals.append($0); model.session.removeTapePromptWords($0) })
    }
    static func context(_ model: Model, _ rendering: PromptRendering,
      _ p: WebsiteConfigNativePresentation, wrongAttempt: Bool = false) -> PromptLineScrollContext {
      let field = model.session.promptCompositionField
      return .init(attemptID: wrongAttempt ? UUID() : model.session.automaticInputAttemptID,
        activeWordID: field?.index, characterOffsets: rendering.compositionTextMap?.fieldCharacterOffsets ?? [:],
        smoothScroll: p.smoothPracticeLineScroll, reducesMotion: model.reducesMotion,
        words: PromptLineScrollWord.compositionFields(field), firstRetainedWordIndex: model.session.firstRetainedPromptWordIndex,
        onRetire: { model.retirements.append($0); model.session.retirePromptWords($0) },
        followsWordReflow: PromptWordReflowPolicy.isEnabled(mode: model.session.configuration.mode,
          slowTimer: false, showAllLines: p.showAllPracticeLines), caretMotion: model.motion,
        centersActiveLine: !p.showAllPracticeLines)
    }
  }
  private func descendants<T: NSView>(_ root: NSView, _ type: T.Type) -> [T] {
    (root as? T).map { [$0] } ?? root.subviews.flatMap { descendants($0, type) }
  }
  private func background(_ root: NSView) -> WebsiteConfigPublishedBackgroundView? {
    if let found = root as? WebsiteConfigPublishedBackgroundView { return found }
    return root.subviews.lazy.compactMap { self.background($0) }.first
  }
  private func png(_ pixel: [UInt8]) throws -> Data {
    let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(pixel) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData(), output = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(output, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(output)); return data as Data
  }
  private func wait(_ host: NSView, until condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(10)
    while !condition(), Date() < deadline {
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    XCTAssertTrue(condition())
  }
  private func advance(_ font: NSFont) throws -> Double {
    var character: UniChar = 120, glyph: CGGlyph = 0, value = CGSize.zero
    XCTAssertTrue(CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1))
    CTFontGetAdvancesForGlyphs(font as CTFont, .horizontal, &glyph, &value, 1)
    return value.width
  }

  func testPublicationAppearanceFollowsSourceEventPriorityWithoutSaving() throws {
    let f = try Fixture(); defer { f.close() }
    for follows in [false, true] {
      for custom in [false, true] {
        for dark in [false, true] {
          let publication = try f.publish("{\"theme\":\"serika_dark\",\"themeLight\":\"serika\",\"themeDark\":\"dracula\",\"autoSwitchTheme\":\(follows),\"customTheme\":\(custom)}")
          let record = try f.register.read().state
          let presenter = try WebsiteConfigPublishedPresentation(publication: publication, owner: f.owner, systemIsDark: dark)
          let initial: WebsiteConfigNativeThemes.Selection = follows
            ? .builtIn(dark ? .dracula : .serika) : (custom ? .inlineCustom : .builtIn(.serika_dark))
          XCTAssertEqual(presenter.appearance.selection, initial)
          let changed = presenter.updateSystemAppearance(isDark: !dark)
          XCTAssertEqual(changed, follows && !custom)
          XCTAssertEqual(presenter.appearance.selection, follows && !custom ? .builtIn(dark ? .serika : .dracula) : initial)
          XCTAssertFalse(presenter.updateSystemAppearance(isDark: !dark))
          XCTAssertEqual(presenter.publication.applicationID, publication.applicationID)
          XCTAssertEqual(try f.register.read().state, record)
        }
      }
    }
    let ready = try f.publish(), unprepared = try f.publish(resources: false)
    XCTAssertThrowsError(try WebsiteConfigPublishedPresentation(publication: ready, owner: UUID(), systemIsDark: false)) {
      guard case WebsiteConfigPublishedPresentationError.wrongOwner = $0 else { return XCTFail("Wrong owner error") }
    }
    XCTAssertThrowsError(try WebsiteConfigPublishedPresentation(publication: unprepared, owner: f.owner, systemIsDark: false)) {
      guard case WebsiteConfigPublishedPresentationError.unprepared = $0 else { return XCTFail("Wrong resource error") }
    }
  }

  func testAppearanceObservationCannotReenterAnIncompleteThemeTransition() throws {
    @MainActor final class Probe { var calls = 0; var nestedResult = true }
    let f = try Fixture(); defer { f.close() }
    let publication = try f.publish(#"{"autoSwitchTheme":true,"customTheme":false,"themeLight":"serika","themeDark":"dracula"}"#)
    let presenter = try WebsiteConfigPublishedPresentation(publication: publication, owner: f.owner, systemIsDark: false)
    let probe = Probe()
    withObservationTracking { _ = presenter.appearance } onChange: {
      MainActor.assumeIsolated {
        probe.calls += 1; probe.nestedResult = presenter.updateSystemAppearance(isDark: false)
      }
    }
    XCTAssertTrue(presenter.updateSystemAppearance(isDark: true))
    XCTAssertEqual(probe.calls, 1); XCTAssertFalse(probe.nestedResult)
    XCTAssertEqual(presenter.appearance.selection, .builtIn(.dracula))
    XCTAssertTrue(presenter.updateSystemAppearance(isDark: false))
    XCTAssertEqual(presenter.appearance.selection, .builtIn(.serika))
  }

  func testMountedPublicationSharesPaletteAndUpdatesThemeWithoutReplacingResourcesOrAttempt() throws {
    let f = try Fixture(); defer { f.close() }
    let custom = try f.publish(##"{"showAllLines":true,"customTheme":true,"autoSwitchTheme":false,"customThemeColors":["#010203","#102030","#203040","#304050","#405060","#506070","#607080","#708090","#8090a0","#90a0b0"]}"##,
      background: .data(png([32, 64, 96, 255])))
    let model = Model(custom, owner: f.owner), host = NSHostingView(rootView: Root(model: model))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 220, height: 400), styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    let palette = try custom.draft.themes.makeCustomTheme(id: custom.applicationID, name: "QA palette").resolvedTheme
    wait(host) { model.ready.last?.style.theme == palette }
    XCTAssertEqual(try model.presentation.background(fallbackStyle: .solid, reduceMotion: true).theme, palette)
    let viewport = try XCTUnwrap(find(host)), attempt = model.session.automaticInputAttemptID
    let next = try f.publish(#"{"showAllLines":true,"autoSwitchTheme":true,"customTheme":false,"themeLight":"serika","themeDark":"dracula"}"#,
      background: .data(png([32, 64, 96, 255])))
    model.publication = next
    wait(host) { model.ready.last?.style.theme == AppTheme.serika.resolvedTheme }
    let record = try f.register.read().state
    guard case .ready(let image) = next.background?.state else { return XCTFail("No owned background") }
    model.systemIsDark = true
    wait(host) { model.ready.last?.style.theme == AppTheme.dracula.resolvedTheme }
    XCTAssertEqual(try model.presentation.background(fallbackStyle: .solid, reduceMotion: true).theme, AppTheme.dracula.resolvedTheme)
    XCTAssertTrue(find(host) === viewport)
    XCTAssertTrue(background(host)?.surface.player.currentSample?.frame.image === image.frames[0].image)
    XCTAssertEqual(model.ready.last?.font, next.font?.renderingFont)
    XCTAssertEqual(model.presentation.publication.applicationID, next.applicationID)
    XCTAssertEqual(model.session.automaticInputAttemptID, attempt); XCTAssertEqual(model.session.typed, "x")
    XCTAssertEqual(try f.register.read().state, record); XCTAssertFalse(window.isVisible)
    // A new publication must sample the current OS input, not reset to light.
    model.publication = try f.publish(#"{"showAllLines":true,"autoSwitchTheme":true,"customTheme":false,"themeLight":"serika","themeDark":"dracula"}"#)
    XCTAssertEqual(model.presentation.appearance.selection, .builtIn(.dracula))
  }

  func testActualPublicationReflowsPrivateSameNameFontWithoutReplacingViewportOrAttempt() throws {
    let f = try Fixture(); defer { f.close() }
    let name = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let first = try f.publish(font: .data(OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 600)),
      background: .data(png([255, 0, 0, 255])))
    let second = try f.publish(font: .data(OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 900)),
      background: .data(png([0, 0, 255, 255])))
    let model = Model(first, owner: f.owner)
    let attempt = model.session.automaticInputAttemptID, target = model.session.promptTargetID
    let host = NSHostingView(rootView: Root(model: model))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 220, height: 400),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    wait(host) { model.ready.last?.font == first.font?.renderingFont }
    let viewport = try XCTUnwrap(find(host)), height = try XCTUnwrap(model.ready.last?.height)
    guard case .ready(let firstImage) = first.background?.state,
      case .ready(let secondImage) = second.background?.state else { return XCTFail("Joint resources missing") }
    XCTAssertTrue(background(host)?.surface.player.currentSample?.frame.image === firstImage.frames[0].image)
    let record = try f.register.read().state
    model.publication = second
    wait(host) { model.ready.last?.font == second.font?.renderingFont && (model.ready.last?.height ?? 0) > height }
    XCTAssertTrue(find(host) === viewport)
    XCTAssertTrue(background(host)?.surface.player.currentSample?.frame.image === secondImage.frames[0].image,
      "The mounted background and prompt must both consume the newly selected publication")
    let ready = try XCTUnwrap(model.ready.last)
    XCTAssertEqual(try advance(ready.font), 25.2, accuracy: 0.001)
    XCTAssertEqual(ready.attemptID, attempt); XCTAssertEqual(ready.targetID, target)
    XCTAssertEqual(model.session.typed, "x"); XCTAssertEqual(try f.register.read().state, record)
    XCTAssertFalse(window.isVisible)
    XCTAssertFalse((CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []).contains(name))
  }

  func testPublishedAppearanceRatherThanLegacyDefaultsReachesReadyPresentation() throws {
    let f = try Fixture(); defer { f.close() }
    let publication = try f.publish(#"{"showAllLines":true,"fontSize":2,"flipTestColors":true,"colorfulMode":true,"typedEffect":"hide","compositionDisplay":"below","indicateTypos":"below","caretStyle":"block","paceCaretStyle":"underline","smoothCaret":"fast","highlightMode":"next_word"}"#)
    let model = Model(publication, owner: f.owner), host = NSHostingView(rootView: Root(model: model))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 220, height: 400), styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    wait(host) { !model.ready.isEmpty }
    let ready = try XCTUnwrap(model.ready.last)
    XCTAssertEqual(ready.style.fontSize, 32); XCTAssertEqual(ready.font.pointSize, 32)
    XCTAssertTrue(ready.style.flipTestColors); XCTAssertTrue(ready.style.colorfulMode)
    XCTAssertEqual(ready.style.typedCharacterEffect, publication.draft.presentation.typedCharacterEffect)
    XCTAssertEqual(ready.style.compositionDisplayStyle, publication.draft.presentation.compositionDisplayStyle)
    XCTAssertEqual(ready.style.typoIndicatorStyle, publication.draft.presentation.typoIndicatorStyle)
    XCTAssertEqual(ready.style.caretStyle, .block); XCTAssertEqual(ready.style.paceCaretStyle, .underline)
    XCTAssertEqual(ready.style.highlightMode, .nextWord)
    XCTAssertFalse(ready.style.usesTapePractice); XCTAssertFalse(window.isVisible)
  }

  func testOwnerAndResourceRejectionsRunBeforeCallerCaretBuilder() throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try f.publish(), unprepared = try f.publish(resources: false)
    let session = Model(ready, owner: f.owner).session
    for (publication, owner) in [(ready, UUID()), (unprepared, f.owner)] {
      var builds = 0
      XCTAssertThrowsError(try PromptViewportPracticePrompt(publication: publication, owner: owner,
        session: session, theme: AppTheme.serika_dark.resolvedTheme, carets: { font, presentation in
          builds += 1; return Root.carets(font: font, presentation: presentation, session: session)
        }, onFailure: { _ in XCTFail("Rejected input mounted") }))
      XCTAssertEqual(builds, 0)
    }
  }

  func testMismatchedCaretFontAndAttemptCannotProduceSplitGeometry() throws {
    let f = try Fixture(); defer { f.close() }
    let publication = try f.publish(), session = Model(publication, owner: f.owner).session
    for wrongFont in [true, false] {
      XCTAssertThrowsError(try PromptViewportPracticePrompt(publication: publication, owner: f.owner,
        session: session, theme: AppTheme.serika_dark.resolvedTheme, carets: { font, presentation in
          Root.carets(font: wrongFont ? .systemFont(ofSize: font.pointSize + 3) : font,
            presentation: presentation, session: session, attempt: wrongFont ? nil : UUID())
        }, onFailure: { _ in XCTFail("Inconsistent caret mounted") })) { error in
          guard case WebsiteConfigPublishedPromptError.inconsistentCaret = error else { return XCTFail("Wrong rejection") }
        }
    }
  }

  func testOtherPromptRoutesAreNotSilentlyRenderedAsWholePreview() throws {
    let f = try Fixture(); defer { f.close() }
    for json in [#"{"showAllLines":false}"#, #"{"tapeMode":"letter"}"#, #"{"tapeMode":"word"}"#] {
      let publication = try f.publish(json), session = Model(publication, owner: f.owner).session
      var builds = 0
      XCTAssertThrowsError(try PromptViewportPracticePrompt(publication: publication, owner: f.owner,
        session: session, theme: AppTheme.serika_dark.resolvedTheme, carets: { font, presentation in
          builds += 1; return Root.carets(font: font, presentation: presentation, session: session)
        }, onFailure: { _ in XCTFail("Wrong route mounted") })) { error in
          guard case WebsiteConfigPublishedPromptError.requiresDifferentRenderer = error else { return XCTFail("Wrong route rejection") }
        }
      XCTAssertEqual(builds, 0)
    }
  }

  func testCaretAppearanceDirectionAndSpacingMustMatchTheCommittedPrompt() throws {
    let f = try Fixture(); defer { f.close() }
    let publication = try f.publish(), session = Model(publication, owner: f.owner).session
    for mismatch in 0..<5 {
      XCTAssertThrowsError(try PromptViewportPracticePrompt(publication: publication, owner: f.owner,
        session: session, theme: AppTheme.serika_dark.resolvedTheme, carets: { font, p in
          .init(text: AttributedString(session.prompt), mainOffset: nil, paceOffset: nil,
            mainStyle: mismatch == 0 ? .off : p.caretStyle,
            paceStyle: mismatch == 1 ? .off : p.paceCaretStyle, font: font,
            lineSpacing: mismatch == 2 ? 8 : 12, rightToLeft: mismatch == 3,
            accent: .blue, motion: mismatch == 4 ? .fast : p.smoothCaretMotion,
            reducesMotion: true, frameRate: 60, attemptID: session.automaticInputAttemptID, coordinator: .init())
        }, onFailure: { _ in XCTFail("Split caret presentation mounted") })) { error in
          guard case WebsiteConfigPublishedPromptError.inconsistentCaret = error else { return XCTFail("Wrong rejection") }
        }
    }
  }

  func testPublishedOrdinaryFieldKeepsCompositionAndReflowsPrivateFont() throws {
    let f = try Fixture(); defer { f.close() }
    let name = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let json = #"{"showAllLines":false,"fontSize":1.75,"smoothCaret":"off","smoothLineScroll":false,"compositionDisplay":"replace"}"#
    let first = try f.publish(json, font: .data(OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 600)))
    let second = try f.publish(json, font: .data(OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 900)))
    let model = Model(first, owner: f.owner); model.composition = "xy"
    let host = NSHostingView(rootView: InlineRoot(model: model, maximumTextWidth: 175))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 220, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    wait(host) { self.descendants(host, PromptFieldNativeView.self).first?.intrinsicContentSize.height ?? 0 > 0 }
    let field = try XCTUnwrap(descendants(host, PromptFieldNativeView.self).first)
    let height = field.intrinsicContentSize.height, revision = field.geometryRevision
    XCTAssertLessThanOrEqual(field.bounds.width, 175.01)
    XCTAssertTrue((field.accessibilityValue() as? String ?? "").contains("xy"))
    let attempt = model.session.automaticInputAttemptID, record = try f.register.read().state
    model.publication = second
    wait(host) { field.geometryRevision > revision && field.intrinsicContentSize.height > height }
    XCTAssertTrue(descendants(host, PromptFieldNativeView.self).first === field)
    XCTAssertEqual(model.session.typed, "x"); XCTAssertEqual(model.composition, "xy")
    XCTAssertEqual(model.session.automaticInputAttemptID, attempt); XCTAssertEqual(try f.register.read().state, record)
    XCTAssertFalse(window.isVisible)
  }

  func testPublishedTapeSelectsBothModesAndUsesSourceMarginWithoutRestart() throws {
    let f = try Fixture(); defer { f.close() }
    let name = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let data = OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 600)
    let letter = try f.publish(#"{"tapeMode":"letter","tapeMargin":25,"fontSize":1.75,"smoothCaret":"off","smoothLineScroll":false}"#, font: .data(data))
    let word = try f.publish(#"{"tapeMode":"word","tapeMargin":40,"fontSize":1.75,"smoothCaret":"off","smoothLineScroll":false}"#, font: .data(data))
    let model = Model(letter, owner: f.owner)
    let host = NSHostingView(rootView: InlineRoot(model: model))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 220, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { descendants(host, TapePromptNativeView.self).forEach { $0.stop() }; window.contentView = nil; window.close() }
    wait(host) { !self.descendants(host, TapePromptNativeView.self).isEmpty }
    let tape = try XCTUnwrap(descendants(host, TapePromptNativeView.self).first)
    tape.present(at: ProcessInfo.processInfo.systemUptime)
    let firstOrigin = try XCTUnwrap(tape.subviews.first).frame.minX
    let attempt = model.session.automaticInputAttemptID
    model.publication = word
    wait(host) {
      tape.present(at: ProcessInfo.processInfo.systemUptime)
      return (tape.subviews.first?.frame.minX ?? firstOrigin) > firstOrigin + 20
    }
    XCTAssertTrue(descendants(host, TapePromptNativeView.self).first === tape)
    XCTAssertEqual(model.motion.wordsTapeMargin, 0, accuracy: 0.01)
    XCTAssertEqual(model.session.automaticInputAttemptID, attempt); XCTAssertEqual(model.session.typed, "x")
    XCTAssertFalse(window.isVisible)
  }

  func testInlineRejectsForeignOwnerBeforeCallbacksAndRejectsOldRetirement() throws {
    let f = try Fixture(); defer { f.close() }
    let publication = try f.publish(#"{"showAllLines":false}"#), model = Model(publication, owner: f.owner)
    var builds = 0
    for foreign in [true, false] {
      XCTAssertThrowsError(try WebsiteConfigPublishedInlinePrompt(publication: publication,
        owner: foreign ? UUID() : f.owner, session: model.session, theme: AppTheme.serika_dark.resolvedTheme,
        carets: { _, font, p in builds += 1; return Root.carets(font: font, presentation: p, session: model.session) },
        retirement: { rendering, p in InlineRoot.context(model, rendering, p, wrongAttempt: true) })) { error in
          if foreign {
            guard case WebsiteConfigPublishedPromptError.wrongOwner = error else { return XCTFail("Wrong owner rejection") }
          } else {
            guard case WebsiteConfigPublishedPromptError.inconsistentRetirement = error else { return XCTFail("Old retirement accepted") }
          }
        }
      XCTAssertEqual(builds, foreign ? 0 : 1)
    }
  }

  func testInlineInvalidWidthDoesNotCallInputOrRetirementBuilders() throws {
    let f = try Fixture(); defer { f.close() }
    let publication = try f.publish(#"{"showAllLines":false}"#), model = Model(publication, owner: f.owner)
    var builds = 0
    for width: CGFloat in [0, -1, .nan, .infinity] {
      XCTAssertThrowsError(try WebsiteConfigPublishedInlinePrompt(publication: publication, owner: f.owner,
        session: model.session, theme: AppTheme.serika_dark.resolvedTheme,
        carets: { _, font, p in builds += 1; return Root.carets(font: font, presentation: p, session: model.session) },
        retirement: { rendering, p in builds += 1; return InlineRoot.context(model, rendering, p) }, maximumTextWidth: width)) { error in
          guard case WebsiteConfigPublishedPromptError.invalidGeometry = error else { return XCTFail("Wrong geometry rejection") }
        }
    }
    XCTAssertEqual(builds, 0)
  }

  func testPublishedSpecialRoutesAdmitTheirExistingDedicatedConsumers() throws {
    let f = try Fixture(); defer { f.close() }
    for (name, modifier) in [("asl", TestModifier.aslVisual), ("choo_choo", .chooVisual)] {
      let publication = try f.publish(#"{"showAllLines":false,"fontSize":1.75,"smoothCaret":"off","smoothLineScroll":false,"funbox":[""# + name + #""]}"#)
      let model = Model(publication, owner: f.owner)
      var session = TypingSession(configuration: .words(40).with(modifiers: [.noQuit, modifier]),
        prompt: Array(repeating: "xxx", count: 40).joined(separator: " "))
      session.insertBatch("x", at: Date(timeIntervalSince1970: 4000)); model.session = session
      XCTAssertNoThrow(try InlineRoot.prompt(model), "A supported dedicated renderer must not be rejected: \(name)")
    }
  }

  func testCompletePublicationAcceptsEverySourceWidthDomainBoundaryAndFraction() throws {
    let f = try Fixture(); defer { f.close() }
    for width in [20.0, 30.5, 1000] {
      let publication = try f.publish("{\"maxLineWidth\":\(width)}")
      XCTAssertEqual(publication.draft.keyboardTypography.columns, width)
      XCTAssertEqual(publication.draft.projection.runtime["maxLineWidth"], .number(width))
      XCTAssertEqual(try f.register.read().state, .available(publication.draft.projection.runtime))
      XCTAssertThrowsError(try publication.draft.keyboardTypography.applying(to: .init())) {
        XCTAssertEqual($0 as? WebsiteConfigNativeKeyboardTypographyError, .unrepresentableField("maxLineWidth"))
      }
    }
  }

  func testCommittedZeroAdvanceSizesBothPromptConsumersAndTracksSameNameReplacement() throws {
    let f = try Fixture(); defer { f.close() }
    let name = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let firstData = OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 600, character: 48)
    let secondData = OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 900, character: 48)
    for all in [false, true] {
      let json = "{\"fontSize\":1.75,\"showAllLines\":\(all),\"maxLineWidth\":30.5,\"smoothCaret\":\"off\",\"smoothLineScroll\":false}"
      let first = try f.publish(json, font: .data(firstData)), second = try f.publish(json, font: .data(secondData))
      XCTAssertEqual(try XCTUnwrap(first.font?.chAdvance), 16.8, accuracy: 0.001)
      XCTAssertEqual(try XCTUnwrap(second.font?.chAdvance), 25.2, accuracy: 0.001)
      let model = Model(first, owner: f.owner)
      model.session = TypingSession(configuration: .words(40), prompt: Array(repeating: "000", count: 40).joined(separator: " "))
      model.session.insertBatch("0", at: Date(timeIntervalSince1970: 4000))
      let attempt = model.session.automaticInputAttemptID
      let root = all ? AnyView(Root(model: model, width: 900)) : AnyView(InlineRoot(model: model, width: 900))
      let host = NSHostingView(rootView: root)
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentView = host
      defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close() }
      func width() -> CGFloat {
        all ? model.ready.last?.width ?? 0 : descendants(host, PromptFieldNativeView.self).first?.bounds.width ?? 0
      }
      var boundedScroll: NSScrollView?
      if !all {
        wait(host) { !self.descendants(host, PromptFieldNativeView.self).isEmpty }
        let field = try XCTUnwrap(descendants(host, PromptFieldNativeView.self).first)
        let scroll = try XCTUnwrap(field.enclosingScrollView)
        scroll.scrollerStyle = .legacy
        boundedScroll = scroll
      }
      wait(host) { abs(width() - 512.4) < 1 }
      XCTAssertEqual(width(), 512.4, accuracy: 1, "Initial width; all=\(all), host=\(host.bounds), fields=\(descendants(host, PromptFieldNativeView.self).map(\.frame)), ready=\(model.ready.last as Any)")
      model.publication = second
      wait(host) { abs(width() - 768.6) < 1 }
      XCTAssertEqual(width(), 768.6, accuracy: 1, "Replacement width; all=\(all), host=\(host.bounds), fields=\(descendants(host, PromptFieldNativeView.self).map(\.frame)), ready=\(model.ready.last as Any)")
      if let scroll = boundedScroll {
        XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1,
          "Legacy indicators must not consume the configured prompt width")
        scroll.scrollerStyle = .overlay
        wait(host) { abs(width() - 768.6) < 1 }
        XCTAssertEqual(scroll.contentSize.width, scroll.bounds.width, accuracy: 1)
        scroll.scrollerStyle = .legacy
        wait(host) { abs(width() - 768.6) < 1 }
      }
      XCTAssertEqual(model.session.typed, "0"); XCTAssertEqual(model.session.automaticInputAttemptID, attempt)
      XCTAssertFalse(window.isVisible)
    }
    XCTAssertFalse((CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []).contains(name))
  }

  func testSourceWidthsStayFluidForZeroAndTapeAndHostLimitCannotWidenThem() throws {
    let f = try Fixture(); defer { f.close() }
    for json in [#"{"maxLineWidth":0}"#, #"{"maxLineWidth":20.5,"tapeMode":"letter"}"#,
      #"{"maxLineWidth":1000,"tapeMode":"word"}"#] {
      let publication = try f.publish(json)
      let inputs = try WebsiteConfigPublishedPromptInputs(publication: publication, owner: f.owner)
      XCTAssertNil(inputs.maximumTextWidth)
      XCTAssertEqual(try inputs.width(limitedBy: 180), 180)
      if inputs.presentation.practiceTapeMode != .off {
        let model = Model(publication, owner: f.owner)
        let host = NSHostingView(rootView: InlineRoot(model: model, width: 900))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 200), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { descendants(host, TapePromptNativeView.self).forEach { $0.stop() }; window.contentView = nil; window.close() }
        wait(host) { abs((self.descendants(host, TapePromptNativeView.self).first?.bounds.width ?? 0) - 900) < 1 }
        XCTAssertFalse(window.isVisible)
      }
    }
    let publication = try f.publish(#"{"maxLineWidth":20.5}"#)
    let inputs = try WebsiteConfigPublishedPromptInputs(publication: publication, owner: f.owner)
    let cap = try XCTUnwrap(inputs.maximumTextWidth)
    XCTAssertEqual(try inputs.width(limitedBy: cap + 100), cap)
    XCTAssertEqual(try inputs.width(limitedBy: cap / 2), cap / 2)
  }

  private func specialSession(_ modifier: TestModifier) -> TypingSession {
    var session = TypingSession(configuration: .words(40).with(modifiers: [.noQuit, modifier]),
      prompt: Array(repeating: "xxx", count: 40).joined(separator: " "))
    session.insertBatch("x", at: Date(timeIntervalSince1970: 4000)); return session
  }

  func testPublishedASLActuallyMountsHandGeometryAndResizesWithoutResettingComposition() throws {
    let f = try Fixture(); defer { f.close() }
    let name = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let data = OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 600)
    let first = try f.publish(#"{"fontSize":1.75,"funbox":["asl"],"showAllLines":false,"smoothCaret":"off","smoothLineScroll":false}"#, font: .data(data))
    let second = try f.publish(#"{"fontSize":2.5,"funbox":["asl"],"showAllLines":false,"smoothCaret":"off","smoothLineScroll":false}"#, font: .data(data))
    let model = Model(first, owner: f.owner); model.session = specialSession(.aslVisual); model.composition = "xy"
    let attempt = model.session.automaticInputAttemptID
    let inputs = try WebsiteConfigPublishedPromptInputs(publication: first, owner: f.owner)
    let rendering = PromptRenderPlan(session: model.session, composition: model.composition,
      style: inputs.style(theme: AppTheme.serika_dark.resolvedTheme)).render()
    let cell = try XCTUnwrap(rendering.compositionTextMap?.fieldRuns.first?.cells.first?.id)
    let host = NSHostingView(rootView: InlineRoot(model: model))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 220, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    wait(host) { self.descendants(host, ASLPromptCaretContainer.self).first?.measuredRect(for: cell) != nil }
    let hand = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let before = try XCTUnwrap(hand.measuredRect(for: cell))
    XCTAssertTrue(descendants(host, PromptFieldNativeView.self).isEmpty, "ASL must not silently become ordinary text")
    model.publication = second
    wait(host) { (self.descendants(host, ASLPromptCaretContainer.self).first?.measuredRect(for: cell)?.height ?? 0) > before.height }
    XCTAssertEqual(model.session.typed, "x"); XCTAssertEqual(model.composition, "xy")
    XCTAssertEqual(model.session.automaticInputAttemptID, attempt)
    wait(host) {
      self.descendants(host, PromptCaretNativeView.self).forEach { $0.present(at: ProcessInfo.processInfo.systemUptime) }
      return model.motion.main.visibleRect != nil
    }
    XCTAssertNotNil(model.motion.main.visibleRect)
    XCTAssertFalse(window.isVisible)
    XCTAssertFalse((CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []).contains(name))
  }

  func testPublishedChooUsesPreparedPrivateFontAndRespectsBothMotionPolicies() throws {
    let f = try Fixture(); defer { f.close() }
    let name = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let publication = try f.publish(#"{"fontSize":1.75,"funbox":["choo_choo"],"showAllLines":false,"smoothCaret":"off","smoothLineScroll":false}"#,
      font: .data(OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 600)))
    let model = Model(publication, owner: f.owner); model.session = specialSession(.chooVisual)
    model.composition = "xx"; model.reducesMotion = false
    let host = NSHostingView(rootView: InlineRoot(model: model).environment(\.typebarSystemReduceMotionOverride, true))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 220, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { self.descendants(host, ChooLayerView.self).forEach { $0.stop() }; window.contentView = nil; window.close() }
    func layers(_ view: ChooLayerView?) -> [CATextLayer] {
      view?.layer?.sublayers?.compactMap { $0 as? CATextLayer }.filter { $0.name != "chooHint" } ?? []
    }
    wait(host) { layers(self.descendants(host, ChooLayerView.self).first).contains { $0.animation(forKey: "chooRotation") != nil } }
    let choo = try XCTUnwrap(descendants(host, ChooLayerView.self).first)
    let layer = try XCTUnwrap(layers(choo).first)
    let text = try XCTUnwrap(layer.string as? NSAttributedString)
    let font = try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    XCTAssertEqual(font.fontName, name); XCTAssertEqual(try advance(font), 16.8, accuracy: 0.001)
    XCTAssertTrue(descendants(host, PromptFieldNativeView.self).isEmpty)
    model.reducesMotion = true
    wait(host) { !layers(choo).isEmpty && layers(choo).allSatisfy { $0.animation(forKey: "chooRotation") == nil } }
    XCTAssertTrue(descendants(host, ChooLayerView.self).first === choo)
    XCTAssertEqual(model.session.typed, "x"); XCTAssertEqual(model.composition, "xx")
    XCTAssertFalse(window.isVisible)
    XCTAssertFalse((CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []).contains(name))
  }
}
