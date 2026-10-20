import Foundation

/// Value-owned temporary navigation, separate from the user's saved selection.
struct WordPracticeTransition {
  let returnPreset: SavedTestPreset
  let returnSelection: ActiveTestSelectionDocument
  let returnCustomTextState: CustomTextStateDocument?
  let preparedPractice: WordPracticeText.SectionedPractice

  static func begin(
    previous: Self?,
    practice: WordPracticeText.SectionedPractice,
    currentPreset: () -> SavedTestPreset,
    currentSelection: (SavedTestPreset) -> ActiveTestSelectionDocument,
    currentCustomTextState: () -> CustomTextStateDocument? = { nil },
    selectCustomMode: () -> Bool
  ) -> Self? {
    let source = previous?.returnPreset ?? currentPreset()
    let selection = previous?.returnSelection ?? currentSelection(source)
    // Mode navigation keeps its first source, but the reference captures
    // custom content from the immediately preceding run on every entry.
    let customState = currentCustomTextState()
    guard selectCustomMode() else { return nil }
    return .init(returnPreset: source,
      returnSelection: selection,
      returnCustomTextState: customState,
      preparedPractice: practice)
  }

  func preparedSections(matching text: String) -> [String]? {
    guard InputTextIdentity.matches(preparedPractice.text, text) else { return nil }
    return preparedPractice.sections
  }

  func persistedSelection(current: ActiveTestSelectionDocument) -> ActiveTestSelectionDocument {
    returnSelection
  }

  func returningPreset(current: SavedTestPreset, parameterMemory: TypebarTestParameterMemory,
    quoteID: String? = nil) -> SavedTestPreset {
    // The source records mode/content switches, not an old global snapshot.
    var returned = current
    returned.configuration.mode = returnPreset.configuration.mode
    returned.configuration.contentOptions = returnPreset.configuration.contentOptions
    switch returned.configuration.mode {
    case .time:
      returned.configuration.duration = TimeInterval(parameterMemory.duration)
      returned.configuration.wordLimit = nil
    case .words:
      returned.configuration.duration = nil
      returned.configuration.wordLimit = parameterMemory.wordLimit
    case .quote, .zen:
      returned.configuration.duration = nil
      returned.configuration.wordLimit = nil
    case .custom:
      break // The independently retained custom source owns its limits.
    }
    returned.quoteID = returned.configuration.mode == .quote ? (quoteID ?? returnPreset.quoteID) : nil
    returned.customText = returned.configuration.mode == .custom
      ? (returnCustomTextState?.source.text ?? returnPreset.customText ?? current.customText) : nil
    returned.settingGroups = nil
    return returned
  }
}
