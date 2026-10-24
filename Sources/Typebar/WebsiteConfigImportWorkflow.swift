import Foundation

/// Explicit test-page actions with a source restart dispatch or subscription.
/// Not the metadata's broader changeRequiresRestart key set. Language remains
/// separate until its persistent lazy-mode listener memory can travel too.
enum WebsiteConfigPracticeEdit: Equatable {
  case mode(TestMode), time(Double), words(Double)
  case difficulty(Difficulty), punctuation(Bool), numbers(Bool), quoteLengths([Int])
  var key: String {
    switch self {
    case .mode: "mode"; case .time: "time"; case .words: "words"
    case .difficulty: "difficulty"; case .punctuation: "punctuation"; case .numbers: "numbers"
    case .quoteLengths: "quoteLength"
    }
  }
  var value: WebsiteConfigValue {
    switch self {
    case .mode(let mode): .string(mode.rawValue)
    case .time(let value), .words(let value): .number(value)
    case .difficulty(let value): .string(value.rawValue)
    case .punctuation(let value), .numbers(let value): .bool(value)
    case .quoteLengths(let groups): .array(groups.map { .number(Double($0)) })
    }
  }
}

enum WebsiteConfigImportWorkflowError: Error, LocalizedError {
  case missing, typebarBackup, activeAttempt, unavailable, busy, conflict, unsupportedPractice
  var errorDescription: String? {
    switch self {
    case .missing: "还没有保存的 Monkeytype 配置；请先粘贴配置 JSON。"
    case .typebarBackup: "这是 Typebar 备份，请使用“导入设置 JSON”。"
    case .activeAttempt: "请先结束当前练习，再修改、导入或恢复配置。活动尝试的迁移记账尚未接通。"
    case .unavailable: "配置记录或窗口当前不可用；未知记录不会被覆盖，请检查后重试。"
    case .busy: "上一项资源准备仍未结束，请稍后重试。"
    case .conflict: "配置或窗口已变化，未应用这次准备；请重新导入。"
    case .unsupportedPractice: "请先退出挑战或单词专项练习，再导入完整配置。"
    }
  }
}

/// Window-owned whole-application workflow. Does not mutate legacy preferences
/// or silently substitute another text provider. Active-attempt cutover remains
/// guarded until the full-configuration departure lifecycle is implemented.
@MainActor final class WebsiteConfigImportWorkflow {
  private weak var page: PracticePageSessionStore?
  private let settings: AppSettings
  private let environment: WebsiteConfigEnvironmentSource
  private let source: WebsiteConfigPracticeScopeSource
  private let coordinator: WebsiteConfigCommitCoordinator
  private let loadQuotes: @MainActor (TypingLanguage) async throws -> [OfflineQuote]
  private var prepared: WebsiteConfigCommitCoordinator.Prepared?
  private var applying = false
  private var stopped = false
  private var operation = UUID()
  private enum Intent { case application(String?), edit(WebsiteConfigPracticeEdit, UUID) }

  init(page: PracticePageSessionStore, settings: AppSettings, account: AccountSession,
    directory: URL, readWindow: @escaping @MainActor () -> WebsiteConfigPracticeScopeSource.Window?,
    loadQuotes: @escaping @MainActor (TypingLanguage) async throws -> [OfflineQuote] = { OfflineContent.quotes(for: $0) }) {
    self.page = page; self.settings = settings; self.loadQuotes = loadQuotes
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

  private func perform(_ intent: Intent, systemIsDark: Bool) async throws -> String {
    guard !stopped, let page else { throw WebsiteConfigImportWorkflowError.unavailable }
    guard !applying else { throw WebsiteConfigImportWorkflowError.busy }
    guard !page.state.session.hasStarted || page.state.session.isFinished else {
      throw WebsiteConfigImportWorkflowError.activeAttempt
    }
    applying = true
    let current = UUID(); operation = current
    defer {
      if let prepared { _ = coordinator.cancel(prepared) }
      prepared = nil; applying = false
    }
    try Task.checkCancellation()
    // Let a prior observed preference mutation finish its MainActor resample.
    await Task.yield()
    guard !stopped else { throw WebsiteConfigImportWorkflowError.unavailable }
    guard operation == current else { throw CancellationError() }
    try Task.checkCancellation()
    guard !page.state.session.hasStarted || page.state.session.isFinished else {
      throw WebsiteConfigImportWorkflowError.activeAttempt
    }
    let ticket: WebsiteConfigCommitCoordinator.Prepared
    switch intent {
    case .edit(let edit, let applicationID):
      guard page.state.presentation?.publication.applicationID == applicationID else {
        throw WebsiteConfigImportWorkflowError.conflict
      }
      ticket = try coordinator.prepareEdit(key: edit.key, value: edit.value, for: page, refreshingWith: source)
    case .application(.some(let json)):
      let fields = try WebsiteConfigJSONReader.read(json).importFields
      if fields?["version"] != nil, fields?["settings"] != nil, fields?["configuration"] != nil,
        fields?.keys.contains(where: { WebsiteConfigNativeDraft.mappedKeys.contains($0) }) == false {
        throw WebsiteConfigImportWorkflowError.typebarBackup
      }
      ticket = try coordinator.prepare(json, for: page, refreshingWith: source)
    case .application(nil):
      switch try coordinator.prepareRestoration(for: page, refreshingWith: source) {
      case .missing: throw WebsiteConfigImportWorkflowError.missing
      case .unavailable: throw WebsiteConfigImportWorkflowError.unavailable
      case .prepared(let value): ticket = value
      }
    }
    prepared = ticket
    guard operation == current else { throw CancellationError() }
    let resources = try await coordinator.prepareResources(for: ticket, from: settings)
    let ready = try await coordinator.preparePractice(for: resources, loadQuotes: loadQuotes)
    try Task.checkCancellation()
    guard !stopped else { throw WebsiteConfigImportWorkflowError.unavailable }
    guard operation == current else { throw CancellationError() }
    switch try coordinator.commit(ready, to: page, systemIsDark: systemIsDark) {
    case .committed:
      // No await after commit. The same coordinator/content catalog owns retry.
      do {
        try page.bindRestartController(using: coordinator, loadQuotes: loadQuotes)
        switch intent {
        case .application(nil): return "已恢复保存的配置，新的练习已准备好。"
        case .application(.some): return "配置已导入，新的练习已准备好。"
        case .edit: return "设置已保存，新的练习已准备好。"
        }
      } catch {
        // The durable commit already succeeded. Never report a rolled-back
        // import merely because an observer retired its receiving window.
        return "配置已保存并应用，但窗口已变化，重开控制未能绑定；请重新打开此面板恢复。"
      }
    case .busy: throw WebsiteConfigImportWorkflowError.busy
    case .conflict, .stale: throw WebsiteConfigImportWorkflowError.conflict
    case .unavailable: throw WebsiteConfigImportWorkflowError.unavailable
    }
  }
  func cancel() {
    operation = UUID()
    if let prepared { _ = coordinator.cancel(prepared) }
  }
  func stop() {
    stopped = true; cancel(); source.stop(); environment.stop()
  }
}
