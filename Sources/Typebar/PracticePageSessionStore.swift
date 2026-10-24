import Foundation
import Observation

/// Window-local state destination. Attachment must follow the actual page's
/// lifetime; this object does not register or activate a preference owner.
@MainActor @Observable
final class PracticePageSessionStore {
  let owner = UUID()
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

  struct GenerationCapture {
    let publication: WebsiteConfigCommitCoordinator.Publication
    let scope: WebsiteConfigSessionBuilder.Scope
    fileprivate let lease: PreferenceConfigurationSaveRouter.Lease
    fileprivate let attachment: UUID
    fileprivate let compositionActivity: UUID
    fileprivate let session: TypingSession.GenerationState
    fileprivate let repetition: WebsitePracticeRepetition
    fileprivate let restartDeparture: UUID?
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
    scope.weakSpotScores = session.liveWeakSpotScores
    scope.decorationState = session.liveWordDecorationState
    return .init(scope: scope, lease: lease, attachment: attachment, compositionActivity: compositionActivity,
      session: session.generationState, publication: state.presentation?.publication.applicationID,
      repetition: state.practice?.repetition, restartDeparture: state.restartDepartureAttemptID)
  }
  func isCurrent(_ capture: ApplicationCapture, router: PreferenceConfigurationSaveRouter) -> Bool {
    !committing && self.router === router && capture.lease.owner == owner && router.isCurrent(capture.lease)
      && capture.attachment == attachment && capture.compositionActivity == compositionActivity
      && state.session.generationState == capture.session
      && state.presentation?.publication.applicationID == capture.publication
      && state.practice?.repetition == capture.repetition
      && state.restartDepartureAttemptID == capture.restartDeparture
  }

  func captureGeneration(router: PreferenceConfigurationSaveRouter) throws -> GenerationCapture {
    guard !committing, self.router === router, let lease = router.captureLease(), lease.owner == owner else {
      throw PracticePageSessionStateError.wrongOwner
    }
    guard let publication = state.presentation?.publication, publication.owner == owner,
      let practice = state.practice,
      state.session.automaticInputAttemptID == practice.session.automaticInputAttemptID
    else { throw PracticePageSessionStateError.incomplete }
    var scope = practice.scope
    scope.weakSpotScores = state.session.liveWeakSpotScores
    scope.decorationState = state.session.liveWordDecorationState
    return .init(publication: publication, scope: scope, lease: lease,
      attachment: attachment, compositionActivity: compositionActivity, session: state.session.generationState,
      repetition: practice.repetition, restartDeparture: state.restartDepartureAttemptID)
  }
  func isCurrent(_ capture: GenerationCapture, router: PreferenceConfigurationSaveRouter) -> Bool {
    !committing && self.router === router && capture.lease.owner == owner && router.isCurrent(capture.lease)
      && capture.attachment == attachment
      && capture.compositionActivity == compositionActivity
      && state.presentation?.publication.applicationID == capture.publication.applicationID
      && state.session.generationState == capture.session
      && state.practice?.repetition == capture.repetition
      && state.restartDepartureAttemptID == capture.restartDeparture
  }
  func noteCompositionActivity(for attemptID: UUID) {
    guard acceptsInput(for: attemptID) else { return }
    compositionActivity = UUID()
  }

  func attach(to router: PreferenceConfigurationSaveRouter) {
    guard !committing else { return }
    startupController.stop(); startupController = .init(); setStartupInputSuspended(false)
    retireRestartController()
    attachment = UUID()
    self.router = router
  }
  func detach() {
    attachment = UUID()
    if committing { pendingDetach = true }
    else { router = nil }
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
  func acceptsAttemptCallback(for attemptID: UUID) -> Bool {
    router != nil && !committing && !startupInputTransition && !startupInputSuspended
      && state.session.automaticInputAttemptID == attemptID
  }
  func setStartupInputSuspended(_ suspended: Bool) {
    guard startupInputSuspended != suspended else { return }
    startupInputTransition = true
    startupInputSuspended = suspended
    startupInputTransition = false
  }
  var isInputSuspendedForRestart: Bool {
    restartController?.isPreparing == true || state.restartDepartureAttemptID == state.session.automaticInputAttemptID
  }
  @discardableResult
  func bindRestartController(using coordinator: WebsiteConfigCommitCoordinator,
    loadQuotes: @escaping @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) },
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)? = nil)
    throws -> WebsitePracticeRestartController {
    guard let router else { throw PracticePageSessionStateError.wrongOwner }
    let capture = try captureGeneration(router: router)
    guard coordinator.publication(for: owner)?.applicationID == capture.publication.applicationID else {
      throw PracticePageSessionStateError.stale
    }
    retireRestartController()
    let controller = WebsitePracticeRestartController(page: self, coordinator: coordinator,
      loadQuotes: loadQuotes, loadExternal: loadExternal)
    restartController = controller
    return controller
  }
  private func retireRestartController() {
    restartController?.stop(); restartController = nil
  }

  /// Called after the coordinator's environment callback and before its CAS.
  /// No suspension or fallible receiver is permitted while this reservation
  /// lives; observation callbacks from the final assignment remain guarded.
  func beginCommit(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture? = nil,
    applicationCapture: ApplicationCapture? = nil) throws {
    guard !committing else { throw PracticePageSessionStateError.stale }
    guard self.router === router, lease.owner == owner else { throw PracticePageSessionStateError.wrongOwner }
    guard router.isCurrent(lease) else { throw PracticePageSessionStateError.stale }
    if let capture, !isCurrent(capture, router: router) { throw PracticePageSessionStateError.stale }
    if let applicationCapture, !isCurrent(applicationCapture, router: router) { throw PracticePageSessionStateError.stale }
    let session = state.session
    guard !session.hasStarted || session.isFinished || !session.configuration.modifiers.contains(.noQuit) else {
      throw PracticePageSessionStateError.locked
    }
    committing = true
  }
  func endCommit() {
    committing = false
    if pendingDetach { router = nil; pendingDetach = false }
  }
  func installCommitted(_ state: PracticePageSessionState) {
    precondition(committing)
    if state.presentation?.publication.applicationID != self.state.presentation?.publication.applicationID { retireRestartController() }
    self.state = state
  }
}
