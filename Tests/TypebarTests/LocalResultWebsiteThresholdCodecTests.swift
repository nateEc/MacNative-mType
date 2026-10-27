import XCTest
@testable import Typebar

@MainActor final class LocalResultWebsiteThresholdCodecTests: XCTestCase {
  private func configuration() throws -> TestConfiguration {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"minWpm":"custom","minWpmCustomSpeed":1e999,"minBurst":"flex","minBurstCustomSpeed":1e999}"#,
      pointsPerRem: 16, context: .init())
    return draft.inputRules.applying(to: .words(5))
  }

  func testVersionTwoRestoresOnlyTheTaggedSpeedMemoriesAndLeavesOtherFieldsIntact() throws {
    var expected = try configuration()
    expected.language = .spanish; expected.contentOptions.includePunctuation = true
    let bytes = try LocalResultConfigurationCodec.encode(expected)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    XCTAssertEqual(object["version"] as? Int, 2)
    let tags = try XCTUnwrap(object["infiniteSpeedMemory"] as? [String: Bool])
    XCTAssertEqual(tags, ["minimumWpm": true, "minimumWordBurst": true])
    XCTAssertEqual(try LocalResultConfigurationCodec.decode(bytes), expected)
    XCTAssertThrowsError(try JSONDecoder().decode(TestConfiguration.self, from: bytes))
    let fields = try LocalResultConfigurationCodec.explicitFields(in: bytes)
    XCTAssertEqual(fields["language"] as? String, expected.language.rawValue)
    let encoder = JSONEncoder(); encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    XCTAssertThrowsError(try encoder.encode(expected), "Existing source JSON formats remain strict")
    XCTAssertThrowsError(try SettingsJSONCommandCodec.export(settings: .init(), configuration: expected,
      layoutFluidLayouts: [.ansiQwerty, .ansiDvorak], testParameterMemory: .defaults))
  }

  func testMalformedFutureDowngradedOrForeignTagsNeverFallBackToFiniteRules() throws {
    let bytes = try LocalResultConfigurationCodec.encode(configuration())
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    var cases: [[String: Any]] = []
    var future = original; future["version"] = 3; cases.append(future)
    var downgraded = original; downgraded["version"] = 1; cases.append(downgraded)
    var foreign = original; foreign["kind"] = "foreign"; cases.append(foreign)
    var missing = original; missing.removeValue(forKey: "infiniteSpeedMemory"); cases.append(missing)
    for tags: Any in [NSNull(), ["minimumWpm": false, "minimumWordBurst": false],
      ["minimumWpm": true], ["minimumWpm": "true", "minimumWordBurst": true]] {
      var altered = original; altered["infiniteSpeedMemory"] = tags; cases.append(altered)
    }
    func changingConfiguration(_ mutate: (inout [String: Any]) throws -> Void) throws -> [String: Any] {
      var altered = original, config = try XCTUnwrap(original["configuration"] as? [String: Any])
      try mutate(&config); altered["configuration"] = config; return altered
    }
    cases.append(try changingConfiguration { $0["duration"] = "Infinity" })
    cases.append(try changingConfiguration { config in
      var rules = try XCTUnwrap(config["rules"] as? [String: Any]); rules["minimumWpm"] = "Infinity"; config["rules"] = rules
    })
    cases.append(try changingConfiguration { config in
      var rules = try XCTUnwrap(config["rules"] as? [String: Any])
      var source = try XCTUnwrap(rules["thresholdSource"] as? [String: Any])
      var raw = try XCTUnwrap(source["configuration"] as? [String: Any]); raw["minimumWpmCustomValue"] = 101
      source["configuration"] = raw; rules["thresholdSource"] = source; config["rules"] = rules
    })
    for (index, altered) in cases.enumerated() {
      let invalid = try JSONSerialization.data(withJSONObject: altered)
      XCTAssertThrowsError(try LocalResultConfigurationCodec.decode(invalid), "Malformed v2 case \(index)")
      XCTAssertThrowsError(try LocalResultConfigurationCodec.explicitFields(in: invalid))
    }
    let fields = try XCTUnwrap(original["configuration"] as? [String: Any])
    var partial = fields; partial.removeValue(forKey: "language")
    var missingLanguage = original; missingLanguage["configuration"] = partial
    let audited = try LocalResultConfigurationCodec.explicitFields(in: JSONSerialization.data(withJSONObject: missingLanguage))
    XCTAssertNil(audited["language"], "Presence audit must not fill legacy defaults while restoring tags")
  }

  func testUnrelatedNonfiniteValuesAndMismatchedSourceAreStillRejected() throws {
    let base = try configuration()
    for field in ["duration", "accuracy", "speed"] {
      var invalid = base
      switch field {
      case "duration": invalid.duration = .infinity
      case "accuracy": invalid.rules.minimumAccuracy = .nan
      default: invalid.rules.minimumWpm = 42
      }
      XCTAssertThrowsError(try LocalResultConfigurationCodec.encode(invalid), field)
    }
  }

  func testOneInfiniteMemoryPreservesTheOtherFiniteBinary64Value() throws {
    for (speed, burst) in [(-0.0, Double.infinity), (.infinity, -0.0),
      (.greatestFiniteMagnitude, .infinity), (.infinity, .greatestFiniteMagnitude)] {
      let source = PracticeThresholdSource(configuration: try .init(websiteMinimumWpmMode: .off,
        speed: speed, accuracyMode: .off, accuracy: 90, burstMode: .off, burst: burst))
      var original = TestConfiguration.words(5); original.rules = source.applying(to: original.rules)
      let decoded = try LocalResultConfigurationCodec.decode(LocalResultConfigurationCodec.encode(original))
      let memory = try XCTUnwrap(decoded.rules.thresholdSource).configuration
      XCTAssertEqual(memory.minimumWpmCustomValue.bitPattern, speed.bitPattern)
      XCTAssertEqual(memory.minimumWordBurstCustomValue.bitPattern, burst.bitPattern)
      XCTAssertEqual(decoded, original)
    }
  }
}
