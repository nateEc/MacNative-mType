import AppKit
import SwiftUI

enum KeyboardLayout: String, Codable, CaseIterable, Identifiable {
  case ansiQwerty
  case ansiDvorak
  case ansiColemak
  case ansiWorkman
  case frenchAzerty

  var id: Self { self }

  var displayName: String {
    switch self {
    case .ansiQwerty: "ANSI QWERTY"
    case .ansiDvorak: "ANSI Dvorak"
    case .ansiColemak: "ANSI Colemak"
    case .ansiWorkman: "ANSI Workman"
    case .frenchAzerty: "French AZERTY"
    }
  }
}

/// Determines whether the native keyboard guide is hidden, static, reacts to
/// the last physical key, or directs the next expected key.
enum KeyboardGuideMode: String, Codable, CaseIterable, Identifiable {
  case off
  case staticGuide = "static"
  case react
  case next

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .staticGuide: "静态"
    case .react: "按键反馈"
    case .next: "下一键"
    }
  }

  func highlightedCharacter(nextCharacter: Character?, recentCharacter: Character?) -> Character? {
    switch self {
    case .off, .staticGuide: nil
    case .react: recentCharacter
    case .next: nextCharacter
    }
  }
}

struct KeyboardGuideFeedback: Equatable {
  let sequence: Int
  let character: Character
  let isCorrect: Bool
}

enum KeyboardGuideScalePolicy {
  static let range: ClosedRange<Double> = 0.5...3.5

  static func normalized(_ value: Double) -> Double {
    (value * 10).rounded().clamped(to: 5.0...35.0) / 10
  }
}

enum KeyboardGuideLegendStyle: String, Codable, CaseIterable, Identifiable {
  case lowercase
  case uppercase
  case blank
  case dynamic

  var id: Self { self }

  var displayName: String {
    switch self {
    case .lowercase: "小写"
    case .uppercase: "大写"
    case .blank: "空白"
    case .dynamic: "动态"
    }
  }
}

/// Mirrors Monkeytype's `keymapKeys` setting without affecting the native
/// input path. It only changes which visual keys appear in the guide.
enum KeyboardGuideKeysMode: String, Codable, CaseIterable, Identifiable {
  case minimal
  case minimalNumberRow = "minimal_numrow"
  case full

  var id: Self { self }

  var displayName: String {
    switch self {
    case .minimal: "精简"
    case .minimalNumberRow: "精简（数字行）"
    case .full: "完整"
    }
  }

  func showsNumberRow(
    for layout: KeyboardLayout,
    mode: KeyboardGuideMode,
    nextCharacter: Character?
  ) -> Bool {
    switch self {
    case .minimalNumberRow, .full:
      true
    case .minimal:
      layout.showsNumberRowInMinimalGuide
        || (mode == .next && nextCharacter.map { "0123456789".contains($0) } == true)
    }
  }
}

struct KeyboardGuideKey: Identifiable, Equatable {
  let id: String
  let label: String
  let characters: Set<Character>
  let width: CGFloat

  init(_ id: String, label: String, characters: String? = nil, width: CGFloat = 28) {
    self.id = id
    self.label = label
    self.characters = characters.map { Set($0.lowercased()) }
      ?? Set(label.flatMap { KeyboardGuideKey.typedCharacters(for: $0) })
    self.width = width
  }

  private static func typedCharacters(for character: Character) -> [Character] {
    let shiftedPairs: [Character: Character] = [
      "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&",
      "8": "*", "9": "(", "0": ")", "-": "_", "=": "+", "[": "{", "]": "}",
      ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?", "\\": "|", "`": "~",
    ]
    let normalized = Character(String(character).lowercased())
    if let shifted = shiftedPairs[normalized] { return [normalized, shifted] }
    return [normalized]
  }

  func legend(
    style: KeyboardGuideLegendStyle,
    modifierFlags: NSEvent.ModifierFlags,
    capsLockEnabled: Bool
  ) -> String {
    if characters.isEmpty, style != .blank { return label }
    switch style {
    case .blank: return ""
    case .lowercase: return label.lowercased()
    case .uppercase: return label.uppercased()
    case .dynamic:
      if modifierFlags.contains(.shift), let shiftedSymbol = Self.shiftedSymbol(for: label) {
        return shiftedSymbol
      }
      return (modifierFlags.contains(.shift) || capsLockEnabled) ? label.uppercased() : label.lowercased()
    }
  }

  private static func shiftedSymbol(for label: String) -> String? {
    let shiftedSymbols: [String: String] = [
      "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&",
      "8": "*", "9": "(", "0": ")", "-": "_", "=": "+", "[": "{", "]": "}",
      ";": ":", "'": "\"", ",": "<", ".": ">", "/": "?", "\\": "|", "`": "~",
    ]
    return shiftedSymbols[label]
  }
}

