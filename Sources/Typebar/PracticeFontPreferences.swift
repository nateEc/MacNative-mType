import SwiftUI

@MainActor
struct PracticeFontPreferences {
  let settings: AppSettings
  var onResult: (Bool) -> Void = { _ in }

  private var selectedSystemDesign: PracticeFont? {
    PracticeFont.allCases.first { NativeSystemPracticeFont.identifier(for: $0) == settings.preferenceFontFamilyName }
  }
  var familyName: String { selectedSystemDesign == nil ? settings.preferenceFontFamilyName : "" }

  var design: Binding<PracticeFont> {
    Binding(get: {
      selectedSystemDesign ?? settings.practiceFont
    }, set: {
      onResult(FontFamilyCommandApplication.apply(.systemDesign($0), to: settings, onConfigurationSave: save))
    })
  }

  var size: Binding<Double> {
    Binding(get: { settings.preferenceConfigurationSaves.fontPointSize ?? settings.fontSize }, set: { value in
      guard value.isFinite, value >= PracticeFontSizePolicy.minimumSize else { onResult(false); return }
      if let accepted = settings.preferenceConfigurationSaves.applyFontEdit(.size(value)) { onResult(accepted); return }
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
      accepted = FontFamilyCommandApplication.apply(.systemDesign(design.wrappedValue), to: settings, onConfigurationSave: save)
    } else {
      accepted = FontFamilyNameCommandPolicy.apply(raw, to: settings, onConfigurationSave: save)
    }
    onResult(accepted)
    return accepted
  }

  private func save() { settings.preferenceConfigurationSaves.deliver() }
}
