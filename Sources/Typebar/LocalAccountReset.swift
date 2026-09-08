import SwiftData

@MainActor
enum LocalAccountReset {
  static func eraseCurrentMacData(
    modelContext: ModelContext,
    settings: AppSettings,
    removeBackground: (() throws -> Void)? = nil,
    removePracticeFont: (() throws -> Void)? = nil
  ) throws {
    try (removeBackground ?? { try settings.removeLocalBackground() })()
    try (removePracticeFont ?? { try settings.removeLocalPracticeFont() })()

    try modelContext.delete(model: TestResultRecord.self)
    try modelContext.delete(model: TestPresetRecord.self)
    try modelContext.delete(model: SavedCustomTextRecord.self)
    try modelContext.delete(model: ResultFilterPresetRecord.self)
    try modelContext.save()

    settings.restoreDefaults()
  }
}
