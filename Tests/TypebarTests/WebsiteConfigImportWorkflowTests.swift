import XCTest
import Observation
@testable import Typebar

@MainActor final class WebsiteConfigImportWorkflowTests: XCTestCase {
  private enum Failure: Error, Equatable { case notParked, provider }
  @MainActor private final class WeakWorkflow { weak var value: WebsiteConfigImportWorkflow? }

  func testLazyModeNoticeIsOncePerWindowUntilRememberedRestoration() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let unsupported = #"{"mode":"words","words":4,"language":"hindi","lazyMode":true}"#
    try await f.workflow.apply(json: unsupported, systemIsDark: false)
    let center = f.account.localNotices
    XCTAssertEqual(center.history.count, 1)
    XCTAssertEqual(center.history.first?.level, .notice)
    XCTAssertTrue(center.history.first?.message.contains("语言不支持") == true)
    XCTAssertTrue(center.active.first?.important == true)
    center.clearAll()
    try await f.workflow.apply(json: unsupported, systemIsDark: false)
    XCTAssertEqual(center.history.count, 1, "Re-enabling on an unsupported language does not reset the latch")
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"spanish","lazyMode":false}"#, systemIsDark: false)
    XCTAssertTrue(f.page.state.presentation?.publication.draft.generators.lazyMode == true)
    try await f.workflow.apply(json: unsupported, systemIsDark: false)
    XCTAssertEqual(center.history.count, 2)
  }

  func testPolyglotLazyModeNoticeNamesTheUnsupportedSelection() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"english","funbox":["polyglot"],"customPolyglot":["hindi","thai"],"lazyMode":true}"#, systemIsDark: false)
    XCTAssertEqual(f.account.localNotices.history.count, 1)
    XCTAssertTrue(f.account.localNotices.history.first?.message.contains("所选多语") == true)
    XCTAssertTrue(f.account.localNotices.active.first?.important == true)
    XCTAssertFalse(try XCTUnwrap(f.page.state.presentation).publication.draft.generators.lazyMode)
  }

  func testLazyNoticeSurvivesWorkflowReplacementButIsIndependentInAnotherWindow() async throws {
    let f = try Fixture(), other = try Fixture()
    defer { f.close(); other.close(); f.account.localNotices.clearAll() }
    let json = #"{"mode":"words","words":4,"language":"hindi","lazyMode":true}"#
    try await f.workflow.apply(json: json, systemIsDark: false)
    f.workflow.stop()
    let replacement = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window })
    defer { replacement.stop() }
    try await replacement.apply(json: json, systemIsDark: false)
    XCTAssertEqual(f.account.localNotices.history.count, 1)
    let secondWindow = WebsiteConfigImportWorkflow(page: other.page, settings: other.settings, account: f.account,
      directory: other.directory, readWindow: { other.window })
    defer { secondWindow.stop() }
    try await secondWindow.apply(json: json, systemIsDark: false)
    XCTAssertEqual(f.account.localNotices.history.count, 2)
  }

  func testLazyNoticeDoesNotRepeatOrSpendTheThreeGenerationFailuresBudget() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in reads += 1; throw Failure.provider })
    defer { workflow.stop() }
    for _ in 0..<2 {
      do {
        try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"language":"hindi","lazyMode":true}"#, systemIsDark: false)
        XCTFail("Generation failures delivered")
      } catch let error as WebsiteConfigInitializationExhaustedError {
        XCTAssertEqual(error.underlying as? Failure, .provider)
      }
    }
    XCTAssertEqual(reads, 6)
    XCTAssertEqual(f.account.localNotices.history.filter { $0.level == .notice }.count, 1)
    XCTAssertEqual(f.account.localNotices.history.filter { $0.level == .error }.count, 6)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
  }

  func testCancellingDuringLazyNoticeWithdrawsItAndAllowsTheNextRequestToWarn() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let handle = WeakWorkflow()
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .hindi, length: .short)]
      })
    handle.value = workflow
    defer { workflow.stop() }
    let transition = NoticeTransition()
    withObservationTracking { _ = f.account.localNotices.history } onChange: {
      MainActor.assumeIsolated {
        guard transition.calls == 0 else { return }; transition.calls += 1
        handle.value?.cancel()
      }
    }
    let json = #"{"mode":"quote","quoteLength":[0],"language":"hindi","lazyMode":true}"#
    do { try await workflow.apply(json: json, systemIsDark: false); XCTFail("Cancelled notice request delivered") }
    catch is CancellationError {}
    XCTAssertEqual(reads, 0); XCTAssertTrue(f.account.localNotices.history.isEmpty)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
    try await workflow.apply(json: json, systemIsDark: false)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.account.localNotices.history.count, 1)
    XCTAssertEqual(f.account.localNotices.history.first?.level, .notice)
  }

  func testUnauthenticatedFavoritesCorrectionDoesNotConsumeGenerationBudgetOrPostARecoveryNotice() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        if reads < 3 { throw Failure.provider }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[-3,-2,0]}"#, systemIsDark: false)
    XCTAssertEqual(reads, 3)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [0,1,2,3])
    XCTAssertEqual(f.account.localNotices.history.map(\.level), [.error, .error])
  }

  func testUnauthenticatedFavoritesSetterSavesBeforeProviderAndResumesWithoutAnotherCorrection() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    var reads = 0
    let handle = WeakWorkflow()
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        guard case .available(let runtime) = try register.read().state else { throw Failure.provider }
        XCTAssertEqual(runtime["quoteLength"], .array((0...3).map { .number(Double($0)) }), "Correct before the first provider read")
        if reads == 1 { handle.value?.cancel() }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    handle.value = workflow
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let publication = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    do {
      try await workflow.editAndBegin(.quoteLengths([-3]), replacing: publication, systemIsDark: false)
      XCTFail("Cancelled preparation delivered")
    } catch is CancellationError {}
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertEqual(pending.draft.quoteSelection.groups, [0,1,2,3])
    let revision = try register.read().revision
    let ledger = f.page.state.priorAttemptLedger
    XCTAssertEqual(ledger.restartCount, 1)
    try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertEqual(reads, 2)
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, ledger.restartCount)
    XCTAssertTrue(f.account.localNotices.history.isEmpty)
  }

  func testAuthenticatedFavoritesAndDormantWordsSelectionDoNotReceiveThePreflightCorrection() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    f.account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
    f.window.favorites = .nativeLocal
    f.settings.favoriteQuoteIDs = ["favorite"]
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        return [.init(id: "favorite", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[-3]}"#, systemIsDark: false)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [-3])
    XCTAssertEqual(f.page.state.practice?.quote?.id, "favorite")
    f.account.currentUser = nil
    try await workflow.apply(json: #"{"mode":"words","words":4,"quoteLength":[-3]}"#, systemIsDark: false)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [-3])
    XCTAssertTrue(f.account.localNotices.history.isEmpty)
  }

  func testUnauthenticatedNativeLocalFavoritesCannotBypassPreflightButSelectedQuoteIsPreserved() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    f.window.favorites = .nativeLocal; f.window.selectedQuoteID = "owned"
    f.settings.favoriteQuoteIDs = ["owned"]
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    for (groups, expected) in [("[-3]", [0,1,2,3]), ("[-2,-3,0]", [0,1,2,3]), ("[-2]", [-2])] {
      try await workflow.apply(json: "{\"mode\":\"quote\",\"quoteLength\":\(groups)}", systemIsDark: false)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, expected)
      XCTAssertEqual(f.page.state.practice?.quote?.id, "owned")
    }
    XCTAssertEqual(reads, 3); XCTAssertTrue(f.account.localNotices.history.isEmpty)
  }

  func testAccountChangeAfterFavoritesCorrectionRejectsDeliveryWithoutRevertingItsSavedSetting() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    let register = WebsiteConfigFileRegister(directory: f.directory)
    var reads = 0
    var savedRevision: WebsiteConfigFileRegister.Revision?
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1; savedRevision = try register.read().revision
        f.account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    do {
      try await workflow.editAndBegin(.quoteLengths([-3]), replacing: publication, systemIsDark: false)
      XCTFail("Old account request delivered")
    } catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigCommitCoordinatorError.stale = error.underlying else { return XCTFail("Unexpected error: \(error)") }
    }
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication)
    XCTAssertEqual(try register.read().revision, savedRevision)
    XCTAssertEqual(f.page.state.configurationDeparture?.draft.quoteSelection.groups, [0,1,2,3])
    XCTAssertTrue(f.account.localNotices.history.isEmpty)
  }
  @MainActor private final class NoticeTransition { var calls = 0 }

  func testGenerationRetriesReachLocalHistoryAndRemainAfterSuccessfulInitialization() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        if reads < 3 { throw NSError(domain: "OwnedGeneration", code: reads,
          userInfo: [NSLocalizedDescriptionKey: "自有目录读取失败 \(reads)"]) }
        return [.init(id: "owned", title: "Owned recovery sample", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop(); f.account.localNotices.clearAll() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false)
    XCTAssertEqual(reads, 3)
    let entries = f.account.localNotices.history
    XCTAssertEqual(entries.count, 2)
    XCTAssertEqual(entries.map(\.level), [.error, .error])
    XCTAssertTrue(entries.first?.title.contains("1/3") == true)
    XCTAssertTrue(entries.last?.title.contains("2/3") == true)
    XCTAssertTrue(entries.last?.message.contains("自有目录读取失败 2") == true)
    XCTAssertTrue(f.account.localNotices.active.allSatisfy { $0.important && $0.durationMilliseconds == 0 })
    XCTAssertEqual(f.account.localNotices.visible(focused: true).count, 2)
    f.account.localNotices.clearAll()
    XCTAssertEqual(f.account.localNotices.history, entries)
  }

  func testQuoteLengthRecoveryPostsAnImportantNoticeNotAnOrdinaryError() async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        [.init(id: "medium", title: "Owned length recovery", text: "ab cd", language: .english, length: .medium)]
      })
    defer { workflow.stop(); f.account.localNotices.clearAll() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false)
    XCTAssertEqual(f.account.localNotices.history.count, 1)
    XCTAssertEqual(f.account.localNotices.history.first?.level, .notice)
    XCTAssertTrue(f.account.localNotices.history.first?.message.contains("所选长度") == true)
    XCTAssertTrue(f.account.localNotices.history.first?.message.contains("全部长度") == true)
    XCTAssertTrue(f.account.localNotices.active.first?.important == true)
    XCTAssertEqual(f.account.localNotices.active.first?.durationMilliseconds, 3000)
  }

  func testExhaustedImportReportsLastCauseButDoesNotPostAFourthNotificationOrWrite() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        throw NSError(domain: "Owned", code: reads, userInfo: [NSLocalizedDescriptionKey: "自有读取失败 \(reads)"])
      })
    defer { workflow.stop() }
    do { try await workflow.apply(json: #"{"mode":"quote"}"#, systemIsDark: false); XCTFail("Failed import delivered") }
    catch let error as WebsiteConfigInitializationExhaustedError {
      XCTAssertEqual((error.underlying as NSError).code, 3)
      XCTAssertTrue(error.localizedDescription.contains("自有读取失败 3"))
      XCTAssertTrue(error.localizedDescription.contains("三次"))
    }
    XCTAssertEqual(reads, 3); XCTAssertEqual(f.account.localNotices.history.count, 3)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
  }

  func testSilentGenerationErrorsConsumeBudgetWithoutPostingBlankNotices() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1; throw WebsiteWordGenerationError(message: "")
      })
    defer { workflow.stop() }
    do { try await workflow.apply(json: #"{"mode":"quote"}"#, systemIsDark: false); XCTFail("Silent failures delivered") }
    catch let error as WebsiteConfigInitializationExhaustedError {
      XCTAssertEqual((error.underlying as? WebsiteWordGenerationError)?.message, "")
      XCTAssertTrue(error.localizedDescription.contains("三次"))
    }
    XCTAssertEqual(reads, 3); XCTAssertTrue(f.account.localNotices.history.isEmpty)
  }

  func testCancellingFromNotificationObservationWithdrawsTheRetiredReceipt() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in reads += 1; throw Failure.provider })
    defer { workflow.stop() }
    withObservationTracking { _ = f.account.localNotices.history } onChange: {
      MainActor.assumeIsolated { workflow.cancel() }
    }
    do { try await workflow.apply(json: #"{"mode":"quote"}"#, systemIsDark: false); XCTFail("Cancelled notice operation delivered") }
    catch is CancellationError {}
    XCTAssertEqual(reads, 1)
    XCTAssertTrue(f.account.localNotices.history.isEmpty); XCTAssertTrue(f.account.localNotices.active.isEmpty)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
  }

  func testAccountChangeDuringNoticeDeliveryDoesNotLeakRetiredFailure() async throws {
    let f = try Fixture(); defer { f.close(); f.account.localNotices.clearAll() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in reads += 1; throw Failure.provider })
    defer { workflow.stop() }
    let transition = NoticeTransition()
    withObservationTracking { _ = f.account.localNotices.history } onChange: {
      MainActor.assumeIsolated {
        guard transition.calls == 0 else { return }; transition.calls += 1
        f.account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "Owned", totalExperience: 0)
        f.account.localNotices.post("New account", options: .init(durationMilliseconds: 0))
      }
    }
    do { try await workflow.apply(json: #"{"mode":"quote"}"#, systemIsDark: false); XCTFail("Old account operation delivered") }
    catch WebsiteConfigCommitCoordinatorError.stale {}
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.account.localNotices.history.map(\.message), ["New account"])
    XCTAssertEqual(f.account.localNotices.active.map(\.entry.message), ["New account"])
    XCTAssertEqual(transition.calls, 1)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
  }
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

  func testUnsupportedLazyLanguageRemembersAndRestoresAcrossFullImportAndColdRestore() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"hindi","lazyMode":true}"#, systemIsDark: false)
    let first = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertFalse(first.generators.lazyMode)
    XCTAssertEqual(first.lazyMemory, .init(remember: true, prefersArabic: true))
    let register = WebsiteConfigFileRegister(directory: f.directory)
    XCTAssertEqual(try register.read().lazyMemory, first.lazyMemory)
    let revision = try register.read().revision
    let attempt = f.page.state.session.automaticInputAttemptID
    do {
      try await f.workflow.editAndBegin(.mode(.custom), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTFail("Missing custom text applied a candidate lazy-memory restoration")
    } catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigSessionBuildError.customTextUnavailable = error.underlying else {
        return XCTFail("Unexpected saved preparation failure: \(error)")
      }
    }
    XCTAssertNotEqual(try register.read().revision, revision)
    XCTAssertFalse(try register.read().lazyMemory.remember, "Custom init restores the remembered value before missing text is detected")
    XCTAssertEqual(f.page.state.configurationDeparture?.draft.testParameters.mode, .custom)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"hindi","lazyMode":true}"#, systemIsDark: false)
    let restoredRevision = try register.read().revision
    try await f.workflow.apply(json: nil, systemIsDark: false)
    XCTAssertEqual(try register.read().revision, restoredRevision, "Stable remembered state must not invalidate other windows on cold restore")
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"spanish","lazyMode":false}"#, systemIsDark: false)
    let restored = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertTrue(restored.generators.lazyMode)
    XCTAssertFalse(restored.lazyMemory.remember)
    XCTAssertTrue(f.page.state.session.configuration.modifiers.contains(.lazyLatin))
    XCTAssertEqual(try register.read().lazyMemory, restored.lazyMemory)
    XCTAssertEqual(f.settings.snapshot, legacy)
  }

  func testArabicLanguageEventAndExplicitLazyPreferencePersistWithoutUsingLegacyPreference() async throws {
    let f = try Fixture(); defer { f.close() }
    f.settings.prefersArabicLazyInput = false
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"spanish","lazyMode":false}"#, systemIsDark: false)
    func edit(_ value: WebsiteConfigPracticeEdit) async throws {
      try await f.workflow.editAndBegin(value, replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    }
    try await edit(.language("arabic"))
    var draft = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertTrue(draft.generators.lazyMode); XCTAssertTrue(draft.lazyMemory.prefersArabic)
    XCTAssertTrue(draft.projection.events.contains { $0.key == "lazyMode" && $0.nosave == true })
    guard case .edited(let source) = draft.origin else { return XCTFail("Language became import") }
    XCTAssertEqual(source.key, "language")
    try await edit(.lazyMode(false))
    draft = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertFalse(draft.generators.lazyMode); XCTAssertFalse(draft.lazyMemory.prefersArabic)
    let revision = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    try await f.workflow.apply(json: nil, systemIsDark: false)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, revision)
    try await edit(.language("spanish")); try await edit(.language("arabic"))
    draft = try XCTUnwrap(f.page.state.presentation).publication.draft
    XCTAssertFalse(draft.generators.lazyMode); XCTAssertFalse(draft.lazyMemory.prefersArabic)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().lazyMemory, draft.lazyMemory)
    XCTAssertEqual(f.settings.snapshot, legacy)
  }

  func testCancelledGenerationCannotPersistCandidateLazyMemory() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let bytes = try Data(contentsOf: path), attempt = f.page.state.session.automaticInputAttemptID
    let task = Task { try await workflow.apply(json: #"{"mode":"quote","language":"hindi","lazyMode":true,"quoteLength":[0]}"#, systemIsDark: false) }
    try await gate.wait(); task.cancel(); gate.resolve()
    do { _ = try await task.value; XCTFail("Cancelled lazy transition committed") } catch is CancellationError {}
    XCTAssertEqual(try Data(contentsOf: path), bytes)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.lazyMemory, .init())
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

  func testExplicitParameterEditsKeepFullProfileAndPersistEditedOrigin() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"time":15,"theme":"dracula","soundVolume":0.3}"#, systemIsDark: false)
    for edit in [WebsiteConfigPracticeEdit.words(7), .mode(.time), .time(30), .time(30)] {
      let before = f.page.state.session.automaticInputAttemptID
      var expected = try XCTUnwrap(f.page.state.presentation).publication.draft.projection.runtime
      expected[edit.key] = edit.value
      try await f.workflow.editAndBegin(edit, replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, before)
      let draft = try XCTUnwrap(f.page.state.presentation).publication.draft
      guard case .edited(let change) = draft.origin else { return XCTFail("Edit became full import") }
      XCTAssertEqual(change.key, edit.key)
      XCTAssertEqual(draft.projection.runtime, expected)
      XCTAssertEqual(draft.projection.runtime["theme"], .string("dracula"))
      XCTAssertEqual(draft.projection.runtime["soundVolume"], .number(0.3))
      XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .available(draft.projection.runtime))
      XCTAssertNotNil(f.page.restartController)
    }
    XCTAssertEqual(f.page.state.session.configuration.duration, 30)
    XCTAssertEqual(f.page.state.practice?.parameterMemory.wordLimit, 7)
    XCTAssertEqual(f.settings.snapshot, legacy)
  }

  func testRejectedSetterKeepsRecordButAcceptedPreparationFailureRemainsSaved() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let attempt = f.page.state.session.automaticInputAttemptID
    let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let bytes = try Data(contentsOf: path)
    do { try await f.workflow.editAndBegin(.words(Double(OfficialTestLimitInput.maximumValue) + 1), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false); XCTFail("Invalid edit committed") }
    catch {}
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(try Data(contentsOf: path), bytes)
    XCTAssertNil(f.page.state.configurationDeparture)
    do { try await f.workflow.editAndBegin(.mode(.custom), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false); XCTFail("Missing custom text delivered") }
    catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigSessionBuildError.customTextUnavailable = error.underlying else {
        return XCTFail("Unexpected initializer failure")
      }
    }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.page.state.configurationDeparture?.draft.testParameters.mode, .custom)
    XCTAssertNotEqual(try Data(contentsOf: path), bytes)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    try await f.workflow.apply(json: #"{"mode":"words","words":6}"#, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 6)
    XCTAssertNil(f.page.state.configurationDeparture)
  }

  func testEditCancellationOwnerLossAndDiskConflictDoNotCommitLateGeneration() async throws {
    for cause in ["cancel", "task", "input", "owner", "disk"] {
      let f = try Fixture(); defer { f.close() }
      let gate = Gate(); defer { gate.resolve() }
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
      defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
      let attempt = f.page.state.session.automaticInputAttemptID
      let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
      let applicationID = try XCTUnwrap(f.page.state.presentation).publication.applicationID
      let task = Task { try await workflow.editAndBegin(.mode(.quote), replacing: applicationID, systemIsDark: false) }
      try await gate.wait()
      do { try await workflow.apply(json: "{}", systemIsDark: false); XCTFail("Concurrent import accepted") }
      catch WebsiteConfigImportWorkflowError.busy {}
      do { try await workflow.editAndBegin(.words(10), replacing: applicationID, systemIsDark: false); XCTFail("Concurrent edit accepted") }
      catch WebsiteConfigImportWorkflowError.busy {}
      switch cause {
      case "cancel": workflow.cancel()
      case "task": task.cancel()
      case "input":
        var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
      case "owner": f.page.detach()
      default:
        let register = WebsiteConfigFileRegister(directory: f.directory)
        let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":9}"#, pointsPerRem: 16, context: .init())
        guard case .committed = try register.commit(draft, replacing: XCTUnwrap(register.read().revision)) else {
          return XCTFail("Conflict setup failed")
        }
      }
      let bytes = try Data(contentsOf: path)
      gate.resolve()
      do { _ = try await task.value; XCTFail("Retired edit committed") } catch {}
      XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(try Data(contentsOf: path), bytes)
      if cause == "input" { XCTAssertEqual(f.page.state.session.typed, "a") }
    }
  }

  func testActiveEditingClosesAndRecordsOldAttemptButCannotBypassMissingProfile() async throws {
    let f = try Fixture(); defer { f.close() }
    do { try await f.workflow.editAndBegin(.words(5), replacing: UUID(), systemIsDark: false); XCTFail("Legacy page edited") } catch {}
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
    try await f.workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let attempt = f.page.state.session.automaticInputAttemptID
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    try await f.workflow.editAndBegin(.words(5), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 5)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertFalse(f.page.acceptsAttemptCallback(for: attempt))
    XCTAssertNotNil(f.page.restartController)
  }

  func testActiveEditPersistsAndClosesInputBeforeQuotePreparation() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"quoteLength":[0]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let attempt = f.page.state.session.automaticInputAttemptID
    let task = Task { try await workflow.editAndBegin(.mode(.quote), replacing: publication.applicationID, systemIsDark: false) }
    defer { task.cancel() }
    try await gate.wait()
    XCTAssertEqual(f.page.state.session.outcome, .abandoned)
    XCTAssertNotNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertFalse(f.page.acceptsInput(for: attempt))
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    guard case .available(let runtime) = try WebsiteConfigFileRegister(directory: f.directory).read().state else {
      return XCTFail("Setter must already be durable")
    }
    XCTAssertEqual(runtime["mode"], .string("quote"))
    gate.resolve(); _ = try await task.value
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testIdleAndCompletedSetterSaveBeforeLoadAndResumeWithoutIncompleteAccounting() async throws {
    for completed in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let gate = Gate(); defer { gate.resolve() }
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
      defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"words","words":2,"quoteLength":[0]}"#, systemIsDark: false)
      var state = f.page.state
      if completed {
        state.session.insertBatch(state.session.prompt + " ")
        XCTAssertEqual(state.session.outcome, .completed)
      }
      state.priorAttemptLedger.recordRestart(engagedDuration: 2, accuracy: 90, savingEnabled: true)
      f.page.replace(state)
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      let task = Task { try await workflow.editAndBegin(.mode(.quote), replacing: publication.applicationID, systemIsDark: false) }
      try await gate.wait()
      XCTAssertEqual(f.page.state.session.generationState, state.session.generationState)
      XCTAssertEqual(f.page.state.priorAttemptLedger, state.priorAttemptLedger)
      XCTAssertFalse(f.page.acceptsInput(for: state.session.automaticInputAttemptID))
      let pending = try XCTUnwrap(f.page.state.configurationDeparture)
      let register = WebsiteConfigFileRegister(directory: f.directory)
      guard case .available(let runtime) = try register.read().state else { return XCTFail("Setter record missing") }
      XCTAssertEqual(runtime["mode"], .string("quote"))
      let disk = try register.read().revision
      task.cancel(); gate.resolve()
      do { _ = try await task.value; XCTFail("Cancelled preparation delivered") } catch is CancellationError {}
      XCTAssertEqual(f.page.state.configurationDeparture?.id, pending.id)
      XCTAssertEqual(try register.read().revision, disk)
      let retry = Task { try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false) }
      try await gate.wait(); gate.resolve(); _ = try await retry.value
      XCTAssertEqual(try register.read().revision, disk)
      XCTAssertEqual(f.page.state.priorAttemptLedger, state.priorAttemptLedger)
      XCTAssertNil(f.page.state.configurationDeparture)
      XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
    }
  }

  func testCancelledActiveEditCanResumeWithoutSetterReplayOrDuplicateLedger() async throws {
    for cancelTask in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let gate = Gate(); defer { gate.resolve() }
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in await gate.read() })
      defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"words","words":4,"quoteLength":[0]}"#, systemIsDark: false)
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
      let task = Task { try await workflow.editAndBegin(.mode(.quote), replacing: publication.applicationID, systemIsDark: false) }
      try await gate.wait()
      let pending = try XCTUnwrap(f.page.state.configurationDeparture)
      let register = WebsiteConfigFileRegister(directory: f.directory)
      let revision = try register.read().revision
      do { try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false); XCTFail("Concurrent resume accepted") }
      catch WebsiteConfigImportWorkflowError.busy {}
      if cancelTask { task.cancel() } else { workflow.cancel() }
      gate.resolve()
      do { _ = try await task.value; XCTFail("Cancelled candidate delivered") } catch is CancellationError {}
      XCTAssertEqual(f.page.state.configurationDeparture?.id, pending.id)
      XCTAssertEqual(try register.read().revision, revision)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
      do { try await workflow.editAndBegin(.words(8), replacing: publication.applicationID, systemIsDark: false); XCTFail("Pending setter replayed") }
      catch WebsiteConfigImportWorkflowError.preparationPending {}
      do { try await workflow.resumeAndBegin(departureID: UUID(), systemIsDark: false); XCTFail("Stale resume accepted") }
      catch WebsiteConfigImportWorkflowError.conflict {}
      let retry = Task { try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false) }
      try await gate.wait(); gate.resolve(); _ = try await retry.value
      XCTAssertNil(f.page.state.configurationDeparture)
      XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
      XCTAssertEqual(try register.read().revision, revision)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.events.filter { $0.key == "mode" }.count, 1)
      XCTAssertNotNil(f.page.restartController)
    }
  }

  func testProviderFailureReportsSavedStateAndRetryPreservesAcceptedSetting() async throws {
    let f = try Fixture(); defer { f.close() }
    var fail = true
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        if fail { throw Failure.provider }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"quoteLength":[0]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    do {
      try await workflow.editAndBegin(.mode(.quote), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTFail("Failed provider delivered")
    } catch let error as WebsiteConfigSavedPreparationError {
      XCTAssertEqual(error.underlying as? Failure, .provider)
    }
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let revision = try register.read().revision
    do { try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false); XCTFail("Failed retry delivered") }
    catch is WebsiteConfigSavedPreparationError {}
    XCTAssertEqual(try register.read().revision, revision)
    fail = false
    try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertEqual(try register.read().revision, revision)
    XCTAssertNil(f.page.state.configurationDeparture)
  }

  func testWorkflowCancelAndResumeKeepAlreadySavedInitCorrection() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    var suspend = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        if suspend { return await gate.read() }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .hindi, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","language":"hindi","lazyMode":false,"quoteLength":[0],"repeatQuotes":"off"}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    suspend = true
    let task = Task { try await workflow.editAndBegin(.lazyMode(true), replacing: publication.applicationID, systemIsDark: false) }
    try await gate.wait()
    let register = WebsiteConfigFileRegister(directory: f.directory)
    XCTAssertTrue(try register.read().lazyMemory.remember)
    let disk = try register.read().revision
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertFalse(pending.draft.generators.lazyMode)
    workflow.cancel(); gate.resolve()
    do { _ = try await task.value; XCTFail("Cancelled initializer delivered") } catch is CancellationError {}
    XCTAssertEqual(f.page.state.configurationDeparture?.id, pending.id)
    XCTAssertEqual(try register.read().revision, disk)
    let retry = Task { try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false) }
    try await gate.wait(); gate.resolve(); _ = try await retry.value
    XCTAssertEqual(try register.read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.events.filter { $0.key == "lazyMode" }.count, 2)
    XCTAssertNotNil(f.page.restartController)
  }

  func testNoQuitActiveEditLeavesConfigurationAndAttemptLive() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["no_quit"]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let revision = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    let id = f.page.state.session.automaticInputAttemptID
    do { try await f.workflow.editAndBegin(.words(8), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false); XCTFail("No Quit bypassed") }
    catch WebsiteConfigImportWorkflowError.rejectedRestartFailed {}
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, revision)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, id)
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertFalse(f.page.state.session.isFinished)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
  }

  func testAllPracticeSetterActionsCanRestartAnActivePublishedAttempt() async throws {
    let actions: [WebsiteConfigPracticeEdit] = [.mode(.time), .time(17), .words(6), .difficulty(.expert),
      .punctuation(true), .numbers(true), .quoteLengths([0]), .language("english"), .lazyMode(true)]
    for action in actions {
      let f = try Fixture(); defer { f.close() }
      let legacy = f.settings.snapshot
      try await f.workflow.apply(json: #"{"mode":"words","words":4,"language":"spanish"}"#, systemIsDark: false)
      let old = f.page.state.session.automaticInputAttemptID
      var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
      try await f.workflow.editAndBegin(action, replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, old, action.key)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1, action.key)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime[action.key], action.value, action.key)
      XCTAssertEqual(f.settings.snapshot, legacy, action.key)
      XCTAssertNil(f.page.state.configurationDeparture, action.key)
    }
  }

  func testObservationRetirementAfterSaveDoesNotReportSetterRollback() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    withObservationTracking { _ = f.page.state } onChange: {
      MainActor.assumeIsolated { f.page.detach() }
    }
    let message = try await f.workflow.editAndBegin(.words(6), replacing: publication.applicationID, systemIsDark: false)
    XCTAssertTrue(message.contains("设置已保存"))
    XCTAssertTrue(message.contains("窗口已变化"))
    XCTAssertEqual(f.page.state.session.outcome, .abandoned)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertEqual(pending.draft.testParameters.wordLimit, 6)
    guard case .available(let runtime) = try WebsiteConfigFileRegister(directory: f.directory).read().state else {
      return XCTFail("Accepted setting lost")
    }
    XCTAssertEqual(runtime["words"], .number(6))
    do { try await f.workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false); XCTFail("Detached window resumed") }
    catch is WebsiteConfigSavedPreparationError {}
  }

  func testRetiredEditorCannotEditAReplacementPublication() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4}"#, systemIsDark: false)
    let old = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    try await f.workflow.apply(json: #"{"mode":"words","words":9}"#, systemIsDark: false)
    do { try await f.workflow.editAndBegin(.words(5), replacing: old, systemIsDark: false); XCTFail("Stale editor applied") }
    catch WebsiteConfigImportWorkflowError.conflict {}
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 9)
  }

  func testFinishedAttemptCanEditThroughFormWithoutClearingPriorLedger() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"difficulty":"master"}"#, systemIsDark: false)
    var state = f.page.state
    state.session.insertBatch("§")
    XCTAssertTrue(state.session.isFinished)
    state.priorAttemptLedger.recordRestart(engagedDuration: 2, accuracy: 90, savingEnabled: true)
    f.page.replace(state)
    let ledger = f.page.state.priorAttemptLedger
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let oldAttempt = f.page.state.session.automaticInputAttemptID
    let form = WebsiteConfigPracticeEditForm(draft: publication.draft)
    form.limit = "6"
    form.startLimit(timed: false, apply: {
      try await f.workflow.editAndBegin($0, replacing: publication.applicationID, systemIsDark: false)
    })
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while form.isWorking && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertFalse(form.isWorking); XCTAssertTrue(form.message?.contains("已保存") == true)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 6)
    XCTAssertFalse(f.page.state.session.isFinished)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, oldAttempt)
    XCTAssertFalse(f.page.acceptsInput(for: oldAttempt))
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
  }

  func testDifficultyAndContentEditsApplyToRealSessionWithoutReimportingOtherFields() async throws {
    let f = try Fixture(); defer { f.close() }
    let legacy = f.settings.snapshot
    try await f.workflow.apply(json: #"{"mode":"words","words":8,"theme":"dracula","quoteLength":[0,0,1]}"#, systemIsDark: false)
    for edit in [WebsiteConfigPracticeEdit.difficulty(.expert), .punctuation(true), .numbers(true),
      .difficulty(.master), .punctuation(false), .numbers(false)] {
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      let attempt = f.page.state.session.automaticInputAttemptID
      var expected = publication.draft.projection.runtime; expected[edit.key] = edit.value
      try await f.workflow.editAndBegin(edit, replacing: publication.applicationID, systemIsDark: false)
      let draft = try XCTUnwrap(f.page.state.presentation).publication.draft
      XCTAssertEqual(draft.projection.runtime, expected)
      guard case .edited(let change) = draft.origin else { return XCTFail("Edit became import") }
      XCTAssertEqual(change.key, edit.key)
      XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(f.page.state.session.configuration.difficulty, draft.inputRules.difficulty)
      XCTAssertEqual(f.page.state.session.configuration.contentOptions, draft.testParameters.contentOptions)
      XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .available(expected))
    }
    XCTAssertEqual(f.settings.snapshot, legacy)
  }

  func testQuoteLengthSameValueRebuildsWeightedQueueButDifficultyPreservesIt() async throws {
    let f = try Fixture(); defer { f.close() }
    let quotes: [OfflineQuote] = [("one", QuoteLength.short), ("two", .short), ("three", .medium)].map {
      .init(id: $0.0, title: "Owned editor sample", text: "ab cd", language: .english, length: $0.1)
    }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in quotes })
    defer { workflow.stop() }
    func budget() throws -> Int? {
      var sampler = try XCTUnwrap(f.page.state.practice?.scope.quoteSampler)
      var budget: Int?
      _ = try sampler.next(randomIndex: { budget = $0; return 0 })
      return budget
    }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0,0,1]}"#, systemIsDark: false)
    XCTAssertEqual(try budget(), 4)
    try await workflow.editAndBegin(.difficulty(.expert), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(try budget(), 3)
    try await workflow.editAndBegin(.quoteLengths([0,0,1]), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(try budget(), 4)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [0,0,1])
    try await workflow.editAndBegin(.mode(.words), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    try await workflow.editAndBegin(.quoteLengths([0,0]), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
    XCTAssertEqual(try budget(), 3)
  }

  func testUnavailableQuoteGroupAutomaticallySavesAllLengthsAndRetries() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        return [.init(id: "owned", title: "Owned", text: "ab", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let attempt = f.page.state.session.automaticInputAttemptID
    let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let bytes = try Data(contentsOf: path)
    reads = 0
    let message = try await workflow.editAndBegin(.quoteLengths([3]), replacing: publication.applicationID, systemIsDark: false)
    XCTAssertTrue(message.contains("已改为全部长度"))
    XCTAssertEqual(reads, 2, "Retry only after applying the source recovery")
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertNotEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
    XCTAssertEqual(f.page.state.practice?.scope.quoteSampler?.selection.groups, [0,1,2,3])
    XCTAssertNotEqual(try Data(contentsOf: path), bytes)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.quoteSelection.groups, [0,1,2,3])
    XCTAssertEqual(f.page.state.presentation?.publication.quoteRecoveries, [.allLengths])
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    try await workflow.editAndBegin(.punctuation(true), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertFalse(f.page.state.session.configuration.contentOptions.includePunctuation)
  }

  func testEmptyQuoteCatalogRecoversToWordsWithoutChangingLanguage() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in reads += 1; return [] })
    defer { workflow.stop() }
    let message = try await workflow.apply(json: #"{"mode":"quote","words":4,"language":"spanish"}"#, systemIsDark: false)
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(f.page.state.session.configuration.mode, .words)
    XCTAssertEqual(f.page.state.session.configuration.language, .spanish)
    XCTAssertEqual(f.page.state.presentation?.publication.quoteRecoveries, [.wordsMode])
    XCTAssertTrue(message.contains("已切换为词数练习"))
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 4)
  }

  func testQuoteRecoveryStopsAfterThreeAttemptsAndRetainsSavedCorrection() async throws {
    let f = try Fixture(); defer { f.close() }
    var invalid = false, reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        return [.init(id: "owned", title: "Owned bounded sample", text: "ab", language: .english,
          length: invalid ? .all : .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0]}"#, systemIsDark: false)
    reads = 0; invalid = true
    do {
      try await workflow.editAndBegin(.quoteLengths([3]), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTFail("Unusable catalog delivered")
    } catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigSessionBuildError.quoteRecoveryLimitReached = error.underlying else {
        return XCTFail("Unexpected failure: \(error)")
      }
      XCTAssertTrue(error.localizedDescription.contains("三次"))
    }
    XCTAssertEqual(reads, 3)
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertEqual(pending.draft.quoteSelection.groups, [0,1,2,3])
    XCTAssertEqual(pending.draft.projection.events.filter { $0.key == "quoteLength" }.count, 4)
    let disk = try WebsiteConfigFileRegister(directory: f.directory).read().revision
    invalid = false
    try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
    XCTAssertNotNil(f.page.restartController)
  }

  func testReaderReconfigurationErrorIsNotMisclassifiedAsSamplerRecovery() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        throw WebsiteConfigSessionBuildError.reconfigurationRequired(["quoteLength": .array((0...3).map { .number(Double($0)) })])
      })
    defer { workflow.stop() }
    do { try await workflow.apply(json: #"{"mode":"quote","quoteLength":[3]}"#, systemIsDark: false); XCTFail("Reader failure replaced content") }
    catch WebsiteConfigSessionBuildError.reconfigurationRequired {}
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(try WebsiteConfigFileRegister(directory: f.directory).read().state, .missing)
  }

  func testCancellationDuringAutomaticQuoteRetryKeepsRecoveryAndItsExplanation() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    var reads = 0, park = true
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        if reads > 1 && park { return await gate.read() }
        return [.init(id: "owned", title: "Owned retry sample", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"quoteLength":[3]}"#, systemIsDark: false)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let id = try XCTUnwrap(f.page.state.presentation).publication.applicationID
    let task = Task { try await workflow.editAndBegin(.mode(.quote), replacing: id, systemIsDark: false) }
    try await gate.wait()
    XCTAssertEqual(reads, 2)
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    XCTAssertEqual(pending.draft.quoteSelection.groups, [0,1,2,3])
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let disk = try register.read().revision
    workflow.cancel(); gate.resolve()
    do { _ = try await task.value; XCTFail("Cancelled retry delivered") } catch is CancellationError {}
    XCTAssertEqual(try register.read().revision, disk)
    park = false
    let message = try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertTrue(message.contains("已改为全部长度"))
    XCTAssertEqual(f.page.state.presentation?.publication.quoteRecoveries, [.allLengths])
    XCTAssertEqual(try register.read().revision, disk)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testCompetingRecordStopsAutomaticQuoteRecoveryBeforeRetry() async throws {
    let f = try Fixture(); defer { f.close() }
    var reads = 0
    let register = WebsiteConfigFileRegister(directory: f.directory)
    let competitor = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":9}"#,
      pointsPerRem: 16, context: .init())
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        reads += 1
        guard case .committed = try register.commit(competitor, replacing: XCTUnwrap(register.read().revision)) else {
          throw Failure.provider
        }
        return [.init(id: "owned", title: "Owned conflict sample", text: "ab", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":4,"quoteLength":[3]}"#, systemIsDark: false)
    do {
      try await workflow.editAndBegin(.mode(.quote), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
      XCTFail("Recovery overwrote a competing record")
    } catch let error as WebsiteConfigSavedPreparationError {
      guard case WebsiteConfigCommitCoordinatorError.stale = error.underlying else { return XCTFail("Unexpected error") }
    }
    XCTAssertEqual(reads, 1)
    XCTAssertEqual(try register.read().state, .available(competitor.projection.runtime))
    XCTAssertEqual(f.page.state.configurationDeparture?.draft.quoteSelection.groups, [3])
  }

  func testFalseSetterReturnKeepsConfigurationButStillDispatchesOrdinaryRestart() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["binary"]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let bytes = try Data(contentsOf: path)
    for edit in [WebsiteConfigPracticeEdit.punctuation(true), .numbers(true), .quoteLengths([99]), .mode(.zen), .time(.nan), .words(-1)] {
      let attempt = f.page.state.session.automaticInputAttemptID
      let message = try await f.workflow.editAndBegin(edit, replacing: publication.applicationID, systemIsDark: false)
      XCTAssertTrue(message.contains("设置未修改"))
      XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime, publication.draft.projection.runtime)
      XCTAssertFalse(f.page.acceptsInput(for: attempt))
      XCTAssertEqual(try Data(contentsOf: path), bytes)
    }
    try await f.workflow.editAndBegin(.difficulty(.expert), replacing: publication.applicationID, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.configuration.difficulty, .expert)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime["funbox"], .array([.string("binary")]))
  }

  func testThrownOverrideDoesNotDispatchTheFollowingRestartEvent() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["binary"]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let attempt = f.page.state.session.automaticInputAttemptID
    do { try await f.workflow.editAndBegin(.quoteLengths([0]), replacing: publication.applicationID, systemIsDark: false); XCTFail("Throwing override accepted") }
    catch WebsiteConfigProjectionError.failedOverride {}
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertNil(f.page.state.restartDepartureAttemptID)
  }

  func testRejectedRestartCancellationOwnerLossAndDiskConflictKeepRecordAndWeightedQueue() async throws {
    for cause in ["cancel", "task", "owner", "disk"] {
      let f = try Fixture(); defer { f.close() }
      let gate = Gate(); defer { gate.resolve() }
      var parked = false
      let quotes: [OfflineQuote] = [("one", QuoteLength.short), ("two", .short), ("three", .medium)].map {
        .init(id: $0.0, title: "Owned rejected restart sample", text: "ab cd", language: .english, length: $0.1)
      }
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
          if parked { return await gate.read() }; return quotes
        })
      defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0,0,1],"funbox":["rot13"],"repeatQuotes":"off"}"#, systemIsDark: false)
      var state = f.page.state
      state.priorAttemptLedger.recordRestart(engagedDuration: 2, accuracy: 90, savingEnabled: true)
      f.page.replace(state)
      let ledger = state.priorAttemptLedger
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      let attempt = f.page.state.session.automaticInputAttemptID
      let controller = try XCTUnwrap(f.page.restartController)
      let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
      func budget() throws -> Int? {
        var sampler = try XCTUnwrap(f.page.state.practice?.scope.quoteSampler)
        var result: Int?; _ = try sampler.next(randomIndex: { result = $0; return 0 }); return result
      }
      XCTAssertEqual(try budget(), 4)
      parked = true
      let task = Task { try await workflow.editAndBegin(.mode(.zen), replacing: publication.applicationID, systemIsDark: false) }
      try await gate.wait()
      XCTAssertTrue(controller.isPreparing); XCTAssertFalse(controller.request())
      XCTAssertFalse(f.page.acceptsInput(for: attempt))
      XCTAssertEqual(f.page.state.restartDepartureAttemptID, attempt)
      switch cause {
      case "cancel": workflow.cancel()
      case "task": task.cancel()
      case "owner": f.page.detach()
      default:
        let register = WebsiteConfigFileRegister(directory: f.directory)
        let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"words","words":9}"#, pointsPerRem: 16, context: .init())
        guard case .committed = try register.commit(draft, replacing: XCTUnwrap(register.read().revision)) else {
          return XCTFail("Conflict setup failed")
        }
      }
      let bytes = try Data(contentsOf: path)
      gate.resolve()
      do { _ = try await task.value; XCTFail("Retired restart installed") }
      catch {
        XCTAssertTrue(error is CancellationError || (error as? WebsiteConfigImportWorkflowError) == .rejectedRestartFailed)
      }
      XCTAssertFalse(controller.isPreparing)
      XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
      XCTAssertEqual(try Data(contentsOf: path), bytes)
      XCTAssertEqual(try budget(), 4)
      if cause == "cancel" || cause == "task" {
        parked = false
        let message = try await workflow.editAndBegin(.mode(.zen), replacing: publication.applicationID, systemIsDark: false)
        XCTAssertTrue(message.contains("设置未修改"))
        XCTAssertEqual(try budget(), 3, "A false setter must not rebuild the quote-length queue")
        XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
        XCTAssertNil(f.page.state.restartDepartureAttemptID)
      }
    }
  }

  func testBusyOrdinaryRestartIsNotRetiredByAnEdit() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    var parked = false
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        if parked { return await gate.read() }
        return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
      })
    defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"repeatQuotes":"off"}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let attempt = f.page.state.session.automaticInputAttemptID
    let controller = try XCTUnwrap(f.page.restartController)
    parked = true; XCTAssertTrue(controller.request()); try await gate.wait()
    do { try await workflow.editAndBegin(.quoteLengths([99]), replacing: publication.applicationID, systemIsDark: false); XCTFail("Busy restart was replaced") }
    catch WebsiteConfigImportWorkflowError.busy {}
    gate.resolve()
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while controller.isPreparing && ContinuousClock.now < deadline { await Task.yield() }
    XCTAssertFalse(controller.isPreparing); XCTAssertNil(controller.message)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
  }

  func testCancellationAtTheDeliveryObservationDoesNotFalselyReportUnappliedRestart() async throws {
    for cause in ["workflow", "task"] {
      let f = try Fixture(); defer { f.close() }
      let gate = Gate(); defer { gate.resolve() }
      var parked = false
      let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
        directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
          if parked { return await gate.read() }
          return [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)]
        })
      defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"funbox":["rot13"],"repeatQuotes":"off"}"#, systemIsDark: false)
      let publication = try XCTUnwrap(f.page.state.presentation).publication
      let attempt = f.page.state.session.automaticInputAttemptID
      parked = true
      let task = Task { try await workflow.editAndBegin(.mode(.zen), replacing: publication.applicationID, systemIsDark: false) }
      try await gate.wait()
      // Departure has already been accepted. The next state change is the
      // synchronous delivery, not generation or a pre-admission cancellation.
      withObservationTracking { _ = f.page.state } onChange: {
        MainActor.assumeIsolated {
          XCTAssertFalse(f.page.acceptsInput(for: attempt))
          if cause == "workflow" { workflow.cancel() } else { task.cancel() }
        }
      }
      gate.resolve()
      do {
        let message = try await task.value
        XCTAssertTrue(message.contains("设置未修改")); XCTAssertTrue(message.contains("新的练习"))
      } catch { XCTFail("A delivered restart was reported as unapplied: \(error)") }
      XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
      XCTAssertNil(f.page.state.restartDepartureAttemptID)
    }
  }

  func testFalseSetterCannotBypassActiveNoQuitDepartureAdmission() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.workflow.apply(json: #"{"mode":"words","words":4,"funbox":["binary","no_quit"]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let attempt = state.session.automaticInputAttemptID
    XCTAssertTrue(state.session.hasStarted); XCTAssertFalse(state.session.isFinished)
    do { try await f.workflow.editAndBegin(.punctuation(true), replacing: publication.applicationID, systemIsDark: false); XCTFail("No Quit bypassed") }
    catch WebsiteConfigImportWorkflowError.rejectedRestartFailed {}
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.page.state.session.typed, "a")
    XCTAssertNil(f.page.state.restartDepartureAttemptID)
    XCTAssertEqual(f.page.state.priorAttemptLedger, state.priorAttemptLedger)
  }

  func testCancelledLengthPreparationKeepsPublishedQueueAndResumesSavedSelection() async throws {
    let f = try Fixture(); defer { f.close() }
    let gate = Gate(); defer { gate.resolve() }
    var parked = false
    let quotes: [OfflineQuote] = [("one", QuoteLength.short), ("two", .short), ("three", .medium)].map {
      .init(id: $0.0, title: "Owned cancellation sample", text: "ab", language: .english, length: $0.1)
    }
    let workflow = WebsiteConfigImportWorkflow(page: f.page, settings: f.settings, account: f.account,
      directory: f.directory, readWindow: { f.window }, loadQuotes: { _ in
        if parked { return await gate.read() }; return quotes
      })
    defer { workflow.stop() }
    func budget() throws -> Int? {
      var sampler = try XCTUnwrap(f.page.state.practice?.scope.quoteSampler)
      var budget: Int?; _ = try sampler.next(randomIndex: { budget = $0; return 0 }); return budget
    }
    try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0,0,1]}"#, systemIsDark: false)
    let publication = try XCTUnwrap(f.page.state.presentation).publication
    let path = f.directory.appendingPathComponent(WebsiteConfigFileRegister.dataFilename)
    let bytes = try Data(contentsOf: path)
    parked = true
    let task = Task { try await workflow.editAndBegin(.quoteLengths([0,0,1]), replacing: publication.applicationID, systemIsDark: false) }
    try await gate.wait()
    XCTAssertEqual(try budget(), 4)
    let savedBytes = try Data(contentsOf: path)
    XCTAssertNotEqual(savedBytes, bytes, "A same-value setter still saves before preparation")
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    task.cancel(); gate.resolve()
    do { _ = try await task.value; XCTFail("Cancelled quote draw applied") } catch is CancellationError {}
    XCTAssertEqual(try budget(), 4)
    XCTAssertEqual(try Data(contentsOf: path), savedBytes)
    parked = false
    try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertEqual(try Data(contentsOf: path), savedBytes)
    XCTAssertEqual(try budget(), 4, "The saved length event rebuilds the pool on eventual delivery")
    try await workflow.editAndBegin(.difficulty(.expert), replacing: XCTUnwrap(f.page.state.presentation).publication.applicationID, systemIsDark: false)
    XCTAssertEqual(try budget(), 3)
  }
}
