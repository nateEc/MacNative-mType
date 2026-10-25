import Foundation
import Observation

/// Window-local state destination. Attachment must follow the actual page's
/// lifetime; this object does not register or activate a preference owner.
@MainActor @Observable
final class PracticePageSessionStore {
  let owner = UUID()
  @ObservationIgnored let lazyModeNotices = WebsiteConfigLazyModeNotices()
  private(set) var state = PracticePageSessionState()
  private(set) var restartController: WebsitePracticeRestartController?
  private(set) var startupController = WebsiteConfigStartupController()
  private var startupInputSuspended = false
  @ObservationIgnored private var startupInputTransition = false
  @ObservationIgnored private weak var router: PreferenceConfigurationSaveRouter?
  @ObservationIgnored private var committing = false
  @ObservationIgnored private var pendingDetach = false
  @ObservationIgnored private var attachment = UUID()
  @ObservationIgnored private var compositionActivity = UUID()
  private(set) var isReturningToTypebarSettings = false
  @ObservationIgnored private var legacyReturnTransition = false
  @ObservationIgnored private var legacyReturnPermit: LegacyReturnPermit?
  @ObservationIgnored private var typebarSettingsAction: (@MainActor () throws -> Void)?

  struct LegacyReturnPermit {
    fileprivate let request: UUID
    fileprivate let lease: PreferenceConfigurationSaveRouter.Lease
    fileprivate let attachment: UUID
    fileprivate let previousAttempt: UUID
  }

  struct GenerationCapture {
    let publication: WebsiteConfigCommitCoordinator.Publication
    let scope: WebsiteConfigSessionBuilder.Scope
    fileprivate let lease: PreferenceConfigurationSaveRouter.Lease
    fileprivate let attachment: UUID
    fileprivate let compositionActivity: UUID
    fileprivate let session: TypingSession.GenerationState
    fileprivate let repetition: WebsitePracticeRepetition
    fileprivate let restartDeparture: UUID?
    let configurationDeparture: UUID?
    fileprivate let quoteInitialization: UUID?
    var testActive: Bool { session.started && !session.finished }
  }

  /// A full application may start before this window has any website profile.
  /// This captures the actual initial/legacy attempt, not a fabricated seed.
  struct ApplicationCapture {
    let scope: WebsiteConfigSessionBuilder.Scope
    fileprivate let lease: PreferenceConfigurationSaveRouter.Lease
    fileprivate let attachment: UUID
    fileprivate let compositionActivity: UUID
    fileprivate let session: TypingSession.GenerationState
    fileprivate let publication: UUID?
    fileprivate let repetition: WebsitePracticeRepetition?
    fileprivate let restartDeparture: UUID?
    let configurationDeparture: UUID?
    fileprivate let quoteInitialization: UUID?
    fileprivate var savedApplication: UUID?
    func acceptingApplication(_ id: UUID) -> Self {
      var copy = self; copy.savedApplication = id; return copy
    }
  }

  func captureApplication(router: PreferenceConfigurationSaveRouter) throws -> ApplicationCapture {
    guard !committing, self.router === router, let lease = router.captureLease(), lease.owner == owner else {
      throw PracticePageSessionStateError.wrongOwner
    }
    let session = state.session
    guard !session.hasStarted || session.isFinished || !session.configuration.modifiers.contains(.noQuit) else {
      throw PracticePageSessionStateError.locked
    }
    var scope = state.practice?.scope ?? .init()
    if let progress = state.currentQuoteInitialization { scope.quoteSampler = progress.sampler }
    scope.weakSpotScores = session.liveWeakSpotScores
    scope.decorationState = session.liveWordDecorationState
    scope.arrowChart = session.generatedWordReplayHistory?.arrowChart ?? scope.arrowChart
    return .init(scope: scope, lease: lease, attachment: attachment, compositionActivity: compositionActivity,
      session: session.generationState, publication: state.presentation?.publication.applicationID,
      repetition: state.practice?.repetition, restartDeparture: state.restartDepartureAttemptID,
      configurationDeparture: state.configurationDeparture?.id, quoteInitialization: state.quoteInitialization?.id,
      savedApplication: state.savedApplication?.id)
  }
  func isCurrent(_ capture: ApplicationCapture, router: PreferenceConfigurationSaveRouter) -> Bool {
    !committing && self.router === router && capture.lease.owner == owner && router.isCurrent(capture.lease)
      && capture.attachment == attachment && capture.compositionActivity == compositionActivity
      && state.session.generationState == capture.session
      && state.presentation?.publication.applicationID == capture.publication
      && state.practice?.repetition == capture.repetition
      && state.restartDepartureAttemptID == capture.restartDeparture
      && state.configurationDeparture?.id == capture.configurationDeparture
      && state.quoteInitialization?.id == capture.quoteInitialization
      && state.savedApplication?.id == capture.savedApplication
  }

