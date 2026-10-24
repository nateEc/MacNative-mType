import XCTest
import Observation
@testable import Typebar

@MainActor final class WebsiteConfigImportWorkflowTests: XCTestCase {
  private enum Failure: Error { case notParked }
  @MainActor private final class Gate {
    var continuation: CheckedContinuation<[OfflineQuote], Never>?
    func read() async -> [OfflineQuote] { await withCheckedContinuation { continuation = $0 } }
    func wait() async throws {
      let deadline = ContinuousClock.now.advanced(by: .seconds(3))
      while continuation == nil && ContinuousClock.now < deadline { await Task.yield() }
      guard continuation != nil else { throw Failure.notParked }
    }
    func resolve() {
      continuation?.resume(returning: [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)])
      continuation = nil
    }
  }
  @MainActor private final class Fixture {
    let suite = "typebar.import-workflow.\(UUID())"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-import-workflow-\(UUID())")
    let defaults: UserDefaults, settings: AppSettings, account: AccountSession
    let page = PracticePageSessionStore()
    let directory: URL
    var window: WebsiteConfigPracticeScopeSource.Window
    lazy var workflow = WebsiteConfigImportWorkflow(page: page, settings: settings, account: account,
      directory: directory, readWindow: { [unowned self] in window })
    init() throws {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
      directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: root)
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = .init(defaults: defaults, localBackgroundStore: .inMemory())
      account = .init(defaults: defaults)
      window = .init(owner: page.owner, customRecoveryBlocked: false)
      settings.preferenceConfigurationSaves.register(owner: page.owner, save: { XCTFail("No legacy write") })
      page.attach(to: settings.preferenceConfigurationSaves)
    }
    func close() {
      workflow.stop(); page.detach()
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: root)
    }
  }

  func testImportCommitsActualPageBindsRestartAndLeavesLegacyPreferencesUntouched() async throws {
    let f = try Fixture(); defer { f.close() }
    let old = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"theme":"dracula"}"#, systemIsDark: true)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 4)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.themes.theme, .dracula)
    XCTAssertNotNil(f.page.restartController)
    XCTAssertEqual(f.settings.snapshot, old)
    let register = WebsiteConfigFileRegister(directory: f.directory)
    XCTAssertEqual(try register.read().state, .available(try XCTUnwrap(f.page.state.presentation).publication.draft.projection.runtime))
    let first = f.page.state.session.automaticInputAttemptID
    try await f.workflow.apply(json: nil, systemIsDark: false)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, first)
    guard case .restored = f.page.state.presentation?.publication.draft.origin else { return XCTFail("Restore became import") }
  }

  func testMissingRestoreAndTypebarBackupNeverChangePageOrCreateDataRecord() async throws {
    let f = try Fixture(); defer { f.close() }
    let attempt = f.page.state.session.automaticInputAttemptID
    do { try await f.workflow.apply(json: nil, systemIsDark: false); XCTFail("Missing record accepted") }
    catch WebsiteConfigImportWorkflowError.missing {}
    let backup = try SettingsJSONCommandCodec.export(settings: f.settings.snapshot,
      configuration: .words(5), layoutFluidLayouts: [], testParameterMemory: .defaults)
    do { try await f.workflow.apply(json: backup, systemIsDark: false); XCTFail("Typebar backup accepted as website JSON") }
    catch WebsiteConfigImportWorkflowError.typebarBackup {}
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
  }

  func testActiveAttemptAndStoppedWorkflowRefuseWithoutWriting() async throws {
    let f = try Fixture(); defer { f.close() }
    var state = f.page.state
    state.session = TypingSession(configuration: .words(2), prompt: "ab cd")
    state.session.insertBatch("a"); f.page.replace(state)
    do { try await f.workflow.apply(json: "{}", systemIsDark: false); XCTFail("Active attempt overwritten") }
    catch WebsiteConfigImportWorkflowError.activeAttempt {}
    f.workflow.stop()
    do { try await f.workflow.apply(json: "{}", systemIsDark: false); XCTFail("Stopped window accepted") }
    catch WebsiteConfigImportWorkflowError.unavailable {}
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
  }

  func testDirectoryIsPrivateAndUnsafeExistingDirectoryIsNotChmoded() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-config-location-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: root)
    XCTAssertEqual(directory.lastPathComponent, "WebsiteConfiguration")
    let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
    XCTAssertEqual(permissions?.intValue, 0o700)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
    XCTAssertThrowsError(try WebsiteConfigStorageDirectory.prepare(applicationSupport: root))
    XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o755)
  }

  func testCancelOrNewInputDuringGenerationCannotCommitAndConcurrentApplyIsRejected() async throws {
    for cancel in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let gate = Gate(); defer { gate.resolve() }
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
      defer { workflow.stop() }
      let task = Task { try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false) }
      try await gate.wait()
      do { try await workflow.apply(json: "{}", systemIsDark: false); XCTFail("Concurrent apply accepted") }
      catch WebsiteConfigImportWorkflowError.busy {}
      if cancel { workflow.cancel() }
      else {
        var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
      }
      gate.resolve()
      do { _ = try await task.value; XCTFail("Late generation committed") }
      catch {
        guard error is CancellationError || (error as? WebsiteConfigCommitCoordinatorError) == .stale else {
          return XCTFail("Unexpected error: \(error)")
        }
      }
      XCTAssertNil(f.page.state.practice)
      XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
    }
  }

  func testPublishedCustomContentKeepsExactTimeAndFiniteSourceOnReimport() async throws {
    let f = try Fixture(); defer { f.close() }
    let timed = WebsiteConfigSessionBuilder.Scope(customText: "Alpha Beta", customTextIsPrepared: true,
      customCompletion: .time, customDurationOverride: 2.5)
    f.window = .published(owner: f.page.owner, revision: UUID(), scope: timed)
    try await f.workflow.apply(json: #"{"mode":"custom"}"#, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.configuration.duration, 2.5)
    XCTAssertEqual(f.page.state.practice?.scope.customDurationOverride, 2.5)
    let finite = WebsiteConfigSessionBuilder.Scope(customText: "preview", finiteTextSource: "actual owned source")
    f.window = .published(owner: f.page.owner, revision: UUID(), scope: finite)
    try await f.workflow.apply(json: #"{"mode":"custom"}"#, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.prompt, "actual owned source")
  }

  func testUnknownWebsiteFieldsDoNotMisclassifyAWebsiteConfigurationAsBackup() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":3,"version":99,"settings":{},"configuration":{}}"#, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 3)
  }

  func testSymlinkedApplicationParentIsRefusedWithoutCreatingAnExternalChild() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-config-symlink-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let elsewhere = root.appendingPathComponent("elsewhere")
    try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Typebar"), withDestinationURL: elsewhere)
    XCTAssertThrowsError(try WebsiteConfigStorageDirectory.prepare(applicationSupport: root))
    XCTAssertFalse(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("WebsiteConfiguration").path))
  }

  func testObserverRetirementAfterCommitReportsAppliedRatherThanPretendingRollback() async throws {
    let f = try Fixture(); defer { f.close() }
    withObservationTracking { _ = f.page.state } onChange: {
      MainActor.assumeIsolated { f.page.detach() }
    }
    let message = try await f.workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    XCTAssertTrue(message.contains("已保存并应用"))
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 4)
    XCTAssertNotNil(f.page.state.practice)
    XCTAssertNil(f.page.restartController)
    guard case .available = try WebsiteConfigFileRegister(directory: f.directory).read().state else {
      return XCTFail("Committed record was falsely rolled back")
    }
  }
}
