import AppKit
import SwiftUI

enum KeyboardLayout: String, Codable, CaseIterable, Identifiable {
  case ansiQwerty
  case ansiDvorak
  case ansiColemak
  case ansiColemakDH
  case ansiWorkman
  case germanQwertz
  case swissGerman
  case swissFrench
  case nordicQwerty
  case norwegianQwerty
  case swedishQwerty
  case danishQwerty
  case ukQwerty
  case spanishQwerty
  case italianQwerty
  case portugueseQwertyISO
  case portugueseQwertyANSI
  case latinAmericanQwerty
  case polishProgrammers
  case frenchAzerty
  case turkishQ
  case turkishF
  case hungarianQwertz
  case greekAlphabetic
  case russianJcuken
  case ukrainianJcuken
  case bulgarianCyrillic
  case bulgarianPhoneticTraditional
  case serbianCyrillic

  var id: Self { self }

  var displayName: String {
    switch self {
    case .ansiQwerty: "ANSI QWERTY"
    case .ansiDvorak: "ANSI Dvorak"
    case .ansiColemak: "ANSI Colemak"
    case .ansiColemakDH: "ANSI Colemak-DH"
    case .ansiWorkman: "ANSI Workman"
    case .germanQwertz: "German QWERTZ"
    case .swissGerman: "Swiss German"
    case .swissFrench: "Swiss French"
    case .nordicQwerty: "Nordic QWERTY"
    case .norwegianQwerty: "Norwegian QWERTY"
    case .swedishQwerty: "Swedish QWERTY"
    case .danishQwerty: "Danish QWERTY"
    case .ukQwerty: "UK QWERTY"
    case .spanishQwerty: "Spanish QWERTY"
    case .italianQwerty: "Italian QWERTY"
    case .portugueseQwertyISO: "Portuguese QWERTY (ISO)"
    case .portugueseQwertyANSI: "Portuguese QWERTY (ANSI)"
    case .latinAmericanQwerty: "Latin American QWERTY"
    case .polishProgrammers: "Polish (Programmers)"
    case .frenchAzerty: "French AZERTY"
    case .turkishQ: "Turkish Q"
    case .turkishF: "Turkish F"
    case .hungarianQwertz: "Hungarian QWERTZ · Typebar"
    case .greekAlphabetic: "Greek Alphabetic · Typebar"
    case .russianJcuken: "Russian JCUKEN"
    case .ukrainianJcuken: "Ukrainian JCUKEN"
    case .bulgarianCyrillic: "Bulgarian Cyrillic · Typebar"
    case .bulgarianPhoneticTraditional: "Bulgarian Phonetic Traditional"
    case .serbianCyrillic: "Serbian Cyrillic · Typebar"
    }
  }
}

/// Matches Monkeytype's separate `layout` input setting. The keyboard guide
/// can show any supported layout while normal typing remains under macOS's
/// input-source and IME control unless emulation is explicitly requested.
enum KeyboardInputLayout: String, Codable, CaseIterable, Identifiable {
  case system
  case custom
  case ansiQwerty
  case ansiDvorak
  case ansiColemak
  case ansiColemakDH
  case ansiWorkman
  case germanQwertz
  case swissGerman
  case swissFrench
  case nordicQwerty
  case norwegianQwerty
  case swedishQwerty
  case danishQwerty
  case ukQwerty
  case spanishQwerty
  case italianQwerty
  case portugueseQwertyISO
  case portugueseQwertyANSI
  case latinAmericanQwerty
  case polishProgrammers
  case frenchAzerty
  case turkishQ
  case turkishF
  case hungarianQwertz
  case greekAlphabetic
  case russianJcuken
  case ukrainianJcuken
  case bulgarianCyrillic
  case bulgarianPhoneticTraditional
  case serbianCyrillic

  var id: Self { self }

  var displayName: String {
    if self == .system { return "系统当前输入法（推荐）" }
    if self == .custom { return "模拟自定义键盘图" }
    guard let emulatedLayout else { return "系统当前输入法（推荐）" }
    return "模拟 \(emulatedLayout.displayName)"
  }

  var emulatedLayout: KeyboardLayout? {
    self == .system || self == .custom ? nil : KeyboardLayout(rawValue: rawValue)
  }

  init(emulating layout: KeyboardLayout) {
    self = KeyboardInputLayout(rawValue: layout.rawValue) ?? .system
  }

  /// Typebar versions before this setting used `keyboardLayout` for both
  /// display and emulation. Keep an existing non-QWERTY choice working when
  /// decoding one of those archives; fresh settings always use the system.
  static func legacyDefault(for keyboardLayout: KeyboardLayout) -> Self {
    keyboardLayout == .ansiQwerty ? .system : .init(emulating: keyboardLayout)
  }

  func inputMapping(for customLayout: CustomKeyboardGuideLayout?) -> KeyboardInputMapping {
    if let layout = emulatedLayout { return .builtIn(layout) }
    if self == .custom, let customLayout, customLayout.supportsPhysicalInputMapping {
      return .custom(customLayout)
    }
    return .system
  }
}

/// The effective native mapping used by the AppKit input bridge. Keeping this
/// separate from the picker value makes a missing or deleted custom layout
/// safely fall back to the active macOS input source.
enum KeyboardInputMapping: Equatable {
  case system
  case builtIn(KeyboardLayout)
  case custom(CustomKeyboardGuideLayout)
}

/// Chooses the source for a visual keyboard without changing text input.
enum KeyboardGuideLayoutSource: String, Codable, CaseIterable, Identifiable {
  case builtIn
  case systemInput
  case custom

  var id: Self { self }

  var displayName: String {
    switch self {
    case .builtIn: "内置布局"
    case .systemInput: "跟随 macOS 当前输入源"
    case .custom: "自定义键盘图"
    }
  }
}

/// A user-authored visual keymap. It can remain presentation-only or be
/// explicitly selected as the native input mapping.
struct CustomKeyboardGuideLayout: Codable, Equatable, Identifiable {
  var id: UUID
  var name: String
  var numberRow: String
  var topRow: String
  var homeRow: String
  var bottomRow: String
  var shiftedNumberRow: String?
  var shiftedTopRow: String?
  var shiftedHomeRow: String?
  var shiftedBottomRow: String?

