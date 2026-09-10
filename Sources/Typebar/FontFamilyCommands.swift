import Foundation
import SwiftUI

enum FontFamilyCommandTarget: Equatable {
  case systemDesign(PracticeFont)
  case installedName(String)
  case customName
  case browseInstalled
  case localFile
  case removeLocalFile
}

enum FontFamilyCommandCatalog {
  static let fixedKnownFontIDs = [
    "Roboto_Mono", "Noto_Naskh_Arabic", "Source_Code_Pro", "IBM_Plex_Sans",
    "Inconsolata", "Fira_Code", "JetBrains_Mono", "Roboto", "Montserrat",
    "Titillium_Web", "Lexend_Deca", "Comic_Sans_MS", "Oxygen", "Nunito", "Itim",
    "Courier", "Comfortaa", "Coming_Soon", "Atkinson_Hyperlegible", "Lato", "Lalezar",
    "Boon", "Open_Dyslexic", "Ubuntu", "Ubuntu_Mono", "Georgia", "Cascadia_Mono",
    "IBM_Plex_Mono", "Overpass_Mono", "Hack", "CommitMono", "Mononoki", "Parkinsans",
    "Geist", "Sarabun", "Kanit", "Geist_Mono", "Iosevka", "Proto", "Adwaita_Mono",
    "Inter_Tight", "Space_Grotesk", "Noto_Sans_Lao",
  ]

  @MainActor
  static func items(hasLocalFont: Bool) -> [CommandPaletteItem] {
    let installedFamilies = NativeFontCatalog.installedFamilies
    let available = Set(fixedKnownFontIDs.filter {
      NativeFontCatalog.containsFamily(installedName(forKnownID: $0), in: installedFamilies)
    })
    return items(hasLocalFont: hasLocalFont, availableKnownFontIDs: available)
  }

  static func items(
    hasLocalFont: Bool, availableKnownFontIDs: Set<String>
  ) -> [CommandPaletteItem] {
    var items = PracticeFont.allCases.map { font in
      let identifier = "fontFamily.native.\(font.rawValue)"
      return CommandPaletteItem(
        id: identifier, title: "字体设计：\(font.displayName)",
        subtitle: "使用 macOS 原生字体设计", systemImage: "textformat",
        keywords: [identifier, "font", "family", "字体", "系统", font.rawValue, font.displayName],
        group: .appearance)
    }
    items.append(contentsOf: fixedKnownFontIDs
      .filter(availableKnownFontIDs.contains)
      .sorted { installedName(forKnownID: $0).localizedStandardCompare(
        installedName(forKnownID: $1)) == .orderedAscending }
      .map { identifier in
        let name = installedName(forKnownID: identifier)
        return CommandPaletteItem(
          id: "setFontFamily\(identifier)", title: "本机字体：\(name)",
          subtitle: "此 Mac 已安装", systemImage: "textformat",
          keywords: ["setFontFamily\(identifier)", "font", "字体", name, identifier],
          group: .appearance)
      })
    items.append(CommandPaletteItem(
      id: "customFontName", title: "输入字体名称…", subtitle: "保存字体家族或 PostScript 名称",
      systemImage: "character.cursor.ibeam", keywords: [
        "customFontName", "custom font name", "字体", "名称",
      ], group: .appearance))
    items.append(CommandPaletteItem(
      id: "browseInstalledFonts", title: "浏览本机字体…", subtitle: "搜索这台 Mac 已安装的字体家族",
      systemImage: "magnifyingglass", keywords: [
        "browseInstalledFonts", "installed font", "字体", "浏览", "搜索",
      ], group: .appearance))
    if hasLocalFont {
      items.append(CommandPaletteItem(
        id: "removeLocalFont", title: "移除本地字体", subtitle: "恢复名称字体或系统设计",
        systemImage: "trash", keywords: ["removeLocalFont", "remove font", "字体", "移除"],
        group: .appearance))
    } else {
      items.append(CommandPaletteItem(
        id: "customLocalFont", title: "选择本地字体文件…", subtitle: "支持 TTF、OTF、WOFF 和 WOFF2",
        systemImage: "doc.badge.plus", keywords: [
          "customLocalFont", "upload font", "local font", "字体", "导入",
        ], group: .appearance))
    }
    return items
  }

  static func target(for identifier: String) -> FontFamilyCommandTarget? {
    if identifier.hasPrefix("fontFamily.native."),
      let font = PracticeFont(rawValue: String(identifier.dropFirst("fontFamily.native.".count)))
    {
      return .systemDesign(font)
    }
    if identifier.hasPrefix("setFontFamily") {
      let fixedID = String(identifier.dropFirst("setFontFamily".count))
      guard fixedKnownFontIDs.contains(fixedID) else { return nil }
      return .installedName(installedName(forKnownID: fixedID))
    }
    switch identifier {
    case "customFontName": return .customName
    case "browseInstalledFonts": return .browseInstalled
    case "customLocalFont": return .localFile
    case "removeLocalFont": return .removeLocalFile
    default: return nil
    }
  }

  private static func installedName(forKnownID identifier: String) -> String {
    identifier.replacingOccurrences(of: "_", with: " ")
  }
}

enum FontFamilyCommandApplication {
  @MainActor
  static func apply(
    _ target: FontFamilyCommandTarget, to settings: AppSettings,
    isFontAvailable: (String) -> Bool = NativePracticeFont.isAvailable
  ) -> Bool {
    switch target {
    case .systemDesign(let font):
      settings.installedPracticeFontName = ""
      settings.practiceFont = font
      return true
    case .installedName(let name):
      guard isFontAvailable(name) else { return false }
      settings.installedPracticeFontName = name
      return true
    case .customName, .browseInstalled, .localFile, .removeLocalFile:
      return false
    }
  }
}

enum FontFamilyNameCommandPolicy {
  static func normalized(_ rawValue: String) -> String? {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.count <= NativePracticeFont.maximumNameLength,
      value.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil
    else { return nil }
    return value
  }

  @MainActor
  static func apply(_ rawValue: String, to settings: AppSettings) -> Bool {
    guard let value = normalized(rawValue) else { return false }
    settings.installedPracticeFontName = value
    return true
  }
}

struct FontFamilyNameCommandEditor: View {
  @Environment(\.dismiss) private var dismiss
  let onApply: (String) -> Void
  @State private var name: String
  @FocusState private var inputFocused: Bool

  init(initialName: String, onApply: @escaping (String) -> Void) {
    _name = State(initialValue: initialName)
    self.onApply = onApply
  }

  private var normalizedName: String? { FontFamilyNameCommandPolicy.normalized(name) }

  var body: some View {
    NavigationStack {
      Form {
        Section("字体名称") {
          TextField("字体家族或 PostScript 名称", text: $name)
            .focused($inputFocused)
          if normalizedName == nil {
            Text("请输入 1–50 个字符且不含换行的字体名称。")
              .foregroundStyle(.red)
          }
        }
        Section {
          Text("未安装的名称会保留，并暂时回退到所选系统设计；安装后会自动恢复使用。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .navigationTitle("输入字体名称")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .keyboardShortcut(.cancelAction)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("应用") {
            guard let normalizedName else { return }
            onApply(normalizedName)
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
          .disabled(normalizedName == nil)
        }
      }
    }
    .frame(width: 460, height: 260)
    .onAppear { inputFocused = true }
  }
}
