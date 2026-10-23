import XCTest
@testable import Typebar

final class WebsiteConfigNativePresentationTests: XCTestCase {
  static func nativeFields(_ s: AppSettingsSnapshot) -> [String: WebsiteConfigValue] {
    let highlight: String
    switch s.promptHighlightMode {
    case .off: highlight = "off"
    case .letter: highlight = "letter"
    case .word: highlight = "word"
    case .nextWord: highlight = "next_word"
    case .nextTwoWords: highlight = "next_two_words"
    case .nextThreeWords: highlight = "next_three_words"
    }
    return ["smoothCaret": .string(s.smoothCaretMotion.rawValue), "caretStyle": .string(s.caretStyle.compatibilityValue),
      "paceCaretStyle": .string(s.paceCaretStyle.compatibilityValue), "timerStyle": .string(s.liveProgressStyle.rawValue),
      "liveSpeedStyle": .string(s.liveSpeedStyle.rawValue), "liveAccStyle": .string(s.liveAccuracyStyle.rawValue),
      "liveBurstStyle": .string(s.liveBurstStyle.rawValue), "timerColor": .string(s.liveStatsColor.compatibilityValue),
      "timerOpacity": .string(s.liveStatsOpacity == .full ? "1" : String(s.liveStatsOpacity.rawValue)),
      "showAverage": .string(s.showAverage == .accuracy ? "acc" : s.showAverage.rawValue),
      "highlightMode": .string(highlight), "typedEffect": .string(s.typedCharacterEffect.rawValue),
      "typingSpeedUnit": .string(s.typingSpeedUnit.rawValue), "monkeyPowerLevel": .string(s.typingPowerMode.compatibilityValue),
      "indicateTypos": .string(s.typoIndicatorStyle.rawValue), "compositionDisplay": .string(s.compositionDisplayStyle.rawValue),
      "showKeyTips": .bool(s.showKeyTips), "alwaysShowDecimalPlaces": .bool(s.alwaysShowDecimalPlaces),
      "alwaysShowWordsHistory": .bool(s.alwaysShowWordsHistory), "burstHeatmap": .bool(s.showWordBurstHeatmap),
      "startGraphsAtZero": .bool(s.startGraphsAtZero), "showOutOfFocusWarning": .bool(s.showFocusWarning),
      "capsLockWarning": .bool(s.showCapsLockWarning), "showPb": .bool(s.showPersonalBest),
      "flipTestColors": .bool(s.flipTestColors), "colorfulMode": .bool(s.colorfulMode), "monkey": .bool(s.showTypingCompanion),
      "smoothLineScroll": .bool(s.smoothPracticeLineScroll), "showAllLines": .bool(s.showAllPracticeLines),
      "tapeMode": .string(s.practiceTapeMode.rawValue), "tapeMargin": .number(s.practiceTapeMargin)]
  }

  /// Compare in native units, not via a lossy multiply-back to a percentage.
  static func expectedFields(_ runtime: [String: WebsiteConfigValue]) -> [String: WebsiteConfigValue] {
    var result = runtime.filter { WebsiteConfigNativePresentation.mappedKeys.contains($0.key) }
    if case .number(let margin) = result["tapeMargin"] { result["tapeMargin"] = .number(margin / 100) }
    return result
  }

  @MainActor
  func testEveryPinnedSourceAlternativeAndMarginEdgesMapsToNativeFields() throws {
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
    XCTAssertEqual(WebsiteConfigNativePresentation.mappedKeys.count, 31)
    var count = 0
    for key in WebsiteConfigNativePresentation.mappedKeys {
      let values: [WebsiteConfigValue]
      if key == "tapeMargin" { values = [10, Double(10).nextUp, 33.3, 50, Double(90).nextDown, 90].map(WebsiteConfigValue.number) }
      else {
        values = try XCTUnwrap(choices[key], key)
        XCTAssertFalse(values.isEmpty, key)
      }
      for value in values {
        let prepared = try WebsiteConfigNativeProfile.prepare(WebsiteConfigJSONWriter.write(.object([key: value])), context: .init())
        let mapped = try WebsiteConfigNativePresentation(runtime: prepared.projection.runtime).applying(to: .init())
        XCTAssertEqual(Self.nativeFields(mapped), Self.expectedFields(prepared.projection.runtime), key)
        count += 1
      }
    }
    print("Pinned native presentation choices and margin edges: \(count)")
  }

