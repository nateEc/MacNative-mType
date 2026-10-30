import XCTest
@testable import Typebar

final class SimplifiedChineseCorpusTests: XCTestCase {
  func testEveryNativeWordHasExactlyOneSourceRowAndExplicitAdaptationKind() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let text = try String(contentsOf: root.appendingPathComponent("Resources/SimplifiedChineseCorpusSources.txt"), encoding: .utf8)
    let lines = text.split(separator: "\n")
    XCTAssertEqual(lines.first, "word\tkind\tsourceForm\tsourceLine\ttargetWholeTokenBand")
    let rows = lines.dropFirst().map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    XCTAssertEqual(rows.count, 50_000)
    XCTAssertTrue(rows.allSatisfy { $0.count == 5 })
    guard rows.allSatisfy({ $0.count == 5 }) else { return }
    XCTAssertEqual(rows.map { $0[0] }, SimplifiedChineseCorpus.allWords)
    var authored = 0, width = 0, comma = 0
    for row in rows {
      switch row[1] {
      case "literal":
        XCTAssertEqual(row[0], row[2])
        XCTAssertNotNil(Int(row[3]))
      case "Typebar authored legacy":
        authored += 1
        XCTAssertEqual(row[0], row[2])
        XCTAssertEqual(row[3], "-")
      case "explicit fullwidth Latin writing adaptation":
        width += 1
        let adapted = row[2].replacingOccurrences(of: "O", with: "Ｏ")
          .replacingOccurrences(of: "K", with: "Ｋ").replacingOccurrences(of: "Q", with: "Ｑ")
        XCTAssertEqual(row[0], adapted)
        XCTAssertNotNil(Int(row[3]))
      case "explicit ASCII-comma writing adaptation":
        comma += 1
        XCTAssertEqual(row[0], row[2].replacingOccurrences(of: "，", with: ","))
        XCTAssertNotNil(Int(row[3]))
      default: XCTFail("Unknown provenance kind: \(row[1])")
      }
      XCTAssertTrue(row[4] == "-" || Int(row[4]) != nil)
    }
    XCTAssertEqual(authored, 7)
    XCTAssertEqual(width, 2)
    XCTAssertEqual(comma, 1)
  }

  func testFiveChoicesUseIndependentRealWordsInsteadOfScaleMarkers() {
    let cases: [(TypingLanguage, Int, Int)] = [(.simplifiedChinese, 200, 3),
      (.simplifiedChinese1k, 1000, 5), (.simplifiedChinese5k, 5000, 6),
      (.simplifiedChinese10k, 10000, 7), (.simplifiedChinese50k, 50000, 9)]
    var previous = Set<String>()
    for (language, count, maximum) in cases {
      let words = language.ownedPracticeLexicon().materialized()
      XCTAssertEqual(words.count, count)
      XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(words.first, "晨光")
      XCTAssertTrue(previous.isSubset(of: Set(words)))
      XCTAssertEqual(words.map(\.count).min(), 2)
      XCTAssertEqual(words.map(\.count).max(), maximum)
      XCTAssertFalse(words.contains("龘靐"))
      previous = Set(words)
    }
  }
}