enum KeyboardGuideModel {
  static func rows(for layout: KeyboardLayout) -> [[KeyboardGuideKey]] {
    switch layout {
    case .ansiQwerty:
      [
        row("number", "1234567890-="),
        row("top", "QWERTYUIOP[]"),
        row("home", "ASDFGHJKL;'"),
        row("bottom", "ZXCVBNM,./"),
      ]
    case .ansiDvorak:
      [
        row("number", "1234567890-="),
        row("top", "',.PYFGCRL/="),
        row("home", "AOEUIDHTNS-"),
        row("bottom", ";QJKXBMWVZ"),
      ]
    case .ansiColemak:
      [
        row("number", "1234567890-="),
        row("top", "QWFPGJLUY;[]"),
        row("home", "ARSTDHNEIO'"),
        row("bottom", "ZXCVBKM,./"),
      ]
    case .ansiWorkman:
      [
        row("number", "1234567890-="),
        row("top", "QDRWBJFUP;[]"),
        row("home", "ASHTGYNEOI'"),
        row("bottom", "ZXMCVKL,./"),
      ]
    case .frenchAzerty:
      [
        row(
          "number", "1234567890-",
          characters: ["1&", "2é~", "3\"#", "4'", "5(", "6-", "7è`", "8_\\", "9ç^", "0à@", "°)"]
        ),
        row("top", "AZERTYUIOP^$"),
        row("home", "QSDFGHJKLMÙ*"),
        row(
          "bottom", "WXCVBN,;:!",
          characters: ["w", "x", "c", "v", "b", "n", ",?", ";.", ":/", "!§"]
        ),
      ]
    }
  }

  static func highlightedKey(for character: Character?, layout: KeyboardLayout = .ansiQwerty)
    -> String?
  {
    guard let character else { return nil }
    if character == " " { return "space" }
    return rows(for: layout)
      .flatMap { $0 }
      .first(where: { $0.characters.contains(Character(String(character).lowercased())) })?
      .id
  }

  static func displayRows(
    for layout: KeyboardLayout,
    keysMode: KeyboardGuideKeysMode,
    mode: KeyboardGuideMode,
    nextCharacter: Character?
  ) -> [[KeyboardGuideKey]] {
    let baseRows = rows(for: layout)
    let contentRows = keysMode.showsNumberRow(
      for: layout, mode: mode, nextCharacter: nextCharacter)
      ? baseRows : Array(baseRows.dropFirst())
    guard keysMode == .full else { return contentRows }

    return [
      [nonTypingKey("escape", label: "Esc", width: 36)] + baseRows[0]
        + [nonTypingKey("delete", label: "⌫", width: 40)],
      [nonTypingKey("tab", label: "⇥", width: 36)] + baseRows[1],
      [nonTypingKey("caps-lock", label: "⇪", width: 42)] + baseRows[2]
        + [nonTypingKey("return", label: "↩", width: 44)],
      [nonTypingKey("left-shift", label: "⇧", width: 52)] + baseRows[3]
        + [nonTypingKey("right-shift", label: "⇧", width: 58)],
    ]
  }

  static func bottomRow(for keysMode: KeyboardGuideKeysMode) -> [KeyboardGuideKey] {
    if keysMode == .full {
      return [
        nonTypingKey("left-control", label: "⌃", width: 34),
        nonTypingKey("left-option", label: "⌥", width: 34),
        nonTypingKey("left-command", label: "⌘", width: 38),
        KeyboardGuideKey("space", label: "空格", characters: " ", width: 170),
        nonTypingKey("right-command", label: "⌘", width: 38),
        nonTypingKey("right-option", label: "⌥", width: 34),
        nonTypingKey("right-control", label: "⌃", width: 34),
      ]
    }
    return [KeyboardGuideKey("space", label: "空格", characters: " ", width: 170)]
  }

