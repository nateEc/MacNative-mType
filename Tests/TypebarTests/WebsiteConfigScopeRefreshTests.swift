import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigScopeRefreshTests: XCTestCase {
  @MainActor private final class Window {
    var value: WebsiteConfigPracticeScopeSource.Window?
    init(owner: UUID) { value = .init(owner: owner, customRecoveryBlocked: false) }
  }
  @MainActor private final class Fixture {
    let suite = "typebar.scope-refresh.\(UUID())"
    let defaults: UserDefaults, settings: AppSettings, account: AccountSession
    let page = PracticePageSessionStore()
    let environment: WebsiteConfigEnvironmentSource
    let window: Window
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-scope-refresh-\(UUID())")
    let register: WebsiteConfigFileRegister
    lazy var source = WebsiteConfigPracticeScopeSource(environment: environment, readWindow: { [window] in window.value })
    lazy var coordinator = WebsiteConfigCommitCoordinator(router: settings.preferenceConfigurationSaves, register: register,
      environment: { [environment] in environment.read() })
    init() throws {
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = .init(defaults: defaults, localBackgroundStore: .inMemory())
      account = .init(defaults: defaults)
      environment = .init(settings: settings, account: account, pointsPerRem: 16, documentComplete: true, development: false)
      window = .init(owner: page.owner)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      settings.preferenceConfigurationSaves.register(owner: page.owner, save: { XCTFail("No legacy save") })
      page.attach(to: settings.preferenceConfigurationSaves)
    }
    func settle() async throws {
      let deadline = ContinuousClock.now.advanced(by: .seconds(2))
      while environment.read() == nil && ContinuousClock.now < deadline { await Task.yield() }
      _ = try XCTUnwrap(environment.read())
    }
    func publish(_ json: String = #"{"mode":"custom"}"#) async throws -> WebsiteConfigCommitCoordinator.Publication {
      try await settle()
      let resources = try coordinator.prepareResources(for: coordinator.prepare(json),
        localFont: .absent, localBackground: .absent)
      let ready = try await coordinator.preparePractice(for: resources, scope: .init(customText: "old"),
        loadQuotes: { _ in [.init(id: "owned", title: "Owned", text: "ab cd", language: .english, length: .short)] })
      guard case .committed(let publication) = try coordinator.commit(ready, to: page, systemIsDark: true) else {
        throw Failure.notCommitted
      }
      return publication
    }
    func close() {
      source.stop(); environment.stop(); page.detach()
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
  }
  private enum Failure: Error { case notCommitted }
  private func document(_ text: String) -> CustomTextStateDocument {
    .init(source: .editor(text), configuration: .init(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init()))
  }

  func testConfigurationDepartureResumeRecapturesRealWindowContentAndRefusesStoppedSource() async throws {
    for stopSource in [false, true] {
      let f = try Fixture(); defer { f.close() }
      XCTAssertTrue(f.settings.saveCustomTextState(document("owned source text")))
      _ = try await f.publish()
      var state = f.page.state; state.session.insertBatch("o"); f.page.replace(state)
      let edit = try f.coordinator.prepareEdit(key: "difficulty", value: .string("expert"),
        for: f.page, refreshingWith: f.source)
      guard case .accepted(let admitted) = try f.coordinator.beginConfigurationRestart(edit,
        for: f.page, action: .difficulty(.expert)) else { return XCTFail("Departure was not accepted") }
      XCTAssertTrue(f.coordinator.cancel(admitted))
      let disk = try f.register.read().revision
      f.window.value?.revision = UUID()
      if stopSource {
        f.source.stop()
        XCTAssertThrowsError(try f.coordinator.resumeConfigurationRestart(for: f.page))
        XCTAssertNotNil(f.page.state.configurationDeparture)
      } else {
        let resumed = try f.coordinator.resumeConfigurationRestart(for: f.page)
        let resources = try f.coordinator.prepareResources(for: resumed, localFont: .absent, localBackground: .absent)
        let ready = try await f.coordinator.preparePractice(for: resources)
        XCTAssertEqual(ready.session.prompt, "owned source text")
        XCTAssertEqual(ready.session.configuration.difficulty, .expert)
        guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: true) else {
          return XCTFail("Fresh source could not deliver the pending configuration")
        }
        XCTAssertNil(f.page.state.configurationDeparture)
      }
      XCTAssertEqual(try f.register.read().revision, disk)
      XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
    }
  }

  func testExplicitWholeApplicationCanReplacePendingQuoteRepeatWithoutInheritingItsSelection() async throws {
    let f = try Fixture(); defer { f.close() }
    _ = try await f.publish(#"{"mode":"quote","quoteLength":[0],"repeatQuotes":"typing"}"#)
    var state = f.page.state; state.session.insertBatch("a"); f.page.replace(state)
    let edit = try f.coordinator.prepareEdit(key: "difficulty", value: .string("expert"),
      for: f.page, refreshingWith: f.source)
    guard case .accepted = try f.coordinator.beginConfigurationRestart(edit, for: f.page,
      action: .difficulty(.expert)) else { return XCTFail("Departure not accepted") }
    let replacement = try f.coordinator.prepare(#"{"mode":"words","words":3}"#, for: f.page, refreshingWith: f.source)
    let resources = try f.coordinator.prepareResources(for: replacement, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources)
    XCTAssertEqual(ready.session.configuration.mode, .words)
    XCTAssertEqual(ready.session.configuration.wordLimit, 3)
    XCTAssertEqual(ready.practice?.repetition, WebsitePracticeRepetition.none)
    guard case .committed = try f.coordinator.commit(ready, to: f.page, systemIsDark: false) else {
      return XCTFail("Explicit full application could not recover the pending page")
    }
    XCTAssertNil(f.page.state.configurationDeparture)
    XCTAssertEqual(f.page.state.priorAttemptLedger.restartCount, 1)
  }

  func testActualStoredContentRefreshAcrossEpochBuildsNewTextAndCommitsToSamePage() async throws {
    let f = try Fixture(); defer { f.close() }
    let original = try await f.publish()
    XCTAssertTrue(f.settings.saveCustomTextState(document("new owned text")))
    try await f.settle()
    XCTAssertNotEqual(f.environment.read()?.revision, original.environmentRevision)
    XCTAssertThrowsError(try f.coordinator.prepareEdit(key: "difficulty", value: .string("expert"), for: f.page))
    let edit = try f.coordinator.prepareEdit(key: "difficulty", value: .string("expert"), for: f.page, refreshingWith: f.source)
    let resources = try f.coordinator.prepareResources(for: edit, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources)
    XCTAssertEqual(ready.practice?.scope.customText, "new owned text")
    XCTAssertEqual(ready.session.prompt, "new owned text")
    guard case .committed(let publication) = try f.coordinator.commit(ready, to: f.page, systemIsDark: true) else {
      return XCTFail("Fresh content could not commit")
    }
    XCTAssertEqual(f.page.state.session.prompt, "new owned text")
    XCTAssertEqual(try f.register.read().state, .available(publication.draft.projection.runtime))
    XCTAssertNil(publication.draft.projection.runtime["customText"])
  }

  func testLocalFavoritesAreExplicitAndMissingStoredTextNeverReusesInheritedContent() async throws {
    let f = try Fixture(); defer { f.close() }
    f.settings.favoriteQuoteIDs = ["local", "local", "missing"]
    try await f.settle()
    let inherited = WebsiteConfigSessionBuilder.Scope(customText: "old private text", finiteTextSource: "old long text",
      favoriteQuoteIDs: ["old-account-id"])
    let missing = try f.source.capture(owner: f.page.owner, preserving: inherited)
    XCTAssertNil(missing.scope.favoriteQuoteIDs, "Unavailable account favorites must not fall back to a local list")
    XCTAssertEqual(missing.scope.customText, "")
    XCTAssertNil(missing.scope.finiteTextSource)
    XCTAssertTrue(missing.scope.customTextRecoveryBlocked)
    f.window.value?.favorites = .nativeLocal
    f.window.value?.revision = UUID()
    let local = try f.source.capture(owner: f.page.owner, preserving: inherited)
    XCTAssertEqual(local.scope.favoriteQuoteIDs, ["local", "local", "missing"])
    XCTAssertFalse(f.source.isCurrent(missing))
  }

  func testSameValueCustomSaveRetiresEnvironmentAndExistingContentCapture() async throws {
    let f = try Fixture(); defer { f.close() }
    let value = document("owned")
    XCTAssertTrue(f.settings.saveCustomTextState(value))
    try await f.settle()
    let snapshot = try f.source.capture(owner: f.page.owner, preserving: .init())
    let before = try XCTUnwrap(f.environment.read())
    XCTAssertTrue(f.settings.saveCustomTextState(value))
    XCTAssertNil(f.environment.read(), "A cooperating same-value save is still a new content application")
    XCTAssertFalse(f.source.isCurrent(snapshot))
    try await f.settle()
    XCTAssertNotEqual(f.environment.read()?.revision, before.revision)
  }

  func testChangeDuringResourceReadStopsOldProducerAndKeepsPreviousRecord() async throws {
    let f = try Fixture(); defer { f.close() }
    let original = try await f.publish()
    XCTAssertTrue(f.settings.saveCustomTextState(document("current")))
    try await f.settle()
    let ticket = try f.coordinator.prepareEdit(key: "difficulty", value: .string("expert"), for: f.page, refreshingWith: f.source)
    do {
      _ = try await f.coordinator.prepareResources(for: ticket, readLocalFont: {
        f.window.value?.revision = UUID()
        return .absent
      }, readLocalBackground: { XCTFail("Stale source continued reads"); return .absent })
      XCTFail("Changed window source was admitted")
    } catch WebsiteConfigCommitCoordinatorError.stale {}
    XCTAssertEqual(try f.register.read().revision, original.disk)
    XCTAssertEqual(f.page.state.session.prompt, "old")
  }

  func testExplicitPreparedAndFiniteWindowSourcesKeepControlsAndLiveBooks() async throws {
    let f = try Fixture(); defer { f.close() }
    let document = CustomTextStateDocument(source: .prepared([" exact ", "second"]),
      configuration: .init(mode: .custom, duration: nil, wordLimit: 7, difficulty: .normal, rules: .init(),
        customTextCompletion: .words, customTextOrdering: .random, customTextPipeDelimiter: true))
    let finite = Array(repeating: "owned", count: 2300).joined(separator: " ")
    f.window.value?.custom = .explicit(document, finiteTextSource: finite, preservesSpelling: true, recoveryBlocked: false)
    f.window.value?.parameterMemory = .init(duration: 47, wordLimit: 83, customTextDuration: 13,
      customTextWordLimit: 19, customTextSectionLimit: 4)
    f.window.value?.selectedQuoteID = "selected"
    var prior = WebsiteConfigSessionBuilder.Scope()
    prior.weakSpotScores.record(character: "z", interval: 1, isCorrect: false)
    prior.decorationState = .init(spanishClosing: "!")
    let value = try f.source.capture(owner: f.page.owner, preserving: prior).scope
    XCTAssertEqual(value.preparedCustomSections, [" exact ", "second"])
    XCTAssertEqual(value.finiteTextSource, finite)
    XCTAssertTrue(value.customTextIsPrepared)
    XCTAssertFalse(value.customTextRecoveryBlocked)
    XCTAssertEqual(value.customCompletion, .words); XCTAssertEqual(value.customOrdering, .random)
    XCTAssertEqual(value.customPipeDelimiter, true)
    XCTAssertEqual(value.parameterMemory.customTextWordLimit, 7)
    XCTAssertEqual(value.parameterMemory.customTextDuration, 13)
    XCTAssertEqual(value.parameterMemory.customTextSectionLimit, 4)
    XCTAssertEqual(value.weakSpotScores, prior.weakSpotScores)
    XCTAssertEqual(value.decorationState, prior.decorationState)
    XCTAssertEqual(value.selectedQuoteID, "selected")
  }

  func testWrongOwnerStoppedReaderAndOtherModelEnvironmentAreRejected() async throws {
    let f = try Fixture(), other = try Fixture(); defer { f.close(); other.close() }
    let publication = try await f.publish()
    let captured = try f.source.capture(owner: f.page.owner, preserving: .init())
    f.window.value = .init(owner: UUID(), customRecoveryBlocked: false)
    XCTAssertThrowsError(try f.source.capture(owner: f.page.owner, preserving: .init()))
    f.window.value = .init(owner: f.page.owner, customRecoveryBlocked: false)
    let wrongModels = WebsiteConfigPracticeScopeSource(environment: other.environment, readWindow: { f.window.value })
    defer { wrongModels.stop() }
    XCTAssertThrowsError(try f.coordinator.prepareEdit(key: "difficulty", value: .string("expert"), for: f.page,
      refreshingWith: wrongModels))
    f.source.stop()
    XCTAssertFalse(f.source.isCurrent(captured))
    XCTAssertThrowsError(try f.source.capture(owner: f.page.owner, preserving: .init()))
    XCTAssertEqual(try f.register.read().revision, publication.disk)
  }

  func testMutationInWindowGetterAndUnsupportedStoredDataCannotProduceBorrowedContent() async throws {
    let f = try Fixture(); defer { f.close() }
    let original = try await f.publish()
    var reads = 0
    let racing = WebsiteConfigPracticeScopeSource(environment: f.environment, readWindow: {
      reads += 1
      if reads == 2 { f.settings.favoriteQuoteIDs = ["changed"] }
      return f.window.value
    })
    defer { racing.stop() }
    XCTAssertThrowsError(try racing.capture(owner: f.page.owner, preserving: .init(customText: "old secret")))
    try await f.settle()
    let unsupported = Data(#"{"version":99}"#.utf8)
    f.defaults.set(unsupported, forKey: CustomTextStateStore.storageKey)
    let scope = try f.source.capture(owner: f.page.owner, preserving: .init(customText: "old secret")).scope
    XCTAssertEqual(scope.customText, "")
    XCTAssertTrue(scope.customTextRecoveryBlocked)
    XCTAssertFalse(f.settings.saveCustomTextState(document("do not overwrite")))
    XCTAssertEqual(f.defaults.data(forKey: CustomTextStateStore.storageKey), unsupported)
    XCTAssertEqual(try f.register.read().revision, original.disk)
  }

  func testValidStoredTextDoesNotBypassWindowRecoveryApproval() async throws {
    let f = try Fixture(); defer { f.close() }
    XCTAssertTrue(f.settings.saveCustomTextState(document("awaiting approval")))
    try await f.settle()
    f.window.value?.customRecoveryBlocked = true
    let blocked = try f.source.capture(owner: f.page.owner, preserving: .init())
    XCTAssertEqual(blocked.scope.customText, "awaiting approval")
    XCTAssertTrue(blocked.scope.customTextRecoveryBlocked)
    f.window.value?.customRecoveryBlocked = false
    f.window.value?.revision = UUID()
    XCTAssertFalse(f.source.isCurrent(blocked))
    let accepted = try f.source.capture(owner: f.page.owner, preserving: .init())
    XCTAssertFalse(accepted.scope.customTextRecoveryBlocked)
  }

  func testFractionalTimedWindowContentIsExactWithoutWideningLegacyStorageOrTruncatingMemory() async throws {
    let f = try Fixture(); defer { f.close() }
    _ = try await f.publish()
    let legacy = CustomTextStateDocument(source: .editor("a b"), configuration:
      .init(mode: .custom, duration: 2.5, wordLimit: nil, difficulty: .normal, rules: .init(), customTextCompletion: .time))
    XCTAssertFalse(legacy.isValid, "The old integer-only persisted format remains unchanged")
    f.window.value?.parameterMemory = .init(duration: 30, wordLimit: 50, customTextDuration: 13,
      customTextWordLimit: 25, customTextSectionLimit: 1)
    f.window.value?.custom = .timed(.init(source: .editor("a b"), seconds: 2.5))
    let edit = try f.coordinator.prepareEdit(key: "difficulty", value: .string("normal"), for: f.page, refreshingWith: f.source)
    let resources = try f.coordinator.prepareResources(for: edit, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources)
    XCTAssertEqual(ready.session.configuration.duration, 2.5)
    XCTAssertEqual(ready.practice?.scope.parameterMemory.customTextDuration, 13)
    var session = ready.session
    let start = Date(timeIntervalSinceReferenceDate: 900_000_000)
    session.insert("a", at: start)
    session.tick(at: start.addingTimeInterval(2.49)); XCTAssertFalse(session.isFinished)
    session.tick(at: start.addingTimeInterval(2.5)); XCTAssertTrue(session.isFinished)
  }

  func testTimedFiniteSourceDoesNotRequireAnEditorPlaceholder() async throws {
    let f = try Fixture(); defer { f.close() }
    _ = try await f.publish()
    var content = WebsiteConfigPracticeScopeSource.TimedContent(source: .editor(""), seconds: 2.5)
    content.corpus = "finite owned source"
    f.window.value?.custom = .timed(content)
    let edit = try f.coordinator.prepareEdit(key: "difficulty", value: .string("normal"), for: f.page, refreshingWith: f.source)
    let resources = try f.coordinator.prepareResources(for: edit, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources)
    XCTAssertTrue(ready.session.prompt.hasPrefix("finite owned source"))
    XCTAssertEqual(ready.session.configuration.duration, 2.5)
  }

  func testExactTimeLimitsRejectInvalidValuesAndPreserveZeroAsInfinite() async throws {
    let f = try Fixture(); defer { f.close() }
    for seconds in [-1.0, Double.nan, Double.infinity, Double(OfficialTestLimitInput.maximumValue) + 1] {
      f.window.value?.custom = .timed(.init(source: .editor("a b"), seconds: seconds))
      XCTAssertThrowsError(try f.source.capture(owner: f.page.owner, preserving: .init()))
    }
    f.window.value?.custom = .timed(.init(source: .editor("a b"), seconds: 0))
    let scope = try f.source.capture(owner: f.page.owner, preserving: .init()).scope
    let draft = try WebsiteConfigNativeProfile.prepareDraft(#"{"mode":"custom"}"#, pointsPerRem: 16, context: .init())
    let ready = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: scope)
    XCTAssertEqual(ready.session.configuration.duration, 0)
    XCTAssertTrue(ready.session.configuration.isInfinite)
  }

  func testUnavailableWindowCustomTextDoesNotBlockOrdinaryWordsAndNeverGeneratesAPlaceholder() async throws {
    let f = try Fixture(); defer { f.close() }
    _ = try await f.publish()
    let sources: [WebsiteConfigPracticeScopeSource.Custom] = [
      .explicit(document(""), finiteTextSource: nil, preservesSpelling: false, recoveryBlocked: false),
      .timed(.init(source: .editor(""), seconds: 2.5)),
    ]
    for source in sources {
      f.window.value?.custom = source; f.window.value?.revision = UUID()
      let ticket = try f.coordinator.prepareEdit(key: "words", value: .number(3), for: f.page, refreshingWith: f.source)
      let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
      let ready = try await f.coordinator.preparePractice(for: resources)
      XCTAssertEqual(ready.session.configuration.mode, .words)
      XCTAssertEqual(ready.session.configuration.wordLimit, 3)
      XCTAssertTrue(try XCTUnwrap(ready.practice).scope.customTextRecoveryBlocked)
      XCTAssertFalse(ready.session.prompt.isEmpty)
      let custom = try f.coordinator.prepareEdit(key: "mode", value: .string("custom"), for: f.page, refreshingWith: f.source)
      let customResources = try f.coordinator.prepareResources(for: custom, localFont: .absent, localBackground: .absent)
      do {
        _ = try await f.coordinator.preparePractice(for: customResources)
        XCTFail("Unavailable custom text generated a placeholder")
      } catch WebsiteConfigSessionBuildError.customTextUnavailable {}
    }
  }

  func testFiniteFinishSourceOwnsTextEvenWithAnEmptyPreview() async throws {
    let f = try Fixture(); defer { f.close() }
    _ = try await f.publish()
    f.window.value?.custom = .explicit(document(""), finiteTextSource: "finite finish source",
      preservesSpelling: true, recoveryBlocked: false)
    let ticket = try f.coordinator.prepareEdit(key: "difficulty", value: .string("normal"), for: f.page, refreshingWith: f.source)
    let resources = try f.coordinator.prepareResources(for: ticket, localFont: .absent, localBackground: .absent)
    let ready = try await f.coordinator.preparePractice(for: resources)
    XCTAssertTrue(ready.session.prompt.hasPrefix("finite finish source"))
    XCTAssertEqual(ready.session.configuration.customTextCompletion, .finish)
  }

  func testFiniteFactoryUsesShortOwnedTextAndNeverSubstitutesPreviewForInvalidInput() {
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .finish)
    let short = TestSessionFactory.make(configuration: configuration, customText: "wrong preview",
      finiteTextSource: "actual finite source")
    XCTAssertTrue(short.prompt.hasPrefix("actual finite source"))
    let oversized = String(repeating: "owned ", count: CustomTextPolicy.maximumLongSavedLength / 6 + 1)
    for invalid in ["", oversized] {
      let failed = TestSessionFactory.make(configuration: configuration, customText: "wrong preview", finiteTextSource: invalid)
      XCTAssertTrue(failed.isFinished)
      XCTAssertEqual(failed.prompt, "")
    }
  }
}
