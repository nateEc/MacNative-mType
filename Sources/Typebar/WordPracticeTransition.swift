import Foundation

/// Value-owned temporary navigation, separate from the user's saved selection.
struct WordPracticeTransition {
  let returnPreset: SavedTestPreset
  let returnSelection: ActiveTestSelectionDocument
  let preparedPractice: WordPracticeText.SectionedPractice

  static func begin(
    previous: Self?,
    practice: WordPracticeText.SectionedPractice,
    currentPreset: () -> SavedTestPreset,
    currentSelection: (SavedTestPreset) -> ActiveTestSelectionDocument,
    selectCustomMode: () -> Bool
  ) -> Self? {
    let source = previous?.returnPreset ?? currentPreset()
    let selection = previous?.returnSelection ?? currentSelection(source)
    guard selectCustomMode() else { return nil }
    return .init(returnPreset: source,
      returnSelection: selection,
      preparedPractice: practice)
  }

  func preparedSections(matching text: String) -> [String]? {
    guard InputTextIdentity.matches(preparedPractice.text, text) else { return nil }
    return preparedPractice.sections
  }

  func persistedSelection(current: ActiveTestSelectionDocument) -> ActiveTestSelectionDocument {
    returnSelection
  }
}
