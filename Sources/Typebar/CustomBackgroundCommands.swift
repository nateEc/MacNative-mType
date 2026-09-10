import SwiftUI

enum CustomBackgroundCommandEditorKind: String, Equatable, Identifiable {
  case remoteURL
  case blur
  case brightness
  case saturation
  case opacity

  var id: Self { self }

  var title: String {
    switch self {
    case .remoteURL: "背景图片 URL"
    case .blur: "背景模糊"
    case .brightness: "背景亮度"
    case .saturation: "背景饱和度"
    case .opacity: "背景不透明度"
    }
  }

  var range: ClosedRange<Double>? {
    switch self {
    case .remoteURL: nil
    case .blur: 0...20
    case .brightness: 0...2
    case .saturation: 0...3
    case .opacity: 0...1
    }
  }
}

enum CustomBackgroundCommandEditorValue: Equatable {
  case remoteURL(String)
  case number(Double)
}

enum CustomBackgroundCommandTarget: Equatable {
  case editor(CustomBackgroundCommandEditorKind)
  case localFile
  case remove
  case fit(CustomBackgroundFit)
}

enum CustomBackgroundCommandCatalog {
  static func items(hasBackground: Bool) -> [CommandPaletteItem] {
    var items = [
      item(
        id: "customBackground", title: "背景图片 URL…", subtitle: "使用受支持的 HTTP(S) 图片",
        icon: "link", keywords: ["custom background", "url", "背景", "图片"]),
      item(
        id: "customLocalBackground", title: "选择本地背景图片…", subtitle: "图片只保存在这台 Mac",
        icon: "photo.on.rectangle", keywords: ["upload background", "local", "本地", "导入"]),
    ]
    if hasBackground {
      items.append(item(
        id: "removeCustomBackground", title: "移除自定义背景", subtitle: "移除本地图片和背景 URL",
        icon: "trash", keywords: ["remove background", "clear", "移除", "清除"]))
    }
    items.append(contentsOf: CustomBackgroundFit.allCases.map { fit in
      item(
        id: "customBackgroundSize.\(fit.rawValue)", title: "背景适配：\(fit.displayName)",
        subtitle: "立即更新背景图片布局", icon: "rectangle.inset.filled",
        keywords: ["customBackgroundSize", "background", "fit", "背景", "适配", fit.rawValue])
    })
    items.append(contentsOf: [
      editorItem(id: "setCustomBackgroundBlur", kind: .blur),
      editorItem(id: "setCustomBackgroundBrightness", kind: .brightness),
      editorItem(id: "setCustomBackgroundSaturation", kind: .saturation),
      editorItem(id: "setCustomBackgroundOpacity", kind: .opacity),
    ])
    return items
  }

  static func target(for identifier: String) -> CustomBackgroundCommandTarget? {
    switch identifier {
    case "customBackground": .editor(.remoteURL)
    case "customLocalBackground": .localFile
    case "removeCustomBackground": .remove
    case "customBackgroundSize.cover": .fit(.cover)
    case "customBackgroundSize.contain": .fit(.contain)
    case "customBackgroundSize.max": .fit(.max)
    case "setCustomBackgroundBlur": .editor(.blur)
    case "setCustomBackgroundBrightness": .editor(.brightness)
    case "setCustomBackgroundSaturation": .editor(.saturation)
    case "setCustomBackgroundOpacity": .editor(.opacity)
    default: nil
    }
  }

  private static func editorItem(
    id: String, kind: CustomBackgroundCommandEditorKind
  ) -> CommandPaletteItem {
    item(
      id: id, title: "\(kind.title)…", subtitle: "输入数值并立即更新原生背景",
      icon: "slider.horizontal.3", keywords: ["filter", "background", "背景", "滤镜", kind.rawValue])
  }

  private static func item(
    id: String, title: String, subtitle: String, icon: String, keywords: [String]
  ) -> CommandPaletteItem {
    CommandPaletteItem(
      id: id, title: title, subtitle: subtitle, systemImage: icon,
      keywords: [id] + keywords, group: .appearance)
  }
}

