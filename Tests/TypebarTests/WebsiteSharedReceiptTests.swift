import XCTest
import Observation
@testable import Typebar

@MainActor final class WebsiteSharedReceiptTests: XCTestCase {
  private final class RejectingWebsiteDefaults: UserDefaults, @unchecked Sendable {
    override func set(_ value: Any?, forKey key: String) {
      if key != WebsiteCustomTextStateStore.storageKey { super.set(value, forKey: key) }
    }
  }
  @MainActor private final class Fixture {
    let suite = "typebar.shared-receipt.\(UUID())"
    let defaults: UserDefaults, settings: AppSettings, account: AccountSession
    let page = PracticePageSessionStore()
    var nativeWindowScope: WebsiteConfigSessionBuilder.Scope?
    let environment: WebsiteConfigEnvironmentSource
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-shared-receipt-\(UUID())")
    let register: WebsiteConfigFileRegister
    lazy var source = WebsiteConfigPracticeScopeSource(environment: environment, readWindow: { [page, weak self] in
      .published(owner: page.owner, revision: page.state.session.automaticInputAttemptID,
        scope: page.state.sharedReceipt?.scope ?? page.state.configurationDeparture?.sharedScope ?? page.state.practice?.scope ?? self?.nativeWindowScope ?? .init())
    })
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: settings.preferenceConfigurationSaves,
      register: register, environment: { [environment] in environment.read() })
    init(rejectWebsiteWrites: Bool = false) throws {
      defaults = try XCTUnwrap(rejectWebsiteWrites ? RejectingWebsiteDefaults(suiteName: suite) : UserDefaults(suiteName: suite))
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
    func nativeBaseline(active: Bool = false) throws -> WebsiteConfigNativeBaseline.Capture {
      settings.fontSize = 40
      let configuration = TestConfiguration.words(3)
      var state = page.state; state.session = .init(configuration: configuration, prompt: "aa bb cc")
      if active { state.session.insertBatch("a") }
      page.replace(state)
      var scope = WebsiteConfigSessionBuilder.Scope(); scope.customText = "cedar river"
      nativeWindowScope = scope
      return try WebsiteConfigNativeBaseline.capture(preferences: settings.snapshot, configuration: configuration, scope: scope,
        layoutFluidLayouts: settings.layoutFluidLayouts, fontFamily: "Courier", pointsPerRem: 16)
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
      return .init(page: page, settings: settings, account: account, directory: directory, readWindow: { [page, weak self] in
        .published(owner: page.owner, revision: page.state.session.automaticInputAttemptID,
          scope: page.state.sharedReceipt?.scope ?? page.state.configurationDeparture?.sharedScope ?? page.state.practice?.scope ?? self?.nativeWindowScope ?? .init(websiteCustomText: seed))
      }, loadQuotes: loadQuotes)
    }
  }
  func testOrdinaryNativeShareActionPublishesWholeRuntimeWithoutSavingIncomingNosaveValues() async throws {
    let f = try Fixture(); defer { f.close() }
    f.settings.fontSize = 40
    let configuration = TestConfiguration.words(3)
    var state = f.page.state; state.session = .init(configuration: configuration, prompt: "aa bb cc"); f.page.replace(state)
    var scope = WebsiteConfigSessionBuilder.Scope(); scope.customText = "cedar river"
    f.nativeWindowScope = scope
    let preferences = f.settings.snapshot
    let baseline = try WebsiteConfigNativeBaseline.capture(preferences: preferences, configuration: configuration,
      scope: scope, layoutFluidLayouts: f.settings.layoutFluidLayouts, fontFamily: "Courier", pointsPerRem: 16)
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    let before = f.page.state.session.automaticInputAttemptID
    let json = #"["words","17",null,null,true,"spanish",null,null]"#
    let link = "typebar://test?testSettings=" + (try XCTUnwrap(URICompressedPayload.compress(json)))
    let result = await TestConfigurationShareActions.applyAsync(link, current: .init(configuration: configuration),
      challenges: [], notices: f.account.localNotices, applyWebsiteSettings: { json in
        try await workflow.applyNativeSharedSettings(json: json, baseline: baseline, systemIsDark: false)
      }, applyPreset: { _ in XCTFail("Ordinary website links must use the whole receiver"); return nil },
      loadChallenge: { _ in .rejected })
    guard result.shouldDismiss else { return XCTFail("Ordinary native receiver did not deliver the full practice: \(result.status ?? "")") }
    let publication = try XCTUnwrap(f.page.state.presentation?.publication)
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, before)
    XCTAssertEqual(publication.draft.projection.runtime["words"], .number(17))
    XCTAssertEqual(publication.draft.projection.runtime["language"], .string("spanish"))
    XCTAssertEqual(publication.draft.projection.runtime["fontSize"], .number(2.5))
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 17)
    XCTAssertEqual(f.page.state.session.configuration.language, .spanish)
    XCTAssertEqual(f.page.state.practice?.scope.websiteCustomText?.text, [.string("cedar"), .string("river")])
    XCTAssertEqual(f.settings.snapshot, preferences)
    guard case .available(let saved) = try f.register.read().state else { return XCTFail("Native baseline was not saved") }
    XCTAssertEqual(saved["words"], .number(3))
    XCTAssertEqual(saved["language"], .string("english"))
    XCTAssertEqual(saved["fontSize"], .number(2.5))
    XCTAssertNil(f.page.state.sharedReceipt); XCTAssertNil(f.page.state.configurationDeparture)
  }

  func testNativeReceiverRejectsAStaleBufferOrParameterMemoryBeforeConversion() async throws {
    for changesText in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let baseline = try f.nativeBaseline()
      var current = try XCTUnwrap(f.nativeWindowScope)
      if changesText { current.customText = "new actual native text" }
      else {
        let m = current.parameterMemory
        current.parameterMemory = .init(duration: 83, wordLimit: m.wordLimit, customTextDuration: m.customTextDuration,
          customTextWordLimit: m.customTextWordLimit, customTextSectionLimit: m.customTextSectionLimit)
      }
      f.nativeWindowScope = current
      let workflow = try f.makeWorkflow(); defer { workflow.stop() }
      let before = f.page.state.session.generationState, generation = f.settings.websiteCustomTextStateGeneration
      do {
        _ = try await workflow.applyNativeSharedSettings(json: #"["words","17",null,null,null,null,null,null]"#,
          baseline: baseline, systemIsDark: false)
        XCTFail("A stale native capture must not replace the window's newer input")
      } catch is WebsiteConfigCommitCoordinatorError {}
      XCTAssertEqual(try f.register.read().state, .missing)
      XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
      XCTAssertEqual(f.page.state.session.generationState, before)
      XCTAssertNil(f.page.state.sharedReceipt)
    }
  }

  func testNativeReceiverIncompleteConversionKeepsJournalAndHealthyRetryDoesNotReplayURL() async throws {
    let f = try Fixture(rejectWebsiteWrites: true); defer { f.close() }
    let baseline = try f.nativeBaseline()
    let workflow = try f.makeWorkflow()
    let before = f.page.state.session.generationState
    let json = #"["words","17",null,null,null,null,null,null]"#
    do {
      _ = try await workflow.applyNativeSharedSettings(json: json, baseline: baseline, systemIsDark: false)
      XCTFail("Dropped text write cannot complete conversion")
    } catch let error as WebsiteNativeSharedStorageError { XCTAssertFalse(error.recovered) }
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertNil(f.page.state.sharedReceipt); XCTAssertFalse(f.page.ownsConfigurationSelection)
    XCTAssertEqual(try f.register.read().state, .unavailable)
    let journal = f.directory.appendingPathComponent(WebsiteConfigFileRegister.archiveJournalFilename)
    XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
    workflow.stop(); f.page.detach()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: f.suite))
    let settings = AppSettings(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}), localBackgroundStore: .inMemory())
    let account = AccountSession(defaults: defaults)
    settings.preferenceConfigurationSaves.register(owner: f.page.owner, save: { XCTFail("No legacy save") })
    f.page.attach(to: settings.preferenceConfigurationSaves)
    let nativeWindow = try XCTUnwrap(f.nativeWindowScope)
    let retry = WebsiteConfigImportWorkflow(page: f.page, settings: settings, account: account, directory: f.directory,
      readWindow: { [page = f.page, scope = nativeWindow] in
        .published(owner: page.owner, revision: page.state.session.automaticInputAttemptID,
          scope: page.state.sharedReceipt?.scope ?? page.state.configurationDeparture?.sharedScope ?? page.state.practice?.scope ?? scope)
      })
    defer { retry.stop() }
    do {
      _ = try await retry.applyNativeSharedSettings(json: json, baseline: baseline, systemIsDark: false)
      XCTFail("Recovery must finish the old conversion before accepting a new link")
    } catch let error as WebsiteNativeSharedStorageError { XCTAssertTrue(error.recovered) }
    XCTAssertFalse(FileManager.default.fileExists(atPath: journal.path))
    XCTAssertNil(f.page.state.sharedReceipt)
    guard case .available(let converted) = try f.register.read().state else { return XCTFail("Conversion did not recover") }
    XCTAssertEqual(converted["words"], .number(3))
    let generation = settings.websiteCustomTextStateGeneration
    guard case .applied = try await retry.applyNativeSharedSettings(json: json, baseline: baseline, systemIsDark: false)
    else { return XCTFail("Native conversion retry failed") }
    XCTAssertEqual(settings.websiteCustomTextStateGeneration, generation)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 17)
    guard case .available(let saved) = try f.register.read().state else { return XCTFail("Converted baseline disappeared") }
    XCTAssertEqual(saved["words"], .number(3))
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 0)
  }

  func testNativeReceiverRejectsChangedPreferencesOrRetiredOwnerBeforeAnyConversion() async throws {
    for changesPreferences in [false, true] {
      let f = try Fixture(); defer { f.close() }; let baseline = try f.nativeBaseline()
      let workflow = try f.makeWorkflow(); defer { workflow.stop() }
      if changesPreferences { f.settings.fontSize = 44 }
      else {
        let other = UUID(); f.settings.preferenceConfigurationSaves.register(owner: other, save: {})
        f.settings.preferenceConfigurationSaves.activate(owner: other)
      }
      do {
        _ = try await workflow.applyNativeSharedSettings(json: #"["words","17",null,null,null,null,null,null]"#,
          baseline: baseline, systemIsDark: false)
        XCTFail("Retired native frame cannot establish a profile")
      } catch is WebsiteConfigCommitCoordinatorError {}
      XCTAssertEqual(try f.register.read().state, .missing)
      XCTAssertEqual(f.settings.websiteCustomTextStateRead, .missing)
      XCTAssertNil(f.page.state.sharedReceipt)
    }
  }

  func testNativeReceiverRetainsExistingSavedProfileAndOwnFallbackText() async throws {
    let f = try Fixture(); defer { f.close() }
    var saved = try WebsiteConfigNativeProfile.defaultDocument().values
    saved["words"] = .number(9); saved["theme"] = .string("dracula")
    guard case .committed = try f.register.commit(runtime: saved, lazyMemory: .init(), replacing: XCTUnwrap(f.register.read().revision))
    else { return XCTFail("Seed failed") }
    let baseline = try f.nativeBaseline()
    let fallback = try f.settings.websiteCustomArchiveStore.fallbackRecordForArchive()
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    guard case .applied = try await workflow.applyNativeSharedSettings(json: #"["words","17",null,null,null,null,null,null]"#,
      baseline: baseline, systemIsDark: false) else { return XCTFail("Native receiver did not apply") }
    XCTAssertEqual(f.page.state.presentation?.publication.draft.testParameters.wordLimit, 17)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime["theme"], .string("paper"))
    XCTAssertEqual(f.page.state.presentation?.publication.savedDraft.testParameters.wordLimit, 9)
    guard case .available(let after) = try f.register.read().state else { return XCTFail("Saved profile disappeared") }
    XCTAssertTrue(WebsiteProfileArchive.sameRuntime(after, saved))
    XCTAssertEqual(try f.settings.websiteCustomArchiveStore.fallbackRecordForArchive(), fallback)
    XCTAssertEqual(f.settings.websiteCustomTextStateRead.settings?.text, [.string("cedar"), .string("river")])
  }

  func testNativeReceiverInvalidPayloadHasNoConversionEffects() async throws {
    let f = try Fixture(); defer { f.close() }
    let baseline = try f.nativeBaseline()
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    let before = f.page.state.session.generationState, generation = f.settings.websiteCustomTextStateGeneration
    do {
      _ = try await workflow.applyNativeSharedSettings(json: "[null]", baseline: baseline, systemIsDark: false)
      XCTFail("Invalid payload must fail before conversion")
    } catch WebsiteSharedSettingsReceiver.Failure.invalidPayload {}
    XCTAssertEqual(try f.register.read().state, .missing)
    XCTAssertEqual(f.settings.websiteCustomTextStateRead, .missing)
    XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertNil(f.page.state.sharedReceipt); XCTAssertFalse(f.page.ownsConfigurationSelection)
  }

  func testNativeReceiverDoesNotMergeForeignLazyMemoryOrWriteItsText() async throws {
    let f = try Fixture(); defer { f.close() }
    let saved = try WebsiteConfigNativeProfile.defaultDocument().values
    let foreignMemory = WebsiteConfigLazyModeMemory(remember: true, prefersArabic: false)
    guard case .committed = try f.register.commit(runtime: saved, lazyMemory: foreignMemory,
      replacing: XCTUnwrap(f.register.read().revision)) else { return XCTFail("Seed failed") }
    let baseline = try f.nativeBaseline()
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    let disk = try f.register.read(), generation = f.settings.websiteCustomTextStateGeneration
    let session = f.page.state.session.generationState, preferences = f.settings.snapshot
    do {
      _ = try await workflow.applyNativeSharedSettings(json: #"["words","17",null,null,null,null,null,null]"#,
        baseline: baseline, systemIsDark: false)
      XCTFail("Different independent memory must not be silently adopted")
    } catch WebsiteConfigNativeBaseline.Failure.unrepresentable("lazyModeMemory") {}
    let after = try f.register.read()
    XCTAssertEqual(after.revision, disk.revision); XCTAssertEqual(after.lazyMemory, foreignMemory)
    guard case .available(let values) = after.state else { return XCTFail("Saved profile disappeared") }
    XCTAssertTrue(WebsiteProfileArchive.sameRuntime(values, saved))
    XCTAssertEqual(f.settings.websiteCustomTextStateRead, .missing)
    XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
    XCTAssertEqual(f.settings.snapshot, preferences)
    XCTAssertEqual(f.page.state.session.generationState, session)
    XCTAssertNil(f.page.state.sharedReceipt); XCTAssertFalse(f.page.ownsConfigurationSelection)
  }

  func testNativePendingReceiptCanReturnWithoutDeletingSavedProfileOrFallback() async throws {
    let f = try Fixture(); defer { f.close() }
    let baseline = try f.nativeBaseline(active: true)
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    guard case .retained = try await workflow.applyNativeSharedSettings(json:
      #"["custom",null,null,null,null,null,null,["no_quit"]]"#,
      baseline: baseline, systemIsDark: false) else { return XCTFail("Expected pending receipt") }
    var state = f.page.state
    for _ in 0..<500 where !state.session.isFinished {
      state.session.insertBatch(state.session.nextExpectedCharacter.map(String.init) ?? " ")
    }
    XCTAssertTrue(state.session.isFinished); f.page.replace(state)
    let disk = try f.register.read().revision, preferences = f.settings.snapshot
    let fallback = try f.settings.websiteCustomArchiveStore.fallbackRecordForArchive()
    let generation = f.settings.websiteCustomTextStateGeneration, ledger = f.page.state.priorAttemptLedger
    let oldAttempt = f.page.state.session.automaticInputAttemptID
    let permit = try f.page.beginLegacyReturn()
    XCTAssertNil(f.page.state.sharedReceipt); XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertFalse(f.page.acceptsInput(for: oldAttempt))
    var native = f.page.state; native.session = .init(configuration: baseline.configuration, prompt: "aa bb cc")
    f.page.replace(native); try f.page.finishLegacyReturn(permit)
    XCTAssertFalse(f.page.ownsConfigurationSelection)
    XCTAssertTrue(f.page.acceptsInput(for: f.page.state.session.automaticInputAttemptID))
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(try f.settings.websiteCustomArchiveStore.fallbackRecordForArchive(), fallback)
    XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
    XCTAssertEqual(f.settings.snapshot, preferences); XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
  }

  func testNativeReceiverNoQuitWaitKeepsOldResultOriginThenContinuesAfterCompletion() async throws {
    let f = try Fixture(); defer { f.close() }
    let baseline = try f.nativeBaseline(active: true)
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    let attempt = f.page.state.session.automaticInputAttemptID
    guard case .retained = try await workflow.applyNativeSharedSettings(json:
      #"["custom",null,{"text":["cc","dd"],"mode":"repeat","limit":{"mode":"word","value":3.5},"pipeDelimiter":false},null,null,null,null,["no_quit"]]"#,
      baseline: baseline, systemIsDark: false) else { return XCTFail("Native No Quit must retain its attempt") }
    XCTAssertTrue(f.page.ownsConfigurationSelection)
    XCTAssertFalse(f.page.ownsPresentedConfigurationSelection)
    XCTAssertTrue(f.page.acceptsInput(for: attempt))
    let generation = f.settings.websiteCustomTextStateGeneration
    var complete = f.page.state
    for _ in 0..<500 where !complete.session.isFinished { complete.session.insertBatch(complete.session.nextExpectedCharacter.map(String.init) ?? " ") }
    XCTAssertEqual(complete.session.outcome, .completed); f.page.replace(complete)
    XCTAssertFalse(f.page.ownsPresentedConfigurationSelection)
    let ledger = f.page.state.priorAttemptLedger
    guard case .applied = try await workflow.continuePendingSharedSettings(systemIsDark: false) else { return XCTFail("Native receipt did not continue") }
    XCTAssertTrue(f.page.ownsPresentedConfigurationSelection)
    XCTAssertEqual(f.page.state.session.configuration.mode, .custom)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 4)
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
    XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
  }

  func testNativeReceiverCancelledPreparationKeepsOneDepartureAndContinuesWithoutReplay() async throws {
    @MainActor final class Gate { var waiting: CheckedContinuation<[OfflineQuote], Error>?; var suspend = true }
    let f = try Fixture(); defer { f.close() }; let gate = Gate()
    let baseline = try f.nativeBaseline(active: true)
    let workflow = try f.makeWorkflow(loadQuotes: { _ in
      if gate.suspend { return try await withCheckedThrowingContinuation { gate.waiting = $0 } }
      return [.init(id: "owned", title: "Owned", text: "cc dd ee", language: .english, length: .short)]
    }); defer { workflow.stop() }
    let task = Task { @MainActor in
      try await workflow.applyNativeSharedSettings(json:
        #"["quote","42",{"text":["cc","dd"],"mode":"repeat","limit":{"mode":"word","value":3.5},"pipeDelimiter":false},null,null,null,null,null]"#,
        baseline: baseline, systemIsDark: false)
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while gate.waiting == nil && ContinuousClock.now < deadline { await Task.yield() }
    guard let waiting = gate.waiting else { task.cancel(); return XCTFail("Native quote preparation never started") }
    let generation = f.settings.websiteCustomTextStateGeneration, ledger = f.page.state.priorAttemptLedger, disk = try f.register.read().revision
    XCTAssertEqual(ledger.restartCount, 1)
    XCTAssertTrue(f.page.state.configurationDeparture?.isNativeSharedReceipt == true)
    task.cancel(); waiting.resume(throwing: CancellationError())
    do { _ = try await task.value; XCTFail("Cancelled native preparation succeeded") } catch is CancellationError {}
    gate.suspend = false
    guard case .applied = try await workflow.continuePendingSharedSettings(systemIsDark: false) else { return XCTFail("Native retry failed") }
    XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
    // ID 42 is not an owned quote ID. The actual source all-length recovery
    // saves quoteLength after the retried catalog loads; that is a new saving
    // event, not a replay of the URL's earlier custom/configuration setters.
    let after = try f.register.read()
    XCTAssertNotEqual(after.revision, disk)
    guard case .available(let saved) = after.state else { return XCTFail("Recovery was not saved") }
    XCTAssertEqual(saved["quoteLength"], .array((0...3).map { .number(Double($0)) }))
    XCTAssertEqual(saved["fontSize"], .number(2.5))
    XCTAssertNotNil(f.page.state.practice?.quote)
    XCTAssertNil(f.page.state.configurationDeparture)
    do { _ = try await workflow.continuePendingSharedSettings(systemIsDark: false); XCTFail("Receipt was consumed twice") }
    catch WebsiteConfigImportWorkflowError.conflict {}
    XCTAssertEqual(try f.register.read().revision, after.revision)
  }

  func testReadOnlyNativeCompatibilityFallbackKeepsLegacyExtensionsAndCanBeCancelled() async throws {
    for cancel in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let current = SavedTestPreset(configuration: .words(3))
      let json = #"["words","17",null,null,null,null,null,null]"#
      let link = "typebar://test?testSettings=" + (try XCTUnwrap(URICompressedPayload.compress(json)))
      var applied = 0
      let task = Task { @MainActor in
        await TestConfigurationShareActions.applyAsync(link, current: current, challenges: [], notices: f.account.localNotices,
          applyWebsiteSettings: { _ in
            if cancel { withUnsafeCurrentTask { $0?.cancel() } }
            throw WebsiteNativeSharedCompatibilityRequired()
          }, applyPreset: { preset in applied += 1; return preset }, loadChallenge: { _ in .rejected })
      }
      let result = await task.value
      XCTAssertEqual(applied, cancel ? 0 : 1)
      XCTAssertEqual(result.shouldDismiss, !cancel)
      XCTAssertEqual(try f.register.read().state, .missing)
      XCTAssertEqual(f.settings.websiteCustomTextStateRead, .missing)
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

  func testFinishedAttemptContinuesRetainedCrossModeReceiptWithoutReplayingWrites() async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = try f.makeWorkflow(); defer { workflow.stop() }
    try await workflow.apply(json: #"{"mode":"words","words":2}"#, systemIsDark: false)
    var active = f.page.state
    active.session.insertBatch(active.session.nextExpectedCharacter.map(String.init) ?? " ")
    f.page.replace(active)
    let application = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let before = f.page.state.session.automaticInputAttemptID, disk = try f.register.read().revision
    guard case .retained = try await workflow.applySharedSettings(json:
      #"["custom",null,{"text":["cc","dd"],"mode":"repeat","limit":{"mode":"word","value":3.5},"pipeDelimiter":false},null,null,null,null,["no_quit"]]"#,
      replacing: application, systemIsDark: false) else { return XCTFail("Cross-mode live receipt must retain the old attempt") }
    let receipt = try XCTUnwrap(f.page.state.sharedReceipt)
    XCTAssertFalse(receipt.requiresInitialization)
    let generation = f.settings.websiteCustomTextStateGeneration
    guard case .retained = try await workflow.continuePendingSharedSettings(systemIsDark: false) else {
      return XCTFail("Active attempt must still withhold this transition")
    }
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, before)
    var complete = f.page.state
    for _ in 0..<500 where !complete.session.isFinished {
      complete.session.insertBatch(complete.session.nextExpectedCharacter.map(String.init) ?? " ")
    }
    XCTAssertEqual(complete.session.outcome, .completed)
    f.page.replace(complete)
    let ledger = f.page.state.priorAttemptLedger
    guard case .applied = try await workflow.continuePendingSharedSettings(systemIsDark: false) else {
      return XCTFail("A completed attempt must allow the retained selection to initialize")
    }
    XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, before)
    XCTAssertEqual(f.page.state.session.configuration.mode, .custom)
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 4)
    XCTAssertTrue(f.page.state.session.configuration.modifiers.contains(.noQuit))
    XCTAssertEqual(f.page.state.practice?.scope.websiteCustomText?.limitValue, 3.5)
    XCTAssertEqual(f.page.state.presentation?.publication.savedDraft.testParameters.wordLimit, 2)
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
    XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertNil(f.page.state.sharedReceipt); XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertNotNil(f.page.restartController)
  }

  func testFinishedQuoteReceiptUsesCurrentCompletionOrFailureAndRetainsPreparationRetry() async throws {
    enum Offline: Error { case unavailable }
    @MainActor final class Loader {
      var reads = 0
      var offline = false
    }
    for failed in [false, true] {
      let f = try Fixture(); defer { f.close() }
      let loader = Loader()
      let workflow = try f.makeWorkflow(loadQuotes: { _ in
        loader.reads += 1
        if loader.offline { throw Offline.unavailable }
        return [.init(id: "owned-\(loader.reads)", title: "Own quote", text: "aa bb cc", language: .english, length: .short)]
      }); defer { workflow.stop() }
      try await workflow.apply(json: #"{"mode":"quote","quoteLength":[0],"difficulty":"master","repeatQuotes":"typing"}"#, systemIsDark: false)
      var active = f.page.state; active.session.insertBatch("a"); f.page.replace(active)
      let originalQuote = try XCTUnwrap(f.page.state.practice?.quote?.id)
      let application = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
      guard case .retained = try await workflow.applySharedSettings(json:
        #"[null,null,{"text":["cc","dd"],"mode":"repeat","limit":{"mode":"word","value":3.5},"pipeDelimiter":false},null,null,null,null,["no_quit"]]"#,
        replacing: application, systemIsDark: false) else { return XCTFail("Quote transition must wait for the old attempt") }
      let generation = f.settings.websiteCustomTextStateGeneration, disk = try f.register.read().revision
      var complete = f.page.state
      if failed { complete.session.insertBatch("§") }
      else {
        for _ in 0..<500 where !complete.session.isFinished {
          complete.session.insertBatch(complete.session.nextExpectedCharacter.map(String.init) ?? " ")
        }
      }
      XCTAssertEqual(complete.session.outcome, failed ? .failed : .completed)
      f.page.replace(complete)
      let ledger = complete.priorAttemptLedger, attempt = complete.session.automaticInputAttemptID, beforeReads = loader.reads
      if !failed {
        loader.offline = true
        do {
          _ = try await workflow.continuePendingSharedSettings(systemIsDark: false)
          XCTFail("Completed quote must prepare a fresh source and expose its failure")
        } catch is WebsiteSharedReceiptPreparationError {}
        XCTAssertEqual(loader.reads, beforeReads + 3)
        XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
        XCTAssertTrue(f.page.state.configurationDeparture?.isSharedReceipt == true)
        XCTAssertFalse(f.page.acceptsInput(for: attempt))
        loader.offline = false
      }
      guard case .applied = try await workflow.continuePendingSharedSettings(systemIsDark: false) else {
        return XCTFail("Terminal quote receipt did not continue")
      }
      XCTAssertEqual(f.page.state.practice?.repetition.repeatsWordset, failed)
      if failed {
        XCTAssertEqual(loader.reads, beforeReads)
        XCTAssertEqual(f.page.state.practice?.quote?.id, originalQuote)
      } else {
        XCTAssertEqual(loader.reads, beforeReads + 4)
        XCTAssertNotEqual(f.page.state.practice?.quote?.id, originalQuote)
      }
      XCTAssertNotEqual(f.page.state.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
      XCTAssertEqual(f.settings.websiteCustomTextStateGeneration, generation)
      XCTAssertEqual(try f.register.read().revision, disk)
      XCTAssertNil(f.page.state.sharedReceipt); XCTAssertNil(f.page.state.configurationDeparture)
    }
  }

  func testFinishedReceiptStillRejectsRetiredOwnerLeaseForeignSavedConfigurationOrDifferentAttempt() async throws {
    for change in ["owner", "disk", "attempt"] {
      let f = try Fixture(); defer { f.close() }; try await f.publish(#"{"mode":"words","words":2}"#)
      var active = f.page.state; active.session.insertBatch(active.session.nextExpectedCharacter.map(String.init) ?? " "); f.page.replace(active)
      let receipt = try f.coordinator.acceptSharedReceipt(#"["custom",null,null,null,null,null,null,["no_quit"]]"#,
        for: f.page, settings: f.settings, refreshingWith: f.source)
      var complete = f.page.state
      for _ in 0..<500 where !complete.session.isFinished {
        complete.session.insertBatch(complete.session.nextExpectedCharacter.map(String.init) ?? " ")
      }
      XCTAssertEqual(complete.session.outcome, .completed); f.page.replace(complete)
      if change == "disk" {
        let snapshot = try f.register.read()
        guard case .available(var runtime) = snapshot.state else { return XCTFail("Missing saved profile") }
        runtime["words"] = .number(88)
        guard case .committed = try f.register.commit(runtime: runtime, lazyMemory: snapshot.lazyMemory,
          replacing: XCTUnwrap(snapshot.revision)) else { return XCTFail("Foreign write failed") }
      } else if change == "owner" {
        let other = UUID()
        f.settings.preferenceConfigurationSaves.register(owner: other, save: {})
        f.settings.preferenceConfigurationSaves.activate(owner: other)
        f.settings.preferenceConfigurationSaves.activate(owner: f.page.owner)
      } else {
        var other = f.page.state
        other.session = TypingSession(configuration: .words(2), prompt: "aa bb")
        other.session.insertBatch(other.session.prompt + " ")
        XCTAssertTrue(other.session.isFinished)
        f.page.replace(other)
      }
      let disk = try f.register.read().revision, before = f.page.state.session.generationState
      XCTAssertThrowsError(try f.coordinator.resumeSharedReceipt(receipt.id, for: f.page))
      XCTAssertEqual(f.page.state.session.generationState, before)
      XCTAssertEqual(f.page.state.priorAttemptLedger, complete.priorAttemptLedger)
      XCTAssertEqual(f.page.state.sharedReceipt?.id, receipt.id)
      XCTAssertNil(f.page.state.configurationDeparture)
      XCTAssertEqual(try f.register.read().revision, disk)
    }
  }

  func testIncompleteFullApplicationDoesNotShareTheOldNativeFallback() async throws {
    let f = try Fixture(); defer { f.close() }
    let workflow = try f.makeWorkflow(loadQuotes: { _ in throw WebsiteConfigImportWorkflowError.unavailable })
    defer { workflow.stop() }
    do {
      _ = try await workflow.apply(json: #"{"mode":"quote"}"#, systemIsDark: false)
      XCTFail("Quote preparation must fail")
    } catch is WebsiteConfigSavedPreparationError {}
    XCTAssertNotNil(f.page.state.savedApplication)
    XCTAssertNil(f.page.state.practice)
    XCTAssertNil(WebsiteTestSettingsShare.pageSnapshot(f.page.state) {
      XCTFail("A saved but undelivered application must not share the old native selection")
      return .init(runtime: [:])
    })
  }

  func testShareSnapshotPrioritizesPublicationAndReceiptOverNativeFallback() async throws {
    let f = try Fixture(); defer { f.close() }
    try await f.publish()
    let initial = try XCTUnwrap(WebsiteTestSettingsShare.pageSnapshot(f.page.state) {
      XCTFail("Published profile must own sharing"); return .init(runtime: [:])
    })
    XCTAssertEqual(initial.runtime["words"], .number(5))
    XCTAssertEqual(initial.customText?.importFields?["text"], .array([.string("aa"), .string("bb")]))
    let before = f.page.state.session.generationState
    let receipt = try f.coordinator.acceptSharedReceipt(
      #"["words","17",{"text":["receipt-owned"],"mode":"repeat","limit":{"mode":"word","value":1},"pipeDelimiter":false},null,null,null,null,null]"#,
      for: f.page, settings: f.settings, refreshingWith: f.source)
    let pending = try XCTUnwrap(WebsiteTestSettingsShare.pageSnapshot(f.page.state) {
      XCTFail("Receipt must own sharing"); return .init(runtime: [:])
    })
    XCTAssertEqual(pending.runtime, receipt.outcome.state.settingsStore)
    XCTAssertEqual(pending.runtime["words"], .number(17))
    XCTAssertEqual(pending.customText?.importFields?["text"], .array([.string("receipt-owned")]))
    XCTAssertEqual(f.page.state.session.generationState, before)
    XCTAssertEqual(f.page.state.sharedReceipt?.id, receipt.id)
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
