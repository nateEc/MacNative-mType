import AppKit
import XCTest
@testable import Typebar

@MainActor final class PromptViewportRetainedGeometryTests: XCTestCase {
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
  private let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
    accent: .blue, colorScheme: .light))
  private let start = Date(timeIntervalSinceReferenceDate: 920_500_000)

  private func measured(_ session: TypingSession, style: PromptRenderStyle? = nil,
    joinsLetters: Bool = false) throws -> PromptViewportFieldLayoutSequence {
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let sequence = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style ?? self.style, width: 180, font: font,
      joinsLetters: joinsLetters))
    while sequence.nextField < sequence.fieldCount {
      let begin = sequence.nextField
      _ = try XCTUnwrap(sequence.append(fields: begin..<min(begin + 8, sequence.fieldCount)))
    }
    return sequence
  }

  func testRetainedBoundariesMatchFreshReflowAcrossInputErrorsCommitsAndDeletion() throws {
    var session = TypingSession(configuration: .words(97),
      prompt: Array(repeating: "oak", count: 97).joined(separator: " "))
    var previous = try measured(session)
    let oldWindow = try XCTUnwrap(previous.revisit(fields: 0..<8))
    let oldInk = oldWindow.runs
    for (index, input) in ["o", "a", "x", "\u{8}", "k ", "\u{8}"].enumerated() {
      if input == "\u{8}" { session.deleteBackward(at: start.addingTimeInterval(Double(index))) }
      else { session.insertBatch(input, at: start.addingTimeInterval(Double(index))) }
      let next = try XCTUnwrap(previous.replacingSessionRetainingTargetGeometry(session, style: style))
      let fresh = try measured(session)
      XCTAssertEqual(next.nextField, fresh.nextField)
      XCTAssertEqual(next.contentHeight, fresh.contentHeight)
      XCTAssertNil(next.drawingSnapshot(windows: [oldWindow]), "Old ink must not acquire a new owner")
      for span in fresh.measuredSpans {
        let reused = try XCTUnwrap(next.revisit(fields: span.fields))
        let expected = try XCTUnwrap(fresh.revisit(fields: span.fields))
        XCTAssertEqual(reused.runs, expected.runs)
        XCTAssertEqual(reused.layout.cellFrames, expected.layout.cellFrames)
        XCTAssertEqual(reused.layout.fieldFrames, expected.layout.fieldFrames)
        XCTAssertEqual(reused.layout.size, expected.layout.size)
        XCTAssertEqual(reused.layout.mainRect(style: .bar), expected.layout.mainRect(style: .bar))
      }
      XCTAssertEqual(oldWindow.runs, oldInk)
      previous = next
    }
  }

  func testMetricChangingAndUnsupportedProjectionsCannotRetainTargetGeometry() throws {
    var session = TypingSession(configuration: .words(3), prompt: "oak ash elm")
    for typo in [TypoIndicatorStyle.replace, .below, .both] {
      var appearance = style; appearance.typoIndicatorStyle = typo
      let sequence = try measured(session, style: appearance)
      XCTAssertNil(sequence.replacingSessionRetainingTargetGeometry(session, style: appearance))
    }
    var dots = style; dots.typedCharacterEffect = .dots
    XCTAssertNil(try measured(session, style: dots)
      .replacingSessionRetainingTargetGeometry(session, style: dots))
    XCTAssertNil(try measured(session, joinsLetters: true)
      .replacingSessionRetainingTargetGeometry(session, style: style))
    let sequence = try measured(session)
    XCTAssertNil(sequence.replacingSessionRetainingTargetGeometry(session.repeatedAttempt(), style: style))
    var changedStyle = style; changedStyle.colorfulMode = true
    XCTAssertNil(sequence.replacingSessionRetainingTargetGeometry(session, style: changedStyle))
    session.insertBatch("oakx", at: start)
    XCTAssertNil(sequence.replacingSessionRetainingTargetGeometry(session, style: style))
    var stopped = TypingSession(configuration: .words(3,
      rules: .init(stopOnErrorMode: .letter)), prompt: "oak ash elm")
    let stoppedSequence = try measured(stopped)
    stopped.insertBatch("x", at: start)
    XCTAssertNil(stoppedSequence.replacingSessionRetainingTargetGeometry(stopped, style: style))
    stopped.bailOut(at: start.addingTimeInterval(1))
    XCTAssertNil(stoppedSequence.replacingSessionRetainingTargetGeometry(stopped, style: style))
  }

  func testPartialPrefixContinuesFromRetainedBoundaryWithoutMutatingOldSequence() throws {
    var session = TypingSession(configuration: .words(97),
      prompt: Array(repeating: "oak", count: 97).joined(separator: " "))
    let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
    let old = try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
      directory: directory, style: style, width: 180, font: font))
    _ = try XCTUnwrap(old.append(fields: 0..<8))
    session.insert("o", at: start)
    let next = try XCTUnwrap(old.replacingSessionRetainingTargetGeometry(session, style: style))
    let continued = try XCTUnwrap(next.append(fields: 8..<16))
    let expected = try XCTUnwrap(try measured(session).revisit(fields: 8..<16))
    XCTAssertEqual(continued.runs, expected.runs)
    XCTAssertEqual(continued.layout.cellFrames, expected.layout.cellFrames)
    XCTAssertEqual(continued.layout.size, expected.layout.size)
    XCTAssertEqual(next.nextField, 16)
    XCTAssertEqual(old.nextField, 8)
  }

  func testProportionalControlAndRTLTargetMetricsMatchFreshReflow() throws {
    for rtl in [false, true] {
      var session = TypingSession(configuration: .words(5), prompt: "Wide i\n oak\t ash  elm")
      let directory = try XCTUnwrap(PromptViewportTargetDirectory(session: session))
      func sequence() throws -> PromptViewportFieldLayoutSequence {
        try XCTUnwrap(PromptViewportFieldLayoutSequence(session: session,
          directory: directory, style: style, width: 120,
          font: NSFont.systemFont(ofSize: 28), rightToLeft: rtl))
      }
      let old = try sequence()
      for field in 0..<old.fieldCount {
        _ = try XCTUnwrap(old.append(fields: field..<(field + 1)))
      }
      session.insert("x", at: start)
      let next = try XCTUnwrap(old.replacingSessionRetainingTargetGeometry(session, style: style))
      let fresh = try sequence()
      for field in 0..<fresh.fieldCount {
        let fields = field..<(field + 1)
        let expected = try XCTUnwrap(fresh.append(fields: fields))
        let actual = try XCTUnwrap(next.revisit(fields: fields))
        XCTAssertEqual(actual.runs, expected.runs)
        XCTAssertEqual(actual.layout.cellFrames, expected.layout.cellFrames)
        XCTAssertEqual(actual.layout.size, expected.layout.size)
      }
      XCTAssertEqual(next.contentHeight, fresh.contentHeight)
    }
  }

  func testRemoteInputRetainsCompleteHeightPositionSelectionAndCurrentInk() throws {
    let count = 97
    var session = TypingSession(configuration: .words(count),
      prompt: Array(repeating: "oak", count: count).joined(separator: " "))
    session.insertBatch(String(repeating: "oak ", count: 80), at: start)
    let sequence = try measured(session)
    _ = NSApplication.shared
    _ = NSScroller.preferredScrollerStyle
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    let host = PromptViewportNativeScrollHost()
    host.scrollView.scrollerStyle = .overlay
    host.frame = .init(x: 0, y: 0, width: 180, height: 100)
    host.scrollView.tile()
    defer { host.stop() }
    XCTAssertTrue(host.configure(sequence: sequence, batchSize: 8))
    XCTAssertTrue(host.scrollToField(80))
    let origin = host.visibleDocumentRect.origin
    let height = host.canvas.frame.height
    let ink = try XCTUnwrap(host.canvas.renderedCellText(for: 320))
    let rect = try XCTUnwrap(host.canvas.measuredRect(for: 320))
    let selection = NSRange(location: 320, length: 3)
    host.canvas.restoreAccessibilitySelection(selection)
    session.insert("x", at: start.addingTimeInterval(1))
    XCTAssertTrue(host.replaceVisibleSession(session, style: style))
    XCTAssertTrue(host.canvas.hasCompleteHeight)
    XCTAssertEqual(host.measuredFieldCount, count)
    XCTAssertEqual(host.canvas.frame.height, height)
    XCTAssertEqual(host.visibleDocumentRect.origin, origin)
    XCTAssertEqual(host.canvas.measuredRect(for: 320), rect)
    XCTAssertNotEqual(host.canvas.renderedCellText(for: 320), ink)
    XCTAssertEqual(host.canvas.accessibilitySelectedTextRange(), selection)
    XCTAssertEqual(host.canvas.accessibilityValue() as? String, session.prompt)
  }
}
