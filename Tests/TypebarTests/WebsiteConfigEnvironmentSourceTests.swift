import Foundation
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigEnvironmentSourceTests: XCTestCase {
  private enum LiveReadFailure: Error { case expected }
  func testSynchronousLiveReadRetainsFreshEpochAndRestoresOrdinaryLockAfterThrowing() async throws {
    try await withModels { settings, account in
      let source = WebsiteConfigEnvironmentSource(settings: settings, account: account,
        pointsPerRem: 16, documentComplete: true, development: false)
      defer { source.stop() }
      let original = try XCTUnwrap(source.read())
      let lock = UUID(); settings.setNoQuitConfigurationLock(true, for: lock)
      defer { settings.setNoQuitConfigurationLock(false, for: lock) }
      XCTAssertNil(source.read())
      let fresh = try source.withLiveBehaviorRead { try XCTUnwrap(source.read()) }
      XCTAssertNotEqual(fresh.revision, original.revision)
      XCTAssertNil(source.read(), "Live context must not reopen ordinary imports")
      for _ in 0..<20 { await Task.yield() }
      XCTAssertEqual(source.withLiveBehaviorRead { source.read() }, fresh,
        "Retired queued resampling must not rotate a freshly captured live epoch")
      XCTAssertThrowsError(try source.withLiveBehaviorRead { () throws -> Void in
        XCTAssertEqual(source.read(), fresh); throw LiveReadFailure.expected
      })
      XCTAssertNil(source.read(), "A thrown command must restore the ordinary lock")
      source.stop()
      XCTAssertNil(source.withLiveBehaviorRead { source.read() }, "Read scope cannot revive stopped sources")
    }
  }
  private func withModels(_ body: (AppSettings, AccountSession) async throws -> Void) async throws {
    let suite = "typebar.config-environment.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try await body(AppSettings(defaults: defaults, localBackgroundStore: .inMemory()),
      AccountSession(defaults: defaults))
  }

  private func settled(_ source: WebsiteConfigEnvironmentSource) async throws -> WebsiteConfigCommitCoordinator.Environment {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while ContinuousClock.now < deadline {
      if let value = source.read() { return value }
      await Task.yield()
    }
    return try XCTUnwrap(source.read(), "Environment did not settle")
  }

  func testLegacySettingABAInvalidatesSynchronouslyAndRearms() async throws {
    try await withModels { settings, account in
      let source = WebsiteConfigEnvironmentSource(settings: settings, account: account,
        pointsPerRem: 17, documentComplete: true, development: false)
      defer { source.stop() }
      let before = try XCTUnwrap(source.read())
      let oldSize = settings.fontSize
      settings.fontSize = oldSize + 1
      XCTAssertNil(source.read(), "The completed mutation must retire the context synchronously")
      settings.fontSize = oldSize
      XCTAssertNil(source.read())
      let after = try await settled(source)
      XCTAssertNotEqual(after.revision, before.revision)
      XCTAssertEqual(after.context, before.context)
      XCTAssertEqual(after.pointsPerRem, 17)
      XCTAssertEqual(settings.fontSize, oldSize)
      XCTAssertEqual(source.read(), after, "A read must not rotate the epoch")
      settings.blindMode.toggle()
      XCTAssertNil(source.read(), "Observation must be rearmed")
      let rearmed = try await settled(source)
      XCTAssertNotEqual(rearmed.revision, after.revision)
    }
  }

  func testRepeatedBackgroundApplicationRetiresAnUnchangedSnapshotEnvironment() async throws {
    try await withModels { settings, account in
      settings.customBackgroundURL = "https://example.invalid/same.png"
      let source = WebsiteConfigEnvironmentSource(settings: settings, account: account,
        pointsPerRem: 16, documentComplete: true, development: false)
      defer { source.stop() }
      let before = try XCTUnwrap(source.read()), snapshot = settings.snapshot
      settings.customBackgroundURL = settings.customBackgroundURL
      XCTAssertEqual(settings.snapshot, snapshot)
      XCTAssertNil(source.read(), "An explicit same-value image application retires pending preparation")
      let after = try await settled(source)
      XCTAssertNotEqual(after.revision, before.revision); XCTAssertEqual(after.context, before.context)
      settings.customBackgroundURL = settings.customBackgroundURL
      XCTAssertNil(source.read(), "The application observation must rearm")
      let rearmed = try await settled(source)
      XCTAssertNotEqual(rearmed.revision, after.revision)
    }
  }

  func testActualAccountAndThemeDirectoryProduceRuntimeContext() async throws {
    try await withModels { settings, account in
      let source = WebsiteConfigEnvironmentSource(settings: settings, account: account,
        pointsPerRem: 16, documentComplete: true, development: false)
      defer { source.stop() }
      let anonymous = try XCTUnwrap(source.read())
      let user = RemoteAccountUser(id: UUID(), email: "local@example.invalid", displayName: "Local", totalExperience: 0)
      account.currentUser = user
      XCTAssertNil(source.read())
      let signedIn = try await settled(source)
      XCTAssertTrue(signedIn.context.authenticated)
      XCTAssertNotEqual(signedIn.revision, anonymous.revision)
      account.currentUser = nil
      account.currentUser = user
      XCTAssertNil(source.read())
      let returned = try await settled(source)
      XCTAssertNotEqual(returned.revision, signedIn.revision)
      XCTAssertEqual(returned.context, signedIn.context)
      XCTAssertNotNil(settings.addCustomTheme(name: "Local QA", background: .black, panel: .gray,
        accent: .white, prefersDark: true))
      XCTAssertNil(source.read())
      let themed = try await settled(source)
      XCTAssertEqual(themed.context.customThemeCount, 1)
      XCTAssertTrue(account.updateEndpoint("http://127.0.0.1:8081"))
      XCTAssertNil(source.read())
      let moved = try await settled(source)
      XCTAssertFalse(moved.context.authenticated)
    }
  }

  func testLocalResourceRevisionsAndUnavailableLayoutAreNotReadinessClaims() async throws {
    try await withModels { settings, account in
      let source = WebsiteConfigEnvironmentSource(settings: settings, account: account,
        pointsPerRem: 16, documentComplete: false, development: true)
      defer { source.stop() }
      let initial = try XCTUnwrap(source.read())
      XCTAssertFalse(initial.context.documentComplete)
      XCTAssertTrue(initial.context.development)
      // Inject only the filesystem operation; exercise the actual AppSettings revision producer.
      try settings.importLocalPracticeFont(data: Data(), originalFilename: "qa.ttf", save: { _, _ in })
      XCTAssertNil(source.read())
      let font = try await settled(source)
      XCTAssertNotEqual(font.revision, initial.revision)
      try settings.removeLocalBackground()
      XCTAssertNil(source.read())
      let background = try await settled(source)
      XCTAssertNotEqual(background.revision, font.revision)
      source.updateLayout(pointsPerRem: nil, documentComplete: true)
      XCTAssertNil(source.read())
      await Task.yield()
      XCTAssertNil(source.read())
      for invalid in [0, -1, Double.infinity, Double.nan] {
        source.updateLayout(pointsPerRem: invalid, documentComplete: true)
        await Task.yield()
        XCTAssertNil(source.read())
      }
      source.updateLayout(pointsPerRem: 20, documentComplete: true)
      XCTAssertNil(source.read())
      let layout = try await settled(source)
      XCTAssertEqual(layout.pointsPerRem, 20)
      XCTAssertTrue(layout.context.documentComplete)
      XCTAssertNotEqual(layout.revision, background.revision)
      source.updateLayout(pointsPerRem: 24, documentComplete: true)
      XCTAssertNil(source.read())
      source.stop()
      source.updateLayout(pointsPerRem: 16, documentComplete: false)
      settings.fontSize += 1
      await Task.yield()
      XCTAssertNil(source.read(), "Stop is terminal, queued rearm must not resurrect the source")
    }
  }

  func testRealEnvironmentSourceFencesDiskCommitAcrossLegacyABA() async throws {
    try await withModels { settings, account in
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-environment-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      defer { try? FileManager.default.removeItem(at: directory) }
      let owner = UUID(), router = settings.preferenceConfigurationSaves
      router.register(owner: owner, save: { XCTFail("No legacy event replay") })
      defer { router.remove(owner: owner) }
      let source = WebsiteConfigEnvironmentSource(settings: settings, account: account,
        pointsPerRem: 16, documentComplete: true, development: false)
      defer { source.stop() }
      let register = WebsiteConfigFileRegister(directory: directory)
      let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register, environment: source.read)
      let ticket = try coordinator.prepare(#"{"time":41}"#)
      let size = settings.fontSize
      settings.fontSize = size + 1
      settings.fontSize = size
      _ = try await settled(source)
      guard case .stale = try coordinator.commit(ticket) else { return XCTFail("Changed context committed") }
      XCTAssertEqual(try register.read().state, .missing)
      XCTAssertNil(coordinator.publication(for: owner))
      let fresh = try coordinator.prepare(#"{"time":43}"#)
      guard case .committed(let published) = try coordinator.commit(fresh) else { return XCTFail("Fresh context rejected") }
      XCTAssertEqual(published.environmentRevision, source.read()?.revision)
      XCTAssertEqual(try register.read().state, .available(published.draft.projection.runtime))
      XCTAssertEqual(published.draft.projection.runtime["time"], .number(43))
      let protectedRecord = try register.read().state
      let imageTicket = try coordinator.prepare(#"{"time":47}"#)
      settings.customBackgroundURL = settings.customBackgroundURL
      _ = try await settled(source)
      guard case .stale = try coordinator.commit(imageTicket) else {
        return XCTFail("Same-value image application allowed an old preparation to commit")
      }
      XCTAssertEqual(try register.read().state, protectedRecord, "Retired image context must not write the file")
    }
  }

  func testNoQuitOwnersWithholdEnvironmentUntilAllLocksRelease() async throws {
    try await withModels { settings, account in
      let first = UUID(), second = UUID()
      settings.setNoQuitConfigurationLock(true, for: first)
      let source = WebsiteConfigEnvironmentSource(settings: settings, account: account,
        pointsPerRem: 16, documentComplete: true, development: false)
      defer { source.stop() }
      XCTAssertNil(source.read(), "A locked initial state must not admit a full configuration")
      settings.setNoQuitConfigurationLock(true, for: second)
      settings.setNoQuitConfigurationLock(false, for: first)
      for _ in 0..<5 { await Task.yield() }
      XCTAssertNil(source.read(), "One window cannot release another window's lock")
      settings.blindMode.toggle()
      for _ in 0..<5 { await Task.yield() }
      XCTAssertNil(source.read(), "Other model changes cannot reopen the admission")
      settings.setNoQuitConfigurationLock(false, for: second)
      let unlocked = try await settled(source)
      settings.setNoQuitConfigurationLock(false, for: second)
      XCTAssertEqual(source.read(), unlocked, "An absent lock release is not an event")
      settings.setNoQuitConfigurationLock(true, for: first)
      XCTAssertNil(source.read(), "Observation must rearm after unlocking")
      settings.setNoQuitConfigurationLock(false, for: first)
      let relocked = try await settled(source)
      XCTAssertNotEqual(relocked.revision, unlocked.revision)
    }
  }

  func testNoQuitABARejectsOldDiskTicketAndAllowsFreshConfigurationAfterUnlock() async throws {
    try await withModels { settings, account in
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-noquit-config-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      defer { try? FileManager.default.removeItem(at: directory) }
      let owner = UUID(), lockOwner = UUID(), router = settings.preferenceConfigurationSaves
      router.register(owner: owner, save: { XCTFail("No legacy save replay") })
      defer { router.remove(owner: owner) }
      let source = WebsiteConfigEnvironmentSource(settings: settings, account: account,
        pointsPerRem: 16, documentComplete: true, development: false)
      defer { source.stop() }
      let register = WebsiteConfigFileRegister(directory: directory)
      let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register, environment: source.read)
      let old = try coordinator.prepare(#"{"time":41}"#)
      let snapshot = settings.snapshot
      settings.setNoQuitConfigurationLock(true, for: lockOwner)
      XCTAssertNil(source.read())
      settings.setNoQuitConfigurationLock(false, for: lockOwner)
      _ = try await settled(source)
      guard case .stale = try coordinator.commit(old) else { return XCTFail("Pre-lock ticket revived") }
      XCTAssertEqual(try register.read().state, .missing)
      XCTAssertNil(coordinator.publication(for: owner))
      XCTAssertEqual(settings.snapshot, snapshot)
      let fresh = try coordinator.prepare(#"{"time":47}"#)
      guard case .committed(let publication) = try coordinator.commit(fresh) else { return XCTFail("Fresh unlocked import rejected") }
      XCTAssertEqual(publication.draft.projection.runtime["time"], .number(47))
      XCTAssertEqual(try register.read().state, .available(publication.draft.projection.runtime))
      settings.setNoQuitConfigurationLock(true, for: lockOwner)
      defer { settings.setNoQuitConfigurationLock(false, for: lockOwner) }
      do { _ = try coordinator.prepare(#"{"time":43}"#); XCTFail("Locked import admitted") }
      catch WebsiteConfigCommitCoordinatorError.noEnvironment {}
      XCTAssertEqual(try register.read().state, .available(publication.draft.projection.runtime))
    }
  }

  func testNoQuitStartDuringAsyncReadStopsTheNextResourceAndCommit() async throws {
    try await withModels { settings, account in
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-noquit-resource-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      defer { try? FileManager.default.removeItem(at: directory) }
      let owner = UUID(), lockOwner = UUID(), router = settings.preferenceConfigurationSaves
      router.register(owner: owner, save: { XCTFail("No legacy replay") })
      defer { router.remove(owner: owner); settings.setNoQuitConfigurationLock(false, for: lockOwner) }
      let source = WebsiteConfigEnvironmentSource(settings: settings, account: account,
        pointsPerRem: 16, documentComplete: true, development: false)
      defer { source.stop() }
      let register = WebsiteConfigFileRegister(directory: directory)
      let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register, environment: source.read)
      let ticket = try coordinator.prepare("{}")
      var backgroundReads = 0
      do {
        _ = try await coordinator.prepareResources(for: ticket, readLocalFont: {
          settings.setNoQuitConfigurationLock(true, for: lockOwner)
          await Task.yield()
          return .absent
        }, readLocalBackground: { backgroundReads += 1; return .absent })
        XCTFail("No Quit did not stop resource preparation")
      } catch WebsiteConfigCommitCoordinatorError.stale {}
      XCTAssertEqual(backgroundReads, 0)
      guard case .stale = try coordinator.commit(ticket) else { return XCTFail("Locked ticket committed") }
      XCTAssertEqual(try register.read().state, .missing)
      XCTAssertNil(coordinator.publication(for: owner))
    }
  }

  func testInitiallyUnknownLayoutTracksChangesAndQueuedTaskDoesNotRetainSource() async throws {
    try await withModels { settings, account in
      var source: WebsiteConfigEnvironmentSource? = .init(settings: settings, account: account,
        pointsPerRem: nil, documentComplete: false, development: false)
      weak var released = source
      XCTAssertNil(source?.read())
      account.currentUser = .init(id: UUID(), email: "local@example.invalid", displayName: "Local", totalExperience: 0)
      await Task.yield()
      XCTAssertNil(source?.read())
      source?.updateLayout(pointsPerRem: 18, documentComplete: true)
      let ready = try await settled(XCTUnwrap(source))
      XCTAssertTrue(ready.context.authenticated)
      XCTAssertEqual(ready.pointsPerRem, 18)
      settings.blindMode.toggle()
      XCTAssertNil(source?.read())
      source = nil
      XCTAssertNil(released, "Neither observation nor the queued refresh owns its source")
      await Task.yield()
      XCTAssertNil(released)
    }
  }

  func testActualBackgroundReapplicationStopsAsyncResourcesBeforeTheNextRead() async throws {
    try await withModels { settings, account in
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-async-environment-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      defer { try? FileManager.default.removeItem(at: directory) }
      let owner = UUID(), router = settings.preferenceConfigurationSaves
      router.register(owner: owner, save: {})
      let source = WebsiteConfigEnvironmentSource(settings: settings, account: account,
        pointsPerRem: 16, documentComplete: true, development: false)
      defer { source.stop() }
      let register = WebsiteConfigFileRegister(directory: directory)
      let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register, environment: source.read)
      let ticket = try coordinator.prepare("{}")
      var backgroundReads = 0
      do {
        _ = try await coordinator.prepareResources(for: ticket, readLocalFont: {
          settings.customBackgroundURL = settings.customBackgroundURL
          await Task.yield(); return .absent
        }, readLocalBackground: { backgroundReads += 1; return .absent })
        XCTFail("Real model reapplication did not retire async resources")
      } catch WebsiteConfigCommitCoordinatorError.stale {
      }
      XCTAssertEqual(backgroundReads, 0)
      XCTAssertNil(coordinator.publication(for: owner))
      XCTAssertEqual(try register.read().state, .missing)
    }
  }
}
