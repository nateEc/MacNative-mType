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

  func testCurrentLanguageCatalogCountsMatchCompatibilityDocuments() throws {
    let languages = TypingLanguage.allCases
    let standalone = languages.filter(\.supportsQuotes)
    let code = languages.filter(\.isCodeLanguage)
    let mixed: Set<TypingLanguage> = [.mixedEnglishChinese, .mixedLanguages]

    XCTAssertEqual(languages.count, 425)
    XCTAssertEqual(standalone.count, 353)
    XCTAssertEqual(code.count, 70)
    XCTAssertEqual(Set(languages), Set(standalone).union(code).union(mixed))

    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let currentSummary = "当前语言目录：353 个可单独练习的语言或书写方式、70 个代码选择和 2 个混合入口。"
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
    XCTAssertEqual(fixture.nativeIndependent.count, 423)
    XCTAssertEqual(fixture.nativeRelatedChoice.count, 23)
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

    for rawValue in Array(fixture.nativeIndependent.values) + Array(fixture.nativeRelatedChoice.values) {
      XCTAssertNotNil(TypingLanguage(rawValue: rawValue), "Unknown Typebar language: \(rawValue)")
    }

    XCTAssertEqual(
      fixture.sourceFiles,
      ["packages/schemas/src/languages.ts", "Sources/Typebar/TypingEngine.swift"])
    XCTAssertTrue(fixture.method.contains("metadata only"))
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("\"words\""))
  }
}
