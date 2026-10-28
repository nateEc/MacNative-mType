import Foundation

enum WebsiteConfigCommitCoordinatorError: Error { case noOwner, noEnvironment, unavailable, reentrant, stale, sessionNotReady }

@MainActor fileprivate final class WebsiteConfigPublicationAuthority {
  var latest: UUID?
  let register: WebsiteConfigFileRegister
  init(register: WebsiteConfigFileRegister) { self.register = register }
}

/// Whole-value publication for the new configuration path. Not a resource
/// loader, legacy AppSettings adapter or UI transaction. No real default path.
@MainActor
final class WebsiteConfigCommitCoordinator {
  struct Environment: Equatable {
    /// The host must rotate this for every auth/resource/legacy-state change,
    /// including ABA. Equality of current values alone cannot prove freshness.
    let revision: UUID
    let context: WebsiteConfigRuntimeContext
    let pointsPerRem: Double
  }
  struct Prepared {
    fileprivate(set) var draft: WebsiteConfigNativeDraft
    fileprivate let identity: UUID
    fileprivate var request: UUID
    fileprivate let owner: PreferenceConfigurationSaveRouter.Lease
    fileprivate let environment: Environment
    fileprivate var disk: WebsiteConfigFileRegister.Revision
    /// The accepted setter snapshot can differ from runtime after nosave
    /// listeners. Delivery alone must not turn those listeners into saves.
    fileprivate var savedDraft: WebsiteConfigNativeDraft?
    fileprivate var funboxSelectionSaved: Bool?
    fileprivate var quoteRecoveries: [WebsiteQuoteSampler.Recovery] = []
    fileprivate var quoteInitialization: WebsiteConfigSessionBuilder.QuoteInitialization?
    fileprivate var retainsQuoteInitialization = false
    fileprivate weak var sourcePage: PracticePageSessionStore?
    fileprivate weak var restartController: WebsitePracticeRestartController?
    fileprivate var requiresRestartController = false
    fileprivate var pageCapture: PracticePageSessionStore.GenerationCapture?
    fileprivate var applicationCapture: PracticePageSessionStore.ApplicationCapture?
    fileprivate var savedApplicationID: UUID?
    fileprivate var applicationEventsApplied = false
    fileprivate weak var contentSource: WebsiteConfigPracticeScopeSource?
    fileprivate var contentCapture: WebsiteConfigPracticeScopeSource.Snapshot?
    fileprivate var wordNavigation: WebsiteWordNavigationEvent?
    fileprivate var departureID: UUID? { pageCapture?.configurationDeparture ?? applicationCapture?.configurationDeparture }
  }
  struct Publication {
    /// One successful publication, including next-attempt-only selection saves.
    let applicationID: UUID
    let draft: WebsiteConfigNativeDraft
    let savedDraft: WebsiteConfigNativeDraft
    let owner: UUID
    let environmentRevision: UUID
    let pointsPerRem: Double
    let disk: WebsiteConfigFileRegister.Revision
    /// nil means no background admission was attempted, not an empty image.
    let background: WebsiteConfigBackgroundResource?
    /// nil means font preparation was not attempted, not a failed font.
    let font: WebsiteConfigFontResource?
    /// Prepared attempt seed for the session-aware path; legacy commits are nil.
    let session: TypingSession?
    /// Whole-draft builder output, including value-owned selection memories.
    /// nil for older explicit session producers and resource-only commits.
    let practice: WebsiteConfigSessionBuilder.Prepared?
    let quoteRecoveries: [WebsiteQuoteSampler.Recovery]
    fileprivate let ownerLease: PreferenceConfigurationSaveRouter.Lease
    fileprivate let authority: WebsiteConfigPublicationAuthority

    @MainActor func isCurrentDelivery(owner: UUID, router: PreferenceConfigurationSaveRouter) -> Bool {
      guard self.owner == owner, authority.latest == applicationID, router.isCurrent(ownerLease),
        let current = try? authority.register.read().revision, current == disk else { return false }
      return router.isCurrent(ownerLease)
    }
  }
  /// Durable full-profile application whose resources/text are not delivered.
  /// The ticket is window-local; a new coordinator uses normal cold recovery.
  struct SavedApplication {
    let id: UUID
    fileprivate let ticket: Prepared
    var draft: WebsiteConfigNativeDraft { ticket.draft }
  }
  fileprivate struct NativeSharedBase {
    let draft: WebsiteConfigNativeDraft
    let savedDraft: WebsiteConfigNativeDraft
    let pointsPerRem: Double
    let quote: OfflineQuote?
    let repetition: WebsitePracticeRepetition
  }
  fileprivate enum SharedBase {
    case published(Publication), native(NativeSharedBase)
    var draft: WebsiteConfigNativeDraft { switch self { case .published(let p): p.draft; case .native(let n): n.draft } }
    var savedDraft: WebsiteConfigNativeDraft { switch self { case .published(let p): p.savedDraft; case .native(let n): n.savedDraft } }
    var pointsPerRem: Double { switch self { case .published(let p): p.pointsPerRem; case .native(let n): n.pointsPerRem } }
    var applicationID: UUID? { if case .published(let p) = self { p.applicationID } else { nil } }
    var isNative: Bool { if case .native = self { true } else { false } }
  }
  struct SharedReceipt {
    let id = UUID()
    let outcome: WebsiteSharedSettingsReceiver.Outcome
    let scope: WebsiteConfigSessionBuilder.Scope
    fileprivate let identity: UUID
    fileprivate let owner: PreferenceConfigurationSaveRouter.Lease
    fileprivate let base: SharedBase
    fileprivate let disk: WebsiteConfigFileRegister.Revision
    fileprivate weak var contentSource: WebsiteConfigPracticeScopeSource?
    fileprivate let contentCapture: WebsiteConfigPracticeScopeSource.Snapshot
    fileprivate let wasActive: Bool
    fileprivate let wasFailed: Bool
    var requiresInitialization: Bool { outcome.restartStarts > 0 }
    // A restart withheld at receipt time is not a permanent veto. An explicit
    // later continue may initialize after that same attempt has ended; the
    // coordinator still verifies the owner, publication, content and disk.
    func canInitialize(after session: TypingSession) -> Bool { requiresInitialization || session.isFinished }
    var basePointsPerRem: Double { base.pointsPerRem }
    var isNative: Bool { base.isNative }
    @MainActor func authorizesInput(owner id: UUID, router: PreferenceConfigurationSaveRouter) -> Bool {
      owner.owner == id && router.isCurrent(owner)
    }
  }

  func acceptSharedReceipt(_ json: String, for page: PracticePageSessionStore, settings: AppSettings,
    refreshingWith source: WebsiteConfigPracticeScopeSource) throws -> SharedReceipt {
    try source.withReceiptRead { try acceptSharedReceiptBody(json, for: page, settings: settings, refreshingWith: source) }
  }
  private func acceptSharedReceiptBody(_ json: String, for page: PracticePageSessionStore, settings: AppSettings,
    refreshingWith source: WebsiteConfigPracticeScopeSource) throws -> SharedReceipt {
    guard !processing, page.restartController?.isPreparing != true else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true; defer { processing = false }
    request = UUID()
    guard settings.preferenceConfigurationSaves === router, let lease = router.captureLease(), lease.owner == page.owner,
      let context = environment() else { throw WebsiteConfigCommitCoordinatorError.noOwner }
    let capture = try page.captureGeneration(router: router)
    guard let base = latest, base.applicationID == capture.publication.applicationID,
      base.authority === publicationAuthority, try register.read().revision == base.disk else {
      throw WebsiteConfigCommitCoordinatorError.stale
    }
    let content = try source.capture(owner: page.owner, preserving: capture.scope)
    guard content.environment == context, page.isCurrent(capture, router: router), environment() == context else {
      throw WebsiteConfigCommitCoordinatorError.stale
    }
    let custom: WebsiteCustomTextSettings
    if let raw = content.scope.websiteCustomText { custom = raw }
    else if let raw = WebsiteTestSettingsShare.customText(in: content.scope) { custom = try .init(value: raw) }
    else {
      // Independently authored fallback: never copy the source's sample text.
      custom = try .init(value: .object(["text": .array(["quiet", "harbor", "cedar", "cloud", "river", "stone", "meadow", "orbit", "lantern"].map(WebsiteConfigValue.string)),
        "mode": .string("repeat"), "limit": .object(["mode": .string("word"), "value": .number(9)]), "pipeDelimiter": .bool(false)]))
    }
    try Task.checkCancellation()
    try page.beginSharedReceipt(owner: lease, router: router, capture: capture)
    defer { page.endCommit() }
    var disk = base.disk
    func ownsWindow() -> Bool {
      page.ownsSharedReceiptReservation(owner: lease, router: router, capture: capture) && source.ownsReceiptIdentity(content)
    }
    let outcome = WebsiteSharedSettingsReceiver.receive(json: json,
      current: .init(runtime: base.draft.projection.runtime, settingsStore: base.draft.settingsStoreValues,
        custom: custom, active: capture.testActive, lazyMemory: base.draft.lazyMemory,
        savedConfig: base.savedDraft.projection.runtime), context: context.context,
      storage: .init(writeCustom: { value in
        ownsWindow() && settings.saveWebsiteCustomTextState(value)
      }, writeConfiguration: { save in
        guard ownsWindow() else { return false }
        switch try self.register.commit(runtime: save.runtime, lazyMemory: base.draft.lazyMemory, replacing: disk) {
        case .committed(let next): disk = next; return true
        case .conflict, .unavailable: return false
        }
      }))
    guard !outcome.parseRejected else { throw WebsiteSharedSettingsReceiver.Failure.invalidPayload }
    // From the first accepted write onward, retain partial effects even when
    // a synchronous observer retires this owner. Resume will recheck authority.
    var state = page.state
    let wasFailed = state.session.outcome == .failed
    var scope = outcome.state.custom.applying(to: content.scope)
    if outcome.state.selectedQuote != nil { scope.selectedQuoteID = nil }
    if outcome.events.contains(where: { $0.key == "quoteLength" }) { scope.quoteSampler = nil }
    let receipt = SharedReceipt(outcome: outcome, scope: scope, identity: identity, owner: lease, base: .published(base),
      disk: disk, contentSource: source, contentCapture: content, wasActive: capture.testActive, wasFailed: wasFailed)
    if receipt.requiresInitialization {
      if capture.testActive, let measurement = state.session.abandonAndMeasure() {
        state.priorAttemptLedger.recordRestart(engagedDuration: measurement.engagedDuration,
          accuracy: measurement.accuracy, savingEnabled: base.draft.behavior.saveCompletedResults)
      }
      state.restartDepartureAttemptID = state.session.automaticInputAttemptID
    }
    state.sharedReceipt = receipt
    if receipt.requiresInitialization { state.quoteInitialization = nil }
    resourceAdmission = UUID(); sessionAdmission = UUID(); sessionRequest = nil
    page.installCommitted(state, retainingRestartController: receipt.requiresInitialization ? nil : page.restartController)
    return receipt
  }

  func acceptNativeSharedReceipt(_ json: String, baseline: WebsiteConfigNativeBaseline.Capture,
    quote: OfflineQuote?, repetition: WebsitePracticeRepetition, for page: PracticePageSessionStore,
    settings: AppSettings, refreshingWith source: WebsiteConfigPracticeScopeSource) throws -> SharedReceipt {
    try source.withReceiptRead {
      try WebsiteSharedSettingsReceiver.validatePayload(json)
      guard !processing, latest == nil, page.state.practice == nil, page.state.presentation == nil,
        page.state.sharedReceipt == nil, page.state.configurationDeparture == nil, page.state.savedApplication == nil,
        page.restartController?.isPreparing != true else { throw WebsiteConfigCommitCoordinatorError.reentrant }
      processing = true; defer { processing = false }; request = UUID()
      guard settings.preferenceConfigurationSaves === router, let lease = router.captureLease(), lease.owner == page.owner,
        let context = environment(), settings.snapshot == baseline.nativePreferences,
        page.state.session.configuration == baseline.configuration else { throw WebsiteConfigCommitCoordinatorError.stale }
      if baseline.configuration.mode == .quote {
        guard let quote, quote.id == baseline.scope.selectedQuoteID else { throw WebsiteConfigCommitCoordinatorError.unavailable }
      }
      let capture = try page.captureApplication(router: router)
      let content = try source.capture(owner: page.owner, preserving: baseline.scope)
      guard content.environment == context, page.isCurrent(capture, router: router),
        try WebsiteConfigNativeBaseline.sameNativeInput(baseline, as: content.scope) else { throw WebsiteConfigCommitCoordinatorError.stale }
      let draft = try baseline.draft(pointsPerRem: context.pointsPerRem)
      try Task.checkCancellation()
      try page.beginCommit(owner: lease, router: router, applicationCapture: capture)
      defer { page.endCommit() }
      @MainActor func ownsWindow() -> Bool {
        page.ownsApplicationReceiptReservation(owner: lease, router: router, capture: capture)
          && source.ownsNativeReceiptWindow(content) && settings.snapshot == baseline.nativePreferences
      }
      let saved = try WebsiteConfigNativeSharedStorage.adopt(baseline, settings: settings, register: register,
        pointsPerRem: context.pointsPerRem, whileCurrent: ownsWindow)
      var disk = saved.revision
      guard let custom = baseline.scope.websiteCustomText else { throw WebsiteConfigCommitCoordinatorError.unavailable }
      let original = page.state.session
      let active = original.hasStarted && !original.isFinished
      let outcome = WebsiteSharedSettingsReceiver.receive(json: json,
        current: .init(runtime: baseline.runtime, settingsStore: baseline.runtime, custom: custom,
          active: active, lazyMemory: baseline.lazyMemory, savedConfig: saved.draft.projection.runtime), context: context.context,
        storage: .init(writeCustom: { value in ownsWindow() && settings.saveWebsiteCustomTextState(value) },
          writeConfiguration: { save in
            guard ownsWindow() else { return false }
            switch try self.register.commit(runtime: save.runtime, lazyMemory: baseline.lazyMemory, replacing: disk) {
            case .committed(let next): disk = next; return true
            case .conflict, .unavailable: return false
            }
          }))
      var scope = outcome.state.custom.applying(to: baseline.scope)
      if outcome.state.selectedQuote != nil { scope.selectedQuoteID = nil }
      if outcome.events.contains(where: { $0.key == "quoteLength" }) { scope.quoteSampler = nil }
      let receipt = SharedReceipt(outcome: outcome, scope: scope, identity: identity, owner: lease,
        base: .native(.init(draft: draft, savedDraft: saved.draft, pointsPerRem: context.pointsPerRem, quote: quote, repetition: repetition)),
        disk: disk, contentSource: source, contentCapture: content, wasActive: active, wasFailed: original.outcome == .failed)
      var state = page.state
      if receipt.requiresInitialization {
        if active, let measurement = state.session.abandonAndMeasure() {
          state.priorAttemptLedger.recordRestart(engagedDuration: measurement.engagedDuration,
            accuracy: measurement.accuracy, savingEnabled: baseline.nativePreferences.saveCompletedResults)
        }
        state.restartDepartureAttemptID = state.session.automaticInputAttemptID
        state.quoteInitialization = nil
      }
      state.sharedReceipt = receipt
      resourceAdmission = UUID(); sessionAdmission = UUID(); sessionRequest = nil
      page.installCommitted(state)
      return receipt
    }
  }

