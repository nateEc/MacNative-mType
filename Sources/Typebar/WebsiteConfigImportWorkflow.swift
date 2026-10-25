import Foundation

/// Explicit test-page actions with a source restart dispatch or subscription.
/// Not the metadata's broader changeRequiresRestart key set.
enum WebsiteConfigPracticeEdit: Equatable {
  case mode(TestMode), time(Double), words(Double)
  case difficulty(Difficulty), punctuation(Bool), numbers(Bool), quoteLengths([Int])
  case language(String), lazyMode(Bool)
  case funboxes([String])
  case polyglotLanguages([String])
  case layoutFluidLayouts([String])
  var key: String {
    switch self {
    case .mode: "mode"; case .time: "time"; case .words: "words"
    case .difficulty: "difficulty"; case .punctuation: "punctuation"; case .numbers: "numbers"
    case .quoteLengths: "quoteLength"
    case .language: "language"; case .lazyMode: "lazyMode"
    case .funboxes: "funbox"
    case .polyglotLanguages: "customPolyglot"
    case .layoutFluidLayouts: "customLayoutfluid"
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
    }
  }
  /// TestConfig controls dispatch after a false setter return; difficulty
  /// restarts only from its successful setter event. A thrown override is
  /// neither case: execution never reaches the following dispatch.
  var dispatchesRestartAfterRejection: Bool {
    switch self {
    case .difficulty, .language, .layoutFluidLayouts: false
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
/// or silently substitute another text provider. Explicit practice setters use
/// durable departure; full import/restoration still protects active attempts.
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
    loadQuotes: @escaping @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) }) {
    self.page = page; self.settings = settings; self.loadQuotes = loadQuotes
    self.notices = account.localNotices
    let environment = WebsiteConfigEnvironmentSource(settings: settings, account: account,
      pointsPerRem: 16, documentComplete: true, development: false)
    self.environment = environment
    source = .init(environment: environment, readWindow: readWindow)
    coordinator = .init(router: settings.preferenceConfigurationSaves, register: .init(directory: directory),
      environment: { [environment] in environment.read() })
  }

  /// nil selects explicit native-record restoration, never an empty import.
  @discardableResult
  func apply(json: String?, systemIsDark: Bool) async throws -> String {
    try await perform(.application(json), systemIsDark: systemIsDark)
  }

  @discardableResult
  func editAndBegin(_ edit: WebsiteConfigPracticeEdit, replacing applicationID: UUID, systemIsDark: Bool) async throws -> String {
    try await perform(.edit(edit, applicationID), systemIsDark: systemIsDark)
  }

  @discardableResult
  func resumeAndBegin(departureID: UUID, systemIsDark: Bool) async throws -> String {
    try await perform(.resume(departureID), systemIsDark: systemIsDark)
  }

  private func perform(_ intent: Intent, systemIsDark: Bool) async throws -> String {
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
      do { ticket = try coordinator.prepareEdit(key: edit.key, value: edit.value, for: page, refreshingWith: source) }
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
  private func restorationTicket(for page: PracticePageSessionStore) throws -> WebsiteConfigCommitCoordinator.Prepared {
    switch try coordinator.prepareRestoration(for: page, refreshingWith: source) {
    case .missing: throw WebsiteConfigImportWorkflowError.missing
    case .unavailable: throw WebsiteConfigImportWorkflowError.unavailable
    case .prepared(let value): return value
    }
  }
  private func postNoQuitSelectionNotice(_ message: String,
    publication: WebsiteConfigCommitCoordinator.Publication, page: PracticePageSessionStore,
    operation current: UUID, noticeGeneration: UUID?) {
    guard let notices, let noticeGeneration else { return }
    notices.postGuarded(message, level: .notice, options: .init(important: true, title: "锁定重开"),
      generation: noticeGeneration, whileCurrent: {
        self.operation == current && !self.stopped && !Task.isCancelled
          && self.environment.read()?.revision == publication.environmentRevision
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
