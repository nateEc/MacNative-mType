import XCTest
import Observation
import Darwin
import TypebarSystem
@testable import Typebar

@MainActor final class WebsiteConfigDepartureTests: XCTestCase {
  private enum Failure: Error { case admission, publication, generation }
  @MainActor private final class Fixture {
    let page = PracticePageSessionStore(), router = PreferenceConfigurationSaveRouter()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-config-departure-\(UUID())")
    let register: WebsiteConfigFileRegister
    var epoch = UUID()
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
      environment: { [unowned self] in .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    init() throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: page.owner, save: { XCTFail("No legacy write") })
      page.attach(to: router)
    }
    func close() { page.detach(); try? FileManager.default.removeItem(at: directory) }
    func publish(_ json: String = #"{"mode":"custom","resultSaving":true,"quoteLength":[0]}"#) async throws {
      let resources = try coordinator.prepareResources(for: coordinator.prepare(json), localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resources, scope: .init(customText: "ab cd"),
        loadQuotes: { _ in [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)] },
        random: .init(quoteIndex: { _ in 0 }))
      guard case .committed = try coordinator.commit(ready, to: page, systemIsDark: false) else { throw Failure.publication }
    }
    func input() { var state = page.state; state.session.insertBatch("a"); page.replace(state) }
    func edit(_ action: WebsiteConfigPracticeEdit = .mode(.quote)) throws -> WebsiteConfigCommitCoordinator.Prepared {
      try coordinator.prepareEdit(key: action.key, value: action.value, for: page)
    }
    func accept(_ ticket: WebsiteConfigCommitCoordinator.Prepared,
      action: WebsiteConfigPracticeEdit = .mode(.quote)) throws -> WebsiteConfigCommitCoordinator.Prepared {
      guard case .accepted(let result) = try coordinator.beginConfigurationRestart(ticket, for: page, action: action) else {
        XCTFail("Expected persisted setter and accepted departure"); throw Failure.admission
      }
      return result
    }
    func finish(_ ticket: WebsiteConfigCommitCoordinator.Prepared) async throws {
      let resources = try coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resources, loadQuotes: { _ in
        [.init(id: "own", title: "Own", text: "ab cd", language: .english, length: .short)]
      })
      guard case .committed = try coordinator.commit(ready, to: page, systemIsDark: false) else { throw Failure.publication }
    }
  }

  func testSetterPersistsAndDepartureIsRecordedBeforeGenerationAndDelivery() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(); f.input()
    let original = f.page.state.session.automaticInputAttemptID
    let oldPresentation = try XCTUnwrap(f.page.state.presentation)
    let ticket = try f.accept(f.edit())
    XCTAssertEqual(try f.register.read().state, .available(ticket.draft.projection.runtime))
    XCTAssertEqual(f.page.state.configurationDeparture?.draft.projection.runtime["mode"], .string("quote"))
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, original)
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertEqual(f.page.state.session.outcome, .abandoned)
    XCTAssertEqual(f.page.state.restartDepartureAttemptID, original)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertFalse(f.page.acceptsInput(for: original))
    XCTAssertFalse(f.page.acceptsAttemptCallback(for: original))
    XCTAssertTrue(f.page.state.presentation === oldPresentation, "A pending configuration is not a delivered practice")
    XCTAssertFalse(oldPresentation.publication.isCurrentDelivery(owner: f.page.owner, router: f.router))
    try await f.finish(ticket)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertNil(f.page.state.restartDepartureAttemptID)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, original)
    XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertTrue(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
  }

  func testGenerationFailureAndCancellationRetainSavedSetterAndCanResumeWithoutDoubleCounting() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(); f.input()
    let raw = try f.edit(), admitted = try f.accept(raw)
    let disk = try f.register.read().revision
    let pendingID = f.page.state.configurationDeparture?.id
    let resources = try f.coordinator.prepareResources(for: admitted, localFont: .absent, localBackground: .absent)
    do {
      _ = try await f.coordinator.preparePractice(for: resources, loadQuotes: { _ in throw Failure.generation })
      XCTFail("Expected provider failure")
    } catch Failure.generation {}
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.configurationDeparture?.id, pendingID)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertTrue(f.coordinator.cancel(admitted))
    guard case .stale = try f.coordinator.beginConfigurationRestart(raw, for: f.page, action: .mode(.quote)) else {
      return XCTFail("An old setter must not be accepted twice")
    }
    let cancelled = try f.coordinator.resumeConfigurationRestart(for: f.page)
    XCTAssertTrue(f.coordinator.cancel(cancelled))
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    try await f.finish(f.coordinator.resumeConfigurationRestart(for: f.page))
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(try f.register.read().revision, disk, "Delivering the already-saved configuration must not rewrite it")
  }

  func testArabicLazyPreferenceIsSavedAtDepartureNotDelayedUntilGeneration() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":4,"language":"arabic","lazyMode":true}"#)
    f.input()
    let action = WebsiteConfigPracticeEdit.lazyMode(false)
    let ticket = try f.accept(f.edit(action), action: action)
    XCTAssertFalse(ticket.draft.lazyMemory.prefersArabic)
    XCTAssertFalse(try f.register.read().lazyMemory.prefersArabic)
    XCTAssertFalse(try XCTUnwrap(f.page.state.configurationDeparture).draft.lazyMemory.prefersArabic)
    let revision = try f.register.read().revision
    XCTAssertTrue(f.coordinator.cancel(ticket))
    let resumed = try f.coordinator.resumeConfigurationRestart(for: f.page)
    XCTAssertFalse(resumed.draft.lazyMemory.prefersArabic)
    try await f.finish(resumed)
    XCTAssertEqual(try f.register.read().revision, revision)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testLanguageListenerRunsBeforeGenerationWithoutSavingItsNosaveLazyOverride() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":4,"language":"spanish","lazyMode":false}"#)
    f.input()
    let action = WebsiteConfigPracticeEdit.language("arabic")
    let ticket = try f.accept(f.edit(action), action: action)
    XCTAssertTrue(ticket.draft.generators.lazyMode)
    XCTAssertEqual(ticket.draft.projection.events.filter { $0.key == "lazyMode" }.count, 1)
    XCTAssertEqual(ticket.draft.projection.events.last?.nosave, true)
    guard case .available(let runtime) = try f.register.read().state else { return XCTFail("Missing saved setter") }
    XCTAssertEqual(runtime["language"], .string("arabic"))
    XCTAssertEqual(runtime["lazyMode"], .bool(false), "The listener's nosave setter is runtime-only at departure")
    XCTAssertTrue(f.coordinator.cancel(ticket))
    let resumed = try f.coordinator.resumeConfigurationRestart(for: f.page)
    let resources = try f.coordinator.prepareResources(for: resumed, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources)
    guard case .committed(let publication) = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("Prepared practice was not delivered")
    }
    XCTAssertEqual(publication.draft.projection.events.filter { $0.key == "lazyMode" }.count, 1,
      "Resuming initialization must not replay the language listener")
  }

  func testUnsupportedLanguageLazyNormalizationWaitsUntilGeneration() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":4,"language":"spanish","lazyMode":true}"#)
    f.input()
    let action = WebsiteConfigPracticeEdit.language("hindi")
    let ticket = try f.accept(f.edit(action), action: action)
    XCTAssertTrue(ticket.draft.generators.lazyMode)
    XCTAssertFalse(ticket.draft.lazyMemory.remember)
    XCTAssertFalse(try f.register.read().lazyMemory.remember)
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources)
    XCTAssertFalse(ready.session.configuration.modifiers.contains(.lazyLatin))
    XCTAssertFalse(try f.register.read().lazyMemory.remember, "A candidate is not a durable generation transition")
    guard case .committed(let publication) = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("Prepared practice was not delivered")
    }
    XCTAssertTrue(publication.draft.lazyMemory.remember)
    XCTAssertTrue(try f.register.read().lazyMemory.remember)
  }

  func testStaleInputOwnerEnvironmentAndCompetingRecordCannotAcceptDeparture() async throws {
    for change in 0..<4 {
      let f = try Fixture(); defer { f.close() }
      try await f.publish(); f.input()
      let ticket = try f.edit(), original = f.page.state.session.automaticInputAttemptID
      switch change {
      case 0: var state = f.page.state; state.session.insertBatch("b"); f.page.replace(state)
      case 1: let other = UUID(); f.router.register(owner: other, save: {}); f.router.activate(owner: other); f.router.activate(owner: f.page.owner)
      case 2: f.epoch = UUID()
      default:
        let epoch = UUID()
        let competitor = WebsiteConfigCommitCoordinator(router: f.router, register: f.register,
          environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
        guard case .committed = try competitor.commit(competitor.prepare(#"{"time":17}"#)) else { throw Failure.publication }
      }
      let disk = try f.register.read().revision
      let result = try f.coordinator.beginConfigurationRestart(ticket, for: f.page, action: .mode(.quote))
      switch result { case .stale, .conflict: break; default: XCTFail("Stale input/owner/environment/disk accepted") }
      XCTAssertEqual(try f.register.read().revision, disk)
      XCTAssertEqual(f.page.state.session.automaticInputAttemptID, original)
      XCTAssertFalse(f.page.state.session.isFinished)
      XCTAssertNil(f.page.state.configurationDeparture)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    }
  }

  func testNoQuitAndUnboundOrWrongActionTicketsCannotPersistOrCloseAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(); f.input()
    let unbound = try f.coordinator.prepare(#"{"mode":"quote"}"#)
    let disk = try f.register.read().revision
    guard case .stale = try f.coordinator.beginConfigurationRestart(unbound, for: f.page, action: .mode(.quote)) else {
      return XCTFail("Unbound import used as an active setter")
    }
    let bound = try f.edit()
    guard case .stale = try f.coordinator.beginConfigurationRestart(bound, for: f.page, action: .words(5)) else {
      return XCTFail("Different action used another setter's capability")
    }
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertFalse(f.page.state.session.isFinished)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    let locked = try Fixture(); defer { locked.close() }
    try await locked.publish(#"{"mode":"custom","funbox":["no_quit"]}"#); locked.input()
    let lockedDisk = try locked.register.read().revision
    XCTAssertThrowsError(try locked.edit())
    XCTAssertEqual(try locked.register.read().revision, lockedDisk)
    XCTAssertFalse(locked.page.state.session.isFinished)
  }

  func testSavingDisabledClosesAttemptWithoutAppendingLedger() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"custom","resultSaving":false,"quoteLength":[0]}"#); f.input()
    let ticket = try f.accept(f.edit())
    XCTAssertEqual(f.page.state.session.outcome, .abandoned)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    try await f.finish(ticket)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
  }

  func testObservationRetirementReportsAcceptedNotRolledBackAndKeepsInputClosed() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(); f.input()
    let ticket = try f.edit()
    withObservationTracking { _ = f.page.state } onChange: {
      MainActor.assumeIsolated { f.page.detach() }
    }
    guard case .acceptedRetired = try f.coordinator.beginConfigurationRestart(ticket, for: f.page, action: .mode(.quote)) else {
      return XCTFail("Post-write retirement must report accepted departure")
    }
    XCTAssertEqual(try f.register.read().state, .available(ticket.draft.projection.runtime))
    XCTAssertNotNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertFalse(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
    XCTAssertThrowsError(try f.coordinator.resumeConfigurationRestart(for: f.page))
  }

  func testBusyRecordLeavesClockAndInputLiveAndSameTicketCanRetry() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(); f.input()
    let ticket = try f.edit(), disk = try f.register.read().revision
    let attempt = f.page.state.session.automaticInputAttemptID
    let lock = Darwin.open(f.directory.appendingPathComponent(WebsiteConfigFileRegister.lockFilename).path,
      O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    XCTAssertGreaterThanOrEqual(lock, 0); defer { Darwin.close(lock) }
    XCTAssertEqual(typebar_file_lock(lock, LOCK_EX | LOCK_NB), 0)
    let outcome = try f.coordinator.beginConfigurationRestart(ticket, for: f.page, action: .mode(.quote))
    XCTAssertEqual(typebar_file_lock(lock, LOCK_UN), 0)
    guard case .busy = outcome else { return XCTFail("Expected bounded busy admission") }
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertFalse(f.page.state.session.isFinished)
    XCTAssertTrue(f.page.acceptsInput(for: attempt))
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    _ = try f.accept(ticket)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testCancellationBeforeWriteRefusesButCancellationAtAcceptedObservationCannotRollBack() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(); f.input()
    let ticket = try f.edit(), disk = try f.register.read().revision
    await Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        _ = try f.coordinator.beginConfigurationRestart(ticket, for: f.page, action: .mode(.quote))
        XCTFail("Cancelled admission wrote")
      } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }.value
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertFalse(f.page.state.session.isFinished)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    try await Task { @MainActor in
      withObservationTracking { _ = f.page.state } onChange: {
        withUnsafeCurrentTask { $0?.cancel() }
      }
      _ = try f.accept(ticket)
    }.value
    XCTAssertEqual(try f.register.read().state, .available(ticket.draft.projection.runtime))
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertNotNil(f.page.state.configurationDeparture)
    try await f.finish(f.coordinator.resumeConfigurationRestart(for: f.page))
  }

  func testPendingStageRejectsOrdinaryRestartAndUnboundPageReplacement() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(); f.input()
    _ = try f.accept(f.edit())
    let pending = f.page.state.configurationDeparture?.id
    let disk = try f.register.read().revision
    XCTAssertThrowsError(try f.edit(.words(6)))
    XCTAssertThrowsError(try f.coordinator.beginRestart(for: f.page))
    do {
      _ = try await f.coordinator.prepareNext(for: f.page)
      XCTFail("Pending setter went through the ordinary next path")
    } catch WebsiteConfigCommitCoordinatorError.sessionNotReady {}
    let raw = try f.coordinator.prepare(#"{"mode":"custom"}"#)
    let resources = try f.coordinator.prepareResources(for: raw, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources, scope: .init(customText: "own replacement"))
    guard case .stale = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("An unbound producer bypassed pending configuration recovery")
    }
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.configurationDeparture?.id, pending)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    try await f.finish(f.coordinator.resumeConfigurationRestart(for: f.page))
  }

  func testResumeRejectsChangedEnvironmentDiskAndForeignCoordinatorWithoutUndoingDeparture() async throws {
    for change in 0..<3 {
      let f = try Fixture(); defer { f.close() }
      try await f.publish(); f.input()
      _ = try f.accept(f.edit())
      let pending = f.page.state.configurationDeparture?.id
      let epoch = f.epoch
      let other = WebsiteConfigCommitCoordinator(router: f.router, register: f.register,
        environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
      switch change {
      case 0: f.epoch = UUID()
      case 1:
        guard case .committed = try other.commit(other.prepare(#"{"words":37}"#)) else { throw Failure.publication }
      default: break
      }
      let disk = try f.register.read().revision
      if change == 2 { XCTAssertThrowsError(try other.resumeConfigurationRestart(for: f.page)) }
      else { XCTAssertThrowsError(try f.coordinator.resumeConfigurationRestart(for: f.page)) }
      XCTAssertEqual(try f.register.read().revision, disk)
      XCTAssertEqual(f.page.state.configurationDeparture?.id, pending)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
      XCTAssertFalse(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
    }
  }

  func testActiveQuoteEditUsesNewDifficultyButOwnedQuoteWithoutDrawingOrConsumingPool() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0,0],"repeatQuotes":"typing","repeatedPace":true}"#)
    let retiredController = try f.page.bindRestartController(using: f.coordinator)
    f.input()
    let action = WebsiteConfigPracticeEdit.difficulty(.expert)
    let ticket = try f.accept(f.edit(action), action: action)
    XCTAssertNil(f.page.restartController)
    XCTAssertFalse(retiredController.request(), "The old restart capability must not cancel this phase")
    let disk = try f.register.read().revision
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources, loadQuotes: { _ in
      XCTFail("A repeated quote must not read another catalog")
      throw Failure.generation
    })
    XCTAssertEqual(ready.session.prompt, "ab cd")
    XCTAssertEqual(ready.session.configuration.difficulty, .expert)
    XCTAssertEqual(ready.practice?.quote?.id, "owned")
    XCTAssertEqual(ready.practice?.repetition, .sameWordset(repeatedPace: true))
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else { throw Failure.publication }
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    var budget: Int?
    _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in
      [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
    }, random: .init(quoteIndex: { budget = $0; return 0 }))
    XCTAssertEqual(budget, 1, "Configuration repeat must retain the old post-draw queue")
  }

  func testQuoteLengthEventResetsQueueButRepeatedQuoteDoesNotRequireNewGroupAvailability() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"typing"}"#); f.input()
    let action = WebsiteConfigPracticeEdit.quoteLengths([3])
    let ticket = try f.accept(f.edit(action), action: action)
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources, loadQuotes: { _ in
      XCTFail("Repeat bypasses catalog selection even when the new length is unavailable")
      throw Failure.generation
    })
    XCTAssertEqual(ready.practice?.quote?.id, "owned")
    XCTAssertNil(ready.practice?.quoteSampler, "The setter's pool reset still happens")
    XCTAssertEqual(ready.practice?.repetition.repeatsWordset, true)
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else { throw Failure.publication }
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [3])
    do {
      _ = try await f.coordinator.prepareNext(for: f.page, loadQuotes: { _ in
        [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
      XCTFail("Fresh generation must not silently ignore the unavailable group")
    } catch WebsiteConfigSessionBuildError.reconfigurationRequired {}
  }

  func testConfigurationRepeatDecisionUsesNewModeAndLanguageNotClosedAttemptConfiguration() async throws {
    for action in [WebsiteConfigPracticeEdit.mode(.words), .language("spanish"), .language("english")] {
      let f = try Fixture(); defer { f.close() }
      try await f.publish(#"{"mode":"quote","language":"english_1k","quoteLength":[0],"repeatQuotes":"typing"}"#)
      f.input()
      let ticket = try f.accept(f.edit(action), action: action)
      let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
      var readCount = 0
      let ready = try await f.coordinator.preparePractice(for: resources, loadQuotes: { language in
        readCount += 1; XCTAssertEqual(language, .spanish)
        return [.init(id: "new-spanish", title: "Own Spanish", text: "ab cd", language: .spanish, length: .short)]
      })
      if action == .language("english") {
        XCTAssertEqual(readCount, 0)
        XCTAssertEqual(ready.practice?.repetition.repeatsWordset, true)
        XCTAssertEqual(ready.practice?.quote?.id, "owned")
      } else {
        XCTAssertEqual(ready.practice?.repetition, WebsitePracticeRepetition.none)
        if action == .mode(.words) { XCTAssertEqual(readCount, 0); XCTAssertEqual(ready.session.configuration.mode, .words) }
        else { XCTAssertEqual(readCount, 1); XCTAssertEqual(ready.practice?.quote?.id, "new-spanish") }
      }
    }
  }

  func testCancelledRepeatedQuoteResamplingCanResumeWithoutDrawingOrRecounting() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"typing","funbox":["rAnDoMcAsE"]}"#)
    f.input()
    let action = WebsiteConfigPracticeEdit.difficulty(.expert)
    let admitted = try f.accept(f.edit(action), action: action)
    let disk = try f.register.read().revision
    let resources = try f.coordinator.prepareResources(for: admitted, localFont: .absent, localBackground: .absent)
    await Task { @MainActor in
      do {
        _ = try await f.coordinator.preparePractice(for: resources, loadQuotes: { _ in
          XCTFail("Repeated quote must not load a catalog"); throw Failure.generation
        }, random: .init(caseBit: { withUnsafeCurrentTask { $0?.cancel() }; return false }))
        XCTFail("Cancelled resampling delivered")
      } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }.value
    XCTAssertNotNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try f.register.read().revision, disk)
    let resumed = try f.coordinator.resumeConfigurationRestart(for: f.page)
    let retryResources = try f.coordinator.prepareResources(for: resumed, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: retryResources, loadQuotes: { _ in
      XCTFail("Retry lost its accepted repetition choice"); throw Failure.generation
    }, random: .init(caseBit: { false }))
    XCTAssertEqual(ready.session.prompt, "ab cd")
    XCTAssertEqual(ready.practice?.repetition.repeatsWordset, true)
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else { throw Failure.publication }
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testAlreadyRepeatedActiveQuoteKeepsOwnedPoolAcrossNonmatchingLanguageEdit() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off"}"#)
    let repeatAttempt = try await f.coordinator.prepareRestart(for: f.page, repeatingRequested: true)
    guard case .advanced = try f.coordinator.advance(repeatAttempt, to: f.page) else { throw Failure.publication }
    f.input()
    let action = WebsiteConfigPracticeEdit.language("spanish")
    let ticket = try f.accept(f.edit(action), action: action)
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources, loadQuotes: { _ in
      XCTFail("Previously repeated active state takes precedence over quote-language mismatch")
      throw Failure.generation
    })
    XCTAssertEqual(ready.session.configuration.language, .spanish)
    XCTAssertEqual(ready.session.prompt, "ab cd")
    XCTAssertEqual(ready.practice?.quote?.id, "owned")
    XCTAssertEqual(ready.practice?.repetition.repeatsWordset, true)
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else { throw Failure.publication }
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  private func repeatAndStart(_ f: Fixture) async throws {
    let ready = try await f.coordinator.prepareRestart(for: f.page, repeatingRequested: true)
    guard case .advanced = try f.coordinator.advance(ready, to: f.page) else { throw Failure.publication }
    f.input()
  }

  private func prepareRepeatedEdit(_ action: WebsiteConfigPracticeEdit, in f: Fixture,
    random: WebsiteConfigSessionBuilder.Random = .init()) async throws -> WebsiteConfigCommitCoordinator.SessionPrepared {
    let ticket = try f.accept(f.edit(action), action: action)
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    return try await f.coordinator.preparePractice(for: resources, random: random)
  }

  func testFiniteWordHistoryRepeatsUnderNewDifficultyWithoutResampling() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":4,"funbox":["rAnDoMcAsE"]}"#)
    let prompt = f.page.state.session.prompt
    try await repeatAndStart(f)
    let ready = try await prepareRepeatedEdit(.difficulty(.master), in: f,
      random: .init(wordIndex: { XCTFail("Cached words must not draw"); return 0 },
        caseBit: { XCTFail("Cached targets must not transform"); return true },
        contentUnit: { XCTFail("Cached decoration must not rerun"); return 0 }))
    XCTAssertTrue(ready.session.prompt.utf16.elementsEqual(prompt.utf16))
    XCTAssertEqual(ready.session.configuration.difficulty, .master)
    XCTAssertEqual(ready.practice?.repetition.repeatsWordset, true)
    var session = ready.session; session.insertBatch("¤")
    XCTAssertEqual(session.outcome, .failed)
  }

  func testShrinkingThenGrowingWordLimitKeepsHiddenFutureHistory() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":4}"#)
    let original = f.page.state.session.prompt
    try await repeatAndStart(f)
    let noDraw = WebsiteConfigSessionBuilder.Random(wordIndex: { XCTFail("Owned history must not draw"); return 0 })
    let shorter = try await prepareRepeatedEdit(.words(2), in: f, random: noDraw)
    XCTAssertEqual(shorter.session.prompt, original.components(separatedBy: " ").prefix(2).joined(separator: " "))
    XCTAssertFalse(shorter.session.usesIncrementalPromptExtension)
    guard case .committed = try f.coordinator.commit(shorter, to: f.page, systemIsDark: false) else { throw Failure.publication }
    f.input()
    let longer = try await prepareRepeatedEdit(.words(4), in: f, random: noDraw)
    XCTAssertEqual(longer.session.prompt, original)
    guard case .committed = try f.coordinator.commit(longer, to: f.page, systemIsDark: false) else { throw Failure.publication }
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 2)
  }

  func testWordHistoryExhaustionGeneratesOnlyMissingSuffixWithCurrentConfiguration() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":4}"#)
    let original = f.page.state.session.prompt
    try await repeatAndStart(f)
    var draws = 0
    let ready = try await prepareRepeatedEdit(.words(6), in: f,
      random: .init(wordIndex: { draws += 1; return draws }))
    XCTAssertTrue(ready.session.prompt.hasPrefix(original + " "))
    XCTAssertEqual(ready.session.prompt.components(separatedBy: " ").count, 6)
    XCTAssertGreaterThan(draws, 0)
    XCTAssertEqual(ready.session.configuration.wordLimit, 6)
  }

  func testWordHistorySurvivesLanguageChangeWithoutReinterpretingTargets() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":4}"#)
    let original = f.page.state.session.prompt
    try await repeatAndStart(f)
    let ready = try await prepareRepeatedEdit(.language("spanish"), in: f,
      random: .init(wordIndex: { XCTFail("Language change cannot replace owned cached words"); return 0 }))
    XCTAssertEqual(ready.session.configuration.language, .spanish)
    XCTAssertEqual(ready.session.prompt, original)
  }

  func testOwnedCodeCandidateHistoryUsesNewRulesWithoutResamplingCodeOrCase() async throws {
    for language in ["code_javascript", "code_python"] {
      let f = try Fixture(); defer { f.close() }
      try await f.publish("{\"mode\":\"words\",\"words\":4,\"language\":\"\(language)\",\"funbox\":[\"rAnDoMcAsE\"]}")
      let original = f.page.state.session.prompt
      try await repeatAndStart(f)
      let ready = try await prepareRepeatedEdit(.difficulty(.expert), in: f,
        random: .init(wordIndex: { XCTFail("Owned code must not draw"); return 0 },
          caseBit: { XCTFail("Owned code case must not resample"); return false }))
      XCTAssertTrue(ready.session.configuration.language.isCodeLanguage)
      XCTAssertEqual(ready.session.configuration.difficulty, .expert)
      XCTAssertEqual(ready.session.prompt, FinitePromptCommitPolicy.finalized(.init(text: original)).text)
      XCTAssertEqual(ready.session.generatedWordReplayHistory?.count, 4)
    }
  }

  func testWordToTimeModeUsesOwnedPrefixAndNewModePrefill() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":4}"#)
    let original = f.page.state.session.prompt
    try await repeatAndStart(f)
    var draws = 0
    let ready = try await prepareRepeatedEdit(.mode(.time), in: f,
      random: .init(wordIndex: { draws += 1; return draws }))
    XCTAssertEqual(ready.session.configuration.mode, .time)
    XCTAssertTrue(ready.session.prompt.hasPrefix(original + " "))
    XCTAssertTrue(ready.session.usesIncrementalPromptExtension)
    XCTAssertGreaterThan(draws, 0)
  }

  func testWholePreviewRepeatKeepsHistoryAcrossCooperativePreparation() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":1001,"showAllLines":true}"#)
    let original = f.page.state.session.prompt
    try await repeatAndStart(f)
    var draws = 0
    let ready = try await prepareRepeatedEdit(.words(1002), in: f,
      random: .init(wordIndex: { draws += 1; return draws }))
    XCTAssertTrue(ready.session.prompt.hasPrefix(original + " "))
    XCTAssertEqual(ready.session.prompt.components(separatedBy: " ").count, 1002)
    XCTAssertGreaterThan(draws, 0)
  }

  func testUnsupportedChangedNonQuoteRepeatCannotSilentlyFallBackToFreshGeneration() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let repeated = try await f.coordinator.prepareRestart(for: f.page, repeatingRequested: true)
    guard case .advanced = try f.coordinator.advance(repeated, to: f.page) else { throw Failure.publication }
    f.input()
    let action = WebsiteConfigPracticeEdit.difficulty(.expert)
    let ticket = try f.accept(f.edit(action), action: action)
    let disk = try f.register.read().revision
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    do {
      _ = try await f.coordinator.preparePractice(for: resources)
      XCTFail("Unimplemented cache reconfiguration silently became a fresh attempt")
    } catch WebsiteConfigSessionBuildError.repeatedConfigurationUnsupported {}
    XCTAssertNotNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testZeroWordLimitCannotGenerateBeyondOwnedHistoryDuringInitialization() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":4}"#)
    try await repeatAndStart(f)
    var draws = 0
    do {
      _ = try await prepareRepeatedEdit(.words(0), in: f,
        random: .init(wordIndex: { draws += 1; return draws }))
      XCTFail("Repeated words=0 unexpectedly fabricated additional history")
    } catch WebsiteConfigSessionBuildError.generationFailed {}
    XCTAssertEqual(draws, 0)
    XCTAssertNotNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testZeroWordLimitHistoryExhaustionDuringInputIsAGenerationFailure() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":100}"#)
    try await repeatAndStart(f)
    let ready = try await prepareRepeatedEdit(.words(0), in: f)
    var session = ready.session
    session.insertBatch(session.prompt)
    XCTAssertEqual(session.outcome, .failed)
    XCTAssertEqual(session.failureReason, .wordGeneration)
  }

  func testCancelledFreshSuffixCannotMutateOwnedHistoryAndRetryPreservesPrefix() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":4}"#)
    let original = f.page.state.session.prompt
    try await repeatAndStart(f)
    let action = WebsiteConfigPracticeEdit.words(6)
    let admitted = try f.accept(f.edit(action), action: action)
    let disk = try f.register.read().revision
    let resources = try f.coordinator.prepareResources(for: admitted, localFont: .absent, localBackground: .absent)
    await Task { @MainActor in
      do {
        _ = try await f.coordinator.preparePractice(for: resources,
          random: .init(wordIndex: { withUnsafeCurrentTask { $0?.cancel() }; return 7 }))
        XCTFail("Cancelled suffix delivered")
      } catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
    }.value
    XCTAssertEqual(f.page.state.session.generatedWordReplayHistory?.count, 4)
    let resumed = try f.coordinator.resumeConfigurationRestart(for: f.page)
    let retryResources = try f.coordinator.prepareResources(for: resumed, localFont: .absent, localBackground: .absent)
    var draws = 0
    let ready = try await f.coordinator.preparePractice(for: retryResources,
      random: .init(wordIndex: { draws += 1; return draws }))
    XCTAssertTrue(ready.session.prompt.hasPrefix(original + " "))
    XCTAssertGreaterThan(draws, 0)
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else { throw Failure.publication }
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try f.register.read().revision, disk)
  }
}
