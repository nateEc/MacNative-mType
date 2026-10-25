import Foundation

/// Window-owned practice actions. Threshold setters retain the attempt;
/// restarting actions require an actual source dispatch/subscription, not
/// merely the metadata's broader changeRequiresRestart flag.
enum WebsiteConfigPracticeEdit: Equatable {
  case mode(TestMode), time(Double), words(Double)
  case difficulty(Difficulty), punctuation(Bool), numbers(Bool), quoteLengths([Int])
  case language(String), lazyMode(Bool)
  case funboxes([String])
  case polyglotLanguages([String])
  case layoutFluidLayouts([String])
  case threshold(WebsiteConfigThresholdEdit)
  case behavior(BehaviorCommandTarget)
  case inputRule(InputRuleCommandTarget)
  case sound(SoundCommandTarget)
  var key: String {
    switch self {
    case .mode: "mode"; case .time: "time"; case .words: "words"
    case .difficulty: "difficulty"; case .punctuation: "punctuation"; case .numbers: "numbers"
    case .quoteLengths: "quoteLength"
    case .language: "language"; case .lazyMode: "lazyMode"
    case .funboxes: "funbox"
    case .polyglotLanguages: "customPolyglot"
    case .layoutFluidLayouts: "customLayoutfluid"
    case .threshold(let edit): edit.key
    case .behavior(let edit): edit.websiteKey
    case .inputRule(let edit): edit.websiteKey
    case .sound(let edit): edit.websiteKey
    }
  }
  var value: WebsiteConfigValue {
    switch self {
    case .mode(let mode): .string(mode.rawValue)
    case .time(let value), .words(let value): .number(value)
    case .difficulty(let value): .string(value.rawValue)
    case .punctuation(let value), .numbers(let value): .bool(value)
    case .quoteLengths(let groups): .array(groups.map { .number(Double($0)) })
    case .language(let value): .string(value)
    case .lazyMode(let value): .bool(value)
    case .funboxes(let values): .array(values.map(WebsiteConfigValue.string))
    case .polyglotLanguages(let values): .array(values.map(WebsiteConfigValue.string))
    case .layoutFluidLayouts(let values): .array(values.map(WebsiteConfigValue.string))
    case .threshold(let edit): edit.value
    case .behavior(let edit): edit.websiteValue
    case .inputRule(let edit): edit.websiteValue
    case .sound(let edit): edit.websiteValue
    }
  }
  /// TestConfig controls dispatch after a false setter return; difficulty
  /// restarts only from its successful setter event. A thrown override is
  /// neither case: execution never reaches the following dispatch.
  var dispatchesRestartAfterRejection: Bool {
    switch self {
    case .difficulty, .language, .layoutFluidLayouts, .threshold, .behavior, .inputRule, .sound: false
    case .mode, .time, .words, .punctuation, .numbers, .quoteLengths, .lazyMode, .funboxes, .polyglotLanguages: true
    }
  }
}

enum WebsiteConfigImportWorkflowError: Error, LocalizedError {
  case missing, typebarBackup, activeAttempt, unavailable, busy, conflict, unsupportedPractice, rejectedRestartFailed
  case preparationPending
  var errorDescription: String? {
    switch self {
    case .missing: "还没有保存的 Monkeytype 配置；请先粘贴配置 JSON。"
    case .typebarBackup: "这是 Typebar 备份，请使用“导入设置 JSON”。"
    case .activeAttempt: "请先结束当前练习，再导入或恢复完整配置。"
    case .unavailable: "配置记录或窗口当前不可用；未知记录不会被覆盖，请检查后重试。"
    case .busy: "上一项资源准备仍未结束，请稍后重试。"
    case .conflict: "配置或窗口已变化，未应用这次准备；请重新导入。"
    case .unsupportedPractice: "请先退出挑战或单词专项练习，再导入完整配置。"
    case .rejectedRestartFailed: "设置未修改；重开未完成，请检查窗口或锁定状态后重试。已接受的旧尝试不会重复记账。"
    case .preparationPending:
      "设置已保存，新练习尚未准备完成。请继续准备；如果窗口或配置已变化，请在导入面板恢复配置。"
    }
  }
}

