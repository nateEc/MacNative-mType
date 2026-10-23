import SwiftUI

/// Explicit visual-keyboard confirmations share the command application path.
@MainActor
struct PracticeKeyboardGuidePreferences {
  let settings: AppSettings

  var mode: Binding<KeyboardGuideMode> {
    Binding(get: { settings.preferenceKeyboardGuideMode }, set: {
      KeyboardGuideCommandTarget.mode($0).apply(to: settings, onConfigurationSave: save)
    })
  }

  var scale: Binding<Double> {
    Binding(get: { settings.keyboardGuideScale }, set: {
      _ = KeyboardGuideScalePolicy.apply($0, to: settings, onConfigurationSave: save)
    })
  }

  var style: Binding<KeyboardGuideStyle> {
    Binding(get: { settings.keyboardGuideStyle }, set: {
      KeyboardGuideCommandTarget.style($0).apply(to: settings, onConfigurationSave: save)
    })
  }

  var legend: Binding<KeyboardGuideLegendStyle> {
    Binding(get: { settings.keyboardGuideLegendStyle }, set: {
      KeyboardGuideCommandTarget.legend($0).apply(to: settings, onConfigurationSave: save)
    })
  }

  var keys: Binding<KeyboardGuideKeysMode> {
    Binding(get: { settings.keyboardGuideKeysMode }, set: {
      KeyboardGuideCommandTarget.keys($0).apply(to: settings, onConfigurationSave: save)
    })
  }

  var layout: Binding<KeyboardLayout> {
    Binding(get: { settings.keyboardLayout }, set: {
      KeyboardGuideLayoutCommandTarget.builtIn($0).apply(to: settings, onConfigurationSave: save)
    })
  }

  var layoutSource: Binding<KeyboardGuideLayoutSource> {
    Binding(get: { settings.keyboardGuideLayoutSource }, set: {
      KeyboardGuidePreferenceApplication.enableForAppearanceChange(settings)
      settings.keyboardGuideLayoutSource = $0
      save()
    })
  }

  private func save() { settings.preferenceConfigurationSaves.deliver() }
}
