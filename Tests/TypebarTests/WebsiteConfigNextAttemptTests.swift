import Darwin
import TypebarSystem
import XCTest
import Observation
@testable import Typebar

@MainActor final class WebsiteConfigNextAttemptTests: XCTestCase {
  private enum Failure: Error { case notCommitted }

  func testExhaustedQuoteInitKeepsConsumedQueueForTheNextAcceptedRestart() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let disk = try f.register.read().revision, presentation = f.page.state.presentation
    let quotes = (0..<4).map { index in
      OfflineQuote(id: "owned-\(index)", title: "Owned failed-draw sample", text: index < 3 ? "" : "ef gh",
        language: .english, length: .short)
    }
    var bounds: [Int] = []
    let first = try f.coordinator.beginRestart(for: f.page)
    let capture = try f.page.captureGeneration(router: f.router)
    let applicationCapture = try f.page.captureApplication(router: f.router)
    let sessionState = f.page.state.session.generationState
    do {
      _ = try await f.coordinator.prepareRestart(first, loadQuotes: { _ in quotes },
        random: .init(quoteIndex: { bounds.append($0); return 0 }))
      XCTFail("Three empty quotes delivered")
    } catch WebsiteConfigSessionBuildError.generationFailed {}
    XCTAssertEqual(bounds, [4, 3, 2])
    XCTAssertFalse(f.page.isCurrent(capture, router: f.router))
    XCTAssertFalse(f.page.isCurrent(applicationCapture, router: f.router))
    XCTAssertEqual(f.page.state.session.generationState, sessionState)
    XCTAssertTrue(f.page.state.presentation === presentation)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try f.register.read().revision, disk)
    let repeatFailure = try f.coordinator.beginRestart(for: f.page, repeatingRequested: true)
    do {
      _ = try await f.coordinator.prepareRestart(repeatFailure, loadQuotes: { _ in
        XCTFail("Explicit repeat must use the actual failed quote, not reload or revive the old visible quote")
        return quotes
      }, random: .init(quoteIndex: { _ in XCTFail("Repeat consumed another draw"); return 0 }))
      XCTFail("Repeating the empty failed quote silently revived the old visible prompt")
    } catch WebsiteConfigSessionBuildError.generationFailed {}
    XCTAssertEqual(bounds, [4, 3, 2])
    let retry = try f.coordinator.beginRestart(for: f.page)
    let ready = try await f.coordinator.prepareRestart(retry, loadQuotes: { _ in quotes },
      random: .init(quoteIndex: { bounds.append($0); return 0 }))
    guard case .advanced = try f.coordinator.advance(ready, to: f.page) else { throw Failure.notCommitted }
    XCTAssertEqual(bounds, [4, 3, 2, 1])
    XCTAssertEqual(f.page.state.practice?.quote?.id, "owned-3")
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testCancelledReaderAfterFailedDrawKeepsOnlyAcceptedSelectionProgress() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let quotes: [OfflineQuote] = [
      .init(id: "bad", title: "Owned empty sample", text: "", language: .english, length: .short),
      .init(id: "good", title: "Owned valid sample", text: "ef gh", language: .english, length: .short),
    ]
    var reads = 0, bounds: [Int] = [], reply: CheckedContinuation<[OfflineQuote], Never>?
    defer { reply?.resume(returning: quotes) }
    let accepted = try f.coordinator.beginRestart(for: f.page)
    let task = Task { _ = try await f.coordinator.prepareRestart(accepted, loadQuotes: { _ in
      reads += 1
      if reads == 2 { return await withCheckedContinuation { reply = $0 } }
      return quotes
    }, random: .init(quoteIndex: { bounds.append($0); return 0 })) }
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while reply == nil && ContinuousClock.now < deadline { await Task.yield() }
    let continuation = try XCTUnwrap(reply)
    let checkpoint = try XCTUnwrap(f.page.state.quoteInitialization).id
    XCTAssertEqual(bounds, [2])
    XCTAssertTrue(f.coordinator.cancel(accepted))
    continuation.resume(returning: quotes); reply = nil
    do { _ = try await task.value; XCTFail("Retired reply delivered") }
    catch WebsiteConfigCommitCoordinatorError.stale {}
    XCTAssertEqual(f.page.state.quoteInitialization?.id, checkpoint)
    let ready = try await f.coordinator.prepareRestart(f.coordinator.beginRestart(for: f.page), loadQuotes: { _ in quotes },
      random: .init(quoteIndex: { bounds.append($0); return 0 }))
    guard case .advanced = try f.coordinator.advance(ready, to: f.page) else { throw Failure.notCommitted }
    XCTAssertEqual(bounds, [2, 1])
    XCTAssertEqual(f.page.state.practice?.quote?.id, "good")
    XCTAssertNil(f.page.state.quoteInitialization)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testNewQuoteSetterAfterFailedRestartResetsEvenWhenCancelledBeforeInit() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let quotes = (0..<4).map { index in
      OfflineQuote(id: "owned-\(index)", title: "Owned reset sample", text: index < 3 ? "" : "ef gh",
        language: .english, length: .short)
    }
    var bounds: [Int] = []
    do {
      _ = try await f.coordinator.prepareRestart(f.coordinator.beginRestart(for: f.page), loadQuotes: { _ in quotes },
        random: .init(quoteIndex: { bounds.append($0); return 0 }))
      XCTFail("Expected failed initialization")
    } catch WebsiteConfigSessionBuildError.generationFailed {}
    let previousDisk = try f.register.read().revision
    let action = WebsiteConfigPracticeEdit.quoteLengths([0])
    let edited = try f.coordinator.prepareEdit(key: action.key, value: action.value, for: f.page)
    guard case .accepted(let ticket) = try f.coordinator.beginConfigurationRestart(edited, for: f.page, action: action) else {
      return XCTFail("Setter was rejected")
    }
    XCTAssertTrue(f.coordinator.cancel(ticket))
    let resumed = try f.coordinator.resumeConfigurationRestart(for: f.page)
    let resources = try f.coordinator.prepareResources(for: resumed, localFont: .absent, localBackground: .absent)
    do {
      _ = try await f.coordinator.preparePractice(for: resources, loadQuotes: { _ in quotes },
        random: .init(quoteIndex: { bounds.append($0); return 0 }))
      XCTFail("New setter reused the exhausted preparation instead of resetting it")
    } catch WebsiteConfigSessionBuildError.generationFailed {}
    XCTAssertEqual(bounds, [4, 3, 2, 4, 3, 2])
    XCTAssertNotEqual(try f.register.read().revision, previousDisk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testPostDrawFailureCannotRetainProgressAfterRecordOrOwnerInvalidation() async throws {
    for changesRecord in [false, true] {
      let f = try Fixture(); defer { f.close() }
      try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
      f.input("a")
      let oldDisk = try XCTUnwrap(f.register.read().revision), presentation = f.page.state.presentation
      let competitor = try WebsiteConfigNativeProfile.prepareDraft(#"{"words":17}"#, pointsPerRem: 16, context: .init())
      var expectedDisk = oldDisk, draws = 0
      let accepted = try f.coordinator.beginRestart(for: f.page)
      do {
        _ = try await f.coordinator.prepareRestart(accepted, loadQuotes: { _ in
          [.init(id: "bad", title: "Owned empty sample", text: "", language: .english, length: .short)]
        }, random: .init(quoteIndex: { _ in
          draws += 1
          if changesRecord {
            do {
              guard case .committed(let revision) = try f.register.commit(competitor, replacing: oldDisk) else {
                XCTFail("Competing write failed"); return 0
              }
              expectedDisk = revision
            } catch { XCTFail("Competing write error: \(error)") }
          } else { f.page.detach() }
          return 0
        }))
        XCTFail("Invalidated draw retained progress")
      } catch WebsiteConfigCommitCoordinatorError.stale {}
      XCTAssertEqual(draws, 1)
      XCTAssertNil(f.page.state.quoteInitialization)
      XCTAssertTrue(f.page.state.presentation === presentation)
      XCTAssertEqual(try f.register.read().revision, expectedDisk)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    }
  }

  func testTaskCancellationAtQuoteCheckpointPreservesDrawButStopsRetry() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let quotes: [OfflineQuote] = [
      .init(id: "bad", title: "Owned empty sample", text: "", language: .english, length: .short),
      .init(id: "good", title: "Owned valid sample", text: "ef gh", language: .english, length: .short),
    ]
    let accepted = try f.coordinator.beginRestart(for: f.page)
    var bounds: [Int] = []
    await Task { @MainActor in
      withObservationTracking { _ = f.page.state.quoteInitialization?.id }
        onChange: { withUnsafeCurrentTask { $0?.cancel() } }
      do {
        _ = try await f.coordinator.prepareRestart(accepted, loadQuotes: { _ in quotes },
          random: .init(quoteIndex: { bounds.append($0); return 0 }))
        XCTFail("Cancelled checkpoint retried or delivered")
      } catch is CancellationError {} catch { XCTFail("Cancellation lost precedence: \(error)") }
    }.value
    XCTAssertEqual(bounds, [2])
    XCTAssertEqual(f.page.state.currentQuoteInitialization?.quote?.id, "bad")
    let ready = try await f.coordinator.prepareRestart(f.coordinator.beginRestart(for: f.page), loadQuotes: { _ in quotes },
      random: .init(quoteIndex: { bounds.append($0); return 0 }))
    guard case .advanced = try f.coordinator.advance(ready, to: f.page) else { throw Failure.notCommitted }
    XCTAssertEqual(bounds, [2, 1])
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testUnacceptedEditCannotReplaceAnEarlierAcceptedQuoteCheckpoint() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off","resultSaving":true}"#)
    f.input("a")
    let disk = try f.register.read().revision
    func catalog(_ length: QuoteLength) -> [OfflineQuote] {
      (0..<4).map { index in
        .init(id: "\(length.rawValue)-\(index)", title: "Owned candidate-isolation sample",
          text: index < 3 ? "" : "ef gh", language: .english, length: length)
      }
    }
    let original = catalog(.short), candidate = catalog(.medium)
    var bounds: [Int] = []
    do {
      _ = try await f.coordinator.prepareRestart(f.coordinator.beginRestart(for: f.page), loadQuotes: { _ in original },
        random: .init(quoteIndex: { bounds.append($0); return 0 }))
      XCTFail("Expected three failed draws")
    } catch WebsiteConfigSessionBuildError.generationFailed {}
    let checkpoint = try XCTUnwrap(f.page.state.quoteInitialization).id
    let edit = try f.coordinator.prepareEdit(key: "quoteLength", value: .array([.number(1)]), for: f.page)
    let resources = try f.coordinator.prepareResources(for: edit, localFont: .absent, localBackground: .absent)
    do {
      _ = try await f.coordinator.preparePractice(for: resources, loadQuotes: { _ in candidate },
        random: .init(quoteIndex: { bounds.append($0); return 0 }))
      XCTFail("Unaccepted edit delivered")
    } catch WebsiteConfigSessionBuildError.generationFailed {}
    XCTAssertEqual(f.page.state.quoteInitialization?.id, checkpoint)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(try f.register.read().revision, disk)
    let ready = try await f.coordinator.prepareRestart(f.coordinator.beginRestart(for: f.page), loadQuotes: { _ in original },
      random: .init(quoteIndex: { bounds.append($0); return 0 }))
    guard case .advanced = try f.coordinator.advance(ready, to: f.page) else { throw Failure.notCommitted }
    XCTAssertEqual(bounds, [4, 3, 2, 4, 3, 2, 1])
    XCTAssertEqual(f.page.state.practice?.quote?.id, "\(QuoteLength.short.rawValue)-3")
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try f.register.read().revision, disk)
  }
  @MainActor private final class Fixture {
    let page = PracticePageSessionStore(), router = PreferenceConfigurationSaveRouter()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-next-attempt-\(UUID())")
    let register: WebsiteConfigFileRegister
    var epoch = UUID()
    var environmentAction: (() -> Void)?
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
      environment: { [unowned self] in
        environmentAction?()
        return .init(revision: epoch, context: .init(), pointsPerRem: 16)
      })
    var quotes: [OfflineQuote] {
      [("101", QuoteLength.short), ("102", .short), ("103", .medium)].map {
        .init(id: $0.0, title: "Owned continuation sample", text: "ab", language: .english, length: $0.1)
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
    func publish(_ json: String = #"{"mode":"quote","quoteLength":[0,0,1]}"#) async throws {
      let resources = try coordinator.prepareResources(for: coordinator.prepare(json), localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resources, scope: .init(customText: "ab cd"),
        loadQuotes: { _ in self.quotes }, random: .init(quoteIndex: { _ in 0 }))
      guard case .committed = try coordinator.commit(ready, to: page, systemIsDark: true) else { throw Failure.notCommitted }
    }
    func input(_ text: String) {
      var value = page.state
      value.session.insertBatch(text)
      page.replace(value)
    }
  }

  func testNextInstallsOnceWithoutWritingConfigOrReplayingQuoteLength() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let presentation = try XCTUnwrap(f.page.state.presentation)
    let disk = try f.register.read().revision
    let bytes = try Data(contentsOf: f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename))
    let oldID = f.page.state.session.automaticInputAttemptID
    var budget: Int?
    let next = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes },
      random: .init(quoteIndex: { budget = $0; return 0 }))
    XCTAssertEqual(budget, 4, "Ordinary next must advance, not reset the five-slot weighted queue")
    guard case .advanced(let old) = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Next was not installed") }
    XCTAssertEqual(old.session.automaticInputAttemptID, oldID)
    XCTAssertNil(old.incomplete)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, oldID)
    XCTAssertFalse(f.page.state.session.hasStarted)
    XCTAssertTrue(f.page.state.presentation === presentation)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(try Data(contentsOf: f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)), bytes)
    guard case .stale = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Next was installed twice") }
    var secondBudget: Int?
    _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes },
      random: .init(quoteIndex: { secondBudget = $0; return 0 }))
    XCTAssertEqual(secondBudget, 3)
  }

  func testInputDuringPreparationRetiresCandidateAndDoesNotConsumeQueue() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    do {
      _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.input("a"); return f.quotes })
      XCTFail("A late candidate replaced new input")
    } catch WebsiteConfigCommitCoordinatorError.stale {}
    XCTAssertEqual(f.page.state.session.typed, "a")
    var budget: Int?
    _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes },
      random: .init(quoteIndex: { budget = $0; return 0 }))
    XCTAssertEqual(budget, 4)
  }

  func testNoQuitAndNewEnvironmentRejectBeforeGeneration() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"funbox":["no_quit"]}"#)
    f.input("a")
    do {
      _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in XCTFail("No Quit reached generation"); return f.quotes })
      XCTFail("Active No Quit restarted")
    } catch PracticePageSessionStateError.locked {}
    f.epoch = UUID()
    do {
      _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in XCTFail("Stale environment reached generation"); return f.quotes })
      XCTFail("Old resources crossed environments")
    } catch WebsiteConfigCommitCoordinatorError.stale {}
  }

  func testPriorActiveAttemptIsReturnedOnlyAfterSuccessfulReplacement() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"custom"}"#)
    f.input("a")
    let next = try await f.coordinator.prepareNext(for: f.page)
    guard case .advanced(let old) = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Next failed") }
    XCTAssertEqual(old.session.typed, "a")
    XCTAssertTrue(old.session.hasStarted)
    XCTAssertFalse(old.session.isFinished)
    XCTAssertEqual(old.incomplete?.accuracy, 100)
    XCTAssertGreaterThanOrEqual(try XCTUnwrap(old.incomplete?.engagedDuration), 0)
    XCTAssertEqual(f.page.state.session.typed, "")
    XCTAssertFalse(f.page.acceptsInput(for: old.session.automaticInputAttemptID))
  }

  func testDiskConflictAndForeignPageKeepTheOldAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let oldID = f.page.state.session.automaticInputAttemptID
    let next = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes })
    let foreign = PracticePageSessionStore(); foreign.attach(to: f.router)
    XCTAssertThrowsError(try f.coordinator.advance(next, to: foreign))
    let disk = try XCTUnwrap(f.register.read().revision)
    let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"words":17}"#, pointsPerRem: 16, context: .init())
    guard case .committed = try f.register.commit(external, replacing: disk) else { return XCTFail("Fixture write failed") }
    guard case .conflict = try f.coordinator.advance(next, to: f.page) else { return XCTFail("External settings were ignored") }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, oldID)
  }

  func testAttachmentABAAndCancellationDoNotReplaceTheAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let oldID = f.page.state.session.automaticInputAttemptID
    let next = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes })
    f.page.detach(); f.page.attach(to: f.router)
    guard case .stale = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Attachment ABA revived a candidate") }
    let cancelled = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes })
    XCTAssertTrue(f.coordinator.cancel(cancelled))
    XCTAssertFalse(f.coordinator.cancel(cancelled))
    guard case .stale = try f.coordinator.advance(cancelled, to: f.page) else { return XCTFail("Cancelled attempt was installed") }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, oldID)
  }

  func testFailedNewGenerationRetiresOlderReadyCandidateWithoutConsumingQueue() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let first = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes })
    do {
      _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in throw Failure.notCommitted })
      XCTFail("Failed source was admitted")
    } catch Failure.notCommitted {}
    guard case .stale = try f.coordinator.advance(first, to: f.page) else { return XCTFail("An older seed survived a newer request") }
    var budget: Int?
    _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes },
      random: .init(quoteIndex: { budget = $0; return 0 }))
    XCTAssertEqual(budget, 4)
  }

  func testBusyReadReleasesPageReservationAndAllowsExactCandidateRetry() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let oldID = f.page.state.session.automaticInputAttemptID
    let next = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes })
    let descriptor = Darwin.open(f.directory.appendingPathComponent(WebsiteConfigFileRegister.lockFilename).path,
      O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    XCTAssertGreaterThanOrEqual(descriptor, 0); defer { Darwin.close(descriptor) }
    XCTAssertEqual(typebar_file_lock(descriptor, LOCK_EX | LOCK_NB), 0)
    defer { _ = typebar_file_lock(descriptor, LOCK_UN) }
    guard case .busy = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Expected bounded busy result") }
    XCTAssertTrue(f.page.acceptsInput(for: oldID), "Busy must release the page reservation")
    XCTAssertEqual(typebar_file_lock(descriptor, LOCK_UN), 0)
    guard case .advanced = try f.coordinator.advance(next, to: f.page) else { return XCTFail("Exact candidate retry failed") }
  }

  func testInjectedOldClockCannotChangeDiskAfterTheFinalRead() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"custom"}"#)
    let seed = try XCTUnwrap(f.page.state.practice?.session)
    let disk = try XCTUnwrap(f.register.read().revision)
    let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"words":17}"#, pointsPerRem: 16, context: .init())
    var armed = false
    var clockTime: TimeInterval = 0
    var state = f.page.state
    state.session = seed.withElapsedClock(.init {
      if armed {
        armed = false
        do {
          guard case .committed = try f.register.commit(external, replacing: disk) else { XCTFail("Fixture clock write failed"); return clockTime }
        } catch { XCTFail("Fixture clock error: \(error)") }
      }
      return clockTime
    })
    f.page.replace(state)
    f.input("a")
    clockTime = 1
    let oldID = f.page.state.session.automaticInputAttemptID
    let next = try await f.coordinator.prepareNext(for: f.page)
    armed = true
    guard case .conflict = try f.coordinator.advance(next, to: f.page) else {
      return XCTFail("Clock callback changed the record after validation, but the attempt was replaced")
    }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, oldID)
    XCTAssertEqual(f.page.state.session.typed, "a")
  }

  func testCancellationFromEnvironmentCallbackStopsBeforeInstallation() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let oldID = f.page.state.session.automaticInputAttemptID
    let disk = try f.register.read().revision
    let next = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in f.quotes })
    var work: Task<Void, Error>?
    f.environmentAction = { work?.cancel() }
    defer { f.environmentAction = nil }
    work = Task { @MainActor in _ = try f.coordinator.advance(next, to: f.page) }
    do {
      try await XCTUnwrap(work).value
      XCTFail("Cancellation from a checked callback was ignored")
    } catch is CancellationError {}
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, oldID)
    XCTAssertEqual(try f.register.read().revision, disk)
  }
}
