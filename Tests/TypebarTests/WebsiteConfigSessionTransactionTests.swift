import Foundation
import Darwin
import TypebarSystem
import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigSessionTransactionTests: XCTestCase {
  private enum Failure: Error { case generation, notCommitted, gateNotEntered, attempt(Int) }
  @MainActor private final class Fixture {
    let directory: URL
    let owner = UUID()
    let router = PreferenceConfigurationSaveRouter()
    let register: WebsiteConfigFileRegister
    var environment = WebsiteConfigCommitCoordinator.Environment(revision: UUID(), context: .init(), pointsPerRem: 16)
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
      environment: { [unowned self] in self.environment })
    init() throws {
      directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-session-transaction-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: owner, save: { XCTFail("Must not write legacy preferences") })
    }
    func close() { try? FileManager.default.removeItem(at: directory) }
    func resources(_ json: String = #"{"mode":"custom","funbox":["ddoouubblleedd","ddoouubblleedd","rot13"]}"#)
      throws -> WebsiteConfigCommitCoordinator.ResourcesPrepared {
      try coordinator.prepareResources(for: coordinator.prepare(json), localFont: .absent, localBackground: .absent)
    }
  }
  @MainActor private final class Gate {
    var pending: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { pending = $0 } }
    func release() { let current = pending; pending = nil; current?.resume() }
    func entered() async throws {
      for _ in 0..<1000 where pending == nil { await Task.yield() }
      guard pending != nil else { throw Failure.gateNotEntered }
    }
  }
  /// A deliberately scoped producer using real typed groups and factory.
  /// This fixture does not claim to implement all production source selection.
  private static func generate(_ draft: WebsiteConfigNativeDraft) throws -> TypingSession {
    var config = draft.testParameters.applying(to: .words(3), parameterMemory: .defaults)
    config = draft.inputRules.applying(to: draft.behavior.applying(to: config))
    config = config.with(modifiers: draft.generators.requestedModifiers)
    config = try draft.generators.applyingTextOrder(to: config)
    return TestSessionFactory.make(configuration: config, customText: "ab")
  }
  private func publication(_ result: WebsiteConfigCommitCoordinator.Outcome) throws -> WebsiteConfigCommitCoordinator.Publication {
    guard case .committed(let result) = result else { throw Failure.notCommitted }
    return result
  }

  func testInitializationExhaustionReturnsLastActualErrorAndDoesNotWriteCandidate() async throws {
    let f = try Fixture(); defer { f.close() }
    let resources = try f.resources(#"{"mode":"quote","quoteLength":[0]}"#)
    var reads = 0
    do {
      _ = try await f.coordinator.preparePractice(for: resources, scope: .init(), loadQuotes: { _ in
        reads += 1; throw Failure.attempt(reads)
      })
      XCTFail("Three failed generations delivered a candidate")
    } catch Failure.attempt(let attempt) { XCTAssertEqual(attempt, 3) }
    XCTAssertEqual(reads, 3)
    XCTAssertEqual(try f.register.read().state, .missing)
    XCTAssertNil(f.coordinator.publication(for: f.owner))
  }

  func testExternalEmptyGenerationAndReaderFailureRecoverWithinTheSameBudget() async throws {
    let f = try Fixture(); defer { f.close() }
    let resources = try f.resources(#"{"mode":"words","words":3,"funbox":["wikipedia"]}"#)
    var reads = 0
    let ready = try await f.coordinator.preparePractice(for: resources, scope: .init(), loadExternal: { source, config in
      reads += 1
      XCTAssertEqual(source, .encyclopedia)
      XCTAssertEqual(config.wordLimit, 3)
      if reads == 2 { throw Failure.generation }
      return .init(source: source, initial: .init(text: reads == 1 ? "" : "ab", noSpaceBoundarySource: nil),
        continuation: .init(text: "cd ef", noSpaceBoundarySource: nil), attribution: "Owned retry source")
    })
    XCTAssertEqual(reads, 3)
    XCTAssertEqual(ready.practice?.external?.attribution, "Owned retry source")
    XCTAssertTrue(ready.session.prompt.contains("ab"))
    XCTAssertEqual(try f.register.read().state, .missing)
    XCTAssertNil(f.coordinator.publication(for: f.owner))
  }

  func testCancelledFailedReaderDoesNotStartAnotherInitialization() async throws {
    let f = try Fixture(); defer { f.close() }
    let resources = try f.resources(#"{"mode":"quote","quoteLength":[0]}"#)
    var reads = 0
    await Task { @MainActor in
      do {
        _ = try await f.coordinator.preparePractice(for: resources, scope: .init(), loadQuotes: { _ in
          reads += 1
          withUnsafeCurrentTask { $0?.cancel() }
          throw Failure.generation
        })
        XCTFail("Cancelled producer delivered")
      } catch is CancellationError {} catch { XCTFail("Cancellation lost precedence: \(error)") }
    }.value
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(try f.register.read().state, .missing)
  }

  func testRealAttemptAndResourcesAppearTogetherOnlyAtSuccessfulCommit() async throws {
    let f = try Fixture(); defer { f.close() }
    let resources = try f.resources()
    let ready = try await f.coordinator.prepareSession(for: resources) { draft in
      XCTAssertNil(f.coordinator.publication(for: f.owner))
      XCTAssertEqual(try f.register.read().state, .missing)
      await Task.yield()
      return try Self.generate(draft)
    }
    XCTAssertEqual(ready.session.prompt, "nnnnoooo")
    XCTAssertNil(f.coordinator.publication(for: f.owner))
    XCTAssertEqual(try f.register.read().state, .missing)
    let published = try publication(f.coordinator.commit(ready))
    let seed = try XCTUnwrap(published.session)
    XCTAssertEqual(seed.automaticInputAttemptID, ready.session.automaticInputAttemptID)
    XCTAssertEqual(seed.configuration, ready.session.configuration)
    XCTAssertEqual(seed.prompt, "nnnnoooo")
    XCTAssertNotNil(published.font); XCTAssertNotNil(published.background)
    XCTAssertEqual(try f.register.read().state, .available(published.draft.projection.runtime))
    guard case .stale = try f.coordinator.commit(ready) else { return XCTFail("Attempt committed twice") }
  }

  func testSessionAdmissionPreventsResourceOnlyOrBareCommitDuringGeneration() async throws {
    let f = try Fixture(); defer { f.close() }
    let ticket = try f.coordinator.prepare(#"{"mode":"custom"}"#)
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.prepareSession(for: resources) { draft in
      guard case .stale = try f.coordinator.commit(resources) else { throw Failure.notCommitted }
      guard case .stale = try f.coordinator.commit(ticket) else { throw Failure.notCommitted }
      XCTAssertEqual(try f.register.read().state, .missing)
      return try Self.generate(draft)
    }
    _ = try publication(f.coordinator.commit(ready))
  }

  func testLaterSessionPreparationRetiresEarlierCandidateEvenIfItFails() async throws {
    let f = try Fixture(); defer { f.close() }
    let resources = try f.resources()
    let old = try await f.coordinator.prepareSession(for: resources, generate: Self.generate)
    do {
      _ = try await f.coordinator.prepareSession(for: resources) { _ in throw Failure.generation }
      XCTFail("Lost generation failure")
    } catch Failure.generation {}
    guard case .stale = try f.coordinator.commit(old) else { return XCTFail("Superseded candidate committed") }
    XCTAssertEqual(try f.register.read().state, .missing)
    let fresh = try await f.coordinator.prepareSession(for: resources, generate: Self.generate)
    _ = try publication(f.coordinator.commit(fresh))
  }

  func testCancelledGenerationCannotPublishEvenWhenProducerIgnoresCancellation() async throws {
    let f = try Fixture(), gate = Gate(); defer { gate.release(); f.close() }
    let resources = try f.resources()
    let pending = Task { @MainActor in
      _ = try await f.coordinator.prepareSession(for: resources) { draft in
        await gate.wait(); return try Self.generate(draft)
      }
    }
    defer { pending.cancel() }
    try await gate.entered(); pending.cancel(); gate.release()
    do { _ = try await pending.value; XCTFail("Cancelled candidate escaped") }
    catch is CancellationError {}
    XCTAssertNil(f.coordinator.publication(for: f.owner))
    XCTAssertEqual(try f.register.read().state, .missing)
  }

  func testOwnerEnvironmentResourcesRequestAndCancellationFenceLateValuesAndErrors() async throws {
    for change in 0..<5 {
      for lateError in [false, true] {
        let f = try Fixture(); defer { f.close() }
        let previous = try publication(f.coordinator.commit(f.resources()))
        let ticket = try f.coordinator.prepare(#"{"mode":"custom","funbox":["ddoouubblleedd","ddoouubblleedd","rot13"]}"#)
        let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
        do {
          _ = try await f.coordinator.prepareSession(for: resources) { draft in
            switch change {
            case 0:
              let other = UUID(); f.router.register(owner: other, save: {})
              f.router.activate(owner: other); f.router.activate(owner: f.owner)
            case 1: f.environment = .init(revision: UUID(), context: .init(), pointsPerRem: 16)
            case 2:
              _ = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
            case 3: _ = try f.coordinator.prepare(#"{"mode":"words","words":7}"#)
            default: XCTAssertTrue(f.coordinator.cancel(resources))
            }
            await Task.yield()
            if lateError { throw Failure.generation }
            return try Self.generate(draft)
          }
          XCTFail("Stale generation escaped: \(change), \(lateError)")
        } catch WebsiteConfigCommitCoordinatorError.stale {}
        XCTAssertEqual(f.coordinator.publication(for: f.owner)?.applicationID, previous.applicationID)
        XCTAssertEqual(try f.register.read().revision, previous.disk)
      }
    }
  }

  func testReplacementSessionWinsOverLateValueOrErrorWithoutChangingResourceTicket() async throws {
    for lateError in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let resources = try f.resources()
      var replacement: WebsiteConfigCommitCoordinator.SessionPrepared?
      do {
        _ = try await f.coordinator.prepareSession(for: resources) { draft in
          replacement = try await f.coordinator.prepareSession(for: resources, generate: Self.generate)
          if lateError { throw Failure.generation }
          return try Self.generate(draft)
        }
        XCTFail("Old generation escaped")
      } catch WebsiteConfigCommitCoordinatorError.stale {}
      let ready = try XCTUnwrap(replacement)
      let published = try publication(f.coordinator.commit(ready))
      XCTAssertEqual(published.session?.automaticInputAttemptID, ready.session.automaticInputAttemptID)
    }
  }

  func testFailedStartedAndCompletedAttemptsAreNotPreparedSeeds() async throws {
    let f = try Fixture(); defer { f.close() }
    let resources = try f.resources()
    for kind in 0..<3 {
      do {
        _ = try await f.coordinator.prepareSession(for: resources) { draft in
          var session = try Self.generate(draft)
          switch kind {
          case 0: session = .init(configuration: session.configuration, prompt: "", initializationFailure: "Owned fixture failure")
          case 1: session.insert("n")
          default: session.insert("nnnnoooo")
          }
          return session
        }
        XCTFail("Non-fresh attempt admitted: \(kind)")
      } catch WebsiteConfigCommitCoordinatorError.sessionNotReady {}
    }
    XCTAssertEqual(try f.register.read().state, .missing)
    let ready = try await f.coordinator.prepareSession(for: resources, generate: Self.generate)
    _ = try publication(f.coordinator.commit(ready))
  }

  func testCancelOnlyCurrentSessionCandidateAndRejectForeignCoordinator() async throws {
    let f = try Fixture(), other = try Fixture(); defer { f.close(); other.close() }
    let resources = try f.resources()
    let old = try await f.coordinator.prepareSession(for: resources, generate: Self.generate)
    let fresh = try await f.coordinator.prepareSession(for: resources, generate: Self.generate)
    XCTAssertFalse(f.coordinator.cancel(old))
    guard case .stale = try other.coordinator.commit(fresh) else { return XCTFail("Foreign seed committed") }
    XCTAssertTrue(f.coordinator.cancel(fresh))
    guard case .stale = try f.coordinator.commit(fresh) else { return XCTFail("Cancelled seed committed") }
    XCTAssertEqual(try f.register.read().state, .missing)
    XCTAssertEqual(try other.register.read().state, .missing)
  }

  func testBusyRetryKeepsSameAttemptAndDiskConflictPreservesCurrentPublicationAndPractice() async throws {
    let f = try Fixture(); defer { f.close() }
    let initial = try await f.coordinator.prepareSession(for: f.resources(), generate: Self.generate)
    let previous = try publication(f.coordinator.commit(initial))
    var active = try XCTUnwrap(previous.session); active.insert("n")
    let resources = try f.resources(#"{"mode":"custom","time":41}"#)
    let ready = try await f.coordinator.prepareSession(for: resources, generate: Self.generate)
    let lock = Darwin.open(f.directory.appendingPathComponent(WebsiteConfigFileRegister.lockFilename).path,
      O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    XCTAssertGreaterThanOrEqual(lock, 0); defer { Darwin.close(lock) }
    XCTAssertEqual(typebar_file_lock(lock, LOCK_EX | LOCK_NB), 0)
    guard case .busy = try f.coordinator.commit(ready) else { return XCTFail("Ignored busy file lock") }
    XCTAssertEqual(f.coordinator.publication(for: f.owner)?.applicationID, previous.applicationID)
    XCTAssertEqual(typebar_file_lock(lock, LOCK_UN), 0)
    let published = try publication(f.coordinator.commit(ready))
    XCTAssertEqual(published.session?.automaticInputAttemptID, ready.session.automaticInputAttemptID)
    let conflict = try await f.coordinator.prepareSession(for: f.resources(), generate: Self.generate)
    let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"time":43}"#, pointsPerRem: 16, context: .init())
    guard case .committed = try f.register.commit(external, replacing: published.disk) else { return XCTFail("External fixture write failed") }
    guard case .conflict = try f.coordinator.commit(conflict) else { return XCTFail("Ignored disk conflict") }
    XCTAssertEqual(f.coordinator.publication(for: f.owner)?.applicationID, published.applicationID)
    XCTAssertEqual(try f.register.read().state, .available(external.projection.runtime))
    XCTAssertEqual(active.typed, "n")
    XCTAssertEqual(active.automaticInputAttemptID, initial.session.automaticInputAttemptID)
  }

  func testCancellationWinsOverLateProducerErrorAndBeforeCommitWithoutConsumingSeed() async throws {
    let f = try Fixture(), gate = Gate(); defer { gate.release(); f.close() }
    let resources = try f.resources()
    let pending = Task { @MainActor in
      _ = try await f.coordinator.prepareSession(for: resources) { _ in
        await gate.wait(); throw Failure.generation
      }
    }
    defer { pending.cancel() }
    try await gate.entered(); pending.cancel(); gate.release()
    do { try await pending.value; XCTFail("Lost cancellation") } catch is CancellationError {}
    let ready = try await f.coordinator.prepareSession(for: resources, generate: Self.generate)
    let commit = Task { @MainActor in
      await gate.wait()
      _ = try f.coordinator.commit(ready)
    }
    defer { commit.cancel() }
    try await gate.entered(); commit.cancel(); gate.release()
    do { try await commit.value; XCTFail("Cancelled task committed") } catch is CancellationError {}
    XCTAssertEqual(try f.register.read().state, .missing)
    _ = try publication(f.coordinator.commit(ready))
  }
}
