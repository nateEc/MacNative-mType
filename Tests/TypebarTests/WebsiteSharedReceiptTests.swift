import XCTest
import Observation
@testable import Typebar

@MainActor final class WebsiteSharedReceiptTests: XCTestCase {
  @MainActor private final class Fixture {
    let suite = "typebar.shared-receipt.\(UUID())"
    let defaults: UserDefaults, settings: AppSettings, account: AccountSession
    let page = PracticePageSessionStore()
    let environment: WebsiteConfigEnvironmentSource
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-shared-receipt-\(UUID())")
    let register: WebsiteConfigFileRegister
    lazy var source = WebsiteConfigPracticeScopeSource(environment: environment, readWindow: { [page] in
      .published(owner: page.owner, revision: page.state.session.automaticInputAttemptID,
        scope: page.state.sharedReceipt?.scope ?? page.state.practice?.scope ?? .init())
    })
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: settings.preferenceConfigurationSaves,
      register: register, environment: { [environment] in environment.read() })
    init() throws {
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = .init(defaults: defaults, localBackgroundStore: .inMemory()); account = .init(defaults: defaults)
      environment = .init(settings: settings, account: account, pointsPerRem: 16, documentComplete: true, development: false)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      settings.preferenceConfigurationSaves.register(owner: page.owner, save: { XCTFail("No legacy save") })
      page.attach(to: settings.preferenceConfigurationSaves)
    }
    func publish(_ json: String = #"{"mode":"words","words":5}"#) async throws {
      let draft = try coordinator.prepare(json)
      let resources = try coordinator.prepareResources(for: draft, localFont: .absent, localBackground: .absent)
      let custom = try WebsiteCustomTextSettings(value: .object(["text": .array([.string("aa"), .string("bb")]),
        "mode": .string("repeat"), "limit": .object(["mode": .string("word"), "value": .number(2)]), "pipeDelimiter": .bool(false)]))
      let ready = try await coordinator.preparePractice(for: resources, scope: .init(websiteCustomText: custom))
      guard case .committed = try coordinator.commit(ready, to: page, systemIsDark: false) else { return XCTFail("Seed failed") }
    }
    func close() {
      source.stop(); environment.stop(); page.detach(); defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
    func settle() async throws {
      let deadline = ContinuousClock.now.advanced(by: .seconds(2))
      while environment.read() == nil && ContinuousClock.now < deadline { await Task.yield() }
      _ = try XCTUnwrap(environment.read())
    }
    func makeWorkflow(loadQuotes: @escaping @MainActor (TypingLanguage) async throws -> [OfflineQuote] = {
      OfflineContent.quotes(for: $0)
    }) throws -> WebsiteConfigImportWorkflow {
      let seed = try WebsiteCustomTextSettings(value: .object(["text": .array([.string("aa"), .string("bb")]),
        "mode": .string("repeat"), "limit": .object(["mode": .string("word"), "value": .number(2)]), "pipeDelimiter": .bool(false)]))
      return .init(page: page, settings: settings, account: account, directory: directory, readWindow: { [page] in
        .published(owner: page.owner, revision: page.state.session.automaticInputAttemptID,
          scope: page.state.sharedReceipt?.scope ?? page.state.practice?.scope ?? .init(websiteCustomText: seed))
      }, loadQuotes: loadQuotes)
    }
  }
  func testAcceptsWindowReceiptAndRetainsSourceOrderedRuntimeInsteadOfSavingFinalState() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let before = f.page.state.session.automaticInputAttemptID
    let receipt = try f.coordinator.acceptSharedReceipt(
      #"["words","17",null,true,false,"arabic","expert",[]]"#, for: f.page, settings: f.settings, refreshingWith: f.source)
    XCTAssertEqual(f.page.state.sharedReceipt?.id, receipt.id)
    XCTAssertEqual(receipt.outcome.state.runtime["words"], .number(17))
    XCTAssertEqual(receipt.outcome.state.settingsStore["language"], .string("arabic"))
    XCTAssertEqual(receipt.outcome.restartStarts, 1)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before)
    guard case .available(let saved) = try f.register.read().state else { return XCTFail("Saved config lost") }
    XCTAssertEqual(saved["words"], .number(5))
    XCTAssertEqual(receipt.outcome.state.savedConfig?["words"], .number(5))
  }

  func testReceiptBecomesOneNewSessionWithoutPromotingTemporarySettings() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let before = f.page.state.session.automaticInputAttemptID, disk = try f.register.read().revision
    let receipt = try f.coordinator.acceptSharedReceipt(#"["words","17",null,true,false,null,"expert",null]"#,
      for: f.page, settings: f.settings, refreshingWith: f.source)
    XCTAssertFalse(f.page.acceptsInput(for: before))
    let ticket = try f.coordinator.resumeSharedReceipt(receipt.id, for: f.page)
    XCTAssertTrue(f.page.state.configurationDeparture?.isSharedReceipt == true)
    XCTAssertFalse(f.page.state.configurationDeparture?.configurationWasSaved ?? true)
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources)
    guard case .committed(let publication) = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("Receipt was not delivered")
    }
    XCTAssertEqual(publication.draft.testParameters.wordLimit, 17)
    XCTAssertEqual(publication.savedDraft.testParameters.wordLimit, 5)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 17)
    XCTAssertEqual(f.page.state.session.configuration.difficulty, .expert)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, before)
    XCTAssertNil(f.page.state.sharedReceipt); XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertThrowsError(try f.coordinator.resumeSharedReceipt(receipt.id, for: f.page))
  }

  func testFailedInitializationResumesWithoutRepeatingReceiptWritesOrDeparture() async throws {
    enum OwnedError: Error { case unavailable }
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    var active = f.page.state; active.session.insertBatch("a"); f.page.replace(active)
    let receipt = try f.coordinator.acceptSharedReceipt(
      #"["quote","42",{"text":["cc","dd"],"mode":"shuffle","limit":{"mode":"word","value":3.5},"pipeDelimiter":true},null,null,null,null,null]"#,
      for: f.page, settings: f.settings, refreshingWith: f.source)
    let generation = f.settings.websiteCustomTextStateGeneration
    let ledger = f.page.state.priorAttemptLedger, attempt = f.page.state.session.automaticInputAttemptID
    let disk = try f.register.read().revision
    try await f.settle()
    let ticket = try f.coordinator.resumeSharedReceipt(receipt.id, for: f.page)
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    var reads = 0
    do {
      _ = try await f.coordinator.preparePractice(for: resources, loadQuotes: { _ in reads += 1; throw OwnedError.unavailable })
      XCTFail("Owned failing loader cannot produce a session")
    } catch OwnedError.unavailable {}
    XCTAssertEqual(reads, 3)
    XCTAssertEqual(try f.register.read().revision, disk)
    _ = f.coordinator.cancel(ticket)
    let next = try f.coordinator.resumeConfigurationRestart(for: f.page)
    let nextResources = try f.coordinator.prepareResources(for: next, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: nextResources, loadQuotes: { _ in
      [.init(id: "owned", title: "Owned content", text: "aa bb cc", language: .english, length: .short)]
    })
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else { return XCTFail("Retry did not deliver") }
    XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertNil(f.page.state.configurationDeparture)
  }

  func testNoQuitRetainsActiveAttemptAndAcceptedIndependentTextAsPendingReceipt() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish(#"{"mode":"words","words":5,"funbox":["no_quit"]}"#)
    var active = f.page.state; active.session.insertBatch("a"); f.page.replace(active)
    f.settings.setNoQuitConfigurationLock(true, for: f.page.owner)
    let before = f.page.state.session.generationState, ledger = f.page.state.priorAttemptLedger
    let receipt = try f.coordinator.acceptSharedReceipt(
      #"["words","17",{"text":["cc","dd"],"mode":"repeat","limit":{"mode":"word","value":7.5},"pipeDelimiter":false},null,null,null,null,null]"#,
      for: f.page, settings: f.settings, refreshingWith: f.source)
    XCTAssertEqual(receipt.outcome.restartStarts, 0)
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
    XCTAssertEqual(f.settings.websiteCustomTextStateRead.settings?.limitValue, 7.5)
    XCTAssertTrue(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
    XCTAssertThrowsError(try f.coordinator.resumeSharedReceipt(receipt.id, for: f.page))
    f.settings.setNoQuitConfigurationLock(false, for: f.page.owner)
  }

  func testUnrepresentableReceiptRetainsRawExportAndCannotFallBackToLegacy() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let json = #"["words","1000000000000000000000000000000",null,null,null,null,null,null]"#
    let receipt = try f.coordinator.acceptSharedReceipt(json, for: f.page, settings: f.settings, refreshingWith: f.source)
    XCTAssertNil(WebsiteConfigExport.draft(in: f.page.state))
    XCTAssertThrowsError(try f.coordinator.resumeSharedReceipt(receipt.id, for: f.page))
    XCTAssertEqual(f.page.state.sharedReceipt?.id, receipt.id)
    let export = SettingsJSONCommandPresentation.exporting(page: f.page.state) { XCTFail("Cannot read legacy state"); return "{}" }
    XCTAssertEqual(export.mode, .exportWebsiteConfig); XCTAssertNil(export.initialError)
    XCTAssertEqual(try WebsiteConfigJSONReader.read(export.initialJSON).importFields, receipt.outcome.state.runtime)
    XCTAssertEqual(try WebsiteConfigJSONReader.read(WebsiteConfigExport.json(in: f.page.state, surface: .settings)).importFields,
      receipt.outcome.state.settingsStore)
  }

  func testRejectedAndRetiredReceiptsCannotOverwriteWindowOrReplayPrefix() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let disk = try f.register.read().revision, before = f.page.state.session.generationState
    XCTAssertThrowsError(try f.coordinator.acceptSharedReceipt("[null]", for: f.page, settings: f.settings, refreshingWith: f.source))
    XCTAssertNil(f.page.state.sharedReceipt); XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(try f.register.read().revision, disk)
    let receipt = try f.coordinator.acceptSharedReceipt(#"[null,null,null,null,null,null,null,null]"#,
      for: f.page, settings: f.settings, refreshingWith: f.source)
    let foreign = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves, register: f.register,
      environment: { [environment = f.environment] in environment.read() })
    XCTAssertThrowsError(try foreign.resumeSharedReceipt(receipt.id, for: f.page))
    f.source.stop()
    XCTAssertThrowsError(try f.coordinator.resumeSharedReceipt(receipt.id, for: f.page))
    XCTAssertEqual(f.page.state.sharedReceipt?.id, receipt.id)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testActualWindowWorkflowAcceptsThenPreparesTheReceiptWithoutSavingNosaveFields() async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":5}"#, systemIsDark: false)
    let application = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let disk = try f.register.read().revision
    let receipt = try workflow.acceptSharedSettings(json: #"["words","17",null,true,false,null,"expert",null]"#, replacing: application)
    try await workflow.continueSharedSettings(receiptID: receipt.id, systemIsDark: false)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 17)
    XCTAssertEqual(f.page.state.session.configuration.difficulty, .expert)
    XCTAssertNil(f.page.state.sharedReceipt); XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertNotNil(f.page.restartController)
  }

  func testWorkflowRetainsFailedReceiptPreparationAndUsesExistingContinueAction() async throws {
    enum OwnedError: Error { case offline }
    let f = try Fixture(); defer { f.close() }
    var unavailable = true
    let workflow = try f.makeWorkflow(loadQuotes: { _ in
      if unavailable { throw OwnedError.offline }
      return [.init(id: "owned", title: "Owned", text: "aa bb cc", language: .english, length: .short)]
    }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":5}"#, systemIsDark: false)
    let application = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let receipt = try workflow.acceptSharedSettings(json:
      #"["quote","42",{"text":["cc","dd"],"mode":"shuffle","limit":{"mode":"word","value":3.5},"pipeDelimiter":true},null,null,null,null,null]"#,
      replacing: application)
    let generation = f.settings.websiteCustomTextStateGeneration, ledger = f.page.state.priorAttemptLedger
    do {
      try await workflow.continueSharedSettings(receiptID: receipt.id, systemIsDark: false)
      XCTFail("Owned failure did not stop preparation")
    } catch is WebsiteSharedReceiptPreparationError {}
    let pending = try XCTUnwrap(f.page.state.configurationDeparture)
    unavailable = false
    try await workflow.resumeAndBegin(departureID: pending.id, systemIsDark: false)
    XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertNotNil(f.page.restartController)
  }

  func testObserverRetiringOwnerStopsLaterWritesAndKeepsAcceptedPrefixWithoutInputAuthority() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish(#"{"mode":"words","words":5,"funbox":["no_quit"]}"#)
    var active = f.page.state; active.session.insertBatch("a"); f.page.replace(active)
    f.settings.setNoQuitConfigurationLock(true, for: f.page.owner)
    withObservationTracking {
      _ = f.settings.websiteCustomTextStateGeneration
    } onChange: {
      MainActor.assumeIsolated {
        let next = UUID()
        f.settings.preferenceConfigurationSaves.register(owner: next, save: {})
        f.settings.preferenceConfigurationSaves.activate(owner: next)
      }
    }
    let receipt = try f.coordinator.acceptSharedReceipt(
      #"[null,null,{"text":["cc","dd"],"mode":"shuffle","limit":{"mode":"word","value":3.5},"pipeDelimiter":true},null,null,null,null,null]"#,
      for: f.page, settings: f.settings, refreshingWith: f.source)
    XCTAssertEqual(receipt.outcome.customWrites.count, 1)
    XCTAssertGreaterThan(receipt.outcome.storageFailures.count, 0)
    XCTAssertEqual(f.settings.websiteCustomTextStateRead.settings?.text, [.string("cc"), .string("dd")])
    XCTAssertEqual(f.settings.websiteCustomTextStateRead.settings?.mode, "repeat")
    XCTAssertEqual(receipt.outcome.restartStarts, 0)
    XCTAssertFalse(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
    XCTAssertThrowsError(try f.coordinator.commitSharedLiveReceipt(receipt.id, for: f.page))
    XCTAssertThrowsError(try f.coordinator.commitSharedLiveReceipt(receipt.id, for: f.page))
    XCTAssertThrowsError(try f.coordinator.resumeSharedReceipt(receipt.id, for: f.page))
    XCTAssertEqual(f.page.state.sharedReceipt?.id, receipt.id)
    f.settings.setNoQuitConfigurationLock(false, for: f.page.owner)
  }

  func testSharePanelRouteDeliversActualSessionWithoutFlatteningOrSavingTemporarySettings() async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":5}"#, systemIsDark: false)
    let application = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let disk = try f.register.read().revision
    let json = #"["words","17",null,true,false,null,"expert",null]"#
    let link = "typebar://test?testSettings=" + (try XCTUnwrap(URICompressedPayload.compress(json)))
    let result = await TestConfigurationShareActions.applyAsync(link, current: .init(configuration: .words(5)),
      challenges: [], notices: f.account.localNotices, applyWebsiteSettings: { value in
        try await workflow.applySharedSettings(json: value, replacing: application, systemIsDark: false)
      }, applyPreset: { _ in XCTFail("Whole-profile links cannot use legacy presets"); return nil },
      loadChallenge: { _ in .rejected })
    XCTAssertTrue(result.shouldDismiss)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 17)
    XCTAssertEqual(f.page.state.session.configuration.difficulty, .expert)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertNil(f.page.state.sharedReceipt); XCTAssertNil(f.page.state.configurationDeparture)
  }

  func testSharePanelCancellationKeepsCheckpointAndContinuationDoesNotReplayCustomWrites() async throws {
    let f = try Fixture(); defer { f.close() }
    @MainActor final class Gate {
      var waiting: CheckedContinuation<[OfflineQuote], Error>?
      var suspend = true
    }
    let gate = Gate()
    let workflow = try f.makeWorkflow(loadQuotes: { _ in
      if gate.suspend { return try await withCheckedThrowingContinuation { gate.waiting = $0 } }
      return [.init(id: "owned", title: "Owned", text: "aa bb cc", language: .english, length: .short)]
    }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":5}"#, systemIsDark: false)
    let application = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let task = Task { @MainActor in
      try await workflow.applySharedSettings(json:
        #"["quote","42",{"text":["cc","dd"],"mode":"shuffle","limit":{"mode":"word","value":3.5},"pipeDelimiter":true},null,null,null,null,null]"#,
        replacing: application, systemIsDark: false)
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while gate.waiting == nil && ContinuousClock.now < deadline { await Task.yield() }
    guard let continuation = gate.waiting else { task.cancel(); return XCTFail("Quote preparation never started") }
    let generation = f.settings.websiteCustomTextStateGeneration, ledger = f.page.state.priorAttemptLedger
    task.cancel(); continuation.resume(throwing: CancellationError())
    do { _ = try await task.value; XCTFail("Cancelled preparation succeeded") } catch is CancellationError {}
    XCTAssertTrue(f.page.state.configurationDeparture?.isSharedReceipt == true)
    gate.suspend = false
    guard case .applied = try await workflow.continuePendingSharedSettings(systemIsDark: false) else {
      return XCTFail("Checkpoint did not continue")
    }
    XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
    XCTAssertNil(f.page.state.configurationDeparture)
  }

  func testExistingNoQuitOrdinaryModePublishesIndependentTextWithoutRestartOrReplay() async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":5,"funbox":["no_quit"]}"#, systemIsDark: false)
    var active = f.page.state; active.session.insertBatch("a"); f.page.replace(active)
    f.settings.setNoQuitConfigurationLock(true, for: f.page.owner)
    defer { f.settings.setNoQuitConfigurationLock(false, for: f.page.owner) }
    let application = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let before = f.page.state.session.generationState
    guard case .applied = try await workflow.applySharedSettings(json:
      #"[null,null,{"text":["cc"],"mode":"repeat","limit":{"mode":"word","value":7.5},"pipeDelimiter":false},null,null,null,null,null]"#,
      replacing: application, systemIsDark: false) else { return XCTFail("Independent text was not published") }
    let generation = f.settings.websiteCustomTextStateGeneration
    do { _ = try await workflow.continuePendingSharedSettings(systemIsDark: false); XCTFail("Cannot consume a receipt twice") }
    catch WebsiteConfigImportWorkflowError.conflict {}
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
    XCTAssertNil(f.page.state.sharedReceipt)
    XCTAssertEqual(f.page.state.practice?.scope.websiteCustomText?.limitValue, 7.5)
  }

  func testFullJSONSupersedingReceiptReportsItsOwnSavedPreparationFailure() async throws {
    enum OwnedError: Error { case offline }
    let f = try Fixture(); defer { f.close() }
    let workflow = try f.makeWorkflow(loadQuotes: { _ in throw OwnedError.offline }); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":5}"#, systemIsDark: false)
    let application = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    _ = try workflow.acceptSharedSettings(json: #"["words","17",null,null,null,null,null,null]"#, replacing: application)
    do {
      try await workflow.apply(json: #"{"mode":"quote"}"#, systemIsDark: false)
      XCTFail("Owned offline quote loader must fail")
    } catch is WebsiteSharedReceiptPreparationError {
      XCTFail("A full JSON import must not be reported as the older link")
    } catch is WebsiteConfigSavedPreparationError {}
    XCTAssertNotNil(f.page.state.savedApplication)
  }

  func testExistingNoQuitCustomReceiptUpdatesLiveLimitWithoutReplacingPoolOrAttempt() async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"custom","funbox":["no_quit"]}"#, systemIsDark: false)
    var active = f.page.state; active.session.insertBatch("a"); f.page.replace(active)
    f.settings.setNoQuitConfigurationLock(true, for: f.page.owner)
    defer { f.settings.setNoQuitConfigurationLock(false, for: f.page.owner) }
    let application = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let before = f.page.state.session.generationState, prompt = f.page.state.session.prompt
    let disk = try f.register.read().revision, ledger = f.page.state.priorAttemptLedger
    guard case .applied = try await workflow.applySharedSettings(json:
      #"[null,null,{"text":["cc","dd"],"mode":"repeat","limit":{"mode":"word","value":7.5},"pipeDelimiter":false},null,null,null,null,null]"#,
      replacing: application, systemIsDark: false) else { return XCTFail("Live settings were withheld") }
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 8)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before.attempt)
    XCTAssertEqual(f.page.state.session.promptTargetID, before.target)
    XCTAssertEqual(f.page.state.session.typed, before.typed)
    XCTAssertEqual(f.page.state.session.prompt, prompt)
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertNil(f.page.state.sharedReceipt); XCTAssertNotNil(f.page.restartController)
    var continued = f.page.state.session
    for _ in 0..<80 where !continued.isFinished {
      continued.insertBatch(continued.nextExpectedCharacter.map(String.init) ?? " ")
    }
    XCTAssertEqual(continued.outcome, .completed)
    XCTAssertEqual(continued.completedWordCount, 8)
    XCTAssertFalse(continued.prompt.contains("cc")); XCTAssertFalse(continued.prompt.contains("dd"))
    XCTAssertEqual(f.page.state.practice?.scope.websiteCustomText?.text, [.string("cc"), .string("dd")])
  }

  func testCancelledLiveReceiptCanContinueWithoutReplayingWrites() async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"custom","funbox":["no_quit"]}"#, systemIsDark: false)
    var active = f.page.state; active.session.insertBatch("a"); f.page.replace(active)
    f.settings.setNoQuitConfigurationLock(true, for: f.page.owner)
    defer { f.settings.setNoQuitConfigurationLock(false, for: f.page.owner) }
    let application = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let receipt = try workflow.acceptSharedSettings(json:
      #"[null,null,{"text":["cc"],"mode":"repeat","limit":{"mode":"time","value":2.5},"pipeDelimiter":false},null,null,null,null,null]"#,
      replacing: application)
    let generation = f.settings.websiteCustomTextStateGeneration
    let before = f.page.state.session.generationState
    let task = Task { @MainActor in try await workflow.continuePendingSharedSettings(systemIsDark: false) }
    task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled delivery was applied") } catch is CancellationError {}
    XCTAssertEqual(f.page.state.sharedReceipt?.id, receipt.id)
    XCTAssertEqual(f.page.state.session.generationState, before)
    guard case .applied = try await workflow.continuePendingSharedSettings(systemIsDark: false) else {
      return XCTFail("Live receipt did not continue")
    }
    XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
    XCTAssertEqual(f.page.state.session.configuration.duration, 2.5)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before.attempt)
  }

  func testNewNoQuitAppliesWordLimitToSameAttemptWithoutRestartOrSavingNosave() async throws {
    try await compareLiveWordLimitReceipt(noSpace: false)
    try await compareLiveWordLimitReceipt(noSpace: true)
  }

  private func compareLiveWordLimitReceipt(noSpace: Bool) async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    try await workflow.apply(json: noSpace ? #"{"mode":"words","words":5,"funbox":["nospace"]}"#
      : #"{"mode":"words","words":5}"#, systemIsDark: false)
    var active = f.page.state; active.session.insertBatch("a"); f.page.replace(active)
    let application = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let before = f.page.state.session.generationState
    let prompt = f.page.state.session.prompt, disk = try f.register.read().revision
    guard case .applied = try await workflow.applySharedSettings(json:
      noSpace ? #"["words","17",null,null,null,null,null,["nospace","no_quit"]]"#
        : #"["words","17",null,null,null,null,null,["no_quit"]]"#,
      replacing: application, systemIsDark: false) else { return XCTFail("New word limit was withheld") }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before.attempt)
    XCTAssertEqual(f.page.state.session.promptTargetID, before.target)
    XCTAssertEqual(f.page.state.session.typed, before.typed)
    XCTAssertEqual(f.page.state.session.prompt, prompt)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 17)
    XCTAssertTrue(f.page.state.session.configuration.modifiers.contains(.noQuit))
    XCTAssertNil(f.page.state.sharedReceipt)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.presentation?.publication.savedDraft.testParameters.wordLimit, 5)
    var continued = f.page.state.session
    for _ in 0..<500 where !continued.isFinished {
      continued.insertBatch(continued.nextExpectedCharacter.map(String.init) ?? " ")
    }
    XCTAssertEqual(continued.outcome, .completed)
    XCTAssertEqual(continued.completedWordCount, 17)
  }

  func testUnrepresentableLiveLimitKeepsRawReceiptWithoutChangingAttemptOrRepeatingWrites() async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"custom","funbox":["no_quit"]}"#, systemIsDark: false)
    var active = f.page.state; active.session.insertBatch("a"); f.page.replace(active)
    f.settings.setNoQuitConfigurationLock(true, for: f.page.owner)
    defer { f.settings.setNoQuitConfigurationLock(false, for: f.page.owner) }
    let application = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let before = f.page.state.session.generationState
    guard case .retained = try await workflow.applySharedSettings(json:
      #"[null,null,{"text":["cc"],"mode":"shuffle","limit":{"mode":"word","value":1e30},"pipeDelimiter":false},null,null,null,null,null]"#,
      replacing: application, systemIsDark: false) else { return XCTFail("Cannot truncate a valid raw limit") }
    let generation = f.settings.websiteCustomTextStateGeneration
    guard case .retained = try await workflow.continuePendingSharedSettings(systemIsDark: false) else {
      return XCTFail("Cannot silently apply an unrepresentable limit")
    }
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.sharedReceipt?.scope.websiteCustomText?.limitValue, 1e30)
    XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
  }

  func testReceivedBoundaryStillAppliesLaterSavingListenerEventsExactlyOnce() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let receipt = try f.coordinator.acceptSharedReceipt(#"[null,null,null,null,null,"arabic",null,null]"#,
      for: f.page, settings: f.settings, refreshingWith: f.source)
    let draft = try WebsiteConfigNativeDraft(received: receipt.outcome, pointsPerRem: 16)
    var projection = draft.projection
    projection.runtime["lazyMode"] = .bool(false)
    projection.events.append(.init(key: "lazyMode", previousValue: .bool(true), newValue: .bool(false), nosave: false))
    let changed = try draft.replacingProjection(projection, memory: draft.lazyMemory, pointsPerRem: 16)
    let applied = try WebsiteConfigLazyModeLifecycle.applyingEvents(changed, pointsPerRem: 16)
    XCTAssertFalse(applied.lazyMemory.prefersArabic)
    XCTAssertEqual(applied.settingsStoreValues["lazyMode"], .bool(false))
    let again = try WebsiteConfigLazyModeLifecycle.applyingEvents(applied, pointsPerRem: 16)
    XCTAssertEqual(again.projection.events, applied.projection.events)
    XCTAssertEqual(again.settingsStoreValues, applied.settingsStoreValues)
  }
}
