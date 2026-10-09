import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptFieldInputWrapTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 916_300_000)
  private let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .medium)

  private func rendering(_ session: TypingSession) throws -> PromptRendering {
    let presentation = try XCTUnwrap(PromptCompositionPresentation(session: session, composition: "", style: .replace))
    return presentation.render { _, glyph, _ in
      AttributedString(PromptControlCharacterPresentation.plan(for: glyph, style: .off).text)
    }
  }

  private func width(_ columns: CGFloat) -> CGFloat {
    ("a" as NSString).size(withAttributes: [.font: font]).width * columns
  }

  func testAlreadyWrappedFieldDoesNotRejectGrowthBecauseLegacyGlobalTextWouldMoveIt() throws {
    var session = TypingSession(configuration: .words(3), prompt: "aa bb cc")
    session.insertBatch("aa bb", at: start)
    let result = try rendering(session)
    let layout = PromptFieldTextLayout(map: try XCTUnwrap(result.compositionTextMap), width: width(5.2), font: font)
    XCTAssertGreaterThan(try XCTUnwrap(layout.fieldFrames[1]).minY, try XCTUnwrap(layout.fieldFrames[0]).minY)
    XCTAssertFalse(PromptInputWrapGeometry.rejects(session: session, candidate: Array("bbx".utf16),
      rendering: result, width: width(5.2), font: font, lineSpacing: 12, isRightToLeft: false))
  }

  func testFirstFieldHeightGrowthStillRejectsAndNoGrowthDoesNot() throws {
    var session = TypingSession(configuration: .words(2), prompt: "aaaa tail")
    session.insertBatch("aaaa", at: start)
    let result = try rendering(session)
    for candidate in ["aaaa", "aaaax"] {
      XCTAssertEqual(PromptInputWrapGeometry.rejects(session: session, candidate: Array(candidate.utf16),
        rendering: result, width: width(4.2), font: font, lineSpacing: 12, isRightToLeft: false), candidate == "aaaax")
    }
  }

  private func rejects(_ session: TypingSession, candidate: String, columns: CGFloat = 5.2,
    rtl: Bool = false, joins: Bool = false) throws -> Bool {
    PromptInputWrapGeometry.rejects(session: session, candidate: Array(candidate.utf16),
      rendering: try rendering(session), width: width(columns), font: font, lineSpacing: 12,
      isRightToLeft: rtl, joinsLetters: joins)
  }

  private func result(_ session: TypingSession) throws -> CompletedTestResult {
    var ended = session
    if !ended.isFinished { ended.failForTimerHealth(at: start.addingTimeInterval(2)) }
    return try XCTUnwrap(ended.result())
  }

  func testBatchAcceptsFittingExtrasAndRejectsOnlyGrowthBeforeMetricsAndReplay() throws {
    var session = TypingSession(configuration: .words(3), prompt: "aa bb cc")
    session.insertBatch("aa bb", at: start)
    var probed: [String] = []
    session.insertBatch("xxyz cc", at: start.addingTimeInterval(1), wrapAdmission: .init { current, candidate in
      probed.append(String(decoding: candidate, as: UTF16.self))
      return PromptInputWrapGeometry.rejects(session: current, candidate: candidate,
        rendering: try! self.rendering(current), width: self.width(5.2), font: self.font,
        lineSpacing: 12, isRightToLeft: false)
    })
    XCTAssertEqual(probed, ["bbx", "bbxx", "bbxxy", "bbxxyz"])
    XCTAssertEqual(session.typed, "aa bbxxy cc")
    XCTAssertEqual(session.outcome, .completed)
    let saved = try result(session)
    XCTAssertEqual(saved.inputMetrics?.totalAttempts, 11)
    XCTAssertEqual(saved.replayEvents.filter { $0.kind == .insert }.map(\.text).joined(), session.typed)
    XCTAssertFalse(saved.replayEvents.contains { $0.text.contains("z") })
  }

  func testRejectedExtraCannotMutateSessionOrRenderingSnapshots() throws {
    var session = TypingSession(configuration: .words(2), prompt: "aaaa tail")
    session.insertBatch("aaaa", at: start)
    let rendering = try rendering(session), fields = try XCTUnwrap(rendering.compositionTextMap?.fieldRuns)
    let before = try result(session)
    session.insertBatch("x", at: start.addingTimeInterval(1), wrapAdmission: .init { current, candidate in
      PromptInputWrapGeometry.rejects(session: current, candidate: candidate, rendering: rendering,
        width: self.width(4.2), font: self.font, lineSpacing: 12, isRightToLeft: false)
    })
    let after = try result(session)
    XCTAssertEqual(after.inputMetrics, before.inputMetrics)
    XCTAssertEqual(after.replayEvents, before.replayEvents)
    XCTAssertEqual(session.typed, "aaaa")
    XCTAssertEqual(rendering.compositionTextMap?.fieldRuns, fields)
  }

  func testRetiredPrefixKeepsActualOwnerAndTheAlreadyWrappedRow() throws {
    var session = TypingSession(configuration: .words(4), prompt: "aa bb cc dd")
    session.insertBatch("aa bb cc", at: start)
    session.retirePromptWords(.init(attemptID: session.automaticInputAttemptID, firstRetainedWordIndex: 1))
    let map = try XCTUnwrap(rendering(session).compositionTextMap)
    XCTAssertFalse(map.fieldRuns.contains { $0.fieldID == 0 })
    XCTAssertFalse(try rejects(session, candidate: "ccx"))
    XCTAssertTrue(try rejects(session, candidate: "ccxxxx", columns: 5.2))
  }

  func testWrongReturnTargetAndActualExtrasShareOneContainer() throws {
    var session = TypingSession(configuration: .words(2), prompt: "aa\nbb")
    session.insertBatch("aax", at: start)
    let current = try XCTUnwrap(rendering(session).compositionTextMap)
    XCTAssertEqual(current.fieldRuns.filter { $0.fieldID == 0 }.flatMap(\.cells).map(\.glyph.character), ["a", "a", "\n"])
    XCTAssertTrue(try rejects(session, candidate: "aaxy", columns: 3.2))
    XCTAssertTrue(try rejects(session, candidate: "aaxyyy", columns: 3.2))
    XCTAssertFalse(try rejects(session, candidate: "aaxy", columns: 8.2))
  }

  func testReturnFieldAdmissionCountsExtrasBeforeTheContainerBreak() throws {
    var session = TypingSession(configuration: .words(2), prompt: "aa\nbb")
    session.insertBatch("aaxy", at: start)
    // Four slots fit on the first row. A fifth must not be admitted into an
    // invented row after the Return icon: the break follows the whole word.
    XCTAssertTrue(try rejects(session, candidate: "aaxyz", columns: 4.2))
    XCTAssertFalse(try rejects(session, candidate: "aaxyz", columns: 5.2))
  }

  func testRTLAndJoiningFlagsDoNotReintroduceGlobalWordReflow() throws {
    var session = TypingSession(configuration: .words(3), prompt: "aa bb cc")
    session.insertBatch("aa bb", at: start)
    for rtl in [false, true] {
      XCTAssertFalse(try rejects(session, candidate: "bbx", rtl: rtl))
      XCTAssertTrue(try rejects(session, candidate: "bbxxxx", rtl: rtl))
    }
    var arabic = TypingSession(configuration: .words(2, language: .arabic), prompt: "سلام عالم")
    arabic.insertBatch("سلام", at: start)
    var extended = arabic; extended.insert("x", at: start)
    let first = PromptFieldTextLayout(map: try XCTUnwrap(rendering(arabic).compositionTextMap), width: width(30), font: font, rightToLeft: true, joinsLetters: true)
    let next = PromptFieldTextLayout(map: try XCTUnwrap(rendering(extended).compositionTextMap), width: width(30), font: font, rightToLeft: true, joinsLetters: true)
    XCTAssertGreaterThan(try XCTUnwrap(next.fieldFrames[0]).height, try XCTUnwrap(first.fieldFrames[0]).height)
    XCTAssertTrue(try rejects(arabic, candidate: "سلامx", columns: 30, rtl: true, joins: true))
    XCTAssertFalse(try rejects(arabic, candidate: "سلامس", columns: 30, rtl: true, joins: true))
    XCTAssertTrue(try rejects(arabic, candidate: "سلامxxxxxx", columns: 3, rtl: true, joins: true))
  }

  func testInvalidWidthAndNoAdditionalUnitsDoNotInventARejection() throws {
    var session = TypingSession(configuration: .words(2), prompt: "aaaa tail")
    session.insertBatch("aaaa", at: start)
    let rendering = try rendering(session)
    for width: CGFloat in [0, -1, .nan, .infinity] {
      XCTAssertFalse(PromptInputWrapGeometry.rejects(session: session, candidate: Array("aaaax".utf16),
        rendering: rendering, width: width, font: font, lineSpacing: 12, isRightToLeft: false))
    }
    XCTAssertFalse(try rejects(session, candidate: "aaa", columns: 1))
    XCTAssertFalse(try rejects(session, candidate: "aaaa", columns: 1))
  }

  func testProductionAdmissionUsesEmptyCandidateAndTheRealJoiningPolicy() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let lower = try XCTUnwrap(source.range(of: "private var promptInputWrapAdmission:"))
    let upper = try XCTUnwrap(source.range(of: "private func playInputFeedback", range: lower.upperBound..<source.endIndex))
    let admission = source[lower.lowerBound..<upper.lowerBound]
    XCTAssertTrue(admission.contains("renderedPrompt(for: current, composition: \"\")"))
    XCTAssertTrue(admission.contains("joinsLetters: current.configuration.usesJoiningScriptPrompt"))
    XCTAssertFalse(admission.contains("compositionText"))
    XCTAssertFalse(admission.contains("composition: nil"))
  }

  func testProbeAgreesWithActuallyRenderedUnrestrictedInputCopiesAcrossNativeWidths() throws {
    let cases: [(String, String, String, String, Bool)] = [
      ("aa bb cc", "aa bb", "bb", "x", false),
      ("aa\nbb", "aax", "aax", "y", false),
      ("😀a tail", "😀a", "😀a", "x", false),
      ("e\u{301} tail", "e\u{301}", "e\u{301}", "\u{301}", false),
      ("سلام عالم", "سلام", "سلام", "س", true),
      ("سلام عالم", "سلام", "سلام", "x", true),
    ]
    for (prompt, accepted, active, extra, joins) in cases {
      var session = TypingSession(configuration: .words(3), prompt: prompt)
      session.insertBatch(accepted, at: start)
      let owner = try XCTUnwrap(session.promptCompositionField?.index)
      var unrestricted = session; unrestricted.insertBatch(extra, at: start.addingTimeInterval(1))
      XCTAssertNotEqual(unrestricted.typed, session.typed)
      let beforeMap = try XCTUnwrap(rendering(session).compositionTextMap)
      let afterMap = try XCTUnwrap(rendering(unrestricted).compositionTextMap)
      for rtl in [false, true] {
        for columns: CGFloat in [2.2, 3.2, 4.2, 5.2, 8.2, 30] {
          let before = PromptFieldTextLayout(map: beforeMap, width: width(columns), font: font,
            rightToLeft: rtl, joinsLetters: joins)
          let after = PromptFieldTextLayout(map: afterMap, width: width(columns), font: font,
            rightToLeft: rtl, joinsLetters: joins)
          let first = try XCTUnwrap(before.fieldFrames[owner]), last = try XCTUnwrap(after.fieldFrames[owner])
          XCTAssertEqual(try rejects(session, candidate: active + extra, columns: columns, rtl: rtl, joins: joins),
            last.minY > first.minY || last.height > first.height,
            "\(prompt.debugDescription) + \(extra.debugDescription), width \(columns), RTL \(rtl)")
        }
      }
    }
  }
}
