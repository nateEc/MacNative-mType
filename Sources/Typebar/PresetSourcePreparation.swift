import Foundation

/// Creates an application value, never a replacement for the stored preset.
@MainActor
enum PresetSourcePreparation {
  struct Baseline {
    let current: AppSettingsSnapshot
    let persisted: AppSettingsSnapshot

    @MainActor func matches(_ settings: AppSettings) -> Bool {
      guard settings.snapshot == current,
        case .available(let stored) = settings.thresholdProfileRead,
        stored == persisted else { return false }
      return true
    }
  }

  struct Prepared {
    let preset: SavedTestPreset
    let baseline: Baseline?
  }

  static func preparing(_ original: SavedTestPreset, to settings: AppSettings,
    appliesGlobalSettings: Bool) -> Prepared? {
    guard settings.allowsRestartingConfigurationChange, original.settingGroups?.isEmpty != true
    else { return nil }
    let incomingSource = PracticeThresholdSource.isPresent(in: original)
    guard settings.hasThresholdProfile || incomingSource else {
      return .init(preset: original, baseline: nil)
    }
    let current = settings.snapshot
    guard let owner = current.thresholdSource,
      case .available(let stored) = settings.thresholdProfileRead, stored.thresholdSource == owner,
      settings.activeTestSelectionRead != .unavailable,
      original.configuration.challengeID == nil,
      (try? LocalPresetCodec.encode(original)) != nil
    else { return nil }
    if !appliesGlobalSettings {
      guard !original.isPartial else { return nil }
      return .init(preset: original, baseline: nil)
    }
    var prepared = original
    let ownsThresholds = !original.isPartial || original.settingGroups?.contains(.behavior) == true
    if !incomingSource, ownsThresholds {
      guard let source = try? LegacyThresholdProjection.source(
        for: original.configuration.rules, preserving: owner) else { return nil }
      if let snapshot = original.settingsSnapshot {
        guard source.matches(snapshot) else { return nil }
        prepared.settingsSnapshot = source.applying(to: snapshot)
      }
      prepared.configuration.rules = source.applying(to: original.configuration.rules)
    }
    if !prepared.isPartial, !PresetSettingsApplication.agreesWithSnapshot(prepared) { return nil }
    return .init(preset: prepared, baseline: .init(current: current, persisted: stored))
  }
}
