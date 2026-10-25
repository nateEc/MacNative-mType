import Observation
import SwiftUI

struct WebsiteQuoteRecoveryNotice: View {
  let recoveries: [WebsiteQuoteSampler.Recovery]
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(recoveries.indices, id: \.self) { index in
        Label(recoveries[index].explanation, systemImage: "arrow.triangle.2.circlepath")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }.accessibilityIdentifier("website-quote-recovery-notice")
  }
}

@MainActor @Observable final class WebsiteConfigPracticeEditForm {
  var mode: TestMode
  var limit: String
  var difficulty: Difficulty
  var quoteLengths: [Int]
  var language: TypingLanguage
  var lazyMode: Bool
  private(set) var remembersLazyMode: Bool
  static let languages = TypingLanguage.allCases.filter { WebsiteLanguageIdentity.name(for: $0) != nil }
  static let quoteChoices: [(label: String, groups: [Int])] = [
    ("全部长度", [0, 1, 2, 3]), ("短", [0]), ("中", [1]), ("长", [2]), ("超长", [3]),
  ]
  private(set) var isWorking = false
  private(set) var message: String?
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var request = UUID()
  init(parameters: WebsiteConfigNativeTestParameters, difficulty: Difficulty = .normal, quoteLengths: [Int] = [1],
    lazyMode: Bool = false, remembersLazyMode: Bool = false) {
    mode = parameters.mode
    limit = String(parameters.mode == .time ? parameters.duration : parameters.wordLimit)
    self.difficulty = difficulty; self.quoteLengths = quoteLengths
    language = parameters.language; self.lazyMode = lazyMode; self.remembersLazyMode = remembersLazyMode
  }
  convenience init(draft: WebsiteConfigNativeDraft) {
    self.init(parameters: draft.testParameters, difficulty: draft.inputRules.difficulty,
      quoteLengths: draft.quoteSelection.groups, lazyMode: draft.generators.lazyMode,
      remembersLazyMode: draft.lazyMemory.remember)
  }
  func startLanguage(apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    guard !isWorking else { return }
    guard let name = WebsiteLanguageIdentity.name(for: language) else {
      message = "这个语言组合不属于 Monkeytype 语言选项；请通过 Polyglot 配置选择组合。"; return
    }
    start(.language(name), apply: apply)
  }
  func start(_ edit: WebsiteConfigPracticeEdit, apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    startPreparation { try await apply(edit) }
  }
  func resume(apply: @escaping @MainActor () async throws -> String) {
    startPreparation(apply)
  }
  private func startPreparation(_ apply: @escaping @MainActor () async throws -> String) {
    guard !isWorking else { return }
    let current = UUID(); request = current
    isWorking = true; message = nil
    work = Task { [weak self] in
      guard let self else { return }
      defer { if self.request == current { self.isWorking = false; self.work = nil } }
      do {
        let message = try await apply()
        guard self.request == current, !Task.isCancelled else { return }
        self.message = message
      } catch {
        guard self.request == current, !Task.isCancelled else { return }
        if let error = error as? WebsiteConfigImportWorkflowError { self.message = error.localizedDescription }
        else if let error = error as? WebsiteConfigSavedPreparationError { self.message = error.localizedDescription }
        else {
          self.message = "练习准备未完成。请检查参数、文本或引语；若设置已保存，可继续准备，或在导入面板恢复配置。"
        }
      }
    }
  }
  func startLimit(timed: Bool, apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    guard !isWorking else { return }
    // The source limit controls accept integral nonnegative limits; final
    // schema, funbox compatibility and native capacity admission still run.
    guard let number = Double(limit.trimmingCharacters(in: .whitespacesAndNewlines)),
      number.isFinite, number >= 0, number.rounded(.towardZero) == number,
      number <= Double(OfficialTestLimitInput.maximumValue) else {
      message = "请输入有效的非负整数；0 表示无限练习。"; return
    }
    start(timed ? .time(number) : .words(number), apply: apply)
  }
  func cancel() {
    request = UUID(); work?.cancel(); work = nil; isWorking = false
    message = "准备已取消；已保存的设置保留，尚未保存的更改不会应用。"
  }
}

