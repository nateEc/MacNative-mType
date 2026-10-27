import Foundation

enum WebsiteConfigPracticeScopeSourceError: Error { case unavailable, wrongOwner, stale, invalidContent }

/// Read-only model/window hydration. Native-local favorites are explicitly
/// separate from the website's authenticated favorite-quote collection.
/// Invoke at stable MainActor actions, not from a producer's willSet observer.
@MainActor final class WebsiteConfigPracticeScopeSource {
  enum Favorites: Equatable { case accountUnavailable, nativeLocal }
  struct TimedContent: Equatable {
    let source: CustomTextSource
    let seconds: TimeInterval
    var ordering: CustomTextOrdering = .inOrder
    var pipeDelimiter: Bool?
    /// Whole timed corpus, not the factory's finish-only finite stream.
    var corpus: String?
    var preservesSpelling = false
    var recoveryBlocked = false
    static func == (a: Self, b: Self) -> Bool {
      let finiteMatches: Bool
      switch (a.corpus, b.corpus) {
      case (nil, nil): finiteMatches = true
      case (.some(let a), .some(let b)): finiteMatches = InputTextIdentity.matches(a, b)
      default: finiteMatches = false
      }
      return a.source == b.source && a.seconds == b.seconds && a.ordering == b.ordering
        && a.pipeDelimiter == b.pipeDelimiter && finiteMatches && a.preservesSpelling == b.preservesSpelling
        && a.recoveryBlocked == b.recoveryBlocked
    }
  }
  enum Custom: Equatable {
    case stored
    case explicit(CustomTextStateDocument, finiteTextSource: String?, preservesSpelling: Bool, recoveryBlocked: Bool)
    case timed(TimedContent)
    case website(WebsiteCustomTextSettings)
    static func == (a: Self, b: Self) -> Bool {
      switch (a, b) {
      case (.stored, .stored): return true
      case (.timed(let a), .timed(let b)): return a == b
      case (.website(let a), .website(let b)): return a == b
      case let (.explicit(ad, af, ap, ab), .explicit(bd, bf, bp, bb)):
        let finiteMatches: Bool
        switch (af, bf) {
        case (nil, nil): finiteMatches = true
        case (.some(let a), .some(let b)): finiteMatches = InputTextIdentity.matches(a, b)
        default: finiteMatches = false
        }
        return ad == bd && finiteMatches && ap == bp && ab == bb
      default: return false
      }
    }
  }
  struct Window: Equatable {
    let owner: UUID
    var customRecoveryBlocked: Bool
    /// The window rotates this for every content/control application, even ABA.
    var revision = UUID()
    var selectedQuoteID: String?
    var parameterMemory: TypebarTestParameterMemory = .defaults
    var custom: Custom = .stored
    var favorites: Favorites = .accountUnavailable

    /// Rehydrate controls from the committed whole scope, not legacy fields
    /// left behind by the pre-migration page. Preserve exact timed duration.
    static func published(owner: UUID, revision: UUID,
      scope: WebsiteConfigSessionBuilder.Scope) -> Self {
      let source = scope.preparedCustomSections.map(CustomTextSource.prepared) ?? .editor(scope.customText)
      let memory = scope.parameterMemory
      let custom: Custom
      if let value = scope.websiteCustomText { custom = .website(value) }
      else if scope.customCompletion == .time {
        custom = .timed(.init(source: source,
          seconds: scope.customDurationOverride ?? Double(memory.customTextDuration),
          ordering: scope.customOrdering, pipeDelimiter: scope.customPipeDelimiter,
          corpus: scope.preparedCustomSections == nil ? scope.customText : nil,
          preservesSpelling: scope.customTextIsPrepared, recoveryBlocked: scope.customTextRecoveryBlocked))
      } else {
        let configuration = TestConfiguration(mode: .custom, duration: nil,
          wordLimit: scope.customCompletion == .words ? memory.customTextWordLimit : nil,
          difficulty: .normal, rules: .init(), customTextCompletion: scope.customCompletion,
          customTextSectionLimit: scope.customCompletion == .sections ? memory.customTextSectionLimit : nil,
          customTextOrdering: scope.customOrdering, customTextPipeDelimiter: scope.customPipeDelimiter)
        custom = .explicit(.init(source: source, configuration: configuration),
          finiteTextSource: scope.finiteTextSource, preservesSpelling: scope.customTextIsPrepared,
          recoveryBlocked: scope.customTextRecoveryBlocked)
      }
      return .init(owner: owner, customRecoveryBlocked: scope.customTextRecoveryBlocked,
        revision: revision, selectedQuoteID: scope.selectedQuoteID, parameterMemory: memory, custom: custom)
    }
  }
  struct Snapshot {
    let scope: WebsiteConfigSessionBuilder.Scope
    let environment: WebsiteConfigCommitCoordinator.Environment
    fileprivate let source: UUID
    fileprivate let window: Window
    fileprivate let models: WebsiteConfigEnvironmentSource.ContentModels
  }
  private let identity = UUID()
  private let environment: WebsiteConfigEnvironmentSource
  private var readWindow: (@MainActor () -> Window?)?
  private var reading = false

