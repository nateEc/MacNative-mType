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
    var configurationWasSaved: Bool { draft.projection.events.contains { $0.nosave == false } }
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
    let capture = try page.captureGeneration(router: router)
    guard capture.configurationDeparture == pending.id,
      capture.publication.authority === publicationAuthority,
      latest?.applicationID == capture.publication.applicationID,
      try register.read().revision == pending.disk else { throw WebsiteConfigCommitCoordinatorError.stale }
    var prepared = Prepared(draft: pending.draft, identity: identity, request: request,
      owner: owner, environment: context, disk: pending.disk)
    prepared.savedDraft = pending.savedDraft
    prepared.quoteRecoveries = pending.quoteRecoveries
    prepared.retainsQuoteInitialization = true
    prepared.quoteInitialization = page.state.currentQuoteInitialization
    prepared.sourcePage = page; prepared.pageCapture = capture
    if pending.requiresContentSource {
      guard let source = pending.contentSource else { throw WebsiteConfigCommitCoordinatorError.unavailable }
      let content = try source.capture(owner: page.owner, preserving: capture.scope)
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
  enum Restoration { case missing, unavailable, prepared(Prepared) }
  private let router: PreferenceConfigurationSaveRouter
  private let register: WebsiteConfigFileRegister
  private let environment: () -> Environment?
  private let identity = UUID()
  private var request = UUID()
  private var resourceAdmission = UUID()
  private var sessionAdmission = UUID()
  private var sessionRequest: UUID?
  private var latest: Publication?
  private let publicationAuthority: WebsiteConfigPublicationAuthority
  private var processing = false

  init(router: PreferenceConfigurationSaveRouter, register: WebsiteConfigFileRegister,
    environment: @escaping () -> Environment?) {
    self.router = router; self.register = register; self.environment = environment
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
    if key == "funbox" {
      guard !testActive || !base.draft.generators.requestedModifiers.contains(.noQuit) else { throw WebsiteConfigNativeDraftError.rejectedEdit }
      let selection = try WebsiteConfigFunboxMemory.selecting(value, from: base.draft,
        pointsPerRem: context.pointsPerRem, context: context.context, testActive: testActive)
      draft = selection.draft; funboxSelectionSaved = selection.saved
    } else {
      draft = try WebsiteConfigNativeProfile.editDraft(base.draft, key: key, value: value,
        pointsPerRem: context.pointsPerRem, context: context.context, testActive: testActive)
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
  private func preparePageEdit(key: String, value: WebsiteConfigValue, for page: PracticePageSessionStore,
    refreshingWith source: WebsiteConfigPracticeScopeSource?) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    guard page.state.configurationDeparture == nil else { throw WebsiteConfigCommitCoordinatorError.sessionNotReady }
    request = UUID()
    let capture = try page.captureGeneration(router: router)
    var prepared = try prepareEdit(key: key, value: value, from: capture.publication, testActive: capture.testActive)
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
    let session = try await prepareSessionBuild(for: resources) { _ in
      // Restore the actual attempt's owned opening/cursors/caches, not a
      // reconstruction from the editor, its grown prompt or a fresh sampler.
      let repeated = original.repeatedAttempt(nextRandomCaseBit: random.caseBit)
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
    guard page.state.configurationDeparture == nil else { throw WebsiteConfigCommitCoordinatorError.sessionNotReady }
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
        let effectiveReason: WebsiteConfigSessionBuilder.Reason = current.configuration.pageCapture?.configurationDeparture != nil
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
        && resources.configuration.pageCapture?.configurationDeparture == nil
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
    if let loadExternal {
      checkedExternal = { source, configuration in
        try await self.readAsyncResource(prepared.configuration, admission: prepared.admission) {
          try await loadExternal(source, configuration)
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
        prepared.configuration.pageCapture?.configurationDeparture == pending.id,
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
      requiresContentSource: requiresContentSource, repetition: repetition, quote: quote, wordHistory: history)
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
        || prepared.pageCapture?.configurationDeparture != nil || prepared.funboxSelectionSaved == false) }
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