/// One applied publication owns one editor lifetime. Parent recreates it on
/// publication replacement, preventing old controls from editing new content.
struct WebsiteConfigPracticeEditor: View {
  @State private var form: WebsiteConfigPracticeEditForm
  let parameters: WebsiteConfigNativeTestParameters
  private let importedQuoteGroups: [Int]
  let canEdit: Bool
  let recoveries: [WebsiteQuoteSampler.Recovery]
  let pendingPreparation: Bool
  let resume: (@MainActor () async throws -> String)?
  let apply: @MainActor (WebsiteConfigPracticeEdit) async throws -> String
  init(draft: WebsiteConfigNativeDraft, canEdit: Bool, recoveries: [WebsiteQuoteSampler.Recovery] = [],
    pendingPreparation: Bool = false,
    resume: (@MainActor () async throws -> String)? = nil,
    apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    parameters = draft.testParameters; importedQuoteGroups = draft.quoteSelection.groups
    self.canEdit = canEdit; self.apply = apply
    self.recoveries = recoveries
    self.pendingPreparation = pendingPreparation; self.resume = resume
    _form = State(initialValue: .init(draft: draft))
  }
  init(form: WebsiteConfigPracticeEditForm, parameters: WebsiteConfigNativeTestParameters, canEdit: Bool,
    recoveries: [WebsiteQuoteSampler.Recovery] = [],
    pendingPreparation: Bool = false, resume: (@MainActor () async throws -> String)? = nil,
    apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    _form = State(initialValue: form); self.parameters = parameters; self.canEdit = canEdit; self.apply = apply
    importedQuoteGroups = form.quoteLengths
    self.recoveries = recoveries
    self.pendingPreparation = pendingPreparation; self.resume = resume
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if !recoveries.isEmpty { WebsiteQuoteRecoveryNotice(recoveries: recoveries) }
      if pendingPreparation {
        VStack(alignment: .leading, spacing: 6) {
          Label("设置已保存", systemImage: "checkmark.circle").font(.subheadline.weight(.semibold))
          Text("新练习尚未准备完成。取消不会撤回已保存的设置。")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          if let resume {
            Button("继续准备新练习") { form.resume(apply: resume) }
              .disabled(form.isWorking).accessibilityIdentifier("website-config-resume-preparation")
          }
        }.accessibilityIdentifier("website-config-saved-pending")
      }
      HStack {
        Picker("模式", selection: $form.mode) {
          ForEach(TestMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        Button("应用模式") { form.start(.mode(form.mode), apply: apply) }
          .accessibilityIdentifier("website-config-apply-mode")
      }.disabled(!canEdit || form.isWorking || pendingPreparation)
      if parameters.mode == .time || parameters.mode == .words {
        HStack {
          Text(parameters.mode == .time ? "秒数" : "词数")
          TextField(parameters.mode == .time ? "秒数" : "词数", text: $form.limit)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("website-config-practice-limit")
          Button(parameters.mode == .time ? "应用时长" : "应用词数") {
            form.startLimit(timed: parameters.mode == .time, apply: apply)
          }.accessibilityIdentifier("website-config-apply-limit")
        }.disabled(!canEdit || form.isWorking || pendingPreparation)
      }
      VStack(alignment: .leading, spacing: 6) {
        PracticeLanguagePicker(languages: WebsiteConfigPracticeEditForm.languages, selection: $form.language)
        HStack { Spacer(); Button("应用语言") { form.startLanguage(apply: apply) }
          .accessibilityIdentifier("website-config-apply-language") }
      }.disabled(!canEdit || form.isWorking || pendingPreparation)
      HStack {
        Picker("简化输入", selection: $form.lazyMode) { Text("关闭").tag(false); Text("开启").tag(true) }
        Button("应用并重开") { form.start(.lazyMode(form.lazyMode), apply: apply) }
          .accessibilityIdentifier("website-config-apply-lazy-mode")
      }.disabled(!canEdit || form.isWorking || pendingPreparation)
      Text(form.remembersLazyMode ? "已记住简化输入；切换到支持的词源会恢复。" : "Arabic 单独记住开关；词源不支持时会临时关闭简化输入。")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      HStack {
        Picker("难度", selection: $form.difficulty) {
          ForEach(Difficulty.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        Button("应用难度") { form.start(.difficulty(form.difficulty), apply: apply) }
          .accessibilityIdentifier("website-config-apply-difficulty")
      }.disabled(!canEdit || form.isWorking || pendingPreparation)
      if parameters.mode != .zen {
        HStack {
          Toggle("标点", isOn: Binding(get: { parameters.contentOptions.includePunctuation },
            set: { form.start(.punctuation($0), apply: apply) }))
          Toggle("数字", isOn: Binding(get: { parameters.contentOptions.includeNumbers },
            set: { form.start(.numbers($0), apply: apply) }))
        }.disabled(!canEdit || form.isWorking || pendingPreparation || parameters.mode == .quote)
      }
      if parameters.mode == .quote {
        VStack(alignment: .leading, spacing: 6) {
          Picker("引语长度", selection: $form.quoteLengths) {
            if !WebsiteConfigPracticeEditForm.quoteChoices.contains(where: { $0.groups == importedQuoteGroups }) {
              Text("已导入分组（\(importedQuoteGroups.map(String.init).joined(separator: ", "))）").tag(importedQuoteGroups)
            }
            ForEach(WebsiteConfigPracticeEditForm.quoteChoices.indices, id: \.self) { index in
              Text(WebsiteConfigPracticeEditForm.quoteChoices[index].label)
                .tag(WebsiteConfigPracticeEditForm.quoteChoices[index].groups)
            }
          }
          HStack {
            Spacer()
            Button("应用引语长度") { form.start(.quoteLengths(form.quoteLengths), apply: apply) }
              .accessibilityIdentifier("website-config-apply-quote-length")
          }
        }.disabled(!canEdit || form.isWorking || pendingPreparation)
      }
      Text(pendingPreparation ? "可继续准备，或在导入面板恢复配置。" : canEdit ? "应用会保存设置并重开；进行中的练习将结束。词数／秒数为 0 表示无限。" : "请等待上一项练习准备完成。")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if form.isWorking {
        HStack {
          ProgressView().controlSize(.small)
          Text("正在准备新练习…").font(.caption)
          Button("取消准备") { form.cancel() }
        }
      }
      if let message = form.message {
        Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityIdentifier("website-config-practice-editor")
    .onDisappear { form.cancel() }
  }
}
