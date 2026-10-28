import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// NSSlider supplies continuous input; a tracked mouse gesture commits once.
@MainActor final class BackgroundSettingsSliderView: NSSlider {
  private var configuredTarget: BackgroundSettingsTarget?
  private var gestureTarget: BackgroundSettingsTarget?
  private var tracking = false
  private var initialValue = 0.0
  private var lastSent = Double.nan
  private var projectedValue = Double.nan
  private var stride = 0.1
  var input: ((Double, BackgroundSettingsTarget) -> Bool)?
  var commit: ((Double, BackgroundSettingsTarget) -> Bool)?
  override init(frame: NSRect) {
    super.init(frame: frame)
    isContinuous = true; target = self; action = #selector(changed)
  }
  required init?(coder: NSCoder) { nil }
  func configure(value: Double, range: ClosedRange<Double>, step: Double, target: BackgroundSettingsTarget?, enabled: Bool) {
    minValue = range.lowerBound; maxValue = range.upperBound; stride = step; isEnabled = enabled
    if target != configuredTarget || projectedValue != value {
      doubleValue = value; projectedValue = value; lastSent = value
    }
    configuredTarget = target
  }
  override func mouseDown(with event: NSEvent) {
    tracking = true; gestureTarget = configuredTarget; initialValue = doubleValue; lastSent = doubleValue
    defer {
      if doubleValue != initialValue, let gestureTarget { _ = commit?(doubleValue, gestureTarget) }
      tracking = false; gestureTarget = nil
    }
    super.mouseDown(with: event)
  }
  @objc private func changed() {
    guard let destination = tracking ? gestureTarget : configuredTarget else { return }
    let value = BackgroundSettingsPreferences.sanitized(doubleValue, range: minValue...maxValue, step: stride)
    doubleValue = value
    guard value != lastSent else { return }; lastSent = value
    _ = input?(value, destination)
    if !tracking { _ = commit?(value, destination) }
  }
}

struct BackgroundSettingsSlider: NSViewRepresentable {
  let model: BackgroundSettingsPreferences
  let component: Int
  func makeNSView(context: Context) -> BackgroundSettingsSliderView { .init(frame: .zero) }
  func updateNSView(_ view: BackgroundSettingsSliderView, context: Context) {
    view.configure(value: model.refs[component], range: model.range(component), step: model.step(component),
      target: model.target, enabled: model.canEdit)
    view.input = { [weak model] value, target in model?.input(component: component, value: value, target: target) ?? false }
    view.commit = { [weak model] value, target in model?.commit(component: component, value: value, target: target) ?? false }
    view.setAccessibilityLabel(["背景模糊", "背景亮度", "背景饱和度", "背景不透明度"][component])
  }
}

struct BackgroundSettingsControls: View {
  let settings: AppSettings
  @State private var model: BackgroundSettingsPreferences
  @State private var importing = false
  @State private var message: String?
  @FocusState private var addressFocused: Bool
  init(settings: AppSettings) {
    self.settings = settings; _model = State(initialValue: .init(settings: settings))
  }
  var body: some View {
    Group {
      if model.source == nil || !settings.hasLocalBackground {
        TextField("背景图片 URL", text: $model.addressDraft).textFieldStyle(.roundedBorder)
          .focused($addressFocused)
          .onSubmit { applyURL(model.addressDraft) }
          .onChange(of: addressFocused) { before, focused in
            if before && !focused && model.source != nil { applyURL(model.addressDraft) }
          }
          .onChange(of: model.addressDraft) { _, value in
            if model.source != nil { message = model.isAddressValid(value) ? nil : "请输入有效的 HTTP(S) 图片地址。" }
          }
        HStack {
          Button("应用 URL") { applyURL(model.addressDraft) }
          if !model.url.isEmpty { Button("移除 URL") { applyURL("") } }
        }
      }
      HStack {
        if model.source == nil || !settings.hasLocalBackground {
          Button(settings.hasLocalBackground ? "替换本地图片…" : "选择本地图片…") { importing = true }
        }
        if settings.hasLocalBackground { Button("移除本地图片", role: .destructive) { removeLocal() } }
      }
      Picker("背景图片适配", selection: Binding(get: { model.fit }, set: { value in
        if value == model.fit { return }
        if !CustomBackgroundCommandApplication.applyImmediate(.fit(value), to: settings) { message = "当前背景未能更新。" }
      })) {
        ForEach(CustomBackgroundFit.allCases) { Text($0.displayName).tag($0) }
      }
      if model.filtersVisible {
        ForEach(0..<4) { index in
          VStack(alignment: .leading) {
            HStack {
              Text(["背景模糊", "背景亮度", "背景饱和度", "背景不透明度"][index])
              Spacer()
              Text(label(model.labels[index])).monospacedDigit()
            }
            BackgroundSettingsSlider(model: model, component: index).frame(height: 22)
          }
        }
      }
      if let message { Text(message).font(.caption).foregroundStyle(.red) }
    }
    .disabled(!model.canEdit)
    .onAppear { model.synchronize() }
    .onChange(of: model.source) { _, _ in model.synchronize() }
    .onChange(of: settings.customBackgroundFilter) { _, _ in model.synchronize() }
    .onChange(of: model.url) { _, _ in model.synchronize() }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
      do {
        let file = try result.get(), access = file.startAccessingSecurityScopedResource()
        defer { if access { file.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: file)
        if let accepted = settings.preferenceConfigurationSaves.applyBackgroundEdit(.localFile(data)) {
          message = accepted ? nil : "当前本地背景未能更新。"
        } else { try settings.importLocalBackground(data: data); message = nil }
      } catch { message = error.localizedDescription }
    }
  }
  private func applyURL(_ value: String) {
    if model.submitAddress(value) { message = nil }
    else { message = "请输入有效的 HTTP(S) 图片 URL，或重新选择当前练习窗口。" }
  }
  private func removeLocal() {
    do {
      if let accepted = settings.preferenceConfigurationSaves.applyBackgroundEdit(.removeLocal) { message = accepted ? nil : "本地背景未能移除。" }
      else { try settings.removeLocalBackground(); message = nil }
    } catch { message = error.localizedDescription }
  }
  private func label(_ value: Double) -> String {
    if value == .infinity { return "Infinity" }; if value == -.infinity { return "-Infinity" }
    if value == 0 { return "0.0" }; if abs(value) >= 1e21 { return String(value) }
    return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
  }
}
