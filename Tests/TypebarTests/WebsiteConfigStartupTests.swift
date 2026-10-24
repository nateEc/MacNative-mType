import XCTest
import Observation
@testable import Typebar

@MainActor final class WebsiteConfigStartupTests: XCTestCase {
  @MainActor private final class Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-startup-\(UUID())")
    let suite = "typebar.startup.\(UUID())"
    let defaults: UserDefaults, settings: AppSettings, account: AccountSession
    let page = PracticePageSessionStore(), startup = WebsiteConfigStartupController()
    var pendingCalls = 0, continueCalls = 0, factories = 0
    var workflow: WebsiteConfigImportWorkflow?
    var quotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) }
    init() throws {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = .init(defaults: defaults, localBackgroundStore: .inMemory())
      account = .init(defaults: defaults)
      settings.preferenceConfigurationSaves.register(owner: page.owner, save: { XCTFail("No legacy save") })
      page.attach(to: settings.preferenceConfigurationSaves)
    }
    func seed(_ json: String = #"{"mode":"words","words":4}"#) throws -> URL {
      let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: root)
      let register = WebsiteConfigFileRegister(directory: directory)
      let draft = try WebsiteConfigNativeProfile.prepareDraft(json,
        pointsPerRem: 16, context: .init())
      guard case .committed = try register.commit(draft, replacing: XCTUnwrap(register.read().revision)) else {
        throw WebsiteConfigImportWorkflowError.conflict
      }
      return directory
    }
    func update(ready: Bool = true, owner: Bool = true) {
      startup.update(page: page, accountReady: ready, ownerReady: owner,
        probe: { try WebsiteConfigStorageDirectory.existing(applicationSupport: self.root) },
        onPending: { self.pendingCalls += 1 }, onContinue: { self.continueCalls += 1 },
        makeWorkflow: { directory in
          self.factories += 1
          let window = WebsiteConfigPracticeScopeSource.Window(owner: self.page.owner, customRecoveryBlocked: false)
          let reader = self.quotes
          let value = WebsiteConfigImportWorkflow(page: self.page, settings: self.settings, account: self.account,
            directory: directory, readWindow: { window }, loadQuotes: reader)
          self.workflow = value; return value
        }, systemIsDark: false)
    }
    func settle() async {
      let deadline = ContinuousClock.now.advanced(by: .seconds(3))
      while startup.isRestoring && ContinuousClock.now < deadline { await Task.yield() }
      XCTAssertFalse(startup.isRestoring)
    }
    func close() {
      startup.stop(); workflow?.stop(); page.detach()
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: root)
    }
  }

  func testMissingRecordDoesNotCreateDirectoriesOrWaitForAccount() throws {
    let f = try Fixture(); defer { f.close() }
    f.update(ready: false, owner: false)
    XCTAssertFalse(f.startup.isBlocking)
    XCTAssertEqual(f.factories, 0); XCTAssertEqual(f.pendingCalls, 0)
    XCTAssertTrue(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
    XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("Typebar").path))
  }

  func testStartupWaitsForAccountAndOwnerThenRestoresOnce() async throws {
    let f = try Fixture(); defer { f.close() }
    let directory = try f.seed(), register = WebsiteConfigFileRegister(directory: directory)
    let before = try register.read().revision
    f.update(ready: false)
    XCTAssertTrue(f.startup.isBlocking); XCTAssertFalse(f.startup.isRestoring)
    XCTAssertFalse(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
    f.update(ready: true, owner: false)
    XCTAssertEqual(f.factories, 0)
    f.update(); f.update()
    await f.settle()
    XCTAssertNil(f.startup.failureMessage); XCTAssertFalse(f.startup.isBlocking)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 4)
    XCTAssertNotNil(f.page.restartController)
    XCTAssertEqual(f.factories, 1); XCTAssertEqual(f.pendingCalls, 1)
    XCTAssertEqual(try register.read().revision, before,
      "Cold restoration of unchanged settings must not invalidate another window's record authority")
    let restored = try register.read().revision
    f.update(ready: false); f.update()
    await f.settle()
    XCTAssertEqual(try register.read().revision, restored)
    XCTAssertEqual(f.factories, 1)
  }

  func testBadRecordBlocksWithRecoveryChoiceAndIsNeverRepaired() async throws {
    let f = try Fixture(); defer { f.close() }
    let directory = try f.seed(), url = directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let opaque = Data("unknown future record".utf8)
    try opaque.write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    f.update(); await f.settle()
    XCTAssertTrue(f.startup.isBlocking); XCTAssertNotNil(f.startup.failureMessage)
    XCTAssertEqual(try Data(contentsOf: url), opaque)
    f.update(); await f.settle()
    XCTAssertEqual(f.factories, 1, "Failure must not start an automatic retry loop")
    f.startup.continueUsingLegacy()
    XCTAssertFalse(f.startup.isBlocking); XCTAssertEqual(f.continueCalls, 1)
    XCTAssertEqual(try Data(contentsOf: url), opaque)
  }

  func testUnstartedRestorationCanBeSkippedBeforeAccountFinishes() throws {
    let f = try Fixture(); defer { f.close() }
    _ = try f.seed()
    f.update(ready: false)
    f.startup.continueUsingLegacy()
    f.update()
    XCTAssertFalse(f.startup.isBlocking); XCTAssertEqual(f.factories, 0)
    XCTAssertEqual(f.continueCalls, 1)
  }

  func testAccountStartupCoalescesMultipleWindows() async {
    let startup = AppAccountStartup()
    var calls = 0
    var release: CheckedContinuation<Void, Never>?
    let first = Task { await startup.restore { calls += 1; await withCheckedContinuation { release = $0 } } }
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while release == nil && ContinuousClock.now < deadline { await Task.yield() }
    let second = Task { await startup.restore { calls += 1 } }
    XCTAssertFalse(startup.isReady)
    release?.resume(); release = nil
    await first.value; await second.value
    XCTAssertTrue(startup.isReady); XCTAssertEqual(calls, 1)
    await startup.restore { calls += 1 }
    XCTAssertEqual(calls, 1)
  }

  func testObservationCannotInsertCachedInputDuringStartupGateTransition() throws {
    let f = try Fixture(); defer { f.close() }
    _ = try f.seed()
    let attempt = f.page.state.session.automaticInputAttemptID
    var checked = false
    withObservationTracking { _ = f.page.acceptsInput(for: attempt) } onChange: {
      MainActor.assumeIsolated {
        checked = true
        XCTAssertFalse(f.page.acceptsInput(for: attempt), "willSet must not expose the previous open gate")
      }
    }
    f.update(ready: false)
    XCTAssertTrue(checked)
    XCTAssertFalse(f.page.acceptsInput(for: attempt))
  }

  func testSecondWindowRestoreKeepsFirstWindowsRestartAuthorityAfterFocusReturns() async throws {
    let f = try Fixture(); defer { f.close() }
    let directory = try f.seed(), register = WebsiteConfigFileRegister(directory: directory)
    f.update(); await f.settle()
    let firstController = try XCTUnwrap(f.page.restartController)
    let firstAttempt = f.page.state.session.automaticInputAttemptID
    let disk = try register.read().revision
    let second = PracticePageSessionStore(), router = f.settings.preferenceConfigurationSaves
    router.register(owner: second.owner, save: {})
    router.activate(owner: second.owner); second.attach(to: router)
    let window = WebsiteConfigPracticeScopeSource.Window(owner: second.owner, customRecoveryBlocked: false)
    let workflow = WebsiteConfigImportWorkflow(page: second, settings: f.settings, account: f.account,
      directory: directory, readWindow: { window })
    defer { workflow.stop(); second.detach(); router.remove(owner: second.owner) }
    try await workflow.apply(json: nil, systemIsDark: false)
    XCTAssertEqual(try register.read().revision, disk)
    router.activate(owner: f.page.owner)
    XCTAssertTrue(firstController.request())
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while firstController.isPreparing && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertFalse(firstController.isPreparing); XCTAssertNil(firstController.message)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, firstAttempt)
    XCTAssertEqual(try register.read().revision, disk)
  }

  func testOwnerLossCancelsParkedRestorationWithoutRetryOrLateCommit() async throws {
    let f = try Fixture(); defer { f.close() }
    var release: CheckedContinuation<[OfflineQuote], Never>?
    f.quotes = { _ in await withCheckedContinuation { release = $0 } }
    let directory = try f.seed(#"{"mode":"quote","quoteLength":[0]}"#)
    let register = WebsiteConfigFileRegister(directory: directory), disk = try register.read().revision
    f.update()
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while release == nil && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertNotNil(release)
    f.update(owner: false)
    XCTAssertNotNil(f.startup.failureMessage); XCTAssertFalse(f.startup.isRestoring)
    release?.resume(returning: [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)])
    release = nil
    for _ in 0..<10 { await Task.yield() }
    f.update()
    XCTAssertEqual(f.factories, 1)
    XCTAssertNil(f.page.state.practice)
    XCTAssertEqual(try register.read().revision, disk)
  }
}
