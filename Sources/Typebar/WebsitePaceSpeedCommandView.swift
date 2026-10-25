import Observation
import SwiftUI

struct WebsitePaceSpeedPresentation: Identifiable {
  static let item = CommandPaletteItem(id: "setPaceCaretCustomSpeedCustom", title: "自定义配速…",
    subtitle: "保存速度并请求重开", systemImage: "metronome", keywords: ["paceCaret", "配速", "custom"], group: .settings)
  let id: UUID
  let initialText: String
  let unit: TypingSpeedUnit
  init(publication: WebsiteConfigCommitCoordinator.Publication) {
    id = publication.applicationID; unit = publication.draft.presentation.typingSpeedUnit
    let text = String(publication.draft.behavior.paceGuideCustomWpm)
    initialText = text.hasSuffix(".0") ? String(text.dropLast(2)) : text
  }
}

@MainActor @Observable final class WebsitePaceSpeedForm {
  var text: String
  let unit: TypingSpeedUnit
  private(set) var isWorking = false
  private(set) var message: String?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var request = UUID()
  init(text: String, unit: TypingSpeedUnit) { self.text = text; self.unit = unit }
  var canSubmit: Bool { WebsitePaceCommand.speed(text, unit: unit)?.isFinite == true }
  func submit(apply: @escaping @MainActor (String) async throws -> Void, completed: @escaping @MainActor () -> Void) {
    guard !isWorking, canSubmit else { return }
    let current = UUID(), captured = text; request = current; isWorking = true; message = nil
    task = Task { [weak self] in
      guard let self else { return }
      defer { if request == current { task = nil; isWorking = false } }
      do {
        try await apply(captured)
        guard request == current, !Task.isCancelled else { return }
        completed()
      } catch {
        guard request == current, !Task.isCancelled else { return }
        message = (error as? LocalizedError)?.errorDescription ?? "配速命令未完成，请检查配置后重试。"
      }
    }
  }
  func cancel() { request = UUID(); task?.cancel(); task = nil; isWorking = false }
}

struct WebsitePaceSpeedCommandView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var form: WebsitePaceSpeedForm
  let canApply: Bool
  let apply: @MainActor (String) async throws -> Void
  init(presentation: WebsitePaceSpeedPresentation, canApply: Bool,
    apply: @escaping @MainActor (String) async throws -> Void) {
    _form = State(initialValue: .init(text: presentation.initialText, unit: presentation.unit))
    self.canApply = canApply; self.apply = apply
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("自定义配速").font(.title2.weight(.semibold)); Spacer()
        Button("关闭") { form.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text("输入单位：\(form.unit.displayName)。空输入按 0 处理。保存后请求重开；No Quit 中保留当前练习。")
        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      TextField("目标速度", text: $form.text).textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("website-pace-speed-input").disabled(!canApply || form.isWorking).onSubmit(submit)
      if let message = form.message { Text(message).fixedSize(horizontal: false, vertical: true) }
      else if !canApply { Text("配置已变化，请关闭后重新打开命令。").font(.caption) }
      else if !form.canSubmit { Text("请输入不小于 0 的有限速度。").font(.caption).foregroundStyle(.red) }
      HStack {
        if form.isWorking { ProgressView().controlSize(.small) }
        Spacer()
        Button("应用") { submit() }.keyboardShortcut(.defaultAction).disabled(!canApply || form.isWorking || !form.canSubmit)
      }
    }.padding(24).frame(minWidth: 440, idealWidth: 520).onDisappear { form.cancel() }
  }
  private func submit() { guard canApply else { return }; form.submit(apply: apply, completed: { dismiss() }) }
}
