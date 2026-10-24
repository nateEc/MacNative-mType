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
    let draft: WebsiteConfigNativeDraft
    fileprivate let identity: UUID
    fileprivate let request: UUID
    fileprivate let owner: PreferenceConfigurationSaveRouter.Lease
    fileprivate let environment: Environment
    fileprivate let disk: WebsiteConfigFileRegister.Revision
    fileprivate weak var sourcePage: PracticePageSessionStore?
    fileprivate var pageCapture: PracticePageSessionStore.GenerationCapture?
  }
  struct Publication {
    /// One successful full application, including repeated identical values.
    let applicationID: UUID
    let draft: WebsiteConfigNativeDraft
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
    fileprivate let ownerLease: PreferenceConfigurationSaveRouter.Lease
    fileprivate let authority: WebsiteConfigPublicationAuthority

    @MainActor func isCurrentDelivery(owner: UUID, router: PreferenceConfigurationSaveRouter) -> Bool {
      guard self.owner == owner, authority.latest == applicationID, router.isCurrent(ownerLease),
        let current = try? authority.register.read().revision, current == disk else { return false }
      return router.isCurrent(ownerLease)
    }
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
  enum Outcome { case committed(Publication), stale, conflict, unavailable, busy }
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
    let draft = try WebsiteConfigNativeProfile.prepareDraft(json, pointsPerRem: context.pointsPerRem, context: context.context)
    guard let disk = try register.read().revision else { throw WebsiteConfigCommitCoordinatorError.unavailable }
    let prepared = Prepared(draft: draft, identity: identity, request: request, owner: owner, environment: context, disk: disk)
    guard isCurrent(prepared) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return prepared
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
    let draft = try WebsiteConfigNativeProfile.editDraft(base.draft, key: key, value: value,
      pointsPerRem: context.pointsPerRem, context: context.context, testActive: testActive)
    let prepared = Prepared(draft: draft, identity: identity, request: request, owner: owner,
      environment: context, disk: disk)
    guard isCurrent(prepared), try register.read().revision == base.disk,
      router.isCurrent(owner) else { throw WebsiteConfigCommitCoordinatorError.stale }
    return prepared
  }

  /// Capture the actual page instead of accepting the original seed's books.
  /// Input can continue during preparation; changed generation state rejects
  /// the candidate before further reads or CAS rather than discarding input.
  func prepareEdit(key: String, value: WebsiteConfigValue, for page: PracticePageSessionStore) throws -> Prepared {
    guard !processing else { throw WebsiteConfigCommitCoordinatorError.reentrant }
    request = UUID()
    let capture = try page.captureGeneration(router: router)
    var prepared = try prepareEdit(key: key, value: value, from: capture.publication, testActive: capture.testActive)
    // Session books are current, but inherited account/content scope is not a
    // fresh read from a new environment. Require scoped re-preparation first;
    // do not silently carry one account's content into another epoch.
    guard prepared.environment.revision == capture.publication.environmentRevision else {
      throw WebsiteConfigCommitCoordinatorError.stale
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
      guard prepared.configuration.pageCapture == nil else { throw WebsiteConfigCommitCoordinatorError.sessionNotReady }
      return (try await generate(draft), nil)
    }
  }
  func preparePractice(for prepared: ResourcesPrepared, scope: WebsiteConfigSessionBuilder.Scope,
    loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) },
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)? = nil,
    random: WebsiteConfigSessionBuilder.Random = .init()) async throws -> SessionPrepared {
    try await preparePracticeBuild(for: prepared, scope: scope, loadQuotes: loadQuotes, loadExternal: loadExternal, random: random)
  }
  func preparePractice(for prepared: ResourcesPrepared,
    loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) },
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)? = nil,
    random: WebsiteConfigSessionBuilder.Random = .init()) async throws -> SessionPrepared {
    try await preparePracticeBuild(for: prepared, scope: nil, loadQuotes: loadQuotes, loadExternal: loadExternal, random: random)
  }
  private func preparePracticeBuild(for prepared: ResourcesPrepared, scope: WebsiteConfigSessionBuilder.Scope?,
    loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote],
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)?,
    random: WebsiteConfigSessionBuilder.Random) async throws -> SessionPrepared {
    let checkedExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> WebsiteConfigSessionBuilder.External)?
    if let loadExternal {
      checkedExternal = { source, configuration in
        try await self.readAsyncResource(prepared.configuration, admission: prepared.admission) {
          try await loadExternal(source, configuration)
        }
      }
    } else { checkedExternal = nil }
    return try await prepareSessionBuild(for: prepared) { draft in
      let effectiveScope: WebsiteConfigSessionBuilder.Scope
      if let capture = prepared.configuration.pageCapture {
        guard scope == nil else { throw WebsiteConfigCommitCoordinatorError.sessionNotReady }
        effectiveScope = capture.scope
      } else {
        guard let scope else { throw WebsiteConfigCommitCoordinatorError.sessionNotReady }
        effectiveScope = scope
      }
      let practice = try await WebsiteConfigSessionBuilder.prepare(draft: draft, scope: effectiveScope,
        reason: .configurationApplication,
        loadQuotes: { language in
          try await self.readAsyncResource(prepared.configuration, admission: prepared.admission) {
            try await loadQuotes(language)
          }
        }, loadExternal: checkedExternal, random: random)
      return (practice.session, practice)
    }
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
    if prepared.pageCapture != nil {
      guard let source = prepared.sourcePage, page === source else { throw PracticePageSessionStateError.wrongOwner }
    }
    if session != nil { try Task.checkCancellation() }
    let applicationID = UUID()
    let appearance: WebsiteConfigPublishedPresentation.PreparedAppearance?
    if let page {
      guard let session, let practice, font != nil, background != nil,
        !session.hasStarted, !session.isFinished,
        session.automaticInputAttemptID == practice.session.automaticInputAttemptID,
        session.configuration == practice.session.configuration,
        session.prompt.utf16.elementsEqual(practice.session.prompt.utf16) else {
        throw PracticePageSessionStateError.invalidAttempt
      }
      appearance = try WebsiteConfigPublishedPresentation.prepareAppearance(draft: prepared.draft,
        applicationID: applicationID, systemIsDark: systemIsDark)
      try page.beginCommit(owner: prepared.owner, router: router, capture: prepared.pageCapture)
    } else { appearance = nil }
    defer { page?.endCommit() }
    let outcome: WebsiteConfigFileRegister.Commit
    do { outcome = try register.commit(prepared.draft, replacing: prepared.disk) }
    catch WebsiteConfigFileRegisterError.busy { return .busy }
    switch outcome {
    case .committed(let disk):
      // No await, fallible receiver, legacy write or resource activation after
      // CAS. The optional page assignment can notify observation synchronously;
      // both coordinator and page stay reserved until publication is complete.
      let publication = Publication(applicationID: applicationID, draft: prepared.draft, owner: prepared.owner.owner,
        environmentRevision: prepared.environment.revision, pointsPerRem: prepared.environment.pointsPerRem,
        disk: disk, background: background, font: font, session: session, practice: practice,
        ownerLease: prepared.owner, authority: publicationAuthority)
      if let page, let appearance, let session, let practice {
        let presentation = WebsiteConfigPublishedPresentation(publication: publication, preparedAppearance: appearance)
        page.installCommitted(.init(session: session.withElapsedClock(), presentation: presentation, practice: practice))
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
    guard let capture = prepared.pageCapture else { return true }
    guard let page = prepared.sourcePage else { return false }
    return page.isCurrent(capture, router: router)
  }
  private func retire(_ prepared: Prepared) {
    if belongsToCurrentRequest(prepared) { request = UUID() }
  }
}
