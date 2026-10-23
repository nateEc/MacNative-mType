import XCTest
@testable import Typebar

final class WebsiteConfigNativeGeneratorsTests: XCTestCase {
  func testVersionedRootCaseHandlesNewLettersExpansionsAndSigmaContext() {
    func lower(_ text: String) -> [UInt16] { WebsiteUnicode17Case.converted(Array(text.utf16), upper: false) }
    XCTAssertEqual(WebsiteUnicode17Case.converted([0xA7CF], upper: true), [0xA7CE])
    XCTAssertEqual(lower("\u{A7CE}Σ"), Array("\u{A7CF}ς".utf16))
    XCTAssertEqual(lower("AΣ\u{A7CF}"), Array("aσ\u{A7CF}".utf16))
    XCTAssertEqual(lower("AΣ\u{0345}"), Array("aς\u{0345}".utf16))
    XCTAssertEqual(lower("\u{0345}Σ"), Array("\u{0345}σ".utf16))
    XCTAssertEqual(lower("İ"), [0x69, 0x0307])
    XCTAssertEqual(WebsiteUnicode17Case.converted(Array("ß".utf16), upper: true), [0x53, 0x53])
    XCTAssertEqual(WebsiteUnicode17Case.converted([0xD800, 0xA7CE, 0x03A3], upper: false), [0xD800, 0xA7CF, 0x03C2])
  }

  static func nativeFields(_ draft: WebsiteConfigNativeGenerators) throws -> [String: WebsiteConfigValue] {
    let names = try draft.funboxes.map { target -> WebsiteConfigValue in
      let pair = try XCTUnwrap(zip(FunboxCommandCatalog.officialNames, FunboxCommandCatalog.targets).first { $0.1 == target })
      return .string(pair.0)
    }
    return ["funbox": .array(names), "lazyMode": .bool(draft.lazyMode),
      "customLayoutfluid": .array(try draft.layoutFluidLayouts.map { .string(try XCTUnwrap(OfficialLayoutCommandCatalog.name(for: $0))) }),
      "customPolyglot": .array(try draft.polyglotLanguages.map { .string(try XCTUnwrap(WebsiteLanguageIdentity.name(for: $0))) })]
  }

  static func assertSourceRuntime(_ runtime: [String: WebsiteConfigValue], expected: [String: WebsiteConfigValue]? = nil) throws {
    let draft = try WebsiteConfigNativeGenerators(runtime: runtime)
    XCTAssertEqual(try nativeFields(draft), (expected ?? runtime).filter { WebsiteConfigNativeGenerators.mappedKeys.contains($0.key) })
  }

