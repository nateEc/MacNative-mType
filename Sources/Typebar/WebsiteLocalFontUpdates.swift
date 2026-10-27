import Foundation
import Observation

/// File notifications are value-owned pending work, not configuration saves.
/// Rearm only file observation while idle; input is observed only when a file
/// update is waiting for the page/owner to become eligible.
@MainActor @Observable final class WebsiteLocalFontUpdates {
  enum Outcome { case applied(UUID), deferred, failed(String) }
  private struct Attempt: Equatable {
    let revision: Int
    let publication: UUID
    let lease: PreferenceConfigurationSaveRouter.Lease
  }
  private weak var page: PracticePageSessionStore?
  private let settings: AppSettings
  private var refresh: (@MainActor () -> Outcome)?
  private var handled: Int
  private var failedAttempt: Attempt?
  private var force = false
  private var running = false
  private var needsAnotherRead = false
  private var stopped = false
  @ObservationIgnored private var needsObservation = true
  @ObservationIgnored private var task: Task<Void, Never>?
  private(set) var failure: String?
  private(set) var publication: UUID?

  init(page: PracticePageSessionStore, settings: AppSettings, refresh: @escaping @MainActor () -> Outcome) {
    self.page = page; self.settings = settings; self.refresh = refresh
    handled = settings.localPracticeFontRevision
    request()
  }
  func retry() { force = true; request() }
  func operationEnded() {
    guard !running, settings.localPracticeFontRevision != handled || force || failedAttempt != nil else { return }
    request()
  }
  private func request() {
    guard !stopped else { return }
    if task != nil { needsAnotherRead = true; return }
    task = Task { @MainActor [weak self] in
      await Task.yield()
      guard let self, !Task.isCancelled, !self.stopped else { return }
      self.needsAnotherRead = false
      self.readAndRefresh()
      self.task = nil
      if self.needsAnotherRead { self.request() }
    }
  }
  private func pendingAttempt() -> (Attempt?, Int?) {
      let revision = settings.localPracticeFontRevision
      guard revision != handled || force || failedAttempt != nil, let page else { return (nil, nil) }
      if page.state.presentation == nil, !page.ownsConfigurationSelection {
        return (nil, revision)
      }
      guard
        let lease = settings.preferenceConfigurationSaves.captureLease(), lease.owner == page.owner,
        page.state.savedApplication == nil, page.state.configurationDeparture == nil, page.state.sharedReceipt == nil,
        page.restartController?.isPreparing != true, let id = page.state.presentation?.publication.applicationID
      else { return (nil, nil) }
      return (.init(revision: revision, publication: id, lease: lease), nil)
  }
  private func readAndRefresh() {
    let attempt: Attempt?, nativeRevision: Int?
    if needsObservation {
      needsObservation = false
      (attempt, nativeRevision) = withObservationTracking { pendingAttempt() } onChange: { [weak self] in
        MainActor.assumeIsolated { self?.needsObservation = true; self?.request() }
      }
    } else {
      (attempt, nativeRevision) = pendingAttempt()
    }
    if let nativeRevision {
      handled = nativeRevision; force = false; failedAttempt = nil; failure = nil; return
    }
    guard let attempt, attempt != failedAttempt || force, let refresh else { return }
    running = true; defer { running = false }
    let outcome = refresh()
    guard !stopped else { return }
    switch outcome {
    case .applied(let id):
      handled = attempt.revision; force = false; failedAttempt = nil; failure = nil; publication = id
    case .deferred: break
    case .failed(let message): failedAttempt = attempt; force = false; failure = message
    }
  }
  func stop() {
    stopped = true; task?.cancel(); task = nil; refresh = nil; failure = nil
  }
}
