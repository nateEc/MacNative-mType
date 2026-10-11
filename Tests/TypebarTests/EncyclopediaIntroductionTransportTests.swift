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

  func testEmptyIntroductionDoesNotReuseTheSummary() async throws {
    try await withSession { session in
      IntroductionProtocol.fixture.set([
        (200, #"{"pageid":724,"title":"Owned","extract":"Short preview"}"#),
        (200, #"{"query":{"pages":{"724":{"extract":" \n\t "}}}}"#)
      ])
      let content = await LivePracticeContentService.fetch(source: .encyclopedia, language: .english, session: session)
      XCTAssertNil(content)
      XCTAssertEqual(IntroductionProtocol.fixture.requests.count, 2)
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
}

private final class IntroductionProtocol: URLProtocol, @unchecked Sendable {
  final class Fixture: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Int, String)] = []
    private var captured: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { captured } }
    func set(_ responses: [(Int, String)]) {
      lock.withLock { self.responses = responses; captured = [] }
    }
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
    guard let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
    else { return }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
