import Foundation

enum ChallengeSetupSelectionPolicy {
  struct Selection: Equatable {
    var language: TypingLanguage
    var englishVariant: EnglishVariant
    var mixedLanguageComponents: [TypingLanguage]
    var contentOptions: ContentOptions
    var polyglotReturnLanguage: TypingLanguage?

    init(language: TypingLanguage, englishVariant: EnglishVariant,
      mixedLanguageComponents: [TypingLanguage], contentOptions: ContentOptions,
      polyglotReturnLanguage: TypingLanguage? = nil) {
      self.language = language
      self.englishVariant = englishVariant
      self.mixedLanguageComponents = mixedLanguageComponents
      self.contentOptions = contentOptions
      self.polyglotReturnLanguage = polyglotReturnLanguage
    }

    init(configuration: TestConfiguration) {
      self.init(language: configuration.language, englishVariant: configuration.englishVariant,
        mixedLanguageComponents: configuration.mixedLanguageComponents, contentOptions: configuration.contentOptions,
        polyglotReturnLanguage: configuration.polyglotBaseLanguage)
    }
  }

  /// Library templates intentionally omit the active identity. Stamp it before
  /// projecting, so model admission and later result verification see the same challenge.
  static func applying(_ selection: Selection, for challenge: TypebarChallenge,
    template: TestConfiguration? = nil, clearingPolyglot: Bool = false) -> TestConfiguration {
    applying(selection, to: (template ?? challenge.preset.configuration).with(challengeID: challenge.id),
      clearingPolyglot: clearingPolyglot)
  }

  static func applying(_ selection: Selection, to template: TestConfiguration,
    clearingPolyglot: Bool = false) -> TestConfiguration {
    guard TypebarChallengeLibrary.challenge(id: template.challengeID) != nil else { return template }
    var configuration = template
    // English Master is the only pinned setup that owns language and both
    // content toggles. Spelling and mixed-language memory remain unowned.
    if template.challengeID != "english-ten-thousand-hour" {
      configuration.language = selection.language
      if clearingPolyglot, selection.language == .mixedLanguages,
        let base = PolyglotReturnLanguagePolicy.validated(selection.polyglotReturnLanguage) {
        configuration.language = base
      }
      configuration.contentOptions = selection.contentOptions
    }
    configuration.englishVariant = selection.englishVariant
    configuration.mixedLanguageComponents = TypingLanguage.normalizedMixedComponents(
      selection.mixedLanguageComponents)
    configuration = configuration.with(polyglotBaseLanguage: selection.polyglotReturnLanguage)
    return configuration.with(modifiers: configuration.modifiers)
  }
}
