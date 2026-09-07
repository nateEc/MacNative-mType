import AppKit
import SwiftUI

enum KeyboardLayout: String, Codable, CaseIterable, Identifiable {
  case ansiQwerty
  case ansiDvorak
  case dvorakLeft
  case dvorakRight
  case programmerDvorak
  case programmerDvorakPrime
  case germanDvorak
  case germanDvorakImproved
  case spanishDvorak
  case swedishColemak
  case swedishDvorak
  case frenchDvorak
  case ansiColemak
  case ansiColemakAngle
  case ansiColemakWide
  case ansiColemakDH
  case ansiColemakDHV
  case colemakDHISO
  case colemakDHMatrix
  case colemakDHWideANSI
  case colemakDHWideISO
  case colemakDHKANSI
  case colemakDHKISO
  case ansiNorman
  case ansiWorkman
  case programmerWorkman
  case mtgapASRT
  case mtgap
  case mtgapFull
  case ina
  case soul
  case niro
  case typehack
  case isrt
  case isrtAngle
  case engram
  case engrammer
  case semimak
  case semimakJQ
  case semimakJQC
  case canary
  case canaryMatrix
  case boo
  case booMangle
  case apt
  case aptAngle
  case middlemak
  case middlemakNH
  case foalmak
  case quartz
  case arensito
  case arts
  case capewellDvorak
  case colman
  case heart
  case klauser
  case oneproduct
  case pine
  case pineV4 = "pine_v4"
  case three
  case asset
  case dwarf
  case flaw
  case stndc
  case uciea
  case whorf
  case whorf6
  case whorfmax
  case octa8
  case nerps
  case gallium
  case galliumAngle = "gallium_angle"
  case galliumV2 = "gallium_v2"
  case nila
  case noctum
  case cascade
  case vylet
  case romak
  case scythe
  case inqwerted
  case rain
  case night
  case nightSTIC = "night_stic"
  case whix2
  case haruka
  case kuntum
  case kuntem = "Kuntem"
  case kuntemJQ = "kuntem-jq"
  case beaklZi = "BEAKL_Zi"
  case snorkle
  case maltron = "MALTRON"
  case prsten = "PRSTEN"
  case rsthd = "RSTHD"
  case handsDownPromethium = "handsdown_promethium"
  case statica3x5 = "statica_3x5"
  case vestnik = "Vestnik"
  case diktor = "Diktor"
  case diktorVoronovMod = "Diktor_VoronovMod"
  case redaktor = "Redaktor"
  case juiyaf = "JUIYAF"
  case zubachev = "Zubachev"
  case colemakQix = "colemak_Qix"
  case colemakQi = "colemak_Qi"
  case colemaQ
  case colemaQF = "colemaQ_F"
  case thaiManoonchai = "thai_manoonchai"
  case brasileiroNativo = "brasileiro_nativo"
  case beakl15 = "beakl_15"
  case beakl19 = "beakl_19"
  case beakl19Bis = "beakl_19_bis"
  case rolll
  case whorfmaxOrtho = "whorfmax_ortho"
  case neo
  case bone
  case adnw = "AdNW"
  case mine
  case noted
  case koy
  case real
  case sertain
  case ctgap
  case graphite
  case focal
  case zenith
  case dhorf
  case gust
  case recurva
  case halmak
  case qgmlwb
  case qgmlwy
  case qwpr
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
  case brazilianABNT2
  case latinAmericanQwerty
  case polishProgrammers
  case frenchAzerty
  case frenchAzertyAFNOR
  case frenchBepo
  case frenchBepoAFNOR
  case ansiAlpha
  case ansiHandsDown
  case ansiHandsDownAlt
  case ansiHandsDownNeu
  case ansiHandsDownNeuInverted
  case turkishQ
  case turkishF
  case turkishE
  case hungarianQwertz
  case greekAlphabetic
  case russianJcuken
  case ukrainianJcuken
  case bulgarianCyrillic
  case bulgarianPhoneticTraditional
  case belarusian
  case macedonian
  case pashto
  case estonian
  case persianStandard
  case persianFarsi
  case arabic101
  case arabic102
  case arabicMac
  case urduPhonetic
  case thaiKedmanee
  case thaiPattachote
  case japaneseHiragana
  case hindiInscript
  case tamil99
  case armenianHMQwerty
  case mongolianCyrillic
  case hebrew
  case serbianCyrillic

  var id: Self { self }

