import CryptoKit
import XCTest
@testable import Typebar

final class KoreanScoringUnitsTests: XCTestCase {
  private func project(_ text: String) -> [UInt16] {
    KoreanScoringUnits.disassemble(Array(text.utf16))
  }

  func testModernSyllablesExpandIntoCompatibilityJamoNotNFD() {
    for (input, expected) in [("가", "ㄱㅏ"), ("각", "ㄱㅏㄱ"), ("갃", "ㄱㅏㄱㅅ"),
      ("괅", "ㄱㅗㅏㄹㄱ"), ("힣", "ㅎㅣㅎ")] {
      XCTAssertEqual(project(input), Array(expected.utf16), input)
    }
    XCTAssertNotEqual(project("가"), Array("가".decomposedStringWithCanonicalMapping.utf16))
  }

  func testMixedComponentClustersSplitButShiftedDoubleLettersDoNot() {
    XCTAssertEqual(project("ㄲㅄㅙ"), Array("ㄲㅂㅅㅗㅐ".utf16))
    XCTAssertEqual(project("까갂"), Array("ㄲㅏㄱㅏㄲ".utf16))
    XCTAssertEqual(project("ㄲㄸㅃㅆㅉ"), Array("ㄲㄸㅃㅆㅉ".utf16))
  }

  func testConjoiningArchaicAndOutOfModernRangeUnitsStayRaw() {
    let raw: [UInt16] = [0x1100,0x1161,0x11a8,0x3130,0x318f,0xa960,0xa97f,
      0xd7a4,0xd7af,0xd7b0,0xd7ff,0xd83d,0xde42,0xd83d,0x20,0xdc00,0xfeff,0x85]
    XCTAssertEqual(KoreanScoringUnits.disassemble(raw), raw)
  }

  func testProjectionDoesNotComposeAcrossRawUnitBoundaries() {
    XCTAssertEqual(project("가"), Array("가".utf16))
    XCTAssertEqual(project("A가🙂\te\u{301} ㄳ"), Array("Aㄱㅏ🙂\te\u{301} ㄱㅅ".utf16))
    let input = Array("A괅🙂가 ㄲ".utf16)
    XCTAssertEqual(KoreanScoringUnits.disassemble(input), input.flatMap { KoreanScoringUnits.disassemble([$0]) })
  }

  func testEveryBMPUnitMatchesPinnedSourceFingerprint() {
    // Digest of the actual, integrity-verified hangul-js 0.2.6 oracle, not a
    // second native implementation. Include raw surrogate halves unchanged.
    var hash = SHA256()
    for value in 0...0xffff {
      let unit = UInt16(value)
      let output = KoreanScoringUnits.disassemble([unit])
      let tuple = [unit, UInt16(output.count)] + output
      hash.update(data: Data(tuple.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] }))
    }
    XCTAssertEqual(hash.finalize().map { String(format: "%02x", $0) }.joined(),
      "3ce3e56e227e9d618cd7b00e63c65ffd783807a110e071bde31d1172d05144a7")
  }

  func testCompleteDomainIsBoundedIdempotentAndUnitwiseComposable() {
    let domain = (0...0xffff).map(UInt16.init)
    var changedModern = 0
    var changedOther = 0
    var maximum = 0
    var individual: [UInt16] = []
    for unit in domain {
      let output = KoreanScoringUnits.disassemble([unit])
      XCTAssertFalse(output.isEmpty)
      XCTAssertLessThanOrEqual(output.count, 5)
      XCTAssertEqual(KoreanScoringUnits.disassemble(output), output)
      if output != [unit] {
        if (0xac00...0xd7a3).contains(unit) { changedModern += 1 }
        else { changedOther += 1 }
      }
      maximum = max(maximum, output.count)
      individual.append(contentsOf: output)
    }
    XCTAssertEqual(changedModern, 11_172)
    XCTAssertEqual(changedOther, 19) // 18 mixed clusters plus the source NUL quirk.
    XCTAssertEqual(maximum, 5)
    XCTAssertEqual(KoreanScoringUnits.disassemble(domain), individual)
    XCTAssertEqual(KoreanScoringUnits.disassemble([]), [])
  }

  func testNULSourceQuirkOnlyChangesExplicitProjectionNotOriginalUnits() {
    let raw: [UInt16] = [0,0xac00,0xd83d,0xdc00]
    XCTAssertEqual(KoreanScoringUnits.disassemble(raw), [0x3131,0x3131,0x314f,0xd83d,0xdc00])
    XCTAssertEqual(raw, [0,0xac00,0xd83d,0xdc00])
  }

  func testExplicitProjectedClassificationMatchesTwelveSourceFixtures() {
    // Keep the foundation composition independently checked alongside the
    // production classifier's explicit basis, using pinned source fixtures.
    let cases: [([UInt16], [UInt16], Bool, [Int])] = [
      (Array("각".utf16), Array("각".utf16), true, [3,3,0,0,0]),
      (Array("가".utf16), Array("각".utf16), true, [2,2,0,0,0]),
      (Array("가".utf16), Array("각".utf16), false, [2,0,0,0,1]),
      (Array("갃".utf16), Array("갃".utf16), true, [4,4,0,0,0]),
      (Array("괅".utf16), Array("괅".utf16), true, [5,5,0,0,0]),
      (Array("갂".utf16), Array("갂".utf16), true, [3,3,0,0,0]),
      (Array("ㄲㅄㅙ".utf16), Array("ㄲㅄㅙ".utf16), true, [5,5,0,0,0]),
      (Array("가".utf16), Array("가".utf16), true, [0,0,2,0,0]),
      (Array("가🙂".utf16), Array("가🙂".utf16), true, [4,4,0,0,0]),
      ([0xac00,0xd83d], [0xac00,0xd83d], true, [3,3,0,0,0]),
      ([0xac00,0x3000], [0xac00,32], true, [3,3,0,0,0]),
      ([0xd83d], [0xd83d,0xde42], false, [1,0,0,0,1]),
    ]
    for (input, target, partial, expected) in cases {
      let value = ResultUnitCharacterStats.classify(
        input: KoreanScoringUnits.disassemble(input),
        target: KoreanScoringUnits.disassemble(target), creditsPartial: partial)
      XCTAssertEqual([value.allCorrect,value.correctWord,value.incorrect,value.extra,value.missed], expected)
      XCTAssertEqual(ResultUnitCharacterStats.classify(input: input, target: target,
        creditsPartial: partial, basis: .koreanJamo), value)
    }
    let input = KoreanScoringUnits.disassemble([0xac00,0x3000])
    XCTAssertEqual(ResultUnitCharacterStats.classify(input: input, target: nil, creditsPartial: false).correctWord, 3)
    XCTAssertEqual(ResultUnitCharacterStats.classify(input: input, target: [], creditsPartial: false).extra, 3)
  }
}
