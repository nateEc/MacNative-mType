import Foundation

struct WebsiteCustomTextSettings: Equatable {
  var text: [WebsiteConfigValue]
  var mode: String
  var limitMode: String
  var limitValue: Double
  var pipeDelimiter: Bool
  init(value: WebsiteConfigValue) throws {
    guard let fields = value.importFields, case .array(let text)? = fields["text"], !text.isEmpty,
      text.allSatisfy({ $0.stringUnits != nil }), case .string(let mode)? = fields["mode"],
      ["repeat", "shuffle", "random"].contains(mode), let limit = fields["limit"]?.importFields,
      case .string(let limitMode)? = limit["mode"], ["word", "time", "section"].contains(limitMode),
      case .number(let number)? = limit["value"], number >= 0,
      case .bool(let pipe)? = fields["pipeDelimiter"] else { throw WebsiteSharedSettingsReceiver.Failure.invalidPayload }
    self.text = text; self.mode = mode; self.limitMode = limitMode; limitValue = number; pipeDelimiter = pipe
  }
  var value: WebsiteConfigValue {
    .object(["text": .array(text), "mode": .string(mode), "limit": .object([
      "mode": .string(limitMode), "value": .number(limitValue)]), "pipeDelimiter": .bool(pipeDelimiter)])
  }
}