  var displayName: String {
    switch self {
    case .ansiQwerty: "ANSI QWERTY"
    case .ansiDvorak: "ANSI Dvorak"
    case .dvorakLeft: "Dvorak – Left-Handed"
    case .dvorakRight: "Dvorak – Right-Handed"
    case .programmerDvorak: "Programmer Dvorak"
    case .programmerDvorakPrime: "Programmer Dvorak Prime"
    case .germanDvorak: "German Dvorak"
    case .germanDvorakImproved: "German Dvorak Improved"
    case .spanishDvorak: "Spanish Dvorak"
    case .swedishColemak: "Swedish Colemak"
    case .swedishDvorak: "Swedish Dvorak"
    case .frenchDvorak: "French Dvorak"
    case .ansiColemak: "ANSI Colemak"
    case .ansiColemakAngle: "ANSI Colemak Angle"
    case .ansiColemakWide: "ANSI Colemak Wide"
    case .ansiColemakDH: "ANSI Colemak-DH"
    case .ansiColemakDHV: "ANSI Colemak-DHv"
    case .colemakDHISO: "Colemak-DH ISO"
    case .colemakDHMatrix: "Colemak-DH Matrix"
    case .colemakDHWideANSI: "Colemak-DH Wide ANSI"
    case .colemakDHWideISO: "Colemak-DH Wide ISO"
    case .colemakDHKANSI: "Colemak-DHk ANSI"
    case .colemakDHKISO: "Colemak-DHk ISO"
    case .ansiNorman: "ANSI Norman"
    case .ansiWorkman: "ANSI Workman"
    case .programmerWorkman: "Programmer Workman"
    case .mtgapASRT: "MTGAP ASRT"
    case .mtgap: "MTGAP"
    case .mtgapFull: "MTGAP Full"
    case .ina: "Ina"
    case .soul: "Soul"
    case .niro: "Niro"
    case .typehack: "TypeHack"
    case .isrt: "ISRT"
    case .isrtAngle: "ISRT Angle"
    case .engram: "Engram"
    case .engrammer: "Engrammer"
    case .semimak: "Semimak"
    case .semimakJQ: "Semimak JQ"
    case .semimakJQC: "Semimak JQC"
    case .canary: "Canary"
    case .canaryMatrix: "Canary Matrix"
    case .boo: "Boo"
    case .booMangle: "Boo Mangle"
    case .apt: "APT"
    case .aptAngle: "APT Angle"
    case .middlemak: "Middlemak"
    case .middlemakNH: "Middlemak-NH"
    case .foalmak: "Foalmak"
    case .quartz: "Quartz"
    case .arensito: "Arensito"
    case .arts: "ARTS"
    case .capewellDvorak: "Capewell Dvorak"
    case .colman: "Colman"
    case .heart: "Heart"
    case .klauser: "Klauser"
    case .oneproduct: "Oneproduct"
    case .pine: "Pine"
    case .pineV4: "Pine v4"
    case .three: "Three"
    case .asset: "Asset"
    case .dwarf: "Dwarf"
    case .flaw: "Flaw"
    case .stndc: "STNDC"
    case .uciea: "UCIEA"
    case .whorf: "Whorf"
    case .whorf6: "Whorf 6"
    case .whorfmax: "Whorfmax"
    case .octa8: "Octa8"
    case .nerps: "Nerps"
    case .gallium: "Gallium"
    case .galliumAngle: "Gallium Angle"
    case .galliumV2: "Gallium v2"
    case .nila: "Nila"
    case .noctum: "Noctum"
    case .cascade: "Cascade"
    case .vylet: "Vylet"
    case .romak: "Romak"
    case .scythe: "Scythe"
    case .inqwerted: "Inqwerted"
    case .rain: "Rain"
    case .night: "Night"
    case .nightSTIC: "Night STIC"
    case .whix2: "Whix2"
    case .haruka: "Haruka"
    case .kuntum: "Kuntum"
    case .kuntem: "Kuntem"
    case .kuntemJQ: "Kuntem-JQ"
    case .beaklZi: "BEAKL Zi"
    case .snorkle: "Snorkle"
    case .maltron: "MALTRON"
    case .prsten: "PRSTEN"
    case .rsthd: "RSTHD"
    case .handsDownPromethium: "Hands Down Promethium"
    case .statica3x5: "Statica 3×5"
    case .vestnik: "Vestnik"
    case .diktor: "Diktor"
    case .diktorVoronovMod: "Diktor Voronov Mod"
    case .redaktor: "Redaktor"
    case .juiyaf: "JUIYAF"
    case .zubachev: "Zubachev"
    case .colemakQix: "Colemak Qi;x"
    case .colemakQi: "Colemak Qi"
    case .colemaQ: "ColemaQ"
    case .colemaQF: "ColemaQ F"
    case .thaiManoonchai: "Thai Manoonchai"
    case .brasileiroNativo: "Brasileiro Nativo"
    case .beakl15: "BEAKL 15"
    case .beakl19: "BEAKL 19"
    case .beakl19Bis: "BEAKL 19 Bis"
    case .rolll: "Rolll"
    case .whorfmaxOrtho: "Whorfmax Ortho"
    case .neo: "Neo"
    case .bone: "Bone"
    case .adnw: "AdNW"
    case .mine: "Mine"
    case .noted: "Noted"
    case .koy: "Koy"
    case .real: "Real"
    case .sertain: "Sertain"
    case .ctgap: "CTGAP"
    case .graphite: "Graphite"
    case .focal: "Focal"
    case .zenith: "Zenith"
    case .dhorf: "Dhorf"
    case .gust: "Gust"
    case .recurva: "Recurva"
    case .halmak: "Halmak"
    case .qgmlwb: "QGMLWB"
    case .qgmlwy: "QGMLWY"
    case .qwpr: "QWPR"
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
    case .brazilianABNT2: "Brazilian – ABNT2"
    case .latinAmericanQwerty: "Latin American QWERTY"
    case .polishProgrammers: "Polish (Programmers)"
    case .frenchAzerty: "French AZERTY"
    case .frenchAzertyAFNOR: "French AZERTY (AFNOR)"
    case .frenchBepo: "French Bépo"
    case .frenchBepoAFNOR: "French Bépo (AFNOR)"
    case .ansiAlpha: "ANSI Alpha"
    case .ansiHandsDown: "ANSI Hands Down"
    case .ansiHandsDownAlt: "ANSI Hands Down Alt"
    case .ansiHandsDownNeu: "ANSI Hands Down Neu"
    case .ansiHandsDownNeuInverted: "ANSI Hands Down Neu Inverted"
    case .turkishQ: "Turkish Q"
    case .turkishF: "Turkish F"
    case .turkishE: "Turkish E"
    case .hungarianQwertz: "Hungarian QWERTZ · Typebar"
    case .greekAlphabetic: "Greek Alphabetic · Typebar"
    case .russianJcuken: "Russian JCUKEN"
    case .ukrainianJcuken: "Ukrainian JCUKEN"
    case .bulgarianCyrillic: "Bulgarian Cyrillic · Typebar"
    case .bulgarianPhoneticTraditional: "Bulgarian Phonetic Traditional"
    case .belarusian: "Belarusian"
    case .macedonian: "Macedonian"
    case .pashto: "Pashto"
    case .estonian: "Estonian"
    case .persianStandard: "Persian (Standard)"
    case .persianFarsi: "Persian (Farsi)"
    case .arabic101: "Arabic (101)"
    case .arabic102: "Arabic (102)"
    case .arabicMac: "Arabic (macOS)"
    case .urduPhonetic: "Urdu Phonetic (CRULP)"
    case .thaiKedmanee: "Thai Kedmanee"
    case .thaiPattachote: "Thai Pattachote"
    case .japaneseHiragana: "Japanese Hiragana"
    case .hindiInscript: "Hindi – InScript (macOS)"
    case .tamil99: "Tamil99 (macOS)"
    case .armenianHMQwerty: "Armenian – HM QWERTY"
    case .mongolianCyrillic: "Mongolian Cyrillic"
    case .hebrew: "Hebrew"
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
  case dvorakLeft
  case dvorakRight
  case programmerDvorak
  case programmerDvorakPrime
  case germanDvorak
  case germanDvorakImproved
  case spanishDvorak
  case swedishColemak
  case swedishDvorak
  case frenchDvorak
  case ansiColemak
  case ansiColemakAngle
  case ansiColemakWide
  case ansiColemakDH
  case ansiColemakDHV
  case colemakDHISO
  case colemakDHMatrix
  case colemakDHWideANSI
  case colemakDHWideISO
  case colemakDHKANSI
  case colemakDHKISO
  case ansiNorman
  case ansiWorkman
  case programmerWorkman
  case mtgapASRT
  case mtgap
  case mtgapFull
  case ina
  case soul
  case niro
  case typehack
  case isrt
  case isrtAngle
  case engram
  case engrammer
  case semimak
  case semimakJQ
  case semimakJQC
  case canary
  case canaryMatrix
  case boo
  case booMangle
  case apt
  case aptAngle
  case middlemak
  case middlemakNH
  case foalmak
  case quartz
  case arensito
  case arts
  case capewellDvorak
  case colman
  case heart
  case klauser
  case oneproduct
  case pine
  case pineV4 = "pine_v4"
  case three
  case asset
  case dwarf
  case flaw
  case stndc
  case uciea
  case whorf
  case whorf6
  case whorfmax
  case octa8
  case nerps
  case gallium
  case galliumAngle = "gallium_angle"
  case galliumV2 = "gallium_v2"
  case nila
  case noctum
  case cascade
  case vylet
  case romak
  case scythe
  case inqwerted
  case rain
  case night
  case nightSTIC = "night_stic"
  case whix2
  case haruka
  case kuntum
  case kuntem = "Kuntem"
  case kuntemJQ = "kuntem-jq"
  case beaklZi = "BEAKL_Zi"
  case snorkle
  case maltron = "MALTRON"
  case prsten = "PRSTEN"
  case rsthd = "RSTHD"
  case handsDownPromethium = "handsdown_promethium"
  case statica3x5 = "statica_3x5"
  case vestnik = "Vestnik"
  case diktor = "Diktor"
  case diktorVoronovMod = "Diktor_VoronovMod"
  case redaktor = "Redaktor"
  case juiyaf = "JUIYAF"
  case zubachev = "Zubachev"
  case colemakQix = "colemak_Qix"
  case colemakQi = "colemak_Qi"
  case colemaQ
  case colemaQF = "colemaQ_F"
  case thaiManoonchai = "thai_manoonchai"
  case brasileiroNativo = "brasileiro_nativo"
  case beakl15 = "beakl_15"
  case beakl19 = "beakl_19"
  case beakl19Bis = "beakl_19_bis"
  case rolll
  case whorfmaxOrtho = "whorfmax_ortho"
  case neo
  case bone
  case adnw = "AdNW"
  case mine
  case noted
  case koy
  case real
  case sertain
  case ctgap
  case graphite
  case focal
  case zenith
  case dhorf
  case gust
  case recurva
  case halmak
  case qgmlwb
  case qgmlwy
  case qwpr
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
  case brazilianABNT2
  case latinAmericanQwerty
  case polishProgrammers
  case frenchAzerty
  case frenchAzertyAFNOR
  case frenchBepo
  case frenchBepoAFNOR
  case ansiAlpha
  case ansiHandsDown
  case ansiHandsDownAlt
  case ansiHandsDownNeu
  case ansiHandsDownNeuInverted
  case turkishQ
  case turkishF
  case turkishE
  case hungarianQwertz
  case greekAlphabetic
  case russianJcuken
  case ukrainianJcuken
  case bulgarianCyrillic
  case bulgarianPhoneticTraditional
  case belarusian
  case macedonian
  case pashto
  case estonian
  case persianStandard
  case persianFarsi
  case arabic101
  case arabic102
  case arabicMac
  case urduPhonetic
  case thaiKedmanee
  case thaiPattachote
  case japaneseHiragana
  case hindiInscript
  case tamil99
  case armenianHMQwerty
  case mongolianCyrillic
  case hebrew
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
    self.characters = characters.map { characters in
      let normalized = characters.lowercased()
      return Set(normalized).union(normalized.unicodeScalars.map { Character(String($0)) })
    }
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

  func exactlyProduces(_ character: Character) -> Bool {
    let target = Character(String(character).lowercased())
    return [label, shiftedLabel, optionLabel, shiftedOptionLabel]
      .compactMap { $0 }
      .contains { output in
        let characters = Array(output.lowercased())
        return characters.count == 1 && characters[0] == target
      }
  }

  func exactlyProducesCaseSensitive(_ character: Character) -> Bool {
    [label, shiftedLabel, optionLabel, shiftedOptionLabel]
      .compactMap { $0 }
      .contains { output in
        let characters = Array(output)
        return characters.count == 1 && characters[0] == character
      }
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
    case .dvorakLeft:
      [
        layeredRow(
          "number", labels: ["`", "[", "]", "/", "p", "f", "m", "l", "j", "4", "3", "2", "1"],
          shiftedLabels: ["~", "{", "}", "?", "P", "F", "M", "L", "J", "$", "#", "@", "!"],
          optionLabels: ["`", "“", "‘", "÷", "π", "ƒ", "µ", "¬", "∆", "¢", "£", "™", "¡"],
          shiftedOptionLabels: ["`", "”", "’", "¿", "∏", "Ï", "Â", "Ò", "Ô", "›", "‹", "€", "⁄"]
        ),
        layeredRow(
          "top", labels: [";", "q", "b", "y", "u", "r", "s", "o", ".", "6", "5", "=", "\\"],
          shiftedLabels: [":", "Q", "B", "Y", "U", "R", "S", "O", ">", "^", "%", "+", "|"],
          optionLabels: ["…", "œ", "∫", "¥", "¨", "®", "ß", "ø", "≥", "§", "∞", "≠", "«"],
          shiftedOptionLabels: ["Ú", "Œ", "ı", "Á", "¨", "‰", "Í", "Ø", "˘", "ﬂ", "ﬁ", "±", "»"]
        ),
        layeredRow(
          "home", labels: ["-", "k", "c", "d", "t", "h", "e", "a", "z", "8", "7"],
          shiftedLabels: ["_", "K", "C", "D", "T", "H", "E", "A", "Z", "*", "&"],
          optionLabels: ["–", "˚", "ç", "∂", "†", "˙", "´", "å", "Ω", "•", "¶"],
          shiftedOptionLabels: ["—", "", "Ç", "Î", "ˇ", "Ó", "´", "Å", "¸", "°", "‡"]
        ),
        layeredRow(
          "bottom", labels: ["'", "x", "g", "v", "w", "n", "i", ",", "0", "9"],
          shiftedLabels: ["\"", "X", "G", "V", "W", "N", "I", "<", ")", "("],
          optionLabels: ["æ", "≈", "©", "√", "∑", "˜", "ˆ", "≤", "º", "ª"],
          shiftedOptionLabels: ["Æ", "˛", "˝", "◊", "„", "˜", "ˆ", "¯", "‚", "·"]
        ),
      ]
    case .dvorakRight:
      [
        layeredRow(
          "number", labels: ["`", "1", "2", "3", "4", "j", "l", "m", "f", "p", "/", "[", "]"],
          shiftedLabels: ["~", "!", "@", "#", "$", "J", "L", "M", "F", "P", "?", "{", "}"],
          optionLabels: ["`", "¡", "™", "£", "¢", "∆", "¬", "µ", "ƒ", "π", "÷", "“", "‘"],
          shiftedOptionLabels: ["`", "⁄", "€", "‹", "›", "Ô", "Ò", "Â", "Ï", "∏", "¿", "”", "’"]
        ),
        layeredRow(
          "top", labels: ["5", "6", "q", ".", "o", "r", "s", "u", "y", "b", ";", "=", "\\"],
          shiftedLabels: ["%", "^", "Q", ">", "O", "R", "S", "U", "Y", "B", ":", "+", "|"],
          optionLabels: ["∞", "§", "œ", "≥", "ø", "®", "ß", "¨", "¥", "∫", "…", "≠", "«"],
          shiftedOptionLabels: ["ﬁ", "ﬂ", "Œ", "˘", "Ø", "‰", "Í", "¨", "Á", "ı", "Ú", "±", "»"]
        ),
        layeredRow(
          "home", labels: ["7", "8", "z", "a", "e", "h", "t", "d", "c", "k", "-"],
          shiftedLabels: ["&", "*", "Z", "A", "E", "H", "T", "D", "C", "K", "_"],
          optionLabels: ["¶", "•", "Ω", "å", "´", "˙", "†", "∂", "ç", "˚", "–"],
          shiftedOptionLabels: ["‡", "°", "¸", "Å", "´", "Ó", "ˇ", "Î", "Ç", "", "—"]
        ),
        layeredRow(
          "bottom", labels: ["9", "0", "x", ",", "i", "n", "w", "v", "g", "'"],
          shiftedLabels: ["(", ")", "X", "<", "I", "N", "W", "V", "G", "\""],
          optionLabels: ["ª", "º", "≈", "≤", "ˆ", "˜", "∑", "√", "©", "æ"],
          shiftedOptionLabels: ["·", "‚", "˛", "¯", "ˆ", "˜", "„", "◊", "˝", "Æ"]
        ),
      ]
    case .programmerDvorak:
      [
        row(
          "number", "$&[{}(=*)+]!#",
          characters: ["$~", "&%", "[7", "{5", "}3", "(1", "=9", "*0", ")2", "+4", "]6", "!8", "#`"],
          shiftedLabels: ["~", "%", "7", "5", "3", "1", "9", "0", "2", "4", "6", "8", "`"]
        ),
        row(
          "top", ";,.PYFGCRL/@\\",
          characters: [";:", ",<", ".>", "pP", "yY", "fF", "gG", "cC", "rR", "lL", "/?", "@^", "\\|"],
          shiftedLabels: [":", "<", ">", "P", "Y", "F", "G", "C", "R", "L", "?", "^", "|"]
        ),
        row("home", "AOEUIDHTNS-"),
        row("bottom", "'QJKXBMWVZ"),
      ]
    case .programmerDvorakPrime:
      [
        row(
          "number", "$+[{(&=)}]*!|",
          characters: ["$~", "+1", "[2", "{3", "(4", "&5", "=6", ")7", "}8", "]9", "*0", "!%", "|`"],
          shiftedLabels: ["~", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "%", "`"]
        ),
        row(
          "top", ";,.PYFGCRL/@\\",
          characters: [";:", ",<", ".>", "pP", "yY", "fF", "gG", "cC", "rR", "lL", "/?", "@^", "\\#"],
          shiftedLabels: [":", "<", ">", "P", "Y", "F", "G", "C", "R", "L", "?", "^", "#"]
        ),
        row("home", "AOEUIDHTNS-"),
        row("bottom", "'QJKXBMWVZ"),
      ]
    case .germanDvorak:
      [
        row(
          "number", "^1234567890+<",
          characters: ["^°", "1!", "2\"", "3§", "4$", "5%", "6&", "7/", "8(", "9)", "0=", "+*", "<>"],
          shiftedLabels: ["°", "!", "\"", "§", "$", "%", "&", "/", "(", ")", "=", "*", ">"]
        ),
        row(
          "top", "Ü,.PYFGCTZß\\",
          characters: ["üÜ", ",;", ".:", "pP", "yY", "fF", "gG", "cC", "tT", "zZ", "ß?", "\\/"],
          shiftedLabels: ["Ü", ";", ":", "P", "Y", "F", "G", "C", "T", "Z", "?", "/"]
        ),
        row("home", "AOEIUHDRNSL-"),
        row(
          "bottom", "ÄÖQJKXBMWV#",
          characters: ["äÄ", "öÖ", "qQ", "jJ", "kK", "xX", "bB", "mM", "wW", "vV", "#'"],
          shiftedLabels: ["Ä", "Ö", "Q", "J", "K", "X", "B", "M", "W", "V", "'"]
        ),
      ]
    case .germanDvorakImproved:
      [
        row(
          "number", "^1234567890+=",
          characters: ["^°", "1§", "2²", "3³", "4#", "5@", "6&", "7~", "8\\", "9(", "0)", "+*", "=%"],
          shiftedLabels: ["°", "§", "²", "³", "#", "@", "&", "~", "\\", "(", ")", "*", "%"]
        ),
        row(
          "top", "Ü,.PYFGCRL/'",
          characters: ["üÜ", ",;", ".:", "pP", "yY", "fF", "gG", "cC", "rR", "lL", "/?", "'\""],
          shiftedLabels: ["Ü", ";", ":", "P", "Y", "F", "G", "C", "R", "L", "?", "\""]
        ),
        row(
          "home", "AOEUIDHTNSß-",
          characters: ["aA", "oO", "eE", "uU", "iI", "dD", "hH", "tT", "nN", "sS", "ß!", "-_"],
          shiftedLabels: ["A", "O", "E", "U", "I", "D", "H", "T", "N", "S", "!", "_"]
        ),
        row("bottom", "ÄÖQJKXBMWVZ"),
      ]
    case .spanishDvorak:
      [
        row(
          "number", "º1234567890'¡",
          characters: ["ºª", "1!", "2\"", "3·", "4$", "5%", "6&", "7/", "8(", "9)", "0=", "'?", "¡¿"],
          shiftedLabels: ["ª", "!", "\"", "·", "$", "%", "&", "/", "(", ")", "=", "?", "¿"]
        ),
        row(
          "top", ".,ÑPYFGCHL`+",
          characters: [".:", ",;", "ñÑ", "pP", "yY", "fF", "gG", "cC", "hH", "lL", "`^", "+*"],
          shiftedLabels: [":", ";", "Ñ", "P", "Y", "F", "G", "C", "H", "L", "^", "*"]
        ),
        row(
          "home", "AOEUIDRTNS´Ç",
          characters: ["aA", "oO", "eE", "uU", "iI", "dD", "rR", "tT", "nN", "sS", "´¨", "çÇ"],
          shiftedLabels: ["A", "O", "E", "U", "I", "D", "R", "T", "N", "S", "¨", "Ç"]
        ),
        row("bottom", "<-QJKXBMWVZ"),
      ]
    case .swedishColemak:
      [
        row(
          "number", "§1234567890+´",
          characters: ["§½", "1!", "2\"", "3#", "4¤", "5%", "6&", "7/", "8(", "9)", "0=", "+?", "´`"],
          shiftedLabels: ["½", "!", "\"", "#", "¤", "%", "&", "/", "(", ")", "=", "?", "`"]
        ),
        row("top", "QWFPGJLUYÖÅ¨"),
        row(
          "home", "ARSTDHNEIOÄ'",
          characters: ["aA", "rR", "sS", "tT", "dD", "hH", "nN", "eE", "iI", "oO", "äÄ", "'*"],
          shiftedLabels: ["A", "R", "S", "T", "D", "H", "N", "E", "I", "O", "Ä", "*"]
        ),
        row(
          "bottom", "<ZXCVBKM,.-",
          characters: ["<>", "zZ", "xX", "cC", "vV", "bB", "kK", "mM", ",;", ".:", "-_"],
          shiftedLabels: [">", "Z", "X", "C", "V", "B", "K", "M", ";", ":", "_"]
        ),
      ]
    case .swedishDvorak:
      [
        row(
          "number", "§1234567890+´",
          characters: ["§°", "1!", "2\"", "3#", "4€", "5%", "6&", "7/", "8(", "9)", "0=", "+?", "´`"],
          shiftedLabels: ["°", "!", "\"", "#", "€", "%", "&", "/", "(", ")", "=", "?", "`"]
        ),
        row(
          "top", "ÅÄÖPYFGCRL,¨",
          characters: ["åÅ", "äÄ", "öÖ", "pP", "yY", "fF", "gG", "cC", "rR", "lL", ",;", "¨^"],
          shiftedLabels: ["Å", "Ä", "Ö", "P", "Y", "F", "G", "C", "R", "L", ";", "^"]
        ),
        row(
          "home", "AOEUIDHTNS-'",
          characters: ["aA", "oO", "eE", "uU", "iI", "dD", "hH", "tT", "nN", "sS", "-_", "'*"],
          shiftedLabels: ["A", "O", "E", "U", "I", "D", "H", "T", "N", "S", "_", "*"]
        ),
        row("bottom", "<.QJKXBMWVZ"),
      ]
    case .frenchDvorak:
      [
        row(
          "number", "*1234567890+%",
          characters: ["*«", "1»", "2/", "3-", "4è", "5\\", "6^", "7(", "8`", "9)", "0_", "+[", "%]"],
          shiftedLabels: ["«", "»", "/", "-", "è", "\\", "^", "(", "`", ")", "_", "[", "]"]
        ),
        row(
          "top", "?<>G!HVCMKZ=",
          characters: ["?:", "<'", ">é", "gG", "!.", "hH", "vV", "cC", "mM", "kK", "zZ", "=-"],
          shiftedLabels: [":", "'", "é", "G", ".", "H", "V", "C", "M", "K", "Z", "-"]
        ),
        row(
          "home", "OAUEBFSTNDW#",
          characters: ["oO", "aA", "uU", "eE", "bB", "fF", "sS", "tT", "nN", "dD", "wW", "#~"],
          shiftedLabels: ["O", "A", "U", "E", "B", "F", "S", "T", "N", "D", "W", "~"]
        ),
        row(
          "bottom", "Ç|Q@IYXRLPJ",
          characters: ["çà", "|;", "qQ", "@,", "iI", "yY", "xX", "rR", "lL", "pP", "jJ"],
          shiftedLabels: ["à", ";", "Q", ",", "I", "Y", "X", "R", "L", "P", "J"]
        ),
      ]
    case .frenchAzertyAFNOR:
      [
        layeredRow(
          "number",
          labels: ["@", "à", "é", "é", "ê", "(", ")", "‘", "’", "«", "»", "'", "^"],
          shiftedLabels: ["#", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "\"", "¨"],
          optionLabels: ["˘", "§", "´", "`", "&", "[", "]", "¯", "_", "“", "”", "°", "ˇ"],
          shiftedOptionLabels: [nil, "À", "É", "È", "Ê", "˝", nil, nil, "—", "‹", "›", "˚", nil]
        ),
        layeredRow(
          "top",
          labels: ["a", "z", "e", "r", "t", "y", "u", "i", "o", "p", "-", "+"],
          shiftedLabels: ["A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P", "–", "±"],
          optionLabels: ["æ", "£", "€", "®", "{", "}", "ù", "˙", "œ", "%", "−", "†"],
          shiftedOptionLabels: ["Æ", nil, nil, nil, "™", nil, "Ù", nil, "Œ", "‰", "‑", "‡"]
        ),
        layeredRow(
          "home",
          labels: ["q", "s", "d", "f", "g", "h", "j", "k", "l", "m", "/", "*"],
          shiftedLabels: ["Q", "S", "D", "F", "G", "H", "J", "K", "L", "M", "\\", "½"],
          optionLabels: ["θ", "ß", "$", "¤", "µ", nil, nil, "⁄", "|", "∞", "÷", "×"],
          shiftedOptionLabels: [nil, "ẞ", nil, nil, nil, nil, nil, nil, nil, nil, "√", "¼"]
        ),
        layeredRow(
          "bottom",
          labels: ["<", "w", "x", "c", "v", "b", "n", ".", ",", ":", ";"],
          shiftedLabels: [">", "W", "X", "C", "V", "B", "N", "?", "!", "…", "="],
          optionLabels: ["≤", "ʒ", "©", "ç", "¸", nil, "~", "¿", "¡", "·", "≃"],
          shiftedOptionLabels: ["≥", "Ʒ", nil, "Ç", "˛", nil, nil, nil, nil, nil, "≠"]
        ),
      ]
    case .frenchBepo:
      [
        layeredRow(
          "number",
          labels: ["$", "\"", "«", "»", "(", ")", "@", "+", "-", "/", "*", "=", "%"],
          shiftedLabels: ["#", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "°", "`"],
          optionLabels: ["–", "—", "<", ">", "[", "]", "^", "±", "−", "÷", "×", "≠", "″"],
          shiftedOptionLabels: ["¶", "„", "“", "”", "⩽", "⩾", nil, "¬", "¼", "½", "¾", nil, "″"]
        ),
        layeredRow(
          "top",
          labels: ["b", "é", "p", "o", "è", "ô", "v", "d", "l", "j", "z", "w"],
          shiftedLabels: ["B", "É", "P", "O", "È", "!", "V", "D", "L", "J", "Z", "W"],
          optionLabels: ["|", "ó", "&", "œ", "ò", "¡", "ǒ", "ð", "ø", "ĳ", "ə", "ŏ"],
          shiftedOptionLabels: ["¦", "ő", "§", "Œ", "`", nil, nil, "Ð", nil, "Ĳ", "Ə", nil]
        ),
        layeredRow(
          "home",
          labels: ["a", "u", "i", "e", ",", "c", "t", "s", "r", "n", "m", "ç"],
          shiftedLabels: ["A", "U", "I", "E", ";", "C", "T", "S", "R", "N", "M", "Ç"],
          optionLabels: ["æ", "ù", "ö", "€", "’", "©", "þ", "ß", "®", "õ", "ō", "¸"],
          shiftedOptionLabels: ["Æ", "Ù", "ȯ", "¤", "ǫ", "ſ", "Þ", "ẞ", "™", nil, "º", ","]
        ),
        layeredRow(
          "bottom",
          labels: ["ê", "à", "y", "x", ".", "k", "'", "q", "g", "h", "f"],
          shiftedLabels: ["Ê", "À", "Y", "X", ":", "K", "?", "Q", "G", "H", "F"],
          optionLabels: ["/", "\\", "{", "}", "…", "~", "¿", "o", "Ω", "†", "ǫ"],
          shiftedOptionLabels: [nil, nil, "‘", "’", "·", nil, "ỏ", "̊", nil, "‡", "ª"]
        ),
      ]
    case .frenchBepoAFNOR:
      [
        layeredRow(
          "number",
          labels: ["$", "\"", "«", "»", "(", ")", "@", "+", "-", "/", "*", "=", "%"],
          shiftedLabels: ["#", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "°", "`"],
          optionLabels: ["–", "—", "<", ">", "[", "]", "^", "±", "−", "÷", "×", "≠", "‰"],
          shiftedOptionLabels: ["¶", "„", "“", "”", "⩽", "⩾", nil, "¬", "¼", "½", "¾", "′", "″"]
        ),
        layeredRow(
          "top",
          labels: ["b", "é", "p", "o", "è", "ô", "v", "d", "l", "j", "z", "w"],
          shiftedLabels: ["B", "É", "P", "O", "È", "!", "V", "D", "L", "J", "Z", "W"],
          optionLabels: ["|", "ó", "&", "œ", "ò", "¡", "ǒ", "∞", "ø", nil, "ɵ", nil],
          shiftedOptionLabels: ["_", nil, "§", "Œ", "`", nil, nil, nil, "£", nil, nil, nil]
        ),
        layeredRow(
          "home",
          labels: ["a", "u", "i", "e", ",", "c", "t", "s", "r", "n", "m", "ç"],
          shiftedLabels: ["A", "U", "I", "E", ";", "C", "T", "S", "R", "N", "M", "Ç"],
          optionLabels: ["æ", "ù", "ö", "€", "'", "¸", "ᵉ", "ß", "ŏ", "õ", "ō", nil],
          shiftedOptionLabels: ["Æ", "Ù", "ȯ", "¤", "ț", "©", "™", "ſ", "®", nil, nil, nil]
        ),
        layeredRow(
          "bottom",
          labels: ["ê", "à", "y", "x", ".", "k", "’", "q", "g", "h", "f"],
          shiftedLabels: ["Ê", "À", "Y", "X", ":", "K", "?", "Q", "G", "H", "F"],
          optionLabels: ["/", "\\", "{", "}", "…", "~", "¿", "å", "Ω", "ọ", "ǫ"],
          shiftedOptionLabels: ["^", "‚", "‘", "’", "·", "‑", "ỏ", "ơ", "†", "‡", nil]
        ),
      ]
    case .ansiAlpha:
      [
        row("number", "`1234567890-="),
        row("top", "ABCDEFGHIJ[]\\"),
        row("home", "KLMNOPQRS;'"),
        row("bottom", "TUVWXYZ,./"),
      ]
    case .ansiHandsDown:
      [
        row("number", "`1234567890-="),
        row("top", "QCHPVKYOJ/[]\\"),
        row("home", "RSNTGWUEIA;"),
        row("bottom", "XMLDBZF',."),
      ]
    case .ansiHandsDownAlt:
      [
        row("number", "`1234567890-="),
        row("top", "WGHMKQCUJ'[]\\"),
        row("home", "RSNTFYAEOI;"),
        row("bottom", "XBLDVZP,./"),
      ]
    case .ansiHandsDownNeu:
      [
        row(
          "number", labels: ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "=", "\\"],
          characters: ["`~", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8?", "9<", "0>", "=_", "\\|"],
          shiftedLabels: ["~", "!", "@", "#", "$", "%", "^", "&", "?", "<", ">", "_", "|"]
        ),
        row(
          "top", labels: ["w", "f", "m", "p", "v", "/", ".", "q", "\"", "'", "z", "(", ")"],
          characters: ["wW", "fF", "mM", "pP", "vV", "/*", ".:", "qQ", "\"[", "']", "zZ", "({", ")}"],
          shiftedLabels: ["W", "F", "M", "P", "V", "*", ":", "Q", "[", "]", "Z", "{", "}"]
        ),
        row(
          "home", labels: ["r", "s", "n", "t", "b", ",", "a", "e", "i", "h", "j"],
          characters: ["rR", "sS", "nN", "tT", "bB", ",;", "aA", "eE", "iI", "hH", "jJ"],
          shiftedLabels: ["R", "S", "N", "T", "B", ";", "A", "E", "I", "H", "J"]
        ),
        row(
          "bottom", labels: ["x", "c", "l", "d", "g", "-", "u", "o", "y", "k"],
          characters: ["xX", "cC", "lL", "dD", "gG", "-+", "uU", "oO", "yY", "kK"],
          shiftedLabels: ["X", "C", "L", "D", "G", "+", "U", "O", "Y", "K"]
        ),
      ]
    case .ansiHandsDownNeuInverted:
      [
        row(
          "number", labels: ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "=", "\\"],
          characters: ["`~", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8?", "9<", "0>", "=_", "\\|"],
          shiftedLabels: ["~", "!", "@", "#", "$", "%", "^", "&", "?", "<", ">", "_", "|"]
        ),
        row(
          "top", labels: ["x", "c", "l", "d", "g", "-", "u", "o", "y", "k", "z", "(", ")"],
          characters: ["xX", "cC", "lL", "dD", "gG", "-+", "uU", "oO", "yY", "kK", "zZ", "({", ")}"],
          shiftedLabels: ["X", "C", "L", "D", "G", "+", "U", "O", "Y", "K", "Z", "{", "}"]
        ),
        row(
          "home", labels: ["r", "s", "n", "t", "b", ",", "a", "e", "i", "h", "j"],
          characters: ["rR", "sS", "nN", "tT", "bB", ",;", "aA", "eE", "iI", "hH", "jJ"],
          shiftedLabels: ["R", "S", "N", "T", "B", ";", "A", "E", "I", "H", "J"]
        ),
        row(
          "bottom", labels: ["w", "f", "m", "p", "v", "/", ".", "q", "\"", "'"],
          characters: ["wW", "fF", "mM", "pP", "vV", "/*", ".:", "qQ", "\"[", "']"],
          shiftedLabels: ["W", "F", "M", "P", "V", "*", ":", "Q", "[", "]"]
        ),
      ]
    case .mtgap:
      [
        row("number", "`1234567890-="),
        row("top", "YPOUJKDLCW[]\\"),
        row(
          "home", labels: ["i", "n", "e", "a", ",", "m", "h", "t", "s", "r", "'"],
          characters: ["iI", "nN", "eE", "aA", ",;", "mM", "hH", "tT", "sS", "rR", "'\""],
          shiftedLabels: ["I", "N", "E", "A", ";", "M", "H", "T", "S", "R", "\""]
        ),
        row(
          "bottom", labels: ["q", "z", "/", ".", ":", "b", "f", "g", "v", "x"],
          characters: ["qQ", "zZ", "/<", ".>", ":?", "bB", "fF", "gG", "vV", "xX"],
          shiftedLabels: ["Q", "Z", "<", ">", "?", "B", "F", "G", "V", "X"]
        ),
      ]
    case .mtgapFull:
      [
        row(
          "number", labels: ["\\", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "q", "z"],
          characters: ["\\^", "1~", "2[", "3{", "4<", "5|", "6#", "7>", "8}", "9]", "0%", "qQ", "zZ"],
          shiftedLabels: ["^", "~", "[", "{", "<", "|", "#", ">", "}", "]", "%", "Q", "Z"]
        ),
        row(
          "top", labels: ["y", "p", "o", "u", "-", "k", "d", "l", "c", "w", "x", "/", "$"],
          characters: ["yY", "pP", "oO", "uU", "-=", "kK", "dD", "lL", "cC", "wW", "xX", "/+", "$@"],
          shiftedLabels: ["Y", "P", "O", "U", "=", "K", "D", "L", "C", "W", "X", "+", "@"]
        ),
        row(
          "home", labels: ["i", "n", "e", "a", ",", "m", "h", "t", "s", "r", "\""],
          characters: ["iI", "nN", "eE", "aA", ",:", "mM", "hH", "tT", "sS", "rR", "\"!"],
          shiftedLabels: ["I", "N", "E", "A", ":", "M", "H", "T", "S", "R", "!"]
        ),
        row(
          "bottom", labels: ["(", ")", "'", ".", "_", "b", "f", "g", "v", "j"],
          characters: ["(`", ")?", "'*", ".;", "_&", "bB", "fF", "gG", "vV", "jJ"],
          shiftedLabels: ["`", "?", "*", ";", "&", "B", "F", "G", "V", "J"]
        ),
      ]
    case .ina:
      [
        row(
          "number", labels: ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "q", "x"],
          characters: ["`~", "1[", "2]", "3#", "4$", "5%", "6^", "7&", "8*", "9{", "0}", "qQ", "xX"],
          shiftedLabels: ["~", "[", "]", "#", "$", "%", "^", "&", "*", "{", "}", "Q", "X"]
        ),
        row(
          "top", labels: ["!", "p", "u", "o", "-", "j", "b", "l", "m", "y", "z", "v", "\\"],
          characters: ["!+", "pP", "uU", "oO", "-_", "jJ", "bB", "lL", "mM", "yY", "zZ", "vV", "\\|"],
          shiftedLabels: ["+", "P", "U", "O", "_", "J", "B", "L", "M", "Y", "Z", "V", "|"]
        ),
        row(
          "home", labels: ["i", "n", "e", "a", ",", "d", "t", "k", "r", "s", "'"],
          characters: ["iI", "nN", "eE", "aA", ",;", "dD", "tT", "kK", "rR", "sS", "'\""],
          shiftedLabels: ["I", "N", "E", "A", ";", "D", "T", "K", "R", "S", "\""]
        ),
        row(
          "bottom", labels: ["=", "@", ":", ".", "?", "g", "h", "c", "w", "f"],
          characters: ["=(", "@)", ":<", ".>", "?/", "gG", "hH", "cC", "wW", "fF"],
          shiftedLabels: ["(", ")", "<", ">", "/", "G", "H", "C", "W", "F"]
        ),
      ]
    case .soul:
      [
        row("number", "`1234567890-="),
        row("top", "QWLDPKMUY;[]\\"),
        row("home", "ASRTGFNEIO'"),
        row("bottom", "ZXCVJBH,./"),
      ]
    case .niro:
      [
        row("number", "`1234567890-="),
        row("top", "QWUDPJFYL;[]\\"),
        row("home", "ASETGHNIRO'"),
        row("bottom", "ZXCVBKM,./"),
      ]
    case .typehack:
      [
        row(
          "number", labels: ["^", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "*", "\\"],
          characters: ["^~", "1!", "2@", "3#", "4$", "5%", "6&", "7`", "8(", "9)", "0=", "*+", "\\|"],
          shiftedLabels: ["~", "!", "@", "#", "$", "%", "&", "`", "(", ")", "=", "+", "|"]
        ),
        row("top", "JGHPFQVOU;/[]"),
        row("home", "RSNTKYIAEL-"),
        row("bottom", "ZWMDBC,'.X"),
      ]
    case .isrt:
      [
        row("number", "`1234567890-="),
        row("top", "YCLMKZFU,'[]\\"),
        row("home", "ISRTGPNEAO;"),
        row("bottom", "QVWDJBH/.X"),
      ]
    case .isrtAngle:
      [
        row("number", "`1234567890-="),
        row("top", "YCLMKZFU,'[]\\"),
        row("home", "ISRTGPNEAO;"),
        row("bottom", "VWDJQBH/.X"),
      ]
    case .engram:
      [
        row(
          "number", labels: ["[", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "]", "/"],
          characters: ["[{", "1|", "2=", "3~", "4+", "5<", "6>", "7^", "8&", "9%", "0*", "]}", "/\\"],
          shiftedLabels: ["{", "|", "=", "~", "+", "<", ">", "^", "&", "%", "*", "}", "\\"]
        ),
        row(
          "top", labels: ["b", "y", "o", "u", "'", "\"", "l", "d", "w", "v", "z", "#", "@"],
          characters: ["bB", "yY", "oO", "uU", "'(", "\")", "lL", "dD", "wW", "vV", "zZ", "#$", "@`"],
          shiftedLabels: ["B", "Y", "O", "U", "(", ")", "L", "D", "W", "V", "Z", "$", "`"]
        ),
        row(
          "home", labels: ["c", "i", "e", "a", ",", ".", "h", "t", "s", "n", "q"],
          characters: ["cC", "iI", "eE", "aA", ",;", ".:", "hH", "tT", "sS", "nN", "qQ"],
          shiftedLabels: ["C", "I", "E", "A", ";", ":", "H", "T", "S", "N", "Q"]
        ),
        row(
          "bottom", labels: ["g", "x", "j", "k", "-", "?", "r", "m", "f", "p"],
          characters: ["gG", "xX", "jJ", "kK", "-_", "?!", "rR", "mM", "fF", "pP"],
          shiftedLabels: ["G", "X", "J", "K", "_", "!", "R", "M", "F", "P"]
        ),
      ]
    case .engrammer:
      [
        row("number", "`1234567890[]"),
        row("top", "BYOU';LDWVZ=\\"),
        row("home", "CIEA,.HTSNQ"),
        row("bottom", "GXJK-/RMFP"),
      ]
    case .semimak:
      [
        row("number", "`1234567890-="),
        row("top", "FLHVZQWUOY[]\\"),
        row("home", "SRNTKCDEAI;"),
        row("bottom", "X'BMJPG,./"),
      ]
    case .semimakJQ:
      [
        row("number", "`1234567890-="),
        row("top", "FLHVZ'WUOY[]\\"),
        row("home", "SRNTKCDEAI;"),
        row("bottom", "XJBMQPG,./"),
      ]
    case .semimakJQC:
      [
        row("number", "`1234567890-="),
        row("top", "FLHVZ'WUOY[]\\"),
        row("home", "SRNTKGDEAI;"),
        row("bottom", "XJBMQPC,./"),
      ]
    case .canary:
      [
        row("number", "`1234567890-="),
        row("top", "WLYPKZXOU;[]\\"),
        row("home", "CRSTBFNEIA'"),
        row("bottom", "JVDGQMH/,."),
      ]
    case .canaryMatrix:
      [
        row("number", "`1234567890-="),
        row("top", "WLYPBZFOU'[]\\"),
        row("home", "CRSTGMNEIA;"),
        row("bottom", "QJVDKXH/,."),
      ]
    case .boo:
      [
        row("number", "`1234567890[]"),
        row(
          "top", labels: [",", ".", "u", "c", "v", "q", "f", "d", "l", "y", "?", "=", "\\"],
          characters: [",<", ".>", "uU", "cC", "vV", "qQ", "fF", "dD", "lL", "yY", "?/", "=+", "\\|"],
          shiftedLabels: ["<", ">", "U", "C", "V", "Q", "F", "D", "L", "Y", "/", "+", "|"]
        ),
        row("home", "AOESGBNTRI-"),
        row("bottom", ";X'WZPHMKJ"),
      ]
    case .booMangle:
      [
        row(
          "number", labels: ["$", "&", "[", "{", "}", "(", "=", "*", ")", "+", "]", "!", "#"],
          characters: ["$~", "&%", "[7", "{5", "}3", "(1", "=9", "*0", ")2", "+4", "]6", "!8", "#`"],
          shiftedLabels: ["~", "%", "7", "5", "3", "1", "9", "0", "2", "4", "6", "8", "`"]
        ),
        row(
          "top", labels: [",", ".", "u", "c", "v", "q", "f", "d", "l", "y", "/", "@", "\\"],
          characters: [",<", ".>", "uU", "cC", "vV", "qQ", "fF", "dD", "lL", "yY", "/?", "@^", "\\|"],
          shiftedLabels: ["<", ">", "U", "C", "V", "Q", "F", "D", "L", "Y", "?", "^", "|"]
        ),
        row("home", "AOESGBNTRI-"),
        row("bottom", "X'W;ZPHMKJ"),
      ]
    case .apt:
      [
        row("number", "`1234567890-="),
        row("top", "WGDFBQLUOY[]\\"),
        row("home", "RSTHKJNEAI;"),
        row("bottom", "XCMPVZ,.'/"),
      ]
    case .aptAngle:
      [
        row("number", "`1234567890-="),
        row("top", "WGDFBQLUOY[]\\"),
        row("home", "RSTHKJNEAI;"),
        row("bottom", "CMPVXZ,.'/"),
      ]
    case .middlemak:
      [
        row("number", "`1234567890-="),
        row("top", "QWLDGJFOU;[]\\"),
        row("home", "ASRTPYNEIH'"),
        row("bottom", "ZXCVBKM,./"),
      ]
    case .middlemakNH:
      [
        row("number", "`1234567890-="),
        row("top", "QWLDGJFOU;[]\\"),
        row("home", "NSRTPYHEIA'"),
        row("bottom", "ZXCVBKM,./"),
      ]
    case .foalmak:
      [
        row("number", "`1234567890-="),
        row("top", "BX.WVZ/UTK[]\\"),
        row("home", "FOALSNEIGH;"),
        row("bottom", "P'.MCQJYDR"),
      ]
    case .quartz:
      [
        row("number", "`12345=67890-"),
        row("top", "QUARTZ/GLYPH\\"),
        row("home", "[JOB];VEX'D"),
        row("bottom", "CWM,FINKS."),
      ]
    case .arensito:
      [
        row("number", "`1234567890-="),
        row("top", "QL.P';FUDK[]\\"),
        row("home", "ARENBGSITO/"),
        row("bottom", "ZW,HJVCYMX"),
      ]
    case .arts:
      [
        row("number", "`1234567890-="),
        row("top", "QLDYGJMOU;[]\\"),
        row("home", "ARTSCPNEIH/"),
        row("bottom", "ZXKWVBF',."),
      ]
    case .capewellDvorak:
      [
        row("number", "`1234567890[]"),
        row("top", "',.PYQFGRK/=\\"),
        row("home", "OAEIUDHTNS-"),
        row("bottom", "ZXCVJLMWB;"),
      ]
    case .colman:
      [
        row("number", "`1234567890-="),
        row("top", "QLRWBJMUY;[]\\"),
        row("home", "ANHSFPTEIO'"),
        row("bottom", "ZXCVKGD,./"),
      ]
    case .heart:
      [
        row("number", "`1234567890-="),
        row("top", "QGDVXJYOU;[]\\"),
        row("home", "RSTHLPNAIE'"),
        row("bottom", "WCBMKZF,./"),
      ]
    case .klauser:
      [
        row("number", "`1234567890-="),
        row("top", "K,UYPWLMFC[]\\"),
        row("home", "OAEIDRNTHS'"),
        row("bottom", "Q.';ZXVGBJ"),
      ]
    case .oneproduct:
      [
        row("number", "`1234567890-="),
        row("top", "PLDWGJXOYQ[]\\"),
        row("home", "NRSTMUAEIH'"),
        row(
          "bottom", "ZCFVB,.?;K",
          characters: ["zZ", "cC", "fF", "vV", "bB", ",<", ".>", "?/", ";:", "kK"],
          shiftedLabels: ["Z", "C", "F", "V", "B", "<", ">", "/", ":", "K"]
        ),
      ]
    case .pine:
      [
        row("number", "`1234567890-="),
        row("top", "YLRDWJMOU,[]\\"),
        row("home", "CSNTGPHAEI;"),
        row("bottom", "XZQVKBF'/."),
      ]
    case .pineV4:
      [
        row("number", "`1234567890-="),
        row("top", "QLCMK'FUOY[]\\"),
        row("home", "NRSTWPHEAI/"),
        row("bottom", "JXZGVBD;,.")
      ]
    case .three:
      [
        row("number", "`1234567890-="),
        row("top", "QFUYZXKCWB[]\\"),
        row("home", "OHEAIDRTNS/"),
        row("bottom", ",M.J;GLPV'")
      ]
    case .asset:
      [
        row("number", "`1234567890-="),
        row("top", "QWJFGYPUL;[]\\"),
        row("home", "ASETDHNIOR'"),
        row("bottom", "ZXCVBKM,./")
      ]
    case .dwarf:
      [
        row("number", "`1234567890-="),
        row(
          "top", "VLHKJGWOU,[]\\",
          characters: ["vV", "lL", "hH", "kK", "jJ", "gG", "wW", "oO", "uU", ",>", "[{", "]}", "\\|"],
          shiftedLabels: ["V", "L", "H", "K", "J", "G", "W", "O", "U", ">", "{", "}", "|"]
        ),
        row("home", "SRNTMYDAEI/"),
        row(
          "bottom", "XQBFZPC';.",
          characters: ["xX", "qQ", "bB", "fF", "zZ", "pP", "cC", "'\"", ";:", ".<"],
          shiftedLabels: ["X", "Q", "B", "F", "Z", "P", "C", "\"", ":", "<"]
        )
      ]
    case .flaw:
      [
        row("number", "`1234567890-="),
        row("top", "FLAWPZKUR/[]\\"),
        row("home", "HSOYCMTENI;"),
        row("bottom", "BJ'GVQD.X,")
      ]
    case .stndc:
      [
        row(
          "number", "`1234567890()",
          characters: ["`~", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9{", "0}", "([", ")]"],
          shiftedLabels: ["~", "!", "@", "#", "$", "%", "^", "&", "*", "{", "}", "[", "]"]
        ),
        row("top", "VMHGPXLOUYJ=\\"),
        row("home", "STNDCWRAEI-"),
        row(
          "bottom", "ZKBFQ,.'\"?",
          characters: ["zZ", "kK", "bB", "fF", "qQ", ",;", ".:", "'<", "\">", "?!"],
          shiftedLabels: ["Z", "K", "B", "F", "Q", ";", ":", "<", ">", "!"]
        )
      ]
    case .uciea:
      [
        row("number", "`1234567890[]"),
        row("top", "PYUO-KDHFXQ=\\"),
        row(
          "home", "CIEA'GTNSRV",
          characters: ["cC", "iI", "eE", "aA", "'/", "gG", "tT", "nN", "sS", "rR", "vV"],
          shiftedLabels: ["C", "I", "E", "A", "/", "G", "T", "N", "S", "R", "V"]
        ),
        row(
          "bottom", "Z\",.;WMLBJ",
          characters: ["zZ", "\"?", ",<", ".>", ";:", "wW", "mM", "lL", "bB", "jJ"],
          shiftedLabels: ["Z", "?", "<", ">", ":", "W", "M", "L", "B", "J"]
        )
      ]
    case .whorf:
      [
        row("number", "`1234567890-="),
        row("top", "FLHDMVWOU,[]\\"),
        row("home", "SRNTKGYAEI/"),
        row("bottom", "XJBZQPC';.")
      ]
    case .whorf6:
      [
        row("number", "`1234567890-="),
        row("top", "FLHDVZGOU.[]\\"),
        row("home", "SRNTMPYEIA/"),
        row("bottom", "XJBKQCW',;")
      ]
    case .whorfmax:
      [
        row("number", "`1234567890[]"),
        row("top", "FLHYKQWOU,-=\\"),
        row("home", "SRNTPCDAEI/"),
        row("bottom", "XJBVZMG';.")
      ]
    case .octa8:
      [
        row("number", "`1234567890-="),
        row("top", "YOUKXGWDL,[]\\"),
        row("home", "IAENFBSTRC;"),
        row("bottom", "/ZH'QVPMJ.")
      ]
    case .nerps:
      [
        row("number", "`1234567890-="),
        row("top", "XLDPVZKOU;[]\\"),
        row("home", "NRTSGYHEIA/"),
        row("bottom", "JMCWQBF',.")
      ]
    case .gallium:
      [
        row("number", "`1234567890-="),
        row("top", "BLDCVZYOU,[]\\"),
        row("home", "NRTSGPHAEI/"),
        row("bottom", "QXMWJKF';.")
      ]
    case .galliumAngle:
      [
        row("number", "`1234567890-="),
        row("top", "BLDCJZYOU,[]\\"),
        row("home", "NRTSVPHAEI/"),
        row("bottom", "XMWGQKF';.")
      ]
    case .galliumV2:
      [
        row("number", "`1234567890-="),
        row("top", "BLDCVJFOU,[]\\"),
        row("home", "NRTSGYHAEI/"),
        row("bottom", "XQMWZKP';.")
      ]
    case .nila:
      [
        row("number", "`1234567890[]"),
        row("top", "XDLGVJFOU,;=\\"),
        row("home", "RTNSBQHAEI-"),
        row("bottom", "KMCWZPY'/.")
      ]
    case .noctum:
      [
        row("number", "`1234567890-="),
        row("top", "BGDLQJFOU,[]\\"),
        row("home", "NSTRKYCAEI/"),
        row("bottom", "VMHXZPW';.")
      ]
    case .cascade:
      [
        row("number", "`1234567890[]"),
        row("top", "WCDLKJ/UOY;=\\"),
        row(
          "home", "RSTHVBNEAI.",
          characters: ["rR", "sS", "tT", "hH", "vV", "bB", "nN", "eE", "aA", "iI", ".<"],
          shiftedLabels: ["R", "S", "T", "H", "V", "B", "N", "E", "A", "I", "<"]
        ),
        row(
          "bottom", "QZGMXPF',-",
          characters: ["qQ", "zZ", "gG", "mM", "xX", "pP", "fF", "'\"", ",>", "-_"],
          shiftedLabels: ["Q", "Z", "G", "M", "X", "P", "F", "\"", ">", "_"]
        )
      ]
    case .vylet:
      [
        row("number", "`1234567890[]"),
        row("top", "WCMPBXLOUJ-=\\"),
        row(
          "home", "RSTHFYNAEI,",
          characters: ["rR", "sS", "tT", "hH", "fF", "yY", "nN", "aA", "eE", "iI", ",>"],
          shiftedLabels: ["R", "S", "T", "H", "F", "Y", "N", "A", "E", "I", ">"]
        ),
        row(
          "bottom", "QVGDKZ/';.",
          characters: ["qQ", "vV", "gG", "dD", "kK", "zZ", "/?", "'\"", ";:", ".<"],
          shiftedLabels: ["Q", "V", "G", "D", "K", "Z", "?", "\"", ":", "<"]
        )
      ]
    case .romak:
      [
        row("number", "`1234567890-="),
        row("top", "QBMGKXLOU;[]\\"),
        row("home", "DNSTWZRAEI'"),
        row("bottom", "YFCPVJH,./")
      ]
    case .scythe:
      [
        row("number", "`1234567890-="),
        row("top", "BUARJGWDY'[]\\"),
        row("home", "SIONLCMTHE;"),
        row("bottom", "Q,.XZVFPK/")
      ]
    case .inqwerted:
      [
        row("number", "`1234567890-="),
        row("top", "TREWQPOIUY[]\\"),
        row("home", "GFDSA;LKJH'"),
        row("bottom", "BVCXZ/.,MN")
      ]
    case .rain:
      [
        row("number", "`1234567890-="),
        row("top", "FDLGVQRUO,[]\\"),
        row("home", "STHCYJNEAI/"),
        row("bottom", "ZKMPWXB;'.")
      ]
    case .night:
      [
        row("number", "`1234567890=\\"),
        row("top", "BFLKQ'GOU.;[]"),
        row("home", "NSHTMYCAEI/"),
        row("bottom", "VJDRZPWX-,")
      ]
    case .nightSTIC:
      [
        row("number", "`1234567890-="),
        row("top", "BFLDVYPOU/[]\\"),
        row("home", "NSHTMGCAEI-"),
        row("bottom", "QXJKZ'W,;.")
      ]
    case .whix2:
      [
        row(
          "number",
          labels: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "", "", ""],
          characters: ["1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9(", "0)", "", "", ""],
          shiftedLabels: ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", nil, nil, nil]
        ),
        row(
          "top",
          labels: ["B", "L", "N", "D", "K", "'", "F", "O", "U", "J", "", "", ""],
          characters: ["bB", "lL", "nN", "dD", "kK", "'\"", "fF", "oO", "uU", "jJ", "", "", ""],
          shiftedLabels: ["B", "L", "N", "D", "K", "\"", "F", "O", "U", "J", nil, nil, nil]
        ),
        row(
          "home",
          labels: ["S", "H", "R", "T", "W", "Y", "C", "A", "E", "I", ""],
          characters: ["sS", "hH", "rR", "tT", "wW", "yY", "cC", "aA", "eE", "iI", ""],
          shiftedLabels: ["S", "H", "R", "T", "W", "Y", "C", "A", "E", "I", nil]
        ),
        row("bottom", "QXMVZPG,./")
      ]
    case .haruka:
      [
        row("number", "`1234567890-="),
        row("top", "QUOPZVFDLM[]\\"),
        row("home", "IEANBGSTRC'"),
        row("bottom", ",/.H;JYKXW")
      ]
    case .kuntum:
      [
        row("number", "`1234567890-="),
        row("top", "VLNDKJWOU,[]\\"),
        row("home", "TSRHFGCAEI;"),
        row("bottom", "ZXPB'MYQ/.")
      ]
    case .kuntem:
      [
        row("number", "`1234567890-="),
        row("top", "VLNDKJWOUQ[]\\"),
        row("home", "TSRHFGCAIE;"),
        row("bottom", "ZXPB'MY.,/")
      ]
    case .kuntemJQ:
      [
        row("number", "`1234567890-="),
        row("top", "VLNDKQWOUJ[]\\"),
        row("home", "TSRHFGCAIE;"),
        row("bottom", "ZXPB'MY.,/")
      ]
    case .beaklZi:
      [
        row("number", "`1234567890-="),
        row("top", "ZYOU;GDNMX[]\\"),
        row("home", "QHEA.CTRSW'"),
        row("bottom", "J-'K,BPLFV")
      ]
    case .snorkle:
      [
        row("number", "`1234567890-="),
        row("top", ",AYCVQDLUX[]\\"),
        row("home", "IONSBPTHER;"),
        row("bottom", ".'FGJKWM;Z")
      ]
    case .maltron:
      [
        row("number", "`1234567890-="),
        row("top", "QPYCBVMUZL[]\\"),
        row("home", "ANISFDTHOR'"),
        row("bottom", ",.JG'/WK-X")
      ]
    case .prsten:
      [
        row("number", "`1234567890-="),
        row("top", "`WCDFQLUY;[]\\"),
        row("home", "PRSTGMNAIO'"),
        row("bottom", "XHVB[,JKZ.")
      ]
    case .rsthd:
      [
        row("number", "`1234567890-="),
        row("top", "JCYFKZL,UQ[]\\"),
        row("home", "RSTHDMNAIO'"),
        row("bottom", "/VGPBXW.;-")
      ]
    case .handsDownPromethium:
      [
        row("number", "`1234567890-="),
        row("top", "FPDLX;UOYBZ]\\"),
        row("home", "SNTHK,AEICQ"),
        row("bottom", "VWGMJ-.'=/")
      ]
    case .statica3x5:
      [
        layeredRow(
          "number", labels: ["\"", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
          shiftedLabels: ["'", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "top", labels: ["ь", "у", "а", "ж", "ю", "г", "б", "р", "л", "х", ",", ".", "\\"],
          shiftedLabels: ["Ь", "У", "А", "Ж", "Ю", "Г", "Б", "Р", "Л", "Х", ";", ":", "|"],
          optionLabels: ["ъ", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
          shiftedOptionLabels: ["Ъ", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
        ),
        layeredRow(
          "home", labels: ["и", "е", "о", "к", "я", "м", "т", "с", "н", "з", "."],
          shiftedLabels: ["И", "Е", "О", "К", "Я", "М", "Т", "С", "Н", "З", ":"],
          optionLabels: [nil, "ё", nil, nil, nil, nil, nil, nil, nil, nil, nil],
          shiftedOptionLabels: [nil, "Ё", nil, nil, nil, nil, nil, nil, nil, nil, nil]
        ),
        layeredRow(
          "bottom", labels: ["ф", "э", "ы", "п", "й", "д", "в", "ч", "ш", "ц"],
          shiftedLabels: ["Ф", "Э", "Ы", "П", "Й", "Д", "В", "Ч", "Ш", "Ц"],
          optionLabels: [nil, nil, nil, nil, nil, nil, nil, nil, "щ", nil],
          shiftedOptionLabels: [nil, nil, nil, nil, nil, nil, nil, nil, "Щ", nil]
        ),
      ]
    case .vestnik:
      [
        layeredRow(
          "number", labels: ["\"", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
          shiftedLabels: ["'", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "top", labels: ["ц", "д", "р", "г", "х", "ф", "п", "а", "я", "э", ",", ".", "\\"],
          shiftedLabels: ["Ц", "Д", "Р", "Г", "Х", "Ф", "П", "А", "Я", "Э", ";", ":", "|"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "home", labels: ["с", "т", "н", "к", "б", "ь", "в", "о", "е", "и", "."],
          shiftedLabels: ["С", "Т", "Н", "К", "Б", "Ь", "В", "О", "Е", "И", ":"],
          optionLabels: [nil, nil, nil, nil, nil, "ъ", nil, nil, "ё", nil, nil],
          shiftedOptionLabels: [nil, nil, nil, nil, nil, "Ъ", nil, nil, "Ё", nil, nil]
        ),
        layeredRow(
          "bottom", labels: ["ш", "з", "л", "м", "ч", "ж", "й", "ы", "у", "ю"],
          shiftedLabels: ["Ш", "З", "Л", "М", "Ч", "Ж", "Й", "Ы", "У", "Ю"],
          optionLabels: ["щ", nil, nil, nil, nil, nil, nil, nil, nil, nil],
          shiftedOptionLabels: ["Щ", nil, nil, nil, nil, nil, nil, nil, nil, nil]
        ),
      ]
    case .diktor:
      [
        layeredRow(
          "number", labels: ["ё", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "*", "="],
          shiftedLabels: ["Ё", "Ъ", "Ь", "№", "%", ":", ";", "-", "\"", "(", ")", "_", "+"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "top", labels: ["ц", "ь", "я", ",", ".", "з", "в", "к", "д", "ч", "ш", "щ", "\\"],
          shiftedLabels: ["Ц", "ъ", "Я", "?", "!", "З", "В", "К", "Д", "Ч", "Ш", "Щ", "/"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "home", labels: ["у", "и", "е", "о", "а", "л", "н", "т", "с", "р", "й"],
          shiftedLabels: ["У", "И", "Е", "О", "А", "Л", "Н", "Т", "С", "Р", "Й"],
          optionLabels: Array(repeating: nil, count: 11),
          shiftedOptionLabels: Array(repeating: nil, count: 11)
        ),
        layeredRow(
          "bottom", labels: ["ф", "э", "х", "ы", "ю", "б", "м", "п", "г", "ж"],
          shiftedLabels: ["Ф", "Э", "Х", "Ы", "Ю", "Б", "М", "П", "Г", "Ж"],
          optionLabels: Array(repeating: nil, count: 10),
          shiftedOptionLabels: Array(repeating: nil, count: 10)
        ),
      ]
    case .diktorVoronovMod:
      [
        layeredRow(
          "number", labels: ["ё", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "*", "="],
          shiftedLabels: ["Ё", "%", "№", "\"", ".", ":", ";", "-", ",", "(", ")", "_", "+"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "top", labels: ["ф", "ь", "х", "я", "ы", "з", "в", "к", "д", "ч", "ш", "щ", "\\"],
          shiftedLabels: ["Ф", "Ь", "Х", "Я", "Ы", "З", "В", "К", "Д", "Ч", "Ш", "Щ", "/"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "home", labels: ["у", "и", "е", "о", "а", "л", "н", "т", "с", "р", "й"],
          shiftedLabels: ["У", "И", "Е", "О", "А", "Л", "Н", "Т", "С", "Р", "Й"],
          optionLabels: Array(repeating: nil, count: 11),
          shiftedOptionLabels: Array(repeating: nil, count: 11)
        ),
        layeredRow(
          "bottom", labels: ["?", "ъ", "э", "ю", "ц", "б", "м", "п", "г", "ж"],
          shiftedLabels: ["!", "Ъ", "Э", "Ю", "Ц", "Б", "М", "П", "Г", "Ж"],
          optionLabels: Array(repeating: nil, count: 10),
          shiftedOptionLabels: Array(repeating: nil, count: 10)
        ),
      ]
    case .redaktor:
      [
        layeredRow(
          "number", labels: ["ё", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "Ъ", "="],
          shiftedLabels: ["Ё", "№", ":", ";", "/", "₽", "@", "ё", "?", "!", "%", "Ь", "+"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "top", labels: ["ц", "ы", "я", "й", "ь", "з", "д", "в", "к", "г", "ш", "щ", "\\"],
          shiftedLabels: ["Ц", "Ы", "Я", "Й", "ъ", "З", "Д", "В", "К", "Г", "Ш", "Щ", "/"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "home", labels: ["у", "и", "о", "е", "а", "л", "р", "т", "н", "с", "х"],
          shiftedLabels: ["У", "И", "О", "Е", "А", "Л", "Р", "Т", "Н", "С", "Х"],
          optionLabels: Array(repeating: nil, count: 11),
          shiftedOptionLabels: Array(repeating: nil, count: 11)
        ),
        layeredRow(
          "bottom", labels: ["ф", "ю", "э", ",", ".", "ч", "м", "п", "б", "ж"],
          shiftedLabels: ["Ф", "Ю", "Э", "-", "\"", "Ч", "М", "П", "Б", "Ж"],
          optionLabels: Array(repeating: nil, count: 10),
          shiftedOptionLabels: Array(repeating: nil, count: 10)
        ),
      ]
    case .juiyaf:
      [
        layeredRow(
          "number", labels: ["ё", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
          shiftedLabels: ["Ё", "!", "\"", "№", ";", "%", ":", "?", "*", "(", ")", "_", "+"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "top", labels: ["й", "у", "и", "я", "ф", "х", "ж", "р", ".", "ш", "ц", "Ь", "\\"],
          shiftedLabels: ["Й", "У", "И", "Я", "Ф", "Х", "Ж", "Р", ",", "Ш", "Ц", "Ъ", "/"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "home", labels: ["в", "е", "а", "о", "ч", "г", "т", "н", "с", "д", "б"],
          shiftedLabels: ["В", "Е", "А", "О", "Ч", "Г", "Т", "Н", "С", "Д", "Б"],
          optionLabels: Array(repeating: nil, count: 11),
          shiftedOptionLabels: Array(repeating: nil, count: 11)
        ),
        layeredRow(
          "bottom", labels: ["ь", "э", "ю", "ы", "щ", "п", "к", "л", "з", "м"],
          shiftedLabels: ["ъ", "Э", "Ю", "Ы", "Щ", "П", "К", "Л", "З", "М"],
          optionLabels: Array(repeating: nil, count: 10),
          shiftedOptionLabels: Array(repeating: nil, count: 10)
        ),
      ]
    case .zubachev:
      [
        layeredRow(
          "number", labels: ["ё", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
          shiftedLabels: ["Ё", "!", "\"", "№", ";", "%", ":", "?", "*", "(", ")", "_", "+"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "top", labels: ["ф", "ы", "а", "я", ",", "й", "м", "р", "п", "х", "ц", "щ", "\\"],
          shiftedLabels: ["Ф", "Ы", "А", "Я", "Ъ", "Й", "М", "Р", "П", "Х", "Ц", "Щ", "/"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "home", labels: ["г", "и", "е", "о", "у", "л", "т", "с", "н", "з", "ж"],
          shiftedLabels: ["Г", "И", "Е", "О", "У", "Л", "Т", "С", "Н", "З", "Ж"],
          optionLabels: Array(repeating: nil, count: 11),
          shiftedOptionLabels: Array(repeating: nil, count: 11)
        ),
        layeredRow(
          "bottom", labels: ["ш", "ь", "ю", ".", "э", "б", "д", "в", "к", "ч"],
          shiftedLabels: ["Ш", "ъ", "Ю", "Ь", "Э", "Б", "Д", "В", "К", "Ч"],
          optionLabels: Array(repeating: nil, count: 10),
          shiftedOptionLabels: Array(repeating: nil, count: 10)
        ),
      ]
    case .colemakQix:
      [
        layeredRow(
          "number", labels: ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "=", "["],
          shiftedLabels: ["~", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "+", "{"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "top", labels: [";", "l", "c", "m", "k", "j", "f", "u", "y", "q", "-", "]", "\\"],
          shiftedLabels: [":", "L", "C", "M", "K", "J", "F", "U", "Y", "Q", "_", "}", "|"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "home", labels: ["a", "r", "s", "t", "g", "p", "n", "e", "i", "o", "'"],
          shiftedLabels: ["A", "R", "S", "T", "G", "P", "N", "E", "I", "O", "\""],
          optionLabels: Array(repeating: nil, count: 11),
          shiftedOptionLabels: Array(repeating: nil, count: 11)
        ),
        layeredRow(
          "bottom", labels: ["x", "w", "d", "v", "z", "b", "h", "/", ".", ","],
          shiftedLabels: ["X", "W", "D", "V", "Z", "B", "H", "?", ">", "<"],
          optionLabels: Array(repeating: nil, count: 10),
          shiftedOptionLabels: Array(repeating: nil, count: 10)
        ),
      ]
    case .colemakQi:
      [
        layeredRow(
          "number", labels: ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "=", "["],
          shiftedLabels: ["~", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "+", "{"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "top", labels: ["q", "l", "w", "m", "k", "j", "f", "u", "y", "'", "-", "]", "\\"],
          shiftedLabels: ["Q", "L", "W", "M", "K", "J", "F", "U", "Y", "\"", "_", "}", "|"],
          optionLabels: Array(repeating: nil, count: 13),
          shiftedOptionLabels: Array(repeating: nil, count: 13)
        ),
        layeredRow(
          "home", labels: ["a", "r", "s", "t", "g", "p", "n", "e", "i", "o", ";"],
          shiftedLabels: ["A", "R", "S", "T", "G", "P", "N", "E", "I", "O", ":"],
          optionLabels: Array(repeating: nil, count: 11),
          shiftedOptionLabels: Array(repeating: nil, count: 11)
        ),
        layeredRow(
          "bottom", labels: ["z", "x", "c", "d", "v", "b", "h", ",", ".", "/"],
          shiftedLabels: ["Z", "X", "C", "D", "V", "B", "H", "<", ">", "?"],
          optionLabels: Array(repeating: nil, count: 10),
          shiftedOptionLabels: Array(repeating: nil, count: 10)
        ),
      ]
    case .colemaQ:
      baseShiftRows(
        normal: ["`1234567890=[", ";wfpbjluyq-]\\", "arstgmneio'", "xcdkzvh/.,"],
        shifted: ["~!@#$%^&*()+{", ":WFPBJLUYQ_}|", "ARSTGMNEIO\"", "XCDKZVH?><"]
      )
    case .colemaQF:
      baseShiftRows(
        normal: ["`1234567890=[", ";wgpbjluyq-]\\", "arstfmneio'", "xcdkzvh/.,"],
        shifted: ["~!@#$%^&*()+{", ":WGPBJLUYQ_}|", "ARSTFMNEIO\"", "XCDKZVH?><"]
      )
    case .thaiManoonchai:
      baseShiftRows(
        normalLabels: [
          ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
          ["ใ", "ต", "ห", "ล", "ส", "ป", "ั", "ก", "ิ", "บ", "็", "ฬ", "ฯ"],
          ["ง", "เ", "ร", "น", "ม", "อ", "า", "่", "้", "ว", "ื"],
          ["ุ", "ไ", "ท", "ย", "จ", "ค", "ี", "ด", "ะ", "ู"],
        ],
        shiftedLabels: [
          ["~", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+"],
          ["ฒ", "ฏ", "ซ", "ญ", "ฟ", "ฉ", "ึ", "ธ", "ฐ", "ฎ", "ฆ", "ฑ", "ฌ"],
          ["ษ", "ถ", "แ", "ช", "พ", "ผ", "ำ", "ข", "โ", "ภ", "\""],
          ["ฤ", "ฝ", "ๆ", "ณ", "๊", "๋", "์", "ศ", "ฮ", "?"],
        ]
      )
    case .brasileiroNativo:
      baseShiftRows(
        normal: ["=1234567890[]", "/,.hxwltcp~-", "ieaoumdsrn´'", ";yçjbkqvgfz"],
        shifted: ["+!@#$%¨&*(){}", "?<>HXWLTCP^_", "IEAOUMDSRN`\"", ":YÇJBKQVGFZ"]
      )
    case .beakl15:
      baseShiftRows(
        normal: ["`1234567890-=", "qhouxgcrfz[]\\", "yiea.dstnb;", "j/,k'wmlpv"],
        shifted: ["~!@#$%^&*()_+", "QHOUXGCRFZ{}|", "YIEA>DSTNB:", "J?<K\"WMLPV"]
      )
    case .beakl19:
      baseShiftRows(
        normal: ["`1234567890-=", "q.oujwdnm,[]\\", "haeikgsrtp;", "z'/yxbclfv"],
        shifted: ["~!@#$%^&*()_+", "Q>OUJWDNM<{}|", "HAEIKGSRTP:", "Z\"?YXBCLFV"]
      )
    case .beakl19Bis:
      baseShiftRows(
        normal: ["`1234567890-=", "qyouzwdnck[]\\", "hiea,gtrsp;", "j'/.xvmlfb"],
        shifted: ["~!@#$%^&*()_+", "QYOUZWDNCK{}|", "HIEA<GTRSP:", "J\"?>XVMLFB"]
      )
    case .rolll:
      baseShiftRows(
        normal: ["`1234567890-=", "youwbxkclv[]\\", "iaenpdhsrt'", "j/,.qfmg'z"],
        shifted: ["~!@#$%^&*()_+", "YOUWBXKCLV{}|", "IAENPDHSRT\"", "J?<>QFMG\"Z"]
      )
    case .whorfmaxOrtho:
      baseShiftRows(
        normal: ["`1234567890[]", "flhyzqwou,-=\\", "srntpcdaei/", "xjbvkmg';."],
        shifted: ["~!@#$%^&*(){}", "FLHYZQWOU<_+|", "SRNTPCDAEI?", "XJBVKMG\":>"]
      )
    case .neo:
      baseShiftRows(
        normal: ["^1234567890-`", "xvlcwkhgfqß'", "uiaeosnrtdy ", " üöäpzbm,.j"],
        shifted: ["ˇ°§ℓ»«$€„“”—¸", "XVLCWKHGFQẞ~", "UIAEOSNRTDY ", " ÜÖÄPZBM–•J"]
      )
    case .bone:
      baseShiftRows(
        normal: ["^1234567890-`", "jduaxphlmwß'", "ctieobnrsgq ", " fvüäöyz,.k"],
        shifted: ["ˇ°§ℓ»«$€„“”—¸", "JDUAXPHLMWẞ~", "CTIEOBNRSGQ ", " FVÜÄÖYZ–•K"]
      )
    case .adnw:
      baseShiftRows(
        normal: ["^1234567890-`", "kuü.ävgcljf'", "hieaodtrnsß ", " xyö,qbpwmz"],
        shifted: ["ˇ°§ℓ»«$€„“”—¸", "KUÜ•ÄVGCLJF~", "HIEAODTRNSẞ ", " XYÖ–QBPWMZ"]
      )
    case .mine:
      baseShiftRows(
        normal: ["^1234567890-`", "jluaqwbdgyzß", "crieomntsh '", " vxüäöpf,.k"],
        shifted: ["ˇ°§ℓ»«$€„“”—¸", "JLUAQWBDGYZẞ", "CRIEOMNTSH ~", " VXÜÄÖPF–•K"]
      )
    case .noted:
      baseShiftRows(
        normal: ["^1234567890-`", "zyuaqpbmlfjß", "csieodtnrh '", " vxüäöwg,.k"],
        shifted: ["ˇ°§ℓ»«$€„“”—¸", "ZYUAQPBMLFJẞ", "CSIEODTNRH ~", " VXÜÄÖWG–•K"]
      )
    case .koy:
      baseShiftRows(
        normal: ["^1234567890-`", "k.o,yvgclßz'", "haeiudtrnsf ", " xqäüöbpwmj"],
        shifted: ["ˇ°§ℓ»«$€„“”—¸", "K•O–YVGCLẞZ~", "HAEIUDTRNSF ", " XQÄÜÖBPWMJ"]
      )
    case .real:
      [
        row("number", "`1234567890[]"),
        row("top", "YLUO.ZFHCW/=\\"),
        row("home", "IREA,DTNSM-"),
        row("bottom", ";J'QXPKBGV"),
      ]
    case .sertain:
      [
        row("number", "`1234567890-="),
        row("top", "XLDKVZWOU;[]\\"),
        row("home", "SRTNFGYEIA/"),
        row("bottom", "QJMHBPC',."),
      ]
    case .ctgap:
      [
        row("number", "`1234567890-="),
        row("top", "QPLCJXFOU/[]\\"),
        row("home", "RNTSGYHEIA;"),
        row("bottom", "ZBMWVKD',."),
      ]
    case .graphite:
      [
        row("number", "`1234567890[]"),
        row(
          "top", "BLDWZ'FOUJ;=\\",
          characters: ["bB", "lL", "dD", "wW", "zZ", "'_", "fF", "oO", "uU", "jJ", ";:", "=+", "\\|"],
          shiftedLabels: ["B", "L", "D", "W", "Z", "_", "F", "O", "U", "J", ":", "+", "|"]
        ),
        row(
          "home", "NRTSGYHAEI,",
          characters: ["nN", "rR", "tT", "sS", "gG", "yY", "hH", "aA", "eE", "iI", ",?"],
          shiftedLabels: ["N", "R", "T", "S", "G", "Y", "H", "A", "E", "I", "?"]
        ),
        row(
          "bottom", "QXMCVKP.-/",
          characters: ["qQ", "xX", "mM", "cC", "vV", "kK", "pP", ".>", "-\"", "/<"],
          shiftedLabels: ["Q", "X", "M", "C", "V", "K", "P", ">", "\"", "<"]
        ),
      ]
    case .focal:
      [
        row("number", "`1234567890-="),
        row("top", "VLHGKQFOUJ[]\\"),
        row("home", "SRNTBYCAEI/"),
        row("bottom", "ZXMDP'W.;,"),
      ]
    case .zenith:
      [
        row("number", "`1234567890-="),
        row("top", "FOURZWVJLD[]\\"),
        row("home", "YAINCGSEHT/"),
        row("bottom", "'.,BXMPQK;"),
      ]
    case .dhorf:
      [
        row("number", "`1234567890-="),
        row("top", "VLHKQJFOU,[]\\"),
        row("home", "SRNTWYCAEI/"),
        row("bottom", "ZXMDBPG';."),
      ]
    case .gust:
      [
        row("number", "`1234567890[]"),
        row("top", ";UOFJQKLRV/=\\"),
        row("home", "EIACYDHTNS-"),
        row("bottom", ",.PG'BMWXZ"),
      ]
    case .recurva:
      [
        row("number", "`1234567890-="),
        row("top", "FRDPVQJUOY[]\\"),
        row("home", "SNTCB.HEAI/"),
        row("bottom", "ZXKGWML;',"),
      ]
    case .ansiColemak:
      [
        row("number", "1234567890-="),
        row("top", "QWFPGJLUY;[]"),
        row("home", "ARSTDHNEIO'"),
        row("bottom", "ZXCVBKM,./"),
      ]
    case .ansiColemakAngle:
      [
        row("number", "1234567890-="),
        row("top", "QWFPGJLUY;[]"),
        row("home", "ARSTDHNEIO'"),
        row("bottom", "XCVBZKM,./"),
      ]
    case .ansiColemakWide:
      [
        row("number", "123456=7890-"),
        row("top", "QWFPG[JLUY;'\\"),
        row("home", "ARSTD]HNEIO"),
        row("bottom", "ZXCVB/KM,."),
      ]
    case .ansiColemakDH:
      [
        row("number", "1234567890-="),
        row("top", "QWFPBJLUY;[]"),
        row("home", "ARSTGMNEIO'"),
        row("bottom", "XCDVZKH,./"),
      ]
    case .ansiColemakDHV:
      [
        row("number", "1234567890=["),
        row("top", "QWCPBJLUY;-]\\"),
        row("home", "ARSTGMNEIO'"),
        row("bottom", "ZXFDKVH/.,"),
      ]
    case .colemakDHISO:
      [
        row("number", "1234567890-="),
        row("top", "QWFPBJLUY;[]"),
        row("home", "ARSTGMNEIO'"),
        row("bottom", "ZXCDV`KH,./"),
      ]
    case .colemakDHMatrix:
      [
        row("number", "1234567890-="),
        row("top", "QWFPBJLUY;[]"),
        row("home", "ARSTGMNEIO'"),
        row("bottom", "ZXCDVKH,./"),
      ]
    case .colemakDHWideANSI:
      [
        row("number", "123456=7890-"),
        row("top", "QWFPB[JLUY;'\\"),
        row("home", "ARSTG]MNEIO"),
        row("bottom", "XCDVZ/KH,."),
      ]
    case .colemakDHWideISO:
      [
        row("number", "123456=7890-"),
        row("top", "QWFPB[JLUY;/"),
        row("home", "ARSTG]MNEIO'"),
        row("bottom", "ZXCDV\\#KH,."),
      ]
    case .colemakDHKANSI:
      [
        row("number", "1234567890-="),
        row("top", "QWFPBJLUY;[]"),
        row("home", "ARSTGKNEIO'"),
        row("bottom", "XCDVZMH,./"),
      ]
    case .colemakDHKISO:
      [
        row("number", "1234567890-="),
        row("top", "QWFPBJLUY;[]"),
        row("home", "ARSTGKNEIO'"),
        row("bottom", "ZXCDV`MH,./"),
      ]
    case .ansiNorman:
      [
        row("number", "1234567890-="),
        row("top", "QWDFKJURL;[]"),
        row("home", "ASETGYNIOH'"),
        row("bottom", "ZXCVBPM,./"),
      ]
    case .ansiWorkman:
      [
        row("number", "1234567890-="),
        row("top", "QDRWBJFUP;[]"),
        row("home", "ASHTGYNEOI'"),
        row("bottom", "ZXMCVKL,./"),
      ]
    case .programmerWorkman:
      [
        row(
          "number", "!@#$%^&*()-=",
          characters: ["!1", "@2", "#3", "$4", "%5", "^6", "&7", "*8", "(9", ")0", "-_", "=+"],
          shiftedLabels: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "_", "+"]
        ),
        row(
          "top", "QDRWBJFUP;{}\\",
          characters: ["qQ", "dD", "rR", "wW", "bB", "jJ", "fF", "uU", "pP", ";:", "{[", "}]", "\\|"],
          shiftedLabels: ["Q", "D", "R", "W", "B", "J", "F", "U", "P", ":", "[", "]", "|"]
        ),
        row("home", "ASHTGYNEOI'"),
        row("bottom", "ZXMCVKL,./"),
      ]
    case .mtgapASRT:
      [
        row("number", "1234567890-="),
        row("top", "QWLDBJFUKP[]"),
        row("home", "ASRTGHNEOI/"),
        row("bottom", "ZXCV;YM,.'"),
      ]
    case .halmak:
      [
        row(
          "number", "1234567890-=",
          characters: ["1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9<", "0>", "-_", "=+"],
          shiftedLabels: ["!", "@", "#", "$", "%", "^", "&", "*", "<", ">", "_", "+"]
        ),
        row("top", "WLRBZ;QUDJ[]"),
        row(
          "home", "SHNT,.AEOI'",
          characters: ["sS", "hH", "nN", "tT", ",(", ".)", "aA", "eE", "oO", "iI", "'\""],
          shiftedLabels: ["S", "H", "N", "T", "(", ")", "A", "E", "O", "I", "\""]
        ),
        row("bottom", "FMVC/GPXKY"),
      ]
    case .qgmlwb:
      [
        row("number", "1234567890-="),
        row("top", "QGMLWBYUV;[]"),
        row("home", "DSTNRIAEOH'"),
        row("bottom", "ZXCFJKP,./"),
      ]
    case .qgmlwy:
      [
        row("number", "1234567890-="),
        row("top", "QGMLWYFUB;[]"),
        row("home", "DSTNRIAEOH'"),
        row("bottom", "ZXCVJKP,./"),
      ]
    case .qwpr:
      [
        row("number", "1234567890-="),
        row("top", "QWPRFYUKL;[]"),
        row("home", "ASDTGHNIOE'"),
        row("bottom", "ZXCVBJM,./"),
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
    case .brazilianABNT2:
      [
        layeredRow(
          "number", labels: ["'", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
          shiftedLabels: ["\"", "!", "@", "#", "$", "%", "¨", "&", "*", "(", ")", "_", "+"],
          optionLabels: ["`", "¹", "²", "³", "£", "¢", "¬", "¶", "•", "∑", "º", "–", "§"],
          shiftedOptionLabels: ["’", "¡", "½", "¾", "¼", "⅜", "¨", "⅞", "×", "·", "°", "—", "±"]
        ),
        layeredRow(
          "top", labels: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "´", "[", "]"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "`", "{", "}"],
          optionLabels: ["/", "?", "€", "®", "ŧ", "←", "↓", "→", "ø", "þ", "´", "ª", "º"],
          shiftedOptionLabels: ["\\", "¿", "€", "®", "Ŧ", "¥", "↑", "ı", "Ø", "Þ", "`", "ª", "º"]
        ),
        layeredRow(
          "home", labels: ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ç", "~"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ç", "^"],
          optionLabels: ["æ", "ß", "ð", "đ", "∆", "ħ", "ʝ", "ĸ", "ł", "·", "~"],
          shiftedOptionLabels: ["Æ", "§", "Ð", "◊", "˝", "Ħ", "&", "", "Ł", "ő", "^"]
        ),
        layeredRow(
          "bottom", labels: ["\\", "z", "x", "c", "v", "b", "n", "m", ",", ".", ";", "/"],
          shiftedLabels: ["|", "Z", "X", "C", "V", "B", "N", "M", "<", ">", ":", "?"],
          optionLabels: ["∏", "Ω", "≈", "₢", "ʋ", "∫", "ŋ", "µ", "≤", "≥", "…", "°"],
          shiftedOptionLabels: ["ă", "<", ">", "©", "Ʋ", "™", "Ŋ", "µ", "«", "»", "…", "¿"]
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
    case .turkishE:
      [
        row(
          "number", "*1234567890/-",
          characters: ["*+", "1!", "2\"", "3^", "4$", "5%", "6&", "7'", "8(", "9)", "0=", "/?", "-_"],
          shiftedLabels: ["+", "!", "\"", "^", "$", "%", "&", "'", "(", ")", "=", "?", "_"]
        ),
        row(
          "top", "QJÜOFCTMKBSP",
          characters: ["qQ", "jJ", "üÜ", "oO", "fF", "cC", "tT", "mM", "kK", "bB", "sS", "pP"]
        ),
        row(
          "home", "EAİIGĞLNRDV,",
          characters: ["eE", "aA", "iİ", "ıI", "gG", "ğĞ", "lL", "nN", "rR", "dD", "vV", ",;"],
          shiftedLabels: ["E", "A", "İ", "I", "G", "Ğ", "L", "N", "R", "D", "V", ";"]
        ),
        row(
          "bottom", "<XWÖUHZÇYŞ.",
          characters: ["<>", "xX", "wW", "öÖ", "uU", "hH", "zZ", "çÇ", "yY", "şŞ", ".:"],
          shiftedLabels: [">", "X", "W", "Ö", "U", "H", "Z", "Ç", "Y", "Ş", ":"]
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
    case .belarusian:
      [
        row(
          "number", "Ё1234567890-=",
          characters: ["ёЁ", "1!", "2\"", "3№", "4;", "5%", "6:", "7?", "8*", "9(", "0)", "-_", "=+"],
          shiftedLabels: ["Ё", "!", "\"", "№", ";", "%", ":", "?", "*", "(", ")", "_", "+"]
        ),
        row(
          "top", "ЙЦУКЕНГШЎЗХ'",
          characters: ["йЙ", "цЦ", "уУ", "кК", "еЕ", "нН", "гГ", "шШ", "ўЎ", "зЗ", "хХ", "''"],
          shiftedLabels: ["Й", "Ц", "У", "К", "Е", "Н", "Г", "Ш", "Ў", "З", "Х", "'"]
        ),
        row(
          "home", "ФЫВАПРОЛДЖЭ\\",
          characters: ["фФ", "ыЫ", "вВ", "аА", "пП", "рР", "оО", "лЛ", "дД", "жЖ", "эЭ", "\\/"],
          shiftedLabels: ["Ф", "Ы", "В", "А", "П", "Р", "О", "Л", "Д", "Ж", "Э", "/"]
        ),
        row(
          "bottom", "<ЯЧСМІТЬБЮ.",
          characters: ["<>", "яЯ", "чЧ", "сС", "мМ", "іІ", "тТ", "ьЬ", "бБ", "юЮ", ".,"],
          shiftedLabels: [">", "Я", "Ч", "С", "М", "І", "Т", "Ь", "Б", "Ю", ","]
        ),
      ]
    case .macedonian:
      [
        row(
          "number", "Ѝ1234567890-=",
          characters: ["ѝЍ", "1!", "2„", "3“", "4'", "5%", "6‚", "7‘", "8*", "9(", "0)", "--", "=+"],
          shiftedLabels: ["Ѝ", "!", "„", "“", "'", "%", "‚", "‘", "*", "(", ")", "-", "+"]
        ),
        row(
          "top", "ЉЊЕРТЅУИОПШЃЖ",
          characters: ["љЉ", "њЊ", "еЕ", "рР", "тТ", "ѕЅ", "уУ", "иИ", "оО", "пП", "шШ", "ѓЃ", "жЖ"],
          shiftedLabels: ["Љ", "Њ", "Е", "Р", "Т", "Ѕ", "У", "И", "О", "П", "Ш", "Ѓ", "Ж"]
        ),
        row(
          "home", "АСДФГХЈКЛЧЌ",
          characters: ["аА", "сС", "дД", "фФ", "гГ", "хХ", "јЈ", "кК", "лЛ", "чЧ", "ќЌ"],
          shiftedLabels: ["А", "С", "Д", "Ф", "Г", "Х", "Ј", "К", "Л", "Ч", "Ќ"]
        ),
        row(
          "bottom", "ЀЗЏЦВБНМ,./",
          characters: ["ѐЀ", "зЗ", "џЏ", "цЦ", "вВ", "бБ", "нН", "мМ", ",;", ".:", "//"],
          shiftedLabels: ["Ѐ", "З", "Џ", "Ц", "В", "Б", "Н", "М", ";", ":", "/"]
        ),
      ]
    case .pashto:
      [
        row(
          "number", labels: ["ZWJ", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹", "۰", "-", "="],
          characters: ["\u{200D}\u{0654}", "۱!", "۲٬", "۳٫", "۴؋", "۵٪", "۶×", "۷»", "۸«", "۹)", "۰(", "-ـ", "=+"],
          shiftedLabels: ["ٔ", "!", "٬", "٫", "؋", "٪", "×", "»", "«", ")", "(", "ـ", "+"]
        ),
        row(
          "top", "ضصثقفغعهخحجچ\\",
          characters: ["ضْ", "صٌ", "ثٍ", "قً", "فُ", "غِ", "عَ", "هّ", "خځ", "حڅ", "ج]", "چ[", "\\*"],
          shiftedLabels: ["ْ", "ٌ", "ٍ", "ً", "ُ", "ِ", "َ", "ّ", "ځ", "څ", "]", "[", "*"]
        ),
        row(
          "home", "شسیبلاتنمکګ",
          characters: ["شښ", "سۍ", "یي", "بپ", "لأ", "اآ", "تټ", "نڼ", "مة", "ک:", "ګ؛"],
          shiftedLabels: ["ښ", "ۍ", "ي", "پ", "أ", "آ", "ټ", "ڼ", "ة", ":", "؛"]
        ),
        row(
          "bottom", "ئېزردړوږ/",
          characters: ["ئظ", "ېط", "زژ", "رء", "ذ\u{200C}", "دډ", "ړؤ", "و،", "ږ.", "/؟"],
          shiftedLabels: ["ظ", "ط", "ژ", "ء", "ZWNJ", "ډ", "ؤ", "،", ".", "؟"]
        ),
      ]
    case .estonian:
      [
        row(
          "number", "ˇ1234567890+´",
          characters: ["ˇ~", "1!", "2\"", "3#", "4¤", "5%", "6&", "7/", "8(", "9)", "0=", "+?", "´`"],
          shiftedLabels: ["~", "!", "\"", "#", "¤", "%", "&", "/", "(", ")", "=", "?", "`"]
        ),
        row(
          "top", "QWERTYUIOPÜÕ'",
          characters: ["qQ", "wW", "eE", "rR", "tT", "yY", "uU", "iI", "oO", "pP", "üÜ", "õÕ", "'*"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "Ü", "Õ", "*"]
        ),
        row(
          "home", "ASDFGHJKLÖÄ",
          characters: ["aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", "öÖ", "äÄ"],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", "Ö", "Ä"]
        ),
        row(
          "bottom", "<ZXCVBNM,.-",
          characters: ["<>", "zZ", "xX", "cC", "vV", "bB", "nN", "mM", ",;", ".:", "-_"],
          shiftedLabels: [">", "Z", "X", "C", "V", "B", "N", "M", ";", ":", "_"]
        ),
      ]
    case .persianStandard:
      [
        row(
          "number", labels: ["ZWJ", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹", "۰", "-", "="],
          characters: ["\u{200D}", "۱!", "۲٬", "۳٫", "۴﷼", "۵٪", "۶×", "۷،", "۸*", "۹)", "۰(", "-ـ", "=+"],
          shiftedLabels: ["ZWJ", "!", "٬", "٫", "﷼", "٪", "×", "،", "*", ")", "(", "ـ", "+"]
        ),
        row(
          "top", "ضصثقفغعهخحجچ\\",
          characters: ["ضْ", "صٌ", "ثٍ", "قً", "فُ", "غِ", "عَ", "هّ", "خ]", "ح[", "ج}", "چ{", "\\|"],
          shiftedLabels: ["ْ", "ٌ", "ٍ", "ً", "ُ", "ِ", "َ", "ّ", "]", "[", "}", "{", "|"]
        ),
        row(
          "home", "شسیبلاتنمکگ",
          characters: ["شؤ", "سئ", "یي", "بإ", "لأ", "اآ", "تة", "ن»", "م«", "ک:", "گ؛"],
          shiftedLabels: ["ؤ", "ئ", "ي", "إ", "أ", "آ", "ة", "»", "«", ":", "؛"]
        ),
        row(
          "bottom", "\\ظطزرذدپو./",
          characters: ["\\|", "ظك", "طط", "زژ", "رٰ", "ذ\u{200C}", "د\u{0654}", "پء", "و>", ".<", "/؟"],
          shiftedLabels: ["|", "ك", "ط", "ژ", "ٰ", "ZWNJ", "ٔ", "ء", ">", "<", "؟"]
        ),
      ]
    case .persianFarsi:
      [
        row(
          "number", "÷1234567890-=",
          characters: ["÷×", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9)", "0(", "-_", "=+"],
          shiftedLabels: ["×", "!", "@", "#", "$", "%", "^", "&", "*", ")", "(", "_", "+"]
        ),
        row(
          "top", "ضصثقفغعهخحجچپ",
          characters: ["ضً", "صٌ", "ثٍ", "قریال", "ف،", "غ؛", "ع,", "ه]", "خ[", "ح\\", "ج}", "چ{", "پ|"],
          shiftedLabels: ["ً", "ٌ", "ٍ", "ریال", "،", "؛", ",", "]", "[", "\\", "}", "{", "|"]
        ),
        row(
          "home", "شسیبلاتنمکگ",
          characters: ["شَ", "سُ", "یِ", "بّ", "لۀ", "اآ", "تـ", "ن«", "م»", "ک:", "گ\""],
          shiftedLabels: ["َ", "ُ", "ِ", "ّ", "ۀ", "آ", "ـ", "«", "»", ":", "\""]
        ),
        row(
          "bottom", "پظطزرذدئو./",
          characters: ["پ|", "ظة", "طي", "زژ", "رؤ", "ذإ", "دأ", "ئء", "و<", ".>", "/؟"],
          shiftedLabels: ["|", "ة", "ي", "ژ", "ؤ", "إ", "أ", "ء", "<", ">", "؟"]
        ),
      ]
    case .arabic101:
      [
        row(
          "number", "ذ1234567890-=",
          characters: ["ذّ", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9)", "0(", "-_", "=+"],
          shiftedLabels: ["ّ", "!", "@", "#", "$", "%", "^", "&", "*", ")", "(", "_", "+"]
        ),
        row(
          "top", "ضصثقفغعهخحجد\\",
          characters: ["ضَ", "صً", "ثُ", "قٌ", "فلإ", "غإ", "ع‘", "ه÷", "خ×", "ح؛", "ج<", "د>", "\\|"],
          shiftedLabels: ["َ", "ً", "ُ", "ٌ", "لإ", "إ", "‘", "÷", "×", "؛", "<", ">", "|"]
        ),
        row(
          "home", "شسيبلاتنمكط",
          characters: ["شِ", "سٍ", "ي]", "ب[", "للأ", "اأ", "تـ", "ن،", "م/", "ك:", "ط\""],
          shiftedLabels: ["ِ", "ٍ", "]", "[", "لأ", "أ", "ـ", "،", "/", ":", "\""]
        ),
        row(
          "bottom", labels: ["\\", "ئ", "ء", "ؤ", "ر", "لا", "ى", "ة", "و", "ز", "ظ"],
          characters: ["\\|", "ئ~", "ءْ", "ؤ}", "ر{", "لالآ", "ىآ", "ة’", "و,", "ز.", "ظ؟"],
          shiftedLabels: ["|", "~", "ْ", "}", "{", "لآ", "آ", "’", ",", ".", "؟"]
        ),
      ]
    case .arabic102:
      [
        row(
          "number", ">1234567890-=",
          characters: ["><", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9)", "0(", "-_", "=+"],
          shiftedLabels: ["<", "!", "@", "#", "$", "%", "^", "&", "*", ")", "(", "_", "+"]
        ),
        row(
          "top", "ضصثقفغعهخحجدذ",
          characters: ["ضَ", "صً", "ثُ", "قٌ", "فلإ", "غإ", "ع‘", "ه÷", "خ×", "ح؛", "ج}", "د{", "ذّ"],
          shiftedLabels: ["َ", "ً", "ُ", "ٌ", "لإ", "إ", "‘", "÷", "×", "؛", "}", "{", "ّ"]
        ),
        row(
          "home", "شسيبلاتنمكط",
          characters: ["ش\\", "س\u{0000}", "ي]", "ب[", "للأ", "اأ", "تـ", "ن،", "م/", "ك:", "ط\""],
          shiftedLabels: ["\\", "NUL", "]", "[", "لأ", "أ", "ـ", "،", "/", ":", "\""]
        ),
        row(
          "bottom", labels: ["ـ", "ئ", "ء", "ؤ", "ر", "لا", "ى", "ة", "و", "ز", "ظ"],
          characters: ["ـ|", "ئ~", "ءْ", "ؤِ", "رٍ", "لالآ", "ىآ", "ة’", "و,", "ز.", "ظ؟"],
          shiftedLabels: ["|", "~", "ْ", "ِ", "ٍ", "لآ", "آ", "’", ",", ".", "؟"]
        ),
      ]
    case .arabicMac:
      [
        row(
          "number", "ـ١٢٣٤٥٦٧٨٩٠-=",
          characters: ["ـ", "١!ظ", "٢@ط❊", "٣#ذ£", "٤$د€", "٥٪∞", "٦^ٱ", "٧&", "٨*", "٩)", "٠(°", "-ـ_", "=+"],
          shiftedLabels: [nil, "!", "@", "#", "$", "٪", "^", "&", "*", ")", "(", "ـ", "+"],
          optionLabels: [nil, "ظ", "ط", "ذ", "د", "∞", "ٱ", nil, nil, nil, "°", "_", nil],
          shiftedOptionLabels: [nil, "ظ", "❊", "£", "€", nil, nil, nil, nil, nil, nil, "_", nil]
        ),
        row(
          "top", "ضصثقفغعهخحجة\\",
          characters: ["ضَ‘", "صً’", "ثِ“", "قٍ”؉", "فُڤ", "غٌ", "عْە", "هّ", "خ]", "ح[", "ج}چ", "ة{", "\\|"],
          shiftedLabels: ["َ", "ً", "ِ", "ٍ", "ُ", "ٌ", "ْ", "ّ", "]", "[", "}", "{", "|"],
          optionLabels: ["‘", "’", "“", "”", "ڤ", nil, "ە", nil, nil, nil, "چ", nil, nil],
          shiftedOptionLabels: [nil, nil, nil, "؉", "ڤ", nil, "ە", nil, nil, nil, "چ", nil, nil]
        ),
        row(
          "home", "شسيبلاتنمك؛",
          characters: ["ش»", "س«ے", "يىی", "بپ", "لٓ", "اآٰ", "تٹ", "ن٫ں", "م٬", "ك:گک", "؛\"…"],
          shiftedLabels: ["»", "«", "ى", nil, nil, "آ", nil, "٫", "٬", ":", "\""],
          optionLabels: [nil, "ے", "ی", "پ", "ٓ", "ٰ", "ٹ", "ں", nil, "گ", "…"],
          shiftedOptionLabels: [nil, "ے", "ی", "پ", nil, nil, "ٹ", "ں", nil, "ک", "…"]
        ),
        row(
          "bottom", "ظطذدزرو،./",
          characters: ["ظ'", "ط", "ذئڈ", "دءڑ", "زأژ", "رإ", "وؤ", "،>,", ".<", "/؟÷"],
          shiftedLabels: ["'", nil, "ئ", "ء", "أ", "إ", "ؤ", ">", "<", "؟"],
          optionLabels: [nil, nil, "ڈ", "ڑ", "ژ", nil, nil, ",", nil, "÷"],
          shiftedOptionLabels: [nil, nil, "ڈ", "ڑ", "ژ", nil, nil, ",", nil, "÷"]
        ),
      ]
    case .urduPhonetic:
      [
        row(
          "number",
          labels: ["ٍ", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹", "۰", "-", "="],
          characters: ["ًٍ", "۱1!", "۲2@", "۳3#", "۴4", "۵5٪", "۶6", "۷7&", "۸8*", "۹9)", "۰0(", "-_", "=+"],
          shiftedLabels: ["ً", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "_", "+"],
          optionLabels: [nil, "!", "@", "#", nil, "٪", nil, "&", "*", ")", "(", nil, nil]
        ),
        row(
          "top", "قوعرتےءیہپ][\\",
          characters: ["قْٓ", "وّ؂", "عٰٖ", "رڑؓ", "تٹؔ", "ےَ؁", "ءئٔ", "یِؑ", "ہۃٕ", "پُٗ", "]}", "[{", "\\|"],
          shiftedLabels: ["ْ", "ّ", "ٰ", "ڑ", "ٹ", "َ", "ئ", "ِ", "ۃ", "ُ", "}", "{", "|"],
          optionLabels: ["ٓ", "؂", "ٖ", "ؓ", "ؔ", "؁", "ٔ", "ؑ", "ٕ", "ٗ", nil, nil, nil]
        ),
        row(
          "home", "اسدفگحجکل؛'",
          characters: ["اآﷲ", "سصؐ", "دڈﷺ", "ف", "گغٛ", "حھؒ", "جضﷻ", "کخ", "لࣇ", "؛:", "'\""],
          shiftedLabels: ["آ", "ص", "ڈ", nil, "غ", "ھ", "ض", "خ", "ࣇ", ":", "\""],
          optionLabels: ["ﷲ", "ؐ", "ﷺ", nil, "ٛ", "ؒ", "ﷻ", nil, nil, nil, nil]
        ),
        row(
          "bottom", "زشچطبنم،۔/",
          characters: ["زذ؏", "شژ؎", "چث؃", "طظؕ", "بݨ﷽", "نں؀", "م٘", "،ٌ>", "۔٫<", "/؟"],
          shiftedLabels: ["ذ", "ژ", "ث", "ظ", "ݨ", "ں", "٘", "ٌ", "٫", "؟"],
          optionLabels: ["؏", "؎", "؃", "ؕ", "﷽", "؀", nil, ">", "<", nil]
        ),
      ]
    case .thaiKedmanee:
      [
        row(
          "number",
          labels: ["_", "ๅ", "/", "-", "ภ", "ถ", "ุ", "ึ", "ค", "ต", "จ", "ข", "ช"],
          characters: ["_%", "ๅ+", "/๑", "-๒", "ภ๓", "ถ๔", "ุู", "ึ฿", "ค๕", "ต๖", "จ๗", "ข๘", "ช๙"],
          shiftedLabels: ["%", "+", "๑", "๒", "๓", "๔", "ู", "฿", "๕", "๖", "๗", "๘", "๙"]
        ),
        row(
          "top",
          labels: ["ๆ", "ไ", "ำ", "พ", "ะ", "ั", "ี", "ร", "น", "ย", "บ", "ล", "ฃ"],
          characters: ["ๆ๐", "ไ\"", "ำฎ", "พฑ", "ะธ", "ัํ", "ี๊", "รณ", "นฯ", "ยญ", "บฐ", "ล,", "ฃฅ"],
          shiftedLabels: ["๐", "\"", "ฎ", "ฑ", "ธ", "ํ", "๊", "ณ", "ฯ", "ญ", "ฐ", ",", "ฅ"]
        ),
        row(
          "home",
          labels: ["ฟ", "ห", "ก", "ด", "เ", "้", "่", "า", "ส", "ว", "ง"],
          characters: ["ฟฤ", "หฆ", "กฏ", "ดโ", "เฌ", "้็", "่๋", "าษ", "สศ", "วซ", "ง."],
          shiftedLabels: ["ฤ", "ฆ", "ฏ", "โ", "ฌ", "็", "๋", "ษ", "ศ", "ซ", "."]
        ),
        row(
          "bottom",
          labels: ["ผ", "ป", "แ", "อ", "ิ", "ื", "ท", "ม", "ใ", "ฝ"],
          characters: ["ผ(", "ป)", "แฉ", "อฮ", "ิฺ", "ื์", "ท?", "มฒ", "ใฬ", "ฝฦ"],
          shiftedLabels: ["(", ")", "ฉ", "ฮ", "ฺ", "์", "?", "ฒ", "ฬ", "ฦ"]
        ),
      ]
    case .thaiPattachote:
      [
        row(
          "number",
          labels: ["_", "=", "๒", "๓", "๔", "๕", "ู", "๗", "๘", "๙", "๐", "๑", "๖"],
          characters: ["_฿", "=+", "๒\"", "๓/", "๔,", "๕?", "ูุ", "๗_", "๘.", "๙(", "๐)", "๑-", "๖%"],
          shiftedLabels: ["฿", "+", "\"", "/", ",", "?", "ุ", "_", ".", "(", ")", "-", "%"]
        ),
        row(
          "top",
          labels: ["็", "ต", "ย", "อ", "ร", "่", "ด", "ม", "ว", "แ", "ใ", "ฌ", "ฃ"],
          characters: ["็๊", "ตฤ", "ยๆ", "อญ", "รษ", "่ึ", "ดฝ", "มซ", "วถ", "แฒ", "ใฯ", "ฌฦ", "ฃฅ"],
          shiftedLabels: ["๊", "ฤ", "ๆ", "ญ", "ษ", "ึ", "ฝ", "ซ", "ถ", "ฒ", "ฯ", "ฦ", "ฅ"]
        ),
        row(
          "home",
          labels: ["้", "ท", "ง", "ก", "ั", "ี", "า", "น", "เ", "ไ", "ข"],
          characters: ["้๋", "ทธ", "งำ", "กณ", "ั์", "ีื", "าผ", "นช", "เโ", "ไฆ", "ขฑ"],
          shiftedLabels: ["๋", "ธ", "ำ", "ณ", "์", "ื", "ผ", "ช", "โ", "ฆ", "ฑ"]
        ),
        row(
          "bottom",
          labels: ["บ", "ป", "ล", "ห", "ิ", "ค", "ส", "ะ", "จ", "พ"],
          characters: ["บฎ", "ปฏ", "ลฐ", "หภ", "ิั", "คศ", "สฮ", "ะฟ", "จฉ", "พฬ"],
          shiftedLabels: ["ฎ", "ฏ", "ฐ", "ภ", "ั", "ศ", "ฮ", "ฟ", "ฉ", "ฬ"]
        ),
      ]
    case .japaneseHiragana:
      [
        row(
          "number", "ろぬふあうえおやゆよわほへ",
          characters: [
            "ろろ", "ぬぬ", "ふふ", "あぁ", "うぅ", "えぇ", "おぉ", "やゃ", "ゆゅ", "よょ", "わを", "ほほ", "へへ",
          ],
          shiftedLabels: [
            "ろ", "ぬ", "ふ", "ぁ", "ぅ", "ぇ", "ぉ", "ゃ", "ゅ", "ょ", "を", "ほ", "へ",
          ]
        ),
        row(
          "top", "たていすかんなにらせ゛゜む",
          characters: [
            "たた", "てて", "いぃ", "すす", "かか", "んん", "なな", "にに", "らら", "せせ", "゛「", "゜」", "むむ",
          ],
          shiftedLabels: [
            "た", "て", "ぃ", "す", "か", "ん", "な", "に", "ら", "せ", "「", "」", "む",
          ]
        ),
        row(
          "home", "ちとしはきくまのりれけ",
          characters: [
            "ちち", "とと", "しし", "はは", "きき", "くく", "まま", "のの", "りり", "れれ", "けけ",
          ],
          shiftedLabels: ["ち", "と", "し", "は", "き", "く", "ま", "の", "り", "れ", "け"]
        ),
        row(
          "bottom", "つさそひこみもねるめ",
          characters: ["つっ", "ささ", "そそ", "ひひ", "ここ", "みみ", "もも", "ね、", "る。", "め・"],
          shiftedLabels: ["っ", "さ", "そ", "ひ", "こ", "み", "も", "、", "。", "・"]
        ),
      ]
    case .hindiInscript:
      [
        row(
          "number",
          labels: ["₹", "१", "२", "३", "४", "५", "६", "७", "८", "९", "०", "-", "ृ"],
          characters: ["₹~", "१ऍ", "२ॅ", "३्र", "४र्", "५ज्ञ", "६त्र", "७क्ष", "८श्र", "९(", "०)", "-ः", "ृऋ"],
          shiftedLabels: ["~", "ऍ", "ॅ", "्र", "र्", "ज्ञ", "त्र", "क्ष", "श्र", "(", ")", "ः", "ऋ"]
        ),
        row(
          "top",
          labels: ["ौ", "ै", "ा", "ी", "ू", "ब", "ह", "ग", "द", "ज", "ड", "़", "ॉ"],
          characters: ["ौऔ", "ैऐ", "ाआ", "ीई", "ूऊ", "बभ", "हङ", "गघ", "दध", "जझ", "डढ", "़ञ", "ॉऑ"],
          shiftedLabels: ["औ", "ऐ", "आ", "ई", "ऊ", "भ", "ङ", "घ", "ध", "झ", "ढ", "ञ", "ऑ"]
        ),
        row(
          "home",
          labels: ["ो", "े", "्", "ि", "ु", "प", "र", "क", "त", "च", "ट"],
          characters: ["ोओ", "ेए", "्अ", "िइ", "ुउ", "पफ", "रऱ", "कख", "तथ", "चछ", "टठ"],
          shiftedLabels: ["ओ", "ए", "अ", "इ", "उ", "फ", "ऱ", "ख", "थ", "छ", "ठ"]
        ),
        row(
          "bottom",
          labels: ["", "ं", "म", "न", "व", "ल", "स", ",", ".", "य"],
          characters: ["", "ंँ", "मण", "न", "व", "ल", "सश", ",ष", ".।", "य?"],
          shiftedLabels: [nil, "ँ", "ण", nil, nil, nil, "श", "ष", "।", "?"]
        ),
      ]
    case .tamil99:
      [
        layeredRow(
          "number", labels: ["₹", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
          shiftedLabels: ["~", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+"],
          optionLabels: ["`", "¡", "™", "£", "¢", "§", nil, "‘", "’", "“", "”", "–", "≠"],
          shiftedOptionLabels: [nil, "⁄", "❊", "#", "€", "٪", "&", "^", "*", ")", "(", "_", "+"]
        ),
        layeredRow(
          "top", labels: ["ஆ", "ஈ", "ஊ", "ஐ", "ஏ", "ள", "ற", "ன", "ட", "ண", "ச", "ஞ", "\\"],
          shiftedLabels: ["ஸ", "ஷ", "ஜ", "ஹ", "X", "ஸ்ரீ", "ஶ", "ஈ", "[", "]", "{", "}", "|"],
          optionLabels: ["ா", "ீ", "ூ", "ை", "ே", nil, nil, nil, nil, nil, "“", "‘", "«"],
          shiftedOptionLabels: [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, "”", "’", "»"]
        ),
        layeredRow(
          "home", labels: ["அ", "இ", "உ", "்", "எ", "க", "ப", "ம", "த", "ந", "ய"],
          shiftedLabels: ["௹", "௺", "௸", "ஃ", nil, nil, nil, "\"", ":", ";", "'"],
          optionLabels: [nil, "ி", "ு", "்", "ெ", nil, nil, nil, nil, nil, "æ"],
          shiftedOptionLabels: [nil, nil, nil, nil, "ஃ", nil, nil, nil, nil, nil, nil]
        ),
        layeredRow(
          "bottom", labels: ["ஔ", "ஓ", "ஒ", "வ", "ங", "ல", "ர", ",", ".", "ழ"],
          shiftedLabels: ["௳", "௴", "௵", "௶", "௷", nil, "/", "<", ">", "?"],
          optionLabels: ["ௌ", "ோ", "ொ", nil, nil, nil, nil, "௹", "।", "/"],
          shiftedOptionLabels: [nil, nil, "©", nil, nil, nil, nil, "„", nil, "¿"]
        ),
      ]
    case .armenianHMQwerty:
      [
        row(
          "number", labels: ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
          characters: ["`~", "1!՜★", "2@™€", "3#£№", "4$¢", "5%★", "6^§", "7&¶", "8*•°", "9(«‹", "0)»›", "-_–—", "=+≠±"],
          shiftedLabels: ["~", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+"],
          optionLabels: ["`", "՜", "™", "£", "¢", "★", "§", "¶", "•", "«", "»", "–", "≠"],
          shiftedOptionLabels: ["~", "★", "€", "№", nil, nil, nil, nil, "°", "‹", "›", "—", "±"]
        ),
        row(
          "top", labels: ["ճ", "ւ", "ե", "ր", "տ", "յ", "ւ", "ի", "ո", "պ", "[", "]", "\\"],
          characters: ["ճՃչՉ", "ւՒ", "եԵէԷ", "րՐռՌ", "տՏթԹ", "յՅ†¥", "ւՒ÷՚", "իԻ„", "ոՈօՕ", "պՊփՓ", "[{“”", "]}‘’", "\\|«»"],
          shiftedLabels: ["Ճ", "Ւ", "Ե", "Ր", "Տ", "Յ", "Ւ", "Ի", "Ո", "Պ", "{", "}", "|"],
          optionLabels: ["չ", nil, "է", "ռ", "թ", "†", "÷", "„", "օ", "փ", "“", "‘", "«"],
          shiftedOptionLabels: ["Չ", nil, "Է", "Ռ", "Թ", "¥", "՚", "„", "Օ", "Փ", "”", "’", "»"]
        ),
        row(
          "home", labels: ["ա", "ս", "դ", "ֆ", "գ", "հ", "ձ", "կ", "լ", ";", "'"],
          characters: ["աԱըԸ", "սՍշՇ", "դԴ", "ֆՖƒ", "գԳ©®", "հՀ", "ձՁջՋ", "կԿքՔ", "լԼղՂ", ";:…՟", "'\"՛֊"],
          shiftedLabels: ["Ա", "Ս", "Դ", "Ֆ", "Գ", "Հ", "Ձ", "Կ", "Լ", ":", "\""],
          optionLabels: ["ը", "շ", nil, "ƒ", "©", nil, "ջ", "ք", "ղ", "…", "՛"],
          shiftedOptionLabels: ["Ը", "Շ", nil, nil, "®", nil, "Ջ", "Ք", "Ղ", "՟", "֊"]
        ),
        row(
          "bottom", labels: ["զ", "խ", "ծ", "վ", "բ", "ն", "մ", ",", ".", "/"],
          characters: ["զԶժԺ", "խԽ", "ծԾցՑ", "վՎև", "բԲ", "նՆ", "մՄ", ",<՝≤", ".>։≥", "/?՞"],
          shiftedLabels: ["Զ", "Խ", "Ծ", "Վ", "Բ", "Ն", "Մ", "<", ">", "?"],
          optionLabels: ["ժ", nil, "ց", "և", nil, nil, nil, "՝", "։", "՞"],
          shiftedOptionLabels: ["Ժ", nil, "Ց", nil, nil, nil, nil, "≤", "≥", "՞"]
        ),
      ]
    case .mongolianCyrillic:
      [
        row(
          "number", labels: ["=", "№", "-", "\"", "₮", ":", ".", "_", ",", "%", "?", "е", "щ"],
          characters: ["=+~≈", "№1!", "-2@—", "\"3#§", "₮4$€", ":5;", ".6^…", "_7&", ",8*", "%9({", "?0)}", "еЕ[—", "щЩ]≈"],
          shiftedLabels: ["+", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "Е", "Щ"],
          optionLabels: ["~", "!", "@", "#", "$", ";", "^", "&", "*", "(", ")", "[", "]"],
          shiftedOptionLabels: ["≈", nil, "—", "§", "€", nil, "…", nil, nil, "{", "}", "—", "≈"]
        ),
        row(
          "top", labels: ["ф", "ц", "у", "ж", "э", "н", "г", "ш", "ү", "з", "к", "ъ", "¥"],
          characters: ["фФјЈ", "цЦџЏ", "уУўЎ", "жЖєЄ", "эЭ", "нНњЊ", "гГѓЃ", "шШѕЅ", "үҮ'„", "зЗ‘’", "кК“”", "ъЪ«»", "¥|\\"],
          shiftedLabels: ["Ф", "Ц", "У", "Ж", "Э", "Н", "Г", "Ш", "Ү", "З", "К", "Ъ", "|"],
          optionLabels: ["ј", "џ", "ў", "є", nil, "њ", "ѓ", "ѕ", "'", "‘", "“", "«", "\\"],
          shiftedOptionLabels: ["Ј", "Џ", "Ў", "Є", nil, "Њ", "Ѓ", "Ѕ", "„", "’", "”", "»", "|"]
        ),
        row(
          "home", labels: ["й", "ы", "б", "ө", "а", "х", "р", "о", "л", "д", "п"],
          characters: ["йЙ", "ыЫ", "бБћЋ", "өӨ", "аА", "хХ", "рР₽", "оО", "лЛљЉ", "дД", "пП"],
          shiftedLabels: ["Й", "Ы", "Б", "Ө", "А", "Х", "Р", "О", "Л", "Д", "П"],
          optionLabels: [nil, nil, "ћ", nil, nil, nil, "₽", nil, "љ", nil, nil],
          shiftedOptionLabels: [nil, nil, "Ћ", nil, nil, nil, nil, nil, "Љ", nil, nil]
        ),
        row(
          "bottom", labels: ["я", "ч", "ё", "с", "м", "и", "т", "ь", "в", "ю"],
          characters: ["яЯђЂ", "чЧ", "ёЁ", "сС", "мМ", "иИіІ", "тТїЇ", "ьЬ<≤", "вВ>≥", "юЮ/"],
          shiftedLabels: ["Я", "Ч", "Ё", "С", "М", "И", "Т", "Ь", "В", "Ю"],
          optionLabels: ["ђ", nil, nil, nil, nil, "і", "ї", "<", ">", "/"],
          shiftedOptionLabels: ["Ђ", nil, nil, nil, nil, "І", "Ї", "≤", "≥", nil]
        ),
      ]
    case .hebrew:
      [
        row(
          "number", ";1234567890-=",
          characters: [";~", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9)", "0(", "-_", "=+"],
          shiftedLabels: ["~", "!", "@", "#", "$", "%", "^", "&", "*", ")", "(", "_", "+"]
        ),
        row(
          "top", "/'קראטוןםפ][\\",
          characters: ["/Q", "'W", "קE", "רR", "אT", "טY", "וU", "ןI", "םO", "פP", "]}", "[{", "\\|"],
          shiftedLabels: ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "}", "{", "|"]
        ),
        row(
          "home", "שדגכעיחלךף,",
          characters: ["שA", "דS", "גD", "כF", "עG", "יH", "חJ", "לK", "ךL", "ף:", ",\""],
          shiftedLabels: ["A", "S", "D", "F", "G", "H", "J", "K", "L", ":", "\""]
        ),
        row(
          "bottom", labels: ["\\", "ז", "ס", "ב", "ה", "נ", "מ", "צ", "ת", "ץ", "."],
          characters: ["\\|", "זZ", "סX", "בC", "הV", "נB", "מN", "צM", "ת>", "ץ<", ".?"],
          shiftedLabels: ["|", "Z", "X", "C", "V", "B", "N", "M", ">", "<", "?"]
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
    let keys = style.isSteno
      ? stenoRows().flatMap { $0 }
      : rows(for: layout).flatMap { $0 } + typingThumbKeys(for: layout)
    let normalized = Character(String(character).lowercased())
    return keys.first(where: { $0.exactlyProducesCaseSensitive(character) })?.id
      ?? keys.first(where: { $0.exactlyProduces(normalized) })?.id
      ?? keys.first(where: { $0.characters.contains(normalized) })?.id
  }

  static func highlightedKey(
    for character: Character?,
    rows: [[KeyboardGuideKey]],
    style: KeyboardGuideStyle = .staggered
  ) -> String? {
    guard let character else { return nil }
    if character == " " { return style.isSteno ? "steno-space" : "space" }
    let keys = style.isSteno ? stenoRows().flatMap { $0 } : rows.flatMap { $0 }
    let normalized = Character(String(character).lowercased())
    return keys.first(where: { $0.exactlyProducesCaseSensitive(character) })?.id
      ?? keys.first(where: { $0.exactlyProduces(normalized) })?.id
      ?? keys.first(where: { $0.characters.contains(normalized) })?.id
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
    layout: KeyboardLayout? = nil,
    style: KeyboardGuideStyle = .staggered
  ) -> [KeyboardGuideKey] {
    if style.isSteno { return [] }
    let thumbKeys = typingThumbKeys(for: layout)
    if keysMode == .full {
      return [
        nonTypingKey("left-control", label: "⌃", width: 34),
        nonTypingKey("left-option", label: "⌥", width: 34),
        nonTypingKey("left-command", label: "⌘", width: 38),
      ] + thumbKeys + [
        nonTypingKey("right-command", label: "⌘", width: 38),
        nonTypingKey("right-option", label: "⌥", width: 34),
        nonTypingKey("right-control", label: "⌃", width: 34),
      ]
    }
    return thumbKeys
  }

  private static func typingThumbKeys(for layout: KeyboardLayout?) -> [KeyboardGuideKey] {
    let space = KeyboardGuideKey("space", label: "空格", characters: " ", width: 120)
    switch layout {
    case .beaklZi:
      return [KeyboardGuideKey("thumb-0", label: "I", characters: "iI", width: 70), space]
    case .maltron, .rsthd:
      return [KeyboardGuideKey("thumb-0", label: "E", characters: "eE", width: 70), space]
    case .prsten:
      return [space, KeyboardGuideKey("thumb-1", label: "E", characters: "eE", width: 70)]
    case .handsDownPromethium:
      return [KeyboardGuideKey("thumb-0", label: "R", characters: "rR", width: 70), space]
    default:
      return [KeyboardGuideKey("space", label: "空格", characters: " ", width: 170)]
    }
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
    shiftedLabels: [String?]? = nil,
    optionLabels: [String?]? = nil,
    shiftedOptionLabels: [String?]? = nil
  )
    -> [KeyboardGuideKey]
  {
    row(
      prefix, labels: Array(labels).map(String.init), characters: characters,
      shiftedLabels: shiftedLabels, optionLabels: optionLabels, shiftedOptionLabels: shiftedOptionLabels)
  }

  private static func row(
    _ prefix: String,
    labels: [String],
    characters: [String]? = nil,
    shiftedLabels: [String?]? = nil,
    optionLabels: [String?]? = nil,
    shiftedOptionLabels: [String?]? = nil
  )
    -> [KeyboardGuideKey]
  {
    labels.enumerated().map { offset, label in
      KeyboardGuideKey(
        "\(prefix)-\(offset)",
        label: label,
        characters: characters?[safe: offset],
        shiftedLabel: shiftedLabels.flatMap { labels in
          labels.indices.contains(offset) ? labels[offset] : nil
        },
        optionLabel: optionLabels.flatMap { labels in
          labels.indices.contains(offset) ? labels[offset] : nil
        },
        shiftedOptionLabel: shiftedOptionLabels.flatMap { labels in
          labels.indices.contains(offset) ? labels[offset] : nil
        }
      )
    }
  }

  private static func layeredRow(
    _ prefix: String,
    labels: [String],
    shiftedLabels: [String?],
    optionLabels: [String?],
    shiftedOptionLabels: [String?]
  ) -> [KeyboardGuideKey] {
    let characters = labels.indices.map { index in
      [labels[index], shiftedLabels[index], optionLabels[index], shiftedOptionLabels[index]]
        .compactMap { $0 }
        .joined()
    }
    return row(
      prefix, labels: labels, characters: characters, shiftedLabels: shiftedLabels,
      optionLabels: optionLabels, shiftedOptionLabels: shiftedOptionLabels)
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

  private static func baseShiftRows(normal: [String], shifted: [String]) -> [[KeyboardGuideKey]] {
    baseShiftRows(
      normalLabels: normal.map { $0.map(String.init) },
      shiftedLabels: shifted.map { $0.map(String.init) }
    )
  }

  private static func baseShiftRows(
    normalLabels: [[String]], shiftedLabels: [[String]]
  ) -> [[KeyboardGuideKey]] {
    zip(["number", "top", "home", "bottom"], zip(normalLabels, shiftedLabels)).map { entry in
      let (rowID, labels) = entry
      return layeredRow(
        rowID,
        labels: labels.0,
        shiftedLabels: labels.1,
        optionLabels: Array(repeating: nil, count: labels.0.count),
        shiftedOptionLabels: Array(repeating: nil, count: labels.0.count)
      )
    }
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
    self == .frenchAzerty || self == .mtgapFull || self == .engram || self == .engrammer
      || self == .booMangle || self == .quartz || self == .capewellDvorak || self == .real
      || self == .stndc || self == .uciea || self == .diktor || self == .diktorVoronovMod
      || self == .redaktor || self == .juiyaf || self == .zubachev
      || self == .colemakQix || self == .colemakQi || self == .colemaQ
      || self == .thaiManoonchai
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
          KeyboardGuideModel.bottomRow(for: keysMode, layout: layout, style: style),
          rowIndex: guideRows.count)
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
