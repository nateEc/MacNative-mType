import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptCaretBlinkTests: XCTestCase {
  private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  private func configuration(_ coordinator: PromptCaretMotionCoordinator = .init(),
    attempt: UUID = UUID(), motion: SmoothCaretMotion = .off,
    reduced: Bool = false) -> PromptCaretNativeView.Configuration {
    .init(text: AttributedString("amber birch"), mainOffset: 1, paceOffset: 3,
      mainStyle: .bar, paceStyle: .outline,
      font: .monospacedSystemFont(ofSize: 28, weight: .medium), lineSpacing: 12,
      rightToLeft: false, accent: .yellow, motion: motion, reducesMotion: reduced,
      frameRate: 60, attemptID: attempt, coordinator: coordinator)
  }

  func testNativeCurvesMatchThirtyTwoActualPausedBrowserSamples() throws {
    struct Samples: Decodable {
      let referenceCommit: String; let cssHash: String
      let timesMilliseconds: [Double]; let smooth: [Double]; let hard: [Double]
    }
    let samples = try JSONDecoder().decode(Samples.self,
      from: Data(contentsOf: root.appendingPathComponent("Compatibility/caret-blink-browser-samples.json")))
    XCTAssertEqual(samples.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(samples.cssHash, "b4caa684bfc4e265f463be27942fcf0989bbfaf8dd6f3ad0a4e94d9741e38bd9")
    XCTAssertEqual(samples.timesMilliseconds.count, 16)
    for (smooth, values) in [(true, samples.smooth), (false, samples.hard)] {
      XCTAssertEqual(values.count, samples.timesMilliseconds.count)
      for (time, opacity) in zip(samples.timesMilliseconds, values) {
        XCTAssertEqual(PromptCaretBlinkCurve.opacity(elapsed: time / 1000, smooth: smooth), opacity,
          accuracy: 0.00001, "smooth=\(smooth), time=\(time)")
      }
    }
  }

  func testHardFadeIsNotASquareWaveAndInvalidTimesAreSafe() {
    XCTAssertEqual(PromptCaretBlinkCurve.opacity(elapsed: 0.5, smooth: false), 1)
    XCTAssertGreaterThan(PromptCaretBlinkCurve.opacity(elapsed: 0.505, smooth: false), 0)
    XCTAssertLessThan(PromptCaretBlinkCurve.opacity(elapsed: 0.505, smooth: false), 1)
    XCTAssertEqual(PromptCaretBlinkCurve.opacity(elapsed: 0.51, smooth: false), 0)
    for time in [Double.nan, .infinity, -.infinity] {
      XCTAssertEqual(PromptCaretBlinkCurve.opacity(elapsed: time, smooth: true), 1)
    }
    XCTAssertEqual(PromptCaretBlinkCurve.opacity(elapsed: -1, smooth: false), 1)
  }

  func testClockKeepsSameAnimationNamePhaseAndRestartsWhenKindChanges() {
    var clock = PromptCaretBlinkClock()
    let state = PromptCaretBlinkPresentation()
    XCTAssertEqual(clock.opacity(at: 10, presentation: state, motion: .slow, reducesMotion: false), 0, accuracy: 1e-8)
    let expected = PromptCaretBlinkCurve.opacity(elapsed: 0.25, smooth: true)
    XCTAssertEqual(clock.opacity(at: 10.25, presentation: state, motion: .fast, reducesMotion: false), expected, accuracy: 1e-8)
    XCTAssertEqual(clock.opacity(at: 10.75, presentation: state, motion: .off, reducesMotion: false), 1)
    XCTAssertEqual(clock.opacity(at: 11.5, presentation: state, motion: .off, reducesMotion: false), 0)
    XCTAssertEqual(clock.opacity(at: 12, presentation: state, motion: .medium, reducesMotion: false), 0, accuracy: 1e-8)
  }

  func testClockObservesBetweenFrameStopRestartViaRevision() {
    var clock = PromptCaretBlinkClock(), state = PromptCaretBlinkPresentation()
    _ = clock.opacity(at: 0, presentation: state, motion: .off, reducesMotion: false)
    XCTAssertEqual(clock.opacity(at: 0.75, presentation: state, motion: .off, reducesMotion: false), 0)
    state.revision = 2 // stop and start both happened before the next presentation.
    XCTAssertEqual(clock.opacity(at: 0.76, presentation: state, motion: .off, reducesMotion: false), 1)
    XCTAssertEqual(clock.opacity(at: 1.51, presentation: state, motion: .off, reducesMotion: false), 0)
  }

  func testHiddenStoppedAndReducedMotionResetRatherThanAccumulatingTime() {
    var clock = PromptCaretBlinkClock(), state = PromptCaretBlinkPresentation()
    _ = clock.opacity(at: 0, presentation: state, motion: .off, reducesMotion: false)
    state.isVisible = false
    XCTAssertEqual(clock.opacity(at: 0.75, presentation: state, motion: .off, reducesMotion: false), 0)
    state.isVisible = true
    XCTAssertEqual(clock.opacity(at: 5, presentation: state, motion: .off, reducesMotion: false), 1)
    state.isBlinking = false
    XCTAssertEqual(clock.opacity(at: 5.75, presentation: state, motion: .off, reducesMotion: false), 1)
    state.isBlinking = true
    XCTAssertEqual(clock.opacity(at: 6, presentation: state, motion: .off, reducesMotion: true), 1)
    XCTAssertEqual(clock.opacity(at: 8, presentation: state, motion: .off, reducesMotion: false), 1)
    XCTAssertEqual(clock.opacity(at: .nan, presentation: state, motion: .off, reducesMotion: false), 1)
    XCTAssertEqual(clock.opacity(at: 10, presentation: state, motion: .off, reducesMotion: false), 1)
  }

  func testFreshProviderStopsHidesAndRestartsWithoutGeometryOrSwiftUIUpdate() throws {
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 150))
    defer { view.stop() }
    var state = PromptCaretBlinkPresentation(), reads = 0
    var config = configuration()
    let attempt = config.attemptID
    config.mainPresentation = { state }
    config.latestInput = { .init(attemptID: attempt, typed: "a", composition: "", glyphID: 0) }
    config.latestRendering = { reads += 1; return .init(text: AttributedString("amber birch"), glyphCharacterOffsets: [0: 1]) }
    view.update(config); view.layout(); view.present(at: 0)
    let main = try XCTUnwrap(view.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }.first { $0.rootView.style == .bar })
    let frames = view.subviews.map(\.frame)
    view.present(at: 0.75); XCTAssertEqual(main.alphaValue, 0)
    state.isBlinking = false; state.revision += 1
    view.present(at: 0.76); XCTAssertEqual(main.alphaValue, 1)
    state.isVisible = false
    view.present(at: 0.77); XCTAssertEqual(main.alphaValue, 0)
    state.isVisible = true; state.isBlinking = true; state.revision += 1
    view.present(at: 0.78); XCTAssertEqual(main.alphaValue, 1)
    view.present(at: 1.53); XCTAssertEqual(main.alphaValue, 0)
    XCTAssertEqual(reads, 1); XCTAssertEqual(view.subviews.map(\.frame), frames)
  }

  func testAttemptAndStopRestartResetNativeClockAndReducedMotionRemainsSolid() throws {
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 150))
    defer { view.stop() }
    let coordinator = PromptCaretMotionCoordinator()
    view.update(configuration(coordinator)); view.layout(); view.present(at: 0); view.present(at: 0.75)
    func main() throws -> NSHostingView<PromptCaretMarkerView> {
      try XCTUnwrap(view.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }.first { $0.rootView.style == .bar })
    }
    XCTAssertEqual(try main().alphaValue, 0)
    view.update(configuration(coordinator)); view.present(at: 0.8)
    XCTAssertEqual(try main().alphaValue, 1)
    view.present(at: 1.55); XCTAssertEqual(try main().alphaValue, 0)
    view.stop(); view.present(at: 1.6); XCTAssertEqual(try main().alphaValue, 0)
    view.update(configuration(coordinator)); view.present(at: 2)
    XCTAssertEqual(try main().alphaValue, 1)
    let attempt = UUID()
    view.update(configuration(coordinator, attempt: attempt, reduced: true))
    view.present(at: 2.75); view.present(at: 3.5)
    XCTAssertEqual(try main().alphaValue, 1)
  }

  func testRepeatedInputStopsBlinkEvenWhenFocusAlreadyCommitted() {
    var callbacks: [@MainActor () -> Void] = []
    let focus = TypingVisualFocus { callbacks.append($0) }
    focus.set(true); callbacks.forEach { $0() }; callbacks.removeAll()
    XCTAssertTrue(focus.isFocused); XCTAssertFalse(focus.caretIsBlinking)
    focus.startCaretBlinking() // actual smooth-caret configuration change while focused.
    XCTAssertTrue(focus.caretIsBlinking)
    focus.inputDidUpdate(hasFeedback: true, textChanged: false, isFinished: false)
    XCTAssertFalse(focus.caretIsBlinking); XCTAssertTrue(callbacks.isEmpty)
    XCTAssertEqual(focus.caretBlinkRevision, 3)
  }

  func testRefocusRestartsAnimationEvenIfNoHiddenFrameWasPresented() {
    let focus = TypingVisualFocus { _ in }
    var clock = PromptCaretBlinkClock()
    func state() -> PromptCaretBlinkPresentation {
      .init(isBlinking: focus.caretIsBlinking, revision: focus.caretBlinkRevision)
    }
    _ = clock.opacity(at: 0, presentation: state(), motion: .off, reducesMotion: false)
    XCTAssertEqual(clock.opacity(at: 0.75, presentation: state(), motion: .off, reducesMotion: false), 0)
    focus.caretDidBecomeVisible()
    XCTAssertEqual(clock.opacity(at: 0.76, presentation: state(), motion: .off, reducesMotion: false), 1)
    XCTAssertTrue(focus.caretIsBlinking)
    XCTAssertEqual(focus.caretBlinkRevision, 1)
  }

  func testEveryVisibleMarkerStyleUsesBlinkWithoutRemovingItsView() throws {
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 150))
    defer { view.stop() }
    for style in TypingCaretStyle.allCases where style.drawsMarker {
      var config = configuration()
      config = .init(text: config.text, mainOffset: config.mainOffset, paceOffset: nil,
        mainStyle: style, paceStyle: .off, font: config.font, lineSpacing: config.lineSpacing,
        rightToLeft: false, accent: .yellow, motion: .off, reducesMotion: false,
        frameRate: 60, attemptID: config.attemptID, coordinator: config.coordinator)
      view.update(config); view.layout(); view.present(at: 0)
      let marker = try XCTUnwrap(view.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }.first { $0.rootView.style == style })
      view.present(at: 0.75)
      XCTAssertEqual(marker.alphaValue, 0, "\(style)"); XCTAssertFalse(marker.isHidden)
      view.present(at: 1)
      XCTAssertEqual(marker.alphaValue, 1, "\(style)")
    }
  }

  func testProductionBlinkProviderFocusCompositionAndConfigurationWiring() throws {
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let overlay = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/PromptCaretOverlay.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("mainPresentation: { .init("))
    XCTAssertTrue(app.contains("isVisible: (inputHasFocus || showsVirtualKeyboard) && typingWindowHasFocus && !session.isFinished"))
    XCTAssertTrue(app.contains("isBlinking: visualFocus.caretIsBlinking"))
    XCTAssertTrue(app.contains("revision: visualFocus.caretBlinkRevision"))
    XCTAssertTrue(app.contains("if hasFocus, !inputHasFocus { visualFocus.caretDidBecomeVisible() }"))
    XCTAssertTrue(app.contains("if hasFocus, !typingWindowHasFocus { visualFocus.caretDidBecomeVisible() }"))
    XCTAssertTrue(app.contains(".onChange(of: settings.smoothCaretMotion) { _, _ in visualFocus.startCaretBlinking() }"))
    XCTAssertTrue(app.contains("visualFocus.inputDidUpdate(hasFeedback: hadMarkedText || !$0.isEmpty"))
    XCTAssertTrue(overlay.contains("paceFrame: paceFrame, mainPresentation: mainPresentation"))
  }

  func testNativeCaretPhasesRenderInOneNeverVisibleComponentWindow() throws {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 400, height: 100),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 100))
    window.contentView = view
    defer { view.stop(); window.contentView = nil; window.close() }
    view.update(configuration()); view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    view.update(configuration()); view.layoutSubtreeIfNeeded(); view.present(at: 0)
    var images: [Data] = []
    for (name, time) in [("caret-hard-on", 0.0), ("caret-hard-off", 0.75)] {
      view.present(at: time)
      view.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      images.append(png)
      if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
      }
      XCTAssertFalse(window.isVisible)
    }
    XCTAssertNotEqual(images[0], images[1], "Must capture the real presentation difference, not just model state")
  }

  func testRetirementRestoresBlinkAndStaleFocusCommitCannotStopIt() {
    var callbacks: [@MainActor () -> Void] = []
    let focus = TypingVisualFocus { callbacks.append($0) }
    focus.inputDidUpdate(hasFeedback: true, textChanged: true, isFinished: false)
    XCTAssertFalse(focus.caretIsBlinking)
    focus.retire(); callbacks.forEach { $0() }
    XCTAssertFalse(focus.isFocused); XCTAssertTrue(focus.caretIsBlinking)
  }

  func testComposedPinnedCaretFocusAndInputStates() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned clean reference")
    }
    struct Action: Decodable {
      let kind: String; let value: Value?
      enum Value: Decodable {
        case bool(Bool), string(String)
        init(from decoder: Decoder) throws {
          let container = try decoder.singleValueContainer()
          if let value = try? container.decode(Bool.self) { self = .bool(value) }
          else { self = .string(try container.decode(String.self)) }
        }
      }
    }
    struct State: Decodable { let focused: Bool; let blinking: Bool; let mode: String }
    struct Fixture: Decodable { let actions: [Action]; let states: [State] }
    struct Output: Decodable { let pin: String; let cssHash: String; let fixtures: [Fixture] }
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-caret-blink.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    guard process.terminationStatus == 0 else { return }
    let source = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(source.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(source.cssHash, "b4caa684bfc4e265f463be27942fcf0989bbfaf8dd6f3ad0a4e94d9741e38bd9")
    XCTAssertEqual(source.fixtures.count, 4); XCTAssertEqual(source.fixtures.map { $0.states.count }.reduce(0, +), 28)
    for (scenario, fixture) in source.fixtures.enumerated() {
      var callbacks: [@MainActor () -> Void] = []
      let focus = TypingVisualFocus { callbacks.append($0) }
      XCTAssertEqual(fixture.actions.count, fixture.states.count)
      for (index, action) in fixture.actions.enumerated() {
        switch action.kind {
        case "focus":
          guard case .bool(let value) = action.value else { return XCTFail("Expected focus Bool") }
          focus.set(value)
        case "flush": let batch = callbacks; callbacks.removeAll(); batch.forEach { $0() }
        case "mouse": focus.mouseMoved(x: 4, y: 0)
        case "input": focus.inputDidUpdate(hasFeedback: true, textChanged: true, isFinished: false)
        case "motion", "start": focus.startCaretBlinking()
        case "stop": focus.stopCaretBlinking()
        default: XCTFail("Unknown source action")
        }
        XCTAssertEqual(focus.isFocused, fixture.states[index].focused, "scenario \(scenario), step \(index)")
        XCTAssertEqual(focus.caretIsBlinking, fixture.states[index].blinking, "scenario \(scenario), step \(index)")
      }
    }
  }

  func testIdleHardBlinkChangesOnlyMainOpacityWithoutMovingEitherCaret() throws {
    let view = PromptCaretNativeView(frame: .init(x: 0, y: 0, width: 400, height: 150))
    defer { view.stop() }
    view.update(.init(text: AttributedString("amber birch"), mainOffset: 1, paceOffset: 3,
      mainStyle: .bar, paceStyle: .outline,
      font: .monospacedSystemFont(ofSize: 28, weight: .medium), lineSpacing: 12,
      rightToLeft: false, accent: .yellow, motion: .off, reducesMotion: false,
      frameRate: 60, attemptID: UUID(), coordinator: PromptCaretMotionCoordinator()))
    view.layout(); view.present(at: 0)
    let markers = view.subviews.compactMap { $0 as? NSHostingView<PromptCaretMarkerView> }
    let main = try XCTUnwrap(markers.first { $0.rootView.style == .bar })
    let pace = try XCTUnwrap(markers.first { $0.rootView.style == .outline })
    let frames = markers.map(\.frame)
    XCTAssertEqual(main.alphaValue, 1)
    view.present(at: 0.75)
    XCTAssertEqual(main.alphaValue, 0, accuracy: 0.00001)
    XCTAssertEqual(pace.alphaValue, 1)
    XCTAssertEqual(markers.map(\.frame), frames)
  }
}
