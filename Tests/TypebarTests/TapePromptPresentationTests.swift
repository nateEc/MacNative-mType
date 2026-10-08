import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class TapePromptPresentationTests: XCTestCase {
  private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)

  func testInitialTapeMarginIsARealRightwardTranslationNotClampedToZero() {
    for mode: PracticeTapeMode in [.letter, .word] {
      XCTAssertEqual(PracticeTapePolicy.horizontalOffset(prompt: AttributedString("amber birch"),
        anchorCharacterIndex: 0, mode: mode, margin: 0.25, font: font, containerWidth: 400), -100)
    }
  }

  func testProductionTapeDoesNotDrawLegacyCaretInsideMovingText() throws {
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("TapePromptNativeView"), "Tape needs actual shared text geometry and separate caret channels")
    let start = try XCTUnwrap(app.range(of: "private struct TapePracticePrompt"))
    let end = try XCTUnwrap(app.range(of: "struct ChooGlyphPalette"))
    XCTAssertFalse(app[start.lowerBound..<end.lowerBound].contains(".easeOut(duration: 0.16)"),
      "Only the Tape path is governed by this contract; unrelated UI transitions are not Tape")
  }

  private func rendering(_ string: String = "amber birch") -> PromptRendering {
    var text = AttributedString(string); text.foregroundColor = .gray
    return .init(text: text, glyphCharacterOffsets: Dictionary(uniqueKeysWithValues: string.indices.enumerated().map { ($0.offset, $0.offset) }))
  }

  private func config(_ coordinator: PromptCaretMotionCoordinator, attempt: UUID = UUID(),
    main: TypingCaretStyle = .bar, pace: TypingCaretStyle = .outline) -> PromptCaretNativeView.Configuration {
    var config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: main, paceStyle: pace, font: font, lineSpacing: 0, rightToLeft: false,
      accent: .yellow, motion: .off, reducesMotion: false, frameRate: 60,
      attemptID: attempt, coordinator: coordinator, mainGlyphID: 0)
    config.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 6) }
    return config
  }

  private func scene(_ config: PromptCaretNativeView.Configuration) -> TapePromptNativeView {
    let view = TapePromptNativeView(frame: .init(x: 0, y: 0, width: 400, height: 60))
    view.configure(rendering: rendering(), anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: true, carets: config, at: 0)
    return view
  }

  private func textView(in view: TapePromptNativeView) throws -> NSView {
    try XCTUnwrap(view.subviews.first { !($0 is PromptCaretNativeView) })
  }

  func testActualNativeTapeStartsTextAndLockedMainAtTheConfiguredMargin() throws {
    let coordinator = PromptCaretMotionCoordinator(), view = scene(config(.init()))
    defer { view.stop() }
    view.configure(rendering: rendering(), anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: true, carets: config(coordinator), at: 0)
    XCTAssertEqual(try textView(in: view).frame.minX, 100)
    XCTAssertEqual(try XCTUnwrap(coordinator.main.position).minX, 100)
    XCTAssertEqual(view.accessibilityLabel(), "amber birch")
    XCTAssertEqual(view.subviews.compactMap { $0 as? PromptCaretNativeView }.count, 1)
    XCTAssertTrue(view.layer?.masksToBounds == true)
  }

  func testActualTapeTextAndPaceScrollTogetherWhileMainRemainsLocked() throws {
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    var typed = ""
    var configuration = config(coordinator, attempt: attempt)
    configuration.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: nil) }
    let view = scene(configuration); defer { view.stop() }
    let start = try XCTUnwrap(coordinator.pace.visibleRect).minX
    typed = "a"
    view.configure(rendering: rendering(), anchorCharacterIndex: 1, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: true, carets: configuration, at: 1)
    view.present(at: 1.05)
    let fraction = PromptCaretChannel.Curve.position.value((0.05 + PromptLineScrollMotion.autoplayLead) / 0.125)
    let middleX = try textView(in: view).frame.minX
    let middlePaceX = try XCTUnwrap(coordinator.pace.visibleRect).minX
    view.present(at: 1.2)
    let advance = -coordinator.wordsTapeMargin
    XCTAssertEqual(advance, ("a" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1e-7)
    XCTAssertEqual(middleX, 100 - advance * fraction, accuracy: 1e-7)
    XCTAssertEqual(try XCTUnwrap(coordinator.main.visibleRect).minX, 100)
    XCTAssertEqual(middlePaceX, start - advance * fraction, accuracy: 1e-7)
  }

  func testWordTapeMainMovesWithinActiveWordButWordOriginRemainsAtMargin() throws {
    let coordinator = PromptCaretMotionCoordinator()
    var configuration = config(coordinator)
    configuration.mainGlyphID = 2
    let view = scene(configuration); defer { view.stop() }
    view.configure(rendering: rendering(), anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
      mode: .word, margin: 0.25, smoothScroll: false, carets: configuration, at: 0)
    let within = try XCTUnwrap(coordinator.main.position).minX - 100
    XCTAssertGreaterThan(within, 20)
    configuration.mainGlyphID = 8
    view.configure(rendering: rendering(), anchorCharacterIndex: 6, wordAnchorCharacterIndex: 6,
      mode: .word, margin: 0.25, smoothScroll: false, carets: configuration, at: 1)
    view.present(at: 1)
    XCTAssertEqual(try XCTUnwrap(coordinator.main.position).minX, 100 + within, accuracy: 1e-7)
    XCTAssertLessThan(try textView(in: view).frame.minX, 100)
  }

  func testRepeatedUnchangedViewUpdateDoesNotRestartTapeTween() throws {
    let coordinator = PromptCaretMotionCoordinator(), configuration = config(coordinator)
    let view = scene(configuration); defer { view.stop() }
    view.configure(rendering: rendering(), anchorCharacterIndex: 1, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: true, carets: configuration, at: 1)
    view.present(at: 1.04)
    view.configure(rendering: rendering(), anchorCharacterIndex: 1, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: true, carets: configuration, at: 1.04)
    view.present(at: 1.125)
    XCTAssertFalse(coordinator.isAnimatingTape)
  }

  func testViewUpdateBetweenFramesCannotSampleEitherRunningTapeChannel() throws {
    let coordinator = PromptCaretMotionCoordinator(), configuration = config(coordinator)
    let view = scene(configuration); defer { view.stop() }
    view.configure(rendering: rendering(), anchorCharacterIndex: 1, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: true, carets: configuration, at: 1)
    view.present(at: 1.02)
    let words = coordinator.wordsTapeMargin, pace = coordinator.pace.tapeMargin
    view.configure(rendering: rendering(), anchorCharacterIndex: 1, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: true, carets: configuration, at: 1.04)
    XCTAssertEqual(coordinator.wordsTapeMargin, words)
    XCTAssertEqual(coordinator.pace.tapeMargin, pace)
  }

  func testNewAttemptResetsAllTapeCorrectionsAndDoesNotContinueOldScroll() throws {
    let coordinator = PromptCaretMotionCoordinator(), configuration = config(coordinator)
    let view = scene(configuration); defer { view.stop() }
    view.configure(rendering: rendering(), anchorCharacterIndex: 6, wordAnchorCharacterIndex: 6,
      mode: .letter, margin: 0.25, smoothScroll: true, carets: configuration, at: 1)
    view.present(at: 1.04)
    view.configure(rendering: rendering(), anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: true, carets: config(coordinator), at: 1.04)
    view.present(at: 10)
    XCTAssertEqual(try textView(in: view).frame.minX, 100)
    XCTAssertEqual(coordinator.pace.cumulativeTapeCorrection, 0)
    XCTAssertFalse(coordinator.isAnimatingTape)
  }

  func testDetachedTapeCannotKeepMovingAndWeakTimerDoesNotRetainIt() throws {
    weak var released: TapePromptNativeView?
    autoreleasepool {
      let view = scene(config(.init()))
      released = view
    }
    XCTAssertNil(released)
    let parent = NSView(), coordinator = PromptCaretMotionCoordinator()
    let view = scene(config(coordinator)); parent.addSubview(view)
    let x = try textView(in: view).frame.minX
    view.removeFromSuperview(); view.present(at: 10)
    XCTAssertEqual(try textView(in: view).frame.minX, x)
  }

  func testHorizontalMarginFoldingDoesNotResetVerticalReadyStateOrDrift() throws {
    var channel = PromptCaretChannel()
    channel.goTo(.init(x: 200, y: 50, width: 20, height: 30), at: 0, duration: 0)
    channel.tapeScroll(to: -40, at: 0, duration: 0)
    channel.lineJump(to: -10, at: 0, duration: 0, isPace: true)
    channel.goTo(.init(x: 160, y: 40, width: 20, height: 30), at: 0, duration: 0)
    XCTAssertEqual(channel.visibleRect, .init(x: 160, y: 40, width: 20, height: 30))
    XCTAssertEqual(channel.cumulativeTapeCorrection, -40)
    XCTAssertEqual(channel.tapeMargin, 0); XCTAssertEqual(channel.margin, 0)
    channel.tapeScroll(to: -60, at: 0, duration: 0)
    XCTAssertEqual(channel.tapeMargin, -20)
    channel.tapeWordsRemoved(width: 30)
    channel.tapeScroll(to: -30, at: 0, duration: 0)
    XCTAssertEqual(channel.tapeMargin, -20)
  }

  func testZeroWidthFirstLetterCannotBorrowAPrecedingWordsVisibleSpace() throws {
    let coordinator = PromptCaretMotionCoordinator()
    var configuration = config(coordinator, main: .block)
    configuration.mainGlyphID = 2
    configuration.paceFrame = { .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: false, targetAfter: false, fraction: 1, targetGlyphID: 2) }
    let view = scene(configuration); defer { view.stop() }
    view.configure(rendering: rendering("a \u{200B}b"), anchorCharacterIndex: 2, wordAnchorCharacterIndex: 2,
      wordStartCharacterOffsets: [0: 0, 2: 2, 3: 2], mode: .word, margin: 0.25,
      smoothScroll: false, carets: configuration, at: 1)
    view.present(at: 1)
    XCTAssertEqual(try XCTUnwrap(coordinator.main.position).width, 0)
    XCTAssertEqual(try XCTUnwrap(coordinator.main.position).minX, 100)
    XCTAssertEqual(try XCTUnwrap(coordinator.pace.position).width, 0)
  }

  func testLogicalWordStartsPreserveExtrasAndNoncontiguousRenderedOffsets() {
    var session = TypingSession(configuration: .words(3), prompt: "abc bay cedar")
    session.insertBatch("abcxy ", at: Date(timeIntervalSince1970: 100))
    let glyphs = session.promptGlyphs
    let rendered = PromptRendering.make(glyphs: glyphs, indices: PromptGlyphLayout.indices(
      glyphs: glyphs, words: session.promptWordPresentations, hideExtraLetters: false)) { _, glyph in AttributedString(String(glyph.character)) }
    let starts = PracticeTapePolicy.wordStartCharacterOffsets(session: session, rendering: rendered)
    XCTAssertEqual(starts[4], 0)
    XCTAssertEqual(starts[6], 6)
    XCTAssertNil(starts[5], "Word separators are not part of either word's letter fallback")
  }

  func testChangedGlyphMetricsReanchorTapeEvenWhenLogicalCursorHasNotMoved() throws {
    let coordinator = PromptCaretMotionCoordinator(), configuration = config(coordinator)
    let view = scene(configuration); defer { view.stop() }
    view.configure(rendering: rendering(), anchorCharacterIndex: 1, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: false, carets: configuration, at: 1)
    view.present(at: 1)
    let old = coordinator.wordsTapeMargin
    view.configure(rendering: rendering("🙂mber birch"), anchorCharacterIndex: 1, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: false, carets: configuration, at: 2)
    view.present(at: 2)
    XCTAssertNotEqual(coordinator.wordsTapeMargin, old, "Same logical offset is not the same measured prefix")
    XCTAssertEqual(-coordinator.wordsTapeMargin, ("🙂" as NSString).size(withAttributes: [.font: font]).width, accuracy: 1e-7)
  }

  func testCompletePinnedTapeScrollAndCaretTraceMatchesNativeHorizontalChannels() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"],
      ProcessInfo.processInfo.environment["TYPEBAR_LINE_SCROLL_ANIME_ARCHIVE"] != nil else {
      throw XCTSkip("Readiness supplies the pinned reference and animation archive")
    }
    struct Marker: Decodable { let x, margin, visible, correction: Double; let ready: Bool }
    struct Event: Decodable {
      let type: String; let time: Double
      let id: String?; let value, duration, x, width, words: Double?
      let linear, rendered: Bool?; let main, pace: Marker?
    }
    struct Fixture: Decodable { let mode, style: String; let smooth, overlap: Bool; let trace: [Event] }
    struct Output: Decodable { let pin: String; let fixtures: [Fixture] }
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-tape-presentation.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    guard process.terminationStatus == 0 else { return }
    let source = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(source.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(source.fixtures.count, 32)
    for (index, fixture) in source.fixtures.enumerated() {
      let coordinator = PromptCaretMotionCoordinator(); coordinator.prepare(attemptID: UUID())
      for event in fixture.trace {
        let time = event.time / 1000
        switch event.type {
        case "scroll": coordinator.tapeScroll(to: try XCTUnwrap(event.value),
          duration: try XCTUnwrap(event.duration) / 1000, at: time)
        case "position":
          let rect = CGRect(x: try XCTUnwrap(event.x), y: 0, width: try XCTUnwrap(event.width), height: 32)
          if event.id == "caret" {
            coordinator.positionMain(at: rect, time: time, duration: try XCTUnwrap(event.duration) / 1000)
          } else {
            // The actual resolver reads the presented words margin. Supply
            // the same unscrolled layout geometry, not the sampled result.
            coordinator.positionPace(at: rect.offsetBy(dx: -CGFloat(try XCTUnwrap(event.words)), dy: 0),
              time: time, duration: try XCTUnwrap(event.duration) / 1000)
          }
        case "frame": if event.rendered == true { coordinator.sample(at: time) }
        case "sample":
          let message = "fixture \(index), \(fixture.mode)/\(fixture.style)/\(fixture.smooth)/\(fixture.overlap), t=\(event.time)"
          XCTAssertEqual(coordinator.wordsTapeMargin, try XCTUnwrap(event.words), accuracy: 1e-6, message)
          for (channel, expected) in [(coordinator.main, try XCTUnwrap(event.main)), (coordinator.pace, try XCTUnwrap(event.pace))] {
            XCTAssertEqual(try XCTUnwrap(channel.position).minX, expected.x, accuracy: 1e-6, message)
            XCTAssertEqual(channel.tapeMargin, expected.margin, accuracy: 1e-6, message)
            XCTAssertEqual(try XCTUnwrap(channel.visibleRect).minX, expected.visible, accuracy: 1e-6, message)
            XCTAssertEqual(channel.cumulativeTapeCorrection, expected.correction, accuracy: 1e-6, message)
            XCTAssertEqual(channel.tapeMarginReady, expected.ready, message)
          }
        default: XCTFail("Unknown actual source trace event")
        }
      }
    }
  }

  func testReducedMotionSnapsTapeAndKeepsBlinkingMainSolid() throws {
    let coordinator = PromptCaretMotionCoordinator()
    var configuration = config(coordinator); configuration = .init(text: configuration.text,
      mainOffset: nil, paceOffset: nil, mainStyle: .bar, paceStyle: .outline,
      font: font, lineSpacing: 0, rightToLeft: false, accent: .yellow,
      motion: .medium, reducesMotion: true, frameRate: 60,
      attemptID: configuration.attemptID, coordinator: coordinator, mainGlyphID: 0)
    let view = scene(configuration); defer { view.stop() }
    view.configure(rendering: rendering(), anchorCharacterIndex: 2, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: true, carets: configuration, at: 1)
    view.present(at: 1)
    XCTAssertFalse(coordinator.isAnimatingTape)
    XCTAssertLessThan(try textView(in: view).frame.minX, 100)
    let child = try XCTUnwrap(view.subviews.compactMap { $0 as? PromptCaretNativeView }.first)
    let main = try XCTUnwrap(child.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }.first { $0.rootView.style == .bar })
    view.present(at: 1.75); XCTAssertEqual(main.alphaValue, 1)
  }

  func testNativeTapeDrawStoragePreservesUnicodeColorsHiddenTargetsAndErrorUnderline() throws {
    var text = AttributedString("🙂é")
    text.foregroundColor = .gray; text.backgroundColor = .blue
    PromptGlyphAppearance(color: .completed, hasErrorUnderline: true).applyErrorUnderline(to: &text, errorColor: .yellow)
    var hidden = AttributedString("z"); hidden.foregroundColor = .clear
    hidden.baselineOffset = -4; hidden.kern = -2
    text += hidden
    let storage = TapePromptTextStorage.prepare(text, font: font)
    XCTAssertEqual(storage.string, "🙂éz")
    func color(_ key: NSAttributedString.Key, _ index: Int) throws -> NSColor {
      try XCTUnwrap((storage.attribute(key, at: index, effectiveRange: nil) as? NSColor)?.usingColorSpace(.deviceRGB))
    }
    XCTAssertEqual(try color(.foregroundColor, 0), NSColor(Color.gray).usingColorSpace(.deviceRGB))
    XCTAssertEqual(try color(.backgroundColor, 2), NSColor(Color.blue).usingColorSpace(.deviceRGB))
    XCTAssertEqual(try color(.underlineColor, 2), NSColor(Color.yellow).usingColorSpace(.deviceRGB))
    XCTAssertEqual(storage.attribute(.underlineStyle, at: 2, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
    XCTAssertEqual(try color(.foregroundColor, 3).alphaComponent, 0)
    XCTAssertEqual(storage.attribute(.baselineOffset, at: 3, effectiveRange: nil) as? Double, -4)
    XCTAssertEqual(storage.attribute(.kern, at: 3, effectiveRange: nil) as? Double, -2)
  }

  func testRealTapeTextBlinkAndScrollRenderSeriallyWithoutShowingWindow() throws {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 60),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
    let view = scene(config(.init())); window.contentView = view
    defer { view.stop(); window.contentView = nil; window.close() }
    view.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    let coordinator = PromptCaretMotionCoordinator(), attempt = UUID()
    var typed = "", configuration = config(coordinator, attempt: attempt)
    configuration.latestInput = { .init(attemptID: attempt, typed: typed, composition: "", glyphID: nil) }
    view.configure(rendering: rendering(), anchorCharacterIndex: 0, wordAnchorCharacterIndex: 0,
      mode: .letter, margin: 0.25, smoothScroll: true, carets: configuration, at: 0)
    var images: [Data] = []
    for (name, time) in [("tape-caret-on", 0.0), ("tape-caret-off", 0.75), ("tape-scroll-midpoint", 1.05)] {
      if time > 1 {
        typed = "a"; configuration.mainPresentation = { .init(isVisible: true, isBlinking: false) }
        view.configure(rendering: rendering(), anchorCharacterIndex: 1, wordAnchorCharacterIndex: 0,
          mode: .letter, margin: 0.25, smoothScroll: true, carets: configuration, at: 1)
      }
      view.present(at: time); view.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      var grayPixels = 0, opaquePixels = 0
      let scaleX = Double(bitmap.pixelsWide) / view.bounds.width
      let scaleY = Double(bitmap.pixelsHigh) / view.bounds.height
      for x in Int(105 * scaleX)..<Int(190 * scaleX) { for y in 0..<min(Int(60 * scaleY), bitmap.pixelsHigh) {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.2 else { continue }
        opaquePixels += 1
        if abs(color.redComponent - color.greenComponent) < 0.05,
          abs(color.greenComponent - color.blueComponent) < 0.05,
          color.redComponent > 0.1, color.redComponent < 0.9 { grayPixels += 1 }
      } }
      XCTAssertGreaterThan(grayPixels, 50, "Actual gray text must render, not only the caret layers; opaque=\(opaquePixels)")
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:])); images.append(png)
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
      }
      XCTAssertFalse(window.isVisible)
    }
    XCTAssertNotEqual(images[0], images[1]); XCTAssertNotEqual(images[0], images[2])
  }
}