  /// Deliver actual zero-restart settings to the initialized generator. Both
  /// independent custom setters and ordinary words/time transitions retain
  /// the old pool and attempt; unsupported generator changes keep the receipt.
  func commitSharedLiveReceipt(_ id: UUID, for page: PracticePageSessionStore) throws -> Publication? {
    guard let source = page.state.sharedReceipt?.contentSource else { throw WebsiteConfigCommitCoordinatorError.stale }
    return try source.withReceiptRead {
      guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
      processing = true; defer { processing = false }
      guard let receipt = page.state.sharedReceipt, receipt.id == id, receipt.identity == identity,
        !receipt.requiresInitialization, router.isCurrent(receipt.owner), let context = environment(),
        source.ownsReceiptIdentity(receipt.contentCapture), latest?.applicationID == receipt.base.applicationID,
        try register.read().revision == receipt.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
      guard case .published(let base) = receipt.base else { return nil }
      let capture = try page.captureGeneration(router: router)
      guard capture.testActive,
        let previous = page.state.presentation, let practice = page.state.practice else { return nil }
      let unchanged = receipt.outcome.state.runtime == base.draft.projection.runtime
      if !unchanged {
        let allowed: Set<String> = ["mode", "time", "words", "punctuation", "numbers", "difficulty", "funbox"]
        guard base.draft.projection.runtime.allSatisfy({ allowed.contains($0.key)
          || receipt.outcome.state.runtime[$0.key] == $0.value }),
          case .array(let oldBoxes)? = base.draft.projection.runtime["funbox"],
          case .array(let boxes)? = receipt.outcome.state.runtime["funbox"], boxes.contains(.string("no_quit")),
          oldBoxes.filter({ $0 != .string("no_quit") }) == boxes.filter({ $0 != .string("no_quit") }) else { return nil }
      } else if !page.state.session.configuration.modifiers.contains(.noQuit) { return nil }
      let draftValue: WebsiteConfigNativeDraft
      do { draftValue = try WebsiteConfigNativeDraft(received: receipt.outcome, pointsPerRem: context.pointsPerRem) }
      catch WebsiteConfigNativeTestParametersError.unrepresentableField { return nil }
      var draft = draftValue
      draft.funboxMemory = base.draft.funboxMemory
      var scope = receipt.scope
      scope.parameterMemory = draft.testParameters.parameterMemory(preserving: scope.parameterMemory)
      var state = page.state
      if !unchanged {
        let projected: TestConfiguration
        do { projected = try WebsiteConfigSessionBuilder.configuration(draft: draft, scope: scope) }
        catch WebsiteConfigSessionBuildError.unrepresentableConfiguration { return nil }
        guard state.session.synchronizeWebsiteGeneratedConfiguration(projected) else { return nil }
      } else if state.session.configuration.mode == .custom {
        do {
          guard try state.session.synchronizeWebsiteCustomText(receipt.outcome.state.custom) else { return nil }
        } catch WebsiteConfigSessionBuildError.unrepresentableConfiguration { return nil }
      }
      var savedOutcome = receipt.outcome
      savedOutcome.state.runtime = receipt.outcome.state.savedConfig ?? base.savedDraft.projection.runtime
      savedOutcome.state.settingsStore = savedOutcome.state.runtime; savedOutcome.events = []
      let saved = try WebsiteConfigNativeDraft(received: savedOutcome, pointsPerRem: context.pointsPerRem)
      let updated = WebsiteConfigSessionBuilder.Prepared(session: state.session, scope: scope,
        quote: practice.quote, external: practice.external, repetition: practice.repetition)
      try Task.checkCancellation()
      try page.beginLiveSharedReceiptCommit(id, owner: receipt.owner, router: router, capture: capture)
      defer { page.endCommit() }
      let publication = Publication(applicationID: UUID(), draft: draft, savedDraft: saved,
        owner: receipt.owner.owner, environmentRevision: context.revision, pointsPerRem: context.pointsPerRem,
        disk: receipt.disk, background: base.background, font: base.font,
        session: state.session, practice: updated, quoteRecoveries: base.quoteRecoveries,
        ownerLease: receipt.owner, authority: publicationAuthority)
      let progress = state.currentQuoteInitialization
      state = .init(session: state.session, presentation: previous.retainingAppearance(for: publication),
        practice: updated, priorAttemptLedger: state.priorAttemptLedger,
        restartDepartureAttemptID: state.restartDepartureAttemptID)
      if let progress {
        state.quoteInitialization = .init(publication: publication.applicationID, configurationDeparture: nil, progress: progress)
      }
      latest = publication; publicationAuthority.latest = publication.applicationID
      resourceAdmission = UUID(); sessionAdmission = UUID(); sessionRequest = nil
      page.installCommitted(state)
      return publication
    }
  }