  init(
    id: UUID = UUID(), name: String, numberRow: String, topRow: String, homeRow: String,
    bottomRow: String, shiftedNumberRow: String? = nil, shiftedTopRow: String? = nil,
    shiftedHomeRow: String? = nil, shiftedBottomRow: String? = nil
  ) {
    self.id = id
    self.name = name
    self.numberRow = numberRow
    self.topRow = topRow
    self.homeRow = homeRow
    self.bottomRow = bottomRow
    self.shiftedNumberRow = shiftedNumberRow
    self.shiftedTopRow = shiftedTopRow
    self.shiftedHomeRow = shiftedHomeRow
    self.shiftedBottomRow = shiftedBottomRow
  }

  var guideRows: [[KeyboardGuideKey]] {
    zip(inputRows, shiftedInputRows).enumerated().map { rowIndex, rows in
      let (labels, shiftedLabels) = rows
      return Array(labels).enumerated().map { keyIndex, label in
        let shiftedLabel: String?
        if let shiftedLabels, shiftedLabels.indices.contains(keyIndex) {
          shiftedLabel = String(shiftedLabels[keyIndex])
        } else {
          shiftedLabel = nil
        }
        return KeyboardGuideKey(
          "custom-\(id.uuidString)-\(rowIndex)-\(keyIndex)", label: String(label),
          characters: String(label) + (shiftedLabel ?? ""), shiftedLabel: shiftedLabel)
      }
    }
  }

  /// A custom layout has one label per physical position. Letter labels follow
  /// their Unicode lower/uppercase pair; single-case symbols keep the same
  /// value with Shift rather than guessing a punctuation pairing.
  var inputRows: [[Character]] {
    [numberRow, topRow, homeRow, bottomRow].map(Array.init)
  }

  var shiftedInputRows: [[Character]?] {
    [shiftedNumberRow, shiftedTopRow, shiftedHomeRow, shiftedBottomRow].map { $0.map(Array.init) }
  }

  /// Visual rows may contain up to sixteen labels, while a standard physical
  /// keyboard has fewer positions on the lower rows. Oversized rows remain
  /// valid for display but cannot safely act as an input map.
  var supportsPhysicalInputMapping: Bool {
    zip(inputRows, CustomKeyboardGuideLayoutPolicy.physicalInputRowMaximums)
      .allSatisfy { row, maximum in row.count <= maximum }
  }
}

enum CustomKeyboardGuideLayoutPolicy {
  static let maximumLayoutCount = 20
  static let physicalInputRowMaximums = [13, 13, 11, 10]
  private static let rowLengthRange = 1...16
  private static let nameLengthRange = 1...40

  static func make(
    name: String, numberRow: String, topRow: String, homeRow: String, bottomRow: String,
    shiftedNumberRow: String? = nil, shiftedTopRow: String? = nil, shiftedHomeRow: String? = nil,
    shiftedBottomRow: String? = nil
  ) -> CustomKeyboardGuideLayout? {
    normalized(.init(
      name: name, numberRow: numberRow, topRow: topRow, homeRow: homeRow, bottomRow: bottomRow,
      shiftedNumberRow: shiftedNumberRow, shiftedTopRow: shiftedTopRow,
      shiftedHomeRow: shiftedHomeRow, shiftedBottomRow: shiftedBottomRow))
  }

  static func normalized(_ layout: CustomKeyboardGuideLayout) -> CustomKeyboardGuideLayout? {
    let name = layout.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard nameLengthRange.contains(name.count),
      let numberRow = normalizedRow(layout.numberRow),
      let topRow = normalizedRow(layout.topRow),
      let homeRow = normalizedRow(layout.homeRow),
      let bottomRow = normalizedRow(layout.bottomRow),
      isValidShiftedRow(layout.shiftedNumberRow, matching: numberRow.count),
      isValidShiftedRow(layout.shiftedTopRow, matching: topRow.count),
      isValidShiftedRow(layout.shiftedHomeRow, matching: homeRow.count),
      isValidShiftedRow(layout.shiftedBottomRow, matching: bottomRow.count)
    else { return nil }
    return .init(
      id: layout.id, name: name, numberRow: numberRow, topRow: topRow, homeRow: homeRow,
      bottomRow: bottomRow, shiftedNumberRow: normalizedShiftedRow(layout.shiftedNumberRow),
      shiftedTopRow: normalizedShiftedRow(layout.shiftedTopRow),
      shiftedHomeRow: normalizedShiftedRow(layout.shiftedHomeRow),
      shiftedBottomRow: normalizedShiftedRow(layout.shiftedBottomRow))
  }

  static func normalizedLayouts(
    _ layouts: [CustomKeyboardGuideLayout]
  ) -> [CustomKeyboardGuideLayout] {
    var identifiers = Set<UUID>()
    var names = Set<String>()
    var acceptedLayouts: [CustomKeyboardGuideLayout] = []
    for layout in layouts {
      guard let layout = normalized(layout), identifiers.insert(layout.id).inserted else { continue }
      let name = normalizedName(layout.name)
      guard names.insert(name).inserted else { continue }
      acceptedLayouts.append(layout)
    }
    return Array(acceptedLayouts.prefix(maximumLayoutCount))
  }

  static func normalizedName(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }

  private static func normalizedRow(_ row: String) -> String? {
    let visible = String(row.filter { !$0.isWhitespace && !$0.isNewline })
    guard rowLengthRange.contains(visible.count) else { return nil }
    return visible
  }

  private static func isValidShiftedRow(_ row: String?, matching length: Int) -> Bool {
    guard let row else { return true }
    let visible = String(row.filter { !$0.isWhitespace && !$0.isNewline })
    return visible.isEmpty || visible.count == length
  }