  func captureGeneration(router: PreferenceConfigurationSaveRouter) throws -> GenerationCapture {
    guard state.savedApplication == nil else { throw PracticePageSessionStateError.incomplete }
    guard !committing, self.router === router, let lease = router.captureLease(), lease.owner == owner else {
      throw PracticePageSessionStateError.wrongOwner
    }
    guard let publication = state.presentation?.publication, publication.owner == owner,
      let practice = state.practice,
      state.session.automaticInputAttemptID == practice.session.automaticInputAttemptID
    else { throw PracticePageSessionStateError.incomplete }
    var scope = practice.scope
    if let progress = state.currentQuoteInitialization { scope.quoteSampler = progress.sampler }
    scope.weakSpotScores = state.session.liveWeakSpotScores
    scope.decorationState = state.session.liveWordDecorationState
    scope.arrowChart = state.session.generatedWordReplayHistory?.arrowChart ?? scope.arrowChart
    return .init(publication: publication, scope: scope, lease: lease,
      attachment: attachment, compositionActivity: compositionActivity, session: state.session.generationState,
      repetition: practice.repetition, restartDeparture: state.restartDepartureAttemptID,
      configurationDeparture: state.configurationDeparture?.id, quoteInitialization: state.quoteInitialization?.id)
  }
  func isCurrent(_ capture: GenerationCapture, router: PreferenceConfigurationSaveRouter) -> Bool {
    state.savedApplication == nil && !committing && self.router === router && capture.lease.owner == owner && router.isCurrent(capture.lease)
      && capture.attachment == attachment
      && capture.compositionActivity == compositionActivity
      && state.presentation?.publication.applicationID == capture.publication.applicationID
      && state.session.generationState == capture.session
      && state.practice?.repetition == capture.repetition
      && state.restartDepartureAttemptID == capture.restartDeparture
      && state.configurationDeparture?.id == capture.configurationDeparture
      && state.quoteInitialization?.id == capture.quoteInitialization
  }
  func noteCompositionActivity(for attemptID: UUID) {
    guard acceptsInput(for: attemptID) else { return }
    compositionActivity = UUID()
  }

  func attach(to router: PreferenceConfigurationSaveRouter) {
    guard !committing else { return }
    typebarSettingsAction = nil; clearLegacyReturn()
    startupController.stop(); startupController = .init(); setStartupInputSuspended(false)
    retireRestartController()
    attachment = UUID()
    self.router = router
  }
  func detach() {
    attachment = UUID()
    if committing { pendingDetach = true }
    else { router = nil }
    typebarSettingsAction = nil; clearLegacyReturn()
    retireRestartController(); startupController.stop()
  }
  func replace(_ state: PracticePageSessionState) {
    guard !committing else { return }
    if state.presentation?.publication.applicationID != self.state.presentation?.publication.applicationID { retireRestartController() }
    self.state = state
  }
  func acceptsInput(for attemptID: UUID) -> Bool {
    acceptsAttemptCallback(for: attemptID) && !isInputSuspendedForRestart
  }
  var ownsConfigurationSelection: Bool { state.practice != nil || state.savedApplication != nil }
  func acceptsAttemptCallback(for attemptID: UUID) -> Bool {
    router != nil && !committing && !startupInputTransition && !startupInputSuspended
      && !legacyReturnTransition && !isReturningToTypebarSettings
      && state.configurationDeparture == nil
      && state.savedApplication == nil
      && state.session.automaticInputAttemptID == attemptID
  }
  func setStartupInputSuspended(_ suspended: Bool) {
    guard startupInputSuspended != suspended else { return }
    startupInputTransition = true
    startupInputSuspended = suspended
    startupInputTransition = false
  }

