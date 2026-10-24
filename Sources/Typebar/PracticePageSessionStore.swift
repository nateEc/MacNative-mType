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

  func attach(to router: PreferenceConfigurationSaveRouter) {
    guard !committing else { return }
    self.router = router
  }
  func detach() {
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
    router: PreferenceConfigurationSaveRouter) throws {
    guard !committing else { throw PracticePageSessionStateError.stale }
    guard self.router === router, lease.owner == owner else { throw PracticePageSessionStateError.wrongOwner }
    guard router.isCurrent(lease) else { throw PracticePageSessionStateError.stale }
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
