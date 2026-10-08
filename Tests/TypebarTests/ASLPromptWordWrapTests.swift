import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ASLPromptWordWrapTests: XCTestCase {
  private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
  }

  private func measure(_ text: String, width: CGFloat, image: String) throws -> (glyphs: [Int: CGRect], words: [Int: CGRect]) {
    let glyphs = text.map { TypingPromptGlyph(character: $0, state: .pending) }
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: .off, font: font, lineSpacing: 12, rightToLeft: false,
      accent: .blue, motion: .off, reducesMotion: true, frameRate: 60, attemptID: UUID(),
      coordinator: .init(), mainGlyphID: 0, automaticallyPresents: false)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: 250),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    defer { window.contentView = nil; window.close() }
    let host = NSHostingView(rootView: ASLPracticePrompt(glyphs: glyphs, fontSize: 28, accent: .blue, carets: config).background(Color.white))
    window.contentView = host; host.frame = .init(x: 0, y: 0, width: width, height: 250)
    host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded()
    let view = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    XCTAssertFalse(window.isVisible)
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
        to: URL(fileURLWithPath: directory).appendingPathComponent(image + ".png"))
    }
    let frames = try Dictionary(uniqueKeysWithValues: glyphs.indices.map { ($0, try XCTUnwrap(view.measuredRect(for: $0))) })
    let wordIDs = Set(ASLPromptWordPlan(glyphs: glyphs, ids: Array(glyphs.indices), words: nil).wordByGlyphID.values)
    return (frames, Dictionary(uniqueKeysWithValues: wordIDs.compactMap { id in view.measuredWordRect(for: id).map { (id, $0) } }))
  }

  func testWordThatFitsFreshRowMovesWholeInsteadOfSplittingIntoRemainingGap() throws {
    let frames = try measure("aa bbbb cc", width: 170, image: "asl-word-whole").glyphs
    let first = try XCTUnwrap(frames[0]), word = try XCTUnwrap(frames[3])
    XCTAssertGreaterThan(word.minY, first.minY)
    for id in 3...6 { XCTAssertEqual(try XCTUnwrap(frames[id]).minY, word.minY, accuracy: 0.5) }
  }

  func testOversizedWordWrapsInternallyButNextWordCannotFillItsLastInnerLine() throws {
    let result = try measure("aaaaaaa b", width: 100, image: "asl-word-oversized")
    let frames = result.glyphs
    let finalInner = try XCTUnwrap(frames[6]), next = try XCTUnwrap(frames[8])
    XCTAssertGreaterThan(finalInner.minY, try XCTUnwrap(frames[0]).minY)
    XCTAssertGreaterThan(next.minY, finalInner.minY)
    let word = try XCTUnwrap(result.words[0])
    XCTAssertEqual(word.minY, try XCTUnwrap(frames[0]).minY, accuracy: 0.5)
    XCTAssertEqual(word.maxY, finalInner.maxY, accuracy: 0.5)
    XCTAssertGreaterThan(word.height, finalInner.height * 2)
    XCTAssertEqual(try XCTUnwrap(result.words[8]), next)
  }

  private func cell(_ width: CGFloat, word: Int = 0, separator: Bool = false) -> ASLPromptFlowGeometry.Cell {
    .init(size: .init(width: width, height: 20), wordID: word, isSeparator: separator)
  }

  func testExactFitStaysOnOuterRowAndWholeNextWordMoves() {
    let cells = [cell(20), cell(20), cell(10, separator: true), cell(25, word: 3), cell(25, word: 3)]
    XCTAssertEqual(ASLPromptFlowGeometry(cells: cells, width: 100).positions,
      [.zero, .init(x: 20, y: 0), .init(x: 40, y: 0), .init(x: 50, y: 0), .init(x: 75, y: 0)])
    XCTAssertEqual(ASLPromptFlowGeometry(cells: cells, width: 99).positions.suffix(2),
      [.init(x: 0, y: 32), .init(x: 25, y: 32)])
  }

  func testOversizedWordOwnsItsAllocationAndTrailingSeparatorDoesNotAddBlankInnerRow() {
    let cells = [cell(30), cell(30), cell(30), cell(10, separator: true), cell(20, word: 4)]
    let layout = ASLPromptFlowGeometry(cells: cells, width: 60)
    XCTAssertEqual(layout.positions, [.zero, .init(x: 30, y: 0), .init(x: 0, y: 32),
      .init(x: 30, y: 32), .init(x: 0, y: 64)])
    let exact = ASLPromptFlowGeometry(cells: [cell(30), cell(30), cell(10, separator: true)], width: 60)
    XCTAssertEqual(exact.size.height, 20)
  }

  func testExplicitBreakAndTabOwnershipAreNotConfusedWithSpace() {
    let glyphs = "a\tb\nc".map { TypingPromptGlyph(character: $0, state: .pending) }
    let plan = ASLPromptWordPlan(glyphs: glyphs, ids: [10, 11, 12, 13, 14], words: nil)
    XCTAssertEqual(plan.wordByGlyphID, [10: 10, 11: 10, 12: 10, 13: 10, 14: 14])
    let layout = ASLPromptFlowGeometry(cells: [cell(20), .init(size: .zero, wordID: 0, isLineBreak: true),
      cell(20, word: 2)], width: 100, rowSpacing: 7)
    XCTAssertEqual(layout.positions, [.zero, .init(x: 20, y: 0), .init(x: 0, y: 27)])
  }

  func testUnboundedAndZeroWidthMeasurementsStayFinite() {
    let cells = [cell(20), cell(30, word: 1)]
    let natural = ASLPromptFlowGeometry(cells: cells, width: nil)
    XCTAssertEqual(natural.size, .init(width: 50, height: 20))
    XCTAssertEqual(ASLPromptFlowGeometry(cells: cells, width: .infinity).size, natural.size)
    XCTAssertEqual(ASLPromptFlowGeometry(cells: cells, width: -1).size.width, 0)
    let zero = ASLPromptFlowGeometry(cells: cells, width: 0)
    XCTAssertEqual(zero.size, .init(width: 0, height: 20))
    XCTAssertTrue(zero.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
  }

  func testAdjacentNoSpaceMetadataOverridesPreviousEndBoundary() {
    let glyphs = "abcd".map { TypingPromptGlyph(character: $0, state: .pending) }
    let words: [TypingPromptWordPresentation] = [.init(range: 0..<2, phase: .active, hasInputError: false, hasCommitError: false),
      .init(range: 2..<4, phase: .future, hasInputError: false, hasCommitError: false)]
    XCTAssertEqual(ASLPromptWordPlan(glyphs: glyphs, ids: [0, 1, 2, 3], words: words).wordByGlyphID[2], 2)
  }

  func testRealSessionExtraIDsStayWithTheirWordAfterDisplayReordering() throws {
    var session = TypingSession(configuration: .words(2), prompt: "ab cd")
    session.insertBatch("abx", at: Date(timeIntervalSinceReferenceDate: 914_000_000))
    let words = session.promptWordPresentations
    let extra = words[0].extraGlyphIndices
    XCTAssertEqual(extra.count, 1)
    let ids = PromptGlyphLayout.indices(glyphs: session.promptGlyphs, words: words, hideExtraLetters: false)
    XCTAssertEqual(ids, [0, 1] + extra + [2, 3, 4])
    let plan = ASLPromptWordPlan(glyphs: session.promptGlyphsInDisplayOrder, ids: ids, words: words)
    XCTAssertEqual(plan.wordByGlyphID[try XCTUnwrap(extra.first)], 0)
    XCTAssertEqual(plan.wordByGlyphID[2], 0)
    XCTAssertEqual(plan.wordByGlyphID[3], 3)
  }

  func testTypedReplacementSpaceCannotCreateATargetWordBoundary() {
    let glyphs: [TypingPromptGlyph] = [.init(character: "a", state: .incorrect, typedCharacter: " "),
      .init(character: "b", state: .pending), .init(character: " ", state: .pending),
      .init(character: "c", state: .pending)]
    let plan = ASLPromptWordPlan(glyphs: glyphs, ids: [0, 1, 2, 3], words: nil)
    XCTAssertEqual(plan.wordByGlyphID, [0: 0, 1: 0, 2: 0, 3: 3])
  }

  func testMeasuredWordBoundsExcludeMissingRetiredCellsButIncludeExtraSpaceInk() {
    let glyphs: [TypingPromptGlyph] = [.init(character: "a", state: .pending),
      .init(character: " ", state: .extra), .init(character: " ", state: .pending),
      .init(character: "b", state: .pending)]
    let words: [TypingPromptWordPresentation] = [.init(range: 0..<1, phase: .committed,
      hasInputError: true, hasCommitError: true, extraGlyphIndices: [4]),
      .init(range: 2..<3, phase: .active, hasInputError: false, hasCommitError: false)]
    let plan = ASLPromptWordPlan(glyphs: glyphs, ids: [0, 4, 1, 2], words: words)
    let bounds = CGRect(x: 0, y: 0, width: 28, height: 31)
    XCTAssertEqual(plan.measuredWords(frames: [2: bounds], glyphs: glyphs, ids: [0, 4, 1, 2]), [2: bounds])
    XCTAssertEqual(plan.measuredWords(frames: [4: bounds], glyphs: glyphs, ids: [0, 4, 1, 2]), [0: bounds])
  }

  func testWordRowsUseFullMultilineHeightAndConfiguredSpacingButCaretKeepsInnerRow() throws {
    let frames: [Int: CGRect] = [0: .init(x: 0, y: 0, width: 28, height: 31),
      1: .init(x: 0, y: 43, width: 28, height: 31), 3: .init(x: 0, y: 86, width: 28, height: 31)]
    let geometry = ASLPromptLineGeometry(frames: frames, rowSpacing: 7,
      wordFrames: [0: frames[0]!.union(frames[1]!), 3: frames[3]!])
    let first = try XCTUnwrap(geometry.measure(active: 0, previous: nil, caret: 1,
      words: [.init(index: 0, glyphID: 0), .init(index: 1, glyphID: 3)]))
    XCTAssertEqual(first.activeRowHeight, 86); XCTAssertEqual(first.caretBottom, 74)
    let last = try XCTUnwrap(geometry.measure(active: 3, previous: 0, caret: 3, words: []))
    XCTAssertEqual(last.activeRowHeight, 38)
    XCTAssertEqual(last.previousLineTop, 0); XCTAssertEqual(last.previousWordTop, 0)
    XCTAssertNil(geometry.measure(active: 1, previous: nil, caret: 1, words: []), "An inner glyph is not a word owner")
    let fallback = ASLPromptLineGeometry(frames: frames, rowSpacing: 7)
    XCTAssertEqual(try XCTUnwrap(fallback.measure(active: 3, previous: nil, caret: 3, words: [])).activeRowHeight, 38)
  }

  func testActualResizeUpdatesWordAndBothCaretFramesWithoutAnotherOwner() throws {
    let glyphs = "aa bbbb".map { TypingPromptGlyph(character: $0, state: .pending) }
    let motion = PromptCaretMotionCoordinator()
    var config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: .outline, font: .monospacedSystemFont(ofSize: 28, weight: .regular),
      lineSpacing: 12, rightToLeft: false, accent: .blue, motion: .off, reducesMotion: true,
      frameRate: 60, attemptID: UUID(), coordinator: motion, mainGlyphID: 3, automaticallyPresents: false)
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 6) }
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 250, height: 250),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.contentView = nil; window.close() }
    let host = NSHostingView(rootView: ASLPracticePrompt(glyphs: glyphs, fontSize: 28, accent: .blue, carets: config))
    window.contentView = host; host.frame = .init(x: 0, y: 0, width: 250, height: 250)
    func settle() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)); host.layoutSubtreeIfNeeded() }
    settle()
    let view = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let caret = try XCTUnwrap(descendants(host, PromptCaretNativeView.self).first)
    caret.layout(); caret.present(at: 0)
    let old = try XCTUnwrap(motion.main.position)
    host.setFrameSize(.init(width: 170, height: 250)); settle()
    caret.layout(); caret.present(at: 0.1)
    XCTAssertGreaterThan(try XCTUnwrap(motion.main.position).minY, old.minY)
    XCTAssertEqual(motion.main.position, view.rect(for: 3)); XCTAssertEqual(motion.pace.position, view.rect(for: 6))
    XCTAssertEqual(try XCTUnwrap(view.measuredWordRect(for: 3)).minY, try XCTUnwrap(view.rect(for: 3)).minY, accuracy: 0.5)
    XCTAssertEqual(descendants(host, ASLPromptCaretContainer.self).count, 1)
    XCTAssertEqual(descendants(host, PromptCaretNativeView.self).count, 1)
    XCTAssertFalse(window.isVisible)
  }
}
