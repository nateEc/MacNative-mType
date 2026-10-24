import Observation
import SwiftUI

@MainActor @Observable final class WebsiteConfigPracticeEditForm {
  var mode: TestMode
  var limit: String
  private(set) var isWorking = false
  private(set) var message: String?
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var request = UUID()
  init(parameters: WebsiteConfigNativeTestParameters) {
    mode = parameters.mode
    limit = String(parameters.mode == .time ? parameters.duration : parameters.wordLimit)
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
  let canEdit: Bool
  let apply: @MainActor (WebsiteConfigPracticeEdit) async throws -> String
  init(parameters: WebsiteConfigNativeTestParameters, canEdit: Bool,
    apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    self.parameters = parameters; self.canEdit = canEdit; self.apply = apply
    _form = State(initialValue: .init(parameters: parameters))
  }
  init(form: WebsiteConfigPracticeEditForm, parameters: WebsiteConfigNativeTestParameters, canEdit: Bool,
    apply: @escaping @MainActor (WebsiteConfigPracticeEdit) async throws -> String) {
    _form = State(initialValue: form); self.parameters = parameters; self.canEdit = canEdit; self.apply = apply
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
      Text(canEdit ? "应用后保存设置并开始新练习；0 表示无限。其他完整配置保持不变。" : "请先结束当前练习，再编辑设置。")
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
