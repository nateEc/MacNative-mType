import XCTest
@testable import Typebar

final class WebsiteConfigNativeBehaviorTests: XCTestCase {
  static func nativeFields(_ s: AppSettingsSnapshot) throws -> [String: WebsiteConfigValue] {
    let click: String
    if s.playKeyclickSound {
      click = String(try XCTUnwrap((1...26).first {
        if case .click(let style?) = SoundCommandCatalog.target(for: "sound.playSoundOnClick.\($0)") {
          return style == s.clickSoundStyle
        }
        return false
      }))
    } else { click = "off" }
    let error: String
    if s.playErrorBeep {
      error = String(try XCTUnwrap((1...4).first {
        if case .error(let style?) = SoundCommandCatalog.target(for: "sound.playSoundOnError.\($0)") {
          return style == s.errorSoundStyle
        }
        return false
      }))
    } else { error = "off" }
    let pace: String
    switch s.paceGuideMode {
    case .off: pace = "off"
    case .custom: pace = "custom"
    case .personalBest: pace = "pb"
    case .accountTagPersonalBest: pace = "tagPb"
    case .lastTest: pace = "last"
    case .recentAverage: pace = "average"
    case .dailyBest: pace = "daily"
    default: throw WebsiteConfigNativeBehaviorError.invalidField("paceCaret")
    }
    return ["playSoundOnClick": .string(click), "playSoundOnError": .string(error),
      "playTimeWarning": .string(s.timeWarningOffset == .off ? "off" : String(s.timeWarningOffset.rawValue)),
      "soundVolume": .number(s.soundVolume), "paceCaret": .string(pace),
      "paceCaretCustomSpeed": .number(s.paceGuideCustomWpm), "repeatedPace": .bool(s.repeatedPace),
      "quickRestart": .string(s.quickRestartKey == .escape ? "esc" : s.quickRestartKey.rawValue),
      "singleListCommandLine": .string(s.commandPaletteListMode == .singleList ? "on" : "manual"),
      "britishEnglish": .bool(s.englishVariant == .british), "resultSaving": .bool(s.saveCompletedResults),
      "repeatQuotes": .string(s.repeatQuotes ? "typing" : "off")]
  }

  static func assertSourceRuntime(_ runtime: [String: WebsiteConfigValue]) throws {
    let snapshot = try WebsiteConfigNativeBehavior(runtime: runtime).applying(to: .init())
    XCTAssertEqual(try nativeFields(snapshot), runtime.filter { WebsiteConfigNativeBehavior.mappedKeys.contains($0.key) })
  }

  @MainActor
  func testEveryPinnedSourceAlternativeAndNumericEdges() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    guard env["TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT"] != nil else { return XCTFail("Requires pinned Zod") }
    struct Output: Decodable { var choices: [String: [WebsiteConfigValue]] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--default-profile"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let choices = try JSONDecoder().decode(Output.self, from: data).choices
    XCTAssertEqual(WebsiteConfigNativeBehavior.mappedKeys.count, 12)
    var count = 0
    for key in WebsiteConfigNativeBehavior.mappedKeys {
      let values: [WebsiteConfigValue]
      if key == "soundVolume" {
        values = [0, Double.leastNonzeroMagnitude, 0.125, 0.5, Double(1).nextDown, 1].map(WebsiteConfigValue.number)
      } else if key == "paceCaretCustomSpeed" {
        values = [0, Double.leastNonzeroMagnitude, 0.5, 123.75, Double.greatestFiniteMagnitude].map(WebsiteConfigValue.number)
      } else {
        values = try XCTUnwrap(choices[key], key)
        XCTAssertFalse(values.isEmpty, key)
      }
      for value in values {
        let prepared = try WebsiteConfigNativeProfile.prepare(WebsiteConfigJSONWriter.write(.object([key: value])),
          context: .init(authenticated: true))
        try Self.assertSourceRuntime(prepared.projection.runtime)
        count += 1
      }
    }
    print("Pinned native sound/behavior alternatives and numeric edges: \(count)")
  }