  @MainActor
  func testCoupledPresentationModesUseFinalRuntimeAndRejectConflictingRequests() throws {
    var count = 0
    for monkey in [false, true] { for speed in ["off", "mini", "text"] { for accuracy in ["off", "mini", "text"] {
      for tape in ["off", "word", "letter"] { for all in [false, true] {
        let input: WebsiteConfigValue = .object(["monkey": .bool(monkey), "liveSpeedStyle": .string(speed),
          "liveAccStyle": .string(accuracy), "tapeMode": .string(tape), "showAllLines": .bool(all)])
        let prepared = try WebsiteConfigNativeProfile.prepare(WebsiteConfigJSONWriter.write(input), context: .init())
        let mapped = try WebsiteConfigNativePresentation(runtime: prepared.projection.runtime).applying(to: .init())
        XCTAssertEqual(Self.nativeFields(mapped), Self.expectedFields(prepared.projection.runtime))
        if (monkey && (speed == "text" || accuracy == "text")) || (all && tape != "off") {
          XCTAssertThrowsError(try WebsiteConfigNativePresentation(runtime: prepared.projection.requested)) {
            XCTAssertEqual($0 as? WebsiteConfigNativePresentationError, .incompatibleModes)
          }
        }
        count += 1
      } }
    } } }
    XCTAssertEqual(count, 108)
  }

  @MainActor
  func testMissingInvalidAndNativeOnlyAliasesDoNotBecomeDefaults() throws {
    let baseline = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    for key in WebsiteConfigNativePresentation.mappedKeys {
      var missing = baseline
      missing.removeValue(forKey: key)
      XCTAssertThrowsError(try WebsiteConfigNativePresentation(runtime: missing)) {
        XCTAssertEqual($0 as? WebsiteConfigNativePresentationError, .missingField(key))
      }
      var invalid = baseline
      invalid[key] = .null
      XCTAssertThrowsError(try WebsiteConfigNativePresentation(runtime: invalid)) {
        XCTAssertEqual($0 as? WebsiteConfigNativePresentationError, .invalidField(key))
      }
    }
    for (key, name) in [("caretStyle", "bar"), ("paceCaretStyle", "bar"), ("timerColor", "primary"),
      ("timerOpacity", "0.250"), ("showAverage", "accuracy"), ("highlightMode", "nextWord"), ("monkeyPowerLevel", "ultra")] {
      var invalid = baseline
      invalid[key] = .string(name)
      XCTAssertThrowsError(try WebsiteConfigNativePresentation(runtime: invalid)) {
        XCTAssertEqual($0 as? WebsiteConfigNativePresentationError, .invalidField(key))
      }
    }
    for margin in [Double.nan, .infinity, -.infinity, 9.999, 90.001] {
      var invalid = baseline
      invalid["tapeMargin"] = .number(margin)
      XCTAssertThrowsError(try WebsiteConfigNativePresentation(runtime: invalid)) {
        XCTAssertEqual($0 as? WebsiteConfigNativePresentationError, .invalidField("tapeMargin"))
      }
    }
  }

