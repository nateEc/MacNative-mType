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
      let ready = try await coordinator.preparePractice(for: resources, scope: .init(customText: "ab cd"))
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
}
