#if TYPEBAR_LIVE_NETWORK_QA
import Foundation
import XCTest
@testable import Typebar

/// Explicit public-network QA only; absent from normal/offline test builds.
@MainActor final class LiveContentNetworkAcceptanceTests: XCTestCase {
  func testPublicPoetryParsesIntoACompletableNativeAttempt() async throws {
    try await check(source: .poetry, language: .english)
  }

  func testPublicEnglishEncyclopediaParsesIntoACompletableNativeAttempt() async throws {
    try await check(source: .encyclopedia, language: .english)
  }

  func testPublicChineseEncyclopediaParsesIntoACompletableNativeAttempt() async throws {
    try await check(source: .encyclopedia, language: .simplifiedChinese)
  }

  func testPublicIndonesianOneThousandEncyclopediaParsesIntoACompletableNativeAttempt() async throws {
    try await check(source: .encyclopedia, language: .indonesian1k)
  }

  private func check(source: LivePracticeContentSource, language: TypingLanguage) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    let transport = URLSession(configuration: configuration)
    defer { transport.invalidateAndCancel() }
    let attempt = Task {
      let loaded = await LivePracticeContentService.fetch(source: source, language: language, session: transport)
      guard let loaded else { return Optional<LivePracticeContent>.none }
      let test = TestConfiguration.words(3, language: language)
      return await loaded.fillingInitialPrompt(for: test, showAllLines: true) {
        await LivePracticeContentService.fetch(source: source, language: language, session: transport)
      }
    }
    let deadline = Task {
      do { try await Task.sleep(for: .seconds(30)) } catch { return }
      attempt.cancel()
    }
    defer { deadline.cancel(); attempt.cancel() }
    let loaded = await attempt.value
    let content = try XCTUnwrap(loaded, "Public provider unavailable, invalid, or exceeded 30 seconds")
    XCTAssertEqual(content.source, source)
    XCTAssertFalse(content.text.isEmpty)
    let modifier: TestModifier = source == .poetry ? .poetryStream : .referenceStream
    let test = TestConfiguration.words(3, language: language).with(modifiers: [modifier])
    let descriptor = content.promptDescriptor(for: test, showAllLines: true)
    var practice = TestSessionFactory.make(configuration: test, streamPrompt: descriptor.text,
      streamNoSpaceBoundarySource: descriptor.noSpaceBoundarySource, showAllLines: true)
    let entered = practice.prompt
    let began = Date(timeIntervalSinceReferenceDate: 917_000_000)
    practice.insertBatch(String(entered.dropLast()), at: began)
    XCTAssertFalse(practice.isFinished)
    practice.insertBatch(String(entered.suffix(1)), at: began.addingTimeInterval(2))
    XCTAssertEqual(practice.outcome, .completed)
    XCTAssertEqual(practice.completedWordCount, 3)
    XCTAssertEqual(practice.errors, 0)
    let result = try XCTUnwrap(practice.result())
    // Compare without printing or retaining public provider text in QA logs.
    XCTAssertTrue(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration) == entered)
  }
}
#endif
