import AppKit
import Observation
import XCTest
@testable import Typebar

@MainActor final class WebsiteLocalFontRefreshTests: XCTestCase {
  @MainActor private final class Fixture {
    let suite = "typebar.font-refresh.\(UUID())"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-font-refresh-\(UUID())")
    let defaults: UserDefaults, settings: AppSettings, account: AccountSession, page: PracticePageSessionStore
    let workflow: WebsiteConfigImportWorkflow
    var register: WebsiteConfigFileRegister { .init(directory: directory) }
    init(loadQuotes: @escaping @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) }) throws {
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory(),
        localPracticeFontResources: .init(directoryURL: directory, defaults: defaults))
      let account = AccountSession(defaults: defaults), page = PracticePageSessionStore()
      self.defaults = defaults; self.settings = settings; self.account = account; self.page = page
      settings.preferenceConfigurationSaves.register(owner: page.owner, save: { XCTFail("Resource refresh must not save native preferences") })
      page.attach(to: settings.preferenceConfigurationSaves)
      workflow = .init(page: page, settings: settings, account: account, directory: directory,
        readWindow: { .published(owner: page.owner, revision: page.state.session.automaticInputAttemptID,
          scope: page.state.sharedReceipt?.scope
            ?? (page.state.configurationDeparture?.isNativeSharedReceipt == true ? page.state.configurationDeparture?.sharedScope : nil)
            ?? page.state.practice?.scope ?? .init()) }, loadQuotes: loadQuotes)
    }
    func publish(noQuit: Bool = false) async throws {
      try await workflow.apply(json: noQuit
        ? #"{"mode":"words","words":5,"fontFamily":"Courier","fontSize":2,"funbox":["no_quit"]}"#
        : #"{"mode":"words","words":5,"fontFamily":"Courier","fontSize":2}"#, systemIsDark: false)
    }
    func install(_ data: Data) throws {
      let name = "local-practice-font-active-owned.ttf", directory = directory, defaults = defaults
      try settings.importLocalPracticeFont(data: data, originalFilename: "owned.ttf", save: { bytes, _ in
        try bytes.write(to: directory.appendingPathComponent(name), options: .atomic)
        defaults.set(name, forKey: LocalPracticeFontPreferenceKeys.selected)
        defaults.set(true, forKey: LocalPracticeFontPreferenceKeys.enabled)
      })
    }
    func close() {
      workflow.stop(); page.detach(); settings.preferenceConfigurationSaves.remove(owner: page.owner)
      defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory)
    }
  }
  private func settle(until predicate: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
  }
  func testActualFileImportUpdatesThePublishedFaceWithoutResavingConfiguration() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let data = OwnedTestFontFixture.make(postScriptName: "TypebarOwnedRefresh")
    let disk = try f.register.read().revision, generation = f.page.state.session.generationState
    let runtime = try XCTUnwrap(f.page.state.presentation?.publication.draft.projection.runtime)
    try f.install(data)
    await settle { f.page.state.presentation?.publication.font?.ownedLocalData == data }
    XCTAssertEqual(f.page.state.presentation?.publication.font?.ownedLocalData, data)
    XCTAssertEqual(f.page.state.presentation?.publication.font?.primary.font.fontName, "TypebarOwnedRefresh")
    XCTAssertEqual(f.page.state.session.generationState, generation)
    XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime, runtime)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testActiveNoQuitAndNosaveSelectionSurviveFileReplacement() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish(noQuit: true)
    let id = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    guard case .applied = try await f.workflow.applySharedSettings(json: #"["words","17",null,null,null,null,null,null]"#,
      replacing: id, systemIsDark: false) else { return XCTFail("Share did not initialize") }
    var active = f.page.state; active.session.insertBatch(String(try XCTUnwrap(active.session.nextExpectedCharacter)))
    f.page.replace(active)
    XCTAssertTrue(f.page.state.session.hasStarted); XCTAssertFalse(f.page.state.session.isFinished)
    let generation = f.page.state.session.generationState, ledger = f.page.state.priorAttemptLedger
    let old = try XCTUnwrap(f.page.state.presentation), controller = try XCTUnwrap(f.page.restartController)
    let disk = try f.register.read().revision, preferences = f.settings.snapshot
    let first = OwnedTestFontFixture.make(postScriptName: "TypebarRefreshFirst", advanceWidth: 500)
    let second = OwnedTestFontFixture.make(postScriptName: "TypebarRefreshSecond", advanceWidth: 900)
    for data in [first, second] {
      try f.install(data); await settle { f.page.state.presentation?.publication.font?.ownedLocalData == data }
      XCTAssertEqual(f.page.state.presentation?.publication.font?.ownedLocalData, data)
      XCTAssertEqual(f.page.state.session.generationState, generation)
      XCTAssertTrue(f.page.restartController === controller)
      XCTAssertEqual(f.page.state.priorAttemptLedger, ledger)
      XCTAssertEqual(f.page.state.presentation?.appearance, old.appearance)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.runtime, old.publication.draft.projection.runtime)
      XCTAssertEqual(f.page.state.presentation?.publication.draft.projection.events, old.publication.draft.projection.events)
      XCTAssertEqual(f.page.state.presentation?.publication.savedDraft.projection.runtime, old.publication.savedDraft.projection.runtime)
      XCTAssertEqual(try f.register.read().revision, disk)
    }
    XCTAssertEqual(f.page.state.session.configuration.wordLimit, 17)
    guard case .available(let saved) = try f.register.read().state else { return XCTFail("Saved profile missing") }
    XCTAssertEqual(saved["words"], .number(5))
    XCTAssertEqual(f.settings.snapshot, preferences)
    XCTAssertNil(NSFont(name: "TypebarRefreshSecond", size: 12))
  }

  func testActivatingRetainedFileAndRemovingItUpdateTheActualPreparedFace() async throws {
    let f = try Fixture(); defer { f.close() }
    let name = "local-practice-font-active-retained.ttf", data = OwnedTestFontFixture.make(postScriptName: "TypebarRetainedRefresh")
    try data.write(to: f.directory.appendingPathComponent(name))
    f.defaults.set(name, forKey: LocalPracticeFontPreferenceKeys.selected)
    f.defaults.set(false, forKey: LocalPracticeFontPreferenceKeys.enabled)
    try await f.publish()
    let generation = f.page.state.session.generationState, disk = try f.register.read().revision
    XCTAssertTrue(f.settings.activateLocalPracticeFont(activate: {
      f.defaults.set(true, forKey: LocalPracticeFontPreferenceKeys.enabled); return true
    }))
    await settle { f.page.state.presentation?.publication.font?.ownedLocalData == data }
    XCTAssertEqual(f.page.state.presentation?.publication.font?.primary.font.fontName, "TypebarRetainedRefresh")
    try f.settings.removeLocalPracticeFont(remove: {
      try FileManager.default.removeItem(at: f.directory.appendingPathComponent(name))
      f.defaults.set("", forKey: LocalPracticeFontPreferenceKeys.selected)
      f.defaults.set(false, forKey: LocalPracticeFontPreferenceKeys.enabled)
    })
    await settle { f.page.state.presentation?.publication.font?.primary.candidate == .family("Courier") }
    XCTAssertEqual(f.page.state.presentation?.publication.font?.primary.candidate, .family("Courier"))
    XCTAssertNil(f.page.state.presentation?.publication.font?.ownedLocalData)
    XCTAssertEqual(f.page.state.session.generationState, generation)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testInvalidSelectionKeepsOldFaceAndExplicitRetryUsesRepairedFileWithoutAnotherEvent() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let id = f.page.state.presentation?.publication.applicationID, disk = try f.register.read().revision
    let data = OwnedTestFontFixture.make(postScriptName: "TypebarRetryRefresh")
    try f.install(data)
    f.defaults.set("../outside.ttf", forKey: LocalPracticeFontPreferenceKeys.selected)
    await settle { f.workflow.localFontFailure != nil }
    XCTAssertNotNil(f.workflow.localFontFailure)
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, id)
    XCTAssertEqual(try f.register.read().revision, disk)
    let revision = f.settings.localPracticeFontRevision
    f.defaults.set("local-practice-font-active-owned.ttf", forKey: LocalPracticeFontPreferenceKeys.selected)
    f.workflow.retryLocalFontResources()
    await settle { f.page.state.presentation?.publication.font?.ownedLocalData == data }
    XCTAssertEqual(f.page.state.presentation?.publication.font?.ownedLocalData, data)
    XCTAssertNil(f.workflow.localFontFailure)
    XCTAssertEqual(f.settings.localPracticeFontRevision, revision)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testInactiveWindowWaitsForItsActualLeaseWithoutReportingFailure() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let second = UUID(), router = f.settings.preferenceConfigurationSaves
    router.register(owner: second, save: {}); router.activate(owner: second)
    defer { router.remove(owner: second) }
    let id = f.page.state.presentation?.publication.applicationID, disk = try f.register.read().revision
    let data = OwnedTestFontFixture.make(postScriptName: "TypebarInactiveRefresh")
    try f.install(data)
    for _ in 0..<30 { await Task.yield() }
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, id)
    XCTAssertNil(f.workflow.localFontFailure)
    router.activate(owner: f.page.owner)
    await settle { f.page.state.presentation?.publication.font?.ownedLocalData == data }
    XCTAssertEqual(f.page.state.presentation?.publication.font?.ownedLocalData, data)
    XCTAssertNil(f.workflow.localFontFailure); XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testStoppingWorkflowRetiresQueuedFileUpdates() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let id = f.page.state.presentation?.publication.applicationID
    let data = OwnedTestFontFixture.make(postScriptName: "TypebarStoppedRefresh")
    try f.install(data); f.workflow.stop()
    for _ in 0..<30 { await Task.yield() }
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, id)
    XCTAssertNil(f.workflow.localFontPublication)
    guard case .data(let retained) = try f.settings.readLocalPracticeFontResource() else { return XCTFail("File disappeared") }
    XCTAssertEqual(retained, data)
  }

  func testForeignSavedConfigurationCannotBeOverwrittenByAResourceUpdate() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let read = try f.register.read(), id = f.page.state.presentation?.publication.applicationID
    guard case .available(var foreign) = read.state else { return XCTFail("Missing profile") }
    foreign["words"] = .number(9)
    guard case .committed = try f.register.commit(runtime: foreign, lazyMemory: read.lazyMemory,
      replacing: XCTUnwrap(read.revision)) else { return XCTFail("Foreign save failed") }
    let disk = try f.register.read().revision
    try f.install(OwnedTestFontFixture.make(postScriptName: "TypebarForeignRefresh"))
    await settle { f.workflow.localFontFailure != nil }
    XCTAssertNotNil(f.workflow.localFontFailure); XCTAssertEqual(f.page.state.presentation?.publication.applicationID, id)
    XCTAssertEqual(try f.register.read().revision, disk)
    guard case .available(let saved) = try f.register.read().state else { return XCTFail("Foreign profile lost") }
    XCTAssertEqual(saved["words"], .number(9))
  }

  func testReturningToNativeClearsAResourceFailureWithoutDeletingSavedValues() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    try f.install(Data([1, 2, 3])); f.defaults.set("../outside.ttf", forKey: LocalPracticeFontPreferenceKeys.selected)
    await settle { f.workflow.localFontFailure != nil }; XCTAssertNotNil(f.workflow.localFontFailure)
    let disk = try f.register.read().revision
    let permit = try f.page.beginLegacyReturn()
    var native = f.page.state; native.session = .init(configuration: .words(3), prompt: "aa bb cc")
    f.page.replace(native); try f.page.finishLegacyReturn(permit)
    await settle { f.workflow.localFontFailure == nil }
    XCTAssertNil(f.workflow.localFontFailure); XCTAssertNil(f.page.state.presentation)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testFileChangeRetiresOldQuotePreparationAndFreshRestorationUsesTheNewFile() async throws {
    @MainActor final class Gate { var waiting: CheckedContinuation<[OfflineQuote], Error>?; var suspend = true }
    let gate = Gate()
    let quote = OfflineQuote(id: "owned", title: "Owned", text: "cc dd ee", language: .english, length: .short)
    let f = try Fixture(loadQuotes: { _ in
      if gate.suspend { return try await withCheckedThrowingContinuation { gate.waiting = $0 } }
      return [quote]
    }); defer { f.close() }
    try await f.publish()
    let id = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let operation = Task { @MainActor in try await f.workflow.editAndBegin(.mode(.quote), replacing: id, systemIsDark: false) }
    await settle { gate.waiting != nil }
    guard let waiting = gate.waiting else { operation.cancel(); return XCTFail("Quote preparation did not suspend") }
    let data = OwnedTestFontFixture.make(postScriptName: "TypebarDeferredRefresh")
    try f.install(data)
    for _ in 0..<30 { await Task.yield() }
    XCTAssertNil(f.workflow.localFontFailure)
    gate.suspend = false; waiting.resume(returning: [quote])
    do { _ = try await operation.value; XCTFail("Resource epoch changed during preparation") } catch {}
    let pending = try XCTUnwrap(f.page.state.configurationDeparture?.id)
    do {
      _ = try await f.workflow.resumeAndBegin(departureID: pending, systemIsDark: false)
      XCTFail("A checkpoint from the previous resource epoch must remain stale")
    } catch {}
    _ = try await f.workflow.apply(json: nil, systemIsDark: false)
    let attempt = f.page.state.session.automaticInputAttemptID
    await settle { f.workflow.localFontPublication != nil }
    XCTAssertEqual(f.page.state.presentation?.publication.font?.ownedLocalData, data)
    XCTAssertEqual(f.page.state.session.automaticInputAttemptID, attempt)
    XCTAssertEqual(f.page.state.session.configuration.mode, .quote)
    XCTAssertNil(f.workflow.localFontFailure)
  }

  func testPreparedRefreshRejectsLaterInputOwnerOrCompetingDiskWithoutSavingAnything() async throws {
    for change in ["input", "owner", "disk"] {
      let f = try Fixture(); defer { f.close() }; let epoch = UUID()
      let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves,
        register: f.register, environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
      let seed = try coordinator.prepare(#"{"mode":"words","words":5}"#)
      let resources = try coordinator.prepareResources(for: seed, localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resources, scope: .init())
      guard case .committed = try coordinator.commit(ready, to: f.page, systemIsDark: false) else { return XCTFail("Seed failed") }
      let id = f.page.state.presentation?.publication.applicationID
      let refresh = try coordinator.prepareFontRefresh(for: f.page,
        local: .data(OwnedTestFontFixture.make(postScriptName: "TypebarStaleRefresh")))
      let second = UUID()
      if change == "input" {
        var state = f.page.state; state.session.insertBatch(String(try XCTUnwrap(state.session.nextExpectedCharacter))); f.page.replace(state)
      } else if change == "owner" {
        f.settings.preferenceConfigurationSaves.register(owner: second, save: {})
        f.settings.preferenceConfigurationSaves.activate(owner: second)
      } else {
        let read = try f.register.read()
        guard case .available(var foreign) = read.state else { return XCTFail("Missing profile") }
        foreign["words"] = .number(9)
        guard case .committed = try f.register.commit(runtime: foreign, lazyMemory: read.lazyMemory,
          replacing: XCTUnwrap(read.revision)) else { return XCTFail("Foreign save failed") }
      }
      defer { f.settings.preferenceConfigurationSaves.remove(owner: second) }
      let disk = try f.register.read().revision, generation = f.page.state.session.generationState
      switch try coordinator.commitFontRefresh(refresh, for: f.page) {
      case .stale, .conflict: break
      default: XCTFail("A changed \(change) still consumed old font resources")
      }
      XCTAssertEqual(f.page.state.presentation?.publication.applicationID, id)
      XCTAssertEqual(try f.register.read().revision, disk)
      XCTAssertEqual(f.page.state.session.generationState, generation)
    }
  }

  func testEnvironmentCallbackCannotReenterRefreshPreparation() async throws {
    @MainActor final class Hook { weak var coordinator: WebsiteConfigCommitCoordinator?; var enabled = false; var rejected = false }
    let f = try Fixture(); defer { f.close() }; let hook = Hook(), epoch = UUID()
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves,
      register: f.register, environment: {
        if hook.enabled {
          hook.enabled = false
          do {
            _ = try hook.coordinator?.prepareFontRefresh(for: f.page, local: .absent)
            XCTFail("Environment callback reentered font preparation")
          } catch WebsiteConfigCommitCoordinatorError.reentrant { hook.rejected = true } catch { XCTFail("Wrong reentry rejection") }
        }
        return .init(revision: epoch, context: .init(), pointsPerRem: 16)
      })
    hook.coordinator = coordinator
    let seed = try coordinator.prepare(#"{"mode":"words","words":5}"#)
    let resources = try coordinator.prepareResources(for: seed, localFont: .absent, localBackground: .absent)
    let ready = try await coordinator.preparePractice(for: resources, scope: .init())
    guard case .committed = try coordinator.commit(ready, to: f.page, systemIsDark: false) else { return XCTFail("Seed failed") }
    let disk = try f.register.read().revision
    hook.enabled = true
    let refresh = try coordinator.prepareFontRefresh(for: f.page, local: .absent)
    XCTAssertTrue(hook.rejected)
    guard case .committed = try coordinator.commitFontRefresh(refresh, for: f.page) else { return XCTFail("Refresh failed") }
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testStopDuringPublicationDoesNotReviveTheDetachedWindowOrRetryLoop() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let disk = try f.register.read().revision, attempt = f.page.state.session.automaticInputAttemptID
    withObservationTracking { _ = f.page.state.presentation?.publication.applicationID } onChange: {
      MainActor.assumeIsolated { f.workflow.stop(); f.page.detach() }
    }
    try f.install(OwnedTestFontFixture.make(postScriptName: "TypebarRetiredRefresh"))
    for _ in 0..<30 { await Task.yield() }
    XCTAssertFalse(f.page.acceptsInput(for: attempt))
    XCTAssertNil(f.workflow.localFontPublication); XCTAssertNil(f.workflow.localFontFailure)
    XCTAssertEqual(try f.register.read().revision, disk)
  }

  func testAnotherFileUpdateDuringPublicationIsNotLost() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let first = OwnedTestFontFixture.make(postScriptName: "TypebarFirstQueuedRefresh")
    let second = OwnedTestFontFixture.make(postScriptName: "TypebarLatestQueuedRefresh")
    let disk = try f.register.read().revision, generation = f.page.state.session.generationState
    withObservationTracking { _ = f.page.state.presentation?.publication.applicationID } onChange: {
      MainActor.assumeIsolated {
        do { try f.install(second) } catch { XCTFail("Second file could not be stored") }
      }
    }
    try f.install(first)
    await settle { f.page.state.presentation?.publication.font?.ownedLocalData == second }
    XCTAssertEqual(f.page.state.presentation?.publication.font?.ownedLocalData, second)
    XCTAssertEqual(f.page.state.session.generationState, generation)
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.settings.localPracticeFontRevision, 2)
    XCTAssertNil(f.workflow.localFontFailure)
  }

  func testOrdinaryInputAfterRefreshDoesNotRepublishFontResources() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let data = OwnedTestFontFixture.make(postScriptName: "TypebarIdleRefresh")
    try f.install(data); await settle { f.page.state.presentation?.publication.font?.ownedLocalData == data }
    let id = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let disk = try f.register.read().revision
    for _ in 0..<10 {
      var state = f.page.state
      if let character = state.session.nextExpectedCharacter { state.session.insertBatch(String(character)) }
      f.page.replace(state); await Task.yield()
    }
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, id)
    XCTAssertEqual(f.page.state.presentation?.publication.font?.ownedLocalData, data)
    XCTAssertEqual(try f.register.read().revision, disk)
  }
}