enum CustomBackgroundCommandApplication {
  @MainActor
  static func applyImmediate(
    _ target: CustomBackgroundCommandTarget, to settings: AppSettings
  ) -> Bool {
    guard case .fit(let fit) = target else { return false }
    settings.customBackgroundFit = fit
    return true
  }

  @MainActor
  static func removeBackground(
    from settings: AppSettings, removeLocal: () throws -> Void
  ) rethrows {
    try removeLocal()
    settings.customBackgroundURL = ""
  }
}

enum CustomBackgroundCommandEditorPolicy {
  static func value(
    from rawValue: String, kind: CustomBackgroundCommandEditorKind
  ) -> CustomBackgroundCommandEditorValue? {
    switch kind {
    case .remoteURL:
      return CustomBackgroundURLPolicy.normalizedRemoteURL(rawValue).map {
        .remoteURL($0)
      }
    case .blur, .brightness, .saturation, .opacity:
      let text = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let number = Double(text), number.isFinite, let range = kind.range,
        range.contains(number)
      else { return nil }
      return .number(number)
    }
  }

  @MainActor
  static func apply(
    _ rawValue: String, kind: CustomBackgroundCommandEditorKind, to settings: AppSettings
  ) -> Bool {
    guard let value = value(from: rawValue, kind: kind) else { return false }
    switch value {
    case .remoteURL(let url):
      settings.customBackgroundURL = url
    case .number(let number):
      var filter = settings.customBackgroundFilter
      switch kind {
      case .blur: filter.blur = number
      case .brightness: filter.brightness = number
      case .saturation: filter.saturation = number
      case .opacity: filter.opacity = number
      case .remoteURL: return false
      }
      settings.customBackgroundFilter = filter
    }
    return true
  }

  static func initialText(
    kind: CustomBackgroundCommandEditorKind, remoteURL: String, filter: CustomBackgroundFilter
  ) -> String {
    switch kind {
    case .remoteURL: remoteURL
    case .blur: String(filter.blur)
    case .brightness: String(filter.brightness)
    case .saturation: String(filter.saturation)
    case .opacity: String(filter.opacity)
    }
  }
}

struct CustomBackgroundCommandEditor: View {
  @Environment(\.dismiss) private var dismiss
  let kind: CustomBackgroundCommandEditorKind
  let onApply: (String) -> Void
  @State private var text: String
  @FocusState private var inputFocused: Bool

  init(
    kind: CustomBackgroundCommandEditorKind, initialText: String,
    onApply: @escaping (String) -> Void
  ) {
    self.kind = kind
    self.onApply = onApply
    _text = State(initialValue: initialText)
  }

  private var value: CustomBackgroundCommandEditorValue? {
    CustomBackgroundCommandEditorPolicy.value(from: text, kind: kind)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(kind.title) {
          TextField(kind == .remoteURL ? "https://…/image.jpg" : "数值", text: $text)
            .focused($inputFocused)
          if value == nil {
            Text(validationMessage)
              .foregroundStyle(.red)
          }
        }
        Section {
          Text(explanation)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      .navigationTitle(kind.title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
            .keyboardShortcut(.cancelAction)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("应用") {
            guard value != nil else { return }
            onApply(text)
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
          .disabled(value == nil)
        }
      }
    }
    .frame(width: 460, height: 260)
    .onAppear { inputFocused = true }
  }

  private var validationMessage: String {
    if kind == .remoteURL {
      return "请输入 HTTP(S) 的 PNG、JPG、GIF 或 WebP 图片 URL；留空可移除 URL。"
    }
    guard let range = kind.range else { return "请输入有效值。" }
    return "请输入 \(range.lowerBound.formatted())–\(range.upperBound.formatted()) 之间的有限数值。"
  }

  private var explanation: String {
    if kind == .remoteURL {
      return "只有应用 URL 后 Typebar 才会访问该图片地址；本地图片仍优先显示。"
    }
    return "只改变这项背景滤镜，不会重开练习、改变输入或修改其他滤镜。"
  }
}
