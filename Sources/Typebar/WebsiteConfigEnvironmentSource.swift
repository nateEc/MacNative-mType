import Foundation
import Observation

/// Context freshness only; neither a resource loader nor a production cutover.
/// Consume from stable MainActor actions, never inside setters or arbitrary
/// Observation callbacks: ordering among different observers is not guaranteed.
@MainActor
final class WebsiteConfigEnvironmentSource {
  private let settings: AppSettings
  private let account: AccountSession
  private let development: Bool
  private var pointsPerRem: Double?
  private var documentComplete: Bool
  private var cached: WebsiteConfigCommitCoordinator.Environment?
  private var modelContext = WebsiteConfigRuntimeContext()
  private var needsObservation = true
  private var stopped = false
  private var refresh: Task<Void, Never>?

  init(settings: AppSettings, account: AccountSession, pointsPerRem: Double?,
    documentComplete: Bool, development: Bool) {
    self.settings = settings
    self.account = account
    self.pointsPerRem = pointsPerRem
    self.documentComplete = documentComplete
    self.development = development
    sample()
  }

  func read() -> WebsiteConfigCommitCoordinator.Environment? { cached }
  func updateLayout(pointsPerRem: Double?, documentComplete: Bool) {
    guard !stopped else { return }
    self.pointsPerRem = pointsPerRem
    self.documentComplete = documentComplete
    invalidate()
  }
  func stop() {
    stopped = true
    cached = nil
    refresh?.cancel()
    refresh = nil
  }

  private func invalidateModels() {
    guard !stopped else { return }
    needsObservation = true
    invalidate()
  }
  private func invalidate() {
    cached = nil
    guard refresh == nil else { return }
    // Do not resample in willSet. All observed producers are MainActor-isolated.
    refresh = Task { @MainActor [weak self] in
      guard let self, !self.stopped else { return }
      self.refresh = nil
      self.sample()
    }
  }
  private func sample() {
    guard !stopped else { return }
    if needsObservation {
      needsObservation = false
      modelContext = withObservationTracking {
        // Reading the complete legacy snapshot tracks the values, not a hash:
        // even a change back to identical values retires the previous epoch.
        _ = settings.snapshot
        _ = settings.activeTestSelectionGeneration
        _ = settings.practiceWrapperRevision
        _ = settings.practiceFontApplicationRevision
        _ = settings.keyboardGuideApplicationRevision
        _ = settings.challengePresentationApplicationRevision
        _ = settings.difficultyApplicationRevision
        _ = settings.testModifiersApplicationRevision
        _ = settings.localPracticeFontRevision
        _ = settings.localBackgroundRevision
        _ = account.endpoint
        _ = account.accountPersonalBestSessionRevision
        return WebsiteConfigRuntimeContext(authenticated: account.currentUser != nil,
          customThemeCount: settings.customThemes.count)
      } onChange: { [weak self] in
        // Only AppSettings and AccountSession are subscribed; their mutations
        // are compiler-isolated to MainActor. Never delay this invalidation.
        MainActor.assumeIsolated { self?.invalidateModels() }
      }
    }
    guard let pointsPerRem, pointsPerRem.isFinite, pointsPerRem > 0 else {
      cached = nil
      return
    }
    var context = modelContext
    context.documentComplete = documentComplete
    context.development = development
    cached = .init(revision: UUID(), context: context, pointsPerRem: pointsPerRem)
  }
}
