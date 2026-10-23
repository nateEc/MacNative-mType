import SwiftUI

@MainActor
struct PracticeFunboxPreferences {
  let settings: AppSettings
  var acceptsChange: () -> Bool = { true }
  var onResult: (Bool) -> Void = { _ in }

  func selection(for modifier: TestModifier) -> Binding<Bool> {
    Binding(get: { settings.preferenceTestModifiers.contains(modifier) }, set: { enabled in
      guard enabled != settings.preferenceTestModifiers.contains(modifier), acceptsChange() else { return }
      let accepted = settings.toggleTestModifier(modifier)
      if accepted { settings.preferenceConfigurationSaves.deliver() }
      onResult(accepted)
    })
  }
}
