import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ASLPromptControlLayoutTests: XCTestCase {
  private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
  }

  private func measure(_ glyphs: [TypingPromptGlyph], rendering: PromptRendering? = nil,
    width: CGFloat = 240, fontSize: CGFloat = 28, mainID: Int? = nil, paceID: Int? = nil, image: String? = nil
  ) throws -> (frames: [Int: CGRect], words: [Int: CGRect], main: CGRect?, pace: CGRect?) {
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    let motion = PromptCaretMotionCoordinator()
    var config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: mainID == nil ? .off : .bar, paceStyle: paceID == nil ? .off : .outline, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .blue, motion: .off, reducesMotion: true, frameRate: 60, attemptID: UUID(),
      coordinator: motion, mainGlyphID: mainID, automaticallyPresents: false)
    if let paceID { config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: paceID) } }
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 300),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    defer { window.contentView = nil; window.close() }
    let host = NSHostingView(rootView: ASLPracticePrompt(glyphs: glyphs, fontSize: fontSize, accent: .blue,
      rendering: rendering, carets: config, font: font).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color.white))
    window.contentView = host; host.frame = .init(x: 0, y: 0, width: width, height: 300)
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded()
    let view = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let caret = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    caret.layout(); caret.present(at: 0)
    let frames = Dictionary(uniqueKeysWithValues: glyphs.indices.compactMap { id in view.measuredRect(for: id).map { (id, $0) } })
    let words = Dictionary(uniqueKeysWithValues: glyphs.indices.compactMap { id in view.measuredWordRect(for: id).map { (id, $0) } })
    XCTAssertFalse(window.isVisible)
    if let image, let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: directory).appendingPathComponent(image + ".png"))
    }
    return (frames, words, motion.main.position, motion.pace.position)
  }

  func testSourceReturnKeepsVisibleMarkerButRemovesOnlyItsStructuralTextBreakBeforeHint() {
    let glyph = TypingPromptGlyph(character: "\n", state: .incorrect, typedCharacter: "X")
    var main = AttributedString("X\n"); main.foregroundColor = .orange
    var hint = AttributedString("↵"); hint.baselineOffset = -12; hint.foregroundColor = .red
    let content = ASLPromptGlyphContent(glyph: glyph, text: main + hint)
    XCTAssertEqual(String(content.main.characters), "X")
    XCTAssertEqual(content.main.foregroundColor, .orange)
    XCTAssertEqual(String(content.hint!.characters), "↵")
    XCTAssertEqual(String(ASLPromptGlyphContent(glyph: .init(character: "\n", state: .pending)).main.characters), "↵")
    XCTAssertEqual(String(ASLPromptGlyphContent(glyph: .init(character: "\t", state: .pending)).main.characters), "→")
  }

  func testLeadingAndConsecutiveReturnsHaveTheirOwnPositiveBoxesAndFullRows() throws {
    let glyphs = "\na\n\nb".map { TypingPromptGlyph(character: $0, state: .pending) }
    let result = try measure(glyphs, image: "asl-control-leading-blank-lines")
    for id in [0, 2, 3] {
      let frame = try XCTUnwrap(result.frames[id])
      XCTAssertGreaterThan(frame.width, 0); XCTAssertGreaterThan(frame.height, 0)
    }
    for (previous, next) in [(0, 1), (2, 3), (3, 4)] {
      XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.frames[next]).minY,
        try XCTUnwrap(result.frames[previous]).maxY + 11)
    }
    XCTAssertNotNil(result.words[0]); XCTAssertNotNil(result.words[3])
  }

  func testExtraReturnIsAnErrorCellNotATargetLineBreak() throws {
    let glyphs: [TypingPromptGlyph] = [.init(character: "a", state: .correct),
      .init(character: "\n", state: .extra), .init(character: "b", state: .pending)]
    let result = try measure(glyphs, image: "asl-control-extra-return")
    XCTAssertGreaterThan(try XCTUnwrap(result.frames[1]).width, 0)
    XCTAssertEqual(try XCTUnwrap(result.frames[2]).minY, try XCTUnwrap(result.frames[0]).minY, accuracy: 0.5)
    XCTAssertEqual(String(ASLPromptGlyphContent(glyph: glyphs[1]).main.characters), "↵")
  }

  func testWrongReturnReplacementRemainsItsTargetLineBreak() throws {
    let glyphs: [TypingPromptGlyph] = [.init(character: "a", state: .correct),
      .init(character: "\n", state: .incorrect, typedCharacter: "X"), .init(character: "b", state: .pending)]
    let result = try measure(glyphs, image: "asl-control-wrong-return")
    XCTAssertGreaterThan(try XCTUnwrap(result.frames[2]).minY, try XCTUnwrap(result.frames[1]).maxY)
    XCTAssertEqual(String(ASLPromptGlyphContent(glyph: glyphs[1]).main.characters), "X")
    XCTAssertTrue(ASLPromptGlyphContent(glyph: glyphs[1]).ownsLineBreak)
  }

  func testReturnParticipatesInWordWidthAndCanWrapInsideOversizedWord() throws {
    let result = try measure("a\nb".map { .init(character: $0, state: .pending) }, width: 40)
    XCTAssertGreaterThan(try XCTUnwrap(result.frames[1]).minY, try XCTUnwrap(result.frames[0]).minY)
    XCTAssertGreaterThan(try XCTUnwrap(result.frames[2]).minY, try XCTUnwrap(result.frames[1]).maxY)
    XCTAssertEqual(try XCTUnwrap(result.words[0]).maxY, try XCTUnwrap(result.frames[1]).maxY)
  }

  func testPositiveBreakCellEndsItsWordBeforeNextGroupAndCountsForFinalSize() {
    let cells: [ASLPromptFlowGeometry.Cell] = [.init(size: .init(width: 20, height: 20), wordID: 0),
      .init(size: .init(width: 10, height: 25), wordID: 0, isLineBreak: true),
      .init(size: .init(width: 10, height: 25), wordID: 2, isLineBreak: true),
      .init(size: .init(width: 20, height: 20), wordID: 3)]
    let layout = ASLPromptFlowGeometry(cells: cells, width: 100)
    XCTAssertEqual(layout.positions, [.zero, .init(x: 20, y: 0), .init(x: 0, y: 37), .init(x: 0, y: 74)])
    XCTAssertEqual(layout.size.height, 94)
    XCTAssertEqual(ASLPromptFlowGeometry(cells: Array(cells.prefix(2)), width: 100).size.height, 37)
  }

  func testZenHiddenReturnReservesAControlCellWithoutRestoringItsInk() throws {
    let glyphs = "\n\na".map { TypingPromptGlyph(character: $0, state: .hidden) }
    let rendering = PromptRendering.make(glyphs: glyphs, indices: Array(glyphs.indices)) { _, glyph in
      var value = AttributedString(String(glyph.character)); value.foregroundColor = .clear; return value
    }
    let contents = ASLPromptGlyphContent.make(glyphs: glyphs, ids: Array(glyphs.indices), rendering: rendering)
    XCTAssertEqual(String(contents[0].main.characters), "↵")
    XCTAssertEqual(contents[0].main.foregroundColor, .clear)
    let result = try measure(glyphs, rendering: rendering, image: "asl-control-hidden-zen")
    XCTAssertGreaterThan(try XCTUnwrap(result.frames[0]).width, 0)
    XCTAssertGreaterThan(try XCTUnwrap(result.frames[1]).minY, try XCTUnwrap(result.frames[0]).maxY)
    XCTAssertGreaterThan(try XCTUnwrap(result.frames[2]).minY, try XCTUnwrap(result.frames[1]).maxY)
  }

  func testMissingSharedReturnCannotCreateAPlaceholderOrRetiredRow() throws {
    let glyphs = "\na\nb".map { TypingPromptGlyph(character: $0, state: .pending) }
    let rendering = PromptRendering.make(glyphs: glyphs, indices: [3]) { _, _ in AttributedString("b") }
    let contents = ASLPromptGlyphContent.make(glyphs: glyphs, ids: Array(glyphs.indices), rendering: rendering)
    XCTAssertTrue(contents[0].main.characters.isEmpty)
    let result = try measure(glyphs, rendering: rendering)
    XCTAssertNil(result.frames[0]); XCTAssertNil(result.frames[1]); XCTAssertNil(result.frames[2])
    XCTAssertEqual(result.frames.count, 1); XCTAssertEqual(result.words.count, 1)
    XCTAssertEqual(try XCTUnwrap(result.frames[3]).minY, 0, accuracy: 1)
  }

  func testMainAndPaceUseTheirOwnReturnBoxesNotThePreviousHand() throws {
    let result = try measure("a\n\nb".map { .init(character: $0, state: .pending) }, mainID: 1, paceID: 2,
      image: "asl-control-independent-markers")
    XCTAssertEqual(result.main, result.frames[1]); XCTAssertEqual(result.pace, result.frames[2])
    XCTAssertNotEqual(result.main, result.frames[0]); XCTAssertNotEqual(result.main, result.pace)
  }

  func testLargerFontRemeasuresBlankRowsInsteadOfUsingTwelvePointGaps() throws {
    let glyphs = "\n\na".map { TypingPromptGlyph(character: $0, state: .pending) }
    let small = try measure(glyphs), large = try measure(glyphs, fontSize: 40)
    XCTAssertGreaterThan(try XCTUnwrap(large.frames[0]).height, try XCTUnwrap(small.frames[0]).height)
    XCTAssertGreaterThan(try XCTUnwrap(large.frames[2]).minY, try XCTUnwrap(small.frames[2]).minY)
  }

  func testCompositionStripsOnlyTargetBreakAndKeepsUnicodeAttributes() {
    let glyph = TypingPromptGlyph(character: "\n", state: .incorrect)
    var value = AttributedString("候 🙂\n"); value.foregroundColor = .purple; value.underlineStyle = .single
    let content = ASLPromptGlyphContent(glyph: glyph, text: value)
    XCTAssertEqual(String(content.main.characters), "候 🙂")
    XCTAssertEqual(content.main.foregroundColor, .purple); XCTAssertNotNil(content.main.underlineStyle)
    XCTAssertTrue(content.ownsLineBreak)
  }

  func testZenTabUsesOneHiddenControlMarkerRatherThanATextTabStop() throws {
    let glyphs = "\ta".map { TypingPromptGlyph(character: $0, state: .hidden) }
    let rendering = PromptRendering.make(glyphs: glyphs, indices: [0, 1]) { _, glyph in
      var value = AttributedString(String(glyph.character)); value.foregroundColor = .clear; return value
    }
    let content = ASLPromptGlyphContent.make(glyphs: glyphs, ids: [0, 1], rendering: rendering)[0]
    XCTAssertEqual(String(content.main.characters), "→"); XCTAssertEqual(content.main.foregroundColor, .clear)
    XCTAssertFalse(content.ownsLineBreak)
    let result = try measure(glyphs, rendering: rendering)
    XCTAssertGreaterThan(try XCTUnwrap(result.frames[0]).width, 0)
    XCTAssertLessThan(try XCTUnwrap(result.frames[0]).width, 28)
    XCTAssertEqual(try XCTUnwrap(result.frames[0]).minY, try XCTUnwrap(result.frames[1]).minY, accuracy: 0.5)
  }

  func testNativeControlMarkersAgainstCompletePinnedWordBuildAndUpdate() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned clean reference")
    }
    struct Letter: Decodable { let text: String; let isExtra, hidden: Bool }
    struct Fixture: Decodable { let mode, style, input, display: String; let updated: [Letter] }
    struct Evidence: Decodable { let pin: String; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-asl-controls.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    guard process.terminationStatus == 0 else { return }
    let evidence = try JSONDecoder().decode(Evidence.self, from: data)
    XCTAssertEqual(evidence.pin, "91bd24bb8513785c7364cbea29296ff7adafac41"); XCTAssertEqual(evidence.fixtures.count, 36)
    for fixture in evidence.fixtures {
      let target = Array(fixture.display), input = Array(fixture.input), zen = fixture.mode == "zen"
      for (index, letter) in fixture.updated.enumerated() {
        // Zen's empty-input invisible underscore is a separate layout sentinel.
        if zen && input.isEmpty { continue }
        let extra = !zen && index >= target.count
        let character = zen || extra ? input[index] : target[index]
        let state: TypingPromptCharacterState = extra ? .extra
          : index < input.count ? (zen || input[index] == character ? .correct : .incorrect) : .pending
        let entered = index < input.count && state == .incorrect ? input[index] : nil
        let glyph = TypingPromptGlyph(character: character, state: state, typedCharacter: entered)
        let plan = PromptControlCharacterPresentation.plan(for: glyph, style: fixture.style == "replace" ? .replace : .off, isZen: zen)
        var text = AttributedString(plan.text); text.foregroundColor = plan.opacity == 0 ? .clear : .orange
        let content = ASLPromptGlyphContent(glyph: glyph, text: text)
        XCTAssertEqual(String(content.main.characters), letter.text, "\(fixture.mode)/\(fixture.style)/\(index)")
        XCTAssertEqual(extra, letter.isExtra)
        XCTAssertEqual(plan.opacity == 0, letter.hidden)
        XCTAssertEqual(content.ownsLineBreak, character == "\n" && !extra)
      }
    }
  }
}