  /// Consume the checkpoint into the existing preparation/retry machinery.
  /// No URL parsing, setter replay or receipt storage callback occurs here.
  func resumeSharedReceipt(_ id: UUID, for page: PracticePageSessionStore) throws -> Prepared {
    guard let source = page.state.sharedReceipt?.contentSource else { throw WebsiteConfigCommitCoordinatorError.stale }
    return try source.withReceiptRead { try resumeSharedReceiptBody(id, for: page) }
  }
  private func resumeSharedReceiptBody(_ id: UUID, for page: PracticePageSessionStore) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true; defer { processing = false }
    request = UUID()
    guard let receipt = page.state.sharedReceipt, receipt.id == id, receipt.identity == identity,
      receipt.canInitialize(after: page.state.session), router.isCurrent(receipt.owner), let context = environment(),
      let source = receipt.contentSource, source.ownsReceiptIdentity(receipt.contentCapture),
      latest?.applicationID == receipt.base.applicationID,
      try register.read().revision == receipt.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
    if case .native(let base) = receipt.base {
      return try resumeNativeSharedReceipt(receipt, base: base, for: page, source: source, context: context)
    }
    let capture = try page.captureGeneration(router: router)
    let content = try source.capture(owner: page.owner, preserving: receipt.scope)
    guard content.environment == context else { throw WebsiteConfigCommitCoordinatorError.stale }
    var draft = try WebsiteConfigNativeDraft(received: receipt.outcome, pointsPerRem: context.pointsPerRem)
    draft.funboxMemory = receipt.base.draft.funboxMemory
    var savedOutcome = receipt.outcome
    savedOutcome.state.runtime = receipt.outcome.state.savedConfig ?? receipt.base.savedDraft.projection.runtime
    savedOutcome.state.settingsStore = savedOutcome.state.runtime; savedOutcome.events = []
    let saved = try WebsiteConfigNativeDraft(received: savedOutcome, pointsPerRem: context.pointsPerRem)
    let previous = try unwrappedPractice(page)
    guard let languageUnits = draft.projection.runtime["language"]?.stringUnits else { throw WebsiteConfigNativeDraftError.incompleteRuntime }
    let deferredUntilFinished = !receipt.requiresInitialization
    let previousQuote = (deferredUntilFinished ? page.state.currentQuoteInitialization?.quote : nil) ?? previous.quote
    let repetition = WebsiteConfigRestartPolicy.resolve(requested: false,
      active: deferredUntilFinished ? capture.testActive : receipt.wasActive,
      previouslyRepeated: previous.repetition.repeatsWordset,
      failed: deferredUntilFinished ? page.state.session.outcome == .failed : receipt.wasFailed,
      mode: draft.testParameters.mode, language: String(decoding: languageUnits, as: UTF16.self),
      quoteLanguage: previousQuote.flatMap { WebsiteLanguageIdentity.name(for: $0.language) },
      repeatQuotes: draft.behavior.repeatQuotes, repeatedPace: draft.behavior.repeatedPace)
    try Task.checkCancellation()
    try page.beginCommit(owner: receipt.owner, router: router, capture: capture)
    var state = page.state
    if deferredUntilFinished { state.restartDepartureAttemptID = state.session.automaticInputAttemptID }
    state.retainingSharedScope(receipt.scope)
    state.sharedReceipt = nil
    state.configurationDeparture = .init(id: UUID(), draft: draft, savedDraft: saved, quoteRecoveries: [], disk: receipt.disk,
      identity: identity, environment: context, contentSource: source, requiresContentSource: true,
      repetition: repetition, quote: previousQuote, wordHistory: state.session.generatedWordReplayHistory, sharedReceipt: receipt)
    page.installCommitted(state); page.endCommit()
    var prepared = Prepared(draft: draft, identity: identity, request: request, owner: receipt.owner, environment: context, disk: receipt.disk)
    prepared.savedDraft = saved; prepared.sourcePage = page; prepared.pageCapture = try page.captureGeneration(router: router)
    prepared.contentSource = source; prepared.contentCapture = content
    prepared.applicationEventsApplied = true; prepared.retainsQuoteInitialization = true
    return prepared
  }
  private func resumeNativeSharedReceipt(_ receipt: SharedReceipt, base: NativeSharedBase,
    for page: PracticePageSessionStore, source: WebsiteConfigPracticeScopeSource, context: Environment) throws -> Prepared {
    guard page.state.practice == nil, page.state.presentation == nil, page.state.savedApplication == nil,
      page.state.configurationDeparture == nil else { throw WebsiteConfigCommitCoordinatorError.stale }
    let capture = try page.captureApplication(router: router)
    var scope = receipt.scope
    scope.weakSpotScores = capture.scope.weakSpotScores
    scope.decorationState = capture.scope.decorationState
    scope.arrowChart = capture.scope.arrowChart
    let content = try source.capture(owner: page.owner, preserving: scope)
    guard content.environment == context else { throw WebsiteConfigCommitCoordinatorError.stale }
    var draft = try WebsiteConfigNativeDraft(received: receipt.outcome, pointsPerRem: context.pointsPerRem)
    draft.funboxMemory = base.draft.funboxMemory
    var savedOutcome = receipt.outcome
    savedOutcome.state.runtime = receipt.outcome.state.savedConfig ?? base.savedDraft.projection.runtime
    savedOutcome.state.settingsStore = savedOutcome.state.runtime; savedOutcome.events = []
    let saved = try WebsiteConfigNativeDraft(received: savedOutcome, pointsPerRem: context.pointsPerRem)
    guard let units = draft.projection.runtime["language"]?.stringUnits else { throw WebsiteConfigNativeDraftError.incompleteRuntime }
    let deferred = !receipt.requiresInitialization
    let repetition = WebsiteConfigRestartPolicy.resolve(requested: false,
      active: deferred ? false : receipt.wasActive, previouslyRepeated: base.repetition.repeatsWordset,
      failed: deferred ? page.state.session.outcome == .failed : receipt.wasFailed,
      mode: draft.testParameters.mode, language: String(decoding: units, as: UTF16.self),
      quoteLanguage: base.quote.flatMap { WebsiteLanguageIdentity.name(for: $0.language) },
      repeatQuotes: draft.behavior.repeatQuotes, repeatedPace: draft.behavior.repeatedPace)
    try Task.checkCancellation()
    try page.beginCommit(owner: receipt.owner, router: router, applicationCapture: capture)
    var state = page.state
    state.restartDepartureAttemptID = state.session.automaticInputAttemptID
    state.sharedReceipt = nil
    state.configurationDeparture = .init(id: UUID(), draft: draft, savedDraft: saved, quoteRecoveries: [], disk: receipt.disk,
      identity: identity, environment: context, contentSource: source, requiresContentSource: true,
      repetition: repetition, quote: base.quote, wordHistory: state.session.generatedWordReplayHistory,
      sharedReceipt: receipt, nativeScope: scope)
    page.installCommitted(state); page.endCommit()
    var prepared = Prepared(draft: draft, identity: identity, request: request, owner: receipt.owner, environment: context, disk: receipt.disk)
    prepared.savedDraft = saved; prepared.sourcePage = page; prepared.applicationCapture = try page.captureApplication(router: router)
    prepared.contentSource = source; prepared.contentCapture = content
    prepared.applicationEventsApplied = true; prepared.retainsQuoteInitialization = true
    return prepared
  }
  private func unwrappedPractice(_ page: PracticePageSessionStore) throws -> WebsiteConfigSessionBuilder.Prepared {
    guard let practice = page.state.practice else { throw PracticePageSessionStateError.incomplete }; return practice
  }
  private func checkpointNativeSharedDeparture(_ prepared: Prepared, admission: UUID) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true; defer { processing = false }
    try Task.checkCancellation()
    guard admission == resourceAdmission, isCurrent(prepared), let page = prepared.sourcePage,
      let capture = prepared.applicationCapture, let pending = page.state.configurationDeparture,
      pending.isNativeSharedReceipt, pending.identity == identity, capture.configurationDeparture == pending.id,
      let saved = prepared.savedDraft else { throw WebsiteConfigCommitCoordinatorError.stale }
    try page.beginCommit(owner: prepared.owner, router: router, applicationCapture: capture)
    let revision: WebsiteConfigFileRegister.Revision
    do {
      switch try register.commit(saved, replacing: prepared.disk, preservingUnchanged: true) {
      case .committed(let next): revision = next
      case .conflict, .unavailable: throw WebsiteConfigCommitCoordinatorError.stale
      }
    } catch { page.endCommit(); throw error }
    var state = page.state
    state.configurationDeparture = .init(id: pending.id, draft: prepared.draft, savedDraft: saved,
      quoteRecoveries: prepared.quoteRecoveries, disk: revision, identity: identity, environment: pending.environment,
      contentSource: pending.contentSource, requiresContentSource: pending.requiresContentSource,
      repetition: pending.repetition, quote: pending.quote, wordHistory: pending.wordHistory,
      sharedReceipt: pending.sharedReceipt, nativeScope: pending.nativeScope)
    if let progress = prepared.quoteInitialization {
      state.quoteInitialization = .init(publication: nil, configurationDeparture: pending.id, progress: progress)
    }
    page.installCommitted(state); page.endCommit()
    var updated = prepared; updated.disk = revision
    updated.applicationCapture = try page.captureApplication(router: router)
    guard isCurrent(updated) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return updated
  }
  struct BackgroundPrepared {
    fileprivate let configuration: Prepared
    fileprivate let admission: UUID
    let background: WebsiteConfigBackgroundResource
  }
  /// Font and background only, not all application resources or a UI transaction.
  struct ResourcesPrepared {
    fileprivate let configuration: Prepared
    fileprivate let admission: UUID
    let background: WebsiteConfigBackgroundResource
    let font: WebsiteConfigFontResource
  }
  struct SessionPrepared {
    fileprivate let resources: ResourcesPrepared
    fileprivate let admission: UUID
    let session: TypingSession
    let practice: WebsiteConfigSessionBuilder.Prepared?
  }
  /// Normally an attempt transition; source recovery can require a saved setter.
  struct NextPrepared { fileprivate let session: SessionPrepared }
  struct RestartAdmission {
    fileprivate var resources: ResourcesPrepared
    fileprivate let original: TypingSession
    fileprivate let previous: WebsiteConfigSessionBuilder.Prepared
    fileprivate let repetition: WebsitePracticeRepetition
  }
  /// Persisted setter / accepted departure, but not a new delivered attempt.
  /// This capability is window-local; cold recovery reads the ordinary record.
  struct ConfigurationDeparture {
    let id: UUID
    let draft: WebsiteConfigNativeDraft
    var configurationWasSaved: Bool {
      if let receipt = sharedReceipt {
        return !receipt.outcome.configWrites.isEmpty
          || draft.projection.events.dropFirst(receipt.outcome.events.count).contains { $0.nosave == false }
      }
      return draft.projection.events.contains { $0.nosave == false }
    }
    var isSharedReceipt: Bool { sharedReceipt != nil }
    var sharedStorageFailureCount: Int { sharedReceipt?.outcome.storageFailures.count ?? 0 }
    var isNativeSharedReceipt: Bool { sharedReceipt?.isNative == true }
    var sharedScope: WebsiteConfigSessionBuilder.Scope? { nativeScope ?? sharedReceipt?.scope }
    fileprivate let savedDraft: WebsiteConfigNativeDraft
    fileprivate let quoteRecoveries: [WebsiteQuoteSampler.Recovery]
    fileprivate let disk: WebsiteConfigFileRegister.Revision
    fileprivate let identity: UUID
    fileprivate let environment: Environment
    fileprivate weak var contentSource: WebsiteConfigPracticeScopeSource?
    fileprivate let requiresContentSource: Bool
    let repetition: WebsitePracticeRepetition
    fileprivate let quote: OfflineQuote?
    fileprivate let wordHistory: GeneratedWordReplayHistory?
    fileprivate var sharedReceipt: SharedReceipt? = nil
    fileprivate var nativeScope: WebsiteConfigSessionBuilder.Scope? = nil
  }
  enum ConfigurationDepartureOutcome {
    case accepted(Prepared), acceptedRetired, stale, conflict, unavailable, busy
    case futureSelectionSaved(Publication)
    case inactiveLayoutSequenceSaved(Publication)
  }
  func beginConfigurationRestart(_ prepared: Prepared, for page: PracticePageSessionStore,
    action: WebsiteConfigPracticeEdit) throws -> ConfigurationDepartureOutcome {
    guard !processing, page.restartController?.isPreparing != true else { return .busy }
    processing = true; defer { processing = false }
    try Task.checkCancellation()
    guard isCurrent(prepared), prepared.sourcePage === page,
      let capture = prepared.pageCapture,
      page.state.configurationDeparture == nil,
      case .edited(let edit) = prepared.draft.origin, edit.key == action.key else { return .stale }
    guard !capture.testActive || !page.state.session.configuration.modifiers.contains(.noQuit) else {
      if action.key == "customPolyglot" {
        return try saveSelectionWithoutRestart(prepared, for: page, capture: capture, key: "customPolyglot")
      }
      throw PracticePageSessionStateError.locked
    }
    if action.key == "customLayoutfluid", !prepared.draft.generators.requestedModifiers.contains(.layoutFluid) {
      return try saveSelectionWithoutRestart(prepared, for: page, capture: capture, key: "customLayoutfluid")
    }
    guard let previous = page.state.practice,
      case .string(let language)? = prepared.draft.projection.runtime["language"] else {
      throw PracticePageSessionStateError.incomplete
    }
    // Resolve against the lifecycle before initialization, including failed
    // quote repetition. Retain it across init failure/retry rather than
    // consulting a retired attempt again.
    let repetition = WebsiteConfigRestartPolicy.resolve(requested: false, active: capture.testActive,
      previouslyRepeated: previous.repetition.repeatsWordset,
      failed: page.state.session.outcome == .failed
        && page.state.restartDepartureAttemptID != page.state.session.automaticInputAttemptID,
      mode: prepared.draft.testParameters.mode, language: language,
      quoteLanguage: previous.quote.flatMap { WebsiteLanguageIdentity.name(for: $0.language) },
      repeatQuotes: prepared.draft.behavior.repeatQuotes, repeatedPace: prepared.draft.behavior.repeatedPace)
    // Close a value copy first. A rejected file CAS must leave the real clock,
    // input, ledger and publication untouched.
    var departed = page.state
    let inheritedQuoteInitialization = departed.currentQuoteInitialization
    let measurement = capture.testActive ? departed.session.abandonAndMeasure() : nil
    let applied = try WebsiteConfigLazyModeLifecycle.applyingEvents(prepared.draft,
      pointsPerRem: prepared.environment.pointsPerRem)
    // The source setter saves before dispatch. Its listener can change the
    // independent Arabic preference, or enable lazy mode with nosave. Carry
    // listener memory durably, but do not persist that runtime-only override.
    var saved = prepared.funboxSelectionSaved == false ? (prepared.savedDraft ?? prepared.draft) : prepared.draft
    saved.lazyMemory = applied.lazyMemory
    guard isCurrent(prepared) else { return .stale }
    try Task.checkCancellation()
    try page.beginCommit(owner: prepared.owner, router: router, capture: capture)
    let disk: WebsiteConfigFileRegister.Revision
    do {
      let result = try register.commit(saved, replacing: prepared.disk, preservingUnchanged: prepared.funboxSelectionSaved == false)
      switch result {
      case .committed(let value): disk = value
      case .conflict: page.endCommit(); retire(prepared); return .conflict
      case .unavailable: page.endCommit(); retire(prepared); return .unavailable
      }
    } catch WebsiteConfigFileRegisterError.busy { page.endCommit(); return .busy }
    catch { page.endCommit(); throw error }
    // Irreversible boundary: no cancellation or throwing observer after CAS.
    // The old resource presentation remains explicitly pending, not current.
    departed.restartDepartureAttemptID = departed.session.automaticInputAttemptID
    if let measurement {
      departed.priorAttemptLedger.recordRestart(engagedDuration: measurement.engagedDuration,
        accuracy: measurement.accuracy, savingEnabled: prepared.draft.behavior.saveCompletedResults)
    }
    departed.configurationDeparture = .init(id: UUID(), draft: applied, savedDraft: saved,
      quoteRecoveries: prepared.quoteRecoveries, disk: disk,
      identity: identity, environment: prepared.environment, contentSource: prepared.contentSource,
      requiresContentSource: prepared.contentCapture != nil, repetition: repetition, quote: previous.quote,
      wordHistory: departed.session.generatedWordReplayHistory)
    if var progress = inheritedQuoteInitialization {
      progress.appliedQuoteLengthEvents = nil
      departed.quoteInitialization = .init(publication: capture.publication.applicationID,
        configurationDeparture: departed.configurationDeparture?.id, progress: progress)
    } else { departed.quoteInitialization = nil }
    resourceAdmission = UUID(); sessionAdmission = UUID(); sessionRequest = nil
    page.installCommitted(departed)
    page.endCommit()
    guard let refreshed = try? page.captureGeneration(router: router) else { return .acceptedRetired }
    var admitted = prepared
    admitted.retainsQuoteInitialization = true
    admitted.draft = applied; admitted.savedDraft = saved; admitted.disk = disk; admitted.pageCapture = refreshed
    return .accepted(admitted)
  }

  /// Only these two source selections may save without rebuilding the attempt:
  /// Polyglot when No Quit blocks its following dispatch, or an inactive
  /// Layoutfluid sequence whose successful event has no restart subscriber.
  private func saveSelectionWithoutRestart(_ prepared: Prepared, for page: PracticePageSessionStore,
    capture: PracticePageSessionStore.GenerationCapture, key: String) throws -> ConfigurationDepartureOutcome {
    guard ["customPolyglot", "customLayoutfluid"].contains(key),
      key != "customLayoutfluid" || !prepared.draft.generators.requestedModifiers.contains(.layoutFluid),
      let previous = page.state.presentation, let practice = page.state.practice,
      prepared.draft.projection.rejectedKeys.isEmpty, !prepared.draft.projection.events.isEmpty,
      prepared.draft.projection.runtime.count == capture.publication.draft.projection.runtime.count,
      prepared.draft.projection.events.allSatisfy({ $0.key == key && $0.nosave == false }),
      capture.publication.draft.projection.runtime.allSatisfy({ field, value in
        field == key || prepared.draft.projection.runtime[field] == value
      }) else { return .stale }
    let applied = try WebsiteConfigLazyModeLifecycle.applyingEvents(prepared.draft,
      pointsPerRem: prepared.environment.pointsPerRem)
    var saved = prepared.draft; saved.lazyMemory = applied.lazyMemory
    var state = page.state
    let progress = state.currentQuoteInitialization
    let controller = page.restartController
    guard isCurrent(prepared) else { return .stale }
    try Task.checkCancellation()
    if key == "customPolyglot" {
      try page.beginFuturePolyglotCommit(owner: prepared.owner, router: router, capture: capture, draft: prepared.draft)
    } else {
      // Layoutfluid retains ordinary No Quit admission; no bypass is added.
      try page.beginCommit(owner: prepared.owner, router: router, capture: capture)
    }
    defer { page.endCommit() }
    let revision: WebsiteConfigFileRegister.Revision
    do {
      switch try register.commit(saved, replacing: prepared.disk) {
      case .committed(let value): revision = value
      case .conflict: return .conflict
      case .unavailable: return .unavailable
      }
    } catch WebsiteConfigFileRegisterError.busy { return .busy }
    // No callback, suspension or throwing operation after the durable CAS.
    let publication = Publication(applicationID: UUID(), draft: applied, savedDraft: saved,
      owner: prepared.owner.owner, environmentRevision: prepared.environment.revision,
      pointsPerRem: prepared.environment.pointsPerRem, disk: revision,
      background: capture.publication.background, font: capture.publication.font,
      session: practice.session, practice: practice,
      quoteRecoveries: capture.publication.quoteRecoveries, ownerLease: prepared.owner,
      authority: publicationAuthority)
    state.presentation = previous.retainingAppearance(for: publication)
    if let progress {
      state.quoteInitialization = .init(publication: publication.applicationID, configurationDeparture: nil, progress: progress)
    }
    latest = publication; publicationAuthority.latest = publication.applicationID
    page.installCommitted(state, retainingRestartController: controller)
    return key == "customPolyglot" ? .futureSelectionSaved(publication) : .inactiveLayoutSequenceSaved(publication)
  }
  /// Retry only initialization. Never re-run the accepted setter or measure
  /// the closed attempt again. A different coordinator must use cold restore.
  func resumeConfigurationRestart(for page: PracticePageSessionStore) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true; defer { processing = false }
    try Task.checkCancellation()
    request = UUID()
    guard let pending = page.state.configurationDeparture, pending.identity == identity,
      let owner = router.captureLease(), owner.owner == page.owner,
      let context = environment(), context == pending.environment else { throw WebsiteConfigCommitCoordinatorError.stale }
    let capture: PracticePageSessionStore.GenerationCapture?
    let application: PracticePageSessionStore.ApplicationCapture?
    if pending.isNativeSharedReceipt {
      capture = nil; application = try page.captureApplication(router: router)
      guard latest == nil, page.state.presentation == nil, page.state.practice == nil,
        application?.configurationDeparture == pending.id else { throw WebsiteConfigCommitCoordinatorError.stale }
    } else {
      let current = try page.captureGeneration(router: router)
      guard current.configurationDeparture == pending.id,
        current.publication.authority === publicationAuthority,
        latest?.applicationID == current.publication.applicationID else { throw WebsiteConfigCommitCoordinatorError.stale }
      capture = current; application = nil
    }
    guard try register.read().revision == pending.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
    var prepared = Prepared(draft: pending.draft, identity: identity, request: request,
      owner: owner, environment: context, disk: pending.disk)
    prepared.savedDraft = pending.savedDraft
    prepared.quoteRecoveries = pending.quoteRecoveries
    prepared.retainsQuoteInitialization = true
    prepared.quoteInitialization = page.state.currentQuoteInitialization
    prepared.sourcePage = page; prepared.pageCapture = capture; prepared.applicationCapture = application
    if pending.requiresContentSource {
      guard let source = pending.contentSource else { throw WebsiteConfigCommitCoordinatorError.unavailable }
      guard let scope = pending.isNativeSharedReceipt ? (pending.sharedScope ?? application?.scope) : capture?.scope
      else { throw WebsiteConfigCommitCoordinatorError.stale }
      let content = try source.capture(owner: page.owner, preserving: scope)
      guard content.environment == context else { throw WebsiteConfigCommitCoordinatorError.stale }
      prepared.contentSource = source; prepared.contentCapture = content
    }
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return prepared
  }
  struct PreviousAttempt {
    struct Incomplete {
      let engagedDuration: TimeInterval
      let accuracy: Double
    }
    let session: TypingSession
    /// Capture before installation; a caller must not measure a live old clock
    /// later when recording abandonment. nil for unstarted/terminal attempts.
    let incomplete: Incomplete?
  }
  enum NextOutcome { case advanced(PreviousAttempt), stale, conflict, unavailable, busy }
  enum Outcome { case committed(Publication), stale, conflict, unavailable, busy }

  /// A source threshold setter has no restart dispatch/subscriber. Keep the
  /// live attempt and let the timer/word-commit consume its updated rules.
  func commitLiveThreshold(_ prepared: Prepared, for page: PracticePageSessionStore) throws -> Outcome {
    try commitLiveEdit(prepared, for: page, kind: .threshold)
  }
  func commitLiveBehavior(_ prepared: Prepared, for page: PracticePageSessionStore) throws -> Outcome {
    try commitLiveEdit(prepared, for: page, kind: .behavior)
  }
  func commitLiveInputRule(_ prepared: Prepared, for page: PracticePageSessionStore) throws -> Outcome {
    try commitLiveEdit(prepared, for: page, kind: .inputRule)
  }
  func commitLiveSound(_ prepared: Prepared, for page: PracticePageSessionStore) throws -> Outcome {
    try commitLiveEdit(prepared, for: page, kind: .sound)
  }
  func commitLiveCaret(_ prepared: Prepared, for page: PracticePageSessionStore) throws -> Outcome {
    try commitLiveEdit(prepared, for: page, kind: .caret)
  }
  func commitLivePaceSelection(_ prepared: Prepared, for page: PracticePageSessionStore, targetWpm: Double?) throws -> Outcome {
    try commitLiveEdit(prepared, for: page, kind: .pace, paceTarget: targetWpm)
  }
  func commitLiveAppearance(_ prepared: Prepared, for page: PracticePageSessionStore) throws -> Outcome {
    try commitLiveEdit(prepared, for: page, kind: .appearance)
  }
  func commitLiveKeymap(_ prepared: Prepared, for page: PracticePageSessionStore) throws -> Outcome {
    try commitLiveEdit(prepared, for: page, kind: .keymap)
  }
  func commitLiveLayoutFluid(_ prepared: Prepared, for page: PracticePageSessionStore) throws -> Outcome {
    try commitLiveEdit(prepared, for: page, kind: .layoutFluid)
  }
  struct LiveFontPrepared {
    fileprivate let configuration: Prepared
    fileprivate let admission: UUID
    fileprivate let font: WebsiteConfigFontResource
  }
  struct FontRefreshPrepared {
    fileprivate let configuration: Prepared
    fileprivate let admission: UUID
    fileprivate let font: WebsiteConfigFontResource
  }
  /// A file change is not a configuration setter. Capture the latest page
  /// under the new resource epoch, retaining its separate saved snapshot.
  func prepareFontRefresh(for page: PracticePageSessionStore, local: WebsiteConfigFontResource.Local) throws -> FontRefreshPrepared {
    let prepared = try fontRefreshTicket(for: page)
    let admission = try beginAsyncResources(prepared)
    let font = try WebsiteConfigFontResource.prepare(typography: prepared.draft.keyboardTypography,
      language: prepared.draft.testParameters.language, local: local)
    try checkAsyncResources(prepared, admission: admission)
    return .init(configuration: prepared, admission: admission, font: font)
  }
  private func fontRefreshTicket(for page: PracticePageSessionStore) throws -> Prepared {
    guard !processing, page.restartController?.isPreparing != true else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true; defer { processing = false }
    guard page.state.configurationDeparture == nil, page.state.savedApplication == nil, page.state.sharedReceipt == nil
    else { throw WebsiteConfigCommitCoordinatorError.stale }
    request = UUID()
    guard let owner = router.captureLease(), owner.owner == page.owner, let context = environment()
    else { throw WebsiteConfigCommitCoordinatorError.noOwner }
    let capture = try page.captureGeneration(router: router)
    let base = capture.publication
    guard base.authority === publicationAuthority, latest?.applicationID == base.applicationID,
      try register.read().revision == base.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
    var prepared = Prepared(draft: base.draft, identity: identity, request: request,
      owner: owner, environment: context, disk: base.disk)
    prepared.savedDraft = base.savedDraft; prepared.sourcePage = page; prepared.pageCapture = capture
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return prepared
  }
  func commitFontRefresh(_ resources: FontRefreshPrepared, for page: PracticePageSessionStore) throws -> Outcome {
    guard !processing, page.restartController?.isPreparing != true else { return .busy }
    processing = true; defer { processing = false }
    try Task.checkCancellation()
    let prepared = resources.configuration
    guard resources.admission == resourceAdmission, isCurrent(prepared), prepared.sourcePage === page,
      let capture = prepared.pageCapture, let previous = page.state.presentation, let practice = page.state.practice,
      page.state.configurationDeparture == nil, page.state.savedApplication == nil, page.state.sharedReceipt == nil
    else { return .stale }
    try page.beginFontResourceCommit(owner: prepared.owner, router: router, capture: capture)
    defer { page.endCommit() }
    guard try register.read().revision == prepared.disk else { return .conflict }
    var state = page.state
    let progress = state.currentQuoteInitialization, controller = page.restartController
    let updated = WebsiteConfigSessionBuilder.Prepared(session: state.session, scope: practice.scope,
      quote: practice.quote, external: practice.external, repetition: practice.repetition)
    let publication = Publication(applicationID: UUID(), draft: capture.publication.draft,
      savedDraft: capture.publication.savedDraft, owner: prepared.owner.owner,
      environmentRevision: prepared.environment.revision, pointsPerRem: prepared.environment.pointsPerRem,
      disk: prepared.disk, background: capture.publication.background, font: resources.font,
      session: state.session, practice: updated, quoteRecoveries: capture.publication.quoteRecoveries,
      ownerLease: prepared.owner, authority: publicationAuthority)
    state = .init(session: state.session, presentation: previous.retainingAppearance(for: publication),
      practice: updated, priorAttemptLedger: state.priorAttemptLedger,
      restartDepartureAttemptID: state.restartDepartureAttemptID, quoteInitialization: state.quoteInitialization)
    if let progress { state.quoteInitialization = .init(publication: publication.applicationID, configurationDeparture: nil, progress: progress) }
    latest = publication; publicationAuthority.latest = publication.applicationID
    page.installCommitted(state, retainingRestartController: controller)
    retire(prepared)
    return .committed(publication)
  }
  func prepareLiveFont(_ prepared: Prepared, local: WebsiteConfigFontResource.Local) throws -> LiveFontPrepared {
    guard let capture = prepared.pageCapture,
      WebsiteConfigFontEdit.admits(prepared.draft, from: capture.publication.draft) else { throw WebsiteConfigCommitCoordinatorError.stale }
    let admission = try beginAsyncResources(prepared)
    let font = try WebsiteConfigFontResource.prepare(typography: prepared.draft.keyboardTypography,
      language: prepared.draft.testParameters.language, local: local)
    try checkAsyncResources(prepared, admission: admission)
    return .init(configuration: prepared, admission: admission, font: font)
  }
  func commitLiveFont(_ prepared: LiveFontPrepared, for page: PracticePageSessionStore) throws -> Outcome {
    guard prepared.admission == resourceAdmission else { return .stale }
    return try commitLiveEdit(prepared.configuration, for: page, kind: .font, font: prepared.font)
  }
  func commitLiveTheme(_ prepared: Prepared, for page: PracticePageSessionStore) throws -> Outcome {
    try commitLiveEdit(prepared, for: page, kind: .theme)
  }
  private enum LiveEditKind { case threshold, behavior, inputRule, sound, caret, pace, appearance, keymap, layoutFluid, font, theme }
  private func commitLiveEdit(_ prepared: Prepared, for page: PracticePageSessionStore, kind: LiveEditKind,
    paceTarget: Double? = nil, font: WebsiteConfigFontResource? = nil) throws -> Outcome {
    guard !processing, page.restartController?.isPreparing != true else { return .busy }
    processing = true; defer { processing = false }
    try Task.checkCancellation()
    guard isCurrent(prepared), prepared.sourcePage === page, let capture = prepared.pageCapture,
      page.state.configurationDeparture == nil, page.state.savedApplication == nil,
      let previous = page.state.presentation, let practice = page.state.practice else { return .stale }
    if let navigation = prepared.wordNavigation {
      guard kind == .layoutFluid, page.state.session.ownsWebsiteWordNavigation(navigation) else { return .stale }
    }
    switch kind {
    case .theme:
      guard WebsiteThemeCommand.admits(prepared.draft, from: capture.publication.draft), page.state.sharedReceipt == nil else { return .stale }
    case .font:
      guard font != nil, WebsiteConfigFontEdit.admits(prepared.draft, from: capture.publication.draft) else { return .stale }
    case .behavior:
      guard WebsiteConfigBehaviorEdit.admits(prepared.draft, from: capture.publication.draft) else { return .stale }
    case .inputRule:
      guard WebsiteConfigInputCommand.admits(prepared.draft, from: capture.publication.draft) else { return .stale }
    case .sound:
      guard WebsiteConfigSoundEdit.admits(prepared.draft, from: capture.publication.draft) else { return .stale }
    case .caret:
      guard WebsiteConfigCaretEdit.admits(prepared.draft, from: capture.publication.draft) else { return .stale }
    case .pace:
      guard WebsitePaceCommand.admits(prepared.draft, from: capture.publication.draft) else { return .stale }
    case .appearance:
      guard WebsiteAppearanceCommand.admits(prepared.draft, from: capture.publication.draft) else { return .stale }
    case .keymap:
      guard WebsiteKeymapCommand.admits(prepared.draft, from: capture.publication.draft) else { return .stale }
    case .layoutFluid:
      guard WebsiteLayoutFluidTransition.admits(prepared.draft, from: capture.publication.draft) else { return .stale }
    case .threshold:
      guard case .edited(let edit) = prepared.draft.origin, WebsiteConfigThresholdEdit.keys.contains(edit.key),
      prepared.draft.projection.rejectedKeys.isEmpty, !prepared.draft.projection.events.isEmpty,
      prepared.draft.projection.events.allSatisfy({ WebsiteConfigThresholdEdit.keys.contains($0.key) && $0.nosave == false }),
      prepared.draft.projection.runtime.count == capture.publication.draft.projection.runtime.count,
      capture.publication.draft.projection.runtime.allSatisfy({ key, value in
        WebsiteConfigThresholdEdit.keys.contains(key) || prepared.draft.projection.runtime[key] == value
      }) else { return .stale }
    }
    var state = page.state
    let themeAppearance: WebsiteConfigPublishedPresentation.PreparedAppearance?
    if kind == .theme, case .edited(let edit) = prepared.draft.origin {
      themeAppearance = try previous.prepareThemeChange(draft: prepared.draft, key: edit.key)
    } else { themeAppearance = nil }
    let progress = state.currentQuoteInitialization
    let controller = page.restartController
    if kind == .inputRule { state.session.synchronizeWebsiteInputRules(prepared.draft.inputRules.rules) }
    else if kind != .sound && kind != .caret && kind != .pace && kind != .appearance && kind != .keymap && kind != .layoutFluid && kind != .font && kind != .theme {
      state.session.synchronizeLiveInputRules(prepared.draft.inputRules.rules, websiteThresholds: true)
    }
    if kind == .appearance, case .edited(let edit) = prepared.draft.origin, edit.key == "highlightMode" {
      state.session.refreshPromptPresentation()
    }
    if kind == .pace, case .edited(let edit) = prepared.draft.origin, edit.key == "paceCaret" {
      state.session.configurePace(wpm: paceTarget, style: prepared.draft.presentation.paceCaretStyle)
    }
    let updatedPractice = WebsiteConfigSessionBuilder.Prepared(session: state.session, scope: practice.scope,
      quote: practice.quote, external: practice.external, repetition: practice.repetition)
    guard isCurrent(prepared) else { return .stale }
    try Task.checkCancellation()
    switch kind {
    case .theme:
      try page.beginLiveThemeCommit(owner: prepared.owner, router: router, capture: capture, draft: prepared.draft)
    case .font:
      try page.beginLiveFontCommit(owner: prepared.owner, router: router, capture: capture, draft: prepared.draft)
    case .behavior:
      try page.beginLiveBehaviorCommit(owner: prepared.owner, router: router, capture: capture, draft: prepared.draft)
    case .inputRule:
      try page.beginLiveInputRuleCommit(owner: prepared.owner, router: router, capture: capture, draft: prepared.draft)
    case .sound:
      try page.beginLiveSoundCommit(owner: prepared.owner, router: router, capture: capture, draft: prepared.draft)
    case .caret:
      try page.beginLiveCaretCommit(owner: prepared.owner, router: router, capture: capture, draft: prepared.draft)
    case .pace:
      try page.beginLivePaceCommit(owner: prepared.owner, router: router, capture: capture, draft: prepared.draft)
    case .appearance:
      try page.beginLiveAppearanceCommit(owner: prepared.owner, router: router, capture: capture, draft: prepared.draft)
    case .keymap:
      try page.beginLiveKeymapCommit(owner: prepared.owner, router: router, capture: capture, draft: prepared.draft)
    case .layoutFluid:
      try page.beginLiveLayoutFluidCommit(owner: prepared.owner, router: router, capture: capture, draft: prepared.draft)
    case .threshold: try page.beginCommit(owner: prepared.owner, router: router, capture: capture)
    }
    defer { page.endCommit() }
    let volatile = kind == .layoutFluid && prepared.draft.projection.events.first?.nosave == true
    let revision: WebsiteConfigFileRegister.Revision
    do {
      if volatile {
        guard try register.read().revision == prepared.disk else { return .conflict }
        revision = prepared.disk
      } else {
        switch try register.commit(prepared.draft, replacing: prepared.disk) {
        case .committed(let value): revision = value
        case .conflict: return .conflict
        case .unavailable: return .unavailable
        }
      }
    } catch WebsiteConfigFileRegisterError.busy { return .busy }
    // No suspension, callback, legacy preference write or fallible operation
    // between the disk check/CAS and publishing the corresponding live rules.
    let publication = Publication(applicationID: UUID(), draft: prepared.draft, savedDraft: volatile ? capture.publication.savedDraft : prepared.draft,
      owner: prepared.owner.owner, environmentRevision: prepared.environment.revision,
      pointsPerRem: prepared.environment.pointsPerRem, disk: revision,
      background: capture.publication.background, font: font ?? capture.publication.font,
      session: state.session, practice: updatedPractice, quoteRecoveries: capture.publication.quoteRecoveries,
      ownerLease: prepared.owner, authority: publicationAuthority)
    let presentation = themeAppearance.map { WebsiteConfigPublishedPresentation(publication: publication, preparedAppearance: $0) }
      ?? previous.retainingAppearance(for: publication)
    state = .init(session: state.session, presentation: presentation,
      practice: updatedPractice, priorAttemptLedger: state.priorAttemptLedger,
      restartDepartureAttemptID: state.restartDepartureAttemptID, quoteInitialization: state.quoteInitialization)
    if let progress {
      state.quoteInitialization = .init(publication: publication.applicationID, configurationDeparture: nil, progress: progress)
    }
    latest = publication; publicationAuthority.latest = publication.applicationID
    page.installCommitted(state, retainingRestartController: controller)
    retire(prepared)
    return .committed(publication)
  }
  enum Restoration { case missing, unavailable, prepared(Prepared) }
  private let router: PreferenceConfigurationSaveRouter
  private let register: WebsiteConfigFileRegister
  private let environment: () -> Environment?
  private let externalLoader: WebsiteConfigSessionBuilder.ExternalLoader?
  private let identity = UUID()
  private var request = UUID()
  private var resourceAdmission = UUID()
  private var sessionAdmission = UUID()
  private var sessionRequest: UUID?
  private var latest: Publication?
  private let publicationAuthority: WebsiteConfigPublicationAuthority
  private var processing = false

  init(router: PreferenceConfigurationSaveRouter, register: WebsiteConfigFileRegister,
    loadExternal: WebsiteConfigSessionBuilder.ExternalLoader? = nil,
    environment: @escaping () -> Environment?) {
    self.router = router; self.register = register; self.environment = environment
    externalLoader = loadExternal
    publicationAuthority = .init(register: register)
  }

  func prepare(_ json: String) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true
    defer { processing = false }
    request = UUID()
    guard let owner = router.captureLease() else { throw WebsiteConfigCommitCoordinatorError.noOwner }
    guard let context = environment() else { throw WebsiteConfigCommitCoordinatorError.noEnvironment }
    var draft = try WebsiteConfigNativeProfile.prepareDraft(json, pointsPerRem: context.pointsPerRem, context: context.context)
    let snapshot = try register.read()
    guard let disk = snapshot.revision else { throw WebsiteConfigCommitCoordinatorError.unavailable }
    draft.lazyMemory = snapshot.lazyMemory
    let prepared = Prepared(draft: draft, identity: identity, request: request, owner: owner, environment: context, disk: disk)
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return prepared
  }

  /// Cold native-record application, not a JSON import or an implicit reset.
  /// Preparation never repairs missing/opaque records and does not publish or
  /// write. Resources and practice must still be prepared before page commit.
  /// A newer restoration intent retires older producers even when no usable
  /// record exists. The captured record revision remains the CAS boundary.
  func prepareRestoration() throws -> Restoration {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true
    defer { processing = false }
    request = UUID()
    guard let owner = router.captureLease() else { throw WebsiteConfigCommitCoordinatorError.noOwner }
    guard let context = environment() else { throw WebsiteConfigCommitCoordinatorError.noEnvironment }
    let disk = try register.read()
    let restoration = try WebsiteConfigNativeProfile.prepareNativeRestoration(disk.state, context: context.context)
    guard router.isCurrent(owner), environment() == context, router.isCurrent(owner) else {
      throw WebsiteConfigCommitCoordinatorError.stale
    }
    switch restoration {
    case .missing: return .missing
    case .unavailable: return .unavailable
    case .prepared(let value):
      guard let revision = disk.revision else { return .unavailable }
      var draft = try WebsiteConfigNativeDraft(restoration: value, pointsPerRem: context.pointsPerRem)
      draft.lazyMemory = disk.lazyMemory
      let prepared = Prepared(draft: draft, identity: identity, request: request,
        owner: owner, environment: context, disk: revision)
      guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
      return .prepared(prepared)
    }
  }

  /// Full application bound to current window input/content, including the
  /// first application where no published profile or generated scope exists.
  func prepare(_ json: String, for page: PracticePageSessionStore,
    refreshingWith source: WebsiteConfigPracticeScopeSource) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    request = UUID()
    let capture = try page.captureApplication(router: router)
    return try bindApplication(prepare(json), to: page, capture: capture, source: source)
  }

  func prepareRestoration(for page: PracticePageSessionStore,
    refreshingWith source: WebsiteConfigPracticeScopeSource) throws -> Restoration {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    request = UUID()
    let capture = try page.captureApplication(router: router)
    let restoration = try prepareRestoration()
    guard page.isCurrent(capture, router: router) else { throw WebsiteConfigCommitCoordinatorError.stale }
    switch restoration {
    case .missing, .unavailable: return restoration
    case .prepared(let prepared):
      return .prepared(try bindApplication(prepared, to: page, capture: capture, source: source))
    }
  }

  private func bindApplication(_ prepared: Prepared, to page: PracticePageSessionStore,
    capture: PracticePageSessionStore.ApplicationCapture,
    source: WebsiteConfigPracticeScopeSource) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true
    defer { processing = false }
    guard isCurrent(prepared), page.isCurrent(capture, router: router) else {
      throw WebsiteConfigCommitCoordinatorError.stale
    }
    let content = try source.capture(owner: page.owner, preserving: capture.scope)
    guard content.environment == prepared.environment else { throw WebsiteConfigCommitCoordinatorError.stale }
    var bound = prepared
    bound.draft.funboxMemory = page.state.configurationDeparture?.draft.funboxMemory
      ?? page.state.presentation?.publication.draft.funboxMemory ?? .init()
    bound.sourcePage = page; bound.applicationCapture = capture
    bound.contentSource = source; bound.contentCapture = content
    guard isCurrent(bound) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return bound
  }

  /// Accept a complete JSON import or a valid native cold restoration before
  /// asynchronous resource/text loading. Unchanged cold records keep their
  /// revision, including other windows' existing publication authority.
  /// An unsuccessful CAS changes no page state; a successful one is retained
  /// even when initialization is cancelled or fails later.
  func acceptApplication(_ prepared: Prepared, for page: PracticePageSessionStore) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true; defer { processing = false }
    guard isCurrent(prepared), prepared.sourcePage === page,
      let capture = prepared.applicationCapture, prepared.savedApplicationID == nil else {
      throw WebsiteConfigCommitCoordinatorError.stale
    }
    let restoringNative: Bool
    if case .imported = prepared.draft.origin { restoringNative = false }
    else if case .restored(let value) = prepared.draft.origin, case .nativeState = value.origin { restoringNative = true }
    else { throw WebsiteConfigCommitCoordinatorError.stale }
    try Task.checkCancellation()
    try page.beginCommit(owner: prepared.owner, router: router, applicationCapture: capture)
    defer { page.endCommit() }
    let disk: WebsiteConfigFileRegister.Revision
    switch try register.commit(prepared.draft, replacing: prepared.disk, preservingUnchanged: restoringNative) {
    case .committed(let value): disk = value
    case .conflict: throw WebsiteConfigCommitCoordinatorError.stale
    case .unavailable: throw WebsiteConfigCommitCoordinatorError.unavailable
    }
    // No suspension, fallible callback or cancellation check after the CAS.
    let id = UUID()
    var admitted = prepared
    admitted.disk = disk; admitted.savedDraft = prepared.draft
    admitted.savedApplicationID = id
    admitted.applicationCapture = capture.acceptingApplication(id)
    var state = page.state
    state.savedApplication = .init(id: id, ticket: admitted)
    page.installCommitted(state)
    return admitted
  }

  func resumeApplication(for page: PracticePageSessionStore) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true; defer { processing = false }
    try Task.checkCancellation()
    guard let pending = page.state.savedApplication, pending.ticket.identity == identity,
      let source = pending.ticket.contentSource,
      router.isCurrent(pending.ticket.owner), environment() == pending.ticket.environment,
      try register.read().revision == pending.ticket.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
    request = UUID()
    var resumed = pending.ticket; resumed.request = request
    resumed.applicationCapture = try page.captureApplication(router: router)
    let content = try source.capture(owner: page.owner,
      preserving: pending.ticket.contentCapture?.scope ?? .init())
    guard content.environment == resumed.environment else { throw WebsiteConfigCommitCoordinatorError.stale }
    resumed.contentCapture = content
    guard isCurrent(resumed) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return resumed
  }

  private func checkpointApplication(_ prepared: Prepared, admission: UUID) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true; defer { processing = false }
    try Task.checkCancellation()
    guard admission == resourceAdmission, isCurrent(prepared), let page = prepared.sourcePage,
      let capture = prepared.applicationCapture, let id = prepared.savedApplicationID,
      page.state.savedApplication?.id == id, let saved = prepared.savedDraft else {
      throw WebsiteConfigCommitCoordinatorError.stale
    }
    try page.beginCommit(owner: prepared.owner, router: router, applicationCapture: capture)
    defer { page.endCommit() }
    let disk: WebsiteConfigFileRegister.Revision
    switch try register.commit(saved, replacing: prepared.disk, preservingUnchanged: true) {
    case .committed(let value): disk = value
    case .conflict: throw WebsiteConfigCommitCoordinatorError.stale
    case .unavailable: throw WebsiteConfigCommitCoordinatorError.unavailable
    }
    var updated = prepared; updated.disk = disk
    var state = page.state
    state.savedApplication = .init(id: id, ticket: updated)
    page.installCommitted(state)
    return updated
  }

  /// Admit a setter against this coordinator's latest committed document, not
  /// arbitrary caller-provided runtime or a stale disk snapshot. This prepares
  /// an edit only: callers must choose the appropriate live-effect or explicit
  /// new-attempt path. It is not permission to restart an immediate-only edit.
  func prepareEdit(key: String, value: WebsiteConfigValue, from source: Publication,
    testActive: Bool) throws -> Prepared {
    try preparePublicationEdit(key: key, value: value, from: source, testActive: testActive, restoringFunboxMemory: true)
  }
  private func preparePublicationEdit(key: String, value: WebsiteConfigValue, from source: Publication,
    testActive: Bool, restoringFunboxMemory: Bool, nosave: Bool = false) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true
    defer { processing = false }
    // A rejected newer edit must retire suspended older producers too.
    request = UUID()
    guard let owner = router.captureLease() else { throw WebsiteConfigCommitCoordinatorError.noOwner }
    guard source.authority === publicationAuthority, let base = latest,
      base.applicationID == source.applicationID, base.owner == owner.owner else {
      throw WebsiteConfigCommitCoordinatorError.stale
    }
    guard let context = environment() else { throw WebsiteConfigCommitCoordinatorError.noEnvironment }
    guard router.isCurrent(owner) else { throw WebsiteConfigCommitCoordinatorError.stale }
    guard let disk = try register.read().revision else { throw WebsiteConfigCommitCoordinatorError.unavailable }
    guard disk == base.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
    let draft: WebsiteConfigNativeDraft
    var funboxSelectionSaved: Bool?
    if key == "funbox", restoringFunboxMemory {
      guard !testActive || !base.draft.generators.requestedModifiers.contains(.noQuit) else { throw WebsiteConfigNativeDraftError.rejectedEdit }
      let selection = try WebsiteConfigFunboxMemory.selecting(value, from: base.draft,
        pointsPerRem: context.pointsPerRem, context: context.context, testActive: testActive)
      draft = selection.draft; funboxSelectionSaved = selection.saved
    } else {
      draft = try WebsiteConfigNativeProfile.editDraft(base.draft, key: key, value: value,
        pointsPerRem: context.pointsPerRem, context: context.context, testActive: testActive, nosave: nosave)
    }
    var prepared = Prepared(draft: draft, identity: identity, request: request, owner: owner,
      environment: context, disk: disk)
    prepared.funboxSelectionSaved = funboxSelectionSaved
    if funboxSelectionSaved == false { prepared.savedDraft = base.savedDraft }
    guard isCurrent(prepared), try register.read().revision == base.disk,
      router.isCurrent(owner) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return prepared
  }

  /// Capture the actual page instead of accepting the original seed's books.
  /// Input can continue during preparation; changed generation state rejects
  /// the candidate before further reads or CAS rather than discarding input.
  func prepareEdit(key: String, value: WebsiteConfigValue, for page: PracticePageSessionStore) throws -> Prepared {
    try preparePageEdit(key: key, value: value, for: page, refreshingWith: nil)
  }
  func prepareEdit(key: String, value: WebsiteConfigValue, for page: PracticePageSessionStore,
    refreshingWith source: WebsiteConfigPracticeScopeSource) throws -> Prepared {
    try preparePageEdit(key: key, value: value, for: page, refreshingWith: source)
  }
  func prepareFailedPoetrySource(for page: PracticePageSessionStore,
    refreshingWith source: WebsiteConfigPracticeScopeSource) throws -> Prepared {
    guard page.state.session.outcome == .failed,
      LivePracticeContentSource.selected(for: page.state.session.configuration) == .poetry,
      case .array(let funboxes)? = page.state.presentation?.publication.draft.projection.runtime["funbox"],
      funboxes.contains(.string("poetry")) else { throw WebsiteConfigCommitCoordinatorError.sessionNotReady }
    return try preparePageEdit(key: "funbox", value: .array(funboxes.filter { $0 != .string("poetry") }),
      for: page, refreshingWith: source, restoringFunboxMemory: false)
  }
  func prepareLayoutFluidStep(key: String, value: WebsiteConfigValue, nosave: Bool, for page: PracticePageSessionStore,
    refreshingWith source: WebsiteConfigPracticeScopeSource, navigation: WebsiteWordNavigationEvent? = nil) throws -> Prepared {
    if let navigation, !page.state.session.ownsWebsiteWordNavigation(navigation) { throw WebsiteConfigCommitCoordinatorError.stale }
    var prepared = try preparePageEdit(key: key, value: value, for: page, refreshingWith: source, nosave: nosave)
    if let navigation, !page.state.session.ownsWebsiteWordNavigation(navigation) { throw WebsiteConfigCommitCoordinatorError.stale }
    prepared.wordNavigation = navigation
    return prepared
  }
  private func preparePageEdit(key: String, value: WebsiteConfigValue, for page: PracticePageSessionStore,
    refreshingWith source: WebsiteConfigPracticeScopeSource?, restoringFunboxMemory: Bool = true, nosave: Bool = false) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    guard page.state.configurationDeparture == nil, page.state.sharedReceipt == nil else { throw WebsiteConfigCommitCoordinatorError.sessionNotReady }
    request = UUID()
    let capture = try page.captureGeneration(router: router)
    var prepared = try preparePublicationEdit(key: key, value: value, from: capture.publication,
      testActive: capture.testActive, restoringFunboxMemory: restoringFunboxMemory, nosave: nosave)
    // Session books are current, but inherited account/content scope is not a
    // fresh read from a new environment. Require scoped re-preparation first;
    // do not silently carry one account's content into another epoch.
    if let source {
      let content = try source.capture(owner: page.owner, preserving: capture.scope)
      guard content.environment == prepared.environment else { throw WebsiteConfigCommitCoordinatorError.stale }
      prepared.contentSource = source
      prepared.contentCapture = content
    } else {
      guard prepared.environment.revision == capture.publication.environmentRevision else {
        throw WebsiteConfigCommitCoordinatorError.stale
      }
    }
    prepared.sourcePage = page
    prepared.pageCapture = capture
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return prepared
  }
  @discardableResult
  func cancel(_ prepared: Prepared) -> Bool {
    guard !processing, belongsToCurrentRequest(prepared) else { return false }
    request = UUID()
    return true
  }
  func publication(for owner: UUID) -> Publication? { latest?.owner == owner ? latest : nil }
  func prepareBackground(for prepared: Prepared, local: WebsiteConfigBackgroundResource.Local,
    remote: WebsiteConfigBackgroundResource.Remote? = nil,
    limits: WebsiteConfigBackgroundResource.Limits = .init()) throws -> BackgroundPrepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true
    defer { processing = false }
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    resourceAdmission = UUID()
    let background = try WebsiteConfigBackgroundResource.prepare(
      preferences: prepared.draft.pagePreferences, local: local, remote: remote, limits: limits)
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return .init(configuration: prepared, admission: resourceAdmission, background: background)
  }
  func prepareResources(for prepared: Prepared, localFont: WebsiteConfigFontResource.Local,
    localBackground: WebsiteConfigBackgroundResource.Local, remoteBackground: WebsiteConfigBackgroundResource.Remote? = nil,
    maximumFontBytes: Int = 32 * 1024 * 1024,
    backgroundLimits: WebsiteConfigBackgroundResource.Limits = .init()) throws -> ResourcesPrepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true
    defer { processing = false }
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    resourceAdmission = UUID()
    let font = try WebsiteConfigFontResource.prepare(typography: prepared.draft.keyboardTypography,
      language: prepared.draft.testParameters.language, local: localFont, maximumBytes: maximumFontBytes)
    let background = try WebsiteConfigBackgroundResource.prepare(preferences: prepared.draft.pagePreferences,
      local: localBackground, remote: remoteBackground, limits: backgroundLimits)
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return .init(configuration: prepared, admission: resourceAdmission, background: background, font: font)
  }
  @discardableResult
  func cancel(_ prepared: ResourcesPrepared) -> Bool {
    guard prepared.admission == resourceAdmission else { return false }
    return cancel(prepared.configuration)
  }
  func prepareResources(for prepared: Prepared,
    readLocalFont: @MainActor () async throws -> WebsiteConfigFontResource.Local,
    readLocalBackground: @MainActor () async throws -> WebsiteConfigBackgroundResource.Local,
    fetchRemoteBackground: (@MainActor (WebsiteConfigValue, Int) async throws -> WebsiteConfigBackgroundResource.Remote)? = nil,
    maximumFontBytes: Int = 32 * 1024 * 1024,
    backgroundLimits: WebsiteConfigBackgroundResource.Limits = .init()) async throws -> ResourcesPrepared {
    let admission = try beginAsyncResources(prepared)
    guard maximumFontBytes > 0 else { throw WebsiteConfigFontResourceError.invalidLimit }
    guard backgroundLimits.encodedBytes > 0, backgroundLimits.pixels > 0,
      backgroundLimits.decodedBytes > 0, backgroundLimits.frames > 0
    else { throw WebsiteConfigBackgroundResourceError.invalidLimits }
    let localFont = try await readAsyncResource(prepared, admission: admission, operation: readLocalFont)
    let font = try WebsiteConfigFontResource.prepare(typography: prepared.draft.keyboardTypography,
      language: prepared.draft.testParameters.language, local: localFont, maximumBytes: maximumFontBytes)
    let localBackground = try await readAsyncResource(prepared, admission: admission, operation: readLocalBackground)
    var remote: WebsiteConfigBackgroundResource.Remote?
    if case .absent = localBackground,
      prepared.draft.pagePreferences.backgroundAddress.stringUnits?.isEmpty != true {
      guard let fetchRemoteBackground else { throw WebsiteConfigBackgroundResourceError.remoteNotProvided }
      remote = try await readAsyncResource(prepared, admission: admission) {
        try await fetchRemoteBackground(prepared.draft.pagePreferences.backgroundAddress, backgroundLimits.encodedBytes)
      }
    }
    let background = try WebsiteConfigBackgroundResource.prepare(preferences: prepared.draft.pagePreferences,
      local: localBackground, remote: remote, limits: backgroundLimits)
    try checkAsyncResources(prepared, admission: admission)
    return .init(configuration: prepared, admission: admission, background: background, font: font)
  }
  private func beginAsyncResources(_ prepared: Prepared) throws -> UUID {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true
    defer { processing = false }
    try Task.checkCancellation()
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    try Task.checkCancellation()
    resourceAdmission = UUID()
    return resourceAdmission
  }
  func prepareResources(for prepared: Prepared, from settings: AppSettings,
    fetchRemoteBackground: (@MainActor (WebsiteConfigValue, Int) async throws -> WebsiteConfigBackgroundResource.Remote)? = nil,
    remoteReader: WebsiteConfigBackgroundRemoteReader = .init(),
    maximumFontBytes: Int = 32 * 1024 * 1024,
    backgroundLimits: WebsiteConfigBackgroundResource.Limits = .init()) async throws -> ResourcesPrepared {
    try await prepareResources(for: prepared,
      readLocalFont: { try settings.readLocalPracticeFontResource(maximumBytes: maximumFontBytes) },
      readLocalBackground: {
        if let data = try settings.localBackgroundStore.encodedData(maximumBytes: backgroundLimits.encodedBytes) { return .data(data) }
        return .absent
      }, fetchRemoteBackground: fetchRemoteBackground ?? { try await remoteReader.read(address: $0, maximumBytes: $1) },
      maximumFontBytes: maximumFontBytes, backgroundLimits: backgroundLimits)
  }
  private func checkAsyncResources(_ prepared: Prepared, admission: UUID) throws {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true
    defer { processing = false }
    try Task.checkCancellation()
    guard admission == resourceAdmission, isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    try Task.checkCancellation()
  }
  private func readAsyncResource<Value>(_ prepared: Prepared, admission: UUID,
    operation: @MainActor () async throws -> Value) async throws -> Value {
    try checkAsyncResources(prepared, admission: admission)
    // Never keep processing or a file lock across a caller's suspension. Check
    // stale/cancellation before forwarding either a late value or a late error.
    let result: Result<Value, Error>
    do { result = .success(try await operation()) }
    catch { result = .failure(error) }
    try checkAsyncResources(prepared, admission: admission)
    return try result.get()
  }
  func commit(_ prepared: ResourcesPrepared) throws -> Outcome {
    guard !processing else { return .busy }
    guard prepared.admission == resourceAdmission else { return .stale }
    return try commit(prepared.configuration, background: prepared.background, font: prepared.font)
  }
  func prepareSession(for prepared: ResourcesPrepared,
    generate: @MainActor (WebsiteConfigNativeDraft) async throws -> TypingSession) async throws -> SessionPrepared {
    try await prepareSessionBuild(for: prepared) { draft in
      guard prepared.configuration.pageCapture == nil, prepared.configuration.applicationCapture == nil else {
        throw WebsiteConfigCommitCoordinatorError.sessionNotReady
      }
      return (try await generate(draft), nil)
    }
  }
  func preparePractice(for prepared: ResourcesPrepared, scope: WebsiteConfigSessionBuilder.Scope,
    initializationReport: WebsiteConfigInitializationReport? = nil,
    loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) },
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)? = nil,
    random: WebsiteConfigSessionBuilder.Random = .init()) async throws -> SessionPrepared {
    try await preparePracticeBuild(for: prepared, scope: scope, initializationReport: initializationReport,
      loadQuotes: loadQuotes, loadExternal: loadExternal, random: random)
  }
  func preparePractice(for prepared: ResourcesPrepared,
    initializationReport: WebsiteConfigInitializationReport? = nil,
    loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) },
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)? = nil,
    random: WebsiteConfigSessionBuilder.Random = .init()) async throws -> SessionPrepared {
    try await preparePracticeBuild(for: prepared, scope: nil, initializationReport: initializationReport,
      loadQuotes: loadQuotes, loadExternal: loadExternal, random: random)
  }
  func prepareNext(for page: PracticePageSessionStore,
    initializationReport: WebsiteConfigInitializationReport? = nil,
    loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) },
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)? = nil,
    random: WebsiteConfigSessionBuilder.Random = .init()) async throws -> NextPrepared {
    let resources = try nextResources(for: page)
    let session = try await preparePracticeBuild(for: resources, scope: nil,
      reason: .nextAttempt, initializationReport: initializationReport,
      loadQuotes: loadQuotes, loadExternal: loadExternal, random: random)
    return .init(session: session)
  }
  func prepareRestart(for page: PracticePageSessionStore, repeatingRequested: Bool = false,
    initializationReport: WebsiteConfigInitializationReport? = nil,
    loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) },
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)? = nil,
    random: WebsiteConfigSessionBuilder.Random = .init()) async throws -> NextPrepared {
    try await prepareRestart(restartPlan(for: page, repeatingRequested: repeatingRequested),
      initializationReport: initializationReport, loadQuotes: loadQuotes, loadExternal: loadExternal, random: random)
  }
  private func restartPlan(for page: PracticePageSessionStore, repeatingRequested: Bool) throws -> RestartAdmission {
    let resources = try nextResources(for: page)
    guard var previous = page.state.practice, let capture = resources.configuration.pageCapture,
      case .string(let language)? = resources.configuration.draft.projection.runtime["language"] else {
      throw PracticePageSessionStateError.incomplete
    }
    let original = page.state.session
    if original.configuration.mode == .quote, let progress = resources.configuration.quoteInitialization {
      previous = .init(session: previous.session, scope: capture.scope, quote: progress.quote,
        external: previous.external, repetition: previous.repetition)
    }
    let behavior = resources.configuration.draft.behavior
    let repetition = WebsiteConfigRestartPolicy.resolve(requested: repeatingRequested,
      active: capture.testActive, previouslyRepeated: previous.repetition.repeatsWordset,
      failed: original.outcome == .failed && page.state.restartDepartureAttemptID != original.automaticInputAttemptID,
      mode: original.configuration.mode, language: language,
      quoteLanguage: previous.quote.flatMap { WebsiteLanguageIdentity.name(for: $0.language) },
      repeatQuotes: behavior.repeatQuotes, repeatedPace: behavior.repeatedPace)
    return .init(resources: resources, original: original, previous: previous, repetition: repetition)
  }
  /// Accept the departure before asynchronous init, as the source restart does.
  /// Rejected admission changes nothing; init failure cannot undo a departure.
  func beginRestart(for page: PracticePageSessionStore, repeatingRequested: Bool = false,
    recoveringWith controller: WebsitePracticeRestartController? = nil) throws -> RestartAdmission {
    if let pending = page.state.configurationDeparture {
      // Only the still-bound controller may resume its automatic correction.
      // An unrelated setter phase remains owned by the configuration workflow.
      guard let controller, page.restartController === controller, controller.isPreparing,
        !pending.quoteRecoveries.isEmpty, let previous = page.state.practice,
        let base = latest, let background = base.background, let font = base.font else {
        throw WebsiteConfigCommitCoordinatorError.sessionNotReady
      }
      var prepared = try resumeConfigurationRestart(for: page)
      prepared.restartController = controller
      prepared.requiresRestartController = true
      resourceAdmission = UUID()
      let resources = ResourcesPrepared(configuration: prepared, admission: resourceAdmission,
        background: background, font: font)
      return .init(resources: resources, original: page.state.session, previous: previous, repetition: pending.repetition)
    }
    var admission = try restartPlan(for: page, repeatingRequested: repeatingRequested)
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true; defer { processing = false }
    var prepared = admission.resources.configuration
    guard let capture = prepared.pageCapture else { throw PracticePageSessionStateError.incomplete }
    var closed = admission.original
    let measurement = page.state.restartDepartureAttemptID == closed.automaticInputAttemptID ? nil : closed.abandonAndMeasure()
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    try Task.checkCancellation()
    try page.beginCommit(owner: prepared.owner, router: router, capture: capture)
    do {
      guard try register.read().revision == prepared.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
      var departed = page.state
      departed.session = closed
      departed.restartDepartureAttemptID = closed.automaticInputAttemptID
      if let measurement {
        departed.priorAttemptLedger.recordRestart(engagedDuration: measurement.engagedDuration,
          accuracy: measurement.accuracy, savingEnabled: prepared.draft.behavior.saveCompletedResults)
      }
      page.installCommitted(departed)
    } catch { page.endCommit(); throw error }
    page.endCommit()
    prepared.retainsQuoteInitialization = true
    prepared.pageCapture = try page.captureGeneration(router: router)
    admission.resources = .init(configuration: prepared, admission: admission.resources.admission,
      background: admission.resources.background, font: admission.resources.font)
    return admission
  }
  @discardableResult
  func cancel(_ admission: RestartAdmission) -> Bool { cancel(admission.resources.configuration) }
  func prepareRestart(_ admission: RestartAdmission,
    initializationReport: WebsiteConfigInitializationReport? = nil,
    loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) },
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)? = nil,
    random: WebsiteConfigSessionBuilder.Random = .init()) async throws -> NextPrepared {
    let resources = admission.resources, original = admission.original, previous = admission.previous
    let repetition = admission.repetition
    guard let capture = resources.configuration.pageCapture else { throw PracticePageSessionStateError.incomplete }
    if !repetition.repeatsWordset {
      let session = try await preparePracticeBuild(for: resources, scope: nil,
        reason: .nextAttempt, initializationReport: initializationReport,
        loadQuotes: loadQuotes, loadExternal: loadExternal, random: random)
      return .init(session: session)
    }
    if original.configuration.mode == .quote, resources.configuration.quoteInitialization != nil {
      let session = try await preparePracticeBuild(for: resources, scope: nil, reason: .nextAttempt,
        repeatedSource: .repeatedQuote(previous.quote, repeatedPace: repetition.repeatsPace),
        initializationReport: initializationReport, loadQuotes: loadQuotes, loadExternal: loadExternal, random: random)
      return .init(session: session)
    }
    if [.words, .time].contains(original.configuration.mode), let history = original.generatedWordReplayHistory {
      let session = try await preparePracticeBuild(for: resources, scope: nil, reason: .nextAttempt,
        repeatedSource: .repeatedWords(history, repeatedPace: repetition.repeatsPace),
        initializationReport: initializationReport, loadQuotes: loadQuotes, loadExternal: loadExternal, random: random)
      return .init(session: session)
    }
    let session = try await prepareSessionBuild(for: resources) { draft in
      // Restore the actual attempt's owned opening/cursors/caches, not a
      // reconstruction from the editor, its grown prompt or a fresh sampler.
      var repeated = original.repeatedAttempt(nextRandomCaseBit: random.caseBit)
      repeated.synchronizeWebsiteInputRules(draft.inputRules.rules)
      guard !repeated.hasStarted, !repeated.isFinished,
        repeated.configuration.mode == .zen || !repeated.prompt.isEmpty else {
        throw WebsiteConfigSessionBuildError.generationFailed
      }
      let practice = WebsiteConfigSessionBuilder.Prepared(session: repeated, scope: capture.scope,
        quote: previous.quote, external: previous.external, repetition: repetition)
      return (repeated, practice)
    }
    return .init(session: session)
  }
  @discardableResult
  func cancel(_ next: NextPrepared) -> Bool { cancel(next.session) }
  private func nextResources(for page: PracticePageSessionStore) throws -> ResourcesPrepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    guard page.state.configurationDeparture == nil, page.state.sharedReceipt == nil else { throw WebsiteConfigCommitCoordinatorError.sessionNotReady }
    processing = true; defer { processing = false }
    request = UUID()
    let capture = try page.captureGeneration(router: router)
    guard let owner = router.captureLease(), owner.owner == page.owner,
      let base = latest, base.applicationID == capture.publication.applicationID,
      capture.publication.authority === publicationAuthority else { throw WebsiteConfigCommitCoordinatorError.stale }
    guard let context = environment(), context.revision == base.environmentRevision,
      context.pointsPerRem == base.pointsPerRem else { throw WebsiteConfigCommitCoordinatorError.stale }
    guard !capture.testActive || !page.state.session.configuration.modifiers.contains(.noQuit) else {
      throw PracticePageSessionStateError.locked
    }
    guard let background = base.background, let font = base.font else { throw PracticePageSessionStateError.incomplete }
    guard let disk = try register.read().revision else { throw WebsiteConfigCommitCoordinatorError.unavailable }
    guard disk == base.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
    var prepared = Prepared(draft: base.draft, identity: identity, request: request,
      owner: owner, environment: context, disk: disk)
    prepared.sourcePage = page; prepared.pageCapture = capture
    prepared.quoteInitialization = page.state.currentQuoteInitialization
    if page.restartController?.isPreparing == true {
      prepared.restartController = page.restartController; prepared.requiresRestartController = true
    }
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    // Already-admitted immutable resources belong to this exact environment.
    // No preference setter, re-import, file-resource read or remote fetch.
    resourceAdmission = UUID()
    return .init(configuration: prepared, admission: resourceAdmission, background: background, font: font)
  }
  func advance(_ next: NextPrepared, to page: PracticePageSessionStore) throws -> NextOutcome {
    if next.session.resources.configuration.pageCapture?.configurationDeparture != nil {
      let old = page.state.session
      // The source setter checkpoint already closed and accounted the old
      // attempt. Publish the corrected full configuration without recounting.
      switch try commit(next.session, to: page, systemIsDark: page.state.presentation?.currentSystemIsDark ?? false) {
      case .committed: return .advanced(.init(session: old, incomplete: nil))
      case .busy: return .busy
      case .conflict: return .conflict
      case .unavailable: return .unavailable
      case .stale: return .stale
      }
    }
    guard !processing else { return .busy }
    processing = true; defer { processing = false }
    try Task.checkCancellation()
    let value = next.session, prepared = value.resources.configuration
    guard value.admission == sessionAdmission, value.resources.admission == resourceAdmission,
      isCurrent(prepared) else { retire(prepared); return .stale }
    guard let source = prepared.sourcePage, page === source, let capture = prepared.pageCapture else {
      throw PracticePageSessionStateError.wrongOwner
    }
    guard let practice = value.practice else { throw PracticePageSessionStateError.incomplete }
    let old = page.state.session
    let incomplete: PreviousAttempt.Incomplete? = old.hasStarted && !old.isFinished
      ? .init(engagedDuration: old.activeEngagedDuration(), accuracy: old.preciseAccuracy) : nil
    // An injected old clock is a callback too. Sample it before final page /
    // environment / record validation, never after the last checked read.
    guard isCurrent(prepared) else { retire(prepared); return .stale }
    try Task.checkCancellation()
    try page.beginCommit(owner: prepared.owner, router: router, capture: capture)
    defer { page.endCommit() }
    // Last fallible operation, after all host callbacks and page reservation.
    // A read verifies the record without generating a new durable revision.
    let current: WebsiteConfigFileRegister.Snapshot
    do { current = try register.read() }
    catch WebsiteConfigFileRegisterError.busy { return .busy }
    guard let revision = current.revision else { retire(prepared); return .unavailable }
    guard revision == prepared.disk else { retire(prepared); return .conflict }
    // Keep the live appearance/resource/configuration publication. A new
    // attempt is not a new full application or a chance to replay its events.
    page.installCommitted(.init(session: value.session.withElapsedClock(),
      presentation: page.state.presentation, practice: practice, priorAttemptLedger: page.state.priorAttemptLedger))
    retire(prepared)
    return .advanced(.init(session: old, incomplete: incomplete))
  }
  private func preparePracticeBuild(for resources: ResourcesPrepared, scope: WebsiteConfigSessionBuilder.Scope?,
    reason: WebsiteConfigSessionBuilder.Reason = .configurationApplication,
    repeatedSource: WebsiteConfigSessionBuilder.AttemptSource = .selection,
    initializationReport: WebsiteConfigInitializationReport? = nil,
    loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote],
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)?,
    random: WebsiteConfigSessionBuilder.Random) async throws -> SessionPrepared {
    var configuration = resources.configuration
    if configuration.funboxSelectionSaved == false {
      try withInitializationReport(initializationReport, resources: resources) { report, current in
        report.recordFunboxSelectionRejection(whileCurrent: current)
      }
    }
    let beforeRemember = configuration.draft
    configuration.draft = WebsiteConfigFunboxMemory.remembering(beforeRemember)
    configuration = try saveGenerationCorrection(configuration, from: beforeRemember, admission: resources.admission)
    var current = ResourcesPrepared(configuration: configuration, admission: resources.admission,
      background: resources.background, font: resources.font)
    // Pinned init enters generation at most three times per restart. Keep the
    // actual source recovery on the last failure too, then stop explicitly.
    for attempt in 0..<3 {
      if attempt > 0 {
        try checkAsyncResources(current.configuration, admission: current.admission)
        guard try register.read().revision == current.configuration.disk else {
          throw WebsiteConfigCommitCoordinatorError.stale
        }
      }
      do {
        let effectiveReason: WebsiteConfigSessionBuilder.Reason = current.configuration.departureID != nil
          ? .configurationApplication : reason
        return try await preparePracticeAttempt(for: current, scope: scope, reason: effectiveReason,
          replayApplicationEvents: attempt == 0, repeatedSource: repeatedSource,
          initializationReport: initializationReport,
          loadQuotes: loadQuotes, loadExternal: loadExternal, random: random)
      } catch let recovery as QuoteRecoveryRequest {
        try Task.checkCancellation()
        try checkAsyncResources(recovery.resources.configuration, admission: recovery.resources.admission)
        current = try prepareQuoteRecovery(recovery.recovery, for: recovery.resources)
        try reportInitializationFailure(WebsiteConfigInitializationReport.quote(attempt: attempt + 1,
          reason: recovery.reason, selectedQuoteID: recovery.selectedQuoteID),
          resources: current, report: initializationReport, exhausted: attempt == 2)
        if attempt == 2 { throw WebsiteConfigSessionBuildError.quoteRecoveryLimitReached }
        await Task.yield()
      } catch let recovery as PolyglotDirectionRecoveryRequest {
        try Task.checkCancellation()
        try checkAsyncResources(recovery.resources.configuration, admission: recovery.resources.admission)
        current = try preparePolyglotDirectionRecovery(recovery.language, for: recovery.resources)
        try withInitializationReport(initializationReport, resources: current) { report, valid in
          report.recordPolyglotDirectionCorrection(recovery.language, whileCurrent: valid)
        }
        let silent = WebsiteWordGenerationError(message: "")
        try reportInitializationFailure(WebsiteConfigInitializationReport.generation(attempt: attempt + 1, error: silent, quote: nil),
          resources: current, report: initializationReport, exhausted: attempt == 2)
        if attempt == 2 { throw silent }
        await Task.yield()
      } catch let failure as GenerationFailure {
        try Task.checkCancellation()
        try checkAsyncResources(failure.resources.configuration, admission: failure.resources.admission)
        // Keep the already-applied runtime/listener checkpoint. Reconstructing
        // from the original import would replay events or resurrect old state.
        var configuration = failure.resources.configuration
        if let progress = failure.quoteInitialization {
          configuration = try retainQuoteInitialization(progress, for: configuration, admission: failure.resources.admission)
        }
        current = .init(configuration: configuration, admission: failure.resources.admission,
          background: failure.resources.background, font: failure.resources.font)
        if failure.underlying as? WebsiteConfigExternalContentError == .poetryUnavailable {
          current = try preparePoetryRecovery(for: current)
        }
        try Task.checkCancellation()
        try reportInitializationFailure(WebsiteConfigInitializationReport.generation(attempt: attempt + 1, error: failure.underlying,
          quote: failure.quoteInitialization ?? current.configuration.quoteInitialization),
          resources: current, report: initializationReport, exhausted: attempt == 2)
        if attempt == 2 { throw failure.underlying }
        await Task.yield()
      }
    }
    throw WebsiteConfigSessionBuildError.quoteRecoveryLimitReached
  }
  @MainActor private struct QuoteRecoveryRequest: Error {
    let recovery: WebsiteQuoteSampler.Recovery
    let reason: WebsiteQuoteSampler.Reason
    let selectedQuoteID: String?
    let resources: ResourcesPrepared
  }
  @MainActor private struct PolyglotDirectionRecoveryRequest: Error {
    let language: String
    let resources: ResourcesPrepared
  }
  private func reportInitializationFailure(_ failure: @autoclosure () -> WebsiteConfigInitializationReport.Failure,
    resources: ResourcesPrepared, report: WebsiteConfigInitializationReport?, exhausted: Bool) throws {
    try withInitializationReport(report, resources: resources) { report, current in
      report.record(failure(), whileCurrent: current)
    }
    if exhausted { report?.finish() }
  }
  private func withInitializationReport(_ report: WebsiteConfigInitializationReport?, resources: ResourcesPrepared,
    deliver: (WebsiteConfigInitializationReport, () -> Bool) -> Void) throws {
    guard let report else { return }
    let prepared = resources.configuration
    try checkAsyncResources(prepared, admission: resources.admission)
    guard try register.read().revision == prepared.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
    deliver(report) {
      guard !self.processing, !Task.isCancelled, resources.admission == self.resourceAdmission,
        self.isCurrent(prepared), let revision = try? self.register.read().revision else { return false }
      return revision == prepared.disk && self.isCurrent(prepared)
    }
    // Posting can synchronously retire a request or switch account/server.
    try checkAsyncResources(prepared, admission: resources.admission)
    guard try register.read().revision == prepared.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
  }
  @MainActor private struct GenerationFailure: Error {
    let underlying: Error
    let resources: ResourcesPrepared
    let quoteInitialization: WebsiteConfigSessionBuilder.QuoteInitialization?
  }
  private func retainQuoteInitialization(_ progress: WebsiteConfigSessionBuilder.QuoteInitialization,
    for prepared: Prepared, admission: UUID) throws -> Prepared {
    var updated = prepared
    updated.quoteInitialization = progress
    if prepared.savedApplicationID != nil { return try checkpointApplication(updated, admission: admission) }
    if prepared.applicationCapture?.configurationDeparture != nil {
      return try checkpointNativeSharedDeparture(updated, admission: admission)
    }
    guard prepared.retainsQuoteInitialization,
      let page = prepared.sourcePage, let capture = prepared.pageCapture,
      capture.configurationDeparture != nil
        || page.state.restartDepartureAttemptID == page.state.session.automaticInputAttemptID else { return updated }
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true; defer { processing = false }
    try Task.checkCancellation()
    guard admission == resourceAdmission, isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    try page.beginCommit(owner: prepared.owner, router: router, capture: capture)
    do {
      guard try register.read().revision == prepared.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
      var state = page.state
      state.quoteInitialization = .init(publication: capture.publication.applicationID,
        configurationDeparture: state.configurationDeparture?.id, progress: progress)
      page.installCommitted(state, retainingRestartController: prepared.restartController)
    } catch { page.endCommit(); throw error }
    page.endCommit()
    updated.pageCapture = try page.captureGeneration(router: router)
    guard isCurrent(updated) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return updated
  }
  private func canRetryGeneration(_ error: Error) -> Bool {
    // These are native admission/representation failures, not a failed source
    // generation. In particular a retired reader must not be called again.
    if error is CancellationError || error is WebsiteConfigCommitCoordinatorError
      || error is PracticePageSessionStateError || error is WebsiteConfigFileRegisterError
      || error is WebsiteConfigNativeGeneratorsError || error is WebsiteConfigNativeQuoteSelectionError { return false }
    if let failure = error as? WebsiteConfigSessionBuildError {
      switch failure {
      case .generationFailed, .customTextUnavailable, .invalidExternalSource: return true
      case .quoteRecoveryRequired, .quoteRecoveryLimitReached, .reconfigurationRequired, .polyglotDirectionConflict,
        .unrepresentableConfiguration, .externalNotProvided, .repeatedConfigurationUnsupported: return false
      }
    }
    if case WholePreviewWordPreparation.PreparationError.unsupportedConfiguration = error { return false }
    return true
  }
  private func prepareQuoteRecovery(_ recovery: WebsiteQuoteSampler.Recovery,
    for resources: ResourcesPrepared) throws -> ResourcesPrepared {
    let original = resources.configuration.draft
    let changes = recovery.websiteChanges
    // Both audited recoveries are single source setters. Do not accept an
    // arbitrary patch from a reader or silently replace language/content.
    guard changes.count == 1, let (key, value) = changes.first else {
      throw WebsiteConfigCommitCoordinatorError.sessionNotReady
    }
    let edited = try WebsiteConfigNativeProfile.editDraft(original, key: key, value: value,
      pointsPerRem: resources.configuration.environment.pointsPerRem,
      context: resources.configuration.environment.context, testActive: false)
    var projection = edited.projection
    projection.events = original.projection.events + projection.events
    projection.rejectedKeys = original.projection.rejectedKeys + projection.rejectedKeys
    let draft = try original.replacingProjection(projection, memory: edited.lazyMemory,
      pointsPerRem: resources.configuration.environment.pointsPerRem)
    var configuration = resources.configuration
    configuration.draft = draft
    configuration.quoteRecoveries.append(recovery)
    if configuration.savedDraft != nil || configuration.pageCapture != nil { configuration.savedDraft = draft }
    configuration = try saveGenerationCorrection(configuration, from: original, admission: resources.admission)
    return .init(configuration: configuration, admission: resources.admission,
      background: resources.background, font: resources.font)
  }
  private func preparePolyglotDirectionRecovery(_ language: String, for resources: ResourcesPrepared) throws -> ResourcesPrepared {
    let original = resources.configuration.draft
    guard original.generators.requestsPolyglot,
      let fallback = PolyglotGenerationPreparation.directionFallback(primary: original.testParameters.language,
        selected: original.generators.polyglotLanguages), WebsiteLanguageIdentity.name(for: fallback) == language else {
      throw WebsiteConfigCommitCoordinatorError.sessionNotReady
    }
    let edited = try WebsiteConfigNativeProfile.editDraft(original, key: "language", value: .string(language),
      pointsPerRem: resources.configuration.environment.pointsPerRem, context: resources.configuration.environment.context)
    let applied = try WebsiteConfigLazyModeLifecycle.applyingEvents(edited, pointsPerRem: resources.configuration.environment.pointsPerRem)
    var projection = applied.projection
    projection.events = original.projection.events + projection.events
    projection.rejectedKeys = original.projection.rejectedKeys + projection.rejectedKeys
    var configuration = resources.configuration
    configuration.draft = try original.replacingProjection(projection, memory: applied.lazyMemory,
      pointsPerRem: resources.configuration.environment.pointsPerRem)
    var saved = edited; saved.lazyMemory = applied.lazyMemory
    configuration.savedDraft = saved
    configuration = try saveGenerationCorrection(configuration, from: original, admission: resources.admission, admittingSourceSetter: true)
    return .init(configuration: configuration, admission: resources.admission, background: resources.background, font: resources.font)
  }
  private func preparePoetryRecovery(for resources: ResourcesPrepared) throws -> ResourcesPrepared {
    let original = resources.configuration.draft
    guard original.generators.requestedModifiers.contains(.poetryStream),
      case .array(let funboxes)? = original.projection.runtime["funbox"] else {
      throw WebsiteConfigCommitCoordinatorError.sessionNotReady
    }
    // A failed pull toggles the source through the ordinary saving setter.
    // It does not restore the UI selection's remembered settings.
    let edited = try WebsiteConfigNativeProfile.editDraft(original, key: "funbox",
      value: .array(funboxes.filter { $0 != .string("poetry") }),
      pointsPerRem: resources.configuration.environment.pointsPerRem,
      context: resources.configuration.environment.context)
    let applied = try WebsiteConfigLazyModeLifecycle.applyingEvents(edited,
      pointsPerRem: resources.configuration.environment.pointsPerRem)
    var projection = applied.projection
    projection.events = original.projection.events + projection.events
    projection.rejectedKeys = original.projection.rejectedKeys + projection.rejectedKeys
    var configuration = resources.configuration
    configuration.draft = try original.replacingProjection(projection, memory: applied.lazyMemory,
      pointsPerRem: resources.configuration.environment.pointsPerRem)
    var saved = edited; saved.lazyMemory = applied.lazyMemory
    configuration.savedDraft = saved
    configuration = try saveGenerationCorrection(configuration, from: original,
      admission: resources.admission, admittingSourceSetter: true)
    return .init(configuration: configuration, admission: resources.admission,
      background: resources.background, font: resources.font)
  }
  private func preparePracticeAttempt(for resources: ResourcesPrepared, scope: WebsiteConfigSessionBuilder.Scope?,
    reason: WebsiteConfigSessionBuilder.Reason,
    replayApplicationEvents: Bool,
    repeatedSource: WebsiteConfigSessionBuilder.AttemptSource,
    initializationReport: WebsiteConfigInitializationReport?,
    loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote],
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)?,
    random: WebsiteConfigSessionBuilder.Random) async throws -> SessionPrepared {
    try checkAsyncResources(resources.configuration, admission: resources.admission)
    var resources = resources
    let beforeActivation = resources.configuration.draft
    var joiningScriptClear = false
    let activated = try WebsiteConfigFunboxActivation.prepare(beforeActivation,
      pointsPerRem: resources.configuration.environment.pointsPerRem,
      context: resources.configuration.environment.context, onJoiningScriptClear: { joiningScriptClear = true })
    var activation = resources.configuration
    activation.draft = activated
    // A complete application's saved configuration precedes nosave activation.
    // Only a later actual saving setter may promote the runtime overrides.
    if activation.savedDraft == nil { activation.savedDraft = beforeActivation }
    activation = try saveGenerationCorrection(activation, from: beforeActivation, admission: resources.admission)
    resources = .init(configuration: activation, admission: resources.admission,
      background: resources.background, font: resources.font)
    if joiningScriptClear {
      try withInitializationReport(initializationReport, resources: resources) { report, current in
        report.recordFunboxJoiningScriptClear(whileCurrent: current)
      }
    }
    // Pinned init repairs unauthenticated favorites before lazy normalization
    // and generation. This is a setter, not a failed sampling attempt: retain
    // its save checkpoint without spending retry budget or posting a notice.
    if resources.configuration.draft.testParameters.mode == .quote,
      resources.configuration.draft.quoteSelection.groups.contains(-3),
      !resources.configuration.environment.context.authenticated {
      resources = try prepareQuoteRecovery(.allLengths, for: resources)
    }
    let original = resources.configuration.draft
    var lazyTransition: WebsiteConfigLazyModeLifecycle.NoticeTransition?
    let draft = try WebsiteConfigLazyModeLifecycle.prepare(original,
      pointsPerRem: resources.configuration.environment.pointsPerRem,
      replayApplicationEvents: replayApplicationEvents && reason == .configurationApplication
        && resources.configuration.departureID == nil
        && !resources.configuration.applicationEventsApplied,
      onNoticeTransition: { lazyTransition = $0 })
    if reason == .nextAttempt, draft.lazyMemory != original.lazyMemory || draft.generators.lazyMode != original.generators.lazyMode {
      throw WebsiteConfigSessionBuildError.reconfigurationRequired(["lazyMode": .bool(draft.generators.lazyMode)])
    }
    var configuration = resources.configuration; configuration.draft = draft
    if configuration.savedApplicationID != nil { configuration.applicationEventsApplied = true }
    if var saved = configuration.savedDraft {
      if WebsiteConfigLazyModeLifecycle.savesConfigurationDuringGeneration(from: original, to: draft) {
        saved = draft
      }
      // Independent listener memory is durable even if no Config save occurs.
      saved.lazyMemory = draft.lazyMemory
      configuration.savedDraft = saved
    }
    configuration = try saveGenerationCorrection(configuration, from: original, admission: resources.admission)
    let prepared = ResourcesPrepared(configuration: configuration, admission: resources.admission,
      background: resources.background, font: resources.font)
    if let lazyTransition {
      try withInitializationReport(initializationReport, resources: prepared) { report, current in
        report.recordLazyMode(lazyTransition, whileCurrent: current)
      }
    }
    let checkedExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)?
    let selectedLoader: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)?
    if let loadExternal { selectedLoader = loadExternal }
    else if let externalLoader {
      selectedLoader = { source, configuration in
        try await externalLoader(source, configuration, draft.presentation.showAllPracticeLines) {
          try self.checkAsyncResources(prepared.configuration, admission: prepared.admission)
          guard try self.register.read().revision == prepared.configuration.disk else {
            throw WebsiteConfigCommitCoordinatorError.stale
          }
          try self.checkAsyncResources(prepared.configuration, admission: prepared.admission)
        }
      }
    } else { selectedLoader = nil }
    if let selectedLoader {
      checkedExternal = { source, configuration in
        try await self.readAsyncResource(prepared.configuration, admission: prepared.admission) {
          try await selectedLoader(source, configuration)
        }
      }
    } else { checkedExternal = nil }
    return try await prepareSessionBuild(for: prepared) { draft in
      var effectiveScope: WebsiteConfigSessionBuilder.Scope
      if prepared.configuration.applicationCapture != nil {
        guard scope == nil, let content = prepared.configuration.contentCapture else {
          throw WebsiteConfigCommitCoordinatorError.sessionNotReady
        }
        // The bound source owns content; captured books remain from the actual
        // page. Never substitute a caller-supplied scope for either one.
        effectiveScope = content.scope
      } else if let capture = prepared.configuration.pageCapture {
        guard scope == nil else { throw WebsiteConfigCommitCoordinatorError.sessionNotReady }
        effectiveScope = prepared.configuration.contentCapture?.scope ?? capture.scope
      } else {
        guard let scope else { throw WebsiteConfigCommitCoordinatorError.sessionNotReady }
        effectiveScope = scope
      }
      if let progress = prepared.configuration.quoteInitialization { effectiveScope.quoteSampler = progress.sampler }
      let quoteLengthEvents = draft.projection.events.filter { $0.key == "quoteLength" }.count
      let applyQuoteLengthEvents = reason == .configurationApplication && quoteLengthEvents > 0
        && prepared.configuration.quoteInitialization?.appliedQuoteLengthEvents != quoteLengthEvents
      var quoteInitialization: WebsiteConfigSessionBuilder.QuoteInitialization?
      let attemptSource: WebsiteConfigSessionBuilder.AttemptSource
      if let pending = prepared.configuration.sourcePage?.state.configurationDeparture,
        prepared.configuration.departureID == pending.id,
        pending.repetition.repeatsWordset {
        if draft.testParameters.mode == .quote, let quote = pending.quote {
          attemptSource = .repeatedQuote(quote, repeatedPace: pending.repetition.repeatsPace)
        } else if let history = pending.wordHistory {
          attemptSource = .repeatedWords(history, repeatedPace: pending.repetition.repeatsPace)
        } else { throw WebsiteConfigSessionBuildError.repeatedConfigurationUnsupported }
      } else { attemptSource = repeatedSource }
      do {
        let practice = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: effectiveScope,
          reason: reason, attemptSource: attemptSource,
          applyQuoteLengthEvents: applyQuoteLengthEvents,
          onQuoteInitialization: { sampler, quote in
            quoteInitialization = .init(sampler: sampler, quote: quote, appliedQuoteLengthEvents: quoteLengthEvents)
          },
          loadQuotes: { language in
            try await self.readAsyncResource(prepared.configuration, admission: prepared.admission) {
              try await loadQuotes(language)
            }
          }, loadExternal: checkedExternal, random: random)
        return (practice.session, practice)
      } catch WebsiteConfigSessionBuildError.quoteRecoveryRequired(let recovery, let reason) {
        throw QuoteRecoveryRequest(recovery: recovery, reason: reason, selectedQuoteID: effectiveScope.selectedQuoteID,
          resources: prepared)
      } catch WebsiteConfigSessionBuildError.polyglotDirectionConflict(let language) {
        throw PolyglotDirectionRecoveryRequest(language: language, resources: prepared)
      } catch {
        guard self.canRetryGeneration(error) else { throw error }
        throw GenerationFailure(underlying: error, resources: prepared, quoteInitialization: quoteInitialization)
      }
    }
  }
  /// Source init can save configuration before the text provider returns.
  /// Advance the pending capability too, so retry starts after this durable
  /// transition rather than repeating the listener or resurrecting its input.
  private func saveGenerationCorrection(_ prepared: Prepared, from original: WebsiteConfigNativeDraft,
    admission: UUID, admittingSourceSetter: Bool = false) throws -> Prepared {
    if prepared.savedApplicationID != nil { return try checkpointApplication(prepared, admission: admission) }
    if prepared.applicationCapture?.configurationDeparture != nil,
      original.projection.runtime != prepared.draft.projection.runtime || original.lazyMemory != prepared.draft.lazyMemory
        || original.funboxMemory != prepared.draft.funboxMemory
        || prepared.draft.projection.events.count > original.projection.events.count
        || WebsiteConfigLazyModeLifecycle.savesConfigurationDuringGeneration(from: original, to: prepared.draft) {
      return try checkpointNativeSharedDeparture(prepared, admission: admission)
    }
    guard prepared.pageCapture != nil,
      prepared.pageCapture?.configurationDeparture != nil || !prepared.quoteRecoveries.isEmpty || admittingSourceSetter,
      original.projection.runtime != prepared.draft.projection.runtime
        || original.lazyMemory != prepared.draft.lazyMemory
        || original.funboxMemory != prepared.draft.funboxMemory
        || prepared.draft.projection.events.count > original.projection.events.count
        || WebsiteConfigLazyModeLifecycle.savesConfigurationDuringGeneration(from: original, to: prepared.draft)
    else { return prepared }
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true; defer { processing = false }
    try Task.checkCancellation()
    guard admission == resourceAdmission, isCurrent(prepared),
      let page = prepared.sourcePage, let capture = prepared.pageCapture,
      let saved = prepared.savedDraft else { throw WebsiteConfigCommitCoordinatorError.stale }
    let pending = page.state.configurationDeparture
    if let pending {
      guard pending.id == capture.configurationDeparture, pending.identity == identity,
        pending.disk == prepared.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
    } else if capture.configurationDeparture != nil || (prepared.quoteRecoveries.isEmpty && !admittingSourceSetter) {
      throw WebsiteConfigCommitCoordinatorError.stale
    }
    var state = page.state
    let inheritedQuoteInitialization = state.currentQuoteInitialization
    let measurement = pending == nil && state.restartDepartureAttemptID != state.session.automaticInputAttemptID
      ? state.session.abandonAndMeasure() : nil
    // The old elapsed clock can call back into the host. Recheck environment,
    // request and controller after sampling, before reserving the final CAS.
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    try Task.checkCancellation()
    try page.beginCommit(owner: prepared.owner, router: router, capture: capture)
    let disk: WebsiteConfigFileRegister.Revision
    do {
      switch try register.commit(saved, replacing: prepared.disk, preservingUnchanged: true) {
      case .committed(let revision): disk = revision
      case .conflict: retire(prepared); throw WebsiteConfigCommitCoordinatorError.stale
      case .unavailable: retire(prepared); throw WebsiteConfigCommitCoordinatorError.unavailable
      }
    } catch { page.endCommit(); throw error }
    // No throwing observer or cancellation check between durable CAS and the
    // matching pending state. Previously accepted departures are not recounted.
    let recoveryEnvironment = pending?.environment ?? prepared.environment
    let recoverySource = pending?.contentSource
    let requiresContentSource = pending?.requiresContentSource ?? false
    let repetition: WebsitePracticeRepetition = pending?.repetition ?? WebsitePracticeRepetition.none
    let quote = pending?.quote ?? state.practice?.quote
    let history = pending?.wordHistory ?? state.session.generatedWordReplayHistory
    state.configurationDeparture = ConfigurationDeparture(id: UUID(), draft: prepared.draft, savedDraft: saved,
      quoteRecoveries: prepared.quoteRecoveries, disk: disk,
      identity: identity, environment: recoveryEnvironment, contentSource: recoverySource,
      requiresContentSource: requiresContentSource, repetition: repetition, quote: quote, wordHistory: history,
      sharedReceipt: pending?.sharedReceipt)
    if let progress = inheritedQuoteInitialization {
      state.quoteInitialization = .init(publication: capture.publication.applicationID,
        configurationDeparture: state.configurationDeparture?.id, progress: progress)
    } else { state.quoteInitialization = nil }
    if pending == nil {
      state.restartDepartureAttemptID = state.session.automaticInputAttemptID
      if let measurement {
        state.priorAttemptLedger.recordRestart(engagedDuration: measurement.engagedDuration,
          accuracy: measurement.accuracy, savingEnabled: prepared.draft.behavior.saveCompletedResults)
      }
    }
    page.installCommitted(state, retainingRestartController: prepared.restartController)
    page.endCommit()
    var updated = prepared
    updated.disk = disk; updated.pageCapture = try page.captureGeneration(router: router)
    updated.retainsQuoteInitialization = true
    guard isCurrent(updated) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return updated
  }
  private func prepareSessionBuild(for prepared: ResourcesPrepared,
    generate: @MainActor (WebsiteConfigNativeDraft) async throws -> (TypingSession, WebsiteConfigSessionBuilder.Prepared?))
    async throws -> SessionPrepared {
    try checkAsyncResources(prepared.configuration, admission: prepared.admission)
    // A failed new producer must also retire an earlier seed. Once this
    // request opts in, resource-only commits cannot race ahead of generation.
    let admission = UUID()
    sessionAdmission = admission
    sessionRequest = prepared.configuration.request
    let result: Result<(TypingSession, WebsiteConfigSessionBuilder.Prepared?), Error>
    do { result = .success(try await generate(prepared.configuration.draft)) }
    catch { result = .failure(error) }
    try checkAsyncResources(prepared.configuration, admission: prepared.admission)
    guard sessionAdmission == admission else { throw WebsiteConfigCommitCoordinatorError.stale }
    let (session, practice) = try result.get()
    guard !session.hasStarted, !session.isFinished else { throw WebsiteConfigCommitCoordinatorError.sessionNotReady }
    return .init(resources: prepared, admission: admission, session: session, practice: practice)
  }
  @discardableResult
  func cancel(_ prepared: SessionPrepared) -> Bool {
    guard prepared.admission == sessionAdmission else { return false }
    return cancel(prepared.resources)
  }
  func commit(_ prepared: SessionPrepared) throws -> Outcome {
    guard !processing else { return .busy }
    try Task.checkCancellation()
    guard prepared.admission == sessionAdmission,
      prepared.resources.admission == resourceAdmission else { return .stale }
    return try commit(prepared.resources.configuration, background: prepared.resources.background,
      font: prepared.resources.font, session: prepared.session, practice: prepared.practice)
  }
  func commit(_ prepared: SessionPrepared, to page: PracticePageSessionStore,
    systemIsDark: Bool) throws -> Outcome {
    guard !processing else { return .busy }
    try Task.checkCancellation()
    guard prepared.admission == sessionAdmission,
      prepared.resources.admission == resourceAdmission else { return .stale }
    guard prepared.practice != nil else { throw PracticePageSessionStateError.incomplete }
    return try commit(prepared.resources.configuration, background: prepared.resources.background,
      font: prepared.resources.font, session: prepared.session, practice: prepared.practice,
      page: page, systemIsDark: systemIsDark)
  }
  @discardableResult
  func cancel(_ prepared: BackgroundPrepared) -> Bool {
    guard prepared.admission == resourceAdmission else { return false }
    return cancel(prepared.configuration)
  }
  func commit(_ prepared: BackgroundPrepared) throws -> Outcome {
    guard !processing else { return .busy }
    guard prepared.admission == resourceAdmission else { return .stale }
    return try commit(prepared.configuration, background: prepared.background)
  }
  func commit(_ prepared: Prepared) throws -> Outcome {
    try commit(prepared, background: nil)
  }
  private func commit(_ prepared: Prepared, background: WebsiteConfigBackgroundResource?,
    font: WebsiteConfigFontResource? = nil, session: TypingSession? = nil,
    practice: WebsiteConfigSessionBuilder.Prepared? = nil,
    page: PracticePageSessionStore? = nil, systemIsDark: Bool = false) throws -> Outcome {
    guard !processing else { return .busy }
    processing = true
    defer { processing = false }
    guard session != nil || sessionRequest != prepared.request else { return .stale }
    guard isCurrent(prepared) else { retire(prepared); return .stale }
    if prepared.pageCapture != nil || prepared.applicationCapture != nil {
      guard let source = prepared.sourcePage, page === source else { throw PracticePageSessionStateError.wrongOwner }
    }
    if session != nil { try Task.checkCancellation() }
    let applicationID = UUID()
    let appearance: WebsiteConfigPublishedPresentation.PreparedAppearance?
    if let page {
      if let pending = page.state.configurationDeparture,
        prepared.pageCapture?.configurationDeparture != pending.id,
        prepared.applicationCapture?.configurationDeparture != pending.id { return .stale }
      guard let session, let practice, font != nil, background != nil,
        !session.hasStarted, !session.isFinished,
        session.automaticInputAttemptID == practice.session.automaticInputAttemptID,
        session.configuration == practice.session.configuration,
        session.prompt.utf16.elementsEqual(practice.session.prompt.utf16) else {
        throw PracticePageSessionStateError.invalidAttempt
      }
      appearance = try WebsiteConfigPublishedPresentation.prepareAppearance(draft: prepared.draft,
        applicationID: applicationID, systemIsDark: systemIsDark)
      try page.beginCommit(owner: prepared.owner, router: router, capture: prepared.pageCapture,
        applicationCapture: prepared.applicationCapture)
    } else { appearance = nil }
    defer { page?.endCommit() }
    let outcome: WebsiteConfigFileRegister.Commit
    let restoringNative: Bool
    if case .restored(let value) = prepared.draft.origin, case .nativeState = value.origin { restoringNative = true }
    else { restoringNative = false }
    do { outcome = try register.commit(prepared.savedDraft ?? prepared.draft, replacing: prepared.disk,
      preservingUnchanged: restoringNative || prepared.savedApplicationID != nil
        || prepared.departureID != nil || prepared.funboxSelectionSaved == false) }
    catch WebsiteConfigFileRegisterError.busy { return .busy }
    switch outcome {
    case .committed(let disk):
      // No await, fallible receiver, legacy write or resource activation after
      // CAS. The optional page assignment can notify observation synchronously;
      // both coordinator and page stay reserved until publication is complete.
      let publication = Publication(applicationID: applicationID, draft: prepared.draft,
        savedDraft: prepared.savedDraft ?? prepared.draft, owner: prepared.owner.owner,
        environmentRevision: prepared.environment.revision, pointsPerRem: prepared.environment.pointsPerRem,
        disk: disk, background: background, font: font, session: session, practice: practice,
        quoteRecoveries: prepared.quoteRecoveries,
        ownerLease: prepared.owner, authority: publicationAuthority)
      if let page, let appearance, let session, let practice {
        let presentation = WebsiteConfigPublishedPresentation(publication: publication, preparedAppearance: appearance)
        page.installCommitted(.init(session: session.withElapsedClock(), presentation: presentation, practice: practice,
          priorAttemptLedger: page.state.priorAttemptLedger), retainingRestartController: prepared.restartController)
      }
      latest = publication
      publicationAuthority.latest = publication.applicationID
      retire(prepared)
      return .committed(publication)
    case .conflict: retire(prepared); return .conflict
    case .unavailable: retire(prepared); return .unavailable
    }
  }

  private func belongsToCurrentRequest(_ prepared: Prepared) -> Bool {
    prepared.identity == identity && prepared.request == request
  }
  private func isCurrent(_ prepared: Prepared) -> Bool {
    guard belongsToCurrentRequest(prepared), router.isCurrent(prepared.owner),
      matchesPage(prepared), environment() == prepared.environment else { return false }
    // A host environment reader is a callback. Revalidate after it returns so
    // it cannot accidentally move ownership and leave an earlier check valid.
    return belongsToCurrentRequest(prepared) && router.isCurrent(prepared.owner) && matchesPage(prepared)
  }
  private func matchesPage(_ prepared: Prepared) -> Bool {
    if prepared.requiresRestartController {
      guard let controller = prepared.restartController,
        prepared.sourcePage?.restartController === controller, controller.isPreparing else { return false }
    }
    if let content = prepared.contentCapture {
      guard let source = prepared.contentSource, source.isCurrent(content) else { return false }
    }
    if let application = prepared.applicationCapture {
      guard let page = prepared.sourcePage, page.isCurrent(application, router: router) else { return false }
    }
    guard let capture = prepared.pageCapture else { return true }
    guard let page = prepared.sourcePage else { return false }
    return page.isCurrent(capture, router: router)
  }
  private func retire(_ prepared: Prepared) {
    if belongsToCurrentRequest(prepared) { request = UUID() }
  }
}
