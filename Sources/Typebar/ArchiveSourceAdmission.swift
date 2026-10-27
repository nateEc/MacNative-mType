import AppKit
import Foundation

@MainActor
enum ArchiveSourceAdmission {
  struct Plan {
    let snapshot: AppSettingsSnapshot
    let selection: ActiveTestSelectionDocument?
    let baseline: PresetSourcePreparation.Baseline?
    let adoptionBaseline: AppSettings.ArchiveSourceAdoptionBaseline?
    let selectionBaseline: ActiveTestSelectionRead?
    let preservesUnchangedSettings: Bool
    let selectionResourcesAvailable: @MainActor (TestConfiguration) -> Bool

    private var hasSourceChallenge: Bool {
      (baseline != nil || adoptionBaseline != nil) && selection?.preset.configuration.challengeID != nil
    }

    @MainActor private func hasAppliedSnapshot(_ settings: AppSettings) -> Bool {
      if baseline != nil || adoptionBaseline != nil {
        guard settings.snapshot == snapshot,
          case .available(let stored) = settings.thresholdProfileRead, stored == snapshot else { return false }
        return true
      }
      return !settings.hasThresholdProfile
    }

    @MainActor private func isCurrent(_ settings: AppSettings) -> Bool {
      guard settings.allowsRestartingConfigurationChange else { return false }
      if let baseline {
        guard baseline.matches(settings) else { return false }
      } else if let adoptionBaseline {
        guard settings.archiveSourceAdoptionBaseline == adoptionBaseline else { return false }
      } else if settings.hasThresholdProfile { return false }
      if let selectionBaseline, settings.activeTestSelectionRead != selectionBaseline { return false }
      return true
    }

    @MainActor func validateBeforeRecords(to settings: AppSettings) throws {
      guard settings.allowsRestartingConfigurationChange else { throw LocalArchiveImportError.noQuitConfigurationLocked }
      guard isCurrent(settings) else { throw LocalArchiveImportError.sourceStateUnavailable }
      if hasSourceChallenge, let selection {
        let available = selectionResourcesAvailable(selection.preset.configuration)
        guard settings.allowsRestartingConfigurationChange else { throw LocalArchiveImportError.noQuitConfigurationLocked }
        guard isCurrent(settings) else { throw LocalArchiveImportError.sourceStateUnavailable }
        guard available else { throw LocalArchiveImportError.activeTestSelectionResourcesUnavailable }
      }
    }

    /// Called only after records and deletion markers have committed. Errors
    /// describe that partial result; they are not a cross-store rollback.
    @MainActor func applyAfterRecords(to settings: AppSettings) throws -> Bool {
      guard isCurrent(settings) else {
        throw LocalArchiveImportError.recordsImportedSettingsNotApplied
      }
      let appliesSettings = !(preservesUnchangedSettings && settings.snapshot == snapshot)
      if appliesSettings {
        let applied = adoptionBaseline.map { settings.adoptArchivedSourceSnapshot(snapshot, expected: $0) }
          ?? settings.apply(snapshot)
        guard applied else { throw LocalArchiveImportError.recordsImportedSettingsNotApplied }
      }
      guard hasAppliedSnapshot(settings) else {
        throw LocalArchiveImportError.recordsImportedSettingsNotApplied
      }
      guard let selection else { return false }
      if let selectionBaseline, settings.activeTestSelectionRead != selectionBaseline {
        throw LocalArchiveImportError.recordsAndSettingsImportedSelectionNotApplied
      }
      if hasSourceChallenge {
        let available = selectionResourcesAvailable(selection.preset.configuration)
        guard hasAppliedSnapshot(settings) else { throw LocalArchiveImportError.recordsImportedSettingsNotApplied }
        guard available, settings.activeTestSelectionRead == selectionBaseline else {
          throw LocalArchiveImportError.recordsAndSettingsImportedSelectionNotApplied
        }
      }
      if selection == settings.activeTestSelection {
        guard hasSourceChallenge, appliesSettings else { return false }
        guard settings.reapplyActiveTestSelection(selection) else {
          throw LocalArchiveImportError.recordsAndSettingsImportedSelectionNotApplied
        }
        return true
      }
      guard settings.allowsRestartingConfigurationChange,
        settings.importActiveTestSelection(selection) else {
        throw LocalArchiveImportError.recordsAndSettingsImportedSelectionNotApplied
      }
      return true
    }
  }

  static func resourcesAvailable(for configuration: TestConfiguration) -> Bool {
    PresetResourceAdmission.refusal(for: configuration,
      wingdingsAvailable: { WingdingsChallengeFont.resolve(size: 12) != nil },
      // Archive bytes cannot prove a user-selected ephemeral script file.
      scriptIsVerified: { _ in false }) == nil
  }

  static func preparing(_ incoming: AppSettingsSnapshot, selection: ActiveTestSelectionDocument?,
    to settings: AppSettings,
    importSource: ArchiveImportSource = .localFile,
    selectionResourcesAvailable: @escaping @MainActor (TestConfiguration) -> Bool = resourcesAvailable) throws -> Plan {
    guard settings.allowsRestartingConfigurationChange else { throw LocalArchiveImportError.noQuitConfigurationLocked }
    let sourceSelection = selection.map { PracticeThresholdSource.isPresent(in: $0.preset) } ?? false
    let hasSource = settings.hasThresholdProfile
    let adoptsSource = !hasSource && incoming.thresholdSource != nil
    guard hasSource || adoptsSource || !sourceSelection else {
      throw LocalArchiveImportError.thresholdSourceNotReady
    }
    var snapshot = incoming
    let baseline: PresetSourcePreparation.Baseline?
    let adoptionBaseline: AppSettings.ArchiveSourceAdoptionBaseline?
    if hasSource {
      adoptionBaseline = nil
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
    } else if adoptsSource {
      baseline = nil
      guard let current = settings.archiveSourceAdoptionBaseline else {
        throw LocalArchiveImportError.sourceStateUnavailable
      }
      guard settings.canAdoptArchivedSourceSnapshot(snapshot) else { throw LocalArchiveImportError.invalidSourceSettings }
      adoptionBaseline = current
    } else { baseline = nil; adoptionBaseline = nil }
    let preparedSelection: ActiveTestSelectionDocument?
    if let selection {
      guard let validated = ActiveTestSelectionPolicy.validated(selection),
        settings.activeTestSelectionRead != .unavailable
      else { throw LocalArchiveImportError.invalidActiveTestSelection }
      if hasSource || adoptsSource, validated.preset.configuration.challengeID != nil,
        !SourceChallengeAdmission.accepts(validated.preset) {
        throw LocalArchiveImportError.invalidActiveTestSelection
      }
      if hasSource || adoptsSource, validated.preset.configuration.rules.thresholdSource == nil,
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
    let preservesUnchangedSettings: Bool
    switch importSource {
    case .localFile: preservesUnchangedSettings = false
    case .cloudSync: preservesUnchangedSettings = true
    }
    let plan = Plan(snapshot: snapshot, selection: preparedSelection, baseline: baseline, adoptionBaseline: adoptionBaseline,
      selectionBaseline: hasSource || adoptsSource || selection != nil ? settings.activeTestSelectionRead : nil,
      preservesUnchangedSettings: preservesUnchangedSettings,
      selectionResourcesAvailable: selectionResourcesAvailable)
    try plan.validateBeforeRecords(to: settings)
    return plan
  }
}
