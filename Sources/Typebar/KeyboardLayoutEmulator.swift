@preconcurrency import AppKit

/// Converts ANSI physical key positions into an explicitly selected practice layout.
/// A nil layout leaves the event on AppKit's normal input path, preserving the
/// active macOS input source, dead keys, and IME composition.
enum KeyboardLayoutEmulator {
  private struct KeyLayers {
    let normal: Character
    let shifted: Character
    let option: Character?
    let shiftedOption: Character?

    init(
      normal: Character, shifted: Character, option: Character? = nil,
      shiftedOption: Character? = nil
    ) {
      self.normal = normal
      self.shifted = shifted
      self.option = option
      self.shiftedOption = shiftedOption
    }
  }

  private typealias OptionPair = (normal: Character, shifted: Character)

  private static let physicalRows: [[UInt16]] = [
    [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24],
    [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],
    [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39],
    [6, 7, 8, 9, 11, 45, 46, 43, 47, 44],
  ]

  static func character(
    forKeyCode keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, mapping: KeyboardInputMapping
  ) -> Character? {
    guard !modifierFlags.contains(.command),
      !modifierFlags.contains(.control)
    else { return nil }
    let layers: KeyLayers?
    switch mapping {
    case .system:
      layers = nil
    case let .builtIn(layout):
      layers = keys(for: layout)[keyCode]
    case let .custom(layout):
      layers = keys(for: layout)[keyCode]
    }
    guard let layers else { return nil }
    if modifierFlags.contains(.option) {
      return modifierFlags.contains(.shift) ? layers.shiftedOption : layers.option
    }
    return modifierFlags.contains(.shift) ? layers.shifted : layers.normal
  }

  static func character(
    forKeyCode keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, layout: KeyboardLayout?
  ) -> Character? {
    character(
      forKeyCode: keyCode, modifierFlags: modifierFlags,
      mapping: layout.map(KeyboardInputMapping.builtIn) ?? .system)
  }

  /// Resolves a character through a selected layout for input devices which
  /// report remapped logical characters instead of their physical key code.
  static func keyCode(for character: Character, layout: KeyboardLayout) -> UInt16? {
    keyCode(for: character, keys: keys(for: layout))
  }

  static func keyCode(for character: Character, mapping: KeyboardInputMapping) -> UInt16? {
    switch mapping {
    case .system:
      nil
    case let .builtIn(layout):
      keyCode(for: character, layout: layout)
    case let .custom(layout):
      keyCode(for: character, keys: keys(for: layout))
    }
  }

  private static func keyCode(for character: Character, keys: [UInt16: KeyLayers]) -> UInt16? {
    keys.first { _, layers in
      [layers.normal, layers.shifted, layers.option, layers.shiftedOption]
        .compactMap { $0 }
        .contains {
          $0 == character || String($0).caseInsensitiveCompare(String(character)) == .orderedSame
        }
    }?.key
  }

  private static func keys(for layout: CustomKeyboardGuideLayout) -> [UInt16: KeyLayers] {
    Dictionary(uniqueKeysWithValues: zip(physicalRows, layout.inputRows).enumerated().flatMap {
      rowIndex, keyCodesAndLabels in
      let (keyCodes, labels) = keyCodesAndLabels
      let shiftedLabels = layout.shiftedInputRows[rowIndex]
      return zip(keyCodes, labels).enumerated().map { keyIndex, keyCodeAndLabel in
        let (keyCode, label) = keyCodeAndLabel
        let layers: KeyLayers
        if let shiftedLabels, shiftedLabels.indices.contains(keyIndex) {
          layers = .init(normal: label, shifted: shiftedLabels[keyIndex])
        } else {
          layers = casePair(for: label)
        }
        return (keyCode, layers)
      }
    })
  }

  private static func casePair(for character: Character) -> KeyLayers {
    let lower = singleCharacter(String(character).lowercased()) ?? character
    let upper = singleCharacter(String(character).uppercased()) ?? character
    return .init(normal: lower, shifted: upper)
  }

  private static func singleCharacter(_ string: String) -> Character? {
    let characters = Array(string)
    guard characters.count == 1 else { return nil }
    return characters[0]
  }