  @MainActor
  func testAllPinnedChoicesAndFinalDeduplication() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    guard env["TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT"] != nil else { return XCTFail("Requires pinned Zod") }
    struct Catalogs: Decodable { let languages: [String], layouts: [String], funboxes: [String] }
    struct Output: Decodable { let catalogs: Catalogs }
    let data = try runProbe("check-source-config-schema.mjs", reference: reference, extra: ["--default-profile"])
    let catalogs = try JSONDecoder().decode(Output.self, from: data).catalogs
    XCTAssertEqual(catalogs.languages.count, 446)
    XCTAssertEqual(catalogs.layouts.count, 239)
    XCTAssertEqual(catalogs.funboxes.count, 48)
    var samples: [WebsiteConfigValue] = catalogs.languages.map {
      .object(["customPolyglot": .array([.string($0 == "english" ? "spanish" : "english"), .string($0)])])
    }
    samples += catalogs.layouts.map {
      .object(["customLayoutfluid": .array([.string($0 == "qwerty" ? "dvorak" : "qwerty"), .string($0)])])
    }
    samples += catalogs.funboxes.map { .object(["mode": .string("words"), "funbox": .array([.string($0)])]) }
    samples += [false, true].map { .object(["lazyMode": .bool($0)]) }
    for sample in samples {
      let runtime = try WebsiteConfigNativeProfile.prepare(WebsiteConfigJSONWriter.write(sample), context: .init()).projection.runtime
      try Self.assertSourceRuntime(runtime)
    }
    XCTAssertEqual(samples.count, 735)
    let prepared = try WebsiteConfigNativeProfile.prepare(
      #"{"customPolyglot":["french","french","english"],"customLayoutfluid":["dvorak","dvorak","qwerty"]}"#,
      context: .init())
    let draft = try WebsiteConfigNativeGenerators(runtime: prepared.projection.runtime)
    XCTAssertEqual(draft.polyglotLanguages, [.french, .english])
    XCTAssertEqual(draft.layoutFluidLayouts, [.ansiDvorak, .ansiQwerty])
    print("Pinned generator identity and option samples: \(samples.count)")
  }

  @MainActor
  func testActualOrderedHandlersAcrossUTF16AndWordBoundaries() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Fixture: Decodable { let chain: [String], word: Int, index: Int, bound: Int, upper: Bool, output: [UInt16] }
    struct Output: Decodable { let names: [String], chains: Int, words: [[UInt16]], fixtures: [Fixture] }
    let output = try JSONDecoder().decode(Output.self, from: runProbe("check-source-ordered-funbox-text.mjs", reference: reference))
    XCTAssertEqual(output.names.count, 10)
    XCTAssertEqual(output.chains, 21)
    XCTAssertEqual(output.words.count, 1016)
    XCTAssertEqual(output.fixtures.count, 28448)
    var runtime = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    var mismatches: [String] = []
    for (index, fixture) in output.fixtures.enumerated() {
      runtime["funbox"] = .array(fixture.chain.map(WebsiteConfigValue.string))
      let draft = try WebsiteConfigNativeGenerators(runtime: runtime)
      let result = try draft.alteredWord(.string(units: output.words[fixture.word]), wordIndex: fixture.index,
        wordBound: fixture.bound, nextRandomCaseBit: { fixture.upper })
      if result.stringUnits != fixture.output {
        let actual = result.stringUnits ?? []
        let offset = zip(actual, fixture.output).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(actual.count, fixture.output.count)
        mismatches.append("\(index) \(fixture.chain) word=\(fixture.word) offset=\(offset) expected=\(fixture.output.dropFirst(offset).prefix(4)) actual=\(actual.dropFirst(offset).prefix(4))")
      }
    }
    XCTAssertTrue(mismatches.isEmpty, "\(mismatches.count) ordered text mismatches: \(mismatches.prefix(12))")
    print("Pinned ordered handler UTF16 fixtures: \(output.fixtures.count)")
  }

  @MainActor
  func testLoneCodeUnitsSurviveOrderingAndLazyIntentIsNotActivated() throws {
    var runtime = try WebsiteConfigNativeProfile.prepare(#"{"language":"arabic","lazyMode":false}"#, context: .init()).projection.runtime
    let disabled = try WebsiteConfigNativeGenerators(runtime: runtime)
    XCTAssertFalse(disabled.requestedModifiers.contains(.lazyLatin))
    runtime["lazyMode"] = .bool(true)
    runtime["funbox"] = .array([.string("backwards"), .string("ddoouubblleedd")])
    let draft = try WebsiteConfigNativeGenerators(runtime: runtime)
    XCTAssertTrue(draft.requestedModifiers.contains(.lazyLatin))
    XCTAssertEqual(try draft.alteredWord(.string("😀")).stringUnits, [0xDE00, 0xDE00, 0xD83D, 0xD83D])
    runtime["funbox"] = .array([.string("ddoouubblleedd"), .string("backwards")])
    let reversed = try WebsiteConfigNativeGenerators(runtime: runtime)
    XCTAssertEqual(try reversed.alteredWord(.string("😀")).stringUnits, [0xDE00, 0xD83D, 0xDE00, 0xD83D])
    runtime["funbox"] = .array([])
    XCTAssertEqual(try WebsiteConfigNativeGenerators(runtime: runtime).alteredWord(.string("café")), .string("café"))
  }

  @MainActor
  func testMalformedFieldsAndNonFinalSelectionsNeverUseLegacyFallbacks() throws {
    let defaults = try WebsiteConfigNativeProfile.prepare("{}", context: .init()).projection.runtime
    for key in WebsiteConfigNativeGenerators.mappedKeys {
      var runtime = defaults
      runtime.removeValue(forKey: key)
      XCTAssertThrowsError(try WebsiteConfigNativeGenerators(runtime: runtime)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeGeneratorsError, .missingField(key))
      }
      runtime[key] = .null
      XCTAssertThrowsError(try WebsiteConfigNativeGenerators(runtime: runtime)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeGeneratorsError, .invalidField(key))
      }
    }
    let invalid: [(String, WebsiteConfigValue)] = [
      ("customLayoutfluid", .array([.string("qwerty")])),
      ("customLayoutfluid", .array([.string("qwerty"), .string("qwerty")])),
      ("customLayoutfluid", .array([.string("ansiQwerty"), .string("dvorak")])),
      ("customPolyglot", .array([.string("english"), .string("english")])),
      ("customPolyglot", .array([.string("english1k"), .string("french")])),
      ("funbox", .array([.string("None")])), ("funbox", .array([.string("mirrorVisual")])),
      ("funbox", .array([.string("ALL_CAPS"), .string("capitals")]))
    ]
    for (key, value) in invalid {
      var runtime = defaults; runtime[key] = value
      XCTAssertThrowsError(try WebsiteConfigNativeGenerators(runtime: runtime)) {
        XCTAssertEqual($0 as? WebsiteConfigNativeGeneratorsError, .invalidField(key))
      }
    }
    let draft = try WebsiteConfigNativeGenerators(runtime: defaults)
    XCTAssertThrowsError(try draft.alteredWord(.number(1)))
    XCTAssertThrowsError(try draft.alteredWord(.string("a"), wordIndex: -1))
    XCTAssertThrowsError(try draft.alteredWord(.string("a"), wordBound: -1))
  }

  private func runProbe(_ script: String, reference: String, extra: [String] = []) throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/\(script)").path, reference] + extra
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    return data
  }

  @MainActor
  func testGeneratorDraftPreservesRepeatedFunboxesAndIndependentSelections() throws {
    var runtime = try WebsiteConfigNativeProfile.prepare(
      #"{"funbox":["rot13","rot13"],"lazyMode":true,"customLayoutfluid":["dvorak","qwerty"],"customPolyglot":["french","english"]}"#,
      context: .init()).projection.runtime
    let draft = try WebsiteConfigNativeGenerators(runtime: runtime)
    XCTAssertEqual(draft.funboxes, [.modifier(.rot13), .modifier(.rot13)])
    XCTAssertEqual(draft.layoutFluidLayouts, [.ansiDvorak, .ansiQwerty])
    XCTAssertEqual(draft.polyglotLanguages, [.french, .english])
    XCTAssertTrue(draft.lazyMode)
    XCTAssertFalse(draft.requestsPolyglot)
    XCTAssertEqual(draft.requestedModifiers, [.rot13, .rot13, .lazyLatin])
    XCTAssertEqual(try draft.alteredWord(.string("Amber")), .string("Amber"))
    XCTAssertEqual(TestModifierPolicy.transformedWord("Amber", modifiers: [.rot13, .rot13]), "Nzore")
    runtime["funbox"] = .array([.string("rot13")])
    XCTAssertEqual(try WebsiteConfigNativeGenerators(runtime: runtime).alteredWord(.string("Amber")), .string("Nzore"))
    runtime["funbox"] = .array([.string("polyglot")])
    let mixed = try WebsiteConfigNativeGenerators(runtime: runtime)
    XCTAssertTrue(mixed.requestsPolyglot)
    XCTAssertEqual(mixed.requestedModifiers, [.lazyLatin])
    let otherKeys = WebsiteConfigNativeInputRules.mappedKeys.union(WebsiteConfigNativePresentation.mappedKeys)
      .union(WebsiteConfigNativeBehavior.mappedKeys).union(WebsiteConfigNativeKeyboardTypography.mappedKeys)
      .union(WebsiteConfigNativeTestParameters.mappedKeys).union(WebsiteConfigNativeQuoteSelection.mappedKeys)
    XCTAssertTrue(otherKeys.isDisjoint(with: WebsiteConfigNativeGenerators.mappedKeys))
    XCTAssertEqual(otherKeys.union(WebsiteConfigNativeGenerators.mappedKeys).count, 81)
  }
}
