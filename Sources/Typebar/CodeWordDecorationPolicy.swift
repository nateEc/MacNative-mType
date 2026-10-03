import Foundation

typealias CodeWordDecorationPolicy = PoolWordDecorationPolicy

/// A transient app-owned sentence marker, never a setting or archived field.
struct PoolWordDecorationState: Equatable {
  var spanishClosing: String?
}

enum PoolWordLanguageFamily {
  case other, spanish, turkish, georgian, chinese, japanese, french, greek
  case arabic, persian, urdu, kurdish, nepali, bangla, hindi, russian, ukrainian, slovak

  init(_ language: TypingLanguage) {
    let identity = language.rawValue
    if identity.hasPrefix("simplifiedChinese") || identity.hasPrefix("traditionalChinese") { self = .chinese }
    else if identity.hasPrefix("greeklish") { self = .other }
    else {
      let families: [(String, Self)] = [("spanish", .spanish), ("turkish", .turkish), ("georgian", .georgian),
        ("japanese", .japanese), ("french", .french), ("greek", .greek), ("arabic", .arabic),
        ("persian", .persian), ("urdu", .urdu), ("kurdish", .kurdish), ("nepali", .nepali),
        ("bangla", .bangla), ("hindi", .hindi), ("russian", .russian), ("ukrainian", .ukrainian), ("slovak", .slovak)]
      self = families.first { identity.hasPrefix($0.0) }?.1 ?? .other
    }
  }

  var easternWidth: Bool { self == .chinese || self == .japanese }
  var arabicQuestionAndComma: Bool { [.arabic, .persian, .urdu, .kurdish].contains(self) }
  var digitBase: UInt32? {
    switch self {
    case .kurdish: return 0x0660
    case .nepali, .hindi: return 0x0966
    case .bangla: return 0x09E6
    default: return nil
    }
  }

  static func preservesASCIICase(_ language: TypingLanguage) -> Bool {
    language.isCodeLanguage && language != .dockerFile
      || ["german", "swissGerman", "klingon"].contains { language.rawValue.hasPrefix($0) }
  }
}

/// Common native per-word decoration for owned language, code and entry pools. It stays
/// separate from authored programs and uses the already-altered prior target.
enum PoolWordDecorationPolicy {
  static func decorated(_ word: String, previousTarget: String?, language: TypingLanguage,
    wordIndex: Int, wordBound: Int, options: ContentOptions,
    britishEnglish: BritishEnglishPolicy.Context? = nil,
    random: () -> Double = { Double.random(in: 0..<1) }) -> String {
    var state = PoolWordDecorationState()
    return decorated(word, previousTarget: previousTarget, language: language, wordIndex: wordIndex,
      wordBound: wordBound, options: options, state: &state, britishEnglish: britishEnglish, random: random)
  }

  static func decorated(_ word: String, previousTarget: String?, language: TypingLanguage,
    wordIndex: Int, wordBound: Int, options: ContentOptions, state: inout PoolWordDecorationState,
    britishEnglish: BritishEnglishPolicy.Context? = nil,
    random: () -> Double = { Double.random(in: 0..<1) }) -> String {
    var result = word
    if options.includePunctuation {
      result = punctuated(word, previous: previousTarget, language: language,
        index: wordIndex, bound: wordBound, state: &state, random: random)
      // Move controls to the end in Tab-then-LF order, even when another
      // punctuation branch has added a suffix after an embedded control.
      for control in ["\t", "\n"] where result.contains(control) {
        result = result.replacingOccurrences(of: control, with: "") + control
      }
    }
    result = BritishEnglishPolicy.transformed(result, context: britishEnglish,
      previousWord: previousTarget.map(BritishEnglishPolicy.previousWordKey))
    if options.includeNumbers && random() < 0.1 {
      let length = integer(random(), count: 4, lowerBound: 1)
      result = (0..<length).map { position in
        String(integer(random(), count: position == 0 ? 9 : 10, lowerBound: position == 0 ? 1 : 0))
      }.joined()
      if let base = PoolWordLanguageFamily(language).digitBase {
        result = String(String.UnicodeScalarView(result.unicodeScalars.map {
          UnicodeScalar(base + $0.value - 48)!
        }))
      }
    }
    return result
  }

