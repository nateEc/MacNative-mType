import Foundation

enum WebsiteConfigNativeRuleError: Error, Equatable {
  case missingField(String), invalidField(String), unrepresentableField(String), incompatibleModes
}

/// Only the input-rule group of a website runtime projection. Not a complete
/// import or an authorization to write preferences/activate a selection.
struct WebsiteConfigNativeInputRules {
  static let mappedKeys: Set<String> = ["difficulty", "strictSpace", "stopOnError", "deleteOnError",
    "hideExtraLetters", "blindMode", "quickEnd", "freedomMode", "confidenceMode", "oppositeShiftMode",
    "codeUnindentOnBackspace", "minWpm", "minWpmCustomSpeed", "minAcc", "minAccCustom", "minBurst", "minBurstCustomSpeed"]

  let difficulty: Difficulty
  let rules: InputRules

  init(runtime: [String: WebsiteConfigValue]) throws {
    func value(_ key: String) throws -> WebsiteConfigValue {
      guard let value = runtime[key] else { throw WebsiteConfigNativeRuleError.missingField(key) }
      return value
    }
    func boolean(_ key: String) throws -> Bool {
      guard case .bool(let result) = try value(key) else { throw WebsiteConfigNativeRuleError.invalidField(key) }
      return result
    }
    func text(_ key: String) throws -> String {
      guard case .string(let result) = try value(key), result.utf8.allSatisfy({ $0 < 128 })
      else { throw WebsiteConfigNativeRuleError.invalidField(key) }
      return result
    }
    func option<T: RawRepresentable>(_ key: String, _ type: T.Type) throws -> T where T.RawValue == String {
      guard let result = try T(rawValue: text(key)) else { throw WebsiteConfigNativeRuleError.invalidField(key) }
      return result
    }
    func number(_ key: String, maximum: Double? = nil) throws -> Double {
      guard case .number(let result) = try value(key), result >= 0,
        maximum.map({ result <= $0 }) ?? true else { throw WebsiteConfigNativeRuleError.invalidField(key) }
      // Website schemas admit +Infinity for speed memories, while native
      // source carriers currently require finite values. Never turn it into 0.
      guard result.isFinite else { throw WebsiteConfigNativeRuleError.unrepresentableField(key) }
      return result
    }
    difficulty = try option("difficulty", Difficulty.self)
    let stop = try option("stopOnError", StopOnErrorMode.self)
    let deletion: DeleteOnErrorMode
    switch try text("deleteOnError") {
    case "off": deletion = .off
    case "letter": deletion = .letter
    case "letter_hard": deletion = .letterHard
    case "word": deletion = .word
    case "word_hard": deletion = .wordHard
    default: throw WebsiteConfigNativeRuleError.invalidField("deleteOnError")
    }
    let confidence: ConfidenceMode
    switch try text("confidenceMode") {
    case "off": confidence = .off
    case "on": confidence = .on
    case "max": confidence = .maximum
    default: throw WebsiteConfigNativeRuleError.invalidField("confidenceMode")
    }
    let freedom = try boolean("freedomMode")
    // This adapter consumes the final runtime, not the pre-setter request.
    // Reject conflicts instead of letting InputRules silently normalize them.
    guard !(stop.isEnabled && deletion.isEnabled),
      confidence == .off || (!freedom && !stop.isEnabled && !deletion.isEnabled)
    else { throw WebsiteConfigNativeRuleError.incompatibleModes }
    var thresholds = PracticeThresholdConfiguration()
    try thresholds.apply(.minimumWpm(mode: option("minWpm", PracticeThresholdConfiguration.Mode.self),
      customValue: number("minWpmCustomSpeed")))
    try thresholds.apply(.minimumAccuracy(mode: option("minAcc", PracticeThresholdConfiguration.Mode.self),
      customValue: number("minAccCustom", maximum: 100)))
    try thresholds.apply(.minimumWordBurst(mode: option("minBurst", MinimumWordBurstMode.self),
      customValue: number("minBurstCustomSpeed")))
    let native = try InputRules(strictSpace: boolean("strictSpace"), stopOnErrorMode: stop,
      deleteOnErrorMode: deletion, hideExtraLetters: boolean("hideExtraLetters"), blindMode: boolean("blindMode"),
      quickEnd: boolean("quickEnd"), freedomMode: freedom, confidenceMode: confidence,
      oppositeShiftMode: option("oppositeShiftMode", OppositeShiftMode.self),
      codeUnindentOnBackspace: boolean("codeUnindentOnBackspace"))
    rules = PracticeThresholdSource(configuration: thresholds).applying(to: native)
  }

  func applying(to configuration: TestConfiguration) -> TestConfiguration {
    var result = configuration
    result.difficulty = difficulty
    result.rules = rules
    return result
  }

  func applying(to snapshot: AppSettingsSnapshot) -> AppSettingsSnapshot {
    var result = snapshot
    result.difficulty = difficulty
    result.strictSpace = rules.strictSpace
    result.stopOnError = rules.stopOnError
    result.stopOnErrorMode = rules.stopOnErrorMode
    result.deleteOnError = rules.deleteOnError
    result.deleteOnErrorMode = rules.deleteOnErrorMode
    result.hideExtraLetters = rules.hideExtraLetters
    result.blindMode = rules.blindMode
    result.quickEnd = rules.quickEnd
    result.freedomMode = rules.freedomMode
    result.confidenceMode = rules.confidenceMode
    result.oppositeShiftMode = rules.oppositeShiftMode
    result.codeUnindentOnBackspace = rules.codeUnindentOnBackspace
    result.minimumWpm = rules.minimumWpm
    result.minimumAccuracy = rules.minimumAccuracy
    result.minimumWordBurstWpm = rules.minimumWordBurstWpm
    result.minimumWordBurstMode = rules.minimumWordBurstMode
    result.thresholdSource = rules.thresholdSource
    return result
  }
}
