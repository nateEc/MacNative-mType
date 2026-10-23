import XCTest
@testable import Typebar

final class WebsiteConfigNativeInputRulesTests: XCTestCase {
  // Independent inverse used only to compare the typed native fields against
  // the source runtime. No production exporter is assumed to exist yet.
  static func websiteFields(_ mapped: WebsiteConfigNativeInputRules) throws -> [String: WebsiteConfigValue] {
    let rules = mapped.rules
    let raw = try XCTUnwrap(rules.thresholdSource).configuration
    let deletion: String
    switch rules.deleteOnErrorMode {
    case .letterHard: deletion = "letter_hard"
    case .wordHard: deletion = "word_hard"
    default: deletion = rules.deleteOnErrorMode.rawValue
    }
    return ["difficulty": .string(mapped.difficulty.rawValue), "strictSpace": .bool(rules.strictSpace),
      "stopOnError": .string(rules.stopOnErrorMode.rawValue), "deleteOnError": .string(deletion),
      "hideExtraLetters": .bool(rules.hideExtraLetters), "blindMode": .bool(rules.blindMode),
      "quickEnd": .bool(rules.quickEnd), "freedomMode": .bool(rules.freedomMode),
      "confidenceMode": .string(rules.confidenceMode == .maximum ? "max" : rules.confidenceMode.rawValue),
      "oppositeShiftMode": .string(rules.oppositeShiftMode.rawValue),
      "codeUnindentOnBackspace": .bool(rules.codeUnindentOnBackspace),
      "minWpm": .string(raw.minimumWpmMode.rawValue), "minWpmCustomSpeed": .number(raw.minimumWpmCustomValue),
      "minAcc": .string(raw.minimumAccuracyMode.rawValue), "minAccCustom": .number(raw.minimumAccuracyCustomValue),
      "minBurst": .string(raw.minimumWordBurstMode.rawValue), "minBurstCustomSpeed": .number(raw.minimumWordBurstCustomValue)]
  }

