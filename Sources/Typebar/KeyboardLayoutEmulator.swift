@preconcurrency import AppKit

/// Converts ANSI physical key positions into an explicitly selected practice layout.
/// A nil layout leaves the event on AppKit's normal input path, preserving the
/// active macOS input source, dead keys, and IME composition.
enum KeyboardLayoutEmulator {
  private struct KeyLayers {
    let normal: String
    let shifted: String
    let option: String?
    let shiftedOption: String?

    init(
      normal: String, shifted: String, option: String? = nil,
      shiftedOption: String? = nil
    ) {
      self.normal = normal
      self.shifted = shifted
      self.option = option
      self.shiftedOption = shiftedOption
    }
  }

  private typealias OptionPair = (normal: String?, shifted: String?)

  private static let physicalRows: [[UInt16]] = [
    [50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24],
    [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30, 42],
    [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39],
    [6, 7, 8, 9, 11, 45, 46, 43, 47, 44],
  ]

  static func character(
    forKeyCode keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, mapping: KeyboardInputMapping
  ) -> Character? {
    text(forKeyCode: keyCode, modifierFlags: modifierFlags, mapping: mapping).flatMap(singleCharacter)
  }

  /// Returns all text emitted by a selected physical key. Most layouts emit a
  /// single character, while a few public system layouts define ligature keys.
  static func text(
    forKeyCode keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, mapping: KeyboardInputMapping
  ) -> String? {
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

  static func text(
    forKeyCode keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, layout: KeyboardLayout?
  ) -> String? {
    text(
      forKeyCode: keyCode, modifierFlags: modifierFlags,
      mapping: layout.map(KeyboardInputMapping.builtIn) ?? .system)
  }

  /// Resolves a character through a selected layout for input devices which
  /// report remapped logical characters instead of their physical key code.
  static func keyCode(for character: Character, layout: KeyboardLayout) -> UInt16? {
    keyCode(for: character, keys: keys(for: layout))
  }

  static func keyCode(forOutput output: String, layout: KeyboardLayout) -> UInt16? {
    keyCode(forOutput: output, keys: keys(for: layout))
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
    keyCode(forOutput: String(character), keys: keys)
  }

  private static func keyCode(forOutput output: String, keys: [UInt16: KeyLayers]) -> UInt16? {
    keys.first { _, layers in
      [layers.normal, layers.shifted, layers.option, layers.shiftedOption]
        .compactMap { $0 }
        .contains {
          $0 == output || $0.caseInsensitiveCompare(output) == .orderedSame
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
          layers = .init(normal: String(label), shifted: String(shiftedLabels[keyIndex]))
        } else {
          layers = casePair(for: label)
        }
        return (keyCode, layers)
      }
    })
  }

  private static func casePair(for character: Character) -> KeyLayers {
    let lower = String(character).lowercased()
    let upper = String(character).uppercased()
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
    case .dvorakLeft:
      withOptionLayers(
        map(
          "50:`~ 18:[{ 19:]} 20:/? 21:pP 23:fF 22:mM 26:lL 28:jJ 25:4$ 29:3# 27:2@ 24:1! "
            + "12:;: 13:qQ 14:bB 15:yY 17:uU 16:rR 32:sS 34:oO 31:.> 35:6^ 33:5% 30:=+ 42:\\| "
            + "0:-_ 1:kK 2:cC 3:dD 5:tT 4:hH 38:eE 40:aA 37:zZ 41:8* 39:7& "
            + "6:'\" 7:xX 8:gG 9:vV 11:wW 45:nN 46:iI 43:,< 47:0) 44:9("
        ),
        options: [
          50: ("`", "`"), 18: ("“", "”"), 19: ("‘", "’"), 20: ("÷", "¿"),
          21: ("π", "∏"), 23: ("ƒ", "Ï"), 22: ("µ", "Â"), 26: ("¬", "Ò"),
          28: ("∆", "Ô"), 25: ("¢", "›"), 29: ("£", "‹"), 27: ("™", "€"), 24: ("¡", "⁄"),
          12: ("…", "Ú"), 13: ("œ", "Œ"), 14: ("∫", "ı"), 15: ("¥", "Á"),
          17: ("¨", "¨"), 16: ("®", "‰"), 32: ("ß", "Í"), 34: ("ø", "Ø"),
          31: ("≥", "˘"), 35: ("§", "ﬂ"), 33: ("∞", "ﬁ"), 30: ("≠", "±"), 42: ("«", "»"),
          0: ("–", "—"), 1: ("˚", ""), 2: ("ç", "Ç"), 3: ("∂", "Î"),
          5: ("†", "ˇ"), 4: ("˙", "Ó"), 38: ("´", "´"), 40: ("å", "Å"),
          37: ("Ω", "¸"), 41: ("•", "°"), 39: ("¶", "‡"),
          6: ("æ", "Æ"), 7: ("≈", "˛"), 8: ("©", "˝"), 9: ("√", "◊"),
          11: ("∑", "„"), 45: ("˜", "˜"), 46: ("ˆ", "ˆ"), 43: ("≤", "¯"),
          47: ("º", "‚"), 44: ("ª", "·"),
        ]
      )
    case .dvorakRight:
      withOptionLayers(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:jJ 22:lL 26:mM 28:fF 25:pP 29:/? 27:[{ 24:]} "
            + "12:5% 13:6^ 14:qQ 15:.> 17:oO 16:rR 32:sS 34:uU 31:yY 35:bB 33:;: 30:=+ 42:\\| "
            + "0:7& 1:8* 2:zZ 3:aA 5:eE 4:hH 38:tT 40:dD 37:cC 41:kK 39:-_ "
            + "6:9( 7:0) 8:xX 9:,< 11:iI 45:nN 46:wW 43:vV 47:gG 44:'\""
        ),
        options: [
          50: ("`", "`"), 18: ("¡", "⁄"), 19: ("™", "€"), 20: ("£", "‹"),
          21: ("¢", "›"), 23: ("∆", "Ô"), 22: ("¬", "Ò"), 26: ("µ", "Â"),
          28: ("ƒ", "Ï"), 25: ("π", "∏"), 29: ("÷", "¿"), 27: ("“", "”"), 24: ("‘", "’"),
          12: ("∞", "ﬁ"), 13: ("§", "ﬂ"), 14: ("œ", "Œ"), 15: ("≥", "˘"),
          17: ("ø", "Ø"), 16: ("®", "‰"), 32: ("ß", "Í"), 34: ("¨", "¨"),
          31: ("¥", "Á"), 35: ("∫", "ı"), 33: ("…", "Ú"), 30: ("≠", "±"), 42: ("«", "»"),
          0: ("¶", "‡"), 1: ("•", "°"), 2: ("Ω", "¸"), 3: ("å", "Å"),
          5: ("´", "´"), 4: ("˙", "Ó"), 38: ("†", "ˇ"), 40: ("∂", "Î"),
          37: ("ç", "Ç"), 41: ("˚", ""), 39: ("–", "—"),
          6: ("ª", "·"), 7: ("º", "‚"), 8: ("≈", "˛"), 9: ("≤", "¯"),
          11: ("ˆ", "ˆ"), 45: ("˜", "˜"), 46: ("∑", "„"), 43: ("√", "◊"),
          47: ("©", "˝"), 44: ("æ", "Æ"),
        ]
      )
    case .ansiColemak:
      map(
        "12:qQ 13:wW 14:fF 15:pP 17:gG 16:jJ 32:lL 34:uU 31:yY 35:;: 33:[{ 30:]} "
          + "0:aA 1:rR 2:sS 3:tT 5:dD 4:hH 38:nN 40:eE 37:iI 41:oO 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:kK 46:mM 43:,< 47:.> 44:/?")
    case .ansiColemakDH:
      map(
        "12:qQ 13:wW 14:fF 15:pP 17:bB 16:jJ 32:lL 34:uU 31:yY 35:;: 33:[{ 30:]} "
          + "0:aA 1:rR 2:sS 3:tT 5:gG 4:mM 38:nN 40:eE 37:iI 41:oO 39:'\" "
          + "6:xX 7:cC 8:dD 9:vV 11:zZ 45:kK 46:hH 43:,< 47:.> 44:/?")
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
    case .nordicQwerty, .norwegianQwerty:
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
    case .danishQwerty:
      map(
        "50:½§ 18:1! 19:2\" 20:3# 21:4¤ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:+? 24:´` "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:åÅ 30:¨^ "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:æÆ 39:øØ 42:'* "
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
    case .brazilianABNT2:
      withOptionLayers(
        map(
          "50:'\" 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6¨ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:´` 30:[{ 42:]} "
            + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:çÇ 39:~^ "
            + "10:\\| 6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,< 47:.> 44:;: 94:/?"
        ),
        options: [
          50: ("`", "’"), 18: ("¹", "¡"), 19: ("²", "½"), 20: ("³", "¾"),
          21: ("£", "¼"), 23: ("¢", "⅜"), 22: ("¬", "¨"), 26: ("¶", "⅞"),
          28: ("•", "×"), 25: ("∑", "·"), 29: ("º", "°"), 27: ("–", "—"), 24: ("§", "±"),
          12: ("/", "\\"), 13: ("?", "¿"), 14: ("€", "€"), 15: ("®", "®"),
          17: ("ŧ", "Ŧ"), 16: ("←", "¥"), 32: ("↓", "↑"), 34: ("→", "ı"),
          31: ("ø", "Ø"), 35: ("þ", "Þ"), 33: ("´", "`"), 30: ("ª", "ª"), 42: ("º", "º"),
          0: ("æ", "Æ"), 1: ("ß", "§"), 2: ("ð", "Ð"), 3: ("đ", "◊"),
          5: ("∆", "˝"), 4: ("ħ", "Ħ"), 38: ("ʝ", "&"), 40: ("ĸ", ""),
          37: ("ł", "Ł"), 41: ("·", "ő"), 39: ("~", "^"),
          10: ("∏", "ă"), 6: ("Ω", "<"), 7: ("≈", ">"), 8: ("₢", "©"),
          9: ("ʋ", "Ʋ"), 11: ("∫", "™"), 45: ("ŋ", "Ŋ"), 46: ("µ", "µ"),
          43: ("≤", "«"), 47: ("≥", "»"), 44: ("…", "…"), 94: ("°", "¿"),
        ]
      )
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
    case .turkishF:
      map(
        "50:+* 18:1! 19:2\" 20:3^ 21:4$ 23:5% 22:6& 26:7' 28:8( 25:9) 29:0= 27:/? 24:-_ "
          + "12:fF 13:gG 14:ğĞ 15:ıI 17:oO 16:dD 32:rR 34:nN 31:hH 35:pP 33:qQ 30:wW "
          + "0:uU 1:iİ 2:eE 3:aA 5:üÜ 4:tT 38:kK 40:mM 37:lL 41:yY 39:şŞ 42:xX "
          + "10:<> 6:jJ 7:öÖ 8:vV 9:cC 11:çÇ 45:zZ 46:sS 43:bB 47:.: 44:,;"
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
    case .bulgarianPhoneticTraditional:
      map(
        "50:чЧ 18:1! 19:2@ 20:3№ 21:4$ 23:5% 22:6€ 26:7§ 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:яЯ 13:вВ 14:еЕ 15:рР 17:тТ 16:ъЪ 32:уУ 34:иИ 31:оО 35:пП 33:шШ 30:щЩ "
          + "0:аА 1:сС 2:дД 3:фФ 5:гГ 4:хХ 38:йЙ 40:кК 37:лЛ 41:;: 39:'\" 42:юЮ "
          + "10:юЮ 6:зЗ 7:ьѝ 8:цЦ 9:жЖ 11:бБ 45:нН 46:мМ 43:,< 47:.> 44:/?"
      )
    case .belarusian:
      map(
        "50:ёЁ 18:1! 19:2\" 20:3№ 21:4; 23:5% 22:6: 26:7? 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:йЙ 13:цЦ 14:уУ 15:кК 17:еЕ 16:нН 32:гГ 34:шШ 31:ўЎ 35:зЗ 33:хХ 30:'' 42:\\/ "
          + "0:фФ 1:ыЫ 2:вВ 3:аА 5:пП 4:рР 38:оО 40:лЛ 37:дД 41:жЖ 39:эЭ "
          + "10:<> 6:яЯ 7:чЧ 8:сС 9:мМ 11:іІ 45:тТ 46:ьЬ 43:бБ 47:юЮ 44:.,"
      )
    case .macedonian:
      map(
        "50:ѝЍ 18:1! 19:2„ 20:3“ 21:4' 23:5% 22:6‚ 26:7‘ 28:8* 25:9( 29:0) 27:-- 24:=+ "
          + "12:љЉ 13:њЊ 14:еЕ 15:рР 17:тТ 16:ѕЅ 32:уУ 34:иИ 31:оО 35:пП 33:шШ 30:ѓЃ 42:жЖ "
          + "0:аА 1:сС 2:дД 3:фФ 5:гГ 4:хХ 38:јЈ 40:кК 37:лЛ 41:чЧ 39:ќЌ "
          + "10:ѐЀ 6:зЗ 7:џЏ 8:цЦ 9:вВ 11:бБ 45:нН 46:мМ 43:,; 47:.: 44://"
      )
    case .pashto:
      map(
        "50:\u{200D}|\u{0654} 18:۱! 19:۲٬ 20:۳٫ 21:۴؋ 23:۵٪ 22:۶× 26:۷» 28:۸« 25:۹) 29:۰( 27:-ـ 24:=+ "
          + "12:ض|ْ 13:ص|ٌ 14:ث|ٍ 15:ق|ً 17:ف|ُ 16:غ|ِ 32:ع|َ 34:ه|ّ 31:خځ 35:حڅ 33:ج] 30:چ[ 42:\\* "
          + "0:شښ 1:سۍ 2:یي 3:بپ 5:لأ 4:اآ 38:تټ 40:نڼ 37:مة 41:ک: 39:ګ؛ "
          + "6:ئظ 7:ېط 8:زژ 9:رء 11:ذ|\u{200C} 45:دډ 46:ړؤ 43:و، 47:ږ. 44:/؟"
      )
    case .estonian:
      map(
        "50:ˇ~ 18:1! 19:2\" 20:3# 21:4¤ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:+? 24:´` "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:üÜ 30:õÕ 42:'* "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:öÖ 39:äÄ "
          + "10:<> 6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,; 47:.: 44:-_"
      )
    case .persianStandard:
      map(
        "50:\u{200D}|\u{200D} 18:۱! 19:۲٬ 20:۳٫ 21:۴﷼ 23:۵٪ 22:۶× 26:۷، 28:۸* 25:۹) 29:۰( 27:-ـ 24:=+ "
          + "12:ض|ْ 13:ص|ٌ 14:ث|ٍ 15:ق|ً 17:ف|ُ 16:غ|ِ 32:ع|َ 34:ه|ّ 31:خ] 35:ح[ 33:ج} 30:چ{ 42:\\| "
          + "0:شؤ 1:سئ 2:یي 3:بإ 5:لأ 4:اآ 38:تة 40:ن» 37:م« 41:ک: 39:گ؛ "
          + "10:\\| 6:ظك 7:طط 8:زژ 9:ر|ٰ 11:ذ|\u{200C} 45:د|\u{0654} 46:پء 43:و> 47:.< 44:/؟"
      )
    case .persianFarsi:
      map(
        "50:÷× 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9) 29:0( 27:-_ 24:=+ "
          + "12:ض|ً 13:ص|ٌ 14:ث|ٍ 15:ق|ریال 17:ف، 16:غ؛ 32:ع, 34:ه] 31:خ[ 35:ح\\ 33:ج} 30:چ{ 42:پ| "
          + "0:ش|َ 1:س|ُ 2:ی|ِ 3:ب|ّ 5:لۀ 4:اآ 38:تـ 40:ن« 37:م» 41:ک: 39:گ\" "
          + "10:پ| 6:ظة 7:طي 8:زژ 9:رؤ 11:ذإ 45:دأ 46:ئء 43:و< 47:.> 44:/؟"
      )
    case .arabic101:
      map(
        "50:ذ|ّ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9) 29:0( 27:-_ 24:=+ "
          + "12:ض|َ 13:ص|ً 14:ث|ُ 15:ق|ٌ 17:ف|لإ 16:غإ 32:ع‘ 34:ه÷ 31:خ× 35:ح؛ 33:ج< 30:د> 42:\\| "
          + "0:ش|ِ 1:س|ٍ 2:ي] 3:ب[ 5:ل|لأ 4:اأ 38:تـ 40:ن، 37:م/ 41:ك: 39:ط\" "
          + "10:\\| 6:ئ~ 7:ء|ْ 8:ؤ} 9:ر{ 11:لا|لآ 45:ىآ 46:ة’ 43:و, 47:ز. 44:ظ؟"
      )
    case .arabic102:
      map(
        "50:>< 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9) 29:0( 27:-_ 24:=+ "
          + "12:ض|َ 13:ص|ً 14:ث|ُ 15:ق|ٌ 17:ف|لإ 16:غإ 32:ع‘ 34:ه÷ 31:خ× 35:ح؛ 33:ج} 30:د{ 42:ذ|ّ "
          + "0:ش\\ 1:س|\u{0000} 2:ي] 3:ب[ 5:ل|لأ 4:اأ 38:تـ 40:ن، 37:م/ 41:ك: 39:ط\" "
          + "10:ـ| 6:ئ~ 7:ء|ْ 8:ؤ|ِ 9:ر|ٍ 11:لا|لآ 45:ىآ 46:ة’ 43:و, 47:ز. 44:ظ؟"
      )
    case .arabicMac:
      withOptionLayers(
        withSuppressedShift(
          map(
            "50:ـ|ـ 18:١! 19:٢@ 20:٣# 21:٤$ 23:٥٪ 22:٦^ 26:٧& 28:٨* 25:٩) 29:٠( 27:-ـ 24:=+ "
              + "12:ض|َ 13:ص|ً 14:ث|ِ 15:ق|ٍ 17:ف|ُ 16:غ|ٌ 32:ع|ْ 34:ه|ّ 31:خ] 35:ح[ 33:ج} 30:ة{ 42:\\| "
              + "0:ش» 1:س« 2:يى 3:ب|ب 5:ل|ل 4:اآ 38:ت|ت 40:ن٫ 37:م٬ 41:ك: 39:؛\" "
              + "6:ظ' 7:ط|ط 8:ذئ 9:دء 11:زأ 45:رإ 46:وؤ 43:،> 47:.< 44:/؟"
          ),
          keyCodes: [3, 5, 7, 38, 50]
        ),
        options: [
          1: ("ے", "ے"), 2: ("ی", "ی"), 3: ("پ", "پ"),
          4: ("\u{0670}", nil), 5: ("\u{0653}", nil), 8: ("ڈ", "ڈ"),
          9: ("ڑ", "ڑ"), 11: ("ژ", "ژ"), 12: ("‘", nil),
          13: ("’", nil), 14: ("“", nil), 15: ("”", "؉"),
          17: ("ڤ", "ڤ"), 18: ("ظ", "ظ"), 19: ("ط", "❊"),
          20: ("ذ", "£"), 21: ("د", "€"), 22: ("ٱ", nil),
          23: ("∞", nil), 27: ("_", "_"), 29: ("°", nil),
          32: ("ە", "ە"), 33: ("چ", "چ"), 38: ("ٹ", "ٹ"),
          39: ("…", "…"), 40: ("ں", "ں"), 41: ("گ", "ک"),
          43: (",", ","), 44: ("÷", "÷"),
        ]
      )
    case .urduPhonetic:
      withOptionLayers(
        withSuppressedShift(
          map(
            "50:ٍ|ً 18:۱1 19:۲2 20:۳3 21:۴4 23:۵5 22:۶6 26:۷7 28:۸8 25:۹9 29:۰0 27:-_ 24:=+ "
              + "12:ق|ْ 13:و|ّ 14:ع|ٰ 15:رڑ 17:تٹ 16:ے|َ 32:ءئ 34:ی|ِ 31:ہۃ 35:پ|ُ 33:]} 30:[{ 42:\\| "
              + "0:اآ 1:سص 2:دڈ 3:ف|ف 5:گغ 4:حھ 38:جض 40:کخ 37:لࣇ 41:؛: 39:'\" "
              + "6:زذ 7:شژ 8:چث 9:طظ 11:بݨ 45:نں 46:م|٘ 43:،|ٌ 47:۔٫ 44:/؟"
          ),
          keyCodes: [3]
        ),
        options: [
          0: ("ﷲ", nil), 1: ("ؐ", nil), 2: ("ﷺ", nil),
          5: ("ٛ", nil), 6: ("؏", nil), 7: ("؎", nil),
          8: ("؃", nil), 9: ("ؕ", nil), 11: ("﷽", nil),
          12: ("ٓ", nil), 13: ("؂", nil), 14: ("ٖ", nil),
          15: ("ؓ", nil), 17: ("ؔ", nil), 16: ("؁", nil),
          18: ("!", nil), 19: ("@", nil), 20: ("#", nil),
          23: ("٪", nil), 26: ("&", nil), 28: ("*", nil),
          25: (")", nil), 29: ("(", nil), 32: ("ٔ", nil),
          34: ("ؑ", nil), 31: ("ٕ", nil), 35: ("ٗ", nil),
          4: ("ؒ", nil), 38: ("ﷻ", nil), 45: ("؀", nil),
          43: (">", nil), 47: ("<", nil),
        ]
      )
    case .thaiKedmanee:
      map(
        "50:_|% 18:ๅ|+ 19:/|๑ 20:-|๒ 21:ภ|๓ 23:ถ|๔ 22:ุ|ู 26:ึ|฿ 28:ค|๕ 25:ต|๖ 29:จ|๗ 27:ข|๘ 24:ช|๙ "
          + "12:ๆ|๐ 13:ไ|\" 14:ำ|ฎ 15:พ|ฑ 17:ะ|ธ 16:ั|ํ 32:ี|๊ 34:ร|ณ 31:น|ฯ 35:ย|ญ 33:บ|ฐ 30:ล|, 42:ฃ|ฅ "
          + "0:ฟ|ฤ 1:ห|ฆ 2:ก|ฏ 3:ด|โ 5:เ|ฌ 4:้|็ 38:่|๋ 40:า|ษ 37:ส|ศ 41:ว|ซ 39:ง|. "
          + "6:ผ|( 7:ป|) 8:แ|ฉ 9:อ|ฮ 11:ิ|ฺ 45:ื|์ 46:ท|? 43:ม|ฒ 47:ใ|ฬ 44:ฝ|ฦ"
      )
    case .thaiPattachote:
      map(
        "50:_|฿ 18:=|+ 19:๒|\" 20:๓|/ 21:๔|, 23:๕|? 22:ู|ุ 26:๗|_ 28:๘|. 25:๙|( 29:๐|) 27:๑|- 24:๖|% "
          + "12:็|๊ 13:ต|ฤ 14:ย|ๆ 15:อ|ญ 17:ร|ษ 16:่|ึ 32:ด|ฝ 34:ม|ซ 31:ว|ถ 35:แ|ฒ 33:ใ|ฯ 30:ฌ|ฦ 42:ฃ|ฅ "
          + "0:้|๋ 1:ท|ธ 2:ง|ำ 3:ก|ณ 5:ั|์ 4:ี|ื 38:า|ผ 40:น|ช 37:เ|โ 41:ไ|ฆ 39:ข|ฑ "
          + "6:บ|ฎ 7:ป|ฏ 8:ล|ฐ 9:ห|ภ 11:ิ|ั 45:ค|ศ 46:ส|ฮ 43:ะ|ฟ 47:จ|ฉ 44:พ|ฬ"
      )
    case .hindiInscript:
      withSuppressedShift(
        withSuppressedBase(
          map(
            "50:₹|~ 18:१|ऍ 19:२|ॅ 20:३|्र 21:४|र् 23:५|ज्ञ 22:६|त्र 26:७|क्ष 28:८|श्र 25:९|( 29:०|) 27:-|ः 24:ृ|ऋ "
              + "12:ौ|औ 13:ै|ऐ 14:ा|आ 15:ी|ई 17:ू|ऊ 16:ब|भ 32:ह|ङ 34:ग|घ 31:द|ध 35:ज|झ 33:ड|ढ 30:़|ञ 42:ॉ|ऑ "
              + "0:ो|ओ 1:े|ए 2:्|अ 3:ि|इ 5:ु|उ 4:प|फ 38:र|ऱ 40:क|ख 37:त|थ 41:च|छ 39:ट|ठ "
              + "6:z|Z 7:ं|ँ 8:म|ण 9:न|N 11:व|V 45:ल|L 46:स|श 43:,|ष 47:.|। 44:य|?"
          ),
          keyCodes: [6]
        ),
        keyCodes: [6, 9, 11, 45]
      )
    case .armenianHMQwerty:
      withOptionLayers(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:ճՃ 13:ւՒ 14:եԵ 15:րՐ 17:տՏ 16:յՅ 32:ւՒ 34:իԻ 31:ոՈ 35:պՊ 33:[{ 30:]} 42:\\| "
            + "0:աԱ 1:սՍ 2:դԴ 3:ֆՖ 5:գԳ 4:հՀ 38:ձՁ 40:կԿ 37:լԼ 41:;: 39:'\" "
            + "6:զԶ 7:խԽ 8:ծԾ 9:վՎ 11:բԲ 45:նՆ 46:մՄ 43:,< 47:.> 44:/?"
        ),
        options: [
          50: ("`", "~"), 18: ("՜", "★"), 19: ("™", "€"), 20: ("£", "№"),
          21: ("¢", nil), 23: ("★", nil), 22: ("§", nil), 26: ("¶", nil),
          28: ("•", "°"), 25: ("«", "‹"), 29: ("»", "›"), 27: ("–", "—"), 24: ("≠", "±"),
          12: ("չ", "Չ"), 14: ("է", "Է"), 15: ("ռ", "Ռ"), 17: ("թ", "Թ"),
          16: ("†", "¥"), 32: ("÷", "՚"), 34: ("„", "„"), 31: ("օ", "Օ"),
          35: ("փ", "Փ"), 33: ("“", "”"), 30: ("‘", "’"), 42: ("«", "»"),
          0: ("ը", "Ը"), 1: ("շ", "Շ"), 3: ("ƒ", nil), 5: ("©", "®"),
          38: ("ջ", "Ջ"), 40: ("ք", "Ք"), 37: ("ղ", "Ղ"), 41: ("…", "՟"), 39: ("՛", "֊"),
          6: ("ժ", "Ժ"), 8: ("ց", "Ց"), 9: ("և", nil), 43: ("՝", "≤"),
          47: ("։", "≥"), 44: ("՞", "՞"),
        ]
      )
    case .mongolianCyrillic:
      withOptionLayers(
        map(
          "50:=+ 18:№1 19:-2 20:\"3 21:₮4 23::5 22:.6 26:_7 28:,8 25:%9 29:?0 27:еЕ 24:щЩ "
            + "12:фФ 13:цЦ 14:уУ 15:жЖ 17:эЭ 16:нН 32:гГ 34:шШ 31:үҮ 35:зЗ 33:кК 30:ъЪ 42:¥| "
            + "0:йЙ 1:ыЫ 2:бБ 3:өӨ 5:аА 4:хХ 38:рР 40:оО 37:лЛ 41:дД 39:пП "
            + "6:яЯ 7:чЧ 8:ёЁ 9:сС 11:мМ 45:иИ 46:тТ 43:ьЬ 47:вВ 44:юЮ"
        ),
        options: [
          50: ("~", "≈"), 18: ("!", nil), 19: ("@", "—"), 20: ("#", "§"),
          21: ("$", "€"), 23: (";", nil), 22: ("^", "…"), 26: ("&", nil),
          28: ("*", nil), 25: ("(", "{"), 29: (")", "}"), 27: ("[", "—"), 24: ("]", "≈"),
          12: ("ј", "Ј"), 13: ("џ", "Џ"), 14: ("ў", "Ў"), 15: ("є", "Є"),
          16: ("њ", "Њ"), 32: ("ѓ", "Ѓ"), 34: ("ѕ", "Ѕ"), 31: ("'", "„"),
          35: ("‘", "’"), 33: ("“", "”"), 30: ("«", "»"), 42: ("\\", "|"),
          2: ("ћ", "Ћ"), 38: ("₽", nil), 37: ("љ", "Љ"),
          6: ("ђ", "Ђ"), 45: ("і", "І"), 46: ("ї", "Ї"), 43: ("<", "≤"),
          47: (">", "≥"), 44: ("/", nil),
        ]
      )
    case .hebrew:
      map(
        "50:;~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9) 29:0( 27:-_ 24:=+ "
          + "12:/Q 13:'W 14:קE 15:רR 17:אT 16:טY 32:וU 34:ןI 31:םO 35:פP 33:]} 30:[{ 42:\\| "
          + "0:שA 1:דS 2:גD 3:כF 5:עG 4:יH 38:חJ 40:לK 37:ךL 41:ף: 39:,\" "
          + "10:\\| 6:זZ 7:סX 8:בC 9:הV 11:נB 45:מN 46:צM 43:ת> 47:ץ< 44:.?"
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

  /// An empty translated string consumes the physical key without inserting
  /// text. This matches layouts whose system keymap intentionally leaves a
  /// modifier layer unassigned, instead of falling through to another input source.
  private static func withSuppressedShift(
    _ keys: [UInt16: KeyLayers], keyCodes: Set<UInt16>
  ) -> [UInt16: KeyLayers] {
    var layeredKeys = keys
    for keyCode in keyCodes {
      guard let existing = layeredKeys[keyCode] else { continue }
      layeredKeys[keyCode] = .init(
        normal: existing.normal, shifted: "", option: existing.option,
        shiftedOption: existing.shiftedOption)
    }
    return layeredKeys
  }

  private static func withSuppressedBase(
    _ keys: [UInt16: KeyLayers], keyCodes: Set<UInt16>
  ) -> [UInt16: KeyLayers] {
    var layeredKeys = keys
    for keyCode in keyCodes {
      guard let existing = layeredKeys[keyCode] else { continue }
      layeredKeys[keyCode] = .init(
        normal: "", shifted: existing.shifted, option: existing.option,
        shiftedOption: existing.shiftedOption)
    }
    return layeredKeys
  }

  private static func map(_ definition: String) -> [UInt16: KeyLayers] {
    Dictionary(uniqueKeysWithValues: definition.split(separator: " ").compactMap { token in
      let tokenScalars = token.unicodeScalars
      guard let colon = tokenScalars.firstIndex(of: ":"),
        let keyCode = UInt16(String(tokenScalars[..<colon]))
      else { return nil }
      let layerScalars = tokenScalars[tokenScalars.index(after: colon)...]
      if let separator = layerScalars.firstIndex(of: "|") {
        let normalString = String(layerScalars[..<separator])
        let shiftedString = String(layerScalars[layerScalars.index(after: separator)...])
        if !normalString.isEmpty, !shiftedString.isEmpty {
          return (keyCode, .init(normal: normalString, shifted: shiftedString))
        }
      }
      let layerString = String(layerScalars)
      guard layerString.count == 2 else { return nil }
      let symbols = Array(layerString)
      return (keyCode, .init(normal: String(symbols[0]), shifted: String(symbols[1])))
    })
  }

}
