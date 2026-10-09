import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptCaretNativeViewTests: XCTestCase {
  private final class Document: NSView { override var isFlipped: Bool { true } }
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)

  private func configuration(_ motion: PromptCaretMotionCoordinator, attempt: UUID,
    text: String = "amber\nbirch\ncedar\ndelta", style: TypingCaretStyle = .bar,
    paceStyle: TypingCaretStyle = .off, mainOffset: Int = 0, accent: Color = .yellow) -> PromptCaretNativeView.Configuration {
    .init(text: AttributedString(text), mainOffset: mainOffset, paceOffset: nil,
      mainStyle: style, paceStyle: paceStyle, font: font, lineSpacing: 12,
      rightToLeft: false, accent: accent, motion: .off, reducesMotion: false,
      frameRate: 30, attemptID: attempt, coordinator: motion)
  }

  func testTranslationMovesNativeFrameWithoutReplacingMarkerContent() throws {
    for style in TypingCaretStyle.allCases where style.drawsMarker {
      let motion = PromptCaretMotionCoordinator(), attempt = UUID()
      let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
      defer { view.stop() }
      var box = CGRect(x: 10, y: 20, width: 18, height: 32), typed = "a"
      var config = configuration(motion, attempt: attempt, style: style)
      config.automaticallyPresents = false
      config.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: 0) }
      config.mainGlyphRect = { _ in box }
      view.update(config); view.layout(); view.present(at: 0)
      let host = try XCTUnwrap(view.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }.first)
      let initialContent = host.rootView.rect, initialFrame = host.frame
      box = box.offsetBy(dx: 30, dy: 45); typed += "b"
      view.present(at: 0.1)
      XCTAssertEqual(host.frame.minX, initialFrame.minX + 30, accuracy: 1e-8)
      XCTAssertEqual(host.frame.minY, initialFrame.minY + 45, accuracy: 1e-8)
      XCTAssertEqual(host.rootView.rect, initialContent,
        "Local marker content does not change when only its native document position moves")
      box.size = .init(width: 22, height: 38); typed += "c"
      view.present(at: 0.2)
      XCTAssertEqual(host.rootView.rect.size, box.size)
      config = configuration(motion, attempt: attempt, style: style, accent: .red)
      config.automaticallyPresents = false
      config.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: 0) }
      config.mainGlyphRect = { _ in box }
      view.update(config); view.present(at: 0.3)
      XCTAssertEqual(host.rootView.accent, .red)
    }
  }

  func testLineMotionTranslatesBothMarkersWithoutChangingLocalContent() throws {
    let motion = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
    defer { view.stop() }
    var config = PromptCaretNativeView.Configuration(text: AttributedString("amber\nbirch"),
      mainOffset: 0, paceOffset: 6, mainStyle: .bar, paceStyle: .outline,
      font: font, lineSpacing: 12, rightToLeft: false, accent: .yellow,
      motion: .medium, reducesMotion: false, frameRate: 60, attemptID: UUID(), coordinator: motion)
    config.automaticallyPresents = false
    view.update(config); view.layout(); view.present(at: 0)
    let markers = view.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }
    XCTAssertEqual(markers.count, 2)
    let contents = markers.map { $0.rootView.rect }, frames = markers.map(\.frame)
    motion.lineJump(to: -45, duration: 0.125, at: 0)
    for time in [0.025, 0.05, 0.1, 0.2] {
      view.present(at: time)
      XCTAssertEqual(markers.map { $0.rootView.rect }, contents)
    }
    XCTAssertNotEqual(markers.map(\.frame), frames)
    let main = try XCTUnwrap(markers.first { $0.rootView.style == .bar })
    let pace = try XCTUnwrap(markers.first { $0.rootView.style == .outline })
    XCTAssertEqual(main.frame.minY, try XCTUnwrap(motion.documentRect(isPace: false)).minY, accuracy: 1e-8)
    XCTAssertEqual(pace.frame.minY, try XCTUnwrap(motion.documentRect(isPace: true)).minY, accuracy: 1e-8)
    XCTAssertEqual(markers.map { $0.rootView.style }, [.outline, .bar])
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

  func testUnresolvedFreshGlyphRecoversWithoutConfigurationUpdate() throws {
    for unresolvedGlyph: Int? in [nil, 999] {
      let motion = PromptCaretMotionCoordinator(), attempt = UUID()
      let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
      defer { view.stop() }
      var glyph = unresolvedGlyph, reads = 0
      var config = configuration(motion, attempt: attempt)
      config.automaticallyPresents = false
      config.latestInput = { .init(attemptID: attempt, typed: "", composition: "", glyphID: nil) }
      config.latestGlyphID = { glyph }
      config.latestRendering = {
        reads += 1
        return .init(text: AttributedString("amber"), glyphCharacterOffsets: [0: 0])
      }
      view.update(config); view.layout()
      for frame in 0..<11 { view.present(at: Double(frame) / 60) }
      XCTAssertNil(motion.main.position)
      // Exploratory observation, not a requirement to keep rebuilding an
      // unresolved target on every frame. Recovery below is the contract.
      print("caret-unresolved glyph=\(unresolvedGlyph == nil ? "nil" : "missing") frames=11 renderingReads=\(reads)")
      glyph = 0
      view.present(at: 0.2)
      XCTAssertNotNil(try XCTUnwrap(motion.main.position))
      let recoveredReads = reads
      for frame in 13..<24 { view.present(at: Double(frame) / 60) }
      XCTAssertEqual(reads, recoveredReads, "Resolved unchanged geometry must not rebuild each frame")
    }
  }

  func testHiddenMainDefersRenderingButResumesWithFreshComposedInput() throws {
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
    defer { view.stop() }
    var visible = false, typed = "", composition = "", glyph: Int? = nil, reads = 0
    var config = configuration(motion, attempt: attempt)
    config.automaticallyPresents = false
    config.mainPresentation = { .init(isVisible: visible, isBlinking: false) }
    config.latestInput = { .init(attemptID: attempt, typed: typed, composition: composition, glyphID: nil) }
    config.latestGlyphID = { glyph }
    config.latestRendering = {
      reads += 1
      return .init(text: AttributedString("amber\nbirch"), glyphCharacterOffsets: [0: 0, 1: 6])
    }
    view.update(config); view.layout()
    for frame in 0..<11 { view.present(at: Double(frame) / 60) }
    XCTAssertEqual(reads, 0, "A hidden unresolved main marker does not need text geometry")
    typed = "amber "; composition = "中"; glyph = 1
    view.present(at: 0.2)
    XCTAssertEqual(reads, 0)
    visible = true
    view.present(at: 0.3)
    XCTAssertEqual(reads, 1)
    XCTAssertGreaterThan(try XCTUnwrap(motion.main.position).minY, 40)
    visible = false
    typed = ""; composition = ""; glyph = 0
    motion.resetLayout()
    view.invalidateGeometry()
    view.present(at: 0.4)
    XCTAssertEqual(reads, 1, "Hidden invalidation remains pending rather than eagerly rebuilding")
    visible = true
    view.present(at: 0.5)
    XCTAssertEqual(reads, 2)
    XCTAssertLessThan(try XCTUnwrap(motion.main.position).minY, 10)
  }

  func testHiddenMainDoesNotSuspendIndependentPaceSteps() throws {
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
    defer { view.stop() }
    var sequence = 1.0, target = 0, reads = 0
    var config = configuration(motion, attempt: attempt, paceStyle: .block)
    config.automaticallyPresents = false
    config.mainPresentation = { .init(isVisible: false) }
    config.latestInput = { .init(attemptID: attempt, typed: "", composition: "", glyphID: nil) }
    config.latestGlyphID = { nil }
    config.latestRendering = {
      reads += 1
      return .init(text: AttributedString("amber\nbirch"), glyphCharacterOffsets: [0: 0, 1: 6])
    }
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 0, stepDuration: 0.1,
      sequence: sequence, targetGlyphID: target) }
    view.update(config); view.layout(); view.present(at: 0)
    let first = try XCTUnwrap(motion.pace.position)
    XCTAssertNil(motion.main.position)
    XCTAssertEqual(reads, 1, "Only the independent pace request needs rendering")
    sequence = 2; target = 1
    view.present(at: 0.2); view.present(at: 0.4)
    XCTAssertGreaterThan(try XCTUnwrap(motion.pace.position).minY, first.minY + 40)
    XCTAssertEqual(reads, 2)
  }

  func testDisabledMainDefersGeometryUntilMarkerIsEnabled() throws {
    let motion = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
    defer { view.stop() }
    var reads = 0
    func config(_ style: TypingCaretStyle) -> PromptCaretNativeView.Configuration {
      var value = configuration(motion, attempt: attempt, style: style)
      value.automaticallyPresents = false
      value.latestInput = { .init(attemptID: attempt, typed: "a", composition: "", glyphID: 0) }
      value.latestRendering = {
        reads += 1
        return .init(text: AttributedString("amber"), glyphCharacterOffsets: [0: 1])
      }
      return value
    }
    view.update(config(.off)); view.layout()
    for frame in 0..<11 { view.present(at: Double(frame) / 60) }
    XCTAssertEqual(reads, 0)
    XCTAssertNil(motion.main.position)
    view.update(config(.bar)); view.present(at: 0.2)
    XCTAssertEqual(reads, 1)
    XCTAssertGreaterThan(try XCTUnwrap(motion.main.position).minX, 0)
  }

  func testFreshProviderRetirementStopsSubsequentGeometryAndPresentationReads() {
    for retiresFromInput in [true, false] {
      let motion = PromptCaretMotionCoordinator(), attempt = UUID()
      let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 360, height: 400))
      defer { view.stop() }
      var presentations = 0, renderings = 0
      var config = configuration(motion, attempt: attempt)
      config.automaticallyPresents = false
      config.latestInput = { [weak view] in
        if retiresFromInput { view?.stop() }
        return .init(attemptID: attempt, typed: "a", composition: "", glyphID: 0)
      }
      config.mainPresentation = { [weak view] in
        presentations += 1
        if !retiresFromInput { view?.stop() }
        return .init()
      }
      config.latestRendering = {
        renderings += 1
        return .init(text: AttributedString("amber"), glyphCharacterOffsets: [0: 0])
      }
      view.update(config); view.layout(); view.present(at: 0)
      XCTAssertEqual(presentations, retiresFromInput ? 0 : 1)
      XCTAssertEqual(renderings, 0)
      XCTAssertNil(motion.main.position)
      view.present(at: 0.1)
      XCTAssertEqual(presentations, retiresFromInput ? 0 : 1)
    }
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
