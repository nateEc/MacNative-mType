typealias CodeWordDecorationPolicy = PoolWordDecorationPolicy

/// Common native per-word decoration for owned code and entry pools. It stays
/// separate from authored programs and uses the already-altered prior target.
enum PoolWordDecorationPolicy {
  static func decorated(_ word: String, previousTarget: String?, language: TypingLanguage,
    wordIndex: Int, wordBound: Int, options: ContentOptions,
    random: () -> Double = { Double.random(in: 0..<1) }) -> String {
    var result = word
    if options.includePunctuation {
      result = punctuated(word, previous: previousTarget, language: language,
        index: wordIndex, bound: wordBound, random: random)
      // Move controls to the end in Tab-then-LF order, even when another
      // punctuation branch has added a suffix after an embedded control.
      for control in ["\t", "\n"] where result.contains(control) {
        result = result.replacingOccurrences(of: control, with: "") + control
      }
    }
    if options.includeNumbers && random() < 0.1 {
      let length = integer(random(), count: 4, lowerBound: 1)
      result = (0..<length).map { position in
        String(integer(random(), count: position == 0 ? 9 : 10, lowerBound: position == 0 ? 1 : 0))
      }.joined()
    }
    return result
  }

  private static func punctuated(_ word: String, previous: String?, language: TypingLanguage,
    index: Int, bound: Int, random: () -> Double) -> String {
    let isCode = language.isCodeLanguage && language != .dockerFile
    let last = previous?.last
    let canWrap = last != "," && last != "."
    if !isCode && (index == 0 || last.map { ".?!؟".contains($0) } == true) {
      return word.prefix(1).uppercased() + word.dropFirst()
    }
    // Draw before the guards, including the forced terminal branch. Fixed
    // unit fixtures must not accidentally shift all following decisions.
    if (random() < 0.1 && canWrap && index != bound - 2) || index == bound - 1 {
      let terminal = random()
      return word + (terminal <= 0.8 ? "." : terminal < 0.9 ? "?" : "!")
    }
    if random() < 0.01 && canWrap { return "\"" + word + "\"" }
    if random() < 0.011 && canWrap { return "'" + word + "'" }
    if random() < 0.012 && canWrap {
      guard isCode else { return "(" + word + ")" }
      var pairs = ["()", "{}", "[]", "<>"]
      if language.rawValue.hasPrefix("codeJavaScript") { pairs.append("``") }
      let pair = pairs[self.index(random(), count: pairs.count)]
      return String(pair.prefix(1)) + word + pair.suffix(1)
    }
    if random() < 0.013 && canWrap && last.map({ ";؛:；：".contains($0) }) != true {
      return word + ":"
    }
    if random() < 0.014 && canWrap && previous != "-" { return "-" }
    if random() < 0.015 && canWrap && last.map({ ";؛；：".contains($0) }) != true {
      return word + ";"
    }
    if random() < 0.2 && last != "," { return word + "," }
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
    // The pinned common decorator draws for its English-only contraction
    // branch even when the code/Dockerfile language cannot enter it.
    _ = random()
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
