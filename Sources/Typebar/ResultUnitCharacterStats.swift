import Foundation

/// Explicit scoring-unit classification, separate from native glyph counts.
/// Position matches are not word-level speed credit. A partial active field
/// suppresses missing units even when a typo prevents prefix credit.
struct ResultUnitCharacterStats: Codable, Equatable {
  var allCorrect = 0
  var correctWord = 0
  var incorrect = 0
  var extra = 0
  var missed = 0

  static func classify(input: [UInt16], target: [UInt16]?, creditsPartial: Bool,
    basis: ResultScoringUnitBasis = .utf16) -> Self {
    var normalized = input.map { unit -> UInt16 in
      guard let scalar = UnicodeScalar(UInt32(unit)),
        InputCharacterEquivalence.isReferenceSpace(Character(String(scalar))) else { return unit }
      return 32
    }
    // Missing source target falls back to normalized input, unlike a known empty word.
    if basis == .koreanJamo { normalized = KoreanScoringUnits.disassemble(normalized) }
    let target = target.map { basis == .koreanJamo ? KoreanScoringUnits.disassemble($0) : $0 } ?? normalized
    let exact = normalized == target
    let credited = exact || creditsPartial && target.starts(with: normalized)
    var value = Self()
    value.correctWord = credited ? normalized.count : 0
    value.extra = max(0, normalized.count - target.count)
    value.missed = creditsPartial ? 0 : max(0, target.count - normalized.count)
    let containsSpace = normalized.contains(32)
    for (entered, expected) in zip(normalized, target) {
      switch (entered == expected, expected == 32) {
      case (true, true) where !exact:
        value.extra += 1
      case (true, _):
        value.allCorrect += 1
      case (false, true) where !containsSpace:
        value.extra += 1
      default:
        value.incorrect += 1
      }
    }
    return value
  }

  mutating func add(_ other: Self) {
    allCorrect += other.allCorrect; correctWord += other.correctWord
    incorrect += other.incorrect; extra += other.extra; missed += other.missed
  }

  private enum CodingKeys: String, CodingKey { case allCorrect, correctWord, incorrect, extra, missed }
  init() {}
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    allCorrect = try values.decode(Int.self, forKey: .allCorrect)
    correctWord = try values.decode(Int.self, forKey: .correctWord)
    incorrect = try values.decode(Int.self, forKey: .incorrect)
    extra = try values.decode(Int.self, forKey: .extra)
    missed = try values.decode(Int.self, forKey: .missed)
    let first = allCorrect.addingReportingOverflow(incorrect)
    let total = first.partialValue.addingReportingOverflow(extra)
    guard [allCorrect, correctWord, incorrect, extra, missed].allSatisfy({ $0 >= 0 }),
      !first.overflow, !total.overflow, correctWord <= total.partialValue else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
        debugDescription: "Unit classification must be nonnegative, bounded and conserve entered units."))
    }
  }
}

enum ResultCharacterStatsPresentation {
  static func unitName(_ stats: ResultCharacterStats) -> String {
    guard stats.sourceUnits != nil else { return "字符" }
    return stats.sourceUnitBasis == .koreanJamo ? "韩文拆分单位" : "UTF-16 单位"
  }
  static func label(_ stats: ResultCharacterStats) -> String {
    stats.sourceUnits == nil ? "字符（匹配/错位/额外/跳过）" : "\(unitName(stats))（计分正确/错误/多打/漏打）"
  }
  static func value(_ stats: ResultCharacterStats) -> String {
    if let units = stats.sourceUnits {
      return "\(units.correctWord)/\(units.incorrect)/\(units.extra)/\(units.missed)"
    }
    return "\(stats.matched)/\(stats.incorrect)/\(stats.extra)/\(stats.missed)"
  }
  static func spoken(_ stats: ResultCharacterStats) -> String {
    if let units = stats.sourceUnits {
      return "\(unitName(stats))：计分正确 \(units.correctWord)，错误 \(units.incorrect)，多打 \(units.extra)，漏打 \(units.missed)；位置匹配 \(units.allCorrect)"
    }
    return "字符：匹配 \(stats.matched)，错位 \(stats.incorrect)，额外 \(stats.extra)，跳过 \(stats.missed)"
  }
}
