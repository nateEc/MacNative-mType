import Foundation

/// Website configuration admission only, separate from native selection
/// normalization and from resource checks during actual prompt activation.
enum WebsiteFunboxAdmission {
  static let knownNames = Set(FunboxCommandCatalog.officialNames)
  static func areCompatible(_ names: [String]) -> Bool {
    guard names.allSatisfy({ knownNames.contains($0) && classifiedNames.contains($0) }) else { return false }
    // Count occurrences, not distinct names: import arrays may contain duplicates.
    guard exclusiveGroups.allSatisfy({ group in names.lazy.filter(group.contains).prefix(2).count <= 1 })
    else { return false }
    let selected = Set(names)
    func overlaps(_ group: Set<String>) -> Bool { !selected.isDisjoint(with: group) }
    if overlaps(layoutChanges) && overlaps(layoutDependent) { return false }
    if overlaps(frequency) && overlaps(ignoresLanguage) { return false }
    if overlaps(capitalization) && overlaps(noLetters) { return false }
    if selected.contains("arrows") && overlaps(["choo_choo", "backwards"]) { return false }
    // Speaking is allowed with language-independent text unless it is also
    // declared unspeakable. This is not the older native selection fallback.
    if selected.contains("tts") && overlaps(unspeakable) && overlaps(ignoresLanguage) { return false }
    return true
  }

  static func accepts(_ proposed: WebsiteConfigValue, current: [String: WebsiteConfigValue]) -> Bool {
    guard let names = names(in: proposed), areCompatible(names) else { return false }
    if names.isEmpty { return true }
    guard let previous = current["funbox"].flatMap(names(in:)), previous.allSatisfy(knownNames.contains) else { return false }
    return names.allSatisfy { candidate in allows(current, active: previous + [candidate]) }
  }

  private static func names(in value: WebsiteConfigValue) -> [String]? {
    guard case .array(let values) = value else { return nil }
    let names = values.compactMap { if case .string(let name) = $0 { name } else { nil } }
    return names.count == values.count ? names : nil
  }

  private static let wordSources: Set<String> = ["58008", "arrows", "gibberish", "ascii", "specials",
    "poetry", "wikipedia", "weakspot", "pseudolang", "IPv4", "IPv6", "binary", "hexadecimal", "polyglot"]
  private static let transforms: Set<String> = ["rAnDoMcAsE", "sPoNgEcAsE", "capitals", "morse",
    "backwards", "ddoouubblleedd", "instant_messaging", "underscore_spaces", "ALL_CAPS", "rot13"]
  private static let frequency: Set<String> = ["weakspot", "zipf"]
  private static let capitalization: Set<String> = ["rAnDoMcAsE", "sPoNgEcAsE", "capitals", "instant_messaging", "ALL_CAPS"]
  private static let noSpaces: Set<String> = ["arrows", "nospace", "morse", "underscore_spaces"]
  private static let pushes: Set<String> = ["plus_zero", "plus_one", "plus_two", "plus_three"]
  private static let visibility: Set<String> = ["simon_says", "tts", "memory", "read_ahead_easy",
    "read_ahead", "read_ahead_hard", "plus_zero", "plus_one", "plus_two", "plus_three"]
  private static let layoutChanges: Set<String> = ["layout_mirror", "layoutfluid"]
  private static let layoutDependent: Set<String> = ["58008", "arrows", "IPv4", "IPv6", "binary",
    "hexadecimal", "morse", "underscore_spaces", "simon_says"]
  private static let ignoresLanguage: Set<String> = ["58008", "arrows", "gibberish", "ascii", "specials",
    "poetry", "wikipedia", "pseudolang", "IPv4", "IPv6", "binary", "hexadecimal", "morse", "underscore_spaces", "polyglot"]
  private static let noLetters: Set<String> = ["58008", "arrows", "ascii", "specials", "IPv4", "IPv6", "binary", "hexadecimal", "morse"]
  private static let unspeakable: Set<String> = ["gibberish", "ascii", "specials", "pseudolang"]
  private static let exclusiveGroups: [Set<String>] = [
    wordSources, noSpaces.union(pushes), visibility, frequency, capitalization, ["tts"], ["backwards"],
    pushes.union(["poetry", "wikipedia"]), ["58008", "IPv4", "IPv6", "hexadecimal"], ["58008", "arrows"], ["arrows"],
    ["mirror", "upside_down"], ["nausea", "round_round_baby"],
    ["tts", "choo_choo", "earthquake", "backwards", "asl"], ["space_balls", "crt"],
  ]
  private static let classifiedNames = exclusiveGroups.reduce(Set(["no_quit"])) { $0.union($1) }
    .union(transforms).union(layoutChanges)
  private static let finiteOnly: Set<String> = ["layoutfluid", "plus_zero", "plus_one", "plus_two",
    "plus_three", "memory", "poetry", "wikipedia"]
  private static let punctuationOff: Set<String> = ["arrows", "ascii", "specials", "poetry", "wikipedia", "binary"]
  private static let numbersOff: Set<String> = ["58008", "arrows", "ascii", "specials", "poetry",
    "wikipedia", "IPv4", "IPv6", "binary", "hexadecimal"]
  private static let characterHighlight: Set<String> = ["simon_says", "tts", "arrows", "read_ahead_easy",
    "read_ahead", "read_ahead_hard", "nospace"]

  private static func allows(_ current: [String: WebsiteConfigValue], active: [String]) -> Bool {
    let selected = Set(active)
    for (key, value) in current {
      switch key {
      case "words", "time":
        if value == .number(0), !selected.isDisjoint(with: finiteOnly) { return false }
      case "punctuation":
        if !selected.isDisjoint(with: punctuationOff), value != .bool(false) { return false }
      case "numbers":
        if !selected.isDisjoint(with: numbersOff), value != .bool(false) { return false }
      case "highlightMode":
        if !selected.isDisjoint(with: characterHighlight), value != .string("letter"), value != .string("off") { return false }
      case "mode":
        if selected.contains("memory"), ![WebsiteConfigValue.string("words"), .string("quote"), .string("custom")].contains(value) { return false }
        if value == .string("quote") || value == .string("custom") {
          if !selected.isDisjoint(with: wordSources.union(frequency)) { return false }
        } else if value == .string("zen") {
          let excluded = wordSources.union(transforms).union(capitalization).union(noSpaces)
            .union(pushes).union(visibility).union(layoutChanges).union(frequency).union(["tts"])
          if !selected.isDisjoint(with: excluded) { return false }
        }
      default: break
      }
    }
    return true
  }
}