  private static func keys(for layout: KeyboardLayout) -> [UInt16: KeyLayers] {
    switch layout {
    case .ansiQwerty:
      ansiQwertyKeys()
    case .ansiDvorak:
      map(
        "12:'\" 13:,< 14:.> 15:pP 17:yY 16:fF 32:gG 34:cC 31:rR 35:lL 33:/? 30:=+ "
          + "0:aA 1:oO 2:eE 3:uU 5:iI 4:dD 38:hH 40:tT 37:nN 41:sS 39:-_ "
          + "6:;: 7:qQ 8:jJ 9:kK 11:xX 45:bB 46:mM 43:wW 47:vV 44:zZ")
    case .ansiColemak:
      map(
        "12:qQ 13:wW 14:fF 15:pP 17:gG 16:jJ 32:lL 34:uU 31:yY 35:;: 33:[{ 30:]} "
          + "0:aA 1:rR 2:sS 3:tT 5:dD 4:hH 38:nN 40:eE 37:iI 41:oO 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:kK 46:mM 43:,< 47:.> 44:/?")
    case .ansiWorkman:
      map(
        "12:qQ 13:dD 14:rR 15:wW 17:bB 16:jJ 32:fF 34:uU 31:pP 35:;: 33:[{ 30:]} "
          + "0:aA 1:sS 2:hH 3:tT 5:gG 4:yY 38:nN 40:eE 37:oO 41:iI 39:'\" "
          + "6:zZ 7:xX 8:mM 9:cC 11:vV 45:kK 46:lL 43:,< 47:.> 44:/?")
    case .germanQwertz:
      map(
        "50:^° 18:1! 19:2\" 20:3§ 21:4$ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:ß? 24:´` "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:zZ 32:uU 34:iI 31:oO 35:pP 33:üÜ 30:+* "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:öÖ 39:äÄ 42:#' "
          + "10:<> 6:yY 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,; 47:.: 44:-_")
    case .swissGerman:
      map(
        "50:§° 18:1+ 19:2\" 20:3* 21:4ç 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:'? 24:^` "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:zZ 32:uU 34:iI 31:oO 35:pP 33:üè 30:‥! "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:öé 39:äà 42:$£ "
          + "10:<> 6:yY 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,; 47:.: 44:-_")
    case .swissFrench:
      map(
        "50:§° 18:1+ 19:2\" 20:3* 21:4ç 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:'? 24:^` "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:zZ 32:uU 34:iI 31:oO 35:pP 33:èü 30:‥! "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:éö 39:àä 42:$£ "
          + "10:<> 6:yY 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,; 47:.: 44:-_")
    case .nordicQwerty:
      map(
        "50:§° 18:1! 19:2\" 20:3# 21:4¤ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:+? 24:\\` "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:åÅ 30:¨^ "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:øØ 39:æÆ 42:'* "
          + "10:<> 6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,; 47:.: 44:-_")
    case .swedishQwerty:
      map(
        "50:§½ 18:1! 19:2\" 20:3# 21:4¤ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:+? 24:´` "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:åÅ 30:¨^ "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:öÖ 39:äÄ 42:'* "
          + "10:<> 6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,; 47:.: 44:-_")
    case .ukQwerty:
      map(
        "50:`¬ 18:1! 19:2\" 20:3£ 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:[{ 30:]} 42:#~ "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:;: 39:'@ "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,< 47:.> 44:/?")
    case .spanishQwerty:
      map(
        "50:ºª 18:1! 19:2\" 20:3· 21:4$ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:'? 24:¡¿ "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:`^ 30:+* "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:ñÑ 39:´¨ 42:çÇ "
          + "10:<> 6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,; 47:.: 44:-_")
    case .italianQwerty:
      map(
        "50:\\| 18:1! 19:2\" 20:3£ 21:4$ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:‘? 24:ì^ "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:èé 30:+* "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:òç 39:à° 42:ù§ "
          + "10:<> 6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,; 47:.: 44:-_")
    case .portugueseQwertyISO:
      map(
        "50:\\| 18:1! 19:2\" 20:3# 21:4$ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:'? 24:«» "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:+* 30:´` "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:çÇ 39:ºª 42:~^ "
          + "10:<> 6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,; 47:.: 44:-_")
    case .portugueseQwertyANSI:
      map(
        "50:\\| 18:1! 19:2\" 20:3# 21:4$ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:'? 24:<> "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:+* 30:´` 42:~^ "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:çÇ 39:ºª "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,; 47:.: 44:-_")
    case .latinAmericanQwerty:
      map(
        "50:|° 18:1! 19:2\" 20:3# 21:4$ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:'? 24:¿¡ "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:´¨ 30:+* "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:ñÑ 39:{[ "
          + "10:<> 6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,; 47:.: 44:-_")
    case .polishProgrammers:
      withOptionLayers(
        ansiQwertyKeys(),
        options: [
          0: ("ą", "Ą"), 1: ("ś", "Ś"), 6: ("ż", "Ż"), 7: ("ź", "Ź"),
          8: ("ć", "Ć"), 14: ("ę", "Ę"), 31: ("ó", "Ó"), 32: ("€", "€"),
          37: ("ł", "Ł"), 45: ("ń", "Ń"),
        ])
    case .frenchAzerty:
      map(
        "18:&1 19:é2 20:\"3 21:'4 23:(5 22:-6 26:è7 28:_8 25:ç9 29:à0 27:)° 24:=+ "
          + "12:aA 13:zZ 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:^¨ 30:$£ "
          + "0:qQ 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:mM 39:ù% "
          + "6:wW 7:xX 8:cC 9:vV 11:bB 45:nN 46:,? 43:;. 47::/ 44:!§")
    case .turkishQ:
      map(
        "50:\"é 18:1! 19:2' 20:3^ 21:4+ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:*? 24:-_ "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:ıI 31:oO 35:pP 33:ğĞ 30:üÜ "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:şŞ 39:iİ 42:,; "
          + "10:<> 6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:öÖ 47:çÇ 44:.:"
      )
    case .hungarianQwertz:
      map(
        "50:-_ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:óÓ 24:?? "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:zZ 32:uU 34:iI 31:oO 35:pP 33:őŐ 30:úÚ 42:űŰ "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:éÉ 39:áÁ "
          + "10:<> 6:íÍ 7:yY 8:xX 9:cC 11:vV 45:bB 46:nN 43:mM 47:öÖ 44:üÜ"
      )
    case .greekAlphabetic:
      map(
        "50:?? 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:,< 24:.> "
          + "12:αΑ 13:βΒ 14:γΓ 15:δΔ 17:εΕ 16:ζΖ 32:ηΗ 34:θΘ 31:ιΙ 35:κΚ 33:λΛ 30:μΜ 42:νΝ "
          + "0:ξΞ 1:οΟ 2:πΠ 3:ρΡ 5:σΣ 4:τΤ 38:υΥ 40:φΦ 37:χΧ 41:ψΨ 39:ωΩ "
          + "10:άΆ 6:έΈ 7:ήΉ 8:ίΊ 9:όΌ 11:ύΎ 45:ώΏ 46:ςΣ 43:·: 47:'\" 44:/\\"
      )
    case .russianJcuken:
      map(
        "50:ёЁ 18:1! 19:2\" 20:3№ 21:4; 23:5% 22:6: 26:7? 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:йЙ 13:цЦ 14:уУ 15:кК 17:еЕ 16:нН 32:гГ 34:шШ 31:щЩ 35:зЗ 33:хХ 30:ъЪ 42:\\/ "
          + "0:фФ 1:ыЫ 2:вВ 3:аА 5:пП 4:рР 38:оО 40:лЛ 37:дД 41:жЖ 39:эЭ "
          + "10:<> 6:яЯ 7:чЧ 8:сС 9:мМ 11:иИ 45:тТ 46:ьЬ 43:бБ 47:юЮ 44:.,"
      )
    case .ukrainianJcuken:
      map(
        "50:ґҐ 18:1! 19:2\" 20:3№ 21:4; 23:5% 22:6: 26:7? 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:йЙ 13:цЦ 14:уУ 15:кК 17:еЕ 16:нН 32:гГ 34:шШ 31:щЩ 35:зЗ 33:хХ 30:їЇ 42:\\/ "
          + "0:фФ 1:іІ 2:вВ 3:аА 5:пП 4:рР 38:оО 40:лЛ 37:дД 41:жЖ 39:єЄ "
          + "10:<> 6:яЯ 7:чЧ 8:сС 9:мМ 11:иИ 45:тТ 46:ьЬ 43:бБ 47:юЮ 44:.,"
      )
    case .bulgarianCyrillic:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:яЯ 13:жЖ 14:еЕ 15:рР 17:тТ 16:ъЪ 32:уУ 34:иИ 31:оО 35:пП 33:шШ 30:щЩ 42:юЮ "
          + "0:аА 1:сС 2:дД 3:фФ 5:гГ 4:хХ 38:йЙ 40:кК 37:лЛ 41:чЧ 39:'\" "
          + "10:<> 6:зЗ 7:ьЬ 8:цЦ 9:вВ 11:бБ 45:нН 46:мМ 43:,< 47:.> 44:/?"
      )
    case .serbianCyrillic:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:љЉ 13:њЊ 14:еЕ 15:рР 17:тТ 16:зЗ 32:уУ 34:иИ 31:оО 35:пП 33:шШ 30:ђЂ 42:\\| "
          + "0:аА 1:сС 2:дД 3:фФ 5:гГ 4:хХ 38:јЈ 40:кК 37:лЛ 41:чЧ 39:ћЋ "
          + "10:<> 6:жЖ 7:џЏ 8:цЦ 9:вВ 11:бБ 45:нН 46:мМ 43:,; 47:.: 44:-_"
      )
    }
  }

  private static func ansiQwertyKeys() -> [UInt16: KeyLayers] {
    map(
      "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
        + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:[{ 30:]} "
        + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:;: 39:'\" "
        + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,< 47:.> 44:/?")
  }

  private static func withOptionLayers(
    _ keys: [UInt16: KeyLayers], options: [UInt16: OptionPair]
  ) -> [UInt16: KeyLayers] {
    var layeredKeys = keys
    for (keyCode, option) in options {
      guard let existing = layeredKeys[keyCode] else { continue }
      layeredKeys[keyCode] = .init(
        normal: existing.normal, shifted: existing.shifted, option: option.normal,
        shiftedOption: option.shifted)
    }
    return layeredKeys
  }

  private static func map(_ definition: String) -> [UInt16: KeyLayers] {
    Dictionary(uniqueKeysWithValues: definition.split(separator: " ").compactMap { token in
      let pieces = token.split(separator: ":", maxSplits: 1)
      guard pieces.count == 2, let keyCode = UInt16(pieces[0]), pieces[1].count == 2 else { return nil }
      let symbols = Array(pieces[1])
      return (keyCode, .init(normal: symbols[0], shifted: symbols[1]))
    })
  }
}
