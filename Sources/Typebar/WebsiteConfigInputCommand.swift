import Foundation

enum WebsiteConfigInputCommand {
  static let keys: Set<String> = ["freedomMode", "strictSpace", "oppositeShiftMode", "stopOnError", "deleteOnError",
    "confidenceMode", "quickEnd", "indicateTypos", "compositionDisplay", "hideExtraLetters", "codeUnindentOnBackspace"]
  struct Step: Equatable { let key: String; let value: WebsiteConfigValue; let accepted: Bool }
  struct Plan { let steps: [Step]; let failedOverride: Bool }
  @MainActor static func plan(current: [String: WebsiteConfigValue], target: InputRuleCommandTarget,
    context: WebsiteConfigRuntimeContext, active: Bool) throws -> Plan {
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
    guard case .edited(let edit) = draft.origin, keys.contains(edit.key), draft.projection.rejectedKeys.isEmpty,
      draft.projection.events.count == 1,
      draft.projection.events.allSatisfy({ $0.key == edit.key && $0.nosave == false }),
      draft.projection.runtime.count == previous.projection.runtime.count else { return false }
    return previous.projection.runtime.allSatisfy { key, value in key == edit.key || draft.projection.runtime[key] == value }
  }
}

enum WebsiteInputCommandError: Error, LocalizedError {
  case failedOverride(saved: Int), interrupted(saved: Int, underlying: Error)
  var errorDescription: String? {
    switch self {
    case .failedOverride(let saved): saved > 0 ? "前面的输入规则已保存；后续依赖被拒绝，原命令未完成。" : "依赖规则被拒绝，输入命令未完成。"
    case .interrupted(let saved, _): "前面 \(saved) 项输入规则已保存，后续设置未完成；请重新打开命令。"
    }
  }
}

extension InputRuleCommandTarget {
  var websiteKey: String {
    switch self {
    case .freedomMode: "freedomMode"; case .strictSpace: "strictSpace"
    case .oppositeShiftMode: "oppositeShiftMode"; case .stopOnError: "stopOnError"
    case .deleteOnError: "deleteOnError"; case .confidenceMode: "confidenceMode"
    case .quickEnd: "quickEnd"; case .indicateTypos: "indicateTypos"
    case .compositionDisplay: "compositionDisplay"; case .hideExtraLetters: "hideExtraLetters"
    case .lazyMode: "lazyMode"; case .codeUnindentOnBackspace: "codeUnindentOnBackspace"
    }
  }
  var websiteValue: WebsiteConfigValue {
    switch self {
    case .freedomMode(let value), .strictSpace(let value), .quickEnd(let value), .hideExtraLetters(let value),
      .lazyMode(let value), .codeUnindentOnBackspace(let value): .bool(value)
    case .oppositeShiftMode(let value): .string(value.rawValue)
    case .stopOnError(let value): .string(value.rawValue)
    case .deleteOnError(let value): .string(value == .letterHard ? "letter_hard" : value == .wordHard ? "word_hard" : value.rawValue)
    case .confidenceMode(let value): .string(value == .maximum ? "max" : value.rawValue)
    case .indicateTypos(let value): .string(value.rawValue)
    case .compositionDisplay(let value): .string(value.rawValue)
    }
  }
}
