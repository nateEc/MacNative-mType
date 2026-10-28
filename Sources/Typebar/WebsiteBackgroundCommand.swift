import Foundation

enum PracticeBackgroundEdit: Equatable {
  case address(String), fit(CustomBackgroundFit), filter(CustomBackgroundCommandEditorKind, String)
  case localFile(Data), remove
  case selectedFile(Data, String)
  case removeLocal
  case settingsFilter(WebsiteBackgroundSettingsState.Token, Int, Double)
  case previewFilter(WebsiteBackgroundSettingsState.Token, [Double])
}
enum WebsiteBackgroundCommandError: Error, LocalizedError {
  case invalidInput
  var errorDescription: String? { "请输入有效的背景地址或数值。" }
}
enum WebsiteBackgroundCommand {
  static let keys: Set<String> = ["customBackground", "customBackgroundSize", "customBackgroundFilter"]
  static func initialText(_ kind: CustomBackgroundCommandEditorKind, preferences: WebsiteConfigNativePagePreferences) -> String {
    let filter = preferences.backgroundFilter
    let number: Double
    switch kind {
    case .remoteURL: return String(decoding: preferences.backgroundAddress.stringUnits ?? [], as: UTF16.self)
    case .blur: number = filter.blurRem
    case .brightness: number = filter.brightness
    case .saturation: number = filter.saturation
    case .opacity: number = filter.opacity
    }
    if number == .infinity { return "Infinity" }; if number == -.infinity { return "-Infinity" }
    if number == 0 { return "0" }
    var text = String(number); if text.hasSuffix(".0") { text.removeLast(2) }; return text
  }
  static func field(_ edit: PracticeBackgroundEdit, current: WebsiteConfigNativeDraft) throws -> (String, WebsiteConfigValue) {
    let key: String, value: WebsiteConfigValue
    switch edit {
    case .settingsFilter(_, let index, let number):
      guard (0..<4).contains(index), number.isFinite,
        case .array(var values) = current.settingsStoreValues["customBackgroundFilter"], values.count == 4
      else { throw WebsiteBackgroundCommandError.invalidInput }
      values[index] = .number(number); key = "customBackgroundFilter"; value = .array(values)
    case .address(let address): key = "customBackground"; value = .string(address)
    case .remove: key = "customBackground"; value = .string("")
    case .fit(let fit): key = "customBackgroundSize"; value = .string(fit.rawValue)
    case .filter(let kind, let input):
      let index: Int
      switch kind { case .blur: index = 0; case .brightness: index = 1; case .saturation: index = 2; case .opacity: index = 3; case .remoteURL: throw WebsiteBackgroundCommandError.invalidInput }
      let number = WebsiteConfigValue.parseFloat(input)
      guard !input.isEmpty, !number.isNaN, case .array(var values) = current.projection.runtime["customBackgroundFilter"], values.count == 4
      else { throw WebsiteBackgroundCommandError.invalidInput }
      values[index] = .number(number); key = "customBackgroundFilter"; value = .array(values)
    case .localFile, .selectedFile, .removeLocal, .previewFilter: throw WebsiteBackgroundCommandError.invalidInput
    }
    let admitted = key == "customBackground" ? value.trimmingWebsiteString : value
    guard WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs).accepts(admitted, for: key) else { throw WebsiteBackgroundCommandError.invalidInput }
    return (key, value)
  }
  static func admits(_ draft: WebsiteConfigNativeDraft, from previous: WebsiteConfigNativeDraft) -> Bool {
    guard case .edited(let edit) = draft.origin, keys.contains(edit.key), draft.projection.rejectedKeys.isEmpty,
      draft.projection.events.count == 1, draft.projection.events.allSatisfy({ $0.key == edit.key && $0.nosave == false }),
      draft.projection.runtime.count == previous.projection.runtime.count else { return false }
    return previous.projection.runtime.allSatisfy { key, value in key == edit.key || draft.projection.runtime[key] == value }
  }
}
