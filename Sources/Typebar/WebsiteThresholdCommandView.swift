import Observation
import SwiftUI

struct WebsiteThresholdCommandPresentation: Identifiable {
  let id: UUID
  let target: PracticeThresholdCommandTarget
  let unit: TypingSpeedUnit
  let initialText: String
  init?(publication: WebsiteConfigCommitCoordinator.Publication, target: PracticeThresholdCommandTarget) {
    guard let source = publication.draft.inputRules.rules.thresholdSource?.configuration, target.editorKind != nil else { return nil }
    id = publication.applicationID; self.target = target; unit = publication.draft.presentation.typingSpeedUnit
    switch target {
    case .minimumWpmCustom: initialText = Self.text(source.minimumWpmCustomValue)
    case .minimumAccuracyCustom: initialText = Self.text(source.minimumAccuracyCustomValue)
    default: initialText = ""
    }
  }
  private static func text(_ value: Double) -> String {
    if value == 0 { return "0" }
    let text = String(value)
    return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
  }
}

@MainActor @Observable final class WebsiteThresholdCommandForm {
  var text: String
  let target: PracticeThresholdCommandTarget
  let unit: TypingSpeedUnit
  private(set) var isWorking = false
  private(set) var message: String?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var request = UUID()
  init(text: String, target: PracticeThresholdCommandTarget, unit: TypingSpeedUnit) {
    self.text = text; self.target = target; self.unit = unit
  }
  var canSubmit: Bool { WebsiteThresholdCommandInput.edits(for: target, raw: text, unit: unit) != nil }
  func submit(apply: @escaping @MainActor (String) async throws -> WebsiteThresholdCommandReceipt,
    completed: @escaping @MainActor () -> Void) {
    guard !isWorking, canSubmit else { return }
    let current = UUID(), input = text; request = current; isWorking = true; message = nil
    task = Task { [weak self] in
      guard let self else { return }
      defer { if request == current { task = nil; isWorking = false } }
      do {
        let result = try await apply(input)
        guard request == current, !Task.isCancelled else { return }
        message = result.message; completed()
      } catch {
        guard request == current, !Task.isCancelled else { return }
        if let error = error as? WebsiteThresholdCommandError { message = error.localizedDescription }
        else if let error = error as? WebsiteConfigImportWorkflowError { message = error.localizedDescription }
        else if case WebsiteConfigNativeRuleError.unrepresentableField = error {
          message = "该数值超出当前原生阈值支持范围，请输入有限数值。"
        } else { message = "阈值命令未完成，请检查配置或重新打开命令。" }
      }
    }
  }
  func cancel() { request = UUID(); task?.cancel(); task = nil; isWorking = false }
}

struct WebsiteThresholdCommandView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var form: WebsiteThresholdCommandForm
  let canApply: Bool
  let apply: @MainActor (String) async throws -> WebsiteThresholdCommandReceipt
  init(presentation: WebsiteThresholdCommandPresentation, canApply: Bool,
    apply: @escaping @MainActor (String) async throws -> WebsiteThresholdCommandReceipt) {
    _form = State(initialValue: .init(text: presentation.initialText, target: presentation.target, unit: presentation.unit))
    self.canApply = canApply; self.apply = apply
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(form.target.editorKind?.title ?? "自动失败阈值").font(.title2.weight(.semibold))
        Spacer()
        Button("关闭") { form.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text(form.target.editorKind?.inputKind == .accuracy ? "输入准确率，范围为 0 至 100。" : "输入单位：\(form.unit.displayName)。保存后按 WPM 计分，不重开当前练习。")
        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      TextField("阈值", text: $form.text).textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("website-threshold-command-input")
        .disabled(!canApply || form.isWorking)
        .onSubmit(submit)
      Text(isBurst ? "单词速度读取整数前缀；模式会先保存，数值被拒绝时原数值保留。空输入不修改，纯空白输入仍会尝试设置模式。"
        : "预填为配置记忆值。速度按当前单位换算；空输入按 0 处理，并保留自定义模式。")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if let message = form.message { Text(message).fixedSize(horizontal: false, vertical: true) }
      else if !canApply { Text("配置已变化或正在准备，请关闭后重新打开命令。").font(.caption) }
      else if !form.canSubmit { Text("输入未通过阈值命令校验。").font(.caption).foregroundStyle(.red) }
      HStack {
        if form.isWorking { ProgressView().controlSize(.small) }
        Spacer()
        Button("应用") { submit() }.keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("website-threshold-command-apply")
          .disabled(!canApply || form.isWorking || !form.canSubmit)
      }
    }.padding(24).frame(minWidth: 460, idealWidth: 540)
      .onDisappear { form.cancel() }
  }
  private var isBurst: Bool { if case .minimumWordBurst = form.target { return true }; return false }
  private func submit() { guard canApply else { return }; form.submit(apply: apply, completed: { dismiss() }) }
}
