import Observation
import SwiftUI

struct WebsiteKeymapSizePresentation: Identifiable {
  static let item = CommandPaletteItem(id: "setKeymapSizeCustom", title: "键盘提示大小…",
    subtitle: "输入 0.5–3.5 倍，步长 0.1", systemImage: "keyboard", keywords: ["keymapSize", "keyboard", "大小", "缩放"], group: .settings)
  let id: UUID
  let initialText: String
  init(publication: WebsiteConfigCommitCoordinator.Publication) {
    id = publication.applicationID
    let text = String(publication.draft.keyboardTypography.guideScale)
    initialText = text.hasSuffix(".0") ? String(text.dropLast(2)) : text
  }
}

@MainActor @Observable final class WebsiteKeymapSizeForm {
  var text: String
  private(set) var isWorking = false
  private(set) var message: String?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var request = UUID()
  init(text: String) { self.text = text }
  var value: Double? { WebsiteKeymapCommand.size(text) }
  func submit(apply: @escaping @MainActor (Double) async throws -> Void, completed: @escaping @MainActor () -> Void) {
    guard !isWorking, let value else { return }
    let current = UUID(); request = current; isWorking = true; message = nil
    task = Task { [weak self] in
      guard let self else { return }
      defer { if request == current { task = nil; isWorking = false } }
      do {
        try await apply(value)
        guard request == current, !Task.isCancelled else { return }
        completed()
      } catch {
        guard request == current, !Task.isCancelled else { return }
        message = (error as? LocalizedError)?.errorDescription ?? "键盘大小未保存，请重新打开命令。"
      }
    }
  }
  func cancel() { request = UUID(); task?.cancel(); task = nil; isWorking = false }
}

struct WebsiteKeymapSizeCommandView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var form: WebsiteKeymapSizeForm
  let canApply: Bool
  let apply: @MainActor (Double) async throws -> Void
  init(presentation: WebsiteKeymapSizePresentation, canApply: Bool,
    apply: @escaping @MainActor (Double) async throws -> Void) {
    _form = State(initialValue: .init(text: presentation.initialText)); self.canApply = canApply; self.apply = apply
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("键盘提示大小").font(.title2.weight(.semibold)); Spacer()
        Button("关闭") { form.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text("输入 0.5 至 3.5，步长 0.1。保存后显示键盘，当前练习继续。")
        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      TextField("缩放倍数", text: $form.text).textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("website-keymap-size-input").disabled(!canApply || form.isWorking).onSubmit(submit)
      if let message = form.message { Text(message).fixedSize(horizontal: false, vertical: true) }
      else if !canApply { Text("配置已变化，请关闭后重新打开命令。").font(.caption) }
      else if form.value == nil { Text("请输入 0.5 至 3.5、步长为 0.1 的有效数值。").font(.caption).foregroundStyle(.red) }
      HStack {
        if form.isWorking { ProgressView().controlSize(.small) }
        Spacer()
        Button("应用") { submit() }.keyboardShortcut(.defaultAction).disabled(!canApply || form.isWorking || form.value == nil)
      }
    }.padding(24).frame(minWidth: 440, idealWidth: 520).onDisappear { form.cancel() }
  }
  private func submit() { guard canApply else { return }; form.submit(apply: apply, completed: { dismiss() }) }
}
