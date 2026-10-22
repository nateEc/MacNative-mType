import Foundation

@MainActor
enum ArchiveSourceAdmission {
  struct Plan {
    let snapshot: AppSettingsSnapshot
    let selection: ActiveTestSelectionDocument?
    let baseline: PresetSourcePreparation.Baseline?
    let selectionBaseline: ActiveTestSelectionRead?

    @MainActor private func isCurrent(_ settings: AppSettings) -> Bool {
      guard settings.allowsRestartingConfigurationChange else { return false }
      if let baseline {
        guard baseline.matches(settings) else { return false }
      } else if settings.hasThresholdProfile { return false }
      if let selectionBaseline, settings.activeTestSelectionRead != selectionBaseline { return false }
      return true
    }

    @MainActor func validateBeforeRecords(to settings: AppSettings) throws {
      guard settings.allowsRestartingConfigurationChange else { throw LocalArchiveImportError.noQuitConfigurationLocked }
      guard isCurrent(settings) else { throw LocalArchiveImportError.sourceStateUnavailable }
    }

    /// Called only after records and deletion markers have committed. Errors
    /// describe that partial result; they are not a cross-store rollback.
    @MainActor func applyAfterRecords(to settings: AppSettings) throws -> Bool {
      guard isCurrent(settings), settings.apply(snapshot) else {
        throw LocalArchiveImportError.recordsImportedSettingsNotApplied
      }
      if baseline != nil {
        guard settings.snapshot == snapshot,
          case .available(let stored) = settings.thresholdProfileRead, stored == snapshot else {
          throw LocalArchiveImportError.recordsImportedSettingsNotApplied
        }
      } else if settings.hasThresholdProfile {
        throw LocalArchiveImportError.recordsImportedSettingsNotApplied
      }
      guard let selection, selection != settings.activeTestSelection else { return false }
      guard settings.allowsRestartingConfigurationChange,
        settings.importActiveTestSelection(selection) else {
        throw LocalArchiveImportError.recordsAndSettingsImportedSelectionNotApplied
      }
      return true
    }
  }

  static func preparing(_ incoming: AppSettingsSnapshot, selection: ActiveTestSelectionDocument?,
    to settings: AppSettings) throws -> Plan {
    guard settings.allowsRestartingConfigurationChange else { throw LocalArchiveImportError.noQuitConfigurationLocked }
    let sourceSelection = selection.map { PracticeThresholdSource.isPresent(in: $0.preset) } ?? false
    let hasSource = settings.hasThresholdProfile
    guard hasSource || (incoming.thresholdSource == nil && !sourceSelection) else {
      throw LocalArchiveImportError.thresholdSourceNotReady
    }
    var snapshot = incoming
    let baseline: PresetSourcePreparation.Baseline?
    if hasSource {
      let current = settings.snapshot
      guard let owner = current.thresholdSource,
        case .available(let stored) = settings.thresholdProfileRead, stored.thresholdSource == owner,
        settings.activeTestSelectionRead != .unavailable
      else { throw LocalArchiveImportError.sourceStateUnavailable }
      baseline = .init(current: current, persisted: stored)
      if incoming.thresholdSource == nil {
        var rules = InputRules()
        rules.minimumAccuracy = incoming.minimumAccuracy
        rules.minimumWpm = incoming.minimumWpm
        rules.minimumWordBurstWpm = incoming.minimumWordBurstWpm
        rules.minimumWordBurstMode = incoming.minimumWordBurstMode
        guard let source = try? LegacyThresholdProjection.source(for: rules, preserving: owner) else {
          throw LocalArchiveImportError.invalidSourceSettings
        }
        snapshot = source.applying(to: incoming)
      }
      guard settings.canApplySourceSnapshot(snapshot) else { throw LocalArchiveImportError.invalidSourceSettings }
    } else { baseline = nil }
    let preparedSelection: ActiveTestSelectionDocument?
    if let selection {
      guard let validated = ActiveTestSelectionPolicy.validated(selection),
        settings.activeTestSelectionRead != .unavailable,
        !hasSource || validated.preset.configuration.challengeID == nil
      else { throw LocalArchiveImportError.invalidActiveTestSelection }
      if hasSource, validated.preset.configuration.rules.thresholdSource == nil,
        let source = snapshot.thresholdSource {
        var preset = validated.preset
        // Source restoration uses the imported global owner, not stale rule
        // values captured in an older legacy active selection.
        preset.configuration.rules = source.applying(to: preset.configuration.rules)
        let promoted = ActiveTestSelectionDocument(preset: preset, quoteSource: validated.quoteSource,
          testParameterMemory: validated.testParameterMemory,
          polyglotReturnLanguage: validated.polyglotReturnLanguage,
          oneHandedChallengeSelection: validated.oneHandedChallengeSelection)
        guard let checked = ActiveTestSelectionPolicy.validated(promoted) else {
          throw LocalArchiveImportError.invalidActiveTestSelection
        }
        preparedSelection = checked
      } else { preparedSelection = validated }
    } else { preparedSelection = nil }
    return .init(snapshot: snapshot, selection: preparedSelection, baseline: baseline,
      selectionBaseline: hasSource || selection != nil ? settings.activeTestSelectionRead : nil)
  }
}
