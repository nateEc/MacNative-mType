import SwiftUI

@MainActor struct PracticeThemePreferences {
  let settings: AppSettings
  var onResult: (Bool) -> Void = { _ in }
  private var source: WebsiteConfigNativeThemes? { settings.preferenceConfigurationSaves.themes }
  var availableThemes: [AppTheme] { AppTheme.allCases.filter { source == nil || $0 != .grove } }
  var favorites: [AppTheme] { source?.favorites ?? AppTheme.allCases.filter(settings.isFavoriteTheme) }
  var showsNativeCustomFavorites: Bool { source == nil }
  var theme: Binding<AppTheme> { binding({ source?.theme ?? settings.theme }, PracticeThemeEdit.selectBuiltIn) { settings.theme = $0 } }
  var followsSystem: Binding<Bool> { binding({ source?.followsSystem ?? settings.followSystemTheme }, PracticeThemeEdit.followSystem) { settings.followSystemTheme = $0 } }
  var light: Binding<AppTheme> { binding({ source?.lightTheme ?? settings.systemLightTheme }, PracticeThemeEdit.light) { settings.systemLightTheme = $0 } }
  var dark: Binding<AppTheme> { binding({ source?.darkTheme ?? settings.systemDarkTheme }, PracticeThemeEdit.dark) { settings.systemDarkTheme = $0 } }
  var random: Binding<RandomThemeMode> { binding({ source?.randomMode ?? settings.randomThemeMode }, PracticeThemeEdit.random) { settings.randomThemeMode = $0 } }
  private func binding<T>(_ read: @escaping () -> T, _ edit: @escaping (T) -> PracticeThemeEdit,
    _ native: @escaping (T) -> Void) -> Binding<T> {
    .init(get: read, set: { value in
      if let accepted = settings.preferenceConfigurationSaves.applyThemeEdit(edit(value)) { onResult(accepted); return }
      native(value); settings.preferenceConfigurationSaves.deliver(); onResult(true)
    })
  }
  func toggleFavorite(_ theme: AppTheme) {
    var values = favorites
    if values.contains(theme) { values.removeAll { $0 == theme } } else { values.append(theme) }
    if let accepted = settings.preferenceConfigurationSaves.applyThemeEdit(.favorites(values)) { onResult(accepted); return }
    settings.toggleFavoriteTheme(theme); settings.preferenceConfigurationSaves.deliver(); onResult(true)
  }
  @discardableResult func select(_ target: ThemeCommandTarget) -> Bool {
    let accepted = ThemeCommandApplication.apply(target, to: settings,
      onConfigurationSave: { settings.preferenceConfigurationSaves.deliver() })
    onResult(accepted); return accepted
  }
}

private extension PracticeThemeEdit {
  static func selectBuiltIn(_ theme: AppTheme) -> Self { .select(.builtIn(theme)) }
}
