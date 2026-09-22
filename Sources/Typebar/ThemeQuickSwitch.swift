import SwiftUI

/// The native equivalent of the reference footer's compact theme indicator.
/// It deliberately describes Typebar-owned themes only; no web theme names,
/// assets, or presentation code are reused.
struct ThemeIndicatorPresentation: Equatable {
  let name: String
  let isCustom: Bool
  let isFavorite: Bool
}

enum ThemeQuickSwitchAction: Equatable {
  case selectBuiltIn
  case selectCustom(UUID)
  case chooseCustom
  case noCustomThemes
}

enum ThemeQuickPickerScope: String, Identifiable {
  case all
  case custom

  var id: String { rawValue }
}

enum ThemeQuickSwitchPolicy {
  static func presentation(
    builtInTheme: AppTheme, activeCustomThemeID: UUID?, customThemes: [CustomThemeDefinition],
    favoriteThemeIDs: [String]
  ) -> ThemeIndicatorPresentation {
    if let activeCustomThemeID,
      let customTheme = customThemes.first(where: { $0.id == activeCustomThemeID })
    {
      return .init(
        name: customTheme.name, isCustom: true,
        isFavorite: favoriteThemeIDs.contains(
          ThemeFavoritePolicy.customID(for: customTheme.id)))
    }
    return .init(
      name: builtInTheme.displayName, isCustom: false,
      isFavorite: favoriteThemeIDs.contains(ThemeFavoritePolicy.builtInID(for: builtInTheme)))
  }

  static func shiftClickAction(
    activeCustomThemeID: UUID?, customThemes: [CustomThemeDefinition]
  ) -> ThemeQuickSwitchAction {
    if let activeCustomThemeID,
      customThemes.contains(where: { $0.id == activeCustomThemeID })
    {
      return .selectBuiltIn
    }
    switch customThemes {
    case []:
      return .noCustomThemes
    case let onlyTheme where onlyTheme.count == 1:
      return .selectCustom(onlyTheme[0].id)
    default:
      return .chooseCustom
    }
  }
}

struct ThemeIndicatorButton: View {
  let presentation: ThemeIndicatorPresentation
  let onActivate: () -> Void

  var body: some View {
    Button(action: onActivate) {
      HStack(spacing: 5) {
        Image(systemName: "paintpalette")
        Text(presentation.name)
          .lineLimit(1)
        if presentation.isFavorite {
          Image(systemName: "star.fill")
            .imageScale(.small)
            .accessibilityHidden(true)
        }
      }
    }
    .help("点按选择主题；按住 Shift 点按可在内置与自定义主题间切换")
    .accessibilityLabel("当前主题：\(presentation.name)")
    .accessibilityHint("点按选择主题；按住 Shift 点按切换内置与自定义主题")
  }
}

struct ThemeQuickPickerView: View {
  @Environment(\.dismiss) private var dismiss
  let scope: ThemeQuickPickerScope
  let customThemes: [CustomThemeDefinition]
  let favoriteThemeIDs: [String]
  let selectedTheme: ThemeCommandTarget
  let onSelect: (ThemeCommandTarget) -> Void

  private var sortedCustomThemes: [CustomThemeDefinition] {
    customThemes.sorted { lhs, rhs in
      let lhsFavorite = favoriteThemeIDs.contains(ThemeFavoritePolicy.customID(for: lhs.id))
      let rhsFavorite = favoriteThemeIDs.contains(ThemeFavoritePolicy.customID(for: rhs.id))
      if lhsFavorite != rhsFavorite { return lhsFavorite }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
  }

  var body: some View {
    NavigationStack {
      List {
        if scope == .all {
          Section("内置主题") {
            ForEach(AppTheme.allCases, id: \.self) { theme in
              themeRow(
                name: theme.displayName,
                accent: theme.accent,
                isFavorite: favoriteThemeIDs.contains(
                  ThemeFavoritePolicy.builtInID(for: theme)),
                isSelected: selectedTheme == .builtIn(theme)
              ) {
                choose(.builtIn(theme))
              }
            }
          }
        }
        Section(scope == .all ? "自定义主题" : "选择自定义主题") {
          if sortedCustomThemes.isEmpty {
            ContentUnavailableView(
              "还没有自定义主题",
              systemImage: "paintpalette",
              description: Text("可在设置的“自定义主题”中创建或导入仅属于这台 Mac 的主题。")
            )
            .frame(maxWidth: .infinity, minHeight: 150)
          } else {
            ForEach(sortedCustomThemes) { theme in
              themeRow(
                name: theme.name,
                accent: theme.accent.color,
                isFavorite: favoriteThemeIDs.contains(
                  ThemeFavoritePolicy.customID(for: theme.id)),
                isSelected: selectedTheme == .custom(theme.id)
              ) {
                choose(.custom(theme.id))
              }
            }
          }
        }
      }
      .navigationTitle("选择主题")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("完成") { dismiss() }
            .keyboardShortcut(.cancelAction)
        }
      }
    }
    .frame(width: 430, height: 410)
  }

  private func themeRow(
    name: String, accent: Color, isFavorite: Bool, isSelected: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Circle().fill(accent).frame(width: 14, height: 14)
        Text(name)
        if isFavorite {
          Image(systemName: "star.fill")
            .foregroundStyle(.secondary)
            .imageScale(.small)
        }
        Spacer()
        if isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(name)\(isFavorite ? "，已收藏" : "")\(isSelected ? "，当前主题" : "")")
  }

  private func choose(_ target: ThemeCommandTarget) {
    onSelect(target)
    dismiss()
  }
}