  func bindTypebarSettingsAction(_ action: @escaping @MainActor () throws -> Void) {
    guard !committing, router != nil else { return }
    typebarSettingsAction = action
  }
  func useTypebarSettings() throws {
    guard !committing, let router, router.captureLease()?.owner == owner else {
      throw PracticePageSessionStateError.wrongOwner
    }
    guard !state.session.hasStarted || state.session.isFinished else { throw PracticePageSessionStateError.locked }
    guard let typebarSettingsAction else { throw PracticePageSessionStateError.incomplete }
    try typebarSettingsAction()
  }

  /// Reversible window-only cutover. No configuration record or preference is
  /// deleted. Input stays closed until the normal native path creates a fresh
  /// attempt; a failed native restoration can retry or restore the full profile.
  func beginLegacyReturn() throws -> LegacyReturnPermit {
    guard !committing, let router, let lease = router.captureLease(), lease.owner == owner else {
      throw PracticePageSessionStateError.wrongOwner
    }
    guard !state.session.hasStarted || state.session.isFinished else { throw PracticePageSessionStateError.locked }
    guard state.practice != nil || state.savedApplication != nil || legacyReturnPermit != nil else { throw PracticePageSessionStateError.incomplete }
    let permit = LegacyReturnPermit(request: UUID(), lease: lease, attachment: attachment,
      previousAttempt: state.session.automaticInputAttemptID)
    committing = true
    legacyReturnPermit = permit
    legacyReturnTransition = true
    isReturningToTypebarSettings = true
    legacyReturnTransition = false
    retireRestartController()
    state = .init(session: state.session, priorAttemptLedger: state.priorAttemptLedger)
    endCommit()
    guard self.router === router, router.isCurrent(lease), attachment == permit.attachment else {
      throw PracticePageSessionStateError.stale
    }
    return permit
  }
  func finishLegacyReturn(_ permit: LegacyReturnPermit) throws {
    guard !committing, let router, router.isCurrent(permit.lease), permit.lease.owner == owner,
      attachment == permit.attachment, legacyReturnPermit?.request == permit.request else {
      throw PracticePageSessionStateError.stale
    }
    guard state.practice == nil, state.presentation == nil,
      state.session.automaticInputAttemptID != permit.previousAttempt,
      !state.session.hasStarted, !state.session.isFinished else { throw PracticePageSessionStateError.invalidAttempt }
    clearLegacyReturn()
  }
  private func clearLegacyReturn() {
    guard isReturningToTypebarSettings || legacyReturnPermit != nil else { return }
    legacyReturnTransition = true
    isReturningToTypebarSettings = false
    legacyReturnPermit = nil
    legacyReturnTransition = false
  }
  var isInputSuspendedForRestart: Bool {
    state.savedApplication != nil || state.configurationDeparture != nil || restartController?.isPreparing == true
      || state.restartDepartureAttemptID == state.session.automaticInputAttemptID
  }
  @ObservationIgnored private var layoutFluidHandlerOwner: UUID?
  @ObservationIgnored private var layoutFluidHandler: ((WebsiteLayoutFluidTransition.Event, UUID) throws -> Void)?
  func bindLayoutFluidHandler(owner: UUID, handler: @escaping (WebsiteLayoutFluidTransition.Event, UUID) throws -> Void) {
    layoutFluidHandlerOwner = owner; layoutFluidHandler = handler
  }
  func retireLayoutFluidHandler(owner: UUID) {
    guard layoutFluidHandlerOwner == owner else { return }
    layoutFluidHandlerOwner = nil; layoutFluidHandler = nil
  }
  func advanceLayoutFluid(_ event: WebsiteLayoutFluidTransition.Event, attemptID: UUID) throws {
    guard acceptsInput(for: attemptID), let layoutFluidHandler else { throw PracticePageSessionStateError.stale }
    try layoutFluidHandler(event, attemptID)
  }
  @discardableResult
  func bindRestartController(using coordinator: WebsiteConfigCommitCoordinator,
    notices: LocalNoticeCenter? = nil,
    loadQuotes: @escaping @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) },
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)? = nil)
    throws -> WebsitePracticeRestartController {
    guard state.configurationDeparture == nil else { throw WebsiteConfigCommitCoordinatorError.sessionNotReady }
    guard let router else { throw PracticePageSessionStateError.wrongOwner }
    let capture = try captureGeneration(router: router)
    guard coordinator.publication(for: owner)?.applicationID == capture.publication.applicationID else {
      throw PracticePageSessionStateError.stale
    }
    retireRestartController()
    let controller = WebsitePracticeRestartController(page: self, coordinator: coordinator, notices: notices,
      loadQuotes: loadQuotes, loadExternal: loadExternal)
    restartController = controller
    return controller
  }
  private func retireRestartController() {
    restartController?.stop(); restartController = nil
    layoutFluidHandlerOwner = nil; layoutFluidHandler = nil
  }

  /// Called after the coordinator's environment callback and before its CAS.
  /// No suspension or fallible receiver is permitted while this reservation
  /// lives; observation callbacks from the final assignment remain guarded.
  func beginCommit(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture? = nil,
    applicationCapture: ApplicationCapture? = nil) throws {
    try validateCommitOwnership(owner: lease, router: router, capture: capture, applicationCapture: applicationCapture)
    let session = state.session
    guard !session.hasStarted || session.isFinished || !session.configuration.modifiers.contains(.noQuit) else {
      throw PracticePageSessionStateError.locked
    }
    committing = true
  }
  func beginLiveBehaviorCommit(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture, draft: WebsiteConfigNativeDraft) throws {
    guard state.configurationDeparture == nil, state.savedApplication == nil,
      WebsiteConfigBehaviorEdit.admits(draft, from: capture.publication.draft) else {
      throw PracticePageSessionStateError.locked
    }
    try validateCommitOwnership(owner: lease, router: router, capture: capture)
    committing = true
  }
  func beginLiveSoundCommit(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture, draft: WebsiteConfigNativeDraft) throws {
    guard state.configurationDeparture == nil, state.savedApplication == nil,
      WebsiteConfigSoundEdit.admits(draft, from: capture.publication.draft) else { throw PracticePageSessionStateError.locked }
    try validateCommitOwnership(owner: lease, router: router, capture: capture)
    committing = true
  }
  func beginLiveCaretCommit(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture, draft: WebsiteConfigNativeDraft) throws {
    guard state.configurationDeparture == nil, state.savedApplication == nil,
      WebsiteConfigCaretEdit.admits(draft, from: capture.publication.draft) else { throw PracticePageSessionStateError.locked }
    try validateCommitOwnership(owner: lease, router: router, capture: capture)
    committing = true
  }
  func beginLivePaceCommit(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture, draft: WebsiteConfigNativeDraft) throws {
    guard state.configurationDeparture == nil, state.savedApplication == nil,
      WebsitePaceCommand.admits(draft, from: capture.publication.draft) else { throw PracticePageSessionStateError.locked }
    try validateCommitOwnership(owner: lease, router: router, capture: capture)
    committing = true
  }
  func beginLiveKeymapCommit(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture, draft: WebsiteConfigNativeDraft) throws {
    guard state.configurationDeparture == nil, state.savedApplication == nil,
      WebsiteKeymapCommand.admits(draft, from: capture.publication.draft) else { throw PracticePageSessionStateError.locked }
    try validateCommitOwnership(owner: lease, router: router, capture: capture)
    committing = true
  }
  func beginLiveLayoutFluidCommit(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture, draft: WebsiteConfigNativeDraft) throws {
    guard state.configurationDeparture == nil, state.savedApplication == nil,
      WebsiteLayoutFluidTransition.admits(draft, from: capture.publication.draft) else { throw PracticePageSessionStateError.locked }
    if case .edited(let edit) = draft.origin, edit.key == "layout",
      state.session.hasStarted && !state.session.isFinished && state.session.configuration.modifiers.contains(.noQuit) {
      throw PracticePageSessionStateError.locked
    }
    try validateCommitOwnership(owner: lease, router: router, capture: capture)
    committing = true
  }
  func beginLiveAppearanceCommit(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture, draft: WebsiteConfigNativeDraft) throws {
    guard state.configurationDeparture == nil, state.savedApplication == nil,
      WebsiteAppearanceCommand.admits(draft, from: capture.publication.draft) else { throw PracticePageSessionStateError.locked }
    try validateCommitOwnership(owner: lease, router: router, capture: capture)
    committing = true
  }
  func beginLiveInputRuleCommit(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture, draft: WebsiteConfigNativeDraft) throws {
    guard state.configurationDeparture == nil, state.savedApplication == nil,
      WebsiteConfigInputCommand.admits(draft, from: capture.publication.draft), case .edited(let edit) = draft.origin else {
      throw PracticePageSessionStateError.locked
    }
    let activeNoQuit = state.session.hasStarted && !state.session.isFinished && state.session.configuration.modifiers.contains(.noQuit)
    guard !activeNoQuit || !WebsiteConfigRuntimeProjector.restartRequiredKeys.contains(edit.key) else { throw PracticePageSessionStateError.locked }
    try validateCommitOwnership(owner: lease, router: router, capture: capture)
    committing = true
  }
  /// Not a general No Quit bypass: only the next-attempt Polyglot list may
  /// differ. The coordinator retains this exact attempt while saving it.
  func beginFuturePolyglotCommit(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture, draft: WebsiteConfigNativeDraft) throws {
    guard state.configurationDeparture == nil, case .edited(let edit) = draft.origin,
      edit.key == "customPolyglot", draft.projection.rejectedKeys.isEmpty,
      !draft.projection.events.isEmpty,
      draft.projection.events.allSatisfy({ $0.key == "customPolyglot" && $0.nosave == false }),
      draft.projection.runtime.count == capture.publication.draft.projection.runtime.count,
      capture.publication.draft.projection.runtime.allSatisfy({ key, value in
        key == "customPolyglot" || draft.projection.runtime[key] == value
      }) else { throw PracticePageSessionStateError.locked }
    try validateCommitOwnership(owner: lease, router: router, capture: capture)
    committing = true
  }
  private func validateCommitOwnership(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture? = nil,
    applicationCapture: ApplicationCapture? = nil) throws {
    guard !committing else { throw PracticePageSessionStateError.stale }
    guard self.router === router, lease.owner == owner else { throw PracticePageSessionStateError.wrongOwner }
    guard router.isCurrent(lease) else { throw PracticePageSessionStateError.stale }
    if let capture, !isCurrent(capture, router: router) { throw PracticePageSessionStateError.stale }
    if let applicationCapture, !isCurrent(applicationCapture, router: router) { throw PracticePageSessionStateError.stale }
  }
  func endCommit() {
    committing = false
    if pendingDetach { router = nil; pendingDetach = false }
  }
  func installCommitted(_ state: PracticePageSessionState,
    retainingRestartController controller: WebsitePracticeRestartController? = nil) {
    precondition(committing)
    clearLegacyReturn()
    let retainsController = controller != nil && restartController === controller
    if !retainsController && (state.presentation?.publication.applicationID != self.state.presentation?.publication.applicationID
      || state.configurationDeparture?.id != self.state.configurationDeparture?.id
      || state.savedApplication?.id != self.state.savedApplication?.id) { retireRestartController() }
    self.state = state
  }
}
