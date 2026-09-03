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

  @State private var flashedKey: String?
  @State private var flashedKeyIsCorrect = true

  private var highlightedKey: String? {
    if mode == .react { return flashedKey }
    let expected = nextCharacter.map { mirrored ? KeyboardMirror.transform($0) : $0 }
    return KeyboardGuideModel.highlightedKey(
      for: mode.highlightedCharacter(nextCharacter: expected, recentCharacter: nil), layout: layout)
  }
  private var guideRows: [[KeyboardGuideKey]] { KeyboardGuideModel.rows(for: layout) }

  var body: some View {
    VStack(spacing: 4) {
      ForEach(guideRows.indices, id: \.self) { index in
        keyRow(guideRows[index])
      }
      keyView(KeyboardGuideKey("space", label: "空格", characters: " ", width: 170))
    }
    .padding(10)
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
    HStack(spacing: 4) {
      ForEach(keys) { key in
        keyView(key)
      }
    }
  }

  private func keyView(_ key: KeyboardGuideKey) -> some View {
    Text(key.label)
      .font(.system(size: 10, weight: .semibold, design: .monospaced))
      .foregroundStyle(key.id == highlightedKey ? .white : .secondary)
      .frame(width: key.width, height: 22)
      .background(
        key.id == highlightedKey ? highlightedColor : Color.primary.opacity(0.08),
        in: RoundedRectangle(cornerRadius: 5))
  }

  private var highlightedColor: Color {
    mode == .react && !flashedKeyIsCorrect ? .red : accent
  }
}
