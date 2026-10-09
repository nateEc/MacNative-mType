import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class TapeWordVisibilityTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 913_000_000)

  private func remove(_ indices: Set<Int>, from session: inout TypingSession) {
    session.removeTapePromptWords(.init(attemptID: session.automaticInputAttemptID, wordIndices: indices))
  }

  private func render(_ session: TypingSession) -> PromptRendering {
    let glyphs = session.promptGlyphs, words = session.promptWordPresentations
    return .make(glyphs: glyphs, indices: PromptGlyphLayout.indices(glyphs: glyphs,
      words: words, hideExtraLetters: false, firstRetainedWordIndex: session.firstRetainedPromptWordIndex),
      words: words, removedTapeWordIndices: session.removedTapePromptWordIndices) { _, glyph in
      var text = AttributedString(PromptControlCharacterPresentation.plan(for: glyph, style: .replace).text)
      text.foregroundColor = .gray
      return text
    }
  }

  func testIndependentHoleBlocksOnlyTheMissingPreviousWordNotCurrentCorrection() {
    for wholeWord in [false, true] {
      var session = TypingSession(configuration: .words(5, rules: .init(freedomMode: true)), prompt: "aa bb cc dd ee")
      session.insertBatch("aa bb cc ", at: start)
      remove([1], from: &session)
      XCTAssertEqual(session.removedTapePromptWordIndices, [1])
      XCTAssertEqual(session.firstRetainedPromptWordIndex, 0)
      session.deleteWordBackward(at: start.addingTimeInterval(1))
      XCTAssertEqual(session.typed, "aa bb ", "The retained previous word is still reachable")
      if wholeWord { session.deleteWordBackward(at: start.addingTimeInterval(2)) }
      else { session.deleteBackward(at: start.addingTimeInterval(2)) }
      XCTAssertEqual(session.typed, "aa bb ")
      session.insertBatch("c", at: start.addingTimeInterval(3))
      session.deleteBackward(at: start.addingTimeInterval(4))
      XCTAssertEqual(session.typed, "aa bb ", "The missing previous word must not freeze current-field edits")
      XCTAssertNotNil(render(session).characterOffset(forGlyphAt: 0), "An earlier retained word is not a fake retired prefix")
    }
  }

  func testMissingPreviousWordBlocksBothHardRecoveryModesWithoutErasingCommittedInput() {
    for mode: DeleteOnErrorMode in [.letterHard, .wordHard] {
      var session = TypingSession(configuration: .words(4, rules: .init(deleteOnErrorMode: mode)), prompt: "aa bb cc dd")
      session.insertBatch("aa bb ", at: start)
      remove([1], from: &session)
      session.insertBatch("z", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.typed, "aa bb ")
      XCTAssertEqual(session.completedWordCount, 2)
    }
  }

  func testAttemptScopeInvalidIndicesActiveWordDuplicatesAndVerticalPruning() {
    var session = TypingSession(configuration: .words(5), prompt: "aa bb cc dd ee")
    session.insertBatch("aa bb ", at: start)
    session.removeTapePromptWords(.init(attemptID: UUID(), wordIndices: [1]))
    XCTAssertTrue(session.removedTapePromptWordIndices.isEmpty)
    remove([Int.min, -1, 0, 1, 2, 4, Int.max], from: &session)
    XCTAssertEqual(session.removedTapePromptWordIndices, [0, 1, 4], "Reject current word, keep valid non-prefix and lookahead identities")
    remove([0, 1, 4], from: &session)
    XCTAssertEqual(session.removedTapePromptWordIndices, [0, 1, 4])
    session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1))
    XCTAssertEqual(session.removedTapePromptWordIndices, [1, 4])
    remove([0], from: &session)
    XCTAssertEqual(session.removedTapePromptWordIndices, [1, 4])
    let repeated = session.repeatedAttempt()
    XCTAssertTrue(repeated.removedTapePromptWordIndices.isEmpty)
    XCTAssertEqual(repeated.firstRetainedPromptWordIndex, 0)
    XCTAssertNotEqual(repeated.automaticInputAttemptID, session.automaticInputAttemptID)
    session.bailOut(at: start.addingTimeInterval(2))
    remove([3], from: &session)
    XCTAssertEqual(session.removedTapePromptWordIndices, [1, 4])
  }

  func testVisibilityCannotChangeReplayScoresPortableResultsOrTheOriginalPrompt() throws {
    var session = TypingSession(configuration: .words(5), prompt: "aa bb cc dd ee")
    session.insertBatch("aa bxx cc ", at: start)
    var before = session
    before.bailOut(at: start.addingTimeInterval(5))
    let expected = try XCTUnwrap(before.result())
    remove([0, 1], from: &session)
    session.bailOut(at: start.addingTimeInterval(5))
    let actual = try XCTUnwrap(session.result())
    func semanticData(_ result: CompletedTestResult) throws -> Data {
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
      // result() intentionally creates a new UUID on each independent read.
      // Every semantic field, including replay/timing/scoring, stays exact.
      object.removeValue(forKey: "id")
      return try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }
    XCTAssertEqual(try semanticData(actual), try semanticData(expected))
    XCTAssertEqual(session.prompt, "aa bb cc dd ee")
    XCTAssertEqual(session.typed, "aa bxx cc ")
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: actual).portableResult), actual)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [actual], presets: [], at: start)).results, [actual])
  }

  func testSharedRenderingOmitsWordInkExtrasAndCanonicalIDsButRetainsUnmappedNewline() throws {
    var session = TypingSession(configuration: .words(5, rules: .init(freedomMode: true)), prompt: "a\u{301}\nbb cc dd ee")
    session.insertBatch("a\u{301}xxx\nbb cc ", at: start)
    let glyphs = session.promptGlyphs, words = session.promptWordPresentations
    remove([0, 2], from: &session)
    var renderedIDs: Set<Int> = []
    let result = PromptRendering.make(glyphs: glyphs,
      indices: PromptGlyphLayout.indices(glyphs: glyphs, words: words, hideExtraLetters: false),
      words: words, removedTapeWordIndices: session.removedTapePromptWordIndices) { index, glyph in
      renderedIDs.insert(index)
      return AttributedString(PromptControlCharacterPresentation.plan(for: glyph, style: .replace).text)
    }
    XCTAssertEqual(String(result.text.characters), "\nbb dd ee")
    XCTAssertEqual(result.structuralNewlineOffsets, [0: 0])
    for index in Array(words[0].range) + words[0].extraGlyphIndices + [words[0].range.upperBound] {
      XCTAssertNil(result.characterOffset(forGlyphAt: index))
      XCTAssertFalse(renderedIDs.contains(index), "Missing ink and hints are not materialized")
    }
    XCTAssertEqual(result.characterOffset(forGlyphAt: words[1].range.lowerBound), 1)
    XCTAssertNotNil(result.characterOffset(forGlyphAt: words[3].range.lowerBound))
    session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1))
    let trimmed = render(session)
    XCTAssertTrue(trimmed.structuralNewlineOffsets.isEmpty, "Only vertical retirement can remove the structural row")
    XCTAssertEqual(String(trimmed.text.characters), "bb dd ee")
  }

  func testUnicodeNoSpaceFieldsUseWordIdentityRatherThanVisibleSeparators() {
    var session = TypingSession(configuration: .init(mode: .quote, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(freedomMode: true), modifiers: [.noSpaces]),
      prompt: "🧑🏽‍💻e\u{301}tail", noSpaceWordEndIndices: [1, 2, 6], noSpaceTargetWords: ["🧑🏽‍💻", "e\u{301}", "tail"])
    session.insertBatch("🧑🏽‍💻e\u{301}", at: start)
    remove([1], from: &session)
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.deleteWordBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "🧑🏽‍💻e\u{301}")
    XCTAssertEqual(String(render(session).text.characters), "🧑🏽‍💻tail")
  }

  private func newlineSession() -> TypingSession {
    var session = TypingSession(configuration: .words(6), prompt: "abc\ndef ghi\njkl\nmno pqr")
    session.insertBatch("abc\ndef ghi\njkl\n", at: start)
    return session
  }

  func testCanonicalProjectionAndFontResetKeepMissingWordBoxesButNotTheirInk() throws {
    var session = newlineSession()
    remove([0, 1, 2], from: &session)
    let rendering = render(session), words = TapePromptProjection.words(session: session, rendering: rendering)
    XCTAssertEqual(words.count, 6)
    XCTAssertEqual(Set(words.filter(\.isRemoved).map(\.index)), [0, 1, 2])
    for index in [0, 2] {
      XCTAssertTrue(words[index].ownsNewline)
      XCTAssertTrue(words[index].characters.isEmpty)
      XCTAssertNil(words[index].newlineCharacterOffset)
    }
    XCTAssertFalse(words[1].ownsNewline)
    let layout = TapeNewlineTextLayout()
    for size: CGFloat in [28, 32] {
      layout.configure(text: rendering.text, words: words, font: .monospacedSystemFont(ofSize: size, weight: .medium),
        rightToLeft: false, resets: true)
      XCTAssertEqual(layout.removedWordIndices, [0, 1, 2])
      XCTAssertEqual(layout.metrics.contentHeight, 4 * layout.metrics.rowHeight)
      XCTAssertEqual(try XCTUnwrap(layout.wordRect(at: words[4].characters.lowerBound)).minY,
        3 * layout.metrics.rowHeight)
      XCTAssertNotNil(layout.glyphRect(at: words[4].characters.lowerBound, minimumOffset: words[4].characters.lowerBound))
    }
    for word in session.promptWordPresentations.prefix(3) {
      XCTAssertNil(rendering.characterOffset(forGlyphAt: word.range.lowerBound))
    }
  }

  private func updateSession(_ session: TypingSession, view: TapePromptNativeView,
    motion: PromptCaretMotionCoordinator, rtl: Bool, time: TimeInterval,
    removed: @escaping (PromptTapeWordRemoval) -> Void) {
    let rendering = render(session), words = TapePromptProjection.words(session: session, rendering: rendering)
    let active = session.promptWordPresentations[4].range.lowerBound
    let typed = session.typed, attempt = session.automaticInputAttemptID
    let glyph = active + (typed.split(separator: "\n", omittingEmptySubsequences: false).last?.count ?? 0)
    var config = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
      mainStyle: .off, paceStyle: .off, font: .monospacedSystemFont(ofSize: 28, weight: .medium),
      lineSpacing: 0, rightToLeft: rtl, accent: .yellow, motion: .off, reducesMotion: false,
      frameRate: 60, attemptID: attempt, coordinator: motion, mainGlyphID: glyph)
    config.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: glyph) }
    view.configure(rendering: rendering, anchorCharacterIndex: rendering.glyphCharacterOffsets[glyph]!,
      wordAnchorCharacterIndex: rendering.glyphCharacterOffsets[active]!, mode: .letter, margin: 0.25, smoothScroll: false,
      retirement: .init(attemptID: attempt, activeWordID: active, characterOffsets: rendering.glyphCharacterOffsets,
        smoothScroll: false, reducesMotion: false, words: words.map { .init(index: $0.index, glyphID: $0.glyphID) }),
      newlineWords: words, onTapeWordsRemoved: removed, carets: config, at: time)
  }

  private func bitmap(_ view: NSView, name: String) throws -> NSBitmapImageRep {
    view.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
        URL(fileURLWithPath: directory).appendingPathComponent("tape-word-visibility-\(name).png"))
    }
    return bitmap
  }

  func testActualSessionAcknowledgementPreservesNativePixelsAndAppliesNoSecondCompensation() throws {
    for rtl in [false, true] {
      var session = newlineSession()
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 80, height: 200),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
      let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 80, height: 200))
      window.contentView = view; view.layer?.backgroundColor = NSColor.black.cgColor
      let motion = PromptCaretMotionCoordinator()
      var events: [PromptTapeWordRemoval] = []
      let delivered = expectation(description: "Independent word removal, rtl=\(rtl)")
      delivered.assertForOverFulfill = true
      let accept: (PromptTapeWordRemoval) -> Void = {
        events.append($0); session.removeTapePromptWords($0); delivered.fulfill()
      }
      defer { view.stop(); window.contentView = nil; window.close() }
      updateSession(session, view: view, motion: motion, rtl: rtl, time: 0, removed: accept)
      let height = view.subviews[0].frame.height
      session.insert("m", at: start.addingTimeInterval(1))
      updateSession(session, view: view, motion: motion, rtl: rtl, time: 1, removed: accept)
      view.present(at: 1)
      let before = try bitmap(view, name: "\(rtl ? "rtl" : "ltr")-native")
      let margin = motion.wordsTapeMargin, correction = motion.pace.cumulativeTapeCorrection
      wait(for: [delivered], timeout: 1)
      XCTAssertEqual(events.count, 1, "rtl=\(rtl), margin=\(margin), correction=\(correction)")
      XCTAssertEqual(session.removedTapePromptWordIndices, [0, 1, 2], "rtl=\(rtl)")
      XCTAssertEqual(session.firstRetainedPromptWordIndex, 0)
      updateSession(session, view: view, motion: motion, rtl: rtl, time: 1.01, removed: accept)
      view.present(at: 1.01)
      let after = try bitmap(view, name: "\(rtl ? "rtl" : "ltr")-acknowledged")
      XCTAssertEqual(motion.wordsTapeMargin, margin)
      XCTAssertEqual(motion.pace.cumulativeTapeCorrection, correction)
      XCTAssertEqual(view.subviews[0].frame.height, height)
      var ink = 0, differences = 0
      for y in 0..<before.pixelsHigh { for x in 0..<before.pixelsWide {
        let a = try XCTUnwrap(before.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        let b = try XCTUnwrap(after.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        if a.redComponent + a.greenComponent + a.blueComponent > 0.2 { ink += 1 }
        if abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
          + abs(a.blueComponent - b.blueComponent) > 0.01 { differences += 1 }
      } }
      XCTAssertGreaterThan(ink, 20)
      XCTAssertEqual(differences, 0)
      session.insert("n", at: start.addingTimeInterval(2))
      updateSession(session, view: view, motion: motion, rtl: rtl, time: 2, removed: accept)
      view.present(at: 2)
      XCTAssertNotEqual(motion.wordsTapeMargin, margin, "Real input after acknowledgement must still scroll")
      RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
      XCTAssertEqual(events.count, 1)
      XCTAssertFalse(window.isVisible)
    }
  }

  func testActualSwiftUIBridgeRetainsSessionHolesDuringFontRebuildAndClearsThemOnRepeat() throws {
    var session = newlineSession()
    remove([0, 1, 2], from: &session)
    let motion = PromptCaretMotionCoordinator()
    func root(size: Double) -> TapePracticePrompt {
      let rendering = render(session), words = TapePromptProjection.words(session: session, rendering: rendering)
      let active = session.promptWordPresentations.first(where: { $0.phase == .active })!.range.lowerBound
      let attempt = session.automaticInputAttemptID, typed = session.typed, glyph = session.promptCaretGlyphIndex
      var config = PromptCaretNativeView.Configuration(text: rendering.text, mainOffset: nil, paceOffset: nil,
        mainStyle: .off, paceStyle: .off, font: .monospacedSystemFont(ofSize: size, weight: .medium),
        lineSpacing: 0, rightToLeft: false, accent: .yellow, motion: .off, reducesMotion: false,
        frameRate: 60, attemptID: attempt, coordinator: motion, mainGlyphID: glyph)
      config.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: glyph) }
      return TapePracticePrompt(rendering: rendering,
        anchorCharacterIndex: PracticeTapePolicy.anchorCharacterIndex(session: session, rendering: rendering, mode: .letter),
        wordAnchorCharacterIndex: rendering.glyphCharacterOffsets[active]!,
        wordStartCharacterOffsets: PracticeTapePolicy.wordStartCharacterOffsets(session: session, rendering: rendering),
        checksDirectionPerGlyph: false, mode: .letter, margin: 0.25, fontSize: size, animatesScroll: false, carets: config,
        retirement: .init(attemptID: attempt, activeWordID: active, characterOffsets: rendering.glyphCharacterOffsets,
          smoothScroll: false, reducesMotion: false, words: words.map { .init(index: $0.index, glyphID: $0.glyphID) }),
        newlineWords: words, viewportLineCount: 4, onTapeWordsRemoved: { session.removeTapePromptWords($0) })
    }
    let host = NSHostingView(rootView: root(size: 28))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 80, height: 200),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    window.contentView = host
    func nativeViews(_ view: NSView) -> [TapePromptNativeView] {
      (view as? TapePromptNativeView).map { [$0] } ?? view.subviews.flatMap(nativeViews)
    }
    defer {
      nativeViews(host).forEach { $0.stop() }
      window.contentView = nil; window.close()
    }
    func settle(label: String, size: Double) {
      let deadline = Date(timeIntervalSinceNow: 1)
      let rendering = render(session), layout = TapeNewlineTextLayout()
      layout.configure(text: rendering.text, words: TapePromptProjection.words(session: session, rendering: rendering),
        font: .monospacedSystemFont(ofSize: size, weight: .medium), rightToLeft: false, resets: true)
      let expectedHeight = min(layout.metrics.contentHeight, 4 * layout.metrics.rowHeight)
      repeat {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
        host.layoutSubtreeIfNeeded()
        if let view = nativeViews(host).first, view.accessibilityLabel() == label,
          abs(view.bounds.height - expectedHeight) < 1 { return }
      } while Date() < deadline
      XCTFail("SwiftUI bridge did not present the expected label and measured font-specific row height: \(expectedHeight), actual=\(nativeViews(host).first?.bounds.height ?? -1)")
    }
    var original: TapePromptNativeView?
    for size: Double in [28, 32] {
      host.rootView = root(size: size)
      settle(label: "\n\njkl↵\nmno pqr", size: size)
      let views = nativeViews(host)
      XCTAssertEqual(views.count, 1)
      let view = try XCTUnwrap(views.first)
      if let original { XCTAssertTrue(view === original) } else { original = view }
      view.present(at: ProcessInfo.processInfo.systemUptime)
      XCTAssertEqual(session.removedTapePromptWordIndices, [0, 1, 2])
      let text = try XCTUnwrap(view.accessibilityLabel())
      XCTAssertEqual(text, "\n\njkl↵\nmno pqr")
      XCTAssertGreaterThan(view.bounds.height, size * 3)
      let image = try bitmap(view, name: "swiftui-font-\(Int(size))")
      var ink = 0
      for y in 0..<image.pixelsHigh { for x in 0..<image.pixelsWide {
        let color = try XCTUnwrap(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        if color.alphaComponent > 0.2 && max(color.redComponent, color.greenComponent, color.blueComponent)
          - min(color.redComponent, color.greenComponent, color.blueComponent) < 0.02
          && color.redComponent > 0.1 && color.redComponent < 0.9 { ink += 1 }
      } }
      XCTAssertGreaterThan(ink, 20)
    }
    session = session.repeatedAttempt()
    host.rootView = root(size: 32)
    settle(label: "abc↵\ndef ghi↵\njkl↵\nmno pqr", size: 32)
    XCTAssertTrue(session.removedTapePromptWordIndices.isEmpty)
    XCTAssertTrue(try XCTUnwrap(nativeViews(host).first?.accessibilityLabel()).hasPrefix("abc↵\n"))
    XCTAssertFalse(window.isVisible)
  }

  func testIndependentPreviousWordIdentityAgainstCompletePinnedDeleteGuards() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned clean reference")
    }
    struct Case: Decodable { let freedom: Bool, confidence: String, correct: Bool, empty: Bool, present: Bool, prevented: Bool }
    struct HardCase: Decodable { let mode: String, present: Bool, returned: Bool }
    struct Evidence: Decodable { let cases: [Case], hardCases: [HardCase] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent(
      "Scripts/check-source-word-retirement.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: "IndependentTapeDeleteProbe", code: Int(process.terminationStatus)) }
    let evidence = try JSONDecoder().decode(Evidence.self, from: bytes)
    XCTAssertEqual(evidence.cases.count, 32); XCTAssertEqual(evidence.hardCases.count, 8)
    for item in evidence.cases { for wholeWord in [false, true] {
      let confidence: ConfidenceMode = item.confidence == "max" ? .maximum : item.confidence == "on" ? .on : .off
      var session = TypingSession(configuration: .words(5,
        rules: .init(freedomMode: item.freedom, confidenceMode: confidence)), prompt: "aa ab cd tail end")
      session.insertBatch("aa " + (item.correct ? "ab " : "ax ") + (item.empty ? "" : "c"), at: start)
      if !item.present { remove([1], from: &session) }
      XCTAssertEqual(session.firstRetainedPromptWordIndex, 0)
      let before = session.typed
      if wholeWord { session.deleteWordBackward(at: start.addingTimeInterval(1)) }
      else { session.deleteBackward(at: start.addingTimeInterval(1)) }
      XCTAssertEqual(session.typed == before, item.prevented)
    } }
    for item in evidence.hardCases {
      let mode: DeleteOnErrorMode = item.mode == "letter_hard" ? .letterHard
        : item.mode == "word_hard" ? .wordHard : item.mode == "word" ? .word : .letter
      var session = TypingSession(configuration: .words(5, rules: .init(deleteOnErrorMode: mode)), prompt: "aa ab cd tail end")
      session.insertBatch("aa ab ", at: start)
      if !item.present { remove([1], from: &session) }
      session.insert("x", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.completedWordCount == 1, item.returned)
      XCTAssertEqual(session.firstRetainedPromptWordIndex, 0)
    }
  }
}
