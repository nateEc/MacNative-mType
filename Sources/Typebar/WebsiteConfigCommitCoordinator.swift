import Foundation

enum WebsiteConfigCommitCoordinatorError: Error { case noOwner, noEnvironment, unavailable, reentrant, stale }

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
    let draft: WebsiteConfigNativeDraft
    fileprivate let identity: UUID
    fileprivate let request: UUID
    fileprivate let owner: PreferenceConfigurationSaveRouter.Lease
    fileprivate let environment: Environment
    fileprivate let disk: WebsiteConfigFileRegister.Revision
  }
  struct Publication {
    let draft: WebsiteConfigNativeDraft
    let owner: UUID
    let environmentRevision: UUID
    let disk: WebsiteConfigFileRegister.Revision
    /// nil means no background admission was attempted, not an empty image.
    let background: WebsiteConfigBackgroundResource?
  }
  struct BackgroundPrepared {
    fileprivate let configuration: Prepared
    fileprivate let admission: UUID
    let background: WebsiteConfigBackgroundResource
  }
  enum Outcome { case committed(Publication), stale, conflict, unavailable, busy }
  private let router: PreferenceConfigurationSaveRouter
  private let register: WebsiteConfigFileRegister
  private let environment: () -> Environment?
  private let identity = UUID()
  private var request = UUID()
  private var backgroundAdmission = UUID()
  private var latest: Publication?
  private var processing = false

  init(router: PreferenceConfigurationSaveRouter, register: WebsiteConfigFileRegister,
    environment: @escaping () -> Environment?) {
    self.router = router; self.register = register; self.environment = environment
  }

  func prepare(_ json: String) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    processing = true
    defer { processing = false }
    request = UUID()
    guard let owner = router.captureLease() else { throw WebsiteConfigCommitCoordinatorError.noOwner }
    guard let context = environment() else { throw WebsiteConfigCommitCoordinatorError.noEnvironment }
    let draft = try WebsiteConfigNativeProfile.prepareDraft(json, pointsPerRem: context.pointsPerRem, context: context.context)
    guard let disk = try register.read().revision else { throw WebsiteConfigCommitCoordinatorError.unavailable }
    let prepared = Prepared(draft: draft, identity: identity, request: request, owner: owner, environment: context, disk: disk)
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
    backgroundAdmission = UUID()
    let background = try WebsiteConfigBackgroundResource.prepare(
      preferences: prepared.draft.pagePreferences, local: local, remote: remote, limits: limits)
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return .init(configuration: prepared, admission: backgroundAdmission, background: background)
  }
  @discardableResult
  func cancel(_ prepared: BackgroundPrepared) -> Bool {
    guard prepared.admission == backgroundAdmission else { return false }
    return cancel(prepared.configuration)
  }
  func commit(_ prepared: BackgroundPrepared) throws -> Outcome {
    guard !processing else { return .busy }
    guard prepared.admission == backgroundAdmission else { return .stale }
    return try commit(prepared.configuration, background: prepared.background)
  }
  func commit(_ prepared: Prepared) throws -> Outcome {
    try commit(prepared, background: nil)
  }
  private func commit(_ prepared: Prepared, background: WebsiteConfigBackgroundResource?) throws -> Outcome {
    guard !processing else { return .busy }
    processing = true
    defer { processing = false }
    guard isCurrent(prepared) else { retire(prepared); return .stale }
    let outcome: WebsiteConfigFileRegister.Commit
    do { outcome = try register.commit(prepared.draft, replacing: prepared.disk) }
    catch WebsiteConfigFileRegisterError.busy { return .busy }
    switch outcome {
    case .committed(let disk):
      // From the record's commit point to this value publication there is no
      // await, caller callback, legacy write, resource activation or event replay.
      let publication = Publication(draft: prepared.draft, owner: prepared.owner.owner,
        environmentRevision: prepared.environment.revision, disk: disk, background: background)
      latest = publication
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
      environment() == prepared.environment else { return false }
    // A host environment reader is a callback. Revalidate after it returns so
    // it cannot accidentally move ownership and leave an earlier check valid.
    return belongsToCurrentRequest(prepared) && router.isCurrent(prepared.owner)
  }
  private func retire(_ prepared: Prepared) {
    if belongsToCurrentRequest(prepared) { request = UUID() }
  }
}
