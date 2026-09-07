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
    case .programmerDvorak:
      map(
        "50:$~ 18:&% 19:[7 20:{5 21:}3 23:(1 22:=9 26:*0 28:)2 25:+4 29:]6 27:!8 24:#` "
          + "12:;: 13:,< 14:.> 15:pP 17:yY 16:fF 32:gG 34:cC 31:rR 35:lL 33:/? 30:@^ 42:\\| "
          + "0:aA 1:oO 2:eE 3:uU 5:iI 4:dD 38:hH 40:tT 37:nN 41:sS 39:-_ "
          + "6:'\" 7:qQ 8:jJ 9:kK 11:xX 45:bB 46:mM 43:wW 47:vV 44:zZ"
      )
    case .programmerDvorakPrime:
      map(
        "50:$~ 18:+1 19:[2 20:{3 21:(4 23:&5 22:=6 26:)7 28:}8 25:]9 29:*0 27:!% 24:|` "
          + "12:;: 13:,< 14:.> 15:pP 17:yY 16:fF 32:gG 34:cC 31:rR 35:lL 33:/? 30:@^ 42:\\# "
          + "0:aA 1:oO 2:eE 3:uU 5:iI 4:dD 38:hH 40:tT 37:nN 41:sS 39:-_ "
          + "6:'\" 7:qQ 8:jJ 9:kK 11:xX 45:bB 46:mM 43:wW 47:vV 44:zZ"
      )
    case .germanDvorak:
      map(
        "50:^° 18:1! 19:2\" 20:3§ 21:4$ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:+* 24:<> "
          + "12:üÜ 13:,; 14:.: 15:pP 17:yY 16:fF 32:gG 34:cC 31:tT 35:zZ 33:ß? 30:\\/ "
          + "0:aA 1:oO 2:eE 3:iI 5:uU 4:hH 38:dD 40:rR 37:nN 41:sS 39:lL 42:-_ "
          + "10:äÄ 6:öÖ 7:qQ 8:jJ 9:kK 11:xX 45:bB 46:mM 43:wW 47:vV 44:#'"
      )
    case .germanDvorakImproved:
      map(
        "50:^° 18:1§ 19:2² 20:3³ 21:4# 23:5@ 22:6& 26:7~ 28:8\\ 25:9( 29:0) 27:+* 24:=% "
          + "12:üÜ 13:,; 14:.: 15:pP 17:yY 16:fF 32:gG 34:cC 31:rR 35:lL 33:/? 30:'\" "
          + "0:aA 1:oO 2:eE 3:uU 5:iI 4:dD 38:hH 40:tT 37:nN 41:sS 39:ß! 42:-_ "
          + "10:äÄ 6:öÖ 7:qQ 8:jJ 9:kK 11:xX 45:bB 46:mM 43:wW 47:vV 44:zZ"
      )
    case .spanishDvorak:
      map(
        "50:ºª 18:1! 19:2\" 20:3· 21:4$ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:'? 24:¡¿ "
          + "12:.: 13:,; 14:ñÑ 15:pP 17:yY 16:fF 32:gG 34:cC 31:hH 35:lL 33:`^ 30:+* "
          + "0:aA 1:oO 2:eE 3:uU 5:iI 4:dD 38:rR 40:tT 37:nN 41:sS 39:´¨ 42:çÇ "
          + "10:<> 6:-_ 7:qQ 8:jJ 9:kK 11:xX 45:bB 46:mM 43:wW 47:vV 44:zZ"
      )
    case .swedishColemak:
      map(
        "50:§½ 18:1! 19:2\" 20:3# 21:4¤ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:+? 24:´` "
          + "12:qQ 13:wW 14:fF 15:pP 17:gG 16:jJ 32:lL 34:uU 31:yY 35:öÖ 33:åÅ 30:¨^ "
          + "0:aA 1:rR 2:sS 3:tT 5:dD 4:hH 38:nN 40:eE 37:iI 41:oO 39:äÄ 42:'* "
          + "10:<> 6:zZ 7:xX 8:cC 9:vV 11:bB 45:kK 46:mM 43:,; 47:.: 44:-_"
      )
    case .swedishDvorak:
      map(
        "50:§° 18:1! 19:2\" 20:3# 21:4€ 23:5% 22:6& 26:7/ 28:8( 25:9) 29:0= 27:+? 24:´` "
          + "12:åÅ 13:äÄ 14:öÖ 15:pP 17:yY 16:fF 32:gG 34:cC 31:rR 35:lL 33:,; 30:¨^ "
          + "0:aA 1:oO 2:eE 3:uU 5:iI 4:dD 38:hH 40:tT 37:nN 41:sS 39:-_ 42:'* "
          + "10:<> 6:.: 7:qQ 8:jJ 9:kK 11:xX 45:bB 46:mM 43:wW 47:vV 44:zZ"
      )
    case .frenchDvorak:
      map(
        "50:*« 18:1» 19:2/ 20:3- 21:4è 23:5\\ 22:6^ 26:7( 28:8` 25:9) 29:0_ 27:+[ 24:%] "
          + "12:?: 13:<' 14:>é 15:gG 17:!. 16:hH 32:vV 34:cC 31:mM 35:kK 33:zZ 30:=- "
          + "0:oO 1:aA 2:uU 3:eE 5:bB 4:fF 38:sS 40:tT 37:nN 41:dD 39:wW 42:#~ "
          + "10:çà 6:|; 7:qQ 8:@, 9:iI 11:yY 45:xX 46:rR 43:lL 47:pP 44:jJ"
      )
    case .frenchAzertyAFNOR:
      withSpaceLayers(
        withOptionLayers(
          map(
            "50:@# 18:à1 19:é2 20:é3 21:ê4 23:(5 22:)6 26:‘7 28:’8 25:«9 29:»0 27:'\" 24:^¨ "
              + "12:aA 13:zZ 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:-– 30:+± "
              + "0:qQ 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:mM 39:/\\ 42:*½ "
              + "10:<> 6:wW 7:xX 8:cC 9:vV 11:bB 45:nN 46:.? 43:,! 47::… 44:;="
          ),
          options: [
            50: ("˘", nil), 18: ("§", "À"), 19: ("´", "É"), 20: ("`", "È"),
            21: ("&", "Ê"), 23: ("[", "˝"), 22: ("]", nil), 26: ("¯", nil),
            28: ("_", "—"), 25: ("“", "‹"), 29: ("”", "›"), 27: ("°", "˚"),
            24: ("ˇ", nil), 12: ("æ", "Æ"), 13: ("£", nil), 14: ("€", nil),
            15: ("®", nil), 17: ("{", "™"), 16: ("}", nil), 32: ("ù", "Ù"),
            34: ("˙", nil), 31: ("œ", "Œ"), 35: ("%", "‰"), 33: ("−", "‑"),
            30: ("†", "‡"), 0: ("θ", nil), 1: ("ß", "ẞ"), 2: ("$", nil),
            3: ("¤", nil), 5: ("µ", nil), 4: (nil, nil), 38: (nil, nil),
            40: ("⁄", nil), 37: ("|", nil), 41: ("∞", nil), 39: ("÷", "√"),
            42: ("×", "¼"), 10: ("≤", "≥"), 6: ("ʒ", "Ʒ"), 7: ("©", nil),
            8: ("ç", "Ç"), 9: ("¸", "˛"), 11: (nil, nil), 45: ("~", nil),
            46: ("¿", nil), 43: ("¡", nil), 47: ("·", nil), 44: ("≃", "≠"),
          ]
        ),
        option: " ", shiftedOption: " "
      )
    case .frenchBepo:
      withSpaceLayers(
        withOptionLayers(
          map(
            "50:$# 18:\"1 19:«2 20:»3 21:(4 23:)5 22:@6 26:+7 28:-8 25:/9 29:*0 27:=° 24:%` "
              + "12:bB 13:éÉ 14:pP 15:oO 17:èÈ 16:ô! 32:vV 34:dD 31:lL 35:jJ 33:zZ 30:wW "
              + "0:aA 1:uU 2:iI 3:eE 5:,; 4:cC 38:tT 40:sS 37:rR 41:nN 39:mM 42:çÇ "
              + "10:êÊ 6:àÀ 7:yY 8:xX 9:.: 11:kK 45:'? 46:qQ 43:gG 47:hH 44:fF"
          ),
          options: [
            50: ("–", "¶"), 18: ("—", "„"), 19: ("<", "“"), 20: (">", "”"),
            21: ("[", "⩽"), 23: ("]", "⩾"), 22: ("^", nil), 26: ("±", "¬"),
            28: ("−", "¼"), 25: ("÷", "½"), 29: ("×", "¾"), 27: ("≠", nil),
            24: ("″", "″"), 12: ("|", "¦"), 13: ("ó", "ő"), 14: ("&", "§"),
            15: ("œ", "Œ"), 17: ("ò", "`"), 16: ("¡", nil), 32: ("ǒ", nil),
            34: ("ð", "Ð"), 31: ("ø", nil), 35: ("ĳ", "Ĳ"), 33: ("ə", "Ə"),
            30: ("ŏ", nil), 0: ("æ", "Æ"), 1: ("ù", "Ù"), 2: ("ö", "ȯ"),
            3: ("€", "¤"), 5: ("’", "ǫ"), 4: ("©", "ſ"), 38: ("þ", "Þ"),
            40: ("ß", "ẞ"), 37: ("®", "™"), 41: ("õ", nil), 39: ("ō", "º"),
            42: ("¸", ","), 10: ("/", nil), 6: ("\\", nil), 7: ("{", "‘"),
            8: ("}", "’"), 9: ("…", "·"), 11: ("~", nil), 45: ("¿", "ỏ"),
            46: ("o", "̊"), 43: ("Ω", nil), 47: ("†", "‡"), 44: ("ǫ", "ª"),
          ]
        )
      )
    case .frenchBepoAFNOR:
      withSpaceLayers(
        withOptionLayers(
          map(
            "50:$# 18:\"1 19:«2 20:»3 21:(4 23:)5 22:@6 26:+7 28:-8 25:/9 29:*0 27:=° 24:%` "
              + "12:bB 13:éÉ 14:pP 15:oO 17:èÈ 16:ô! 32:vV 34:dD 31:lL 35:jJ 33:zZ 30:wW "
              + "0:aA 1:uU 2:iI 3:eE 5:,; 4:cC 38:tT 40:sS 37:rR 41:nN 39:mM 42:çÇ "
              + "10:êÊ 6:àÀ 7:yY 8:xX 9:.: 11:kK 45:’? 46:qQ 43:gG 47:hH 44:fF"
          ),
          options: [
            50: ("–", "¶"), 18: ("—", "„"), 19: ("<", "“"), 20: (">", "”"),
            21: ("[", "⩽"), 23: ("]", "⩾"), 22: ("^", nil), 26: ("±", "¬"),
            28: ("−", "¼"), 25: ("÷", "½"), 29: ("×", "¾"), 27: ("≠", "′"),
            24: ("‰", "″"), 12: ("|", "_"), 13: ("ó", nil), 14: ("&", "§"),
            15: ("œ", "Œ"), 17: ("ò", "`"), 16: ("¡", nil), 32: ("ǒ", nil),
            34: ("∞", nil), 31: ("ø", "£"), 35: (nil, nil), 33: ("ɵ", nil),
            30: (nil, nil), 0: ("æ", "Æ"), 1: ("ù", "Ù"), 2: ("ö", "ȯ"),
            3: ("€", "¤"), 5: ("'", "ț"), 4: ("¸", "©"), 38: ("ᵉ", "™"),
            40: ("ß", "ſ"), 37: ("ŏ", "®"), 41: ("õ", nil), 39: ("ō", nil),
            42: (nil, nil), 10: ("/", "^"), 6: ("\\", "‚"), 7: ("{", "‘"),
            8: ("}", "’"), 9: ("…", "·"), 11: ("~", "‑"), 45: ("¿", "ỏ"),
            46: ("å", "ơ"), 43: ("Ω", "†"), 47: ("ọ", "‡"), 44: ("ǫ", nil),
          ]
        )
      )
    case .ansiAlpha:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:aA 13:bB 14:cC 15:dD 17:eE 16:fF 32:gG 34:hH 31:iI 35:jJ 33:[{ 30:]} 42:\\| "
          + "0:kK 1:lL 2:mM 3:nN 5:oO 4:pP 38:qQ 40:rR 37:sS 41:;: 39:'\" "
          + "6:tT 7:uU 8:vV 9:wW 11:xX 45:yY 46:zZ 43:,< 47:.> 44:/?"
      )
    case .ansiHandsDown:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:cC 14:hH 15:pP 17:vV 16:kK 32:yY 34:oO 31:jJ 35:/? 33:[{ 30:]} 42:\\| "
          + "0:rR 1:sS 2:nN 3:tT 5:gG 4:wW 38:uU 40:eE 37:iI 41:aA 39:;: "
          + "6:xX 7:mM 8:lL 9:dD 11:bB 45:zZ 46:fF 43:'\" 47:,< 44:.>"
      )
    case .ansiHandsDownAlt:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:wW 13:gG 14:hH 15:mM 17:kK 16:qQ 32:cC 34:uU 31:jJ 35:'\" 33:[{ 30:]} 42:\\| "
          + "0:rR 1:sS 2:nN 3:tT 5:fF 4:yY 38:aA 40:eE 37:oO 41:iI 39:;: "
          + "6:xX 7:bB 8:lL 9:dD 11:vV 45:zZ 46:pP 43:,< 47:.> 44:/?"
      )
    case .ansiHandsDownNeu:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8? 25:9< 29:0> 27:=_ 24:\\| "
          + "12:wW 13:fF 14:mM 15:pP 17:vV 16:/* 32:.: 34:qQ 31:\"[ 35:'] 33:zZ 30:({ 42:)} "
          + "0:rR 1:sS 2:nN 3:tT 5:bB 4:,; 38:aA 40:eE 37:iI 41:hH 39:jJ "
          + "6:xX 7:cC 8:lL 9:dD 11:gG 45:-+ 46:uU 43:oO 47:yY 44:kK"
      )
    case .ansiHandsDownNeuInverted:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8? 25:9< 29:0> 27:=_ 24:\\| "
          + "12:xX 13:cC 14:lL 15:dD 17:gG 16:-+ 32:uU 34:oO 31:yY 35:kK 33:zZ 30:({ 42:)} "
          + "0:rR 1:sS 2:nN 3:tT 5:bB 4:,; 38:aA 40:eE 37:iI 41:hH 39:jJ "
          + "6:wW 7:fF 8:mM 9:pP 11:vV 45:/* 46:.: 43:qQ 47:\"[ 44:']"
      )
    case .mtgap:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:yY 13:pP 14:oO 15:uU 17:jJ 16:kK 32:dD 34:lL 31:cC 35:wW 33:[{ 30:]} 42:\\| "
          + "0:iI 1:nN 2:eE 3:aA 5:,; 4:mM 38:hH 40:tT 37:sS 41:rR 39:'\" "
          + "6:qQ 7:zZ 8:/< 9:.> 11::? 45:bB 46:fF 43:gG 47:vV 44:xX"
      )
    case .mtgapFull:
      map(
        "50:\\^ 18:1~ 19:2[ 20:3{ 21:4< 23:5| 22:6# 26:7> 28:8} 25:9] 29:0% 27:qQ 24:zZ "
          + "12:yY 13:pP 14:oO 15:uU 17:-= 16:kK 32:dD 34:lL 31:cC 35:wW 33:xX 30:/+ 42:$@ "
          + "0:iI 1:nN 2:eE 3:aA 5:,: 4:mM 38:hH 40:tT 37:sS 41:rR 39:\"! "
          + "6:(` 7:)? 8:'* 9:.; 11:_& 45:bB 46:fF 43:gG 47:vV 44:jJ"
      )
    case .ina:
      map(
        "50:`~ 18:1[ 19:2] 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9{ 29:0} 27:qQ 24:xX "
          + "12:!+ 13:pP 14:uU 15:oO 17:-_ 16:jJ 32:bB 34:lL 31:mM 35:yY 33:zZ 30:vV 42:\\| "
          + "0:iI 1:nN 2:eE 3:aA 5:,; 4:dD 38:tT 40:kK 37:rR 41:sS 39:'\" "
          + "6:=( 7:@) 8::< 9:.> 11:?/ 45:gG 46:hH 43:cC 47:wW 44:fF"
      )
    case .soul:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:wW 14:lL 15:dD 17:pP 16:kK 32:mM 34:uU 31:yY 35:;: 33:[{ 30:]} 42:\\| "
          + "0:aA 1:sS 2:rR 3:tT 5:gG 4:fF 38:nN 40:eE 37:iI 41:oO 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:jJ 45:bB 46:hH 43:,< 47:.> 44:/?"
      )
    case .niro:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:wW 14:uU 15:dD 17:pP 16:jJ 32:fF 34:yY 31:lL 35:;: 33:[{ 30:]} 42:\\| "
          + "0:aA 1:sS 2:eE 3:tT 5:gG 4:hH 38:nN 40:iI 37:rR 41:oO 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:kK 46:mM 43:,< 47:.> 44:/?"
      )
    case .typehack:
      map(
        "50:^~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6& 26:7` 28:8( 25:9) 29:0= 27:*+ 24:\\| "
          + "12:jJ 13:gG 14:hH 15:pP 17:fF 16:qQ 32:vV 34:oO 31:uU 35:;: 33:/? 30:[{ 42:]} "
          + "0:rR 1:sS 2:nN 3:tT 5:kK 4:yY 38:iI 40:aA 37:eE 41:lL 39:-_ "
          + "6:zZ 7:wW 8:mM 9:dD 11:bB 45:cC 46:,< 43:'\" 47:.> 44:xX"
      )
    case .isrt:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:yY 13:cC 14:lL 15:mM 17:kK 16:zZ 32:fF 34:uU 31:,< 35:'\" 33:[{ 30:]} 42:\\| "
          + "0:iI 1:sS 2:rR 3:tT 5:gG 4:pP 38:nN 40:eE 37:aA 41:oO 39:;: "
          + "6:qQ 7:vV 8:wW 9:dD 11:jJ 45:bB 46:hH 43:/? 47:.> 44:xX"
      )
    case .isrtAngle:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:yY 13:cC 14:lL 15:mM 17:kK 16:zZ 32:fF 34:uU 31:,< 35:'\" 33:[{ 30:]} 42:\\| "
          + "0:iI 1:sS 2:rR 3:tT 5:gG 4:pP 38:nN 40:eE 37:aA 41:oO 39:;: "
          + "6:vV 7:wW 8:dD 9:jJ 11:qQ 45:bB 46:hH 43:/? 47:.> 44:xX"
      )
    case .engram:
      map(
        "50:[{ 18:1| 19:2= 20:3~ 21:4+ 23:5< 22:6> 26:7^ 28:8& 25:9% 29:0* 27:]} 24:/\\ "
          + "12:bB 13:yY 14:oO 15:uU 17:'( 16:\") 32:lL 34:dD 31:wW 35:vV 33:zZ 30:#$ 42:@` "
          + "0:cC 1:iI 2:eE 3:aA 5:,; 4:.: 38:hH 40:tT 37:sS 41:nN 39:qQ "
          + "6:gG 7:xX 8:jJ 9:kK 11:-_ 45:?! 46:rR 43:mM 47:fF 44:pP"
      )
    case .engrammer:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
          + "12:bB 13:yY 14:oO 15:uU 17:'\" 16:;: 32:lL 34:dD 31:wW 35:vV 33:zZ 30:=+ 42:\\| "
          + "0:cC 1:iI 2:eE 3:aA 5:,< 4:.> 38:hH 40:tT 37:sS 41:nN 39:qQ "
          + "6:gG 7:xX 8:jJ 9:kK 11:-_ 45:/? 46:rR 43:mM 47:fF 44:pP"
      )
    case .semimak:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:fF 13:lL 14:hH 15:vV 17:zZ 16:qQ 32:wW 34:uU 31:oO 35:yY 33:[{ 30:]} 42:\\| "
          + "0:sS 1:rR 2:nN 3:tT 5:kK 4:cC 38:dD 40:eE 37:aA 41:iI 39:;: "
          + "6:xX 7:'\" 8:bB 9:mM 11:jJ 45:pP 46:gG 43:,< 47:.> 44:/?"
      )
    case .semimakJQ:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:fF 13:lL 14:hH 15:vV 17:zZ 16:'\" 32:wW 34:uU 31:oO 35:yY 33:[{ 30:]} 42:\\| "
          + "0:sS 1:rR 2:nN 3:tT 5:kK 4:cC 38:dD 40:eE 37:aA 41:iI 39:;: "
          + "6:xX 7:jJ 8:bB 9:mM 11:qQ 45:pP 46:gG 43:,< 47:.> 44:/?"
      )
    case .semimakJQC:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:fF 13:lL 14:hH 15:vV 17:zZ 16:'\" 32:wW 34:uU 31:oO 35:yY 33:[{ 30:]} 42:\\| "
          + "0:sS 1:rR 2:nN 3:tT 5:kK 4:gG 38:dD 40:eE 37:aA 41:iI 39:;: "
          + "6:xX 7:jJ 8:bB 9:mM 11:qQ 45:pP 46:cC 43:,< 47:.> 44:/?"
      )
    case .canary:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:wW 13:lL 14:yY 15:pP 17:kK 16:zZ 32:xX 34:oO 31:uU 35:;: 33:[{ 30:]} 42:\\| "
          + "0:cC 1:rR 2:sS 3:tT 5:bB 4:fF 38:nN 40:eE 37:iI 41:aA 39:'\" "
          + "6:jJ 7:vV 8:dD 9:gG 11:qQ 45:mM 46:hH 43:/? 47:,< 44:.>"
      )
    case .canaryMatrix:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:wW 13:lL 14:yY 15:pP 17:bB 16:zZ 32:fF 34:oO 31:uU 35:'\" 33:[{ 30:]} 42:\\| "
          + "0:cC 1:rR 2:sS 3:tT 5:gG 4:mM 38:nN 40:eE 37:iI 41:aA 39:;: "
          + "6:qQ 7:jJ 8:vV 9:dD 11:kK 45:xX 46:hH 43:/? 47:,< 44:.>"
      )
    case .boo:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
          + "12:,< 13:.> 14:uU 15:cC 17:vV 16:qQ 32:fF 34:dD 31:lL 35:yY 33:?/ 30:=+ 42:\\| "
          + "0:aA 1:oO 2:eE 3:sS 5:gG 4:bB 38:nN 40:tT 37:rR 41:iI 39:-_ "
          + "6:;: 7:xX 8:'\" 9:wW 11:zZ 45:pP 46:hH 43:mM 47:kK 44:jJ"
      )
    case .booMangle:
      map(
        "50:$~ 18:&% 19:[7 20:{5 21:}3 23:(1 22:=9 26:*0 28:)2 25:+4 29:]6 27:!8 24:#` "
          + "12:,< 13:.> 14:uU 15:cC 17:vV 16:qQ 32:fF 34:dD 31:lL 35:yY 33:/? 30:@^ 42:\\| "
          + "0:aA 1:oO 2:eE 3:sS 5:gG 4:bB 38:nN 40:tT 37:rR 41:iI 39:-_ "
          + "6:xX 7:'\" 8:wW 9:;: 11:zZ 45:pP 46:hH 43:mM 47:kK 44:jJ"
      )
    case .apt:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:wW 13:gG 14:dD 15:fF 17:bB 16:qQ 32:lL 34:uU 31:oO 35:yY 33:[{ 30:]} 42:\\| "
          + "0:rR 1:sS 2:tT 3:hH 5:kK 4:jJ 38:nN 40:eE 37:aA 41:iI 39:;: "
          + "6:xX 7:cC 8:mM 9:pP 11:vV 45:zZ 46:,< 43:.> 47:'\" 44:/?"
      )
    case .aptAngle:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:wW 13:gG 14:dD 15:fF 17:bB 16:qQ 32:lL 34:uU 31:oO 35:yY 33:[{ 30:]} 42:\\| "
          + "0:rR 1:sS 2:tT 3:hH 5:kK 4:jJ 38:nN 40:eE 37:aA 41:iI 39:;: "
          + "6:cC 7:mM 8:pP 9:vV 11:xX 45:zZ 46:,< 43:.> 47:'\" 44:/?"
      )
    case .middlemak:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:wW 14:lL 15:dD 17:gG 16:jJ 32:fF 34:oO 31:uU 35:;: 33:[{ 30:]} 42:\\| "
          + "0:aA 1:sS 2:rR 3:tT 5:pP 4:yY 38:nN 40:eE 37:iI 41:hH 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:kK 46:mM 43:,< 47:.> 44:/?"
      )
    case .middlemakNH:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:wW 14:lL 15:dD 17:gG 16:jJ 32:fF 34:oO 31:uU 35:;: 33:[{ 30:]} 42:\\| "
          + "0:nN 1:sS 2:rR 3:tT 5:pP 4:yY 38:hH 40:eE 37:iI 41:aA 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:kK 46:mM 43:,< 47:.> 44:/?"
      )
    case .foalmak:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:bB 13:xX 14:.> 15:wW 17:vV 16:zZ 32:/? 34:uU 31:tT 35:kK 33:[{ 30:]} 42:\\| "
          + "0:fF 1:oO 2:aA 3:lL 5:sS 4:nN 38:eE 40:iI 37:gG 41:hH 39:;: "
          + "6:pP 7:'\" 8:.> 9:mM 11:cC 45:qQ 46:jJ 43:yY 47:dD 44:rR"
      )
    case .quartz:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:=+ 26:6^ 28:7& 25:8* 29:9( 27:0) 24:-_ "
          + "12:qQ 13:uU 14:aA 15:rR 17:tT 16:zZ 32:/? 34:gG 31:lL 35:yY 33:pP 30:hH 42:\\| "
          + "0:[{ 1:jJ 2:oO 3:bB 5:]} 4:;: 38:vV 40:eE 37:xX 41:'\" 39:dD "
          + "6:cC 7:wW 8:mM 9:,< 11:fF 45:iI 46:nN 43:kK 47:sS 44:.>"
      )
    case .arensito:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:lL 14:.> 15:pP 17:'\" 16:;: 32:fF 34:uU 31:dD 35:kK 33:[{ 30:]} 42:\\| "
          + "0:aA 1:rR 2:eE 3:nN 5:bB 4:gG 38:sS 40:iI 37:tT 41:oO 39:/? "
          + "6:zZ 7:wW 8:,< 9:hH 11:jJ 45:vV 46:cC 43:yY 47:mM 44:xX"
      )
    case .arts:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:lL 14:dD 15:yY 17:gG 16:jJ 32:mM 34:oO 31:uU 35:;: 33:[{ 30:]} 42:\\| "
          + "0:aA 1:rR 2:tT 3:sS 5:cC 4:pP 38:nN 40:eE 37:iI 41:hH 39:/? "
          + "6:zZ 7:xX 8:kK 9:wW 11:vV 45:bB 46:fF 43:'\" 47:,< 44:.>"
      )
    case .capewellDvorak:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
          + "12:'\" 13:,< 14:.> 15:pP 17:yY 16:qQ 32:fF 34:gG 31:rR 35:kK 33:/? 30:=+ 42:\\| "
          + "0:oO 1:aA 2:eE 3:iI 5:uU 4:dD 38:hH 40:tT 37:nN 41:sS 39:-_ "
          + "6:zZ 7:xX 8:cC 9:vV 11:jJ 45:lL 46:mM 43:wW 47:bB 44:;:"
      )
    case .colman:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:lL 14:rR 15:wW 17:bB 16:jJ 32:mM 34:uU 31:yY 35:;: 33:[{ 30:]} 42:\\| "
          + "0:aA 1:nN 2:hH 3:sS 5:fF 4:pP 38:tT 40:eE 37:iI 41:oO 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:kK 45:gG 46:dD 43:,< 47:.> 44:/?"
      )
    case .heart:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:gG 14:dD 15:vV 17:xX 16:jJ 32:yY 34:oO 31:uU 35:;: 33:[{ 30:]} 42:\\| "
          + "0:rR 1:sS 2:tT 3:hH 5:lL 4:pP 38:nN 40:aA 37:iI 41:eE 39:'\" "
          + "6:wW 7:cC 8:bB 9:mM 11:kK 45:zZ 46:fF 43:,< 47:.> 44:/?"
      )
    case .klauser:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:kK 13:,< 14:uU 15:yY 17:pP 16:wW 32:lL 34:mM 31:fF 35:cC 33:[{ 30:]} 42:\\| "
          + "0:oO 1:aA 2:eE 3:iI 5:dD 4:rR 38:nN 40:tT 37:hH 41:sS 39:'\" "
          + "6:qQ 7:.> 8:'\" 9:;: 11:zZ 45:xX 46:vV 43:gG 47:bB 44:jJ"
      )
    case .oneproduct:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:pP 13:lL 14:dD 15:wW 17:gG 16:jJ 32:xX 34:oO 31:yY 35:qQ 33:[{ 30:]} 42:\\| "
          + "0:nN 1:rR 2:sS 3:tT 5:mM 4:uU 38:aA 40:eE 37:iI 41:hH 39:'\" "
          + "6:zZ 7:cC 8:fF 9:vV 11:bB 45:,< 46:.> 43:?|/ 47:;: 44:kK"
      )
    case .pine:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:yY 13:lL 14:rR 15:dD 17:wW 16:jJ 32:mM 34:oO 31:uU 35:,< 33:[{ 30:]} 42:\\| "
          + "0:cC 1:sS 2:nN 3:tT 5:gG 4:pP 38:hH 40:aA 37:eE 41:iI 39:;: "
          + "6:xX 7:zZ 8:qQ 9:vV 11:kK 45:bB 46:fF 43:'\" 47:/? 44:.>"
      )
    case .pineV4:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:lL 14:cC 15:mM 17:kK 16:'\" 32:fF 34:uU 31:oO 35:yY 33:[{ 30:]} 42:\\| "
          + "0:nN 1:rR 2:sS 3:tT 5:wW 4:pP 38:hH 40:eE 37:aA 41:iI 39:/? "
          + "6:jJ 7:xX 8:zZ 9:gG 11:vV 45:bB 46:dD 43:;: 47:,< 44:.>"
      )
    case .three:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:fF 14:uU 15:yY 17:zZ 16:xX 32:kK 34:cC 31:wW 35:bB 33:[{ 30:]} 42:\\| "
          + "0:oO 1:hH 2:eE 3:aA 5:iI 4:dD 38:rR 40:tT 37:nN 41:sS 39:/? "
          + "6:,< 7:mM 8:.> 9:jJ 11:;: 45:gG 46:lL 43:pP 47:vV 44:'\""
      )
    case .asset:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:wW 14:jJ 15:fF 17:gG 16:yY 32:pP 34:uU 31:lL 35:;: 33:[{ 30:]} 42:\\| "
          + "0:aA 1:sS 2:eE 3:tT 5:dD 4:hH 38:nN 40:iI 37:oO 41:rR 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:kK 46:mM 43:,< 47:.> 44:/?"
      )
    case .dwarf:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:vV 13:lL 14:hH 15:kK 17:jJ 16:gG 32:wW 34:oO 31:uU 35:,|> 33:[{ 30:]} 42:\\| "
          + "0:sS 1:rR 2:nN 3:tT 5:mM 4:yY 38:dD 40:aA 37:eE 41:iI 39:/? "
          + "6:xX 7:qQ 8:bB 9:fF 11:zZ 45:pP 46:cC 43:'\" 47:;: 44:.|<"
      )
    case .flaw:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:fF 13:lL 14:aA 15:wW 17:pP 16:zZ 32:kK 34:uU 31:rR 35:/? 33:[{ 30:]} 42:\\| "
          + "0:hH 1:sS 2:oO 3:yY 5:cC 4:mM 38:tT 40:eE 37:nN 41:iI 39:;: "
          + "6:bB 7:jJ 8:'\" 9:gG 11:vV 45:qQ 46:dD 43:.> 47:xX 44:,<"
      )
    case .stndc:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9{ 29:0} 27:([ 24:)] "
          + "12:vV 13:mM 14:hH 15:gG 17:pP 16:xX 32:lL 34:oO 31:uU 35:yY 33:jJ 30:=+ 42:\\| "
          + "0:sS 1:tT 2:nN 3:dD 5:cC 4:wW 38:rR 40:aA 37:eE 41:iI 39:-_ "
          + "6:zZ 7:kK 8:bB 9:fF 11:qQ 45:,; 46:.: 43:'< 47:\"> 44:?!"
      )
    case .uciea:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
          + "12:pP 13:yY 14:uU 15:oO 17:-_ 16:kK 32:dD 34:hH 31:fF 35:xX 33:qQ 30:=+ 42:\\| "
          + "0:cC 1:iI 2:eE 3:aA 5:'/ 4:gG 38:tT 40:nN 37:sS 41:rR 39:vV "
          + "6:zZ 7:\"? 8:,< 9:.> 11:;: 45:wW 46:mM 43:lL 47:bB 44:jJ"
      )
    case .whorf:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:fF 13:lL 14:hH 15:dD 17:mM 16:vV 32:wW 34:oO 31:uU 35:,< 33:[{ 30:]} 42:\\| "
          + "0:sS 1:rR 2:nN 3:tT 5:kK 4:gG 38:yY 40:aA 37:eE 41:iI 39:/? "
          + "6:xX 7:jJ 8:bB 9:zZ 11:qQ 45:pP 46:cC 43:'\" 47:;: 44:.>"
      )
    case .whorf6:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:fF 13:lL 14:hH 15:dD 17:vV 16:zZ 32:gG 34:oO 31:uU 35:.> 33:[{ 30:]} 42:\\| "
          + "0:sS 1:rR 2:nN 3:tT 5:mM 4:pP 38:yY 40:eE 37:iI 41:aA 39:/? "
          + "6:xX 7:jJ 8:bB 9:kK 11:qQ 45:cC 46:wW 43:'\" 47:,< 44:;:"
      )
    case .whorfmax:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
          + "12:fF 13:lL 14:hH 15:yY 17:kK 16:qQ 32:wW 34:oO 31:uU 35:,< 33:-_ 30:=+ 42:\\| "
          + "0:sS 1:rR 2:nN 3:tT 5:pP 4:cC 38:dD 40:aA 37:eE 41:iI 39:/? "
          + "6:xX 7:jJ 8:bB 9:vV 11:zZ 45:mM 46:gG 43:'\" 47:;: 44:.>"
      )
    case .octa8:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:yY 13:oO 14:uU 15:kK 17:xX 16:gG 32:wW 34:dD 31:lL 35:,< 33:[{ 30:]} 42:\\| "
          + "0:iI 1:aA 2:eE 3:nN 5:fF 4:bB 38:sS 40:tT 37:rR 41:cC 39:;: "
          + "6:/? 7:zZ 8:hH 9:'\" 11:qQ 45:vV 46:pP 43:mM 47:jJ 44:.>"
      )
    case .nerps:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:xX 13:lL 14:dD 15:pP 17:vV 16:zZ 32:kK 34:oO 31:uU 35:;: 33:[{ 30:]} 42:\\| "
          + "0:nN 1:rR 2:tT 3:sS 5:gG 4:yY 38:hH 40:eE 37:iI 41:aA 39:/? "
          + "6:jJ 7:mM 8:cC 9:wW 11:qQ 45:bB 46:fF 43:'\" 47:,< 44:.>"
      )
    case .gallium:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:bB 13:lL 14:dD 15:cC 17:vV 16:zZ 32:yY 34:oO 31:uU 35:,< 33:[{ 30:]} 42:\\| "
          + "0:nN 1:rR 2:tT 3:sS 5:gG 4:pP 38:hH 40:aA 37:eE 41:iI 39:/? "
          + "6:qQ 7:xX 8:mM 9:wW 11:jJ 45:kK 46:fF 43:'\" 47:;: 44:.>"
      )
    case .galliumAngle:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:bB 13:lL 14:dD 15:cC 17:jJ 16:zZ 32:yY 34:oO 31:uU 35:,< 33:[{ 30:]} 42:\\| "
          + "0:nN 1:rR 2:tT 3:sS 5:vV 4:pP 38:hH 40:aA 37:eE 41:iI 39:/? "
          + "6:xX 7:mM 8:wW 9:gG 11:qQ 45:kK 46:fF 43:'\" 47:;: 44:.>"
      )
    case .galliumV2:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:bB 13:lL 14:dD 15:cC 17:vV 16:jJ 32:fF 34:oO 31:uU 35:,< 33:[{ 30:]} 42:\\| "
          + "0:nN 1:rR 2:tT 3:sS 5:gG 4:yY 38:hH 40:aA 37:eE 41:iI 39:/? "
          + "6:xX 7:qQ 8:mM 9:wW 11:zZ 45:kK 46:pP 43:'\" 47:;: 44:.>"
      )
    case .nila:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
          + "12:xX 13:dD 14:lL 15:gG 17:vV 16:jJ 32:fF 34:oO 31:uU 35:,< 33:;: 30:=+ 42:\\| "
          + "0:rR 1:tT 2:nN 3:sS 5:bB 4:qQ 38:hH 40:aA 37:eE 41:iI 39:-_ "
          + "6:kK 7:mM 8:cC 9:wW 11:zZ 45:pP 46:yY 43:'\" 47:/? 44:.>"
      )
    case .noctum:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:bB 13:gG 14:dD 15:lL 17:qQ 16:jJ 32:fF 34:oO 31:uU 35:,< 33:[{ 30:]} 42:\\| "
          + "0:nN 1:sS 2:tT 3:rR 5:kK 4:yY 38:cC 40:aA 37:eE 41:iI 39:/? "
          + "6:vV 7:mM 8:hH 9:xX 11:zZ 45:pP 46:wW 43:'\" 47:;: 44:.>"
      )
    case .cascade:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
          + "12:wW 13:cC 14:dD 15:lL 17:kK 16:jJ 32:/? 34:uU 31:oO 35:yY 33:;: 30:=+ 42:\\| "
          + "0:rR 1:sS 2:tT 3:hH 5:vV 4:bB 38:nN 40:eE 37:aA 41:iI 39:.< "
          + "6:qQ 7:zZ 8:gG 9:mM 11:xX 45:pP 46:fF 43:'\" 47:,> 44:-_"
      )
    case .vylet:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
          + "12:wW 13:cC 14:mM 15:pP 17:bB 16:xX 32:lL 34:oO 31:uU 35:jJ 33:-_ 30:=+ 42:\\| "
          + "0:rR 1:sS 2:tT 3:hH 5:fF 4:yY 38:nN 40:aA 37:eE 41:iI 39:,> "
          + "6:qQ 7:vV 8:gG 9:dD 11:kK 45:zZ 46:/? 43:'\" 47:;: 44:.<"
      )
    case .romak:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:bB 14:mM 15:gG 17:kK 16:xX 32:lL 34:oO 31:uU 35:;: 33:[{ 30:]} 42:\\| "
          + "0:dD 1:nN 2:sS 3:tT 5:wW 4:zZ 38:rR 40:aA 37:eE 41:iI 39:'\" "
          + "6:yY 7:fF 8:cC 9:pP 11:vV 45:jJ 46:hH 43:,< 47:.> 44:/?"
      )
    case .scythe:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:bB 13:uU 14:aA 15:rR 17:jJ 16:gG 32:wW 34:dD 31:yY 35:'\" 33:[{ 30:]} 42:\\| "
          + "0:sS 1:iI 2:oO 3:nN 5:lL 4:cC 38:mM 40:tT 37:hH 41:eE 39:;: "
          + "6:qQ 7:,< 8:.> 9:xX 11:zZ 45:vV 46:fF 43:pP 47:kK 44:/?"
      )
    case .inqwerted:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:tT 13:rR 14:eE 15:wW 17:qQ 16:pP 32:oO 34:iI 31:uU 35:yY 33:[{ 30:]} 42:\\| "
          + "0:gG 1:fF 2:dD 3:sS 5:aA 4:;: 38:lL 40:kK 37:jJ 41:hH 39:'\" "
          + "6:bB 7:vV 8:cC 9:xX 11:zZ 45:/? 46:.> 43:,< 47:mM 44:nN"
      )
    case .rain:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:fF 13:dD 14:lL 15:gG 17:vV 16:qQ 32:rR 34:uU 31:oO 35:,< 33:[{ 30:]} 42:\\| "
          + "0:sS 1:tT 2:hH 3:cC 5:yY 4:jJ 38:nN 40:eE 37:aA 41:iI 39:/? "
          + "6:zZ 7:kK 8:mM 9:pP 11:wW 45:xX 46:bB 43:;: 47:'\" 44:.>"
      )
    case .night:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:=+ 24:\\| "
          + "12:bB 13:fF 14:lL 15:kK 17:qQ 16:'\" 32:gG 34:oO 31:uU 35:.> 33:;: 30:[{ 42:]} "
          + "0:nN 1:sS 2:hH 3:tT 5:mM 4:yY 38:cC 40:aA 37:eE 41:iI 39:/? "
          + "6:vV 7:jJ 8:dD 9:rR 11:zZ 45:pP 46:wW 43:xX 47:-_ 44:,<"
      )
    case .nightSTIC:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:bB 13:fF 14:lL 15:dD 17:vV 16:yY 32:pP 34:oO 31:uU 35:/? 33:[{ 30:]} 42:\\| "
          + "0:nN 1:sS 2:hH 3:tT 5:mM 4:gG 38:cC 40:aA 37:eE 41:iI 39:-_ "
          + "6:qQ 7:xX 8:jJ 9:kK 11:zZ 45:'\" 46:wW 43:,< 47:;: 44:.>"
      )
    case .whix2:
      withSuppressedKeys(
        map(
          "50:1! 18:2@ 19:3# 20:4$ 21:5% 23:6^ 22:7& 26:8* 28:9( 25:0) "
            + "12:bB 13:lL 14:nN 15:dD 17:kK 16:'\" 32:fF 34:oO 31:uU 35:jJ "
            + "0:sS 1:hH 2:rR 3:tT 5:wW 4:yY 38:cC 40:aA 37:eE 41:iI "
            + "6:qQ 7:xX 8:mM 9:vV 11:zZ 45:pP 46:gG 43:,< 47:.> 44:/?"
        ),
        keyCodes: [29, 27, 24, 33, 30, 42, 39]
      )
    case .haruka:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:uU 14:oO 15:pP 17:zZ 16:vV 32:fF 34:dD 31:lL 35:mM 33:[{ 30:]} 42:\\| "
          + "0:iI 1:eE 2:aA 3:nN 5:bB 4:gG 38:sS 40:tT 37:rR 41:cC 39:'\" "
          + "6:,< 7:/? 8:.> 9:hH 11:;: 45:jJ 46:yY 43:kK 47:xX 44:wW"
      )
    case .kuntum:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:vV 13:lL 14:nN 15:dD 17:kK 16:jJ 32:wW 34:oO 31:uU 35:,< 33:[{ 30:]} 42:\\| "
          + "0:tT 1:sS 2:rR 3:hH 5:fF 4:gG 38:cC 40:aA 37:eE 41:iI 39:;: "
          + "6:zZ 7:xX 8:pP 9:bB 11:'\" 45:mM 46:yY 43:qQ 47:/? 44:.>"
      )
    case .kuntem:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:vV 13:lL 14:nN 15:dD 17:kK 16:jJ 32:wW 34:oO 31:uU 35:qQ 33:[{ 30:]} 42:\\| "
          + "0:tT 1:sS 2:rR 3:hH 5:fF 4:gG 38:cC 40:aA 37:iI 41:eE 39:;: "
          + "6:zZ 7:xX 8:pP 9:bB 11:'\" 45:mM 46:yY 43:.> 47:,< 44:/?"
      )
    case .kuntemJQ:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:vV 13:lL 14:nN 15:dD 17:kK 16:qQ 32:wW 34:oO 31:uU 35:jJ 33:[{ 30:]} 42:\\| "
          + "0:tT 1:sS 2:rR 3:hH 5:fF 4:gG 38:cC 40:aA 37:iI 41:eE 39:;: "
          + "6:zZ 7:xX 8:pP 9:bB 11:'\" 45:mM 46:yY 43:.> 47:,< 44:/?"
      )
    case .beaklZi:
      withThumbKey(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:zZ 13:yY 14:oO 15:uU 17:;: 16:gG 32:dD 34:nN 31:mM 35:xX 33:[{ 30:]} 42:\\| "
            + "0:qQ 1:hH 2:eE 3:aA 5:.> 4:cC 38:tT 40:rR 37:sS 41:wW 39:'\" "
            + "6:jJ 7:-_ 8:'\" 9:kK 11:,< 45:bB 46:pP 43:lL 47:fF 44:vV"
        ), normal: "i", shifted: "I")
    case .snorkle:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:,< 13:aA 14:yY 15:cC 17:vV 16:qQ 32:dD 34:lL 31:uU 35:xX 33:[{ 30:]} 42:\\| "
          + "0:iI 1:oO 2:nN 3:sS 5:bB 4:pP 38:tT 40:hH 37:eE 41:rR 39:;: "
          + "6:.> 7:'\" 8:fF 9:gG 11:jJ 45:kK 46:wW 43:mM 47:;: 44:zZ"
      )
    case .maltron:
      withThumbKey(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:qQ 13:pP 14:yY 15:cC 17:bB 16:vV 32:mM 34:uU 31:zZ 35:lL 33:[{ 30:]} 42:\\| "
            + "0:aA 1:nN 2:iI 3:sS 5:fF 4:dD 38:tT 40:hH 37:oO 41:rR 39:'\" "
            + "6:,< 7:.> 8:jJ 9:gG 11:'\" 45:/? 46:wW 43:kK 47:-_ 44:xX"
        ), normal: "e", shifted: "E")
    case .prsten:
      withThumbKey(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:`~ 13:wW 14:cC 15:dD 17:fF 16:qQ 32:lL 34:uU 31:yY 35:;: 33:[{ 30:]} 42:\\| "
            + "0:pP 1:rR 2:sS 3:tT 5:gG 4:mM 38:nN 40:aA 37:iI 41:oO 39:'\" "
            + "6:xX 7:hH 8:vV 9:bB 11:[{ 45:,< 46:jJ 43:kK 47:zZ 44:.>"
        ), normal: " ", shifted: " ")
    case .rsthd:
      withThumbKey(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:jJ 13:cC 14:yY 15:fF 17:kK 16:zZ 32:lL 34:,< 31:uU 35:qQ 33:[{ 30:]} 42:\\| "
            + "0:rR 1:sS 2:tT 3:hH 5:dD 4:mM 38:nN 40:aA 37:iI 41:oO 39:'\" "
            + "6:/? 7:vV 8:gG 9:pP 11:bB 45:xX 46:wW 43:.> 47:;: 44:-_"
        ), normal: "e", shifted: "E")
    case .handsDownPromethium:
      withBaseFallbackOptionLayers(
        withThumbKey(
          map(
            "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
              + "12:fF 13:pP 14:dD 15:lL 17:xX 16:;: 32:uU 34:oO 31:yY 35:bB 33:zZ 30:]} 42:\\| "
              + "0:sS 1:nN 2:tT 3:hH 5:kK 4:,< 38:aA 40:eE 37:iI 41:cC 39:qQ "
              + "6:vV 7:wW 8:gG 9:mM 11:jJ 45:-_ 46:.> 43:'\" 47:=+ 44:/?"
          ), normal: "r", shifted: "R"),
        overrides: [:])
    case .statica3x5:
      withBaseFallbackOptionLayers(
        map(
          "50:\"' 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:ьЬ 13:уУ 14:аА 15:жЖ 17:юЮ 16:гГ 32:бБ 34:рР 31:лЛ 35:хХ 33:,; 30:.: 42:\\| "
            + "0:иИ 1:еЕ 2:оО 3:кК 5:яЯ 4:мМ 38:тТ 40:сС 37:нН 41:зЗ 39:.: "
            + "6:фФ 7:эЭ 8:ыЫ 9:пП 11:йЙ 45:дД 46:вВ 43:чЧ 47:шШ 44:цЦ"
        ),
        overrides: [12: ("ъ", "Ъ"), 1: ("ё", "Ё"), 47: ("щ", "Щ")]
      )
    case .vestnik:
      withBaseFallbackOptionLayers(
        map(
          "50:\"' 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:цЦ 13:дД 14:рР 15:гГ 17:хХ 16:фФ 32:пП 34:аА 31:яЯ 35:эЭ 33:,; 30:.: 42:\\| "
            + "0:сС 1:тТ 2:нН 3:кК 5:бБ 4:ьЬ 38:вВ 40:оО 37:еЕ 41:иИ 39:.: "
            + "6:шШ 7:зЗ 8:лЛ 9:мМ 11:чЧ 45:жЖ 46:йЙ 43:ыЫ 47:уУ 44:юЮ"
        ),
        overrides: [4: ("ъ", "Ъ"), 37: ("ё", "Ё"), 6: ("щ", "Щ")]
      )
    case .diktor:
      withBaseFallbackOptionLayers(
        map(
          "50:ёЁ 18:1Ъ 19:2Ь 20:3№ 21:4% 23:5: 22:6; 26:7- 28:8\" 25:9( 29:0) 27:*_ 24:=+ "
            + "12:цЦ 13:ьъ 14:яЯ 15:,? 17:.! 16:зЗ 32:вВ 34:кК 31:дД 35:чЧ 33:шШ 30:щЩ 42:\\/ "
            + "0:уУ 1:иИ 2:еЕ 3:оО 5:аА 4:лЛ 38:нН 40:тТ 37:сС 41:рР 39:йЙ "
            + "6:фФ 7:эЭ 8:хХ 9:ыЫ 11:юЮ 45:бБ 46:мМ 43:пП 47:гГ 44:жЖ"
        ), overrides: [:])
    case .diktorVoronovMod:
      withBaseFallbackOptionLayers(
        map(
          "50:ёЁ 18:1% 19:2№ 20:3\" 21:4. 23:5: 22:6; 26:7- 28:8, 25:9( 29:0) 27:*_ 24:=+ "
            + "12:фФ 13:ьЬ 14:хХ 15:яЯ 17:ыЫ 16:зЗ 32:вВ 34:кК 31:дД 35:чЧ 33:шШ 30:щЩ 42:\\/ "
            + "0:уУ 1:иИ 2:еЕ 3:оО 5:аА 4:лЛ 38:нН 40:тТ 37:сС 41:рР 39:йЙ "
            + "6:?! 7:ъЪ 8:эЭ 9:юЮ 11:цЦ 45:бБ 46:мМ 43:пП 47:гГ 44:жЖ"
        ), overrides: [:])
    case .redaktor:
      withBaseFallbackOptionLayers(
        map(
          "50:ёЁ 18:1№ 19:2: 20:3; 21:4/ 23:5₽ 22:6@ 26:7ё 28:8? 25:9! 29:0% 27:ЪЬ 24:=+ "
            + "12:цЦ 13:ыЫ 14:яЯ 15:йЙ 17:ьъ 16:зЗ 32:дД 34:вВ 31:кК 35:гГ 33:шШ 30:щЩ 42:\\/ "
            + "0:уУ 1:иИ 2:оО 3:еЕ 5:аА 4:лЛ 38:рР 40:тТ 37:нН 41:сС 39:хХ "
            + "6:фФ 7:юЮ 8:эЭ 9:,- 11:.\" 45:чЧ 46:мМ 43:пП 47:бБ 44:жЖ"
        ), overrides: [:])
    case .juiyaf:
      withBaseFallbackOptionLayers(
        map(
          "50:ёЁ 18:1! 19:2\" 20:3№ 21:4; 23:5% 22:6: 26:7? 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:йЙ 13:уУ 14:иИ 15:яЯ 17:фФ 16:хХ 32:жЖ 34:рР 31:., 35:шШ 33:цЦ 30:ЬЪ 42:\\/ "
            + "0:вВ 1:еЕ 2:аА 3:оО 5:чЧ 4:гГ 38:тТ 40:нН 37:сС 41:дД 39:бБ "
            + "6:ьъ 7:эЭ 8:юЮ 9:ыЫ 11:щЩ 45:пП 46:кК 43:лЛ 47:зЗ 44:мМ"
        ), overrides: [:])
    case .zubachev:
      withBaseFallbackOptionLayers(
        map(
          "50:ёЁ 18:1! 19:2\" 20:3№ 21:4; 23:5% 22:6: 26:7? 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:фФ 13:ыЫ 14:аА 15:яЯ 17:,Ъ 16:йЙ 32:мМ 34:рР 31:пП 35:хХ 33:цЦ 30:щЩ 42:\\/ "
            + "0:гГ 1:иИ 2:еЕ 3:оО 5:уУ 4:лЛ 38:тТ 40:сС 37:нН 41:зЗ 39:жЖ "
            + "6:шШ 7:ьъ 8:юЮ 9:.Ь 11:эЭ 45:бБ 46:дД 43:вВ 47:кК 44:чЧ"
        ), overrides: [:])
    case .colemakQix:
      withBaseFallbackOptionLayers(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:=+ 24:[{ "
            + "12:;: 13:lL 14:cC 15:mM 17:kK 16:jJ 32:fF 34:uU 31:yY 35:qQ 33:-_ 30:]} 42:\\| "
            + "0:aA 1:rR 2:sS 3:tT 5:gG 4:pP 38:nN 40:eE 37:iI 41:oO 39:'\" "
            + "6:xX 7:wW 8:dD 9:vV 11:zZ 45:bB 46:hH 43:/? 47:.> 44:,<"
        ), overrides: [:])
    case .colemakQi:
      withBaseFallbackOptionLayers(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:=+ 24:[{ "
            + "12:qQ 13:lL 14:wW 15:mM 17:kK 16:jJ 32:fF 34:uU 31:yY 35:'\" 33:-_ 30:]} 42:\\| "
            + "0:aA 1:rR 2:sS 3:tT 5:gG 4:pP 38:nN 40:eE 37:iI 41:oO 39:;: "
            + "6:zZ 7:xX 8:cC 9:dD 11:vV 45:bB 46:hH 43:,< 47:.> 44:/?"
        ), overrides: [:])
    case .colemaQ:
      withBaseFallbackOptionLayers(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:=+ 24:[{ "
            + "12:;: 13:wW 14:fF 15:pP 17:bB 16:jJ 32:lL 34:uU 31:yY 35:qQ 33:-_ 30:]} 42:\\| "
            + "0:aA 1:rR 2:sS 3:tT 5:gG 4:mM 38:nN 40:eE 37:iI 41:oO 39:'\" "
            + "6:xX 7:cC 8:dD 9:kK 11:zZ 45:vV 46:hH 43:/? 47:.> 44:,<"
        ), overrides: [:])
    case .colemaQF:
      withBaseFallbackOptionLayers(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:=+ 24:[{ "
            + "12:;: 13:wW 14:gG 15:pP 17:bB 16:jJ 32:lL 34:uU 31:yY 35:qQ 33:-_ 30:]} 42:\\| "
            + "0:aA 1:rR 2:sS 3:tT 5:fF 4:mM 38:nN 40:eE 37:iI 41:oO 39:'\" "
            + "6:xX 7:cC 8:dD 9:kK 11:zZ 45:vV 46:hH 43:/? 47:.> 44:,<"
        ), overrides: [:])
    case .thaiManoonchai:
      withBaseFallbackOptionLayers(
        baseShiftMap(
          keyRows: physicalRows,
          normalRows: [
            ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
            ["ใ", "ต", "ห", "ล", "ส", "ป", "ั", "ก", "ิ", "บ", "็", "ฬ", "ฯ"],
            ["ง", "เ", "ร", "น", "ม", "อ", "า", "่", "้", "ว", "ื"],
            ["ุ", "ไ", "ท", "ย", "จ", "ค", "ี", "ด", "ะ", "ู"],
          ],
          shiftedRows: [
            ["~", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+"],
            ["ฒ", "ฏ", "ซ", "ญ", "ฟ", "ฉ", "ึ", "ธ", "ฐ", "ฎ", "ฆ", "ฑ", "ฌ"],
            ["ษ", "ถ", "แ", "ช", "พ", "ผ", "ำ", "ข", "โ", "ภ", "\""],
            ["ฤ", "ฝ", "ๆ", "ณ", "๊", "๋", "์", "ศ", "ฮ", "?"],
          ]
        ), overrides: [:])
    case .brasileiroNativo:
      withBaseFallbackOptionLayers(
        map(
          "50:=+ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6¨ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
            + "12:/? 13:,< 14:.> 15:hH 17:xX 16:wW 32:lL 34:tT 31:cC 35:pP 33:~^ 30:-_ "
            + "0:iI 1:eE 2:aA 3:oO 5:uU 4:mM 38:dD 40:sS 37:rR 41:nN 39:´` 42:'\" "
            + "10:;: 6:yY 7:çÇ 8:jJ 9:bB 11:kK 45:qQ 46:vV 43:gG 47:fF 44:zZ"
        ), overrides: [:])
    case .beakl15:
      withBaseFallbackOptionLayers(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:qQ 13:hH 14:oO 15:uU 17:xX 16:gG 32:cC 34:rR 31:fF 35:zZ 33:[{ 30:]} 42:\\| "
            + "0:yY 1:iI 2:eE 3:aA 5:.> 4:dD 38:sS 40:tT 37:nN 41:bB 39:;: "
            + "6:jJ 7:/? 8:,< 9:kK 11:'\" 45:wW 46:mM 43:lL 47:pP 44:vV"
        ), overrides: [:])
    case .beakl19:
      withBaseFallbackOptionLayers(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:qQ 13:.> 14:oO 15:uU 17:jJ 16:wW 32:dD 34:nN 31:mM 35:,< 33:[{ 30:]} 42:\\| "
            + "0:hH 1:aA 2:eE 3:iI 5:kK 4:gG 38:sS 40:rR 37:tT 41:pP 39:;: "
            + "6:zZ 7:'\" 8:/? 9:yY 11:xX 45:bB 46:cC 43:lL 47:fF 44:vV"
        ), overrides: [:])
    case .beakl19Bis:
      withBaseFallbackOptionLayers(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:qQ 13:yY 14:oO 15:uU 17:zZ 16:wW 32:dD 34:nN 31:cC 35:kK 33:[{ 30:]} 42:\\| "
            + "0:hH 1:iI 2:eE 3:aA 5:,< 4:gG 38:tT 40:rR 37:sS 41:pP 39:;: "
            + "6:jJ 7:'\" 8:/? 9:.> 11:xX 45:vV 46:mM 43:lL 47:fF 44:bB"
        ), overrides: [:])
    case .rolll:
      withBaseFallbackOptionLayers(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
            + "12:yY 13:oO 14:uU 15:wW 17:bB 16:xX 32:kK 34:cC 31:lL 35:vV 33:[{ 30:]} 42:\\| "
            + "0:iI 1:aA 2:eE 3:nN 5:pP 4:dD 38:hH 40:sS 37:rR 41:tT 39:'\" "
            + "6:jJ 7:/? 8:,< 9:.> 11:qQ 45:fF 46:mM 43:gG 47:'\" 44:zZ"
        ), overrides: [:])
    case .whorfmaxOrtho:
      withBaseFallbackOptionLayers(
        map(
          "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
            + "12:fF 13:lL 14:hH 15:yY 17:zZ 16:qQ 32:wW 34:oO 31:uU 35:,< 33:-_ 30:=+ 42:\\| "
            + "0:sS 1:rR 2:nN 3:tT 5:pP 4:cC 38:dD 40:aA 37:eE 41:iI 39:/? "
            + "6:xX 7:jJ 8:bB 9:vV 11:kK 45:mM 46:gG 43:'\" 47:;: 44:.>"
        ), overrides: [:])
    case .neo:
      withBaseFallbackOptionLayers(
        baseShiftMap(
          keyRows: [
            physicalRows[0], Array(physicalRows[1].dropLast()), physicalRows[2] + [42],
            [10] + physicalRows[3],
          ],
          normalRows: [
            ["^", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "`"],
            ["x", "v", "l", "c", "w", "k", "h", "g", "f", "q", "ß", "'"],
            ["u", "i", "a", "e", "o", "s", "n", "r", "t", "d", "y", " "],
            [" ", "ü", "ö", "ä", "p", "z", "b", "m", ",", ".", "j"],
          ],
          shiftedRows: [
            ["ˇ", "°", "§", "ℓ", "»", "«", "$", "€", "„", "“", "”", "—", "¸"],
            ["X", "V", "L", "C", "W", "K", "H", "G", "F", "Q", "ẞ", "~"],
            ["U", "I", "A", "E", "O", "S", "N", "R", "T", "D", "Y", " "],
            [" ", "Ü", "Ö", "Ä", "P", "Z", "B", "M", "–", "•", "J"],
          ]
        ), overrides: [:])
    case .bone:
      withBaseFallbackOptionLayers(
        isoBaseShiftMap(
          normal: ["^1234567890-`", "jduaxphlmwß'", "ctieobnrsgq ", " fvüäöyz,.k"],
          shifted: ["ˇ°§ℓ»«$€„“”—¸", "JDUAXPHLMWẞ~", "CTIEOBNRSGQ ", " FVÜÄÖYZ–•K"]
        ), overrides: [:])
    case .adnw:
      withBaseFallbackOptionLayers(
        isoBaseShiftMap(
          normal: ["^1234567890-`", "kuü.ävgcljf'", "hieaodtrnsß ", " xyö,qbpwmz"],
          shifted: ["ˇ°§ℓ»«$€„“”—¸", "KUÜ•ÄVGCLJF~", "HIEAODTRNSẞ ", " XYÖ–QBPWMZ"]
        ), overrides: [:])
    case .mine:
      withBaseFallbackOptionLayers(
        isoBaseShiftMap(
          normal: ["^1234567890-`", "jluaqwbdgyzß", "crieomntsh '", " vxüäöpf,.k"],
          shifted: ["ˇ°§ℓ»«$€„“”—¸", "JLUAQWBDGYZẞ", "CRIEOMNTSH ~", " VXÜÄÖPF–•K"]
        ), overrides: [:])
    case .noted:
      withBaseFallbackOptionLayers(
        isoBaseShiftMap(
          normal: ["^1234567890-`", "zyuaqpbmlfjß", "csieodtnrh '", " vxüäöwg,.k"],
          shifted: ["ˇ°§ℓ»«$€„“”—¸", "ZYUAQPBMLFJẞ", "CSIEODTNRH ~", " VXÜÄÖWG–•K"]
        ), overrides: [:])
    case .koy:
      withBaseFallbackOptionLayers(
        isoBaseShiftMap(
          normal: ["^1234567890-`", "k.o,yvgclßz'", "haeiudtrnsf ", " xqäüöbpwmj"],
          shifted: ["ˇ°§ℓ»«$€„“”—¸", "K•O–YVGCLẞZ~", "HAEIUDTRNSF ", " XQÄÜÖBPWMJ"]
        ), overrides: [:])
    case .threeL:
      withBaseFallbackOptionLayers(
        ansiBaseShiftMap(
          normal: [" 1234567890  ", "qfuyzxkcwb   ", "oheaidrtns ", ",m.j;glpv "],
          shifted: [" 1234567890  ", "QFUYZXKCWB   ", "OHEAIDRTNS ", ",M.J;GLPV "]
        ), overrides: [:])
    case .korean:
      withBaseFallbackOptionLayers(
        ansiBaseShiftMap(
          normal: ["`1234567890-=", "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ[]\\", "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ;'", "ㅋㅌㅊㅍㅠㅜㅡ,./"],
          shifted: ["~!@#$%^&*()_+", "ㅃㅉㄸㄲㅆㅛㅕㅑㅒㅖ{}|", "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ:\"", "ㅋㅌㅊㅍㅠㅜㅡ<>?"]
        ), overrides: [:])
    case .ekvertoB:
      withBaseFallbackOptionLayers(
        isoBaseShiftMap(
          normal: ["`1234567890-=", "ŝĝertŭuiopĵĥ", "asdfghjkl;'\\", "<zĉcvbnm,./"],
          shifted: ["~!@#$%^&*()_+", "ŜĜERTŬUIOPĴĤ", "ASDFGHJKL:\"|", ">ZĈCVBNM<>?"]
        ), overrides: [:])
    case .sturdyAngleANSI:
      withBaseFallbackOptionLayers(
        ansiBaseShiftMap(
          normal: ["`1234567890-=", "vmlcpxfouj[]\\", "strdy.naei/", "kqgwzbh';,"],
          shifted: ["~!@#$%^&*<>_+", "VMLCPXFOUJ{}|", "STRDY(NAEI?", "KQGWZBH\":)"]
        ), overrides: [:])
    case .sturdyAngleISO:
      withBaseFallbackOptionLayers(
        isoBaseShiftMap(
          normal: ["`1234567890-=", "vmlcpxfouj[]", "strdy.naei/\\", "zkqgw!bh';,"],
          shifted: ["~!@#$%^&*<>_+", "VMLCPXFOUJ{}", "STRDY(NAEI?|", "ZKQGW?BH\":)"]
        ), overrides: [:])
    case .sturdyOrtho:
      withBaseFallbackOptionLayers(
        ansiBaseShiftMap(
          normal: ["`1234567890-=", "vmlcpxfouj[]\\", "strdy.naei/", "zkqgwbh';,"],
          shifted: ["~!@#$%^&*()_+", "VMLCPXFOUJ{}|", "STRDY>NAEI?", "ZKQGWBH\":<"]
        ), overrides: [:])
    case .hiYou:
      withBaseFallbackOptionLayers(
        isoBaseShiftMap(
          normal: ["`1234567890[]", "kyou'vdlpw/|", "hiea-cstnrx\\", "qj,.;fgmbz="],
          shifted: ["~!@#$%¨&*(){}", "KYOU\"VDLPW?|", "HIEA_CSTNRX\\", "QJ<>:FGMBZ+"]
        ), overrides: [:])
    case .xenia:
      withBaseFallbackOptionLayers(
        ansiBaseShiftMap(
          normal: ["`1234567890-=", ",ourqjfdvg[]\\", "iaenxyhtsc/", ".';lzkpmbw"],
          shifted: ["~!@#$%^&*()_+", "<OURQJFDVG{}|", "IAENXYHTSC?", ">\":LZKPMBW"]
        ), overrides: [:])
    case .xeniaAlt:
      withBaseFallbackOptionLayers(
        ansiBaseShiftMap(
          normal: ["`1234567890-=", "gvdfjqruo'[]\\", "csthylneai;", "wbmpkzx,./"],
          shifted: ["~!@#$%^&*()_+", "GVDFJQRUO\"{}|", "CSTHYLNEAI:", "WBMPKZX<>?"]
        ), overrides: [:])
    case .burmese:
      withBaseFallbackOptionLayers(
        baseShiftMap(
          keyRows: physicalRows,
          normalRows: [
            ["ၐ", "၁", "၂", "၃", "၄", "၅", "၆", "၇", "၈", "၉", "၀", "-", "="],
            ["ဆ", "တ", "န", "မ", "အ", "ပ", "က", "င", "သ", "စ", "ဟ", "ဩ", "\\"],
            ["ေ", "ျ", "ိ", "်", "ါ", "့", "ြ", "ု", "ူ", "း", "'"],
            ["ဖ", "ထ", "ခ", "လ", "ဘ", "ည", "ာ", ",", ".", "/"],
          ],
          shiftedRows: [
            ["ဎ", "ဍ", "ၒ", "ဋ", "ၓ", "ၔ", "ၕ", "ရ", "*", "(", ")", "_", "+"],
            ["ဈ", "ဝ", "ဣ", "၎", "ဤ", "၌", "ဥ", "၍", "ဿ", "ဏ", "ဧ", "ဪ", "|"],
            ["ဗ", "ှ", "ီ", "္", "ွ", "ံ", "ဲ", "ဒ", "ဓ", "ဂ", "\""],
            ["ဇ", "ဌ", "ဃ", "ဠ", "ယ", "ဉ", "ဦ", "၊", "။", "?"],
          ]
        ), overrides: [:])
    case .galliumV2Matrix:
      withBaseFallbackOptionLayers(
        ansiBaseShiftMap(
          normal: ["`1234567890-=", "bldcvjyou,[]\\", "nrtsgphaei/", "xqmwzkf';."],
          shifted: ["~!@#$%^&*()_+", "BLDCVJYOU<{}|", "NRTSGPHAEI?", "XQMWZKF\":>"]
        ), overrides: [:])
    case .galliumNL:
      withBaseFallbackOptionLayers(
        ansiBaseShiftMap(
          normal: ["`1234567890-=", "bldcvypuo,[]\\", "nrtswfheai/", "xqmgjzk';."],
          shifted: ["~!@#$%^&*()_+", "BLDCVYPUO<{}|", "NRTSWFHEAI?", "XQMGJZK\":>"]
        ), overrides: [:])
    case .maya:
      withBaseFallbackOptionLayers(
        ansiBaseShiftMap(
          normal: ["`1234567890[]", "bldgqjfou,;=\\", "nrtsvkhaei-", "xmcwzpy'/."],
          shifted: ["~!@#$%^&*(){}", "BLDGQJFOU<:+|", "NRTSVKHAEI_", "XMCWZPY\"?>"]
        ), overrides: [:])
    case .gallayaAngleANSI:
      withBaseFallbackOptionLayers(
        ansiBaseShiftMap(
          normal: ["`1234567890-=", "bldcqjfou,[]\\", "nrtsgphaei/", "xmwvzky';."],
          shifted: ["~!@#$%^&*()_+", "BLDCQJFOU<{}|", "NRTSGPHAEI?", "XMWVZKY\":>"]
        ), overrides: [:])
    case .gallayaAngleISO:
      withBaseFallbackOptionLayers(
        isoBaseShiftMap(
          normal: ["`1234567890-=", "bldczjfou,[]", "nrtsgphaei/#", "qxmwv\\ky';."],
          shifted: ["¬!\"£$%^&*()_+", "BLDCZJFOU<{}", "NRTSGPHAEI?~", "QXMWV|KY@:>"]
        ), overrides: [:])
    case .real:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
          + "12:yY 13:lL 14:uU 15:oO 17:.> 16:zZ 32:fF 34:hH 31:cC 35:wW 33:/? 30:=+ 42:\\| "
          + "0:iI 1:rR 2:eE 3:aA 5:,< 4:dD 38:tT 40:nN 37:sS 41:mM 39:-_ "
          + "6:;: 7:jJ 8:'\" 9:qQ 11:xX 45:pP 46:kK 43:bB 47:gG 44:vV"
      )
    case .sertain:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:xX 13:lL 14:dD 15:kK 17:vV 16:zZ 32:wW 34:oO 31:uU 35:;: 33:[{ 30:]} 42:\\| "
          + "0:sS 1:rR 2:tT 3:nN 5:fF 4:gG 38:yY 40:eE 37:iI 41:aA 39:/? "
          + "6:qQ 7:jJ 8:mM 9:hH 11:bB 45:pP 46:cC 43:'\" 47:,< 44:.>"
      )
    case .ctgap:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:pP 14:lL 15:cC 17:jJ 16:xX 32:fF 34:oO 31:uU 35:/? 33:[{ 30:]} 42:\\| "
          + "0:rR 1:nN 2:tT 3:sS 5:gG 4:yY 38:hH 40:eE 37:iI 41:aA 39:;: "
          + "6:zZ 7:bB 8:mM 9:wW 11:vV 45:kK 46:dD 43:'\" 47:,< 44:.>"
      )
    case .graphite:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
          + "12:bB 13:lL 14:dD 15:wW 17:zZ 16:'|_ 32:fF 34:oO 31:uU 35:jJ 33:;: 30:=+ 42:\\| "
          + "0:nN 1:rR 2:tT 3:sS 5:gG 4:yY 38:hH 40:aA 37:eE 41:iI 39:,|? "
          + "6:qQ 7:xX 8:mM 9:cC 11:vV 45:kK 46:pP 43:.> 47:-|\" 44:/|<"
      )
    case .focal:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:vV 13:lL 14:hH 15:gG 17:kK 16:qQ 32:fF 34:oO 31:uU 35:jJ 33:[{ 30:]} 42:\\| "
          + "0:sS 1:rR 2:nN 3:tT 5:bB 4:yY 38:cC 40:aA 37:eE 41:iI 39:/? "
          + "6:zZ 7:xX 8:mM 9:dD 11:pP 45:'\" 46:wW 43:.> 47:;: 44:,<"
      )
    case .zenith:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:fF 13:oO 14:uU 15:rR 17:zZ 16:wW 32:vV 34:jJ 31:lL 35:dD 33:[{ 30:]} 42:\\| "
          + "0:yY 1:aA 2:iI 3:nN 5:cC 4:gG 38:sS 40:eE 37:hH 41:tT 39:/? "
          + "6:'\" 7:.> 8:,< 9:bB 11:xX 45:mM 46:pP 43:qQ 47:kK 44:;:"
      )
    case .dhorf:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:vV 13:lL 14:hH 15:kK 17:qQ 16:jJ 32:fF 34:oO 31:uU 35:,< 33:[{ 30:]} 42:\\| "
          + "0:sS 1:rR 2:nN 3:tT 5:wW 4:yY 38:cC 40:aA 37:eE 41:iI 39:/? "
          + "6:zZ 7:xX 8:mM 9:dD 11:bB 45:pP 46:gG 43:'\" 47:;: 44:.>"
      )
    case .gust:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:[{ 24:]} "
          + "12:;: 13:uU 14:oO 15:fF 17:jJ 16:qQ 32:kK 34:lL 31:rR 35:vV 33:/? 30:=+ 42:\\| "
          + "0:eE 1:iI 2:aA 3:cC 5:yY 4:dD 38:hH 40:tT 37:nN 41:sS 39:-_ "
          + "6:,< 7:.> 8:pP 9:gG 11:'\" 45:bB 46:mM 43:wW 47:xX 44:zZ"
      )
    case .recurva:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:fF 13:rR 14:dD 15:pP 17:vV 16:qQ 32:jJ 34:uU 31:oO 35:yY 33:[{ 30:]} 42:\\| "
          + "0:sS 1:nN 2:tT 3:cC 5:bB 4:.> 38:hH 40:eE 37:aA 41:iI 39:/? "
          + "6:zZ 7:xX 8:kK 9:gG 11:wW 45:mM 46:lL 43:;: 47:'\" 44:,<"
      )
    case .ansiColemak:
      map(
        "12:qQ 13:wW 14:fF 15:pP 17:gG 16:jJ 32:lL 34:uU 31:yY 35:;: 33:[{ 30:]} "
          + "0:aA 1:rR 2:sS 3:tT 5:dD 4:hH 38:nN 40:eE 37:iI 41:oO 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:kK 46:mM 43:,< 47:.> 44:/?")
    case .ansiColemakAngle:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:wW 14:fF 15:pP 17:gG 16:jJ 32:lL 34:uU 31:yY 35:;: 33:[{ 30:]} 42:\\| "
          + "0:aA 1:rR 2:sS 3:tT 5:dD 4:hH 38:nN 40:eE 37:iI 41:oO 39:'\" "
          + "6:xX 7:cC 8:vV 9:bB 11:zZ 45:kK 46:mM 43:,< 47:.> 44:/?"
      )
    case .ansiColemakWide:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:=+ 28:7& 25:8* 29:9( 27:0) 24:-_ "
          + "12:qQ 13:wW 14:fF 15:pP 17:gG 16:[{ 32:jJ 34:lL 31:uU 35:yY 33:;: 30:'\" 42:\\| "
          + "0:aA 1:rR 2:sS 3:tT 5:dD 4:]} 38:hH 40:nN 37:eE 41:iI 39:oO "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:/? 46:kK 43:mM 47:,< 44:.>"
      )
    case .ansiColemakDH:
      map(
        "12:qQ 13:wW 14:fF 15:pP 17:bB 16:jJ 32:lL 34:uU 31:yY 35:;: 33:[{ 30:]} "
          + "0:aA 1:rR 2:sS 3:tT 5:gG 4:mM 38:nN 40:eE 37:iI 41:oO 39:'\" "
          + "6:xX 7:cC 8:dD 9:vV 11:zZ 45:kK 46:hH 43:,< 47:.> 44:/?")
    case .ansiColemakDHV:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:=+ 24:[{ "
          + "12:qQ 13:wW 14:cC 15:pP 17:bB 16:jJ 32:lL 34:uU 31:yY 35:;: 33:-_ 30:]} 42:\\| "
          + "0:aA 1:rR 2:sS 3:tT 5:gG 4:mM 38:nN 40:eE 37:iI 41:oO 39:'\" "
          + "6:zZ 7:xX 8:fF 9:dD 11:kK 45:vV 46:hH 43:/? 47:.> 44:,<"
      )
    case .colemakDHISO:
      map(
        "12:qQ 13:wW 14:fF 15:pP 17:bB 16:jJ 32:lL 34:uU 31:yY 35:;: 33:[{ 30:]} "
          + "0:aA 1:rR 2:sS 3:tT 5:gG 4:mM 38:nN 40:eE 37:iI 41:oO 39:'\" "
          + "10:zZ 6:xX 7:cC 8:dD 9:vV 11:`~ 45:kK 46:hH 43:,< 47:.> 44:/?")
    case .colemakDHMatrix:
      map(
        "12:qQ 13:wW 14:fF 15:pP 17:bB 16:jJ 32:lL 34:uU 31:yY 35:;: 33:[{ 30:]} "
          + "0:aA 1:rR 2:sS 3:tT 5:gG 4:mM 38:nN 40:eE 37:iI 41:oO 39:'\" "
          + "6:zZ 7:xX 8:cC 9:dD 11:vV 45:kK 46:hH 43:,< 47:.> 44:/?")
    case .colemakDHWideANSI:
      map(
        "18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:=+ 28:7& 25:8* 29:9( 27:0) 24:-_ "
          + "12:qQ 13:wW 14:fF 15:pP 17:bB 16:[{ 32:jJ 34:lL 31:uU 35:yY 33:;: 30:'\" 42:\\| "
          + "0:aA 1:rR 2:sS 3:tT 5:gG 4:]} 38:mM 40:nN 37:eE 41:iI 39:oO "
          + "6:xX 7:cC 8:dD 9:vV 11:zZ 45:/? 46:kK 43:hH 47:,< 44:.>")
    case .colemakDHWideISO:
      map(
        "18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:=+ 28:7& 25:8* 29:9( 27:0) 24:-_ "
          + "12:qQ 13:wW 14:fF 15:pP 17:bB 16:[{ 32:jJ 34:lL 31:uU 35:yY 33:;: 30:/? "
          + "0:aA 1:rR 2:sS 3:tT 5:gG 4:]} 38:mM 40:nN 37:eE 41:iI 39:oO 42:'\" "
          + "10:zZ 6:xX 7:cC 8:dD 9:vV 11:\\| 45:#~ 46:kK 43:hH 47:,< 44:.>")
    case .colemakDHKANSI:
      map(
        "12:qQ 13:wW 14:fF 15:pP 17:bB 16:jJ 32:lL 34:uU 31:yY 35:;: 33:[{ 30:]} "
          + "0:aA 1:rR 2:sS 3:tT 5:gG 4:kK 38:nN 40:eE 37:iI 41:oO 39:'\" "
          + "6:xX 7:cC 8:dD 9:vV 11:zZ 45:mM 46:hH 43:,< 47:.> 44:/?")
    case .colemakDHKISO:
      map(
        "12:qQ 13:wW 14:fF 15:pP 17:bB 16:jJ 32:lL 34:uU 31:yY 35:;: 33:[{ 30:]} "
          + "0:aA 1:rR 2:sS 3:tT 5:gG 4:kK 38:nN 40:eE 37:iI 41:oO 39:'\" "
          + "10:zZ 6:xX 7:cC 8:dD 9:vV 11:`~ 45:mM 46:hH 43:,< 47:.> 44:/?")
    case .ansiNorman:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:wW 14:dD 15:fF 17:kK 16:jJ 32:uU 34:rR 31:lL 35:;: 33:[{ 30:]} 42:\\| "
          + "0:aA 1:sS 2:eE 3:tT 5:gG 4:yY 38:nN 40:iI 37:oO 41:hH 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:pP 46:mM 43:,< 47:.> 44:/?"
      )
    case .ansiWorkman:
      map(
        "12:qQ 13:dD 14:rR 15:wW 17:bB 16:jJ 32:fF 34:uU 31:pP 35:;: 33:[{ 30:]} "
          + "0:aA 1:sS 2:hH 3:tT 5:gG 4:yY 38:nN 40:eE 37:oO 41:iI 39:'\" "
          + "6:zZ 7:xX 8:mM 9:cC 11:vV 45:kK 46:lL 43:,< 47:.> 44:/?")
    case .programmerWorkman:
      map(
        "50:`~ 18:!1 19:@2 20:#3 21:$4 23:%5 22:^6 26:&7 28:*8 25:(9 29:)0 27:-_ 24:=+ "
          + "12:qQ 13:dD 14:rR 15:wW 17:bB 16:jJ 32:fF 34:uU 31:pP 35:;: 33:{[ 30:}] 42:\\| "
          + "0:aA 1:sS 2:hH 3:tT 5:gG 4:yY 38:nN 40:eE 37:oO 41:iI 39:'\" "
          + "6:zZ 7:xX 8:mM 9:cC 11:vV 45:kK 46:lL 43:,< 47:.> 44:/?"
      )
    case .mtgapASRT:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:wW 14:lL 15:dD 17:bB 16:jJ 32:fF 34:uU 31:kK 35:pP 33:[{ 30:]} 42:\\| "
          + "0:aA 1:sS 2:rR 3:tT 5:gG 4:hH 38:nN 40:eE 37:oO 41:iI 39:/? "
          + "6:zZ 7:xX 8:cC 9:vV 11:;: 45:yY 46:mM 43:,< 47:.> 44:'\""
      )
    case .halmak:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9< 29:0> 27:-_ 24:=+ "
          + "12:wW 13:lL 14:rR 15:bB 17:zZ 16:;: 32:qQ 34:uU 31:dD 35:jJ 33:[{ 30:]} 42:\\| "
          + "0:sS 1:hH 2:nN 3:tT 5:,( 4:.) 38:aA 40:eE 37:oO 41:iI 39:'\" "
          + "6:fF 7:mM 8:vV 9:cC 11:/? 45:gG 46:pP 43:xX 47:kK 44:yY"
      )
    case .qgmlwb:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:gG 14:mM 15:lL 17:wW 16:bB 32:yY 34:uU 31:vV 35:;: 33:[{ 30:]} 42:\\| "
          + "0:dD 1:sS 2:tT 3:nN 5:rR 4:iI 38:aA 40:eE 37:oO 41:hH 39:'\" "
          + "6:zZ 7:xX 8:cC 9:fF 11:jJ 45:kK 46:pP 43:,< 47:.> 44:/?"
      )
    case .qgmlwy:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:gG 14:mM 15:lL 17:wW 16:yY 32:fF 34:uU 31:bB 35:;: 33:[{ 30:]} 42:\\| "
          + "0:dD 1:sS 2:tT 3:nN 5:rR 4:iI 38:aA 40:eE 37:oO 41:hH 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:jJ 45:kK 46:pP 43:,< 47:.> 44:/?"
      )
    case .qwpr:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:wW 14:pP 15:rR 17:fF 16:yY 32:uU 34:kK 31:lL 35:;: 33:[{ 30:]} 42:\\| "
          + "0:aA 1:sS 2:dD 3:tT 5:gG 4:hH 38:nN 40:iI 37:oO 41:eE 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:jJ 46:mM 43:,< 47:.> 44:/?"
      )
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
    case .turkishE:
      map(
        "50:*+ 18:1! 19:2\" 20:3^ 21:4$ 23:5% 22:6& 26:7' 28:8( 25:9) 29:0= 27:/? 24:-_ "
          + "12:qQ 13:jJ 14:üÜ 15:oO 17:fF 16:cC 32:tT 34:mM 31:kK 35:bB 33:sS 30:pP "
          + "0:eE 1:aA 2:iİ 3:ıI 5:gG 4:ğĞ 38:lL 40:nN 37:rR 41:dD 39:vV 42:,; "
          + "10:<> 6:xX 7:wW 8:öÖ 9:uU 11:hH 45:zZ 46:çÇ 43:yY 47:şŞ 44:.:"
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
    case .japaneseHiragana:
      map(
        "50:ろろ 18:ぬぬ 19:ふふ 20:あぁ 21:うぅ 23:えぇ 22:おぉ 26:やゃ 28:ゆゅ 25:よょ 29:わを 27:ほほ 24:へへ "
          + "12:たた 13:てて 14:いぃ 15:すす 17:かか 16:んん 32:なな 34:にに 31:らら 35:せせ 33:゛「 30:゜」 42:むむ "
          + "0:ちち 1:とと 2:しし 3:はは 5:きき 4:くく 38:まま 40:のの 37:りり 41:れれ 39:けけ "
          + "6:つっ 7:ささ 8:そそ 9:ひひ 11:ここ 45:みみ 46:もも 43:ね、 47:る。 44:め・"
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
    case .tamil99:
      withOptionLayers(
        withSuppressedShift(
          map(
            "50:₹|~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
              + "12:ஆ|ஸ 13:ஈ|ஷ 14:ஊ|ஜ 15:ஐ|ஹ 17:ஏ|X 16:ள|ஸ்ரீ 32:ற|ஶ 34:ன|ஈ 31:ட|[ 35:ண|] 33:ச|{ 30:ஞ|} 42:\\| "
              + "0:அ|௹ 1:இ|௺ 2:உ|௸ 3:்|ஃ 5:எ|எ 4:க|க 38:ப|ப 40:ம|\" 37:த|: 41:ந|; 39:ய|' "
              + "6:ஔ|௳ 7:ஓ|௴ 8:ஒ|௵ 9:வ|௶ 11:ங|௷ 45:ல|ல 46:ர|/ 43:,< 47:.> 44:ழ|?"
          ),
          keyCodes: [4, 5, 38, 45]
        ),
        options: [
          50: ("`", nil), 18: ("¡", "⁄"), 19: ("™", "❊"), 20: ("£", "#"),
          21: ("¢", "€"), 23: ("§", "٪"), 22: (nil, "&"), 26: ("‘", "^"),
          28: ("’", "*"), 25: ("“", ")"), 29: ("”", "("), 27: ("–", "_"), 24: ("≠", "+"),
          12: ("ா", nil), 13: ("ீ", nil), 14: ("ூ", nil), 15: ("ை", nil),
          17: ("ே", nil), 33: ("“", "”"), 30: ("‘", "’"), 42: ("«", "»"),
          1: ("ி", nil), 2: ("ு", nil), 3: ("்", nil), 5: ("ெ", "ஃ"), 39: ("æ", nil),
          6: ("ௌ", nil), 7: ("ோ", nil), 8: ("ொ", "©"), 43: ("௹", "„"),
          47: ("।", nil), 44: ("/", "¿"),
        ]
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

  private static func withBaseFallbackOptionLayers(
    _ keys: [UInt16: KeyLayers], overrides: [UInt16: OptionPair]
  ) -> [UInt16: KeyLayers] {
    var layeredKeys = keys
    for (keyCode, layers) in keys {
      let override = overrides[keyCode]
      layeredKeys[keyCode] = .init(
        normal: layers.normal,
        shifted: layers.shifted,
        option: override?.normal ?? layers.normal,
        shiftedOption: override?.shifted ?? layers.shifted)
    }
    return layeredKeys
  }

  private static func baseShiftMap(
    keyRows: [[UInt16]], normalRows: [[String]], shiftedRows: [[String]]
  ) -> [UInt16: KeyLayers] {
    Dictionary(uniqueKeysWithValues: zip(keyRows, zip(normalRows, shiftedRows)).flatMap { entry in
      let (keyCodes, labels) = entry
      return zip(keyCodes, zip(labels.0, labels.1)).map { keyEntry in
        let (keyCode, output) = keyEntry
        return (keyCode, KeyLayers(normal: output.0, shifted: output.1))
      }
    })
  }

  private static func isoBaseShiftMap(normal: [String], shifted: [String]) -> [UInt16: KeyLayers] {
    baseShiftMap(
      keyRows: [
        physicalRows[0], Array(physicalRows[1].dropLast()), physicalRows[2] + [42],
        [10] + physicalRows[3],
      ],
      normalRows: normal.map { $0.map(String.init) },
      shiftedRows: shifted.map { $0.map(String.init) }
    )
  }

  private static func ansiBaseShiftMap(normal: [String], shifted: [String]) -> [UInt16: KeyLayers] {
    baseShiftMap(
      keyRows: physicalRows,
      normalRows: normal.map { $0.map(String.init) },
      shiftedRows: shifted.map { $0.map(String.init) }
    )
  }

  private static func withSpaceLayers(
    _ keys: [UInt16: KeyLayers], option: String? = nil, shiftedOption: String? = nil
  ) -> [UInt16: KeyLayers] {
    var layeredKeys = keys
    layeredKeys[49] = .init(
      normal: " ", shifted: " ", option: option, shiftedOption: shiftedOption)
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

  /// Keeps intentionally blank physical positions inside an emulated layout
  /// from falling through to the active macOS input source.
  private static func withSuppressedKeys(
    _ keys: [UInt16: KeyLayers], keyCodes: Set<UInt16>
  ) -> [UInt16: KeyLayers] {
    var layeredKeys = keys
    for keyCode in keyCodes {
      layeredKeys[keyCode] = .init(normal: "", shifted: "")
    }
    return layeredKeys
  }

  private static func withThumbKey(
    _ keys: [UInt16: KeyLayers], normal: String, shifted: String
  ) -> [UInt16: KeyLayers] {
    var layeredKeys = keys
    layeredKeys[49] = .init(normal: normal, shifted: shifted)
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