/// Ordered source effects for an incoming eight-slot selection. This kernel
/// performs only the supplied synchronous storage effects. Session initialization
/// and GUI publication remain the caller's responsibility.
@MainActor enum WebsiteSharedSettingsReceiver {
  enum Failure: Error { case invalidPayload }
  struct State {
    var runtime: [String: WebsiteConfigValue]
    var settingsStore: [String: WebsiteConfigValue]
    var custom: WebsiteCustomTextSettings
    var selectedQuote: WebsiteConfigValue?
    var active: Bool
    var restarting = false
    var resultCalculating = false
    var lazyMemory = WebsiteConfigLazyModeMemory()
    // Warm source storage cache, distinct from temporary Config/getConfig.
    var savedConfig: [String: WebsiteConfigValue]?
  }
  struct ConfigSave {
    let key: String
    let runtime: [String: WebsiteConfigValue]
  }
  struct Storage {
    var writeCustom: @MainActor (WebsiteCustomTextSettings) throws -> Bool = { _ in true }
    var writeConfiguration: @MainActor (ConfigSave) throws -> Bool = { _ in true }
  }
  struct StorageAttempt {
    let key: String, json: String
    let accepted: Bool
  }
  struct Outcome {
    var state: State
    var events: [WebsiteConfigApplicationEvent] = []
    var configSaves: [ConfigSave] = []
    var configWrites: [String] = []
    var customWrites: [String] = []
    var restartRequests: [String] = []
    var restartStarts = 0
    var parseRejected = false
    var threw = false
    var storageAttempts: [StorageAttempt] = []
    var storageFailures: [String] = []
  }
  static func validatePayload(_ json: String) throws { _ = try parse(json) }
  static func receive(json: String, current: State, context: WebsiteConfigRuntimeContext = .init(),
    storage: Storage = .init()) -> Outcome {
    var result = Outcome(state: current)
    let values: [WebsiteConfigValue]
    do { values = try parse(json) }
    catch { result.parseRejected = true; return result }
    let defaults: [String: WebsiteConfigValue]
    do { defaults = try WebsiteConfigNativeProfile.defaultDocument().values }
    catch { result.threw = true; return result }
    let schema = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs)
    func requestRestart(_ source: String) {
      result.restartRequests.append(source)
      if result.state.active, case .array(let names)? = result.state.runtime["funbox"], names.contains(.string("no_quit")) { return }
      guard !result.state.restarting, !result.state.resultCalculating else { return }
      result.state.active = false; result.state.restarting = true; result.restartStarts += 1
    }
    func assign(_ key: String, _ value: WebsiteConfigValue, nosave: Bool = true) throws {
      let before = result.state.runtime
      _ = try WebsiteConfigRuntimeProjector.edit(current: before, key: key, value: value,
        defaults: defaults, schema: schema, context: context, testActive: result.state.active, nosave: nosave,
        observeAssignment: { key, value, accepted in
          guard accepted else { return }
          let previous = result.state.runtime[key]
          result.state.runtime[key] = value
          if !nosave {
            result.configSaves.append(.init(key: key, runtime: result.state.runtime))
            let serialized = WebsiteConfigJSONWriter.write(.object(result.state.runtime), asciiOnly: false)
            let cached = result.state.savedConfig.map { WebsiteConfigJSONWriter.write(.object($0), asciiOnly: false) }
            if serialized != cached {
              let accepted = (try? storage.writeConfiguration(.init(key: key, runtime: result.state.runtime))) ?? false
              result.storageAttempts.append(.init(key: "config", json: serialized, accepted: accepted))
              if accepted {
                result.configWrites.append(serialized)
                result.state.savedConfig = result.state.runtime
              } else { result.storageFailures.append("config") }
            }
          }
          result.events.append(.init(key: key, previousValue: previous, newValue: value, nosave: nosave))
          if key == "language" {
            if let units = value.stringUnits, String(decoding: units, as: UTF16.self).hasPrefix("arabic"),
              result.state.lazyMemory.prefersArabic {
              // The real synchronous listener runs before the parent's store
              // update. The next outer setter reads this admitted runtime.
              try? assign("lazyMode", .bool(true))
            }
            requestRestart("listener")
          }
          result.state.settingsStore[key] = value
        })
    }
    func changeCustom(_ change: (inout WebsiteCustomTextSettings) -> Void) {
      var candidate = result.state.custom
      change(&candidate)
      guard candidate.limitValue >= 0 else { result.storageFailures.append("customTextSettings"); return }
      let proposed = WebsiteConfigJSONWriter.write(candidate.value, asciiOnly: false)
      // Source LocalStorageWithSchema compares JSON before updating its cache;
      // an unchanged serialization is not another durable write.
      guard proposed != WebsiteConfigJSONWriter.write(result.state.custom.value, asciiOnly: false) else { return }
      let accepted = (try? storage.writeCustom(candidate)) ?? false
      result.storageAttempts.append(.init(key: "customTextSettings", json: proposed, accepted: accepted))
      guard accepted else { result.storageFailures.append("customTextSettings"); return }
      result.state.custom = candidate; result.customWrites.append(proposed)
    }
    do {
      let selectedMode = values[0] == .null ? current.runtime["mode"] : values[0]
      if values[0] != .null { try assign("mode", values[0]) }
      if values[1] != .null {
        let text = string(values[1])!
        let count = WebsiteThresholdCommandInput.integerPrefix(text)
        switch selectedMode {
        case .string("time"): try assign("time", .number(count))
        case .string("words"): try assign("words", .number(count))
        case .string("quote"):
          try assign("quoteLength", .array([.number(-2)]), nosave: false)
          result.state.selectedQuote = .number(count)
        default: break
        }
      }
      if let custom = values[2].importFields, case .array(let text)? = custom["text"] {
        changeCustom { $0.text = text; $0.limitValue = Double(text.count) }
        changeCustom { $0.mode = string(custom["mode"] ?? .string("repeat"))!; $0.limitValue = Double($0.text.count) }
        if let limit = custom["limit"]?.importFields, case .number(let number)? = limit["value"] {
          changeCustom { $0.limitMode = string(limit["mode"]!)! }
          changeCustom { $0.limitValue = number }
        } else {
          if custom["isWordRandom"] == .bool(true) { changeCustom { $0.limitMode = "word" } }
          else if custom["isTimeRandom"] == .bool(true) { changeCustom { $0.limitMode = "time" } }
          if case .number(let number)? = custom["word"] { changeCustom { $0.limitValue = number } }
          else if case .number(let number)? = custom["time"] { changeCustom { $0.limitValue = number } }
        }
        if custom["pipeDelimiter"] == .bool(true) || custom["delimiter"] == .string("|") {
          changeCustom { $0.pipeDelimiter = true }
        }
      }
      for (index, key) in [(3,"punctuation"),(4,"numbers"),(5,"language"),(6,"difficulty")] where values[index] != .null {
        try assign(key, values[index])
      }
      if values[7] != .null {
        let value: WebsiteConfigValue
        if let text = string(values[7]) {
          value = .array(text.components(separatedBy: "#").map(WebsiteConfigValue.string))
        } else { value = values[7] }
        try assign("funbox", value)
      }
      requestRestart("handler")
    } catch { result.threw = true }
    return result
  }

  private static func string(_ value: WebsiteConfigValue) -> String? {
    value.stringUnits.map { String(decoding: $0, as: UTF16.self) }
  }
  private static func parse(_ json: String) throws -> [WebsiteConfigValue] {
    guard case .array(var values) = try WebsiteConfigJSONReader.read(json), values.count == 8 else { throw Failure.invalidPayload }
    let schema = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs)
    for (index, key) in [(0,"mode"),(6,"difficulty")] where values[index] != .null {
      guard schema.accepts(values[index], for: key) else { throw Failure.invalidPayload }
    }
    if values[1] != .null {
      if case .number(let number) = values[1], !number.isNaN { values[1] = .string(WebsiteNumberText.decimal(number)) }
      else {
        guard let units = values[1].stringUnits,
          units == Array("zen".utf16) || units == Array("custom".utf16)
            || (!units.isEmpty && units.allSatisfy({ (48...57).contains($0) })) else { throw Failure.invalidPayload }
      }
    }
    for index in [3,4] where values[index] != .null {
      guard case .bool = values[index] else { throw Failure.invalidPayload }
    }
    guard values[5] == .null || values[5].stringUnits != nil else { throw Failure.invalidPayload }
    if values[7] != .null, values[7].stringUnits == nil {
      guard schema.accepts(values[7], for: "funbox") else { throw Failure.invalidPayload }
    }
    if values[2] != .null {
      guard let fields = values[2].importFields, case .array(let text)? = fields["text"], !text.isEmpty,
        text.allSatisfy({ $0.stringUnits != nil }) else { throw Failure.invalidPayload }
      for (key, choices) in [("mode",["repeat","random","shuffle"])] {
        if let value = fields[key] { guard let text = string(value), choices.contains(text) else { throw Failure.invalidPayload } }
      }
      for key in ["pipeDelimiter","isTimeRandom","isWordRandom"] {
        if let value = fields[key] { guard case .bool = value else { throw Failure.invalidPayload } }
      }
      if let value = fields["delimiter"], value.stringUnits == nil { throw Failure.invalidPayload }
      for key in ["word","time"] {
        if let value = fields[key] {
          guard case .number(let number) = value, number.isFinite, number.rounded(.towardZero) == number else { throw Failure.invalidPayload }
        }
      }
      if let value = fields["limit"] {
        guard let limit = value.importFields, let mode = limit["mode"].flatMap(string),
          ["word","time","section"].contains(mode), case .number(let number)? = limit["value"], number >= 0
        else { throw Failure.invalidPayload }
      }
    }
    return values
  }
}