  private static func row(_ prefix: String, _ labels: String, characters: [String]? = nil)
    -> [KeyboardGuideKey]
  {
    Array(labels).enumerated().map { offset, label in
      KeyboardGuideKey(
        "\(prefix)-\(offset)",
        label: String(label),
        characters: characters?[safe: offset]
      )
    }
  }

  private static func nonTypingKey(_ id: String, label: String, width: CGFloat) -> KeyboardGuideKey {
    KeyboardGuideKey(id, label: label, characters: "", width: width)
  }
}

private extension KeyboardLayout {
  var showsNumberRowInMinimalGuide: Bool {
    self == .frenchAzerty
  }
}

extension Collection {
  fileprivate subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

struct KeyboardGuide: View {
  let nextCharacter: Character?
  let mode: KeyboardGuideMode
  let feedback: KeyboardGuideFeedback?
  let accent: Color
  let panel: Color
  let layout: KeyboardLayout
  let mirrored: Bool
  let scale: Double
  let legendStyle: KeyboardGuideLegendStyle
  let keysMode: KeyboardGuideKeysMode
  let modifierFlags: NSEvent.ModifierFlags
  let capsLockEnabled: Bool

  @State private var flashedKey: String?
  @State private var flashedKeyIsCorrect = true

  private var highlightedKey: String? {
    if mode == .react { return flashedKey }
    let expected = nextCharacter.map { mirrored ? KeyboardMirror.transform($0) : $0 }
    return KeyboardGuideModel.highlightedKey(
      for: mode.highlightedCharacter(nextCharacter: expected, recentCharacter: nil), layout: layout)
  }
  private var guideRows: [[KeyboardGuideKey]] {
    KeyboardGuideModel.displayRows(
      for: layout, keysMode: keysMode, mode: mode, nextCharacter: nextCharacter)
  }

  var body: some View {
    VStack(spacing: 4 * scale) {
      ForEach(guideRows.indices, id: \.self) { index in
        keyRow(guideRows[index])
      }
      keyRow(KeyboardGuideModel.bottomRow(for: keysMode))
    }
    .padding(10 * scale)
    .background(panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("键盘提示")
    .accessibilityValue(accessibilityValue)
    .task(id: feedback?.sequence) {
      guard mode == .react, let feedback else {
        flashedKey = nil
        return
      }
      flashedKey = KeyboardGuideModel.highlightedKey(for: feedback.character, layout: layout)
      flashedKeyIsCorrect = feedback.isCorrect
      try? await Task.sleep(nanoseconds: 180_000_000)
      guard !Task.isCancelled else { return }
      flashedKey = nil
    }
  }

  private var accessibilityValue: String {
    switch mode {
    case .off: "键盘提示已关闭"
    case .staticGuide: "当前键盘布局"
    case .react: highlightedLabel.map { "最近按键：\($0)" } ?? "等待按键"
    case .next: highlightedLabel.map { "下一键：\($0)" } ?? "没有可提示的下一键"
    }
  }

  private var highlightedLabel: String? {
    if highlightedKey == "space" { return "空格" }
    return KeyboardGuideModel.rows(for: layout).flatMap { $0 }.first(where: {
      $0.id == highlightedKey
    })?.label
  }

  private func keyRow(_ keys: [KeyboardGuideKey]) -> some View {
    HStack(spacing: 4 * scale) {
      ForEach(keys) { key in
        keyView(key)
      }
    }
  }

  private func keyView(_ key: KeyboardGuideKey) -> some View {
    Text(key.legend(
      style: legendStyle, modifierFlags: modifierFlags, capsLockEnabled: capsLockEnabled))
      .font(.system(size: 10 * scale, weight: .semibold, design: .monospaced))
      .foregroundStyle(key.id == highlightedKey ? .white : .secondary)
      .frame(width: key.width * scale, height: 22 * scale)
      .background(
        key.id == highlightedKey ? highlightedColor : Color.primary.opacity(0.08),
        in: RoundedRectangle(cornerRadius: 5))
  }

  private var highlightedColor: Color {
    mode == .react && !flashedKeyIsCorrect ? .red : accent
  }
}
