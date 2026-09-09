import Foundation
import XCTest

@testable import Typebar

final class OfficialLayoutCoverageTests: XCTestCase {
  private struct Fixture: Decodable {
    let referenceRepository: String
    let referenceCommit: String
    let officialCount: Int
    let officialNames: [String]
    let nativeExact: [String: String]
    let nativeRelated: [String: String]
    let unlistedPolicy: String
  }

  private struct LanguageFixture: Decodable {
    let referenceRepository: String
    let referenceCommit: String
    let officialCount: Int
    let officialIDs: [String]
    let nativeIndependent: [String: String]
    let nativeRelatedChoice: [String: String]
    let unmappedOfficialIDs: [String]
    let sourceFiles: [String]
    let method: String
  }

  private struct ConfigFixture: Decodable {
    let referenceRepository: String
    let referenceCommit: String
    let officialCount: Int
    let officialKeys: [String]
    let mapped: [String: String]
    let partial: [String: String]
    let notApplicable: [String: String]
    let unimplemented: [String: String]
    let untrackedOfficialKeys: [String]
    let officialChoices: [String: [String]]
    let officialChoiceCounts: [String: Int]
    let officialBooleanKeys: [String]
    let sourceFiles: [String]
    let method: String
  }

  func testPinnedOfficialLayoutCoverageIsCompleteUniqueAndResolvable() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let data = try Data(
      contentsOf: repositoryRoot.appendingPathComponent("Compatibility/official-layouts.json"))
    let fixture = try JSONDecoder().decode(Fixture.self, from: data)
    let officialNames = Set(fixture.officialNames)
    let exactNames = Set(fixture.nativeExact.keys)
    let relatedNames = Set(fixture.nativeRelated.keys)

    XCTAssertEqual(fixture.referenceRepository, "monkeytypegame/monkeytype")
    XCTAssertEqual(fixture.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(fixture.officialCount, 239)
    XCTAssertEqual(fixture.officialNames.count, fixture.officialCount)
    XCTAssertEqual(officialNames.count, fixture.officialCount)
    XCTAssertEqual(fixture.nativeExact.count, 239)
    XCTAssertEqual(fixture.nativeRelated.count, 0)
    XCTAssertTrue(exactNames.isSubset(of: officialNames))
    XCTAssertTrue(relatedNames.isSubset(of: officialNames))
    XCTAssertTrue(exactNames.isDisjoint(with: relatedNames))
    XCTAssertEqual(
      fixture.officialCount - exactNames.count - relatedNames.count,
      0)
    XCTAssertEqual(fixture.unlistedPolicy, "systemInputOrCustom")

    for rawValue in Array(fixture.nativeExact.values) + Array(fixture.nativeRelated.values) {
      XCTAssertNotNil(KeyboardLayout(rawValue: rawValue), "Unknown Typebar layout: \(rawValue)")
    }

    let configAudit = try String(
      contentsOf: repositoryRoot.appendingPathComponent("OFFICIAL_CONFIG_AUDIT.md"),
      encoding: .utf8)
    XCTAssertTrue(
      configAudit.contains("当前 \(KeyboardLayout.allCases.count) 个原生内置布局"))
    XCTAssertTrue(
      configAudit.contains(
        "\(fixture.nativeExact.count) 项精确映射与 \(fixture.nativeRelated.count) 项兼容映射"))
  }

  func testLayoutCommandCatalogCoversOnlyPinnedOfficialChoicesAndRoutesEveryMapping() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let data = try Data(
      contentsOf: repositoryRoot.appendingPathComponent("Compatibility/official-layouts.json"))
    let fixture = try JSONDecoder().decode(Fixture.self, from: data)
    let expectedIDs = Set(["input.layout.default"] + fixture.officialNames.map { "input.layout.\($0)" })

