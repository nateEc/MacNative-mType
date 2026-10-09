import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class SpecialPromptCaretTests: XCTestCase {
  private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)

  private func configuration(_ coordinator: PromptCaretMotionCoordinator = .init(),
    attempt: UUID = UUID(), mainID: Int? = 5) -> PromptCaretNativeView.Configuration {
    .init(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: .bar, paceStyle: .outline, font: font, lineSpacing: 12,
      rightToLeft: false, accent: .yellow, motion: .off, reducesMotion: false,
      frameRate: 60, attemptID: attempt, coordinator: coordinator, mainGlyphID: mainID)
  }

  func testCanonicalTargetChangeDoesNotNeedInventedTextCharacterOffsets() throws {
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 100))
    defer { view.stop() }
    let first = CGRect(x: 31, y: 4, width: 22, height: 32)
    let next = CGRect(x: 72, y: 4, width: 22, height: 32)
    var config = configuration(coordinator, attempt: attempt)
    config.glyphRect = { [5: first, 23: next][$0] }
    view.update(config); view.layout(); view.present(at: 0)
    XCTAssertEqual(coordinator.main.position, first)
    config.mainGlyphID = 23
    view.update(config); view.present(at: 0.1)
    XCTAssertEqual(coordinator.main.position, next)
  }

  func testListeningAndChooUseIndependentCaretsInsteadOfAnUnconditionalExclusion() throws {
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertFalse(app.contains("guard !session.configuration.modifiers.contains(.listening) else { return false }"))
    XCTAssertTrue(app.contains("view.configureCarets("), "Rotating glyphs need their actual laid-out frames, not TextKit approximations")
    XCTAssertFalse(app.contains("if session.configuration.modifiers.contains(.listening) {\n        character.foregroundColor = .clear\n        return character"), "Listening must not hide correct and incorrect input indiscriminately")
  }

  private func configureChoo(_ text: String, ids: [Int], config: PromptCaretNativeView.Configuration,
    width: CGFloat = 400) -> ChooLayerView {
    let glyphs = text.map { TypingPromptGlyph(character: $0, state: .pending) }
    let height = ChooLayerView.measure(glyphs: glyphs, font: font, width: width)
    let view = ChooLayerView(frame: .init(x: 0, y: 0, width: width, height: height))
    view.configure(glyphs: glyphs, font: font,
      palette: .init(theme: AppTheme.paper.resolvedTheme, flipsCompletionAndFuture: false, usesColorfulMode: false),
      animates: true, frameRate: 60)
    view.configureCarets(config, glyphIDs: ids)
    return view
  }

  private func caret(in view: ChooLayerView) throws -> PromptCaretNativeView {
    try XCTUnwrap(view.subviews.compactMap { $0 as? PromptCaretNativeView }.first)
  }

  func testChooUsesItsActualUntransformedLayerFramesAndNoncontiguousIDs() throws {
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    let config = configuration(coordinator, attempt: attempt, mainID: 23)
    let view = configureChoo("aéz", ids: [5, 23, 11], config: config)
    defer { view.stopCarets() }
    let layer = try XCTUnwrap(view.layer?.sublayers?.compactMap { $0 as? CATextLayer }.first { $0.string as? String == "é" })
    XCTAssertNotNil(layer.animation(forKey: "chooRotation"))
    try caret(in: view).layout(); try caret(in: view).present(at: 0)
    XCTAssertEqual(coordinator.main.position, layer.frame)
    XCTAssertEqual(view.accessibilityLabel(), "aéz")
    XCTAssertEqual(view.subviews.compactMap { $0 as? PromptCaretNativeView }.count, 1)
  }

  func testChooWrapAndResizeReadNewFramesRatherThanOrdinaryTextKit() throws {
    let coordinator = PromptCaretMotionCoordinator()
    let config = configuration(coordinator, mainID: 11)
    let view = configureChoo("amber", ids: [5, 23, 11, 42, 7], config: config)
    defer { view.stopCarets() }
    try caret(in: view).layout(); try caret(in: view).present(at: 0)
    let old = try XCTUnwrap(coordinator.main.position)
    view.setFrameSize(.init(width: 40, height: 300)); view.layoutSubtreeIfNeeded()
    try caret(in: view).layout(); try caret(in: view).present(at: 0.1)
    let layer = try XCTUnwrap(view.layer?.sublayers?.compactMap { $0 as? CATextLayer }.first { $0.string as? String == "b" })
    XCTAssertEqual(coordinator.main.position, layer.frame)
    XCTAssertGreaterThan(layer.frame.minY, old.minY)
  }

  func testZeroWidthChooTargetUsesClosestPreviousVisibleGlyph() throws {
    let coordinator = PromptCaretMotionCoordinator()
    let view = configureChoo("a\nb", ids: [5, 23, 11], config: configuration(coordinator, mainID: 23))
    defer { view.stopCarets() }
    try caret(in: view).layout(); try caret(in: view).present(at: 0)
    let layer = try XCTUnwrap(view.layer?.sublayers?.compactMap { $0 as? CATextLayer }.first { $0.string as? String == "a" })
    XCTAssertEqual(coordinator.main.position, layer.frame)
  }

  func testBlinkChangesOnlyChooMainCaretNotRotatingTextOrPace() throws {
    let coordinator = PromptCaretMotionCoordinator()
    var config = configuration(coordinator, mainID: 23)
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 11) }
    let view = configureChoo("aéz", ids: [5, 23, 11], config: config)
    defer { view.stopCarets() }
    let child = try caret(in: view)
    child.layout(); child.present(at: 0)
    let markers = child.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }
    let main = try XCTUnwrap(markers.first { $0.rootView.style == .bar })
    let pace = try XCTUnwrap(markers.first { $0.rootView.style == .outline })
    let layers = view.layer?.sublayers?.compactMap { $0 as? CATextLayer } ?? []
    let frames = layers.map(\.frame), positions = [coordinator.main.position, coordinator.pace.position]
    child.present(at: 0.75)
    XCTAssertEqual(main.alphaValue, 0); XCTAssertEqual(pace.alphaValue, 1)
    XCTAssertTrue(layers.allSatisfy { $0.opacity == 1 && $0.animation(forKey: "chooRotation") != nil })
    XCTAssertEqual(layers.map(\.frame), frames)
    XCTAssertEqual([coordinator.main.position, coordinator.pace.position], positions)
  }

  func testMissingCustomIDCannotFallBackToInventedTextGeometry() {
    let coordinator = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 100))
    defer { view.stop() }
    var config = configuration(coordinator, mainID: 999)
    config.glyphRect = { _ in nil }
    view.update(config); view.layout(); view.present(at: 0)
    XCTAssertNil(coordinator.main.position)
  }

  func testUnchangedCustomPaceDestinationDoesNotRestartOnGeometryRevision() throws {
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 100))
    defer { view.stop() }
    var config = configuration(coordinator, attempt: attempt), fraction = 0.0
    config.glyphRect = { .init(x: $0 == 0 ? 0 : 100, y: 0, width: 20, height: 30) }
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: fraction, stepDuration: 1, sequence: 1, targetGlyphID: 5) }
    view.update(config); view.layout(); view.present(at: 0)
    fraction = 0.25; view.present(at: 0.25)
    config.geometryRevision = 1; view.update(config); view.present(at: 0.25)
    fraction = 0.5; view.present(at: 0.5)
    XCTAssertEqual(try XCTUnwrap(coordinator.pace.position).minX, 51.2, accuracy: 1e-8)
  }

  func testChangedCustomPaceDestinationRetargetsWithRemainingDuration() throws {
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 100))
    defer { view.stop() }
    var config = configuration(coordinator, attempt: attempt), fraction = 0.0, targetX = 100.0
    config.glyphRect = { .init(x: $0 == 0 ? 0 : targetX, y: 0, width: 20, height: 30) }
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: fraction, stepDuration: 1, sequence: 1, targetGlyphID: 5) }
    view.update(config); view.layout(); view.present(at: 0)
    fraction = 0.25; view.present(at: 0.25)
    let start = try XCTUnwrap(coordinator.pace.position).minX
    targetX = 180; config.geometryRevision = 1
    view.update(config); view.present(at: 0.25)
    fraction = 0.5; view.present(at: 0.5)
    XCTAssertEqual(try XCTUnwrap(coordinator.pace.position).minX,
      start + (180 - start) * (0.25 + PromptLineScrollMotion.autoplayLead) / 0.75, accuracy: 1e-8)
  }

  func testCustomFullWidthPaceAfterTargetUsesSpaceAdvanceNotTargetWidth() throws {
    let coordinator = PromptCaretMotionCoordinator()
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 100))
    defer { view.stop() }
    var config = configuration(coordinator)
    let rect = CGRect(x: 40, y: 5, width: 30, height: 33)
    config.glyphRect = { _ in rect }
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: true, fraction: 1, targetGlyphID: 23) }
    view.update(config); view.layout(); view.present(at: 0)
    let pace = try XCTUnwrap(coordinator.pace.position)
    XCTAssertEqual(pace.minX, rect.maxX)
    XCTAssertEqual(pace.width, (" " as NSString).size(withAttributes: [.font: font]).width)
  }

  func testCustomHorizontalGeometryAgainstCompletePinnedCaretResolver() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned clean reference")
    }
    struct Box: Decodable { let x, y, width, height: Double }
    struct Position: Decodable { let left, top, width: Double }
    struct Fixture: Decodable { let style: String; let after: Bool; let rect: Box; let source: Position }
    struct Output: Decodable { let pin: String; let fixtures: [Fixture] }
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-special-caret.mjs").path,
      reference, "--emit-fixtures", String(Double((" " as NSString).size(withAttributes: [.font: font]).width))]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    guard process.terminationStatus == 0 else { return }
    let source = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(source.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(source.fixtures.count, 16)
    for fixture in source.fixtures {
      let style: TypingCaretStyle
      switch fixture.style {
      case "default": style = .bar
      case "block": style = .block
      case "outline": style = .outline
      case "underline": style = .underline
      default: XCTFail("Unknown pinned style"); continue
      }
      let coordinator = PromptCaretMotionCoordinator()
      let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 100))
      defer { view.stop() }
      var config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
        mainStyle: .off, paceStyle: style, font: font, lineSpacing: 12, rightToLeft: false,
        accent: .yellow, motion: .off, reducesMotion: false, frameRate: 60,
        attemptID: UUID(), coordinator: coordinator, firstGlyphID: 5)
      config.glyphRect = { _ in .init(x: fixture.rect.x, y: fixture.rect.y,
        width: fixture.rect.width, height: fixture.rect.height) }
      config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
        fromAfter: false, targetAfter: fixture.after, fraction: 1, targetGlyphID: 5) }
      view.update(config); view.layout(); view.present(at: 0)
      let rect = try XCTUnwrap(coordinator.pace.position)
      let marker = try XCTUnwrap(view.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }.first)
      if style == .bar {
        // CSS left is the 2-point stroke's left edge; the native marker is centered on the anchor.
        XCTAssertEqual(marker.frame.midX, fixture.source.left + 1, accuracy: 1e-8)
      } else {
        XCTAssertEqual(rect.minX, fixture.source.left, accuracy: 1e-8)
        XCTAssertEqual(rect.width, fixture.source.width, accuracy: 1e-8)
      }
      // Owned glyph boxes are not a claim about CSS/native font baselines or shape heights.
    }
  }

  func testActualChooTextAndIndependentCaretRenderInOneNeverVisibleWindow() throws {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 100),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    let view = configureChoo("amber birch", ids: Array(0..<11), config: configuration(mainID: 2))
    window.contentView = view
    defer { view.stopCarets(); window.contentView = nil; window.close() }
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    view.configureCarets(configuration(mainID: 2), glyphIDs: Array(0..<11))
    let child = try caret(in: view)
    child.layoutSubtreeIfNeeded(); child.present(at: 0)
    // Freeze the existing layer animation clock for reproducible component captures.
    view.layer?.speed = 0; view.layer?.timeOffset = 0
    var images: [Data] = []
    for (name, time) in [("choo-caret-on", 0.0), ("choo-caret-off", 0.75)] {
      child.present(at: time); view.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      images.append(png)
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
      }
      XCTAssertFalse(window.isVisible)
      XCTAssertEqual(view.accessibilityLabel(), "amber birch")
    }
    XCTAssertNotEqual(images[0], images[1], "The real independent caret must change the captured component")
  }

  func testChooDetachmentStopsAndRemovesOnlyItsCaretChild() throws {
    let parent = NSView(frame: .init(x: 0, y: 0, width: 400, height: 200))
    let view = configureChoo("ab", ids: [5, 23], config: configuration())
    parent.addSubview(view)
    let child = try caret(in: view)
    child.layout(); child.present(at: 0)
    let before = child.subviews.map(\.frame)
    view.removeFromSuperview()
    XCTAssertTrue(view.subviews.isEmpty)
    child.present(at: 10)
    XCTAssertEqual(child.subviews.map(\.frame), before)
    XCTAssertTrue((view.layer?.sublayers?.compactMap { $0 as? CATextLayer } ?? []).allSatisfy { $0.animation(forKey: "chooRotation") != nil })
  }

  func testCustomGeometryClosureDoesNotRetainChooRenderer() {
    weak var released: ChooLayerView?
    autoreleasepool {
      let view = configureChoo("ab", ids: [5, 23], config: configuration())
      released = view
    }
    XCTAssertNil(released)
  }

  func testChooCurrentGlyphDoesNotKeepAFakeCaretBackgroundOrRevealAnAccentTarget() {
    for flipped in [false, true] { for colorful in [false, true] {
      let palette = ChooGlyphPalette(theme: AppTheme.paper.resolvedTheme,
        flipsCompletionAndFuture: flipped, usesColorfulMode: colorful)
      XCTAssertEqual(palette.foreground(for: .current), palette.foreground(for: .pending))
      XCTAssertNil(palette.background(for: .current))
    } }
  }

  private func listeningAppearances(_ session: TypingSession,
    mode: PromptHighlightMode = .letter, effect: TypedCharacterEffect = .keep) -> [PromptGlyphAppearance] {
    PromptGlyphAppearance.plan(glyphs: session.promptGlyphs, words: session.promptWordPresentations, mode: mode,
      blindMode: session.configuration.rules.blindMode, typedEffect: effect, hidesUntypedGlyphs: true)
  }

  func testListeningKeepsCorrectAndIncorrectInputVisibleWhileConcealingUntypedTargets() {
    var session = TypingSession(configuration: .words(10).with(modifiers: [.listening]), prompt: "amber birch")
    XCTAssertTrue(listeningAppearances(session).allSatisfy { $0.color == .hidden })
    _ = TypingLiveInputFeedback.insertBatch("ax", into: &session)
    let roles = listeningAppearances(session).map(\.color)
    XCTAssertEqual(Array(roles.prefix(2)), [.completed, .error])
    XCTAssertTrue(roles.dropFirst(2).allSatisfy { $0 == .hidden })
    XCTAssertEqual(session.typed, "ax")
  }

  func testListeningOffHighlightDoesNotRevealCorrectTargetsThroughTypedEffects() {
    var session = TypingSession(configuration: .words(10).with(modifiers: [.listening]), prompt: "ab cd")
    _ = TypingLiveInputFeedback.insertBatch("ab ", into: &session)
    for effect in TypedCharacterEffect.allCases {
      XCTAssertTrue(listeningAppearances(session, mode: .off, effect: effect).allSatisfy { $0.color == .hidden })
    }
  }

  func testListeningBlindInputUsesExistingBlindRolesWithoutChangingAcceptedInput() {
    var session = TypingSession(configuration: .words(10, rules: .init(blindMode: true)).with(modifiers: [.listening]), prompt: "ab cd")
    _ = TypingLiveInputFeedback.insertBatch("x", into: &session)
    XCTAssertEqual(listeningAppearances(session).first?.color, .completed)
    XCTAssertEqual(listeningAppearances(session, mode: .off).first?.color, .hidden)
    XCTAssertEqual(session.typed, "x")
  }

  func testListeningConcealmentRunsAfterLegacyCaretAndTypedEffects() throws {
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let caret = try XCTUnwrap(app.range(of: "applyCaret(to: &character, theme: activeTheme)"))
    let concealment = try XCTUnwrap(app.range(of: "appearance.applyVisibility(to: &character)")
      ?? app.range(of: "if appearance.color == .hidden { character.foregroundColor = .clear }"))
    XCTAssertGreaterThan(concealment.lowerBound, caret.lowerBound,
      "A fallback bar/carrot/banana/monkey must not reveal an untyped listening target")
  }

  func testFinalHiddenRoleConcealsFallbackForegroundWithoutDeletingLayoutOrCaretBackground() {
    var text = AttributedString("é")
    text.foregroundColor = .yellow
    text.backgroundColor = .blue
    text.underlineStyle = .single
    let hidden = PromptGlyphAppearance(color: .hidden)
    hidden.applyVisibility(to: &text)
    XCTAssertEqual(String(text.characters), "é")
    XCTAssertEqual(text.foregroundColor, .clear)
    XCTAssertEqual(text.backgroundColor, .blue)
    XCTAssertEqual(text.underlineStyle, .single)
    for role: PromptGlyphColor in [.completed, .future, .error, .extra] {
      var visible = AttributedString("é"); visible.foregroundColor = .red
      PromptGlyphAppearance(color: role).applyVisibility(to: &visible)
      XCTAssertEqual(visible.foregroundColor, .red)
    }
  }
}
