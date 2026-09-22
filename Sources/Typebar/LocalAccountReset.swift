import SwiftData

@MainActor
enum LocalAccountReset {
  static func eraseCurrentMacData(
    modelContext: ModelContext,
    settings: AppSettings,
    resultTombstoneStore: ResultTombstoneStore = .init(),
    presetTombstoneStore: PresetTombstoneStore = .init(),
    savedTextTombstoneStore: SavedTextTombstoneStore = .init(),
    customizationTombstoneStore: CustomizationTombstoneStore = .init(),
    tombstoneStore: ResultFilterPresetTombstoneStore = .init(),
    removeBackground: (() throws -> Void)? = nil,
    removePracticeFont: (() throws -> Void)? = nil,
    clearPendingPublications: (() -> Void)? = nil
  ) throws {
    try (removeBackground ?? { try settings.removeLocalBackground() })()
    try (removePracticeFont ?? { try settings.removeLocalPracticeFont() })()

    try modelContext.delete(model: TestResultRecord.self)
    try modelContext.delete(model: TestPresetRecord.self)
    try modelContext.delete(model: SavedCustomTextRecord.self)
    try modelContext.delete(model: ResultFilterPresetRecord.self)
    try modelContext.save()

    resultTombstoneStore.removeAll()
    presetTombstoneStore.removeAll()
    savedTextTombstoneStore.removeAll()
    tombstoneStore.removeAll()
    (clearPendingPublications ?? { PendingResultPublicationStore().removeAll() })()
    settings.restoreDefaults(customizationTombstoneStore: customizationTombstoneStore)
    customizationTombstoneStore.removeAll()
  }
}
