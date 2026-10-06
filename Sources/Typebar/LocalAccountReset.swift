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
    clearPendingPublications: (() -> Void)? = nil,
    save: (() throws -> Void)? = nil
  ) throws {
    try (removeBackground ?? { try settings.removeLocalBackground() })()
    try (removePracticeFont ?? { try settings.removeLocalPracticeFont() })()

    let personalBestCheckpoint = try LocalPersonalBestStore.checkpoint(in: modelContext)
    do {
      // Batch deletion can commit before the final save on the current SDK.
      // Stage tracked deletions so history and the PB reset share one commit.
      for row in try modelContext.fetch(FetchDescriptor<TestResultRecord>()) { modelContext.delete(row) }
      for row in try modelContext.fetch(FetchDescriptor<TestPresetRecord>()) { modelContext.delete(row) }
      for row in try modelContext.fetch(FetchDescriptor<SavedCustomTextRecord>()) { modelContext.delete(row) }
      for row in try modelContext.fetch(FetchDescriptor<ResultFilterPresetRecord>()) { modelContext.delete(row) }
      let empty = try LocalPersonalBestLedgerRecord(ledger: .init())
      if let existing = personalBestCheckpoint.record { existing.ledgerData = empty.ledgerData }
      else { modelContext.insert(empty) }
      try (save ?? { try modelContext.save() })()
    } catch { LocalPersonalBestStore.restore(personalBestCheckpoint, in: modelContext); throw error }

    resultTombstoneStore.removeAll()
    presetTombstoneStore.removeAll()
    savedTextTombstoneStore.removeAll()
    tombstoneStore.removeAll()
    (clearPendingPublications ?? { PendingResultPublicationStore().removeAll() })()
    settings.restoreDefaults(customizationTombstoneStore: customizationTombstoneStore)
    customizationTombstoneStore.removeAll()
  }
}
