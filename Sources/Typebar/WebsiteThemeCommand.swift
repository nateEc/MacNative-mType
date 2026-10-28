import Foundation

enum PracticeThemeEdit: Equatable {
  case select(ThemeCommandTarget), followSystem(Bool), light(AppTheme), dark(AppTheme)
  case favorites([AppTheme]), random(RandomThemeMode), customEnabled(Bool)
}

enum WebsiteThemeCommandError: Error, LocalizedError {
  case unsupported, interrupted(saved: Int, underlying: Error)
  var errorDescription: String? {
    switch self {
    case .unsupported: "此主题不能无损写入当前完整配置。"
    case .interrupted(let saved, _): "前面 \(saved) 项主题设置已保存，后续修改未完成；请重新打开主题菜单。"
    }
  }
}

enum WebsiteThemeCommand {
  struct Completion { let disabledSystemFollowing: Bool }
  struct Field: Equatable { let key: String; let value: WebsiteConfigValue }
  struct Step: Equatable { let key: String; let value: WebsiteConfigValue; let accepted: Bool }
  struct Plan { let steps: [Step]; let disablesSystem: Bool }
  @MainActor static func fields(for edit: PracticeThemeEdit, customThemes: [CustomThemeDefinition]) throws -> [Field] {
    func theme(_ key: String, _ theme: AppTheme) throws -> [Field] {
      guard theme != .grove else { throw WebsiteThemeCommandError.unsupported }
      return [.init(key: key, value: .string(theme.rawValue))]
    }
    switch edit {
    case .select(.builtIn(let value)): return try theme("theme", value)
    case .light(let value): return try theme("themeLight", value)
    case .dark(let value): return try theme("themeDark", value)
    case .followSystem(let value): return [.init(key: "autoSwitchTheme", value: .bool(value))]
    case .customEnabled(let value): return [.init(key: "customTheme", value: .bool(value))]
    case .favorites(let values):
      guard !values.contains(.grove) else { throw WebsiteThemeCommandError.unsupported }
      return [.init(key: "favThemes", value: .array(values.map { .string($0.rawValue) }))]
    case .random(let value): return [.init(key: "randomTheme", value: .string(value.rawValue))]
    case .select(.custom(let id)):
      guard let value = customThemes.first(where: { $0.id == id }), value.fadedText == value.panel else {
        throw WebsiteThemeCommandError.unsupported
      }
      // The website has ten opaque RGB slots. Native-only alpha, precision or
      // the eleventh faded-text slot must never be silently discarded.
      func hex(_ color: ThemeColor) throws -> WebsiteConfigValue {
        guard color.opacity == 1 else { throw WebsiteThemeCommandError.unsupported }
        let bytes = try [color.red, color.green, color.blue].map { component -> Int in
          guard component.isFinite, (0...1).contains(component) else { throw WebsiteThemeCommandError.unsupported }
          let byte = Int((component * 255).rounded())
          guard Double(byte) / 255 == component else { throw WebsiteThemeCommandError.unsupported }
          return byte
        }
        return .string(String(format: "#%02x%02x%02x", bytes[0], bytes[1], bytes[2]))
      }
      let colors = try [value.background, value.accent, value.caret, value.secondaryText, value.panel, value.text,
        value.error, value.extraInput, value.colorfulError, value.colorfulExtraInput].map(hex)
      let channels = [value.background.red, value.background.green, value.background.blue].map { Int(($0 * 255).rounded()) }
      guard value.prefersDark == (channels.max()! + channels.min()! < 255) else { throw WebsiteThemeCommandError.unsupported }
      return [.init(key: "customTheme", value: .bool(true)), .init(key: "customThemeColors", value: .array(colors))]
    }
  }

  @MainActor static func plan(current: [String: WebsiteConfigValue], fields: [Field],
    context: WebsiteConfigRuntimeContext, active: Bool) throws -> Plan {
    var runtime = current, steps: [Step] = []
    func append(_ field: Field) throws {
      guard WebsiteConfigNativeThemes.mappedKeys.contains(field.key) else { throw WebsiteThemeCommandError.unsupported }
      let result = try WebsiteConfigRuntimeProjector.edit(current: runtime, key: field.key, value: field.value,
        defaults: WebsiteConfigNativeProfile.defaultDocument().values,
        schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs), context: context, testActive: active,
        observeAssignment: { steps.append(.init(key: $0, value: $1, accepted: $2)) })
      runtime = result.runtime
    }
    for field in fields { try append(field) }
    // Config setters dispatch synchronously. The controller's awaited visual
    // application disables system following after the command's setters.
    let disables = runtime["autoSwitchTheme"] == .bool(true) && steps.contains {
      $0.accepted && ["theme", "customTheme", "customThemeColors"].contains($0.key)
    }
    if disables { try append(.init(key: "autoSwitchTheme", value: .bool(false))) }
    return .init(steps: steps, disablesSystem: disables)
  }

  static func admits(_ draft: WebsiteConfigNativeDraft, from previous: WebsiteConfigNativeDraft) -> Bool {
    guard case .edited(let edit) = draft.origin, WebsiteConfigNativeThemes.mappedKeys.contains(edit.key),
      draft.projection.rejectedKeys.isEmpty, draft.projection.events.count == 1,
      draft.projection.events.allSatisfy({ $0.key == edit.key && $0.nosave == false }),
      draft.projection.runtime.count == previous.projection.runtime.count else { return false }
    return previous.projection.runtime.allSatisfy { key, value in key == edit.key || draft.projection.runtime[key] == value }
  }
}