    XCTAssertEqual(OfficialLayoutCommandCatalog.items.count, fixture.officialCount + 1)
    XCTAssertEqual(Set(OfficialLayoutCommandCatalog.items.map(\.id)), expectedIDs)
    XCTAssertEqual(OfficialLayoutCommandCatalog.target(for: "input.layout.default"), .system)
    for (officialName, rawValue) in fixture.nativeExact {
      let layout = try XCTUnwrap(KeyboardLayout(rawValue: rawValue))
      XCTAssertEqual(
        OfficialLayoutCommandCatalog.target(for: "input.layout.\(officialName)"),
        .builtIn(layout), officialName)
    }
    XCTAssertNil(OfficialLayoutCommandCatalog.target(for: "input.layout.nordicQwerty"))
    XCTAssertNil(OfficialLayoutCommandCatalog.target(for: "input.layout.qwerty.extra"))
    XCTAssertNil(OfficialLayoutCommandCatalog.target(for: "input.layout."))
  }

  func testCurrentLanguageCatalogCountsMatchCompatibilityDocuments() throws {
    let languages = TypingLanguage.allCases
    let standalone = languages.filter(\.supportsQuotes)
    let code = languages.filter(\.isCodeLanguage)
    let mixed: Set<TypingLanguage> = [.mixedEnglishChinese, .mixedLanguages]

    XCTAssertEqual(languages.count, 448)
    XCTAssertEqual(standalone.count, 376)
    XCTAssertEqual(code.count, 70)
    XCTAssertEqual(Set(languages), Set(standalone).union(code).union(mixed))

    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let currentSummary = "当前语言目录：376 个可单独练习的语言或书写方式、70 个代码选择和 2 个混合入口。"
    for name in [
      "README.md", "FUNCTIONAL_INVENTORY.md", "REWRITE_SPEC.md",
      "OFFICIAL_CONFIG_AUDIT.md", "OFFICIAL_LANGUAGE_AUDIT.md",
    ] {
      let document = try String(
        contentsOf: repositoryRoot.appendingPathComponent(name), encoding: .utf8)
      XCTAssertTrue(document.contains(currentSummary), "\(name) 缺少当前语言目录摘要")
    }
  }

  func testPinnedOfficialLanguageCoverageIsPartitionedAndResolvable() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fixtureURL = repositoryRoot.appendingPathComponent("Compatibility/official-languages.json")
    let data = try Data(contentsOf: fixtureURL)
    let fixture = try JSONDecoder().decode(LanguageFixture.self, from: data)
    let officialIDs = Set(fixture.officialIDs)
    let independentIDs = Set(fixture.nativeIndependent.keys)
    let relatedIDs = Set(fixture.nativeRelatedChoice.keys)
    let unmappedIDs = Set(fixture.unmappedOfficialIDs)
    let expectedUnmappedIDs: Set<String> = []

    XCTAssertEqual(fixture.referenceRepository, "monkeytypegame/monkeytype")
    XCTAssertEqual(fixture.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(fixture.officialCount, 446)
    XCTAssertEqual(fixture.officialIDs.count, fixture.officialCount)
    XCTAssertEqual(officialIDs.count, fixture.officialCount)
    XCTAssertEqual(fixture.nativeIndependent.count, 446)
    XCTAssertEqual(fixture.nativeRelatedChoice.count, 0)
    XCTAssertEqual(unmappedIDs.count, 0)
    XCTAssertEqual(unmappedIDs, expectedUnmappedIDs)
    XCTAssertTrue(independentIDs.isDisjoint(with: relatedIDs))
    XCTAssertTrue(independentIDs.isDisjoint(with: unmappedIDs))
    XCTAssertTrue(relatedIDs.isDisjoint(with: unmappedIDs))
    XCTAssertEqual(independentIDs.union(relatedIDs).union(unmappedIDs), officialIDs)

    let independentlyCoveredLanguages = Set(fixture.nativeIndependent.values)
    let nativeNonMixedLanguages = Set(
      TypingLanguage.allCases.filter { language in
        language != .mixedEnglishChinese && language != .mixedLanguages
      }.map(\.rawValue))
    XCTAssertEqual(independentlyCoveredLanguages.count, fixture.nativeIndependent.count)
    XCTAssertEqual(independentlyCoveredLanguages, nativeNonMixedLanguages)
    XCTAssertEqual(
      Set(TypingLanguage.mixableLanguages.map(\.rawValue)), independentlyCoveredLanguages)

    for rawValue in Array(fixture.nativeIndependent.values) + Array(fixture.nativeRelatedChoice.values) {
      XCTAssertNotNil(TypingLanguage(rawValue: rawValue), "Unknown Typebar language: \(rawValue)")
    }

    XCTAssertEqual(
      fixture.sourceFiles,
      ["packages/schemas/src/languages.ts", "Sources/Typebar/TypingEngine.swift"])
    XCTAssertTrue(fixture.method.contains("metadata only"))
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"words\""))
  }

  func testPinnedOfficialConfigCoverageIsPartitionedWithoutMissingKeys() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let data = try Data(
      contentsOf: repositoryRoot.appendingPathComponent("Compatibility/official-configs.json"))
    let fixture = try JSONDecoder().decode(ConfigFixture.self, from: data)
    let officialKeys = Set(fixture.officialKeys)
    let mappedKeys = Set(fixture.mapped.keys)
    let partialKeys = Set(fixture.partial.keys)
    let notApplicableKeys = Set(fixture.notApplicable.keys)
    let unimplementedKeys = Set(fixture.unimplemented.keys)
    let untrackedKeys = Set(fixture.untrackedOfficialKeys)

    XCTAssertEqual(fixture.referenceRepository, "monkeytypegame/monkeytype")
    XCTAssertEqual(fixture.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(fixture.officialCount, 94)
    XCTAssertEqual(fixture.officialKeys.count, fixture.officialCount)
    XCTAssertEqual(officialKeys.count, fixture.officialCount)
    XCTAssertEqual(fixture.mapped.count, 91)
    XCTAssertEqual(fixture.partial.count, 2)
    XCTAssertEqual(fixture.notApplicable.count, 1)
    XCTAssertEqual(fixture.notApplicable["ads"], "无")
    XCTAssertEqual(
      fixture.officialChoiceCounts,
      [
        "playSoundOnClick": 27, "playSoundOnError": 5, "playTimeWarning": 5,
        "caretStyle": 8, "paceCaretStyle": 8, "timerColor": 4, "monkeyPowerLevel": 5,
        "quoteLength": 6, "timerStyle": 6, "liveSpeedStyle": 3, "liveAccStyle": 3,
        "liveBurstStyle": 3, "timerOpacity": 4, "highlightMode": 6,
        "typedEffect": 4, "tapeMode": 3, "typingSpeedUnit": 5,
      ])
    XCTAssertEqual(fixture.officialChoices["quoteLength"], ["-3", "-2", "0", "1", "2", "3"])
    XCTAssertEqual(
      fixture.officialChoices["playSoundOnError"], ["off", "1", "2", "3", "4"])
    XCTAssertEqual(
      fixture.officialChoices["playTimeWarning"], ["off", "1", "3", "5", "10"])
    XCTAssertEqual(
      fixture.officialChoices["caretStyle"],
      ["off", "default", "block", "outline", "underline", "carrot", "banana", "monkey"])
    XCTAssertEqual(
      fixture.officialChoices["paceCaretStyle"], fixture.officialChoices["caretStyle"])
    XCTAssertEqual(
      fixture.officialChoices["timerColor"], ["black", "sub", "text", "main"])
    XCTAssertEqual(
      fixture.officialChoices["timerStyle"],
      ["off", "bar", "text", "mini", "flash_text", "flash_mini"])
    XCTAssertEqual(fixture.officialChoices["liveSpeedStyle"], ["off", "text", "mini"])
    XCTAssertEqual(fixture.officialChoices["liveAccStyle"], ["off", "text", "mini"])
    XCTAssertEqual(fixture.officialChoices["liveBurstStyle"], ["off", "text", "mini"])
    XCTAssertEqual(fixture.officialChoices["timerOpacity"], ["0.25", "0.5", "0.75", "1"])
    XCTAssertEqual(
      fixture.officialChoices["highlightMode"],
      ["off", "letter", "word", "next_word", "next_two_words", "next_three_words"])
    XCTAssertEqual(fixture.officialChoices["typedEffect"], ["keep", "hide", "fade", "dots"])
    XCTAssertEqual(fixture.officialChoices["tapeMode"], ["off", "letter", "word"])
    XCTAssertEqual(
      fixture.officialChoices["typingSpeedUnit"], ["wpm", "cpm", "wps", "cps", "wph"])
    XCTAssertEqual(
      fixture.officialChoices["monkeyPowerLevel"], ["off", "1", "2", "3", "4"])
    XCTAssertEqual(
      fixture.officialBooleanKeys,
      [
        "smoothLineScroll", "showAllLines", "alwaysShowDecimalPlaces", "startGraphsAtZero",
        "monkey",
      ])
    XCTAssertEqual(
      Set(TypingCaretStyle.allCases.map(\.compatibilityValue)),
      Set(fixture.officialChoices["caretStyle"] ?? []))
    XCTAssertEqual(
      Set(TypingCaretStyle.allCases.map(\.compatibilityValue)),
      Set(fixture.officialChoices["paceCaretStyle"] ?? []))
    XCTAssertEqual(
      Set(LiveStatsColor.allCases.map(\.compatibilityValue)),
      Set(fixture.officialChoices["timerColor"] ?? []))
    XCTAssertEqual(
      Set(TypingPowerMode.allCases.map(\.compatibilityValue)),
      Set(fixture.officialChoices["monkeyPowerLevel"] ?? []))
    XCTAssertEqual(
      QuoteSelection.compatibilityValues(mode: .lengths)
        .union(QuoteSelection.compatibilityValues(mode: .favorites))
        .union(QuoteSelection.compatibilityValues(mode: .search)),
      Set(fixture.officialChoices["quoteLength"] ?? []))
    XCTAssertEqual(
      TypingClickSoundStyle.allCases.count + 1,
      fixture.officialChoiceCounts["playSoundOnClick"])
    XCTAssertEqual(
      TypingErrorSoundStyle.allCases.count + 1,
      fixture.officialChoiceCounts["playSoundOnError"])
    XCTAssertEqual(
      TimeWarningOffset.allCases.count,
      fixture.officialChoiceCounts["playTimeWarning"])
    XCTAssertEqual(
      Set(TimeWarningOffset.allCases.map { $0 == .off ? "off" : String($0.rawValue) }),
      Set(fixture.officialChoices["playTimeWarning"] ?? []))
    XCTAssertTrue(unimplementedKeys.isEmpty)
    XCTAssertTrue(untrackedKeys.isEmpty)
    XCTAssertTrue(mappedKeys.isDisjoint(with: partialKeys))
    XCTAssertTrue(mappedKeys.isDisjoint(with: notApplicableKeys))
    XCTAssertTrue(mappedKeys.isDisjoint(with: unimplementedKeys))
    XCTAssertTrue(partialKeys.isDisjoint(with: notApplicableKeys))
    XCTAssertTrue(partialKeys.isDisjoint(with: unimplementedKeys))
    XCTAssertTrue(notApplicableKeys.isDisjoint(with: unimplementedKeys))
    XCTAssertEqual(
      mappedKeys.union(partialKeys).union(notApplicableKeys).union(unimplementedKeys)
        .union(untrackedKeys), officialKeys)
    XCTAssertTrue(
      (Array(fixture.mapped.values) + Array(fixture.partial.values)
        + Array(fixture.notApplicable.values) + Array(fixture.unimplemented.values))
        .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    XCTAssertEqual(
      fixture.sourceFiles,
      ["packages/schemas/src/configs.ts", "OFFICIAL_CONFIG_AUDIT.md"])
    XCTAssertTrue(fixture.method.contains("metadata only"))
  }
}
