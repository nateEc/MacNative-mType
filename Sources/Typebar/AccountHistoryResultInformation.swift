import Foundation

/// Read-only presentation of the accepted row, never the active test settings.
struct AccountHistoryResultInformation: Equatable {
  let characterCounts: String
  let characterCountsDescription: String
  let scoringUnitBasis: String
  let difficulty: String
  let punctuation: String
  let numbers: String
  let blindMode: String
  let lazyMode: String
  let modifiers: String

  init(_ result: RemoteAccountResult) {
    if let evidence = result.experienceEvidence {
      characterCounts = evidence.characterCounts.map(String.init).joined(separator: "/")
      characterCountsDescription = zip(["正确词信用", "错误", "额外", "遗漏"], evidence.characterCounts)
        .map { "\($0) \($1)" }.joined(separator: "，")
      scoringUnitBasis = evidence.scoringUnitBasis == .utf16 ? "UTF-16 单位" : "韩语拆音单位"
    } else {
      characterCounts = "未知"; characterCountsDescription = "字符计数未知"
      scoringUnitBasis = "未知"
    }
    let options = result.personalBestConfiguration
    difficulty = options.flatMap { Difficulty(rawValue: $0.difficulty) }?.displayName ?? "未知"
    punctuation = Self.flag(options?.punctuation ?? result.experienceEvidence?.punctuation)
    numbers = Self.flag(options?.numbers ?? result.experienceEvidence?.numbers)
    blindMode = Self.flag(result.blindMode)
    lazyMode = Self.flag(options?.lazyMode)
    if let controls = result.rankingEvidence?.modifiers ?? result.experienceEvidence?.modifiers {
      modifiers = controls.isEmpty ? "无修饰器" : controls.map {
        $0 == "polyglot" ? "Polyglot 多语混排" : TestModifier(rawValue: $0)?.displayName ?? $0
      }.joined(separator: "、")
    } else { modifiers = "未知" }
  }

  private static func flag(_ value: Bool?) -> String {
    value.map { $0 ? "开启" : "关闭" } ?? "未知"
  }
}