  init(environment: WebsiteConfigEnvironmentSource, readWindow: @escaping @MainActor () -> Window?) {
    self.environment = environment; self.readWindow = readWindow
  }
  func stop() { readWindow = nil }
  func withReceiptRead<T>(_ body: () throws -> T) rethrows -> T {
    try environment.withSynchronousSetterRead(body)
  }

  func capture(owner: UUID, preserving previous: WebsiteConfigSessionBuilder.Scope) throws -> Snapshot {
    guard !reading, let context = environment.read(), let readWindow else {
      throw WebsiteConfigPracticeScopeSourceError.unavailable
    }
    reading = true; defer { reading = false }
    let models = environment.contentModels()
    guard let window = readWindow() else { throw WebsiteConfigPracticeScopeSourceError.unavailable }
    guard window.owner == owner else { throw WebsiteConfigPracticeScopeSourceError.wrongOwner }
    var scope = previous
    // Replace every content field, retaining only the page's live books and
    // its value-owned quote queue (the builder still checks catalog identity).
    scope.parameterMemory = window.parameterMemory
    scope.selectedQuoteID = window.selectedQuoteID
    scope.favoriteQuoteIDs = window.favorites == .nativeLocal ? models.localFavorites : nil
    scope.customText = ""; scope.preparedCustomSections = nil; scope.finiteTextSource = nil
    scope.customTextIsPrepared = false; scope.customTextRecoveryBlocked = true
    scope.customCompletion = .finish; scope.customOrdering = .inOrder; scope.customPipeDelimiter = nil
    scope.customDurationOverride = nil
    scope.websiteCustomText = nil
    let document: CustomTextStateDocument?
    switch window.custom {
    case .stored:
      switch models.websiteCustom {
      case .missing: document = models.custom.document
      case .unavailable: document = nil
      case .available(let value):
        document = nil; scope = value.applying(to: scope)
        scope.customTextRecoveryBlocked = scope.customTextRecoveryBlocked || window.customRecoveryBlocked
      }
    case .website(let value):
      guard (try? WebsiteCustomTextSettings(value: value.value)) != nil else { throw WebsiteConfigPracticeScopeSourceError.invalidContent }
      document = nil; scope = value.applying(to: scope)
      scope.customTextRecoveryBlocked = scope.customTextRecoveryBlocked || window.customRecoveryBlocked
    case .explicit(let value, let finite, let prepared, let blocked):
      document = value; scope.finiteTextSource = finite
      scope.customTextIsPrepared = prepared
      scope.customTextRecoveryBlocked = blocked || window.customRecoveryBlocked
    case .timed(let content):
      guard content.seconds.isFinite, content.seconds >= 0,
        content.seconds <= Double(OfficialTestLimitInput.maximumValue) else {
        throw WebsiteConfigPracticeScopeSourceError.invalidContent
      }
      let configuration = TestConfiguration(mode: .custom, duration: content.seconds, wordLimit: nil,
        difficulty: .normal, rules: .init(), customTextCompletion: .time)
      let textReady: Bool
      if let corpus = content.corpus {
        textReady = CustomTextPolicy.isValid(corpus, configuration: configuration)
      } else {
        switch content.source {
        case .editor(let text):
          textReady = CustomTextPolicy.isValid(text, configuration: configuration)
        case .prepared(let sections):
          textReady = !sections.isEmpty
        }
      }
      document = nil
      scope.customText = content.corpus ?? content.source.text
      scope.preparedCustomSections = content.corpus == nil
        ? content.source.preparedSections(matching: content.source.text) : nil
      scope.customTextIsPrepared = content.preservesSpelling
      scope.customCompletion = .time; scope.customDurationOverride = content.seconds
      scope.customOrdering = content.ordering; scope.customPipeDelimiter = content.pipeDelimiter
      scope.customTextRecoveryBlocked = !textReady || content.recoveryBlocked || window.customRecoveryBlocked
    }
    // A valid finite finish stream owns its text independently of a preview.
    // Invalid dormant custom content instead blocks custom generation only;
    // it must not prevent an unrelated ordinary-word attempt.
    let finiteFinishReady = document.map {
      scope.finiteTextSource?.isEmpty == false && $0.version == CustomTextStateDocument.currentVersion
        && $0.completion == .finish && !$0.configuration.usesCustomTextPipeDelimiter
        && SettingsJSONConfigurationPolicy.isValid($0.configuration)
    } ?? false
    if let document, document.isValid || finiteFinishReady {
      scope.customText = document.source.text
      scope.preparedCustomSections = document.source.preparedSections(matching: document.source.text)
      scope.customCompletion = document.completion; scope.customOrdering = document.ordering
      scope.customPipeDelimiter = document.pipeDelimiter
      if case .stored = window.custom { scope.customTextRecoveryBlocked = window.customRecoveryBlocked }
      let memory = window.parameterMemory
      func duration(_ value: Double?) throws -> Int {
        guard let value else { return memory.customTextDuration }
        guard value.isFinite, value.rounded(.towardZero) == value,
          value >= 0, value <= Double(OfficialTestLimitInput.maximumValue) else {
          throw WebsiteConfigPracticeScopeSourceError.invalidContent
        }
        return Int(value)
      }
      scope.parameterMemory = .init(duration: memory.duration, wordLimit: memory.wordLimit,
        customTextDuration: try duration(document.duration), customTextWordLimit: document.wordLimit ?? memory.customTextWordLimit,
        customTextSectionLimit: document.sectionLimit ?? memory.customTextSectionLimit)
    } else if document != nil {
      scope.customTextRecoveryBlocked = true
    }
    let snapshot = Snapshot(scope: scope, environment: context, source: identity, window: window, models: models)
    guard matches(snapshot) else { throw WebsiteConfigPracticeScopeSourceError.stale }
    return snapshot
  }
  func isCurrent(_ snapshot: Snapshot) -> Bool {
    guard !reading else { return false }
    reading = true; defer { reading = false }
    return matches(snapshot)
  }
  /// An accepted receipt's own website-custom writes rotate the ordinary
  /// environment. They must not authorize crossing account/window epochs.
  func ownsReceiptIdentity(_ snapshot: Snapshot) -> Bool {
    guard snapshot.source == identity, let window = readWindow?(), window.owner == snapshot.window.owner,
      window.revision == snapshot.window.revision else { return false }
    let current = environment.contentModels()
    return current.custom == snapshot.models.custom && current.customGeneration == snapshot.models.customGeneration
      && current.localFavorites == snapshot.models.localFavorites && current.accountScope == snapshot.models.accountScope
      && current.accountGeneration == snapshot.models.accountGeneration
  }
  /// Before the native receipt is installed, its actual editor/control window
  /// must still match. Its own website-cache writes may rotate the environment.
  func ownsNativeReceiptWindow(_ snapshot: Snapshot) -> Bool {
    ownsReceiptIdentity(snapshot) && readWindow?() == snapshot.window
  }
  private func matches(_ snapshot: Snapshot) -> Bool {
    guard snapshot.source == identity, readWindow != nil, environment.read() == snapshot.environment,
      environment.contentModels() == snapshot.models, let window = readWindow?(), window == snapshot.window else { return false }
    return readWindow != nil && environment.read() == snapshot.environment && environment.contentModels() == snapshot.models
  }
}
