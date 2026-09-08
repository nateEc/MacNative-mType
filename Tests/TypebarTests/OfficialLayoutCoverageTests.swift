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

    XCTAssertEqual(languages.count, 223)
    XCTAssertEqual(standalone.count, 152)
    XCTAssertEqual(code.count, 69)
    XCTAssertEqual(Set(languages), Set(standalone).union(code).union(mixed))

    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let currentSummary = "当前语言目录：152 个可单独练习的语言或书写方式、69 个代码选择和 2 个混合入口。"
    for name in [
      "README.md", "FUNCTIONAL_INVENTORY.md", "REWRITE_SPEC.md",
      "OFFICIAL_CONFIG_AUDIT.md", "OFFICIAL_LANGUAGE_AUDIT.md",
    ] {
      let document = try String(
        contentsOf: repositoryRoot.appendingPathComponent(name), encoding: .utf8)
      XCTAssertTrue(document.contains(currentSummary), "\(name) 缺少当前语言目录摘要")
    }
  }
}
