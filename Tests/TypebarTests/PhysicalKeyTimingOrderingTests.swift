import XCTest
@testable import Typebar

final class PhysicalKeyTimingOrderingTests: XCTestCase {
  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  private func result(_ events: [(UInt16, Bool, Double)]) throws -> CompletedTestResult {
    var session = TypingSession(configuration: .timed(seconds: 1), prompt: "amber")
    // Start the input clock independently so pre-start physical events can
    // exercise cleanup without changing typing or result eligibility.
    for (code, down, offset) in events where offset < 0 {
      session.recordPhysicalKeyEvent(keyCode: code, isKeyDown: down, isRepeat: false,
                                     at: start.addingTimeInterval(offset))
    }
    session.insert("a", at: start)
    for (code, down, offset) in events where offset >= 0 {
      session.recordPhysicalKeyEvent(keyCode: code, isKeyDown: down, isRepeat: false,
                                     at: start.addingTimeInterval(offset))
    }
    session.tick(at: start.addingTimeInterval(1))
    return try XCTUnwrap(session.result(at: start.addingTimeInterval(1)))
  }

  private func assertTimings(_ result: CompletedTestResult, holds: [Double], overlap: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(result.keyDurationSamples.count, holds.count, file: file, line: line)
    for (actual, expected) in zip(result.keyDurationSamples, holds) {
      XCTAssertEqual(actual, expected, accuracy: 0.000_001, file: file, line: line)
    }
    XCTAssertEqual(result.keyOverlapDuration, overlap, accuracy: 0.000_001,
                   file: file, line: line)
  }

  func testZeroTimeReleaseBeforeDownLeavesLogicalPresenceUntilAnotherRelease() throws {
    assertTimings(try result([(0, true, 0), (0, false, 0), (1, true, 0.9)]),
                  holds: [0, 0.08], overlap: 0.08)
  }

  func testTwoUnclosedLogicalKeysDoNotCountAnOpenOverlapAtTestEnd() throws {
    assertTimings(try result([
      (0, true, 0), (0, false, 0), (1, true, 0.1), (1, false, 0.1), (2, true, 0.9),
    ]), holds: [0, 0, 0.08], overlap: 0)
  }

  func testLaterSameTimeReleaseCanCloseAnEarlierPressOfTheSameCode() throws {
    let completed = try result([
      (0, true, 0), (0, false, 0), (0, true, 0.1), (0, false, 0.1), (1, true, 0.9),
    ])
    assertTimings(completed, holds: [0.1, 0, 0.08], overlap: 0.08)
    XCTAssertEqual(completed.keySpacingSamples.count, 2)
    XCTAssertEqual(completed.keySpacingSamples[0], 0.1, accuracy: 0.000_001)
    XCTAssertEqual(completed.keySpacingSamples[1], 0.8, accuracy: 0.000_001)
  }

  func testDistinctRawTimesThatQuantizeToTheSameTickUseReleaseFirst() throws {
    assertTimings(try result([(0, true, 0), (0, false, 0.000_003), (1, true, 0.9)]),
                  holds: [0, 0.08], overlap: 0.08)
  }

  func testDroppedPreStartReleaseStillLeavesTheLastPreStartDownInTheLog() throws {
    let completed = try result([
      (0, true, -0.1), (0, false, -0.05), (1, true, 0.2), (1, false, 0.3),
    ])
    assertTimings(completed, holds: [0, 0.1], overlap: 0.1)
    XCTAssertEqual(completed.keySpacingSamples.count, 1)
    XCTAssertEqual(completed.keySpacingSamples[0], 0.2, accuracy: 0.000_001)
  }

  func testLogicalPresenceExtendsAClosedThreeKeyOverlapWithoutPairwiseOvercounting() throws {
    assertTimings(try result([
      (0, true, 0), (0, false, 0), (1, true, 0.1), (2, true, 0.2),
      (1, false, 0.3), (2, false, 0.4),
    ]), holds: [0, 0.2, 0.2], overlap: 0.3)
  }

  func testLaterOrdinaryReleaseClearsLogicalPresenceBeforeTheNextKey() throws {
    assertTimings(try result([
      (0, true, 0), (0, false, 0), (0, true, 0.1), (0, false, 0.2),
      (1, true, 0.3), (1, false, 0.4),
    ]), holds: [0, 0.1, 0.1], overlap: 0)
  }

  func testReleaseBeforeDownAtOverlapHandoffCommitsOnlyTheClosedEpisode() throws {
    assertTimings(try result([
      (0, true, 0), (1, true, 0.1), (1, false, 0.1), (0, false, 0.3),
      (2, true, 0.3), (2, false, 0.3),
    ]), holds: [0.3, 0, 0], overlap: 0.2)
  }

  func testReassignedSamplesAndZeroSlotSurviveArchiveAndAnonymousEvidence() throws {
    let completed = try result([
      (0, true, 0), (0, false, 0), (0, true, 0.1), (0, false, 0.1), (1, true, 0.9),
    ])
    let decoded = try JSONDecoder().decode(CompletedTestResult.self,
                                          from: JSONEncoder().encode(completed))
    assertTimings(decoded, holds: [0.1, 0, 0.08], overlap: 0.08)
    XCTAssertEqual(decoded.keySpacingSamples, completed.keySpacingSamples)
    let evidence = try XCTUnwrap(RemoteResultTimingEvidence(result: decoded))
    XCTAssertEqual(evidence.keyDurationMilliseconds, [100, 0, 80])
    XCTAssertEqual(evidence.keySpacingMilliseconds, [100, 800])
    XCTAssertEqual(evidence.keyOverlapMilliseconds, 80)
  }
}
