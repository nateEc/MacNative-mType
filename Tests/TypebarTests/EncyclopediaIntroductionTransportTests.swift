import Foundation
import XCTest
@testable import Typebar

final class EncyclopediaIntroductionTransportTests: XCTestCase {
  private func withSession(_ body: (URLSession) async throws -> Void) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [IntroductionProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel(); IntroductionProtocol.fixture.reset() }
    try await body(session)
  }

  func testRandomPageIdentityLoadsItsFullIntroductionInsteadOfSummary() async throws {
    try await withSession { session in
      IntroductionProtocol.fixture.set([
        (200, #"{"pageid":724,"title":"Owned harbor","author":"Owned writer","extract":"Short preview"}"#),
        (200, #"{"query":{"pages":{"725":{"extract":"Wrong page"},"724":{"extract":"Long independent introduction\nwith another paragraph"}}}}"#)
      ])
      let content = await LivePracticeContentService.fetch(source: .encyclopedia, language: .german, session: session)
      XCTAssertEqual(content?.text, "Long independent introduction with another paragraph")
      XCTAssertEqual(content?.title, "Owned harbor")
      XCTAssertEqual(content?.byline, "Owned writer")
      let requests = IntroductionProtocol.fixture.requests
      XCTAssertEqual(requests.count, 2)
      guard requests.count == 2 else { return }
      XCTAssertEqual(requests[0].url?.host, "de.wikipedia.org")
      XCTAssertEqual(requests[0].url?.path, "/api/rest_v1/page/random/summary")
      XCTAssertEqual(requests[1].url?.host, "de.wikipedia.org")
      XCTAssertEqual(requests[1].url?.path, "/w/api.php")
      let items = try XCTUnwrap(URLComponents(url: try XCTUnwrap(requests[1].url), resolvingAgainstBaseURL: false)?.queryItems)
      let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
      XCTAssertEqual(query["action"], "query")
      XCTAssertEqual(query["prop"], "extracts")
      XCTAssertEqual(query["pageids"], "724")
      XCTAssertEqual(query["exintro"], "true")
      XCTAssertEqual(query["explaintext"], "true")
      XCTAssertNil(query["exchars"])
      XCTAssertNil(query["exsentences"])
      for request in requests {
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.timeoutInterval, 8)
        XCTAssertNil(request.httpBody)
      }
    }
  }

  func testMissingPageOrFailedIntroductionNeverFallsBackToShortSummary() async throws {
    try await withSession { session in
      for response in [(200, #"{"query":{"pages":{"725":{"extract":"Wrong page"}}}}"#), (503, "{}"), (200, "{}")] {
        IntroductionProtocol.fixture.set([
          (200, #"{"pageid":724,"title":"Owned","extract":"Short preview"}"#), response
        ])
        let content = await LivePracticeContentService.fetch(source: .encyclopedia, language: .english, session: session)
        XCTAssertNil(content)
        XCTAssertEqual(IntroductionProtocol.fixture.requests.count, 2)
      }
    }
  }

  func testInvalidRandomIdentityDoesNotIssueAnIntroductionRequest() async throws {
    try await withSession { session in
      for payload in ["{}", #"{"pageid":-1,"title":"Owned","extract":"Short preview"}"#, #"{"title":"Owned","extract":"Short preview"}"#] {
        IntroductionProtocol.fixture.set([(200, payload)])
        let content = await LivePracticeContentService.fetch(source: .encyclopedia, language: .english, session: session)
        XCTAssertNil(content)
        XCTAssertEqual(IntroductionProtocol.fixture.requests.count, 1)
      }
    }
  }

  func testFailedRandomRequestStopsBeforeIntroduction() async throws {
    try await withSession { session in
      IntroductionProtocol.fixture.set([(503, #"{"pageid":724,"title":"Owned","extract":"Short preview"}"#)])
      let content = await LivePracticeContentService.fetch(source: .encyclopedia, language: .english, session: session)
      XCTAssertNil(content)
      XCTAssertEqual(IntroductionProtocol.fixture.requests.count, 1)
    }
  }

  func testIntroductionPreservesNumbersAndPunctuationWhileCleaningReferenceMarkers() async throws {
    try await withSession { session in
      for (language, text, expected) in [
        (TypingLanguage.english, "“North”—2026… [12] café\u{200B}!", "\"North\"-2026... caf!"),
        (.german, "Über 12, ‘Boote’\u{FEFF} [3] am\u{00A0}Ufer.", "Über 12, 'Boote' am Ufer.")
      ] {
        let response = try JSONSerialization.data(withJSONObject: [
          "query": ["pages": ["724": ["extract": text]]]
        ])
        IntroductionProtocol.fixture.set([
          (200, #"{"pageid":724,"title":"Owned"}"#),
          (200, String(decoding: response, as: UTF8.self))
        ])
        let content = await LivePracticeContentService.fetch(source: .encyclopedia, language: language, session: session)
        XCTAssertEqual(content?.text, expected)
        let loaded = try XCTUnwrap(content)
        let configuration = TestConfiguration.words(
          expected.split(separator: " ").count, language: language).with(modifiers: [.referenceStream])
        let descriptor = loaded.promptDescriptor(for: configuration, showAllLines: true)
        var practice = TestSessionFactory.make(configuration: configuration,
          streamPrompt: descriptor.text, streamNoSpaceBoundarySource: descriptor.noSpaceBoundarySource,
          showAllLines: true)
        XCTAssertEqual(practice.prompt, expected)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        practice.insertBatch(expected, at: now)
        XCTAssertEqual(practice.outcome, .completed)
        XCTAssertEqual(practice.completedWordCount, configuration.wordLimit)
        XCTAssertEqual(practice.errors, 0)
        let result = try XCTUnwrap(practice.result(at: now))
        XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
          through: result.elapsedDuration), expected)
      }
    }
  }

  func testEmptyIntroductionRequestsAnotherRandomPage() async throws {
    try await withSession { session in
      IntroductionProtocol.fixture.set([
        (200, #"{"pageid":724,"title":"Empty","extract":"Do not reuse"}"#),
        (200, #"{"query":{"pages":{"724":{"extract":"[12] \n\t"}}}}"#),
        (200, #"{"pageid":812,"title":"Second independent page"}"#),
        (200, #"{"query":{"pages":{"812":{"extract":"Fresh introduction 42."}}}}"#)
      ])
      let content = await LivePracticeContentService.fetch(source: .encyclopedia, language: .english, session: session)
      XCTAssertEqual(content?.text, "Fresh introduction 42.")
      XCTAssertEqual(content?.title, "Second independent page")
      XCTAssertEqual(IntroductionProtocol.fixture.requests.count, 4)
    }
  }

  @MainActor func testInitialPromptUsesFreshIntroductionsInsteadOfCyclingShortPage() async throws {
      let transportConfiguration = URLSessionConfiguration.ephemeral
      transportConfiguration.protocolClasses = [IntroductionProtocol.self]
      let session = URLSession(configuration: transportConfiguration)
      defer { session.invalidateAndCancel(); IntroductionProtocol.fixture.reset() }
      IntroductionProtocol.fixture.set([
        (200, #"{"pageid":724,"title":"First owned page"}"#),
        (200, #"{"query":{"pages":{"724":{"extract":"Amber harbor."}}}}"#),
        (200, #"{"pageid":812,"title":"Second owned page"}"#),
        (200, #"{"query":{"pages":{"812":{"extract":"Fresh boats arrive."}}}}"#)
      ])
      let first = await LivePracticeContentService.fetch(source: .encyclopedia, language: .english, session: session)
      let initial = try XCTUnwrap(first)
      let configuration = TestConfiguration.words(4).with(modifiers: [.referenceStream])
      let filled = await initial.fillingInitialPrompt(for: configuration, showAllLines: true) {
        await LivePracticeContentService.fetch(source: .encyclopedia, language: .english, session: session)
      }
      let loaded = try XCTUnwrap(filled)
      let descriptor = loaded.promptDescriptor(for: configuration, showAllLines: true)
      XCTAssertEqual(descriptor.text, "Amber harbor. Fresh boats")
      XCTAssertEqual(loaded.title, "First owned page / Second owned page")
      XCTAssertEqual(IntroductionProtocol.fixture.requests.count, 4)
      var practice = TestSessionFactory.make(configuration: configuration,
        streamPrompt: descriptor.text, showAllLines: true)
      let now = Date(timeIntervalSince1970: 1_700_000_000)
      practice.insertBatch(descriptor.text, at: now)
      XCTAssertEqual(practice.outcome, .completed)
      XCTAssertEqual(practice.completedWordCount, 4)
      XCTAssertEqual(practice.errors, 0)
  }

  @MainActor func testInitialPromptFillDoesNotCycleAfterFetchFailureOrCancellation() async throws {
    let first = LivePracticeContent(source: .encyclopedia, title: "Owned", byline: nil,
      tokens: ["Amber", "harbor."], separator: " ")
    let configuration = TestConfiguration.words(4).with(modifiers: [.referenceStream])
    var calls = 0
    let failed = await first.fillingInitialPrompt(for: configuration, showAllLines: true) {
      calls += 1
      return nil
    }
    XCTAssertNil(failed)
    XCTAssertEqual(calls, 1)
    let task = Task {
      await first.fillingInitialPrompt(for: configuration, showAllLines: true) {
        withUnsafeCurrentTask { $0?.cancel() }
        return LivePracticeContent(source: .encyclopedia, title: "Late", byline: nil,
          tokens: ["Must", "not", "apply"], separator: " ")
      }
    }
    let cancelled = await task.value
    XCTAssertNil(cancelled)
  }

  @MainActor func testFreshNoSpaceInitialSectionsKeepBoundariesAndReplay() async throws {
    let first = LivePracticeContent(source: .encyclopedia, title: "海港", byline: "甲",
      tokens: ["「海港」", "12艘"], separator: "")
    let configuration = TestConfiguration.words(4, language: .simplifiedChinese)
      .with(modifiers: [.referenceStream])
    let filled = await first.fillingInitialPrompt(for: configuration, showAllLines: true) {
      LivePracticeContent(source: .encyclopedia, title: "船舶", byline: "乙",
        tokens: ["船，", "天气好。", "多余"], separator: "")
    }
    let loaded = try XCTUnwrap(filled)
    XCTAssertEqual(loaded.byline, "甲 / 乙")
    let descriptor = loaded.promptDescriptor(for: configuration, showAllLines: true)
    XCTAssertEqual(descriptor.text, "「海港」12艘船，天气好。")
    XCTAssertEqual(descriptor.noSpaceBoundarySource, "「海港」 12艘 船， 天气好。")
    var practice = TestSessionFactory.make(configuration: configuration,
      streamPrompt: descriptor.text, streamNoSpaceBoundarySource: descriptor.noSpaceBoundarySource,
      showAllLines: true)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    practice.insertBatch(descriptor.text, at: now)
    XCTAssertEqual(practice.outcome, .completed)
    XCTAssertEqual(practice.completedWordCount, 4)
    XCTAssertEqual(practice.errors, 0)
    let result = try XCTUnwrap(practice.result(at: now))
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), descriptor.text)
    let alreadyFilled = await loaded.fillingInitialPrompt(for: configuration, showAllLines: true) {
      XCTFail("A complete initial word budget must not request another section")
      return nil
    }
    XCTAssertEqual(alreadyFilled, loaded)
  }

  @MainActor func testLargerPreviewConsumesRetainedSectionTailWithoutAnotherFetch() async throws {
    for (language, firstTokens, nextTokens, separator) in [
      (TypingLanguage.english, ["Amber"], ["harbor.", "Fresh", "boats"], " "),
      (.simplifiedChinese, ["「海港」"], ["12艘", "船，", "天气好。"], "")
    ] {
      let first = LivePracticeContent(source: .encyclopedia, title: "First", byline: nil,
        tokens: firstTokens, separator: separator)
      let short = TestConfiguration.words(2, language: language).with(modifiers: [.referenceStream])
      let initial = await first.fillingInitialPrompt(for: short, showAllLines: true) {
        LivePracticeContent(source: .encyclopedia, title: "Second", byline: nil,
          tokens: nextTokens, separator: separator)
      }
      let retained = try XCTUnwrap(initial)
      let allTokens = firstTokens + nextTokens
      XCTAssertEqual(retained.text, allTokens.joined(separator: separator))
      XCTAssertEqual(retained.promptDescriptor(for: short, showAllLines: true).text,
        allTokens.prefix(2).joined(separator: separator))
      let expandedConfiguration = TestConfiguration.words(4, language: language)
        .with(modifiers: [.referenceStream])
      var extraRequests = 0
      let expanded = await retained.fillingInitialPrompt(for: expandedConfiguration, showAllLines: true) {
        extraRequests += 1
        return nil
      }
      XCTAssertEqual(extraRequests, 0)
      let loaded = try XCTUnwrap(expanded)
      let descriptor = loaded.promptDescriptor(for: expandedConfiguration, showAllLines: true)
      XCTAssertEqual(descriptor.text, allTokens.joined(separator: separator))
      var practice = TestSessionFactory.make(configuration: expandedConfiguration,
        streamPrompt: descriptor.text, streamNoSpaceBoundarySource: descriptor.noSpaceBoundarySource,
        showAllLines: true)
      let now = Date(timeIntervalSince1970: 1_700_000_000)
      practice.insertBatch(descriptor.text, at: now)
      XCTAssertEqual(practice.outcome, .completed)
      XCTAssertEqual(practice.completedWordCount, 4)
      XCTAssertEqual(practice.errors, 0)
      let result = try XCTUnwrap(practice.result(at: now))
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), descriptor.text)
    }
  }

  func testEmptyIntroductionStopsWhenNextRandomRequestFails() async throws {
    try await withSession { session in
      IntroductionProtocol.fixture.set([
        (200, #"{"pageid":724,"title":"Owned","extract":"Short preview"}"#),
        (200, #"{"query":{"pages":{"724":{"extract":" \n\t "}}}}"#),
        (503, "{}")
      ])
      let content = await LivePracticeContentService.fetch(source: .encyclopedia, language: .english, session: session)
      XCTAssertNil(content)
      XCTAssertEqual(IntroductionProtocol.fixture.requests.count, 3)
    }
  }

  func testChineseIntroductionRetainsPunctuationAndDigitsAcrossNativeWordBoundaries() async throws {
    try await withSession { session in
      let expected = "「海港」有12艘船，天气好。"
      let response = try JSONSerialization.data(withJSONObject: [
        "query": ["pages": ["724": ["extract": expected]]]
      ])
      IntroductionProtocol.fixture.set([
        (200, #"{"pageid":724,"title":"原创海港"}"#),
        (200, String(decoding: response, as: UTF8.self))
      ])
      let fetched = await LivePracticeContentService.fetch(
        source: .encyclopedia, language: .simplifiedChinese, session: session)
      let content = try XCTUnwrap(fetched)
      XCTAssertEqual(content.text, expected)
      let preview = content.promptDescriptor(for: .init(mode: .custom, duration: nil,
        wordLimit: nil, difficulty: .normal, rules: .init(), language: .simplifiedChinese))
      let boundaries = try XCTUnwrap(preview.noSpaceBoundarySource)
      XCTAssertEqual(boundaries.replacingOccurrences(of: " ", with: ""), expected)
      let configuration = TestConfiguration.words(boundaries.split(separator: " ").count,
        language: .simplifiedChinese).with(modifiers: [.referenceStream])
      var practice = TestSessionFactory.make(configuration: configuration,
        streamPrompt: content.text, streamNoSpaceBoundarySource: boundaries, showAllLines: true)
      XCTAssertEqual(practice.prompt, expected)
      let now = Date(timeIntervalSince1970: 1_700_000_000)
      practice.insertBatch(expected, at: now)
      XCTAssertEqual(practice.outcome, .completed)
      XCTAssertEqual(practice.completedWordCount, configuration.wordLimit)
      XCTAssertEqual(practice.errors, 0)
      let result = try XCTUnwrap(practice.result(at: now))
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), expected)
    }
  }

  func testAlreadyCancelledTaskDoesNotStartEitherRequest() async throws {
    try await withSession { session in
      IntroductionProtocol.fixture.set([])
      let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await LivePracticeContentService.fetch(source: .encyclopedia, language: .english, session: session)
      }
      let content = await task.value
      XCTAssertNil(content)
      XCTAssertTrue(IntroductionProtocol.fixture.requests.isEmpty)
    }
  }

  func testCancellationDuringReplacementPageRequestStopsEmptyIntroductionRetry() async throws {
    try await withSession { session in
      let replacementStarted = expectation(description: "replacement page request started")
      IntroductionProtocol.fixture.set([
        (200, #"{"pageid":724,"title":"Empty"}"#),
        (200, #"{"query":{"pages":{"724":{"extract":""}}}}"#),
        (0, "")
      ], onHold: { replacementStarted.fulfill() })
      let task = Task {
        await LivePracticeContentService.fetch(source: .encyclopedia, language: .english, session: session)
      }
      await fulfillment(of: [replacementStarted], timeout: 2)
      task.cancel()
      let content = await task.value
      XCTAssertNil(content)
      XCTAssertEqual(IntroductionProtocol.fixture.requests.count, 3)
    }
  }
}

private final class IntroductionProtocol: URLProtocol, @unchecked Sendable {
  final class Fixture: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, String)] = []
    private var captured: [URLRequest] = []
    private var holdCallback: (@Sendable () -> Void)?
    var requests: [URLRequest] { lock.withLock { captured } }
    func set(_ responses: [(Int, String)], onHold: (@Sendable () -> Void)? = nil) {
      lock.withLock { self.responses = responses; captured = []; holdCallback = onHold }
    }
    func notifyHeldRequest() { lock.withLock { holdCallback }?() }
    func reset() { set([]) }
    func next(_ request: URLRequest) -> (Int, Data) {
      lock.withLock {
        captured.append(request)
        let response = responses.isEmpty ? (599, "{}") : responses.removeFirst()
        return (response.0, Data(response.1.utf8))
      }
    }
  }
  static let fixture = Fixture()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let (status, data) = Self.fixture.next(request)
    if status == 0 {
      Self.fixture.notifyHeldRequest()
      return
    }
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
    else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