  private static func punctuated(_ word: String, previous: String?, language: TypingLanguage,
    index: Int, bound: Int, state: inout PoolWordDecorationState, random: () -> Double) -> String {
    let isCode = language.isCodeLanguage && language != .dockerFile
    let family = PoolWordLanguageFamily(language)
    let last = previous?.last
    let canWrap = last != "," && last != "."
    if !isCode && family != .georgian && (index == 0 || last.map { ".?!؟".contains($0) } == true) {
      var result = word.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        .components(separatedBy: " ").map { component in
          guard let first = component.unicodeScalars.first, first.value <= 0xFFFF else { return component }
          return String(first).uppercased() + String(component.unicodeScalars.dropFirst())
        }.joined(separator: " ")
      if family == .turkish { result = result.replacingOccurrences(of: "I", with: "İ") }
      if family == .spanish {
        let opening = random()
        if opening > 0.9 { result = "¿" + result; state.spanishClosing = "?" }
        else if opening > 0.8 { result = "¡" + result; state.spanishClosing = "!" }
      }
      return result
    }
    // Draw before the guards, including the forced terminal branch. Fixed
    // unit fixtures must not accidentally shift all following decisions.
    if (random() < 0.1 && canWrap && index != bound - 2) || index == bound - 1 {
      if family == .spanish {
        guard let closing = state.spanishClosing, closing == "?" || closing == "!" else { return word }
        state.spanishClosing = nil
        return word + closing
      }
      let terminal = random()
      if terminal <= 0.8 {
        let mark = [.nepali, .bangla, .hindi].contains(family) ? "।" : family.easternWidth ? "。" : "."
        return word + mark
      }
      let mark = terminal < 0.9
        ? (family.arabicQuestionAndComma ? "؟" : family == .greek ? ";" : family.easternWidth ? "？" : "?")
        : (family.easternWidth ? "！" : "!")
      return family == .french ? mark : word + mark
    }
    if random() < 0.01 && canWrap && family != .russian { return "\"" + word + "\"" }
    if random() < 0.011 && canWrap && ![.russian, .ukrainian, .slovak].contains(family) { return "'" + word + "'" }
    if random() < 0.012 && canWrap {
      if family.easternWidth { return "（" + word + "）" }
      guard isCode else { return "(" + word + ")" }
      var pairs = ["()", "{}", "[]", "<>"]
      if language.rawValue.hasPrefix("codeJavaScript") { pairs.append("``") }
      let pair = pairs[self.index(random(), count: pairs.count)]
      return String(pair.prefix(1)) + word + pair.suffix(1)
    }
    if random() < 0.013 && canWrap && last.map({ ";؛:；：".contains($0) }) != true {
      return family == .french ? ":" : word + (family == .chinese ? "：" : ":")
    }
    if random() < 0.014 && canWrap && previous != "-" { return "-" }
    if random() < 0.015 && canWrap && last.map({ ";؛；：".contains($0) }) != true {
      if family == .french { return ";" }
      if family == .greek { return "." }
      return word + ([.arabic, .kurdish].contains(family) ? "؛" : family == .chinese ? "；" : ";")
    }
    if random() < 0.2 && last != "," {
      return word + (family.arabicQuestionAndComma ? "،" : family == .japanese ? "、" : family == .chinese ? "，" : ",")
    }
    let operatorChance = random()
    if operatorChance < 0.25 && isCode {
      // These are syntax symbols, not a copied vocabulary or program asset.
      var operators = "{}[]();=+%/".map(String.init)
      if (language.rawValue.hasPrefix("codeC") && language != .codeCSS) || language == .codeArduino {
        operators += "/* */ // != == <= >= || && << >> %= &= *= ++ += -- -= /= ^= |="
          .split(separator: " ").map(String.init)
      } else if language.rawValue.hasPrefix("codeJavaScript") {
        operators.append("`")
      }
      return operators[self.index(random(), count: operators.count)]
    }
    // Draw for this gate even outside English. The replacement itself takes
    // one independent choice only if its whole ASCII-word match succeeds.
    if random() < 0.5 && EnglishWordPoolContent.supports(language) {
      return EnglishPunctuationPolicy.replacingAtWordGate(word, random: random)
    }
    return word
  }

  private static func index(_ unit: Double, count: Int) -> Int {
    min(count - 1, Int(min(max(unit, 0), 0.999_999_999) * Double(count)))
  }

  private static func integer(_ unit: Double, count: Int, lowerBound: Int) -> Int {
    // Addition must precede floor: an IEEE-754 boundary can round across the
    // nominal upper limit. Preserve that observable source behavior too.
    Int((unit * Double(count) + Double(lowerBound)).rounded(.down))
  }
}
