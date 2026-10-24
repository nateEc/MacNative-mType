import Observation
import SwiftUI

@MainActor @Observable final class WebsiteConfigPracticeEditForm {
  var mode: TestMode
  var limit: String
  var difficulty: Difficulty
  var quoteLengths: [Int]
  static let quoteChoices: [(label: String, groups: [Int])] = [
    ("全部长度", [0, 1, 2, 3]), ("短", [0]), ("中", [1]), ("长", [2]), ("超长", [3]),
  ]
  private(set) var isWorking = false
  private(set) var message: String?
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var request = UUID()
  init(parameters: WebsiteConfigNativeTestParameters, difficulty: Difficulty = .normal, quoteLengths: [Int] = [1]) {
    mode = parameters.mode
    limit = String(parameters.mode == .time ? parameters.duration : parameters.wordLimit)
    self.difficulty = difficulty; self.quoteLengths = quoteLengths
  }
  convenience init(draft: WebsiteConfigNativeDraft) {
    self.init(parameters: draft.testParameters, difficulty: draft.inputRules.difficulty,
      quoteLengths: draft.quoteSelection.groups)
  }
  func start(_ edit: WebsiteConfigPracticeEdit, apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    guard !isWorking else { return }
    let current = UUID(); request = current
    isWorking = true; message = nil
    work = Task { [weak self] in
      guard let self else { return }
      defer { if self.request == current { self.isWorking = false; self.work = nil } }
      do {
        let message = try await apply(edit)
        guard self.request == current, !Task.isCancelled else { return }
        self.message = message
      } catch {
        guard self.request == current, !Task.isCancelled else { return }
        if let error = error as? WebsiteConfigImportWorkflowError { self.message = error.localizedDescription }
        else {
          self.message = "设置未应用。请检查参数、所选模式所需的文本或引语；窗口和配置变化后请重新打开设置。"
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
    message = "准备已取消；未完成的设置不会应用。"
  }
}

/// One applied publication owns one editor lifetime. Parent recreates it on
/// publication replacement, preventing old controls from editing new content.
struct WebsiteConfigPracticeEditor: View {
  @State private var form: WebsiteConfigPracticeEditForm
  let parameters: WebsiteConfigNativeTestParameters
  private let importedQuoteGroups: [Int]
  let canEdit: Bool
  let apply: @MainActor (WebsiteConfigPracticeEdit) async throws -> String
  init(draft: WebsiteConfigNativeDraft, canEdit: Bool,
    apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    parameters = draft.testParameters; importedQuoteGroups = draft.quoteSelection.groups
    self.canEdit = canEdit; self.apply = apply
    _form = State(initialValue: .init(draft: draft))
  }
  init(form: WebsiteConfigPracticeEditForm, parameters: WebsiteConfigNativeTestParameters, canEdit: Bool,
    apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    _form = State(initialValue: form); self.parameters = parameters; self.canEdit = canEdit; self.apply = apply
    importedQuoteGroups = form.quoteLengths
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Picker("模式", selection: $form.mode) {
          ForEach(TestMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        Button("应用模式") { form.start(.mode(form.mode), apply: apply) }
          .accessibilityIdentifier("website-config-apply-mode")
      }.disabled(!canEdit || form.isWorking)
      if parameters.mode == .time || parameters.mode == .words {
        HStack {
          Text(parameters.mode == .time ? "秒数" : "词数")
          TextField(parameters.mode == .time ? "秒数" : "词数", text: $form.limit)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("website-config-practice-limit")
          Button(parameters.mode == .time ? "应用时长" : "应用词数") {
            form.startLimit(timed: parameters.mode == .time, apply: apply)
          }.accessibilityIdentifier("website-config-apply-limit")
        }.disabled(!canEdit || form.isWorking)
      }
      HStack {
        Picker("难度", selection: $form.difficulty) {
          ForEach(Difficulty.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        Button("应用难度") { form.start(.difficulty(form.difficulty), apply: apply) }
          .accessibilityIdentifier("website-config-apply-difficulty")
      }.disabled(!canEdit || form.isWorking)
      if parameters.mode != .zen {
        HStack {
          Toggle("标点", isOn: Binding(get: { parameters.contentOptions.includePunctuation },
            set: { form.start(.punctuation($0), apply: apply) }))
          Toggle("数字", isOn: Binding(get: { parameters.contentOptions.includeNumbers },
            set: { form.start(.numbers($0), apply: apply) }))
        }.disabled(!canEdit || form.isWorking || parameters.mode == .quote)
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
        }.disabled(!canEdit || form.isWorking)
      }
      Text(canEdit ? "应用或切换标点／数字后保存并开始新练习；其他完整配置保持不变。词数／秒数为 0 表示无限。" : "请先结束当前练习，再编辑设置。")
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
