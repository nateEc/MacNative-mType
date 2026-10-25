import Foundation

/// Resolve the primary language before building a fresh Polyglot word pool.
/// This is not decoding or replay: historical configurations stay unchanged.
struct PolyglotGenerationPreparation {
  static func directionFallback(primary: TypingLanguage, selected: [TypingLanguage]) -> TypingLanguage? {
    guard selected.count >= 2 else { return nil }
    let conflicts = primary.usesRightToLeftPrompt
      ? selected.allSatisfy { !$0.usesRightToLeftPrompt } : selected.allSatisfy(\.usesRightToLeftPrompt)
    return conflicts ? selected.first : nil
  }
  let configuration: TestConfiguration
  let switchedPrimaryLanguage: TypingLanguage?

  init(_ requested: TestConfiguration) {
    guard requested.language == .mixedLanguages else {
      configuration = requested
      switchedPrimaryLanguage = nil
      return
    }
    let primary = requested.wordPoolBaseLanguage
    let selected = requested.mixedLanguageComponents
    let fallback = Self.directionFallback(primary: primary, selected: selected)
    let resolved = fallback ?? primary
    var prepared = requested.with(polyglotBaseLanguage: resolved)
    prepared.polyglotUsesPrimaryDirection = true
    prepared.polyglotUsesPrimaryCodeInput = true
    prepared.polyglotUsesPrimaryInputNormalization = true
    configuration = prepared
    switchedPrimaryLanguage = fallback
  }

  var notice: String? {
    switchedPrimaryLanguage.map { "语言方向冲突：生成主语言已切换为 \($0.displayName)，保留多语组合。" }
  }
}
