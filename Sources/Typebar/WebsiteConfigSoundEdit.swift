import Foundation

enum WebsiteSoundCommandError: Error, LocalizedError {
  case unsupportedTone
  var errorDescription: String? { "此原创扩展音型仅适用于 Typebar 设置，不能写入当前完整配置。" }
}

enum WebsiteConfigSoundEdit {
  static let keys: Set<String> = ["soundVolume", "playSoundOnClick", "playSoundOnError", "playTimeWarning"]
  static func admits(_ draft: WebsiteConfigNativeDraft, from previous: WebsiteConfigNativeDraft) -> Bool {
    guard case .edited(let edit) = draft.origin, keys.contains(edit.key), draft.projection.rejectedKeys.isEmpty,
      draft.projection.events.count == 1, draft.projection.events.allSatisfy({ $0.key == edit.key && $0.nosave == false }),
      draft.projection.runtime.count == previous.projection.runtime.count else { return false }
    return previous.projection.runtime.allSatisfy { key, value in key == edit.key || draft.projection.runtime[key] == value }
  }
  static func volume(_ raw: String) -> Double? {
    let value = WebsiteThresholdCommandInput.number(raw)
    return value.isFinite && (0...1).contains(value) ? value : nil
  }
}

extension SoundCommandTarget {
  var websiteKey: String {
    switch self {
    case .volume: "soundVolume"; case .click: "playSoundOnClick"
    case .error: "playSoundOnError"; case .timeWarning: "playTimeWarning"
    }
  }
  var websiteValue: WebsiteConfigValue {
    if case .volume(let value) = self { return .number(value) }
    let prefix = "sound.\(websiteKey)."
    guard let item = SoundCommandCatalog.items.first(where: { $0.id.hasPrefix(prefix) && SoundCommandCatalog.target(for: $0.id) == self }) else { return .null }
    return .string(String(item.id.dropFirst(prefix.count)))
  }
}
