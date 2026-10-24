import Observation
import XCTest
@testable import Typebar

@MainActor final class PracticePageLegacyReturnTests: XCTestCase {
  @MainActor private final class Fixture {
    let page = PracticePageSessionStore(), router = PreferenceConfigurationSaveRouter()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-legacy-return-\(UUID())")
    let register: WebsiteConfigFileRegister
    let epoch = UUID()
    var observations = 0
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
      environment: { [unowned self] in .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    init() throws {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: page.owner, save: {})
      page.attach(to: router)
    }
    func publish() async throws {
      let resources = try coordinator.prepareResources(for: coordinator.prepare(#"{"mode":"words","words":4}"#),
        localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resources, scope: .init())
      guard case .committed = try coordinator.commit(ready, to: page, systemIsDark: false) else {
        throw WebsiteConfigImportWorkflowError.conflict
      }
      try page.bindRestartController(using: coordinator)
    }
    func nativeSeed() {
      var state = page.state
      state.session = TypingSession(configuration: .words(3), prompt: "ab cd ef")
      page.replace(state)
    }
    func close() { page.detach(); try? FileManager.default.removeItem(at: directory) }
  }

  func testReturnKeepsRecordAndLedgerAndRequiresANewNativeAttemptBeforeOpeningInput() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    var history = f.page.state
    history.priorAttemptLedger.recordRestart(engagedDuration: 2, accuracy: 90, savingEnabled: true)
    f.page.replace(history)
    let disk = try f.register.read().revision
    let old = f.page.state.session.automaticInputAttemptID
    let ledger = f.page.state.priorAttemptLedger
    XCTAssertGreaterThan(ledger.restartCount, 0)
    let permit = try f.page.beginLegacyReturn()
    XCTAssertNil(f.page.state.practice); XCTAssertNil(f.page.state.presentation)
    XCTAssertNil(f.page.restartController)
    XCTAssertFalse(f.page.acceptsInput(for: old))
    XCTAssertTrue(f.page.isReturningToTypebarSettings)
    XCTAssertThrowsError(try f.page.finishLegacyReturn(permit))
    XCTAssertTrue(f.page.isReturningToTypebarSettings)
    f.nativeSeed()
    try f.page.finishLegacyReturn(permit)
    XCTAssertFalse(f.page.isReturningToTypebarSettings)
    XCTAssertTrue(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
    XCTAssertFalse(f.page.acceptsInput(for: old))
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testActiveAttemptIsNotDiscardedEvenWithoutNoQuit() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let publication = f.page.state.presentation?.publication.applicationID
    XCTAssertThrowsError(try f.page.beginLegacyReturn()) { error in
      guard case PracticePageSessionStateError.locked = error else { return XCTFail("Unexpected: \(error)") }
    }
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication)
    XCTAssertFalse(f.page.isReturningToTypebarSettings)
  }

  func testRetryRetiresOldPermitAndDetachRefusesCompletion() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let old = try f.page.beginLegacyReturn()
    let current = try f.page.beginLegacyReturn()
    f.nativeSeed()
    XCTAssertThrowsError(try f.page.finishLegacyReturn(old))
    XCTAssertTrue(f.page.isReturningToTypebarSettings)
    f.page.detach()
    XCTAssertThrowsError(try f.page.finishLegacyReturn(current))
    XCTAssertFalse(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
  }

  func testObservationCannotAdmitCachedInputWhileClearingProfileOrOpeningGate() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let old = f.page.state.session.automaticInputAttemptID
    withObservationTracking { _ = f.page.state } onChange: {
      MainActor.assumeIsolated { f.observations += 1; XCTAssertFalse(f.page.acceptsInput(for: old)) }
    }
    let permit = try f.page.beginLegacyReturn()
    f.nativeSeed()
    let native = f.page.state.session.automaticInputAttemptID
    withObservationTracking { _ = f.page.isReturningToTypebarSettings } onChange: {
      MainActor.assumeIsolated { f.observations += 1; XCTAssertFalse(f.page.acceptsInput(for: native)) }
    }
    try f.page.finishLegacyReturn(permit)
    XCTAssertEqual(f.observations, 2)
    XCTAssertTrue(f.page.acceptsInput(for: native))
  }

  func testRestoringAWholeProfileRetiresAnIncompleteReturn() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let permit = try f.page.beginLegacyReturn()
    try await f.publish()
    XCTAssertFalse(f.page.isReturningToTypebarSettings)
    XCTAssertNotNil(f.page.state.practice)
    XCTAssertThrowsError(try f.page.finishLegacyReturn(permit))
    XCTAssertTrue(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
  }

  func testFailedOrStartedNativeCandidateDoesNotOpenTheReturnGate() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let permit = try f.page.beginLegacyReturn()
    var state = f.page.state
    state.session = TypingSession(configuration: .words(3), prompt: "", initializationFailure: "owned QA failure")
    f.page.replace(state)
    XCTAssertThrowsError(try f.page.finishLegacyReturn(permit))
    f.nativeSeed()
    state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    XCTAssertThrowsError(try f.page.finishLegacyReturn(permit))
    XCTAssertTrue(f.page.isReturningToTypebarSettings)
  }

  func testOwnerABARefusesAnOldReturnPermit() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let permit = try f.page.beginLegacyReturn()
    f.nativeSeed()
    let other = UUID()
    f.router.register(owner: other, save: {})
    f.router.activate(owner: other); f.router.activate(owner: f.page.owner)
    XCTAssertThrowsError(try f.page.finishLegacyReturn(permit))
    XCTAssertTrue(f.page.isReturningToTypebarSettings)
    let fresh = try f.page.beginLegacyReturn()
    f.nativeSeed(); try f.page.finishLegacyReturn(fresh)
    XCTAssertFalse(f.page.isReturningToTypebarSettings)
  }
}
