import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptCaretNativeViewTests: XCTestCase {
  private final class Document: NSView { override var isFlipped: Bool { true } }
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)

  private func configuration(_ motion: PromptCaretMotionCoordinator, attempt: UUID,
    text: String = "amber\nbirch\ncedar\ndelta", style: TypingCaretStyle = .bar,
    paceStyle: TypingCaretStyle = .off, mainOffset: Int = 0) -> PromptCaretNativeView.Configuration {
    .init(text: AttributedString(text), mainOffset: mainOffset, paceOffset: nil,
      mainStyle: style, paceStyle: paceStyle, font: font, lineSpacing: 12,
      rightToLeft: false, accent: .yellow, motion: .off, reducesMotion: false,
      frameRate: 30, attemptID: attempt, coordinator: motion)
  }

  func testLatestInputAndMarkedCompositionReadFreshGeometryWithoutPerFrameRendering() throws {
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
    var typed = "", composition = "", glyph = 0, reads = 0, glyphReads = 0
    var config = configuration(motion, attempt: attempt)
    config.latestInput = { .init(attemptID: attempt, typed: typed, composition: composition, glyphID: nil) }
    config.latestGlyphID = { glyphReads += 1; return glyph }
    config.latestRendering = {
      reads += 1
      return .init(text: AttributedString("amber\nbirch\ncedar"), glyphCharacterOffsets: [0: 0, 1: 6, 2: 12])
    }
    view.update(config); view.layout(); view.present(at: 0)
    let initial = try XCTUnwrap(motion.main.position)
    for frame in 1...10 { view.present(at: Double(frame) / 1000) }
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(glyphReads, 1)
    typed = "amber "; glyph = 1
    view.present(at: 0.02) // No SwiftUI/configuration update yet.
    XCTAssertEqual(try XCTUnwrap(motion.main.position).minY, initial.minY + 45, accuracy: 0.1)
    XCTAssertEqual(reads, 2)
    composition = "中文"; glyph = 2
    view.present(at: 0.03)
    XCTAssertEqual(try XCTUnwrap(motion.main.position).minY, initial.minY + 90, accuracy: 0.1)
    XCTAssertEqual(reads, 3)
    XCTAssertEqual(glyphReads, 3)
    motion.resetLayout() // The sibling follower can invalidate geometry too.
    view.present(at: 0.04)
    XCTAssertNotNil(motion.main.position)
    view.stop()
  }

  func testPrefixRebuildKeepsReadyMarginAndProgrammaticScrollIsNotAppliedTwice() throws {
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 360, height: 135))
    let document = Document(frame: .init(x: 0, y: 0, width: 360, height: 600))
    let view = PromptCaretNativeView(frame: document.bounds)
    scroll.documentView = document; document.addSubview(view)
    var glyph = 0, typed = "", text = "amber\nbirch\ncedar\ndelta"
    var offsets = [0: 0, 1: 6, 2: 12, 3: 18]
    var config = configuration(motion, attempt: attempt)
    config.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: glyph) }
    config.latestRendering = { .init(text: AttributedString(text), glyphCharacterOffsets: offsets) }
    view.update(config); view.layout(); view.present(at: 0)
    let initial = try XCTUnwrap(motion.main.position).minY
    motion.lineJump(to: -45, duration: 0.125, at: 0)
    glyph = 2; typed = "amber birch "
    view.present(at: 0)
    view.present(at: 0.025)
    let scrollTop = 45 * PromptLineScrollMotion.progress(elapsed: 0.037)
    scroll.contentView.scroll(to: .init(x: 0, y: scrollTop))
    motion.reportProgrammaticScroll(scrollTop)
    view.present(at: 0.025)
    let marker = try XCTUnwrap(view.subviews.first)
    XCTAssertEqual(marker.frame.minY - scroll.contentView.bounds.minY,
      initial + 90 - scrollTop, accuracy: 1e-8)
    motion.wordsDidFinish(at: 0.2)
    scroll.contentView.scroll(to: .init(x: 0, y: 45)); motion.reportProgrammaticScroll(45)
    view.present(at: 0.2)
    XCTAssertTrue(motion.main.marginReady)
    text = "birch\ncedar\ndelta"; offsets = [1: 0, 2: 6, 3: 12]
    config = configuration(motion, attempt: attempt, text: text)
    config.firstRetainedWordIndex = 1
    config.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: glyph) }
    config.latestRendering = { .init(text: AttributedString(text), glyphCharacterOffsets: offsets) }
    view.update(config)
    scroll.contentView.scroll(to: .zero); motion.reportProgrammaticScroll(0)
    view.present(at: 0.2)
    XCTAssertTrue(motion.main.marginReady, "Prefix-only redraw is not a source goTo")
    XCTAssertEqual(motion.main.margin, -45)
    XCTAssertEqual(marker.frame.minY, initial + 45, accuracy: 1e-8)
    // Manual scroll moves text and marker together; it is not compensated.
    scroll.contentView.scroll(to: .init(x: 0, y: 10)); view.present(at: 0.2)
    XCTAssertEqual(marker.frame.minY - scroll.contentView.bounds.minY, initial + 35, accuracy: 1e-8)
    typed += "c"; view.present(at: 0.21)
    XCTAssertEqual(motion.main.margin, 0)
    XCTAssertFalse(motion.main.marginReady)
    XCTAssertEqual(marker.frame.minY, initial + 45, accuracy: 1e-8)
    view.stop()
  }

  func testPaceRetainsIndependentPositionForPrunedTargetsAndReadsRenderingOnlyPerStep() throws {
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
    var sequence = 1.0, target = 2, reads = 0
    var config = configuration(motion, attempt: attempt, paceStyle: .block)
    config.latestRendering = {
      reads += 1
      return .init(text: AttributedString("amber\nbirch\ncedar"), glyphCharacterOffsets: [2: 12])
    }
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 0, stepDuration: 0.1,
      sequence: sequence, targetGlyphID: target) }
    view.update(config); view.layout(); view.present(at: 0)
    for time in [0.01, 0.025, 0.05] { view.present(at: time) }
    XCTAssertEqual(reads, 2, "One main request and one pace step, not one rebuild per tick")
    XCTAssertGreaterThan(try XCTUnwrap(motion.pace.position).minY, 20)
    XCTAssertLessThan(try XCTUnwrap(motion.pace.position).minY, 90)
    motion.lineJump(to: -45, duration: 0, at: 0.05)
    sequence = 2; target = 999
    view.present(at: 0.2)
    XCTAssertTrue(motion.pace.marginReady)
    XCTAssertEqual(motion.pace.margin, -45)
    let visible = motion.pace.visibleRect
    sequence = 3; target = 2
    view.present(at: 0.2)
    XCTAssertEqual(motion.pace.visibleRect, visible, "Valid next step folds without snapping")
    XCTAssertFalse(motion.pace.marginReady)
    XCTAssertEqual(motion.pace.margin, 0)
    view.stop()
  }

  func testRestartClearsTransientChannelsAndDetachedViewReleasesProvider() {
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    final class Token {}
    weak var released: Token?
    autoreleasepool {
      var token: Token? = Token(); released = token
      let parent = NSView(), view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
      parent.addSubview(view)
      var config = configuration(motion, attempt: attempt)
      config.latestRendering = { [owner = token!] in
        _ = owner
        return .init(text: AttributedString("amber"), glyphCharacterOffsets: [:])
      }
      view.update(config); view.layout(); view.present(at: 0)
      motion.lineJump(to: -45, duration: 0.125, at: 0)
      motion.reportProgrammaticScroll(45)
      motion.prepare(attemptID: UUID())
      XCTAssertNil(motion.main.position)
      XCTAssertEqual(motion.main.margin, 0)
      XCTAssertEqual(motion.programmaticScroll, 0)
      token = nil
      view.removeFromSuperview()
    }
    XCTAssertNil(released)
  }

  func testNewMarkerDuringLineMotionDoesNotResetTheFollowersWordsOrScrollState() throws {
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    motion.prepare(attemptID: attempt)
    motion.positionMain(at: .init(x: 0, y: 90, width: 12, height: 33), time: 0, duration: 0)
    motion.lineJump(to: -45, duration: 0.125, at: 0)
    motion.sample(at: 0.025)
    let margin = motion.wordsMargin
    motion.reportProgrammaticScroll(-margin)
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
    let config = configuration(motion, attempt: attempt, mainOffset: 12)
    view.update(config); view.layout(); view.present(at: 0.025)
    XCTAssertEqual(motion.wordsMargin, margin, accuracy: 1e-8)
    XCTAssertEqual(motion.programmaticScroll, -margin, accuracy: 1e-8)
    XCTAssertEqual(motion.main.margin, margin, accuracy: 1e-8)
    XCTAssertEqual(try XCTUnwrap(motion.main.position).minY, 90, accuracy: 0.1)
    view.stop()
  }

  func testMarkerStyleChangeAndDetachDoNotOwnTheWordsAnimation() {
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
    view.update(configuration(motion, attempt: attempt)); view.layout(); view.present(at: 0)
    motion.lineJump(to: -45, duration: 0.125, at: 0)
    motion.sample(at: 0.025)
    let margin = motion.wordsMargin
    view.update(configuration(motion, attempt: attempt, style: .block))
    XCTAssertEqual(motion.wordsMargin, margin, accuracy: 1e-8)
    view.stop()
    motion.sample(at: 0.075)
    XCTAssertEqual(motion.wordsMargin, -45 * PromptLineScrollMotion.progress(elapsed: 0.087), accuracy: 1e-8)
  }

  func testPaceOnlySkipsMainGeometryPollingAndLatePaceLayerStaysBehindMain() {
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
    var frame: PromptPaceCaretInterpolation?, reads = 0
    let rendering: () -> PromptRendering = {
      reads += 1
      return .init(text: AttributedString("amber"), glyphCharacterOffsets: [1: 1])
    }
    var config = configuration(motion, attempt: attempt, style: .off, paceStyle: .block)
    config.latestRendering = rendering; config.paceFrame = { frame }
    view.update(config); view.layout(); view.present(at: 0)
    let initial = reads
    view.present(at: 0.01); view.present(at: 0.02)
    XCTAssertEqual(reads, initial, "An invisible main caret must not rebuild prompt geometry every tick")
    config = configuration(motion, attempt: attempt, paceStyle: .block)
    config.latestRendering = rendering; config.paceFrame = { frame }
    view.update(config); view.present(at: 0.03)
    frame = .init(fromCharacterOffset: nil, targetCharacterOffset: nil, fromAfter: false,
      targetAfter: false, fraction: 0, stepDuration: 0.1, sequence: 1, targetGlyphID: 1)
    view.present(at: 0.04)
    let markers = view.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }
    XCTAssertEqual(markers.map { $0.rootView.style }, [.block, .bar],
      "The translucent pace layer stays below the main marker, including late creation")
    view.stop()
  }

  func testCoordinatorRequestsAndWordsCompletionDoNotPresentSiblingChannels() {
    let motion = PromptCaretMotionCoordinator()
    motion.prepare(attemptID: UUID())
    let rect = CGRect(x: 0, y: 90, width: 12, height: 33)
    motion.positionMain(at: rect, time: 0, duration: 0)
    motion.positionPace(at: rect, time: 0, duration: 0)
    motion.lineJump(to: -45, duration: 0.125, at: 0)
    motion.sample(at: 0.025)
    let main = motion.main.visibleRect, pace = motion.pace.visibleRect, words = motion.wordsMargin
    motion.positionMain(at: nil, time: 0.2, duration: 0.15)
    motion.positionPace(at: rect, time: 0.2, duration: 0.15)
    XCTAssertEqual(motion.main.visibleRect, main)
    XCTAssertEqual(motion.pace.visibleRect, pace)
    XCTAssertEqual(motion.wordsMargin, words)
    motion.wordsDidFinish(at: 0.2)
    XCTAssertEqual(motion.wordsMargin, 0)
    XCTAssertEqual(motion.main.visibleRect, main)
    XCTAssertEqual(motion.pace.visibleRect, pace)
    motion.cancelCarets(at: 0.3)
    motion.sample(at: 1)
    XCTAssertEqual(motion.main.visibleRect, main)
    XCTAssertEqual(motion.pace.visibleRect, pace)
    XCTAssertFalse(motion.main.marginReady)
    XCTAssertFalse(motion.pace.marginReady)
  }
}
