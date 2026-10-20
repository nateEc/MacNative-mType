import SwiftUI

/// Bindings shared by the settings page and its isolated behavior tests.
@MainActor
struct PracticeThresholdPreferences {
  let settings: AppSettings
  var acceptsChange: () -> Bool = { true }
  var onResult: (Bool) -> Void = { _ in }

  var accuracyEnabled: Binding<Bool> {
    Binding(
      get: {
        settings.thresholdConfiguration.map { $0.minimumAccuracyMode == .custom }
          ?? (settings.minimumAccuracy > 0)
      },
      set: { enabled in
        mutate(.minimumAccuracy(mode: enabled ? .custom : .off, customValue: nil)) {
          settings.minimumAccuracy = enabled ? max(95, settings.minimumAccuracy) : 0
        }
      })
  }

  var wpmEnabled: Binding<Bool> {
    Binding(
      get: {
        settings.thresholdConfiguration.map { $0.minimumWpmMode == .custom }
          ?? (settings.minimumWpm > 0)
      },
      set: { enabled in
        mutate(.minimumWpm(mode: enabled ? .custom : .off, customValue: nil)) {
          settings.minimumWpm = enabled ? max(60, settings.minimumWpm) : 0
        }
      })
  }

  var accuracy: Binding<Double> {
    Binding(
      get: {
        settings.thresholdConfiguration?.minimumAccuracyCustomValue ?? settings.minimumAccuracy
      },
      set: { value in
        mutate(.minimumAccuracy(mode: nil, customValue: value)) { settings.minimumAccuracy = value }
      })
  }

  var wpm: Binding<Double> {
    Binding(
      get: {
        settings.thresholdConfiguration?.minimumWpmCustomValue ?? settings.minimumWpm
      },
      set: { value in
        mutate(.minimumWpm(mode: nil, customValue: value)) { settings.minimumWpm = value }
      })
  }

  var burstMode: Binding<MinimumWordBurstMode> {
    Binding(
      get: {
        settings.thresholdConfiguration?.minimumWordBurstMode ?? settings.minimumWordBurstMode
      },
      set: { mode in
        mutate(.minimumWordBurst(mode: mode, customValue: nil)) {
          settings.minimumWordBurstMode = mode
        }
      })
  }

  var burst: Binding<Double> {
    Binding(
      get: {
        settings.thresholdConfiguration?.minimumWordBurstCustomValue ?? settings.minimumWordBurstWpm
      },
      set: { value in
        mutate(.minimumWordBurst(mode: nil, customValue: value)) {
          settings.minimumWordBurstWpm = value
        }
      })
  }

  private func mutate(_ change: PracticeThresholdConfiguration.Change, legacy: () -> Void) {
    guard acceptsChange() else { return }
    guard settings.allowsRestartingConfigurationChange else {
      onResult(false)
      return
    }
    // Validate even for legacy bindings; do not report normalization of invalid input as success.
    var validation = PracticeThresholdConfiguration()
    guard (try? validation.apply(change)) != nil else {
      onResult(false)
      return
    }
    if settings.hasThresholdProfile {
      onResult(settings.updateThresholdConfiguration(change))
    } else {
      legacy()
      onResult(true)
    }
  }
}
