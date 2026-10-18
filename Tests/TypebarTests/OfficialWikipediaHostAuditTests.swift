import Foundation
import XCTest
@testable import Typebar

final class OfficialWikipediaHostAuditTests: XCTestCase {
  private struct Coverage: Decodable {
    let officialIDs: [String]
    let nativeIndependent: [String: String]
  }

  private struct SourceLanguage: Decodable {
    let bcp47: String?
  }

  func testEnabledWikipediaHostsMatchSourceOrDeclaredNativeExceptions() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let referenceRoot = environment["TYPEBAR_REFERENCE_ROOT"]
      ?? environment["TYPEBAR_LAYOUT_AUDIT_REFERENCE"] else {
      throw XCTSkip("Pinned read-only Monkeytype reference required")
    }
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let coverage = try JSONDecoder().decode(Coverage.self,
      from: Data(contentsOf: projectRoot.appendingPathComponent("Compatibility/official-languages.json")))
    let sourceRoot = URL(fileURLWithPath: referenceRoot)
      .appendingPathComponent("frontend/static/languages")
    // Missing source bcp47 falls back to English; Typebar keeps a usable
    // local-language host. The source's nb alias redirects to canonical no,
    // its bn_BD value is not a valid Wikipedia host label, and Indonesian 1k
    // is incorrectly tagged hu-HU despite containing Indonesian words.
    let nativeExceptions = [
      "ukrainian": "uk", "ukrainian_1k": "uk", "ukrainian_10k": "uk", "ukrainian_50k": "uk",
      "afrikaans": "af", "afrikaans_1k": "af", "afrikaans_10k": "af",
      "croatian": "hr", "filipino": "tl",
      "norwegian_bokmal": "no", "norwegian_bokmal_1k": "no", "norwegian_bokmal_5k": "no",
      "norwegian_bokmal_10k": "no", "norwegian_bokmal_150k": "no", "norwegian_bokmal_600k": "no",
      "icelandic": "is", "catalan": "ca", "bangla_10k": "bn", "indonesian_1k": "id",
      "urdu": "ur", "urdu_1k": "ur", "urdu_5k": "ur", "xhosa_3k": "xh"
    ]
    var checked = 0
    var checkedExceptions: Set<String> = []
    for officialID in coverage.officialIDs {
      let nativeID = try XCTUnwrap(coverage.nativeIndependent[officialID])
      let language = try XCTUnwrap(TypingLanguage(rawValue: nativeID))
      let configuration = TestConfiguration.words(25, language: language)
        .with(modifiers: [.referenceStream])
      guard LivePracticeContentSource.selected(for: configuration) == .encyclopedia else { continue }
      let source = try JSONDecoder().decode(SourceLanguage.self,
        from: Data(contentsOf: sourceRoot.appendingPathComponent("\(officialID).json")))
      let expected = source.bcp47?.components(separatedBy: "-").first ?? "en"
      let actual = LivePracticeContentService.wikipediaLanguageCode(for: language)
      if let native = nativeExceptions[officialID] {
        XCTAssertEqual(actual, native, officialID)
        XCTAssertNotEqual(actual, expected, "Remove an exception once the source and native host converge")
        checkedExceptions.insert(officialID)
      } else {
        XCTAssertEqual(actual, expected, officialID)
      }
      checked += 1
    }
    XCTAssertGreaterThan(checked, 0)
    XCTAssertEqual(checkedExceptions, Set(nativeExceptions.keys))
  }
}
