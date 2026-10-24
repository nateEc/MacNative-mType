import Observation
import SwiftUI

@MainActor @Observable final class WebsiteConfigImportForm {
  var json = ""
  private(set) var isWorking = false
  private(set) var message: String?
  private(set) var isError = false
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private var request = UUID()
  @ObservationIgnored private let apply: @MainActor (String?) async throws -> String
  @ObservationIgnored private let cancelOperation: @MainActor () -> Void
  init(apply: @escaping @MainActor (String?) async throws -> String, cancel: @escaping @MainActor () -> Void) {
    self.apply = apply; cancelOperation = cancel
  }
  func start(restoring: Bool = false) {
    guard !isWorking else { return }
    let current = UUID(); request = current
    let input = restoring ? nil : json
    isWorking = true; message = nil; isError = false
    work = Task { [weak self] in
      guard let self else { return }
      defer { if self.request == current { self.work = nil; self.isWorking = false } }
      do {
        let result = try await self.apply(input)
        guard self.request == current, !Task.isCancelled else { return }
        self.message = result
      } catch {
        guard self.request == current else { return }
        self.isError = !(error is CancellationError)
        self.message = error is CancellationError ? "操作已取消。" : Self.message(for: error)
      }
    }
  }
  func cancel() {
    request = UUID(); work?.cancel(); work = nil
    cancelOperation(); isWorking = false; isError = false
    message = "操作已取消；未完成的准备不会应用。"
  }
  @discardableResult
  func useTypebarSettings(_ action: () throws -> Void) -> Bool {
    guard !isWorking else { return false }
    do {
      try action()
      isError = false
      message = "本窗口已使用 Typebar 设置；完整配置存档保留，下次启动仍会尝试恢复。"
      return true
    } catch {
      isError = true; message = Self.message(for: error)
      return false
    }
  }
  private static func message(for error: Error) -> String {
    if case PracticePageSessionStateError.locked = error {
      return "请先结束当前练习，再切换到 Typebar 设置。"
    }
    if case PracticePageSessionStateError.invalidAttempt = error {
      return "Typebar 设置未能生成新的练习，切换尚未完成；请检查设置或恢复保存的完整配置。存档未删除。"
    }
    if let error = error as? WebsiteConfigImportWorkflowError { return error.localizedDescription }
    if case WebsiteConfigSessionBuildError.reconfigurationRequired = error {
      return "当前引语来源不可用；请检查语言与引语长度后重新导入。原配置未修改。"
    }
    if case WebsiteConfigSessionBuildError.externalNotProvided = error {
      return "在线词源的完整导入生命周期尚未接通；这次导入未应用。"
    }
    return "配置未能应用。请检查 JSON、所需字体／背景和当前窗口后重试；未知存档不会被修复或覆盖。"
  }
}

struct WebsiteConfigImportView: View {
  @State private var form: WebsiteConfigImportForm
  private let useTypebarSettings: (() throws -> Void)?
  @Environment(\.dismiss) private var dismiss
  init(apply: @escaping @MainActor (String?) async throws -> String, cancel: @escaping @MainActor () -> Void,
    useTypebarSettings: (() throws -> Void)? = nil) {
    _form = State(initialValue: .init(apply: apply, cancel: cancel))
    self.useTypebarSettings = useTypebarSettings
  }
  init(form: WebsiteConfigImportForm, useTypebarSettings: (() throws -> Void)? = nil) {
    _form = State(initialValue: form); self.useTypebarSettings = useTypebarSettings
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text("导入 Monkeytype 配置").font(.title2.weight(.semibold))
          Text("粘贴 Monkeytype 导出的配置 JSON，不是 Typebar 备份。")
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("关闭") { form.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
      }
      TextEditor(text: $form.json)
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden).padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(.separator, lineWidth: 1) }
        .frame(minHeight: 300).disabled(form.isWorking)
        .accessibilityLabel("Monkeytype 配置 JSON")
      if form.isWorking {
        HStack { ProgressView().controlSize(.small); Text("正在校验配置并准备字体、背景与练习…") }
          .font(.callout)
      }
      if let message = form.message {
        Label(message, systemImage: form.isError ? "exclamationmark.triangle" : "info.circle")
          .font(.callout).foregroundStyle(form.isError ? Color.red : Color.secondary)
      }
      Text("请先结束当前练习。配置保存在此 Mac 的独立目录，启动时会尝试恢复；失败时可在此重试。成绩、凭据和自定义练习文本不会从 JSON 导入。")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if useTypebarSettings != nil {
        Text("切回仅影响本窗口，不删除完整配置存档；下次启动仍会尝试恢复它。")
          .font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Button("恢复已保存配置") { form.start(restoring: true) }.disabled(form.isWorking)
        if let useTypebarSettings {
          Button("本窗口使用 Typebar 设置") {
            if form.useTypebarSettings(useTypebarSettings) { dismiss() }
          }.disabled(form.isWorking)
        }
        Spacer()
        if form.isWorking { Button("取消准备") { form.cancel() } }
        Button("导入并开始练习") { form.start() }
          .disabled(form.isWorking || form.json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24).frame(minWidth: 680, idealWidth: 760, minHeight: 520)
    .accessibilityIdentifier("website-config-import")
    .onDisappear { form.cancel() }
  }
}
