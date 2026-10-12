import Foundation
import XCTest
@testable import Typebar

/// Diagnostic scale evidence, not a machine-dependent latency acceptance gate.
@MainActor final class LiveSessionConstructionEvidenceTests: XCTestCase {
  func testRealFactoryPreservesLargeRetainedSourceAndConsumesItsFirstField() async throws {
    for tailCount in [1_001, 10_001, 100_001] {
      let initialCount = GeneratedPromptChunkPolicy.wordCount(for: .words(200_000), showAllLines: false)
      let configuration = TestConfiguration.words(initialCount + tailCount).with(modifiers: [.poetryStream])
      let content = LivePracticeContent(source: .poetry, title: "Owned scale fixture", byline: nil,
        tokens: Array(repeating: "start", count: initialCount)
          + (0..<tailCount).map { "owned\($0)" }, separator: " ")
      let prompt = try await content.preparingPromptDescriptor(for: configuration)
      let preparedContinuation = try await content.preparingContinuationDescriptor(for: configuration)
      let continuation = try XCTUnwrap(preparedContinuation)
      XCTAssertTrue(continuation.text.hasSuffix("owned\(tailCount - 1)"))
      let began = ProcessInfo.processInfo.systemUptime
      var session = TestSessionFactory.make(configuration: configuration,
        streamPrompt: prompt.text, streamContinuation: continuation, streamsLiveContent: true)
      let constructionSeconds = ProcessInfo.processInfo.systemUptime - began
      XCTAssertEqual(session.configuration.wordLimit, initialCount + tailCount)
      XCTAssertEqual(session.prompt.trimmingCharacters(in: .whitespacesAndNewlines), prompt.text)
      XCTAssertTrue(session.usesIncrementalPromptExtension)
      XCTAssertFalse(session.isFinished)
      let consumptionBegan = ProcessInfo.processInfo.systemUptime
      session.insertBatch("start ", at: Date(timeIntervalSince1970: 1_000))
      let consumptionSeconds = ProcessInfo.processInfo.systemUptime - consumptionBegan
      XCTAssertTrue(session.prompt.contains("owned0"), "The first retained field must be consumable")
      XCTAssertFalse(session.prompt.contains("owned\(tailCount - 1)"),
        "The bounded visible window must not eagerly append the whole tail")
      XCTAssertFalse(session.isFinished)
      print("TYPEBAR_QA_LIVE_FACTORY tail=\(tailCount) construction_seconds=\(constructionSeconds) first_input_seconds=\(consumptionSeconds)")
    }
  }
}
