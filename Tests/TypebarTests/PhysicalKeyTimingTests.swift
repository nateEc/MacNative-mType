import XCTest
@testable import Typebar

final class PhysicalKeyTimingTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  private func press(_ code: UInt16, _ offset: Double, in session: inout TypingSession,
                     repeat isRepeat: Bool = false) {
    session.recordPhysicalKeyEvent(keyCode: code, isKeyDown: true, isRepeat: isRepeat,
                                   at: start.addingTimeInterval(offset))
  }

  private func release(_ code: UInt16, _ offset: Double, in session: inout TypingSession) {
    session.recordPhysicalKeyEvent(keyCode: code, isKeyDown: false, isRepeat: false,
                                   at: start.addingTimeInterval(offset))
  }

  private func finish(_ session: inout TypingSession) throws -> CompletedTestResult {
    session.tick(at: start.addingTimeInterval(1))
    return try XCTUnwrap(session.result(at: start.addingTimeInterval(1)))
  }

  private func assertSamples(_ actual: [Double], _ expected: [Double],
                             file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    for (actual, expected) in zip(actual, expected) {
      XCTAssertEqual(actual, expected, accuracy: 0.000_001, file: file, line: line)
    }
  }

  func testHoldSamplesStayInPressOrderWhenReleaseOrderDiffers() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    press(0, 0, in: &session)
    session.insert("a", at: start)
    press(1, 0.1, in: &session)
    release(1, 0.2, in: &session)
    release(0, 0.3, in: &session)
    let result = try finish(&session)
    assertSamples(result.keyDurationSamples, [0.3, 0.1])
    XCTAssertEqual(result.keyOverlapDuration, 0.1, accuracy: 0.000_001)
  }

  func testHeldKeysUsePositiveCompletedMeanIncludingTheirOverlap() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    press(0, 0, in: &session)
    session.insert("a", at: start)
    release(0, 0.1, in: &session)
    press(1, 0.2, in: &session)
    release(1, 0.4, in: &session)
    press(2, 0.8, in: &session)
    press(3, 0.9, in: &session)
    let result = try finish(&session)
    assertSamples(result.keyDurationSamples, [0.1, 0.2, 0.15, 0.15])
    XCTAssertEqual(result.keyOverlapDuration, 0.05, accuracy: 0.000_001)
    let stats = try XCTUnwrap(result.keyDurationStats)
    XCTAssertEqual(stats.sampleCount, 4)
    XCTAssertEqual(stats.averageMilliseconds, 150, accuracy: 0.000_001)
    XCTAssertEqual(stats.standardDeviationMilliseconds, sqrt(1_250), accuracy: 0.000_001)
  }

  func testFinalWordKeyStillHeldUsesDefaultEightyMilliseconds() throws {
    var session = TypingSession(configuration: .words(1), prompt: "a")
    press(0, 0, in: &session)
    session.insert("a", at: start)
    assertSamples(try XCTUnwrap(session.result(at: start)).keyDurationSamples, [0.08])
  }

  func testZeroDurationRemainsASampleButDoesNotReduceTheEstimate() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    press(0, 0, in: &session)
    session.insert("a", at: start)
    release(0, 0, in: &session)
    press(1, 0.9, in: &session)
    assertSamples(try finish(&session).keyDurationSamples, [0, 0.08])
  }

  func testReusedKeyEstimateMatchesLatestDownAndFirstReleaseBoundary() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    press(0, 0, in: &session)
    session.insert("a", at: start)
    release(0, 0.1, in: &session)
    press(0, 0.2, in: &session)
    release(0, 0.5, in: &session)
    press(1, 0.9, in: &session)
    assertSamples(try finish(&session).keyDurationSamples, [0.1, 0.3, 0.08])
  }

  func testDuplicateNonRepeatDownClosesPreviousPressAndStartsAnother() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    press(0, 0, in: &session)
    session.insert("a", at: start)
    press(0, 0.1, in: &session)
    release(0, 0.3, in: &session)
    press(1, 0.9, in: &session)
    let result = try finish(&session)
    assertSamples(result.keyDurationSamples, [0.1, 0.2, 0.08])
    assertSamples(result.keySpacingSamples, [0.1, 0.8])
  }

  func testRepeatUnmatchedAndLateReleasesDoNotChangeTheSnapshot() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    press(0, 0, in: &session)
    session.insert("a", at: start)
    press(0, 0.03, in: &session, repeat: true)
    release(9, 0.04, in: &session)
    release(0, 0.1, in: &session)
    press(1, 0.9, in: &session)
    let result = try finish(&session)
    assertSamples(result.keyDurationSamples, [0.1, 0.1])
    release(1, 1.2, in: &session)
    press(2, 1.3, in: &session)
    let later = try XCTUnwrap(session.result(at: start.addingTimeInterval(5)))
    XCTAssertEqual(later.keyDurationSamples, result.keyDurationSamples)
    XCTAssertEqual(later.keySpacingSamples, result.keySpacingSamples)
    XCTAssertEqual(later.keyOverlapDuration, result.keyOverlapDuration)
  }

  func testOnlyLastPreStartPressSurvivesAndSpacingClampsItToStart() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    press(0, -0.5, in: &session)
    release(0, -0.4, in: &session)
    press(1, -0.1, in: &session)
    session.insert("a", at: start)
    release(1, 0.1, in: &session)
    press(2, 0.2, in: &session)
    release(2, 0.3, in: &session)
    let result = try finish(&session)
    assertSamples(result.keyDurationSamples, [0.2, 0.1])
    assertSamples(result.keySpacingSamples, [0.2])
  }

  func testEstimatedDurationHasHundredthMillisecondResolution() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    press(0, 0, in: &session)
    session.insert("a", at: start)
    release(0, 0.100_12, in: &session)
    press(1, 0.2, in: &session)
    release(1, 0.300_14, in: &session)
    press(2, 0.9, in: &session)
    assertSamples(try finish(&session).keyDurationSamples, [0.100_12, 0.100_14, 0.100_13])
  }

  func testThreeHeldKeysCountTheOverlapUnionNotPairwiseSums() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    session.insert("a", at: start)
    press(0, 0.9, in: &session)
    press(1, 0.92, in: &session)
    press(2, 0.94, in: &session)
    let result = try finish(&session)
    assertSamples(result.keyDurationSamples, [0.08, 0.08, 0.08])
    XCTAssertEqual(result.keyOverlapDuration, 0.08, accuracy: 0.000_001)
  }

  func testResultRoundTripKeepsEstimatedSamplesInPressOrder() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    press(0, 0, in: &session)
    session.insert("a", at: start)
    press(1, 0.1, in: &session)
    release(1, 0.2, in: &session)
    release(0, 0.3, in: &session)
    press(2, 0.9, in: &session)
    let result = try finish(&session)
    let decoded = try JSONDecoder().decode(CompletedTestResult.self,
                                         from: JSONEncoder().encode(result))
    assertSamples(decoded.keyDurationSamples, [0.3, 0.1, 0.2])
    XCTAssertEqual(decoded.keyDurationSamples, result.keyDurationSamples)
    XCTAssertEqual(decoded.keySpacingSamples, result.keySpacingSamples)
    XCTAssertEqual(decoded.keyOverlapDuration, result.keyOverlapDuration)
  }

  func testAnonymousRemoteEvidenceIncludesEstimateWithoutPhysicalCodesOrText() throws {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    press(0, 0, in: &session)
    session.insert("a", at: start)
    release(0, 0.1, in: &session)
    press(1, 0.9, in: &session)
    let evidence = try XCTUnwrap(RemoteResultTimingEvidence(result: finish(&session)))
    XCTAssertEqual(evidence.keyDurationMilliseconds, [100, 100])
    XCTAssertEqual(evidence.keySpacingMilliseconds, [900])
    let json = try XCTUnwrap(String(data: JSONEncoder().encode(evidence), encoding: .utf8))
    XCTAssertFalse(json.contains("keyCode"))
    XCTAssertFalse(json.contains("amber"))
    XCTAssertFalse(json.contains("replay"))
  }

  func testFailedAndBailedOutResultsUseTheSameTerminalTimingProjection() throws {
    for bailOut in [false, true] {
      var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber")
      press(0, 0, in: &session)
      session.insert("a", at: start)
      if bailOut {
        session.bailOut(at: start.addingTimeInterval(1))
      } else {
        session.failForTimerHealth(at: start.addingTimeInterval(1))
      }
      let result = try XCTUnwrap(session.result(at: start.addingTimeInterval(1)))
      assertSamples(result.keyDurationSamples, [0.08])
      XCTAssertEqual(result.outcome, bailOut ? .bailedOut : .failed)
      XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: result.outcome, enabled: true))
    }
  }
}
