import Foundation

enum WebsiteAppearanceCommandError: Error, LocalizedError {
  case unsupportedOption, failedOverride(saved: Int), interrupted(saved: Int, underlying: Error)
  var errorDescription: String? {
    switch self {
    case .unsupportedOption: "此显示选项不能写入当前完整配置。"
    case .failedOverride(let saved): saved > 0 ? "前面的显示设置已保存，后续依赖被拒绝。" : "依赖设置被拒绝，显示命令未完成。"
    case .interrupted(let saved, _): "前面 \(saved) 项显示设置已保存，后续修改未完成；请重新打开命令。"
    }
  }
}

enum WebsiteAppearanceCommand {
  static let keys: Set<String> = ["timerStyle", "liveSpeedStyle", "liveAccStyle", "liveBurstStyle", "timerColor", "timerOpacity",
    "highlightMode", "typedEffect", "tapeMode", "smoothLineScroll", "showAllLines", "typingSpeedUnit",
    "alwaysShowDecimalPlaces", "startGraphsAtZero", "monkey"]
  struct Step: Equatable { let key: String; let value: WebsiteConfigValue; let accepted: Bool }
  struct Plan { let steps: [Step]; let failedOverride: Bool }
  @MainActor static func plan(current: [String: WebsiteConfigValue], target: AppearanceCommandTarget,
    context: WebsiteConfigRuntimeContext, active: Bool) throws -> Plan {
    guard target.websiteValue != .null else { throw WebsiteAppearanceCommandError.unsupportedOption }
    var steps: [Step] = []
    do {
      _ = try WebsiteConfigRuntimeProjector.edit(current: current, key: target.websiteKey, value: target.websiteValue,
        defaults: WebsiteConfigNativeProfile.defaultDocument().values,
        schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs), context: context, testActive: active,
        observeAssignment: { steps.append(.init(key: $0, value: $1, accepted: $2)) })
      return .init(steps: steps, failedOverride: false)
    } catch WebsiteConfigProjectionError.failedOverride { return .init(steps: steps, failedOverride: true) }
  }
  static func admits(_ draft: WebsiteConfigNativeDraft, from previous: WebsiteConfigNativeDraft) -> Bool {
    guard case .edited(let edit) = draft.origin, keys.contains(edit.key),
      edit.key != "monkey" || draft.projection.runtime["monkey"] == .bool(false), draft.projection.rejectedKeys.isEmpty,
      draft.projection.events.count == 1, draft.projection.events.allSatisfy({ $0.key == edit.key && $0.nosave == false }),
      draft.projection.runtime.count == previous.projection.runtime.count else { return false }
    return previous.projection.runtime.allSatisfy { key, value in key == edit.key || draft.projection.runtime[key] == value }
  }
}

extension AppearanceCommandTarget {
  var websiteKey: String {
    switch self {
    case .progress: "timerStyle"; case .speed: "liveSpeedStyle"; case .accuracy: "liveAccStyle"; case .burst: "liveBurstStyle"
    case .color: "timerColor"; case .opacity: "timerOpacity"; case .highlight: "highlightMode"; case .typedEffect: "typedEffect"
    case .tape: "tapeMode"; case .smoothLineScroll: "smoothLineScroll"; case .showAllLines: "showAllLines"
    case .speedUnit: "typingSpeedUnit"; case .alwaysShowDecimalPlaces: "alwaysShowDecimalPlaces"; case .startGraphsAtZero: "startGraphsAtZero"
    }
  }
  var websiteValue: WebsiteConfigValue {
    switch self {
    case .smoothLineScroll(let value), .showAllLines(let value), .alwaysShowDecimalPlaces(let value), .startGraphsAtZero(let value): return .bool(value)
    case .speedUnit(let unit): return .string(unit.rawValue) // WPH is importable but hidden in the source menu.
    default:
      let prefix = "appearance.\(websiteKey)."
      guard let item = AppearanceCommandCatalog.items.first(where: { $0.id.hasPrefix(prefix) && AppearanceCommandCatalog.target(for: $0.id) == self }) else { return .null }
      return .string(String(item.id.dropFirst(prefix.count)))
    }
  }
}
