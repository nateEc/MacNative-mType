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
  private var needsLockObservation = true
  private var backgroundRevision = UUID()
  private var stopped = false
  private var refresh: Task<Void, Never>?
  private var readingSynchronousSetter = false

  init(settings: AppSettings, account: AccountSession, pointsPerRem: Double?,
    documentComplete: Bool, development: Bool) {
    self.settings = settings
    self.account = account
    self.pointsPerRem = pointsPerRem
    self.documentComplete = documentComplete
    self.development = development
    sample()
  }

  func read() -> WebsiteConfigCommitCoordinator.Environment? {
    guard readingSynchronousSetter || settings.allowsRestartingConfigurationChange else { return nil }
    return cached
  }
  /// Observing an admitted image grants no configuration/restart capability.
  func backgroundDisplayRevision() -> UUID? { stopped ? nil : backgroundRevision }
  /// Synchronous model reads for live behavior and owned No Quit setters.
  /// This grants no commit capability; the coordinator/page still validate
  /// the exact field, events, owner, attempt and file version. Never suspend
  /// while ordinary full-configuration admission is withheld.
  func withSynchronousSetterRead<T>(_ body: () throws -> T) rethrows -> T {
    let previous = readingSynchronousSetter
    readingSynchronousSetter = true
    defer { readingSynchronousSetter = previous }
    if cached == nil {
      refresh?.cancel(); refresh = nil
      sample()
    }
    return try body()
  }
  struct ContentModels: Equatable {
    let custom: CustomTextStateRead
    let customGeneration: UInt64
    let websiteCustom: WebsiteCustomTextStateRead
    let websiteCustomGeneration: UInt64
    let localFavorites: [String]
    let accountScope: ResultPublicationScope?
    let accountGeneration: UInt64
  }
  /// Read the very same models that own this environment, never another
  /// account/settings pair supplied alongside an otherwise matching context.
  func contentModels() -> ContentModels {
    .init(custom: settings.customTextStateRead, customGeneration: settings.customTextStateGeneration,
      websiteCustom: settings.websiteCustomTextStateRead, websiteCustomGeneration: settings.websiteCustomTextStateGeneration,
      localFavorites: settings.favoriteQuoteIDs, accountScope: account.resultPublicationScope,
      accountGeneration: account.accountPersonalBestSessionRevision)
  }
  func updateLayout(pointsPerRem: Double?, documentComplete: Bool) {
    guard !stopped else { return }
    self.pointsPerRem = pointsPerRem
    self.documentComplete = documentComplete
    backgroundRevision = UUID()
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
    backgroundRevision = UUID()
    needsObservation = true
    invalidate()
  }
  private func invalidate() {
    cached = nil
    guard refresh == nil else { return }
    // Do not resample in willSet. All observed producers are MainActor-isolated.
    refresh = Task { @MainActor [weak self] in
      guard let self, !self.stopped, !Task.isCancelled else { return }
      self.refresh = nil
      self.sample()
    }
  }
  private func sample() {
    guard !stopped else { return }
    if needsLockObservation {
      needsLockObservation = false
      withObservationTracking { _ = settings.allowsRestartingConfigurationChange } onChange: { [weak self] in
        MainActor.assumeIsolated {
          self?.needsLockObservation = true; self?.invalidate()
        }
      }
    }
    if needsObservation {
      needsObservation = false
      modelContext = withObservationTracking {
        // Reading the complete legacy snapshot tracks the values, not a hash:
        // even a change back to identical values retires the previous epoch.
        _ = settings.snapshot
        _ = settings.customTextStateGeneration
        _ = settings.websiteCustomTextStateGeneration
        // The restart lock is observed separately: it retires full replay,
        // but does not change an already admitted background's resources.
        _ = settings.activeTestSelectionGeneration
        _ = settings.practiceWrapperRevision
        _ = settings.practiceFontApplicationRevision
        _ = settings.keyboardGuideApplicationRevision
        _ = settings.challengePresentationApplicationRevision
        _ = settings.difficultyApplicationRevision
        _ = settings.testModifiersApplicationRevision
        _ = settings.localPracticeFontRevision
        _ = settings.localBackgroundRevision
        _ = settings.customBackgroundApplicationID
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
