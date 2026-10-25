import XCTest
import Darwin
import TypebarSystem
@testable import Typebar

@MainActor final class WebsiteConfigEditAdmissionTests: XCTestCase {
  private enum Failure: Error { case notCommitted }
  func testLiveThresholdCommitRejectsOtherFieldsAndCompetingRecordWithoutChangingRules() async throws {
    let f = try Fixture(); defer { f.close() }
    _ = try await f.publish()
    let before = f.page.state.session.generationState, revision = try f.register.read().revision
    let unrelated = try f.coordinator.prepareEdit(key: "fontSize", value: .number(2), for: f.page)
    guard case .stale = try f.coordinator.commitLiveThreshold(unrelated, for: f.page) else {
      return XCTFail("Threshold path accepted appearance settings")
    }
    XCTAssertEqual(try f.register.read().revision, revision)
    let prepared = try f.coordinator.prepareEdit(key: "minWpmCustomSpeed", value: .number(20), for: f.page)
    let other = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":7}"#, pointsPerRem: 16, context: .init())
    guard case .committed = try f.register.commit(other, replacing: XCTUnwrap(revision)) else { return XCTFail("Cannot save competing record") }
    let changed = try f.register.read().revision
    guard case .conflict = try f.coordinator.commitLiveThreshold(prepared, for: f.page) else { return XCTFail("Ignored competing record") }
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(try f.register.read().revision, changed)
    XCTAssertTrue(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
  }

  func testBusyThresholdSaveKeepsLiveRulesUntilTheSameProposalCanCommit() async throws {
    let f = try Fixture(); defer { f.close() }
    _ = try await f.publish()
    let before = f.page.state.session.generationState
    let attempt = f.page.state.session.automaticInputAttemptID
    let prepared = try f.coordinator.prepareEdit(key: "minAccCustom", value: .number(0), for: f.page)
    let descriptor = Darwin.open(f.directory.appendingPathComponent(WebsiteConfigFileRegister.lockFilename).path,
      O_RDWR | O_CLOEXEC | O_NOFOLLOW)
    XCTAssertGreaterThanOrEqual(descriptor, 0); defer { Darwin.close(descriptor) }
    XCTAssertEqual(typebar_file_lock(descriptor, LOCK_EX | LOCK_NB), 0)
    guard case .busy = try f.coordinator.commitLiveThreshold(prepared, for: f.page) else { return XCTFail("Ignored busy record") }
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertTrue(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
    XCTAssertEqual(typebar_file_lock(descriptor, LOCK_UN), 0)
    guard case .committed = try f.coordinator.commitLiveThreshold(prepared, for: f.page) else { return XCTFail("Could not retry threshold save") }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.page.state.session.configuration.rules.thresholdSource?.configuration.minimumAccuracyMode, .custom)
  }
  @MainActor private final class Fixture {
    let page = PracticePageSessionStore()
    let router = PreferenceConfigurationSaveRouter()
    let directory: URL
    let register: WebsiteConfigFileRegister
    var context: WebsiteConfigCommitCoordinator.Environment? = .init(revision: UUID(), context: .init(), pointsPerRem: 16)
    var onRead: (() -> Void)?
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
      environment: { [unowned self] in self.onRead?(); return self.context })
    init() throws {
      directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-edit-admission-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: page.owner, save: { XCTFail("Source edits must not write legacy settings") })
      page.attach(to: router)
    }
    func close() { page.detach(); try? FileManager.default.removeItem(at: directory) }
    func publish(_ json: String = #"{"mode":"words","words":3,"time":77}"#) async throws -> WebsiteConfigCommitCoordinator.Publication {
      let resources = try coordinator.prepareResources(for: coordinator.prepare(json), localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resources, scope: .init())
      guard case .committed(let publication) = try coordinator.commit(ready, to: page, systemIsDark: true) else { throw Failure.notCommitted }
      return publication
    }
    func edit(_ base: WebsiteConfigCommitCoordinator.Publication, key: String = "words", value: WebsiteConfigValue = .number(5),
      active: Bool = false) throws -> WebsiteConfigCommitCoordinator.Prepared {
      try coordinator.prepareEdit(key: key, value: value, from: base, testActive: active)
    }
  }

  func testExplicitEditAndNewAttemptCommitUseFullCurrentDraftAndRealPageDestination() async throws {
    let f = try Fixture(); defer { f.close() }
    let base = try await f.publish()
    let oldID = f.page.state.session.automaticInputAttemptID
    let ticket = try f.edit(base)
    var expected = base.draft.projection.runtime; expected["words"] = .number(5)
    XCTAssertEqual(ticket.draft.projection.runtime, expected)
    XCTAssertNil(ticket.draft.prepared)
    XCTAssertEqual(ticket.draft.projection.events.map(\.key), ["words"])
    XCTAssertEqual(try f.register.read().revision, base.disk)
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources, scope: XCTUnwrap(base.practice?.scope))
    guard case .committed(let publication) = try f.coordinator.commit(ready, to: f.page, systemIsDark: true) else { return XCTFail("Edit failed") }
    XCTAssertEqual(try f.register.read().state, .available(expected))
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 5)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, oldID)
    XCTAssertFalse(f.page.acceptsInput(for: oldID))
    XCTAssertEqual(f.page.state.practice?.parameterMemory.duration, 77)
  }

  func testOwnerABARequiresNewEditLeaseButDoesNotMakeLatestBaseUnusable() async throws {
    let f = try Fixture(); defer { f.close() }
    let base = try await f.publish(), old = try f.edit(base)
    let other = UUID(); f.router.register(owner: other, save: {})
    f.router.activate(owner: other)
    XCTAssertThrowsError(try f.edit(base))
    f.router.activate(owner: f.page.owner)
    XCTAssertFalse(base.isCurrentDelivery(owner: f.page.owner, router: f.router))
    guard case .stale = try f.coordinator.commit(old) else { return XCTFail("Old lease survived ABA") }
    let fresh = try f.edit(base)
    let resources = try f.coordinator.prepareResources(for: fresh, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources, scope: XCTUnwrap(base.practice?.scope))
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: true) else {
      return XCTFail("Fresh edit could not re-admit the base for the actual page")
    }
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 5)
  }

  func testForeignAndSupersededBasesCannotWriteAndFailedEditRetiresPriorRequest() async throws {
    let f = try Fixture(), foreign = try Fixture(); defer { f.close(); foreign.close() }
    let first = try await f.publish(), other = try await foreign.publish()
    let pending = try f.edit(first)
    XCTAssertThrowsError(try f.edit(other))
    guard case .stale = try f.coordinator.commit(pending) else { return XCTFail("Failed new request did not retire old edit") }
    let second = try await f.publish(#"{"words":9,"mode":"words"}"#)
    XCTAssertThrowsError(try f.edit(first))
    XCTAssertEqual(try f.register.read().revision, second.disk)
    XCTAssertEqual(f.coordinator.publication(for: f.page.owner)?.applicationID, second.applicationID)
  }

  func testExternalWriterBeforeAndAfterPreparationIsNeverSilentlyMergedOrOverwritten() async throws {
    let f = try Fixture(); defer { f.close() }
    let base = try await f.publish(), pending = try f.edit(base)
    let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"words":11}"#, pointsPerRem: 16, context: .init())
    guard case .committed(let revision) = try f.register.commit(external, replacing: base.disk) else { return XCTFail("External setup failed") }
    XCTAssertThrowsError(try f.edit(base))
    guard case .stale = try f.coordinator.commit(pending) else { return XCTFail("New rejected request did not retire pending edit") }
    XCTAssertEqual(try f.register.read().revision, revision)
    let freshBase = try await f.publish()
    let freshEdit = try f.edit(freshBase)
    guard case .committed(let changed) = try f.register.commit(external, replacing: freshBase.disk) else { return XCTFail("Second writer setup failed") }
    guard case .conflict = try f.coordinator.commit(freshEdit) else { return XCTFail("Commit did not report CAS conflict") }
    XCTAssertEqual(try f.register.read().revision, changed)
  }

  func testEnvironmentCallbackCannotLaunderOwnerABAOrDiskChanges() async throws {
    let f = try Fixture(); defer { f.close() }
    let base = try await f.publish()
    let other = UUID(); f.router.register(owner: other, save: {})
    f.onRead = { f.onRead = nil; f.router.activate(owner: other); f.router.activate(owner: f.page.owner) }
    XCTAssertThrowsError(try f.edit(base))
    let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"time":99}"#, pointsPerRem: 16, context: .init())
    f.onRead = { f.onRead = nil; _ = try? f.register.commit(external, replacing: base.disk) }
    XCTAssertThrowsError(try f.edit(base))
    XCTAssertNotEqual(try f.register.read().revision, base.disk)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, base.applicationID)
  }

  func testMetadataNoQuitAndActualPageNoQuitAreSeparateAdmissions() async throws {
    let f = try Fixture(); defer { f.close() }
    let base = try await f.publish(#"{"mode":"words","words":3,"funbox":["no_quit"]}"#)
    var state = f.page.state
    state.session.insert("a", at: Date(timeIntervalSinceReferenceDate: 900_000_000))
    f.page.replace(state)
    XCTAssertTrue(f.page.state.session.hasStarted)
    XCTAssertThrowsError(try f.edit(base, active: true))
    let audio = try f.edit(base, key: "soundVolume", value: .number(0.1), active: true)
    XCTAssertEqual(audio.draft.projection.runtime["soundVolume"], .number(0.1))
    let resources = try f.coordinator.prepareResources(for: audio, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources, scope: XCTUnwrap(base.practice?.scope))
    XCTAssertThrowsError(try f.coordinator.commit(ready, to: f.page, systemIsDark: true))
    XCTAssertEqual(try f.register.read().revision, base.disk,
      "Admitting an immediate field is not permission to restart an active No Quit page")
  }

  func testRejectedEditRetiresSuspendedResourceProducerBeforeNextRead() async throws {
    let f = try Fixture(); defer { f.close() }
    let base = try await f.publish(), pending = try f.edit(base)
    do {
      _ = try await f.coordinator.prepareResources(for: pending, readLocalFont: {
        XCTAssertThrowsError(try f.edit(base, value: .bool(true)))
        return .absent
      }, readLocalBackground: { XCTFail("Retired producer continued resource reads"); return .absent })
      XCTFail("Retired producer returned resources")
    } catch WebsiteConfigCommitCoordinatorError.stale {}
    XCTAssertEqual(try f.register.read().revision, base.disk)
  }

  func testFinalEnvironmentReadCannotHideAnInterveningFileWrite() async throws {
    let f = try Fixture(); defer { f.close() }
    let base = try await f.publish()
    let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"time":101}"#, pointsPerRem: 16, context: .init())
    var reads = 0
    f.onRead = {
      reads += 1
      if reads == 2 { f.onRead = nil; _ = try? f.register.commit(external, replacing: base.disk) }
    }
    XCTAssertThrowsError(try f.edit(base))
    XCTAssertEqual(reads, 2)
    XCTAssertEqual(try f.register.read().state, .available(external.projection.runtime))
    XCTAssertEqual(f.coordinator.publication(for: f.page.owner)?.applicationID, base.applicationID)
  }

  func testMissingEnvironmentAndOwnerRetireOlderTicketsAndNewContextIsUsedForSetters() async throws {
    let f = try Fixture(); defer { f.close() }
    let base = try await f.publish(), pending = try f.edit(base)
    let initial = f.context
    f.context = nil
    XCTAssertThrowsError(try f.edit(base))
    f.context = initial
    guard case .stale = try f.coordinator.commit(pending) else { return XCTFail("Missing context revived old edit") }
    f.context = .init(revision: UUID(), context: .init(authenticated: true), pointsPerRem: 18)
    let authenticated = try f.edit(base, key: "paceCaret", value: .string("pb"))
    XCTAssertEqual(authenticated.draft.projection.runtime["paceCaret"], .string("pb"))
    f.router.remove(owner: f.page.owner)
    XCTAssertThrowsError(try f.edit(base))
    f.router.register(owner: f.page.owner, save: {})
    guard case .stale = try f.coordinator.commit(authenticated) else { return XCTFail("Missing owner revived old edit") }
    XCTAssertEqual(try f.register.read().revision, base.disk)
  }

  func testReentrantEditIsRejectedWithoutInvalidatingTheOuterPreparation() async throws {
    let f = try Fixture(); defer { f.close() }
    let base = try await f.publish()
    var rejected = false
    f.onRead = {
      f.onRead = nil
      do { _ = try f.edit(base); XCTFail("Reentrant edit was admitted") }
      catch WebsiteConfigCommitCoordinatorError.reentrant { rejected = true }
      catch { XCTFail("Wrong rejection: \(error)") }
    }
    let outer = try f.edit(base)
    XCTAssertTrue(rejected)
    guard case .committed = try f.coordinator.commit(outer) else { return XCTFail("Reentry retired the valid outer request") }
  }
}
