import Foundation

/// Independently mapped numerical identities, without source descriptions/assets.
enum ExperienceModifierCatalog {
  struct Entry: Equatable {
    let sourceName: String?
    let difficulty: Double
  }
  static let entries: [String: Entry] = [
    "accountingStream": .init(sourceName: "58008", difficulty: 1),
    "mirrorVisual": .init(sourceName: "mirror", difficulty: 3),
    "upsideDownVisual": .init(sourceName: "upside_down", difficulty: 3),
    "nauseaVisual": .init(sourceName: "nausea", difficulty: 2),
    "roundVisual": .init(sourceName: "round_round_baby", difficulty: 3),
    "simonSays": .init(sourceName: "simon_says", difficulty: 1),
    "listening": .init(sourceName: "tts", difficulty: 1),
    "chooVisual": .init(sourceName: "choo_choo", difficulty: 2),
    "arrowStream": .init(sourceName: "arrows", difficulty: 1),
    "randomCase": .init(sourceName: "rAnDoMcAsE", difficulty: 2),
    "alternatingCase": .init(sourceName: "sPoNgEcAsE", difficulty: 2),
    "titleCase": .init(sourceName: "capitals", difficulty: 1),
    "mirrorKeyboard": .init(sourceName: "layout_mirror", difficulty: 3),
    "layoutFluid": .init(sourceName: "layoutfluid", difficulty: 1),
    "earthquakeVisual": .init(sourceName: "earthquake", difficulty: 1),
    "spaceVisual": .init(sourceName: "space_balls", difficulty: 0),
    "gibberishStream": .init(sourceName: "gibberish", difficulty: 1),
    "asciiStream": .init(sourceName: "ascii", difficulty: 1),
    "specialCharacterStream": .init(sourceName: "specials", difficulty: 1),
    "focusCurrentWord": .init(sourceName: "plus_zero", difficulty: 1),
    "focusNextWord": .init(sourceName: "plus_one", difficulty: 0),
    "focusTwoWords": .init(sourceName: "plus_two", difficulty: 0),
    "focusThreeWords": .init(sourceName: "plus_three", difficulty: 0),
    "readAheadEasy": .init(sourceName: "read_ahead_easy", difficulty: 1),
    "readAhead": .init(sourceName: "read_ahead", difficulty: 2),
    "readAheadHard": .init(sourceName: "read_ahead_hard", difficulty: 3),
    "memory": .init(sourceName: "memory", difficulty: 3),
    "noSpaces": .init(sourceName: "nospace", difficulty: 0),
    "poetryStream": .init(sourceName: "poetry", difficulty: 0),
    "referenceStream": .init(sourceName: "wikipedia", difficulty: 0),
    "weakSpot": .init(sourceName: "weakspot", difficulty: 0),
    "pseudolangStream": .init(sourceName: "pseudolang", difficulty: 0),
    "ipv4Stream": .init(sourceName: "IPv4", difficulty: 1),
    "ipv6Stream": .init(sourceName: "IPv6", difficulty: 1),
    "binaryStream": .init(sourceName: "binary", difficulty: 1),
    "hexadecimalStream": .init(sourceName: "hexadecimal", difficulty: 1),
    "zipf": .init(sourceName: "zipf", difficulty: 0),
    "morseStream": .init(sourceName: "morse", difficulty: 1),
    "crtVisual": .init(sourceName: "crt", difficulty: 0),
    "backwards": .init(sourceName: "backwards", difficulty: 3),
    "doubleCharacters": .init(sourceName: "ddoouubblleedd", difficulty: 1),
    "messagingStyle": .init(sourceName: "instant_messaging", difficulty: 0),
    "underscoreSeparators": .init(sourceName: "underscore_spaces", difficulty: 1),
    "uppercase": .init(sourceName: "ALL_CAPS", difficulty: 1),
    "polyglot": .init(sourceName: "polyglot", difficulty: 1),
    "aslVisual": .init(sourceName: "asl", difficulty: 1),
    "rot13": .init(sourceName: "rot13", difficulty: 1),
    "noQuit": .init(sourceName: "no_quit", difficulty: 0),
    // Explicit native-only extensions have no original Funbox identity/bonus.
    "symbolStream": .init(sourceName: nil, difficulty: 0),
    "correctBeforeAdvance": .init(sourceName: nil, difficulty: 0),
    "clearCurrentWordOnError": .init(sourceName: nil, difficulty: 0),
  ]
}
