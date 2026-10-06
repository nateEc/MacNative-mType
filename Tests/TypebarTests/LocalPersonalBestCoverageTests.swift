import XCTest
@testable import Typebar

final class LocalPersonalBestCoverageTests: XCTestCase {
  private func result(_ configuration: TestConfiguration, speed: Double = 60.25) -> CompletedTestResult {
    let start = Date(timeIntervalSince1970: 100)
    return .init(id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(20),
      typedCharacterCount: 100, correctCharacterCount: 99, errorCount: 1,
      wpm: 60, rawWpm: 65, accuracy: 99,
      preciseWpm: speed, preciseRawWpm: 65.5, preciseAccuracy: 99,
      tags: ["focus"], prompt: "owned fixture")
  }

  func testCustomAndZenHaveFixedBucketsInsteadOfBeingOmitted() {
    for mode in [TestMode.custom, .zen] {
      let short = TestConfiguration(mode: mode, duration: 15, wordLimit: 10,
        difficulty: .normal, rules: .init())
      let long = TestConfiguration(mode: mode, duration: 60, wordLimit: 50,
        difficulty: .normal, rules: .init())
      let winner = result(long, speed: 60.49)
      let rows = LocalPersonalBestTablePolicy.rows(results: [result(short), winner])
      XCTAssertEqual(rows.count, 1)
      XCTAssertEqual(rows.first?.id, winner.id)
      XCTAssertEqual(rows.first?.mode, mode)
    }
  }

  func testInfiniteTimeAndWordsKeepTheirZeroMode2Buckets() {
    for configuration in [TestConfiguration.timed(seconds: 0), .words(0)] {
      let candidate = result(configuration)
      let rows = LocalPersonalBestTablePolicy.rows(results: [candidate])
      XCTAssertEqual(rows.count, 1)
      XCTAssertEqual(rows.first?.id, candidate.id)
      XCTAssertEqual(rows.first?.parameter, 0)
    }
  }
}