  @MainActor
  func testAllErrorModeCombinationsMapTheFinalRuntimeNotTheRequest() throws {
    XCTAssertEqual(WebsiteConfigNativeInputRules.mappedKeys.count, 17)
    var count = 0
    for difficulty in ["normal", "expert", "master"] {
      for confidence in ["off", "on", "max"] {
        for stop in ["off", "word", "letter"] {
          for deletion in ["off", "letter", "letter_hard", "word", "word_hard"] {
            for freedom in [false, true] {
              let input: WebsiteConfigValue = .object(["difficulty": .string(difficulty), "confidenceMode": .string(confidence),
                "stopOnError": .string(stop), "deleteOnError": .string(deletion), "freedomMode": .bool(freedom)])
              let prepared = try WebsiteConfigNativeProfile.prepare(WebsiteConfigJSONWriter.write(input), context: .init())
              let mapped = try WebsiteConfigNativeInputRules(runtime: prepared.projection.runtime)
              XCTAssertEqual(try Self.websiteFields(mapped), prepared.projection.runtime.filter {
                WebsiteConfigNativeInputRules.mappedKeys.contains($0.key)
              })
              XCTAssertEqual(mapped.rules.stopOnError, mapped.rules.stopOnErrorMode.isEnabled)
              XCTAssertEqual(mapped.rules.deleteOnError, mapped.rules.deleteOnErrorMode.isEnabled)
              count += 1
            }
          }
        }
      }
    }
    XCTAssertEqual(count, 270)
    let conflicting = try WebsiteConfigNativeProfile.prepare(#"{"confidenceMode":"max","stopOnError":"word"}"#, context: .init())
    XCTAssertThrowsError(try WebsiteConfigNativeInputRules(runtime: conflicting.projection.requested)) {
      XCTAssertEqual($0 as? WebsiteConfigNativeRuleError, .incompatibleModes)
    }
    XCTAssertNoThrow(try WebsiteConfigNativeInputRules(runtime: conflicting.projection.runtime))
  }

  @MainActor
  func testMissingMalformedAndUnrepresentableFieldsNeverBecomeDefaults() throws {
    let baseline = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    for key in WebsiteConfigNativeInputRules.mappedKeys {
      var missing = baseline
      missing.removeValue(forKey: key)
      XCTAssertThrowsError(try WebsiteConfigNativeInputRules(runtime: missing)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeRuleError, .missingField(key))
      }
      var invalid = baseline
      invalid[key] = .null
      XCTAssertThrowsError(try WebsiteConfigNativeInputRules(runtime: invalid)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeRuleError, .invalidField(key))
      }
    }
    for (key, alias) in [("confidenceMode", "maximum"), ("deleteOnError", "wordHard"), ("difficulty", "hard")] {
      var invalid = baseline
      invalid[key] = .string(alias)
      XCTAssertThrowsError(try WebsiteConfigNativeInputRules(runtime: invalid)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeRuleError, .invalidField(key))
      }
    }
    for key in ["minWpmCustomSpeed", "minBurstCustomSpeed"] {
      for mode in ["off", key == "minWpmCustomSpeed" ? "custom" : "fixed"] {
        let json = "{\"\(key)\":1e400,\"\(key == "minWpmCustomSpeed" ? "minWpm" : "minBurst")\":\"\(mode)\"}"
        let prepared = try WebsiteConfigNativeProfile.prepare(json, context: .init())
        XCTAssertEqual(prepared.projection.runtime[key], .number(.infinity))
        XCTAssertThrowsError(try WebsiteConfigNativeInputRules(runtime: prepared.projection.runtime)) {
          XCTAssertEqual($0 as? WebsiteConfigNativeRuleError, .unrepresentableField(key))
        }
      }
    }
    var invalidAccuracy = baseline
    invalidAccuracy["minAccCustom"] = .number(100.01)
    XCTAssertThrowsError(try WebsiteConfigNativeInputRules(runtime: invalidAccuracy))
    var large = baseline
    large["minWpm"] = .string("custom")
    large["minWpmCustomSpeed"] = .number(.greatestFiniteMagnitude)
    let mapped = try WebsiteConfigNativeInputRules(runtime: large)
    XCTAssertEqual(mapped.rules.minimumWpm, .greatestFiniteMagnitude)
  }

  @MainActor
  func testNativeDraftCarriersAndVersionedJSONAgreeWithoutChangingOtherFields() throws {
    let prepared = try WebsiteConfigNativeProfile.prepare(#"{"difficulty":"expert","deleteOnError":"letter_hard","strictSpace":true,"minWpm":"off","minWpmCustomSpeed":42.5,"minBurst":"flex","minBurstCustomSpeed":0}"#, context: .init())
    let mapped = try WebsiteConfigNativeInputRules(runtime: prepared.projection.runtime)
    let originalConfiguration = TestConfiguration.words(3)
    var originalSettings = AppSettingsSnapshot(fontSize: 31)
    originalSettings.globalHotkeyEnabled = true
    let configuration = mapped.applying(to: originalConfiguration)
    let settings = mapped.applying(to: originalSettings)
    XCTAssertEqual(originalConfiguration.rules.thresholdSource, nil)
    XCTAssertEqual(originalSettings.thresholdSource, nil)
    XCTAssertEqual(configuration.mode, originalConfiguration.mode)
    XCTAssertEqual(configuration.wordLimit, originalConfiguration.wordLimit)
    XCTAssertEqual(configuration.modifiers, originalConfiguration.modifiers)
    XCTAssertEqual(settings.fontSize, 31)
    XCTAssertTrue(settings.globalHotkeyEnabled)
    XCTAssertEqual(settings.thresholdSource, configuration.rules.thresholdSource)
    XCTAssertTrue(try XCTUnwrap(settings.thresholdSource).matches(settings))
    XCTAssertTrue(try XCTUnwrap(configuration.rules.thresholdSource).matches(configuration.rules))
    let json = try SettingsJSONCommandCodec.export(settings: settings, configuration: configuration,
      layoutFluidLayouts: [.ansiQwerty, .ansiDvorak], testParameterMemory: .defaults)
    let decoded = try SettingsJSONCommandCodec.decode(json)
    XCTAssertEqual(decoded.version, 6)
    XCTAssertEqual(decoded.configuration.rules, mapped.rules)
    XCTAssertEqual(decoded.configuration.difficulty, mapped.difficulty)
    XCTAssertEqual(decoded.settings.thresholdSource, mapped.rules.thresholdSource)
    XCTAssertEqual(decoded.settings.deleteOnErrorMode, .letterHard)
    XCTAssertEqual(decoded.settings.strictSpace, true)
  }

  @MainActor
  func testMappedRulesDriveTheActualTypingEngine() throws {
    func configuration(_ json: String) throws -> TestConfiguration {
      let prepared = try WebsiteConfigNativeProfile.prepare(json, context: .init())
      return try WebsiteConfigNativeInputRules(runtime: prepared.projection.runtime).applying(to: .words(3))
    }
    let start = Date(timeIntervalSinceReferenceDate: 10_000)
    var master = TypingSession(configuration: try configuration(#"{"difficulty":"master"}"#), prompt: "amber bay cedar")
    master.insert("x", at: start)
    XCTAssertEqual(master.outcome, .failed)
    var stop = TypingSession(configuration: try configuration(#"{"stopOnError":"letter"}"#), prompt: "amber bay cedar")
    stop.insert("x", at: start)
    XCTAssertEqual(stop.typed, "")
    var confidence = TypingSession(configuration: try configuration(#"{"confidenceMode":"max"}"#), prompt: "amber bay cedar")
    confidence.insert("am", at: start)
    confidence.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(confidence.typed, "am")
  }

  @MainActor
  func testSignedZeroMemoriesSurviveBothNativeCarriersAndJSON() throws {
    let prepared = try WebsiteConfigNativeProfile.prepare(#"{"minWpm":"off","minWpmCustomSpeed":-0,"minAcc":"custom","minAccCustom":-0,"minBurst":"fixed","minBurstCustomSpeed":-0}"#, context: .init())
    let mapped = try WebsiteConfigNativeInputRules(runtime: prepared.projection.runtime)
    let configuration = mapped.applying(to: TestConfiguration.words(3))
    let settings = mapped.applying(to: AppSettingsSnapshot())
    let json = try SettingsJSONCommandCodec.export(settings: settings, configuration: configuration,
      layoutFluidLayouts: [.ansiQwerty, .ansiDvorak], testParameterMemory: .defaults)
    let decoded = try SettingsJSONCommandCodec.decode(json)
    for source in [mapped.rules.thresholdSource, settings.thresholdSource,
      decoded.configuration.rules.thresholdSource, decoded.settings.thresholdSource] {
      let raw = try XCTUnwrap(source).configuration
      XCTAssertEqual(raw.minimumWpmMode, .off)
      XCTAssertEqual(raw.minimumAccuracyMode, .custom)
      XCTAssertEqual(raw.minimumWordBurstMode, .fixed)
      XCTAssertEqual(raw.minimumWpmCustomValue.sign, .minus)
      XCTAssertEqual(raw.minimumAccuracyCustomValue.sign, .minus)
      XCTAssertEqual(raw.minimumWordBurstCustomValue.sign, .minus)
    }
  }

  @MainActor
  func testRuntimeRuleMappingRetainsDisabledMemoryAndZeroModes() throws {
    let prepared = try WebsiteConfigNativeProfile.prepare(#"{"difficulty":"master","strictSpace":true,"deleteOnError":"word_hard","hideExtraLetters":true,"blindMode":true,"quickEnd":true,"freedomMode":true,"oppositeShiftMode":"keymap","codeUnindentOnBackspace":true,"minWpm":"off","minWpmCustomSpeed":73.5,"minAcc":"custom","minAccCustom":0,"minBurst":"flex","minBurstCustomSpeed":0}"#, context: .init())
    let mapped = try WebsiteConfigNativeInputRules(runtime: prepared.projection.runtime)
    XCTAssertEqual(mapped.difficulty, .master)
    XCTAssertTrue(mapped.rules.strictSpace)
    XCTAssertTrue(mapped.rules.hideExtraLetters)
    XCTAssertTrue(mapped.rules.blindMode)
    XCTAssertTrue(mapped.rules.quickEnd)
    XCTAssertTrue(mapped.rules.freedomMode)
    XCTAssertTrue(mapped.rules.codeUnindentOnBackspace)
    XCTAssertEqual(mapped.rules.deleteOnErrorMode, .wordHard)
    XCTAssertEqual(mapped.rules.oppositeShiftMode, .keymap)
    let source = try XCTUnwrap(mapped.rules.thresholdSource)
    XCTAssertEqual(source.configuration.minimumWpmMode, .off)
    XCTAssertEqual(source.configuration.minimumWpmCustomValue, 73.5)
    XCTAssertEqual(source.configuration.minimumAccuracyMode, .custom)
    XCTAssertEqual(source.configuration.minimumAccuracyCustomValue, 0)
    XCTAssertEqual(source.configuration.minimumWordBurstMode, .flex)
    XCTAssertEqual(source.configuration.minimumWordBurstCustomValue, 0)
    XCTAssertEqual(mapped.rules.minimumWpm, 0)
    XCTAssertEqual(mapped.rules.minimumAccuracy, 0)
    XCTAssertEqual(mapped.rules.minimumWordBurstMode, .off)
  }
}