  @MainActor
  func testPaceSourcesRemainDistinctAndDisplayedUnitsDoNotChangeWpm() throws {
    var count = 0
    for mode in ["off", "custom", "pb", "tagPb", "average", "daily", "last"] {
      for unit in TypingSpeedUnit.allCases {
        let input: WebsiteConfigValue = .object(["paceCaret": .string(mode), "paceCaretCustomSpeed": .number(123.75),
          "typingSpeedUnit": .string(unit.rawValue)])
        let prepared = try WebsiteConfigNativeProfile.prepare(WebsiteConfigJSONWriter.write(input), context: .init(authenticated: true))
        let mapped = try WebsiteConfigNativeBehavior(runtime: prepared.projection.runtime)
        XCTAssertEqual(mapped.paceGuideCustomWpm, 123.75)
        try Self.assertSourceRuntime(prepared.projection.runtime)
        if mode == "tagPb" {
          XCTAssertEqual(mapped.paceGuideMode, .accountTagPersonalBest)
          XCTAssertNotEqual(mapped.paceGuideMode, .activeTagPersonalBest)
          let configuration = TestConfiguration.timed(seconds: 15)
          let local = PaceGuideSample(configuration: configuration, outcome: .completed,
            finishedAt: Date(timeIntervalSince1970: 100), wpm: 300, tags: ["desk"])
          XCTAssertNil(PaceGuidePolicy.targetWpm(mode: mapped.paceGuideMode, customWpm: 123.75,
            configuration: configuration, samples: [local], activeTags: ["desk"], accountTags: nil))
        }
        count += 1
      }
    }
    XCTAssertEqual(count, 35)
    let anonymous = try WebsiteConfigNativeProfile.prepare(#"{"paceCaret":"tagPb"}"#, context: .init())
    // Actual pinned applyConfig enables custom while assigning its remembered
    // speed, then rejects the later unauthenticated tagPb setter. It does not
    // restore off or authorize a tag PB target.
    XCTAssertEqual(anonymous.projection.requested["paceCaret"], .string("tagPb"))
    XCTAssertEqual(anonymous.projection.runtime["paceCaret"], .string("custom"))
    XCTAssertEqual(anonymous.projection.rejectedKeys, ["paceCaret"])
    let rejected = try WebsiteConfigNativeBehavior(runtime: anonymous.projection.runtime)
    XCTAssertEqual(rejected.paceGuideMode, .custom)
    XCTAssertEqual(rejected.paceGuideCustomWpm, 100)
    for value in [0.0, 0.5] {
      let input: WebsiteConfigValue = .object(["paceCaret": .string("custom"), "paceCaretCustomSpeed": .number(value)])
      let prepared = try WebsiteConfigNativeProfile.prepare(WebsiteConfigJSONWriter.write(input), context: .init())
      let mapped = try WebsiteConfigNativeBehavior(runtime: prepared.projection.runtime)
      XCTAssertEqual(mapped.paceGuideMode, .custom)
      XCTAssertEqual(mapped.paceGuideCustomWpm, value)
      XCTAssertNil(PaceGuidePolicy.targetWpm(mode: mapped.paceGuideMode, customWpm: mapped.paceGuideCustomWpm,
        configuration: .timed(seconds: 15), samples: []))
    }
  }

  @MainActor
  func testMissingMalformedAndUnrepresentableValuesAreNotSilentlyCoerced() throws {
    let baseline = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    for key in WebsiteConfigNativeBehavior.mappedKeys {
      var missing = baseline
      missing.removeValue(forKey: key)
      XCTAssertThrowsError(try WebsiteConfigNativeBehavior(runtime: missing)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeBehaviorError, .missingField(key))
      }
      var invalid = baseline
      invalid[key] = .null
      XCTAssertThrowsError(try WebsiteConfigNativeBehavior(runtime: invalid)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeBehaviorError, .invalidField(key))
      }
    }
    for (key, alias) in [("playSoundOnClick", "01"), ("playSoundOnClick", "27"), ("playSoundOnClick", "ripple"),
      ("playSoundOnClick", "١"), ("playSoundOnError", "submarine"), ("playTimeWarning", "0"),
      ("paceCaret", "personalBest"), ("quickRestart", "escape"), ("singleListCommandLine", "grouped"), ("repeatQuotes", "true")] {
      var invalid = baseline
      invalid[key] = .string(alias)
      XCTAssertThrowsError(try WebsiteConfigNativeBehavior(runtime: invalid)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeBehaviorError, .invalidField(key))
      }
    }
    for value in [Double.nan, .infinity, -.infinity, -0.01, 1.001] {
      var invalid = baseline
      invalid["soundVolume"] = .number(value)
      XCTAssertThrowsError(try WebsiteConfigNativeBehavior(runtime: invalid)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeBehaviorError, .invalidField("soundVolume"))
      }
    }
    for mode in ["off", "custom"] {
      let prepared = try WebsiteConfigNativeProfile.prepare("{\"paceCaret\":\"\(mode)\",\"paceCaretCustomSpeed\":1e400}", context: .init())
      XCTAssertEqual(prepared.projection.runtime["paceCaretCustomSpeed"], .number(.infinity))
      try Self.assertSourceRuntime(prepared.projection.runtime)
    }
  }

  @MainActor
  func testDisabledSoundMemoryAndComposedDraftsSurviveNativeJSONWithoutPublishing() throws {
    let prepared = try WebsiteConfigNativeProfile.prepare(#"{"playSoundOnClick":"off","playSoundOnError":"off","playTimeWarning":"3","paceCaret":"off","paceCaretCustomSpeed":-0,"britishEnglish":true,"resultSaving":false,"repeatQuotes":"typing","quickRestart":"enter","difficulty":"expert","timerStyle":"flash_text"}"#, context: .init())
    let behavior = try WebsiteConfigNativeBehavior(runtime: prepared.projection.runtime)
    let rules = try WebsiteConfigNativeInputRules(runtime: prepared.projection.runtime)
    let presentation = try WebsiteConfigNativePresentation(runtime: prepared.projection.runtime)
    let otherKeys = WebsiteConfigNativeInputRules.mappedKeys.union(WebsiteConfigNativePresentation.mappedKeys)
    XCTAssertTrue(otherKeys.isDisjoint(with: WebsiteConfigNativeBehavior.mappedKeys))
    XCTAssertEqual(otherKeys.union(WebsiteConfigNativeBehavior.mappedKeys).count, 60)
    var before = AppSettingsSnapshot(fontSize: 31)
    before.playKeyclickSound = true
    before.clickSoundStyle = .ripple
    before.playErrorBeep = true
    before.errorSoundStyle = .submarine
    before.publishCompletedResults = true
    let snapshot = behavior.applying(to: presentation.applying(to: rules.applying(to: before)))
    XCTAssertEqual(snapshot, rules.applying(to: presentation.applying(to: behavior.applying(to: before))))
    XCTAssertFalse(snapshot.playKeyclickSound)
    XCTAssertEqual(snapshot.clickSoundStyle, .ripple)
    XCTAssertFalse(snapshot.playErrorBeep)
    XCTAssertEqual(snapshot.errorSoundStyle, .submarine)
    XCTAssertEqual(snapshot.timeWarningSoundStyle, before.timeWarningSoundStyle)
    XCTAssertEqual(snapshot.fontSize, 31)
    XCTAssertTrue(snapshot.publishCompletedResults, "Result-saving preference is not a new publication permission")
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: .completed, enabled: snapshot.saveCompletedResults))
    XCTAssertTrue(snapshot.quickRestartKey.matches(charactersIgnoringModifiers: "\r"))
    XCTAssertTrue(TimeWarningPolicy.shouldPlay(remainingSeconds: 3, previousSecond: 4, offset: snapshot.timeWarningOffset))
    let configuration = behavior.applying(to: rules.applying(to: TestConfiguration.words(3)))
    XCTAssertEqual(configuration.englishVariant, snapshot.englishVariant)
    let json = try SettingsJSONCommandCodec.export(settings: snapshot, configuration: configuration,
      layoutFluidLayouts: [.ansiQwerty, .ansiDvorak], testParameterMemory: .defaults)
    let decoded = try SettingsJSONCommandCodec.decode(json)
    XCTAssertEqual(decoded.configuration.rules, rules.rules)
    XCTAssertEqual(decoded.configuration.englishVariant, .british)
    XCTAssertEqual(decoded.settings.clickSoundStyle, .ripple)
    XCTAssertEqual(decoded.settings.errorSoundStyle, .submarine)
    XCTAssertEqual(decoded.settings.paceGuideCustomWpm.sign, .minus)
    XCTAssertEqual(try Self.nativeFields(decoded.settings), prepared.projection.runtime.filter {
      WebsiteConfigNativeBehavior.mappedKeys.contains($0.key)
    })
    XCTAssertEqual(before.playKeyclickSound, true)
    XCTAssertEqual(before.englishVariant, .american)
  }

  @MainActor
  func testSoundPaceAndBehaviorMapWithoutReinterpretingCanonicalSpeed() throws {
    let prepared = try WebsiteConfigNativeProfile.prepare(#"{"playSoundOnClick":"10","playSoundOnError":"4","playTimeWarning":"3","soundVolume":0.125,"paceCaret":"custom","paceCaretCustomSpeed":123.75,"repeatedPace":false,"quickRestart":"esc","singleListCommandLine":"manual","britishEnglish":true,"resultSaving":false,"repeatQuotes":"typing","typingSpeedUnit":"cps"}"#, context: .init())
    let mapped = try WebsiteConfigNativeBehavior(runtime: prepared.projection.runtime)
    let snapshot = mapped.applying(to: AppSettingsSnapshot())
    XCTAssertTrue(snapshot.playKeyclickSound)
    XCTAssertEqual(snapshot.clickSoundStyle, .pianoSquare)
    XCTAssertTrue(snapshot.playErrorBeep)
    XCTAssertEqual(snapshot.errorSoundStyle, .submarine)
    XCTAssertEqual(snapshot.timeWarningOffset, .threeSeconds)
    XCTAssertEqual(snapshot.soundVolume, 0.125)
    XCTAssertEqual(snapshot.paceGuideMode, .custom)
    XCTAssertEqual(snapshot.paceGuideCustomWpm, 123.75)
    XCTAssertFalse(snapshot.repeatedPace)
    XCTAssertEqual(snapshot.quickRestartKey, .escape)
    XCTAssertEqual(snapshot.commandPaletteListMode, .grouped)
    XCTAssertEqual(snapshot.englishVariant, .british)
    XCTAssertFalse(snapshot.saveCompletedResults)
    XCTAssertTrue(snapshot.repeatQuotes)
    XCTAssertEqual(mapped.applying(to: TestConfiguration.words(3)).englishVariant, .british)
  }
}
