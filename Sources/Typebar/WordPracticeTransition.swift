import Foundation

/// Value-owned temporary navigation, separate from the user's saved selection.
struct WordPracticeTransition {
  enum PersistenceCause { case automatic, configurationSave }
  let returnPreset: SavedTestPreset
  let returnSelection: ActiveTestSelectionDocument
  let returnCustomTextState: CustomTextStateDocument?
  let preparedPractice: WordPracticeText.SectionedPractice
  private(set) var lastPersistedSelection: ActiveTestSelectionDocument?

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
      preparedPractice: practice,
      lastPersistedSelection: previous?.lastPersistedSelection)
  }

  func preparedSections(matching text: String) -> [String]? {
    guard InputTextIdentity.matches(preparedPractice.text, text) else { return nil }
    return preparedPractice.sections
  }

  func persistedSelection(current: ActiveTestSelectionDocument,
    cause: PersistenceCause = .automatic) -> ActiveTestSelectionDocument {
    switch cause {
    case .automatic: lastPersistedSelection ?? returnSelection
    case .configurationSave: current
    }
  }

  @discardableResult
  mutating func persistSelection(current: ActiveTestSelectionDocument, cause: PersistenceCause,
    save: (ActiveTestSelectionDocument) -> Bool) -> Bool {
    let selected = persistedSelection(current: current, cause: cause)
    guard save(selected) else { return false }
    lastPersistedSelection = selected
    return true
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
