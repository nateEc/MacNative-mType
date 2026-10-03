import Foundation

/// Resolve the primary language before building a fresh Polyglot word pool.
/// This is not decoding or replay: historical configurations stay unchanged.
struct PolyglotGenerationPreparation {
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
    let conflicts = primary.usesRightToLeftPrompt
      ? selected.allSatisfy { !$0.usesRightToLeftPrompt }
      : selected.allSatisfy(\.usesRightToLeftPrompt)
    // TestConfiguration has already normalized this to at least two languages.
    let resolved = conflicts ? selected[0] : primary
    var prepared = requested.with(polyglotBaseLanguage: resolved)
    prepared.polyglotUsesPrimaryDirection = true
    configuration = prepared
    switchedPrimaryLanguage = conflicts ? resolved : nil
  }

  var notice: String? {
    switchedPrimaryLanguage.map { "语言方向冲突：生成主语言已切换为 \($0.displayName)，保留多语组合。" }
  }
}
