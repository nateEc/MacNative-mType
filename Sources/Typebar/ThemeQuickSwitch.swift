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

struct ThemeQuickPickerResults {
  let builtInThemes: [AppTheme]
  let customThemes: [CustomThemeDefinition]

  var isEmpty: Bool { builtInThemes.isEmpty && customThemes.isEmpty }
}

enum ThemeQuickPickerSearch {
  static func results(
    scope: ThemeQuickPickerScope, query: String, builtInThemes: [AppTheme],
    customThemes: [CustomThemeDefinition], favoriteThemeIDs: [String]
  ) -> ThemeQuickPickerResults {
    let favorites = Set(favoriteThemeIDs)
    let matchingBuiltIns = scope == .all
      ? builtInThemes.filter { matches(query, name: $0.displayName, id: $0.rawValue) }
      : []
    let matchingCustom = customThemes.filter { matches(query, name: $0.name) }
    return .init(
      builtInThemes: matchingBuiltIns.filter {
        favorites.contains(ThemeFavoritePolicy.builtInID(for: $0))
      } + matchingBuiltIns.filter {
        !favorites.contains(ThemeFavoritePolicy.builtInID(for: $0))
      },
      customThemes: matchingCustom.sorted { lhs, rhs in
        let lhsFavorite = favorites.contains(ThemeFavoritePolicy.customID(for: lhs.id))
        let rhsFavorite = favorites.contains(ThemeFavoritePolicy.customID(for: rhs.id))
        if lhsFavorite != rhsFavorite { return lhsFavorite }
        let order = lhs.name.localizedStandardCompare(rhs.name)
        return order == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString
          : order == .orderedAscending
      })
  }

  private static func matches(_ query: String, name: String, id: String = "") -> Bool {
    let needle = normalized(query)
    return needle.isEmpty || normalized(name).contains(needle) || normalized(id).contains(needle)
  }

  private static func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .replacingOccurrences(of: "_", with: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }
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
  @FocusState private var searchFocused: Bool
  @State private var searchText = ""
  let scope: ThemeQuickPickerScope
  let customThemes: [CustomThemeDefinition]
  let favoriteThemeIDs: [String]
  let selectedTheme: ThemeCommandTarget
  let onSelect: (ThemeCommandTarget) -> Void

  private var searchResults: ThemeQuickPickerResults {
    ThemeQuickPickerSearch.results(
      scope: scope, query: searchText, builtInThemes: AppTheme.allCases,
      customThemes: customThemes, favoriteThemeIDs: favoriteThemeIDs)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        TextField("搜索主题", text: $searchText)
          .textFieldStyle(.roundedBorder)
          .focused($searchFocused)
          .accessibilityLabel("搜索主题")
          .onSubmit { chooseFirstSearchResult() }
          .padding(.horizontal, 16)
          .padding(.top, 12)

        if searchResults.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          ContentUnavailableView(
            "没有匹配的主题", systemImage: "magnifyingglass",
            description: Text("换个名称，或试试主题 ID。"))
        } else {
          List {
            if !searchResults.builtInThemes.isEmpty {
              Section("内置主题") {
                ForEach(searchResults.builtInThemes, id: \.self) { theme in
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
            if !searchResults.customThemes.isEmpty || customThemes.isEmpty && searchText.isEmpty {
              Section(scope == .all ? "自定义主题" : "选择自定义主题") {
                if customThemes.isEmpty {
                  ContentUnavailableView(
                    "还没有自定义主题", systemImage: "paintpalette",
                    description: Text("可在设置的“自定义主题”中创建或导入仅属于这台 Mac 的主题。"))
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                  ForEach(searchResults.customThemes) { theme in
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
    .onAppear { searchFocused = true }
  }

  private func chooseFirstSearchResult() {
    guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    if let theme = searchResults.builtInThemes.first {
      choose(.builtIn(theme))
    } else if let theme = searchResults.customThemes.first {
      choose(.custom(theme.id))
    }
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
