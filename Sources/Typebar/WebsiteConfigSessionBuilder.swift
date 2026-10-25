import Foundation

enum WebsiteConfigSessionBuildError: Error, LocalizedError {
  /// Emitted only by quote selection, distinct from other reconfiguration
  /// requests or a content reader's ordinary error.
  case quoteRecoveryRequired(WebsiteQuoteSampler.Recovery)
  case quoteRecoveryLimitReached
  case reconfigurationRequired([String: WebsiteConfigValue])
  case unrepresentableConfiguration, customTextUnavailable, externalNotProvided, invalidExternalSource, generationFailed
  case repeatedConfigurationUnsupported
  var errorDescription: String? {
    if case .quoteRecoveryLimitReached = self {
      return "引语初始化已尝试三次，仍未找到可用内容。请检查引语来源，或在导入面板恢复配置。"
    }
    return nil
  }
}

/// Whole-draft generation with explicit window/account content scope. No
/// preference mutation, resource activation, record write or page installation.
@MainActor enum WebsiteConfigSessionBuilder {
  enum Reason: Equatable {
    /// Continue already-applied settings without replaying their setter events.
    case nextAttempt
    /// Apply this draft's events once to a candidate scope before generation.
    case configurationApplication
  }
  enum AttemptSource {
    case selection
    /// Owned raw quote, not the previous transformed display or a catalog ID.
    case repeatedQuote(OfflineQuote, repeatedPace: Bool)
    case repeatedWords(GeneratedWordReplayHistory, repeatedPace: Bool)
  }
  struct Scope {
    var parameterMemory: TypebarTestParameterMemory = .defaults
    var customText = ""
    var customTextIsPrepared = false
    var preparedCustomSections: [String]? = nil
    var finiteTextSource: String? = nil
    var customCompletion: CustomTextCompletion = .finish
    /// Exact transient source duration, separate from legacy integer controls.
    var customDurationOverride: TimeInterval? = nil
    var customOrdering: CustomTextOrdering = .inOrder
    var customPipeDelimiter: Bool? = nil
    var customTextRecoveryBlocked = false
    var selectedQuoteID: String? = nil
    var favoriteQuoteIDs: [String]? = nil
    var quoteSampler: WebsiteQuoteSampler? = nil
    var weakSpotScores: WeakSpotScores = .init()
    var decorationState: PoolWordDecorationState = .init()
    var arrowChart: WebsiteArrowChart = .init()
  }
  struct Random {
    var wordIndex: () -> Int = { Int.random(in: Int.min...Int.max) }
    var caseBit: () -> Bool = { Bool.random() }
    var contentUnit: () -> Double = { Double.random(in: 0..<1) }
    var shuffleIndex: (Int) -> Int = { Int.random(in: 0..<$0) }
    var quoteIndex: (Int) -> Int = { Int.random(in: 0..<$0) }
  }
  struct External {
    let source: LivePracticeContentSource
    let initial: LivePracticePrompt
    let continuation: LivePracticePrompt?
    var attribution: String? = nil
  }
  struct Prepared {
    let session: TypingSession
    let scope: Scope
    let quote: OfflineQuote?
    let external: External?
    let repetition: WebsitePracticeRepetition
    init(session: TypingSession, scope: Scope, quote: OfflineQuote?, external: External?,
      repetition: WebsitePracticeRepetition = .none) {
      self.session = session; self.scope = scope; self.quote = quote
      self.external = external; self.repetition = repetition
    }
    /// A value-owned post-draw queue. Install only after successful commit.
    var quoteSampler: WebsiteQuoteSampler? { scope.quoteSampler }
    var parameterMemory: TypebarTestParameterMemory { scope.parameterMemory }
  }
  static func prepare(draft: WebsiteConfigNativeDraft, scope: Scope,
    reason: Reason = .nextAttempt,
    attemptSource: AttemptSource = .selection,
    loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) },
    loadExternal: (@MainActor (LivePracticeContentSource, TestConfiguration) async throws -> External)? = nil,
    random: Random = .init()) async throws -> Prepared {
    try Task.checkCancellation()
    let config = try configuration(draft: draft, scope: scope)
    let liveSource = LivePracticeContentSource.selected(for: config)
    if liveSource == nil && (config.modifiers.contains(.poetryStream) || config.modifiers.contains(.referenceStream)) {
      throw WebsiteConfigSessionBuildError.unrepresentableConfiguration
    }
    var nextScope = scope
    // The actual source listener rebuilds for every quoteLength setter event,
    // including identical arrays and nosave=true. Other events do not reset it.
    // Keep this candidate value-owned so cancellation/failure cannot advance or
    // clear the caller's already-installed queue.
    if reason == .configurationApplication,
      draft.projection.events.contains(where: { $0.key == "quoteLength" }) {
      nextScope.quoteSampler = nil
    }
    nextScope.parameterMemory = draft.testParameters.parameterMemory(preserving: scope.parameterMemory)
    var selectedQuote: OfflineQuote?
    var selectedExternal: External?
    let repetition: WebsitePracticeRepetition
    var wordHistory: GeneratedWordReplayHistory?
    switch attemptSource {
    case .selection: repetition = .none
    case .repeatedQuote(let quote, let repeatedPace):
      guard config.mode == .quote, liveSource == nil else {
        throw WebsiteConfigSessionBuildError.repeatedConfigurationUnsupported
      }
      selectedQuote = quote
      repetition = .sameWordset(repeatedPace: repeatedPace)
    case .repeatedWords(let history, let repeatedPace):
      guard [.words, .time].contains(config.mode), liveSource == nil,
        history.count > 0, history.noSpace == TestModifierPolicy.usesNoSpaceInput(config.modifiers),
        (WebsiteRandomWordGenerator.usesCandidateStream(for: config)
          || TypebarStreamContent.prompt(configuration: config, wordCount: 1) == nil) else {
        throw WebsiteConfigSessionBuildError.repeatedConfigurationUnsupported
      }
      wordHistory = history
      repetition = .sameWordset(repeatedPace: repeatedPace)
    }
    if config.mode == .quote && selectedQuote == nil {
      let catalog = try await read { try await loadQuotes(draft.testParameters.language) }
      var sampler: WebsiteQuoteSampler
      if let previous = nextScope.quoteSampler, previous.matches(selection: draft.quoteSelection, quotes: catalog) {
        sampler = previous
      } else { sampler = try .init(selection: draft.quoteSelection, quotes: catalog) }
      switch try sampler.next(selectedQuoteID: scope.selectedQuoteID, favoriteIDs: scope.favoriteQuoteIDs,
        randomIndex: random.quoteIndex) {
      case .quote(let quote): selectedQuote = quote
      case .unavailable(_, let recovery):
        throw WebsiteConfigSessionBuildError.quoteRecoveryRequired(recovery)
      }
      nextScope.quoteSampler = sampler
    }
    let showAllLines = draft.presentation.showAllPracticeLines
    let pseudolangModel = try await WebsitePseudolangModel.preparing(configuration: config)
    let session: TypingSession
    if let wordHistory {
      session = try await prepareWordReplay(configuration: config, history: wordHistory,
        scope: scope, showAllLines: showAllLines, random: random, pseudolangModel: pseudolangModel)
    } else if let source = liveSource {
      guard let loadExternal else { throw WebsiteConfigSessionBuildError.externalNotProvided }
      let external = try await read { try await loadExternal(source, config) }
      guard external.source == source, !external.initial.text.isEmpty else {
        throw WebsiteConfigSessionBuildError.invalidExternalSource
      }
      selectedExternal = external
      session = try await TestSessionFactory.preparingLiveSession(configuration: config,
        prompt: external.initial, continuation: external.continuation,
        weakSpotScores: scope.weakSpotScores, wordDecorationState: scope.decorationState,
        showAllLines: showAllLines, nextRandomCaseBit: random.caseBit)
    } else if WholePreviewWordPreparation.usesAsyncPreparation(configuration: config, showAllLines: showAllLines) {
      session = try await WholePreviewWordPreparation.prepareSession(configuration: config,
        weakSpotScores: scope.weakSpotScores, wordDecorationState: scope.decorationState, arrowChart: scope.arrowChart,
        pseudolangModel: pseudolangModel,
        nextRandomWordIndex: random.wordIndex, nextRandomCaseBit: random.caseBit,
        nextRandomContentUnit: random.contentUnit, nextRandomPoolShuffleIndex: random.shuffleIndex)
    } else {
      if config.mode == .custom {
        guard !scope.customTextRecoveryBlocked,
          scope.finiteTextSource?.isEmpty == false || scope.preparedCustomSections?.isEmpty == false
            || CustomTextPolicy.isValid(scope.customText, configuration: config)
        else { throw WebsiteConfigSessionBuildError.customTextUnavailable }
      }
      session = TestSessionFactory.make(configuration: config, customText: scope.customText,
        customTextIsPrepared: scope.customTextIsPrepared, preparedCustomSections: scope.preparedCustomSections,
        finiteTextSource: scope.finiteTextSource, quote: selectedQuote,
        weakSpotScores: scope.weakSpotScores, wordDecorationState: scope.decorationState, arrowChart: scope.arrowChart,
        pseudolangModel: pseudolangModel,
        showAllLines: showAllLines, nextRandomWordIndex: random.wordIndex, nextRandomCaseBit: random.caseBit,
        nextRandomContentUnit: random.contentUnit, nextRandomPoolShuffleIndex: random.shuffleIndex)
    }
    try Task.checkCancellation()
    guard !session.hasStarted, !session.isFinished, config.mode == .zen || !session.prompt.isEmpty else {
      throw WebsiteConfigSessionBuildError.generationFailed
    }
    nextScope.arrowChart = session.generatedWordReplayHistory?.arrowChart ?? scope.arrowChart
    return .init(session: session, scope: nextScope, quote: selectedQuote, external: selectedExternal,
      repetition: repetition)
  }

  private static func prepareWordReplay(configuration: TestConfiguration, history: GeneratedWordReplayHistory,
    scope: Scope, showAllLines: Bool, random: Random, pseudolangModel: WebsitePseudolangModel?) async throws -> TypingSession {
    let preparation = PolyglotGenerationPreparation(configuration)
    var config = preparation.configuration
    if config.language == .dockerFile { config.dockerfileUsesLiteralIndentation = true }
    let count = GeneratedPromptChunkPolicy.wordCount(for: config, showAllLines: showAllLines)
    var history = history
    history.arrowChart = scope.arrowChart
    var cursor = GeneratedCandidateContinuation(configuration: config, batchTokenCount: 100,
      showAllLines: showAllLines, weakSpotScores: scope.weakSpotScores,
      decorationState: scope.decorationState, pseudolangModel: pseudolangModel, replayHistory: history,
      nextRandomPoolShuffleIndex: random.shuffleIndex)
    var chunks: [GeneratedWordChunk] = []
    var prepared = 0
    while prepared < count {
      try Task.checkCancellation()
      let size = min(100, count - prepared)
      let chunk = cursor.nextChunk(maximumWordCount: size, initialPreparationWordBound: count,
        nextRandomWordIndex: random.wordIndex, nextRandomCaseBit: random.caseBit, nextRandomContentUnit: random.contentUnit)
      guard !chunk.source.isEmpty else { throw WebsiteConfigSessionBuildError.generationFailed }
      chunks.append(chunk); prepared += size
      await Task.yield()
    }
    let assembled = try await WholePreviewChunkAssembly.assemble(chunks)
    let batch = TransformedPromptBatch(text: assembled.prompt, noSpaceTargetWords: assembled.targetWords)
    let finalized = cursor.hasRemaining ? batch : FinitePromptCommitPolicy.finalized(batch)
    let needsCommit = cursor.hasRemaining && !history.noSpace
      && finalized.text.last != " " && finalized.text.last != "\n"
    try Task.checkCancellation()
    return .init(configuration: config, prompt: finalized.text + (needsCommit ? " " : ""),
      generatedCodeContinuation: cursor.hasRemaining ? cursor : nil, generatedReplayHistory: cursor.replayHistory,
      noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(for: finalized.noSpaceWordLengths),
      noSpaceTargetWords: finalized.noSpaceTargetWords,
      generationNotice: preparation.notice, weakSpotScores: scope.weakSpotScores, wordDecorationState: cursor.decorationState)
  }

  private static func read<Value>(_ operation: @MainActor () async throws -> Value) async throws -> Value {
    try Task.checkCancellation()
    let result: Result<Value, Error>
    do { result = .success(try await operation()) } catch { result = .failure(error) }
    try Task.checkCancellation()
    return try result.get()
  }

  private static func configuration(draft: WebsiteConfigNativeDraft, scope: Scope) throws -> TestConfiguration {
    guard [scope.parameterMemory.customTextDuration, scope.parameterMemory.customTextWordLimit,
      scope.parameterMemory.customTextSectionLimit].allSatisfy({ (0...OfficialTestLimitInput.maximumValue).contains($0) })
    else { throw WebsiteConfigSessionBuildError.unrepresentableConfiguration }
    if let duration = scope.customDurationOverride,
      !duration.isFinite || duration < 0 || duration > Double(OfficialTestLimitInput.maximumValue) {
      throw WebsiteConfigSessionBuildError.unrepresentableConfiguration
    }
    var config = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: scope.customCompletion, customTextSectionLimit: scope.parameterMemory.customTextSectionLimit,
      customTextOrdering: scope.customOrdering, customTextPipeDelimiter: scope.customPipeDelimiter)
    config = draft.testParameters.applying(to: config, parameterMemory: scope.parameterMemory)
    if config.mode == .custom, scope.customCompletion == .time, let duration = scope.customDurationOverride {
      config.duration = duration
    }
    config = draft.inputRules.applying(to: draft.behavior.applying(to: config))
    if draft.generators.requestsPolyglot {
      let languages = draft.generators.polyglotLanguages
      if languages.allSatisfy({ $0.usesRightToLeftPrompt != config.language.usesRightToLeftPrompt }),
        let first = languages.first, let name = WebsiteLanguageIdentity.name(for: first) {
        throw WebsiteConfigSessionBuildError.reconfigurationRequired(["language": .string(name)])
      }
      guard TypingLanguage.normalizedMixedComponents(languages) == languages else {
        throw WebsiteConfigSessionBuildError.unrepresentableConfiguration
      }
      config.language = .mixedLanguages
      config.mixedLanguageComponents = languages
      config = config.with(polyglotBaseLanguage: draft.testParameters.language)
    }
    let requested = draft.generators.requestedModifiers
    config = config.with(modifiers: requested)
    guard config.mode == draft.testParameters.mode, Set(config.modifiers) == Set(requested),
      config.contentOptions == draft.testParameters.contentOptions else {
      throw WebsiteConfigSessionBuildError.unrepresentableConfiguration
    }
    config = try draft.generators.applyingTextOrder(to: config)
    let groups = Set(draft.quoteSelection.groups.compactMap { group in
      QuoteLength.allCases.first { $0.compatibilityValue == String(group) }
    })
    config.quoteLengths = groups.isEmpty ? nil : groups
    config.quoteLength = groups.isEmpty ? .all : QuoteLengthSelection.legacyValue(for: groups)
    switch draft.quoteSelection.route {
    case .lengths: config.quoteSelectionMode = .lengths
    case .selectedQuote: config.quoteSelectionMode = .search
    case .favorites: config.quoteSelectionMode = .favorites
    }
    return config
  }
}
