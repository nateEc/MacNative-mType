import XCTest
@testable import Typebar

@MainActor final class LiveWholePreviewBudgetTests: XCTestCase {
  @MainActor private final class CancellationRequest {
    var cancel: (() -> Void)?
  }

  func testImmediateCachedSectionsAllowQueuedCancellationBeforePublishing() async {
    await checkQueuedCancellation(limit: 1001)
  }

  func testQueuedCancellationAfterFinalCachedSectionDoesNotPublish() async {
    await checkQueuedCancellation(limit: 2)
  }

  private func checkQueuedCancellation(limit: Int) async {
    let request = CancellationRequest()
    var fetches = 0
    let task = Task { @MainActor in
      await LivePracticeContent(source: .encyclopedia, title: "First", byline: nil,
        tokens: ["harbor"], separator: " ")
        .fillingInitialPrompt(for: .words(limit), showAllLines: true) {
          fetches += 1
          if fetches == 1 { Task { @MainActor in request.cancel?() } }
          return LivePracticeContent(source: .encyclopedia, title: "Cached", byline: nil,
            tokens: ["next"], separator: " ")
        }
    }
    request.cancel = { task.cancel() }
    let result = await task.value
    request.cancel = nil
    XCTAssertTrue(result == nil, "Queued cancellation must run before a cached fill publishes")
    XCTAssertLessThan(fetches, max(2, limit - 1), "Immediate async responses must not monopolize the actor")
  }

  func testAboveSynchronousCeilingFetchesFullInitialBudgetAndRetainsOversupply() async throws {
    for source: LivePracticeContentSource in [.poetry, .encyclopedia] {
      let configuration = TestConfiguration.words(100_001)
        .with(modifiers: [source == .poetry ? .poetryStream : .referenceStream])
      let first = LivePracticeContent(source: source, title: "First", byline: nil,
        tokens: Array(repeating: "start", count: 100), separator: " ")
      var fetches = 0
      let result = await first.fillingInitialPrompt(for: configuration, showAllLines: true) {
        fetches += 1
        return LivePracticeContent(source: source, title: "Next", byline: nil,
          tokens: Array(repeating: "harbor", count: 99_902), separator: " ")
      }
      let filled = try XCTUnwrap(result)
      XCTAssertEqual(fetches, 1)
      XCTAssertEqual(filled.text.split(separator: " ").count, 100_002)
      let prompt = filled.promptDescriptor(for: configuration, showAllLines: true)
      XCTAssertEqual(prompt.text.split(separator: " ").count, 100_001)
      XCTAssertTrue(filled.continuationDescriptor(for: configuration, showAllLines: true) == nil)
      let session = TestSessionFactory.make(configuration: configuration, streamPrompt: prompt.text,
        streamsLiveContent: true, showAllLines: true)
      XCTAssertTrue(session.prompt == prompt.text)
      XCTAssertTrue(session.generationNotice == nil,
        "A complete external preview must not report synchronous generation truncation")
      let expanded = TestConfiguration.words(100_002).with(modifiers: configuration.modifiers)
      let retained = await filled.fillingInitialPrompt(for: expanded, showAllLines: true) {
        XCTFail("Retained tail must satisfy the expanded budget"); return nil
      }
      XCTAssertTrue(retained?.promptDescriptor(for: expanded, showAllLines: true).text == filled.text)
    }
  }

  func testHugeLivePreviewCancellationDoesNotPublishFetchedPartialContent() async {
    let configuration = TestConfiguration.words(OfficialTestLimitInput.maximumValue)
      .with(modifiers: [.referenceStream])
    var fetches = 0
    let task = Task { @MainActor in
      await LivePracticeContent(source: .encyclopedia, title: "First", byline: nil,
        tokens: Array(repeating: "harbor", count: 100), separator: " ")
        .fillingInitialPrompt(for: configuration, showAllLines: true) {
          fetches += 1
          withUnsafeCurrentTask { $0?.cancel() }
          return LivePracticeContent(source: .encyclopedia, title: "Next", byline: nil,
            tokens: ["late"], separator: " ")
        }
    }
    let result = await task.value
    XCTAssertTrue(result == nil)
    XCTAssertEqual(fetches, 1)
  }

  func testWholePreviewPreservesTimedInfiniteAndVisibleOverrideBudgets() {
    let content = LivePracticeContent(source: .encyclopedia, title: "Owned", byline: nil,
      tokens: Array(repeating: "harbor", count: 201), separator: " ")
    for configuration in [TestConfiguration.words(0), .timed(seconds: 30),
      .words(100_001).with(modifiers: [.focusNextWord])] {
      XCTAssertEqual(content.promptDescriptor(for: configuration, showAllLines: true).text.split(separator: " ").count,
        GeneratedPromptChunkPolicy.wordCount(for: configuration, showAllLines: true))
    }
  }
}
