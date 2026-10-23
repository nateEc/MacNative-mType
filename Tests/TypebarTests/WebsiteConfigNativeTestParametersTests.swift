import XCTest
@testable import Typebar

final class WebsiteConfigNativeTestParametersTests: XCTestCase {
  @MainActor
  func testEveryPinnedModeLanguageAndLimitBoundary() throws {
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
    XCTAssertEqual(choices["language"]?.count, 446)
    var count = 0
    for key in WebsiteConfigNativeTestParameters.mappedKeys {
      let values: [WebsiteConfigValue]
      if key == "time" || key == "words" {
        values = [0, -0.0, 1, 15, 100_001, Double(OfficialTestLimitInput.maximumValue),
          9_007_199_254_740_992.0, Double.greatestFiniteMagnitude].map(WebsiteConfigValue.number)
      } else { values = try XCTUnwrap(choices[key], key) }
      XCTAssertFalse(values.isEmpty, key)
      for value in values {
        let runtime = try WebsiteConfigNativeProfile.prepare(WebsiteConfigJSONWriter.write(.object([key: value])), context: .init()).projection.runtime
        try Self.assertSourceRuntime(runtime)
        count += 1
      }
    }
    XCTAssertEqual(count, 471)
    print("Pinned native test parameter alternatives and limit boundaries: \(count)")
  }

  static func nativeFields(_ configuration: TestConfiguration, memory: TypebarTestParameterMemory) throws -> [String: WebsiteConfigValue] {
    ["mode": .string(configuration.mode.rawValue), "time": .number(Double(memory.duration)),
      "words": .number(Double(memory.wordLimit)), "language": .string(try XCTUnwrap(WebsiteLanguageIdentity.name(for: configuration.language))),
      "punctuation": .bool(configuration.contentOptions.includePunctuation), "numbers": .bool(configuration.contentOptions.includeNumbers)]
  }

  static func assertSourceRuntime(_ runtime: [String: WebsiteConfigValue], expected: [String: WebsiteConfigValue]? = nil) throws {
    let expected = expected ?? runtime
    let gaps = Set(["time", "words"].filter { key in
      if case .number(let value) = expected[key] { return value > Double(OfficialTestLimitInput.maximumValue) }
      return false
    })
    if !gaps.isEmpty {
      XCTAssertThrowsError(try WebsiteConfigNativeTestParameters(runtime: runtime)) {
        guard case .unrepresentableField(let key) = $0 as? WebsiteConfigNativeTestParametersError else {
          return XCTFail("Expected native limit-domain gap, got \($0)")
        }
        XCTAssertTrue(gaps.contains(key), key)
      }
      return
    }
    let draft = try WebsiteConfigNativeTestParameters(runtime: runtime)
    let memory = draft.parameterMemory(preserving: .defaults)
    let configuration = draft.applying(to: .words(3), parameterMemory: .defaults)
    XCTAssertEqual(try nativeFields(configuration, memory: memory), expected.filter { WebsiteConfigNativeTestParameters.mappedKeys.contains($0.key) })
    switch configuration.mode {
    case .time:
      XCTAssertEqual(configuration.duration, Double(memory.duration)); XCTAssertNil(configuration.wordLimit)
    case .words:
      XCTAssertEqual(configuration.wordLimit, memory.wordLimit); XCTAssertNil(configuration.duration)
    case .quote, .zen, .custom:
      XCTAssertNil(configuration.wordLimit); XCTAssertNil(configuration.duration)
    }
  }

