import Foundation
import SwiftData

enum LocalAccountResetError: LocalizedError {
  case settingsUnavailable
  var errorDescription: String? {
    "本机设置被锁定、不可读或未能恢复默认；本机清理未完成。"
  }
}

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
    guard settings.canRestoreDefaults else { throw LocalAccountResetError.settingsUnavailable }
    try (removeBackground ?? { try settings.removeLocalBackground() })()
    try (removePracticeFont ?? { try settings.removeLocalPracticeFont() })()

    let personalBestCheckpoint = try LocalPersonalBestStore.checkpoint(in: modelContext)
    do {
      // Batch deletion can commit before the final save on the current SDK.
      // Stage tracked deletions so history and the PB reset share one commit.
      for row in try modelContext.fetch(FetchDescriptor<TestResultRecord>()) {
        modelContext.delete(row)
      }
      for row in try modelContext.fetch(FetchDescriptor<TestPresetRecord>()) {
        modelContext.delete(row)
      }
      for row in try modelContext.fetch(FetchDescriptor<SavedCustomTextRecord>()) {
        modelContext.delete(row)
      }
      for row in try modelContext.fetch(FetchDescriptor<ResultFilterPresetRecord>()) {
        modelContext.delete(row)
      }
      let empty = try LocalPersonalBestLedgerRecord(ledger: .init())
      if let existing = personalBestCheckpoint.record {
        existing.ledgerData = empty.ledgerData
      } else {
        modelContext.insert(empty)
      }
      try (save ?? { try modelContext.save() })()
    } catch {
      LocalPersonalBestStore.restore(personalBestCheckpoint, in: modelContext)
      throw error
    }

    resultTombstoneStore.removeAll()
    presetTombstoneStore.removeAll()
    savedTextTombstoneStore.removeAll()
    tombstoneStore.removeAll()
    (clearPendingPublications ?? { PendingResultPublicationStore().removeAll() })()
    guard settings.restoreDefaults(customizationTombstoneStore: customizationTombstoneStore) else {
      throw LocalAccountResetError.settingsUnavailable
    }
    customizationTombstoneStore.removeAll()
  }
}