  @MainActor
  func testPresentationAndRuleDraftsComposeAndRoundTripWithoutOverwritingOtherFields() throws {
    let prepared = try WebsiteConfigNativeProfile.prepare(#"{"difficulty":"master","minWpm":"off","minWpmCustomSpeed":42.5,"timerStyle":"flash_mini","timerColor":"sub","timerOpacity":"0.75","typingSpeedUnit":"cps","caretStyle":"outline","highlightMode":"next_two_words","smoothCaret":"fast","monkeyPowerLevel":"4","tapeMargin":25,"tapeMode":"word"}"#, context: .init())
    let presentation = try WebsiteConfigNativePresentation(runtime: prepared.projection.runtime)
    let rules = try WebsiteConfigNativeInputRules(runtime: prepared.projection.runtime)
    XCTAssertTrue(WebsiteConfigNativePresentation.mappedKeys.isDisjoint(with: WebsiteConfigNativeInputRules.mappedKeys))
    XCTAssertEqual(WebsiteConfigNativePresentation.mappedKeys.union(WebsiteConfigNativeInputRules.mappedKeys).count, 48)
    var before = AppSettingsSnapshot(fontSize: 31)
    before.globalHotkeyEnabled = true
    before.customBackgroundURL = "https://example.com/owned.png"
    let snapshot = presentation.applying(to: rules.applying(to: before))
    XCTAssertEqual(snapshot, rules.applying(to: presentation.applying(to: before)))
    XCTAssertEqual(before.fontSize, 31)
    XCTAssertEqual(snapshot.fontSize, before.fontSize)
    XCTAssertEqual(snapshot.globalHotkeyEnabled, before.globalHotkeyEnabled)
    XCTAssertEqual(snapshot.customBackgroundURL, before.customBackgroundURL)
    XCTAssertEqual(snapshot.thresholdSource, rules.rules.thresholdSource)
    let configuration = rules.applying(to: TestConfiguration.words(3))
    let json = try SettingsJSONCommandCodec.export(settings: snapshot, configuration: configuration,
      layoutFluidLayouts: [.ansiQwerty, .ansiDvorak], testParameterMemory: .defaults)
    let decoded = try SettingsJSONCommandCodec.decode(json)
    XCTAssertEqual(decoded.configuration.rules, rules.rules)
    XCTAssertEqual(Self.nativeFields(decoded.settings), Self.expectedFields(prepared.projection.runtime))
    // Exercise existing native consumers; this is not a rendered-window test.
    XCTAssertTrue(snapshot.liveProgressStyle.showsProgressValue(isTimed: true, remainingSeconds: 15))
    XCTAssertFalse(snapshot.liveProgressStyle.showsProgressValue(isTimed: true, remainingSeconds: 14))
    XCTAssertEqual(snapshot.typingSpeedUnit.formatted(wpm: 120), "10")
    XCTAssertEqual(snapshot.promptHighlightMode.futureWordCount, 2)
    XCTAssertEqual(snapshot.smoothCaretMotion.duration, 0.085)
    XCTAssertTrue(snapshot.caretStyle.usesFullGlyphWidth)
    XCTAssertTrue(snapshot.typingPowerMode.usesShake)
    XCTAssertTrue(snapshot.typingPowerMode.usesSpectrum)
    XCTAssertEqual(PracticeTapePolicy.anchorCharacterIndex(typed: "amber b", mode: snapshot.practiceTapeMode), 6)
  }

  @MainActor
  func testPresentationUsesNativeNamesAndPercentUnits() throws {
    let prepared = try WebsiteConfigNativeProfile.prepare(#"{"smoothCaret":"off","caretStyle":"banana","paceCaretStyle":"outline","timerStyle":"flash_text","timerColor":"text","timerOpacity":"0.25","showAverage":"acc","highlightMode":"next_three_words","typedEffect":"dots","typingSpeedUnit":"wph","monkeyPowerLevel":"3","indicateTypos":"both","compositionDisplay":"below","tapeMode":"letter","tapeMargin":33.3,"smoothLineScroll":true,"showAllLines":true}"#, context: .init())
    let mapped = try WebsiteConfigNativePresentation(runtime: prepared.projection.runtime)
    let snapshot = mapped.applying(to: AppSettingsSnapshot(fontSize: 31))
    XCTAssertEqual(snapshot.smoothCaretMotion, .off)
    XCTAssertEqual(snapshot.caretStyle, .banana)
    XCTAssertEqual(snapshot.paceCaretStyle, .outline)
    XCTAssertEqual(snapshot.liveProgressStyle, .flashText)
    XCTAssertEqual(snapshot.liveStatsColor, .primary)
    XCTAssertEqual(snapshot.liveStatsOpacity, .quarter)
    XCTAssertEqual(snapshot.showAverage, .accuracy)
    XCTAssertEqual(snapshot.promptHighlightMode, .nextThreeWords)
    XCTAssertEqual(snapshot.typedCharacterEffect, .dots)
    XCTAssertEqual(snapshot.typingSpeedUnit, .wph)
    XCTAssertEqual(snapshot.typingPowerMode, .ultra)
    XCTAssertEqual(snapshot.typoIndicatorStyle, .both)
    XCTAssertEqual(snapshot.compositionDisplayStyle, .below)
    XCTAssertEqual(snapshot.practiceTapeMode, .letter)
    XCTAssertEqual(snapshot.practiceTapeMargin, 33.3 / 100)
    XCTAssertTrue(snapshot.smoothPracticeLineScroll)
    XCTAssertFalse(snapshot.showAllPracticeLines)
    XCTAssertEqual(snapshot.fontSize, 31)
  }
}