  @MainActor
  func testAllModesKeepIndependentMemoryAndCustomCompletionContext() throws {
    let memory = TypebarTestParameterMemory(duration: 15, wordLimit: 10,
      customTextDuration: 99, customTextWordLimit: 44, customTextSectionLimit: 3)
    for mode in TestMode.allCases {
      let runtime = try WebsiteConfigNativeProfile.prepare(
        "{\"mode\":\"\(mode.rawValue)\",\"words\":888,\"time\":555,\"punctuation\":true,\"numbers\":true}", context: .init()).projection.runtime
      let draft = try WebsiteConfigNativeTestParameters(runtime: runtime)
      try Self.assertSourceRuntime(runtime)
      XCTAssertEqual(runtime["punctuation"], .bool(mode != .quote))
      XCTAssertEqual(runtime["numbers"], .bool(mode != .quote))
      for completion in CustomTextCompletion.allCases {
        var before = TestConfiguration.words(3)
        before.customTextCompletion = completion
        before.customTextOrdering = .shuffled
        before.customTextPipeDelimiter = true
        before.customTextSectionLimit = 8
        let result = draft.applying(to: before, parameterMemory: memory)
        XCTAssertEqual(result.mode, mode)
        XCTAssertEqual(result.customTextCompletion, completion)
        XCTAssertEqual(result.customTextOrdering, .shuffled)
        XCTAssertEqual(result.customTextPipeDelimiter, true)
        let updated = draft.parameterMemory(preserving: memory)
        XCTAssertEqual(updated.duration, 555)
        XCTAssertEqual(updated.wordLimit, 888)
        XCTAssertEqual(updated.customTextDuration, 99)
        XCTAssertEqual(updated.customTextWordLimit, 44)
        XCTAssertEqual(updated.customTextSectionLimit, 3)
        if mode == .custom {
          switch completion {
          case .time: XCTAssertEqual(result.duration, 99); XCTAssertNil(result.wordLimit)
          case .words: XCTAssertEqual(result.wordLimit, 44); XCTAssertNil(result.duration)
          case .sections: XCTAssertNil(result.duration); XCTAssertNil(result.wordLimit); XCTAssertEqual(result.customTextSectionLimit, 3)
          case .finish: XCTAssertNil(result.duration); XCTAssertNil(result.wordLimit)
          }
        }
      }
    }
  }

