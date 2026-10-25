import SwiftUI

enum WebsiteConfigThresholdField: String, CaseIterable, Identifiable {
  case speed, accuracy, burst
  var id: String { rawValue }
  var title: String {
    switch self {
    case .speed: "最低整体速度"; case .accuracy: "最低准确率"; case .burst: "最低单词速度"
    }
  }
  var unit: String { self == .accuracy ? "%" : "WPM" }
  var modes: [String] { self == .burst ? ["off", "fixed", "flex"] : ["off", "custom"] }
  func mode(in source: PracticeThresholdConfiguration) -> String {
    switch self {
    case .speed: source.minimumWpmMode.rawValue
    case .accuracy: source.minimumAccuracyMode.rawValue
    case .burst: source.minimumWordBurstMode.rawValue
    }
  }
  func value(in source: PracticeThresholdConfiguration) -> Double {
    switch self {
    case .speed: source.minimumWpmCustomValue
    case .accuracy: source.minimumAccuracyCustomValue
    case .burst: source.minimumWordBurstCustomValue
    }
  }
  func modeEdit(_ text: String) -> WebsiteConfigThresholdEdit? {
    if self == .burst { return MinimumWordBurstMode(rawValue: text).map(WebsiteConfigThresholdEdit.burstMode) }
    guard let mode = PracticeThresholdConfiguration.Mode(rawValue: text) else { return nil }
    return self == .speed ? .speedMode(mode) : .accuracyMode(mode)
  }
  func valueEdit(_ text: String) -> WebsiteConfigThresholdEdit? {
    guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite,
      value >= 0, self != .accuracy || value <= 100 else { return nil }
    switch self {
    case .speed: return .speedValue(value)
    case .accuracy: return .accuracyValue(value)
    case .burst: return .burstValue(value)
    }
  }
}

/// Native numeric controls use canonical WPM/% explicitly. Website command
/// input parsing/unit conversion is a separate command-surface contract.
struct WebsiteConfigThresholdEditor: View {
  let configuration: PracticeThresholdConfiguration
  let canEdit: Bool
  let apply: @MainActor (WebsiteConfigThresholdEdit) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(WebsiteConfigThresholdField.allCases) { field in
        ThresholdRow(field: field, mode: field.mode(in: configuration), value: field.value(in: configuration), apply: apply)
          .id(field.rawValue + "." + field.mode(in: configuration) + "." + String(field.value(in: configuration)))
        if field != .burst { Divider() }
      }
      Text("启用的阈值会在后续检查生效；修改不重开当前练习。关闭会保留数值；0 不等同于关闭。No Quit 进行中不能修改。")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    .disabled(!canEdit)
    .accessibilityIdentifier("website-threshold-editor")
  }

  private struct ThresholdRow: View {
    let field: WebsiteConfigThresholdField
    let apply: @MainActor (WebsiteConfigThresholdEdit) -> Void
    @State private var mode: String
    @State private var text: String
    @State private var invalid = false
    init(field: WebsiteConfigThresholdField, mode: String, value: Double,
      apply: @escaping @MainActor (WebsiteConfigThresholdEdit) -> Void) {
      self.field = field; self.apply = apply
      _mode = State(initialValue: mode); _text = State(initialValue: String(value))
    }
    var body: some View {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(field.title)
          Spacer()
          Picker("模式", selection: $mode) {
            ForEach(field.modes, id: \.self) { value in Text(modeTitle(value)).tag(value) }
          }.labelsHidden().frame(width: 120)
            .accessibilityIdentifier("website-threshold-\(field.rawValue)-mode")
          Button("应用模式") { if let edit = field.modeEdit(mode) { apply(edit) } }
            .accessibilityIdentifier("website-threshold-\(field.rawValue)-apply-mode")
        }
        HStack {
          Text("自定义数值（\(field.unit)）")
          TextField(field.unit, text: $text).textFieldStyle(.roundedBorder).frame(maxWidth: 140)
            .accessibilityIdentifier("website-threshold-\(field.rawValue)-value")
          Button("应用数值") {
            guard let edit = field.valueEdit(text) else { invalid = true; return }
            invalid = false; apply(edit)
          }.accessibilityIdentifier("website-threshold-\(field.rawValue)-apply-value")
          Spacer(minLength: 0)
        }
        Text(field == .burst ? "应用数值只修改记忆值；请选择固定或弹性模式启用。" : "应用数值会同时启用自定义模式。")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if invalid {
          Text(field == .accuracy ? "准确率请输入 0 至 100 的数字。" : "请输入有效的非负速度。")
            .font(.caption).foregroundStyle(.red)
        }
      }
    }
    private func modeTitle(_ value: String) -> String {
      switch value { case "off": "关闭"; case "custom": "自定义"; case "fixed": "固定"; default: "弹性" }
    }
  }
}
