import Observation
import SwiftUI

struct WebsiteSoundVolumePresentation: Identifiable {
  static let item = CommandPaletteItem(id: "setSoundVolumeCustom", title: "自定义声音音量…", subtitle: "输入 0 至 1 的音量", systemImage: "speaker.wave.2", keywords: ["soundVolume", "volume", "自定义", "音量"], group: .settings)
  let id: UUID
  let initialText: String
  init(publication: WebsiteConfigCommitCoordinator.Publication) {
    id = publication.applicationID
    let text = String(publication.draft.behavior.soundVolume)
    initialText = text.hasSuffix(".0") ? String(text.dropLast(2)) : text
  }
}

@MainActor @Observable final class WebsiteSoundVolumeForm {
  var text: String
  private(set) var isWorking = false
  private(set) var message: String?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var request = UUID()
  init(text: String) { self.text = text }
  var value: Double? { WebsiteConfigSoundEdit.volume(text) }
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
        message = (error as? LocalizedError)?.errorDescription ?? "音量未保存，请检查配置后重试。"
      }
    }
  }
  func cancel() { request = UUID(); task?.cancel(); task = nil; isWorking = false }
}

struct WebsiteSoundVolumeCommandView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var form: WebsiteSoundVolumeForm
  let canApply: Bool
  let apply: @MainActor (Double) async throws -> Void
  init(presentation: WebsiteSoundVolumePresentation, canApply: Bool,
    apply: @escaping @MainActor (Double) async throws -> Void) {
    _form = State(initialValue: .init(text: presentation.initialText)); self.canApply = canApply; self.apply = apply
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("自定义声音音量").font(.title2.weight(.semibold)); Spacer()
        Button("关闭") { form.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text("输入 0 至 1；空输入按 0 处理。保存后不试听，当前练习继续。")
        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      TextField("音量", text: $form.text).textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("website-sound-volume-input").disabled(!canApply || form.isWorking).onSubmit(submit)
      if let message = form.message { Text(message).fixedSize(horizontal: false, vertical: true) }
      else if !canApply { Text("配置已变化，请关闭后重新打开命令。").font(.caption) }
      else if form.value == nil { Text("请输入 0 至 1 的有效数值。").font(.caption).foregroundStyle(.red) }
      HStack {
        if form.isWorking { ProgressView().controlSize(.small) }
        Spacer()
        Button("应用") { submit() }.keyboardShortcut(.defaultAction)
          .disabled(!canApply || form.isWorking || form.value == nil)
      }
    }.padding(24).frame(minWidth: 440, idealWidth: 520).onDisappear { form.cancel() }
  }
  private func submit() { guard canApply else { return }; form.submit(apply: apply, completed: { dismiss() }) }
}
