import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigRepeatAttemptTests: XCTestCase {
  private enum Failure: Error { case notCommitted }
  @MainActor private final class Fixture {
    let page = PracticePageSessionStore(), router = PreferenceConfigurationSaveRouter()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-repeat-attempt-\(UUID())")
    let register: WebsiteConfigFileRegister
    lazy var coordinator: WebsiteConfigCommitCoordinator = {
      let epoch = UUID()
      return .init(router: router, register: register,
        environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    }()
    var quotes: [OfflineQuote] {
      [("101", QuoteLength.short), ("102", .short), ("103", .medium)].map {
        .init(id: $0.0, title: "Owned repeat sample", text: "ab", language: .english, length: $0.1)
      }
    }
    init() throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: page.owner, save: { XCTFail("No legacy settings write") })
      page.attach(to: router)
    }
    func close() { page.detach(); try? FileManager.default.removeItem(at: directory) }
    func publish(_ json: String = #"{"mode":"quote","quoteLength":[0,0,1],"repeatedPace":true}"#,
      scope: WebsiteConfigSessionBuilder.Scope = .init(customText: "ab cd")) async throws {
      let resource = try coordinator.prepareResources(for: coordinator.prepare(json), localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resource, scope: scope,
        loadQuotes: { _ in self.quotes }, random: .init(quoteIndex: { _ in 0 }))
      guard case .committed = try coordinator.commit(ready, to: page, systemIsDark: true) else { throw Failure.notCommitted }
    }
    func input(_ text: String) {
      var state = page.state; state.session.insert(text); page.replace(state)
    }
  }

  func testPinnedQuoteRepeatUsesOwnedPoolWithoutReadingNewLanguageOrLengthCatalog() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Output: Decodable { let fixtures, nullWordset: Int }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-config-quote-repeat.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures, 24)
    XCTAssertEqual(output.nullWordset, 1)
  }

  func testPinnedRepeatedWordHistoryAndExhaustionPolicy() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable { let mode: TestMode; let customMode, outcome: String; let limit, index: Int }
    struct Output: Decodable { let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-word-history.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 60)
    var history = GeneratedWordReplayHistory(noSpace: false)
    history.append(source: "Ab", target: "Ab "); history.append(source: "cd", target: "cd\n")
    for f in output.fixtures {
      let completion: CustomTextCompletion = f.customMode == "time" ? .time : f.customMode == "section" ? .sections : .words
      let config = TestConfiguration(mode: f.mode, duration: nil, wordLimit: f.limit, difficulty: .normal,
        rules: .init(), customTextCompletion: completion, customTextSectionLimit: f.limit)
      let actual = history.word(at: f.index) != nil ? "cached"
        : GeneratedRepeatedWordPolicy.permitsFreshWord(configuration: config, wordIndex: f.index, sectionIndex: f.index)
          ? "fresh" : "unavailable"
      XCTAssertEqual(actual, f.outcome, "\(f.mode) \(f.customMode) limit=\(f.limit) index=\(f.index)")
    }
  }

  func testPinnedRestartPrefixDecisionsIncludingFailureAndLanguageMatch() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable {
      let mode: TestMode
      let active, previouslyRepeated, requested, failed, repeatQuotes, repeatedPace: Bool
      let language: String
      let quoteLanguage: String?
      let repeats, pace: Bool
    }
    struct Output: Decodable { let entryFixtures: Int; let noQuitFixtures: Int; let fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-result-repeat.mjs").path,
      reference, "--restart-policy"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertGreaterThan(output.entryFixtures, 0)
    XCTAssertEqual(output.noQuitFixtures, 5)
    XCTAssertEqual(output.fixtures.count, 960)
    for f in output.fixtures {
      let actual = WebsiteConfigRestartPolicy.resolve(requested: f.requested, active: f.active,
        previouslyRepeated: f.previouslyRepeated, failed: f.failed, mode: f.mode,
        language: f.language, quoteLanguage: f.quoteLanguage, repeatQuotes: f.repeatQuotes, repeatedPace: f.repeatedPace)
      let expected: WebsitePracticeRepetition = f.repeats ? .sameWordset(repeatedPace: f.pace) : .none
      XCTAssertEqual(actual, expected, "\(f.mode) active=\(f.active) failed=\(f.failed) quote=\(f.quoteLanguage as Any)")
    }
  }

  func testExplicitQuoteRepeatKeepsQueueResourcesAndConfigurationRevision() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let presentation = try XCTUnwrap(f.page.state.presentation)
    let disk = try f.register.read().revision
    let prompt = f.page.state.session.prompt
    let repeatAttempt = try await f.coordinator.prepareRestart(for: f.page, repeatingRequested: true,
      loadQuotes: { _ in XCTFail("A repeat must not draw another quote"); return f.quotes })
    guard case .advanced = try f.coordinator.advance(repeatAttempt, to: f.page) else { return XCTFail("Repeat did not install") }
    XCTAssertEqual(f.page.state.session.prompt, prompt)
    XCTAssertEqual(f.page.state.practice?.quote?.id, "101")
    XCTAssertEqual(f.page.state.practice?.repetition, .sameWordset(repeatedPace: true))
    XCTAssertTrue(f.page.state.presentation === presentation)
    XCTAssertEqual(try f.register.read().revision, disk)
    var budget: Int?
    let next = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes },
      random: .init(quoteIndex: { budget = $0; return 0 }))
    XCTAssertEqual(budget, 4)
    guard case .advanced = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Fresh next did not install") }
    XCTAssertEqual(f.page.state.practice?.repetition, WebsitePracticeRepetition.none)
  }

  func testOrdinaryCandidateRepeatReusesOwnedTargetsWithoutDrawsOrSetterReplay() async throws {
    for json in [
      #"{"mode":"words","words":4,"funbox":["rAnDoMcAsE"],"repeatedPace":true}"#,
      #"{"mode":"words","words":4,"language":"code_javascript","funbox":["rAnDoMcAsE"]}"#,
      #"{"mode":"words","words":1001,"showAllLines":true}"#,
    ] {
      let f = try Fixture(); defer { f.close() }
      try await f.publish(json)
      let original = f.page.state.session
      let presentation = try XCTUnwrap(f.page.state.presentation)
      let disk = try f.register.read().revision
      let next = try await f.coordinator.prepareRestart(for: f.page, repeatingRequested: true,
        random: .init(wordIndex: { XCTFail("Repeat cannot draw a new word"); return 0 },
          caseBit: { XCTFail("Repeat cannot alter an owned target"); return false },
          contentUnit: { XCTFail("Repeat cannot redecorate an owned word"); return 0 }))
      guard case .advanced = try f.coordinator.advance(next, to: f.page) else { throw Failure.notCommitted }
      XCTAssertEqual(f.page.state.session.prompt, FinitePromptCommitPolicy.finalized(.init(text: original.prompt)).text)
      XCTAssertEqual(f.page.state.session.configuration, original.configuration)
      XCTAssertEqual(f.page.state.session.generatedWordReplayHistory?.count, original.generatedWordReplayHistory?.count)
      XCTAssertEqual(f.page.state.practice?.repetition.repeatsWordset, true)
      XCTAssertEqual(f.page.state.practice?.repetition.repeatsPace, presentation.publication.draft.behavior.repeatedPace)
      XCTAssertTrue(f.page.state.presentation === presentation)
      XCTAssertEqual(try f.register.read().revision, disk)
    }
  }

  func testActiveRepeatedCustomRestartsRepeatButUnstartedRepeatCanReturnToFreshGeneration() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"custom","repeatedPace":false}"#)
    let first = try await f.coordinator.prepareRestart(for: f.page, repeatingRequested: true)
    guard case .advanced = try f.coordinator.advance(first, to: f.page) else { throw Failure.notCommitted }
    f.input("a")
    let second = try await f.coordinator.prepareRestart(for: f.page)
    guard case .advanced(let old) = try f.coordinator.advance(second, to: f.page) else { throw Failure.notCommitted }
    XCTAssertEqual(old.session.typed, "a")
    XCTAssertNotNil(old.incomplete)
    XCTAssertEqual(f.page.state.practice?.repetition, .sameWordset(repeatedPace: false))
    let fresh = try await f.coordinator.prepareRestart(for: f.page)
    guard case .advanced = try f.coordinator.advance(fresh, to: f.page) else { throw Failure.notCommitted }
    XCTAssertEqual(f.page.state.practice?.repetition, WebsitePracticeRepetition.none)
  }

  func testFailedQuoteWithTypingRepeatUsesItsOwnedQuoteWithoutAnotherDraw() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","language":"english_1k","difficulty":"master","repeatQuotes":"typing"}"#)
    f.input("x")
    XCTAssertTrue(f.page.state.session.isFinished)
    XCTAssertEqual(f.page.state.session.outcome, .failed)
    XCTAssertNil(f.page.state.session.failureReason, "Native difficulty failures have no typed reason; do not miss the source failure marker")
    let retry = try await f.coordinator.prepareRestart(for: f.page,
      loadQuotes: { _ in XCTFail("Failed matching quote should repeat"); return f.quotes })
    guard case .advanced = try f.coordinator.advance(retry, to: f.page) else { throw Failure.notCommitted }
    XCTAssertEqual(f.page.state.session.prompt, "ab")
    XCTAssertEqual(f.page.state.practice?.repetition.repeatsWordset, true)
  }

  func testLongFiniteRepeatRestoresOpeningAndKeepsItsContinuation() async throws {
    let f = try Fixture(); defer { f.close() }
    let source = String(repeating: "amber harbor ", count: 1000) + "end"
    try await f.publish(#"{"mode":"custom"}"#, scope: .init(customText: "preview", finiteTextSource: source))
    let opening = f.page.state.session.prompt
    f.input(opening)
    XCTAssertGreaterThan(f.page.state.session.prompt.count, opening.count)
    let repeatAttempt = try await f.coordinator.prepareRestart(for: f.page, repeatingRequested: true)
    guard case .advanced = try f.coordinator.advance(repeatAttempt, to: f.page) else { throw Failure.notCommitted }
    XCTAssertEqual(f.page.state.session.prompt, opening)
    XCTAssertEqual(f.page.state.session.typed, "")
    f.input(opening)
    XCTAssertGreaterThan(f.page.state.session.prompt.count, opening.count)
    XCTAssertFalse(f.page.state.session.isFinished)
  }

  func testNoQuitCannotBeBypassedByExplicitRepeat() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"custom","funbox":["no_quit"]}"#)
    f.input("a")
    do {
      _ = try await f.coordinator.prepareRestart(for: f.page, repeatingRequested: true)
      XCTFail("Repeat bypassed active No Quit")
    } catch PracticePageSessionStateError.locked {}
    XCTAssertEqual(f.page.state.session.typed, "a")
  }

  func testRepetitionMetadataChangeRetiresCapturedPreparation() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let next = try await f.coordinator.prepareRestart(for: f.page, repeatingRequested: true)
    let capture = try f.page.captureGeneration(router: f.router)
    let old = f.page.state, practice = try XCTUnwrap(old.practice)
    let changed = WebsiteConfigSessionBuilder.Prepared(session: practice.session, scope: practice.scope,
      quote: practice.quote, external: practice.external, repetition: .sameWordset(repeatedPace: false))
    f.page.replace(.init(session: old.session, presentation: old.presentation, practice: changed))
    XCTAssertFalse(f.page.isCurrent(capture, router: f.router))
    guard case .stale = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Changed repetition revived a stale decision") }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, old.session.automaticInputAttemptID)
  }

  func testNewInputDuringQuoteTargetResamplingRejectsRepeatWithoutConsumingQueue() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0,0,1],"funbox":["rAnDoMcAsE"]}"#)
    let oldID = f.page.state.session.automaticInputAttemptID
    var sampled = false
    do {
      _ = try await f.coordinator.prepareRestart(for: f.page, repeatingRequested: true,
        random: .init(caseBit: { sampled = true; f.input("a"); return false }))
      XCTFail("A repeat replaced input received during its target transformation")
    } catch WebsiteConfigCommitCoordinatorError.stale {}
    XCTAssertTrue(sampled)
    XCTAssertFalse(f.page.state.session.typed.isEmpty)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, oldID)
    XCTAssertEqual(f.page.state.practice?.repetition, WebsitePracticeRepetition.none)
    var budget: Int?
    _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes },
      random: .init(quoteIndex: { budget = $0; return 0 }))
    XCTAssertEqual(budget, 4)
  }
}
