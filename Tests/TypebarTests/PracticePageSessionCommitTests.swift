import Darwin
import Observation
import TypebarSystem
import XCTest
@testable import Typebar

@MainActor final class PracticePageSessionCommitTests: XCTestCase {
  private enum Failure: Error { case commit }
  @MainActor private final class Fixture {
    let page = PracticePageSessionStore(), router = PreferenceConfigurationSaveRouter()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-page-commit-\(UUID())")
    let register: WebsiteConfigFileRegister
    var environmentAction: (() -> Void)?
    var nestedWasBusy = false
    var observedOldAttempt: UUID?
    var observerPrepared: WebsiteConfigCommitCoordinator.SessionPrepared?
    lazy var coordinator: WebsiteConfigCommitCoordinator = {
      let epoch = UUID()
      return .init(router: router, register: register, environment: { [unowned self] in
        environmentAction?()
        return .init(revision: epoch, context: .init(), pointsPerRem: 16)
      })
    }()
    init() throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: page.owner, save: { XCTFail("No legacy save during page commit") })
      page.attach(to: router)
    }
    func prepare(_ json: String = #"{"mode":"custom"}"#) async throws -> WebsiteConfigCommitCoordinator.SessionPrepared {
      let resource = try coordinator.prepareResources(for: coordinator.prepare(json), localFont: .absent, localBackground: .absent)
      return try await coordinator.preparePractice(for: resource, scope: .init(customText: "ab"))
    }
    func close() { try? FileManager.default.removeItem(at: directory) }
  }

  func testStartedNoQuitRejectsBeforeWritingOrPublishing() async throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try await f.prepare()
    var old = PracticePageSessionState()
    old.session = TypingSession(configuration: TestConfiguration.words(2).with(modifiers: [.noQuit]), prompt: "ab cd")
    old.session.insert("a"); f.page.replace(old)
    let disk = try f.register.read().revision
    XCTAssertThrowsError(try f.coordinator.commit(ready, to: f.page, systemIsDark: false))
    XCTAssertEqual(try f.register.read().revision, disk, "Page rejection must precede durable CAS")
    XCTAssertNil(f.coordinator.publication(for: f.page.owner)?.applicationID)
    XCTAssertEqual(f.page.state.session.typed, "a")
  }

  func testSuccessfulCommitHasAlreadyInstalledExactAttemptAndResourcesOnReturn() async throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try await f.prepare(#"{"mode":"custom","funbox":["rot13"],"theme":"dracula"}"#)
    guard case .committed(let publication) = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      throw Failure.commit
    }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, ready.session.automaticInputAttemptID)
    XCTAssertEqual(f.page.state.session.prompt, "no")
    XCTAssertEqual(f.page.state.practice?.scope.customText, "ab")
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    XCTAssertEqual(f.page.state.presentation?.appearance.selection, .builtIn(.dracula))
    XCTAssertEqual(try f.register.read().revision, publication.disk)
  }

  func testDetachedAndForeignPagesCannotCauseADurableWrite() async throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try await f.prepare(), disk = try f.register.read().revision
    let foreign = PracticePageSessionStore(); foreign.attach(to: f.router)
    XCTAssertThrowsError(try f.coordinator.commit(ready, to: foreign, systemIsDark: false))
    f.page.detach()
    XCTAssertThrowsError(try f.coordinator.commit(ready, to: f.page, systemIsDark: false))
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertNil(f.coordinator.publication(for: f.page.owner)?.applicationID)
    f.page.attach(to: f.router)
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("Explicit retry after attachment should remain possible")
    }
  }

  func testOwnerABARetiresPreparedCommitWithoutReplacingPage() async throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try await f.prepare(), disk = try f.register.read().revision
    let oldAttempt = f.page.state.session.automaticInputAttemptID, other = UUID()
    f.router.register(owner: other, save: {}); f.router.activate(owner: other); f.router.activate(owner: f.page.owner)
    guard case .stale = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("Owner ABA must retire the old request")
    }
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, oldAttempt)
  }

  func testBusyFileReleasesPageReservationAndRetriesTheExactAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try await f.prepare(), old = f.page.state.session.automaticInputAttemptID
    let lock = Darwin.open(f.directory.appendingPathComponent(WebsiteConfigFileRegister.lockFilename).path,
      O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    XCTAssertGreaterThanOrEqual(lock, 0); defer { Darwin.close(lock) }
    XCTAssertEqual(typebar_file_lock(lock, LOCK_EX | LOCK_NB), 0)
    guard case .busy = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("Expected bounded busy outcome")
    }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, old)
    XCTAssertEqual(typebar_file_lock(lock, LOCK_UN), 0)
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("Busy must not consume either reservation")
    }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, ready.session.automaticInputAttemptID)
  }

  func testEnvironmentCallbackCannotLockPageAfterAdmissionAndStillWrite() async throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try await f.prepare(), disk = try f.register.read().revision
    f.environmentAction = {
      var locked = f.page.state
      locked.session = TypingSession(configuration: TestConfiguration.words(2).with(modifiers: [.noQuit]), prompt: "ab cd")
      locked.session.insert("a"); f.page.replace(locked)
    }
    XCTAssertThrowsError(try f.coordinator.commit(ready, to: f.page, systemIsDark: false))
    f.environmentAction = nil
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertNil(f.coordinator.publication(for: f.page.owner)?.applicationID)
  }

  func testSynchronousObservationCannotReenterCommitOrOverwriteInstalledAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try await f.prepare(), old = f.page.state.session.automaticInputAttemptID
    f.observerPrepared = ready
    withObservationTracking { _ = f.page.state } onChange: {
      MainActor.assumeIsolated {
        f.observedOldAttempt = f.page.state.session.automaticInputAttemptID
        XCTAssertNil(f.coordinator.publication(for: f.page.owner)?.applicationID,
          "Will-change observation must not see new publication paired with old page")
        f.page.replace(PracticePageSessionState())
        if let prepared = f.observerPrepared,
          let outcome = try? f.coordinator.commit(prepared, to: f.page, systemIsDark: false), case .busy = outcome {
          f.nestedWasBusy = true
        }
      }
    }
    guard case .committed(let publication) = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("Expected the outer application")
    }
    XCTAssertTrue(f.nestedWasBusy); XCTAssertEqual(f.observedOldAttempt, old)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, ready.session.automaticInputAttemptID)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
  }

  func testConflictingWriterKeepsOldPageAndDoesNotLeaveItReserved() async throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try await f.prepare(), old = f.page.state.session.automaticInputAttemptID
    let epoch = UUID()
    let other = WebsiteConfigCommitCoordinator(router: f.router, register: f.register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    guard case .committed(let winner) = try other.commit(other.prepare(#"{"theme":"dracula"}"#)) else {
      return XCTFail("Expected competing durable write")
    }
    guard case .conflict = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("Expected CAS conflict")
    }
    XCTAssertEqual(try f.register.read().revision, winner.disk)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, old)
    var changed = f.page.state; changed.session.insert("a"); f.page.replace(changed)
    XCTAssertEqual(f.page.state.session.typed, "a", "Failed CAS must release the page reservation")
    XCTAssertNil(f.coordinator.publication(for: f.page.owner)?.applicationID)
  }

  func testSessionOnlyProducerIsRejectedBeforeWritingPageCommit() async throws {
    let f = try Fixture(); defer { f.close() }
    let resources = try f.coordinator.prepareResources(for: f.coordinator.prepare("{}"),
      localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.prepareSession(for: resources) { _ in
      TypingSession(configuration: .words(2), prompt: "ab cd")
    }
    let disk = try f.register.read().revision
    XCTAssertThrowsError(try f.coordinator.commit(ready, to: f.page, systemIsDark: false))
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertNil(f.page.state.presentation)
  }

  func testCancellationBeforeCommitKeepsDiskPageAndPublicationUnchanged() async throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try await f.prepare(), disk = try f.register.read().revision
    let old = f.page.state.session.automaticInputAttemptID
    let task = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        _ = try f.coordinator.commit(ready, to: f.page, systemIsDark: false)
        XCTFail("Cancelled commit must not cross the durable boundary")
      } catch is CancellationError {} catch { XCTFail("Expected cancellation, got \(error)") }
    }
    await task.value
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, old)
    XCTAssertNil(f.coordinator.publication(for: f.page.owner)?.applicationID)
  }

  func testRetirementDuringSynchronousObservationIsNotLostAfterCommit() async throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try await f.prepare()
    withObservationTracking { _ = f.page.state } onChange: {
      MainActor.assumeIsolated { f.page.detach() }
    }
    guard case .committed(let publication) = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("Retirement in the post-CAS observation cannot undo an already replaced record")
    }
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    XCTAssertFalse(f.page.acceptsInput(for: ready.session.automaticInputAttemptID),
      "A synchronous retirement must remain effective after the reservation ends")
    let next = try await f.prepare()
    XCTAssertThrowsError(try f.coordinator.commit(next, to: f.page, systemIsDark: false))
    XCTAssertEqual(try f.register.read().revision, publication.disk)
  }
}