  @MainActor
  func testLimitsRejectNonNativeRangesWithoutTruncationAndFieldsAreRequired() throws {
    let defaults = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    for key in WebsiteConfigNativeTestParameters.mappedKeys {
      var runtime = defaults
      runtime.removeValue(forKey: key)
      XCTAssertThrowsError(try WebsiteConfigNativeTestParameters(runtime: runtime)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeTestParametersError, .missingField(key))
      }
      runtime[key] = .null
      XCTAssertThrowsError(try WebsiteConfigNativeTestParameters(runtime: runtime)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeTestParametersError, .invalidField(key))
      }
    }
    for key in ["time", "words"] {
      for number in [-1.0, 0.5, .nan, .infinity, -.infinity] {
        var runtime = defaults
        runtime[key] = .number(number)
        XCTAssertThrowsError(try WebsiteConfigNativeTestParameters(runtime: runtime)) {
          XCTAssertEqual($0 as? WebsiteConfigNativeTestParametersError, .invalidField(key))
        }
      }
      for number in [9_007_199_254_740_992.0, Double.greatestFiniteMagnitude] {
        var runtime = defaults
        runtime[key] = .number(number)
        XCTAssertThrowsError(try WebsiteConfigNativeTestParameters(runtime: runtime)) {
          XCTAssertEqual($0 as? WebsiteConfigNativeTestParametersError, .unrepresentableField(key))
        }
      }
    }
    for (key, alias) in [("language", "english1k"), ("language", "mixedLanguages"), ("mode", "timed")] {
      var runtime = defaults
      runtime[key] = .string(alias)
      XCTAssertThrowsError(try WebsiteConfigNativeTestParameters(runtime: runtime)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeTestParametersError, .invalidField(key))
      }
    }
    var nonfinal = defaults
    nonfinal["mode"] = .string("quote")
    nonfinal["numbers"] = .bool(true)
    XCTAssertThrowsError(try WebsiteConfigNativeTestParameters(runtime: nonfinal)) {
      XCTAssertEqual($0 as? WebsiteConfigNativeTestParametersError, .invalidField("numbers"))
    }
  }

  @MainActor
  func testZeroLimitsDriveActualInfiniteSessionsAndFiniteWordsFinish() throws {
    let start = Date(timeIntervalSinceReferenceDate: 10_000)
    for mode in ["words", "time"] {
      let runtime = try WebsiteConfigNativeProfile.prepare(
        "{\"mode\":\"\(mode)\",\"time\":-0,\"words\":0}", context: .init()).projection.runtime
      let draft = try WebsiteConfigNativeTestParameters(runtime: runtime)
      let configuration = draft.applying(to: .words(2), parameterMemory: .defaults)
      XCTAssertTrue(configuration.isInfinite)
      var session = TypingSession(configuration: configuration, prompt: "amber bay cedar")
      session.insert("amber ", at: start)
      XCTAssertEqual(session.outcome, .active)
    }
    let runtime = try WebsiteConfigNativeProfile.prepare(#"{"mode":"words","words":2}"#, context: .init()).projection.runtime
    let configuration = try WebsiteConfigNativeTestParameters(runtime: runtime).applying(to: .timed(seconds: 15), parameterMemory: .defaults)
    var finite = TypingSession(configuration: configuration, prompt: "amber bay")
    finite.insert("amber bay ", at: start)
    XCTAssertEqual(finite.outcome, .completed)
  }

  @MainActor
  func testDraftGroupsAndInactiveParametersSurviveNativeJSON() throws {
    let runtime = try WebsiteConfigNativeProfile.prepare(
      #"{"mode":"words","words":75,"time":120,"language":"french_1k","difficulty":"expert","minWpmCustomSpeed":0,"minWpm":"custom","britishEnglish":true,"keymapLayout":"qwerty"}"#,
      context: .init()).projection.runtime
    let parameters = try WebsiteConfigNativeTestParameters(runtime: runtime)
    let rules = try WebsiteConfigNativeInputRules(runtime: runtime)
    let behavior = try WebsiteConfigNativeBehavior(runtime: runtime)
    let keyboard = try WebsiteConfigNativeKeyboardTypography(runtime: runtime, pointsPerRem: 16)
    let presentation = try WebsiteConfigNativePresentation(runtime: runtime)
    let otherKeys = WebsiteConfigNativeInputRules.mappedKeys.union(WebsiteConfigNativeBehavior.mappedKeys)
      .union(WebsiteConfigNativePresentation.mappedKeys).union(WebsiteConfigNativeKeyboardTypography.mappedKeys)
    XCTAssertTrue(otherKeys.isDisjoint(with: WebsiteConfigNativeTestParameters.mappedKeys))
    XCTAssertEqual(otherKeys.union(WebsiteConfigNativeTestParameters.mappedKeys).count, 76)
    let configuration = parameters.applying(to: behavior.applying(to: rules.applying(to: .timed(seconds: 15))), parameterMemory: .defaults)
    XCTAssertEqual(configuration, rules.applying(to: behavior.applying(to: parameters.applying(to: .timed(seconds: 15), parameterMemory: .defaults))))
    let settings = keyboard.applying(to: presentation.applying(to: behavior.applying(to: rules.applying(to: AppSettingsSnapshot()))))
    let memory = parameters.parameterMemory(preserving: .defaults)
    let json = try SettingsJSONCommandCodec.export(settings: settings, configuration: configuration,
      layoutFluidLayouts: [.ansiQwerty, .ansiDvorak], testParameterMemory: memory)
    let restored = try SettingsJSONCommandCodec.decode(json)
    XCTAssertEqual(restored.version, 6)
    XCTAssertEqual(restored.testParameterMemory, memory)
    XCTAssertEqual(try Self.nativeFields(restored.configuration, memory: restored.testParameterMemory),
      runtime.filter { WebsiteConfigNativeTestParameters.mappedKeys.contains($0.key) })
    XCTAssertEqual(restored.configuration.rules.thresholdSource, configuration.rules.thresholdSource)
  }

  @MainActor
  func testFinalModeKeepsBothOrdinaryLimitsAndCustomMemory() throws {
    let runtime = try WebsiteConfigNativeProfile.prepare(
      #"{"mode":"words","words":75,"time":120,"language":"english_1k","numbers":true,"punctuation":true}"#,
      context: .init()).projection.runtime
    let draft = try WebsiteConfigNativeTestParameters(runtime: runtime)
    let memory = TypebarTestParameterMemory(duration: 15, wordLimit: 10,
      customTextDuration: 99, customTextWordLimit: 44, customTextSectionLimit: 3)
    let updated = draft.parameterMemory(preserving: memory)
    let configuration = draft.applying(to: .timed(seconds: 15), parameterMemory: memory)
    XCTAssertEqual(configuration.mode, .words)
    XCTAssertEqual(configuration.wordLimit, 75)
    XCTAssertNil(configuration.duration)
    XCTAssertEqual(configuration.language, .english1k)
    XCTAssertTrue(configuration.contentOptions.includePunctuation)
    XCTAssertTrue(configuration.contentOptions.includeNumbers)
    XCTAssertEqual(updated.duration, 120)
    XCTAssertEqual(updated.wordLimit, 75)
    XCTAssertEqual(updated.customTextDuration, 99)
    XCTAssertEqual(updated.customTextWordLimit, 44)
    XCTAssertEqual(updated.customTextSectionLimit, 3)
  }
}
