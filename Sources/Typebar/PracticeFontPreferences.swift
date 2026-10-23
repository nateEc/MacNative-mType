import SwiftUI

@MainActor
struct PracticeFontPreferences {
  let settings: AppSettings
  var onResult: (Bool) -> Void = { _ in }

  var familyName: String { settings.preferenceFontFamilyName }

  var design: Binding<PracticeFont> {
    Binding(get: { settings.practiceFont }, set: {
      onResult(FontFamilyCommandApplication.apply(.systemDesign($0), to: settings, onConfigurationSave: save))
    })
  }

  var size: Binding<Double> {
    Binding(get: { settings.fontSize }, set: { value in
      guard value.isFinite, value >= PracticeFontSizePolicy.minimumSize else { onResult(false); return }
      settings.fontSize = value
      save()
      onResult(true)
    })
  }

  var installedSelection: Binding<String> {
    Binding(get: { familyName }, set: {
      onResult(FontFamilyCommandApplication.apply(.installedName($0), to: settings, onConfigurationSave: save))
    })
  }

  @discardableResult
  func applyName(_ raw: String) -> Bool {
    let accepted: Bool
    if raw.isEmpty || raw.allSatisfy({ $0 == " " }) {
      accepted = FontFamilyCommandApplication.apply(.systemDesign(settings.practiceFont), to: settings, onConfigurationSave: save)
    } else {
      accepted = FontFamilyNameCommandPolicy.apply(raw, to: settings, onConfigurationSave: save)
    }
    onResult(accepted)
    return accepted
  }

  private func save() { settings.preferenceConfigurationSaves.deliver() }
}
