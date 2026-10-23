import Foundation

struct WebsiteConfigRuntimeContext: Decodable {
  var authenticated = false
  var documentComplete = true
  var customThemeCount = 0
  var development = false
}

struct WebsiteConfigApplicationEvent: Equatable, Decodable {
  var key: String
  var previousValue: WebsiteConfigValue?
  var newValue: WebsiteConfigValue?
  var nosave: Bool?
}

struct WebsiteConfigRuntimeProjection {
  var requested: [String: WebsiteConfigValue]
  var runtime: [String: WebsiteConfigValue]
  var rejectedKeys: [String]
  var events: [WebsiteConfigApplicationEvent]
}

enum WebsiteConfigProjectionError: Error { case invalidInput, invalidOrder, failedOverride }

enum WebsiteConfigRuntimeProjector {
  /// Normalized website input only. This never installs settings, emits UI
  /// notifications, persists preferences or restores a native backup.
  static func project(
    requested: [String: WebsiteConfigValue], defaults: [String: WebsiteConfigValue],
    orderedKeys: [String], schema: WebsiteConfigSchema, context: WebsiteConfigRuntimeContext,
    admitsFunbox: (WebsiteConfigValue, [String: WebsiteConfigValue]) -> Bool
  ) throws -> WebsiteConfigRuntimeProjection {
    guard Set(requested.keys) == schema.keys, Set(defaults.keys) == schema.keys,
      requested.allSatisfy({ schema.accepts($0.value, for: $0.key) }),
      defaults.allSatisfy({ schema.accepts($0.value, for: $0.key) }), defaults["funbox"] == .array([])
    else { throw WebsiteConfigProjectionError.invalidInput }
    guard orderedKeys.count == schema.keys.count, Set(orderedKeys) == schema.keys
    else { throw WebsiteConfigProjectionError.invalidOrder }
    let last = ["keymapMode", "minWpm", "minAcc", "minBurst", "paceCaret", "quoteLength",
      "words", "time", "mode", "numbers", "punctuation", "funbox"]
    let late = Set(last)
    var result = WebsiteConfigRuntimeProjection(requested: requested, runtime: defaults,
      rejectedKeys: [], events: [.init(key: "fullConfigChange")])

    func assign(_ key: String, _ proposed: WebsiteConfigValue) throws -> Bool {
      var value = proposed
      let previous = result.runtime[key]
      // Value overrides precede admission and schema validation.
      switch key {
      case "punctuation", "numbers":
        if result.runtime["mode"] == .string("quote") { value = .bool(false) }
      case "customLayoutfluid", "customPolyglot":
        if case .array(let values) = value {
          var unique: [WebsiteConfigValue] = []
          for value in values where !unique.contains(value) { unique.append(value) }
          value = .array(unique)
        }
      case "keymapSize":
        if case .number(let number) = value { value = .number(((min(3.5, max(0.5, number)) + Double.ulpOfOne) * 10).rounded() / 10) }
      case "customBackground":
        if case .string(let string) = value { value = .string(WebsiteConfigValue.trimmingWebsiteWhitespace(string)) }
      case "customThemeColors":
        if case .array(let colors) = value, colors.allSatisfy({ $0 == colors.first }) {
          value = defaults[key] ?? value
        }
      case "accountChart":
        if case .array(var values) = value, values.count == 4, values[0] == .string("off"), values[1] == .string("off") {
          let first = result.runtime[key].flatMap { if case .array(let items) = $0 { items.first } else { nil } }
          values[values[0] == first ? 0 : 1] = .string("on")
          value = .array(values)
          // The source mutates this particular requested array in place.
          result.requested[key] = value
        }
      case "ads": if context.development { value = .string("off") }
      default: break
      }
      let blocked: Bool
      switch key {
      case "paceCaret": blocked = context.documentComplete && !context.authenticated
        && (value == .string("pb") || value == .string("tagPb"))
      case "randomTheme": blocked = value == .string("custom")
        && (!context.authenticated || context.customThemeCount == 0)
      case "showAllLines": blocked = value == .bool(true) && result.runtime["tapeMode"] != .string("off")
      case "funbox": blocked = !admitsFunbox(value, result.runtime)
      default: blocked = false
      }
      guard !blocked, schema.accepts(value, for: key) else { return false }
      // Dependent setters retain the same event/order semantics as top-level setters.
      let children: [(String, WebsiteConfigValue)]
      switch key {
      case "words": children = result.runtime["mode"] != .string("words") ? [("mode", .string("words"))] : []
      case "time": children = result.runtime["mode"] != .string("time") ? [("mode", .string("time"))] : []
      case "quoteLength": children = result.runtime["mode"] != .string("quote") ? [("mode", .string("quote"))] : []
      case "mode": children = [WebsiteConfigValue.string("quote"), .string("custom"), .string("zen")].contains(value)
        ? [("numbers", .bool(false)), ("punctuation", .bool(false))] : []
      case "minWpmCustomSpeed": children = [("minWpm", .string("custom"))]
      case "minAccCustom": children = [("minAcc", .string("custom"))]
      case "paceCaretCustomSpeed": children = [("paceCaret", .string("custom"))]
      case "freedomMode": children = value == .bool(true) ? [("confidenceMode", .string("off"))] : []
      case "stopOnError": children = value != .string("off")
        ? [("confidenceMode", .string("off")), ("deleteOnError", .string("off"))] : []
      case "deleteOnError": children = value != .string("off")
        ? [("confidenceMode", .string("off")), ("stopOnError", .string("off"))] : []
      case "confidenceMode": children = value != .string("off")
        ? [("freedomMode", .bool(false)), ("stopOnError", .string("off")), ("deleteOnError", .string("off"))] : []
      case "liveSpeedStyle", "liveAccStyle": children = value == .string("text") ? [("monkey", .bool(false))] : []
      case "tapeMode": children = value != .string("off") ? [("showAllLines", .bool(false))] : []
      case "keymapLayout", "keymapStyle", "keymapLegendStyle", "keymapKeys", "keymapSize":
        children = result.runtime["keymapMode"] == .string("off") ? [("keymapMode", .string("static"))] : []
      case "theme": children = [("customTheme", .bool(false))]
      case "monkey": children = value == .bool(true) ? ["liveSpeedStyle", "liveAccStyle"].compactMap {
        result.runtime[$0] == .string("text") ? ($0, .string("mini")) : nil
      } : []
      default: children = []
      }
      for (child, value) in children where result.runtime[child] != value {
        guard try assign(child, value) else { throw WebsiteConfigProjectionError.failedOverride }
      }
      result.runtime[key] = value
      result.events.append(.init(key: key, previousValue: previous, newValue: value, nosave: true))
      return true
    }
    for key in orderedKeys.filter({ !late.contains($0) }) + last {
      if let value = result.requested[key], try !assign(key, value) { result.rejectedKeys.append(key) }
    }
    result.events.append(.init(key: "fullConfigChangeFinished"))
    return result
  }
}
