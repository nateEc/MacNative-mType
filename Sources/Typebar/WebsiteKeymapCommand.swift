import Foundation

enum WebsiteKeymapCommandError: Error, LocalizedError {
  case invalidInput, failedOverride(saved: Int), interrupted(saved: Int, underlying: Error), restartFailed(saved: Int)
  var errorDescription: String? {
    switch self {
    case .invalidInput: "请输入 0.5 至 3.5、步长为 0.1 的键盘大小，或重新选择有效键盘选项。"
    case .failedOverride(let saved): "前面 \(saved) 项键盘设置已保存，后续依赖被拒绝。"
    case .interrupted(let saved, _): "前面 \(saved) 项键盘设置已保存，后续修改未完成；请重新打开命令。"
    case .restartFailed(let saved): "已保存 \(saved) 项键盘设置，但重开未完成。"
    }
  }
}

enum WebsiteKeymapCommandTarget: Equatable {
  case display(KeyboardGuideCommandTarget), layout(KeyboardGuideLayoutCommandTarget), size(Double)
  var key: String {
    switch self {
    case .display(.mode): "keymapMode"
    case .display(.style): "keymapStyle"
    case .display(.legend): "keymapLegendStyle"
    case .display(.keys): "keymapKeys"
    case .layout: "keymapLayout"
    case .size: "keymapSize"
    }
  }
  var value: WebsiteConfigValue {
    switch self {
    case .display(.mode(let value)): .string(value.rawValue)
    case .display(.style(let value)): .string(value.rawValue)
    case .display(.legend(let value)): .string(value.rawValue)
    case .display(.keys(let value)): .string(value.rawValue)
    case .layout(.inputSync): .string("overrideSync")
    case .layout(.builtIn(let value)): OfficialLayoutCommandCatalog.name(for: value).map(WebsiteConfigValue.string) ?? .null
    case .size(let value): .number(value)
    }
  }
  var requestsRestart: Bool { if case .layout = self { true } else { false } }
}

@MainActor enum WebsiteKeymapCommand {
  static let keys: Set<String> = ["keymapMode", "keymapStyle", "keymapLegendStyle", "keymapKeys", "keymapLayout", "keymapSize"]
  private static var schema: WebsiteConfigSchema { .init(catalogs: WebsiteConfigNativeProfile.catalogs) }
  struct Step: Equatable { let key: String; let value: WebsiteConfigValue; let accepted: Bool }
  struct Plan { let steps: [Step]; let failedOverride: Bool }
  static func size(_ raw: String) -> Double? {
    let value = WebsiteThresholdCommandInput.number(raw)
    return schema.accepts(.number(value), for: "keymapSize") ? value : nil
  }
  @MainActor static func plan(current: [String: WebsiteConfigValue], target: WebsiteKeymapCommandTarget,
    context: WebsiteConfigRuntimeContext, active: Bool) throws -> Plan {
    guard schema.accepts(target.value, for: target.key) else { throw WebsiteKeymapCommandError.invalidInput }
    var steps: [Step] = []
    do {
      _ = try WebsiteConfigRuntimeProjector.edit(current: current, key: target.key, value: target.value,
        defaults: WebsiteConfigNativeProfile.defaultDocument().values, schema: schema, context: context, testActive: active,
        observeAssignment: { steps.append(.init(key: $0, value: $1, accepted: $2)) })
      return .init(steps: steps, failedOverride: false)
    } catch WebsiteConfigProjectionError.failedOverride { return .init(steps: steps, failedOverride: true) }
  }
  static func admits(_ draft: WebsiteConfigNativeDraft, from previous: WebsiteConfigNativeDraft) -> Bool {
    guard case .edited(let edit) = draft.origin, keys.contains(edit.key), draft.projection.rejectedKeys.isEmpty,
      draft.projection.events.count == 1, draft.projection.events.allSatisfy({ $0.key == edit.key && $0.nosave == false }),
      draft.projection.runtime.count == previous.projection.runtime.count else { return false }
    return previous.projection.runtime.allSatisfy { key, value in key == edit.key || draft.projection.runtime[key] == value }
  }
}
