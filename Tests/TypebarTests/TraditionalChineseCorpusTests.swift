import XCTest
@testable import Typebar

final class TraditionalChineseCorpusTests: XCTestCase {
  func testAllNativeWordsKeepSeparateFrequencyScopesAndExplicitSourceKinds() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let text = try String(contentsOf: root.appendingPathComponent("Resources/TraditionalChineseCorpusSources.txt"), encoding: .utf8)
    let lines = text.split(separator: "\n")
    XCTAssertEqual(lines.first, "word\tkind\tsourceForm\tsimplifiedSourceForm\tsourceLine\ttargetRawBand\tsimplifiedSourceBand")
    let rows = lines.dropFirst().map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
    XCTAssertEqual(rows.count, 49_984)
    XCTAssertTrue(rows.allSatisfy { $0.count == 7 })
    guard rows.allSatisfy({ $0.count == 7 }) else { return }
    let all = TraditionalChineseCorpus.allWords + TraditionalChineseCorpus.basic
    XCTAssertEqual(Set(rows.map { $0[0] }), Set(all))
    XCTAssertEqual(Set(rows.map { $0[0] }).count, rows.count)
    var kinds: [String: Int] = [:]
    var unknownTargetWithKnownSource = 0
    for row in rows {
      kinds[row[1], default: 0] += 1
      switch row[1] {
      case "literal": XCTAssertEqual(row[0], row[2])
      case "Typebar authored legacy":
        XCTAssertEqual(row[0], row[2])
        XCTAssertEqual(Array(row[3...4]), ["-", "-"])
        XCTAssertEqual(row[6], "-")
      case "explicit fullwidth Latin writing adaptation":
        XCTAssertEqual(row[0], row[2].replacingOccurrences(of: "O", with: "Ｏ")
          .replacingOccurrences(of: "K", with: "Ｋ").replacingOccurrences(of: "Q", with: "Ｑ"))
      case "explicit ASCII-comma writing adaptation":
        XCTAssertEqual(row[0], row[2].replacingOccurrences(of: "，", with: ","))
      default: XCTFail("Unknown source kind")
      }
      if row[1] != "Typebar authored legacy" { XCTAssertNotNil(Int(row[4])) }
      for value in row[5...6] { XCTAssertTrue(value == "-" || Int(value) != nil) }
      if row[5] == "-" && row[6] != "-" { unknownTargetWithKnownSource += 1 }
    }
    XCTAssertEqual(kinds, ["literal": 49_975, "Typebar authored legacy": 6,
      "explicit fullwidth Latin writing adaptation": 2, "explicit ASCII-comma writing adaptation": 1])
    XCTAssertGreaterThan(unknownTargetWithKnownSource, 20_000)
  }

  func testFiveChoicesPreserveFullLengthDistributionsWithIndependentWords() {
    let cases: [(TypingLanguage, [Int: Int])] = [
      (.traditionalChinese, [1: 60, 2: 138, 3: 2]),
      (.traditionalChinese1k, [2: 986, 3: 11, 4: 2, 5: 1]),
      (.traditionalChinese5k, [2: 4624, 3: 278, 4: 77, 5: 10, 6: 2]),
      (.traditionalChinese10k, [2: 9022, 3: 685, 4: 246, 5: 15, 6: 5, 7: 1]),
      (.traditionalChinese50k, [1: 1, 2: 38062, 3: 6125, 4: 5591, 5: 102, 6: 28, 7: 6, 9: 10]),
    ]
    let legacy = Set("晨霧 海灣 筆記 微雨 松林 專注 緩步 清楚 河岸 茶香 街燈 木門 書頁 旅途 耐心 片刻 山徑 風鈴 安靜 方向 星群 畫布 庭院 呼吸".split(separator: " ").map(String.init))
    var previousLarge = Set<String>()
    for (language, expected) in cases {
      let words = language.ownedPracticeLexicon().materialized()
      XCTAssertEqual(words.count, expected.values.reduce(0, +))
      XCTAssertEqual(Set(words).count, words.count)
      XCTAssertEqual(Dictionary(grouping: words, by: \.count).mapValues(\.count), expected)
      XCTAssertTrue(legacy.isSubset(of: Set(words)))
      if language != .traditionalChinese {
        XCTAssertTrue(previousLarge.isSubset(of: Set(words)))
        previousLarge = Set(words)
      }
    }
  }
}
