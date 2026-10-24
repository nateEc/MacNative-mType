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
    var publication: WebsiteConfigCommitCoordinator.Publication
    let owner: UUID
    var session: TypingSession
    var ready: [PromptViewportPresentationReady] = []
    var composition = ""
    let motion = PromptCaretMotionCoordinator()
    var retirements: [PromptWordRetirement] = []
    var removals: [PromptTapeWordRemoval] = []
    init(_ publication: WebsiteConfigCommitCoordinator.Publication, owner: UUID) {
      self.publication = publication; self.owner = owner
      var session = TypingSession(configuration: .words(40).with(modifiers: [.noQuit]),
        prompt: Array(repeating: "xxx", count: 40).joined(separator: " "))
      session.insertBatch("x", at: Date(timeIntervalSince1970: 4000))
      self.session = session
    }
  }
  private struct Root: View {
    let model: Model
    var body: some View {
      ScrollView {
        makePrompt().frame(width: 220)
      }.frame(width: 220, height: 400)
        .background(try! WebsiteConfigPublishedBackground(publication: model.publication, owner: model.owner,
          fallbackStyle: .solid, theme: AppTheme.serika_dark.resolvedTheme, reduceMotion: true))
    }
    private func makePrompt() -> some View {
      // Test fixtures are known admitted; a production importer must surface rejection.
      try! PromptViewportPracticePrompt(publication: model.publication, owner: model.owner,
        session: model.session, theme: AppTheme.serika_dark.resolvedTheme,
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
    var body: some View {
      try! WebsiteConfigPublishedInlinePrompt(publication: model.publication, owner: model.owner,
        session: model.session, composition: model.composition, theme: AppTheme.serika_dark.resolvedTheme,
        carets: { rendering, font, p in
          var config = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
            mainStyle: p.caretStyle, paceStyle: p.paceCaretStyle, font: font,
            lineSpacing: model.session.configuration.usesJoiningScriptPrompt ? 8 : 12,
            rightToLeft: model.session.configuration.usesRightToLeftPrompt, accent: .blue,
            motion: p.smoothCaretMotion, reducesMotion: true, frameRate: 60,
            attemptID: model.session.automaticInputAttemptID, coordinator: model.motion,
            mainGlyphID: model.session.promptCaretGlyphIndex)
          config.latestInput = { .init(attemptID: model.session.automaticInputAttemptID,
            typed: model.session.typed, composition: model.composition, glyphID: model.session.promptCaretGlyphIndex) }
          return config
        }, retirement: { rendering, p in Self.context(model, rendering, p) },
        maximumTextWidth: maximumTextWidth,
        onTapeWordsRemoved: { model.removals.append($0); model.session.removeTapePromptWords($0) })
        .frame(width: 220)
    }
    static func context(_ model: Model, _ rendering: PromptRendering,
      _ p: WebsiteConfigNativePresentation, wrongAttempt: Bool = false) -> PromptLineScrollContext {
      let field = model.session.promptCompositionField
      return .init(attemptID: wrongAttempt ? UUID() : model.session.automaticInputAttemptID,
        activeWordID: field?.index, characterOffsets: rendering.compositionTextMap?.fieldCharacterOffsets ?? [:],
        smoothScroll: p.smoothPracticeLineScroll, reducesMotion: true,
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
}