/// Retain the diagnostic without making a failed initializer look like a
/// rejected setter. The durable setting and departure have already succeeded.
struct WebsiteConfigSavedPreparationError: Error, LocalizedError {
  let underlying: Error
  let initializationMessage: String?
  let configurationWasSaved: Bool
  init(underlying: Error, initializationMessage: String? = nil, configurationWasSaved: Bool = true) {
    self.underlying = underlying; self.initializationMessage = initializationMessage
    self.configurationWasSaved = configurationWasSaved
  }
  var errorDescription: String? {
    if !configurationWasSaved {
      return "可恢复的临时设置已恢复，趣味模式选择未保存。新练习尚未准备完成，可继续准备。" + (initializationMessage ?? "")
    }
    if let initializationMessage {
      return "设置已保存，新练习尚未完成。" + initializationMessage + " 可继续准备，已接纳的旧尝试不会重复记账。"
    }
    if case WebsiteConfigSessionBuildError.quoteRecoveryLimitReached = underlying {
      return "设置校正已保存。" + underlying.localizedDescription
    }
    return WebsiteConfigImportWorkflowError.preparationPending.errorDescription
  }
}

/// Window-owned whole-application workflow. Does not mutate legacy preferences
/// or silently substitute another text provider. Restarting setters use durable
/// departure; thresholds retain the attempt, and imports protect active tests.
@MainActor final class WebsiteConfigImportWorkflow {
  private weak var page: PracticePageSessionStore?
  private let settings: AppSettings
  private let environment: WebsiteConfigEnvironmentSource
  private let source: WebsiteConfigPracticeScopeSource
  private let coordinator: WebsiteConfigCommitCoordinator
  private let loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote]
  private weak var notices: LocalNoticeCenter?
  private var prepared: WebsiteConfigCommitCoordinator.Prepared?
  private var rejectedRestart: (controller: WebsitePracticeRestartController, request: UUID)?
  private var applying = false
  private var stopped = false
  private var operation = UUID()
  private enum Intent { case application(String?), edit(WebsiteConfigPracticeEdit, UUID), resume(UUID) }

  init(page: PracticePageSessionStore, settings: AppSettings, account: AccountSession,
    directory: URL, readWindow: @escaping @MainActor () -> WebsiteConfigPracticeScopeSource.Window?,
    loadExternal: WebsiteConfigSessionBuilder.ExternalLoader? = nil,
    loadQuotes: @escaping @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) }) {
    self.page = page; self.settings = settings; self.loadQuotes = loadQuotes
    self.notices = account.localNotices
    let environment = WebsiteConfigEnvironmentSource(settings: settings, account: account,
      pointsPerRem: 16, documentComplete: true, development: false)
    self.environment = environment
    source = .init(environment: environment, readWindow: readWindow)
    coordinator = .init(router: settings.preferenceConfigurationSaves, register: .init(directory: directory),
      loadExternal: loadExternal,
      environment: { [environment] in environment.read() })
  }

  /// nil selects explicit native-record restoration, never an empty import.
  @discardableResult
  func apply(json: String?, systemIsDark: Bool) async throws -> String {
    try await perform(.application(json), systemIsDark: systemIsDark)
  }

  @discardableResult
  func editAndBegin(_ edit: WebsiteConfigPracticeEdit, replacing applicationID: UUID, systemIsDark: Bool) async throws -> String {
    if case .behavior = edit { return try runSingleLiveCommand(edit, replacing: applicationID) }
    if case .sound(let target) = edit {
      guard target.websiteValue != .null else { throw WebsiteSoundCommandError.unsupportedTone }
      return try runSingleLiveCommand(edit, replacing: applicationID)
    }
    if case .inputRule(let target) = edit {
      if case .lazyMode(let enabled) = target { return try await perform(.edit(.lazyMode(enabled), applicationID), systemIsDark: systemIsDark) }
      return try runInputCommand(target, replacing: applicationID)
    }
    return try await perform(.edit(edit, applicationID), systemIsDark: systemIsDark)
  }

  private func runSingleLiveCommand(_ edit: WebsiteConfigPracticeEdit, replacing applicationID: UUID) throws -> String {
    guard !stopped, let page else { throw WebsiteConfigImportWorkflowError.unavailable }
    guard !applying, page.restartController?.isPreparing != true else { throw WebsiteConfigImportWorkflowError.busy }
    guard page.state.savedApplication == nil, page.state.configurationDeparture == nil else {
      throw WebsiteConfigImportWorkflowError.preparationPending
    }
    guard page.state.presentation?.publication.applicationID == applicationID else { throw WebsiteConfigImportWorkflowError.conflict }
    try Task.checkCancellation()
    let current = UUID(); applying = true; operation = current
    defer {
      if let prepared { _ = coordinator.cancel(prepared) }
      prepared = nil; applying = false
    }
    return try environment.withSynchronousSetterRead {
      let ticket = try coordinator.prepareEdit(key: edit.key, value: edit.value, for: page, refreshingWith: source)
      prepared = ticket
      try Task.checkCancellation()
      guard operation == current, !stopped else { throw CancellationError() }
      let outcome: WebsiteConfigCommitCoordinator.Outcome
      if case .sound = edit { outcome = try coordinator.commitLiveSound(ticket, for: page) }
      else { outcome = try coordinator.commitLiveBehavior(ticket, for: page) }
      switch outcome {
      case .committed: return "设置已保存，当前练习继续。"
      case .stale, .conflict: throw WebsiteConfigImportWorkflowError.conflict
      case .unavailable: throw WebsiteConfigImportWorkflowError.unavailable
      case .busy: throw WebsiteConfigImportWorkflowError.busy
      }
    }
  }

  private func runInputCommand(_ target: InputRuleCommandTarget, replacing applicationID: UUID) throws -> String {
    guard !stopped, let page else { throw WebsiteConfigImportWorkflowError.unavailable }
    guard !applying, page.restartController?.isPreparing != true else { throw WebsiteConfigImportWorkflowError.busy }
    guard page.state.savedApplication == nil, page.state.configurationDeparture == nil else { throw WebsiteConfigImportWorkflowError.preparationPending }
    guard let original = page.state.presentation?.publication, original.applicationID == applicationID else { throw WebsiteConfigImportWorkflowError.conflict }
    try Task.checkCancellation()
    let current = UUID(); applying = true; operation = current
    let noticeGeneration = notices?.deliveryGeneration
    defer {
      if let prepared { _ = coordinator.cancel(prepared) }
      prepared = nil; applying = false
    }
    func execute() throws -> String {
      guard let context = environment.read() else { throw WebsiteConfigCommitCoordinatorError.noEnvironment }
      let plan = try WebsiteConfigInputCommand.plan(current: original.draft.projection.runtime, target: target,
        context: context.context, active: page.state.session.hasStarted && !page.state.session.isFinished)
      var receiptID = applicationID, saved = 0
      do {
        for step in plan.steps {
          try Task.checkCancellation()
          guard operation == current, !stopped, page.state.presentation?.publication.applicationID == receiptID else { throw WebsiteConfigImportWorkflowError.conflict }
          if !step.accepted {
            if ownsActiveNoQuit, WebsiteConfigRuntimeProjector.restartRequiredKeys.contains(step.key),
              let publication = page.state.presentation?.publication {
              postNoQuitSelectionNotice("输入规则未修改；No Quit 保留当前练习。", publication: publication,
                page: page, operation: current, noticeGeneration: noticeGeneration, expectedEnvironment: context.revision)
            }
            continue
          }
          let ticket = try coordinator.prepareEdit(key: step.key, value: step.value, for: page, refreshingWith: source)
          prepared = ticket
          guard operation == current, !stopped else { throw CancellationError() }
          switch try coordinator.commitLiveInputRule(ticket, for: page) {
          case .committed(let publication): saved += 1; receiptID = publication.applicationID
          case .stale, .conflict: throw WebsiteConfigImportWorkflowError.conflict
          case .unavailable: throw WebsiteConfigImportWorkflowError.unavailable
          case .busy: throw WebsiteConfigImportWorkflowError.busy
          }
        }
      } catch {
        if saved > 0 { throw WebsiteInputCommandError.interrupted(saved: saved, underlying: error) }
        throw error
      }
      if plan.failedOverride { throw WebsiteInputCommandError.failedOverride(saved: saved) }
      return saved == 0 ? "输入规则未修改。" : "输入规则已保存，当前练习继续。"
    }
    if ownsActiveNoQuit { return try environment.withSynchronousSetterRead { try execute() } }
    return try execute()
  }

  /// Execute the source command synchronously. Burst's two ordinary setters
  /// have separate durable effects; neither rejection nor a later write error
  /// rolls back an already accepted mode setter.
  func runThresholdCommand(_ target: PracticeThresholdCommandTarget, input: String,
    replacing applicationID: UUID) throws -> WebsiteThresholdCommandReceipt {
    if ownsActiveNoQuit {
      return try environment.withSynchronousSetterRead {
        try executeThresholdCommand(target, input: input, replacing: applicationID)
      }
    }
    return try executeThresholdCommand(target, input: input, replacing: applicationID)
  }
  private var ownsActiveNoQuit: Bool {
    guard let session = page?.state.session else { return false }
    return session.hasStarted && !session.isFinished && session.configuration.modifiers.contains(.noQuit)
  }
  private func executeThresholdCommand(_ target: PracticeThresholdCommandTarget, input: String,
    replacing applicationID: UUID) throws -> WebsiteThresholdCommandReceipt {
    guard !stopped, let page else { throw WebsiteConfigImportWorkflowError.unavailable }
    guard !applying, page.restartController?.isPreparing != true else { throw WebsiteConfigImportWorkflowError.busy }
    guard page.state.savedApplication == nil, page.state.configurationDeparture == nil else {
      throw WebsiteConfigImportWorkflowError.preparationPending
    }
    guard let publication = page.state.presentation?.publication, publication.applicationID == applicationID else {
      throw WebsiteConfigImportWorkflowError.conflict
    }
    try Task.checkCancellation()
    guard let edits = WebsiteThresholdCommandInput.edits(for: target, raw: input,
      unit: publication.draft.presentation.typingSpeedUnit) else { throw WebsiteThresholdCommandError.invalidInput }
    applying = true
    let current = UUID(); operation = current
    let noticeGeneration = notices?.deliveryGeneration
    var accepted = 0, rejected: [String] = [], receiptID = applicationID
    defer {
      if let prepared { _ = coordinator.cancel(prepared) }
      prepared = nil; applying = false
    }
    do {
      for edit in edits {
        try Task.checkCancellation()
        guard operation == current, !stopped else { throw CancellationError() }
        guard page.state.presentation?.publication.applicationID == receiptID else {
          throw WebsiteConfigImportWorkflowError.conflict
        }
        do {
          let ticket = try coordinator.prepareEdit(key: edit.key, value: edit.value, for: page, refreshingWith: source)
          prepared = ticket
          guard operation == current, !stopped else { throw CancellationError() }
          switch try coordinator.commitLiveThreshold(ticket, for: page) {
          case .committed(let updated): accepted += 1; receiptID = updated.applicationID
          case .stale, .conflict: throw WebsiteConfigImportWorkflowError.conflict
          case .unavailable: throw WebsiteConfigImportWorkflowError.unavailable
          case .busy: throw WebsiteConfigImportWorkflowError.busy
          }
        } catch WebsiteConfigNativeDraftError.rejectedEdit {
          rejected.append(edit.key)
          if page.state.session.hasStarted, !page.state.session.isFinished,
            page.state.session.configuration.modifiers.contains(.noQuit), let publication = page.state.presentation?.publication {
            postNoQuitSelectionNotice("阈值未修改；No Quit 保留当前练习。", publication: publication,
              page: page, operation: current, noticeGeneration: noticeGeneration,
              expectedEnvironment: environment.read()?.revision)
          }
        }
      }
    } catch {
      if accepted > 0 { throw WebsiteThresholdCommandError.partiallySaved(error) }
      throw error
    }
    return .init(publicationID: receiptID, acceptedSetters: accepted, rejectedKeys: rejected)
  }

  @discardableResult
  func resumeAndBegin(departureID: UUID, systemIsDark: Bool) async throws -> String {
    try await perform(.resume(departureID), systemIsDark: systemIsDark)
  }
  /// Automatic pull failure, distinct from the funbox selection UI's memory
  /// restoration. The coordinator validates and derives the exact removal.
  @discardableResult
  func recoverFailedPoetry(replacing applicationID: UUID, systemIsDark: Bool) async throws -> String {
    guard case .array(let values)? = page?.state.presentation?.publication.draft.projection.runtime["funbox"] else {
      throw WebsiteConfigImportWorkflowError.unavailable
    }
    let remaining = values.compactMap { value -> String? in
      guard case .string(let name) = value, name != "poetry" else { return nil }; return name
    }
    return try await perform(.edit(.funboxes(remaining), applicationID), systemIsDark: systemIsDark, failedPoetrySource: true)
  }

  private func perform(_ intent: Intent, systemIsDark: Bool, failedPoetrySource: Bool = false) async throws -> String {
    guard !stopped, let page else { throw WebsiteConfigImportWorkflowError.unavailable }
    guard !applying else { throw WebsiteConfigImportWorkflowError.busy }
    try checkRestartBusy(intent, page: page)
    try checkIntent(intent, page: page)
    applying = true
    let current = UUID(); operation = current
    let noticeGeneration = notices?.deliveryGeneration
    defer {
      if let prepared { _ = coordinator.cancel(prepared) }
      if let rejectedRestart { rejectedRestart.controller.cancel(requestID: rejectedRestart.request) }
      rejectedRestart = nil
      prepared = nil; applying = false
    }
    try Task.checkCancellation()
    // Let a prior observed preference mutation finish its MainActor resample.
    await Task.yield()
    guard !stopped else { throw WebsiteConfigImportWorkflowError.unavailable }
    guard operation == current else { throw CancellationError() }
    try Task.checkCancellation()
    try checkRestartBusy(intent, page: page)
    try checkIntent(intent, page: page)
    var ticket: WebsiteConfigCommitCoordinator.Prepared
    switch intent {
    case .edit(let edit, let applicationID):
      guard page.state.presentation?.publication.applicationID == applicationID else {
        throw WebsiteConfigImportWorkflowError.conflict
      }
      if ownsActiveNoQuit, WebsiteConfigThresholdEdit.keys.contains(edit.key)
        || ["customPolyglot", "customLayoutfluid", "lazyMode"].contains(edit.key) {
        return try performNoQuitSelection(edit, replacing: applicationID, page: page,
          operation: current, noticeGeneration: noticeGeneration)
      }
      do {
        if failedPoetrySource { ticket = try coordinator.prepareFailedPoetrySource(for: page, refreshingWith: source) }
        else { ticket = try coordinator.prepareEdit(key: edit.key, value: edit.value, for: page, refreshingWith: source) }
      }
      catch WebsiteConfigNativeDraftError.rejectedEdit where WebsiteConfigThresholdEdit.keys.contains(edit.key) {
        if page.state.session.hasStarted, !page.state.session.isFinished,
          page.state.session.configuration.modifiers.contains(.noQuit), let publication = page.state.presentation?.publication {
          postNoQuitSelectionNotice("阈值未修改；No Quit 保留当前练习。", publication: publication,
            page: page, operation: current, noticeGeneration: noticeGeneration)
        }
        throw WebsiteConfigNativeDraftError.rejectedEdit
      }
      catch WebsiteConfigNativeDraftError.rejectedEdit where edit.key == "customLayoutfluid" {
        if page.state.session.hasStarted, !page.state.session.isFinished,
          page.state.session.configuration.modifiers.contains(.noQuit), let publication = page.state.presentation?.publication {
          postNoQuitSelectionNotice("布局序列未修改；No Quit 保留当前练习。", publication: publication,
            page: page, operation: current, noticeGeneration: noticeGeneration)
        }
        throw WebsiteConfigNativeDraftError.rejectedEdit
      }
      catch WebsiteConfigNativeDraftError.rejectedEdit where edit.dispatchesRestartAfterRejection {
        guard let controller = page.restartController else { throw WebsiteConfigImportWorkflowError.unavailable }
        rejectedRestart = (controller, current)
        let advanced = try await controller.requestAndWait(requestID: current)
        if advanced { return "设置未修改；已按原配置开始新的练习。" }
        if edit.key == "customPolyglot", page.state.session.hasStarted, !page.state.session.isFinished,
          page.state.session.configuration.modifiers.contains(.noQuit), let publication = page.state.presentation?.publication {
          postNoQuitSelectionNotice("多语组合未修改；No Quit 保留当前练习。", publication: publication,
            page: page, operation: current, noticeGeneration: noticeGeneration)
        }
        try Task.checkCancellation()
        guard operation == current, !stopped else { throw CancellationError() }
        throw WebsiteConfigImportWorkflowError.rejectedRestartFailed
      }
      if case .threshold = edit {
        prepared = ticket
        guard operation == current, !stopped else { throw CancellationError() }
        try Task.checkCancellation()
        switch try coordinator.commitLiveThreshold(ticket, for: page) {
        case .committed:
          return page.state.session.isFinished ? "阈值已保存，下一轮使用新设置。" : "阈值已保存，将用于当前练习的后续检查。"
        case .stale, .conflict: throw WebsiteConfigImportWorkflowError.conflict
        case .unavailable: throw WebsiteConfigImportWorkflowError.unavailable
        case .busy: throw WebsiteConfigImportWorkflowError.busy
        }
      }
      switch try coordinator.beginConfigurationRestart(ticket, for: page, action: edit) {
      case .accepted(let admitted): ticket = admitted
      case .futureSelectionSaved(let publication):
        let message = "多语组合已保存；No Quit 保留当前练习，下一轮使用新组合。"
        postNoQuitSelectionNotice(message, publication: publication, page: page,
          operation: current, noticeGeneration: noticeGeneration)
        return message
      case .inactiveLayoutSequenceSaved:
        return "布局序列已保存；Layoutfluid 未启用，当前练习继续。"
      case .acceptedRetired:
        if ticket.draft.projection.events.contains(where: { $0.nosave == false }) {
          return "设置已保存，但窗口已变化；请重新打开面板恢复配置。"
        }
        return "趣味模式选择未保存，窗口已变化；请重新打开面板恢复配置。"
      case .busy: throw WebsiteConfigImportWorkflowError.busy
      case .stale, .conflict: throw WebsiteConfigImportWorkflowError.conflict
      case .unavailable: throw WebsiteConfigImportWorkflowError.unavailable
      }
    case .resume:
      do { ticket = try coordinator.resumeConfigurationRestart(for: page) }
      catch is CancellationError { throw CancellationError() }
      catch { throw WebsiteConfigSavedPreparationError(underlying: error,
        configurationWasSaved: page.state.configurationDeparture?.configurationWasSaved ?? true) }
    case .application(.some(let json)):
      let fields = try WebsiteConfigJSONReader.read(json).importFields
      if fields?["version"] != nil, fields?["settings"] != nil, fields?["configuration"] != nil,
        fields?.keys.contains(where: { WebsiteConfigNativeDraft.mappedKeys.contains($0) }) == false {
        throw WebsiteConfigImportWorkflowError.typebarBackup
      }
      ticket = try coordinator.prepare(json, for: page, refreshingWith: source)
      ticket = try coordinator.acceptApplication(ticket, for: page)
    case .application(nil):
      if page.state.savedApplication != nil {
        do { ticket = try coordinator.resumeApplication(for: page) }
        catch WebsiteConfigCommitCoordinatorError.stale { ticket = try restorationTicket(for: page) }
      } else {
        ticket = try restorationTicket(for: page)
      }
    }
    prepared = ticket
    guard operation == current else { throw CancellationError() }
    let initializationReport = WebsiteConfigInitializationReport(notices: notices, lazyModeNotices: page.lazyModeNotices)
    do {
      let resources = try await coordinator.prepareResources(for: ticket, from: settings)
      let ready = try await coordinator.preparePractice(for: resources,
        initializationReport: initializationReport, loadQuotes: loadQuotes)
      try Task.checkCancellation()
      guard !stopped else { throw WebsiteConfigImportWorkflowError.unavailable }
      guard operation == current else { throw CancellationError() }
      switch try coordinator.commit(ready, to: page, systemIsDark: systemIsDark) {
      case .committed(let publication):
        let recovery = publication.quoteRecoveries.map(\.explanation).joined(separator: " ")
        let notice = recovery.isEmpty ? "" : " " + recovery
        // No await after commit. The same coordinator/content catalog owns retry.
        do {
          try page.bindRestartController(using: coordinator, notices: notices, loadQuotes: loadQuotes)
          switch intent {
          case .application(nil): return "已恢复保存的配置，新的练习已准备好。" + notice
          case .application(.some): return "配置已导入，新的练习已准备好。" + notice
          case .edit where publication.draft.projection.rejectedKeys.contains("funbox"):
            return "趣味模式选择未更改；可恢复的临时设置已恢复，新的练习已准备好。" + notice
          case .edit: return "设置已保存，新的练习已准备好。" + notice
          case .resume: return "已继续准备，新的练习已准备好。" + notice
          }
        } catch {
          // The durable commit already succeeded. Never report a rolled-back
          // import merely because an observer retired its receiving window.
          if publication.draft.projection.rejectedKeys.contains("funbox"),
            !publication.draft.projection.events.contains(where: { $0.nosave == false }) {
            return "临时设置已恢复，选择未保存；窗口已变化，重开控制未能绑定，请重新打开此面板恢复。"
          }
          return "配置已保存并应用，但窗口已变化，重开控制未能绑定；请重新打开此面板恢复。"
        }
      case .busy: throw WebsiteConfigImportWorkflowError.busy
      case .conflict, .stale: throw WebsiteConfigImportWorkflowError.conflict
      case .unavailable: throw WebsiteConfigImportWorkflowError.unavailable
      }
    } catch {
      // cancel() retires the coordinator ticket, so a late resource return can
      // report stale before our post-await operation check is reached.
      if operation != current || Task.isCancelled { throw CancellationError() }
      if !(error is CancellationError), page.state.configurationDeparture != nil || page.state.savedApplication != nil {
        throw WebsiteConfigSavedPreparationError(underlying: error, initializationMessage: initializationReport.finalMessage,
          configurationWasSaved: page.state.savedApplication != nil || (page.state.configurationDeparture?.configurationWasSaved ?? true))
      }
      if let message = initializationReport.finalMessage {
        throw WebsiteConfigInitializationExhaustedError(underlying: error, message: message)
      }
      throw error
    }
  }
  /// Never suspend inside the read scope. Threshold/Layoutfluid setters must
  /// reject; only the already validated future Polyglot path may save.
  private func performNoQuitSelection(_ edit: WebsiteConfigPracticeEdit, replacing applicationID: UUID,
    page: PracticePageSessionStore, operation current: UUID, noticeGeneration: UUID?) throws -> String {
    return try environment.withSynchronousSetterRead {
      guard ownsActiveNoQuit, operation == current, !stopped,
        let original = page.state.presentation?.publication, original.applicationID == applicationID,
        let context = environment.read() else { throw WebsiteConfigImportWorkflowError.conflict }
      let ticket: WebsiteConfigCommitCoordinator.Prepared
      do { ticket = try coordinator.prepareEdit(key: edit.key, value: edit.value, for: page, refreshingWith: source) }
      catch WebsiteConfigNativeDraftError.rejectedEdit {
        postNoQuitSelectionNotice("设置未修改；No Quit 保留当前练习。", publication: original,
          page: page, operation: current, noticeGeneration: noticeGeneration, expectedEnvironment: context.revision)
        if edit.key == "lazyMode" {
          postNoQuitSelectionNotice("No Quit 保留当前练习，未执行重开。", publication: original,
            page: page, operation: current, noticeGeneration: noticeGeneration, expectedEnvironment: context.revision)
        }
        if edit.dispatchesRestartAfterRejection { throw WebsiteConfigImportWorkflowError.rejectedRestartFailed }
        throw WebsiteConfigNativeDraftError.rejectedEdit
      }
      prepared = ticket
      try Task.checkCancellation()
      guard ownsActiveNoQuit, operation == current, !stopped, edit.key == "customPolyglot" else {
        throw WebsiteConfigImportWorkflowError.conflict
      }
      switch try coordinator.beginConfigurationRestart(ticket, for: page, action: edit) {
      case .futureSelectionSaved(let publication):
        let message = "多语组合已保存；No Quit 保留当前练习，下一轮使用新组合。"
        postNoQuitSelectionNotice(message, publication: publication, page: page,
          operation: current, noticeGeneration: noticeGeneration, expectedEnvironment: context.revision)
        return message
      case .busy: throw WebsiteConfigImportWorkflowError.busy
      case .unavailable: throw WebsiteConfigImportWorkflowError.unavailable
      default: throw WebsiteConfigImportWorkflowError.conflict
      }
    }
  }
  private func restorationTicket(for page: PracticePageSessionStore) throws -> WebsiteConfigCommitCoordinator.Prepared {
    switch try coordinator.prepareRestoration(for: page, refreshingWith: source) {
    case .missing: throw WebsiteConfigImportWorkflowError.missing
    case .unavailable: throw WebsiteConfigImportWorkflowError.unavailable
    case .prepared(let value): return try coordinator.acceptApplication(value, for: page)
    }
  }
  private func postNoQuitSelectionNotice(_ message: String,
    publication: WebsiteConfigCommitCoordinator.Publication, page: PracticePageSessionStore,
    operation current: UUID, noticeGeneration: UUID?, expectedEnvironment: UUID? = nil) {
    guard let notices, let noticeGeneration else { return }
    notices.postGuarded(message, level: .notice, options: .init(important: true, title: "锁定重开"),
      generation: noticeGeneration, whileCurrent: {
        self.operation == current && !self.stopped && !Task.isCancelled
          && self.environment.read()?.revision == (expectedEnvironment ?? publication.environmentRevision)
          && page.state.presentation?.publication.applicationID == publication.applicationID
          && publication.isCurrentDelivery(owner: page.owner, router: self.settings.preferenceConfigurationSaves)
      })
  }
  func cancel() {
    operation = UUID()
    if let prepared { _ = coordinator.cancel(prepared) }
    if let rejectedRestart { rejectedRestart.controller.cancel(requestID: rejectedRestart.request) }
  }
  private func checkRestartBusy(_ intent: Intent, page: PracticePageSessionStore) throws {
    if case .application = intent { return }
    if page.restartController?.isPreparing == true {
      throw WebsiteConfigImportWorkflowError.busy
    }
  }
  private func checkIntent(_ intent: Intent, page: PracticePageSessionStore) throws {
    switch intent {
    case .application:
      guard !page.state.session.hasStarted || page.state.session.isFinished else {
        throw WebsiteConfigImportWorkflowError.activeAttempt
      }
    case .edit:
      guard page.state.savedApplication == nil else { throw WebsiteConfigImportWorkflowError.preparationPending }
      if let pending = page.state.configurationDeparture {
        if !pending.configurationWasSaved {
          throw WebsiteConfigSavedPreparationError(underlying: WebsiteConfigImportWorkflowError.preparationPending,
            configurationWasSaved: false)
        }
        throw WebsiteConfigImportWorkflowError.preparationPending
      }
    case .resume(let id):
      guard page.state.configurationDeparture?.id == id else { throw WebsiteConfigImportWorkflowError.conflict }
    }
  }
  func stop() {
    stopped = true; cancel(); source.stop(); environment.stop()
  }
}
