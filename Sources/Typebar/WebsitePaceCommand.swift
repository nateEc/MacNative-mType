import Foundation

enum WebsitePaceCommandError: Error, LocalizedError {
  case invalidInput, unsupportedMode
  case interrupted(saved: Int, underlying: Error), restartFailed(saved: Int)
  var errorDescription: String? {
    switch self {
    case .invalidInput: "请输入不小于 0 的有效速度。"
    case .unsupportedMode: "当前完整配置不支持这个原生扩展配速模式。"
    case .interrupted(let saved, _): "前面 \(saved) 项配速设置已保存，后续修改未完成；请重新打开命令。"
    case .restartFailed(let saved): saved > 0 ? "配速设置已保存，新一轮尚未开始；请重试重开。" : "设置未修改，重开未完成。"
    }
  }
}

enum WebsitePaceCommand {
  static let keys: Set<String> = ["paceCaret", "paceCaretCustomSpeed"]
  struct Step: Equatable { let key: String; let value: WebsiteConfigValue; let accepted: Bool }
  struct Plan { let steps: [Step] }
  static func speed(_ raw: String, unit: TypingSpeedUnit) -> Double? {
    let value = WebsiteThresholdCommandInput.toWpm(WebsiteThresholdCommandInput.number(raw), unit: unit)
    return !value.isNaN && value >= 0 ? value : nil
  }
  @MainActor static func plan(current: [String: WebsiteConfigValue], target: PaceCaretCommandTarget,
    input: String?, context: WebsiteConfigRuntimeContext, active: Bool) throws -> Plan {
    let key: String, value: WebsiteConfigValue
    switch target {
    case .mode:
      guard let mode = target.websiteMode else { throw WebsitePaceCommandError.unsupportedMode }
      key = "paceCaret"; value = .string(mode)
    case .customSpeed:
      guard case .string(let unitName)? = current["typingSpeedUnit"], let unit = TypingSpeedUnit(rawValue: unitName),
        let input, let speed = speed(input, unit: unit) else { throw WebsitePaceCommandError.invalidInput }
      key = "paceCaretCustomSpeed"; value = .number(speed)
    }
    var steps: [Step] = []
    _ = try WebsiteConfigRuntimeProjector.edit(current: current, key: key, value: value,
      defaults: WebsiteConfigNativeProfile.defaultDocument().values,
      schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs), context: context, testActive: active,
      observeAssignment: { steps.append(.init(key: $0, value: $1, accepted: $2)) })
    return .init(steps: steps)
  }
  static func admits(_ draft: WebsiteConfigNativeDraft, from previous: WebsiteConfigNativeDraft) -> Bool {
    guard case .edited(let edit) = draft.origin, keys.contains(edit.key), draft.projection.rejectedKeys.isEmpty,
      draft.projection.events.count == 1, draft.projection.events.allSatisfy({ $0.key == edit.key && $0.nosave == false }),
      draft.projection.runtime.count == previous.projection.runtime.count else { return false }
    return previous.projection.runtime.allSatisfy { key, value in key == edit.key || draft.projection.runtime[key] == value }
  }
}

extension PaceCaretCommandTarget {
  var websiteMode: String? {
    switch self {
    case .mode(.off): "off"; case .mode(.personalBest): "pb"
    case .mode(.activeTagPersonalBest), .mode(.accountTagPersonalBest): "tagPb"
    case .mode(.lastTest): "last"; case .mode(.recentAverage): "average"; case .mode(.dailyBest): "daily"
    default: nil
    }
  }
}
