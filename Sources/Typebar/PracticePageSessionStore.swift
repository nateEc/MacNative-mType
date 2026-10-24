import Foundation
import Observation

/// Window-local state destination. Attachment must follow the actual page's
/// lifetime; this object does not register or activate a preference owner.
@MainActor @Observable
final class PracticePageSessionStore {
  let owner = UUID()
  private(set) var state = PracticePageSessionState()
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
    var testActive: Bool { session.started && !session.finished }
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
      repetition: practice.repetition)
  }
  func isCurrent(_ capture: GenerationCapture, router: PreferenceConfigurationSaveRouter) -> Bool {
    !committing && self.router === router && capture.lease.owner == owner && router.isCurrent(capture.lease)
      && capture.attachment == attachment
      && capture.compositionActivity == compositionActivity
      && state.presentation?.publication.applicationID == capture.publication.applicationID
      && state.session.generationState == capture.session
      && state.practice?.repetition == capture.repetition
  }
  func noteCompositionActivity(for attemptID: UUID) {
    guard acceptsInput(for: attemptID) else { return }
    compositionActivity = UUID()
  }

  func attach(to router: PreferenceConfigurationSaveRouter) {
    guard !committing else { return }
    attachment = UUID()
    self.router = router
  }
  func detach() {
    attachment = UUID()
    if committing { pendingDetach = true }
    else { router = nil }
  }
  func replace(_ state: PracticePageSessionState) {
    guard !committing else { return }
    self.state = state
  }
  func acceptsInput(for attemptID: UUID) -> Bool {
    router != nil && !committing && state.session.automaticInputAttemptID == attemptID
  }

  /// Called after the coordinator's environment callback and before its CAS.
  /// No suspension or fallible receiver is permitted while this reservation
  /// lives; observation callbacks from the final assignment remain guarded.
  func beginCommit(owner lease: PreferenceConfigurationSaveRouter.Lease,
    router: PreferenceConfigurationSaveRouter, capture: GenerationCapture? = nil) throws {
    guard !committing else { throw PracticePageSessionStateError.stale }
    guard self.router === router, lease.owner == owner else { throw PracticePageSessionStateError.wrongOwner }
    guard router.isCurrent(lease) else { throw PracticePageSessionStateError.stale }
    if let capture, !isCurrent(capture, router: router) { throw PracticePageSessionStateError.stale }
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
    self.state = state
  }
}
