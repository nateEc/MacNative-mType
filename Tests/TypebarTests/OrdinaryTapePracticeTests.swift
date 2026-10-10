import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class OrdinaryTapePracticeTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 913_300_000)

  @Observable final class Model {
    var session: TypingSession
    var mode = PracticeTapeMode.letter
    var fontSize: Double = 28
    var style = TypoIndicatorStyle.off
    var smooth = false
    var reduced = true
    var marked: String? = nil
    var latestProjection: (() -> TapePromptProjectionSnapshot?)? = nil
    let motion = PromptCaretMotionCoordinator()
    var retirements: [PromptWordRetirement] = []
    var removals: [PromptTapeWordRemoval] = []
    var onRemoval: ((PromptTapeWordRemoval) -> Void)? = nil
    init(_ session: TypingSession) { self.session = session }
    var rendering: PromptRendering {
      if let marked, let presentation = PromptCompositionPresentation(session: session, composition: marked, style: .replace) {
        return presentation.render { _, glyph, cell in AttributedString(cell?.text ?? String(glyph.character)) }
      }
      let glyphs = session.promptGlyphs, words = session.promptWordPresentations
      return .make(glyphs: glyphs, indices: PromptGlyphLayout.indices(glyphs: glyphs,
        words: words, hideExtraLetters: session.configuration.rules.hideExtraLetters,
        firstRetainedWordIndex: session.firstRetainedPromptWordIndex),
        words: words, removedTapeWordIndices: session.removedTapePromptWordIndices) { index, glyph in
        let plan = PromptControlCharacterPresentation.plan(for: glyph, style: style,
          isExtra: index >= session.prompt.count)
        var value = AttributedString(plan.text)
        value.foregroundColor = (glyph.state == .incorrect ? Color.red : Color.gray).opacity(plan.opacity)
        return value
      }
    }
  }

  private struct Root: View {
    let model: Model
    var body: some View {
      let session = model.session, rendering = model.rendering
      let attempt = session.automaticInputAttemptID, glyph = session.promptCaretGlyphIndex, typed = session.typed
      let active = session.promptWordPresentations.first { $0.phase == .active }?.range.lowerBound
      var carets = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
        mainStyle: .outline, paceStyle: .off, font: .monospacedSystemFont(ofSize: model.fontSize, weight: .medium),
        lineSpacing: 0, rightToLeft: session.configuration.usesRightToLeftPrompt, accent: .blue,
        motion: .off, reducesMotion: model.reduced, frameRate: 60,
        attemptID: attempt, coordinator: model.motion, mainGlyphID: glyph)
      carets.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: glyph) }
      carets.mainPresentation = { .init(isVisible: true, isBlinking: false) }
      let retirement = PromptLineScrollContext(attemptID: attempt, activeWordID: active,
        characterOffsets: rendering.glyphCharacterOffsets, smoothScroll: model.smooth, reducesMotion: model.reduced,
        words: session.promptWordPresentations.enumerated().map { .init(index: $0.offset, glyphID: $0.element.range.lowerBound) },
        firstRetainedWordIndex: session.firstRetainedPromptWordIndex,
        onRetire: { model.retirements.append($0); model.session.retirePromptWords($0) },
        followsWordReflow: PromptWordReflowPolicy.isEnabled(mode: session.configuration.mode,
          slowTimer: false, showAllLines: false), caretMotion: model.motion)
      let prompt = TapePracticePrompt(session: session, rendering: rendering, mode: model.mode,
        margin: 0.25, fontSize: model.fontSize, animatesScroll: model.smooth,
        carets: carets, retirement: retirement,
        latestProjection: model.latestProjection,
        onTapeWordsRemoved: { model.removals.append($0); model.session.removeTapePromptWords($0); model.onRemoval?($0) })
      return Group {
        if PracticeLineDisplayPolicy.needsOuterViewport(showsAllLines: false,
          usesTape: model.mode != .off, usesASL: false, usesChoo: false) {
          PracticePromptViewport(text: rendering.text, font: carets.font, lineSpacing: 12,
            isRightToLeft: session.configuration.usesRightToLeftPrompt, lineCount: 3,
            measuresTextRows: false) { prompt }
        } else { prompt }
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
  }
  private func mount(_ model: Model, width: CGFloat = 400) -> (NSWindow, NSHostingView<Root>) {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 240),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: Root(model: model)); window.contentView = host
    return (window, host)
  }
  private func close(_ window: NSWindow, _ host: NSView) {
    descendants(host, TapePromptNativeView.self).forEach { $0.stop() }
    window.contentView = nil; window.close()
  }
  private func geometry(_ model: Model) -> TapePromptLayoutMetrics {
    let layout = TapeNewlineTextLayout()
    layout.configure(text: model.rendering.text,
      words: TapePromptProjection.words(session: model.session, rendering: model.rendering),
      font: .monospacedSystemFont(ofSize: model.fontSize, weight: .medium),
      rightToLeft: model.session.configuration.usesRightToLeftPrompt, resets: true,
      compositionMap: model.rendering.compositionTextMap)
    return layout.metrics
  }
  private func expectedHeight(_ model: Model) -> CGFloat {
    if model.session.hasPracticeNewlineContent { return geometry(model).rowHeight * 3 }
    if model.session.prompt.contains("\n") { return geometry(model).contentHeight }
    return CGFloat(model.fontSize * 1.7)
  }

  func testProductionCompositionGateAllowsTapeWithSharedDirectionPolicy() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let start = try XCTUnwrap(source.range(of: "let usesCompositionProjection ="))
    let end = try XCTUnwrap(source.range(of: "let presentation =", range: start.upperBound..<source.endIndex))
    let gate = source[start.lowerBound..<end.lowerBound]
    XCTAssertFalse(gate.contains("!usesTapePractice"))
    XCTAssertTrue(gate.contains("composition != nil"))
    XCTAssertTrue(gate.contains("PromptFieldProjectionPolicy.supports(session.configuration)"))
    XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10)))
    for rtl in TypingLanguage.allCases.filter(\.usesRightToLeftPrompt) {
      XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .mixedLanguages,
        mixedLanguageComponents: [.english, rtl])))
    }
    XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .mixedLanguages,
      mixedLanguageComponents: [.english, .arabic, .bangla])))
    XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .mixedLanguages,
      mixedLanguageComponents: [.english, .arabic, .hindi])))
    for tamil in [TypingLanguage.tamil, .tamil1k, .tamilOld] {
      XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .mixedLanguages,
        mixedLanguageComponents: [.english, .arabic, tamil])))
    }
    for gujarati in [TypingLanguage.gujarati, .gujarati1k] {
      XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .mixedLanguages,
        mixedLanguageComponents: [.english, .arabic, gujarati])))
    }
    for devanagari in [TypingLanguage.nepali, .nepali1k, .sanskrit] {
      XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .mixedLanguages,
        mixedLanguageComponents: [.english, .arabic, devanagari])))
    }
    XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .mixedLanguages,
      mixedLanguageComponents: [.english, .arabic, .kannada])))
    XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .mixedLanguages,
      mixedLanguageComponents: [.english, .arabic, .khmer])))
    for korean in [TypingLanguage.korean, .korean1k, .korean5k] {
      XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .mixedLanguages,
        mixedLanguageComponents: [.english, .arabic, korean])))
    }
    XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .mixedLanguages,
      mixedLanguageComponents: [.english, .arabic, .malayalam])))
    XCTAssertTrue(PromptFieldProjectionPolicy.supports(.words(10, language: .mixedLanguages,
      mixedLanguageComponents: [.english, .arabic, .sinhala])))
    XCTAssertFalse(PromptFieldProjectionPolicy.supports(.words(10, language: .mixedLanguages,
      mixedLanguageComponents: [.english, .arabic, .telugu])))
  }

  func testSwiftUIBridgeUsesExplicitProjectedFieldInsteadOfLegacyCaretOffset() throws {
    var session = TypingSession(configuration: .words(3), prompt: "a\nbc tail")
    session.insertBatch("a\nb", at: start)
    let model = Model(session); model.marked = "XYZ😀"
    var latest: TapePromptProjectionSnapshot?
    var reads = 0
    model.latestProjection = { reads += 1; return latest }
    let (window, host) = mount(model)
    defer { close(window, host) }
    let owner = try settle(host, model)
    let field = try XCTUnwrap(session.promptCompositionField)
    let native = TapeNewlineTextLayout()
    native.configure(text: model.rendering.text,
      words: TapePromptProjection.words(session: session, rendering: model.rendering),
      font: .monospacedSystemFont(ofSize: model.fontSize, weight: .medium), rightToLeft: false,
      resets: true, compositionMap: model.rendering.compositionTextMap)
    let advance = try XCTUnwrap(native.projectedAdvance(fieldID: field.index,
      acceptedUTF16Count: field.inputUTF16.count, mode: .letter, hidesExtras: false, viewportWidth: 400))
    XCTAssertEqual(model.motion.wordsTapeMargin, -advance, accuracy: 0.001)
    let main = try XCTUnwrap(model.motion.main.position)
    let projected = try XCTUnwrap(native.projectedMainRect(style: .outline))
    XCTAssertEqual(main.width, projected.width, accuracy: 0.001)
    XCTAssertEqual(main.minY, try XCTUnwrap(native.projectedFieldRect(field.index)).minY, accuracy: 0.001)
    let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session, composition: "候选", style: .replace))
    let rendering = presentation.render { _, glyph, cell in AttributedString(cell?.text ?? String(glyph.character)) }
    latest = .init(input: .init(attemptID: session.automaticInputAttemptID, typed: session.typed,
      composition: "候选", glyphID: session.promptCaretGlyphIndex), field: field, rendering: rendering,
      newlineWords: TapePromptProjection.words(session: session, rendering: rendering),
      retirement: .init(attemptID: session.automaticInputAttemptID,
        activeWordID: session.promptWordPresentations[field.index].range.lowerBound,
        characterOffsets: rendering.glyphCharacterOffsets, smoothScroll: false, reducesMotion: true,
        words: session.promptWordPresentations.enumerated().map { .init(index: $0.offset, glyphID: $0.element.range.lowerBound) },
        firstRetainedWordIndex: session.firstRetainedPromptWordIndex, onRetire: { _ in }))
    reads = 0; owner.present(at: ProcessInfo.processInfo.systemUptime)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(owner.accessibilityLabel(), String(rendering.text.characters))
    XCTAssertEqual(model.marked, "XYZ😀", "Provider refresh must not require a SwiftUI model update")
  }
  @discardableResult private func settle(_ host: NSView, _ model: Model,
    retained: Int? = nil) throws -> TapePromptNativeView {
    let deadline = Date(timeIntervalSinceNow: 0.4)
    repeat {
      host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
      host.layoutSubtreeIfNeeded()
      if let view = descendants(host, TapePromptNativeView.self).first,
        view.accessibilityLabel() == String(model.rendering.text.characters),
        abs(view.bounds.height - expectedHeight(model)) < 1,
        retained.map({ model.session.firstRetainedPromptWordIndex == $0 }) ?? true {
        view.present(at: ProcessInfo.processInfo.systemUptime); return view
      }
    } while Date() < deadline
    let view = try XCTUnwrap(descendants(host, TapePromptNativeView.self).first)
    XCTFail("Expected measured Tape height=\(expectedHeight(model)), actual=\(view.bounds.height), retained=\(model.session.firstRetainedPromptWordIndex)")
    return view
  }
  private func capture(_ view: NSView, name: String) throws {
    view.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    var textInk = 0
    for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
      guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
      if color.alphaComponent > 0.2, color.redComponent > 0.2, color.redComponent < 0.8,
        abs(color.redComponent - color.greenComponent) < 0.05,
        abs(color.greenComponent - color.blueComponent) < 0.05 { textInk += 1 }
    } }
    XCTAssertGreaterThan(textInk, 20, "Require gray text pixels, not only the blue caret")
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
        URL(fileURLWithPath: directory).appendingPathComponent("ordinary-tape-\(name).png"))
    }
  }
  private func quote(_ source: String, modifiers: [TestModifier] = []) -> TypingSession {
    TestSessionFactory.make(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true), modifiers: modifiers),
      quote: .init(id: "owned-multiline-tape", title: "Owned line draft", text: source,
        language: .english, length: .long))
  }

  func testProductionTapeRouteDoesNotExcludeOrdinaryNewlineTargets() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertFalse(app.contains("settings.practiceTapeMode != .off && !session.hasPracticeNewlineContent"))
    XCTAssertTrue(app.contains("TapePracticePrompt(session: session, rendering: rendering"))
    XCTAssertTrue(app.contains("if !PracticeLineDisplayPolicy.needsOuterViewport(showsAllLines: showsAllPracticeLines"))
  }

  func testTapeOwnsItsViewportWhileOrdinaryASLAndChooKeepTheirOuterScroller() throws {
    for all in [false, true] { for tape in [false, true] {
      for asl in [false, true] { for choo in [false, true] {
        XCTAssertEqual(PracticeLineDisplayPolicy.needsOuterViewport(showsAllLines: all,
          usesTape: tape, usesASL: asl, usesChoo: choo), !all && (!tape || asl || choo))
      } }
    } }
    let model = Model(TypingSession(configuration: .words(2), prompt: "ab\ncd"))
    let (window, host) = mount(model); defer { close(window, host) }
    try settle(host, model)
    XCTAssertTrue(descendants(host, NSScrollView.self).isEmpty,
      "The actual Tape must not sit inside an independent 184-point scrolling viewport")
    XCTAssertFalse(window.isVisible)
  }

  func testShortOrdinaryNewlineTargetsReserveThreeRowsInBothTapeModes() throws {
    for mode in [TestMode.words, .time, .quote, .custom] {
      for tape in [PracticeTapeMode.word, .letter] {
        let model = Model(TypingSession(configuration: .init(mode: mode,
          duration: mode == .time ? 30 : nil, wordLimit: mode == .words ? 2 : nil,
          difficulty: .normal, rules: .init()), prompt: "ab\ncd")); model.mode = tape
        let (window, host) = mount(model); defer { close(window, host) }
        let native = try settle(host, model)
        XCTAssertEqual(native.bounds.height, geometry(model).rowHeight * 3, accuracy: 0.01)
        XCTAssertEqual(model.session.prompt, "ab\ncd"); XCTAssertFalse(window.isVisible)
        if mode == .quote { try capture(native, name: "short-\(tape.rawValue)") }
      }
    }
  }

  func testInitialQuoteSignalReservesThreeRowsBeforeItsFutureReturnIsGenerated() throws {
    for tape in [PracticeTapeMode.word, .letter] {
      let model = Model(quote("ab cd\nef", modifiers: [.focusCurrentWord])); model.mode = tape
      XCTAssertTrue(model.session.hasPracticeNewlineContent); XCTAssertEqual(model.session.prompt, "ab ")
      let (window, host) = mount(model); defer { close(window, host) }
      let native = try settle(host, model)
      model.session.insertBatch("ab ", at: start)
      XCTAssertTrue(try settle(host, model) === native)
      XCTAssertTrue(model.session.prompt.contains("\n")); XCTAssertTrue(model.session.acceptsNewlineInput)
      XCTAssertEqual(model.session.typed, "ab "); XCTAssertFalse(window.isVisible)
    }
  }

  func testLaterMessagingReturnUsesNaturalContentHeightWithoutChangingInitialInputCapability() throws {
    let model = Model(quote("ab tail. end", modifiers: [.messagingStyle, .focusCurrentWord]))
    XCTAssertFalse(model.session.hasPracticeNewlineContent)
    let (window, host) = mount(model); defer { close(window, host) }
    let native = try settle(host, model)
    model.session.insertBatch("ab ", at: start); try settle(host, model)
    model.session.insertBatch("tail ", at: start.addingTimeInterval(1))
    XCTAssertTrue(try settle(host, model) === native)
    XCTAssertFalse(model.session.hasPracticeNewlineContent); XCTAssertFalse(model.session.acceptsNewlineInput)
    XCTAssertTrue(model.session.prompt.contains("tail\nend"))
    XCTAssertEqual(native.bounds.height, geometry(model).rowHeight * 2, accuracy: 0.01)
    XCTAssertGreaterThan(try XCTUnwrap(model.motion.main.visibleRect).minY, 0)
    let typed = model.session.typed; model.session.insert("\n", at: start.addingTimeInterval(2))
    XCTAssertEqual(model.session.typed, typed); try settle(host, model)
    try capture(native, name: "late-messaging"); XCTAssertFalse(window.isVisible)
  }

  func testRealOrdinaryInputRetiresRowsAndKeepsCompleteResultAndReplay() throws {
    for tape in [PracticeTapeMode.word, .letter] {
      let target = "a\nb\nc\nd"
      let model = Model(TypingSession(configuration: .init(mode: .quote, duration: nil,
        wordLimit: nil, difficulty: .normal, rules: .init(freedomMode: true)), prompt: target)); model.mode = tape
      let (window, host) = mount(model); defer { close(window, host) }
      let native = try settle(host, model)
      for (index, text) in ["a\n", "b\n", "c\n"].enumerated() {
        model.session.insertBatch(text, at: start.addingTimeInterval(Double(index)))
        XCTAssertTrue(try settle(host, model, retained: max(0, index)) === native)
        let caret = try XCTUnwrap(model.motion.main.visibleRect)
        XCTAssertGreaterThan(caret.width, 0); XCTAssertGreaterThanOrEqual(caret.minY, 0)
        XCTAssertLessThanOrEqual(caret.maxY, native.bounds.height + 1)
      }
      XCTAssertEqual(model.retirements.map(\.firstRetainedWordIndex), [1, 2])
      try capture(native, name: "retired-\(tape.rawValue)")
      model.session.insertBatch("d", at: start.addingTimeInterval(4))
      let result = try XCTUnwrap(model.session.result())
      XCTAssertEqual(result.prompt, target); XCTAssertEqual(model.session.typed, target); XCTAssertEqual(result.errorCount, 0)
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), target)
      XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
      model.session = model.session.repeatedAttempt()
      XCTAssertTrue(try settle(host, model, retained: 0) === native)
      XCTAssertTrue(model.session.removedTapePromptWordIndices.isEmpty); XCTAssertEqual(model.session.typed, "")
      XCTAssertEqual(model.session.prompt, target); XCTAssertFalse(window.isVisible)
    }
  }

  func testIncorrectReturnReplacementKeepsItsOwnedRowAndCanBeCorrected() throws {
    let model = Model(TypingSession(configuration: .init(mode: .quote, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init(freedomMode: true)), prompt: "a\nb\nc"))
    model.style = .replace
    let (window, host) = mount(model); defer { close(window, host) }
    let native = try settle(host, model)
    model.session.insertBatch("a ", at: start); try settle(host, model)
    XCTAssertTrue(try XCTUnwrap(TapePromptProjection.words(session: model.session, rendering: model.rendering).first).incorrectNewline)
    XCTAssertGreaterThan(try XCTUnwrap(model.motion.main.visibleRect).minY, 0)
    try capture(native, name: "wrong-return")
    model.session.deleteBackward(at: start.addingTimeInterval(1)); try settle(host, model)
    model.session.insert("\n", at: start.addingTimeInterval(2)); try settle(host, model)
    XCTAssertFalse(try XCTUnwrap(TapePromptProjection.words(session: model.session, rendering: model.rendering).first).incorrectNewline)
    XCTAssertEqual(model.session.typed, "a\n"); XCTAssertEqual(model.session.prompt, "a\nb\nc")
    try capture(native, name: "corrected-return"); XCTAssertFalse(window.isVisible)
  }

  func testRTLUnicodeRetirementAndFontRebuildKeepTheSameNativeOwner() throws {
    let target = "אב 👩🏽‍💻\nגד e\u{301}\nהו זח\nטיכ"
    let model = Model(TypingSession(configuration: .init(mode: .quote, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init(freedomMode: true), language: .hebrew), prompt: target))
    let (window, host) = mount(model); defer { close(window, host) }
    let native = try settle(host, model)
    model.session.insertBatch("אב 👩🏽‍💻\n", at: start); try settle(host, model)
    model.session.insertBatch("גד e\u{301}\n", at: start.addingTimeInterval(1))
    try settle(host, model, retained: 2)
    let before = model.session.typed, prefix = model.session.firstRetainedPromptWordIndex
    model.fontSize = 32
    XCTAssertTrue(try settle(host, model, retained: prefix) === native)
    let caret = try XCTUnwrap(model.motion.main.visibleRect)
    XCTAssertGreaterThanOrEqual(caret.minX, 0); XCTAssertLessThanOrEqual(caret.maxX, native.bounds.width + 1)
    XCTAssertGreaterThanOrEqual(caret.minY, 0); XCTAssertLessThanOrEqual(caret.maxY, native.bounds.height + 1)
    XCTAssertEqual(model.session.typed, before); XCTAssertEqual(model.session.prompt, target)
    try capture(native, name: "rtl-font"); XCTAssertFalse(window.isVisible)
  }

  func testLaterGeneratedRowsCanExceedThreeWhenTheInitialSignalWasFalse() throws {
    for tape in [PracticeTapeMode.word, .letter] {
      let model = Model(quote("ab tail. first. second. third. end", modifiers: [.messagingStyle, .focusCurrentWord]))
      model.mode = tape
      model.session.insertBatch("ab tail first second ", at: start)
      XCTAssertFalse(model.session.hasPracticeNewlineContent); XCTAssertFalse(model.session.acceptsNewlineInput)
      XCTAssertEqual(geometry(model).contentHeight / geometry(model).rowHeight, 4, accuracy: 0.01)
      let (window, host) = mount(model); defer { close(window, host) }
      let native = try settle(host, model)
      XCTAssertEqual(native.bounds.height, geometry(model).rowHeight * 4, accuracy: 0.01)
      XCTAssertTrue(descendants(host, NSScrollView.self).isEmpty)
      try capture(native, name: "natural-four-\(tape.rawValue)"); XCTAssertFalse(window.isVisible)
    }
  }

  func testNarrowMultilineTapeKeepsIndependentHolesAcrossFontRebuild() throws {
    let target = "alpha bravo charlie delta\necho foxtrot\ngolf"
    let model = Model(TypingSession(configuration: .init(mode: .quote, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init(freedomMode: true)), prompt: target))
    let delivered = expectation(description: "Actual ordinary horizontal removal")
    var received = false
    model.onRemoval = { event in
      if !received, !event.wordIndices.isEmpty { received = true; delivered.fulfill() }
    }
    let (window, host) = mount(model, width: 80); defer { close(window, host) }
    let native = try settle(host, model)
    for (index, input) in ["alpha ", "bravo ", "charlie "].enumerated() {
      model.session.insertBatch(input, at: start.addingTimeInterval(Double(index))); try settle(host, model)
    }
    wait(for: [delivered], timeout: 1); model.onRemoval = nil
    let mask = model.session.removedTapePromptWordIndices
    XCTAssertFalse(mask.isEmpty); XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    model.fontSize = 32
    XCTAssertTrue(try settle(host, model) === native)
    XCTAssertEqual(model.session.removedTapePromptWordIndices, mask)
    XCTAssertEqual(model.session.typed, "alpha bravo charlie "); XCTAssertEqual(model.session.prompt, target)
    for index in mask {
      XCTAssertTrue(model.session.promptWordPresentations[index].range.allSatisfy {
        model.rendering.characterOffset(forGlyphAt: $0) == nil })
    }
    let events = model.removals.count; host.needsLayout = true; try settle(host, model)
    XCTAssertEqual(model.removals.count, events)
    try capture(native, name: "horizontal-hole-font"); XCTAssertFalse(window.isVisible)
  }

  func testSmoothOrdinaryRetirementCannotReachARepeatedAttempt() throws {
    let model = Model(TypingSession(configuration: .init(mode: .quote, duration: nil,
      wordLimit: nil, difficulty: .normal, rules: .init()), prompt: "a\nb\nc\nd"))
    model.smooth = true; model.reduced = false
    let (window, host) = mount(model); defer { close(window, host) }
    let native = try settle(host, model)
    model.session.insertBatch("a\n", at: start); try settle(host, model)
    model.session.insertBatch("b\n", at: start.addingTimeInterval(1)); try settle(host, model, retained: 1)
    model.session.insertBatch("c\n", at: start.addingTimeInterval(2)); try settle(host, model)
    let old = model.session.automaticInputAttemptID, events = model.retirements.count
    model.session = model.session.repeatedAttempt()
    XCTAssertTrue(try settle(host, model, retained: 0) === native)
    let expired = expectation(description: "Old retirement deadline has passed")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { expired.fulfill() }
    wait(for: [expired], timeout: 1)
    try settle(host, model)
    XCTAssertNotEqual(model.session.automaticInputAttemptID, old)
    XCTAssertEqual(model.retirements.count, events); XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
    XCTAssertEqual(model.session.typed, ""); XCTAssertFalse(window.isVisible)
  }

  func testNativeThreeRowViewportAgainstTheCompletePinnedWrapperFunction() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned clean reference")
    }
    struct Fixture: Decodable {
      let mode, tapeMode, gate, limitMode: String
      let force, expanded, hasNewline: Bool
      let limit: Int
      let rowHeight: Double
      let height: String?
    }
    struct WordFixture: Decodable { let tokens, display: [String]; let wordCount: Int }
    struct Evidence: Decodable { let pin: String; let fixtures: [Fixture]; let wordFixtures: [WordFixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-ordinary-tape-viewport.mjs").path,
      reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    guard process.terminationStatus == 0 else { return }
    let evidence = try JSONDecoder().decode(Evidence.self, from: data)
    XCTAssertEqual(evidence.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(evidence.fixtures.count, 768)
    XCTAssertEqual(evidence.wordFixtures.count, 8)
    for fixture in evidence.wordFixtures {
      let model = Model(TypingSession(configuration: .words(fixture.wordCount), prompt: fixture.tokens.joined()))
      let words = TapePromptProjection.words(session: model.session, rendering: model.rendering)
      XCTAssertEqual(words.count, fixture.wordCount, "Canonical projection must match actual source word records: \(fixture.tokens)")
      let rows = 1 + fixture.display.dropLast().filter { $0.contains("\n") }.count
      XCTAssertEqual(geometry(model).contentHeight / geometry(model).rowHeight, CGFloat(rows), accuracy: 0.01)
    }
    var compared = 0
    for fixture in evidence.fixtures where fixture.force && !fixture.expanded && fixture.hasNewline && fixture.gate == "test" {
      let mode = try XCTUnwrap(TestMode(rawValue: fixture.mode))
      let configuration = TestConfiguration(mode: mode,
        duration: mode == .time || mode == .custom && fixture.limitMode == "time" ? 30 : nil,
        wordLimit: mode == .words || mode == .custom && fixture.limitMode != "time" ? fixture.limit : nil,
        difficulty: .normal, rules: .init(),
        customTextCompletion: fixture.limitMode == "time" ? .time : .words)
      let model = Model(TypingSession(configuration: configuration, prompt: "a\nb"))
      model.mode = try XCTUnwrap(PracticeTapeMode(rawValue: fixture.tapeMode))
      model.fontSize = fixture.rowHeight > 40 ? 32 : 28
      let (window, host) = mount(model); defer { close(window, host) }
      let native = try settle(host, model)
      let height = try XCTUnwrap(Double(try XCTUnwrap(fixture.height).replacingOccurrences(of: "px", with: "")))
      XCTAssertEqual(native.bounds.height / geometry(model).rowHeight, height / fixture.rowHeight, accuracy: 0.01,
        "Compare the source multiplier with native measured rows, not CSS pixel or font equivalence")
      XCTAssertTrue(descendants(host, NSScrollView.self).isEmpty); XCTAssertFalse(window.isVisible)
      compared += 1
    }
    XCTAssertEqual(compared, 24)
  }
}
