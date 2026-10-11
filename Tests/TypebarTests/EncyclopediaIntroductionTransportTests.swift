import Foundation
import XCTest
@testable import Typebar

final class EncyclopediaIntroductionTransportTests: XCTestCase {
  func testIntroductionPreservesSourceMetadataWithoutTrimmingOrFallback() async throws {
    try await withSession { session in
      for (title, author) in [("  Harbor — \n", " Writer \t"), ("", ""), (" \t", " \n")] {
        let identity = try JSONSerialization.data(withJSONObject: [
          "pageid": 724, "title": title, "author": author
        ])
        IntroductionProtocol.fixture.set([
          (200, String(decoding: identity, as: UTF8.self)),
          (200, #"{"query":{"pages":{"724":{"extract":"<p>Owned harbor.</p>"}}}}"#)
        ])
        let fetched = await LivePracticeContentService.fetch(
          source: .encyclopedia, language: .english, session: session)
        let content = try XCTUnwrap(fetched)
        XCTAssertEqual(content.title, title)
        XCTAssertEqual(content.byline, author)
        XCTAssertEqual(content.text, "Owned harbor.")
        XCTAssertEqual(IntroductionProtocol.fixture.requests.count, 2)
      }
    }
  }

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
      XCTAssertNil(query["explaintext"])
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

  func testHTMLIntroductionUsesDecodedTextNodesAndReferenceCleaningOrder() async throws {
    try await withSession { session in
      let cases: [(TypingLanguage, String, String)] = [
        (.english, "<p>North <b>harbor</b>&nbsp;2026 [12]</p><p>South &amp; west &#x1F680;.</p>",
          "North harbor 2026 South & west ."),
        (.english, "<p>left\nright\tend</p><p>next&nbsp;word</p>", "leftrightend next word"),
        (.german, "<p>left\nright\tend</p><p>next&nbsp;word</p>", "left right end next word"),
        (.german, "<div>Über<br>12</div><div>&NotEqualTilde; ‘Boote’</div><!--ignored--><p>am</p><p>Ufer.</p>",
          "Über12≂̸ 'Boote'am Ufer."),
        (.english, "<img src='https://invalid.example/owned.png'>North<script>owned()</script><style>.x{}</style>tail",
          "Northowned().x{}tail"),
        (.english, "<p>One <b>two</p>three", "One twothree")
      ]
      for (language, html, expected) in cases {
        let response = try JSONSerialization.data(withJSONObject: [
          "query": ["pages": ["724": ["extract": html]]]
        ])
        IntroductionProtocol.fixture.set([
          (200, #"{"pageid":724,"title":"Owned"}"#),
          (200, String(decoding: response, as: UTF8.self))
        ])
        let content = await LivePracticeContentService.fetch(source: .encyclopedia,
          language: language, session: session)
        XCTAssertEqual(content?.text, expected, html)
        XCTAssertEqual(IntroductionProtocol.fixture.requests.count, 2,
          "HTML resources must never initiate requests")
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

  func testRetainedSectionTailContinuesActualSessionWithoutRepeatingInitialWords() throws {
    for (language, tokens, separator) in [
      (TypingLanguage.english, (0..<173).map { "owned\($0)" }, " "),
      (.simplifiedChinese, (0..<173).map { "港\($0)船" }, "")
    ] {
      let configuration = TestConfiguration.words(151, language: language)
        .with(modifiers: [.referenceStream])
      let content = LivePracticeContent(source: .encyclopedia, title: "Owned section", byline: nil,
        tokens: tokens, separator: separator)
      let preview = content.promptDescriptor(for: configuration)
      let tail = content.continuationDescriptor(for: configuration)
      XCTAssertNotNil(tail)
      var practice = TestSessionFactory.make(configuration: configuration,
        streamPrompt: preview.text, streamNoSpaceBoundarySource: preview.noSpaceBoundarySource,
        streamContinuation: tail)
      let now = Date(timeIntervalSince1970: 1_700_000_000)
      let expected = tokens.prefix(151).joined(separator: separator)
      let prefix = tokens.prefix(100).joined(separator: separator) + separator
      practice.insertBatch(prefix, at: now)
      XCTAssertEqual(practice.outcome, .active)
      XCTAssertEqual(practice.completedWordCount, 100)
      XCTAssertEqual(practice.prompt, expected)
      practice.insertBatch(tokens[100..<151].joined(separator: separator), at: now)
      XCTAssertEqual(practice.prompt, expected)
      XCTAssertEqual(practice.outcome, .completed)
      XCTAssertEqual(practice.completedWordCount, 151)
      XCTAssertEqual(practice.errors, 0)
      let result = try XCTUnwrap(practice.result(at: now))
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), expected)
      var repeated = practice.repeatedAttempt()
      repeated.insertBatch(expected, at: now)
      XCTAssertEqual(repeated.prompt, expected)
      XCTAssertEqual(repeated.outcome, .completed)
      XCTAssertEqual(repeated.errors, 0)
    }
  }

  func testInfiniteAndTimedSessionsConsumeRetainedTailBeforeRepeatingBuffer() throws {
    let tokens = (0..<373).map { "owned\($0)" }
    let content = LivePracticeContent(source: .encyclopedia, title: "Owned", byline: nil,
      tokens: tokens, separator: " ")
    for configuration in [TestConfiguration.words(0), .timed(seconds: 30)] {
      let configuration = configuration.with(modifiers: [.referenceStream])
      let preview = content.promptDescriptor(for: configuration)
      var practice = TestSessionFactory.make(configuration: configuration,
        streamPrompt: preview.text,
        streamContinuation: content.continuationDescriptor(for: configuration))
      XCTAssertEqual(practice.prompt.trimmingCharacters(in: .whitespaces), preview.text)
      practice.insertBatch(tokens.prefix(100).joined(separator: " ") + " ",
        at: Date(timeIntervalSince1970: 1_700_000_000))
      XCTAssertEqual(practice.prompt, tokens.joined(separator: " "))
      XCTAssertEqual(practice.completedWordCount, 100)
      XCTAssertEqual(practice.outcome, .active)
      XCTAssertEqual(practice.errors, 0)
    }
  }

  func testRetainedTailKeepsUnderscoreCommitsAtBatchBoundaryAndFiniteEnd() throws {
    let tokens = (0..<151).map { "owned\($0)" }
    let configuration = TestConfiguration.words(151)
      .with(modifiers: [.referenceStream, .underscoreSeparators])
    XCTAssertTrue(configuration.modifiers.contains(.underscoreSeparators))
    let content = LivePracticeContent(source: .encyclopedia, title: "Owned", byline: nil,
      tokens: tokens, separator: " ")
    let preview = content.promptDescriptor(for: configuration)
    var practice = TestSessionFactory.make(configuration: configuration,
      streamPrompt: preview.text, streamContinuation: content.continuationDescriptor(for: configuration))
    XCTAssertEqual(practice.prompt, tokens.prefix(100).joined(separator: "_") + "_")
    let expected = tokens.joined(separator: "_")
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    practice.insertBatch(expected, at: now)
    XCTAssertEqual(practice.prompt, expected)
    XCTAssertEqual(practice.outcome, .completed)
    XCTAssertEqual(practice.completedWordCount, 151)
    XCTAssertEqual(practice.errors, 0)
    let result = try XCTUnwrap(practice.result(at: now))
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
      through: result.elapsedDuration), expected)
    var repeated = practice.repeatedAttempt()
    repeated.insertBatch(expected, at: now)
    XCTAssertEqual(repeated.prompt, expected)
    XCTAssertEqual(repeated.outcome, .completed)
    XCTAssertEqual(repeated.errors, 0)
  }

  func testOpenEndedUnderscoreTailKeepsItsLastCommitForFutureContent() throws {
    let tokens = (0..<373).map { "owned\($0)" }
    let content = LivePracticeContent(source: .encyclopedia, title: "Owned", byline: nil,
      tokens: tokens, separator: " ")
    for configuration in [TestConfiguration.words(0), .timed(seconds: 30)] {
      let configuration = configuration.with(modifiers: [.referenceStream, .underscoreSeparators])
      let preview = content.promptDescriptor(for: configuration)
      var practice = TestSessionFactory.make(configuration: configuration,
        streamPrompt: preview.text, streamContinuation: content.continuationDescriptor(for: configuration))
      XCTAssertEqual(practice.prompt, tokens.prefix(100).joined(separator: "_") + "_")
      practice.insertBatch(tokens.prefix(100).joined(separator: "_") + "_",
        at: Date(timeIntervalSince1970: 1_700_000_000))
      XCTAssertEqual(practice.prompt, tokens.joined(separator: "_") + "_")
      XCTAssertEqual(practice.completedWordCount, 100)
      XCTAssertEqual(practice.outcome, .active)
      XCTAssertEqual(practice.errors, 0)
    }
  }

  func testNewLiveSectionPrecedesRetainedTailWithoutResettingInputOrReplay() throws {
    for (language, tokens, separator) in [
      (TypingLanguage.english, (0..<190).map { "owned\($0)" }, " "),
      (.simplifiedChinese, (0..<190).map { "港\($0)船" }, "")
    ] {
      let configuration = TestConfiguration.words(175, language: language)
        .with(modifiers: [.referenceStream])
      let content = LivePracticeContent(source: .encyclopedia, title: "Owned", byline: nil,
        tokens: Array(tokens.prefix(151)), separator: separator)
      let preview = content.promptDescriptor(for: configuration)
      var practice = TestSessionFactory.make(configuration: configuration,
        streamPrompt: preview.text, streamNoSpaceBoundarySource: preview.noSpaceBoundarySource,
        streamContinuation: content.continuationDescriptor(for: configuration), streamsLiveContent: true)
      let now = Date(timeIntervalSince1970: 1_700_000_000)
      practice.insertBatch(tokens.prefix(10).joined(separator: separator) + separator, at: now)
      let started = practice.startedAt
      let beforeRejectedAppend = practice.prompt
      XCTAssertFalse(practice.appendLiveContent(.init(text: " ", noSpaceBoundarySource: nil)))
      XCTAssertFalse(practice.appendLiveContent(.init(text: "mismatch", noSpaceBoundarySource: "other words")))
      XCTAssertEqual(practice.prompt, beforeRejectedAppend)
      XCTAssertEqual(practice.completedWordCount, 10)
      let extra = tokens[151..<190]
      XCTAssertTrue(practice.appendLiveContent(.init(text: extra.joined(separator: separator),
        noSpaceBoundarySource: separator.isEmpty ? extra.joined(separator: " ") : nil)))
      XCTAssertEqual(practice.startedAt, started)
      XCTAssertEqual(practice.completedWordCount, 10)
      let expectedWords = Array(tokens.prefix(110)) + Array(extra) + Array(tokens[110..<136])
      let expected = expectedWords.joined(separator: separator)
      XCTAssertEqual(practice.prompt, expectedWords.prefix(150).joined(separator: separator) + separator)
      practice.insertBatch(expectedWords.dropFirst(10).joined(separator: separator), at: now)
      XCTAssertEqual(practice.outcome, .completed)
      XCTAssertEqual(practice.errors, 0)
      XCTAssertEqual(practice.completedWordCount, 175)
      XCTAssertFalse(practice.appendLiveContent(.init(text: "must not append", noSpaceBoundarySource: nil)))
      XCTAssertEqual(practice.prompt, expected)
      let result = try XCTUnwrap(practice.result(at: now))
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), expected)
      var repeated = practice.repeatedAttempt()
      repeated.insertBatch(tokens.prefix(136).joined(separator: separator) + separator, at: now)
      XCTAssertTrue(repeated.needsLiveContentGeneration)
      XCTAssertTrue(repeated.acceptGeneratedLiveContent(.init(text: extra.joined(separator: separator),
        noSpaceBoundarySource: separator.isEmpty ? extra.joined(separator: " ") : nil)))
      repeated.insertBatch(extra.joined(separator: separator), at: now)
      XCTAssertEqual(repeated.prompt, (Array(tokens.prefix(136)) + Array(extra)).joined(separator: separator))
      XCTAssertNotEqual(repeated.prompt, expected, "Direct side fields are not inserted into generator replay history")
      XCTAssertEqual(repeated.outcome, .completed)
      XCTAssertEqual(repeated.errors, 0)
    }
  }

  func testLivePrefetchThresholdCountsPublishedFieldsRatherThanPendingTail() throws {
    for (language, tokens, separator) in [
      (TypingLanguage.english, (0..<300).map { "owned\($0)" }, " "),
      (.simplifiedChinese, (0..<300).map { "港\($0)船" }, "")
    ] {
      let configuration = TestConfiguration.words(300, language: language)
        .with(modifiers: [.referenceStream])
      let content = LivePracticeContent(source: .encyclopedia, title: "Owned", byline: nil,
        tokens: Array(tokens.prefix(151)), separator: separator)
      let preview = content.promptDescriptor(for: configuration)
      var practice = TestSessionFactory.make(configuration: configuration,
        streamPrompt: preview.text, streamNoSpaceBoundarySource: preview.noSpaceBoundarySource,
        streamContinuation: content.continuationDescriptor(for: configuration))
      let now = Date(timeIntervalSince1970: 1_700_000_000)
      XCTAssertFalse(practice.needsLiveContentPrefetch)
      practice.insertBatch(tokens.prefix(81).joined(separator: separator) + separator, at: now)
      XCTAssertTrue(practice.needsLiveContentPrefetch, "A queued tail does not suppress the published nineteen-field side threshold")
      practice.insertBatch(tokens[81..<131].joined(separator: separator) + separator, at: now)
      XCTAssertEqual(practice.completedWordCount, 131)
      XCTAssertFalse(practice.needsLiveContentPrefetch, "Exactly 20 remaining words does not trigger")
      practice.insertBatch(tokens[131] + separator, at: now)
      XCTAssertEqual(practice.completedWordCount, 132)
      XCTAssertTrue(practice.needsLiveContentPrefetch, "19 remaining words requests the next section")
      let rest = tokens[151..<300]
      XCTAssertTrue(practice.appendLiveContent(.init(text: rest.joined(separator: separator),
        noSpaceBoundarySource: separator.isEmpty ? rest.joined(separator: " ") : nil)))
      XCTAssertFalse(practice.needsLiveContentPrefetch, "The complete finite budget is now loaded")
      practice.insertBatch(tokens[132..<300].joined(separator: separator), at: now)
      XCTAssertEqual(practice.outcome, .completed)
      XCTAssertFalse(practice.needsLiveContentPrefetch)
    }
    XCTAssertFalse(TestSessionFactory.make(configuration: .words(300)).needsLiveContentPrefetch)
  }

  func testOpenEndedPrefetchThresholdKeepsSourceWordCountsWithHiddenSeparators() throws {
    let tokens = (0..<151).map { "owned\($0)" }
    let content = LivePracticeContent(source: .encyclopedia, title: "Owned", byline: nil,
      tokens: tokens, separator: " ")
    for base in [TestConfiguration.words(0), .timed(seconds: 30)] {
      for (alterations, commit) in [([TestModifier](), " "), ([.noSpaces], ""), ([.underscoreSeparators], "_")] {
        let configuration = base.with(modifiers: [.referenceStream] + alterations)
        XCTAssertEqual(configuration.modifiers.contains(.referenceStream), !configuration.isInfinite)
        XCTAssertEqual(LivePracticeContentSource.selected(for: configuration) != nil, !configuration.isInfinite)
        let preview = content.promptDescriptor(for: configuration)
        var practice = TestSessionFactory.make(configuration: configuration,
          streamPrompt: preview.text, streamContinuation: content.continuationDescriptor(for: configuration))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        practice.insertBatch(tokens.prefix(131).joined(separator: commit) + commit, at: now)
        XCTAssertEqual(practice.completedWordCount, 131)
        XCTAssertFalse(practice.needsLiveContentPrefetch)
        practice.insertBatch(tokens[131] + commit, at: now)
        XCTAssertEqual(practice.completedWordCount, 132)
        XCTAssertEqual(practice.errors, 0)
        XCTAssertEqual(practice.needsLiveContentPrefetch, !configuration.isInfinite,
          "Timed sources prefetch at 19; incompatible infinite configurations must not fetch")
      }
    }
  }

  func testLiveBufferExhaustionWaitsWithoutRepeatingOrScoringBlindInput() throws {
    for (language, tokens, separator) in [
      (TypingLanguage.english, (0..<125).map { "owned\($0)" }, " "),
      (.simplifiedChinese, (0..<125).map { "港\($0)船" }, "")
    ] {
      let configuration = TestConfiguration.words(125, language: language)
        .with(modifiers: [.referenceStream])
      let content = LivePracticeContent(source: .encyclopedia, title: "Owned", byline: nil,
        tokens: Array(tokens.prefix(100)), separator: separator)
      let preview = content.promptDescriptor(for: configuration)
      var practice = TestSessionFactory.make(configuration: configuration,
        streamPrompt: preview.text, streamNoSpaceBoundarySource: preview.noSpaceBoundarySource,
        streamsLiveContent: true)
      let now = Date(timeIntervalSince1970: 1_700_000_000)
      practice.insertBatch(tokens.prefix(100).joined(separator: separator) + separator, at: now)
      XCTAssertTrue(practice.isWaitingForLiveContent)
      XCTAssertEqual(practice.prompt, preview.text + separator)
      XCTAssertEqual(practice.outcome, .active)
      XCTAssertEqual(practice.completedWordCount, 100)
      let typed = practice.typed
      let errors = practice.errors
      let started = practice.startedAt
      practice.insertBatch("blind input", at: now)
      XCTAssertEqual(practice.typed, typed)
      XCTAssertEqual(practice.errors, errors)
      let rest = tokens[100..<125]
      XCTAssertTrue(practice.appendLiveContent(.init(text: rest.joined(separator: separator),
        noSpaceBoundarySource: separator.isEmpty ? rest.joined(separator: " ") : nil)))
      XCTAssertFalse(practice.isWaitingForLiveContent)
      XCTAssertEqual(practice.startedAt, started)
      practice.insertBatch(rest.joined(separator: separator), at: now)
      XCTAssertEqual(practice.outcome, .completed)
      XCTAssertEqual(practice.completedWordCount, 125)
      XCTAssertEqual(practice.errors, 0)
      let result = try XCTUnwrap(practice.result(at: now))
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
        through: result.elapsedDuration), tokens.joined(separator: separator))
      var repeated = practice.repeatedAttempt()
      repeated.insertBatch(tokens.prefix(100).joined(separator: separator) + separator, at: now)
      XCTAssertEqual(repeated.outcome, .active)
      XCTAssertTrue(repeated.needsLiveContentGeneration, "The directly published side section was not saved as generator history")
      XCTAssertTrue(repeated.acceptGeneratedLiveContent(.init(text: rest.joined(separator: separator),
        noSpaceBoundarySource: separator.isEmpty ? rest.joined(separator: " ") : nil)))
      repeated.insertBatch(rest.joined(separator: separator), at: now)
      XCTAssertEqual(repeated.outcome, .completed)
      XCTAssertEqual(repeated.errors, 0)
    }
  }

  func testTimedLiveWaitDoesNotPauseClockWithAlteredSeparators() throws {
    let tokens = (0..<100).map { "owned\($0)" }
    let content = LivePracticeContent(source: .encyclopedia, title: "Owned", byline: nil,
      tokens: tokens, separator: " ")
    for (alterations, commit) in [([TestModifier](), " "), ([.noSpaces], ""), ([.underscoreSeparators], "_")] {
      let configuration = TestConfiguration.timed(seconds: 30)
        .with(modifiers: [.referenceStream] + alterations)
      let preview = content.promptDescriptor(for: configuration)
      var practice = TestSessionFactory.make(configuration: configuration,
        streamPrompt: preview.text, streamsLiveContent: true)
      let now = Date(timeIntervalSince1970: 1_700_000_000)
      practice.insertBatch(tokens.joined(separator: commit) + commit, at: now)
      XCTAssertEqual(practice.completedWordCount, 100)
      XCTAssertEqual(practice.errors, 0)
      XCTAssertTrue(practice.isWaitingForLiveContent)
      practice.tick(at: now.addingTimeInterval(1))
      XCTAssertEqual(practice.remainingSeconds(at: now.addingTimeInterval(1)), 29)
      XCTAssertTrue(practice.isWaitingForLiveContent)
      practice.tick(at: now.addingTimeInterval(30))
      XCTAssertTrue(practice.isFinished)
      XCTAssertFalse(practice.isWaitingForLiveContent)
    }
  }

  func testFailedLiveFetchTerminatesWaitingWithoutAcceptingMoreInput() throws {
    let configuration = TestConfiguration.words(125).with(modifiers: [.referenceStream])
    let initial = (0..<100).map { "owned\($0)" }.joined(separator: " ")
    var practice = TestSessionFactory.make(configuration: configuration,
      streamPrompt: initial, streamsLiveContent: true)
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    practice.insertBatch(initial + " ", at: now)
    XCTAssertTrue(practice.isWaitingForLiveContent)
    let typed = practice.typed
    practice.failLiveContentFetch(at: now)
    XCTAssertEqual(practice.outcome, .failed)
    XCTAssertEqual(practice.failureReason, .wordGeneration)
    XCTAssertFalse(practice.isWaitingForLiveContent)
    XCTAssertFalse(practice.needsLiveContentPrefetch)
    practice.insertBatch("not accepted", at: now)
    XCTAssertEqual(practice.typed, typed)
    XCTAssertEqual(practice.errors, 0)
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
      XCTAssertNil(preview.noSpaceBoundarySource)
      let configuration = TestConfiguration.words(1,
        language: .simplifiedChinese).with(modifiers: [.referenceStream])
      var practice = TestSessionFactory.make(configuration: configuration,
        streamPrompt: content.text, streamsLiveContent: true, showAllLines: true)
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

  func testChineseIntroductionsPreserveASCIISourceFieldsInsteadOfSystemTokens() async throws {
    for language in [TypingLanguage.simplifiedChinese, .traditionalChinese, .jyutping] {
      try await withSession { session in
        let expected = "「海港」有12艘船，天气好。 第二段有34艘。"
        let response = try JSONSerialization.data(withJSONObject: [
          "query": ["pages": ["724": ["extract": "<p>「海港」有12艘船，天气好。</p><p>第二段有34艘。</p>"]]]
        ])
        IntroductionProtocol.fixture.set([
          (200, #"{"pageid":724,"title":"原创海港"}"#),
          (200, String(decoding: response, as: UTF8.self))
        ])
        let fetched = await LivePracticeContentService.fetch(source: .encyclopedia,
          language: language, session: session)
        let content = try XCTUnwrap(fetched)
        XCTAssertEqual(content.text, expected)
        let configuration = TestConfiguration.words(2, language: language).with(modifiers: [.referenceStream])
        let descriptor = content.promptDescriptor(for: configuration, showAllLines: true)
        XCTAssertEqual(descriptor.text, expected)
        XCTAssertNil(descriptor.noSpaceBoundarySource)
        var practice = TestSessionFactory.make(configuration: configuration,
          streamPrompt: descriptor.text, streamsLiveContent: true, showAllLines: true)
        XCTAssertEqual(practice.prompt, expected)
        let began = Date(timeIntervalSince1970: 1_700_000_000)
        practice.insertBatch(String(expected.dropLast()), at: began)
        XCTAssertFalse(practice.isFinished)
        practice.insertBatch(String(expected.suffix(1)), at: began.addingTimeInterval(2))
        XCTAssertEqual(practice.outcome, .completed)
        XCTAssertEqual(practice.completedWordCount, 2)
        XCTAssertEqual(practice.errors, 0)
        let result = try XCTUnwrap(practice.result())
        XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
          through: result.elapsedDuration), expected)
        XCTAssertEqual(practice.repeatedAttempt().prompt, expected)
      }
    }
  }

  func testParsedChineseSectionsRetainTailPrefetchBudgetAndExactFinalReplay() async throws {
    for language in [TypingLanguage.simplifiedChinese, .traditionalChinese, .jyutping] {
      for underscore in [false, true] {
        try await withSession { transport in
          let tokens = (0..<180).map { "海\($0)港。" }
          func introduction(_ id: String, _ words: ArraySlice<String>) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: [
              "query": ["pages": [id: ["extract": "<p>" + words.joined(separator: " ") + "</p>"]]]
            ])
            return String(decoding: data, as: UTF8.self)
          }
          IntroductionProtocol.fixture.set([
            (200, #"{"pageid":724,"title":"第一段"}"#),
            (200, try introduction("724", tokens[..<125])),
            (200, #"{"pageid":812,"title":"第二段"}"#),
            (200, try introduction("812", tokens[125...]))
          ])
          let fetched = await LivePracticeContentService.fetch(source: .encyclopedia,
            language: language, session: transport)
          let first = try XCTUnwrap(fetched)
          let modifiers: [TestModifier] = underscore ? [.referenceStream, .underscoreSeparators] : [.referenceStream]
          let configuration = TestConfiguration.words(175, language: language).with(modifiers: modifiers)
          let preview = first.promptDescriptor(for: configuration)
          XCTAssertEqual(preview.text, tokens.prefix(100).joined(separator: " "))
          XCTAssertNil(preview.noSpaceBoundarySource)
          var practice = TestSessionFactory.make(configuration: configuration,
            streamPrompt: preview.text, streamContinuation: first.continuationDescriptor(for: configuration),
            streamsLiveContent: true)
          let separator = underscore ? "_" : " "
          let began = Date(timeIntervalSince1970: 1_700_000_000)
          practice.insertBatch(tokens.prefix(105).joined(separator: separator) + separator, at: began)
          XCTAssertEqual(practice.completedWordCount, 105)
          XCTAssertFalse(practice.needsLiveContentPrefetch, "20 retained source fields remain")
          practice.insertBatch(tokens[105] + separator, at: began.addingTimeInterval(1))
          XCTAssertEqual(practice.completedWordCount, 106)
          XCTAssertTrue(practice.needsLiveContentPrefetch, "19 retained source fields trigger prefetch")
          XCTAssertFalse(practice.isWaitingForLiveContent)
          let next = await LivePracticeContentService.fetch(source: .encyclopedia,
            language: language, session: transport)
          XCTAssertTrue(practice.appendLiveContent(try XCTUnwrap(next).sectionDescriptor))
          XCTAssertEqual(IntroductionProtocol.fixture.requests.count, 4)
          XCTAssertFalse(practice.needsLiveContentPrefetch, "The finite budget is now fully loaded")
          let sideInput = tokens[125..<180].joined(separator: underscore ? "" : separator)
          let remaining = tokens[106..<125].joined(separator: separator) + separator + sideInput
          practice.insertBatch(String(remaining.dropLast()), at: began.addingTimeInterval(2))
          XCTAssertFalse(practice.isFinished)
          practice.insertBatch(String(remaining.suffix(1)), at: began.addingTimeInterval(3))
          XCTAssertEqual(practice.outcome, .completed)
          XCTAssertEqual(practice.completedWordCount, 180, "The fetched 55-field side section is not clipped to fifty remaining fields")
          XCTAssertEqual(practice.errors, 0)
          let expected = tokens.prefix(125).joined(separator: separator) + separator + sideInput
          let result = try XCTUnwrap(practice.result())
          XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents,
            through: result.elapsedDuration), expected)
          XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
          var repeated = practice.repeatedAttempt()
          repeated.insertBatch(tokens.prefix(125).joined(separator: separator) + separator, at: began.addingTimeInterval(4))
          XCTAssertTrue(repeated.needsLiveContentGeneration)
          XCTAssertEqual(repeated.errors, 0, "Saved-history phase: \(language), underscore=\(underscore)")
          XCTAssertEqual(repeated.typed, tokens.prefix(125).joined(separator: separator) + separator,
            "Saved-history input boundary: \(language), underscore=\(underscore)")
          XCTAssertTrue(repeated.acceptGeneratedLiveContent(try XCTUnwrap(next).sectionDescriptor))
          XCTAssertEqual(repeated.nextExpectedCharacter, "海", "Fresh-section boundary: \(language), underscore=\(underscore)")
          repeated.insertBatch(tokens[125..<175].joined(separator: separator), at: began.addingTimeInterval(5))
          XCTAssertEqual(repeated.prompt, tokens.prefix(175).joined(separator: separator))
          XCTAssertEqual(repeated.outcome, .completed)
          XCTAssertEqual(repeated.completedWordCount, 175)
          XCTAssertEqual(repeated.errors, 0)
        }
      }
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
