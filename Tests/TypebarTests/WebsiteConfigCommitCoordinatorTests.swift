import XCTest
import Observation
import Darwin
import TypebarSystem
@testable import Typebar

final class WebsiteConfigCommitCoordinatorTests: XCTestCase {
  private enum Failure: Error { case notCommitted }
  @MainActor private final class EnvironmentBox {
    var value: WebsiteConfigCommitCoordinator.Environment? = .init(revision: UUID(), context: .init(), pointsPerRem: 16)
    var onRead: (() -> Void)?
    func read() -> WebsiteConfigCommitCoordinator.Environment? { onRead?(); return value }
    var observedTransition = false
  }
  @MainActor
  private func success(_ outcome: WebsiteConfigCommitCoordinator.Outcome) throws -> WebsiteConfigCommitCoordinator.Publication {
    guard case .committed(let value) = outcome else { XCTFail("Expected publication"); throw Failure.notCommitted }
    return value
  }
  private func stale(_ outcome: WebsiteConfigCommitCoordinator.Outcome, file: StaticString = #filePath, line: UInt = #line) {
    guard case .stale = outcome else { return XCTFail("Expected stale request", file: file, line: line) }
  }

  @MainActor
  private func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-config-commit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
  }

  @MainActor
  func testOwnerChangeCannotCommitOrPublishPreparedConfiguration() throws {
    try withDirectory { directory in
      let router = PreferenceConfigurationSaveRouter(), a = UUID(), b = UUID()
      router.register(owner: a, save: {})
      let register = WebsiteConfigFileRegister(directory: directory)
      let revision = UUID()
      let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
        environment: { .init(revision: revision, context: .init(), pointsPerRem: 16) })
      let prepared = try coordinator.prepare(#"{"time":41}"#)
      router.register(owner: b, save: {})
      router.activate(owner: b)
      guard case .stale = try coordinator.commit(prepared) else { return XCTFail("Retired owner committed") }
      XCTAssertNil(coordinator.publication(for: a))
      XCTAssertNil(coordinator.publication(for: b))
      XCTAssertEqual(try register.read().state, .missing)
    }
  }

  @MainActor
  func testCompleteValuePublishesOnlyForItsOwnerAfterRealRecordCommit() throws {
    try withDirectory { directory in
      let router = PreferenceConfigurationSaveRouter(), owner = UUID(), other = UUID(), box = EnvironmentBox()
      var legacyDeliveries = 0
      router.register(owner: owner, save: { legacyDeliveries += 1 })
      let register = WebsiteConfigFileRegister(directory: directory)
      let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register, environment: box.read)
      let ticket = try coordinator.prepare(#"{"time":41,"autoSwitchTheme":true,"customTheme":true,"funbox":["rot13","rot13"],"quoteLength":[0,0,1],"customBackgroundFilter":[-0,1e400,1,1]}"#)
      XCTAssertNil(coordinator.publication(for: owner))
      XCTAssertEqual(try register.read().state, .missing)
      let published = try success(coordinator.commit(ticket))
      XCTAssertEqual(published.owner, owner)
      XCTAssertEqual(published.environmentRevision, box.value?.revision)
      XCTAssertEqual(try register.read().revision, published.disk)
      XCTAssertEqual(try register.read().state, .available(published.draft.projection.runtime))
      XCTAssertEqual(coordinator.publication(for: owner)?.draft.projection.runtime["time"], .number(41))
      XCTAssertNil(coordinator.publication(for: other))
      XCTAssertEqual(published.draft.generators.requestedModifiers, [.rot13, .rot13])
      XCTAssertEqual(published.draft.quoteSelection.groups, [0, 0, 1])
      XCTAssertEqual(published.draft.pagePreferences.backgroundFilter.blurRem.sign, .minus)
      XCTAssertEqual(published.draft.pagePreferences.backgroundFilter.brightness, .infinity)
      XCTAssertTrue(published.draft.themes.followsSystem)
      XCTAssertTrue(published.draft.themes.customEnabled)
      XCTAssertEqual(legacyDeliveries, 0)
      stale(try coordinator.commit(ticket))
    }
  }

  @MainActor
  func testActualRouterLeasesCoverABAReplacementRemovalWithoutStealingFocus() throws {
    let router = PreferenceConfigurationSaveRouter(), a = UUID(), b = UUID()
    XCTAssertNil(router.captureLease())
    router.register(owner: a, save: {})
    let original = try XCTUnwrap(router.captureLease())
    router.register(owner: b, save: {})
    XCTAssertTrue(router.isCurrent(original))
    router.activate(owner: a)
    router.activate(owner: UUID())
    router.remove(owner: b)
    XCTAssertTrue(router.isCurrent(original))
    router.register(owner: b, save: {})
    router.activate(owner: b); router.activate(owner: a)
    XCTAssertFalse(router.isCurrent(original))
    let beforeReplacement = try XCTUnwrap(router.captureLease())
    router.register(owner: a, save: {})
    XCTAssertFalse(router.isCurrent(beforeReplacement))
    let beforeRemoval = try XCTUnwrap(router.captureLease())
    let other = PreferenceConfigurationSaveRouter()
    other.register(owner: a, save: {})
    XCTAssertFalse(other.isCurrent(beforeRemoval))
    let observed = EnvironmentBox()
    withObservationTracking { _ = router.fontFamilyName } onChange: {
      MainActor.assumeIsolated {
        observed.observedTransition = true
        XCTAssertNil(router.captureLease())
        XCTAssertFalse(router.isCurrent(beforeRemoval))
      }
    }
    router.register(owner: a, fontFamilyName: { "Owned family" }, save: {})
    XCTAssertTrue(observed.observedTransition)
    router.remove(owner: a)
    XCTAssertFalse(router.isCurrent(beforeRemoval))
    XCTAssertEqual(router.captureLease()?.owner, b)
  }

  @MainActor
  func testContextResourceEpochScaleAndUnavailableStateInvalidateRequests() throws {
    try withDirectory { directory in
      let router = PreferenceConfigurationSaveRouter(), owner = UUID(), box = EnvironmentBox()
      router.register(owner: owner, save: {})
      let register = WebsiteConfigFileRegister(directory: directory)
      let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register, environment: box.read)
      let original = try XCTUnwrap(box.value)
      let alternatives: [WebsiteConfigCommitCoordinator.Environment?] = [
        .init(revision: UUID(), context: original.context, pointsPerRem: 16),
        .init(revision: original.revision, context: .init(authenticated: true), pointsPerRem: 16),
        .init(revision: original.revision, context: original.context, pointsPerRem: 18), nil]
      for value in alternatives {
        box.value = original
        let ticket = try coordinator.prepare(#"{"time":41}"#)
        box.value = value
        stale(try coordinator.commit(ticket))
        box.value = original
        stale(try coordinator.commit(ticket), file: #filePath, line: #line)
        XCTAssertEqual(try register.read().state, .missing)
        XCTAssertNil(coordinator.publication(for: owner))
      }
    }
  }

  @MainActor
  func testNewIntentCancellationAndForeignCoordinatorCannotResurrectRequests() throws {
    try withDirectory { directory in
      let router = PreferenceConfigurationSaveRouter(), owner = UUID(), box = EnvironmentBox()
      router.register(owner: owner, save: {})
      let register = WebsiteConfigFileRegister(directory: directory)
      let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register, environment: box.read)
      let old = try coordinator.prepare(#"{"time":41}"#)
      let new = try coordinator.prepare(#"{"time":42}"#)
      stale(try coordinator.commit(old))
      XCTAssertFalse(coordinator.cancel(old))
      let other = WebsiteConfigCommitCoordinator(router: router, register: register, environment: box.read)
      stale(try other.commit(new))
      XCTAssertFalse(other.cancel(new))
      _ = try success(coordinator.commit(new))
      let cancelled = try coordinator.prepare(#"{"time":43}"#)
      XCTAssertTrue(coordinator.cancel(cancelled))
      stale(try coordinator.commit(cancelled))
      let beforeBadInput = try coordinator.prepare(#"{"time":44}"#)
      XCTAssertThrowsError(try coordinator.prepare("{"))
      stale(try coordinator.commit(beforeBadInput))
      XCTAssertEqual(coordinator.publication(for: owner)?.draft.projection.runtime["time"], .number(42))
    }
  }

  @MainActor
  func testDiskConflictAndOpaqueStateKeepPreviousPublication() throws {
    try withDirectory { directory in
      let router = PreferenceConfigurationSaveRouter(), owner = UUID(), box = EnvironmentBox()
      router.register(owner: owner, save: {})
      let register = WebsiteConfigFileRegister(directory: directory)
      let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register, environment: box.read)
      _ = try success(coordinator.commit(coordinator.prepare(#"{"time":31}"#)))
      let pending = try coordinator.prepare(#"{"time":32}"#)
      let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"time":33}"#, pointsPerRem: 16, context: .init())
      guard case .committed = try register.commit(external, replacing: XCTUnwrap(register.read().revision)) else { return XCTFail("External commit failed") }
      guard case .conflict = try coordinator.commit(pending) else { return XCTFail("Ignored disk conflict") }
      XCTAssertEqual(coordinator.publication(for: owner)?.draft.projection.runtime["time"], .number(31))
      XCTAssertEqual(try register.read().state, .available(external.projection.runtime))
      let another = try coordinator.prepare(#"{"time":34}"#)
      let file = directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
      let opaque = Data("Owned unreadable future state".utf8)
      try opaque.write(to: file)
      guard case .unavailable = try coordinator.commit(another) else { return XCTFail("Opaque bytes replaced") }
      XCTAssertEqual(try Data(contentsOf: file), opaque)
      XCTAssertEqual(coordinator.publication(for: owner)?.draft.projection.runtime["time"], .number(31))
      XCTAssertThrowsError(try coordinator.prepare("{}"))
    }
  }

  @MainActor
  func testBusyAndIOFailurePermitOnlyExplicitRetryWithoutPublishingPartialState() throws {
    try withDirectory { directory in
      let router = PreferenceConfigurationSaveRouter(), owner = UUID(), box = EnvironmentBox()
      router.register(owner: owner, save: {})
      let register = WebsiteConfigFileRegister(directory: directory)
      let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register, environment: box.read)
      _ = try success(coordinator.commit(coordinator.prepare(#"{"time":31}"#)))
      let ticket = try coordinator.prepare(#"{"time":32}"#)
      let lock = Darwin.open(directory.appendingPathComponent(WebsiteConfigFileRegister.lockFilename).path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
      XCTAssertGreaterThanOrEqual(lock, 0)
      defer { Darwin.close(lock) }
      XCTAssertEqual(typebar_file_lock(lock, LOCK_EX | LOCK_NB), 0)
      guard case .busy = try coordinator.commit(ticket) else { return XCTFail("Lock busy ignored") }
      XCTAssertEqual(coordinator.publication(for: owner)?.draft.projection.runtime["time"], .number(31))
      XCTAssertEqual(typebar_file_lock(lock, LOCK_UN), 0)
      _ = try success(coordinator.commit(ticket))
      let retry = try coordinator.prepare(#"{"time":33}"#)
      let before = try Data(contentsOf: directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename))
      guard geteuid() != 0 else { throw XCTSkip("Permission denial requires non-root") }
      try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
      defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
      XCTAssertThrowsError(try coordinator.commit(retry))
      XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)), before)
      XCTAssertEqual(coordinator.publication(for: owner)?.draft.projection.runtime["time"], .number(32))
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      _ = try success(coordinator.commit(retry))
    }
  }

  @MainActor
  func testProviderOwnershipChangeAndReentrantOperationsCannotCrossCommitBoundary() throws {
    try withDirectory { directory in
      let router = PreferenceConfigurationSaveRouter(), a = UUID(), b = UUID(), box = EnvironmentBox()
      router.register(owner: a, save: {}); router.register(owner: b, save: {})
      let register = WebsiteConfigFileRegister(directory: directory)
      let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register, environment: box.read)
      let moved = try coordinator.prepare(#"{"time":41}"#)
      box.onRead = { box.onRead = nil; router.activate(owner: b) }
      stale(try coordinator.commit(moved))
      XCTAssertEqual(try register.read().state, .missing)
      router.activate(owner: a)
      let ticket = try coordinator.prepare(#"{"time":42}"#)
      box.onRead = {
        box.onRead = nil
        do {
          _ = try coordinator.prepare("{}")
          XCTFail("Reentrant preparation admitted")
        } catch {
          XCTAssertEqual(error as? WebsiteConfigCommitCoordinatorError, .reentrant)
        }
        do {
          guard case .busy = try coordinator.commit(ticket) else { return XCTFail("Reentrant commit admitted") }
        } catch { XCTFail("Unexpected reentrant error") }
        XCTAssertFalse(coordinator.cancel(ticket))
      }
      _ = try success(coordinator.commit(ticket))
      XCTAssertEqual(coordinator.publication(for: a)?.draft.projection.runtime["time"], .number(42))
    }
  }

  @MainActor
  func testPreparationRequiresOwnerStableEnvironmentAndRepresentableWholeDraft() throws {
    try withDirectory { directory in
      let router = PreferenceConfigurationSaveRouter(), owner = UUID(), box = EnvironmentBox()
      let register = WebsiteConfigFileRegister(directory: directory)
      let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register, environment: box.read)
      XCTAssertThrowsError(try coordinator.prepare("{}"))
      router.register(owner: owner, save: {})
      box.value = nil
      XCTAssertThrowsError(try coordinator.prepare("{}"))
      box.value = .init(revision: UUID(), context: .init(), pointsPerRem: 16)
      XCTAssertThrowsError(try coordinator.prepare(#"{"fontSize":1e400}"#))
      box.onRead = { box.value = .init(revision: UUID(), context: .init(), pointsPerRem: 16) }
      XCTAssertThrowsError(try coordinator.prepare("{}"))
      box.onRead = nil
      XCTAssertEqual(try register.read().state, .missing)
      XCTAssertNil(coordinator.publication(for: owner))
    }
  }
}
