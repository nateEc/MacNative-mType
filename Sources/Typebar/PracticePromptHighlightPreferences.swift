import SwiftUI

@MainActor
struct PracticePromptHighlightPreferences {
  let settings: AppSettings
  var onResult: (Bool) -> Void = { _ in }

  var selection: Binding<PromptHighlightMode> {
    Binding(get: { settings.promptHighlightMode }, set: { mode in
      let accepted = settings.applyPromptHighlightMode(mode)
      if accepted { settings.preferenceConfigurationSaves.deliver() }
      onResult(accepted)
    })
  }
}