  private static func normalizedShiftedRow(_ row: String?) -> String? {
    guard let row else { return nil }
    let visible = String(row.filter { !$0.isWhitespace && !$0.isNewline })
    return visible.isEmpty ? nil : visible
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

/// Native geometry choices corresponding to Monkeytype's `keymapStyle` values.
/// They change only the visual guide, never keyboard interpretation or scoring.
enum KeyboardGuideStyle: String, Codable, CaseIterable, Identifiable {
  case staggered
  case alice
  case matrix
  case split
  case splitMatrix = "split_matrix"
  case steno
  case stenoMatrix = "steno_matrix"

  var id: Self { self }

  var displayName: String {
    switch self {
    case .staggered: "错列"
    case .alice: "人体工学"
    case .matrix: "矩阵"
    case .split: "分体错列"
    case .splitMatrix: "分体矩阵"
    case .steno: "速录"
    case .stenoMatrix: "速录矩阵"
    }
  }

  var isSteno: Bool {
    self == .steno || self == .stenoMatrix
  }

  var usesSplit: Bool {
    self == .split || self == .splitMatrix || self == .alice || isSteno
  }

  func rowLeadingInset(for rowIndex: Int) -> CGFloat {
    switch self {
    case .staggered, .split:
      CGFloat(min(rowIndex, 3)) * 4
    case .steno:
      rowIndex == 0 ? 0 : 8
    case .alice, .matrix, .splitMatrix, .stenoMatrix:
      0
    }
  }
}

struct KeyboardGuideKey: Identifiable, Equatable {
  let id: String
  let label: String
  let characters: Set<Character>
  let width: CGFloat
  let shiftedLabel: String?
  let optionLabel: String?
  let shiftedOptionLabel: String?

  init(
    _ id: String,
    label: String,
    characters: String? = nil,
    width: CGFloat = 28,
    shiftedLabel: String? = nil,
    optionLabel: String? = nil,
    shiftedOptionLabel: String? = nil
  ) {
    self.id = id
    self.label = label
    self.characters = characters.map { Set($0.lowercased()) }
      ?? Set(label.flatMap { KeyboardGuideKey.typedCharacters(for: $0) })
    self.width = width
    self.shiftedLabel = shiftedLabel
    self.optionLabel = optionLabel
    self.shiftedOptionLabel = shiftedOptionLabel
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
      if modifierFlags.contains(.option) {
        if modifierFlags.contains(.shift), let shiftedOptionLabel { return shiftedOptionLabel }
        if let optionLabel { return optionLabel }
      }
      if modifierFlags.contains(.shift), let shiftedLabel { return shiftedLabel }
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
    case .ansiColemakDH:
      [
        row("number", "1234567890-="),
        row("top", "QWFPBJLUY;[]"),
        row("home", "ARSTGMNEIO'"),
        row("bottom", "XCDVZKH,./"),
      ]
    case .ansiWorkman:
      [
        row("number", "1234567890-="),
        row("top", "QDRWBJFUP;[]"),
        row("home", "ASHTGYNEOI'"),
        row("bottom", "ZXMCVKL,./"),
      ]
    case .germanQwertz:
      [
        row(
          "number", "1234567890ß´",
          characters: ["1!", "2\"", "3§", "4$", "5%", "6&", "7/", "8(", "9)", "0=", "ß?", "´`"],
          shiftedLabels: ["!", "\"", "§", "$", "%", "&", "/", "(", ")", "=", "?", "`"]
        ),
        row(
          "top", "QWERTZUIOPÜ+",
          characters: ["qQ", "wW", "eE", "rR", "tT", "zZ", "uU", "iI", "oO", "pP", "üÜ", "+*"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", "Ü", "*"]
        ),
        row(
          "home", "ASDFGHJKLÖÄ#",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "öÖ", "äÄ", "#'"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ö", "Ä", "'"]
        ),
        row(
          "bottom", "<YXCVBNM,.-",
          characters: ["<>", "yY", "xX", "cC", "vV", "bB", "nN", "mM", ",;", ".:", "-_"],
          shiftedLabels: [">", "Y", "X", "C", "V", "B", "N", "M", ";", ":", "_"]
        ),
      ]
    case .swissGerman:
      swissQwertzRows(
        topLabels: "QWERTZUIOPÜ‥",
        topCharacters: ["qQ", "wW", "eE", "rR", "tT", "zZ", "uU", "iI", "oO", "pP", "üè", "‥!"],
        topShiftedLabels: ["Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", "è", "!"],
        homeLabels: "ASDFGHJKLÖÄ$",
        homeCharacters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "öé", "äà", "$£"],
        homeShiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "é", "à", "£"]
      )
    case .swissFrench:
      swissQwertzRows(
        topLabels: "QWERTZUIOPÈ‥",
        topCharacters: ["qQ", "wW", "eE", "rR", "tT", "zZ", "uU", "iI", "oO", "pP", "èü", "‥!"],
        topShiftedLabels: ["Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", "ü", "!"],
        homeLabels: "ASDFGHJKLÉÀ$",
        homeCharacters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "éö", "àä", "$£"],
        homeShiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "ö", "ä", "£"]
      )
    case .nordicQwerty, .norwegianQwerty:
      [
        row(
          "number", "§1234567890+\\",
          characters: ["§°", "1!", "2\"", "3#", "4¤", "5%", "6&", "7/", "8(", "9)", "0=", "+?", "\\`"],
          shiftedLabels: ["°", "!", "\"", "#", "¤", "%", "&", "/", "(", ")", "=", "?", "`"]
        ),
        row(
          "top", "QWERTYUIOPÅ¨",
          characters: ["qQ", "wW", "eE", "rR", "tT", "yY", "uU", "iI", "oO", "pP", "åÅ", "¨^"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "Å", "^"]
        ),
        row(
          "home", "ASDFGHJKLØÆ'",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "øØ", "æÆ", "'*"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ø", "Æ", "*"]
        ),
        isoBottomRow()
      ]
    case .swedishQwerty:
      [
        row(
          "number", "§1234567890+´",
          characters: ["§½", "1!", "2\"", "3#", "4¤", "5%", "6&", "7/", "8(", "9)", "0=", "+?", "´`"],
          shiftedLabels: ["½", "!", "\"", "#", "¤", "%", "&", "/", "(", ")", "=", "?", "`"]
        ),
        row(
          "top", "QWERTYUIOPÅ¨",
          characters: ["qQ", "wW", "eE", "rR", "tT", "yY", "uU", "iI", "oO", "pP", "åÅ", "¨^"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "Å", "^"]
        ),
        row(
          "home", "ASDFGHJKLÖÄ'",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "öÖ", "äÄ", "'*"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ö", "Ä", "*"]
        ),
        isoBottomRow()
      ]
    case .danishQwerty:
      [
        row(
          "number", "½1234567890+´",
          characters: ["½§", "1!", "2\"", "3#", "4¤", "5%", "6&", "7/", "8(", "9)", "0=", "+?", "´`"],
          shiftedLabels: ["§", "!", "\"", "#", "¤", "%", "&", "/", "(", ")", "=", "?", "`"]
        ),
        row(
          "top", "QWERTYUIOPÅ¨",
          characters: ["qQ", "wW", "eE", "rR", "tT", "yY", "uU", "iI", "oO", "pP", "åÅ", "¨^"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "Å", "^"]
        ),
        row(
          "home", "ASDFGHJKLÆØ'",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "æÆ", "øØ", "'*"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Æ", "Ø", "*"]
        ),
        isoBottomRow()
      ]
    case .ukQwerty:
      [
        row(
          "number", "`1234567890-=",
          characters: ["`¬", "1!", "2\"", "3£", "4$", "5%", "6^", "7&", "8*", "9(", "0)", "-_", "=+"],
          shiftedLabels: ["¬", "!", "\"", "£", "$", "%", "^", "&", "*", "(", ")", "_", "+"]
        ),
        row(
          "top", "QWERTYUIOP[]#",
          characters: ["qQ", "wW", "eE", "rR", "tT", "yY", "uU", "iI", "oO", "pP", "[{", "]}", "#~"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "{", "}", "~"]
        ),
        row(
          "home", "ASDFGHJKL;'",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", ";:", "'@"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", ":", "@"]
        ),
        row(
          "bottom", "ZXCVBNM,./",
          characters: ["zZ", "xX", "cC", "vV", "bB", "nN", "mM", ",<", ".>", "/?"],
          shiftedLabels: ["Z", "X", "C", "V", "B", "N", "M", "<", ">", "?"]
        ),
      ]
    case .spanishQwerty:
      [
        row(
          "number", "º1234567890'¡",
          characters: ["ºª", "1!", "2\"", "3·", "4$", "5%", "6&", "7/", "8(", "9)", "0=", "'?", "¡¿"],
          shiftedLabels: ["ª", "!", "\"", "·", "$", "%", "&", "/", "(", ")", "=", "?", "¿"]
        ),
        row(
          "top", "QWERTYUIOP`+",
          characters: ["qQ", "wW", "eE", "rR", "tT", "yY", "uU", "iI", "oO", "pP", "`^", "+*"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "^", "*"]
        ),
        row(
          "home", "ASDFGHJKLÑ´Ç",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "ñÑ", "´¨", "çÇ"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ñ", "¨", "Ç"]
        ),
        isoBottomRow()
      ]
    case .italianQwerty:
      [
        row(
          "number", "\\1234567890‘Ì",
          characters: ["\\|", "1!", "2\"", "3£", "4$", "5%", "6&", "7/", "8(", "9)", "0=", "‘?", "ì^"],
          shiftedLabels: ["|", "!", "\"", "£", "$", "%", "&", "/", "(", ")", "=", "?", "^"]
        ),
        row(
          "top", "QWERTYUIOPÈ+",
          characters: ["qQ", "wW", "eE", "rR", "tT", "yY", "uU", "iI", "oO", "pP", "èé", "+*"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "é", "*"]
        ),
        row(
          "home", "ASDFGHJKLÒÀÙ",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "òç", "à°", "ù§"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "ç", "°", "§"]
        ),
        isoBottomRow()
      ]
    case .portugueseQwertyISO:
      [
        row(
          "number", "\\1234567890'«",
          characters: ["\\|", "1!", "2\"", "3#", "4$", "5%", "6&", "7/", "8(", "9)", "0=", "'?", "«»"],
          shiftedLabels: ["|", "!", "\"", "#", "$", "%", "&", "/", "(", ")", "=", "?", "»"]
        ),
        row(
          "top", "QWERTYUIOP+´",
          characters: ["qQ", "wW", "eE", "rR", "tT", "yY", "uU", "iI", "oO", "pP", "+*", "´`"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "*", "`"]
        ),
        row(
          "home", "ASDFGHJKLÇº~",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "çÇ", "ºª", "~^"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ç", "ª", "^"]
        ),
        isoBottomRow()
      ]
    case .portugueseQwertyANSI:
      [
        row(
          "number", "\\1234567890'<",
          characters: ["\\|", "1!", "2\"", "3#", "4$", "5%", "6&", "7/", "8(", "9)", "0=", "'?", "<>"],
          shiftedLabels: ["|", "!", "\"", "#", "$", "%", "&", "/", "(", ")", "=", "?", ">"]
        ),
        row(
          "top", "QWERTYUIOP+´~",
          characters: ["qQ", "wW", "eE", "rR", "tT", "yY", "uU", "iI", "oO", "pP", "+*", "´`", "~^"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "*", "`", "^"]
        ),
        row(
          "home", "ASDFGHJKLÇº",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "çÇ", "ºª"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ç", "ª"]
        ),
        row(
          "bottom", "ZXCVBNM,.-",
          characters: ["zZ", "xX", "cC", "vV", "bB", "nN", "mM", ",;", ".:", "-_"],
          shiftedLabels: ["Z", "X", "C", "V", "B", "N", "M", ";", ":", "_"]
        ),
      ]
    case .latinAmericanQwerty:
      [
        row(
          "number", "|1234567890'¿",
          characters: ["|°", "1!", "2\"", "3#", "4$", "5%", "6&", "7/", "8(", "9)", "0=", "'?", "¿¡"],
          shiftedLabels: ["°", "!", "\"", "#", "$", "%", "&", "/", "(", ")", "=", "?", "¡"]
        ),
        row(
          "top", "QWERTYUIOP´+",
          characters: ["qQ", "wW", "eE", "rR", "tT", "yY", "uU", "iI", "oO", "pP", "´¨", "+*"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "¨", "*"]
        ),
        row(
          "home", "ASDFGHJKLÑ{",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "ñÑ", "{["],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ñ", "["]
        ),
        isoBottomRow()
      ]
    case .polishProgrammers:
      [
        row("number", "1234567890-="),
        row(
          "top", "QWERTYUIOP[]",
          characters: ["qQ", "wW", "eEęĘ", "rR", "tT", "yY", "uU€", "iI", "oOóÓ", "pP", "[{", "]}"],
          optionLabels: [nil, nil, "ę", nil, nil, nil, "€", nil, "ó", nil, nil, nil],
          shiftedOptionLabels: [nil, nil, "Ę", nil, nil, nil, "€", nil, "Ó", nil, nil, nil]
        ),
        row(
          "home", "ASDFGHJKL;'",
          characters: ["aAąĄ", "sSśŚ", "dD", "fF", "gG", "hH", "jJ", "kK", "lLłŁ", ";:", "'\""],
          optionLabels: ["ą", "ś", nil, nil, nil, nil, nil, nil, "ł", nil, nil],
          shiftedOptionLabels: ["Ą", "Ś", nil, nil, nil, nil, nil, nil, "Ł", nil, nil]
        ),
        row(
          "bottom", "ZXCVBNM,./",
          characters: ["zZżŻ", "xXźŹ", "cCćĆ", "vV", "bB", "nNńŃ", "mM", ",<", ".>", "/?"],
          optionLabels: ["ż", "ź", "ć", nil, nil, "ń", nil, nil, nil, nil],
          shiftedOptionLabels: ["Ż", "Ź", "Ć", nil, nil, "Ń", nil, nil, nil, nil]
        ),
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
    case .turkishQ:
      [
        row(
          "number", "\"1234567890*-",
          characters: ["\"é", "1!", "2'", "3^", "4+", "5%", "6&", "7/", "8(", "9)", "0=", "*?", "-_"],
          shiftedLabels: ["é", "!", "'", "^", "+", "%", "&", "/", "(", ")", "=", "?", "_"]
        ),
        row(
          "top", "QWERTYUIOPĞÜ",
          characters: ["qQ", "wW", "eE", "rR", "tT", "yY", "uU", "ıI", "oO", "pP", "ğĞ", "üÜ"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "Ğ", "Ü"]
        ),
        row(
          "home", "ASDFGHJKLŞİ,",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "şŞ", "iİ", ",;"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ş", "İ", ";"]
        ),
        row(
          "bottom", "<ZXCVBNMÖÇ.",
          characters: ["<>", "zZ", "xX", "cC", "vV", "bB", "nN", "mM", "öÖ", "çÇ", ".:"],
          shiftedLabels: [">", "Z", "X", "C", "V", "B", "N", "M", "Ö", "Ç", ":"]
        ),
      ]
    case .turkishF:
      [
        row(
          "number", "+1234567890/-",
          characters: ["+*", "1!", "2\"", "3^", "4$", "5%", "6&", "7'", "8(", "9)", "0=", "/?", "-_"],
          shiftedLabels: ["*", "!", "\"", "^", "$", "%", "&", "'", "(", ")", "=", "?", "_"]
        ),
        row(
          "top", "FGĞIODRNHPQW",
          characters: ["fF", "gG", "ğĞ", "ıI", "oO", "dD", "rR", "nN", "hH", "pP", "qQ", "wW"]
        ),
        row(
          "home", "UİEAÜTKMLYŞX",
          characters: ["uU", "iİ", "eE", "aA", "üÜ", "tT", "kK", "mM", "lL", "yY", "şŞ", "xX"]
        ),
        row(
          "bottom", "<JÖVCÇZSB.,",
          characters: ["<>", "jJ", "öÖ", "vV", "cC", "çÇ", "zZ", "sS", "bB", ".:", ",;"],
          shiftedLabels: [">", "J", "Ö", "V", "C", "Ç", "Z", "S", "B", ":", ";"]
        ),
      ]
    case .hungarianQwertz:
      [
        row(
          "number", "-1234567890Ó?",
          characters: ["-_", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9(", "0)", "óÓ", "??"],
          shiftedLabels: ["_", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "Ó", "?"]
        ),
        row(
          "top", "QWERTZUIOPŐÚŰ",
          characters: ["qQ", "wW", "eE", "rR", "tT", "zZ", "uU", "iI", "oO", "pP", "őŐ", "úÚ", "űŰ"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", "Ő", "Ú", "Ű"]
        ),
        row(
          "home", "ASDFGHJKLÉÁ",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "éÉ", "áÁ"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "É", "Á"]
        ),
        row(
          "bottom", "<ÍYXCVBNMÖÜ",
          characters: ["<>", "íÍ", "yY", "xX", "cC", "vV", "bB", "nN", "mM", "öÖ", "üÜ"],
          shiftedLabels: [">", "Í", "Y", "X", "C", "V", "B", "N", "M", "Ö", "Ü"]
        ),
      ]
    case .greekAlphabetic:
      [
        row(
          "number", "?1234567890,.",
          characters: ["??", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9(", "0)", ",<", ".>"],
          shiftedLabels: ["?", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "<", ">"]
        ),
        row(
          "top", "ΑΒΓΔΕΖΗΘΙΚΛΜΝ",
          characters: ["αΑ", "βΒ", "γΓ", "δΔ", "εΕ", "ζΖ", "ηΗ", "θΘ", "ιΙ", "κΚ", "λΛ", "μΜ", "νΝ"],
          shiftedLabels: ["Α", "Β", "Γ", "Δ", "Ε", "Ζ", "Η", "Θ", "Ι", "Κ", "Λ", "Μ", "Ν"]
        ),
        row(
          "home", "ΞΟΠΡΣΤΥΦΧΨΩ",
          characters: ["ξΞ", "οΟ", "πΠ", "ρΡ", "σΣ", "τΤ", "υΥ", "φΦ", "χΧ", "ψΨ", "ωΩ"],
          shiftedLabels: ["Ξ", "Ο", "Π", "Ρ", "Σ", "Τ", "Υ", "Φ", "Χ", "Ψ", "Ω"]
        ),
        row(
          "bottom", "ΆΈΉΊΌΎΏΣ·'/",
          characters: ["άΆ", "έΈ", "ήΉ", "ίΊ", "όΌ", "ύΎ", "ώΏ", "ςΣ", "·:", "'\"", "/\\"],
          shiftedLabels: ["Ά", "Έ", "Ή", "Ί", "Ό", "Ύ", "Ώ", "Σ", ":", "\"", "\\"]
        ),
      ]
    case .russianJcuken:
      [
        row(
          "number", "Ё1234567890-=",
          characters: ["ёЁ", "1!", "2\"", "3№", "4;", "5%", "6:", "7?", "8*", "9(", "0)", "-_", "=+"],
          shiftedLabels: ["Ё", "!", "\"", "№", ";", "%", ":", "?", "*", "(", ")", "_", "+"]
        ),
        row(
          "top", "ЙЦУКЕНГШЩЗХЪ\\",
          characters: ["йЙ", "цЦ", "уУ", "кК", "еЕ", "нН", "гГ", "шШ", "щЩ", "зЗ", "хХ", "ъЪ", "\\/"],
          shiftedLabels: ["Й", "Ц", "У", "К", "Е", "Н", "Г", "Ш", "Щ", "З", "Х", "Ъ", "/"]
        ),
        row(
          "home", "ФЫВАПРОЛДЖЭ",
          characters: ["фФ", "ыЫ", "вВ", "аА", "пП", "рР", "оО", "лЛ", "дД", "жЖ", "эЭ"],
          shiftedLabels: ["Ф", "Ы", "В", "А", "П", "Р", "О", "Л", "Д", "Ж", "Э"]
        ),
        row(
          "bottom", "<ЯЧСМИТЬБЮ.",
          characters: ["<>", "яЯ", "чЧ", "сС", "мМ", "иИ", "тТ", "ьЬ", "бБ", "юЮ", ".,"],
          shiftedLabels: [">", "Я", "Ч", "С", "М", "И", "Т", "Ь", "Б", "Ю", ","]
        ),
      ]
    case .ukrainianJcuken:
      [
        row(
          "number", "Ґ1234567890-=",
          characters: ["ґҐ", "1!", "2\"", "3№", "4;", "5%", "6:", "7?", "8*", "9(", "0)", "-_", "=+"],
          shiftedLabels: ["Ґ", "!", "\"", "№", ";", "%", ":", "?", "*", "(", ")", "_", "+"]
        ),
        row(
          "top", "ЙЦУКЕНГШЩЗХЇ\\",
          characters: ["йЙ", "цЦ", "уУ", "кК", "еЕ", "нН", "гГ", "шШ", "щЩ", "зЗ", "хХ", "їЇ", "\\/"],
          shiftedLabels: ["Й", "Ц", "У", "К", "Е", "Н", "Г", "Ш", "Щ", "З", "Х", "Ї", "/"]
        ),
        row(
          "home", "ФІВАПРОЛДЖЄ",
          characters: ["фФ", "іІ", "вВ", "аА", "пП", "рР", "оО", "лЛ", "дД", "жЖ", "єЄ"],
          shiftedLabels: ["Ф", "І", "В", "А", "П", "Р", "О", "Л", "Д", "Ж", "Є"]
        ),
        row(
          "bottom", "<ЯЧСМИТЬБЮ.",
          characters: ["<>", "яЯ", "чЧ", "сС", "мМ", "иИ", "тТ", "ьЬ", "бБ", "юЮ", ".,"],
          shiftedLabels: [">", "Я", "Ч", "С", "М", "И", "Т", "Ь", "Б", "Ю", ","]
        ),
      ]
    case .bulgarianCyrillic:
      [
        row(
          "number", "`1234567890-=",
          characters: ["`~", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9(", "0)", "-_", "=+"],
          shiftedLabels: ["~", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+"]
        ),
        row(
          "top", "ЯЖЕРТЪУИОПШЩЮ",
          characters: ["яЯ", "жЖ", "еЕ", "рР", "тТ", "ъЪ", "уУ", "иИ", "оО", "пП", "шШ", "щЩ", "юЮ"],
          shiftedLabels: ["Я", "Ж", "Е", "Р", "Т", "Ъ", "У", "И", "О", "П", "Ш", "Щ", "Ю"]
        ),
        row(
          "home", "АСДФГХЙКЛЧ'",
          characters: ["аА", "сС", "дД", "фФ", "гГ", "хХ", "йЙ", "кК", "лЛ", "чЧ", "'\""],
          shiftedLabels: ["А", "С", "Д", "Ф", "Г", "Х", "Й", "К", "Л", "Ч", "\""]
        ),
        row(
          "bottom", "<ЗЬЦВБНМ,./",
          characters: ["<>", "зЗ", "ьЬ", "цЦ", "вВ", "бБ", "нН", "мМ", ",<", ".>", "/?"],
          shiftedLabels: [">", "З", "Ь", "Ц", "В", "Б", "Н", "М", "<", ">", "?"]
        ),
      ]
    case .bulgarianPhoneticTraditional:
      [
        row(
          "number", "Ч1234567890-=",
          characters: ["чЧ", "1!", "2@", "3№", "4$", "5%", "6€", "7§", "8*", "9(", "0)", "-_", "=+"],
          shiftedLabels: ["Ч", "!", "@", "№", "$", "%", "€", "§", "*", "(", ")", "_", "+"]
        ),
        row(
          "top", "ЯВЕРТЪУИОПШЩ",
          characters: ["яЯ", "вВ", "еЕ", "рР", "тТ", "ъЪ", "уУ", "иИ", "оО", "пП", "шШ", "щЩ"],
          shiftedLabels: ["Я", "В", "Е", "Р", "Т", "Ъ", "У", "И", "О", "П", "Ш", "Щ"]
        ),
        row(
          "home", "АСДФГХЙКЛ;'Ю",
          characters: ["аА", "сС", "дД", "фФ", "гГ", "хХ", "йЙ", "кК", "лЛ", ";:", "'\"", "юЮ"],
          shiftedLabels: ["А", "С", "Д", "Ф", "Г", "Х", "Й", "К", "Л", ":", "\"", "Ю"]
        ),
        row(
          "bottom", "ЮЗЬЦЖБНМ,./",
          characters: ["юЮ", "зЗ", "ьѝ", "цЦ", "жЖ", "бБ", "нН", "мМ", ",<", ".>", "/?"],
          shiftedLabels: ["Ю", "З", "Ѝ", "Ц", "Ж", "Б", "Н", "М", "<", ">", "?"]
        ),
      ]
    case .serbianCyrillic:
      [
        row(
          "number", "`1234567890-=",
          characters: ["`~", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9(", "0)", "-_", "=+"],
          shiftedLabels: ["~", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+"]
        ),
        row(
          "top", "ЉЊЕРТЗУИОПШЂ\\",
          characters: ["љЉ", "њЊ", "еЕ", "рР", "тТ", "зЗ", "уУ", "иИ", "оО", "пП", "шШ", "ђЂ", "\\|"],
          shiftedLabels: ["Љ", "Њ", "Е", "Р", "Т", "З", "У", "И", "О", "П", "Ш", "Ђ", "|"]
        ),
        row(
          "home", "АСДФГХЈКЛЧЋ",
          characters: ["аА", "сС", "дД", "фФ", "гГ", "хХ", "јЈ", "кК", "лЛ", "чЧ", "ћЋ"],
          shiftedLabels: ["А", "С", "Д", "Ф", "Г", "Х", "Ј", "К", "Л", "Ч", "Ћ"]
        ),
        row(
          "bottom", "<ЖЏЦВБНМ,.-",
          characters: ["<>", "жЖ", "џЏ", "цЦ", "вВ", "бБ", "нН", "мМ", ",;", ".:", "-_"],
          shiftedLabels: [">", "Ж", "Џ", "Ц", "В", "Б", "Н", "М", ";", ":", "_"]
        ),
      ]
    }
  }

  static func highlightedKey(
    for character: Character?,
    layout: KeyboardLayout = .ansiQwerty,
    style: KeyboardGuideStyle = .staggered
  )
    -> String?
  {
    guard let character else { return nil }
    if character == " " { return style.isSteno ? "steno-space" : "space" }
    let keys = style.isSteno ? stenoRows().flatMap { $0 } : rows(for: layout).flatMap { $0 }
    return keys
      .first(where: { $0.characters.contains(Character(String(character).lowercased())) })?
      .id
  }

  static func highlightedKey(
    for character: Character?,
    rows: [[KeyboardGuideKey]],
    style: KeyboardGuideStyle = .staggered
  ) -> String? {
    guard let character else { return nil }
    if character == " " { return style.isSteno ? "steno-space" : "space" }
    let keys = style.isSteno ? stenoRows().flatMap { $0 } : rows.flatMap { $0 }
    return keys
      .first(where: { $0.characters.contains(Character(String(character).lowercased())) })?
      .id
  }

  static func displayRows(
    for layout: KeyboardLayout,
    keysMode: KeyboardGuideKeysMode,
    mode: KeyboardGuideMode,
    nextCharacter: Character?,
    style: KeyboardGuideStyle = .staggered
  ) -> [[KeyboardGuideKey]] {
    if style.isSteno { return stenoRows() }
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

  static func displayRows(
    for rows: [[KeyboardGuideKey]],
    keysMode: KeyboardGuideKeysMode,
    mode: KeyboardGuideMode,
    nextCharacter: Character?,
    style: KeyboardGuideStyle = .staggered
  ) -> [[KeyboardGuideKey]] {
    if style.isSteno { return stenoRows() }
    guard rows.count == 4 else { return rows }
    let showsNumberRow = keysMode == .minimalNumberRow || keysMode == .full
      || (mode == .next && nextCharacter.map { "0123456789".contains($0) } == true)
    let contentRows = showsNumberRow ? rows : Array(rows.dropFirst())
    guard keysMode == .full else { return contentRows }

    return [
      [nonTypingKey("escape", label: "Esc", width: 36)] + rows[0]
        + [nonTypingKey("delete", label: "⌫", width: 40)],
      [nonTypingKey("tab", label: "⇥", width: 36)] + rows[1],
      [nonTypingKey("caps-lock", label: "⇪", width: 42)] + rows[2]
        + [nonTypingKey("return", label: "↩", width: 44)],
      [nonTypingKey("left-shift", label: "⇧", width: 52)] + rows[3]
        + [nonTypingKey("right-shift", label: "⇧", width: 58)],
    ]
  }

  static func bottomRow(
    for keysMode: KeyboardGuideKeysMode,
    style: KeyboardGuideStyle = .staggered
  ) -> [KeyboardGuideKey] {
    if style.isSteno { return [] }
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

  static func stenoRows() -> [[KeyboardGuideKey]] {
    [
      stenoRow("steno-left-top", "STPH", "steno-right-top", "FPLTR"),
      stenoRow("steno-left-bottom", "SKWR", "steno-right-bottom", "RBGSZ"),
      [KeyboardGuideKey("steno-space", label: "—", characters: " ", width: 150)],
    ]
  }

  private static func row(
    _ prefix: String,
    _ labels: String,
    characters: [String]? = nil,
    shiftedLabels: [String]? = nil,
    optionLabels: [String?]? = nil,
    shiftedOptionLabels: [String?]? = nil
  )
    -> [KeyboardGuideKey]
  {
    Array(labels).enumerated().map { offset, label in
      KeyboardGuideKey(
        "\(prefix)-\(offset)",
        label: String(label),
        characters: characters?[safe: offset],
        shiftedLabel: shiftedLabels?[safe: offset],
        optionLabel: optionLabels.flatMap { labels in
          labels.indices.contains(offset) ? labels[offset] : nil
        },
        shiftedOptionLabel: shiftedOptionLabels.flatMap { labels in
          labels.indices.contains(offset) ? labels[offset] : nil
        }
      )
    }
  }

  private static func swissQwertzRows(
    topLabels: String,
    topCharacters: [String],
    topShiftedLabels: [String],
    homeLabels: String,
    homeCharacters: [String],
    homeShiftedLabels: [String]
  ) -> [[KeyboardGuideKey]] {
    [
      row(
        "number", "§1234567890'^",
        characters: ["§°", "1+", "2\"", "3*", "4ç", "5%", "6&", "7/", "8(", "9)", "0=", "'?", "^`"],
        shiftedLabels: ["°", "+", "\"", "*", "ç", "%", "&", "/", "(", ")", "=", "?", "`"]
      ),
      row("top", topLabels, characters: topCharacters, shiftedLabels: topShiftedLabels),
      row("home", homeLabels, characters: homeCharacters, shiftedLabels: homeShiftedLabels),
      row(
        "bottom", "<YXCVBNM,.-",
        characters: ["<>", "yY", "xX", "cC", "vV", "bB", "nN", "mM", ",;", ".:", "-_"],
        shiftedLabels: [">", "Y", "X", "C", "V", "B", "N", "M", ";", ":", "_"]
      ),
    ]
  }

  private static func isoBottomRow() -> [KeyboardGuideKey] {
    row(
      "bottom", "<ZXCVBNM,.-",
      characters: ["<>", "zZ", "xX", "cC", "vV", "bB", "nN", "mM", ",;", ".:", "-_"],
      shiftedLabels: [">", "Z", "X", "C", "V", "B", "N", "M", ";", ":", "_"]
    )
  }

  private static func nonTypingKey(_ id: String, label: String, width: CGFloat) -> KeyboardGuideKey {
    KeyboardGuideKey(id, label: label, characters: "", width: width)
  }

  private static func stenoRow(
    _ leftID: String,
    _ left: String,
    _ rightID: String,
    _ right: String
  ) -> [KeyboardGuideKey] {
    row(leftID, left) + [KeyboardGuideKey("\(leftID)-star", label: "*", width: 34)]
      + row(rightID, right)
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
  let overrideRows: [[KeyboardGuideKey]]?
  let mirrored: Bool
  let scale: Double
  let legendStyle: KeyboardGuideLegendStyle
  let keysMode: KeyboardGuideKeysMode
  let style: KeyboardGuideStyle
  let modifierFlags: NSEvent.ModifierFlags
  let capsLockEnabled: Bool

  @State private var flashedKey: String?
  @State private var flashedKeyIsCorrect = true

  private var baseGuideRows: [[KeyboardGuideKey]] {
    overrideRows ?? KeyboardGuideModel.rows(for: layout)
  }

  private var highlightedKey: String? {
    if mode == .react { return flashedKey }
    let expected = nextCharacter.map { mirrored ? KeyboardMirror.transform($0) : $0 }
    let character = mode.highlightedCharacter(nextCharacter: expected, recentCharacter: nil)
    if let overrideRows {
      return KeyboardGuideModel.highlightedKey(
        for: character, rows: overrideRows, style: style)
    }
    return KeyboardGuideModel.highlightedKey(for: character, layout: layout, style: style)
  }
  private var guideRows: [[KeyboardGuideKey]] {
    if let overrideRows {
      return KeyboardGuideModel.displayRows(
        for: overrideRows, keysMode: keysMode, mode: mode,
        nextCharacter: nextCharacter, style: style)
    }
    return KeyboardGuideModel.displayRows(
      for: layout, keysMode: keysMode, mode: mode, nextCharacter: nextCharacter, style: style)
  }

  var body: some View {
    VStack(spacing: 4 * scale) {
      ForEach(guideRows.indices, id: \.self) { index in
        keyRow(guideRows[index], rowIndex: index)
      }
      if !style.isSteno {
        keyRow(
          KeyboardGuideModel.bottomRow(for: keysMode, style: style), rowIndex: guideRows.count)
      }
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
      if let overrideRows {
        flashedKey = KeyboardGuideModel.highlightedKey(
          for: feedback.character, rows: overrideRows, style: style)
      } else {
        flashedKey = KeyboardGuideModel.highlightedKey(
          for: feedback.character, layout: layout, style: style)
      }
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
    return baseGuideRows.flatMap { $0 }.first(where: {
      $0.id == highlightedKey
    })?.label
  }

  @ViewBuilder
  private func keyRow(_ keys: [KeyboardGuideKey], rowIndex: Int) -> some View {
    switch style {
    case .split, .splitMatrix, .steno, .stenoMatrix:
      splitKeyRow(keys, rowIndex: rowIndex)
    case .alice:
      aliceKeyRow(keys, rowIndex: rowIndex)
    case .staggered, .matrix:
      regularKeyRow(keys, rowIndex: rowIndex)
    }
  }

  private func regularKeyRow(_ keys: [KeyboardGuideKey], rowIndex: Int) -> some View {
    HStack(spacing: 4 * scale) {
      if style.rowLeadingInset(for: rowIndex) > 0 {
        Color.clear.frame(width: style.rowLeadingInset(for: rowIndex) * scale)
      }
      ForEach(keys) { key in
        keyView(key)
      }
    }
  }

  private func splitKeyRow(_ keys: [KeyboardGuideKey], rowIndex: Int) -> some View {
    let splitIndex = (keys.count + 1) / 2
    return HStack(spacing: 4 * scale) {
      if style.rowLeadingInset(for: rowIndex) > 0 {
        Color.clear.frame(width: style.rowLeadingInset(for: rowIndex) * scale)
      }
      ForEach(keys.indices, id: \.self) { index in
        if index == splitIndex {
          Color.clear.frame(width: 24 * scale)
        }
        keyView(keys[index])
      }
    }
  }

  private func aliceKeyRow(_ keys: [KeyboardGuideKey], rowIndex: Int) -> some View {
    let splitIndex = (keys.count + 1) / 2
    return HStack(spacing: 4 * scale) {
      ForEach(keys.indices, id: \.self) { index in
        if index == splitIndex {
          Color.clear.frame(width: 14 * scale)
        }
        let side = index < splitIndex ? -1.0 : 1.0
        let distance = abs(Double(index) - (Double(keys.count - 1) / 2))
        let verticalOffset = CGFloat(min(distance, 4) * 1.4) * scale
        keyView(keys[index])
          .rotationEffect(.degrees(side * min(distance, 4) * 2.2))
          .offset(y: verticalOffset)
      }
    }
    .padding(.vertical, 4 * scale)
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
