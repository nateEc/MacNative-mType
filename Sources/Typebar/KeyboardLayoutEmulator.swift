@preconcurrency import AppKit

/// Converts ANSI physical key positions into Typebar's supported practice layouts.
/// This is intentionally local and deterministic: it never reads the active system
/// keyboard layout, so dead keys and IME composition keep using the normal AppKit path.
enum KeyboardLayoutEmulator {
  private typealias KeyPair = (normal: Character, shifted: Character)

  static func character(
    forKeyCode keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, layout: KeyboardLayout
  ) -> Character? {
    guard layout != .ansiQwerty,
      !modifierFlags.contains(.command),
      !modifierFlags.contains(.control),
      !modifierFlags.contains(.option),
      let pair = keys(for: layout)[keyCode]
    else { return nil }
    return modifierFlags.contains(.shift) ? pair.shifted : pair.normal
  }

  /// Resolves a character through a selected layout for input devices which
  /// report remapped logical characters instead of their physical key code.
  static func keyCode(for character: Character, layout: KeyboardLayout) -> UInt16? {
    keys(for: layout).first { _, pair in
      pair.normal == character || pair.shifted == character
        || String(pair.normal).caseInsensitiveCompare(String(character)) == .orderedSame
        || String(pair.shifted).caseInsensitiveCompare(String(character)) == .orderedSame
    }?.key
  }

  private static func keys(for layout: KeyboardLayout) -> [UInt16: KeyPair] {
    switch layout {
    case .ansiQwerty:
      map(
        "50:`~ 18:1! 19:2@ 20:3# 21:4$ 23:5% 22:6^ 26:7& 28:8* 25:9( 29:0) 27:-_ 24:=+ "
          + "12:qQ 13:wW 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:[{ 30:]} "
          + "0:aA 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:;: 39:'\" "
          + "6:zZ 7:xX 8:cC 9:vV 11:bB 45:nN 46:mM 43:,< 47:.> 44:/?")
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
    case .frenchAzerty:
      map(
        "18:&1 19:é2 20:\"3 21:'4 23:(5 22:-6 26:è7 28:_8 25:ç9 29:à0 27:)° 24:=+ "
          + "12:aA 13:zZ 14:eE 15:rR 17:tT 16:yY 32:uU 34:iI 31:oO 35:pP 33:^¨ 30:$£ "
          + "0:qQ 1:sS 2:dD 3:fF 5:gG 4:hH 38:jJ 40:kK 37:lL 41:mM 39:ù% "
          + "6:wW 7:xX 8:cC 9:vV 11:bB 45:nN 46:,? 43:;. 47::/ 44:!§")
    }
  }

  private static func map(_ definition: String) -> [UInt16: KeyPair] {
    Dictionary(uniqueKeysWithValues: definition.split(separator: " ").compactMap { token in
      let pieces = token.split(separator: ":", maxSplits: 1)
      guard pieces.count == 2, let keyCode = UInt16(pieces[0]), pieces[1].count == 2 else { return nil }
      let symbols = Array(pieces[1])
      return (keyCode, (symbols[0], symbols[1]))
    })
  }
}
