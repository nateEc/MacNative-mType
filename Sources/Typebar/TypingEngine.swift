import Foundation

/// Monkeytype treats spaces and explicit line breaks as word commits. Tabs
/// remain content because code and custom prompts may need them verbatim.
func isPromptWordSeparator(_ character: Character) -> Bool {
  character == " " || character == "\n"
}

private func splitPromptWords(
  _ text: String, omittingEmptySubsequences: Bool
) -> [Substring] {
  text.split(
    omittingEmptySubsequences: omittingEmptySubsequences,
    whereSeparator: isPromptWordSeparator)
}

/// Swift's text equality includes canonical Unicode equivalence. Input
/// validation instead needs the actual retained spelling, after only the
/// explicit typing substitutions below. For well-formed native Characters,
/// identical scalars also mean identical UTF-16 units, without allocating.
enum InputTextIdentity {
  static func matches(_ first: Character, _ second: Character) -> Bool {
    first.unicodeScalars.elementsEqual(second.unicodeScalars)
  }

  static func matches<First: StringProtocol, Second: StringProtocol>(
    _ first: First, _ second: Second
  ) -> Bool {
    first.utf16.elementsEqual(second.utf16)
  }
}

enum InputCharacterEquivalence {
  static let sets: [Set<Character>] = [
    ["’", "‘", "'", "ʼ", "׳", "ʻ", "᾽"],
    ["\"", "”", "“", "„"],
    ["–", "—", "-", "‐", "‑"],
    [",", "‚"],
  ]
  static let russianYoSet: Set<Character> = ["ё", "е", "e"]

  static func matches(
    _ first: Character, _ second: Character, language: TypingLanguage
  ) -> Bool {
    if InputTextIdentity.matches(first, second)
      || sets.contains(where: {
        $0.contains(where: { InputTextIdentity.matches($0, first) })
          && $0.contains(where: { InputTextIdentity.matches($0, second) })
      }) {
      return true
    }
    return language.usesRussianYoInputEquivalence
      && russianYoSet.contains(where: { InputTextIdentity.matches($0, first) })
      && russianYoSet.contains(where: { InputTextIdentity.matches($0, second) })
  }

  static func isReferenceSpace(_ character: Character) -> Bool {
    [
      " ", "\u{2002}", "\u{2003}", "\u{2009}", "\u{3000}", "\u{00A0}", "\u{1680}", "\u{202F}",
      "\u{FEFF}", "\u{2007}", "\u{2008}", "\u{2004}", "\u{200A}", "\u{200B}",
    ].contains(character)
  }

  static func normalized(
    _ character: Character, expected: Character?, language: TypingLanguage
  ) -> Character {
    guard let expected else { return isReferenceSpace(character) ? " " : character }
    if (character == " " || expected == " ")
      && isReferenceSpace(character) && isReferenceSpace(expected)
    {
      return expected
    }
    if matches(character, expected, language: language) { return expected }
    return isReferenceSpace(character) ? " " : character
  }
}

enum TestMode: String, CaseIterable, Codable {
  case time
  case words
  case quote
  case zen
  case custom
}

/// The reference memory funbox only runs in word, quote, and custom tests.
/// Direct controls reject an incompatible toggle; this fallback only cleans
/// up an imported configuration that predates the shared mode gate.
enum MemoryFunboxModePolicy {
  static let allowedModes: Set<TestMode> = [.words, .quote, .custom]
  /// Imported configurations do not carry the live control's separate word
  /// count. Use the native control's default when memory forces a new mode.
  static let fallbackWordLimit = 25

  static func effectiveMode(requested: TestMode, modifiers: [TestModifier]) -> TestMode {
    guard modifiers.contains(.memory), !allowedModes.contains(requested) else { return requested }
    return .words
  }
}

enum Difficulty: String, CaseIterable, Codable {
  case normal
  case expert
  case master
}

enum ConfidenceMode: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case on
  case maximum

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .on: "开启"
    case .maximum: "最大"
    }
  }
}

/// Mirrors the two selectable stop-on-error behaviors from the reference
/// product without retaining its implementation or presentation code.
enum StopOnErrorMode: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case letter
  case word

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .letter: "字符"
    case .word: "单词"
    }
  }

  var isEnabled: Bool { self != .off }
}

/// The four delete-on-error variants. "Hard" returns to the previous word
/// when the mistake happens before entering any character of the new word.
enum DeleteOnErrorMode: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case letter
  case letterHard
  case word
  case wordHard

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .letter: "字符（退一格）"
    case .letterHard: "字符（硬）"
    case .word: "单词"
    case .wordHard: "单词（硬）"
    }
  }

  var isEnabled: Bool { self != .off }

  var clearsWholeWord: Bool {
    self == .word || self == .wordHard
  }

  var returnsToPreviousWordAtStart: Bool {
    self == .letterHard || self == .wordHard
  }
}

/// A minimum per-word burst can be a fixed threshold, or a threshold that
/// relaxes for longer target words using the reference product's published
/// formula.
enum MinimumWordBurstMode: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case fixed
  case flex

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .fixed: "固定"
    case .flex: "弹性"
    }
  }
}

enum MinimumWordBurstPolicy {
  static func threshold(baseWpm: Double, mode: MinimumWordBurstMode, wordLength: Int) -> Double {
    switch mode {
    case .off: return 0
    case .fixed: return baseWpm
    case .flex:
      let adjusted = floor(baseWpm * pow(1.03, -2 * Double(max(0, wordLength - 3))))
      return min(baseWpm, adjusted)
    }
  }
}

/// Burst weights text in UTF-16 code units, independently of the grapheme
/// indices used by native input, word boundaries, timestamps and replay.
enum WordBurstInputUnits {
  static func count<C: Collection>(_ characters: C) -> Int where C.Element == Character {
    characters.reduce(0) { $0 + String($1).utf16.count }
  }
}

enum PracticeThresholdPolicy {
  static func speed(_ value: Double) -> Double {
    value.isFinite && value >= 0 ? value : 0
  }

  static func accuracy(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return value.clamped(to: 0...100)
  }
}

enum OppositeShiftMode: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case on
  case keymap

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .on: "开启"
    case .keymap: "按键位图"
    }
  }
}

enum QuickRestartKey: String, CaseIterable, Codable, Equatable, Identifiable {
  case off
  case escape
  case tab
  case enter

  var id: Self { self }

  var displayName: String {
    switch self {
    case .off: "关闭"
    case .escape: "Esc"
    case .tab: "Tab"
    case .enter: "Enter"
    }
  }

  func matches(charactersIgnoringModifiers: String?) -> Bool {
    switch self {
    case .off: false
    case .escape: charactersIgnoringModifiers == "\u{1B}"
    case .tab: charactersIgnoringModifiers == "\t"
    case .enter: charactersIgnoringModifiers == "\r" || charactersIgnoringModifiers == "\n"
    }
  }
}

extension Difficulty {
  var displayName: String {
    switch self {
    case .normal: "普通"
    case .expert: "专家"
    case .master: "大师"
    }
  }
}

enum TypingLanguage: String, CaseIterable, Codable, Equatable, Hashable {
  case english
  case english1k
  case english5k
  case english10k
  case english25k
  case english450k
  case englishFiveLetter
  case englishFiveLetter1k
  case englishCommonlyMisspelled
  case englishContractions
  case englishDoubleLetter
  case englishLegal
  case englishMedical
  case englishShakespearean
  case oldEnglish
  case kokanu
  case likanu
  case pigLatin
  case spanish
  case spanish1k
  case spanish10k
  case spanish650k
  case german
  case german1k
  case german10k
  case german250k
  case swissGerman
  case swissGerman1k
  case swissGerman2k
  case afrikaans
  case afrikaans1k
  case afrikaans10k
  case albanian
  case albanian1k
  case bemba
  case bemba1k
  case bemba10k
  case bosnian
  case bosnian4k
  case esperanto
  case esperanto1k
  case esperanto10k
  case esperanto25k
  case esperanto36k
  case esperantoXSystem
  case esperantoXSystem1k
  case esperantoXSystem10k
  case esperantoXSystem25k
  case esperantoXSystem36k
  case esperantoHSystem
  case esperantoHSystem1k
  case esperantoHSystem10k
  case esperantoHSystem25k
  case esperantoHSystem36k
  case latin
  case loremIpsum
  case git
  case twitchEmotes
  case typingOfTheDead
  case pokemon1k
  case arenaStrategy
  case friulian
  case malagasy
  case malagasy1k
  case welsh
  case welsh1k
  case hausa
  case hausa1k
  case tatar
  case tatar1k
  case tatar5k
  case tatar9k
  case tatarCrimean
  case tatarCrimean1k
  case tatarCrimean5k
  case tatarCrimean10k
  case tatarCrimean15k
  case tatarCrimeanCyrillic
  case tatarCrimeanCyrillic1k
  case tatarCrimeanCyrillic5k
  case tatarCrimeanCyrillic10k
  case tatarCrimeanCyrillic15k
  case klingon
  case klingon1k
  case quenya
  case viossa
  case viossaNjutro
  case maori
  case lojbanGismu
  case lojbanCmavo
  case uzbek
  case uzbek1k
  case uzbek70k
  case occitan
  case occitan1k
  case occitan2k
  case occitan5k
  case occitan10k
  case oromo
  case oromo1k
  case oromo5k
  case macedonian
  case macedonian1k
  case macedonian10k
  case macedonian75k
  case kazakh
  case kazakh1k
  case vietnamese
  case vietnamese1k
  case vietnamese5k
  case jyutping
  case pinyin
  case pinyin1k
  case pinyin10k
  case bashkir
  case basque
  case frisian
  case frisian1k
  case zulu
  case hawaiian
  case hawaiian1k
  case kabyle
  case kabyle1k
  case kabyle2k
  case kabyle5k
  case kabyle10k
  case maltese
  case maltese1k
  case tokiPona
  case tokiPonaKuSuli
  case tokiPonaKuLili
  case xhosa
  case xhosa3k
  case tibetan
  case tibetan1k
  case kyrgyz
  case kyrgyz1k
  case udmurt
  case yoruba
  case swahili
  case kinyarwanda
  case shona
  case shona1k
  case santali
  case yiddish
  case arabic
  case arabic10k
  case arabicEgypt
  case arabicEgypt1k
  case arabicMorocco
  case pashto
  case sindhi
  case hebrew
  case hebrew1k
  case hebrew5k
  case hebrew10k
  case persian
  case persian1k
  case persian5k
  case persian20k
  case persianRomanized
  case urdu
  case urdu1k
  case urdu5k
  case urduRoman
  case urdish
  case tamil
  case tamil1k
  case tamilOld
  case tanglish
  case hindi
  case hindi1k
  case hinglish
  case gujarati
  case gujarati1k
  case bangla
  case bangla10k
  case banglaLetters
  case thai
  case thai1k
  case thai5k
  case thai10k
  case thai20k
  case thai50k
  case thai60k
  case nepali
  case nepali1k
  case nepaliRomanized
  case kannada
  case telugu
  case telugu1k
  case malayalam
  case sanskrit
  case sanskritRoman
  case sinhala
  case khmer
  case myanmarBurmese
  case lao
  case amharic
  case amharic1k
  case amharic5k
  case armenian
  case armenian1k
  case armenianWestern
  case armenianWestern1k
  case georgian
  case azerbaijani
  case azerbaijani1k
  case belarusian
  case belarusian1k
  case belarusian5k
  case belarusian10k
  case belarusian25k
  case belarusian50k
  case belarusian100k
  case belarusianLacinka
  case belarusianLacinka1k
  case lithuanian
  case lithuanian1k
  case lithuanian3k
  case latvian
  case latvian1k
  case mongolian
  case mongolian10k
  case irish
  case irish1k
  case galician
  case marathi
  case kurdishCentral
  case kurdishCentral2k
  case kurdishCentral4k
  case greek
  case greek1k
  case greek5k
  case greek10k
  case greek25k
  case greekKoine
  case greeklish
  case greeklish1k
  case greeklish5k
  case greeklish10k
  case greeklish25k
  case dutch
  case dutch1k
  case dutch10k
  case filipino
  case filipino1k
  case catalan
  case catalan1k
  case indonesian
  case indonesian1k
  case indonesian10k
  case malay
  case malay1k
  case danish
  case danish1k
  case danish10k
  case norwegianBokmal
  case norwegianBokmal1k
  case norwegianBokmal5k
  case norwegianBokmal10k
  case norwegianBokmal150k
  case norwegianBokmal600k
  case norwegianNynorsk
  case norwegianNynorsk1k
  case norwegianNynorsk5k
  case norwegianNynorsk10k
  case norwegianNynorsk100k
  case norwegianNynorsk400k
  case swedish
  case swedish1k
  case swedishDiacritics
  case hungarian
  case hungarian1k
  case hungarian2k
  case czech
  case czech1k
  case czech10k
  case slovak
  case slovak1k
  case slovak10k
  case slovenian
  case slovenian1k
  case slovenian5k
  case croatian
  case croatian1k
  case serbian
  case serbian10k
  case serbianLatin
  case serbianLatin10k
  case bulgarian
  case bulgarian1k
  case bulgarianLatin
  case bulgarianLatin1k
  case romanian
  case romanian1k
  case romanian5k
  case romanian10k
  case romanian25k
  case romanian50k
  case romanian100k
  case romanian200k
  case finnish
  case finnish1k
  case finnish10k
  case estonian
  case estonian1k
  case estonian5k
  case estonian10k
  case icelandic
  case icelandic1k
  case french
  case french1k
  case french2k
  case french10k
  case french600k
  case frenchBitoduc
  case italian
  case italian1k
  case italian7k
  case italian60k
  case italian280k
  case portuguese
  case portuguese1k
  case portuguese3k
  case portuguese5k
  case portuguese320k
  case portuguese550k
  case portugueseAccents
  case simplifiedChinese
  case simplifiedChinese1k
  case simplifiedChinese5k
  case simplifiedChinese10k
  case simplifiedChinese50k
  case traditionalChinese
  case traditionalChinese1k
  case traditionalChinese5k
  case traditionalChinese10k
  case traditionalChinese50k
  case russian
  case russian1k
  case russian5k
  case russian10k
  case russian25k
  case russian50k
  case russian375k
  case russianAbbreviations
  case russianContractions
  case russianContractions1k
  case ukrainian
  case ukrainian1k
  case ukrainian10k
  case ukrainian50k
  case ukrainianEndings
  case ukrainianLatin
  case ukrainianLatynka1k
  case ukrainianLatynka10k
  case ukrainianLatynka50k
  case ukrainianLatynkaEndings
  case japaneseHiragana
  case japaneseKatakana
  case japaneseRomaji
  case japaneseRomaji1k
  case korean
  case korean1k
  case korean5k
  case turkish
  case turkish1k
  case turkish5k
  case polish
  case polish2k
  case polish5k
  case polish10k
  case polish20k
  case polish40k
  case polish200k
  case mixedEnglishChinese
  case mixedLanguages
  case dockerFile
  case codeSwift
  case codeJavaScript
  case codePython
  case codePython1k
  case codePython2k
  case codePython5k
  case codeFSharp
  case codeC
  case codeCSharp
  case codeCSS
  case codeCPP
  case codeDart
  case codeBrainfck
  case codeJavaScript1k
  case codeJavaScriptReact
  case codeJule
  case codeJulia
  case codeHaskell
  case codeHTML
  case codeNim
  case codeNix
  case codePascal
  case codeJava
  case codeKotlin
  case codeGo
  case codeRockstar
  case codeRust
  case codeRuby
  case codeR
  case codeR2k
  case codeScala
  case codeBash
  case codePowerShell
  case codeLua
  case codeLuau
  case codeLaTeX
  case codeTypst
  case codeMATLAB
  case codeSQL
  case codePerl
  case codePHP
  case codeVim
  case codeVimscript
  case codeOpenCL
  case codeVisualBasic
  case codeArduino
  case codeSystemVerilog
  case codeElixir
  case codeGleam
  case codeZig
  case codeGDScript
  case codeGDScript2
  case codeAssembly
  case codeV
  case codeOok
  case codeTypeScript
  case codeCOBOL
  case codeClojure
  case codeCommonLisp
  case codeErlang
  case codeOCaml
  case codeOdin
  case codeFortran
  case codeABAP
  case codeABAP1k
  case codeYoptaScript
  case codeCUDA
  case codeVHDL
  case code6502Assembly
}

enum EnglishVariant: String, CaseIterable, Codable, Equatable, Identifiable {
  case american
  case british

  var id: Self { self }
}

enum QuoteLength: String, CaseIterable, Codable, Equatable, Identifiable {
  case all
  case short
  case medium
  case long
  case extended

  var id: Self { self }

  var compatibilityValue: String? {
    switch self {
    case .all: nil
    case .short: "0"
    case .medium: "1"
    case .long: "2"
    case .extended: "3"
    }
  }
}

enum QuoteSelectionMode: String, CaseIterable, Codable, Equatable, Identifiable {
  case lengths
  case favorites
  case search

  var id: Self { self }

  var advancesAutomatically: Bool { self != .search }

  var displayName: String {
    switch self {
    case .lengths: "按长度"
    case .favorites: "收藏"
    case .search: "搜索"
    }
  }
}

enum CustomTextCompletion: String, CaseIterable, Codable, Equatable, Identifiable {
  case finish
  case time
  case words
  case sections

  var id: Self { self }

  var displayName: String {
    switch self {
    case .finish: "输入完成"
    case .time: "循环计时"
    case .words: "循环字数"
    case .sections: "分节完成"
    }
  }
}

enum CustomTextOrdering: String, CaseIterable, Codable, Equatable, Identifiable {
  case inOrder
  case shuffled
  case random

  var id: Self { self }

  var displayName: String {
    switch self {
    case .inOrder: "按原顺序"
    case .shuffled: "打乱一次"
    case .random: "随机抽取"
    }
  }
}

enum TestModifier: String, CaseIterable, Codable, Equatable, Identifiable {
  case noSpaces
  case underscoreSeparators
  case uppercase
  case titleCase
  case alternatingCase
  case randomCase
  case messagingStyle
  case mirrorVisual
  case upsideDownVisual
  case crtVisual
  case earthquakeVisual
  case spaceVisual
  case nauseaVisual
  case roundVisual
  case chooVisual
  case layoutFluid
  case aslVisual
  case rot13
  case backwards
  case doubleCharacters
  case listening
  case simonSays
  case memory
  case readAheadEasy
  case readAhead
  case readAheadHard
  case noQuit
  case binaryStream
  case accountingStream
  case hexadecimalStream
  case symbolStream
  case asciiStream
  case specialCharacterStream
  case gibberishStream
  case poetryStream
  case referenceStream
  case arrowStream
  case ipv4Stream
  case ipv6Stream
  case mirrorKeyboard
  case pseudolangStream
  case morseStream
  case zipf
  case weakSpot
  case focusCurrentWord
  case focusNextWord
  case focusTwoWords
  case focusThreeWords
  case correctBeforeAdvance
  case clearCurrentWordOnError
  case lazyLatin

  var id: Self { self }

  static let inputPreferenceCases: [Self] = [.lazyLatin]
  static let funboxPreferenceCases: [Self] = allCases.filter { $0 != .lazyLatin }

  var displayName: String {
    switch self {
    case .noSpaces: "无空格"
    case .underscoreSeparators: "下划线分隔"
    case .uppercase: "全大写"
    case .titleCase: "逐词首字母大写"
    case .alternatingCase: "交替大小写"
    case .randomCase: "随机大小写"
    case .messagingStyle: "即时消息文本"
    case .mirrorVisual: "镜像练习区"
    case .upsideDownVisual: "倒置练习区"
    case .crtVisual: "CRT 练习区"
    case .earthquakeVisual: "地震练习区"
    case .spaceVisual: "太空练习区"
    case .nauseaVisual: "眩晕练习区"
    case .roundVisual: "旋转练习区"
    case .chooVisual: "旋转文字"
    case .layoutFluid: "布局流动"
    case .aslVisual: "ASL 指语练习"
    case .rot13: "ROT13"
    case .backwards: "逐词反写"
    case .doubleCharacters: "字符双写"
    case .listening: "听写模式"
    case .simonSays: "Simon 指令"
    case .memory: "记忆模式"
    case .readAheadEasy: "预读遮挡（当前词）"
    case .readAhead: "预读遮挡（当前和下一词）"
    case .readAheadHard: "预读遮挡（当前及后两词）"
    case .noQuit: "锁定重开"
    case .binaryStream: "二进制流"
    case .accountingStream: "会计数字流"
    case .hexadecimalStream: "十六进制流"
    case .symbolStream: "符号流"
    case .asciiStream: "ASCII 字符流"
    case .specialCharacterStream: "特殊符号流"
    case .gibberishStream: "无意义字串"
    case .poetryStream: "诗性散文"
    case .referenceStream: "知识短文"
    case .arrowStream: "方向键流"
    case .ipv4Stream: "IPv4 地址流"
    case .ipv6Stream: "IPv6 地址流"
    case .mirrorKeyboard: "镜像键盘"
    case .pseudolangStream: "伪语言词流"
    case .morseStream: "摩斯符号流"
    case .zipf: "Zipf 高频词"
    case .weakSpot: "弱项选词"
    case .focusCurrentWord: "专注当前词"
    case .focusNextWord: "预读下一词"
    case .focusTwoWords: "预读后两词"
    case .focusThreeWords: "预读后三词"
    case .correctBeforeAdvance: "修正后再前进"
    case .clearCurrentWordOnError: "遇错清除当前词"
    case .lazyLatin: "简化重音输入"
    }
  }
}

/// Carries rendered targets, not a recipe that can resample random transforms.
struct TransformedPromptBatch {
  let text: String
  let noSpaceWordLengths: [Int]
  let noSpaceTargetWords: [String]

  init(text: String, noSpaceTargetWords: [String] = []) {
    self.text = text
    let lengths = noSpaceTargetWords.map(\.count)
    // Preserve actual words even when joining fuses their glyphs. Only the
    // legacy grapheme-indexed engine's offsets require non-fusing boundaries.
    if !lengths.isEmpty, noSpaceTargetWords.joined().utf16.elementsEqual(text.utf16) {
      // Equal glyph totals are insufficient: three regional indicators can
      // regroup into two glyphs while moving the original first word's end.
      var glyphUnitEnds: Set<Int> = [0]
      var end = 0
      for glyph in text {
        end += glyph.utf16.count
        glyphUnitEnds.insert(end)
      }
      var wordEnd = 0
      let aligned = noSpaceTargetWords.allSatisfy { word in
        wordEnd += word.utf16.count
        return glyphUnitEnds.contains(wordEnd)
      }
      self.noSpaceWordLengths = aligned ? lengths : []
      self.noSpaceTargetWords = noSpaceTargetWords
    } else {
      self.noSpaceWordLengths = []
      self.noSpaceTargetWords = []
    }
  }
}

enum TestModifierPolicy {
  static let finiteDurationOnly: Set<TestModifier> = [
    .layoutFluid, .focusCurrentWord, .focusNextWord, .focusTwoWords, .focusThreeWords,
    .memory, .poetryStream, .referenceStream,
  ]

  /// Content modes whose visible prompt identity comes from the modifier,
  /// matching the fixed reference metadata's `ignoresLanguage` result rule.
  static let languageIndependentResultModifiers: Set<TestModifier> = [
    .underscoreSeparators, .binaryStream, .accountingStream, .hexadecimalStream,
    .symbolStream, .asciiStream, .specialCharacterStream, .gibberishStream,
    .poetryStream, .referenceStream, .arrowStream, .ipv4Stream, .ipv6Stream,
    .pseudolangStream, .morseStream,
  ]

  /// The fixed source declares compatibility through funbox metadata rather
  /// than one hand-written conflict list. These sets retain that observable
  /// contract while keeping Typebar's native-only modifiers independent.
  private static let sourceWordGeneratorModifiers: Set<TestModifier> = [
    .binaryStream, .accountingStream, .hexadecimalStream, .symbolStream,
    .asciiStream, .specialCharacterStream, .gibberishStream, .poetryStream,
    .referenceStream, .arrowStream, .ipv4Stream, .ipv6Stream,
    .pseudolangStream, .weakSpot,
  ]
  private static let sourceLayoutChangingModifiers: Set<TestModifier> = [
    .layoutFluid, .mirrorKeyboard,
  ]
  private static let sourceLayoutRestrictedModifiers: Set<TestModifier> = [
    .accountingStream, .arrowStream, .ipv4Stream, .ipv6Stream,
    .binaryStream, .hexadecimalStream, .morseStream, .underscoreSeparators,
    .simonSays,
  ]
  private static let sourceNoSpaceOrPushModifiers: Set<TestModifier> = [
    .noSpaces, .underscoreSeparators, .arrowStream, .morseStream,
    .focusCurrentWord, .focusNextWord, .focusTwoWords, .focusThreeWords,
  ]
  /// These funboxes do not append the normal inter-word commit character in
  /// the reference generator. `underscoreSeparators` supplies its own `_`
  /// token; the others concatenate their transformed word targets directly.
  private static let sourceNoSpaceInputModifiers: Set<TestModifier> = [
    .noSpaces, .underscoreSeparators, .arrowStream, .morseStream,
  ]
  private static let sourceWordVisibilityModifiers: Set<TestModifier> = [
    .listening, .simonSays, .memory,
    .focusCurrentWord, .focusNextWord, .focusTwoWords, .focusThreeWords,
    .readAheadEasy, .readAhead, .readAheadHard,
  ]
  private static let sourceFrequencyModifiers: Set<TestModifier> = [.zipf, .weakSpot]
  private static let sourceCapitalisationModifiers: Set<TestModifier> = [
    .uppercase, .titleCase, .alternatingCase, .randomCase, .messagingStyle,
  ]
  private static let sourceNoLetterModifiers: Set<TestModifier> = [
    .accountingStream, .arrowStream, .asciiStream, .specialCharacterStream,
    .ipv4Stream, .ipv6Stream, .binaryStream, .hexadecimalStream, .morseStream,
  ]
  private static let sourceSymmetricCharacterModifiers: Set<TestModifier> = [.arrowStream]
  private static let sourceSymmetricConflictModifiers: Set<TestModifier> = [
    .chooVisual, .backwards,
  ]
  private static let sourceCSSModifierGroups: [Set<TestModifier>] = [
    [.mirrorVisual, .upsideDownVisual],
    [.nauseaVisual, .roundVisual],
    [.listening, .chooVisual, .earthquakeVisual, .backwards, .aslVisual],
    [.crtVisual, .spaceVisual],
  ]
  private static let sourceZenIncompatibleModifiers: Set<TestModifier> =
    sourceWordGeneratorModifiers
    .union(sourceLayoutChangingModifiers)
    .union(sourceNoSpaceOrPushModifiers)
    .union(sourceWordVisibilityModifiers)
    .union(sourceFrequencyModifiers)
    .union(sourceCapitalisationModifiers)
    .union([.rot13, .backwards, .doubleCharacters, .morseStream])

  /// Mirrors the fixed source's mode gate before it accepts a funbox. Quote
  /// and custom tests retain text transformations but reject modes that supply
  /// or replace a word source; Zen additionally rejects transformations that
  /// require a generated target or constrained input.
  static func modifiersCompatibleWithMode(
    _ modifiers: [TestModifier], mode: TestMode
  ) -> [TestModifier] {
    let incompatible: Set<TestModifier>
    switch mode {
    case .time, .words:
      incompatible = []
    case .quote, .custom:
      incompatible = sourceWordGeneratorModifiers.union(sourceFrequencyModifiers)
    case .zen:
      incompatible = sourceZenIncompatibleModifiers
    }
    return modifiers.filter { !incompatible.contains($0) }
  }

  /// Interactive mode changes are rejected by the reference while an active
  /// funbox requires a different mode. Imports use `modifiersCompatibleWithMode`
  /// to sanitize persisted data instead.
  static func acceptsModeSelection(_ mode: TestMode, modifiers: [TestModifier]) -> Bool {
    guard !modifiers.contains(.memory) || MemoryFunboxModePolicy.allowedModes.contains(mode) else {
      return false
    }
    return modifiersCompatibleWithMode(modifiers, mode: mode) == modifiers
  }

  /// The reference rejects an interactive attempt to add a conflicting
  /// funbox, preserving the selected set. This differs from persisted-config
  /// normalization, which safely reduces legacy or imported combinations.
  static func acceptsInteractiveModifierAddition(
    _ modifier: TestModifier, to modifiers: [TestModifier]
  ) -> Bool {
    guard !modifiers.contains(modifier) else { return false }
    return isSourceCompatible(modifiers + [modifier])
  }

  /// Returns whether a group would be accepted by the fixed reference
  /// metadata validator. This is deliberately visible to the package so tests
  /// can assert the user-facing combination boundary directly.
  static func isSourceCompatible(_ modifiers: [TestModifier]) -> Bool {
    let selected = Set(modifiers)
    func hasAtMostOne(_ candidates: Set<TestModifier>) -> Bool {
      selected.intersection(candidates).count <= 1
    }

    guard hasAtMostOne(sourceWordGeneratorModifiers),
      hasAtMostOne(sourceNoSpaceOrPushModifiers),
      hasAtMostOne(sourceWordVisibilityModifiers),
      hasAtMostOne(sourceFrequencyModifiers),
      hasAtMostOne(sourceCapitalisationModifiers),
      sourceCSSModifierGroups.allSatisfy({ hasAtMostOne($0) })
    else { return false }

    let changesLayout = !selected.intersection(sourceLayoutChangingModifiers).isEmpty
    let hasLayoutRestriction = !selected.intersection(sourceLayoutRestrictedModifiers).isEmpty
    guard !(changesLayout && hasLayoutRestriction) else { return false }

    let changesCapitalisation = !selected.intersection(sourceCapitalisationModifiers).isEmpty
    let hasNoLetters = !selected.intersection(sourceNoLetterModifiers).isEmpty
    guard !(changesCapitalisation && hasNoLetters) else { return false }

    let usesSymmetricCharacters = !selected.intersection(sourceSymmetricCharacterModifiers).isEmpty
    let conflictsWithSymmetricCharacters =
      !selected.intersection(sourceSymmetricConflictModifiers).isEmpty
    guard !(usesSymmetricCharacters && conflictsWithSymmetricCharacters) else { return false }

    let changesFrequency = !selected.intersection(sourceFrequencyModifiers).isEmpty
    let ignoresLanguage = !selected.intersection(languageIndependentResultModifiers).isEmpty
    guard !(changesFrequency && ignoresLanguage) else { return false }

    let speaks = selected.contains(.listening)
    guard !(speaks && ignoresLanguage) else { return false }

    let pushesWords = selected.contains(.focusCurrentWord)
      || selected.contains(.focusNextWord)
      || selected.contains(.focusTwoWords)
      || selected.contains(.focusThreeWords)
    let pullsSection = selected.contains(.poetryStream) || selected.contains(.referenceStream)
    return !(pushesWords && pullsSection)
  }

  /// `polyglot` is represented by Typebar's language selection rather than a
  /// modifier. The source still treats it as a word provider that ignores its
  /// current language, so selecting it clears only incompatible modifiers.
  static func modifiersCompatibleWithPolyglot(_ modifiers: [TestModifier]) -> [TestModifier] {
    let incompatible = sourceWordGeneratorModifiers.union(sourceFrequencyModifiers).union([.listening])
    return normalized(modifiers.filter { !incompatible.contains($0) })
  }

  static func compatibleWithInfiniteTest(_ modifiers: [TestModifier]) -> [TestModifier] {
    normalized(modifiers).filter { !finiteDurationOnly.contains($0) }
  }

  /// Whether the reference generator removes the ordinary inter-word commit
  /// space for this modifier set. Keep this separate from visibility funboxes
  /// that merely push the viewport forward.
  static func usesNoSpaceInput(_ modifiers: [TestModifier]) -> Bool {
    !sourceNoSpaceInputModifiers.isDisjoint(with: modifiers)
  }

  static func normalized(_ modifiers: [TestModifier]) -> [TestModifier] {
    let boundaryModifier: TestModifier? =
      modifiers.contains(.noSpaces)
      ? .noSpaces
      : modifiers.contains(.underscoreSeparators) ? .underscoreSeparators : nil
    let caseModifier: TestModifier? =
      modifiers.contains(.uppercase)
      ? .uppercase
      : modifiers.contains(.titleCase)
        ? .titleCase
        : modifiers.contains(.alternatingCase)
          ? .alternatingCase
          : modifiers.contains(.randomCase) ? .randomCase : nil
    let messagingModifier = modifiers.contains(.messagingStyle) ? TestModifier.messagingStyle : nil
    let visibilityModifier: TestModifier? =
      modifiers.contains(.focusCurrentWord)
      ? .focusCurrentWord
      : modifiers.contains(.focusNextWord)
        ? .focusNextWord
        : modifiers.contains(.focusTwoWords)
          ? .focusTwoWords
          : modifiers.contains(.focusThreeWords) ? .focusThreeWords : nil
    let concealmentModifier: TestModifier? =
      modifiers.contains(.listening)
      ? .listening
      : modifiers.contains(.simonSays) ? .simonSays
      : modifiers.contains(.memory) ? .memory : nil
    let readAheadModifier: TestModifier? =
      modifiers.contains(.readAheadEasy)
      ? .readAheadEasy
      : modifiers.contains(.readAhead)
        ? .readAhead
        : modifiers.contains(.readAheadHard) ? .readAheadHard : nil
    let streamModifier: TestModifier? =
      modifiers.contains(.weakSpot)
      ? nil
      : modifiers.contains(.binaryStream)
      ? .binaryStream
      : modifiers.contains(.accountingStream)
        ? .accountingStream
      : modifiers.contains(.hexadecimalStream)
        ? .hexadecimalStream
        : modifiers.contains(.symbolStream)
          ? .symbolStream
        : modifiers.contains(.asciiStream)
          ? .asciiStream
        : modifiers.contains(.specialCharacterStream)
          ? .specialCharacterStream
        : modifiers.contains(.gibberishStream)
          ? .gibberishStream
        : modifiers.contains(.poetryStream)
          ? .poetryStream
        : modifiers.contains(.referenceStream)
          ? .referenceStream
          : modifiers.contains(.arrowStream)
            ? .arrowStream
          : modifiers.contains(.ipv4Stream)
            ? .ipv4Stream
            : modifiers.contains(.ipv6Stream)
              ? .ipv6Stream
              : modifiers.contains(.pseudolangStream) ? .pseudolangStream : nil
    let candidates = [
      boundaryModifier, caseModifier, messagingModifier, modifiers.contains(.rot13) ? .rot13 : nil,
      modifiers.contains(.backwards) ? .backwards : nil,
      modifiers.contains(.doubleCharacters) ? .doubleCharacters : nil, concealmentModifier,
      visibilityModifier, readAheadModifier,
      modifiers.contains(.correctBeforeAdvance) ? .correctBeforeAdvance : nil,
      modifiers.contains(.clearCurrentWordOnError) ? .clearCurrentWordOnError : nil,
      modifiers.contains(.lazyLatin) ? .lazyLatin : nil,
      modifiers.contains(.zipf) ? .zipf : nil,
      modifiers.contains(.weakSpot) ? .weakSpot : nil,
      modifiers.contains(.mirrorVisual) ? .mirrorVisual : nil,
      modifiers.contains(.upsideDownVisual) ? .upsideDownVisual : nil,
      modifiers.contains(.crtVisual) ? .crtVisual : nil,
      modifiers.contains(.earthquakeVisual) ? .earthquakeVisual : nil,
      modifiers.contains(.spaceVisual) ? .spaceVisual : nil,
      modifiers.contains(.nauseaVisual) ? .nauseaVisual : nil,
      modifiers.contains(.roundVisual) ? .roundVisual : nil,
      modifiers.contains(.chooVisual) ? .chooVisual : nil,
      modifiers.contains(.layoutFluid) ? .layoutFluid : nil,
      modifiers.contains(.aslVisual) ? .aslVisual : nil,
      modifiers.contains(.noQuit) ? .noQuit : nil, streamModifier,
      modifiers.contains(.mirrorKeyboard) ? .mirrorKeyboard : nil,
      modifiers.contains(.morseStream) ? .morseStream : nil,
    ].compactMap { $0 }
    return canonicalSourceCompatible(candidates)
  }

  static func toggling(_ modifier: TestModifier, in modifiers: [TestModifier]) -> [TestModifier] {
    if modifiers.contains(modifier) { return modifiers.filter { $0 != modifier } }
    let conflicts: Set<TestModifier>
    switch modifier {
    case .uppercase, .titleCase, .alternatingCase, .randomCase, .messagingStyle:
      conflicts = [.uppercase, .titleCase, .alternatingCase, .randomCase, .messagingStyle]
    case .noSpaces, .underscoreSeparators:
      conflicts = modifier == .noSpaces ? [.underscoreSeparators] : [.noSpaces]
    case .focusCurrentWord, .focusNextWord, .focusTwoWords, .focusThreeWords:
      conflicts = [
        .focusCurrentWord, .focusNextWord, .focusTwoWords, .focusThreeWords, .memory,
        .readAheadEasy, .readAhead, .readAheadHard,
      ]
    case .memory, .simonSays:
      conflicts = [
        .listening, .simonSays, .memory, .focusCurrentWord, .focusNextWord, .focusTwoWords, .focusThreeWords,
        .readAheadEasy, .readAhead, .readAheadHard,
      ]
    case .readAheadEasy, .readAhead, .readAheadHard:
      conflicts = [
        .listening, .simonSays, .memory, .focusCurrentWord, .focusNextWord, .focusTwoWords, .focusThreeWords,
        .readAheadEasy, .readAhead, .readAheadHard,
      ]
    case .listening: conflicts = [.simonSays, .memory, .readAheadEasy, .readAhead, .readAheadHard]
    case .weakSpot, .binaryStream, .accountingStream, .hexadecimalStream, .symbolStream, .asciiStream, .specialCharacterStream,
      .gibberishStream,
      .poetryStream,
      .referenceStream,
      .arrowStream, .ipv4Stream, .ipv6Stream,
      .pseudolangStream:
      conflicts = [
        .weakSpot, .binaryStream, .accountingStream, .hexadecimalStream, .symbolStream, .asciiStream, .specialCharacterStream,
        .gibberishStream,
        .poetryStream,
        .referenceStream,
        .arrowStream, .ipv4Stream, .ipv6Stream,
        .pseudolangStream,
      ]
    case .rot13, .backwards, .doubleCharacters, .correctBeforeAdvance, .clearCurrentWordOnError,
      .lazyLatin, .zipf, .mirrorVisual, .upsideDownVisual, .crtVisual, .earthquakeVisual, .spaceVisual,
      .nauseaVisual, .roundVisual, .chooVisual, .layoutFluid, .aslVisual,
      .noQuit, .mirrorKeyboard, .morseStream:
      conflicts = []
    }
    let afterExistingConflicts = modifiers.filter { !conflicts.contains($0) }
    let sourceConflicts = sourceCompatibilityConflicts(
      for: modifier, current: afterExistingConflicts)
    return normalized(afterExistingConflicts.filter { !sourceConflicts.contains($0) } + [modifier])
  }

  private static func canonicalSourceCompatible(_ candidates: [TestModifier]) -> [TestModifier] {
    candidates.reduce(into: [TestModifier]()) { accepted, candidate in
      if isSourceCompatible(accepted + [candidate]) {
        accepted.append(candidate)
      }
    }
  }

  private static func sourceCompatibilityConflicts(
    for modifier: TestModifier, current: [TestModifier]
  ) -> Set<TestModifier> {
    var retained = normalized(current)
    while !isSourceCompatible(retained + [modifier]) {
      guard let conflict = retained.reversed().first(where: {
        !isSourceCompatible([$0, modifier])
      }) else { break }
      retained.removeAll { $0 == conflict }
    }
    return Set(current).subtracting(retained)
  }

  static func transformed(
    _ prompt: String, modifiers: [TestModifier], language: TypingLanguage? = nil,
    nextRandomCaseBit: () -> Bool = { Bool.random() }
  ) -> String {
    transformedBatch(prompt, modifiers: modifiers, language: language,
      nextRandomCaseBit: nextRandomCaseBit).text
  }

  static func transformedBatch(
    _ prompt: String, modifiers: [TestModifier], language: TypingLanguage? = nil,
    preservesNoSpaceBoundaries: Bool = false, wordOffset: Int = 0, wordBound: Int? = nil,
    preservesWordOrder: Bool = false, formatsWordPool: Bool = false,
    britishEnglish: BritishEnglishPolicy.Context? = nil,
    nextRandomCaseBit: () -> Bool = { Bool.random() }
  ) -> TransformedPromptBatch {
    let presented = language?.presentationText(prompt) ?? prompt
    guard britishEnglish?.enabled == true || formatsWordPool || preservesNoSpaceBoundaries || modifiers.contains(where: { canonicalTextAlterations.contains($0)
      || [.noSpaces, .arrowStream, .lazyLatin].contains($0) }) else {
      return .init(text: presented)
    }
    let capturesTargets = usesNoSpaceInput(modifiers) || preservesNoSpaceBoundaries
    // A literal ASCII commit can share a grapheme with a following combining
    // mark. Split scalars so the mark stays in its word, not in the separator.
    var words = presented.unicodeScalars.split(separator: " ", omittingEmptySubsequences: false)
      .map { String(String.UnicodeScalarView($0)) }
    // Prepared pools/cursors retain their actual draw order; only the
    // standalone whole-text entry reverses its flat finite pool here.
    if modifiers.contains(.backwards), !preservesWordOrder { words.reverse() }
    var output = ""
    var targets: [String] = []
    var generatedWordIndex = wordOffset
    var previousBritishWord: String?
    for (index, word) in words.enumerated() {
      // A chunk's leading commit or repeated separators are not generated
      // words. Keep the standalone finite-text API's legacy behavior unless
      // a caller supplies the actual generation bound.
      let altered = word.isEmpty && wordBound != nil ? "" : transformedWord(word,
        modifiers: modifiers, language: language,
        wordIndex: wordBound == nil ? index : generatedWordIndex,
        wordBound: wordBound ?? words.count, britishEnglish: britishEnglish,
        previousBritishWord: previousBritishWord, nextRandomCaseBit: nextRandomCaseBit)
      if !word.isEmpty, britishEnglish?.isQuote == true {
        previousBritishWord = BritishEnglishPolicy.previousWordKey(altered)
      }
      if !word.isEmpty { generatedWordIndex += 1 }
      output += altered
      if capturesTargets, !word.isEmpty { targets.append(altered) }
      if index < words.count - 1, !capturesTargets, altered.unicodeScalars.last != "\n" {
        output.append(" ")
      }
    }
    // This batch API has historically represented a complete prompt. The
    // streaming word API below keeps newline commits until its caller knows
    // whether generation is actually complete.
    if modifiers.contains(.messagingStyle), output.hasSuffix("\n") {
      output.removeLast()
      if capturesTargets, targets.last?.hasSuffix("\n") == true {
        targets[targets.count - 1].removeLast()
      }
    }
    return .init(text: output, noSpaceTargetWords: targets)
  }

  // Direct reference toggles sort official names before applying alterText.
  // This is execution order, not the persisted native conflict-priority list.
  private static let canonicalTextAlterations: [TestModifier] = [
    .uppercase, .backwards, .titleCase, .doubleCharacters, .messagingStyle,
    .morseStream, .randomCase, .rot13, .alternatingCase, .underscoreSeparators,
  ]

  static func transformedWord(
    _ word: String, modifiers: [TestModifier], language: TypingLanguage? = nil,
    wordIndex: Int = 0, wordBound: Int = 1,
    britishEnglish: BritishEnglishPolicy.Context? = nil, previousBritishWord: String? = nil,
    nextRandomCaseBit: () -> Bool = { Bool.random() }
  ) -> String {
    var output = language?.presentationText(word) ?? word
    if modifiers.contains(.lazyLatin) {
      output = TypingTextNormalizer.lazyLatin(output, language: language)
    }
    output = BritishEnglishPolicy.transformed(output, context: britishEnglish, previousWord: previousBritishWord)
    for modifier in canonicalTextAlterations where modifiers.contains(modifier) {
      switch modifier {
      case .uppercase: output = output.uppercased()
      case .backwards: output = String(decoding: output.utf16.reversed(), as: UTF16.self)
      case .titleCase:
        // charAt(0) does not capitalize a whole astral letter. A first BMP
        // scalar may expand under uppercasing; retain all later units intact.
        if let first = output.unicodeScalars.first, first.value <= 0xFFFF {
          output = String(first).uppercased() + String(output.unicodeScalars.dropFirst())
        }
      case .doubleCharacters:
        output = output.unicodeScalars.reduce(into: "") { result, scalar in
          result.unicodeScalars.append(scalar)
          if ![0x0A, 0x0D, 0x2028, 0x2029].contains(scalar.value) {
            result.unicodeScalars.append(scalar)
          }
        }
      case .messagingStyle: output = MessagingTextPolicy.transformedWord(output)
      case .morseStream: output = MorseTextPolicy.transformed(output)
      case .randomCase: output = RandomCasePolicy.transformed(output, nextBit: nextRandomCaseBit)
      case .rot13:
        output = output.unicodeScalars.reduce(into: "") { result, scalar in
          let base: UInt32
          if (65...90).contains(scalar.value) { base = 65 }
          else if (97...122).contains(scalar.value) { base = 97 }
          else { result.unicodeScalars.append(scalar); return }
          result.unicodeScalars.append(UnicodeScalar(base + (scalar.value - base + 13) % 26)!)
        }
      case .alternatingCase: output = AlternatingCasePolicy.transformed(output)
      case .underscoreSeparators:
        if wordIndex != wordBound - 1 { output.append("_") }
      default: break
      }
    }
    if modifiers.contains(.arrowStream) { output.removeAll(where: \.isWhitespace) }
    return output
  }
}

/// Keeps direct Funbox controls consistent with the fixed source: a newly
/// requested conflicting modifier is rejected, rather than silently replacing
/// the user's existing selection. Persisted imports still use the separate
/// normalization path above.
enum InteractiveFunboxSelectionPolicy {
  static func updatedModifiers(
    toggling modifier: TestModifier, current: [TestModifier]
  ) -> [TestModifier]? {
    if current.contains(modifier) {
      return current.filter { $0 != modifier }
    }
    guard TestModifierPolicy.acceptsInteractiveModifierAddition(modifier, to: current) else {
      return nil
    }
    return current + [modifier]
  }
}

/// A Typebar-authored implementation of International Morse encoding. The
/// reference funbox transforms its active word source instead of replacing it;
/// this policy preserves that composition while keeping the mapping local.
enum MorseTextPolicy {
  private static let codeByCharacter: [Character: String] = [
    "a": ".-", "b": "-...", "c": "-.-.", "d": "-..", "e": ".", "f": "..-.",
    "g": "--.", "h": "....", "i": "..", "j": ".---", "k": "-.-", "l": ".-..",
    "m": "--", "n": "-.", "o": "---", "p": ".--.", "q": "--.-", "r": ".-.",
    "s": "...", "t": "-", "u": "..-", "v": "...-", "w": ".--", "x": "-..-",
    "y": "-.--", "z": "--..", "0": "-----", "1": ".----", "2": "..---",
    "3": "...--", "4": "....-", "5": ".....", "6": "-....", "7": "--...",
    "8": "---..", "9": "----.", ".": ".-.-.-", ",": "--..--", "?": "..--..",
    "'": ".----.", "/": "-..-.", "(": "-.--.", ")": "-.--.-", "&": ".-...",
    ":": "---...", ";": "-.-.-.", "=": "-...-", "+": ".-.-.", "-": "-....-",
    "_": "..--.-", "\"": ".-..-.", "$": "...-..-", "!": "-.-.--", "@": ".--.-.",
  ]

  static func transformed(_ text: String) -> String {
    // Canonical decomposition and the combining-diacritic block are the
    // source contract, not compatibility/width folding or transliteration.
    let scalars = text.decomposedStringWithCanonicalMapping.unicodeScalars
      .filter { !(0x0300...0x036F).contains($0.value) }
    let normalized = String(String.UnicodeScalarView(scalars)).lowercased()
    return normalized.unicodeScalars.reduce(into: "") { output, scalar in
      if let code = codeByCharacter[Character(String(scalar))] {
        output += code
        output.append("/")
      }
    }
  }
}

/// `sPoNgEcAsE` is applied by Monkeytype's generator to each word before its
/// commit separator is appended. Keep that word boundary observable in the
/// native prompt rather than carrying its lower/upper phase through spaces.
enum AlternatingCasePolicy {
  static func transformed(_ source: String) -> String {
    source.split(separator: " ", omittingEmptySubsequences: false).map { word in
      var utf16Offset = 0
      return word.unicodeScalars.reduce(into: "") { output, scalar in
        let character = String(scalar)
        output += utf16Offset.isMultiple(of: 2) ? character.lowercased() : character.uppercased()
        utf16Offset += scalar.value > 0xFFFF ? 2 : 1
      }
    }.joined(separator: " ")
  }
}

/// Mirrors the reference word-list metadata used to describe whether Zipf
/// sampling is meaningful. It is informational: Zipf stays enabled and keeps
/// its rank-weighted generator, exactly as the reference funbox does.
enum ZipfFrequencySupport: Equatable {
  case supported
  case unsupported
  case unknown
}

enum ZipfFrequencyPolicy {
  static func notice(for language: TypingLanguage, modifiers: [TestModifier]) -> String? {
    guard modifiers.contains(.zipf) else { return nil }
    switch language.zipfFrequencySupport {
    case .supported:
      return nil
    case .unsupported:
      return "\(language.displayName) 不支持 Zipf 高频词：该词表未按词频排序。请选择其他词表。"
    case .unknown:
      return "\(language.displayName) 可能不支持 Zipf 高频词：参考配置未说明词表是否按词频排序。"
    }
  }
}

/// Keeps Arabic's optional simplified-input default separate from the saved
/// modifier list. The user can still opt out, while non-Arabic configurations
/// retain only the modifiers they explicitly selected.
enum ArabicLazyInputPolicy {
  static func effectiveModifiers(
    _ modifiers: [TestModifier], language: TypingLanguage, mode: TestMode = .time,
    mixedLanguageComponents: [TypingLanguage] = [], automaticallyEnabled: Bool
  ) -> [TestModifier] {
    let supportsLazyInput: Bool
    if mode == .custom {
      // Monkeytype allows lazy mode for user-supplied text even when the
      // selected wordset marks it unavailable.
      supportsLazyInput = true
    } else if language == .mixedLanguages {
      // Its polyglot path enables the feature when any selected component
      // supports it, rather than requiring every component to do so.
      supportsLazyInput = mixedLanguageComponents.contains { $0.supportsLazyLatinInput }
    } else {
      supportsLazyInput = language.supportsLazyLatinInput
    }
    guard supportsLazyInput else {
      return TestModifierPolicy.normalized(modifiers.filter { $0 != .lazyLatin })
    }
    guard [.arabic, .arabic10k].contains(language), automaticallyEnabled else {
      return TestModifierPolicy.normalized(modifiers)
    }
    return TestModifierPolicy.normalized(modifiers + [.lazyLatin])
  }
}

/// Mirrors the fixed reference's `noJoiningScript` funbox guard. When the
/// selected language uses native glyph joining, activating any listed funbox
/// clears the entire funbox selection. Polyglot keeps its selected base
/// language semantics; the reference does not inspect every component here.
enum JoiningScriptFunboxPolicy {
  static let unsupportedModifiers: Set<TestModifier> = [
    .chooVisual, .earthquakeVisual, .crtVisual, .doubleCharacters, .aslVisual,
  ]

  static func shouldClearAll(
    modifiers: [TestModifier], language: TypingLanguage,
    mixedLanguageComponents: [TypingLanguage] = []
  ) -> Bool {
    // `mixedLanguageComponents` deliberately remains part of the public
    // policy signature so callers document the polyglot context. The source
    // guard checks only the selected language at activation time.
    _ = mixedLanguageComponents
    guard language != .mixedLanguages, language.usesJoiningScriptPrompt else { return false }
    return !unsupportedModifiers.isDisjoint(with: modifiers)
  }

  static func effectiveModifiers(
    _ modifiers: [TestModifier], language: TypingLanguage,
    mixedLanguageComponents: [TypingLanguage] = []
  ) -> [TestModifier] {
    guard !shouldClearAll(
      modifiers: modifiers, language: language,
      mixedLanguageComponents: mixedLanguageComponents)
    else { return [] }
    return TestModifierPolicy.normalized(modifiers)
  }
}

/// Mirrors the reference's `noInfiniteDuration` activation fallback. The
/// setter rejects changing an active finite-only funbox to zero, while
/// activating one from an infinite test changes that active limit to the
/// reference's finite default.
enum FiniteFunboxLimitPolicy {
  static let timeFallback = 15
  static let wordsFallback = 10

  static func fallbackLimit(
    for mode: TestMode, customTextCompletion: CustomTextCompletion,
    modifiers: [TestModifier]
  ) -> Int? {
    guard !TestModifierPolicy.finiteDurationOnly.isDisjoint(with: modifiers) else { return nil }
    switch mode {
    case .time: return timeFallback
    case .words: return wordsFallback
    case .custom:
      switch customTextCompletion {
      case .time: return timeFallback
      case .words: return wordsFallback
      case .finish, .sections: return nil
      }
    case .quote, .zen: return nil
    }
  }
}

struct PracticeVisualTransform: Equatable {
  let horizontalScale: Double
  let rotationDegrees: Double

  static func make(modifiers: [TestModifier]) -> Self {
    .init(
      horizontalScale: modifiers.contains(.mirrorVisual) ? -1 : 1,
      rotationDegrees: modifiers.contains(.upsideDownVisual) ? 180 : 0)
  }
}

struct PracticeVisualEffect: Equatable {
  let usesCRT: Bool
  let usesEarthquake: Bool
  let usesSpace: Bool
  let usesNausea: Bool
  let usesRound: Bool
  let usesChoo: Bool
  let usesASL: Bool

  static func make(modifiers: [TestModifier]) -> Self {
    .init(
      usesCRT: modifiers.contains(.crtVisual),
      usesEarthquake: modifiers.contains(.earthquakeVisual),
      usesSpace: modifiers.contains(.spaceVisual),
      usesNausea: modifiers.contains(.nauseaVisual),
      usesRound: modifiers.contains(.roundVisual),
      usesChoo: modifiers.contains(.chooVisual),
      usesASL: modifiers.contains(.aslVisual))
  }
}

/// Keeps the reference's `ignoreReducedMotion` metadata explicit. These
/// deliberate visual modes bypass only the operating-system preference; a
/// user can still opt into Typebar's own reduce-motion setting.
enum VisualFunboxReducedMotionPolicy {
  static let ignoringSystemMotionModifiers: Set<TestModifier> = [
    .nauseaVisual, .roundVisual, .chooVisual, .earthquakeVisual, .spaceVisual,
  ]

  static func shouldReduceMotion(
    modifiers: [TestModifier], typebarRequested: Bool, systemRequested: Bool
  ) -> Bool {
    typebarRequested || (
      systemRequested && ignoringSystemMotionModifiers.isDisjoint(with: modifiers))
  }
}

struct NauseaVisualTransform: Equatable {
  let rotationDegrees: Double
  let horizontalScale: Double
  let verticalScale: Double

  static let identity = Self(rotationDegrees: 0, horizontalScale: 1, verticalScale: 1)
}

enum NauseaVisualPolicy {
  static func transform(at date: Date, isEnabled: Bool, reducesMotion: Bool) -> NauseaVisualTransform {
    guard isEnabled && !reducesMotion else { return .identity }
    let phase = date.timeIntervalSinceReferenceDate * .pi * 2 / 6.8
    return .init(
      rotationDegrees: sin(phase) * 7,
      horizontalScale: 1.08 + cos(phase * 0.7) * 0.13,
      verticalScale: 0.94 + sin(phase * 1.2) * 0.09)
  }
}

enum RoundVisualPolicy {
  static func rotationDegrees(at date: Date, isEnabled: Bool, reducesMotion: Bool) -> Double {
    guard isEnabled && !reducesMotion else { return 0 }
    let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5)
    return phase / 5 * 360
  }
}

enum PracticeVisualAnimationPolicy {
  static func shouldAnimate(
    isEnabled: Bool, reducesMotion: Bool, systemReducedMotion: Bool,
    ignoresSystemReducedMotion: Bool
  ) -> Bool {
    isEnabled && !reducesMotion && (!systemReducedMotion || ignoresSystemReducedMotion)
  }
}

enum ChooVisualPolicy {
  static let cycleDuration: TimeInterval = 2

  static func rotationDegrees(at date: Date, isEnabled: Bool, reducesMotion: Bool) -> Double {
    guard isEnabled && !reducesMotion else { return 0 }
    let phase = date.timeIntervalSinceReferenceDate
      .truncatingRemainder(dividingBy: cycleDuration)
    return phase / cycleDuration * 360
  }
}

enum ASLMotionCue: Equatable {
  case jCurve
  case zZigzag
}

enum ASLHandshapePolicy {
  /// Original handshape categories used solely to draw Typebar's own vector
  /// prompts. They intentionally do not embed or depend on a third-party font.
  static func fingerMask(for character: Character) -> UInt8? {
    guard let scalar = character.uppercased().unicodeScalars.first, scalar.isASCII,
      (65...90).contains(scalar.value)
    else { return nil }
    let masks: [UInt8] = [
      0b00001, 0b11110, 0b00010, 0b00001, 0b00000, 0b00110, 0b00011,
      0b00011, 0b00001, 0b00001, 0b00110, 0b10010, 0b00000, 0b00000,
      0b00000, 0b00110, 0b00010, 0b00110, 0b00000, 0b00000, 0b00110,
      0b00110, 0b01110, 0b00010, 0b10001, 0b00010,
    ]
    return masks[Int(scalar.value - 65)]
  }

  static func motionCue(for character: Character) -> ASLMotionCue? {
    switch character.uppercased() {
    case "J": .jCurve
    case "Z": .zZigzag
    default: nil
    }
  }

  static func usesMotionCue(for character: Character) -> Bool {
    motionCue(for: character) != nil
  }
}

enum LayoutFluidPolicy {
  static let defaultLayouts: [KeyboardLayout] = [.ansiQwerty, .ansiColemak, .ansiDvorak]
  /// The reference configuration permits up to fifteen unique layouts. The
  /// native sequence therefore truncates only its selected layouts.
  static let maximumLayouts = 15
  static let maximumSupportedLayouts = min(maximumLayouts, KeyboardLayout.allCases.count)

  static func normalizedLayouts(_ layouts: [KeyboardLayout]) -> [KeyboardLayout] {
    var unique: [KeyboardLayout] = []
    for layout in layouts where !unique.contains(layout) {
      unique.append(layout)
    }
    return Array((unique.isEmpty ? defaultLayouts : unique).prefix(maximumLayouts))
  }

  static func activeLayout(
    completedWords: Int, wordLimit: Int?, layouts: [KeyboardLayout] = defaultLayouts
  ) -> KeyboardLayout {
    let layouts = normalizedLayouts(layouts)
    guard let wordLimit, wordLimit > 0 else { return layouts[0] }
    let wordsPerLayout = max(1, wordLimit / layouts.count)
    return layouts[min(layouts.count - 1, max(0, completedWords / wordsPerLayout))]
  }

  static func upcomingLayout(
    completedWords: Int, wordLimit: Int?, layouts: [KeyboardLayout] = defaultLayouts
  ) -> (layout: KeyboardLayout, wordsRemaining: Int)? {
    let layouts = normalizedLayouts(layouts)
    guard let wordLimit, wordLimit > 0, layouts.count > 1 else { return nil }
    let wordsPerLayout = max(1, wordLimit / layouts.count)
    let currentIndex = min(layouts.count - 1, max(0, completedWords / wordsPerLayout))
    let remaining = wordsPerLayout - (completedWords % wordsPerLayout)
    guard remaining <= 3, currentIndex + 1 < layouts.count else { return nil }
    return (layouts[currentIndex + 1], remaining)
  }

  /// The fixed reference's timer recomputes the selected layout from its
  /// integer elapsed-second tick. Keeping that integer boundary means a
  /// delayed native clock can catch up without stretching a layout segment.
  static func activeLayout(
    elapsedSeconds: Int, duration: TimeInterval?, layouts: [KeyboardLayout] = defaultLayouts
  ) -> KeyboardLayout {
    let layouts = normalizedLayouts(layouts)
    guard let duration, duration.isFinite, duration > 0 else { return layouts[0] }
    let secondsPerLayout = duration / Double(layouts.count)
    guard secondsPerLayout.isFinite, secondsPerLayout > 0 else { return layouts[0] }
    let index = Int((Double(max(0, elapsedSeconds)) / secondsPerLayout).rounded(.down))
    return layouts[min(layouts.count - 1, max(0, index))]
  }

  /// Countdown boundaries intentionally use the floor of each split, while
  /// the active layout remains based on the elapsed-time quotient. This
  /// preserves the fixed reference's behavior for durations that do not
  /// divide evenly by the selected layout count.
  static func upcomingLayout(
    elapsedSeconds: Int, duration: TimeInterval?, layouts: [KeyboardLayout] = defaultLayouts
  ) -> (layout: KeyboardLayout, secondsRemaining: Int)? {
    let layouts = normalizedLayouts(layouts)
    guard layouts.count > 1, let duration, duration.isFinite, duration > 0 else { return nil }
    let secondsPerLayout = duration / Double(layouts.count)
    guard secondsPerLayout.isFinite, secondsPerLayout > 0 else { return nil }
    let elapsedSeconds = max(0, elapsedSeconds)
    let currentIndex = Int((Double(elapsedSeconds) / secondsPerLayout).rounded(.down))
    guard currentIndex >= 0, currentIndex + 1 < layouts.count else { return nil }
    let switchSeconds = (1..<layouts.count).map {
      Int((secondsPerLayout * Double($0)).rounded(.down))
    }
    for secondsRemaining in stride(from: 3, through: 1, by: -1)
      where switchSeconds.contains(elapsedSeconds + secondsRemaining)
    {
      return (layouts[currentIndex + 1], secondsRemaining)
    }
    return nil
  }
}

enum StarfieldPolicy {
  static func point(index: Int, in size: CGSize) -> CGPoint {
    precondition(index >= 0)
    let x = Double((index * 73 + 29) % 101) / 100 * size.width
    let y = Double((index * 47 + 11) % 97) / 96 * size.height
    return .init(x: x, y: y)
  }
}

enum EarthquakeOffsetPolicy {
  static func offset(at date: Date, isEnabled: Bool, reducesMotion: Bool) -> (x: Double, y: Double) {
    guard isEnabled && !reducesMotion else { return (0, 0) }
    let seconds = date.timeIntervalSinceReferenceDate
    return (sin(seconds * 18) * 3.2, cos(seconds * 23) * 1.8)
  }
}

enum RandomCasePolicy {
  /// Mirrors the source funbox's per-Unicode-scalar random choice. Punctuation
  /// and spacing remain visually unchanged but still consume a choice, so later
  /// letters receive the same independent treatment as the web generator.
  static func transformed(
    _ value: String, nextBit: () -> Bool = { Bool.random() }
  ) -> String {
    value.unicodeScalars.reduce(into: "") { output, scalar in
      let character = String(scalar)
      output += nextBit() ? character.uppercased() : character.lowercased()
    }
  }
}

enum MessagingTextPolicy {
  /// Mirrors the source funbox's per-word chat conversion. Only an ASCII terminal
  /// `.`, `!`, or `?` becomes a line break; punctuation inside a word remains
  /// input, as do brackets and non-ASCII sentence marks.
  static func transformed(_ value: String) -> String {
    let words = value.split(separator: " ", omittingEmptySubsequences: false)
    let transformedWords = words.map { transformedWord(String($0)) }
    var output = ""
    for (index, word) in transformedWords.enumerated() {
      output += word
      if index < transformedWords.count - 1, !word.hasSuffix("\n") {
        output.append(" ")
      }
    }
    return collapsingNewlines(in: output).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func transformedWord(_ source: String) -> String {
    var output = source.lowercased()
    if let terminal = output.last, ".!?".contains(terminal) {
      output.removeLast()
      output.append("\n")
    }
    let removable = CharacterSet(charactersIn: ".()'\"")
    let stripped = output.unicodeScalars.reduce(into: "") { result, scalar in
      if !removable.contains(scalar) { result.unicodeScalars.append(scalar) }
    }
    return collapsingNewlines(in: stripped)
  }

  private static func collapsingNewlines(in value: String) -> String {
    value.reduce(into: "") { output, character in
      guard character != "\n" || output.last != "\n" else { return }
      output.append(character)
    }
  }
}

enum TypingTextNormalizer {
  static func lazyLatin(_ value: String, language: TypingLanguage? = nil) -> String {
    replaceAccents(in: value, replacements: replacements(for: language))
  }

  /// Lazy input is a deliberately finite replacement table, not generic
  /// Unicode accent folding. This preserves glyphs that the reference leaves
  /// literal (for example, Spanish ñ) while retaining its combining-mark
  /// behavior and casing for multi-character expansions.
  private static func replaceAccents(in value: String, replacements: [String: String]) -> String {
    guard !value.isEmpty else { return value }

    let uppercasedUnits = Array(value.uppercased().utf16)
    let sourceScalars = Array(value.unicodeScalars)
    let caseFlags = sourceScalars.enumerated().map { index, scalar in
      guard index < uppercasedUnits.count,
        let uppercasedScalar = UnicodeScalar(UInt32(uppercasedUnits[index]))
      else { return false }
      return scalar == uppercasedScalar
    }
    let units = Array(value.utf16)
    var output = ""
    var index = 0

    while index < units.count {
      let unit = units[index]
      if (0xD800...0xDBFF).contains(unit), index + 1 < units.count,
        (0xDC00...0xDFFF).contains(units[index + 1])
      {
        output += String(decoding: units[index...index + 1], as: UTF16.self)
        index += 2
        continue
      }

      guard let scalar = UnicodeScalar(UInt32(unit)) else {
        output += String(decoding: [unit], as: UTF16.self)
        index += 1
        continue
      }

      let lookup = String(scalar).lowercased().unicodeScalars.first.map(String.init)
      guard let lookup, let replacement = replacements[lookup] else {
        let source = String(scalar)
        output += isUppercase(caseFlags, at: index) ? source.uppercased() : source
        index += 1
        continue
      }

      for (offset, replacementScalar) in replacement.unicodeScalars.enumerated() {
        let replacementCharacter = String(replacementScalar)
        output += isUppercase(caseFlags, at: index + offset)
          ? replacementCharacter.uppercased()
          : replacementCharacter
      }
      index += 1
    }

    return output
  }

  private static func isUppercase(_ flags: [Bool], at index: Int) -> Bool {
    index < flags.count && flags[index]
  }

  private static let commonReplacements = replacementMap(from: [
    ("áàâäåãą\u{0301}ā\u{0304}ă", "a"),
    ("éèêëẽę\u{0301}ē\u{0304}ėě", "e"),
    ("íìîïĩį\u{0301}ī\u{0304}ı", "i"),
    ("óòôöøõōǫ\u{0301}ǭő", "o"),
    ("úùûüŭũūůű", "u"),
    ("ńňṇṅ", "n"),
    ("çĉčć", "c"),
    ("řŕṛ", "r"),
    ("ďđḍ", "d"),
    ("ťțṭ", "t"),
    ("ṃ", "m"),
    ("æ", "ae"),
    ("œ", "oe"),
    ("ẅŵ", "w"),
    ("ĝğg\u{0303}", "g"),
    ("ĥ", "h"),
    ("ĵ", "j"),
    ("ŝśšșşṣ", "s"),
    ("ß", "ss"),
    ("żźž", "z"),
    ("ÿỹýŷ", "y"),
    ("łľĺ", "l"),
    ("أإآ", "ا"),
    ("ًٌٍَُِّْ", ""),
    ("ё", "е"),
    ("ά", "α"),
    ("έ", "ε"),
    ("ί", "ι"),
    ("ύ", "υ"),
    ("ό", "ο"),
    ("ή", "η"),
    ("ώ", "ω"),
    ("þ", "th"),
  ])

  private static func replacements(for language: TypingLanguage?) -> [String: String] {
    var replacements = commonReplacements
    for rule in languageSpecificRules(for: language) {
      for scalar in rule.0.unicodeScalars {
        replacements[String(scalar)] = rule.1
      }
    }
    return replacements
  }

  /// Language-specific sequences overlay the common table character by
  /// character. This is important for the reference's combined-script rules:
  /// their later scalar entries intentionally take precedence.
  private static func languageSpecificRules(for language: TypingLanguage?) -> [(String, String)] {
    switch language {
    case .german, .german1k, .german10k, .german250k:
      return [("ä", "ae"), ("ö", "oe"), ("ü", "ue")]
    case .serbianLatin, .serbianLatin10k:
      return [("đ", "dj")]
    case .pinyin, .pinyin1k, .pinyin10k:
      return [
        ("āáǎà", "a"), ("ōóǒò", "o"), ("ēéěè", "e"), ("īíǐì", "i"),
        ("ūúǔù", "u"), ("üǖǘǚǜ", "v"),
      ]
    case .quenya:
      return [
        ("äá", "a"), ("öó", "o"), ("ëé", "e"), ("í", "i"),
        ("Úú", "u"), ("χ", "x"), ("þ", "p"),
      ]
    case .yiddish:
      return [
        ("אַ", "א"), ("אָ", "א"), ("בּ", "ב"), ("בֿ", "ב"),
        ("וּ", "ו"), ("וֹ", "ו"), ("יִ", "י"), ("כּ", "כ"),
        ("פּ", "פ"), ("פֿ", "פ"), ("שׂ", "ש"), ("תּ", "ת"),
        ("ײַ", "יי"), ("ײ", "יי"), ("ױ", "וי"), ("װ", "וו"),
      ]
    case .vietnamese, .vietnamese1k, .vietnamese5k:
      return [
        ("áàăắằẵẳâấầẫẩãảạặậ", "a"), ("đ", "d"),
        ("éèêếềễểẽẻẹệ", "e"), ("íìĩỉị", "i"),
        ("óòôốồỗổõỏơớờỡởợọộ", "o"), ("úùũủưứừữửựụ", "u"),
        ("ýỳỹỷỵ", "y"),
      ]
    default:
      return []
    }
  }

  private static func replacementMap(from rules: [(String, String)]) -> [String: String] {
    rules.reduce(into: [:]) { map, rule in
      for scalar in rule.0.unicodeScalars {
        map[String(scalar)] = rule.1
      }
    }
  }
}

struct InputRules: Codable, Equatable {
  var strictSpace = false
  /// Legacy Boolean retained in saved configurations for backward decoding.
  /// New callers should select `stopOnErrorMode`.
  var stopOnError = false
  var stopOnErrorMode: StopOnErrorMode = .off
  /// Legacy Boolean retained in saved configurations for backward decoding.
  /// New callers should select `deleteOnErrorMode`.
  var deleteOnError = false
  var deleteOnErrorMode: DeleteOnErrorMode = .off
  var hideExtraLetters = false
  var blindMode = false
  var quickEnd = false
  var freedomMode = false
  var confidenceMode: ConfidenceMode = .off
  var oppositeShiftMode: OppositeShiftMode = .off
  var codeUnindentOnBackspace = false
  /// Zero disables the final-accuracy threshold. A positive threshold is
  /// evaluated whenever a finite test would otherwise complete.
  var minimumAccuracy = 0.0
  /// Zero disables the final whole-test WPM threshold.
  var minimumWpm = 0.0
  /// Zero disables Typebar's minimum per-word speed rule. A positive value
  /// is evaluated after a measurable, space-delimited word commit.
  var minimumWordBurstWpm = 0.0
  var minimumWordBurstMode: MinimumWordBurstMode = .off

  init(
    strictSpace: Bool = false,
    stopOnError: Bool = false,
    stopOnErrorMode: StopOnErrorMode = .off,
    deleteOnError: Bool = false,
    deleteOnErrorMode: DeleteOnErrorMode = .off,
    hideExtraLetters: Bool = false,
    blindMode: Bool = false,
    quickEnd: Bool = false,
    freedomMode: Bool = false,
    confidenceMode: ConfidenceMode = .off,
    oppositeShiftMode: OppositeShiftMode = .off,
    codeUnindentOnBackspace: Bool = false,
    minimumAccuracy: Double = 0,
    minimumWpm: Double = 0,
    minimumWordBurstWpm: Double = 0,
    minimumWordBurstMode: MinimumWordBurstMode = .off
  ) {
    self.strictSpace = strictSpace
    self.stopOnErrorMode = stopOnErrorMode.isEnabled
      ? stopOnErrorMode : (stopOnError ? .letter : .off)
    self.deleteOnErrorMode = deleteOnErrorMode.isEnabled
      ? deleteOnErrorMode : (deleteOnError ? .letter : .off)
    self.stopOnError = self.stopOnErrorMode.isEnabled
    self.deleteOnError = self.deleteOnErrorMode.isEnabled
    self.hideExtraLetters = hideExtraLetters
    self.blindMode = blindMode
    self.quickEnd = quickEnd
    self.freedomMode = freedomMode
    self.confidenceMode = confidenceMode
    self.oppositeShiftMode = oppositeShiftMode
    self.codeUnindentOnBackspace = codeUnindentOnBackspace
    self.minimumAccuracy = PracticeThresholdPolicy.accuracy(minimumAccuracy)
    self.minimumWpm = PracticeThresholdPolicy.speed(minimumWpm)
    self.minimumWordBurstWpm = PracticeThresholdPolicy.speed(minimumWordBurstWpm)
    self.minimumWordBurstMode = minimumWordBurstMode == .off && self.minimumWordBurstWpm > 0
      ? .fixed : minimumWordBurstMode
    normalizeErrorHandlingModes()
  }

  private enum CodingKeys: String, CodingKey {
    case strictSpace, stopOnError, stopOnErrorMode, deleteOnError, deleteOnErrorMode,
      hideExtraLetters, blindMode, quickEnd,
      freedomMode, confidenceMode, oppositeShiftMode, codeUnindentOnBackspace, minimumAccuracy, minimumWpm,
      minimumWordBurstWpm, minimumWordBurstMode
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    strictSpace = try values.decodeIfPresent(Bool.self, forKey: .strictSpace) ?? false
    let legacyStopOnError = try values.decodeIfPresent(Bool.self, forKey: .stopOnError) ?? false
    stopOnErrorMode = try values.decodeIfPresent(StopOnErrorMode.self, forKey: .stopOnErrorMode)
      ?? (legacyStopOnError ? .letter : .off)
    stopOnError = stopOnErrorMode.isEnabled
    let legacyDeleteOnError = try values.decodeIfPresent(Bool.self, forKey: .deleteOnError) ?? false
    deleteOnErrorMode =
      try values.decodeIfPresent(DeleteOnErrorMode.self, forKey: .deleteOnErrorMode)
      ?? (legacyDeleteOnError ? .letter : .off)
    deleteOnError = deleteOnErrorMode.isEnabled
    hideExtraLetters = try values.decodeIfPresent(Bool.self, forKey: .hideExtraLetters) ?? false
    blindMode = try values.decodeIfPresent(Bool.self, forKey: .blindMode) ?? false
    quickEnd = try values.decodeIfPresent(Bool.self, forKey: .quickEnd) ?? false
    freedomMode = try values.decodeIfPresent(Bool.self, forKey: .freedomMode) ?? false
    confidenceMode = try values.decodeIfPresent(ConfidenceMode.self, forKey: .confidenceMode) ?? .off
    oppositeShiftMode =
      try values.decodeIfPresent(OppositeShiftMode.self, forKey: .oppositeShiftMode) ?? .off
    codeUnindentOnBackspace =
      try values.decodeIfPresent(Bool.self, forKey: .codeUnindentOnBackspace) ?? false
    minimumAccuracy = PracticeThresholdPolicy.accuracy(
      try values.decodeIfPresent(Double.self, forKey: .minimumAccuracy) ?? 0)
    minimumWpm = PracticeThresholdPolicy.speed(
      try values.decodeIfPresent(Double.self, forKey: .minimumWpm) ?? 0)
    minimumWordBurstWpm = PracticeThresholdPolicy.speed(
      try values.decodeIfPresent(Double.self, forKey: .minimumWordBurstWpm) ?? 0)
    minimumWordBurstMode =
      try values.decodeIfPresent(MinimumWordBurstMode.self, forKey: .minimumWordBurstMode)
      ?? (minimumWordBurstWpm > 0 ? .fixed : .off)
    normalizeErrorHandlingModes()
  }

  mutating func normalizeErrorHandlingModes() {
    // Configurations saved before variants used Booleans. Also honor callers
    // that still set those public compatibility fields after initialization.
    if stopOnError && stopOnErrorMode == .off { stopOnErrorMode = .letter }
    if deleteOnError && deleteOnErrorMode == .off { deleteOnErrorMode = .letter }
    if minimumWordBurstWpm <= 0 {
      minimumWordBurstMode = .off
    } else if minimumWordBurstMode == .off {
      minimumWordBurstMode = .fixed
    }
    if confidenceMode != .off {
      stopOnErrorMode = .off
      deleteOnErrorMode = .off
    } else if stopOnErrorMode.isEnabled {
      deleteOnErrorMode = .off
    } else if deleteOnErrorMode.isEnabled {
      stopOnErrorMode = .off
    }
    stopOnError = stopOnErrorMode.isEnabled
    deleteOnError = deleteOnErrorMode.isEnabled
  }
}

struct ContentOptions: Codable, Equatable {
  var includePunctuation = false
  var includeNumbers = false
}

/// Fixed funbox metadata can constrain the source content options. Keep this
/// separate from stream generation so configurations, saved presets, results,
/// and imported links describe the same effective test.
enum FunboxForcedContentOptionsPolicy {
  static let punctuationDisabledModifiers: Set<TestModifier> = [
    .arrowStream, .asciiStream, .specialCharacterStream, .poetryStream, .referenceStream,
    .binaryStream,
  ]

  static let numbersDisabledModifiers: Set<TestModifier> = [
    .accountingStream, .arrowStream, .asciiStream, .specialCharacterStream, .poetryStream,
    .referenceStream, .ipv4Stream, .ipv6Stream, .binaryStream, .hexadecimalStream,
  ]

  /// The fixed source metadata only restricts highlighting for this subset.
  /// Native presentation can impose additional temporary fallbacks when a
  /// prompt has no reliable word boundaries, but those do not reject a saved
  /// user preference.
  static let characterOnlyHighlightModifiers: Set<TestModifier> = [
    .simonSays, .listening, .arrowStream, .readAheadEasy, .readAhead, .readAheadHard, .noSpaces,
  ]

  static let allowedForcedHighlightModes: Set<PromptHighlightMode> = [.letter, .off]

  /// Direct configuration changes are rejected by the reference whenever a
  /// funbox forces punctuation or numbers off. Persisted data is instead
  /// sanitized by `effectiveOptions`.
  static func accepts(_ selected: ContentOptions, modifiers: [TestModifier]) -> Bool {
    effectiveOptions(selected, modifiers: modifiers) == selected
  }

  /// Mirrors the source `highlightMode: ["letter", "off"]` constraint.
  static func accepts(
    promptHighlightMode: PromptHighlightMode, modifiers: [TestModifier]
  ) -> Bool {
    characterOnlyHighlightModifiers.isDisjoint(with: Set(modifiers))
      || allowedForcedHighlightModes.contains(promptHighlightMode)
  }

  static func effectiveOptions(
    _ selected: ContentOptions, modifiers: [TestModifier]
  ) -> ContentOptions {
    let activeModifiers = Set(modifiers)
    return .init(
      includePunctuation: selected.includePunctuation
        && punctuationDisabledModifiers.isDisjoint(with: activeModifiers),
      includeNumbers: selected.includeNumbers
        && numbersDisabledModifiers.isDisjoint(with: activeModifiers))
  }
}

/// Fresh local selection follows the pinned reference's 30-second test and
/// medium quote filter. Persisted selections keep their own explicit values.
enum TypebarInitialTestSelection {
  static let configuration = TestConfiguration(
    mode: .time, duration: 30, wordLimit: nil, difficulty: .normal,
    rules: .init(), quoteLengths: [.medium])
}

struct TestConfiguration: Codable, Equatable {
  var mode: TestMode
  var duration: TimeInterval?
  var wordLimit: Int?
  var difficulty: Difficulty
  var rules: InputRules
  var language: TypingLanguage
  var englishVariant: EnglishVariant
  var quoteLength: QuoteLength
  /// Nil preserves single-length configurations written before quote length
  /// became a multi-selection. New quote presets encode the concrete set.
  var quoteLengths: Set<QuoteLength>?
  /// Missing in older archives and links, which decode to the historical
  /// length-filter behavior.
  var quoteSelectionMode: QuoteSelectionMode
  var customTextCompletion: CustomTextCompletion
  var customTextSectionLimit: Int?
  var customTextOrdering: CustomTextOrdering
  /// Nil preserves the historical native default: pipes only for section
  /// completion. Explicit values keep the delimiter independent of limits.
  var customTextPipeDelimiter: Bool?
  var mixedLanguageComponents: [TypingLanguage]
  var modifiers: [TestModifier]
  var contentOptions: ContentOptions
  var challengeID: String?

  var isInfinite: Bool {
    Self.usesInfiniteLimit(
      mode: mode, duration: duration, wordLimit: wordLimit,
      customTextCompletion: customTextCompletion, customTextSectionLimit: customTextSectionLimit)
  }

  var usesCustomTextPipeDelimiter: Bool {
    customTextPipeDelimiter ?? (customTextCompletion == .sections)
  }

  /// Mirrors reference `joiningScript` metadata for native prompt shaping.
  /// A mixed prompt needs this behavior when any selected component needs it.
  var usesJoiningScriptPrompt: Bool {
    language.usesJoiningScriptPrompt
      || (language == .mixedLanguages && mixedLanguageComponents.contains { $0.usesJoiningScriptPrompt })
  }

  /// A polyglot prompt uses an RTL paragraph base only when every selected
  /// language is RTL. Mixed-direction prompts keep the native LTR base and
  /// let macOS apply Unicode bidirectional layout to each run.
  var usesRightToLeftPrompt: Bool {
    guard language == .mixedLanguages else { return language.usesRightToLeftPrompt }
    return !mixedLanguageComponents.isEmpty
      && mixedLanguageComponents.allSatisfy(\.usesRightToLeftPrompt)
  }

  /// Character-position overlays support a wholly RTL paragraph. Mixed-direction
  /// polyglots remain on the glyph-attached fallback to avoid guessing an
  /// inline edge across Unicode bidirectional runs.
  var containsRightToLeftPromptRun: Bool {
    language.usesRightToLeftPrompt
      || (language == .mixedLanguages
        && mixedLanguageComponents.contains(where: \.usesRightToLeftPrompt))
  }

  init(
    mode: TestMode, duration: TimeInterval?, wordLimit: Int?, difficulty: Difficulty,
    rules: InputRules, language: TypingLanguage = .english,
    englishVariant: EnglishVariant = .american, quoteLength: QuoteLength = .all,
    quoteLengths: Set<QuoteLength>? = nil,
    quoteSelectionMode: QuoteSelectionMode = .lengths,
    customTextCompletion: CustomTextCompletion = .finish, customTextSectionLimit: Int? = nil,
    customTextOrdering: CustomTextOrdering = .inOrder,
    customTextPipeDelimiter: Bool? = nil,
    mixedLanguageComponents: [TypingLanguage] = TypingLanguage.referenceDefaultMixedComponents,
    modifiers: [TestModifier] = [], contentOptions: ContentOptions = .init(),
    challengeID: String? = nil
  ) {
    self.mode = mode
    self.duration = duration
    self.wordLimit = wordLimit
    self.difficulty = difficulty
    var normalizedRules = rules
    normalizedRules.normalizeErrorHandlingModes()
    if normalizedRules.confidenceMode != .off { normalizedRules.freedomMode = false }
    self.rules = normalizedRules
    self.language = language
    self.englishVariant = englishVariant
    let normalizedQuoteLengths = quoteLengths.map(QuoteLengthSelection.normalized)
    self.quoteLength = normalizedQuoteLengths.map(QuoteLengthSelection.legacyValue) ?? quoteLength
    self.quoteLengths = normalizedQuoteLengths
    self.quoteSelectionMode = quoteSelectionMode
    self.customTextCompletion = customTextCompletion
    self.customTextSectionLimit = customTextSectionLimit
    self.customTextOrdering = customTextOrdering
    self.customTextPipeDelimiter = customTextPipeDelimiter
    let normalizedMixedLanguageComponents = TypingLanguage.normalizedMixedComponents(
      mixedLanguageComponents)
    self.mixedLanguageComponents = normalizedMixedLanguageComponents
    let normalizedModifiers = JoiningScriptFunboxPolicy.effectiveModifiers(
      modifiers, language: language, mixedLanguageComponents: normalizedMixedLanguageComponents)
    let effectiveMode = MemoryFunboxModePolicy.effectiveMode(
      requested: mode, modifiers: normalizedModifiers)
    if effectiveMode != mode {
      self.mode = effectiveMode
      self.duration = nil
      self.wordLimit = wordLimit ?? MemoryFunboxModePolicy.fallbackWordLimit
    }
    let modeCompatibleModifiers = TestModifierPolicy.modifiersCompatibleWithMode(
      normalizedModifiers, mode: self.mode)
    self.modifiers = Self.usesInfiniteLimit(
      mode: self.mode, duration: self.duration, wordLimit: self.wordLimit,
      customTextCompletion: customTextCompletion, customTextSectionLimit: customTextSectionLimit)
      ? TestModifierPolicy.compatibleWithInfiniteTest(modeCompatibleModifiers) : modeCompatibleModifiers
    self.contentOptions = FunboxForcedContentOptionsPolicy.effectiveOptions(
      contentOptions, modifiers: self.modifiers)
    self.challengeID = challengeID
  }

  static func timed(
    seconds: TimeInterval, difficulty: Difficulty = .normal, rules: InputRules = .init(),
    language: TypingLanguage = .english, englishVariant: EnglishVariant = .american,
    mixedLanguageComponents: [TypingLanguage] = TypingLanguage.referenceDefaultMixedComponents,
    contentOptions: ContentOptions = .init()
  ) -> Self {
    .init(
      mode: .time, duration: seconds, wordLimit: nil, difficulty: difficulty, rules: rules,
      language: language, englishVariant: englishVariant,
      mixedLanguageComponents: mixedLanguageComponents, contentOptions: contentOptions)
  }

  static func words(
    _ count: Int, difficulty: Difficulty = .normal, rules: InputRules = .init(),
    language: TypingLanguage = .english, englishVariant: EnglishVariant = .american,
    mixedLanguageComponents: [TypingLanguage] = TypingLanguage.referenceDefaultMixedComponents,
    contentOptions: ContentOptions = .init()
  ) -> Self {
    .init(
      mode: .words, duration: nil, wordLimit: count, difficulty: difficulty, rules: rules,
      language: language, englishVariant: englishVariant,
      mixedLanguageComponents: mixedLanguageComponents, contentOptions: contentOptions)
  }

  func with(modifiers: [TestModifier]) -> Self {
    var copy = self
    let normalizedModifiers = JoiningScriptFunboxPolicy.effectiveModifiers(
      modifiers, language: copy.language, mixedLanguageComponents: copy.mixedLanguageComponents)
    let effectiveMode = MemoryFunboxModePolicy.effectiveMode(
      requested: copy.mode, modifiers: normalizedModifiers)
    if effectiveMode != copy.mode {
      copy.mode = effectiveMode
      copy.duration = nil
      copy.wordLimit = copy.wordLimit ?? MemoryFunboxModePolicy.fallbackWordLimit
    }
    let modeCompatibleModifiers = TestModifierPolicy.modifiersCompatibleWithMode(
      normalizedModifiers, mode: copy.mode)
    copy.modifiers = copy.isInfinite
      ? TestModifierPolicy.compatibleWithInfiniteTest(modeCompatibleModifiers) : modeCompatibleModifiers
    copy.contentOptions = FunboxForcedContentOptionsPolicy.effectiveOptions(
      copy.contentOptions, modifiers: copy.modifiers)
    return copy
  }

  func with(challengeID: String?) -> Self {
    var copy = self
    copy.challengeID = challengeID
    return copy
  }

  var visibleFutureWordCount: Int? {
    if modifiers.contains(.focusCurrentWord) { return 0 }
    if modifiers.contains(.focusNextWord) { return 1 }
    if modifiers.contains(.focusTwoWords) { return 2 }
    if modifiers.contains(.focusThreeWords) { return 3 }
    return nil
  }

  var readAheadConcealedWordCount: Int? {
    if modifiers.contains(.readAheadEasy) { return 1 }
    if modifiers.contains(.readAhead) { return 2 }
    if modifiers.contains(.readAheadHard) { return 3 }
    return nil
  }

  var effectiveQuoteLengths: Set<QuoteLength> {
    quoteLengths ?? QuoteLengthSelection.fromLegacy(quoteLength)
  }

  private enum CodingKeys: String, CodingKey {
    case mode, duration, wordLimit, difficulty, rules, language, englishVariant, quoteLength,
      quoteLengths, quoteSelectionMode, customTextCompletion, customTextSectionLimit,
      customTextOrdering, customTextPipeDelimiter, mixedLanguageComponents,
      modifiers, contentOptions, challengeID
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let decodedMode = try values.decode(TestMode.self, forKey: .mode)
    mode = decodedMode
    duration = try values.decodeIfPresent(TimeInterval.self, forKey: .duration)
    wordLimit = try values.decodeIfPresent(Int.self, forKey: .wordLimit)
    difficulty = try values.decode(Difficulty.self, forKey: .difficulty)
    rules = try values.decode(InputRules.self, forKey: .rules)
    language = try values.decodeIfPresent(TypingLanguage.self, forKey: .language) ?? .english
    englishVariant =
      try values.decodeIfPresent(EnglishVariant.self, forKey: .englishVariant) ?? .american
    let legacyQuoteLength = try values.decodeIfPresent(QuoteLength.self, forKey: .quoteLength) ?? .all
    quoteLengths = try values.decodeIfPresent(Set<QuoteLength>.self, forKey: .quoteLengths)
      .map(QuoteLengthSelection.normalized)
    quoteLength = quoteLengths.map(QuoteLengthSelection.legacyValue) ?? legacyQuoteLength
    quoteSelectionMode =
      try values.decodeIfPresent(QuoteSelectionMode.self, forKey: .quoteSelectionMode) ?? .lengths
    customTextCompletion =
      try values.decodeIfPresent(CustomTextCompletion.self, forKey: .customTextCompletion)
      ?? .finish
    customTextSectionLimit = try values.decodeIfPresent(Int.self, forKey: .customTextSectionLimit)
    customTextOrdering =
      try values.decodeIfPresent(CustomTextOrdering.self, forKey: .customTextOrdering) ?? .inOrder
    customTextPipeDelimiter = try values.decodeIfPresent(Bool.self, forKey: .customTextPipeDelimiter)
    mixedLanguageComponents = TypingLanguage.normalizedMixedComponents(
      try values.decodeIfPresent([TypingLanguage].self, forKey: .mixedLanguageComponents)
        ?? TypingLanguage.referenceDefaultMixedComponents)
    let normalizedModifiers = TestModifierPolicy.normalized(
      try values.decodeIfPresent([TestModifier].self, forKey: .modifiers) ?? [])
    let effectiveMode = MemoryFunboxModePolicy.effectiveMode(
      requested: decodedMode, modifiers: normalizedModifiers)
    if effectiveMode != decodedMode {
      mode = effectiveMode
      duration = nil
      wordLimit = wordLimit ?? MemoryFunboxModePolicy.fallbackWordLimit
    }
    let modeCompatibleModifiers = TestModifierPolicy.modifiersCompatibleWithMode(
      normalizedModifiers, mode: mode)
    modifiers = Self.usesInfiniteLimit(
      mode: mode, duration: duration, wordLimit: wordLimit,
      customTextCompletion: customTextCompletion, customTextSectionLimit: customTextSectionLimit)
      ? TestModifierPolicy.compatibleWithInfiniteTest(modeCompatibleModifiers) : modeCompatibleModifiers
    let decodedContentOptions =
      try values.decodeIfPresent(ContentOptions.self, forKey: .contentOptions) ?? .init()
    contentOptions = FunboxForcedContentOptionsPolicy.effectiveOptions(
      decodedContentOptions, modifiers: modifiers)
    challengeID = try values.decodeIfPresent(String.self, forKey: .challengeID)
  }

  private static func usesInfiniteLimit(
    mode: TestMode, duration: TimeInterval?, wordLimit: Int?,
    customTextCompletion: CustomTextCompletion, customTextSectionLimit: Int?
  ) -> Bool {
    switch mode {
    case .time: duration == 0
    case .words: wordLimit == 0
    case .custom:
      (customTextCompletion == .time && duration == 0)
        || (customTextCompletion == .words && wordLimit == 0)
        || (customTextCompletion == .sections && customTextSectionLimit == 0)
    case .quote, .zen: false
    }
  }
}

enum TestOutcome: String, Codable, Equatable {
  case active
  case completed
  case failed
  case invalidAFK
  case abandoned
  case bailedOut
}

/// The user-visible cause of a failed attempt: practice thresholds, unreliable
/// timer delivery, or an unusable candidate encountered during generation.
enum TestFailureReason: Hashable {
  case minimumWpm
  case minimumAccuracy
  case timerHealth
  case wordGeneration
}

/// Native equivalent of the reference test's one-second inactivity accounting.
/// It consumes only local event timestamps; the timer is deliberately not
/// paused, so timed tests keep their normal wall-clock deadline.
enum TestInactivityPolicy {
  static let trailingInactiveIntervals = 5

  static func intervalBoundaries(
    duration: TimeInterval, includesFractionalTail: Bool
  ) -> [TimeInterval] {
    let fullIntervals = Int(duration.rounded(.down))
    var boundaries = fullIntervals > 0 ? (1...fullIntervals).map(Double.init) : []
    // The reference classifies the tail after rounding seconds to hundredths,
    // including carry into a whole second. Event cutoffs still use raw time.
    if includesFractionalTail, retainsFractionalTail(duration: duration) { boundaries.append(duration) }
    return boundaries
  }

  static func retainsFractionalTail(duration: TimeInterval) -> Bool {
    let roundedHundredths = ((duration + Double.ulpOfOne) * 100).rounded()
    return roundedHundredths.truncatingRemainder(dividingBy: 100) >= 50
  }

  static func intervalCounts(
    activityDates: [Date], startedAt: Date, endedAt: Date, includesFractionalTail: Bool
  ) -> [Int] {
    let boundaries = intervalBoundaries(
      duration: max(0, endedAt.timeIntervalSince(startedAt)),
      includesFractionalTail: includesFractionalTail)
    var counts = Array(repeating: 0, count: boundaries.count)
    for date in activityDates {
      let offset = date.timeIntervalSince(startedAt)
      guard offset > -Double.leastNonzeroMagnitude else { continue }
      var lower = 0
      var upper = boundaries.count
      while lower < upper {
        let middle = lower + (upper - lower) / 2
        if boundaries[middle] < offset {
          lower = middle + 1
        } else {
          upper = middle
        }
      }
      if lower < counts.count { counts[lower] += 1 }
    }
    return counts
  }

  static func inactiveDuration(
    activityDates: [Date], startedAt: Date, endedAt: Date, includesFractionalTail: Bool
  ) -> TimeInterval {
    TimeInterval(
      intervalCounts(
        activityDates: activityDates, startedAt: startedAt, endedAt: endedAt,
        includesFractionalTail: includesFractionalTail
      ).filter { $0 == 0 }.count)
  }

  static func hasTrailingInactivity(
    insertionDates: [Date], startedAt: Date, endedAt: Date, includesFractionalTail: Bool
  ) -> Bool {
    let counts = intervalCounts(
      activityDates: insertionDates, startedAt: startedAt, endedAt: endedAt,
      includesFractionalTail: includesFractionalTail)
    return !counts.isEmpty && counts.suffix(trailingInactiveIntervals).allSatisfy { $0 == 0 }
  }
}

/// Keeps short tests from producing a misleading score after the local timer
/// has repeatedly missed its one-second grid. The thresholds mirror the
/// pinned reference's observable safety boundary, while the state remains
/// wholly local to the current native attempt.
enum TimerHealthPolicy {
  static let lowFrameRateDrift: TimeInterval = 0.125
  static let severeDrift: TimeInterval = 0.250
  static let fatalDrift: TimeInterval = 0.500
  static let allowedSevereDrifts = 5
  static let reducedFrameRate = 30

  static func monitors(_ configuration: TestConfiguration) -> Bool {
    switch configuration.mode {
    case .time:
      guard let duration = configuration.duration else { return false }
      return duration > 0 && duration < 130
    case .words:
      guard let wordLimit = configuration.wordLimit else { return false }
      return wordLimit > 0 && wordLimit < 250
    case .quote, .zen, .custom:
      return false
    }
  }
}

struct TimerHealthState: Equatable {
  private(set) var usesLowFrameRate = false
  private(set) var severeDriftCount = 0
  private(set) var shouldFail = false

  mutating func observe(drift: TimeInterval, configuration: TestConfiguration) {
    guard TimerHealthPolicy.monitors(configuration), !shouldFail else { return }
    guard drift.isFinite else {
      usesLowFrameRate = true
      shouldFail = true
      return
    }
    let lateness = max(0, drift)
    if lateness > TimerHealthPolicy.lowFrameRateDrift { usesLowFrameRate = true }
    if lateness > TimerHealthPolicy.severeDrift { severeDriftCount += 1 }
    if lateness > TimerHealthPolicy.fatalDrift
      || severeDriftCount > TimerHealthPolicy.allowedSevereDrifts
    {
      shouldFail = true
    }
  }
}

enum TypingPromptCharacterState: Equatable {
  case correct
  case incorrect
  case pending
  case current
  case hidden
  case extra
}

struct TypingPromptGlyph: Equatable {
  let character: Character
  let state: TypingPromptCharacterState
  /// The source character entered at this location, retained only for local
  /// presentation choices such as typo replacement and hints.
  let typedCharacter: Character?

  init(character: Character, state: TypingPromptCharacterState, typedCharacter: Character? = nil) {
    self.character = character
    self.state = state
    self.typedCharacter = typedCharacter
  }
}

enum TypingPromptPresentation {
  /// Zen mode does not compare input with a generated target. Render the
  /// locally entered text itself as correct and retain a trailing caret.
  static func zenGlyphs(typed: String, isFinished: Bool, blindMode: Bool) -> [TypingPromptGlyph] {
    var output = typed.map {
      TypingPromptGlyph(character: $0, state: .correct)
    }
    if !isFinished {
      output.append(.init(character: " ", state: .current))
    }
    return output
  }

  static func glyphs(
    target: String, typed: String, isFinished: Bool, blindMode: Bool,
    forcedErrorIndices: Set<Int> = [],
    blindCommittedMissingTargetIndices: Set<Int> = [],
    typedTargetIndices: [Int?]? = nil, currentTargetIndex: Int? = nil,
    hideExtraLetters: Bool = false,
    visibleFutureWords: Int? = nil, concealAll: Bool = false,
    concealedCurrentAndFutureWords: Int? = nil, concealPendingCharacters: Bool = false
  ) -> [TypingPromptGlyph] {
    let targetCharacters = Array(target)
    let typedCharacters = Array(typed)
    let effectiveTargetIndices = typedTargetIndices ?? typedCharacters.indices.map(Optional.some)
    let typedIndexByTarget = effectiveTargetIndices.enumerated().reduce(into: [Int: Int]()) {
      indices, element in
      guard let targetIndex = element.element, targetCharacters.indices.contains(targetIndex),
        indices[targetIndex] == nil
      else { return }
      indices[targetIndex] = element.offset
    }
    let activeTargetIndex = min(
      currentTargetIndex ?? min(typedCharacters.count, targetCharacters.count), targetCharacters.count)
    var output = targetCharacters.indices.map { index in
      let state: TypingPromptCharacterState
      if let typedIndex = typedIndexByTarget[index] {
        state =
          blindMode
          ? .correct
          : InputTextIdentity.matches(typedCharacters[typedIndex], targetCharacters[index]) && !forcedErrorIndices.contains(index)
            ? .correct : .incorrect
      } else if index < activeTargetIndex {
        state = blindCommittedMissingTargetIndices.contains(index) ? .correct : .pending
      } else if index == activeTargetIndex, !isFinished {
        state = .current
      } else {
        state = .pending
      }
      return TypingPromptGlyph(
        character: targetCharacters[index], state: state,
        typedCharacter: typedIndexByTarget[index].flatMap {
          !InputTextIdentity.matches(typedCharacters[$0], targetCharacters[index]) || forcedErrorIndices.contains(index)
            ? typedCharacters[$0] : nil
        })
    }

    if let visibleFutureWords, !isFinished {
      let currentWord = targetCharacters.prefix(activeTargetIndex)
        .filter(isPromptWordSeparator).count
      var word = 0
      for index in output.indices {
        if index > 0, isPromptWordSeparator(targetCharacters[index - 1]) { word += 1 }
        if index >= activeTargetIndex, word > currentWord + visibleFutureWords {
          output[index] = .init(
            character: targetCharacters[index], state: .hidden,
            typedCharacter: output[index].typedCharacter)
        }
      }
    }

    if concealAll {
      output = output.map {
        .init(character: $0.character, state: .hidden, typedCharacter: $0.typedCharacter)
      }
    }

    if concealPendingCharacters && !isFinished {
      output = output.enumerated().map { index, glyph in
        index >= activeTargetIndex
          ? .init(character: glyph.character, state: .hidden, typedCharacter: glyph.typedCharacter)
          : glyph
      }
    }

    if let concealedCurrentAndFutureWords, !isFinished {
      let currentWord = targetCharacters.prefix(activeTargetIndex)
        .filter(isPromptWordSeparator).count
      var word = 0
      for index in output.indices {
        if index > 0, isPromptWordSeparator(targetCharacters[index - 1]) { word += 1 }
        if (currentWord...(currentWord + concealedCurrentAndFutureWords - 1)).contains(word) {
          output[index] = .init(
            character: targetCharacters[index], state: .hidden,
            typedCharacter: output[index].typedCharacter)
        }
      }
    }

    let extraCharacters: [Character] = typedCharacters.enumerated().compactMap { index, character in
      guard index >= effectiveTargetIndices.count
        || effectiveTargetIndices[index] == nil
        || !(targetCharacters.indices.contains(effectiveTargetIndices[index] ?? -1))
      else { return nil }
      return character
    }
    guard !blindMode, !extraCharacters.isEmpty else { return output }
    output += extraCharacters.map {
      TypingPromptGlyph(
        character: $0, state: concealAll || hideExtraLetters ? .hidden : .extra)
    }
    return output
  }
}

enum TypedCharacterEffectPolicy {
  /// Dot replacement is a completed-word effect. Joining scripts follow the
  /// same rule: the entire submitted word is already stable before any of its
  /// glyphs are replaced, so native shaping is not interrupted mid-word.
  static func replacesCommittedCharacterWithDot(
    isCompleted: Bool, character: Character, effect: TypedCharacterEffect
  ) -> Bool {
    effect == .dots && isCompleted && !character.isWhitespace
  }

  /// Returns target-character positions belonging to words already submitted
  /// with a space or line break. Deliberately independent from correctness: this is an
  /// appearance preference, not an input rule.
  static func completedCharacterIndices(
    target: String, typed: String, typedTargetIndices: [Int?]? = nil, isFinished: Bool
  ) -> Set<Int> {
    let targetCharacters = Array(target)
    let typedCharacters = Array(typed)
    let effectiveTargetIndices = typedTargetIndices ?? typedCharacters.indices.map(Optional.some)
    var indices = Set<Int>()
    var wordStart = 0

    for index in targetCharacters.indices where isPromptWordSeparator(targetCharacters[index]) {
      guard let typedIndex = effectiveTargetIndices.firstIndex(where: { $0 == index }),
        typedCharacters.indices.contains(typedIndex),
        isPromptWordSeparator(typedCharacters[typedIndex])
      else { continue }
      indices.formUnion(wordStart..<index)
      wordStart = index + 1
    }
    if isFinished {
      indices.formUnion(wordStart..<targetCharacters.count)
    }
    return indices
  }
}

enum TypingAttentionWarning: Equatable {
  case inputUnfocused
  case windowUnfocused
  case capsLockEnabled

  var message: String {
    switch self {
    case .inputUnfocused: "输入框未聚焦，点击练习区继续"
    case .windowUnfocused: "窗口未聚焦，点击窗口继续"
    case .capsLockEnabled: "大写锁定已开启"
    }
  }

  var systemImage: String {
    switch self {
    case .inputUnfocused: "cursorarrow.click"
    case .windowUnfocused: "macwindow"
    case .capsLockEnabled: "capslock"
    }
  }
}

enum TypingAttentionPolicy {
  static func warnings(
    isInputFocused: Bool,
    isWindowFocused: Bool = true,
    focusWarningDelayElapsed: Bool = true,
    capsLockEnabled: Bool,
    language: TypingLanguage,
    isFinished: Bool,
    showFocusWarning: Bool,
    showCapsLockWarning: Bool
  ) -> [TypingAttentionWarning] {
    guard !isFinished else { return [] }
    var warnings: [TypingAttentionWarning] = []
    if showFocusWarning, focusWarningDelayElapsed {
      if !isWindowFocused {
        warnings.append(.windowUnfocused)
      } else if !isInputFocused {
        warnings.append(.inputUnfocused)
      }
    }
    if showCapsLockWarning, capsLockEnabled, language.supportsCapsLockWarning {
      warnings.append(.capsLockEnabled)
    }
    return warnings
  }
}

enum TypingRestartPolicy {
  static func isLocked(_ session: TypingSession) -> Bool {
    session.hasStarted && !session.isFinished && session.configuration.modifiers.contains(.noQuit)
  }
}

/// The reference refreshes an untouched time/word prompt after the page comes
/// back into focus, so a user cannot inspect it elsewhere before beginning.
/// A native window reports its initial key state too, therefore callers pass
/// only an actual return from a prior unfocused state.
enum TypingWindowRefocusRestartPolicy {
  static func shouldRememberWindowResignation(hasAttachedSheet: Bool) -> Bool {
    !hasAttachedSheet
  }

  static func shouldRestart(
    returnedFromUnfocusedWindow: Bool,
    hasStarted: Bool,
    isFinished: Bool,
    resultIsVisible: Bool,
    mode: TestMode
  ) -> Bool {
    returnedFromUnfocusedWindow
      && !hasStarted
      && !isFinished
      && !resultIsVisible
      && (mode == .time || mode == .words)
  }
}

/// NSViewRepresentable reports snapshots as well as key-window notifications.
/// Only a real key-to-nonkey transition can arm an untouched prompt refresh.
struct TypingWindowFocusTracker {
  private var hasBeenKey = false
  private var wasKey = false
  private var pendingExternalReturn = false

  mutating func record(isKey: Bool, hasAttachedSheet: Bool) -> Bool {
    if isKey {
      let returned = hasBeenKey && !wasKey && pendingExternalReturn
      hasBeenKey = true
      wasKey = true
      pendingExternalReturn = false
      return returned
    }

    if wasKey {
      pendingExternalReturn =
        TypingWindowRefocusRestartPolicy.shouldRememberWindowResignation(
          hasAttachedSheet: hasAttachedSheet)
    } else if hasAttachedSheet {
      pendingExternalReturn = false
    }
    wasKey = false
    return false
  }
}

/// The reference rejects a configuration change when it would restart an
/// in-progress no-quit test. Preferences that apply live stay outside this
/// gate.
enum NoQuitConfigurationChangePolicy {
  static func allowsRestartingChange(for session: TypingSession) -> Bool {
    !TypingRestartPolicy.isLocked(session)
  }
}

/// Shared settings must remain unchanged while any app window owns an active
/// no-quit test. The registry intentionally has no persistence: closing a
/// window releases its process-local test state.
struct NoQuitConfigurationLockRegistry: Equatable {
  private(set) var ownerIDs: Set<UUID> = []

  var allowsRestartingConfigurationChange: Bool {
    ownerIDs.isEmpty
  }

  mutating func setLock(_ isLocked: Bool, for ownerID: UUID) {
    if isLocked {
      ownerIDs.insert(ownerID)
    } else {
      ownerIDs.remove(ownerID)
    }
  }
}

/// Mirrors the reference thresholds that protect lengthy configured tests
/// and explicitly saved long texts from an accidental quick-restart keypress.
enum QuickRestartSafetyPolicy {
  static let longWordLimit = 1_000
  static let longDuration: TimeInterval = 900

  static func requiresShift(
    for configuration: TestConfiguration, savedLongText: Bool = false
  ) -> Bool {
    if configuration.mode == .custom, savedLongText { return true }
    switch configuration.mode {
    case .words:
      return configuration.wordLimit == 0 || (configuration.wordLimit ?? 0) >= longWordLimit
    case .time:
      return configuration.duration == 0 || (configuration.duration ?? 0) >= longDuration
    case .custom:
      switch configuration.customTextCompletion {
      case .time:
        return configuration.duration == 0 || (configuration.duration ?? 0) >= longDuration
      case .words:
        return configuration.wordLimit == 0 || (configuration.wordLimit ?? 0) >= longWordLimit
      case .sections:
        return configuration.customTextSectionLimit == 0
          || (configuration.customTextSectionLimit ?? 0) >= longWordLimit
      case .finish:
        return false
      }
    case .quote, .zen:
      return false
    }
  }
}

/// Matches the reference command palette's more conservative bailout entry.
/// It intentionally has higher thresholds than quick-restart protection.
enum CommandBailoutPolicy {
  static func isAvailable(for configuration: TestConfiguration, savedLongText: Bool = false) -> Bool {
    if savedLongText { return true }
    switch configuration.mode {
    case .zen:
      return true
    case .time:
      return configuration.duration == 0 || (configuration.duration ?? 0) >= 3_600
    case .words:
      return configuration.wordLimit == 0 || (configuration.wordLimit ?? 0) >= 5_000
    case .custom:
      switch configuration.customTextCompletion {
      case .time: return configuration.duration == 0 || (configuration.duration ?? 0) >= 3_600
      case .words: return configuration.wordLimit == 0 || (configuration.wordLimit ?? 0) >= 5_000
      case .sections:
        return configuration.customTextSectionLimit == 0
          || (configuration.customTextSectionLimit ?? 0) >= 5_000
      case .finish: return false
      }
    case .quote:
      return false
    }
  }
}

struct TypedWordReview: Equatable, Identifiable {
  let index: Int
  let target: String
  let typed: String
  let hasInputError: Bool
  var id: Int { index }
  var isCorrect: Bool { InputTextIdentity.matches(target, typed) && !hasInputError }

  init(index: Int, target: String, typed: String, hasInputError: Bool = false) {
    self.index = index
    self.target = target
    self.typed = typed
    self.hasInputError = hasInputError
  }
}

/// The number of incorrect input events attributed to one original target
/// word. This is session-only data used to weight a local follow-up exercise.
struct MissedWordErrorCount: Equatable {
  let word: String
  let count: Int
}

enum TypingReplayEventKind: String, Codable, Equatable, Sendable {
  case insert
  case delete
}

/// A recorded field after an input action, independent of when that action's
/// original timestamp sorts it into the saved tape.
struct TypingReplayInputField: Codable, Equatable, Sendable {
  let index: Int
  let value: String
  /// Archive 14. `value` is display-safe; these optional units retain lone
  /// surrogates which Swift String cannot represent. Never infer old units.
  let valueUTF16: [UInt16]?
  var validatedValueUTF16: [UInt16]? {
    guard let valueUTF16,
      Array(String(decoding: valueUTF16, as: UTF16.self).utf16) == Array(value.utf16)
    else { return nil }
    return valueUTF16
  }
  var units: [UInt16] { validatedValueUTF16 ?? Array(value.utf16) }

  init(index: Int, value: String, valueUTF16: [UInt16]? = nil) {
    self.index = index
    self.value = value
    self.valueUTF16 = valueUTF16
  }

  init(index: Int, units: [UInt16]) {
    self.init(index: index, value: String(decoding: units, as: UTF16.self), valueUTF16: units)
  }

  private enum CodingKeys: String, CodingKey { case index, value, valueUTF16 }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    index = try values.decode(Int.self, forKey: .index)
    guard index >= 0 else {
      throw DecodingError.dataCorruptedError(forKey: .index, in: values,
        debugDescription: "An input field index cannot be negative.")
    }
    value = try values.decode(String.self, forKey: .value)
    valueUTF16 = try values.decodeIfPresent([UInt16].self, forKey: .valueUTF16)
    guard valueUTF16 == nil || validatedValueUTF16 != nil else {
      throw DecodingError.dataCorruptedError(forKey: .valueUTF16, in: values,
        debugDescription: "Raw field units must project to the recorded display text.")
    }
  }
}

/// Archive 16. Insertion validation reads this position BEFORE updating the
/// field or navigating. A stopped attempt can leave a shorter field snapshot;
/// lastWord describes the catalog at the event, not the final grown catalog.
struct TypingReplayInputPosition: Codable, Equatable, Sendable {
  let charIndex: Int
  let lastWord: Bool

  init(charIndex: Int, lastWord: Bool) {
    self.charIndex = charIndex
    self.lastWord = lastWord
  }

  private enum CodingKeys: String, CodingKey { case charIndex, lastWord }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    charIndex = try values.decode(Int.self, forKey: .charIndex)
    lastWord = try values.decode(Bool.self, forKey: .lastWord)
    guard charIndex >= 0 else {
      throw DecodingError.dataCorruptedError(forKey: .charIndex, in: values,
        debugDescription: "A validation position cannot be negative.")
    }
  }
}

struct TypingReplayEvent: Codable, Equatable, Identifiable, Sendable {
  let offset: TimeInterval
  let kind: TypingReplayEventKind
  let text: String
  let forceError: Bool
  let automatic: Bool
  /// Missing in older archives; false preserves a separator in its input
  /// field when word-stop accepts the key but prevents navigation.
  let commitsWord: Bool?
  /// The first primitive of one whole-word deletion. Old readers still
  /// apply every primitive; only action-aware views collapse this span.
  let wordDeletionCount: Int?
  /// A character-delete input action can clear a whole destination field
  /// during code unindent. Keep its type separate from a word-delete action.
  let characterDeletionCount: Int?
  /// A judged attempt removed by letter-stop or opposite Shift. It counts
  /// as input activity but never contributes retained text or replay actions.
  /// Missing on legacy tapes: those cannot recover attempts never recorded.
  let inputStopped: Bool?
  /// Archive 12. Missing legacy snapshots cannot be inferred reliably after
  /// delayed input has reordered primitive insert/delete actions.
  let inputField: TypingReplayInputField?
  /// Archive 13: input-time judgments in UTF-16 order. A native grapheme can
  /// represent several source input actions, including mixed surrogate results.
  /// nil retains the prior archive's derivation; never backfill old judgments.
  let inputCorrectness: [Bool]?
  /// Archive 14. Insert payload in source units; a deletion's empty payload
  /// marks a unit primitive. String text is only its safe display projection.
  let textUTF16: [UInt16]?
  /// Captured only for known no-space unit fields so far. Absence on any
  /// legacy or unsupported path is not permission to infer a source position.
  let inputPosition: TypingReplayInputPosition?
  /// Archive 17: explicit unit contraction before this action, when finite
  /// terminal navigation cleared the element but retained its prior snapshot.
  /// Absence preserves the cumulative primitive contract of archives 1–16.
  let discardedInputUnits: Int?
  /// Archive 18: the regression destination abandoned its following word.
  /// Saved history consumes this; scoring still reads that word's raw bucket.
  let clearedNextWord: Bool?
  /// Archive 20: one source position on the FINAL primitive of a logical
  /// manual deletion. Within-field actions use their pre-delete length;
  /// regression and code destination actions use the resulting field length.
  /// This is not an insertion position and carries no fabricated lastWord.
  let deletionCharIndex: Int?
  var validatedDeletionCharIndex: Int? {
    guard kind == .delete, text.isEmpty, let inputField, inputField.index >= 0,
      let deletionCharIndex, deletionCharIndex >= 0 else { return nil }
    return deletionCharIndex
  }
  var validatedClearedNextWord: Bool {
    clearedNextWord == true && kind == .delete && validatedTextUTF16 != nil
      && inputField.map { $0.index >= 0 && $0.index < Int.max } == true
  }
  var validatedDiscardedInputUnits: Int? {
    guard let discardedInputUnits, discardedInputUnits > 0,
      validatedTextUTF16 != nil, let inputField, inputField.index >= 0 else { return nil }
    return discardedInputUnits
  }
  var validatedInputPosition: TypingReplayInputPosition? {
    guard kind == .insert, !inputUnits.isEmpty,
      let inputField, inputField.index >= 0,
      let inputPosition, inputPosition.charIndex >= 0 else { return nil }
    return inputPosition
  }
  var validatedTextUTF16: [UInt16]? {
    guard let textUTF16,
      kind == .insert ? !textUTF16.isEmpty : textUTF16.isEmpty,
      Array(String(decoding: textUTF16, as: UTF16.self).utf16) == Array(text.utf16)
    else { return nil }
    return textUTF16
  }
  var inputUnits: [UInt16] { validatedTextUTF16 ?? Array(text.utf16) }
  var hasRawUTF16Metadata: Bool { textUTF16 != nil || inputField?.valueUTF16 != nil }
  var deletesUTF16Unit: Bool {
    kind == .delete && (validatedTextUTF16 != nil || inputField?.validatedValueUTF16 != nil)
  }
  var validatedInputCorrectness: [Bool]? {
    guard kind == .insert, !text.isEmpty, let inputCorrectness,
      inputCorrectness.count == inputUnits.count else { return nil }
    return inputCorrectness
  }
  var isStoppedInsertion: Bool { kind == .insert && inputStopped == true }
  var id: String { "\(offset)-\(kind.rawValue)-\(text)" }

  init(
    offset: TimeInterval, kind: TypingReplayEventKind, text: String, forceError: Bool = false,
    automatic: Bool = false, commitsWord: Bool? = nil, wordDeletionCount: Int? = nil,
    characterDeletionCount: Int? = nil, inputStopped: Bool? = nil,
    inputField: TypingReplayInputField? = nil, inputCorrectness: [Bool]? = nil,
    textUTF16: [UInt16]? = nil, inputPosition: TypingReplayInputPosition? = nil,
    discardedInputUnits: Int? = nil, clearedNextWord: Bool? = nil,
    deletionCharIndex: Int? = nil
  ) {
    self.offset = offset
    self.kind = kind
    self.text = text
    self.forceError = forceError
    self.automatic = automatic
    self.commitsWord = commitsWord
    self.wordDeletionCount = wordDeletionCount
    self.characterDeletionCount = characterDeletionCount
    self.inputStopped = inputStopped
    self.inputField = inputField
    self.inputCorrectness = inputCorrectness
    self.textUTF16 = textUTF16
    self.inputPosition = inputPosition
    self.discardedInputUnits = discardedInputUnits
    self.clearedNextWord = clearedNextWord
    self.deletionCharIndex = deletionCharIndex
  }

  init(
    offset: TimeInterval, kind: TypingReplayEventKind, units: [UInt16], forceError: Bool = false,
    automatic: Bool = false, commitsWord: Bool? = nil, wordDeletionCount: Int? = nil,
    characterDeletionCount: Int? = nil, inputStopped: Bool? = nil,
    inputField: TypingReplayInputField? = nil, inputCorrectness: [Bool]? = nil,
    inputPosition: TypingReplayInputPosition? = nil, discardedInputUnits: Int? = nil,
    clearedNextWord: Bool? = nil, deletionCharIndex: Int? = nil
  ) {
    self.init(offset: offset, kind: kind, text: String(decoding: units, as: UTF16.self),
      forceError: forceError, automatic: automatic, commitsWord: commitsWord,
      wordDeletionCount: wordDeletionCount, characterDeletionCount: characterDeletionCount,
      inputStopped: inputStopped, inputField: inputField, inputCorrectness: inputCorrectness,
      textUTF16: units, inputPosition: inputPosition, discardedInputUnits: discardedInputUnits,
      clearedNextWord: clearedNextWord, deletionCharIndex: deletionCharIndex)
  }

  private enum CodingKeys: String, CodingKey {
    case offset, kind, text, forceError, automatic, commitsWord, wordDeletionCount, characterDeletionCount
    case inputStopped, inputField, inputCorrectness, textUTF16, inputPosition, discardedInputUnits
    case clearedNextWord, deletionCharIndex
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    offset = try values.decode(TimeInterval.self, forKey: .offset)
    kind = try values.decode(TypingReplayEventKind.self, forKey: .kind)
    text = try values.decode(String.self, forKey: .text)
    forceError = try values.decodeIfPresent(Bool.self, forKey: .forceError) ?? false
    automatic = try values.decodeIfPresent(Bool.self, forKey: .automatic) ?? false
    commitsWord = try values.decodeIfPresent(Bool.self, forKey: .commitsWord)
    wordDeletionCount = try values.decodeIfPresent(Int.self, forKey: .wordDeletionCount)
    characterDeletionCount = try values.decodeIfPresent(Int.self, forKey: .characterDeletionCount)
    inputStopped = try values.decodeIfPresent(Bool.self, forKey: .inputStopped)
    inputField = try values.decodeIfPresent(TypingReplayInputField.self, forKey: .inputField)
    textUTF16 = try values.decodeIfPresent([UInt16].self, forKey: .textUTF16)
    inputCorrectness = try values.decodeIfPresent([Bool].self, forKey: .inputCorrectness)
    inputPosition = try values.decodeIfPresent(TypingReplayInputPosition.self, forKey: .inputPosition)
    discardedInputUnits = try values.decodeIfPresent(Int.self, forKey: .discardedInputUnits)
    clearedNextWord = try values.decodeIfPresent(Bool.self, forKey: .clearedNextWord)
    deletionCharIndex = try values.decodeIfPresent(Int.self, forKey: .deletionCharIndex)
    guard textUTF16 == nil || validatedTextUTF16 != nil else {
      throw DecodingError.dataCorruptedError(forKey: .textUTF16, in: values,
        debugDescription: "Raw insert units must be nonempty and project to text; deletion payloads must be empty.")
    }
    guard inputCorrectness == nil || validatedInputCorrectness != nil else {
      throw DecodingError.dataCorruptedError(forKey: .inputCorrectness, in: values,
        debugDescription: "Input judgments require one Boolean per inserted UTF-16 unit.")
    }
    guard inputPosition == nil || validatedInputPosition != nil else {
      throw DecodingError.dataCorruptedError(forKey: .inputPosition, in: values,
        debugDescription: "A validation position requires a nonempty insertion and a recorded field.")
    }
    guard discardedInputUnits == nil || validatedDiscardedInputUnits != nil else {
      throw DecodingError.dataCorruptedError(forKey: .discardedInputUnits, in: values,
        debugDescription: "A contraction requires a positive unit count, raw action and recorded field.")
    }
    guard clearedNextWord == nil || validatedClearedNextWord else {
      throw DecodingError.dataCorruptedError(forKey: .clearedNextWord, in: values,
        debugDescription: "A next-word clear requires a true marker, raw deletion and bounded destination field.")
    }
    guard deletionCharIndex == nil || validatedDeletionCharIndex != nil else {
      throw DecodingError.dataCorruptedError(forKey: .deletionCharIndex, in: values,
        debugDescription: "A deletion position requires a nonnegative index, empty deletion payload and recorded field.")
    }
  }
}

enum TypingReplaySoundCue: Equatable {
  case click
  case error
}

struct TypingReplayTimedSoundCue: Equatable {
  let offset: TimeInterval
  let cue: TypingReplaySoundCue
}

enum TypingReplaySoundRoute: Equatable {
  case none
  case click
  case error

  static func resolve(
    cue: TypingReplaySoundCue, playsClicks: Bool, playsErrors: Bool
  ) -> Self {
    switch cue {
    case .click:
      playsClicks ? .click : .none
    case .error:
      playsErrors ? .error : (playsClicks ? .click : .none)
    }
  }
}

enum TypingReplay {
  struct Action {
    enum Kind: Equatable { case insert, deleteCharacter, deleteWord }
    let kind: Kind
    let primitiveRange: Range<Int>
    let primitives: ArraySlice<TypingReplayEvent>
  }

  /// Retain the legacy playback tape, while exposing real future deletion
  /// actions without inferring missing provenance from equal timestamps.
  static func actions(events: [TypingReplayEvent]) -> [Action] {
    let ordered = chronologicalEvents(events)
    var result: [Action] = []
    var index = 0
    while index < ordered.count {
      if ordered[index].isStoppedInsertion { index += 1; continue }
      let deletionRange = deletionActionRange(at: index, in: ordered)
      let range = deletionRange ?? index..<(index + 1)
      let kind: Action.Kind = ordered[index].kind == .insert ? .insert
        : deletionRange != nil && ordered[index].wordDeletionCount != nil ? .deleteWord : .deleteCharacter
      result.append(.init(kind: kind, primitiveRange: range, primitives: ordered[range]))
      index = range.upperBound
    }
    return result
  }

  private static func deletionActionRange(at index: Int, in events: [TypingReplayEvent]) -> Range<Int>? {
    let first = events[index]
    guard first.kind == .delete,
      first.wordDeletionCount == nil || first.characterDeletionCount == nil,
      let count = first.wordDeletionCount ?? first.characterDeletionCount,
      count > 0, count <= events.count - index, first.offset.isFinite
    else { return nil }
    let range = index..<(index + count)
    guard range.allSatisfy({ position in
      let event = events[position]
      return event.kind == .delete && event.text.isEmpty && event.offset == first.offset
        && event.automatic == first.automatic && !event.forceError && event.commitsWord == nil
        && (position == index || (event.wordDeletionCount == nil && event.characterDeletionCount == nil))
    }) else { return nil }
    return range
  }

  private static func deletionContinuationIndices(in events: [TypingReplayEvent]) -> Set<Int> {
    var result = Set<Int>()
    var index = 0
    while index < events.count {
      if let range = deletionActionRange(at: index, in: events) {
        result.formUnion(range.dropFirst())
        index = range.upperBound
      } else { index += 1 }
    }
    return result
  }

  private struct CharacterCoordinate: Hashable {
    let word: Int
    let position: Int
    let isSeparator: Bool
  }

  static func playbackElapsed(
    startedAt: TimeInterval, now: TimeInterval, duration: TimeInterval
  ) -> TimeInterval {
    min(max(0, now - startedAt), max(0, duration))
  }

  static func chronologicalEvents(_ events: [TypingReplayEvent]) -> [TypingReplayEvent] {
    guard !zip(events, events.dropFirst()).allSatisfy({ $0.offset <= $1.offset }) else {
      return events
    }
    return events.enumerated().sorted { lhs, rhs in
      lhs.element.offset == rhs.element.offset
        ? lhs.offset < rhs.offset : lhs.element.offset < rhs.element.offset
    }.map(\.element)
  }

  static func typedText(events: [TypingReplayEvent], through elapsed: TimeInterval) -> String {
    guard events.contains(where: \.hasRawUTF16Metadata) else {
      return legacyTypedText(events: events, through: elapsed)
    }
    return String(decoding: rawTypedUTF16(events: events, through: elapsed), as: UTF16.self)
  }

  /// Keep the original native String path for genuine legacy tapes: repeatedly
  /// decoding the entire unit buffer on each old backspace is quadratic.
  private static func legacyTypedText(events: [TypingReplayEvent], through elapsed: TimeInterval) -> String {
    chronologicalEvents(events).filter { $0.offset <= elapsed }.reduce(into: "") { typed, event in
      switch event.kind {
      case .insert: if !event.isStoppedInsertion { typed += event.text }
      case .delete:
        guard !typed.isEmpty else { return }
        typed.removeLast()
      }
    }
  }

  /// Decode only after reconstruction: separately recorded surrogate halves
  /// can rejoin. Old deletion primitives retain their whole-grapheme contract.
  static func typedUTF16(events: [TypingReplayEvent], through elapsed: TimeInterval) -> [UInt16] {
    guard events.contains(where: \.hasRawUTF16Metadata) else {
      return Array(legacyTypedText(events: events, through: elapsed).utf16)
    }
    return rawTypedUTF16(events: events, through: elapsed)
  }

  private static func rawTypedUTF16(events: [TypingReplayEvent], through elapsed: TimeInterval) -> [UInt16] {
    chronologicalEvents(events).filter { $0.offset <= elapsed }.reduce(into: []) { typed, event in
      if let discarded = event.validatedDiscardedInputUnits { typed.removeLast(min(discarded, typed.count)) }
      switch event.kind {
      case .insert: if !event.isStoppedInsertion { typed.append(contentsOf: event.inputUnits) }
      case .delete:
        guard !typed.isEmpty else { return }
        let count = event.deletesUTF16Unit ? 1
          : String(decoding: typed, as: UTF16.self).last.map { String($0).utf16.count } ?? 0
        typed.removeLast(min(count, typed.count))
      }
    }
  }

  static func inputGlyphs(
    prompt: String, events: [TypingReplayEvent], through elapsed: TimeInterval
  ) -> [TypingPromptGlyph] {
    let promptCharacters = Array(prompt)
    let promptCoordinates = promptCharacterIndices(prompt: prompt)
    var typed: [Character] = []
    var output: [TypingPromptGlyph] = []
    var typedWord = 0
    var typedPosition = 0
    var retainedSeparators = Set<Int>()
    for event in chronologicalEvents(events) {
      guard event.offset <= elapsed else { break }
      switch event.kind {
      case .insert:
        guard !event.isStoppedInsertion else { continue }
        for character in event.text {
          let coordinate = characterCoordinate(
            word: typedWord, position: typedPosition, character: character)
          let state: TypingPromptCharacterState
          if let promptIndex = promptCoordinates[coordinate] {
            state = InputTextIdentity.matches(promptCharacters[promptIndex], character) && !event.forceError
              ? .correct : .incorrect
          } else {
            state = .extra
          }
          if isPromptWordSeparator(character), event.commitsWord == false {
            retainedSeparators.insert(typed.count)
          }
          typed.append(character)
          output.append(.init(character: character, state: state))
          advanceCursor(for: character, word: &typedWord, position: &typedPosition,
            commitsWord: event.commitsWord)
        }
      case .delete:
        guard !typed.isEmpty else { continue }
        retainedSeparators.remove(typed.count - 1)
        typed.removeLast()
        output.removeLast()
        (typedWord, typedPosition) = cursorPosition(after: typed, retainedSeparators: retainedSeparators)
      }
    }
    return output
  }

  static func soundCues(
    prompt: String, events: [TypingReplayEvent], after lowerBound: TimeInterval,
    through upperBound: TimeInterval, configuration: TestConfiguration? = nil
  ) -> [TypingReplaySoundCue] {
    guard upperBound > lowerBound else { return [] }
    return soundCues(in: soundTimeline(prompt: prompt, events: events, configuration: configuration),
      after: lowerBound, through: upperBound)
  }

  /// The timeline is the ordered, finite snapshot returned by soundTimeline.
  static func soundCues(in timeline: [TypingReplayTimedSoundCue], after lowerBound: TimeInterval,
    through upperBound: TimeInterval) -> [TypingReplaySoundCue] {
    guard upperBound > lowerBound else { return [] }
    var lower = 0
    var upper = timeline.count
    while lower < upper {
      let middle = (lower + upper) / 2
      if timeline[middle].offset <= lowerBound { lower = middle + 1 }
      else { upper = middle }
    }
    var result: [TypingReplaySoundCue] = []
    while lower < timeline.count, timeline[lower].offset <= upperBound {
      result.append(timeline[lower].cue)
      lower += 1
    }
    return result
  }

  /// Prepared once for a result's immutable tape. Automatic input still
  /// produces playback actions; it is not a new live keyboard attempt.
  static func soundTimeline(prompt: String, events: [TypingReplayEvent],
    configuration: TestConfiguration? = nil) -> [TypingReplayTimedSoundCue] {
    let targetFields = promptFields(prompt)
    let isZen = configuration?.mode == .zen
    var typed: [Character] = []
    var typedWord = 0
    var typedPosition = 0
    var previousEventWord: Int?
    var cues: [TypingReplayTimedSoundCue] = []
    var retainedSeparators = Set<Int>()

    let orderedEvents = chronologicalEvents(events.filter { $0.offset.isFinite })
    if let recorded = recordedFieldActions(targetFields: targetFields,
      events: orderedEvents, configuration: configuration)
    { return recorded.map { .init(offset: $0.offset, cue: $0.soundCue) } }
    if orderedEvents.contains(where: { $0.validatedTextUTF16 != nil || $0.inputField?.validatedValueUTF16 != nil }) {
      return rawUnitSoundTimeline(targetFields: targetFields, events: orderedEvents, isZen: isZen)
    }
    let finalFields = SavedTextInputHistoryPolicy.inputFieldUTF16(events: orderedEvents)
    let continuationIndices = deletionContinuationIndices(in: orderedEvents)
    for (eventIndex, event) in orderedEvents.enumerated() {
      if event.kind == .insert, event.text.isEmpty || event.isStoppedInsertion {
        if event.isStoppedInsertion, let previous = previousEventWord, typedWord > previous {
          let correct = isZen || (targetFields.indices.contains(previous)
            && finalFields.indices.contains(previous)
            && finalFields[previous] == Array(String(targetFields[previous]).utf16))
          cues.append(.init(offset: event.offset, cue: correct ? .click : .error))
          previousEventWord = typedWord
        }
        continue
      }
      var eventWord = typedWord
      var cue: TypingReplaySoundCue?
      switch event.kind {
      case .insert:
        if let previous = previousEventWord, typedWord > previous {
          let correct = isZen || (targetFields.indices.contains(previous)
            && finalFields.indices.contains(previous)
            && finalFields[previous] == Array(String(targetFields[previous]).utf16))
          cues.append(.init(offset: event.offset, cue: correct ? .click : .error))
        }
        var eventContainsError = false
        for character in event.text {
          let characterIsIncorrect = !isZen && (event.forceError
            || !targetFields.indices.contains(typedWord)
            || !targetFields[typedWord].indices.contains(typedPosition)
            || !InputTextIdentity.matches(targetFields[typedWord][typedPosition], character))
          eventContainsError = eventContainsError || characterIsIncorrect
          if isPromptWordSeparator(character), event.commitsWord == false {
            retainedSeparators.insert(typed.count)
          }
          typed.append(character)
          advanceCursor(for: character, word: &typedWord, position: &typedPosition,
            commitsWord: event.commitsWord)
        }
        if !event.text.isEmpty {
          cue = eventContainsError ? .error : .click
        }
      case .delete:
        if !typed.isEmpty {
          retainedSeparators.remove(typed.count - 1)
          typed.removeLast()
          (typedWord, typedPosition) = cursorPosition(after: typed, retainedSeparators: retainedSeparators)
        }
        eventWord = typedWord
        cue = .click
      }

      if !continuationIndices.contains(eventIndex), let cue {
        if let judgments = event.validatedInputCorrectness {
          cues.append(contentsOf: judgments.map { .init(offset: event.offset, cue: $0 ? .click : .error) })
        } else {
          cues.append(.init(offset: event.offset, cue: cue))
        }
      }
      previousEventWord = eventWord
    }
    return cues
  }

  /// Flat/unknown target tapes have no hidden word catalog to reconstruct.
  /// Still compare raw units, never their lossy display replacements. Mixed
  /// old payloads keep one aggregate cue unless judgments were recorded.
  private static func rawUnitSoundTimeline(
    targetFields: [[Character]], events: [TypingReplayEvent], isZen: Bool
  ) -> [TypingReplayTimedSoundCue] {
    let targets = targetFields.map { Array(String($0).utf16) }
    let finalFields = SavedTextInputHistoryPolicy.inputFieldUTF16(events: events)
    let continuationIndices = deletionContinuationIndices(in: events)
    var typed: [UInt16] = []
    var retainedSeparators = Set<Int>()
    var word = 0
    var position = 0
    var previousEventWord: Int?
    var cues: [TypingReplayTimedSoundCue] = []
    func submitIfNeeded(at offset: TimeInterval) {
      guard let previousEventWord, word > previousEventWord else { return }
      let correct = isZen || (targets.indices.contains(previousEventWord)
        && finalFields.indices.contains(previousEventWord)
        && finalFields[previousEventWord] == targets[previousEventWord])
      cues.append(.init(offset: offset, cue: correct ? .click : .error))
    }
    for (index, event) in events.enumerated() {
      if event.isStoppedInsertion {
        submitIfNeeded(at: event.offset)
        previousEventWord = word
        continue
      }
      switch event.kind {
      case .insert:
        let units = event.inputUnits
        guard !units.isEmpty else { continue }
        submitIfNeeded(at: event.offset)
        let eventWord = word
        let judgments = event.validatedInputCorrectness
        let separateCues = event.validatedTextUTF16 != nil || judgments != nil
        var allCorrect = true
        for (index, unit) in units.enumerated() {
          let correct = judgments?[index] ?? (isZen || (!event.forceError
            && targets.indices.contains(word) && targets[word].indices.contains(position)
            && targets[word][position] == unit))
          allCorrect = allCorrect && correct
          if separateCues { cues.append(.init(offset: event.offset, cue: correct ? .click : .error)) }
          let separator = unit == 32 || unit == 10
          if separator && event.commitsWord == false { retainedSeparators.insert(typed.count) }
          typed.append(unit)
          if separator && event.commitsWord != false { word += 1; position = 0 }
          else { position += 1 }
        }
        if !separateCues { cues.append(.init(offset: event.offset, cue: allCorrect ? .click : .error)) }
        previousEventWord = eventWord
      case .delete:
        if !typed.isEmpty {
          let count = event.deletesUTF16Unit ? 1
            : String(decoding: typed, as: UTF16.self).last.map { String($0).utf16.count } ?? 0
          let start = max(0, typed.count - count)
          for index in start..<typed.count { retainedSeparators.remove(index) }
          typed.removeLast(typed.count - start)
          word = 0
          position = 0
          for (index, unit) in typed.enumerated() {
            if (unit == 32 || unit == 10) && !retainedSeparators.contains(index) { word += 1; position = 0 }
            else { position += 1 }
          }
        }
        if !continuationIndices.contains(index) { cues.append(.init(offset: event.offset, cue: .click)) }
        previousEventWord = word
      }
    }
    return cues
  }

  /// Input-time field position is not necessarily playback position when
  /// automatic actions keep an earlier timestamp. Legacy and unsegmented
  /// tapes retain their existing derivation rather than inventing targets.
  struct FieldAction {
    enum Kind: Equatable {
      case input(text: String, correct: Bool)
      case advance(correct: Bool)
      case retreat
      case resize(Int)
    }
    let offset: TimeInterval
    let kind: Kind
    var soundCue: TypingReplaySoundCue {
      switch kind {
      case .input(_, let correct), .advance(let correct): return correct ? .click : .error
      case .retreat, .resize: return .click
      }
    }
  }

  static func promptFields(_ prompt: String) -> [[Character]] {
    var fields: [[Character]] = []
    var field: [Character] = []
    for character in prompt {
      field.append(character)
      if isPromptWordSeparator(character) { fields.append(field); field = [] }
    }
    if !field.isEmpty { fields.append(field) }
    return fields
  }

  static func fieldActions(prompt: String, events: [TypingReplayEvent],
    configuration: TestConfiguration? = nil,
    targetWordDirectory: ResultTargetWordDirectory? = nil) -> [FieldAction]? {
    guard let targets = replayTargetFields(prompt: prompt, configuration: configuration,
      targetWordDirectory: targetWordDirectory) else { return nil }
    return recordedFieldActions(targetFields: targets.map { Array($0) },
      events: chronologicalEvents(events.filter { $0.offset.isFinite }), configuration: configuration,
      allowsNoSpace: targetWordDirectory != nil)
  }

  /// Captured source targets include empty slots and literal commits. A flat
  /// no-space prompt cannot recover their boundaries; never split or resample it.
  static func replayTargetFields(prompt: String, configuration: TestConfiguration?,
    targetWordDirectory: ResultTargetWordDirectory?) -> [String]? {
    let noSpace = TestModifierPolicy.usesNoSpaceInput(configuration?.modifiers ?? [])
    if let targetWordDirectory {
      guard targetWordDirectory.matches(prompt: prompt, noSpace: noSpace) else { return nil }
      return targetWordDirectory.words
    }
    guard !noSpace else { return nil }
    return promptFields(prompt).map { String($0) }
  }

  private static func recordedFieldActions(
    targetFields: [[Character]], events: [TypingReplayEvent], configuration: TestConfiguration?,
    allowsNoSpace: Bool = false
  ) -> [FieldAction]? {
    let isZen = configuration?.mode == .zen
    guard !events.isEmpty,
      allowsNoSpace || !TestModifierPolicy.usesNoSpaceInput(configuration?.modifiers ?? []),
      events.allSatisfy({ event in
        guard let field = event.inputField, field.index >= 0 else { return false }
        return isZen || targetFields.indices.contains(field.index)
      })
    else { return nil }

    let targets = targetFields.map { Array(String($0).utf16) }
    let finalFields = events.reduce(into: [Int: [UInt16]]()) { fields, event in
      if let field = event.inputField { fields[field.index] = field.units }
    }
    var previousField: Int?
    var actions: [FieldAction] = []
    var index = 0
    while index < events.count {
      let range = deletionActionRange(at: index, in: events) ?? index..<(index + 1)
      // Native word deletion has multiple primitives but one source action,
      // whose snapshot is its final destination, not its first removed unit.
      let event = events[range.upperBound - 1]
      index = range.upperBound
      guard let field = event.inputField else { continue }
      if event.kind == .insert && event.text.isEmpty && !event.isStoppedInsertion { continue }
      let wentBack = previousField.map { field.index < $0 } ?? false
      if let previousField, field.index != previousField {
        let correct = wentBack || isZen
          || finalFields[previousField] == targets[previousField]
        actions.append(.init(offset: event.offset, kind: wentBack ? .retreat : .advance(correct: correct)))
      }
      switch event.kind {
      case .insert:
        if !event.isStoppedInsertion {
          let units = event.inputUnits
          if let judgments = event.validatedInputCorrectness {
            for (index, unit) in units.enumerated() {
              // A lone surrogate is a separate source DOM node. Display it
              // as replacement text in Swift, without changing retained input.
              let text = String(decoding: [unit], as: UTF16.self)
              actions.append(.init(offset: event.offset, kind: .input(text: text, correct: judgments[index])))
            }
          } else {
            let end = field.units.count
            let start = end - units.count
            if event.validatedTextUTF16 != nil {
              for (offset, unit) in units.enumerated() {
                let position = start + offset
                let correct = isZen || (!event.forceError && targets[field.index].indices.contains(position)
                  && targets[field.index][position] == unit)
                actions.append(.init(offset: event.offset,
                  kind: .input(text: String(decoding: [unit], as: UTF16.self), correct: correct)))
              }
            } else {
              let correct = isZen || (!event.forceError && start >= 0 && end <= targets[field.index].count
                && units.enumerated().allSatisfy { offset, unit in targets[field.index][start + offset] == unit })
              actions.append(.init(offset: event.offset, kind: .input(text: event.text, correct: correct)))
            }
          }
        }
      case .delete:
        // Regression already emits the source back-word action. Do not add
        // a second same-time click for setting the destination field length.
        if !wentBack { actions.append(.init(offset: event.offset, kind: .resize(field.units.count))) }
      }
      previousField = field.index
    }
    return actions
  }

  static func characterSeekOffsets(
    prompt: String, events: [TypingReplayEvent]
  ) -> [Int: TimeInterval] {
    let promptCoordinates = promptCharacterIndices(prompt: prompt)

    var offsets: [Int: TimeInterval] = [:]
    var typed: [Character] = []
    var typedWord = 0
    var typedPosition = 0
    var retainedSeparators = Set<Int>()
    for event in chronologicalEvents(events) {
      switch event.kind {
      case .insert:
        guard !event.isStoppedInsertion else { continue }
        for character in event.text {
          let coordinate = characterCoordinate(
            word: typedWord, position: typedPosition, character: character)
          if let promptIndex = promptCoordinates[coordinate], offsets[promptIndex] == nil {
            offsets[promptIndex] = event.offset
          }
          if isPromptWordSeparator(character), event.commitsWord == false {
            retainedSeparators.insert(typed.count)
          }
          typed.append(character)
          advanceCursor(
            for: character, word: &typedWord, position: &typedPosition,
            commitsWord: event.commitsWord)
        }
      case .delete:
        guard !typed.isEmpty else { continue }
        retainedSeparators.remove(typed.count - 1)
        typed.removeLast()
        (typedWord, typedPosition) = cursorPosition(after: typed, retainedSeparators: retainedSeparators)
      }
    }
    return offsets
  }

  private static func promptCharacterIndices(prompt: String) -> [CharacterCoordinate: Int] {
    var indices: [CharacterCoordinate: Int] = [:]
    var word = 0
    var position = 0
    for (index, character) in prompt.enumerated() {
      indices[characterCoordinate(word: word, position: position, character: character)] = index
      advanceCursor(for: character, word: &word, position: &position)
    }
    return indices
  }

  private static func characterCoordinate(
    word: Int, position: Int, character: Character
  ) -> CharacterCoordinate {
    let isSeparator = isPromptWordSeparator(character)
    return CharacterCoordinate(
      word: word, position: isSeparator ? 0 : position, isSeparator: isSeparator)
  }

  private static func advanceCursor(
    for character: Character, word: inout Int, position: inout Int, commitsWord: Bool? = nil
  ) {
    if isPromptWordSeparator(character), commitsWord != false {
      word += 1
      position = 0
    } else {
      position += 1
    }
  }

  private static func cursorPosition(after characters: [Character],
    retainedSeparators: Set<Int>) -> (word: Int, position: Int) {
    var word = 0
    var position = 0
    for (index, character) in characters.enumerated() {
      advanceCursor(for: character, word: &word, position: &position,
        commitsWord: retainedSeparators.contains(index) ? false : nil)
    }
    return (word, position)
  }
}

/// Classifies the final accepted text without changing Typebar's scoring.
/// `missed` counts target positions skipped by an early word commit, so it is
/// intentionally separate from the accepted-character conservation total.
struct ResultCharacterStats: Codable, Equatable {
  let matched: Int
  let incorrect: Int
  let extra: Int
  let missed: Int
  /// Archive 19. Absent on genuine older results; never infer or backfill it.
  let sourceUnits: ResultUnitCharacterStats?
  /// Archive 22. Missing on older classifications means their original UTF-16 basis.
  let sourceUnitBasis: ResultScoringUnitBasis?

  init(matched: Int, incorrect: Int, extra: Int, missed: Int, sourceUnits: ResultUnitCharacterStats? = nil,
    sourceUnitBasis: ResultScoringUnitBasis? = nil) {
    self.matched = max(0, matched)
    self.incorrect = max(0, incorrect)
    self.extra = max(0, extra)
    self.missed = max(0, missed)
    self.sourceUnits = sourceUnits
    self.sourceUnitBasis = sourceUnitBasis
  }

  private enum CodingKeys: String, CodingKey { case matched, incorrect, extra, missed, sourceUnits, sourceUnitBasis }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    matched = try values.decode(Int.self, forKey: .matched)
    incorrect = try values.decode(Int.self, forKey: .incorrect)
    extra = try values.decode(Int.self, forKey: .extra)
    missed = try values.decode(Int.self, forKey: .missed)
    sourceUnits = try values.decodeIfPresent(ResultUnitCharacterStats.self, forKey: .sourceUnits)
    sourceUnitBasis = try values.decodeIfPresent(ResultScoringUnitBasis.self, forKey: .sourceUnitBasis)
    guard sourceUnitBasis == nil || sourceUnits != nil else {
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
        debugDescription: "A classification basis requires its saved unit counts."))
    }
  }

  static func legacy(typedCharacterCount: Int, correctCharacterCount: Int) -> Self {
    let typed = max(0, typedCharacterCount)
    let matched = min(typed, max(0, correctCharacterCount))
    return .init(matched: matched, incorrect: typed - matched, extra: 0, missed: 0)
  }
}

struct ResultKeyTimingStats: Equatable {
  let averageMilliseconds: Double
  let standardDeviationMilliseconds: Double
  let sampleCount: Int

  static func make(samples: [TimeInterval]) -> Self? {
    let milliseconds = samples.filter { $0.isFinite && $0 >= 0 }.map { $0 * 1_000 }
    guard !milliseconds.isEmpty else { return nil }
    let average = milliseconds.reduce(0, +) / Double(milliseconds.count)
    let variance = milliseconds.reduce(0) { total, value in
      total + pow(value - average, 2)
    } / Double(milliseconds.count)
    return .init(
      averageMilliseconds: average,
      standardDeviationMilliseconds: sqrt(variance),
      sampleCount: milliseconds.count)
  }
}

struct ChallengePresentationSnapshot: Codable, Equatable {
  let liveSpeedStyle: LiveMetricStyle
  let paceCaretStyle: TypingCaretStyle
  let tapeMode: PracticeTapeMode
  /// Optional so archived challenge results from before layout-segment scoring
  /// remain readable, but cannot claim unrecorded per-layout performance.
  let layoutFluidLayouts: [KeyboardLayout]?
  /// Nil on older archives; missing input provenance must never pass a virtual-only challenge.
  let virtualKeyboardOnly: Bool?
  /// Optional challenge-local display evidence; historical results cannot
  /// claim a font or hidden keymap that they never recorded.
  let fontFamily: String?
  let keyboardGuideMode: KeyboardGuideMode?
  let fontStayedAvailable: Bool?
  /// Optional evidence added with the one-handed challenge. Older results stay decodable.
  let oneHandedSelection: OneHandedChallengeSelection?
  let completedWords: Int?

  init(
    liveSpeedStyle: LiveMetricStyle, paceCaretStyle: TypingCaretStyle,
    tapeMode: PracticeTapeMode, layoutFluidLayouts: [KeyboardLayout]? = nil,
    virtualKeyboardOnly: Bool? = nil, fontFamily: String? = nil,
    keyboardGuideMode: KeyboardGuideMode? = nil,
    fontStayedAvailable: Bool? = nil,
    oneHandedSelection: OneHandedChallengeSelection? = nil,
    completedWords: Int? = nil
  ) {
    self.liveSpeedStyle = liveSpeedStyle
    self.paceCaretStyle = paceCaretStyle
    self.tapeMode = tapeMode
    self.layoutFluidLayouts = layoutFluidLayouts
    self.virtualKeyboardOnly = virtualKeyboardOnly
    self.fontFamily = fontFamily
    self.keyboardGuideMode = keyboardGuideMode
    self.fontStayedAvailable = fontStayedAvailable
    self.oneHandedSelection = oneHandedSelection
    self.completedWords = completedWords
  }
}

enum TypingInputOrigin {
  case physicalKeyboard
  case virtualKeyboard
}

struct CompletedTestResult: Codable, Equatable, Identifiable {
  let id: UUID
  let configuration: TestConfiguration
  let outcome: TestOutcome
  let startedAt: Date
  let finishedAt: Date
  let afkDuration: TimeInterval
  let typedCharacterCount: Int
  let correctCharacterCount: Int
  let errorCount: Int
  let wpm: Int
  let rawWpm: Int
  let accuracy: Int
  let preciseWpm: Double
  let preciseRawWpm: Double
  let preciseAccuracy: Double
  let inputMetrics: ResultInputMetrics?
  let restartCount: Int
  /// Effective native typing time accumulated before the terminal attempt.
  /// The result sheet keeps `engagedDuration` scoped to the terminal attempt;
  /// history and exports use `totalEngagedDuration` when they need the full run.
  let priorAttemptEngagedDuration: TimeInterval
  let characterStats: ResultCharacterStats
  let keyDurationSamples: [TimeInterval]
  let keySpacingSamples: [TimeInterval]
  let keyOverlapDuration: TimeInterval
  let tags: [String]
  let quoteSource: ResultQuoteSource?
  let prompt: String
  let replayEvents: [TypingReplayEvent]
  let targetWordDirectory: ResultTargetWordDirectory?
  let challengePresentation: ChallengePresentationSnapshot?

  init(
    id: UUID,
    configuration: TestConfiguration,
    outcome: TestOutcome,
    startedAt: Date,
    finishedAt: Date,
    afkDuration: TimeInterval = 0,
    typedCharacterCount: Int,
    correctCharacterCount: Int,
    errorCount: Int,
    wpm: Int,
    rawWpm: Int,
    accuracy: Int,
    preciseWpm: Double? = nil,
    preciseRawWpm: Double? = nil,
    preciseAccuracy: Double? = nil,
    inputMetrics: ResultInputMetrics? = nil,
    restartCount: Int = 0,
    priorAttemptEngagedDuration: TimeInterval = 0,
    characterStats: ResultCharacterStats? = nil,
    keyDurationSamples: [TimeInterval] = [],
    keySpacingSamples: [TimeInterval] = [],
    keyOverlapDuration: TimeInterval = 0,
    tags: [String] = [],
    quoteSource: ResultQuoteSource? = nil,
    prompt: String = "",
    replayEvents: [TypingReplayEvent] = [],
    targetWordDirectory: ResultTargetWordDirectory? = nil,
    challengePresentation: ChallengePresentationSnapshot? = nil
  ) {
    self.id = id
    self.configuration = configuration
    self.outcome = outcome
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.afkDuration = max(0, afkDuration)
    self.typedCharacterCount = typedCharacterCount
    self.correctCharacterCount = correctCharacterCount
    self.errorCount = errorCount
    self.wpm = wpm
    self.rawWpm = rawWpm
    self.accuracy = accuracy
    self.preciseWpm = Self.normalizedMetricPrecision(preciseWpm, fallback: wpm)
    self.preciseRawWpm = Self.normalizedMetricPrecision(preciseRawWpm, fallback: rawWpm)
    self.preciseAccuracy = Self.normalizedAccuracyPrecision(preciseAccuracy, fallback: accuracy)
    self.inputMetrics = inputMetrics
    self.restartCount = max(0, restartCount)
    self.priorAttemptEngagedDuration = Self.normalizedDuration(priorAttemptEngagedDuration)
    self.characterStats = characterStats ?? .legacy(
      typedCharacterCount: typedCharacterCount,
      correctCharacterCount: correctCharacterCount)
    self.keyDurationSamples = keyDurationSamples.filter { $0.isFinite && $0 >= 0 }
    self.keySpacingSamples = keySpacingSamples.filter { $0.isFinite && $0 >= 0 }
    self.keyOverlapDuration = keyOverlapDuration.isFinite ? max(0, keyOverlapDuration) : 0
    self.tags = tags
    self.quoteSource = configuration.mode == .quote ? quoteSource : nil
    self.prompt = prompt
    self.replayEvents = TypingReplay.chronologicalEvents(replayEvents)
    self.targetWordDirectory = targetWordDirectory
    self.challengePresentation = challengePresentation
  }

  var elapsedDuration: TimeInterval {
    max(0, finishedAt.timeIntervalSince(startedAt))
  }

  var engagedDuration: TimeInterval {
    max(0, elapsedDuration - afkDuration)
  }

  var totalEngagedDuration: TimeInterval {
    engagedDuration + priorAttemptEngagedDuration
  }

  var afkPercentage: Double {
    guard elapsedDuration > 0 else { return 0 }
    return afkDuration / elapsedDuration * 100
  }

  var keyDurationStats: ResultKeyTimingStats? {
    ResultKeyTimingStats.make(samples: keyDurationSamples)
  }

  var keySpacingStats: ResultKeyTimingStats? {
    ResultKeyTimingStats.make(samples: keySpacingSamples)
  }

  private enum CodingKeys: String, CodingKey {
    case id, configuration, outcome, startedAt, finishedAt, typedCharacterCount,
      afkDuration, correctCharacterCount, errorCount, wpm, rawWpm, accuracy, characterStats,
      preciseWpm, preciseRawWpm, preciseAccuracy, inputMetrics, restartCount, keyDurationSamples,
      priorAttemptEngagedDuration, keySpacingSamples, keyOverlapDuration, tags, prompt, quoteSource, replayEvents,
      challengePresentation, targetWordDirectory
    case startedAtReferenceTime, finishedAtReferenceTime
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(configuration, forKey: .configuration)
    try values.encode(outcome, forKey: .outcome)
    try CompatibleDatePrecision.encode(startedAt, into: &values,
      legacyKey: .startedAt, precisionKey: .startedAtReferenceTime)
    try CompatibleDatePrecision.encode(finishedAt, into: &values,
      legacyKey: .finishedAt, precisionKey: .finishedAtReferenceTime)
    try values.encode(afkDuration, forKey: .afkDuration)
    try values.encode(typedCharacterCount, forKey: .typedCharacterCount)
    try values.encode(correctCharacterCount, forKey: .correctCharacterCount)
    try values.encode(errorCount, forKey: .errorCount)
    try values.encode(wpm, forKey: .wpm)
    try values.encode(rawWpm, forKey: .rawWpm)
    try values.encode(accuracy, forKey: .accuracy)
    try values.encode(preciseWpm, forKey: .preciseWpm)
    try values.encode(preciseRawWpm, forKey: .preciseRawWpm)
    try values.encode(preciseAccuracy, forKey: .preciseAccuracy)
    try values.encodeIfPresent(inputMetrics, forKey: .inputMetrics)
    try values.encode(restartCount, forKey: .restartCount)
    try values.encode(priorAttemptEngagedDuration, forKey: .priorAttemptEngagedDuration)
    try values.encode(characterStats, forKey: .characterStats)
    try values.encode(keyDurationSamples, forKey: .keyDurationSamples)
    try values.encode(keySpacingSamples, forKey: .keySpacingSamples)
    try values.encode(keyOverlapDuration, forKey: .keyOverlapDuration)
    try values.encode(tags, forKey: .tags)
    try values.encodeIfPresent(quoteSource, forKey: .quoteSource)
    try values.encode(prompt, forKey: .prompt)
    try values.encode(replayEvents, forKey: .replayEvents)
    try values.encodeIfPresent(targetWordDirectory, forKey: .targetWordDirectory)
    try values.encodeIfPresent(challengePresentation, forKey: .challengePresentation)
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    configuration = try values.decode(TestConfiguration.self, forKey: .configuration)
    outcome = try values.decode(TestOutcome.self, forKey: .outcome)
    startedAt = try CompatibleDatePrecision.decode(from: values,
      legacyKey: .startedAt, precisionKey: .startedAtReferenceTime)
    finishedAt = try CompatibleDatePrecision.decode(from: values,
      legacyKey: .finishedAt, precisionKey: .finishedAtReferenceTime)
    afkDuration = max(0, try values.decodeIfPresent(TimeInterval.self, forKey: .afkDuration) ?? 0)
    typedCharacterCount = try values.decode(Int.self, forKey: .typedCharacterCount)
    correctCharacterCount = try values.decode(Int.self, forKey: .correctCharacterCount)
    errorCount = try values.decode(Int.self, forKey: .errorCount)
    wpm = try values.decode(Int.self, forKey: .wpm)
    rawWpm = try values.decode(Int.self, forKey: .rawWpm)
    accuracy = try values.decode(Int.self, forKey: .accuracy)
    preciseWpm = Self.normalizedMetricPrecision(
      try values.decodeIfPresent(Double.self, forKey: .preciseWpm), fallback: wpm)
    preciseRawWpm = Self.normalizedMetricPrecision(
      try values.decodeIfPresent(Double.self, forKey: .preciseRawWpm), fallback: rawWpm)
    preciseAccuracy = Self.normalizedAccuracyPrecision(
      try values.decodeIfPresent(Double.self, forKey: .preciseAccuracy), fallback: accuracy)
    inputMetrics = try values.decodeIfPresent(ResultInputMetrics.self, forKey: .inputMetrics)
    restartCount = max(0, try values.decodeIfPresent(Int.self, forKey: .restartCount) ?? 0)
    priorAttemptEngagedDuration = Self.normalizedDuration(
      try values.decodeIfPresent(TimeInterval.self, forKey: .priorAttemptEngagedDuration) ?? 0)
    characterStats = try values.decodeIfPresent(ResultCharacterStats.self, forKey: .characterStats)
      ?? .legacy(
        typedCharacterCount: typedCharacterCount,
        correctCharacterCount: correctCharacterCount)
    keyDurationSamples = try values.decodeIfPresent(
      [TimeInterval].self, forKey: .keyDurationSamples
    )?.filter { $0.isFinite && $0 >= 0 } ?? []
    keySpacingSamples = try values.decodeIfPresent(
      [TimeInterval].self, forKey: .keySpacingSamples
    )?.filter { $0.isFinite && $0 >= 0 } ?? []
    let decodedKeyOverlapDuration = try values.decodeIfPresent(
      TimeInterval.self, forKey: .keyOverlapDuration) ?? 0
    keyOverlapDuration = decodedKeyOverlapDuration.isFinite
      ? max(0, decodedKeyOverlapDuration) : 0
    tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
    quoteSource = configuration.mode == .quote
      ? (try? values.decodeIfPresent(ResultQuoteSource.self, forKey: .quoteSource)) ?? nil
      : nil
    prompt = try values.decodeIfPresent(String.self, forKey: .prompt) ?? ""
    replayEvents = TypingReplay.chronologicalEvents(
      try values.decodeIfPresent([TypingReplayEvent].self, forKey: .replayEvents) ?? [])
    targetWordDirectory = try values.decodeIfPresent(ResultTargetWordDirectory.self, forKey: .targetWordDirectory)
    if let targetWordDirectory, !targetWordDirectory.matches(prompt: prompt,
      noSpace: TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)) {
      throw DecodingError.dataCorruptedError(forKey: .targetWordDirectory, in: values,
        debugDescription: "Target words do not match the recorded prompt and separator mode")
    }
    challengePresentation = try values.decodeIfPresent(
      ChallengePresentationSnapshot.self, forKey: .challengePresentation)
  }

  private static func normalizedMetricPrecision(_ value: Double?, fallback: Int) -> Double {
    guard let value, value.isFinite, value >= 0 else { return Double(fallback) }
    return value
  }

  static func normalizedAccuracyPrecision(_ value: Double?, fallback: Int) -> Double {
    guard let value, value.isFinite else { return Double(fallback) }
    return value.clamped(to: 0...100)
  }

  private static func normalizedDuration(_ value: TimeInterval) -> TimeInterval {
    guard value.isFinite else { return 0 }
    return max(0, value)
  }
}

/// Funboxes with source-enforced character highlighting, along with native
/// concealment and separator modes that cannot safely expose word ranges.
enum PromptHighlightAvailabilityPolicy {
  static let characterOnlyModifiers: Set<TestModifier> = [
    .noSpaces, .underscoreSeparators, .listening, .simonSays, .memory,
    .readAheadEasy, .readAhead, .readAheadHard, .arrowStream, .morseStream,
  ]

  static func allowsWordRanges(
    languageUsesSpaceDelimitedWords: Bool, usesTapePractice: Bool,
    modifiers: [TestModifier]
  ) -> Bool {
    languageUsesSpaceDelimitedWords
      && !usesTapePractice
      && characterOnlyModifiers.isDisjoint(with: modifiers)
  }
}

/// Determines the prompt positions that receive a presentation-only emphasis.
/// It is deliberately independent from the accepted text, error accounting,
/// and word-completion rules.
enum PromptHighlightPolicy {
  static func highlightedIndices(
    in target: String,
    currentTargetIndex: Int?,
    mode: PromptHighlightMode,
    allowsWordRanges: Bool
  ) -> Set<Int> {
    let characters = Array(target)
    guard mode != .off,
      let currentTargetIndex,
      characters.indices.contains(currentTargetIndex)
    else { return [] }
    guard let futureWordCount = mode.futureWordCount, allowsWordRanges else {
      return [currentTargetIndex]
    }

    let currentWord = characters[..<currentTargetIndex].filter(isPromptWordSeparator).count
    let highlightedWords = currentWord...(currentWord + futureWordCount)
    var word = 0
    var indices = Set<Int>()
    for index in characters.indices {
      if !isPromptWordSeparator(characters[index]), highlightedWords.contains(word) {
        indices.insert(index)
      }
      if isPromptWordSeparator(characters[index]) { word += 1 }
    }
    return indices
  }
}

struct TypingSession {
  private(set) var configuration: TestConfiguration
  private(set) var generationNotice: String?
  private let initialGenerationNotice: String?
  private let initializationFailure: String?
  private(set) var prompt: String {
    didSet { refreshUnitTargets() }
  }
  private var unitTargets = UnitInputTargets("")
  /// Source initialization selects this once; input or later prompt growth
  /// cannot switch the scoring basis. It is not a language-menu preference.
  private let initialKoreanScoring: Bool
  private var promptSeparatorUnitCount = 0
  private var acceptedUnits: AcceptedUnitInput?
  private var currentInputUnit: UInt16?
  private var latestReplayInputUnits: [UInt16]?
  private var latestReplayInputPosition: TypingReplayInputPosition?
  private var latestNoSpaceAttempt: [UInt16]?
  private var latestNoSpaceAttemptFieldIndex: Int?
  private var latestNoSpaceFinishDecision = false
  private var latestReplayDiscardedUnits: Int?
  private var latestReplayClearedNextWord = false
  private var recordedFieldStats = RecordedInputFieldStats()
  private var promptCharacters: [Character]
  private var requiredWordStartIndex: Int?
  private var promptWordCount: Int
  private let initialPrompt: String
  private let repeatingPrompt: String?
  private var generatedWordContinuation: GeneratedWordContinuation?
  private let initialGeneratedWordContinuation: GeneratedWordContinuation?
  private var generatedStreamContinuation: GeneratedStreamContinuation?
  private let initialGeneratedStreamContinuation: GeneratedStreamContinuation?
  private var generatedCodeContinuation: GeneratedCodeContinuation?
  private let initialGeneratedCodeContinuation: GeneratedCodeContinuation?
  private var quoteWordStream: QuoteWordStream?
  private let randomCustomSourceTokens: [String]?
  private var randomCustomPreviousWords: [String]
  private let initialRandomCustomPreviousWords: [String]
  private var sequentialCustomWordStream: CustomSequentialWordStream?
  private let initialSequentialCustomWordStream: CustomSequentialWordStream?
  private var finiteCustomTextStream: CustomFiniteTextStream?
  private let initialFiniteCustomTextStream: CustomFiniteTextStream?
  private var sectionEndIndices: [Int]
  private let initialSectionEndIndices: [Int]
  private var noSpaceSectionWordEnds: [Int]
  private let initialNoSpaceSectionWordEnds: [Int]
  private var customSectionWordStream: CustomSectionWordStream?
  private let initialCustomSectionWordStream: CustomSectionWordStream?
  /// In no-space tests, the reference product still commits each source word
  /// when its final character is entered. Keep those boundaries separately:
  /// after the prompt has been flattened, spaces can no longer recover them.
  private var noSpaceWordEndIndices: [Int]
  private let initialNoSpaceWordEndIndices: [Int]
  /// Rendered word slices paired with the separate no-space boundaries. They
  /// let result history and local practice retain word-level behavior even
  /// though the prompt itself has no visible separator.
  private var noSpaceTargetWords: [String] {
    didSet {
      // Scan only newly appended targets, never the whole prompt per key.
      if firstEmptyNoSpaceWordIndex == nil, noSpaceTargetWords.count > oldValue.count {
        firstEmptyNoSpaceWordIndex = noSpaceTargetWords.indices.dropFirst(oldValue.count)
          .first { noSpaceTargetWords[$0].isEmpty }
      }
      refreshUnitTargets()
    }
  }
  private var firstEmptyNoSpaceWordIndex: Int?
  private let initialNoSpaceTargetWords: [String]
  private let repeatingNoSpaceWordLengths: [Int]
  private let repeatingNoSpaceTargetWords: [String]
  private(set) var typed = ""
  /// Most ASCII input keeps one grapheme per accepted key. A non-ASCII key or
  /// a CRLF join requires full-string indexing, even if later deleted.
  private var typedNeedsFullSegmentation = false
  /// Keep the grapheme length without resegmenting the entire growing input
  /// after every key in long Unicode custom-text sessions.
  private var typedGraphemeCount = 0
  private var cachedCommittedWordCount = 0
  private var canUseCachedWordProgress = true
  /// Each accepted input character keeps the target position it advanced to.
  /// A word can be submitted early with space, so this cannot always be
  /// inferred from the input string's character offset.
  private var typedTargetIndices: [Int?] = []
  private struct JoinedInputPart {
    let targetIndex: Int?
    let forced: Bool
    let extra: Bool
  }
  /// Only fused BMP input needs a part journal. ASCII long tests retain the
  /// existing compact metadata; one visible grapheme can have several inputs.
  private var joinedBMPInputParts: [Int: [JoinedInputPart]] = [:]
  private var recordsBMPUnits = false
  private var lastDeletionWasBMPUnit = false
  private var retainedWordSeparatorTypedIndices = Set<Int>()
  /// A blind word commit neutralizes its untouched letters. That display
  /// survives a later blind toggle, but is discarded when the word is reopened.
  /// It is not an input attempt, validation override, or persisted result field.
  private var blindCommittedMissingTargetIndices = Set<Int>()
  /// A border is created only by an ordinary erroneous commit. Blind mode
  /// masks an existing border, but cannot create one for a past blind word.
  private var committedErrorWordStarts = Set<Int>()
  /// Input offsets for extra letters retained in a completed source word.
  /// They have no target character, but remain scoring errors after that word
  /// is submitted and the active input buffer becomes empty.
  private var extraErrorTypedIndices = Set<Int>()
  private var typedCharacterDates: [Date] = []
  private var keyboardActivityDates: [Date] = []
  private var insertionActivityDates: [Date] = []
  /// Accuracy is an input-event metric. Unlike the rendered input, it keeps
  /// an incorrect attempt after the user deletes and corrects that character.
  private var inputAttemptCount = 0
  /// Feedback follows the final attempted UTF-16 unit in one text event,
  /// including attempts that stop/delete rules do not leave on screen.
  private(set) var lastInputWasCorrect: Bool?
  private var latestInputCorrectness: [Bool]?
  private var latestReplayInputText: String?
  private var liveInsertionFeedback: [Bool] = []
  /// A stopped letter can be drawn without entering the accepted input.
  /// Only a final input callback publishes this candidate; pre-input guards
  /// and earlier characters in a batch must not replace the visible snapshot.
  private struct StoppedPromptInput {
    let character: Character
    let targetIndex: Int?
  }
  private var stoppedPromptCandidate: StoppedPromptInput?
  private var stoppedPromptInput: StoppedPromptInput?
  let automaticInputAttemptID = UUID()
  private var queuedCodeInputDates: [Date] = []
  private var queuedCodeInputHead = 0
  private var applyingAutomaticCodeInput = false
  private var automaticInputExecutionDate: Date?
  /// Input/deletion/composition UI publishes hundredths, but a real-second
  /// timer update publishes the unrounded live cache. Neither alters scoring.
  private var roundsLiveAccuracyForInputDisplay = true
  private(set) var hasAcceptedVirtualKeyboardInput = false
  private var hasAcceptedPhysicalKeyboardInput = false
  private var hasPhysicalKeyboardActivityDuringAttempt = false
  var hasUsedOnlyVirtualKeyboard: Bool {
    hasAcceptedVirtualKeyboardInput && !hasAcceptedPhysicalKeyboardInput
      && !hasPhysicalKeyboardActivityDuringAttempt
  }
  mutating func recordPhysicalKeyboardActivityDuringAttempt() {
    if hasStarted && !isFinished { hasPhysicalKeyboardActivityDuringAttempt = true }
  }
  private var correctInputAttemptCount = 0
  private var forcedErrorIndices = Set<Int>()
  /// Target positions at which the user made an input error during this
  /// attempt. Unlike `forcedErrorIndices`, these remain after a backspace so
  /// local error practice can include words the user later corrected.
  private var attemptedErrorCounts = [Int: Int]()
  private var noSpaceUnitAttemptErrors = [Int: Int]()
  private var highestAttemptedNoSpaceField: Int?
  private var committedWordBursts: [Int] = []
  private var replayEvents: [TypingReplayEvent] = []
  private var replayCommittedSeparatorCount = 0
  /// Derived only when saving long-text progress, using recorded fields for
  /// new tapes and the unchanged primitive projection for legacy tapes.
  var savedTextProgressWordCount: Int {
    SavedTextInputHistoryPolicy.progressWordCount(
      displays: unitTargets.noSpace || hasNoSpaceWordSegmentation
        ? noSpaceTargetWords : SavedTextInputHistoryPolicy.displayWords(in: prompt),
      events: replayEvents,
      noSpaceWordEnds: hasNoSpaceWordSegmentation ? noSpaceWordEndIndices : [])
  }
  private var weakSpotInputSamples: [WeakSpotInputSample] = []
  private var weakSpotLastInputDate: Date?
  private var physicalKeyTiming = PhysicalKeyTiming()
  private(set) var startedAt: Date?
  private(set) var finishedAt: Date?
  private(set) var outcome: TestOutcome = .active
  private(set) var failureReason: TestFailureReason?

  init(
    configuration: TestConfiguration, prompt: String, repeatingPrompt: String? = nil,
    generatedWordContinuation: GeneratedWordContinuation? = nil,
    generatedStreamContinuation: GeneratedStreamContinuation? = nil,
    generatedCodeContinuation: GeneratedCodeContinuation? = nil,
    quoteWordStream: QuoteWordStream? = nil,
    sectionEndIndices: [Int] = [], noSpaceSectionWordEnds: [Int] = [],
    randomCustomSourceTokens: [String]? = nil,
    randomCustomPreviousWords: [String] = [],
    sequentialCustomWordStream: CustomSequentialWordStream? = nil,
    finiteCustomTextStream: CustomFiniteTextStream? = nil,
    customSectionWordStream: CustomSectionWordStream? = nil,
    noSpaceWordEndIndices: [Int] = [],
    noSpaceTargetWords: [String] = [], repeatingNoSpaceWordLengths: [Int] = [],
    repeatingNoSpaceTargetWords: [String] = [], generationNotice: String? = nil,
    initializationFailure: String? = nil
  ) {
    self.configuration = configuration
    self.generationNotice = initializationFailure ?? generationNotice
    self.initialGenerationNotice = initializationFailure ?? generationNotice
    self.initializationFailure = initializationFailure
    if initializationFailure != nil { self.outcome = .failed }
    self.prompt = prompt
    self.promptCharacters = Array(prompt)
    let initialTargets = UnitInputTargets(prompt)
    self.unitTargets = initialTargets
    self.initialKoreanScoring = configuration.mode != .zen && initialTargets.requiresKoreanDisassembly
    self.promptSeparatorUnitCount = prompt.utf8.reduce(into: 0) { count, unit in
      if unit == 32 || unit == 10 { count += 1 }
    }
    let wordProgress = Self.wordProgress(configuration.wordLimit, in: self.promptCharacters)
    self.requiredWordStartIndex = wordProgress.startIndex
    self.promptWordCount = wordProgress.count
    self.initialPrompt = prompt
    self.repeatingPrompt = repeatingPrompt
    self.generatedWordContinuation = generatedWordContinuation
    self.initialGeneratedWordContinuation = generatedWordContinuation
    self.generatedStreamContinuation = generatedStreamContinuation
    self.initialGeneratedStreamContinuation = generatedStreamContinuation
    self.generatedCodeContinuation = generatedCodeContinuation
    self.initialGeneratedCodeContinuation = generatedCodeContinuation
    self.quoteWordStream = quoteWordStream
    self.randomCustomSourceTokens = randomCustomSourceTokens
    self.randomCustomPreviousWords = randomCustomPreviousWords
    self.initialRandomCustomPreviousWords = randomCustomPreviousWords
    self.sequentialCustomWordStream = sequentialCustomWordStream
    self.initialSequentialCustomWordStream = sequentialCustomWordStream
    self.finiteCustomTextStream = finiteCustomTextStream
    self.initialFiniteCustomTextStream = finiteCustomTextStream
    self.sectionEndIndices = sectionEndIndices
    self.initialSectionEndIndices = sectionEndIndices
    self.noSpaceSectionWordEnds = noSpaceSectionWordEnds
    self.initialNoSpaceSectionWordEnds = noSpaceSectionWordEnds
    self.customSectionWordStream = customSectionWordStream
    self.initialCustomSectionWordStream = customSectionWordStream
    self.noSpaceWordEndIndices = noSpaceWordEndIndices
    self.initialNoSpaceWordEndIndices = noSpaceWordEndIndices
    self.noSpaceTargetWords = noSpaceTargetWords
    self.firstEmptyNoSpaceWordIndex = noSpaceTargetWords.firstIndex(of: "")
    self.initialNoSpaceTargetWords = noSpaceTargetWords
    self.repeatingNoSpaceWordLengths = repeatingNoSpaceWordLengths
    self.repeatingNoSpaceTargetWords = repeatingNoSpaceTargetWords
    refreshUnitTargets()
  }

  private mutating func refreshUnitTargets() {
    unitTargets = UnitInputTargets(prompt, buildsASCIICatalog: acceptedUnits != nil,
      noSpaceWords: TestModifierPolicy.usesNoSpaceInput(configuration.modifiers) ? noSpaceTargetWords : nil,
      asciiSeparatorCount: promptSeparatorUnitCount)
  }

  /// Restarts from the original source: owned quotes regenerate sampled targets,
  /// while other paths restore the initial snapshot (not a grown timed prompt).
  func repeatedAttempt(nextRandomCaseBit: () -> Bool = { Bool.random() }) -> TypingSession {
    if let quoteWordStream {
      var stream = quoteWordStream.reset()
      do {
        let batch = try stream.initialChunk(nextRandomCaseBit: nextRandomCaseBit)
        return .init(configuration: configuration, prompt: batch.text, quoteWordStream: stream,
          noSpaceWordEndIndices: NoSpaceWordBoundaryPolicy.endIndices(for: batch.noSpaceWordLengths),
          noSpaceTargetWords: batch.noSpaceTargetWords, generationNotice: initialGenerationNotice)
      } catch {
        return .init(configuration: configuration, prompt: "",
          initializationFailure: "引语包含空的 ASCII 空格词候选，无法生成练习。请选择另一条引语或切换拼写设置。")
      }
    }
    return TypingSession(
      configuration: configuration, prompt: initialPrompt, repeatingPrompt: repeatingPrompt,
      generatedWordContinuation: initialGeneratedWordContinuation,
      generatedStreamContinuation: initialGeneratedStreamContinuation,
      generatedCodeContinuation: initialGeneratedCodeContinuation,
      sectionEndIndices: initialSectionEndIndices,
      noSpaceSectionWordEnds: initialNoSpaceSectionWordEnds,
      randomCustomSourceTokens: randomCustomSourceTokens,
      randomCustomPreviousWords: initialRandomCustomPreviousWords,
      sequentialCustomWordStream: initialSequentialCustomWordStream,
      finiteCustomTextStream: initialFiniteCustomTextStream,
      customSectionWordStream: initialCustomSectionWordStream,
      noSpaceWordEndIndices: initialNoSpaceWordEndIndices,
      noSpaceTargetWords: initialNoSpaceTargetWords,
      repeatingNoSpaceWordLengths: repeatingNoSpaceWordLengths,
      repeatingNoSpaceTargetWords: repeatingNoSpaceTargetWords, generationNotice: initialGenerationNotice,
      initializationFailure: initializationFailure)
  }

  var isFinished: Bool { outcome != .active }
  var hasStarted: Bool { startedAt != nil }
  /// Code has the same word-commit input rules as ordinary generated words.
  var usesWordCommitInput: Bool {
    configuration.language.usesSpaceDelimitedWords || configuration.language.isCodeLanguage
  }
  /// A matching conversion may confirm the final word without an extra IME
  /// action. Probe the ordinary input path on a value copy, so all finite
  /// limits and difficulty rules remain owned by the engine, not AppKit.
  func shouldFinishWithComposition(
    _ text: String, forceError: Bool = false, at date: Date = .now
  ) -> Bool {
    guard !isFinished, !isAtEmptyNoSpaceWord, !text.isEmpty, !forceError, !configuration.isInfinite,
      configuration.mode != .time, configuration.mode != .zen,
      !(configuration.mode == .custom && configuration.customTextCompletion == .time)
    else { return false }

    if unitTargets.noSpace {
      let acceptedUnits = acceptedUnits ?? AcceptedUnitInput()
      let index = acceptedUnits.fieldIndex
      guard unitTargets.fields.indices.contains(index),
        acceptedUnits.field(index) + Array(text.utf16) == unitTargets.field(index),
        !acceptedUnits.entries[acceptedUnits.range(index)].contains(where: \.forced)
      else { return false }
      var projected = self
      projected.insertBatch(text, at: date)
      return projected.outcome == .completed || projected.outcome == .invalidAFK
    }

    let wordIndex: Int
    let currentInput: String
    if let range = activeNoSpaceWordRange,
      let index = noSpaceWordRanges.firstIndex(of: range)
    {
      wordIndex = index
      currentInput = String(Array(typed)[range.lowerBound...])
    } else {
      wordIndex = promptCharacters.prefix(nextTargetIndex).filter(isPromptWordSeparator).count
      currentInput = String(retainedInputWords(omittingEmptySubsequences: false).last ?? "")
    }
    guard let range = targetRange(forWord: wordIndex),
      !hasError(inWord: wordIndex, indices: forcedErrorIndices)
    else { return false }
    if let limit = configuration.wordLimit, limit > 0 {
      guard completedWordCount + 1 >= limit else { return false }
    } else {
      guard !usesIncrementalPromptExtension, range.upperBound == promptCharacters.count else {
        return false
      }
    }
    var target = String(promptCharacters[range])
    if target.last.map(isPromptWordSeparator) == true { target.removeLast() }
    guard InputTextIdentity.matches(currentInput + text, target) else { return false }
    var projected = self
    projected.insertBatch(text, at: date)
    return projected.outcome == .completed || projected.outcome == .invalidAFK
  }
  var usesIncrementalPromptExtension: Bool {
    generatedWordContinuation != nil || generatedStreamContinuation != nil
      || generatedCodeContinuation?.hasRemaining == true
      || repeatingPrompt?.isEmpty == false
      || randomCustomSourceTokens?.isEmpty == false
      || sequentialCustomWordStream != nil || finiteCustomTextStream?.hasRemaining == true
      || customSectionWordStream?.hasRemaining == true
      || quoteWordStream?.hasRemaining == true
  }
  var liveWeakSpotInputSamples: [WeakSpotInputSample] { weakSpotInputSamples }
  var typedCharacterCount: Int { typed.count }
  var afkDuration: TimeInterval {
    guard let startedAt, let finishedAt else { return 0 }
    return TestInactivityPolicy.inactiveDuration(
      activityDates: keyboardActivityDates, startedAt: startedAt, endedAt: finishedAt,
      includesFractionalTail: configuration.duration == nil)
  }

  /// Measures a still-active attempt without changing its terminal state.
  /// This lets a restart account for only engaged time while leaving the view's
  /// result observer untouched.
  func activeEngagedDuration(at date: Date = .now) -> TimeInterval {
    guard let startedAt, !isFinished else { return 0 }
    let endedAt = max(startedAt, date)
    let elapsed = max(0, endedAt.timeIntervalSince(startedAt))
    let inactive = TestInactivityPolicy.inactiveDuration(
      activityDates: keyboardActivityDates, startedAt: startedAt, endedAt: endedAt,
      includesFractionalTail: configuration.duration == nil)
    return max(0, elapsed - inactive)
  }

  mutating func recordKeyboardActivity(at date: Date = .now) {
    guard !isFinished, startedAt != nil else { return }
    keyboardActivityDates.append(date)
  }

  /// Records anonymous physical presses for the terminal timing snapshot.
  /// Auto-repeat does not begin a second press, and unmatched releases are ignored.
  mutating func recordPhysicalKeyEvent(
    keyCode: UInt16, isKeyDown: Bool, isRepeat: Bool, at date: Date = .now
  ) {
    guard !isFinished else { return }
    physicalKeyTiming.record(code: keyCode, down: isKeyDown, isRepeat: isRepeat, at: date)
  }

  var sectionProgress: (completed: Int, total: Int)? {
    guard configuration.customTextCompletion == .sections else { return nil }
    guard customSectionWordStream != nil || !sectionEndIndices.isEmpty else { return nil }
    if unitTargets.noSpace || hasNoSpaceWordSegmentation, !noSpaceSectionWordEnds.isEmpty {
      let committed = completedWordCount
      var lower = 0
      var upper = noSpaceSectionWordEnds.count
      while lower < upper {
        let middle = (lower + upper) / 2
        if noSpaceSectionWordEnds[middle] <= committed { lower = middle + 1 }
        else { upper = middle }
      }
      let total = customSectionWordStream?.sectionLimit ?? noSpaceSectionWordEnds.count
      return (total == 0 ? lower : min(lower, total), total)
    }
    let targetIndex = nextTargetIndex
    var lower = 0
    var upper = sectionEndIndices.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if sectionEndIndices[middle] <= targetIndex { lower = middle + 1 }
      else { upper = middle }
    }
    let awaitingFinalCommit = lower > 0 && sectionEndIndices[lower - 1] == promptCharacters.count
      && !isFinished && !lastInputCommitsWord
    let completed = lower - (awaitingFinalCommit ? 1 : 0)
    let total = customSectionWordStream?.sectionLimit ?? sectionEndIndices.count
    return (total == 0 ? completed : min(completed, total), total)
  }
  var nextExpectedCharacter: Character? {
    guard !isFinished, !isAtEmptyNoSpaceWord, nextTargetIndex < promptCharacters.count else { return nil }
    return promptCharacters[nextTargetIndex]
  }

  var promptGlyphs: [TypingPromptGlyph] {
    var glyphs = acceptedPromptGlyphs
    guard let stoppedPromptInput, !configuration.rules.blindMode else { return glyphs }
    if let index = stoppedPromptInput.targetIndex, glyphs.indices.contains(index) {
      let glyph = glyphs[index]
      glyphs[index] = .init(character: glyph.character,
        state: glyph.state == .hidden ? .hidden : .incorrect,
        typedCharacter: stoppedPromptInput.character)
    } else {
      let concealed = configuration.rules.hideExtraLetters
        || (configuration.modifiers.contains(.memory) && hasStarted && !isFinished)
      glyphs.append(.init(character: stoppedPromptInput.character,
        state: concealed ? .hidden : .extra))
    }
    return glyphs
  }

  /// Error color and cursor ownership are independent. A transient extra
  /// belongs before the source separator, with the caret at its leading edge.
  var promptCaretGlyphIndex: Int? {
    guard !isFinished else { return nil }
    let glyphs = acceptedPromptGlyphs
    if let stoppedPromptInput, stoppedPromptInput.targetIndex == nil,
      !configuration.rules.blindMode, !configuration.rules.hideExtraLetters
    { return glyphs.count }
    return glyphs.firstIndex { $0.state == .current }
  }

  private var acceptedPromptGlyphs: [TypingPromptGlyph] {
    if configuration.mode == .zen {
      return TypingPromptPresentation.zenGlyphs(
        typed: typed, isFinished: isFinished, blindMode: configuration.rules.blindMode)
    }
    let presentation = promptPresentationInput
    let glyphs = TypingPromptPresentation.glyphs(
      target: prompt,
      typed: typed,
      isFinished: isFinished,
      blindMode: configuration.rules.blindMode,
      forcedErrorIndices: presentation.forcedErrors,
      blindCommittedMissingTargetIndices: blindCommittedMissingTargetIndices,
      typedTargetIndices: presentation.targets,
      currentTargetIndex: nextTargetIndex,
      hideExtraLetters: configuration.rules.hideExtraLetters,
      visibleFutureWords: usesWordCommitInput
        ? configuration.visibleFutureWordCount : nil,
      concealAll: configuration.modifiers.contains(.memory) && hasStarted && !isFinished,
      concealedCurrentAndFutureWords: hasStarted ? configuration.readAheadConcealedWordCount : nil,
      concealPendingCharacters: configuration.modifiers.contains(.simonSays)
    )
    // The active empty field owns no visible target. Do not highlight the
    // first glyph of a later word as if it could be entered now.
    guard isAtEmptyNoSpaceWord else { return glyphs }
    return glyphs.map { glyph in
      glyph.state == .current
        ? .init(character: glyph.character, state: .pending, typedCharacter: glyph.typedCharacter) : glyph
    }
  }

  /// Rendering can match a correct retained newline to its glyph without
  /// changing the engine's navigation cursor. A later commit at that same
  /// target is extra input, not a retroactive error on the first correct LF.
  private var promptPresentationInput: (targets: [Int?], forcedErrors: Set<Int>, extraErrors: Set<Int>) {
    guard !retainedWordSeparatorTypedIndices.isEmpty else {
      return (typedTargetIndices, forcedErrorIndices, extraErrorTypedIndices)
    }
    var targets = typedTargetIndices
    var forcedErrors = forcedErrorIndices
    var extraErrors = extraErrorTypedIndices
    var retainedTargets = Set<Int>()
    var cursor = 0
    for (index, character) in typed.enumerated() where targets.indices.contains(index) {
      if let target = typedTargetIndices[index] {
        if retainedTargets.contains(target) {
          targets[index] = nil
          if forcedErrorIndices.contains(target) { extraErrors.insert(index) }
        }
        cursor = target + 1
      } else if character == "\n", retainedWordSeparatorTypedIndices.contains(index),
        !extraErrorTypedIndices.contains(index), promptCharacters.indices.contains(cursor),
        character == promptCharacters[cursor]
      {
        targets[index] = cursor
        retainedTargets.insert(cursor)
        forcedErrors.remove(cursor)
      }
    }
    return (targets, forcedErrors, extraErrors)
  }

  var promptGlyphsInDisplayOrder: [TypingPromptGlyph] {
    let glyphs = promptGlyphs
    return PromptGlyphLayout.indices(
      glyphs: glyphs, words: promptWordPresentations,
      hideExtraLetters: configuration.rules.hideExtraLetters).map { glyphs[$0] }
  }

  /// A linear snapshot of word ownership for presentation, including retained
  /// no-space boundaries and extra letters that have no target position.
  var promptWordPresentations: [TypingPromptWordPresentation] {
    let isZen = configuration.mode == .zen
    let characters = isZen ? Array(typed + " ") : promptCharacters
    let usesHiddenBoundaries = !isZen && hasNoSpaceWordSegmentation
    let ranges = usesHiddenBoundaries ? noSpaceWordRanges
      : TypingPromptWordPresentation.ranges(in: characters)
    let cursor = isZen ? typed.count : nextTargetIndex
    var wordByTarget = Array(repeating: -1, count: characters.count)
    for (word, range) in ranges.enumerated() {
      for index in range where characters.indices.contains(index) { wordByTarget[index] = word }
      if !usesHiddenBoundaries, characters.indices.contains(range.upperBound) {
        wordByTarget[range.upperBound] = word
      }
    }
    var inputErrors = Set<Int>()
    var extraGlyphIndices = Array(repeating: [Int](), count: ranges.count)
    if !isZen {
      let presentation = promptPresentationInput
      var owner = 0
      var targetCursor = 0
      var extraGlyphIndex = characters.count
      for (typedIndex, character) in typed.enumerated() {
        let targetIndex = presentation.targets.indices.contains(typedIndex)
          ? presentation.targets[typedIndex] : nil
        if let targetIndex, characters.indices.contains(targetIndex) {
          owner = wordByTarget[targetIndex]
          if character != characters[targetIndex] || presentation.forcedErrors.contains(targetIndex) {
            inputErrors.insert(owner)
          }
        } else {
          // Extra input belongs to the field awaiting the next target, not
          // necessarily the word owning the previous committed separator.
          if usesHiddenBoundaries, targetCursor == emptyNoSpaceWordBoundary,
            let firstEmptyNoSpaceWordIndex { owner = firstEmptyNoSpaceWordIndex }
          else if wordByTarget.indices.contains(targetCursor) { owner = wordByTarget[targetCursor] }
          if presentation.extraErrors.contains(typedIndex) { inputErrors.insert(owner) }
          if !configuration.rules.blindMode, extraGlyphIndices.indices.contains(owner) {
            extraGlyphIndices[owner].append(extraGlyphIndex)
            extraGlyphIndex += 1
          }
        }
        if typedTargetIndices.indices.contains(typedIndex), let actualTarget = typedTargetIndices[typedIndex] {
          targetCursor = actualTarget + 1
        }
      }
    }
    var words: [TypingPromptWordPresentation] = ranges.enumerated().map { word, range in
      let phase: TypingPromptWordPhase
      if usesHiddenBoundaries, firstEmptyNoSpaceWordIndex != nil {
        let committed = completedWordCount
        phase = word < committed ? .committed : word == committed ? .active : .future
      } else if usesHiddenBoundaries ? range.upperBound <= cursor : range.upperBound < cursor {
        phase = .committed
      } else if range.lowerBound <= cursor { phase = .active }
      else { phase = .future }
      return .init(range: range, phase: phase, hasInputError: inputErrors.contains(word),
        hasCommitError: committedErrorWordStarts.contains(range.lowerBound),
        extraGlyphIndices: extraGlyphIndices[word])
    }
    if let stoppedPromptInput, !configuration.rules.blindMode,
      let owner = words.firstIndex(where: { $0.phase == .active })
    {
      let word = words[owner]
      var extras = word.extraGlyphIndices
      if stoppedPromptInput.targetIndex == nil { extras.append(acceptedPromptGlyphs.count) }
      words[owner] = .init(range: word.range, phase: word.phase, hasInputError: true,
        hasCommitError: word.hasCommitError, extraGlyphIndices: extras)
    }
    return words
  }

  /// Runtime blind-mode changes have their own active-session boundary.
  mutating func setBlindMode(_ enabled: Bool) {
    guard !isFinished else { return }
    configuration.rules.blindMode = enabled
  }

  /// Visibility changes do not accept input or erase retained extra errors.
  /// Finished configurations stay immutable for their result and repeat.
  mutating func setHideExtraLetters(_ enabled: Bool) {
    guard !isFinished else { return }
    configuration.rules.hideExtraLetters = enabled
  }

  /// Synchronizes only settings whose reference metadata permits live changes.
  mutating func synchronizeLiveInputRules(_ rules: InputRules) {
    guard !isFinished else { return }
    var live = rules
    live.normalizeErrorHandlingModes()
    configuration.rules.freedomMode = live.confidenceMode == .off && live.freedomMode
    configuration.rules.confidenceMode = live.confidenceMode
    configuration.rules.oppositeShiftMode = live.oppositeShiftMode
    configuration.rules.deleteOnErrorMode = live.deleteOnErrorMode
    configuration.rules.deleteOnError = live.deleteOnErrorMode.isEnabled
    configuration.rules.quickEnd = live.quickEnd
    // These two live rules explicitly disable stopped input in the source.
    // Clear both persisted aliases; disabling them must not restore old rules.
    if live.confidenceMode != .off || live.deleteOnErrorMode.isEnabled {
      configuration.rules.stopOnErrorMode = .off
      configuration.rules.stopOnError = false
    }
    setBlindMode(live.blindMode)
    setHideExtraLetters(live.hideExtraLetters)
  }

  var completedPromptCharacterIndices: Set<Int> {
    TypedCharacterEffectPolicy.completedCharacterIndices(
      target: prompt, typed: typed, typedTargetIndices: typedTargetIndices, isFinished: isFinished)
  }

  var errors: Int {
    let typedCharacters = Array(typed)
    let targetCharacters = promptCharacters
    return typedCharacters.indices.reduce(into: 0) { total, typedIndex in
      guard typedTargetIndices.indices.contains(typedIndex) else { return }
      guard let targetIndex = typedTargetIndices[typedIndex], targetCharacters.indices.contains(targetIndex)
      else {
        if extraErrorTypedIndices.contains(typedIndex) { total += 1 }
        return
      }
      if !InputTextIdentity.matches(typedCharacters[typedIndex], targetCharacters[targetIndex])
        || forcedErrorIndices.contains(targetIndex)
      {
        total += 1
      }
    }
  }

  /// Result WPM follows word-completion scoring for ordinary space-delimited
  /// tests. A completed typo does not earn partial WPM credit, while a timed
  /// or bailed-out final word can retain its correctly typed prefix.
  private var scoredCorrectCharacters: Int {
    referenceWordCredit(countPartialLastWord: resultCreditsPartialLastWord).characters
  }

  private var resultCreditsPartialLastWord: Bool {
    ResultIntervalSamplingPolicy.isTimed(configuration) || outcome == .bailedOut
  }

  /// The pre-result display always credits a correct prefix of the active
  /// word, matching the live speed readout without changing final scoring.
  private func referenceWordCredit(countPartialLastWord: Bool) -> TypingWordCredit {
    if unitTargets.noSpace {
      return recordedFieldStats.counts(targets: unitTargets,
        creditsActivePrefix: countPartialLastWord, basis: sourceScoringBasis).credit
    }
    if hasKnownOrdinarySourceFields, isFinished || initialKoreanScoring {
      return recordedFieldStats.counts(targets: sourceStatsTargets,
        creditsActivePrefix: countPartialLastWord, basis: sourceScoringBasis).credit
    }
    if let acceptedUnits {
      if configuration.mode == .zen {
        return .init(characters: typedGraphemeCount, inputUnits: acceptedUnits.entries.count)
      }
      var credit = TypingWordCredit()
      for index in acceptedUnits.starts.indices {
        // A commit's identity belongs to the word: stripping SPACE and LF
        // before comparison would make the wrong separator earn full credit.
        let input = acceptedUnits.field(index)
        let target = unitTargets.field(index)
        let prefix = countPartialLastWord && index == acceptedUnits.fieldIndex
        if input == target || prefix && input.count <= target.count && target.starts(with: input) {
          credit.inputUnits += input.count
          credit.characters += String(decoding: input, as: UTF16.self).count
        }
      }
      return credit
    }
    if hasNoSpaceWordSegmentation {
      return noSpaceWordCredit(countPartialLastWord: countPartialLastWord)
    }
    guard configuration.mode != .zen,
      !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
    else {
      let errorUnits = typed.enumerated().reduce(into: 0) { total, entry in
        let (typedIndex, character) = entry
        guard typedTargetIndices.indices.contains(typedIndex) else { return }
        guard let targetIndex = typedTargetIndices[typedIndex], promptCharacters.indices.contains(targetIndex)
        else {
          if extraErrorTypedIndices.contains(typedIndex) { total += String(character).utf16.count }
          return
        }
        if !InputTextIdentity.matches(character, promptCharacters[targetIndex]) || forcedErrorIndices.contains(targetIndex) {
          total += String(character).utf16.count
        }
      }
      return .init(characters: max(0, typed.count - errors), inputUnits: max(0, typed.utf16.count - errorUnits))
    }
    return TypingWordCredit.words(target: prompt, input: typed, creditsActivePrefix: countPartialLastWord,
      retainedSeparatorIndices: retainedWordSeparatorTypedIndices)
  }

  /// No-space input visually flattens its prompt but still advances through
  /// source words one at a time. Result WPM therefore keeps the same complete
  /// word rule as ordinary input rather than treating an early typo as a
  /// globally correct character prefix.
  private func noSpaceWordCredit(countPartialLastWord: Bool) -> TypingWordCredit {
    let typedCharacters = Array(typed)
    let activeWordIndex = noSpaceWordRanges.lastIndex { typedCharacters.count > $0.lowerBound }
    return noSpaceWordRanges.enumerated().reduce(into: TypingWordCredit()) { total, entry in
      let (index, range) = entry
      if let firstEmptyNoSpaceWordIndex, index >= firstEmptyNoSpaceWordIndex { return }
      guard noSpaceTargetWords.indices.contains(index) else { return }
      let typedEnd = min(range.upperBound, typedCharacters.count)
      guard typedEnd > range.lowerBound else { return }
      let inputWord = String(typedCharacters[range.lowerBound..<typedEnd])
      let targetWord = noSpaceTargetWords[index]
      let credit = TypingWordCredit.word(target: targetWord, input: inputWord,
        creditsPrefix: countPartialLastWord && index == activeWordIndex)
      total.characters += credit.characters
      total.inputUnits += credit.inputUnits
    }
  }

  /// A native final-state classification derived from the accepted input's
  /// exact target mapping. It is descriptive only and never feeds scoring.
  var characterStats: ResultCharacterStats {
    if configuration.mode == .zen {
      // Zen's source context has no target words. Classify the logged fields
      // against their normalized input, not the displayed or final text.
      return .init(matched: typed.count, incorrect: 0, extra: 0, missed: 0,
        sourceUnits: recordedFieldStats.counts(targets: .init(""),
          creditsActivePrefix: false).unitStats)
    }

    let typedCharacters = Array(typed)
    let targetCharacters = promptCharacters
    var matched = 0
    var incorrect = 0
    var extra = 0
    var missed = 0
    var previousTargetIndex = -1

    for typedIndex in typedCharacters.indices {
      guard typedTargetIndices.indices.contains(typedIndex),
        let targetIndex = typedTargetIndices[typedIndex],
        targetCharacters.indices.contains(targetIndex)
      else {
        extra += 1
        continue
      }
      if targetIndex > previousTargetIndex + 1 {
        missed += targetIndex - previousTargetIndex - 1
      }
      previousTargetIndex = max(previousTargetIndex, targetIndex)
      if InputTextIdentity.matches(typedCharacters[typedIndex], targetCharacters[targetIndex])
        && !forcedErrorIndices.contains(targetIndex)
      {
        matched += 1
      } else {
        incorrect += 1
      }
    }
    return .init(matched: matched, incorrect: incorrect, extra: extra, missed: missed,
      sourceUnits: unitTargets.noSpace || hasKnownOrdinarySourceFields
        ? recordedFieldStats.counts(targets: sourceStatsTargets,
          creditsActivePrefix: finishedAt == nil || resultCreditsPartialLastWord,
          basis: sourceScoringBasis).unitStats : nil,
      sourceUnitBasis: usesKoreanSourceScoring ? .koreanJamo : nil)
  }

  private var hasKnownOrdinarySourceFields: Bool {
    hasOrdinarySourceFields
  }

  private var usesKoreanSourceScoring: Bool {
    initialKoreanScoring && (unitTargets.noSpace || hasKnownOrdinarySourceFields)
  }
  private var sourceScoringBasis: ResultScoringUnitBasis {
    usesKoreanSourceScoring ? .koreanJamo : .utf16
  }

  private var hasOrdinarySourceFields: Bool {
    configuration.mode != .zen && usesWordCommitInput && !prompt.isEmpty
      && !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
  }

  /// ASCII keeps its fast insertion path. Only result/stat readers need the
  /// complete unit catalog, not every keystroke or live speed update.
  private var sourceStatsTargets: UnitInputTargets {
    unitTargets.fields.isEmpty ? .init(prompt, buildsASCIICatalog: true) : unitTargets
  }

  var accuracy: Int {
    guard inputAttemptCount > 0 else { return isFinished ? 0 : 100 }
    return Int((liveAccuracy * 100).rounded())
  }

  var preciseAccuracy: Double {
    let percentage = inputAttemptCount == 0 && isFinished ? 0 : liveAccuracy * 100
    return isFinished ? ((percentage + Double.ulpOfOne) * 100).rounded() / 100 : percentage
  }

  var liveAccuracyForDisplay: Double {
    let percentage = liveAccuracy * 100
    return roundsLiveAccuracyForInputDisplay
      ? ((percentage + Double.ulpOfOne) * 100).rounded() / 100 : percentage
  }

  func wpm(at date: Date) -> Int {
    guard let startedAt else { return 0 }
    let end = finishedAt ?? date
    let credit = referenceWordCredit(countPartialLastWord: finishedAt == nil || resultCreditsPartialLastWord)
    return wpm(characters: credit.inputUnits, seconds: end.timeIntervalSince(startedAt))
  }

  func preciseWpm(at date: Date) -> Double {
    guard let startedAt else { return 0 }
    let end = finishedAt ?? date
    let credit = referenceWordCredit(countPartialLastWord: finishedAt == nil || resultCreditsPartialLastWord)
    return wpmValue(characters: credit.inputUnits, seconds: end.timeIntervalSince(startedAt))
  }

  func rawWpm(at date: Date) -> Int {
    guard let startedAt else { return 0 }
    let end = finishedAt ?? date
    return wpm(characters: rawSpeedInputUnitCount, seconds: end.timeIntervalSince(startedAt))
  }

  func preciseRawWpm(at date: Date) -> Double {
    guard let startedAt else { return 0 }
    let end = finishedAt ?? date
    return wpmValue(characters: rawSpeedInputUnitCount, seconds: end.timeIntervalSince(startedAt))
  }

  private var rawSpeedInputUnitCount: Int {
    unitTargets.noSpace || hasKnownOrdinarySourceFields && (isFinished || initialKoreanScoring)
      ? recordedFieldStats.counts(targets: sourceStatsTargets, creditsActivePrefix: false,
        basis: sourceScoringBasis).rawUnits
      : typed.utf16.count
  }

  /// Word burst is the WPM for the latest completed word, or the currently
  /// active word once it has at least two accepted characters. The submitting
  /// space counts as one UTF-16 unit; an active/no-space word has one virtual
  /// submit unit. Native character indices remain grapheme-based.
  var burstWpm: Int {
    if let acceptedUnits {
      return acceptedUnits.burst(acceptedUnits.fieldIndex) ?? committedWordBursts.last ?? 0
    }
    let characters = Array(typed)
    if tracksNoSpaceWordBursts {
      if noSpaceCommittedWordIndex != nil { return committedWordBursts.last ?? 0 }
      let start = isAtEmptyNoSpaceWord ? emptyNoSpaceWordBoundary ?? 0
        : noSpaceWordEndIndices.last(where: { $0 < characters.count }) ?? 0
      return activeWordBurst(start: start, in: characters) ?? committedWordBursts.last ?? 0
    }
    guard let lastSeparator = characters.lastIndex(where: isPromptWordSeparator) else {
      return activeWordBurst(start: 0, in: characters) ?? committedWordBursts.last ?? 0
    }
    let start = lastSeparator + 1
    guard start < characters.count else { return committedWordBursts.last ?? 0 }
    return activeWordBurst(start: start, in: characters) ?? committedWordBursts.last ?? 0
  }

  /// The most recent submitted-word speeds for the live practice strip.
  /// Values are local to the current session and include attempted words,
  /// so a user can see pace changes alongside their error count.
  var recentWordBursts: [Int] { Array(committedWordBursts.suffix(8)) }

  /// Per-attempt burst speeds for the result-page word history. A missing
  /// value means the attempt has no measurable interval (for example, text was
  /// inserted in a single event), so presentation can keep it neutral instead
  /// of inventing an extreme speed.
  var wordBurstHistory: [Int?] {
    if let acceptedUnits {
      return acceptedUnits.starts.indices.compactMap { index -> [Int?]? in
        acceptedUnits.range(index).isEmpty ? nil : [acceptedUnits.burst(index)]
      }.flatMap { $0 }
    }
    let characters = Array(typed)
    guard characters.count == typedCharacterDates.count else { return [] }
    if hasNoSpaceWordSegmentation {
      var bursts: [Int?] = []
      for range in noSpaceWordRanges where range.lowerBound < characters.count {
        let end = min(range.upperBound, characters.count) - 1
        bursts.append(wordBurst(
          from: range.lowerBound, through: end, in: characters, includesTrailingSpace: false))
      }
      return bursts
    }
    guard usesWordCommitInput,
      !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers), !typed.isEmpty
    else { return [] }
    var bursts: [Int?] = []
    var wordStart = 0
    for index in characters.indices where isPromptWordSeparator(characters[index])
      && !retainedWordSeparatorTypedIndices.contains(index) {
      bursts.append(wordBurst(
        from: wordStart, through: index, in: characters, includesTrailingSpace: true))
      wordStart = index + 1
    }
    if wordStart < characters.count {
      bursts.append(wordBurst(
        from: wordStart, through: characters.count - 1, in: characters, includesTrailingSpace: false))
    }
    return bursts
  }

  /// Distinct target words that received at least one incorrect input event.
  /// A correct but unfinished word is deliberately excluded: it was not an
  /// error, even if a timed test ended before its final characters were typed.
  /// Unreached prompt words are intentionally excluded so a timed test does
  /// not turn its remaining text into an error list.
  var missedWords: [String] {
    missedWordErrorCounts.map(\.word)
  }

  /// Error frequency for each distinct attempted target word, in first-target
  /// order. The count survives backspaces and repeated mistakes at the same
  /// position so local practice can use it as a weight.
  var missedWordErrorCounts: [MissedWordErrorCount] {
    if configuration.language.usesCJKWordStream,
      !prompt.contains(where: \.isWhitespace), !unitTargets.noSpace, !hasNoSpaceWordSegmentation
    {
      return missedNoSpaceWordErrorCounts
    }
    let targetWords = resultTargetWords
    guard !targetWords.isEmpty else { return [] }
    let errorCounts = missedWordErrorCountsByWord
    var result: [MissedWordErrorCount] = []
    for index in targetWords.indices where errorCounts.indices.contains(index) && errorCounts[index] > 0 {
      if let existing = result.firstIndex(where: { $0.word == targetWords[index] }) {
        result[existing] = .init(word: targetWords[index], count: result[existing].count + errorCounts[index])
      } else {
        result.append(.init(word: targetWords[index], count: errorCounts[index]))
      }
    }
    return result
  }

  /// Per-target-word event counts. It includes zeros for unattempted words so
  /// result review indices remain aligned, including when no-space metadata
  /// restores safe source-word boundaries.
  var missedWordErrorCountsByWord: [Int] {
    let targetWords = resultTargetWords
    guard !targetWords.isEmpty else { return [] }
    return attemptedInputErrorCountsByWord(targetWordCount: targetWords.count)
  }

  private var missedNoSpaceWordErrorCounts: [MissedWordErrorCount] {
    let targetCharacters = promptCharacters
    let tokens = (StarterLexicon.noSpaceWords(for: configuration.language) ?? []).map {
      (text: $0, characters: Array($0))
    }.sorted { $0.characters.count > $1.characters.count }
    var result: [MissedWordErrorCount] = []
    var index = 0

    while index < targetCharacters.count {
      guard let token = tokens.first(where: { token in
        let end = index + token.characters.count
        guard end <= targetCharacters.count else { return false }
        return targetCharacters[index..<end].elementsEqual(token.characters)
      }) else {
        index += 1
        continue
      }

      let end = index + token.characters.count
      let count = attemptedInputErrorCount(in: index..<end)
      if count > 0 {
        if let existing = result.firstIndex(where: { $0.word == token.text }) {
          result[existing] = .init(word: token.text, count: result[existing].count + count)
        } else {
          result.append(.init(word: token.text, count: count))
        }
      }
      index = end
    }
    return result
  }

  /// Per-word comparison for words actually attempted during a test with
  /// space delimiters, or with safely reconstructed no-space boundaries.
  var wordReviews: [TypedWordReview] {
    if unitTargets.noSpace, acceptedUnits != nil {
      let count = min(noSpaceTargetWords.count, (highestAttemptedNoSpaceField ?? -1) + 1)
      return (0..<count).map { index in
        let input = recordedFieldStats.history(index)
        let target = unitTargets.field(index)
        return .init(index: index, target: noSpaceTargetWords[index],
          typed: String(decoding: input, as: UTF16.self),
          hasInputError: input == target && noSpaceUnitAttemptErrors[index, default: 0] > 0)
      }
    }
    guard (!typed.isEmpty || !attemptedErrorCounts.isEmpty),
      (usesWordCommitInput || hasNoSpaceWordSegmentation)
    else { return [] }
    let targetWords = resultTargetWords
    guard !targetWords.isEmpty else { return [] }
    let attemptedErrors = attemptedInputErrorCountsByWord(targetWordCount: targetWords.count)
    if hasNoSpaceWordSegmentation {
      return noSpaceWordReviews(targetWords: targetWords, attemptedErrors: attemptedErrors)
    }
    let typedWords = retainedInputWords(omittingEmptySubsequences: false).map(String.init)
    let finalAttemptedCount = lastInputCommitsWord
      ? max(0, typedWords.count - 1) : typedWords.count
    let historicalAttemptedCount = attemptedErrors.indices.last(where: { attemptedErrors[$0] > 0 })
      .map { $0 + 1 } ?? 0
    let attemptedCount = max(finalAttemptedCount, historicalAttemptedCount)
    // Review targets omit source commit characters. A single retained LF in
    // the active blank field matches its source commit, not an extra letter.
    // A real second commit has already been removed by retainedInputWords;
    // its surviving LF must remain visible as an incorrect extra instead.
    let retainsBlankReviewCommit = !lastInputCommitsWord
      && nextTargetIndex < promptCharacters.count && promptCharacters[nextTargetIndex] == "\n"
    return (0..<min(attemptedCount, targetWords.count)).map {
      var typedWord = $0 < typedWords.count ? typedWords[$0] : ""
      if retainsBlankReviewCommit, $0 == typedWords.count - 1,
        targetWords[$0].isEmpty, typedWord == "\n"
      {
        typedWord = ""
      }
      return TypedWordReview(
        index: $0, target: targetWords[$0], typed: typedWord,
        hasInputError: InputTextIdentity.matches(typedWord, targetWords[$0])
          && attemptedErrors[$0] > 0)
    }
  }

  var hasPracticeNewlineContent: Bool {
    // Owned quotes retain the initial generation signal, not the contents of
    // the growing buffer. Other modes retain their existing dynamic behavior.
    if let quoteWordStream { return quoteWordStream.initialHasNewline }
    return unitTargets.hasNewline
  }

  var acceptsNewlineInput: Bool {
    configuration.mode == .zen || hasPracticeNewlineContent
  }

  var acceptsTabInput: Bool {
    if configuration.mode == .zen { return true }
    if let quoteWordStream { return quoteWordStream.initialHasTab }
    return prompt.contains("\t")
  }

  func remainingSeconds(at date: Date) -> Int? {
    guard configuration.duration != 0 else { return nil }
    guard let duration = configuration.duration, let startedAt else {
      return configuration.duration.map { Int($0) }
    }
    return max(0, Int(ceil(duration - date.timeIntervalSince(startedAt))))
  }

  /// Live counter text for limited tests. Timed tests retain a countdown;
  /// word tests show committed source words out of their configured target,
  /// including no-space prompts whose commits happen on a word's final
  /// character. This presentation does not derive any scoring state.
  func progressText(at date: Date = .now) -> String? {
    if let stream = quoteWordStream {
      return "\(min(quoteNavigationIndex, max(0, stream.totalWords - 1)))/\(stream.totalWords)"
    }
    if let sections = sectionProgress {
      return sections.total == 0 ? "\(sections.completed)" : "\(sections.completed)/\(sections.total)"
    }
    if configuration.duration == 0 {
      guard let startedAt else { return "0s" }
      return "\(max(0, Int(date.timeIntervalSince(startedAt).rounded(.down))))s"
    }
    if configuration.wordLimit == 0 { return "\(completedWordCount)" }
    if let remaining = remainingSeconds(at: date) { return "\(remaining)s" }
    guard let wordLimit = configuration.wordLimit,
      (usesWordCommitInput || tracksNoSpaceWordBursts)
    else { return nil }
    return "\(min(wordLimit, completedWordCount))/\(wordLimit)"
  }

  var progressLabel: String {
    if quoteWordStream != nil { return "进度" }
    if sectionProgress != nil { return "段数" }
    if configuration.duration == 0 { return "用时" }
    if configuration.wordLimit == 0 { return "词数" }
    return configuration.duration == nil && configuration.wordLimit != nil ? "进度" : "剩余"
  }

  func progressFraction(at date: Date = .now) -> Double? {
    if let stream = quoteWordStream {
      if outcome == .completed || outcome == .invalidAFK { return 1 }
      guard stream.totalWords > 0, hasStarted else { return 0 }
      return floor(Double(quoteNavigationIndex) / Double(stream.totalWords) * 100) / 100
    }
    if let sections = sectionProgress {
      return sections.total == 0 ? 0 : Double(sections.completed) / Double(sections.total)
    }
    if let duration = configuration.duration {
      if duration == 0 { return 1 }
      // The reference bar depicts time remaining, not elapsed time. Before a
      // test begins it is full; once started it targets the following one
      // second of the countdown so its linear animation continues shrinking.
      // This only informs the native bar and never affects timer or scoring.
      guard let startedAt else { return 1 }
      let elapsedSeconds = max(0, Int(date.timeIntervalSince(startedAt).rounded(.down)))
      return (1 - Double(elapsedSeconds + 1) / duration).clamped(to: 0...1)
    }
    guard let wordLimit = configuration.wordLimit,
      (usesWordCommitInput || tracksNoSpaceWordBursts)
    else { return nil }
    if wordLimit == 0 { return 0 }
    return Double(min(wordLimit, completedWordCount)) / Double(wordLimit)
  }

  var completedWordCount: Int {
    if let acceptedUnits {
      let committed = acceptedUnits.completedFieldCount
      if unitTargets.noSpace { return committed + (outcome == .completed && noSpaceTerminalFieldMatches ? 1 : 0) }
      if outcome == .completed, isAtFinalBlankTarget,
        retainedWordSeparatorTypedIndices.contains(typedGraphemeCount - 1)
      { return committed + 1 }
      if outcome == .completed, configuration.mode == .custom,
        configuration.customTextCompletion == .words, !acceptedUnits.lastCommits
      { return committed + 1 }
      return committed + (nextTargetIndex >= promptCharacters.count
        && unitTargets.units.last.map({ $0 != 32 && $0 != 10 }) == true ? 1 : 0)
    }
    if tracksNoSpaceWordBursts {
      let typedLength = typedGraphemeCount
      var lower = 0
      var upper = hasNoSpaceWordSegmentation
        ? firstEmptyNoSpaceWordIndex ?? noSpaceWordEndIndices.count : noSpaceWordEndIndices.count
      while lower < upper {
        let middle = lower + (upper - lower) / 2
        if noSpaceWordEndIndices[middle] <= typedLength {
          lower = middle + 1
        } else {
          upper = middle
        }
      }
      return lower
    }
    let targetCharacters = promptCharacters
    let committed = canUseCachedWordProgress
      ? cachedCommittedWordCount : scannedCommittedWordCount
    if outcome == .completed, isAtFinalBlankTarget,
      retainedWordSeparatorTypedIndices.contains(typedGraphemeCount - 1)
    {
      // Finishing a matching final blank is independent of navigation: its
      // retained LF completes one word without becoming a submitted separator.
      return committed + 1
    }
    if outcome == .completed, configuration.mode == .custom,
      configuration.customTextCompletion == .words,
      let lastTyped = typed.last, !isPromptWordSeparator(lastTyped)
    {
      // A finite custom test may end on its last required word while a
      // subsequent generated chunk remains visible but untyped.
      return committed + 1
    }
    guard nextTargetIndex >= targetCharacters.count,
      !targetCharacters.isEmpty,
      !isPromptWordSeparator(targetCharacters[targetCharacters.count - 1])
    else { return committed }
    return committed + 1
  }

  private var scannedCommittedWordCount: Int {
    let typedCharacters = Array(typed)
    var seenSeparatorTargets = Set<Int>()
    var committed = 0
    for (typedIndex, targetIndex) in typedTargetIndices.enumerated() {
      guard let targetIndex, promptCharacters.indices.contains(targetIndex),
        typedCharacters.indices.contains(typedIndex),
        isPromptWordSeparator(promptCharacters[targetIndex]),
        seenSeparatorTargets.insert(targetIndex).inserted
      else { continue }
      if isPromptWordSeparator(typedCharacters[typedIndex]) { committed += 1 }
    }
    return committed
  }

  func result(
    at date: Date = .now, tags: [String] = [], restartCount: Int = 0,
    priorAttemptEngagedDuration: TimeInterval = 0,
    quoteSource: ResultQuoteSource? = nil,
    challengePresentation: ChallengePresentationSnapshot? = nil
  ) -> CompletedTestResult? {
    guard let startedAt, let finishedAt else { return nil }
    let keyTiming = physicalKeyTiming.snapshot(startedAt: startedAt, finishedAt: finishedAt)
    let credit = referenceWordCredit(countPartialLastWord: resultCreditsPartialLastWord)
    let nativeCount = unitTargets.noSpace
      ? recordedFieldStats.counts(targets: unitTargets, creditsActivePrefix: false).rawCharacters : typed.count
    let retainedUnits = rawSpeedInputUnitCount
    // The v1 service assumes retained units cover the native character count.
    // Source terminal trimming violates that assumption without losing attempts.
    let needsVersionTwo = usesKoreanSourceScoring || retainedUnits < nativeCount
    let retainedInputUnits = usesKoreanSourceScoring
      ? recordedFieldStats.counts(targets: sourceStatsTargets, creditsActivePrefix: false,
        basis: sourceScoringBasis).retainedInputUnits : retainedUnits
    return .init(
      id: UUID(),
      configuration: configuration,
      outcome: outcome,
      startedAt: startedAt,
      finishedAt: finishedAt,
      afkDuration: afkDuration,
      typedCharacterCount: nativeCount,
      correctCharacterCount: scoredCorrectCharacters,
      errorCount: errors,
      wpm: wpm(at: date),
      rawWpm: rawWpm(at: date),
      accuracy: accuracy,
      preciseWpm: preciseWpm(at: date),
      preciseRawWpm: preciseRawWpm(at: date),
      preciseAccuracy: preciseAccuracy,
      inputMetrics: .init(version: needsVersionTwo ? 2 : 1, correctAttempts: correctInputAttemptCount,
        totalAttempts: inputAttemptCount, creditedUnits: credit.inputUnits, retainedUnits: retainedUnits,
        retainedInputUnits: needsVersionTwo ? retainedInputUnits : nil,
        scoringUnitBasis: needsVersionTwo ? sourceScoringBasis : nil),
      restartCount: restartCount,
      priorAttemptEngagedDuration: priorAttemptEngagedDuration,
      characterStats: characterStats,
      keyDurationSamples: keyTiming.durations,
      keySpacingSamples: keyTiming.spacings,
      keyOverlapDuration: keyTiming.overlap,
      tags: ResultTagPolicy.normalized(tags),
      quoteSource: quoteSource,
      prompt: prompt,
      replayEvents: replayEvents,
      targetWordDirectory: capturedTargetWordDirectory,
      challengePresentation: challengePresentation
    )
  }

  mutating func insert(_ text: String, forceError: Bool = false, at date: Date = .now) {
    liveInsertionFeedback.removeAll()
    insertText(
      text, forceError: forceError, at: date, evaluatesTerminalRulesOnLastCharacterOnly: false)
  }

  /// Handles a single platform text-insertion event such as a paste or a
  /// confirmed IME composition. The reference processes every character but
  /// delays difficulty and burst terminal checks until the event's final
  /// character.
  /// Returns transient UI feedback, including automatic tabs and recursive
  /// spelling replacements; it is deliberately separate from persisted replay.
  @discardableResult mutating func insertBatch(
    _ text: String, forceError: Bool = false, at date: Date = .now,
    origin: TypingInputOrigin = .physicalKeyboard, defersAutomaticInput: Bool = false
  ) -> [Bool] {
    liveInsertionFeedback.removeAll()
    insertText(
      text, forceError: forceError, at: date, evaluatesTerminalRulesOnLastCharacterOnly: true,
      origin: origin, defersAutomaticInput: true)
    if !defersAutomaticInput { drainAutomaticInput() }
    return liveInsertionFeedback
  }

  var hasPendingAutomaticInput: Bool { queuedCodeInputHead < queuedCodeInputDates.count }

  mutating func cancelAutomaticInput() {
    queuedCodeInputDates.removeAll()
    queuedCodeInputHead = 0
  }

  /// Executes one queued callback, with its original input timestamp but the
  /// current rules and field. A schedule-time match is not an execution guard.
  /// Live callers supply the execution clock for terminal results; nil keeps
  /// pure-engine simulations deterministic without changing replay timestamps.
  mutating func processNextAutomaticInput(for attemptID: UUID, executedAt: Date? = nil) -> [Bool] {
    guard attemptID == automaticInputAttemptID else { return [] }
    guard !isFinished else { cancelAutomaticInput(); return [] }
    guard hasPendingAutomaticInput else { return [] }
    let date = queuedCodeInputDates[queuedCodeInputHead]
    queuedCodeInputHead += 1
    if !hasPendingAutomaticInput { cancelAutomaticInput() }
    liveInsertionFeedback.removeAll()
    applyingAutomaticCodeInput = true
    automaticInputExecutionDate = executedAt
    defer {
      applyingAutomaticCodeInput = false
      automaticInputExecutionDate = nil
    }
    insertText("\t", forceError: false, at: date,
      evaluatesTerminalRulesOnLastCharacterOnly: true, defersAutomaticInput: true)
    return liveInsertionFeedback
  }

  private mutating func drainAutomaticInput() {
    var feedback = liveInsertionFeedback
    while hasPendingAutomaticInput {
      feedback += processNextAutomaticInput(for: automaticInputAttemptID)
    }
    liveInsertionFeedback = feedback
  }

  /// A marked-text composition starts the reference attempt before its text is
  /// committed. It intentionally leaves scoring and replay untouched until
  /// the text input system confirms the composition through `insertBatch`.
  mutating func beginComposition(at date: Date = .now) {
    guard !isFinished else { return }
    beginIfNeeded(at: date)
    recordKeyboardActivity(at: date)
    roundsLiveAccuracyForInputDisplay = true
  }

  /// An explicit highlight-mode redraw uses accepted input, not the last typo.
  mutating func refreshPromptPresentation() {
    stoppedPromptInput = nil
  }

  /// Candidate changes refresh display only: marked text never adds attempts.
  mutating func refreshLiveAccuracyAfterComposition(hadMarkedText: Bool, hasMarkedText: Bool) {
    guard !isFinished, hadMarkedText || hasMarkedText else { return }
    stoppedPromptInput = nil
    roundsLiveAccuracyForInputDisplay = true
  }

  private mutating func insertText(
    _ text: String, forceError: Bool, at date: Date,
    evaluatesTerminalRulesOnLastCharacterOnly: Bool,
    origin: TypingInputOrigin = .physicalKeyboard, defersAutomaticInput: Bool = false
  ) {
    lastInputWasCorrect = nil
    guard !isFinished, !text.isEmpty else { return }
    // ASCII fields already have one code unit per native primitive. On the
    // first Unicode field/input, retain real units rather than decoded glyphs.
    if supportsBMPUnitInput, acceptedUnits == nil,
      unitTargets.noSpace || text.utf16.contains(where: { $0 > 127 || $0 == 13 }) || unitTargets.requiresUnitInput
    { beginUnitInput() }
    let inputUnits = acceptedUnits == nil ? nil : Array(text.utf16)
    let characters: [Character] = inputUnits.map { units in
      units.map { Character(String(decoding: [$0], as: UTF16.self)) }
    } ?? Array(text)
    let attemptsBeforeEvent = inputAttemptCount
    for (index, character) in characters.enumerated() {
      guard !isFinished else { break }
      currentInputUnit = inputUnits?[index]
      defer { currentInputUnit = nil }
      if shouldExpandReferenceEllipsis(character, at: date) {
        // The web reference replaces a single ellipsis with three periods
        // only when the prompt expects periods. Treat that replacement as
        // its own multi-character insertion event so replay and terminal
        // rules match the transformed user input.
        insertText(
          "...", forceError: forceError, at: date,
          evaluatesTerminalRulesOnLastCharacterOnly: true, origin: origin,
          defersAutomaticInput: defersAutomaticInput)
        continue
      }
      if shouldExpandDutchLigature(character, at: date) {
        // The reference expands the Dutch IJ ligature through its ordinary
        // multi-character input path, but preserves a literal ligature target.
        insertText(
          "ij", forceError: forceError, at: date,
          evaluatesTerminalRulesOnLastCharacterOnly: true, origin: origin,
          defersAutomaticInput: defersAutomaticInput)
        continue
      }
      let evaluatesTerminalRules = !evaluatesTerminalRulesOnLastCharacterOnly
        || index == characters.indices.last
      let quoteWordBefore = quoteWordStream == nil ? 0 : quoteNavigationIndex
      let attemptsBeforeCharacter = inputAttemptCount
      stoppedPromptCandidate = nil
      let accepted = insertCharacter(
        character, forceError: forceError, at: date,
        evaluatesTerminalRules: evaluatesTerminalRules)
      // A batch reports its final attempted character, even when an error
      // guard removes it. Recursive spelling replacements have their own
      // final callback; pre-insertion rejection has no UI feedback.
      if evaluatesTerminalRules, inputAttemptCount > attemptsBeforeCharacter,
        let correct = lastInputWasCorrect
      {
        stoppedPromptInput = stoppedPromptCandidate
        liveInsertionFeedback.append(correct)
      }
      if accepted {
        if !applyingAutomaticCodeInput {
          switch origin {
          case .physicalKeyboard: hasAcceptedPhysicalKeyboardInput = true
          case .virtualKeyboard: hasAcceptedVirtualKeyboardInput = true
          }
        }
        // The source logs normalized data, not the pre-normalization key.
        recordReplayEvent(kind: .insert, text: latestReplayInputText ?? String(character), forceError: forceError, at: date)
        insertCodeIndentationIfNeeded(at: date)
        if !defersAutomaticInput, !applyingAutomaticCodeInput { drainAutomaticInput() }
        if quoteWordStream != nil, quoteNavigationIndex > quoteWordBefore {
          refillQuoteIfNeeded(activeWordBefore: quoteWordBefore, at: date)
        }
      }
    }
    // Browser input guards reject a leading separator, unsupported Return,
    // and no-space whitespace before the reference test starts. Once an
    // attempt exists, rejected keys still count as local activity, but an
    // entirely rejected first event must not begin the timer.
    if startedAt != nil {
      keyboardActivityDates.append(date)
      // A key rejected by the pre-insertion guard is still local keyboard
      // activity, but it has no insertText event for the trailing AFK check.
      if inputAttemptCount > attemptsBeforeEvent { insertionActivityDates.append(date) }
    }
    if inputAttemptCount > attemptsBeforeEvent { roundsLiveAccuracyForInputDisplay = true }
    if usesIncrementalPromptExtension,
      (!usesWordCommitInput
        || TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)),
      nextTargetIndex >= promptCharacters.count, !reachedConfiguredWordLimit
    {
      // No-space input has no separator key to trigger the next chunk. Make
      // the upcoming target visible immediately after its final character.
      extendPromptIfNeeded(at: date)
    }
    if finiteCustomTextStream?.hasRemaining == true,
      nextTargetIndex >= promptCharacters.count
    {
      extendPromptIfNeeded(at: date)
    }
    if !isFinished, customSectionWordStream?.hasRemaining == true,
      nextTargetIndex >= promptCharacters.count
    {
      // A candidate batch already carries its last commit. Do not require
      // an extra, blind keypress before exposing the next generated target.
      extendPromptIfNeeded(at: date)
    }
    finishIfNeeded(at: date)
  }

  mutating func deleteBackward(at date: Date = .now) {
    guard !isFinished else { return }
    recordKeyboardActivity(at: date)
    guard !typed.isEmpty else { return }
    guard canDeleteBackward else { return }
    stoppedPromptInput = nil
    roundsLiveAccuracyForInputDisplay = true
    if configuration.rules.codeUnindentOnBackspace, configuration.language.isCodeLanguage,
      removeCodeIndentationBeforeField(at: date)
    {
      return
    }
    let deletionStart = replayEvents.count
    let previousField = replayInputField(kind: .delete, inputStopped: false)
    removeLastTypedCharacter()
    recordReplayEvent(kind: .delete, text: "", at: date)
    recordDeletionPosition(since: deletionStart, previousField: previousField)
  }

  /// Handles the platform's word-backward command (for example Option-Delete)
  /// without bypassing the same confidence and committed-word protections as
  /// ordinary backspace. Each removed character stays visible to replay.
  mutating func deleteWordBackward(at date: Date = .now) {
    guard !isFinished else { return }
    recordKeyboardActivity(at: date)
    guard !typed.isEmpty else { return }
    guard canDeleteBackward else { return }
    stoppedPromptInput = nil
    roundsLiveAccuracyForInputDisplay = true
    if configuration.rules.codeUnindentOnBackspace, configuration.language.isCodeLanguage,
      removeCodeIndentationBeforeField(at: date, deletesWholeIndent: true)
    {
      return
    }

    let deletionStart = replayEvents.count
    let previousField = replayInputField(kind: .delete, inputStopped: false)
    defer {
      markDeletion(since: deletionStart)
      recordDeletionPosition(since: deletionStart, previousField: previousField)
    }

    // A hidden source-word boundary is still a commit. Do not let the
    // space-delimited fallback clear the entire flattened input history.
    if tracksNoSpaceWordBursts, acceptedUnits == nil {
      if noSpaceCommittedWordIndex != nil {
        removePreviousWordForHardDelete(clearingWord: true, at: date)
      } else {
        clearCurrentWord(at: date)
      }
      return
    }

    var removedCurrentWord = false
    while !typed.isEmpty, !lastInputCommitsWord {
      removeLastTypedCharacter()
      recordReplayEvent(kind: .delete, text: "", at: date)
      removedCurrentWord = true
    }
    guard !removedCurrentWord, lastInputCommitsWord else { return }

    removeLastTypedCharacter()
    recordReplayEvent(kind: .delete, text: "", at: date)
    while !typed.isEmpty, !lastInputCommitsWord {
      removeLastTypedCharacter()
      recordReplayEvent(kind: .delete, text: "", at: date)
    }
  }

  private var canDeleteBackward: Bool {
    if let acceptedUnits, acceptedUnits.terminalElementCleared, acceptedUnits.fieldIndex == 0 { return false }
    if configuration.rules.confidenceMode == .maximum { return false }
    if configuration.rules.freedomMode { return true }
    if acceptedUnits == nil, let word = noSpaceCommittedWordIndex, let range = noSpaceWordRange(for: word) {
      if configuration.rules.confidenceMode == .on { return false }
      return range.contains { !isTypedCharacterCorrect(at: $0) }
    }
    guard lastInputCommitsWord else {
      return true
    }
    if configuration.rules.confidenceMode == .on { return false }
    if let acceptedUnits {
      let index = acceptedUnits.fieldIndex - 1
      return acceptedUnits.field(index) != unitTargets.field(index)
    }
    // Drop the active field, not submitted empty fields: a blank line is a
    // real prior word whose correctness controls reopening it.
    let completedWords = Array(retainedInputWords(omittingEmptySubsequences: false).dropLast())
    guard let typedWord = completedWords.last else { return true }
    let targetWords = splitPromptWords(prompt, omittingEmptySubsequences: false)
    let index = completedWords.count - 1
    guard index < targetWords.count else { return true }
    return !InputTextIdentity.matches(typedWord, targetWords[index])
  }

  mutating func replaceInput(with value: String, at date: Date = .now) {
    guard !isFinished else { return }
    if value.count < typed.count {
      stoppedPromptInput = nil
      roundsLiveAccuracyForInputDisplay = true
      while typed.count > value.count { removeLastTypedCharacter() }
      return
    }
    let suffix = String(value.dropFirst(typed.count))
    insert(suffix, at: date)
  }

  mutating func tick(at date: Date = .now) {
    guard !isFinished, let duration = configuration.duration, let startedAt else { return }
    guard duration > 0 else { return }
    if date.timeIntervalSince(startedAt) >= duration { complete(at: date) }
  }

  /// Mirrors the reference's once-per-real-second threshold evaluation. Speed
  /// is intentionally deferred until the fifth active word; accuracy is not.
  mutating func enforceLivePracticeThresholds(at date: Date = .now) {
    guard !isFinished, startedAt != nil else { return }
    roundsLiveAccuracyForInputDisplay = false
    guard let reason = livePracticeThresholdFailure(at: date) else { return }
    fail(at: date, reason: reason)
  }

  /// Stops a running attempt when local timer delivery has become too delayed
  /// to trust a short-test result. It intentionally uses the ordinary failed
  /// outcome so result saving, statistics, sync, and publication stay off.
  mutating func failForTimerHealth(at date: Date = .now) {
    guard !isFinished, startedAt != nil else { return }
    fail(at: date, reason: .timerHealth)
  }

  mutating func abandon(at date: Date = .now) {
    guard !isFinished, startedAt != nil else { return }
    outcome = .abandoned
    finishedAt = date
  }

  /// Ends a long test through the same result path as the reference's
  /// double Shift+Enter bailout. It is deliberately distinct from a manual
  /// abandonment: callers can present its local result, while persistence
  /// and publication policies continue to reject it.
  mutating func bailOut(at date: Date = .now) {
    guard !isFinished, startedAt != nil else { return }
    outcome = .bailedOut
    finishedAt = date
  }

  /// Infinite timed challenges need an intentional successful finish. A normal
  /// long-test bailout remains unsaved and cannot satisfy a challenge.
  var canFinishInfiniteChallenge: Bool {
    guard hasStarted, !isFinished,
      configuration.mode == .time, configuration.duration == 0,
      let challenge = TypebarChallengeLibrary.challenge(id: configuration.challengeID)
    else { return false }
    return challenge.preset.configuration.mode == .time
      && challenge.preset.configuration.duration == 0
  }

  mutating func finishInfiniteChallenge(at date: Date = .now) {
    guard canFinishInfiniteChallenge else { return }
    complete(at: date)
  }

  /// Zen has no automatic terminal condition. It completes only through its
  /// explicit Shift+Enter command after the user has begun entering text.
  mutating func finishZen(at date: Date = .now) {
    guard configuration.mode == .zen, !isFinished, startedAt != nil else { return }
    complete(at: date)
  }

  private mutating func beginIfNeeded(at date: Date) {
    if startedAt == nil {
      startedAt = date
    }
  }

  /// The reference expands the typographic ellipsis only when it is not the
  /// character the prompt itself requests. This preserves literal ellipses
  /// in custom text while accepting the common macOS replacement for `...`.
  private mutating func shouldExpandReferenceEllipsis(_ character: Character, at date: Date) -> Bool {
    guard character == "…" else { return false }
    extendPromptIfNeeded(at: date)
    guard nextTargetIndex < promptCharacters.count else { return true }
    return promptCharacters[nextTargetIndex] != character
  }

  /// The fixed reference expands the Dutch IJ ligature through regular `i`
  /// and `j` input for the base catalog and its numeric-size variants. It
  /// keeps a literal ligature target intact for custom prompts.
  private mutating func shouldExpandDutchLigature(_ character: Character, at date: Date) -> Bool {
    guard character == "ĳ", configuration.language.usesDutchLigatureInputExpansion else {
      return false
    }
    extendPromptIfNeeded(at: date)
    guard nextTargetIndex < promptCharacters.count else { return true }
    return promptCharacters[nextTargetIndex] != character
  }

  @discardableResult
  private mutating func insertCharacter(
    _ character: Character, forceError: Bool, at date: Date, evaluatesTerminalRules: Bool
  ) -> Bool {
    latestReplayInputPosition = nil
    latestNoSpaceAttempt = nil
    latestNoSpaceAttemptFieldIndex = nil
    latestNoSpaceFinishDecision = false
    // `forceError` also supports deterministic engine tests that intentionally
    // retain a wrong character. Only the physical opposite-Shift path has the
    // reference behavior of immediately rejecting its text.
    let rejectsOppositeShiftInput = forceError && configuration.rules.oppositeShiftMode != .off
    if configuration.mode == .zen {
      // The reference still starts a Zen test when opposite Shift rejects a
      // key, but Zen has no target character to score as incorrect. The key
      // therefore leaves no accepted text or replay action, but still has a
      // correct judged input event for activity statistics.
      if rejectsOppositeShiftInput {
        beginIfNeeded(at: date)
        recordInputAttempt(character, correctUnits: String(character).utf16.count)
        recordWeakSpotInput(character, isCorrect: true, at: date)
        recordReplayEvent(kind: .insert, text: String(character), inputStopped: true, at: date)
        return false
      }
      let accepted = insertZenCharacter(character, at: date, evaluatesTerminalRules: evaluatesTerminalRules)
      if accepted {
        recordInputAttempt(character, correctUnits: String(character).utf16.count)
        recordWeakSpotInput(character, isCorrect: true, at: date)
      }
      return accepted
    }
    // The reference input accepts several platform space characters as the
    // regular word separator, but no-space rejects every one of them before
    // it can reach validation or result statistics.
    if TestModifierPolicy.usesNoSpaceInput(configuration.modifiers), isReferenceInputSpace(character) {
      return false
    }
    if character == "\n", !acceptsNewlineInput {
      return false
    }
    extendPromptIfNeeded(at: date)
    if unitTargets.noSpace, let acceptedUnits,
      unitTargets.fields.indices.contains(acceptedUnits.fieldIndex)
    {
      latestReplayInputPosition = .init(charIndex: acceptedUnits.validationCount,
        lastWord: acceptedUnits.fieldIndex == unitTargets.fields.count - 1)
    } else if usesWordCommitInput, !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers),
      !prompt.isEmpty {
      let fieldIndex = acceptedUnits?.fieldIndex ?? replayCommittedSeparatorCount
      if fieldIndex < unitTargets.sourceFieldCount {
        latestReplayInputPosition = .init(
          charIndex: acceptedUnits?.validationCount ?? inputWordText().utf16.count,
          lastWord: fieldIndex == unitTargets.sourceFieldCount - 1)
      }
    }
    if isAtEmptyNoSpaceWord, !unitTargets.noSpace {
      return insertIntoEmptyNoSpaceWord(character, rejectsOppositeShiftInput: rejectsOppositeShiftInput,
        forceError: forceError, at: date, evaluatesTerminalRules: evaluatesTerminalRules)
    }
    let currentTargetIndex = nextTargetIndex
    let inputCharacter = normalizedInputCharacter(
      character,
      expected: currentTargetIndex < promptCharacters.count ? promptCharacters[currentTargetIndex] : nil)
    // Finite terminal navigation clears the element without advancing the
    // source field. Convert ASCII only at that edge, not on every insertion.
    // Check the cheap candidate first: a finite stream's exhaustion reader
    // counts its whole source and must not run for every ordinary character.
    if acceptedUnits == nil, hasOrdinarySourceFields, inputCharacter == " ", !inputWordIsEmpty,
      replayCommittedSeparatorCount == unitTargets.sourceFieldCount - 1,
      !usesIncrementalPromptExtension {
      beginUnitInput()
    }
    if let unit = currentInputUnit, !(0xD800...0xDFFF).contains(unit) {
      currentInputUnit = String(inputCharacter).utf16.first
    }
    if unitTargets.noSpace, let acceptedUnits {
      latestNoSpaceAttemptFieldIndex = acceptedUnits.fieldIndex
      latestNoSpaceAttempt = acceptedUnits.field(acceptedUnits.fieldIndex)
        + [currentInputUnit ?? String(inputCharacter).utf16.first!]
      let stopped = rejectsOppositeShiftInput || configuration.rules.stopOnErrorMode == .letter
        && !inputAccuracyUnits(for: inputCharacter, targetIndex: currentTargetIndex,
          forceError: forceError).lastCorrect
      let attempted = latestNoSpaceAttempt!
      let target = unitTargets.field(acceptedUnits.fieldIndex)
      let quick = configuration.rules.quickEnd && configuration.rules.stopOnErrorMode == .off
        && !configuration.rules.deleteOnErrorMode.isEnabled && attempted.count == target.count
      latestNoSpaceFinishDecision = attempted == target || quick || !stopped
        && shouldCommitNoSpaceUnit(currentInputUnit ?? String(inputCharacter).utf16.first!)
    }
    let commitsCurrentWord = isPromptWordSeparator(inputCharacter) && !inputWordIsEmpty
    let retainsLeadingSeparator = isPromptWordSeparator(inputCharacter) && inputWordIsEmpty
      && (unitTargets.noSpace || usesWordCommitInput && !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers))
      && (configuration.rules.strictSpace || configuration.difficulty != .normal)
    // Ignore an ordinary leading space before word-stop can retain it.
    // Strict space and expert/master instead keep it in the current field.
    if inputCharacter == " " && inputWordIsEmpty && shouldRejectLeadingSeparator,
      currentTargetIndex < promptCharacters.count,
      promptCharacters[currentTargetIndex] != " " { return false }
    let retainsStoppedSeparator = configuration.rules.stopOnErrorMode == .word
      && !retainsLeadingSeparator
      && usesWordCommitInput && !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
      && isPromptWordSeparator(inputCharacter) && !currentWordIsCorrect
    if let inputLimit = currentSpaceDelimitedWordInputLimit,
      activeInputWordUTF16Length >= inputLimit,
      !commitsCurrentWord || retainsStoppedSeparator
    {
      return false
    }
    if retainsStoppedSeparator {
      beginIfNeeded(at: date)
      let units = inputAccuracyUnits(for: inputCharacter,
        targetIndex: currentTargetIndex, forceError: forceError)
      recordInputAttempt(inputCharacter, correctUnits: units.correct, lastUnitCorrect: units.lastCorrect,
        judgments: units.judgments)
      recordWeakSpotInput(inputCharacter, isCorrect: units.lastCorrect, at: date)
      if !units.lastCorrect { attemptedErrorCounts[currentTargetIndex, default: 0] += 1 }
      if rejectsOppositeShiftInput {
        recordReplayEvent(kind: .insert, text: String(inputCharacter), forceError: true,
          inputStopped: true, at: date)
        if evaluatesTerminalRules, configuration.difficulty == .master { fail(at: date) }
        return false
      }
      retainedWordSeparatorTypedIndices.insert(typedGraphemeCount)
      appendTypedCharacter(inputCharacter, targetIndex: nil,
        countsAsExtraError: !units.lastCorrect, at: date)
      if evaluatesTerminalRules,
        (configuration.difficulty == .expert && commitsCurrentWord)
          || (configuration.difficulty == .master && !units.lastCorrect)
      { fail(at: date) }
      return true
    }
    if currentTargetIndex >= promptCharacters.count && acceptedUnits == nil {
      beginIfNeeded(at: date)
      recordInputAttempt(inputCharacter, correctUnits: 0)
      recordWeakSpotInput(inputCharacter, isCorrect: false, at: date)
      if rejectsOppositeShiftInput {
        recordReplayEvent(kind: .insert, text: String(inputCharacter), forceError: true,
          inputStopped: true, at: date)
        if evaluatesTerminalRules, configuration.difficulty == .master { fail(at: date) }
        return false
      }
      appendTypedCharacter(
        inputCharacter, targetIndex: nil,
        countsAsExtraError: inputCharacter != " " && hasUncommittedSpaceDelimitedInput, at: date)
      recordWordBurstIfCommitted()
      recordNoSpaceWordBurstIfCommitted()
      return true
    }
    beginIfNeeded(at: date)
    let fallbackExpected: Character = promptCharacters.isEmpty ? "\u{FFFD}"
      : promptCharacters[min(currentTargetIndex, promptCharacters.count - 1)]
    let expected: Character = acceptedUnits.map { _ in
      let comparison = inputAccuracyTarget(at: currentTargetIndex)
      return comparison.units.indices.contains(comparison.position)
        ? UnicodeScalar(UInt32(comparison.units[comparison.position])).map { Character(String($0)) }
          ?? fallbackExpected
        : fallbackExpected
    } ?? fallbackExpected
    let retainsCurrentWordAsExtra = shouldRetainInCurrentWord(
      inputCharacter, expected: expected)
    let earlyWordCommitTargetIndex = incompleteWordCommitTargetIndex(
      for: inputCharacter, currentTargetIndex: currentTargetIndex)
    // A separator-only target has no interior cursor position to consume
    // while navigation is blocked. Nonempty words still consume their first
    // character, so the next comparison stays at its word-local position.
    let retainsEmptySlot = retainsLeadingSeparator && isPromptWordSeparator(expected)
    let pastTargetEnd = currentTargetIndex >= promptCharacters.count
      || unitTargets.noSpace && activeInputWordUTF16Length >= unitTargets.field(acceptedUnits!.fieldIndex).count
    let targetIndex = retainsCurrentWordAsExtra || retainsEmptySlot || pastTargetEnd
      ? nil : earlyWordCommitTargetIndex ?? currentTargetIndex
    let accuracyUnits = inputAccuracyUnits(
      for: inputCharacter, targetIndex: currentTargetIndex, forceError: forceError)
    let followsRetainedLeadingSeparator = !retainedWordSeparatorTypedIndices.isEmpty
      && inputWordText().first.map(isPromptWordSeparator) == true
    let isCorrect = !retainsCurrentWordAsExtra && !forceError && accuracyUnits.lastCorrect
      && (supportsBMPUnitInput
        ? accuracyUnits.correct == String(inputCharacter).utf16.count
        : InputTextIdentity.matches(inputCharacter, expected))
    recordInputAttempt(inputCharacter, correctUnits: accuracyUnits.correct,
      lastUnitCorrect: accuracyUnits.lastCorrect, judgments: accuracyUnits.judgments)
    recordWeakSpotInput(inputCharacter, isCorrect: isCorrect, at: date)
    if !isCorrect { attemptedErrorCounts[currentTargetIndex, default: 0] += 1 }
    // Opposite Shift records a failed physical attempt, but the reference
    // immediately removes its text and does not run stop/delete-on-error
    // recovery. Master difficulty still fails on that rejected mistake.
    if rejectsOppositeShiftInput {
      recordReplayEvent(kind: .insert, text: String(inputCharacter), forceError: true,
        inputStopped: true, at: date)
      if evaluatesTerminalRules,
        configuration.difficulty == .master || shouldFailExpertOnAttemptedInput(inputCharacter)
      {
        fail(at: date)
      }
      return false
    }
    let failsExpertAttempt = shouldFailExpertOnAttemptedInput(inputCharacter)
    let blocksNoSpaceWordAdvance = !unitTargets.noSpace && shouldBlockNoSpaceWordAdvance(
      with: inputCharacter, forceError: forceError)
    if configuration.modifiers.contains(.correctBeforeAdvance),
      (usesWordCommitInput || tracksNoSpaceWordBursts),
      ((isPromptWordSeparator(inputCharacter) && !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
        && !currentWordIsCorrect)
        || blocksNoSpaceWordAdvance)
    {
      return false
    }
    if configuration.rules.stopOnErrorMode == .word,
      (usesWordCommitInput || tracksNoSpaceWordBursts),
      blocksNoSpaceWordAdvance
    {
      return false
    }
    if !isCorrect && configuration.rules.stopOnErrorMode == .letter {
      if !configuration.rules.blindMode {
        // Unlike a space commit, a source Return is a visible target slot.
        // The first stopped letter at that slot replaces its icon; after a
        // retained Return has consumed it, further stopped text is extra.
        let fieldStart = promptCharacters[..<currentTargetIndex].lastIndex(where: isPromptWordSeparator)
          .map { $0 + 1 } ?? 0
        let occupiesReturn = expected == "\n"
          && activeInputWordUTF16Length == String(promptCharacters[fieldStart..<currentTargetIndex]).utf16.count
        stoppedPromptCandidate = .init(character: inputCharacter,
          targetIndex: (retainsCurrentWordAsExtra || retainsEmptySlot || pastTargetEnd) && !occupiesReturn
            ? nil : currentTargetIndex)
      }
      recordReplayEvent(kind: .insert, text: String(inputCharacter), forceError: forceError,
        inputStopped: true, at: date)
      if evaluatesTerminalRules,
        (configuration.difficulty == .master && !accuracyUnits.lastCorrect)
          || shouldFailExpertOnAttemptedInput(inputCharacter)
      {
        fail(at: date)
      }
      return false
    }
    if !isCorrect && configuration.rules.deleteOnErrorMode.isEnabled {
      // The reference first inserts and logs the failed key, then emits its
      // recovery deletes. Keeping that transient state in the native replay
      // makes playback, automatic-event sound policy, and live input history
      // agree with the visible error recovery.
      let activeWordWasEmpty = activeDeleteOnErrorWordIsEmpty
      // Difficulty uses the attempted field before recovery rewinds it.
      // Still perform and log recovery before publishing the failed outcome.
      let failsDifficulty = (configuration.difficulty == .master && !accuracyUnits.lastCorrect)
        || shouldFailExpertOnAttemptedInput(inputCharacter)
      if isPromptWordSeparator(inputCharacter) {
        // Recovery never submits its erroneous separator. Persist the same
        // existing no-commit marker used for other retained field separators.
        retainedWordSeparatorTypedIndices.insert(typedGraphemeCount)
      }
      appendTypedCharacter(
        inputCharacter, targetIndex: targetIndex,
        forceError: forceError || earlyWordCommitTargetIndex != nil,
        countsAsExtraError: retainsCurrentWordAsExtra || pastTargetEnd, at: date)
      recordReplayEvent(
        kind: .insert, text: String(inputCharacter), forceError: forceError, at: date)
      deleteForError(
        configuration.rules.deleteOnErrorMode, activeWordWasEmpty: activeWordWasEmpty, at: date)
      if evaluatesTerminalRules && failsDifficulty { fail(at: date) }
      return false
    }
    if !isCorrect && configuration.modifiers.contains(.clearCurrentWordOnError),
      usesWordCommitInput,
      !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
    {
      clearCurrentWord(at: date)
      return false
    }
    let commitErrorStart = ordinaryCommitErrorStart(for: inputCharacter, targetIndex: targetIndex)
    if retainsLeadingSeparator { retainedWordSeparatorTypedIndices.insert(typedGraphemeCount) }
    appendTypedCharacter(
      inputCharacter, targetIndex: targetIndex,
      forceError: forceError || earlyWordCommitTargetIndex != nil
        || (followsRetainedLeadingSeparator && !isCorrect && InputTextIdentity.matches(inputCharacter, expected)),
      countsAsExtraError: retainsCurrentWordAsExtra || (retainsEmptySlot && !isCorrect)
        || (pastTargetEnd && !isPromptWordSeparator(inputCharacter)), at: date)
    if let commitErrorStart { committedErrorWordStarts.insert(commitErrorStart) }
    if configuration.rules.blindMode, let commitIndex = earlyWordCommitTargetIndex {
      let end = isPromptWordSeparator(promptCharacters[commitIndex]) ? commitIndex : commitIndex + 1
      blindCommittedMissingTargetIndices.formUnion(currentTargetIndex..<end)
    }
    recordWordBurstIfCommitted()
    recordNoSpaceWordBurstIfCommitted()
    if !configuration.rules.blindMode, committedNoSpaceWordHasError,
      let word = noSpaceCommittedWordIndex, let range = noSpaceWordRange(for: word)
    {
      committedErrorWordStarts.insert(range.lowerBound)
    }

    // Multi-unit text runs terminal difficulty only on its last input unit.
    // Keep the whole glyph's diagnostic error separate: it can be wrong
    // while its final combining mark is correct (or the reverse after drift).
    if evaluatesTerminalRules, configuration.difficulty == .master && !accuracyUnits.lastCorrect {
      fail(at: date)
    } else if evaluatesTerminalRules, configuration.difficulty == .expert
      && (unitTargets.noSpace ? failsExpertAttempt
        : (commitsCurrentWord && (!isCorrect || errorsInCurrentWord() > 0)) || committedNoSpaceWordHasError)
    {
      fail(at: date)
    } else if evaluatesTerminalRules, shouldFailMinimumWordBurst(after: inputCharacter) {
      fail(at: date)
    }
    return true
  }

  /// A zero-length no-space target has no final letter capable of committing
  /// it. Nonseparator attempts belong to that field, never to later glyphs.
  private mutating func insertIntoEmptyNoSpaceWord(
    _ character: Character, rejectsOppositeShiftInput: Bool, forceError: Bool,
    at date: Date, evaluatesTerminalRules: Bool
  ) -> Bool {
    guard let boundary = emptyNoSpaceWordBoundary,
      String(typed.suffix(max(0, typedGraphemeCount - boundary))).utf16.count < 20
    else { return false }
    beginIfNeeded(at: date)
    recordInputAttempt(character, correctUnits: 0)
    recordWeakSpotInput(character, isCorrect: false, at: date)
    attemptedErrorCounts[boundary, default: 0] += 1
    if evaluatesTerminalRules, configuration.difficulty == .master { fail(at: date) }
    if rejectsOppositeShiftInput || configuration.rules.stopOnErrorMode == .letter {
      if !rejectsOppositeShiftInput && !configuration.rules.blindMode {
        stoppedPromptCandidate = .init(character: character, targetIndex: nil)
      }
      recordReplayEvent(kind: .insert, text: String(character), forceError: forceError,
        inputStopped: true, at: date)
      return false
    }
    let activeWordWasEmpty = typedGraphemeCount == boundary
    appendTypedCharacter(character, targetIndex: nil, countsAsExtraError: true, at: date)
    if configuration.rules.deleteOnErrorMode.isEnabled {
      recordReplayEvent(kind: .insert, text: String(character), forceError: forceError, at: date)
      deleteForError(configuration.rules.deleteOnErrorMode,
        activeWordWasEmpty: activeWordWasEmpty, at: date)
      return false
    }
    return true
  }

  private mutating func recordWeakSpotInput(
    _ character: Character, isCorrect: Bool, at date: Date
  ) {
    defer { weakSpotLastInputDate = date }
    guard let previous = weakSpotLastInputDate else { return }
    let interval = date.timeIntervalSince(previous)
    guard interval.isFinite, interval >= 0 else { return }
    // The reference live cache rounds the millisecond gap to two decimal
    // places before weakspot consumes it, which also avoids Date's binary
    // floating-point noise changing an otherwise identical ranking.
    let roundedInterval = (interval * 100_000).rounded() / 100_000
    weakSpotInputSamples.append(
      .init(character: character, interval: roundedInterval, isCorrect: isCorrect))
  }

  private func ordinaryCommitErrorStart(for character: Character, targetIndex: Int?) -> Int? {
    if let acceptedUnits {
      guard !configuration.rules.blindMode, isPromptWordSeparator(character),
        unitTargets.fields.indices.contains(acceptedUnits.fieldIndex)
      else { return nil }
      let range = unitTargets.fields[acceptedUnits.fieldIndex]
      let attempted = acceptedUnits.field(acceptedUnits.fieldIndex) + [currentInputUnit ?? String(character).utf16.first!]
      let correct = attempted == unitTargets.field(acceptedUnits.fieldIndex)
        && !acceptedUnits.entries[acceptedUnits.range(acceptedUnits.fieldIndex)].contains(where: \.forced)
      return correct || range.isEmpty ? nil : unitTargets.glyphs[range.lowerBound]
    }
    guard !configuration.rules.blindMode, !tracksNoSpaceWordBursts,
      isPromptWordSeparator(character), let targetIndex,
      promptCharacters.indices.contains(targetIndex),
      isPromptWordSeparator(promptCharacters[targetIndex]) || targetIndex == promptCharacters.count - 1
    else { return nil }
    let start = promptCharacters[..<targetIndex].lastIndex(where: isPromptWordSeparator)
      .map { $0 + 1 } ?? 0
    let end = isPromptWordSeparator(promptCharacters[targetIndex]) ? targetIndex : targetIndex + 1
    let input = inputWordText()
    let target = String(promptCharacters[start..<end])
    let correct = InputTextIdentity.matches(input, target)
      && InputTextIdentity.matches(promptCharacters[targetIndex], character)
      && !(start..<end).contains { forcedErrorIndices.contains($0) }
    return correct ? nil : start
  }

  private mutating func recordInputAttempt(
    _ character: Character, correctUnits: Int, lastUnitCorrect: Bool? = nil, judgments: [Bool]? = nil
  ) {
    let units = String(character).utf16.count
    inputAttemptCount += units
    correctInputAttemptCount += correctUnits
    lastInputWasCorrect = lastUnitCorrect ?? (correctUnits == units)
    latestInputCorrectness = judgments ?? Array(repeating: correctUnits == units, count: units)
    latestReplayInputText = String(character)
    latestReplayInputUnits = currentInputUnit.map { [$0] }
    if unitTargets.noSpace, let acceptedUnits {
      let index = acceptedUnits.fieldIndex
      highestAttemptedNoSpaceField = max(highestAttemptedNoSpaceField ?? -1, index)
      if correctUnits < units { noSpaceUnitAttemptErrors[index, default: 0] += units - correctUnits }
    }
  }

  /// Accuracy follows input-event units, not the native caret's grapheme
  /// position. A wrong emoji can share a correct surrogate with its target.
  /// Deletion changes the next comparison position but never these tallies.
  private func inputAccuracyUnits(
    for character: Character, targetIndex: Int, forceError: Bool
  ) -> (correct: Int, lastCorrect: Bool, judgments: [Bool]) {
    let inputUnits = currentInputUnit.map { [$0] } ?? Array(String(character).utf16)
    guard !forceError, acceptedUnits != nil || promptCharacters.indices.contains(targetIndex) else {
      return (0, false, Array(repeating: false, count: inputUnits.count))
    }
    let comparison = inputAccuracyTarget(at: targetIndex)
    let targetUnits = comparison.units
    let position = comparison.position
    var correct = 0
    var lastCorrect = false
    var judgments: [Bool] = []
    for (index, unit) in inputUnits.enumerated() {
      lastCorrect = targetUnits.indices.contains(position + index) && targetUnits[position + index] == unit
      judgments.append(lastCorrect)
      if lastCorrect { correct += 1 }
    }
    return (correct, lastCorrect, judgments)
  }

  private func inputAccuracyTarget(at targetIndex: Int) -> (units: [UInt16], position: Int) {
    if let acceptedUnits {
      return (unitTargets.field(acceptedUnits.fieldIndex), acceptedUnits.validationCount)
    }
    guard promptCharacters.indices.contains(targetIndex) else { return ([], 0) }
    let target: String
    let position: Int
    if let range = activeNoSpaceWordRange, range.upperBound <= promptCharacters.count {
      target = String(promptCharacters[range])
      position = String(typed.suffix(max(0, typed.count - range.lowerBound))).utf16.count
    } else if TestModifierPolicy.usesNoSpaceInput(configuration.modifiers) {
      // Without hidden boundaries, use the known flattened target only.
      target = prompt
      position = typed.utf16.count
    } else {
      let start = promptCharacters[..<targetIndex].lastIndex(where: isPromptWordSeparator)
        .map { $0 + 1 } ?? 0
      let separator = promptCharacters[targetIndex...].firstIndex(where: isPromptWordSeparator)
      let end = separator.map { $0 + 1 } ?? promptCharacters.count
      target = String(promptCharacters[start..<end])
      position = activeInputWordUTF16Length
    }
    return (Array(target.utf16), position)
  }

  /// Zen accepts the user's own text rather than comparing it to a generated
  /// word list. Space and Return end an entered word; Tab remains text.
  @discardableResult
  private mutating func insertZenCharacter(
    _ character: Character, at date: Date, evaluatesTerminalRules: Bool
  ) -> Bool {
    let commitsWord = isZenWordCommit(character)
    let activeLength = zenActiveWordLength
    if activeLength >= 30 && !commitsWord { return false }
    if character == " " && activeLength == 0 { return false }

    beginIfNeeded(at: date)
    appendTypedCharacter(character, targetIndex: nil, at: date)
    recordZenWordBurstIfCommitted(after: character)
    if evaluatesTerminalRules, shouldFailMinimumWordBurst(after: character) { fail(at: date) }
    return true
  }

  private var currentWordIsCorrect: Bool {
    if let acceptedUnits {
      let index = acceptedUnits.lastCommits ? acceptedUnits.submittedFieldIndex : acceptedUnits.fieldIndex
      guard unitTargets.fields.indices.contains(index) else { return false }
      return acceptedUnits.field(index, withoutCommit: true) == unitTargets.field(index, withoutCommit: true)
        && !acceptedUnits.entries[acceptedUnits.range(index)].contains(where: \.forced)
    }
    // Input retains submitted blank fields. Target slots must use the same
    // indexing or a later correct word is compared with the wrong target.
    let targetWords = splitPromptWords(prompt, omittingEmptySubsequences: false)
    let typedWords = retainedInputWords(omittingEmptySubsequences: false)
    let wordIndex = lastInputCommitsWord
      ? max(typedWords.count - 1, 0) : typedWords.count - 1
    guard wordIndex >= 0, wordIndex < targetWords.count, wordIndex < typedWords.count else {
      return false
    }
    return InputTextIdentity.matches(typedWords[wordIndex], targetWords[wordIndex])
      && !hasForcedError(inWord: wordIndex)
  }

  /// Removes accepted characters from the active, unfinished word while
  /// preserving any already submitted words. Each removal becomes a replay
  /// event so result playback reconstructs the same input state.
  private mutating func clearCurrentWord(at date: Date, automatic: Bool = false) {
    if let range = activeNoSpaceWordRange {
      while typed.count > range.lowerBound {
        removeLastTypedCharacter()
        recordReplayEvent(kind: .delete, text: "", automatic: automatic, at: date)
      }
      return
    }
    while !typed.isEmpty, !lastInputCommitsWord {
      removeLastTypedCharacter()
      recordReplayEvent(kind: .delete, text: "", automatic: automatic, at: date)
    }
  }

  /// Mirrors the reference's event sequence: the failed key is logged first,
  /// then automatic deletions remove it and, depending on the selected mode,
  /// prior progress. Historical input attempts deliberately remain scored.
  private mutating func deleteForError(
    _ mode: DeleteOnErrorMode, activeWordWasEmpty: Bool, at date: Date
  ) {
    // `insertCharacter` has already retained the failed key long enough to
    // serialize it to replay. It must be removed before examining the prior
    // word boundary, including when the failed key is itself a separator.
    guard !typed.isEmpty else { return }
    let deletionStart = replayEvents.count
    removeLastTypedCharacter()
    recordReplayEvent(kind: .delete, text: "", automatic: true, at: date)

    if mode.returnsToPreviousWordAtStart && activeWordWasEmpty,
      ((usesWordCommitInput
        && !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)) || tracksNoSpaceWordBursts), !typed.isEmpty
    {
      if mode.clearsWholeWord { markDeletion(since: deletionStart) }
      removePreviousWordForHardDelete(
        clearingWord: mode.clearsWholeWord, automatic: true, at: date)
      return
    }
    if mode.clearsWholeWord {
      clearCurrentWord(at: date, automatic: true)
      markDeletion(since: deletionStart)
    } else {
      removeLastCharacterFromCurrentWord(at: date, automatic: true)
    }
  }

  private mutating func removeLastCharacterFromCurrentWord(
    at date: Date, automatic: Bool = false
  ) {
    if isAtEmptyNoSpaceWord, typedGraphemeCount == emptyNoSpaceWordBoundary { return }
    if let range = activeNoSpaceWordRange, typedGraphemeCount == range.lowerBound { return }
    guard !typed.isEmpty, !lastInputCommitsWord else { return }
    removeLastTypedCharacter()
    recordReplayEvent(kind: .delete, text: "", automatic: automatic, at: date)
  }

  private mutating func removePreviousWordForHardDelete(
    clearingWord: Bool, automatic: Bool = false, at date: Date
  ) {
    let deletionStart = replayEvents.count
    defer { if clearingWord { markDeletion(since: deletionStart) } }
    if tracksNoSpaceWordBursts, acceptedUnits == nil,
      let wordIndex = noSpaceWordEndIndices.firstIndex(of: typed.count),
      let previousRange = noSpaceWordRange(for: wordIndex)
    {
      if clearingWord {
        while typed.count > previousRange.lowerBound {
          removeLastTypedCharacter()
          recordReplayEvent(kind: .delete, text: "", automatic: automatic, at: date)
        }
      } else {
        removeLastTypedCharacter()
        recordReplayEvent(kind: .delete, text: "", automatic: automatic, at: date)
      }
      return
    }
    guard lastInputCommitsWord else { return }
    removeLastTypedCharacter()
    recordReplayEvent(kind: .delete, text: "", automatic: automatic, at: date)
    if clearingWord {
      clearCurrentWord(at: date, automatic: automatic)
    }
  }

  private mutating func recordReplayEvent(
    kind: TypingReplayEventKind, text: String, forceError: Bool = false, automatic: Bool = false,
    inputStopped: Bool = false,
    at date: Date
  )
  {
    guard let startedAt else { return }
    if kind == .insert, inputStopped { discardTerminalElementIfNeeded() }
    let field = replayInputField(kind: kind, inputStopped: inputStopped)
    // A converted session preserves actual units, including lone surrogates;
    // no-space/legacy primitives retain their distinct archive contracts.
    let raw = acceptedUnits != nil || (kind == .insert ? recordsBMPUnits : lastDeletionWasBMPUnit)
    let recordedField = acceptedUnits != nil ? field
      : raw ? field.map { TypingReplayInputField(index: $0.index, units: Array($0.value.utf16)) } : field
    let retainsSeparator = acceptedUnits.map { buffer in
      guard let last = buffer.entries.last else { return false }
      return (last.unit == 32 || last.unit == 10) && !last.commits
    } ?? retainedWordSeparatorTypedIndices.contains(typedGraphemeCount - 1)
    replayEvents.append(
      .init(
        offset: max(0, date.timeIntervalSince(startedAt)), kind: kind, text: text,
        forceError: forceError, automatic: automatic || applyingAutomaticCodeInput,
        commitsWord: kind == .insert && retainsSeparator
          ? false : nil, inputStopped: inputStopped ? true : nil,
        inputField: recordedField, inputCorrectness: kind == .insert ? latestInputCorrectness : nil,
        textUTF16: raw ? (kind == .insert ? latestReplayInputUnits ?? Array(text.utf16) : []) : nil,
        inputPosition: kind == .insert ? latestReplayInputPosition : nil,
        discardedInputUnits: latestReplayDiscardedUnits,
        clearedNextWord: latestReplayClearedNextWord ? true : nil))
    if unitTargets.noSpace || configuration.mode == .zen || hasOrdinarySourceFields {
      recordedFieldStats.record(replayEvents.last!)
    }
    latestReplayDiscardedUnits = nil
    latestReplayClearedNextWord = false
  }

  private func replayInputField(
    kind: TypingReplayEventKind, inputStopped: Bool
  ) -> TypingReplayInputField? {
    if let acceptedUnits {
      let submitted = kind == .insert && !inputStopped && acceptedUnits.lastCommits
      let index = submitted ? acceptedUnits.submittedFieldIndex : acceptedUnits.fieldIndex
      return .init(index: index, units: acceptedUnits.field(index))
    }
    if tracksNoSpaceWordBursts {
      let completed = completedWordCount
      let submitted = kind == .insert && !inputStopped && completed > 0
        && noSpaceWordEndIndices[completed - 1] == typedGraphemeCount
      let index = submitted ? completed - 1 : completed
      let field = min(index, noSpaceWordEndIndices.count - 1)
      guard let range = noSpaceWordRange(for: field) else { return nil }
      return .init(index: field,
        value: String(typed.suffix(max(0, typedGraphemeCount - range.lowerBound))))
    }
    // Unknown hidden boundaries remain a legacy flat tape, not guessed words.
    guard configuration.mode == .zen || usesWordCommitInput,
      !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
    else { return nil }
    let submitted = kind == .insert && !inputStopped && lastInputCommitsWord
    let index = max(0, replayCommittedSeparatorCount - (submitted ? 1 : 0))
    let value = submitted
      ? inputWordText(omittingLastCommit: true) + String(typed.last!)
      : inputWordText()
    return .init(index: index, value: value)
  }

  private mutating func markDeletion(since start: Int, wholeWord: Bool = true) {
    guard start < replayEvents.count else { return }
    for index in start..<replayEvents.count {
      let event = replayEvents[index]
      replayEvents[index] = .init(offset: event.offset, kind: event.kind, text: event.text,
        forceError: event.forceError, automatic: event.automatic, commitsWord: event.commitsWord,
        wordDeletionCount: wholeWord && index == start ? replayEvents.count - start : nil,
        characterDeletionCount: !wholeWord && index == start ? replayEvents.count - start : nil,
        inputStopped: event.inputStopped, inputField: event.inputField,
        inputCorrectness: event.inputCorrectness, textUTF16: event.textUTF16,
        inputPosition: event.inputPosition, discardedInputUnits: event.discardedInputUnits,
        clearedNextWord: event.clearedNextWord, deletionCharIndex: event.deletionCharIndex)
    }
  }

  private mutating func recordDeletionPosition(since start: Int,
    previousField: TypingReplayInputField?, usesDestinationPosition: Bool = false
  ) {
    guard start < replayEvents.count, let previousField,
      let event = replayEvents.last, event.kind == .delete,
      let destination = event.inputField else { return }
    let position = usesDestinationPosition || destination.index != previousField.index
      ? destination.units.count : previousField.units.count
    replayEvents[replayEvents.count - 1] = .init(offset: event.offset, kind: event.kind,
      text: event.text, forceError: event.forceError, automatic: event.automatic,
      commitsWord: event.commitsWord, wordDeletionCount: event.wordDeletionCount,
      characterDeletionCount: event.characterDeletionCount, inputStopped: event.inputStopped,
      inputField: event.inputField, inputCorrectness: event.inputCorrectness,
      textUTF16: event.textUTF16, inputPosition: event.inputPosition,
      discardedInputUnits: event.discardedInputUnits, clearedNextWord: event.clearedNextWord,
      deletionCharIndex: position)
  }

  private func errorsInCurrentWord() -> Int {
    if let acceptedUnits, acceptedUnits.lastCommits {
      let index = acceptedUnits.submittedFieldIndex
      let input = acceptedUnits.field(index, withoutCommit: true)
      let target = unitTargets.field(index, withoutCommit: true)
      return input.enumerated().reduce(0) { total, part in
        total + (target.indices.contains(part.offset) && target[part.offset] == part.element ? 0 : 1)
      }
    }
    let typedWords = retainedInputWords(omittingEmptySubsequences: false)
    let promptWords = splitPromptWords(prompt, omittingEmptySubsequences: false)
    guard let typedWord = typedWords.dropLast().last, typedWords.count - 2 < promptWords.count
    else { return 0 }
    let promptWord = promptWords[typedWords.count - 2]
    let typedCharacters = Array(typed)
    let wordStart = typedCharacters.indices.reversed().first(where: {
      $0 < typedCharacters.count - 1 && isPromptWordSeparator(typedCharacters[$0])
        && !retainedWordSeparatorTypedIndices.contains($0)
    }).map { $0 + 1 } ?? 0
    return zip(typedWord, promptWord).enumerated().reduce(0) { total, pair in
      total + (InputTextIdentity.matches(pair.element.0, pair.element.1)
        && !forcedErrorIndices.contains(wordStart + pair.offset) ? 0 : 1)
    } + max(0, typedWord.count - promptWord.count)
  }

  private func activeWordBurst(start: Int, in characters: [Character]) -> Int? {
    let length = typedCharacterDates.count - start
    guard length >= 2, start >= 0, start < typedCharacterDates.count,
      characters.count == typedCharacterDates.count
    else { return nil }
    let elapsed = typedCharacterDates.last!.timeIntervalSince(typedCharacterDates[start])
    guard elapsed > 0 else { return nil }
    return wpm(characters: WordBurstInputUnits.count(characters[start...]) + 1, seconds: elapsed)
  }

  private func wordBurst(
    from start: Int, through end: Int, in characters: [Character], includesTrailingSpace: Bool
  ) -> Int? {
    guard start >= 0, end >= start, end < typedCharacterDates.count,
      end < characters.count
    else { return nil }
    let elapsed = typedCharacterDates[end].timeIntervalSince(typedCharacterDates[start])
    guard elapsed > 0 else { return nil }
    let units = WordBurstInputUnits.count(characters[start...end]) + (includesTrailingSpace ? 0 : 1)
    return wpm(characters: units, seconds: elapsed)
  }

  private mutating func recordWordBurstIfCommitted() {
    guard lastInputCommitsWord else { return }
    if let acceptedUnits {
      if let burst = acceptedUnits.burst(acceptedUnits.submittedFieldIndex) { committedWordBursts.append(burst) }
      return
    }
    if !typedNeedsFullSegmentation {
      let end = typedCharacterDates.count - 1
      let wordLength = retainedWordSeparatorTypedIndices.isEmpty
        ? typed.reversed().dropFirst().prefix { !isPromptWordSeparator($0) }.count
        : inputWordText(omittingLastCommit: true).count
      let start = end - wordLength
      guard start >= 0, start < end else { return }
      let elapsed = typedCharacterDates[end].timeIntervalSince(typedCharacterDates[start])
      guard elapsed > 0 else { return }
      committedWordBursts.append(wpm(characters: end - start + 1, seconds: elapsed))
      return
    }
    guard typedCharacterDates.count == typedGraphemeCount
    else { return }
    let end = typedGraphemeCount - 1
    let wordLength = retainedWordSeparatorTypedIndices.isEmpty
      ? typed.reversed().dropFirst().prefix { !isPromptWordSeparator($0) }.count
      : inputWordText(omittingLastCommit: true).count
    let start = end - wordLength
    guard start < end else { return }
    let elapsed = typedCharacterDates[end].timeIntervalSince(typedCharacterDates[start])
    guard elapsed > 0 else { return }
    let units = WordBurstInputUnits.count(typed.suffix(end - start + 1))
    committedWordBursts.append(wpm(characters: units, seconds: elapsed))
  }

  private mutating func recordNoSpaceWordBurstIfCommitted() {
    guard acceptedUnits == nil, let wordIndex = noSpaceCommittedWordIndex,
      typedCharacterDates.count == typedGraphemeCount
    else { return }
    let start = wordIndex == 0 ? 0 : noSpaceWordEndIndices[wordIndex - 1]
    let end = noSpaceWordEndIndices[wordIndex] - 1
    guard start < end else { return }
    let elapsed = typedCharacterDates[end].timeIntervalSince(typedCharacterDates[start])
    guard elapsed > 0 else { return }
    // A no-space commit is the word's last letter rather than an entered
    // separator, so count the same virtual trailing character used by the
    // regular word-burst path.
    let units = WordBurstInputUnits.count(typed.suffix(end - start + 1)) + 1
    committedWordBursts.append(wpm(characters: units, seconds: elapsed))
  }

  private mutating func recordZenWordBurstIfCommitted(after character: Character) {
    guard isZenWordCommit(character) else { return }
    if let acceptedUnits {
      if let burst = acceptedUnits.burst(acceptedUnits.submittedFieldIndex) { committedWordBursts.append(burst) }
      return
    }
    let characters = Array(typed)
    guard typedCharacterDates.count == characters.count else { return }
    let end = characters.count - 1
    let start = characters[..<end].lastIndex(where: { isZenWordCommit($0) }).map { $0 + 1 } ?? 0
    guard start < end else { return }
    let elapsed = typedCharacterDates[end].timeIntervalSince(typedCharacterDates[start])
    guard elapsed > 0 else { return }
    let units = WordBurstInputUnits.count(characters[start...end])
    committedWordBursts.append(wpm(characters: units, seconds: elapsed))
  }

  private func shouldFailMinimumWordBurst(after character: Character) -> Bool {
    if acceptedUnits?.terminalElementCleared == true { return false }
    let minimum = configuration.rules.minimumWordBurstWpm
    let mode = configuration.rules.minimumWordBurstMode
    let commitsWord: Bool
    if configuration.mode == .zen {
      commitsWord = isZenWordCommit(character)
    } else if tracksNoSpaceWordBursts {
      commitsWord = noSpaceCommittedWordIndex != nil
    } else {
      commitsWord = lastInputCommitsWord && isPromptWordSeparator(character) && usesWordCommitInput
        && !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
    }
    // Monkeytype computes minBurst only after goToNextWord has actually
    // advanced its active-word index. A terminal finite word completes the
    // attempt instead, so its burst is visible but cannot turn completion
    // into a failure. Repeating prompts can grow before that navigation, and
    // zen always creates another active word.
    let advancesToAnotherWord = configuration.mode == .zen
      || nextTargetIndex < promptCharacters.count
      || usesIncrementalPromptExtension
    guard mode != .off, minimum > 0, commitsWord, advancesToAnotherWord,
      let burst = committedWordBursts.last,
      let targetLength = lastCommittedBurstWordLength
    else { return false }
    let threshold = MinimumWordBurstPolicy.threshold(
      baseWpm: minimum, mode: mode, wordLength: targetLength)
    return Double(burst) < threshold
  }

  private var lastCommittedBurstWordLength: Int? {
    if let acceptedUnits, acceptedUnits.lastCommits {
      return configuration.mode == .zen ? acceptedUnits.range(acceptedUnits.submittedFieldIndex).count
        : unitTargets.field(acceptedUnits.submittedFieldIndex, withoutCommit: true).count
    }
    if configuration.mode == .zen {
      let characters = Array(typed)
      guard let last = characters.last, isZenWordCommit(last) else { return nil }
      let end = characters.count - 1
      let start = characters[..<end].lastIndex(where: { isZenWordCommit($0) }).map { $0 + 1 } ?? 0
      return WordBurstInputUnits.count(characters[start...end])
    }
    if let wordIndex = noSpaceCommittedWordIndex {
      let start = wordIndex == 0 ? 0 : noSpaceWordEndIndices[wordIndex - 1]
      let end = noSpaceWordEndIndices[wordIndex]
      guard start >= 0, start < end, end <= promptCharacters.count else { return nil }
      return WordBurstInputUnits.count(promptCharacters[start..<end])
    }
    guard lastInputCommitsWord else { return nil }
    let committedWords = retainedInputWords(omittingEmptySubsequences: true)
    let targetWords = splitPromptWords(prompt, omittingEmptySubsequences: true)
    guard committedWords.count > 0, committedWords.count <= targetWords.count else { return nil }
    return targetWords[committedWords.count - 1].utf16.count
  }

  private var zenActiveWordLength: Int {
    if let acceptedUnits { return acceptedUnits.activeCount }
    return String(typed.reversed().prefix { !isZenWordCommit($0) }.reversed()).utf16.count
  }

  private func isZenWordCommit(_ character: Character) -> Bool {
    isPromptWordSeparator(character)
  }

  private var tracksNoSpaceWordBursts: Bool {
    unitTargets.noSpace || !noSpaceWordEndIndices.isEmpty
  }

  private var noSpaceCommittedWordIndex: Int? {
    guard tracksNoSpaceWordBursts else { return nil }
    if unitTargets.noSpace, let acceptedUnits {
      return acceptedUnits.lastCommits ? acceptedUnits.submittedFieldIndex : nil
    }
    if isAtEmptyNoSpaceWord, let firstEmptyNoSpaceWordIndex, let boundary = emptyNoSpaceWordBoundary {
      return typedGraphemeCount == boundary && firstEmptyNoSpaceWordIndex > 0
        ? firstEmptyNoSpaceWordIndex - 1 : nil
    }
    return noSpaceWordEndIndices.firstIndex(of: typedGraphemeCount)
  }

  /// No-space keeps a hidden word boundary after every source word. The final
  /// visible character is therefore the equivalent of an entered separator.
  private var nextNoSpaceCommittedWordIndex: Int? {
    guard tracksNoSpaceWordBursts, !isAtEmptyNoSpaceWord else { return nil }
    return noSpaceWordEndIndices.firstIndex(of: typedGraphemeCount + 1)
  }

  /// A no-space word remains actionable only when its original boundary is
  /// retained. Unsegmented content deliberately falls through to the legacy
  /// character-level behavior instead of guessing linguistic word breaks.
  private var activeNoSpaceWordRange: Range<Int>? {
    guard tracksNoSpaceWordBursts, acceptedUnits == nil else { return nil }
    // The committed count already locates the first end strictly beyond the
    // input with binary search. Reuse it instead of re-counting a Unicode
    // string inside every comparison of a linear boundary scan.
    return noSpaceWordRange(for: completedWordCount)
  }

  /// Mirrors the reference product's explicit space set. Keep Return outside
  /// this group because custom prompts and Zen use it as a real newline.
  private func isReferenceInputSpace(_ character: Character) -> Bool {
    InputCharacterEquivalence.isReferenceSpace(character)
  }

  private func normalizedInputCharacter(_ character: Character, expected: Character?) -> Character {
    if let currentInputUnit, (0xD800...0xDFFF).contains(currentInputUnit) { return character }
    guard supportsBMPUnitInput else {
      return InputCharacterEquivalence.normalized(character, expected: expected, language: configuration.language)
    }
    // No reference equivalence set contains an ASCII letter except Russian
    // `e`. Its text cannot normalize differently at any target position, so
    // ordinary letter input needs no second field/UTF-16 buffer construction.
    if character.isASCII, character.isLetter,
      character != "e" || !configuration.language.usesRussianYoInputEquivalence
    { return character }
    let comparison = inputAccuracyTarget(at: nextTargetIndex)
    // A known surrogate or an exhausted field is not a different visible
    // glyph to normalize against. Only the actual next unit owns equivalence.
    let unitExpected = comparison.units.indices.contains(comparison.position)
      ? UnicodeScalar(UInt32(comparison.units[comparison.position])).map { Character(String($0)) } : nil
    return InputCharacterEquivalence.normalized(character, expected: unitExpected, language: configuration.language)
  }

  private var supportsBMPUnitInput: Bool {
    unitTargets.noSpace || configuration.mode == .zen || (usesWordCommitInput && !tracksNoSpaceWordBursts
      && !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers))
  }

  private var shouldRejectLeadingSeparator: Bool {
    configuration.difficulty == .normal
      && !configuration.rules.strictSpace
      && !configuration.rules.deleteOnErrorMode.returnsToPreviousWordAtStart
  }

  /// Return is a commit character, unlike the space-only leading-key guard in
  /// the reference input handler. A normal, unrestricted multiline test can
  /// therefore submit an empty line; stricter error rules retain the word.
  private var shouldCommitLeadingNewline: Bool {
    configuration.difficulty == .normal
      && !configuration.rules.strictSpace
      && configuration.rules.stopOnErrorMode == .off
      && !configuration.rules.deleteOnErrorMode.isEnabled
      && !configuration.modifiers.contains(.correctBeforeAdvance)
      && !configuration.modifiers.contains(.clearCurrentWordOnError)
  }

  /// `typed` contains every accepted word in this native engine, so either
  /// edge is an empty input buffer for the current source word.
  private var inputWordIsEmpty: Bool {
    typed.isEmpty || lastInputCommitsWord
  }

  private var lastInputCommitsWord: Bool {
    if let acceptedUnits { return acceptedUnits.lastCommits }
    if firstEmptyNoSpaceWordIndex != nil, hasNoSpaceWordSegmentation {
      return noSpaceCommittedWordIndex != nil
    }
    return typed.last.map(isPromptWordSeparator) == true
      && !retainedWordSeparatorTypedIndices.contains(typedGraphemeCount - 1)
  }

  private func retainedInputWords(omittingEmptySubsequences: Bool) -> [Substring] {
    if let acceptedUnits {
      return acceptedUnits.starts.indices.compactMap { index in
        let units = acceptedUnits.field(index, withoutCommit: true)
        if units.isEmpty && omittingEmptySubsequences { return nil }
        return Substring(String(decoding: units, as: UTF16.self))
      }
    }
    guard !retainedWordSeparatorTypedIndices.isEmpty else {
      return splitPromptWords(typed, omittingEmptySubsequences: omittingEmptySubsequences)
    }
    var words: [Substring] = []
    var start = typed.startIndex
    for (offset, index) in typed.indices.enumerated()
      where isPromptWordSeparator(typed[index]) && !retainedWordSeparatorTypedIndices.contains(offset)
    {
      if start != index || !omittingEmptySubsequences { words.append(typed[start..<index]) }
      start = typed.index(after: index)
    }
    if start != typed.endIndex || !omittingEmptySubsequences { words.append(typed[start...]) }
    return words
  }

  /// Delete-on-error hard modes also apply to a retained hidden boundary in
  /// no-space languages, where the visible input has no separator to inspect.
  private var activeDeleteOnErrorWordIsEmpty: Bool {
    activeNoSpaceWordRange.map { typed.count == $0.lowerBound } ?? inputWordIsEmpty
  }

  private var hasUncommittedSpaceDelimitedInput: Bool {
    configuration.mode != .zen
      && usesWordCommitInput
      && !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
      && !inputWordIsEmpty
  }

  private var activeInputWordUTF16Length: Int {
    if let acceptedUnits { return acceptedUnits.activeCount }
    return inputWordText().utf16.count
  }

  /// Inspect only the current field, even after an older stopped separator
  /// survives a later real commit. Whole-history splitting here turns long
  /// custom text into a quadratic scan on each separator.
  private func inputWordText(omittingLastCommit: Bool = false) -> String {
    if let acceptedUnits {
      let index = omittingLastCommit && acceptedUnits.lastCommits
        ? acceptedUnits.submittedFieldIndex : acceptedUnits.fieldIndex
      return String(decoding: acceptedUnits.field(index, withoutCommit: omittingLastCommit), as: UTF16.self)
    }
    let skipped = omittingLastCommit ? 1 : 0
    let reversed = typed.reversed().dropFirst(skipped)
    if retainedWordSeparatorTypedIndices.isEmpty {
      return String(reversed.prefix { !isPromptWordSeparator($0) }.reversed())
    }
    return String(reversed.enumerated().prefix { entry in
      !isPromptWordSeparator(entry.element)
        || retainedWordSeparatorTypedIndices.contains(typedGraphemeCount - 1 - skipped - entry.offset)
    }.map(\.element).reversed())
  }

  /// Mirrors the reference guard of the current word, including its visible
  /// commit separator when one exists, plus twenty extra UTF-16 units.
  private var currentSpaceDelimitedWordInputLimit: Int? {
    if let acceptedUnits, configuration.mode != .zen {
      return unitTargets.field(acceptedUnits.fieldIndex).count + 20
    }
    guard configuration.mode != .zen,
      usesWordCommitInput,
      !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers), !prompt.isEmpty
    else { return nil }
    let targetCharacters = promptCharacters
    let targetIndex = min(nextTargetIndex, targetCharacters.count - 1)
    let wordStart = targetCharacters[..<targetIndex].lastIndex(where: isPromptWordSeparator)
      .map { $0 + 1 } ?? 0
    let wordEnd = targetCharacters[targetIndex...].firstIndex(where: isPromptWordSeparator)
      ?? targetCharacters.count
    let endWithCommit = wordEnd < targetCharacters.count ? wordEnd + 1 : wordEnd
    let targetLength = String(targetCharacters[wordStart..<endWithCommit]).utf16.count
    return targetLength + 20
  }

  /// The reference keeps letters beyond a word's target length in that same
  /// word buffer. They are visible errors but do not advance toward the next
  /// word until the user enters its separator.
  private func shouldRetainInCurrentWord(_ character: Character, expected: Character) -> Bool {
    guard !isPromptWordSeparator(character), isPromptWordSeparator(expected),
      configuration.mode != .zen, usesWordCommitInput,
      !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
    else { return false }
    // A freshly appended chunk can still expose the closing separator of
    // the previous nonempty target after its earlier commit. That is not an
    // empty target field; only a leading/consecutive separator creates one.
    let targetIndex = nextTargetIndex
    return !inputWordIsEmpty || targetIndex == 0
      || isPromptWordSeparator(promptCharacters[targetIndex - 1])
  }

  /// The target cursor is independent from raw input length when normal
  /// typing submits an incomplete word with space. All ordinary input keeps
  /// its original one-to-one mapping, including no-space and code prompts.
  private var nextTargetIndex: Int {
    if let acceptedUnits {
      if hasOrdinarySourceFields, acceptedUnits.terminalElementCleared {
        return promptCharacters.count
      }
      return unitTargets.cursor(field: acceptedUnits.fieldIndex, position: acceptedUnits.activeCount,
        endGlyph: promptCharacters.count)
    }
    guard let previousTargetIndex = typedTargetIndices.reversed().first(where: { $0 != nil }) ?? nil
    else {
      return 0
    }
    // Converted BMP input owns a unit cursor. Before that cutover, preserve
    // legacy diagnostic mappings, except a correctly entered BMP prefix must
    // remain on its unfinished target glyph for the next mark.
    if supportsBMPUnitInput, promptCharacters.indices.contains(previousTargetIndex), !lastInputCommitsWord,
      recordsBMPUnits || (promptCharacters[previousTargetIndex].unicodeScalars.count > 1
        && promptCharacters[previousTargetIndex].unicodeScalars.allSatisfy({ $0.utf16.count == 1 })
        && latestInputCorrectness?.allSatisfy({ $0 }) == true)
    {
      let start = promptCharacters[..<previousTargetIndex].lastIndex(where: isPromptWordSeparator).map { $0 + 1 } ?? 0
      let position = activeInputWordUTF16Length
      var end = 0
      for index in start..<promptCharacters.count {
        end += String(promptCharacters[index]).utf16.count
        if position < end || isPromptWordSeparator(promptCharacters[index]) { return index }
      }
      return promptCharacters.count
    }
    return min(previousTargetIndex + 1, promptCharacters.count)
  }

  private func incompleteWordCommitTargetIndex(
    for character: Character, currentTargetIndex: Int
  ) -> Int? {
    if let acceptedUnits {
      guard isPromptWordSeparator(character),
        !inputWordIsEmpty || character == "\n" && shouldCommitLeadingNewline,
        unitTargets.fields.indices.contains(acceptedUnits.fieldIndex)
      else { return nil }
      let range = unitTargets.fields[acceptedUnits.fieldIndex]
      let position = range.lowerBound + acceptedUnits.validationCount
      guard position < range.upperBound, position < unitTargets.units.count,
        unitTargets.units[position] != 32, unitTargets.units[position] != 10
      else { return nil }
      return range.isEmpty ? nil : unitTargets.glyphs[range.upperBound - 1]
    }
    guard isPromptWordSeparator(character),
      (!inputWordIsEmpty || (character == "\n" && shouldCommitLeadingNewline)),
      usesWordCommitInput,
      !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
    else { return nil }
    let targetCharacters = promptCharacters
    guard targetCharacters.indices.contains(currentTargetIndex),
      !isPromptWordSeparator(targetCharacters[currentTargetIndex])
    else { return nil }
    // A finite final word has no following separator in its prompt. Its
    // submitted space still advances past that word, so anchor the accepted
    // key at the final target position and let the target cursor reach end.
    return targetCharacters[currentTargetIndex...].firstIndex(where: isPromptWordSeparator)
      ?? targetCharacters.index(before: targetCharacters.endIndex)
  }

  private mutating func appendTypedCharacter(
    _ character: Character, targetIndex: Int?, forceError: Bool = false,
    countsAsExtraError: Bool = false, at date: Date
  ) {
    if acceptedUnits != nil {
      appendAcceptedUnit(character, targetIndex: targetIndex, forceError: forceError,
        countsAsExtraError: countsAsExtraError, at: date)
      return
    }
    let typedIndex = typedGraphemeCount
    let previous = typed.last
    let joinsBMP = supportsBMPUnitInput && (!character.isASCII || previous?.isASCII == false) && previous.map {
      $0.unicodeScalars.allSatisfy({ $0.utf16.count == 1 })
        && character.unicodeScalars.allSatisfy({ $0.utf16.count == 1 })
        && String([$0, character]).count == 1 && !isPromptWordSeparator($0)
        && $0 != "\r" && character != "\n"
    } == true
    let joinsPreviousGrapheme = joinsBMP || (previous == "\r" && character == "\n")
    if joinsBMP {
      recordsBMPUnits = true
      let index = typedIndex - 1
      let oldTarget = typedTargetIndices[index]
      var parts = joinedBMPInputParts[index] ?? [.init(targetIndex: oldTarget,
        forced: oldTarget.map { forcedErrorIndices.contains($0) } ?? false,
        extra: extraErrorTypedIndices.contains(index))]
      parts.append(.init(targetIndex: targetIndex, forced: forceError, extra: countsAsExtraError))
      joinedBMPInputParts[index] = parts
    }
    if isPromptWordSeparator(character), !joinsPreviousGrapheme,
      !retainedWordSeparatorTypedIndices.contains(typedIndex)
    { replayCommittedSeparatorCount += 1 }
    if !character.isASCII || joinsPreviousGrapheme {
      canUseCachedWordProgress = false
    }
    if let targetIndex,
      let previousTargetIndex = typedTargetIndices.reversed().first(where: { $0 != nil }) ?? nil,
      targetIndex <= previousTargetIndex
    {
      canUseCachedWordProgress = false
    }
    if canUseCachedWordProgress, let targetIndex,
      promptCharacters.indices.contains(targetIndex),
      isPromptWordSeparator(promptCharacters[targetIndex]),
      isPromptWordSeparator(character)
    {
      cachedCommittedWordCount += 1
    }
    typed.append(character)
    if !character.isASCII || joinsPreviousGrapheme {
      typedGraphemeCount = typed.count
    } else {
      typedGraphemeCount += 1
    }
    if !character.isASCII || joinsPreviousGrapheme { typedNeedsFullSegmentation = true }
    if joinsBMP {
      typedTargetIndices[typedIndex - 1] = targetIndex ?? typedTargetIndices[typedIndex - 1]
    } else {
      typedTargetIndices.append(targetIndex)
      typedCharacterDates.append(date)
    }
    if forceError, let targetIndex { forcedErrorIndices.insert(targetIndex) }
    if countsAsExtraError { extraErrorTypedIndices.insert(joinsBMP ? typedIndex - 1 : typedIndex) }
  }

  private mutating func beginUnitInput() {
    unitTargets = UnitInputTargets(prompt, buildsASCIICatalog: true,
      noSpaceWords: TestModifierPolicy.usesNoSpaceInput(configuration.modifiers) ? noSpaceTargetWords : nil)
    var buffer = AcceptedUnitInput()
    for (index, character) in typed.enumerated() {
      let target = typedTargetIndices[index]
      let units = Array(String(character).utf16)
      for (part, unit) in units.enumerated() {
        buffer.append(.init(unit: unit, target: target, date: typedCharacterDates[index],
          forced: target.map { forcedErrorIndices.contains($0) } ?? false,
          extra: extraErrorTypedIndices.contains(index),
          commits: part == units.count - 1 && isPromptWordSeparator(character)
            && !retainedWordSeparatorTypedIndices.contains(index)))
      }
    }
    acceptedUnits = buffer
    recordsBMPUnits = true
    canUseCachedWordProgress = false
  }

  /// Re-segment the changed tail, not the entire growing history. The two
  /// previous glyphs include a pending surrogate plus its joinable neighbor.
  private mutating func projectUnitTail(oldTail: String, unitStart: Int) {
    let oldCount = oldTail.count
    let glyphStart = typedGraphemeCount - oldCount
    typed.removeLast(oldCount)
    let entries = acceptedUnits!.entries[unitStart...]
    let tail = String(decoding: entries.map(\.unit), as: UTF16.self)
    typed.append(tail)
    typedTargetIndices.removeLast(oldCount)
    typedCharacterDates.removeLast(oldCount)
    extraErrorTypedIndices = extraErrorTypedIndices.filter { $0 < glyphStart }
    retainedWordSeparatorTypedIndices = retainedWordSeparatorTypedIndices.filter { $0 < glyphStart }
    var offset = unitStart
    for (part, character) in tail.enumerated() {
      let length = String(character).utf16.count
      let pieces = acceptedUnits!.entries[offset..<(offset + length)]
      typedTargetIndices.append(pieces.reversed().first(where: { $0.target != nil })?.target)
      typedCharacterDates.append(pieces.first!.date)
      if pieces.contains(where: \.extra) { extraErrorTypedIndices.insert(glyphStart + part) }
      if pieces.contains(where: { ($0.unit == 32 || $0.unit == 10) && !$0.commits }) {
        retainedWordSeparatorTypedIndices.insert(glyphStart + part)
      }
      offset += length
    }
    typedGraphemeCount = glyphStart + tail.count
    typedNeedsFullSegmentation = true
    replayCommittedSeparatorCount = acceptedUnits!.fieldIndex
  }

  private mutating func appendAcceptedUnit(
    _ character: Character, targetIndex: Int?, forceError: Bool,
    countsAsExtraError: Bool, at date: Date
  ) {
    let unit = currentInputUnit ?? String(character).utf16.first!
    let commits = unitTargets.noSpace ? shouldCommitNoSpaceUnit(unit) : nil
    discardTerminalElementIfNeeded()
    let oldTail = String(typed.suffix(2))
    let start = acceptedUnits!.entries.count - oldTail.utf16.count
    let retained = retainedWordSeparatorTypedIndices.contains(typedGraphemeCount)
    let advances = !(unitTargets.noSpace || hasOrdinarySourceFields && unit == 32)
      || acceptedUnits!.fieldIndex < unitTargets.fields.count - 1
      || usesIncrementalPromptExtension
    acceptedUnits!.append(.init(unit: unit, target: targetIndex, date: date,
      forced: forceError, extra: countsAsExtraError,
      commits: commits ?? ((unit == 32 || unit == 10) && !retained)),
      advances: advances)
    if forceError, let targetIndex { forcedErrorIndices.insert(targetIndex) }
    projectUnitTail(oldTail: oldTail, unitStart: start)
  }

  private func shouldCommitNoSpaceUnit(_ unit: UInt16) -> Bool {
    guard let acceptedUnits, unitTargets.fields.indices.contains(acceptedUnits.fieldIndex) else { return false }
    let target = unitTargets.field(acceptedUnits.fieldIndex)
    let attempted = latestNoSpaceAttempt ?? acceptedUnits.field(acceptedUnits.fieldIndex) + [unit]
    guard unit == 10 || attempted.count == target.count else { return false }
    if unit == 10, attempted.count == 1,
      configuration.rules.strictSpace || configuration.difficulty != .normal { return false }
    if configuration.rules.stopOnErrorMode != .off || configuration.rules.deleteOnErrorMode.isEnabled
      || configuration.modifiers.contains(.correctBeforeAdvance)
    { return attempted == target }
    return true
  }

  private mutating func discardTerminalElementIfNeeded(retainsHistory: Bool = false) {
    guard let buffer = acceptedUnits, buffer.terminalElementCleared else { return }
    let range = buffer.range(buffer.fieldIndex)
    let oldTail = String(typed.suffix(min(typedGraphemeCount, range.count + 2)))
    let start = buffer.entries.count - oldTail.utf16.count
    let forced = Set(buffer.entries[range].compactMap { $0.forced ? $0.target : nil })
    let count = acceptedUnits!.discardClearedTerminalField(retainsHistory: retainsHistory)
    for target in forced where !acceptedUnits!.entries.contains(where: { $0.target == target && $0.forced }) {
      forcedErrorIndices.remove(target)
    }
    if count > 0 { latestReplayDiscardedUnits = (latestReplayDiscardedUnits ?? 0) + count }
    projectUnitTail(oldTail: oldTail, unitStart: start)
  }

  private mutating func removeAcceptedUnit() {
    if acceptedUnits?.terminalElementCleared == true {
      latestReplayClearedNextWord = !applyingAutomaticCodeInput
      discardTerminalElementIfNeeded(retainsHistory: true)
    }
    guard !acceptedUnits!.entries.isEmpty else { return }
    let oldTail = String(typed.suffix(2))
    let start = acceptedUnits!.entries.count - oldTail.utf16.count
    let removed = acceptedUnits!.removeLast()!
    if removed.forced, let target = removed.target,
      !acceptedUnits!.entries.contains(where: { $0.target == target && $0.forced })
    { forcedErrorIndices.remove(target) }
    if removed.commits, let target = removed.target {
      let start = promptCharacters[..<target].lastIndex(where: isPromptWordSeparator).map { $0 + 1 } ?? 0
      committedErrorWordStarts.remove(start)
      for index in start..<target { blindCommittedMissingTargetIndices.remove(index) }
    }
    lastDeletionWasBMPUnit = true
    projectUnitTail(oldTail: oldTail, unitStart: start)
  }

  private mutating func removeLastTypedCharacter() {
    if acceptedUnits != nil { removeAcceptedUnit(); return }
    lastDeletionWasBMPUnit = false
    guard !typed.isEmpty else { return }
    let typedIndex = typedGraphemeCount - 1
    if var parts = joinedBMPInputParts[typedIndex], parts.count > 1 {
      let removed = parts.removeLast()
      typed.unicodeScalars.removeLast()
      lastDeletionWasBMPUnit = true
      recordsBMPUnits = true
      joinedBMPInputParts[typedIndex] = parts.count > 1 ? parts : nil
      typedTargetIndices[typedIndex] = parts.last?.targetIndex
      if let target = removed.targetIndex, !parts.contains(where: { $0.targetIndex == target && $0.forced }) {
        forcedErrorIndices.remove(target)
      }
      if !parts.contains(where: \.extra) { extraErrorTypedIndices.remove(typedIndex) }
      return
    }
    joinedBMPInputParts.removeValue(forKey: typedIndex)
    if typed.last.map(isPromptWordSeparator) == true,
      !retainedWordSeparatorTypedIndices.contains(typedIndex)
    { replayCommittedSeparatorCount = max(0, replayCommittedSeparatorCount - 1) }
    retainedWordSeparatorTypedIndices.remove(typedIndex)
    let removedCharacter = typed.last
    let targetIndex = typedTargetIndices.popLast() ?? nil
    if !blindCommittedMissingTargetIndices.isEmpty || !committedErrorWordStarts.isEmpty,
      removedCharacter.map(isPromptWordSeparator) == true, let targetIndex,
      promptCharacters.indices.contains(targetIndex)
    {
      let start = promptCharacters[..<targetIndex].lastIndex(where: isPromptWordSeparator)
        .map { $0 + 1 } ?? 0
      let end = isPromptWordSeparator(promptCharacters[targetIndex]) ? targetIndex : targetIndex + 1
      for index in start..<end { blindCommittedMissingTargetIndices.remove(index) }
      committedErrorWordStarts.remove(start)
    }
    if tracksNoSpaceWordBursts, let targetIndex,
      let word = noSpaceWordEndIndices.firstIndex(of: targetIndex + 1),
      let range = noSpaceWordRange(for: word)
    { committedErrorWordStarts.remove(range.lowerBound) }
    if canUseCachedWordProgress, let targetIndex,
      promptCharacters.indices.contains(targetIndex),
      isPromptWordSeparator(promptCharacters[targetIndex]),
      removedCharacter.map(isPromptWordSeparator) == true
    {
      cachedCommittedWordCount -= 1
    }
    typed.removeLast()
    typedGraphemeCount = typedNeedsFullSegmentation ? typed.count : typedGraphemeCount - 1
    typedCharacterDates.removeLast()
    if let targetIndex { forcedErrorIndices.remove(targetIndex) }
    extraErrorTypedIndices.remove(typedIndex)
  }

  private func shouldBlockNoSpaceWordAdvance(with character: Character, forceError: Bool) -> Bool {
    guard tracksNoSpaceWordBursts,
      let wordIndex = nextNoSpaceCommittedWordIndex,
      let range = noSpaceWordRange(for: wordIndex)
    else { return false }

    let promptCharacters = self.promptCharacters
    guard typedGraphemeCount == range.upperBound - 1, range.upperBound <= promptCharacters.count else { return false }
    return range.contains { index in
      if index == typedGraphemeCount {
        return !InputTextIdentity.matches(character, promptCharacters[index]) || forceError
      }
      return !isTypedCharacterCorrect(at: index)
    }
  }

  /// Difficulty judges the attempted commit even when stopped or recovered.
  /// Expert compares the complete field, not the Shift correctness flag.
  private func shouldFailExpertOnAttemptedInput(_ character: Character) -> Bool {
    guard configuration.difficulty == .expert else { return false }
    if unitTargets.noSpace, let acceptedUnits {
      let unit = currentInputUnit ?? String(character).utf16.first!
      let target = unitTargets.field(acceptedUnits.fieldIndex)
      let attempted = latestNoSpaceAttempt ?? acceptedUnits.field(acceptedUnits.fieldIndex) + [unit]
      if unit == 10, attempted.count == 1 { return false }
      return (unit == 10 || attempted.count == target.count) && attempted != target
    }
    if tracksNoSpaceWordBursts, let range = activeNoSpaceWordRange,
      range.upperBound <= promptCharacters.count
    {
      let attempted = String(typed.suffix(max(0, typedGraphemeCount - range.lowerBound))) + String(character)
      let target = String(promptCharacters[range])
      return attempted.utf16.count == target.utf16.count && !InputTextIdentity.matches(attempted, target)
    }
    guard isPromptWordSeparator(character), !inputWordIsEmpty else { return false }
    return !currentWordIsCorrect || nextTargetIndex >= promptCharacters.count
      || !InputTextIdentity.matches(character, promptCharacters[nextTargetIndex])
  }

  private func noSpaceWordRange(for wordIndex: Int) -> Range<Int>? {
    guard noSpaceWordEndIndices.indices.contains(wordIndex) else { return nil }
    let start = wordIndex == 0 ? 0 : noSpaceWordEndIndices[wordIndex - 1]
    let end = noSpaceWordEndIndices[wordIndex]
    guard start <= end else { return nil }
    return start..<end
  }

  /// Expert difficulty evaluates a no-space word on its final visible
  /// character, the same logical point at which the reference product moves
  /// to its next retained word. Use the accepted text and forced physical
  /// input errors rather than historical attempts: a corrected word is valid.
  private var committedNoSpaceWordHasError: Bool {
    if unitTargets.noSpace, let acceptedUnits, acceptedUnits.lastCommits {
      let index = acceptedUnits.submittedFieldIndex
      return acceptedUnits.field(index) != unitTargets.field(index)
    }
    guard let wordIndex = noSpaceCommittedWordIndex,
      let range = noSpaceWordRange(for: wordIndex)
    else { return false }
    return range.contains { !isTypedCharacterCorrect(at: $0) }
  }

  private var lastCommittedWordIsCorrect: Bool {
    if let acceptedUnits { return acceptedUnits.lastCommits && currentWordIsCorrect }
    guard lastInputCommitsWord else { return false }
    let committedWords = retainedInputWords(omittingEmptySubsequences: true)
    let targetWords = splitPromptWords(prompt, omittingEmptySubsequences: true)
    guard let submitted = committedWords.last, committedWords.count <= targetWords.count else {
      return false
    }
    return InputTextIdentity.matches(submitted, targetWords[committedWords.count - 1])
      && !hasForcedError(inWord: committedWords.count - 1)
  }

  private func isTypedCharacterCorrect(at index: Int) -> Bool {
    let typedCharacters = Array(typed)
    let targetCharacters = promptCharacters
    guard targetCharacters.indices.contains(index),
      let typedIndex = typedTargetIndices.firstIndex(where: { $0 == index }),
      typedCharacters.indices.contains(typedIndex)
    else { return false }
    return InputTextIdentity.matches(typedCharacters[typedIndex], targetCharacters[index])
      && !forcedErrorIndices.contains(index)
  }

  private var codeInputFieldText: String {
    if let range = activeNoSpaceWordRange {
      return String(typed.suffix(max(0, typedGraphemeCount - range.lowerBound)))
    }
    return inputWordText()
  }

  private var codeTargetFieldText: String {
    if unitTargets.noSpace, let acceptedUnits {
      return String(decoding: unitTargets.field(acceptedUnits.fieldIndex), as: UTF16.self)
    }
    if let range = activeNoSpaceWordRange {
      guard range.upperBound <= promptCharacters.count else { return "" }
      return String(promptCharacters[range])
    }
    // Never infer hidden word boundaries from flattened no-space text.
    guard !tracksNoSpaceWordBursts else { return "" }
    let inputStart = typedGraphemeCount - codeInputFieldText.count
    let anchor = typedTargetIndices.indices.contains(inputStart)
      ? typedTargetIndices[inputStart] ?? nextTargetIndex : nextTargetIndex
    guard promptCharacters.indices.contains(anchor) else { return "" }
    let start = promptCharacters[..<anchor].lastIndex(where: isPromptWordSeparator)
      .map { $0 + 1 } ?? 0
    let end = promptCharacters[anchor...].firstIndex(where: isPromptWordSeparator)
      ?? promptCharacters.count
    return String(promptCharacters[start..<end])
  }

  private mutating func insertCodeIndentationIfNeeded(at date: Date) {
    // Correctness belongs to the attempted key, not its remapped commit
    // cursor: an early space can navigate without being a correct insert.
    guard configuration.language.isCodeLanguage, lastInputWasCorrect == true else { return }
    let target = Array(codeTargetFieldText.utf16)
    let offset = codeInputFieldText.utf16.count
    guard target.first == 9, target.indices.contains(offset), target[offset] == 9 else { return }
    queuedCodeInputDates.append(date)
  }

  private mutating func removeCodeIndentationBeforeField(
    at date: Date, deletesWholeIndent: Bool = false
  ) -> Bool {
    let field = codeInputFieldText
    guard !field.isEmpty, field.allSatisfy({ $0 == "\t" }) else { return false }
    let remainingTabs = deletesWholeIndent ? 0 : field.count - 1
    let prefix = codeTargetFieldText.prefix(remainingTabs)
    // The reference checks the indentation after the browser has removed
    // the requested input. A word deletion leaves an empty indentation,
    // while ordinary Backspace leaves all tabs except the final one.
    guard prefix.count == remainingTabs, prefix.allSatisfy({ $0 == "\t" })
    else { return false }
    let deletionStart = replayEvents.count
    let previousField = replayInputField(kind: .delete, inputStopped: false)
    for _ in field {
      removeLastTypedCharacter()
      recordReplayEvent(kind: .delete, text: "", at: date)
    }
    markDeletion(since: deletionStart)
    recordDeletionPosition(since: deletionStart, previousField: previousField)
    let navigationStart = replayEvents.count
    removePreviousWordForHardDelete(clearingWord: deletesWholeIndent, at: date)
    if replayEvents.count == navigationStart {
      // At the first field, the source still logs a destination character
      // action after clearing tabs. The tape is already empty: this is a
      // no-op, not a fabricated removal of an earlier word.
      recordReplayEvent(kind: .delete, text: "", at: date)
    }
    markDeletion(since: navigationStart, wholeWord: false)
    recordDeletionPosition(since: navigationStart, previousField: previousField,
      usesDestinationPosition: true)
    return true
  }

  private func hasForcedError(inWord word: Int) -> Bool {
    hasError(inWord: word, indices: forcedErrorIndices)
  }

  /// Word targets for result history and local follow-up practice. A flattened
  /// prompt is eligible only when its saved word slices still exactly match
  /// the current boundary list; otherwise there is no trustworthy word-level
  /// representation to expose.
  private var resultTargetWords: [String] {
    if unitTargets.noSpace || hasNoSpaceWordSegmentation { return noSpaceTargetWords }
    guard usesWordCommitInput,
      !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
    else { return [] }
    return splitPromptWords(prompt, omittingEmptySubsequences: false).map(String.init)
  }

  private var capturedTargetWordDirectory: ResultTargetWordDirectory? {
    guard TestModifierPolicy.usesNoSpaceInput(configuration.modifiers) else { return nil }
    let directory = ResultTargetWordDirectory(words: noSpaceTargetWords, noSpace: true)
    return directory.matches(prompt: prompt, noSpace: true) ? directory : nil
  }

  private var noSpaceWordRanges: [Range<Int>] {
    guard hasNoSpaceWordSegmentation else { return [] }
    var start = 0
    return noSpaceWordEndIndices.map { end in
      defer { start = end }
      return start..<end
    }
  }

  private var hasNoSpaceWordSegmentation: Bool {
    tracksNoSpaceWordBursts
      && noSpaceTargetWords.count == noSpaceWordEndIndices.count
  }

  private var emptyNoSpaceWordBoundary: Int? {
    guard hasNoSpaceWordSegmentation, let firstEmptyNoSpaceWordIndex else { return nil }
    return noSpaceWordEndIndices[firstEmptyNoSpaceWordIndex]
  }

  private var isAtEmptyNoSpaceWord: Bool {
    if unitTargets.noSpace {
      let index = acceptedUnits?.fieldIndex ?? 0
      return unitTargets.fields.indices.contains(index) && unitTargets.fields[index].isEmpty
    }
    guard let boundary = emptyNoSpaceWordBoundary else { return false }
    return nextTargetIndex == boundary
  }

  private func noSpaceWordReviews(
    targetWords: [String], attemptedErrors: [Int]
  ) -> [TypedWordReview] {
    let typedCharacters = Array(typed)
    let directlyAttemptedCount = noSpaceWordRanges.lastIndex {
      typedCharacters.count > $0.lowerBound
    }.map { $0 + 1 } ?? 0
    let historicalAttemptedCount = attemptedErrors.indices.last(where: { attemptedErrors[$0] > 0 })
      .map { $0 + 1 } ?? 0
    let attemptedCount = min(max(directlyAttemptedCount, historicalAttemptedCount),
      firstEmptyNoSpaceWordIndex.map { $0 + 1 } ?? targetWords.count)
    return (0..<min(attemptedCount, targetWords.count)).map { index in
      let range = noSpaceWordRanges[index]
      let typedEnd = index == firstEmptyNoSpaceWordIndex
        ? typedCharacters.count : min(range.upperBound, typedCharacters.count)
      let typedWord = typedEnd > range.lowerBound
        ? String(typedCharacters[range.lowerBound..<typedEnd]) : ""
      return .init(
        index: index, target: targetWords[index], typed: typedWord,
        hasInputError: InputTextIdentity.matches(typedWord, targetWords[index])
          && attemptedErrors[index] > 0)
    }
  }

  /// Assign each target position to its result word once, then aggregate the
  /// sparse historical errors without rescanning the entire prompt per word.
  private func attemptedInputErrorCountsByWord(targetWordCount: Int) -> [Int] {
    var counts = Array(repeating: 0, count: targetWordCount)
    if unitTargets.noSpace {
      for (index, count) in noSpaceUnitAttemptErrors where counts.indices.contains(index) { counts[index] = count }
      return counts
    }
    guard !attemptedErrorCounts.isEmpty else { return counts }

    let targetCharacters = promptCharacters
    var wordByTargetIndex = Array(repeating: -1, count: targetCharacters.count)
    if hasNoSpaceWordSegmentation {
      var start = 0
      for (word, end) in noSpaceWordEndIndices.prefix(targetWordCount).enumerated() {
        let safeEnd = min(max(end, start), targetCharacters.count)
        if start < safeEnd {
          for index in start..<safeEnd { wordByTargetIndex[index] = word }
        }
        start = safeEnd
      }
    } else {
      var word = 0
      for index in targetCharacters.indices {
        if word < targetWordCount { wordByTargetIndex[index] = word }
        if isPromptWordSeparator(targetCharacters[index]) { word += 1 }
      }
    }
    for (index, count) in attemptedErrorCounts {
      if index == emptyNoSpaceWordBoundary, let firstEmptyNoSpaceWordIndex {
        counts[firstEmptyNoSpaceWordIndex] += count
        continue
      }
      guard wordByTargetIndex.indices.contains(index) else { continue }
      let word = wordByTargetIndex[index]
      if counts.indices.contains(word) { counts[word] += count }
    }
    return counts
  }

  private func hasError(inWord word: Int, indices: Set<Int>) -> Bool {
    guard let range = targetRange(forWord: word) else { return false }
    return indices.contains(where: range.contains)
  }

  private func attemptedInputErrorCount(in range: Range<Int>) -> Int {
    attemptedErrorCounts.reduce(into: 0) { total, error in
      if range.contains(error.key) { total += error.value }
    }
  }

  private func targetRange(forWord word: Int) -> Range<Int>? {
    guard word >= 0 else { return nil }
    if hasNoSpaceWordSegmentation {
      guard noSpaceWordRanges.indices.contains(word) else { return nil }
      return noSpaceWordRanges[word]
    }
    let targetCharacters = promptCharacters
    var currentWord = 0
    var start = 0
    for index in targetCharacters.indices {
      if isPromptWordSeparator(targetCharacters[index]) {
        if currentWord == word {
          return start..<(index + 1)
        }
        currentWord += 1
        start = index + 1
      }
    }
    return currentWord == word ? start..<targetCharacters.count : nil
  }

  private func wpm(characters: Int, seconds: TimeInterval) -> Int {
    Int(wpmValue(characters: characters, seconds: seconds).rounded())
  }

  private func wpmValue(characters: Int, seconds: TimeInterval) -> Double {
    guard seconds.isFinite, seconds > 0 else { return 0 }
    return Double(characters) / 5 / seconds * 60
  }

  private mutating func finishIfNeeded(at date: Date) {
    guard !isFinished, !isAtEmptyNoSpaceWord else { return }
    if unitTargets.noSpace {
      // Navigation may extend the catalog. Completion compares the captured
      // input field against that post-navigation catalog, unlike `lastWord`
      // in the event, which describes the pre-navigation catalog. Repeating
      // external previews may oversupply it: honor the finite word budget.
      let wordBudget = configuration.mode == .words
        || configuration.mode == .custom && configuration.customTextCompletion == .words
          && customSectionWordStream == nil ? configuration.wordLimit : nil
      let finalFieldCount = wordBudget.flatMap { $0 > 0 ? min($0, unitTargets.fields.count) : nil }
        ?? unitTargets.fields.count
      guard latestNoSpaceFinishDecision, let attemptedField = latestNoSpaceAttemptFieldIndex,
        attemptedField >= finalFieldCount - 1 else { return }
      switch configuration.mode {
      case .time, .zen: return
      case .words:
        if reachedConfiguredWordLimit || !usesIncrementalPromptExtension { complete(at: date) }
      case .custom:
        guard configuration.customTextCompletion != .time, !configuration.isInfinite else { return }
        if !usesIncrementalPromptExtension || configuration.customTextCompletion == .words
          && customSectionWordStream == nil && reachedConfiguredWordLimit { complete(at: date) }
      case .quote:
        if !usesIncrementalPromptExtension { complete(at: date) }
      }
      return
    }
    switch configuration.mode {
    case .words:
      if hasNoSpaceWordSegmentation || !usesWordCommitInput
        || TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
      {
        if reachedConfiguredWordLimit
          || noSpaceTerminalFieldMatches
          || (!usesIncrementalPromptExtension && reachedInputTargetEnd)
        {
          complete(at: date)
        }
      } else if shouldFinishEnglishWordsTest {
        complete(at: date)
      }
    case .quote:
      if !usesIncrementalPromptExtension, shouldFinishFiniteSpaceDelimitedTest { complete(at: date) }
    case .custom:
      switch configuration.customTextCompletion {
      case .finish:
        if !usesIncrementalPromptExtension
          && ((!unitTargets.noSpace && (acceptedUnits.map { $0.units == unitTargets.units }
            ?? InputTextIdentity.matches(typed, prompt))) || shouldFinishFiniteSpaceDelimitedTest)
        {
          complete(at: date)
        }
      case .time:
        break
      case .words:
        if customSectionWordStream != nil {
          // Pipe initialization can prefetch whole sections past wordLimit;
          // non-pipe initialization includes newline-only candidate words.
          // Match the generated queue, not an earlier configured word index;
          // a partial batch must still continue before final-word rules apply.
          if !configuration.isInfinite, !usesIncrementalPromptExtension,
            shouldFinishFiniteSpaceDelimitedTest { complete(at: date) }
        } else if tracksNoSpaceWordBursts {
          if reachedConfiguredWordLimit || noSpaceTerminalFieldMatches { complete(at: date) }
        } else if shouldFinishEnglishWordsTest {
          complete(at: date)
        }
      case .sections:
        if !usesIncrementalPromptExtension && shouldFinishFiniteSpaceDelimitedTest { complete(at: date) }
      }
    case .time, .zen:
      break
    }
  }

  private mutating func extendPromptIfNeeded(at date: Date) {
    guard !isAtEmptyNoSpaceWord, reachedInputTargetEnd else { return }
    if quoteWordStream?.hasRemaining == true {
      refillQuoteIfNeeded(activeWordBefore: max(0, quoteNavigationIndex - 1), at: date)
      return
    }
    if var stream = customSectionWordStream, stream.hasRemaining {
      let chunk = stream.nextChunk()
      customSectionWordStream = stream
      let previousEnd = promptCharacters.count
      appendPrompt(chunk.text)
      if configuration.customTextCompletion == .sections {
        sectionEndIndices += chunk.sectionEndOffsets.map { previousEnd + $0 }
        noSpaceSectionWordEnds += chunk.sectionWordEnds
      }
      if TestModifierPolicy.usesNoSpaceInput(configuration.modifiers) {
        var end = previousEnd
        for length in chunk.noSpaceWordLengths {
          end += length
          noSpaceWordEndIndices.append(end)
        }
        noSpaceTargetWords += chunk.noSpaceTargetWords
      }
      return
    }
    if var stream = finiteCustomTextStream, stream.hasRemaining {
      let source = stream.nextChunk()
      finiteCustomTextStream = stream
      let chunk = GeneratedWordChunk(source: source, configuration: configuration,
        wordOffset: noSpaceTargetWords.count)
      let batch = TransformedPromptBatch(text: chunk.transformed, noSpaceTargetWords: chunk.noSpaceTargetWords)
      let prepared = stream.hasRemaining ? batch : FinitePromptCommitPolicy.finalized(batch)
      let previousEnd = promptCharacters.count
      appendPrompt(prepared.text)
      if TestModifierPolicy.usesNoSpaceInput(configuration.modifiers) {
        var end = previousEnd
        for length in prepared.noSpaceWordLengths {
          end += length
          noSpaceWordEndIndices.append(end)
        }
        noSpaceTargetWords += prepared.noSpaceTargetWords
      }
      return
    }
    if let randomCustomSourceTokens, !randomCustomSourceTokens.isEmpty {
      let words = CustomTextOrderPolicy.randomWords(
        from: randomCustomSourceTokens,
        count: CustomTextOrderPolicy.maximumCompleteRandomWordCount,
        avoiding: randomCustomPreviousWords,
        lazyLanguage: configuration.modifiers.contains(.lazyLatin)
          ? configuration.language : nil,
        reversesCandidatePool: configuration.modifiers.contains(.backwards))
      randomCustomPreviousWords = Array(words.suffix(2))
      let source = words.joined(separator: " ")
      let chunk = GeneratedWordChunk(source: source, configuration: configuration,
        wordOffset: noSpaceTargetWords.count, preservesWordOrder: true)
      let usesNoSpaceSeparator = TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
      let separator = usesNoSpaceSeparator || prompt.last?.isWhitespace == true ? "" : " "
      let previousEnd = promptCharacters.count + separator.count
      appendPrompt(separator + chunk.transformed)
      if usesNoSpaceSeparator {
        var end = previousEnd
        for length in chunk.noSpaceWordLengths {
          end += length
          noSpaceWordEndIndices.append(end)
        }
        noSpaceTargetWords += chunk.noSpaceTargetWords
      }
      return
    }
    if var stream = sequentialCustomWordStream {
      let source = stream.nextWords(count: 100)
      sequentialCustomWordStream = stream
      let chunk = GeneratedWordChunk(source: source, configuration: configuration,
        wordOffset: noSpaceTargetWords.count, preservesWordOrder: true)
      let previousEnd = promptCharacters.count
      appendPrompt(chunk.transformed)
      if TestModifierPolicy.usesNoSpaceInput(configuration.modifiers) {
        var end = previousEnd
        for length in chunk.noSpaceWordLengths {
          end += length
          noSpaceWordEndIndices.append(end)
        }
        noSpaceTargetWords += chunk.noSpaceTargetWords
      }
      return
    }
    var generatedChunk: GeneratedWordChunk?
    if var continuation = generatedWordContinuation {
      generatedChunk = continuation.nextChunk()
      generatedWordContinuation = continuation
    } else if var continuation = generatedStreamContinuation {
      generatedChunk = continuation.nextChunk()
      generatedStreamContinuation = continuation
    } else if var continuation = generatedCodeContinuation {
      generatedChunk = continuation.nextChunk()
      generatedCodeContinuation = continuation
    }
    if let chunk = generatedChunk {
      let usesNoSpaceSeparator = TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
      let separator = usesNoSpaceSeparator || prompt.last?.isWhitespace == true
        || generatedCodeContinuation != nil ? "" : " "
      let previousEnd = promptCharacters.count + separator.count
      appendPrompt(separator + chunk.transformed)
      if usesNoSpaceSeparator {
        var end = previousEnd
        for length in chunk.noSpaceWordLengths {
          end += length
          noSpaceWordEndIndices.append(end)
        }
        noSpaceTargetWords += chunk.noSpaceTargetWords
      }
      return
    }
    guard let repeatingPrompt, !repeatingPrompt.isEmpty else { return }
    let usesNoSpaceSeparator = TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
    let separator = usesNoSpaceSeparator || prompt.last?.isWhitespace == true ? "" : " "
    let previousEnd = promptCharacters.count + separator.count
    appendPrompt(separator + repeatingPrompt)
    guard usesNoSpaceSeparator else { return }
    var end = previousEnd
    for length in repeatingNoSpaceWordLengths {
      end += length
      noSpaceWordEndIndices.append(end)
    }
    guard !repeatingNoSpaceTargetWords.isEmpty,
      repeatingNoSpaceTargetWords.joined().utf16.elementsEqual(repeatingPrompt.utf16)
    else { return }
    noSpaceTargetWords += repeatingNoSpaceTargetWords
  }

  private var quoteNavigationIndex: Int {
    if tracksNoSpaceWordBursts { return completedWordCount }
    return canUseCachedWordProgress ? cachedCommittedWordCount : scannedCommittedWordCount
  }

  private mutating func refillQuoteIfNeeded(activeWordBefore: Int, at date: Date) {
    guard !isFinished, !isAtEmptyNoSpaceWord, var stream = quoteWordStream, stream.hasRemaining else { return }
    if TestModifierPolicy.usesNoSpaceInput(configuration.modifiers), !unitTargets.noSpace, !hasNoSpaceWordSegmentation {
      // An unsafe grapheme boundary has no usable word-navigation count.
      // Consume the actual visible prefix before requesting its next target;
      // comparing a fabricated zero word index would permanently stall it.
      guard nextTargetIndex >= promptCharacters.count else { return }
    } else {
      guard stream.emittedWords - (activeWordBefore + 1) <= stream.lookaheadBound else { return }
    }
    do {
      let previousEnd = promptCharacters.count
      let hadTargets = noSpaceTargetWords.count == stream.emittedWords
      let chunk = try stream.nextWord()
      quoteWordStream = stream
      appendPrompt(chunk.text)
      if TestModifierPolicy.usesNoSpaceInput(configuration.modifiers) {
        if hadTargets,
          chunk.noSpaceTargetWords.count == 1 {
          if noSpaceWordEndIndices.count == noSpaceTargetWords.count,
            let lastWord = noSpaceTargetWords.last,
            TransformedPromptBatch(text: lastWord + chunk.text,
              noSpaceTargetWords: [lastWord, chunk.text]).noSpaceWordLengths.count == 2,
            promptCharacters.count == previousEnd + chunk.text.count {
            noSpaceWordEndIndices += chunk.noSpaceWordLengths.map { previousEnd + $0 }
          } else {
            noSpaceWordEndIndices = []
          }
          noSpaceTargetWords += chunk.noSpaceTargetWords
        } else {
          // Incomplete actual target metadata is not a recoverable catalog.
          noSpaceWordEndIndices = []
          noSpaceTargetWords = []
          firstEmptyNoSpaceWordIndex = nil
        }
      }
    } catch {
      generationNotice = "无法生成引语的下一个词，练习已停止。请选择另一条引语或切换拼写设置。"
      fail(at: date, reason: .wordGeneration)
    }
  }

  private mutating func appendPrompt(_ chunk: String) {
    let startsWithSeparator = chunk.first.map(isPromptWordSeparator) == true
      && !(prompt.last == "\r" && chunk.first == "\n")
    let followsStableSeparator: Bool
    if let previous = promptCharacters.last, isPromptWordSeparator(previous), let first = chunk.first {
      followsStableSeparator = String([previous, first]).count == 2
    } else {
      followsStableSeparator = false
    }
    let previousCount = promptCharacters.count
    // The prompt's only post-initialization mutation appends a chunk. Count
    // its literal separators once, not the entire growing ASCII prompt.
    promptSeparatorUnitCount += chunk.utf8.reduce(into: 0) { count, unit in
      if unit == 32 || unit == 10 { count += 1 }
    }
    prompt += chunk
    if startsWithSeparator || followsStableSeparator {
      // An explicit word separator breaks the grapheme boundary with the
      // previous chunk. Only the new characters need word-boundary scanning.
      var afterSeparator = true
      for (offset, character) in chunk.enumerated() {
        promptCharacters.append(character)
        if isPromptWordSeparator(character) {
          afterSeparator = true
        } else if afterSeparator {
          promptWordCount += 1
          if promptWordCount == configuration.wordLimit {
            requiredWordStartIndex = previousCount + offset
          }
          afterSeparator = false
        }
      }
      return
    }
    // A chunk may begin with a combining scalar that joins the final
    // Character of the existing prompt; re-segment and rescan in that case.
    canUseCachedWordProgress = false
    promptCharacters = Array(prompt)
    let wordProgress = Self.wordProgress(configuration.wordLimit, in: promptCharacters)
    requiredWordStartIndex = wordProgress.startIndex
    promptWordCount = wordProgress.count
  }

  private static func wordProgress(
    _ wordLimit: Int?, in characters: [Character]
  ) -> (count: Int, startIndex: Int?) {
    var word = 0
    var afterSeparator = true
    var requiredStart: Int?
    for index in characters.indices {
      if isPromptWordSeparator(characters[index]) {
        afterSeparator = true
      } else if afterSeparator {
        word += 1
        if word == wordLimit { requiredStart = index }
        afterSeparator = false
      }
    }
    return (word, requiredStart)
  }

  private var reachedConfiguredWordLimit: Bool {
    guard let wordLimit = configuration.wordLimit, wordLimit > 0 else { return false }
    return completedWordCount >= wordLimit
  }

  private var reachedInputTargetEnd: Bool {
    if unitTargets.noSpace { return (acceptedUnits?.completedFieldCount ?? 0) >= unitTargets.fields.count }
    return nextTargetIndex >= promptCharacters.count
  }

  /// Matching a final retained LF can finish without a forward action. Do
  /// not use this predicate for refill: that field has not been submitted.
  private var noSpaceTerminalFieldMatches: Bool {
    guard unitTargets.noSpace, let acceptedUnits, !acceptedUnits.lastCommits else { return false }
    let limit = configuration.mode == .words
      || configuration.mode == .custom && configuration.customTextCompletion == .words && customSectionWordStream == nil
      ? configuration.wordLimit : nil
    let count = limit.flatMap { $0 > 0 ? $0 : nil } ?? unitTargets.fields.count
    let index = acceptedUnits.fieldIndex
    guard index == count - 1, unitTargets.fields.indices.contains(index),
      acceptedUnits.activeCount > 0
    else { return false }
    return acceptedUnits.field(index) == unitTargets.field(index)
  }

  private var shouldFinishEnglishWordsTest: Bool {
    guard let wordLimit = configuration.wordLimit, wordLimit > 0 else { return false }
    if let acceptedUnits {
      let targets = unitTargets.fields.indices.filter { !unitTargets.field($0, withoutCommit: true).isEmpty }
      guard targets.count >= wordLimit, acceptedUnits.fieldIndex >= targets[wordLimit - 1] else { return false }
      let input = acceptedUnits.starts.indices.filter { !acceptedUnits.field($0, withoutCommit: true).isEmpty }
      guard input.count >= wordLimit else { return false }
      if currentWordIsCorrect || lastInputCommitsWord { return true }
      return configuration.rules.quickEnd && !configuration.rules.stopOnError && !configuration.rules.deleteOnError
        && acceptedUnits.field(input[wordLimit - 1], withoutCommit: true).count
          == unitTargets.field(targets[wordLimit - 1], withoutCommit: true).count
    }
    guard let requiredWordStartIndex, nextTargetIndex >= requiredWordStartIndex else {
      return false
    }
    let targetWords = Array(
      splitPromptWords(prompt, omittingEmptySubsequences: true).prefix(wordLimit))
    let typedWords = retainedInputWords(omittingEmptySubsequences: true)
    guard targetWords.count == wordLimit, typedWords.count >= wordLimit
    else { return false }

    // A correct final word completes even if an earlier word was submitted
    // with errors. An incorrect final word instead needs its separator.
    if currentWordIsCorrect || lastInputCommitsWord { return true }

    // Quick end only applies at the final generated word and is deliberately
    // disabled when an error rule would reject the same character upstream.
    let allowsQuickEnd =
      configuration.rules.quickEnd
      && !configuration.rules.stopOnError
      && !configuration.rules.deleteOnError
    return allowsQuickEnd
      && typedWords[wordLimit - 1].utf16.count == targetWords[wordLimit - 1].utf16.count
  }

  /// Finite quotes and custom text use the same final-word rule as regular
  /// word tests: an incorrect word remains editable until its separator is
  /// entered, unless the optional quick-end rule explicitly applies.
  private var shouldFinishFiniteSpaceDelimitedTest: Bool {
    if unitTargets.noSpace { return reachedInputTargetEnd || noSpaceTerminalFieldMatches }
    let reachedTargetEnd = nextTargetIndex >= promptCharacters.count
    guard usesWordCommitInput,
      !TestModifierPolicy.usesNoSpaceInput(configuration.modifiers)
    else { return reachedTargetEnd }
    // A final newline-only word can match its complete target without word
    // navigation. Strict space/difficulty retain that first LF; correctness
    // (or permitted quick-end) still finishes the last generated word.
    if isAtFinalBlankTarget, !usesIncrementalPromptExtension {
      let input = inputWordText()
      if input == "\n", lastInputWasCorrect == true { return true }
      if configuration.rules.quickEnd, !configuration.rules.stopOnError,
        !configuration.rules.deleteOnError, input.utf16.count == 1 { return true }
    }
    if reachedTargetEnd,
      currentWordIsCorrect || lastInputCommitsWord { return true }
    // UTF-16 length can match before the grapheme cursor reaches target end.
    // A finite stream edge is not its final word while another chunk remains.
    let finalWordStart = promptCharacters.lastIndex(where: isPromptWordSeparator)
      .map { $0 + 1 } ?? 0
    guard nextTargetIndex >= finalWordStart, !usesIncrementalPromptExtension,
      configuration.rules.quickEnd,
      !configuration.rules.stopOnError,
      !configuration.rules.deleteOnError
    else { return false }
    guard let typedWord = retainedInputWords(omittingEmptySubsequences: false).last,
      let targetWord = splitPromptWords(prompt, omittingEmptySubsequences: true).last
    else { return false }
    return typedWord.utf16.count == targetWord.utf16.count
  }

  private var isAtFinalBlankTarget: Bool {
    guard let last = promptCharacters.indices.last,
      nextTargetIndex == last, promptCharacters[last] == "\n"
    else { return false }
    return last == 0 || isPromptWordSeparator(promptCharacters[last - 1])
  }

  /// The correct final word needs to retain its original preceding commit
  /// characters: a custom prompt can use a newline rather than a space.
  private func targetInputThroughWord(_ word: Int) -> String? {
    guard word >= 0 else { return nil }
    let targetCharacters = promptCharacters
    var currentWord = 0
    for index in targetCharacters.indices where isPromptWordSeparator(targetCharacters[index]) {
      if currentWord == word {
        return String(targetCharacters[..<index])
      }
      currentWord += 1
    }
    guard currentWord == word else { return nil }
    return prompt
  }

  private mutating func complete(at date: Date) {
    let end = automaticInputExecutionDate ?? date
    finishedAt = end
    outcome = hasTrailingInactivity(endingAt: end) ? .invalidAFK : .completed
  }

  /// Retain unrounded accuracy for threshold comparison: the reference
  /// compares its live percentage directly, while `accuracy` is display data.
  private var liveAccuracy: Double {
    guard inputAttemptCount > 0 else { return 1 }
    return Double(correctInputAttemptCount) / Double(inputAttemptCount)
  }

  private func livePracticeThresholdFailure(at date: Date) -> TestFailureReason? {
    let rules = configuration.rules
    if rules.minimumWpm > 0,
      completedWordCount > 3,
      Double(wpm(at: date)) < rules.minimumWpm
    {
      return .minimumWpm
    }
    if rules.minimumAccuracy > 0,
      liveAccuracy * 100 < rules.minimumAccuracy
    {
      return .minimumAccuracy
    }
    return nil
  }

  private func hasTrailingInactivity(endingAt date: Date) -> Bool {
    guard let startedAt else { return false }
    return TestInactivityPolicy.hasTrailingInactivity(
      insertionDates: insertionActivityDates, startedAt: startedAt, endedAt: date,
      includesFractionalTail: configuration.duration == nil)
  }

  private mutating func fail(at date: Date, reason: TestFailureReason? = nil) {
    failureReason = reason
    outcome = .failed
    finishedAt = automaticInputExecutionDate ?? date
  }
}

enum PigLatinPolicy {
  static func transform(_ text: String) -> String {
    var output = ""
    var word = ""
    for character in text {
      if character.isLetter || character == "'" {
        word.append(character)
      } else {
        output += transformedWord(word)
        word = ""
        output.append(character)
      }
    }
    return output + transformedWord(word)
  }

  private static func transformedWord(_ word: String) -> String {
    guard !word.isEmpty else { return "" }
    let wasCapitalized = word.first?.isUppercase == true
    let normalized = word.lowercased()
    let vowels = Set("aeiou")
    let transformed: String
    if let first = normalized.first, vowels.contains(first) {
      transformed = normalized + "way"
    } else if let vowelIndex = normalized.firstIndex(where: vowels.contains) {
      transformed = String(normalized[vowelIndex...]) + String(normalized[..<vowelIndex]) + "ay"
    } else {
      transformed = normalized + "ay"
    }
    guard wasCapitalized, let first = transformed.first else { return transformed }
    return String(first).uppercased() + transformed.dropFirst()
  }
}

/// Converts Typebar-owned Latin Kokanu text with the public Likanu character
/// rules. This is an independent syllable parser, not imported dictionary data
/// or conversion code from the reference project.
enum LikanuPolicy {
  private static let consonants: [Character: String] = [
    "p": "ʜ", "t": "ʌ", "k": "x", "w": "ɕ", "l": "ʋ", "j": "ɂ",
    "m": "ɞ", "n": "ƨ", "s": "ɤ", "c": "ɛ", "h": "ɵ",
  ]
  private static let vowels: [Character: String] = [
    "a": "", "e": "ȷ", "i": "ı", "o": "ʃ", "u": "ſ",
  ]
  private static let punctuation: [Character: Character] = [
    ".": ":", ",": "､", ";": "､", "!": "ʭ", "?": "≈", ":": "–",
  ]

  static func transform(_ text: String) -> String {
    var output = ""
    var word = ""
    func flushWord() {
      guard !word.isEmpty else { return }
      output += transformWord(word)
      word = ""
    }

    for character in text.lowercased() {
      if character.isASCII, character.isLetter {
        word.append(character)
      } else {
        flushWord()
        output.append(punctuation[character] ?? character)
      }
    }
    flushWord()
    return output
  }

  private static func transformWord(_ word: String) -> String {
    let characters = Array(word)
    var index = 0
    var output = ""
    while index < characters.count {
      let onset: String
      if let consonant = consonants[characters[index]],
         index + 1 < characters.count,
         vowels[characters[index + 1]] != nil
      {
        onset = consonant
        index += 1
      } else if vowels[characters[index]] != nil {
        onset = "o"
      } else {
        output.append(characters[index])
        index += 1
        continue
      }

      guard index < characters.count, let vowel = vowels[characters[index]] else {
        output += onset
        continue
      }
      index += 1
      let hasFinalN = index < characters.count
        && characters[index] == "n"
        && (index + 1 == characters.count || vowels[characters[index + 1]] == nil)
      output += onset
      if hasFinalN {
        output.append("\u{0304}")
        index += 1
      }
      output += vowel
    }
    return output
  }
}

struct IndexedLexicon: RandomAccessCollection {
  typealias Index = Int

  let count: Int
  private let wordAt: (Int) -> String

  var startIndex: Int { 0 }
  var endIndex: Int { count }

  init(count: Int, wordAt: @escaping (Int) -> String) {
    precondition(count >= 0)
    self.count = count
    self.wordAt = wordAt
  }

  init(_ words: [String]) {
    self.init(count: words.count) { words[$0] }
  }

  /// A draw-order view; even the largest owned lexicon stays lazy.
  static func ordered<C: RandomAccessCollection>(_ source: C, reversed: Bool) -> IndexedLexicon
    where C.Element == String {
    let count = source.count
    return .init(count: count) { position in
      source[source.index(source.startIndex, offsetBy: reversed ? count - 1 - position : position)]
    }
  }

  subscript(position: Int) -> String {
    precondition(indices.contains(position))
    return wordAt(position)
  }

  func materialized() -> [String] {
    indices.map { self[$0] }
  }
}

/// A virtual pool of Typebar-owned words. Large indexed lexicons stay lazy.
struct PolyglotWordPool {
  let sources: [(lexicon: IndexedLexicon, punctuation: [String])]
  let count: Int

  init(sources: [(IndexedLexicon, [String])]) {
    self.sources = sources.filter { !$0.0.isEmpty }
    count = self.sources.reduce(0) { $0 + $1.lexicon.count }
  }

  func entry(at index: Int) -> (word: String, punctuation: [String]) {
    precondition((0..<count).contains(index))
    var remainder = index
    for source in sources {
      if remainder < source.lexicon.count {
        return (source.lexicon[remainder], source.punctuation)
      }
      remainder -= source.lexicon.count
    }
    preconditionFailure("Polyglot pool index fell outside its sources")
  }

  /// A session-stable permutation keeps Zipf's preferred ranks from favoring
  /// the first selected language without allocating a shuffled word array.
  func zipfPermutation() -> (offset: Int, step: Int) {
    guard count > 1 else { return (0, 1) }
    let offset = Int.random(in: 0..<count)
    var step: Int
    repeat {
      step = Int.random(in: 1..<count)
    } while Self.gcd(step, count) != 1
    return (offset, step)
  }

  func index(for unit: Double, zipf: Bool, offset: Int = 0, step: Int = 1) -> Int {
    precondition(count > 0)
    let bounded = min(max(unit, 0), 0.999_999_999_999)
    guard zipf else { return min(count - 1, Int(bounded * Double(count))) }
    // A continuous harmonic approximation avoids O(pool size) work per word.
    let rank = min(count - 1, Int(expm1(bounded * log1p(Double(count)))))
    return (rank * step + offset) % count
  }

  private static func gcd(_ left: Int, _ right: Int) -> Int {
    var a = left
    var b = right
    while b != 0 { (a, b) = (b, a % b) }
    return a
  }
}

/// Recreates the visible English contraction behavior used when punctuation is
/// enabled without depending on the reference generator or its word lists.
enum EnglishPunctuationPolicy {
  private static let replacements: [String: [String]] = [
    "are": ["aren't"], "can": ["can't"], "could": ["couldn't"],
    "did": ["didn't"], "does": ["doesn't"], "do": ["don't"],
    "had": ["hadn't"], "has": ["hasn't"], "have": ["haven't"],
    "is": ["isn't"], "it": ["it's", "it'll"],
    "i": ["i'm", "i'll", "i've", "i'd"],
    "you": ["you'll", "you're", "you've", "you'd"],
    "that": ["that's", "that'll", "that'd"],
    "must": ["mustn't", "must've"],
    "there": ["there's", "there'll", "there'd"],
    "he": ["he's", "he'll", "he'd"], "she": ["she's", "she'll", "she'd"],
    "we": ["we're", "we'll", "we'd"], "they": ["they're", "they'll", "they'd"],
    "should": ["shouldn't", "should've"], "was": ["wasn't"],
    "were": ["weren't"], "will": ["won't"],
    "would": ["wouldn't", "would've"], "going": ["goin'"]
  ]

  static func transformed(_ token: String, random: () -> Double = { Double.random(in: 0..<1) }) -> String {
    guard random() < 0.5 else { return token }

    let characters = Array(token)
    var start = 0
    while start < characters.count, !isASCIIAlphabetic(characters[start]) { start += 1 }
    var end = characters.count
    while end > start, !isASCIIAlphabetic(characters[end - 1]) { end -= 1 }
    guard start < end else { return token }

    let prefix = String(characters[..<start])
    let source = String(characters[start..<end])
    let suffix = end < characters.count ? String(characters[end...]) : ""
    guard let choices = replacements[source.lowercased()] else { return token }

    let choice = choices[boundedIndex(random(), upperBound: choices.count)]
    return prefix + preservingCase(of: source, in: choice) + suffix
  }

  static func punctuatedPrompt(
    _ rawTokens: [String], random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    generatedPrompt(rawTokens, includesPunctuation: true, includesNumbers: false, random: random)
  }

  static func generatedPrompt(
    _ rawTokens: [String], includesPunctuation: Bool, includesNumbers: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    var generated: [String] = []
    for (index, rawToken) in rawTokens.enumerated() {
      let punctuated = includesPunctuation
        ? punctuatedToken(
          previousToken: generated.last, rawToken: rawToken, index: index,
          totalCount: rawTokens.count, random: random)
        : rawToken
      generated.append(includesNumbers && random() < 0.1 ? numberToken(random: random) : punctuated)
    }
    return generated
  }

  private static func isASCIIAlphabetic(_ character: Character) -> Bool {
    character.isASCII && character.isLetter
  }

  private static func boundedIndex(_ value: Double, upperBound: Int) -> Int {
    let normalized = min(max(value, 0), 0.999_999_999)
    return min(Int(normalized * Double(upperBound)), upperBound - 1)
  }

  private static func preservingCase(of source: String, in replacement: String) -> String {
    if source != "I", source == source.uppercased() {
      return replacement.uppercased()
    }
    guard let first = source.first, String(first) == String(first).uppercased() else {
      return replacement
    }
    return replacement.prefix(1).uppercased() + replacement.dropFirst()
  }

  private static func punctuatedToken(
    previousToken: String?, rawToken: String, index: Int, totalCount: Int,
    random: () -> Double
  ) -> String {
    let previousLastCharacter = previousToken?.last
    let followsComma = previousLastCharacter == ","
    let followsPeriod = previousLastCharacter == "."
    let followsSemicolon = previousLastCharacter == ";"
    let followsColon = previousLastCharacter == ":"

    if index == 0 || previousLastCharacter.map(isSentenceTerminator) == true {
      return capitalizingFirstCharacter(in: rawToken)
    }

    if (
      (random() < 0.1 && !followsPeriod && !followsComma && index != totalCount - 2)
        || index == totalCount - 1
    ) {
      let terminalChoice = random()
      if terminalChoice <= 0.8 { return rawToken + "." }
      if terminalChoice < 0.9 { return rawToken + "?" }
      return rawToken + "!"
    }
    if random() < 0.01 && !followsComma && !followsPeriod {
      return "\"\(rawToken)\""
    }
    if random() < 0.011 && !followsComma && !followsPeriod {
      return "'\(rawToken)'"
    }
    if random() < 0.012 && !followsComma && !followsPeriod {
      return "(\(rawToken))"
    }
    if random() < 0.013 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return rawToken + ":"
    }
    if random() < 0.014 && !followsComma && !followsPeriod && previousToken != "-" {
      return "-"
    }
    if random() < 0.015 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return rawToken + ";"
    }
    if random() < 0.2 && !followsComma {
      return rawToken + ","
    }
    return transformed(rawToken, random: random)
  }

  private static func numberToken(random: () -> Double) -> String {
    let length = boundedIndex(random(), upperBound: 4) + 1
    return (0..<length).map { index in
      let lowerBound = index == 0 ? 1 : 0
      let rangeSize = index == 0 ? 9 : 10
      return String(lowerBound + boundedIndex(random(), upperBound: rangeSize))
    }.joined()
  }

  private static func capitalizingFirstCharacter(in token: String) -> String {
    guard let first = token.first else { return token }
    return String(first).uppercased() + token.dropFirst()
  }

  private static func isSentenceTerminator(_ character: Character) -> Bool {
    character == "." || character == "?" || character == "!" || character == "؟"
  }
}

/// Produces Spanish sentence punctuation from native rules, including paired
/// inverted question and exclamation marks, without using reference assets.
enum SpanishPunctuationPolicy {
  static func punctuatedPrompt(
    _ rawTokens: [String], random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    generatedPrompt(rawTokens, includesPunctuation: true, includesNumbers: false, random: random)
  }

  static func generatedPrompt(
    _ rawTokens: [String], includesPunctuation: Bool, includesNumbers: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    var generated: [String] = []
    var sentenceTracker: Character?

    for (index, rawToken) in rawTokens.enumerated() {
      let punctuated = includesPunctuation
        ? punctuatedToken(
          previousToken: generated.last, rawToken: rawToken, index: index,
          totalCount: rawTokens.count, sentenceTracker: &sentenceTracker, random: random)
        : rawToken
      generated.append(includesNumbers && random() < 0.1 ? numberToken(random: random) : punctuated)
    }
    return generated
  }

  private static func punctuatedToken(
    previousToken: String?, rawToken: String, index: Int, totalCount: Int,
    sentenceTracker: inout Character?, random: () -> Double
  ) -> String {
    let previousLastCharacter = previousToken?.last
    let followsComma = previousLastCharacter == ","
    let followsPeriod = previousLastCharacter == "."
    let followsSemicolon = previousLastCharacter == ";"
    let followsColon = previousLastCharacter == ":"

    if index == 0 || previousLastCharacter.map(isSentenceTerminator) == true {
      let word = capitalizingFirstCharacter(in: rawToken)
      let sentenceStartChoice = random()
      if sentenceStartChoice > 0.9 {
        sentenceTracker = "?"
        return "¿\(word)"
      }
      if sentenceStartChoice > 0.8 {
        sentenceTracker = "!"
        return "¡\(word)"
      }
      return word
    }

    if (
      (random() < 0.1 && !followsPeriod && !followsComma && index != totalCount - 2)
        || index == totalCount - 1
    ) {
      defer { sentenceTracker = nil }
      return sentenceTracker.map { rawToken + String($0) } ?? rawToken
    }
    if random() < 0.01 && !followsComma && !followsPeriod {
      return "\"\(rawToken)\""
    }
    if random() < 0.011 && !followsComma && !followsPeriod {
      return "'\(rawToken)'"
    }
    if random() < 0.012 && !followsComma && !followsPeriod {
      return "(\(rawToken))"
    }
    if random() < 0.013 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return rawToken + ":"
    }
    if random() < 0.014 && !followsComma && !followsPeriod && previousToken != "-" {
      return "-"
    }
    if random() < 0.015 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return rawToken + ";"
    }
    if random() < 0.2 && !followsComma {
      return rawToken + ","
    }
    return rawToken
  }

  private static func numberToken(random: () -> Double) -> String {
    let length = boundedIndex(random(), upperBound: 4) + 1
    return (0..<length).map { index in
      let lowerBound = index == 0 ? 1 : 0
      let rangeSize = index == 0 ? 9 : 10
      return String(lowerBound + boundedIndex(random(), upperBound: rangeSize))
    }.joined()
  }

  private static func boundedIndex(_ value: Double, upperBound: Int) -> Int {
    let normalized = min(max(value, 0), 0.999_999_999)
    return min(Int(normalized * Double(upperBound)), upperBound - 1)
  }

  private static func capitalizingFirstCharacter(in token: String) -> String {
    guard let first = token.first else { return token }
    return String(first).uppercased() + token.dropFirst()
  }

  private static func isSentenceTerminator(_ character: Character) -> Bool {
    character == "." || character == "?" || character == "!" || character == "؟"
  }
}

/// Reproduces the French sentence and standalone-mark behavior with native
/// generation, keeping Typebar's independently authored French vocabularies.
enum FrenchPunctuationPolicy {
  static func punctuatedPrompt(
    _ rawTokens: [String], random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    generatedPrompt(rawTokens, includesPunctuation: true, includesNumbers: false, random: random)
  }

  static func generatedPrompt(
    _ rawTokens: [String], includesPunctuation: Bool, includesNumbers: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    var generated: [String] = []
    for (index, rawToken) in rawTokens.enumerated() {
      let punctuated = includesPunctuation
        ? punctuatedToken(
          previousToken: generated.last, rawToken: rawToken, index: index,
          totalCount: rawTokens.count, random: random)
        : rawToken
      generated.append(includesNumbers && random() < 0.1 ? numberToken(random: random) : punctuated)
    }
    return generated
  }

  private static func punctuatedToken(
    previousToken: String?, rawToken: String, index: Int, totalCount: Int,
    random: () -> Double
  ) -> String {
    let previousLastCharacter = previousToken?.last
    let followsComma = previousLastCharacter == ","
    let followsPeriod = previousLastCharacter == "."
    let followsSemicolon = previousLastCharacter == ";"
    let followsColon = previousLastCharacter == ":"

    if index == 0 || previousLastCharacter.map(isSentenceTerminator) == true {
      return capitalizingFirstCharacter(in: rawToken)
    }

    if (
      (random() < 0.1 && !followsPeriod && !followsComma && index != totalCount - 2)
        || index == totalCount - 1
    ) {
      let terminalChoice = random()
      if terminalChoice <= 0.8 { return rawToken + "." }
      if terminalChoice < 0.9 { return "?" }
      return "!"
    }
    if random() < 0.01 && !followsComma && !followsPeriod {
      return "\"\(rawToken)\""
    }
    if random() < 0.011 && !followsComma && !followsPeriod {
      return "'\(rawToken)'"
    }
    if random() < 0.012 && !followsComma && !followsPeriod {
      return "(\(rawToken))"
    }
    if random() < 0.013 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return ":"
    }
    if random() < 0.014 && !followsComma && !followsPeriod && previousToken != "-" {
      return "-"
    }
    if random() < 0.015 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return ";"
    }
    if random() < 0.2 && !followsComma {
      return rawToken + ","
    }
    return rawToken
  }

  private static func numberToken(random: () -> Double) -> String {
    let length = boundedIndex(random(), upperBound: 4) + 1
    return (0..<length).map { index in
      let lowerBound = index == 0 ? 1 : 0
      let rangeSize = index == 0 ? 9 : 10
      return String(lowerBound + boundedIndex(random(), upperBound: rangeSize))
    }.joined()
  }

  private static func boundedIndex(_ value: Double, upperBound: Int) -> Int {
    let normalized = min(max(value, 0), 0.999_999_999)
    return min(Int(normalized * Double(upperBound)), upperBound - 1)
  }

  private static func capitalizingFirstCharacter(in token: String) -> String {
    guard let first = token.first else { return token }
    return String(first).uppercased() + token.dropFirst()
  }

  private static func isSentenceTerminator(_ character: Character) -> Bool {
    character == "." || character == "?" || character == "!" || character == "؟"
  }
}

/// Recreates the Greek question and separator conventions with native prompt
/// generation while retaining Typebar-authored Greek word sources.
enum GreekPunctuationPolicy {
  static func punctuatedPrompt(
    _ rawTokens: [String], random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    generatedPrompt(rawTokens, includesPunctuation: true, includesNumbers: false, random: random)
  }

  static func generatedPrompt(
    _ rawTokens: [String], includesPunctuation: Bool, includesNumbers: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    var generated: [String] = []
    for (index, rawToken) in rawTokens.enumerated() {
      let punctuated = includesPunctuation
        ? punctuatedToken(
          previousToken: generated.last, rawToken: rawToken, index: index,
          totalCount: rawTokens.count, random: random)
        : rawToken
      generated.append(includesNumbers && random() < 0.1 ? numberToken(random: random) : punctuated)
    }
    return generated
  }

  private static func punctuatedToken(
    previousToken: String?, rawToken: String, index: Int, totalCount: Int,
    random: () -> Double
  ) -> String {
    let previousLastCharacter = previousToken?.last
    let followsComma = previousLastCharacter == ","
    let followsPeriod = previousLastCharacter == "."
    let followsSemicolon = previousLastCharacter == ";"
    let followsColon = previousLastCharacter == ":"

    if index == 0 || previousLastCharacter.map(isSentenceTerminator) == true {
      return capitalizingFirstCharacter(in: rawToken)
    }

    if (
      (random() < 0.1 && !followsPeriod && !followsComma && index != totalCount - 2)
        || index == totalCount - 1
    ) {
      let terminalChoice = random()
      if terminalChoice <= 0.8 { return rawToken + "." }
      if terminalChoice < 0.9 { return rawToken + ";" }
      return rawToken + "!"
    }
    if random() < 0.01 && !followsComma && !followsPeriod {
      return "\"\(rawToken)\""
    }
    if random() < 0.011 && !followsComma && !followsPeriod {
      return "'\(rawToken)'"
    }
    if random() < 0.012 && !followsComma && !followsPeriod {
      return "(\(rawToken))"
    }
    if random() < 0.013 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return rawToken + ":"
    }
    if random() < 0.014 && !followsComma && !followsPeriod && previousToken != "-" {
      return "-"
    }
    if random() < 0.015 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return "."
    }
    if random() < 0.2 && !followsComma {
      return rawToken + ","
    }
    return rawToken
  }

  private static func numberToken(random: () -> Double) -> String {
    let length = boundedIndex(random(), upperBound: 4) + 1
    return (0..<length).map { index in
      let lowerBound = index == 0 ? 1 : 0
      let rangeSize = index == 0 ? 9 : 10
      return String(lowerBound + boundedIndex(random(), upperBound: rangeSize))
    }.joined()
  }

  private static func boundedIndex(_ value: Double, upperBound: Int) -> Int {
    let normalized = min(max(value, 0), 0.999_999_999)
    return min(Int(normalized * Double(upperBound)), upperBound - 1)
  }

  private static func capitalizingFirstCharacter(in token: String) -> String {
    guard let first = token.first else { return token }
    return String(first).uppercased() + token.dropFirst()
  }

  private static func isSentenceTerminator(_ character: Character) -> Bool {
    character == "." || character == "?" || character == "!" || character == "؟"
  }
}

/// Generates Central Kurdish punctuation and Arabic-Indic number tokens from
/// Typebar-authored words, preserving visible right-to-left conventions.
enum KurdishPunctuationPolicy {
  static func punctuatedPrompt(
    _ rawTokens: [String], random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    generatedPrompt(rawTokens, includesPunctuation: true, includesNumbers: false, random: random)
  }

  static func generatedPrompt(
    _ rawTokens: [String], includesPunctuation: Bool, includesNumbers: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    var generated: [String] = []
    for (index, rawToken) in rawTokens.enumerated() {
      let punctuated = includesPunctuation
        ? punctuatedToken(
          previousToken: generated.last, rawToken: rawToken, index: index,
          totalCount: rawTokens.count, random: random)
        : rawToken
      generated.append(includesNumbers && random() < 0.1 ? numberToken(random: random) : punctuated)
    }
    return generated
  }

  private static func punctuatedToken(
    previousToken: String?, rawToken: String, index: Int, totalCount: Int,
    random: () -> Double
  ) -> String {
    let previousLastCharacter = previousToken?.last
    let followsComma = previousLastCharacter == ","
    let followsPeriod = previousLastCharacter == "."
    let followsSemicolon = previousLastCharacter == ";" || previousLastCharacter == "؛"
      || previousLastCharacter == "；" || previousLastCharacter == "："
    let followsColon = previousLastCharacter == ":" || previousLastCharacter == "："

    if index == 0 || previousLastCharacter.map(isSentenceTerminator) == true {
      return capitalizingFirstCharacter(in: rawToken)
    }

    if (
      (random() < 0.1 && !followsPeriod && !followsComma && index != totalCount - 2)
        || index == totalCount - 1
    ) {
      let terminalChoice = random()
      if terminalChoice <= 0.8 { return rawToken + "." }
      if terminalChoice < 0.9 { return rawToken + "؟" }
      return rawToken + "!"
    }
    if random() < 0.01 && !followsComma && !followsPeriod {
      return "\"\(rawToken)\""
    }
    if random() < 0.011 && !followsComma && !followsPeriod {
      return "'\(rawToken)'"
    }
    if random() < 0.012 && !followsComma && !followsPeriod {
      return "(\(rawToken))"
    }
    if random() < 0.013 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return rawToken + ":"
    }
    if random() < 0.014 && !followsComma && !followsPeriod && previousToken != "-" {
      return "-"
    }
    if random() < 0.015 && !followsComma && !followsPeriod && !followsSemicolon {
      return rawToken + "؛"
    }
    if random() < 0.2 && !followsComma {
      return rawToken + "،"
    }
    return rawToken
  }

  private static func numberToken(random: () -> Double) -> String {
    let length = boundedIndex(random(), upperBound: 4) + 1
    let arabicIndicDigits = Array("٠١٢٣٤٥٦٧٨٩")
    return (0..<length).map { index in
      let lowerBound = index == 0 ? 1 : 0
      let rangeSize = index == 0 ? 9 : 10
      return String(arabicIndicDigits[lowerBound + boundedIndex(random(), upperBound: rangeSize)])
    }.joined()
  }

  private static func boundedIndex(_ value: Double, upperBound: Int) -> Int {
    let normalized = min(max(value, 0), 0.999_999_999)
    return min(Int(normalized * Double(upperBound)), upperBound - 1)
  }

  private static func capitalizingFirstCharacter(in token: String) -> String {
    guard let first = token.first else { return token }
    return String(first).uppercased() + token.dropFirst()
  }

  private static func isSentenceTerminator(_ character: Character) -> Bool {
    character == "." || character == "?" || character == "!" || character == "؟"
  }
}

/// Generates Arabic punctuation and ASCII number tokens from Typebar-authored
/// words, matching the shared Arabic-family branch of the reference generator.
enum ArabicPunctuationPolicy {
  static func punctuatedPrompt(
    _ rawTokens: [String], random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    generatedPrompt(rawTokens, includesPunctuation: true, includesNumbers: false, random: random)
  }

  static func generatedPrompt(
    _ rawTokens: [String], includesPunctuation: Bool, includesNumbers: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    var generated: [String] = []
    for (index, rawToken) in rawTokens.enumerated() {
      let punctuated = includesPunctuation
        ? punctuatedToken(
          previousToken: generated.last, rawToken: rawToken, index: index,
          totalCount: rawTokens.count, random: random)
        : rawToken
      generated.append(includesNumbers && random() < 0.1 ? numberToken(random: random) : punctuated)
    }
    return generated
  }

  private static func punctuatedToken(
    previousToken: String?, rawToken: String, index: Int, totalCount: Int,
    random: () -> Double
  ) -> String {
    let previousLastCharacter = previousToken?.last
    let followsComma = previousLastCharacter == ","
    let followsPeriod = previousLastCharacter == "."
    let followsSemicolon = previousLastCharacter == ";" || previousLastCharacter == "؛"
      || previousLastCharacter == "；" || previousLastCharacter == "："
    let followsColon = previousLastCharacter == ":" || previousLastCharacter == "："

    if index == 0 || previousLastCharacter.map(isSentenceTerminator) == true {
      return capitalizingFirstCharacter(in: rawToken)
    }

    if (
      (random() < 0.1 && !followsPeriod && !followsComma && index != totalCount - 2)
        || index == totalCount - 1
    ) {
      let terminalChoice = random()
      if terminalChoice <= 0.8 { return rawToken + "." }
      if terminalChoice < 0.9 { return rawToken + "؟" }
      return rawToken + "!"
    }
    if random() < 0.01 && !followsComma && !followsPeriod {
      return "\"\(rawToken)\""
    }
    if random() < 0.011 && !followsComma && !followsPeriod {
      return "'\(rawToken)'"
    }
    if random() < 0.012 && !followsComma && !followsPeriod {
      return "(\(rawToken))"
    }
    if random() < 0.013 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return rawToken + ":"
    }
    if random() < 0.014 && !followsComma && !followsPeriod && previousToken != "-" {
      return "-"
    }
    if random() < 0.015 && !followsComma && !followsPeriod && !followsSemicolon {
      return rawToken + "؛"
    }
    if random() < 0.2 && !followsComma {
      return rawToken + "،"
    }
    return rawToken
  }

  private static func numberToken(random: () -> Double) -> String {
    let length = boundedIndex(random(), upperBound: 4) + 1
    return (0..<length).map { index in
      let lowerBound = index == 0 ? 1 : 0
      let rangeSize = index == 0 ? 9 : 10
      return String(lowerBound + boundedIndex(random(), upperBound: rangeSize))
    }.joined()
  }

  private static func boundedIndex(_ value: Double, upperBound: Int) -> Int {
    let normalized = min(max(value, 0), 0.999_999_999)
    return min(Int(normalized * Double(upperBound)), upperBound - 1)
  }

  private static func capitalizingFirstCharacter(in token: String) -> String {
    guard let first = token.first else { return token }
    return String(first).uppercased() + token.dropFirst()
  }

  private static func isSentenceTerminator(_ character: Character) -> Bool {
    character == "." || character == "?" || character == "!" || character == "؟"
  }
}

/// Shares the reference Persian and Urdu family branch while keeping every
/// Typebar corpus local. Unlike Arabic and Kurdish, this branch emits an ASCII
/// semicolon and ASCII number tokens.
enum PersianUrduPunctuationPolicy {
  static func punctuatedPrompt(
    _ rawTokens: [String], random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    generatedPrompt(rawTokens, includesPunctuation: true, includesNumbers: false, random: random)
  }

  static func generatedPrompt(
    _ rawTokens: [String], includesPunctuation: Bool, includesNumbers: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    var generated: [String] = []
    for (index, rawToken) in rawTokens.enumerated() {
      let punctuated = includesPunctuation
        ? punctuatedToken(
          previousToken: generated.last, rawToken: rawToken, index: index,
          totalCount: rawTokens.count, random: random)
        : rawToken
      generated.append(includesNumbers && random() < 0.1 ? numberToken(random: random) : punctuated)
    }
    return generated
  }

  private static func punctuatedToken(
    previousToken: String?, rawToken: String, index: Int, totalCount: Int,
    random: () -> Double
  ) -> String {
    let previousLastCharacter = previousToken?.last
    let followsComma = previousLastCharacter == ","
    let followsPeriod = previousLastCharacter == "."
    let followsSemicolon = previousLastCharacter == ";" || previousLastCharacter == "؛"
      || previousLastCharacter == "；" || previousLastCharacter == "："
    let followsColon = previousLastCharacter == ":" || previousLastCharacter == "："

    if index == 0 || previousLastCharacter.map(isSentenceTerminator) == true {
      return capitalizingFirstCharacter(in: rawToken)
    }

    if (
      (random() < 0.1 && !followsPeriod && !followsComma && index != totalCount - 2)
        || index == totalCount - 1
    ) {
      let terminalChoice = random()
      if terminalChoice <= 0.8 { return rawToken + "." }
      if terminalChoice < 0.9 { return rawToken + "؟" }
      return rawToken + "!"
    }
    if random() < 0.01 && !followsComma && !followsPeriod { return "\"\(rawToken)\"" }
    if random() < 0.011 && !followsComma && !followsPeriod { return "'\(rawToken)'" }
    if random() < 0.012 && !followsComma && !followsPeriod { return "(\(rawToken))" }
    if random() < 0.013 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return rawToken + ":"
    }
    if random() < 0.014 && !followsComma && !followsPeriod && previousToken != "-" { return "-" }
    if random() < 0.015 && !followsComma && !followsPeriod && !followsSemicolon {
      return rawToken + ";"
    }
    if random() < 0.2 && !followsComma { return rawToken + "،" }
    return rawToken
  }

  private static func numberToken(random: () -> Double) -> String {
    let length = boundedIndex(random(), upperBound: 4) + 1
    return (0..<length).map { index in
      let lowerBound = index == 0 ? 1 : 0
      let rangeSize = index == 0 ? 9 : 10
      return String(lowerBound + boundedIndex(random(), upperBound: rangeSize))
    }.joined()
  }

  private static func boundedIndex(_ value: Double, upperBound: Int) -> Int {
    let normalized = min(max(value, 0), 0.999_999_999)
    return min(Int(normalized * Double(upperBound)), upperBound - 1)
  }

  private static func capitalizingFirstCharacter(in token: String) -> String {
    guard let first = token.first else { return token }
    return String(first).uppercased() + token.dropFirst()
  }

  private static func isSentenceTerminator(_ character: Character) -> Bool {
    character == "." || character == "?" || character == "!" || character == "؟"
  }
}

/// Generates the shared Hindi, Nepali, and Bangla punctuation branch with a
/// caller-supplied local digit system.
enum IndicPunctuationPolicy {
  static func punctuatedPrompt(
    _ tokens: [String], digits: [Character], random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    generatedPrompt(tokens, digits: digits, includesPunctuation: true, includesNumbers: false, random: random)
  }

  static func generatedPrompt(
    _ tokens: [String], digits: [Character], includesPunctuation: Bool, includesNumbers: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    var result: [String] = []
    for (index, raw) in tokens.enumerated() {
      let word = includesPunctuation ? punctuated(
        previous: result.last, raw: raw, index: index, total: tokens.count, random: random) : raw
      result.append(includesNumbers && random() < 0.1 ? number(digits: digits, random: random) : word)
    }
    return result
  }

  private static func punctuated(
    previous: String?, raw: String, index: Int, total: Int, random: () -> Double
  ) -> String {
    let last = previous?.last
    let followsComma = last == ","
    let followsPeriod = last == "."
    let followsSemicolon = last == ";" || last == "؛" || last == "；" || last == "："
    let followsColon = last == ":" || last == "："
    if index == 0 || [".", "?", "!", "؟"].contains(last) {
      guard let first = raw.first else { return raw }
      return String(first).uppercased() + raw.dropFirst()
    }
    if (random() < 0.1 && !followsPeriod && !followsComma && index != total - 2) || index == total - 1 {
      let choice = random()
      return raw + (choice <= 0.8 ? "।" : choice < 0.9 ? "?" : "!")
    }
    if random() < 0.01 && !followsComma && !followsPeriod { return "\"\(raw)\"" }
    if random() < 0.011 && !followsComma && !followsPeriod { return "'\(raw)'" }
    if random() < 0.012 && !followsComma && !followsPeriod { return "(\(raw))" }
    if random() < 0.013 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon { return raw + ":" }
    if random() < 0.014 && !followsComma && !followsPeriod && previous != "-" { return "-" }
    if random() < 0.015 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon { return raw + ";" }
    if random() < 0.2 && !followsComma { return raw + "," }
    return raw
  }

  private static func number(digits: [Character], random: () -> Double) -> String {
    precondition(digits.count == 10)
    let count = min(max(Int(random() * 4), 0), 3) + 1
    return (0..<count).map { index in
      let lower = index == 0 ? 1 : 0
      let range = index == 0 ? 9 : 10
      let offset = min(max(Int(random() * Double(range)), 0), range - 1)
      return String(digits[lower + offset])
    }.joined()
  }
}

/// Generates the standard reference word stream while retaining the quote
/// exclusions used by the Russian, Ukrainian, and Slovak language families.
enum SlavicPunctuationPolicy {
  static func punctuatedPrompt(
    _ tokens: [String], allowsDoubleQuotes: Bool, allowsApostrophes: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    generatedPrompt(
      tokens, allowsDoubleQuotes: allowsDoubleQuotes, allowsApostrophes: allowsApostrophes,
      includesPunctuation: true, includesNumbers: false, random: random)
  }

  static func generatedPrompt(
    _ tokens: [String], allowsDoubleQuotes: Bool, allowsApostrophes: Bool,
    includesPunctuation: Bool, includesNumbers: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    var result: [String] = []
    for (index, raw) in tokens.enumerated() {
      let word = includesPunctuation ? punctuated(
        previous: result.last, raw: raw, index: index, total: tokens.count,
        allowsDoubleQuotes: allowsDoubleQuotes, allowsApostrophes: allowsApostrophes,
        random: random) : raw
      result.append(includesNumbers && random() < 0.1 ? number(random: random) : word)
    }
    return result
  }

  private static func punctuated(
    previous: String?, raw: String, index: Int, total: Int,
    allowsDoubleQuotes: Bool, allowsApostrophes: Bool, random: () -> Double
  ) -> String {
    let last = previous?.last
    let followsComma = last == ","
    let followsPeriod = last == "."
    let followsSemicolon = last == ";" || last == "؛" || last == "；" || last == "："
    let followsColon = last == ":" || last == "："
    if index == 0 || [".", "?", "!", "؟"].contains(last) {
      guard let first = raw.first else { return raw }
      return String(first).uppercased() + raw.dropFirst()
    }
    if (random() < 0.1 && !followsPeriod && !followsComma && index != total - 2) || index == total - 1 {
      let choice = random()
      if choice <= 0.8 { return raw + "." }
      if choice > 0.8 && choice < 0.9 { return raw + "?" }
      return raw + "!"
    }
    if random() < 0.01 && !followsComma && !followsPeriod && allowsDoubleQuotes { return "\"\(raw)\"" }
    if random() < 0.011 && !followsComma && !followsPeriod && allowsApostrophes { return "'\(raw)'" }
    if random() < 0.012 && !followsComma && !followsPeriod { return "(\(raw))" }
    if random() < 0.013 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon { return raw + ":" }
    if random() < 0.014 && !followsComma && !followsPeriod && previous != "-" { return "-" }
    if random() < 0.015 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon { return raw + ";" }
    if random() < 0.2 && !followsComma { return raw + "," }
    return raw
  }

  private static func number(random: () -> Double) -> String {
    let count = min(max(Int(random() * 4), 0), 3) + 1
    return (0..<count).map { index in
      let lower = index == 0 ? 1 : 0
      let range = index == 0 ? 9 : 10
      let offset = min(max(Int(random() * Double(range)), 0), range - 1)
      return String(lower + offset)
    }.joined()
  }
}

/// Generates the Japanese and Chinese punctuation branches without importing
/// the reference generator or its content.
enum CJKPunctuationPolicy {
  static func punctuatedPrompt(
    _ tokens: [String], usesChineseMarks: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    generatedPrompt(
      tokens, usesChineseMarks: usesChineseMarks, includesPunctuation: true,
      includesNumbers: false, random: random)
  }

  static func generatedPrompt(
    _ tokens: [String], usesChineseMarks: Bool, includesPunctuation: Bool, includesNumbers: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    var result: [String] = []
    for (index, raw) in tokens.enumerated() {
      let word = includesPunctuation ? punctuated(
        previous: result.last, raw: raw, index: index, total: tokens.count,
        usesChineseMarks: usesChineseMarks, random: random) : raw
      result.append(includesNumbers && random() < 0.1 ? number(random: random) : word)
    }
    return result
  }

  private static func punctuated(
    previous: String?, raw: String, index: Int, total: Int, usesChineseMarks: Bool,
    random: () -> Double
  ) -> String {
    let last = previous?.last
    let followsComma = last == ","
    let followsPeriod = last == "."
    let followsSemicolon = last == ";" || last == "؛" || last == "；" || last == "："
    let followsColon = last == ":" || last == "："
    if index == 0 || [".", "?", "!", "؟"].contains(last) { return raw }
    if (random() < 0.1 && !followsPeriod && !followsComma && index != total - 2) || index == total - 1 {
      let choice = random()
      if choice <= 0.8 { return raw + "。" }
      if choice > 0.8 && choice < 0.9 { return raw + "？" }
      return raw + "！"
    }
    if random() < 0.01 && !followsComma && !followsPeriod { return "\"\(raw)\"" }
    if random() < 0.011 && !followsComma && !followsPeriod { return "'\(raw)'" }
    if random() < 0.012 && !followsComma && !followsPeriod { return "（\(raw)）" }
    if random() < 0.013 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return raw + (usesChineseMarks ? "：" : ":")
    }
    if random() < 0.014 && !followsComma && !followsPeriod && previous != "-" { return "-" }
    if random() < 0.015 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return raw + (usesChineseMarks ? "；" : ";")
    }
    if random() < 0.2 && !followsComma { return raw + (usesChineseMarks ? "，" : "、") }
    return raw
  }

  private static func number(random: () -> Double) -> String {
    let count = min(max(Int(random() * 4), 0), 3) + 1
    return (0..<count).map { index in
      let lower = index == 0 ? 1 : 0
      let range = index == 0 ? 9 : 10
      let offset = min(max(Int(random() * Double(range)), 0), range - 1)
      return String(lower + offset)
    }.joined()
  }
}

/// Applies the source-compatible Turkish sentence case and contextual marks to
/// Typebar-owned Turkish words without importing the web generator or corpus.
enum TurkishPunctuationPolicy {
  static func punctuatedPrompt(
    _ rawTokens: [String], random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    generatedPrompt(rawTokens, includesPunctuation: true, includesNumbers: false, random: random)
  }

  static func generatedPrompt(
    _ rawTokens: [String], includesPunctuation: Bool, includesNumbers: Bool,
    random: () -> Double = { Double.random(in: 0..<1) }
  ) -> [String] {
    var generated: [String] = []
    for (index, rawToken) in rawTokens.enumerated() {
      let punctuated = includesPunctuation
        ? punctuatedToken(
          previousToken: generated.last, rawToken: rawToken, index: index,
          totalCount: rawTokens.count, random: random)
        : rawToken
      generated.append(includesNumbers && random() < 0.1 ? numberToken(random: random) : punctuated)
    }
    return generated
  }

  private static func punctuatedToken(
    previousToken: String?, rawToken: String, index: Int, totalCount: Int,
    random: () -> Double
  ) -> String {
    let previousLastCharacter = previousToken?.last
    let followsComma = previousLastCharacter == ","
    let followsPeriod = previousLastCharacter == "."
    let followsSemicolon = previousLastCharacter == ";"
    let followsColon = previousLastCharacter == ":"

    if index == 0 || previousLastCharacter.map(isSentenceTerminator) == true {
      return sentenceCase(rawToken)
    }

    if (
      (random() < 0.1 && !followsPeriod && !followsComma && index != totalCount - 2)
        || index == totalCount - 1
    ) {
      let terminalChoice = random()
      if terminalChoice <= 0.8 { return rawToken + "." }
      if terminalChoice < 0.9 { return rawToken + "?" }
      return rawToken + "!"
    }
    if random() < 0.01 && !followsComma && !followsPeriod {
      return "\"\(rawToken)\""
    }
    if random() < 0.011 && !followsComma && !followsPeriod {
      return "'\(rawToken)'"
    }
    if random() < 0.012 && !followsComma && !followsPeriod {
      return "(\(rawToken))"
    }
    if random() < 0.013 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return rawToken + ":"
    }
    if random() < 0.014 && !followsComma && !followsPeriod && previousToken != "-" {
      return "-"
    }
    if random() < 0.015 && !followsComma && !followsPeriod && !followsSemicolon && !followsColon {
      return rawToken + ";"
    }
    if random() < 0.2 && !followsComma {
      return rawToken + ","
    }
    return rawToken
  }

  private static func sentenceCase(_ token: String) -> String {
    guard let first = token.first else { return token }
    let capitalized = String(first).uppercased().replacingOccurrences(of: "I", with: "İ")
    return capitalized + token.dropFirst()
  }

  private static func numberToken(random: () -> Double) -> String {
    let length = boundedIndex(random(), upperBound: 4) + 1
    return (0..<length).map { index in
      let lowerBound = index == 0 ? 1 : 0
      let rangeSize = index == 0 ? 9 : 10
      return String(lowerBound + boundedIndex(random(), upperBound: rangeSize))
    }.joined()
  }

  private static func boundedIndex(_ value: Double, upperBound: Int) -> Int {
    let normalized = min(max(value, 0), 0.999_999_999)
    return min(Int(normalized * Double(upperBound)), upperBound - 1)
  }

  private static func isSentenceTerminator(_ character: Character) -> Bool {
    character == "." || character == "?" || character == "!" || character == "؟"
  }
}

enum StarterLexicon {
  private static let englishScaleRoots = [
    "amber", "birch", "cairn", "delta", "ember", "field", "grove", "harbor",
    "islet", "juniper", "keel", "lumen", "meadow", "north", "orbit", "pebble",
    "quill", "river", "solar", "trail", "upland", "vivid", "willow", "zephyr",
  ]

  private static func alphabeticIndex(_ index: Int) -> String {
    var value = index
    var scalars: [UnicodeScalar] = []
    repeat {
      scalars.append(UnicodeScalar(97 + value % 26)!)
      value /= 26
    } while value > 0
    return String(String.UnicodeScalarView(scalars.reversed()))
  }

  private static let cyrillicScaleAlphabet = Array(
    "абвгдеёжзійклмнопрстуўфхцчшыьэюя")

  private static let ethiopicScaleAlphabet = Array(
    "ሀለሐመሠረሰሸቀበተኀነአከወዐዘየደገጠጸፀፈፐ")

  private static let armenianScaleAlphabet = Array(
    "աբգդեզէըթժիլխծկհձղճմյնշոչպջռսվտրցւփքևօֆ")

  private static let tibetanScaleAlphabet = Array(
    "ཀཁགངཅཆཇཉཏཐདནཔཕབམཙཚཛཝཞཟའཡརལཤསཧཨ")

  private static func characterIndex(_ index: Int, alphabet: [Character]) -> String {
    precondition(!alphabet.isEmpty)
    var value = index
    var characters: [Character] = []
    repeat {
      characters.append(alphabet[value % alphabet.count])
      value /= alphabet.count
    } while value > 0
    return String(characters.reversed())
  }

  private static func cyrillicIndex(_ index: Int) -> String {
    characterIndex(index, alphabet: cyrillicScaleAlphabet)
  }

  private static func englishScaleLexicon(
    marker: String, count: Int, minimumToken: String, maximumLength: Int,
    uppercaseCount: Int, punctuationCount: Int
  ) -> IndexedLexicon {
    precondition(count > max(uppercaseCount + 2, punctuationCount + 2))
    return IndexedLexicon(count: count) { index in
      var entry = marker + englishScaleRoots[index % englishScaleRoots.count]
        + alphabeticIndex(index)
      if index == 0 {
        entry = minimumToken
      } else if index == 1 {
        entry = String(repeating: marker.last!, count: maximumLength)
      } else if index < uppercaseCount + 2 {
        entry = entry.prefix(1).uppercased() + entry.dropFirst()
      }
      if index >= count - punctuationCount {
        entry += "-"
      }
      return entry
    }
  }

  // Typebar-authored deterministic scale corpora. They preserve the pinned
  // choice sizes and aggregate input shapes without importing reference words.
  static var english1kLexicon: IndexedLexicon {
    englishScaleLexicon(
      marker: "q", count: 1_000, minimumToken: "q", maximumLength: 11,
      uppercaseCount: 1, punctuationCount: 0)
  }
  static var english5kLexicon: IndexedLexicon {
    englishScaleLexicon(
      marker: "ve", count: 5_000, minimumToken: "v", maximumLength: 18,
      uppercaseCount: 216, punctuationCount: 0)
  }
  static var english10kLexicon: IndexedLexicon {
    englishScaleLexicon(
      marker: "wi", count: 9_944, minimumToken: "w", maximumLength: 18,
      uppercaseCount: 403, punctuationCount: 0)
  }
  static var english25kLexicon: IndexedLexicon {
    englishScaleLexicon(
      marker: "xo", count: 24_141, minimumToken: "qxqz", maximumLength: 27,
      uppercaseCount: 946, punctuationCount: 0)
  }
  static var english450kLexicon: IndexedLexicon {
    englishScaleLexicon(
      marker: "yu", count: 450_029, minimumToken: "b", maximumLength: 31,
      uppercaseCount: 33_021, punctuationCount: 176)
  }

  static var english1kWords: [String] { english1kLexicon.materialized() }
  static var english5kWords: [String] { english5kLexicon.materialized() }
  static var english10kWords: [String] { english10kLexicon.materialized() }
  static var english25kWords: [String] { english25kLexicon.materialized() }
  static var english450kWords: [String] { english450kLexicon.materialized() }

  private static let spanishScaleRoots = [
    "brisa", "claro", "faro", "jardin", "luna", "mar",
    "nube", "papel", "puente", "ruta", "sendero", "sol",
  ]

  private static func spanishScaleLexicon(
    marker: String, count: Int, minimumToken: String, maximumLength: Int,
    uppercaseCount: Int, punctuationCount: Int, spaceCount: Int, nonASCIICount: Int
  ) -> IndexedLexicon {
    let minimumUsesNonASCII = minimumToken.unicodeScalars.contains { !$0.isASCII }
    let generatedNonASCIICount = nonASCIICount - (minimumUsesNonASCII ? 1 : 0)
    precondition(count > max(uppercaseCount + 2, generatedNonASCIICount + 2))
    precondition((0...punctuationCount).contains(spaceCount))
    return IndexedLexicon(count: count) { index in
      var entry = marker + spanishScaleRoots[index % spanishScaleRoots.count]
        + alphabeticIndex(index)
      if index == 0 {
        entry = minimumToken
      } else if index == 1 {
        entry = String(repeating: marker.last!, count: maximumLength)
      } else {
        if index < uppercaseCount + 2 {
          entry = entry.prefix(1).uppercased() + entry.dropFirst()
        }
        if index < generatedNonASCIICount + 2 {
          entry += "ñ"
        }
      }
      if index >= count - spaceCount {
        entry += " roca"
      } else if index >= count - punctuationCount {
        entry += "-"
      }
      return entry
    }
  }

  static var spanish1kLexicon: IndexedLexicon {
    spanishScaleLexicon(
      marker: "zq", count: 998, minimumToken: "q", maximumLength: 15,
      uppercaseCount: 10, punctuationCount: 0, spaceCount: 0, nonASCIICount: 179)
  }
  static var spanish10kLexicon: IndexedLexicon {
    spanishScaleLexicon(
      marker: "wx", count: 9_990, minimumToken: "w", maximumLength: 20,
      uppercaseCount: 433, punctuationCount: 1, spaceCount: 0, nonASCIICount: 2_062)
  }
  static var spanish650kLexicon: IndexedLexicon {
    spanishScaleLexicon(
      marker: "qzv", count: 646_579, minimumToken: "á", maximumLength: 26,
      uppercaseCount: 3, punctuationCount: 239, spaceCount: 162, nonASCIICount: 247_122)
  }

  static var spanish1kWords: [String] { spanish1kLexicon.materialized() }
  static var spanish10kWords: [String] { spanish10kLexicon.materialized() }
  static var spanish650kWords: [String] { spanish650kLexicon.materialized() }

  private static let frenchScaleRoots = [
    "arc", "bois", "ciel", "dune", "fil", "lac", "rive", "vent",
  ]

  private static func frenchScaleLexicon(
    marker: String, count: Int, minimumToken: String, maximumLength: Int,
    uppercaseCount: Int, punctuationCount: Int, spaceCount: Int,
    punctuationSpaceOverlap: Int, nonASCIICount: Int
  ) -> IndexedLexicon {
    let minimumNonASCIICount = minimumToken.unicodeScalars.contains { !$0.isASCII } ? 1 : 0
    let generatedNonASCIICount = nonASCIICount - minimumNonASCIICount
    precondition(generatedNonASCIICount >= 0)
    precondition(count > max(uppercaseCount + 2, generatedNonASCIICount + 2))
    precondition(punctuationSpaceOverlap <= min(punctuationCount, spaceCount))
    let punctuationOnlyCount = punctuationCount - punctuationSpaceOverlap
    return IndexedLexicon(count: count) { index in
      var entry = marker + frenchScaleRoots[index % frenchScaleRoots.count]
        + alphabeticIndex(index)
      if index == 0 {
        entry = minimumToken
      } else if index == 1 {
        entry = String(repeating: marker.first!, count: maximumLength)
      } else {
        if index < uppercaseCount + 2 {
          entry = entry.prefix(1).uppercased() + entry.dropFirst()
        }
        if index < generatedNonASCIICount + 2 {
          entry += "é"
        }
      }
      if index >= count - spaceCount {
        entry += " x"
        if index >= count - punctuationSpaceOverlap {
          entry += "-"
        }
      } else if index >= count - spaceCount - punctuationOnlyCount {
        entry += "-"
      }
      return entry
    }
  }

  static var french1kLexicon: IndexedLexicon {
    frenchScaleLexicon(
      marker: "qfr", count: 1_394, minimumToken: "q", maximumLength: 14,
      uppercaseCount: 0, punctuationCount: 6, spaceCount: 6,
      punctuationSpaceOverlap: 0, nonASCIICount: 257)
  }
  static var french2kLexicon: IndexedLexicon {
    frenchScaleLexicon(
      marker: "wfr", count: 2_041, minimumToken: "w", maximumLength: 14,
      uppercaseCount: 3, punctuationCount: 10, spaceCount: 11,
      punctuationSpaceOverlap: 0, nonASCIICount: 503)
  }
  static var french10kLexicon: IndexedLexicon {
    frenchScaleLexicon(
      marker: "xfr", count: 10_251, minimumToken: "x", maximumLength: 15,
      uppercaseCount: 4, punctuationCount: 73, spaceCount: 60,
      punctuationSpaceOverlap: 2, nonASCIICount: 3_224)
  }
  static var french600kLexicon: IndexedLexicon {
    frenchScaleLexicon(
      marker: "qvfr", count: 633_941, minimumToken: "ǿ", maximumLength: 33,
      uppercaseCount: 0, punctuationCount: 34, spaceCount: 0,
      punctuationSpaceOverlap: 0, nonASCIICount: 282_793)
  }

  static var french1kWords: [String] { french1kLexicon.materialized() }
  static var french2kWords: [String] { french2kLexicon.materialized() }
  static var french10kWords: [String] { french10kLexicon.materialized() }
  static var french600kWords: [String] { french600kLexicon.materialized() }

  private static let germanScaleRoots = [
    "hain", "ufer", "spur", "klang", "pfad", "licht", "wind", "feld",
  ]

  private static func germanScaleLexicon(
    marker: String, count: Int, minimumToken: String, maximumLength: Int,
    uppercaseCount: Int, punctuationCount: Int, spaceCount: Int, nonASCIICount: Int
  ) -> IndexedLexicon {
    precondition(count > max(uppercaseCount + 2, nonASCIICount + 2))
    precondition(punctuationCount + spaceCount < count)
    return IndexedLexicon(count: count) { index in
      var entry = marker + germanScaleRoots[index % germanScaleRoots.count]
        + alphabeticIndex(index)
      if index == 0 {
        entry = minimumToken
      } else if index == 1 {
        entry = String(repeating: marker.first!, count: maximumLength)
      } else {
        if index < uppercaseCount + 2 {
          entry = entry.prefix(1).uppercased() + entry.dropFirst()
        }
        if index < nonASCIICount + 2 {
          entry += "ü"
        }
      }
      if index >= count - spaceCount {
        entry += " x"
      } else if index >= count - spaceCount - punctuationCount {
        entry += "-"
      }
      return entry
    }
  }

  static var german1kLexicon: IndexedLexicon {
    germanScaleLexicon(
      marker: "qgd", count: 988, minimumToken: "qz", maximumLength: 17,
      uppercaseCount: 415, punctuationCount: 3, spaceCount: 8, nonASCIICount: 109)
  }
  static var german10kLexicon: IndexedLexicon {
    germanScaleLexicon(
      marker: "wgd", count: 9_994, minimumToken: "wx", maximumLength: 27,
      uppercaseCount: 5_447, punctuationCount: 25, spaceCount: 40,
      nonASCIICount: 1_599)
  }
  static var german250kLexicon: IndexedLexicon {
    germanScaleLexicon(
      marker: "xgd", count: 239_243, minimumToken: "vx", maximumLength: 35,
      uppercaseCount: 181_917, punctuationCount: 0, spaceCount: 0,
      nonASCIICount: 45_170)
  }

  static var german1kWords: [String] { german1kLexicon.materialized() }
  static var german10kWords: [String] { german10kLexicon.materialized() }
  static var german250kWords: [String] { german250kLexicon.materialized() }

  private static let romanianScaleRoots = [
    "mal", "fir", "nor", "lac", "pas", "zori", "deal", "drum",
  ]

  private static func romanianScaleLexicon(
    marker: String, count: Int, maximumLength: Int,
    punctuationCount: Int, nonASCIICount: Int
  ) -> IndexedLexicon {
    precondition(count > nonASCIICount + 1)
    precondition(punctuationCount < count)
    return IndexedLexicon(count: count) { index in
      var entry = marker + romanianScaleRoots[index % romanianScaleRoots.count]
        + alphabeticIndex(index)
      if index == 0 {
        entry = "ș"
      } else if index == 1 {
        entry = String(repeating: marker.first!, count: maximumLength)
      } else if index < nonASCIICount + 1 {
        entry += "ă"
      }
      if index >= count - punctuationCount {
        entry += "-"
      }
      return entry
    }
  }

  static var romanian1kLexicon: IndexedLexicon {
    romanianScaleLexicon(
      marker: "qro", count: 1_000, maximumLength: 19,
      punctuationCount: 21, nonASCIICount: 364)
  }
  static var romanian5kLexicon: IndexedLexicon {
    romanianScaleLexicon(
      marker: "wro", count: 5_000, maximumLength: 23,
      punctuationCount: 95, nonASCIICount: 1_981)
  }
  static var romanian10kLexicon: IndexedLexicon {
    romanianScaleLexicon(
      marker: "xro", count: 10_000, maximumLength: 25,
      punctuationCount: 202, nonASCIICount: 3_941)
  }
  static var romanian25kLexicon: IndexedLexicon {
    romanianScaleLexicon(
      marker: "zro", count: 25_000, maximumLength: 34,
      punctuationCount: 474, nonASCIICount: 9_931)
  }
  static var romanian50kLexicon: IndexedLexicon {
    romanianScaleLexicon(
      marker: "vro", count: 50_000, maximumLength: 25,
      punctuationCount: 957, nonASCIICount: 19_705)
  }
  static var romanian100kLexicon: IndexedLexicon {
    romanianScaleLexicon(
      marker: "jro", count: 100_000, maximumLength: 31,
      punctuationCount: 1_912, nonASCIICount: 39_497)
  }
  static var romanian200kLexicon: IndexedLexicon {
    romanianScaleLexicon(
      marker: "kro", count: 200_000, maximumLength: 50,
      punctuationCount: 3_891, nonASCIICount: 79_168)
  }

  static var romanian1kWords: [String] { romanian1kLexicon.materialized() }
  static var romanian5kWords: [String] { romanian5kLexicon.materialized() }
  static var romanian10kWords: [String] { romanian10kLexicon.materialized() }
  static var romanian25kWords: [String] { romanian25kLexicon.materialized() }
  static var romanian50kWords: [String] { romanian50kLexicon.materialized() }
  static var romanian100kWords: [String] { romanian100kLexicon.materialized() }
  static var romanian200kWords: [String] { romanian200kLexicon.materialized() }

  private static let polishScaleRoots = [
    "las", "nurt", "most", "brzeg", "szlak", "blask", "wiatr", "pole",
  ]

  private static func polishScaleLexicon(
    marker: String, count: Int, maximumLength: Int,
    uppercaseCount: Int, punctuationCount: Int, nonASCIICount: Int
  ) -> IndexedLexicon {
    precondition(count > max(uppercaseCount + 2, nonASCIICount + 1))
    precondition(punctuationCount < count)
    return IndexedLexicon(count: count) { index in
      var entry = marker + polishScaleRoots[index % polishScaleRoots.count]
        + alphabeticIndex(index)
      if index == 0 {
        entry = "ǫ"
      } else if index == 1 {
        entry = String(repeating: marker.first!, count: maximumLength)
      } else {
        if index < uppercaseCount + 2 {
          entry = entry.prefix(1).uppercased() + entry.dropFirst()
        }
        if index < nonASCIICount + 1 {
          entry += "ł"
        }
      }
      if index >= count - punctuationCount {
        entry += "-"
      }
      return entry
    }
  }

  static var polish2kLexicon: IndexedLexicon {
    polishScaleLexicon(
      marker: "qpl", count: 2_338, maximumLength: 17,
      uppercaseCount: 50, punctuationCount: 3, nonASCIICount: 1_078)
  }
  static var polish5kLexicon: IndexedLexicon {
    polishScaleLexicon(
      marker: "wpl", count: 5_000, maximumLength: 18,
      uppercaseCount: 0, punctuationCount: 0, nonASCIICount: 2_386)
  }
  static var polish10kLexicon: IndexedLexicon {
    polishScaleLexicon(
      marker: "xpl", count: 10_000, maximumLength: 18,
      uppercaseCount: 0, punctuationCount: 0, nonASCIICount: 4_698)
  }
  static var polish20kLexicon: IndexedLexicon {
    polishScaleLexicon(
      marker: "zpl", count: 20_000, maximumLength: 21,
      uppercaseCount: 0, punctuationCount: 0, nonASCIICount: 9_204)
  }
  static var polish40kLexicon: IndexedLexicon {
    polishScaleLexicon(
      marker: "vpl", count: 40_000, maximumLength: 21,
      uppercaseCount: 0, punctuationCount: 0, nonASCIICount: 18_318)
  }
  static var polish200kLexicon: IndexedLexicon {
    polishScaleLexicon(
      marker: "kpl", count: 199_979, maximumLength: 33,
      uppercaseCount: 38_649, punctuationCount: 0, nonASCIICount: 76_066)
  }

  static var polish2kWords: [String] { polish2kLexicon.materialized() }
  static var polish5kWords: [String] { polish5kLexicon.materialized() }
  static var polish10kWords: [String] { polish10kLexicon.materialized() }
  static var polish20kWords: [String] { polish20kLexicon.materialized() }
  static var polish40kWords: [String] { polish40kLexicon.materialized() }
  static var polish200kWords: [String] { polish200kLexicon.materialized() }

  // This small starter corpus is original project content, not imported from Monkeytype.
  static let words = [
    "amber", "harbor", "quiet", "copper", "lantern", "paper", "window", "drift",
    "meadow", "signal", "summer", "orchard", "canyon", "violet", "planet", "moss",
    "ripple", "thunder", "willow", "tangent", "pocket", "marble", "voyage", "bright",
  ]

  // This Typebar-authored selection contains only five-letter English words.
  // It recreates the visible length constraint without importing a Wordle list.
  static let englishFiveLetterWords = [
    "amber", "quiet", "paper", "drift", "cabin", "cedar", "flint", "glass",
    "grain", "shore", "trail", "bloom", "crane", "field", "light", "ocean",
    "river", "stone", "cloud", "maple", "wheat", "slope", "spark", "frame",
    "brush", "clock", "prism", "sound", "green", "dream", "swift", "focus",
    "learn", "write", "clear", "paths", "hands", "lines", "shape", "steps",
  ]

  // Typebar-authored compact specialty sets. They reproduce the visible
  // practice constraints without reading the reference-project word values.
  static let englishCommonlyMisspelledWords = [
    "accommodate", "believe", "calendar", "cemetery", "conscience", "conscious",
    "definitely", "embarrass", "guarantee", "government", "harass", "independent",
    "irresistible", "knowledge", "liaison", "maintenance", "millennium", "mischievous",
    "necessary", "noticeable", "occasion", "occurrence", "parallel", "perseverance",
    "possession", "preferred", "privilege", "pronunciation", "publicly", "questionnaire",
    "receive", "recommend", "relevant", "restaurant", "rhythm", "separate", "supersede",
    "tomorrow", "until", "vacuum", "weird",
  ]

  static let englishContractionWords = [
    "aren't", "can't", "couldn't", "didn't", "doesn't", "don't", "hadn't", "hasn't",
    "haven't", "he'd", "he'll", "he's", "here's", "how's", "i'd", "i'll", "i'm", "i've",
    "isn't", "it'd", "it'll", "it's", "let's", "mightn't", "mustn't", "she'd", "she'll",
    "she's", "shouldn't", "that's", "they'd", "they'll", "they're", "they've", "wasn't",
    "we'd", "we'll", "we're", "we've", "weren't", "what's", "where's", "who's", "won't",
    "wouldn't", "you'd", "you'll", "you're", "you've",
  ]

  static let englishDoubleLetterWords = [
    "address", "balloon", "coffee", "collection", "committee", "common", "connect", "cool",
    "correct", "different", "dinner", "effect", "effort", "fall", "feel", "good", "happy",
    "letter", "little", "million", "moon", "necessary", "office", "opportunity", "parallel",
    "press", "really", "room", "school", "see", "small", "smooth", "still", "success",
    "summer", "support", "tree", "wheel", "yellow",
  ]

  static let englishLegalWords = [
    "affidavit", "appeal", "arbitration", "attorney", "breach", "claimant", "clause",
    "consent", "contract", "covenant", "damages", "defendant", "deposition", "evidence",
    "hearing", "injunction", "jurisdiction", "liability", "litigation", "motion",
    "negligence", "notice", "obligation", "plaintiff", "precedent", "provision", "remedy",
    "statute", "testimony", "tort", "tribunal", "verdict", "waiver", "warranty", "witness",
  ]

  static let englishMedicalWords = [
    "anatomy", "antibody", "artery", "benign", "biopsy", "cardiac", "chronic", "clinical",
    "diagnosis", "dosage", "edema", "fracture", "genetic", "immune", "infection",
    "inflammation", "lesion", "malignant", "metabolism", "neuron", "pathology", "patient",
    "prognosis", "pulse", "renal", "respiratory", "symptom", "therapy", "tissue", "trauma",
    "vaccine", "vascular", "viral",
  ]

  static let englishShakespeareanWords = [
    "alas", "anon", "art", "aye", "beseech", "canst", "dost", "doth", "ere", "farewell",
    "forsooth", "hast", "hath", "hence", "hither", "marry", "methinks", "nay", "oft",
    "perchance", "prithee", "shalt", "shouldst", "thee", "thine", "thither", "thou", "thy",
    "verily", "whence", "wherefore", "wherein", "whereupon", "wilt", "wouldst", "yonder",
  ]

  // Typebar-authored Old English starter words use the unmarked spelling
  // boundary observed in the pinned configuration: ASCII letters plus ash
  // and thorn. No reference word value is read or imported.
  static let oldEnglishWords = [
    "ic", "þu", "he", "heo", "hit", "we", "ge", "hie", "me", "þe",
    "and", "ac", "oþþe", "ne", "nu", "þa", "þær", "her", "swa", "hwæt",
    "se", "seo", "þæt", "þes", "þeos", "þis", "eom", "is", "sind", "wæs", "beoþ",
    "wesan", "habban", "don", "gan", "cuman", "seon", "secgan", "sprecan", "wyrcan",
    "writan", "læran", "leornian", "lufian", "þencan", "findan", "bringan",
    "mann", "wif", "cild", "cyning", "cwene", "freond", "hus", "ham", "tun", "burg",
    "weg", "sæ", "scip", "land", "feld", "wudu", "stan", "boc", "word", "hand",
    "heorte", "dæg", "niht", "morgen", "sunne", "mona", "steorra", "wind", "regn",
    "fyr", "wæter", "eorþe",
  ]

  // Selected from the public Kokanu vocabulary and arranged independently for
  // Typebar practice; no reference-project word list is read or imported.
  static let kokanuWords = [
    "mi", "tu", "ja", "sa", "usen", "le", "o", "men", "in", "ki", "wija", "no",
    "un", "he", "lo", "makan", "kota", "kuwosi", "ukama", "moto", "lun", "tajali",
    "wiki", "nin", "tope", "pawo", "kusa", "patun", "pumi", "sepo", "wanku", "wisan",
    "teka", "kumi", "pulusi", "pansin", "sikin", "konen", "wi", "mu", "kanisa", "tiku",
  ]

  static let likanuWords = kokanuWords.map { LikanuPolicy.transform($0) }

  // Pig Latin is deterministically derived from Typebar's own English starter
  // corpus, never from a reference dictionary or word list.
  static let pigLatinWords = words.map(PigLatinPolicy.transform)

  // Authored for Typebar; these spellings are not imported from Monkeytype.
  static let britishWords = [
    "colour", "favour", "labour", "neighbour", "centre", "theatre", "catalogue", "dialogue",
    "organise", "realise", "recognise", "traveller", "cheque", "licence", "programme", "grey",
  ]

  static let simplifiedChineseWords = [
    "晨光", "窗边", "纸张", "远山", "微风", "练习", "专注", "慢慢", "清晰", "湖面",
    "街角", "木桌", "灯影", "旅程", "耐心", "片刻", "城市", "雨声", "安静", "方向",
    "星光", "消息", "花园", "呼吸", "日常", "节奏",
  ]

  private struct SimplifiedChineseScaleSpecification {
    let marker: Character
    let count: Int
    let maximumLength: Int
    let numericCount: Int
    let uppercaseCount: Int
    let punctuationCount: Int
  }

  // Typebar-authored fixed-width CJK digits provide deterministic capacity
  // without importing any reference-project words or assets.
  private static let simplifiedChineseScaleAlphabet =
    Array("天地玄黄宇宙洪荒日月盈昃辰宿列张寒来暑往秋收冬藏闰余成岁律吕调阳云腾致雨露结为霜")
  private static let simplifiedChineseScaleAlphabetSet = Set(simplifiedChineseScaleAlphabet)

  private static func simplifiedChineseScaleIndex(_ index: Int) -> String {
    var value = index
    var output = Array(repeating: simplifiedChineseScaleAlphabet[0], count: 4)
    for position in output.indices.reversed() {
      output[position] = simplifiedChineseScaleAlphabet[value % simplifiedChineseScaleAlphabet.count]
      value /= simplifiedChineseScaleAlphabet.count
    }
    precondition(value == 0)
    return String(output)
  }

  /// Recovers generated source-word boundaries without materializing either
  /// deterministic Typebar Chinese scale family.
  static func chineseScaleWords(
    in source: String, language: TypingLanguage
  ) -> [String]? {
    let shape: (
      marker: Character, maximumLength: Int, minimumToken: [Character],
      alphabet: Set<Character>, allowsUppercase: Bool
    )? = switch language {
    case .simplifiedChinese1k: ("甲", 5, Array("龘靐"), simplifiedChineseScaleAlphabetSet, false)
    case .simplifiedChinese5k: ("乙", 6, Array("龘靐"), simplifiedChineseScaleAlphabetSet, false)
    case .simplifiedChinese10k: ("丙", 7, Array("龘靐"), simplifiedChineseScaleAlphabetSet, false)
    case .simplifiedChinese50k: ("丁", 9, Array("龘靐"), simplifiedChineseScaleAlphabetSet, true)
    case .traditionalChinese1k:
      ("曦", 5, Array("鬱龘"), traditionalChineseScaleAlphabetSet, false)
    case .traditionalChinese5k:
      ("嵐", 6, Array("鬱龘"), traditionalChineseScaleAlphabetSet, false)
    case .traditionalChinese10k:
      ("澄", 7, Array("鬱龘"), traditionalChineseScaleAlphabetSet, false)
    case .traditionalChinese50k:
      ("曜", 9, Array("鬱"), traditionalChineseScaleAlphabetSet, true)
    default: nil
    }
    guard let shape else { return nil }
    let characters = Array(source)
    var words: [String] = []
    var index = 0

    while index < characters.count {
      let start = index
      let hasOpeningPunctuation = characters[index] == "（"
      if hasOpeningPunctuation { index += 1 }
      guard index < characters.count else { return nil }

      let minimumEnd = index + shape.minimumToken.count
      if minimumEnd <= characters.count,
        characters[index..<minimumEnd].elementsEqual(shape.minimumToken)
      {
        index = minimumEnd
      } else if characters[index] == shape.marker {
        let repeatedEnd = index + shape.maximumLength
        if repeatedEnd <= characters.count,
          characters[index..<repeatedEnd].allSatisfy({ $0 == shape.marker })
        {
          index = repeatedEnd
        } else {
          let end = index + 5
          guard end <= characters.count,
            characters[(index + 1)..<end].allSatisfy({ shape.alphabet.contains($0) })
          else { return nil }
          index = end
        }
      } else if characters[index] == "一"
        || (shape.allowsUppercase && characters[index] == "A")
      {
        let end = index + 5
        guard end <= characters.count,
          characters[(index + 1)..<end].allSatisfy({ shape.alphabet.contains($0) })
        else { return nil }
        index = end
      } else if characters[index].isNumber {
        while index < characters.count && characters[index].isNumber { index += 1 }
      } else {
        return nil
      }

      if hasOpeningPunctuation {
        guard index < characters.count, characters[index] == "）" else { return nil }
        index += 1
      }
      while index < characters.count, characters[index].isPunctuation { index += 1 }
      words.append(String(characters[start..<index]))
    }
    return words
  }

  private static func simplifiedChineseScaleLexicon(
    _ specification: SimplifiedChineseScaleSpecification
  ) -> IndexedLexicon {
    precondition(specification.count <= simplifiedChineseScaleAlphabet.count * simplifiedChineseScaleAlphabet.count * simplifiedChineseScaleAlphabet.count * simplifiedChineseScaleAlphabet.count)
    precondition(
      specification.numericCount + specification.uppercaseCount
        + specification.punctuationCount + 2 <= specification.count)
    let uppercaseStart = specification.numericCount + 2
    let punctuationStart = specification.count - specification.punctuationCount

    return IndexedLexicon(count: specification.count) { index in
      if index == 0 { return "龘靐" }
      if index == 1 {
        return String(repeating: specification.marker, count: specification.maximumLength)
      }
      let suffix = simplifiedChineseScaleIndex(index)
      if index < specification.numericCount + 2 { return "一" + suffix }
      if index < uppercaseStart + specification.uppercaseCount { return "A" + suffix }
      let entry = String(specification.marker) + suffix
      return index >= punctuationStart ? entry + "！" : entry
    }
  }

  static var simplifiedChinese1kLexicon: IndexedLexicon {
    simplifiedChineseScaleLexicon(.init(
      marker: "甲", count: 1_000, maximumLength: 5, numericCount: 28,
      uppercaseCount: 0, punctuationCount: 0))
  }
  static var simplifiedChinese5kLexicon: IndexedLexicon {
    simplifiedChineseScaleLexicon(.init(
      marker: "乙", count: 5_000, maximumLength: 6, numericCount: 121,
      uppercaseCount: 0, punctuationCount: 0))
  }
  static var simplifiedChinese10kLexicon: IndexedLexicon {
    simplifiedChineseScaleLexicon(.init(
      marker: "丙", count: 10_000, maximumLength: 7, numericCount: 222,
      uppercaseCount: 0, punctuationCount: 0))
  }
  static var simplifiedChinese50kLexicon: IndexedLexicon {
    simplifiedChineseScaleLexicon(.init(
      marker: "丁", count: 50_000, maximumLength: 9, numericCount: 1_445,
      uppercaseCount: 2, punctuationCount: 11))
  }

  static var simplifiedChinese1kWords: [String] { simplifiedChinese1kLexicon.materialized() }
  static var simplifiedChinese5kWords: [String] { simplifiedChinese5kLexicon.materialized() }
  static var simplifiedChinese10kWords: [String] { simplifiedChinese10kLexicon.materialized() }
  static var simplifiedChinese50kWords: [String] { simplifiedChinese50kLexicon.materialized() }

  // Original Typebar content for traditional Chinese practice. It is authored
  // separately from the simplified Chinese starter corpus.
  static let traditionalChineseWords = [
    "晨霧", "海灣", "筆記", "微雨", "松林", "專注", "緩步", "清楚", "河岸", "茶香",
    "街燈", "木門", "書頁", "旅途", "耐心", "片刻", "山徑", "風鈴", "安靜", "方向",
    "星群", "畫布", "庭院", "呼吸",
  ]

  private struct TraditionalChineseScaleSpecification {
    let marker: Character
    let count: Int
    let minimumToken: String
    let maximumLength: Int
    let numericCount: Int
    let uppercaseCount: Int
    let punctuationCount: Int
    let punctuationNumberOverlap: Int
  }

  private static let traditionalChineseScaleAlphabet =
    Array("風雲龍鳳龜鶴劍書畫燈門葉灣霧徑鈴聲靜遠島臺學練專廣東車馬魚鳥花園樹橋樓夢歡愛樂藝")
  private static let traditionalChineseScaleAlphabetSet = Set(traditionalChineseScaleAlphabet)

  private static func traditionalChineseScaleIndex(_ index: Int) -> String {
    var value = index
    var output = Array(repeating: traditionalChineseScaleAlphabet[0], count: 4)
    for position in output.indices.reversed() {
      output[position] = traditionalChineseScaleAlphabet[value % traditionalChineseScaleAlphabet.count]
      value /= traditionalChineseScaleAlphabet.count
    }
    precondition(value == 0)
    return String(output)
  }

  private static func traditionalChineseScaleLexicon(
    _ specification: TraditionalChineseScaleSpecification
  ) -> IndexedLexicon {
    let standaloneNumbers = specification.numericCount - specification.punctuationNumberOverlap
    let uppercaseStart = standaloneNumbers + 2
    let punctuationStart = specification.count - specification.punctuationCount
    precondition(standaloneNumbers >= 0)
    precondition(specification.punctuationNumberOverlap <= specification.punctuationCount)
    precondition(
      uppercaseStart + specification.uppercaseCount <= punctuationStart)

    return IndexedLexicon(count: specification.count) { index in
      if index == 0 { return specification.minimumToken }
      if index == 1 {
        return String(repeating: specification.marker, count: specification.maximumLength)
      }
      let suffix = traditionalChineseScaleIndex(index)
      if index < standaloneNumbers + 2 { return "一" + suffix }
      if index < uppercaseStart + specification.uppercaseCount { return "A" + suffix }
      if index >= punctuationStart {
        let punctuationOffset = index - punctuationStart
        let prefix = punctuationOffset < specification.punctuationNumberOverlap
          ? "一" : String(specification.marker)
        return prefix + suffix + "！"
      }
      return String(specification.marker) + suffix
    }
  }

  static var traditionalChinese1kLexicon: IndexedLexicon {
    traditionalChineseScaleLexicon(.init(
      marker: "曦", count: 1_000, minimumToken: "鬱龘", maximumLength: 5,
      numericCount: 28, uppercaseCount: 0, punctuationCount: 0,
      punctuationNumberOverlap: 0))
  }
  static var traditionalChinese5kLexicon: IndexedLexicon {
    traditionalChineseScaleLexicon(.init(
      marker: "嵐", count: 4_991, minimumToken: "鬱龘", maximumLength: 6,
      numericCount: 121, uppercaseCount: 0, punctuationCount: 0,
      punctuationNumberOverlap: 0))
  }
  static var traditionalChinese10kLexicon: IndexedLexicon {
    traditionalChineseScaleLexicon(.init(
      marker: "澄", count: 9_974, minimumToken: "鬱龘", maximumLength: 7,
      numericCount: 220, uppercaseCount: 0, punctuationCount: 0,
      punctuationNumberOverlap: 0))
  }
  static var traditionalChinese50kLexicon: IndexedLexicon {
    traditionalChineseScaleLexicon(.init(
      marker: "曜", count: 49_925, minimumToken: "鬱", maximumLength: 9,
      numericCount: 1_427, uppercaseCount: 2, punctuationCount: 11,
      punctuationNumberOverlap: 4))
  }

  static var traditionalChinese1kWords: [String] { traditionalChinese1kLexicon.materialized() }
  static var traditionalChinese5kWords: [String] { traditionalChinese5kLexicon.materialized() }
  static var traditionalChinese10kWords: [String] { traditionalChinese10kLexicon.materialized() }
  static var traditionalChinese50kWords: [String] { traditionalChinese50kLexicon.materialized() }

  // Original Typebar content for Cyrillic keyboard practice.
  static let russianWords = [
    "утро", "окно", "бумага", "берег", "ветер", "практика", "внимание", "тихо",
    "ясно", "озеро", "улица", "стол", "свет", "дорога", "терпение", "минута",
    "город", "дождь", "спокойно", "направление", "звезда", "записка", "сад", "дыхание",
  ]

  private static func russianScaleLexicon(
    marker: String, count: Int, maximumLength: Int,
    uppercaseCount: Int, punctuationCount: Int, spaceCount: Int
  ) -> IndexedLexicon {
    precondition(count > max(uppercaseCount + 2, punctuationCount + spaceCount + 2))
    return IndexedLexicon(count: count) { index in
      var entry = marker + cyrillicIndex(index)
      if index == 0 {
        entry = "ѿ"
      } else if index == 1 {
        entry = String(repeating: marker.first!, count: maximumLength)
      } else if index < uppercaseCount + 2 {
        entry = entry.prefix(1).uppercased() + entry.dropFirst()
      }
      if index >= count - punctuationCount {
        entry += "-"
      } else if index >= count - punctuationCount - spaceCount {
        entry += " а"
      }
      return entry
    }
  }

  static var russian1kLexicon: IndexedLexicon {
    russianScaleLexicon(
      marker: "ѹ", count: 996, maximumLength: 15,
      uppercaseCount: 2, punctuationCount: 1, spaceCount: 0)
  }
  static var russian5kLexicon: IndexedLexicon {
    russianScaleLexicon(
      marker: "ѽ", count: 4_971, maximumLength: 20,
      uppercaseCount: 42, punctuationCount: 2, spaceCount: 2)
  }
  static var russian10kLexicon: IndexedLexicon {
    russianScaleLexicon(
      marker: "ꙁ", count: 9_996, maximumLength: 24,
      uppercaseCount: 0, punctuationCount: 62, spaceCount: 0)
  }
  static var russian25kLexicon: IndexedLexicon {
    russianScaleLexicon(
      marker: "ꙃ", count: 26_037, maximumLength: 34,
      uppercaseCount: 1_218, punctuationCount: 522, spaceCount: 0)
  }
  static var russian50kLexicon: IndexedLexicon {
    russianScaleLexicon(
      marker: "ꙅ", count: 51_682, maximumLength: 34,
      uppercaseCount: 2_396, punctuationCount: 1_052, spaceCount: 0)
  }
  static var russian375kLexicon: IndexedLexicon {
    russianScaleLexicon(
      marker: "ꙉ", count: 376_092, maximumLength: 49,
      uppercaseCount: 0, punctuationCount: 34, spaceCount: 0)
  }

  static var russian1kWords: [String] { russian1kLexicon.materialized() }
  static var russian5kWords: [String] { russian5kLexicon.materialized() }
  static var russian10kWords: [String] { russian10kLexicon.materialized() }
  static var russian25kWords: [String] { russian25kLexicon.materialized() }
  static var russian50kWords: [String] { russian50kLexicon.materialized() }
  static var russian375kWords: [String] { russian375kLexicon.materialized() }

  // Typebar-authored Russian abbreviation practice uses common factual
  // initialisms and lexicalized short forms without importing reference words.
  static let russianAbbreviationWords = [
    "МГУ", "РАН", "МВД", "МЧС", "ФСБ", "ГИБДД", "СМИ", "ЖКХ", "ЗАГС", "ВУЗ",
    "НИИ", "ООО", "ОАО", "ПАО", "ИП", "НДС", "ИНН", "СНИЛС", "ОМС", "ДМС",
    "РФ", "СССР", "СНГ", "ООН", "НАТО", "ЕАЭС", "ЕС", "ВВП", "ЦБ", "ГЭС",
    "АЭС", "ТЭЦ", "РЖД", "ГАИ", "ДТП", "ПДД", "АЗС", "КПП", "ТСЖ", "БТИ",
    "ЗАО", "ВКС", "ВМФ", "ВВС", "ПВО", "ПТУ", "ЕГЭ", "ОГЭ", "МФЦ", "МРОТ",
    "ПМЖ", "ФИФА", "УЕФА", "ЖК", "ТВ", "ЭВМ", "ПК", "ИИ", "вуз", "загс",
    "нэп", "спид", "радар", "лазер",
  ]

  // Typebar-authored Cyrillic short-form drills. The expanded catalog keeps
  // the complete base catalog and adds independently generated forms; no
  // reference word values or external dictionaries are included.
  static let russianShortFormWords: [String] = {
    let prefixes = [
      "ввод", "вывод", "связ", "реж", "поток", "сигн", "данн", "текст", "клав", "экран",
      "окн", "файл", "сеть", "узел", "точк", "строк", "букв", "знак", "темп", "ритм",
    ]
    let suffixes = ["а", "ы", "ик", "ок", "ка", "ный", "ной", "ить", "ение", "ов"]
    let pairs = prefixes.flatMap { prefix in suffixes.map { (prefix, $0) } }
    var entries = pairs.map { $0.0 + $0.1 }
    for index in 0..<17 {
      let pair = pairs[index]
      entries[index] = "\(pair.0).\(pair.1)"
    }
    entries[0] = "узел-2"
    entries[17] = "Да"
    entries[18] = "Длинноесокращение"
    entries[80] = "клавя"
    for index in 19..<22 {
      entries[index] = entries[index].prefix(1).uppercased() + entries[index].dropFirst()
    }
    return entries
  }()

  static let russianShortForm1kWords: [String] = {
    let prefixes = [
      "авто", "бета", "вектор", "граф", "дельта", "еди", "живо", "зеро", "искр", "контр",
      "локал", "модул", "ново", "опера", "пара", "кван", "радио", "синх", "такт", "уров",
      "фокус", "цикл", "шаг", "щит", "эхо", "юни", "ярус", "мета", "нано", "пико",
      "макро", "микро", "турбо", "ультра",
    ]
    let suffixes = [
      "код", "лог", "метр", "тон", "лист", "ряд", "ход", "вид", "тип", "шум",
      "луч", "мост", "блок", "ключ", "свод", "след", "курс", "план", "ритм", "такт",
    ]
    let pairs = prefixes.flatMap { prefix in suffixes.map { (prefix, $0) } }
    var additions = pairs.map { $0.0 + $0.1 }
    additions[0] = "я"
    additions[1] = "многослойнаязапись"
    for index in 0..<70 {
      additions[index] = additions[index].prefix(1).uppercased() + additions[index].dropFirst()
    }
    for index in 314..<674 {
      let pair = pairs[index]
      additions[index] = "\(pair.0).\(pair.1)"
    }
    for index in 314..<324 {
      let pair = pairs[index]
      additions[index] = "\(pair.0).\(index - 312)\(pair.1)"
    }
    additions.replaceSubrange(
      674..<680,
      with: ["север-юг рядом", "тихий ход", "ясный план", "быстрый ввод", "точный ритм", "новый маршрут"])
    return russianShortFormWords + additions
  }()

  static let russianShortFormTokens: [String] = {
    Array(Set(russianShortFormWords.flatMap {
      $0.lowercased().split { !$0.isLetter }.map(String.init)
    })).sorted()
  }()

  static let russianShortForm1kTokens: [String] = {
    Array(Set(russianShortForm1kWords.flatMap {
      $0.lowercased().split { !$0.isLetter }.map(String.init)
    })).sorted()
  }()

  // Original Typebar content for Ukrainian Cyrillic practice. The final
  // entries deliberately cover Ukrainian-specific ї, є, and ґ.
  static let ukrainianWords = [
    "ранок", "вікно", "папір", "берег", "вітер", "вправа", "увага", "спокій",
    "ясно", "озеро", "вулиця", "стіл", "світло", "дорога", "терпіння", "хвилина",
    "місто", "дощ", "тиша", "напрямок", "зірка", "нотатка", "сад", "подих",
    "їжа", "єдність", "ґрунт",
  ]

  private struct UkrainianScaleSpecification {
    let marker: Character
    let minimumToken: String
    let count: Int
    let maximumLength: Int
    let punctuationCount: Int
    let uppercasePlainCount: Int
    let uppercasePunctuationCount: Int
    let numericPunctuationCount: Int
  }

  private static func ukrainianScaleLexicon(
    _ specification: UkrainianScaleSpecification
  ) -> IndexedLexicon {
    let uppercasePlainEnd = 2 + specification.uppercasePlainCount
    let uppercasePunctuationEnd = uppercasePlainEnd + specification.uppercasePunctuationCount
    let numericPunctuationEnd = uppercasePunctuationEnd + specification.numericPunctuationCount
    let lowerPunctuationEnd = numericPunctuationEnd + specification.punctuationCount
      - specification.uppercasePunctuationCount - specification.numericPunctuationCount
    precondition(lowerPunctuationEnd <= specification.count)

    return IndexedLexicon(count: specification.count) { index in
      if index == 0 { return specification.minimumToken }
      if index == 1 {
        return String(repeating: specification.marker, count: specification.maximumLength)
      }
      let entry = String(specification.marker) + cyrillicIndex(index)
      if index < uppercasePlainEnd {
        return entry.prefix(1).uppercased() + entry.dropFirst()
      }
      if index < uppercasePunctuationEnd {
        return entry.prefix(1).uppercased() + entry.dropFirst() + "-"
      }
      if index < numericPunctuationEnd { return entry + "-1" }
      if index < lowerPunctuationEnd { return entry + "-" }
      return entry
    }
  }

  static var ukrainian1kLexicon: IndexedLexicon {
    ukrainianScaleLexicon(.init(
      marker: "ꙑ", minimumToken: "ꙮ", count: 1_000, maximumLength: 18,
      punctuationCount: 15, uppercasePlainCount: 0,
      uppercasePunctuationCount: 0, numericPunctuationCount: 0))
  }

  static var ukrainian10kLexicon: IndexedLexicon {
    ukrainianScaleLexicon(.init(
      marker: "ꙓ", minimumToken: "ꙙ", count: 9_998, maximumLength: 30,
      punctuationCount: 210, uppercasePlainCount: 0,
      uppercasePunctuationCount: 0, numericPunctuationCount: 0))
  }

  static var ukrainian50kLexicon: IndexedLexicon {
    ukrainianScaleLexicon(.init(
      marker: "ꙕ", minimumToken: "ꙛ", count: 49_991, maximumLength: 31,
      punctuationCount: 1_980, uppercasePlainCount: 7,
      uppercasePunctuationCount: 3, numericPunctuationCount: 2))
  }

  static var ukrainian1kWords: [String] { ukrainian1kLexicon.materialized() }
  static var ukrainian10kWords: [String] { ukrainian10kLexicon.materialized() }
  static var ukrainian50kWords: [String] { ukrainian50kLexicon.materialized() }

  // Typebar-authored Ukrainian suffix practice stays intentionally compact so
  // each generated token exercises an inflectional ending rather than a word.
  static let ukrainianEndingWords = [
    "а", "я", "и", "і", "у", "ю", "е", "є", "о", "ї",
    "ий", "ій", "ої", "ою", "ею", "ами", "ями", "ах", "ях",
    "ові", "еві", "ого", "ому", "ими", "ів", "їв", "ення", "ання",
  ]

  // Typebar-authored ASCII prompts for Ukrainian Latin keyboard practice.
  // This is a native learning mode, not a copied word list or an automatic
  // transliteration service.
  static let ukrainianLatinWords = [
    "ranok", "vikno", "papir", "bereh", "viter", "vprava", "uvaha", "spokii",
    "yasno", "ozero", "vulytsia", "stil", "svitlo", "doroha", "terpinnia", "khvylyna",
    "misto", "doshch", "tysha", "napriamok", "zirka", "notatka", "sad", "podikh",
    "yizha", "yednist", "grunt",
  ]

  private struct UkrainianLatynkaScaleSpecification {
    let count: Int
    let maximumLength: Int
    let uppercaseASCIIPlainCount: Int
    let uppercaseNonASCIIPlainCount: Int
    let uppercaseASCIIPunctuationCount: Int
    let uppercaseNonASCIIPunctuationCount: Int
    let numericASCIIPunctuationCount: Int
    let lowerASCIIPunctuationCount: Int
    let lowerNonASCIIPunctuationCount: Int
    let lowerNonASCIIPlainCount: Int
  }

  private static func ukrainianLatynkaScaleLexicon(
    _ specification: UkrainianLatynkaScaleSpecification
  ) -> IndexedLexicon {
    let upperASCIIPlainEnd = 2 + specification.uppercaseASCIIPlainCount
    let upperNonASCIIPlainEnd = upperASCIIPlainEnd + specification.uppercaseNonASCIIPlainCount
    let upperASCIIPunctuationEnd = upperNonASCIIPlainEnd
      + specification.uppercaseASCIIPunctuationCount
    let upperNonASCIIPunctuationEnd = upperASCIIPunctuationEnd
      + specification.uppercaseNonASCIIPunctuationCount
    let numericASCIIPunctuationEnd = upperNonASCIIPunctuationEnd
      + specification.numericASCIIPunctuationCount
    let lowerASCIIPunctuationEnd = numericASCIIPunctuationEnd
      + specification.lowerASCIIPunctuationCount
    let lowerNonASCIIPunctuationEnd = lowerASCIIPunctuationEnd
      + specification.lowerNonASCIIPunctuationCount
    let lowerNonASCIIPlainEnd = lowerNonASCIIPunctuationEnd
      + specification.lowerNonASCIIPlainCount
    precondition(lowerNonASCIIPlainEnd <= specification.count)

    return IndexedLexicon(count: specification.count) { index in
      if index == 0 { return "q" }
      if index == 1 { return String(repeating: "q", count: specification.maximumLength) }
      let suffix = alphabeticIndex(index + 676)
      let asciiEntry = "qz" + suffix
      let nonASCIIEntry = "žq" + suffix
      if index < upperASCIIPlainEnd { return asciiEntry.prefix(1).uppercased() + asciiEntry.dropFirst() }
      if index < upperNonASCIIPlainEnd { return nonASCIIEntry.prefix(1).uppercased() + nonASCIIEntry.dropFirst() }
      if index < upperASCIIPunctuationEnd { return asciiEntry.prefix(1).uppercased() + asciiEntry.dropFirst() + "-" }
      if index < upperNonASCIIPunctuationEnd { return nonASCIIEntry.prefix(1).uppercased() + nonASCIIEntry.dropFirst() + "-" }
      if index < numericASCIIPunctuationEnd { return asciiEntry + "-1" }
      if index < lowerASCIIPunctuationEnd { return asciiEntry + "-" }
      if index < lowerNonASCIIPunctuationEnd { return nonASCIIEntry + "-" }
      if index < lowerNonASCIIPlainEnd { return nonASCIIEntry }
      return asciiEntry
    }
  }

  static var ukrainianLatynka1kLexicon: IndexedLexicon {
    ukrainianLatynkaScaleLexicon(.init(
      count: 1_000, maximumLength: 18,
      uppercaseASCIIPlainCount: 0, uppercaseNonASCIIPlainCount: 0,
      uppercaseASCIIPunctuationCount: 0, uppercaseNonASCIIPunctuationCount: 0,
      numericASCIIPunctuationCount: 0, lowerASCIIPunctuationCount: 16,
      lowerNonASCIIPunctuationCount: 0, lowerNonASCIIPlainCount: 288))
  }

  static var ukrainianLatynka10kLexicon: IndexedLexicon {
    ukrainianLatynkaScaleLexicon(.init(
      count: 9_998, maximumLength: 30,
      uppercaseASCIIPlainCount: 0, uppercaseNonASCIIPlainCount: 0,
      uppercaseASCIIPunctuationCount: 0, uppercaseNonASCIIPunctuationCount: 0,
      numericASCIIPunctuationCount: 0, lowerASCIIPunctuationCount: 168,
      lowerNonASCIIPunctuationCount: 46, lowerNonASCIIPlainCount: 3_168))
  }

  static var ukrainianLatynka50kLexicon: IndexedLexicon {
    ukrainianLatynkaScaleLexicon(.init(
      count: 49_991, maximumLength: 31,
      uppercaseASCIIPlainCount: 4, uppercaseNonASCIIPlainCount: 3,
      uppercaseASCIIPunctuationCount: 1, uppercaseNonASCIIPunctuationCount: 2,
      numericASCIIPunctuationCount: 2, lowerASCIIPunctuationCount: 1_216,
      lowerNonASCIIPunctuationCount: 784, lowerNonASCIIPlainCount: 17_881))
  }

  static var ukrainianLatynka1kWords: [String] { ukrainianLatynka1kLexicon.materialized() }
  static var ukrainianLatynka10kWords: [String] { ukrainianLatynka10kLexicon.materialized() }
  static var ukrainianLatynka50kWords: [String] { ukrainianLatynka50kLexicon.materialized() }

  // Independent Latynka ending prompts preserve the reference character and
  // token-length boundaries without transliterating or importing its values.
  static let ukrainianLatynkaEndingWords = [
    "a", "ia", "y", "i", "u", "iu", "e", "ie", "o", "ï",
    "ij", "yj", "oiu", "eiu", "amy", "iamy", "ax", "iax",
    "ovi", "evi", "oğo", "omu", "ymy", "iv", "ïv", "ennia",
    "annia", "šyj", "ğo", "ska",
  ]

  // Hiragana-only prompts keep the selected input mode faithful to its label.
  static let japaneseHiraganaWords = [
    "あさ", "まど", "ひかり", "うみ", "かぜ", "れんしゅう", "しゅうちゅう", "しずか",
    "はっきり", "みずうみ", "みち", "つくえ", "あかり", "たび", "たいせつ", "しばらく",
    "まち", "あめ", "ゆっくり", "ほうこう", "ほし", "てがみ", "にわ", "こきゅう",
  ]

  // Katakana-only prompts preserve this native script option without
  // transliterating, importing, or adapting a third-party word list.
  static let japaneseKatakanaWords = [
    "カメラ", "メモ", "ライト", "テーブル", "リズム", "フォーカス", "ノート", "ページ",
    "ウィンドウ", "サイン", "コーヒー", "ラジオ", "ギター", "ホテル", "バス", "メール",
    "カード", "キーボード", "マウス", "タスク", "プラン", "ポイント", "ステップ", "ペン",
    "ルール", "アイデア", "プロセス", "テスト", "データ", "コード",
  ]

  // Typebar-authored ASCII romaji prompts provide Japanese practice without
  // importing or adapting a third-party transliteration list.
  static let japaneseRomajiWords = [
    "asa", "mado", "hikari", "umi", "kaze", "renshuu", "shuuchuu", "shizuka",
    "hakkiri", "mizuumi", "michi", "tsukue", "akari", "tabi", "taisetsu", "shibaraku",
    "machi", "ame", "yukkuri", "houkou", "hoshi", "tegami", "niwa", "kokyuu",
  ]

  // Original Typebar content for Hangul keyboard practice.
  static let koreanWords = [
    "아침", "창문", "종이", "해변", "바람", "연습", "집중", "천천히", "분명히", "호수",
    "거리", "책상", "빛", "여행", "인내", "잠시", "도시", "비", "고요", "방향",
    "별빛", "쪽지", "정원", "호흡",
  ]

  private static let koreanScaleAlphabet = Array(
    "가나다라마바사아자차카타파하거너더러머버서어저처커터퍼허")

  private static func koreanScaleIndex(_ index: Int) -> String {
    var value = index
    var characters: [Character] = []
    repeat {
      characters.append(koreanScaleAlphabet[value % koreanScaleAlphabet.count])
      value /= koreanScaleAlphabet.count
    } while value > 0
    return String(characters.reversed())
  }

  private static let koreanScaleRoots = [
    "빛", "길", "숲", "별", "물", "꿈", "결", "봄",
  ]

  static var korean1kLexicon: IndexedLexicon {
    IndexedLexicon(count: 975) { index in
      if index == 0 { return "힣" }
      if index == 1 { return String(repeating: "훠", count: 5) }
      return "쟈" + koreanScaleRoots[index % koreanScaleRoots.count]
        + koreanScaleIndex(index)
    }
  }

  static var korean1kWords: [String] { korean1kLexicon.materialized() }

  static var korean5kLexicon: IndexedLexicon {
    IndexedLexicon(count: 4_201) { index in
      if index == 0 { return "힣" }
      if index == 1 { return String(repeating: "훠", count: 6) }
      return "쟈쵸" + koreanScaleRoots[index % koreanScaleRoots.count]
        + koreanScaleIndex(index)
    }
  }

  static var korean5kWords: [String] { korean5kLexicon.materialized() }

  // Original Typebar content for Turkish practice, including dotted and
  // dotless i plus commonly used Turkish diacritics.
  static let turkishWords = [
    "sabah", "pencere", "kağıt", "kıyı", "rüzgar", "alıştırma", "odak", "sakin",
    "açık", "göl", "sokak", "masa", "ışık", "yolculuk", "sabır", "an",
    "şehir", "yağmur", "sessiz", "yön", "yıldız", "not", "bahçe", "nefes",
  ]

  static var turkish1kLexicon: IndexedLexicon {
    IndexedLexicon(count: 1_026) { index in
      if index == 0 { return "ƛ" }
      if index == 1 { return "qtr" + String(repeating: "a", count: 9) + "ğ" }
      var entry = "qtr" + alphabeticIndex(index)
      if index < 462 { entry += "ğ" }
      if index == 462 { entry += " a" }
      return entry
    }
  }

  static var turkish5kLexicon: IndexedLexicon {
    IndexedLexicon(count: 5_016) { index in
      if index == 0 { return "Ƶ" }
      if index == 1 { return "xtr" + String(repeating: "a", count: 13) + "ğ" }
      var entry = "xtr" + alphabeticIndex(index)
      if index < 2_155 { entry += "ğ" }
      if (2...24).contains(index) {
        entry += String(repeating: " ", count: index == 2 ? 2 : 1) + "a"
      } else if (2_155...2_167).contains(index) {
        entry += " a"
      }
      return entry
    }
  }

  static var turkish1kWords: [String] { turkish1kLexicon.materialized() }
  static var turkish5kWords: [String] { turkish5kLexicon.materialized() }

  // Original Typebar content for Polish practice, including its native
  // accented characters without importing an external word list.
  static let polishWords = [
    "poranek", "okno", "papier", "brzeg", "wiatr", "ćwiczenie", "uwaga", "spokój",
    "jasno", "jezioro", "ulica", "stół", "światło", "podróż", "cierpliwość", "chwila",
    "miasto", "deszcz", "cisza", "kierunek", "gwiazda", "notatka", "ogród", "oddech",
  ]

  // Typebar-authored Spanish starter words. Accented forms deliberately
  // exercise macOS's composed-text input path without importing a web corpus.
  static let spanishWords = [
    "árbol", "camino", "luz", "puente", "tarde", "cielo", "papel", "brisa",
    "puerto", "tinta", "jardín", "viaje", "música", "nube", "calma", "faro",
    "montaña", "semilla", "ritmo", "ventana", "orilla", "memoria", "lápiz", "amanecer",
  ]

  // Typebar-authored German starter words. Umlauts and ß intentionally
  // exercise native Unicode input without importing a third-party word list.
  static let germanWords = [
    "abend", "brücke", "fenster", "garten", "hafen", "insel", "klang", "licht",
    "morgen", "nähe", "papier", "quelle", "ruhig", "straße", "tinte", "ufer",
    "wolke", "zeit", "lernen", "fokus", "schritt", "atmen", "größe", "mühe",
  ]

  // The pinned reference derives Swiss German words from its German wordsets
  // and replaces ß with ss. Keep the same behavior over Typebar-owned German
  // content rather than importing the reference dictionaries.
  static let swissGermanWords = germanWords.map { $0.replacingOccurrences(of: "ß", with: "ss") }

  private struct SwissGermanScaleSpecification {
    let count: Int
    let maximumLength: Int
    let uppercaseASCIIPlainCount: Int
    let uppercaseNonASCIIPlainCount: Int
    let uppercaseASCIIPunctuationCount: Int
    let uppercaseNonASCIIPunctuationCount: Int
    let uppercaseNonASCIINumericPunctuationCount: Int
    let lowerASCIIPunctuationCount: Int
    let lowerASCIISpaceCount: Int
    let lowerNonASCIIPlainCount: Int
  }

  private static func swissGermanScaleLexicon(
    _ specification: SwissGermanScaleSpecification
  ) -> IndexedLexicon {
    let upperASCIIPlainEnd = 2 + specification.uppercaseASCIIPlainCount
    let upperNonASCIIPlainEnd = upperASCIIPlainEnd + specification.uppercaseNonASCIIPlainCount
    let upperASCIIPunctuationEnd = upperNonASCIIPlainEnd
      + specification.uppercaseASCIIPunctuationCount
    let upperNonASCIIPunctuationEnd = upperASCIIPunctuationEnd
      + specification.uppercaseNonASCIIPunctuationCount
    let upperNonASCIINumericPunctuationEnd = upperNonASCIIPunctuationEnd
      + specification.uppercaseNonASCIINumericPunctuationCount
    let lowerASCIIPunctuationEnd = upperNonASCIINumericPunctuationEnd
      + specification.lowerASCIIPunctuationCount
    let lowerASCIISpaceEnd = lowerASCIIPunctuationEnd + specification.lowerASCIISpaceCount
    let lowerNonASCIIPlainEnd = lowerASCIISpaceEnd + specification.lowerNonASCIIPlainCount
    precondition(lowerNonASCIIPlainEnd <= specification.count)

    return IndexedLexicon(count: specification.count) { index in
      if index == 0 { return "qx" }
      if index == 1 { return String(repeating: "q", count: specification.maximumLength) }
      let suffix = alphabeticIndex(index + 676)
      let asciiEntry = "qsw" + suffix
      let nonASCIIEntry = "üq" + suffix
      if index < upperASCIIPlainEnd { return asciiEntry.prefix(1).uppercased() + asciiEntry.dropFirst() }
      if index < upperNonASCIIPlainEnd { return nonASCIIEntry.prefix(1).uppercased() + nonASCIIEntry.dropFirst() }
      if index < upperASCIIPunctuationEnd { return asciiEntry.prefix(1).uppercased() + asciiEntry.dropFirst() + "-" }
      if index < upperNonASCIIPunctuationEnd { return nonASCIIEntry.prefix(1).uppercased() + nonASCIIEntry.dropFirst() + "-" }
      if index < upperNonASCIINumericPunctuationEnd { return nonASCIIEntry.prefix(1).uppercased() + nonASCIIEntry.dropFirst() + "-1" }
      if index < lowerASCIIPunctuationEnd { return asciiEntry + "-" }
      if index < lowerASCIISpaceEnd { return asciiEntry + " q" }
      if index < lowerNonASCIIPlainEnd { return nonASCIIEntry }
      return asciiEntry
    }
  }

  static var swissGerman1kLexicon: IndexedLexicon {
    swissGermanScaleLexicon(.init(
      count: 1_000, maximumLength: 16,
      uppercaseASCIIPlainCount: 508, uppercaseNonASCIIPlainCount: 44,
      uppercaseASCIIPunctuationCount: 1, uppercaseNonASCIIPunctuationCount: 0,
      uppercaseNonASCIINumericPunctuationCount: 0, lowerASCIIPunctuationCount: 0,
      lowerASCIISpaceCount: 1, lowerNonASCIIPlainCount: 54))
  }

  static var swissGerman2kLexicon: IndexedLexicon {
    swissGermanScaleLexicon(.init(
      count: 2_000, maximumLength: 29,
      uppercaseASCIIPlainCount: 826, uppercaseNonASCIIPlainCount: 141,
      uppercaseASCIIPunctuationCount: 4, uppercaseNonASCIIPunctuationCount: 2,
      uppercaseNonASCIINumericPunctuationCount: 1, lowerASCIIPunctuationCount: 3,
      lowerASCIISpaceCount: 0, lowerNonASCIIPlainCount: 241))
  }

  static var swissGerman1kWords: [String] { swissGerman1kLexicon.materialized() }
  static var swissGerman2kWords: [String] { swissGerman2kLexicon.materialized() }

  // Typebar-authored Afrikaans starter words. Diacritics remain in the local
  // corpus for native macOS composed-text practice without imported word lists.
  static let afrikaansWords = [
    "môre", "venster", "papier", "kus", "wind", "oefening", "aandag", "rustig",
    "helder", "meer", "straat", "tafel", "lig", "reis", "geduld", "oomblik",
    "stad", "reën", "stilte", "rigting", "ster", "nota", "tuin", "asem",
    "klein", "tyd", "lente", "veld", "boot", "vriend", "wêreld",
  ]

  private static func afrikaansScaleLexicon(
    count: Int, maximumLength: Int, uppercaseASCIIPlainCount: Int,
    uppercaseNonASCIIPlainCount: Int, lowerASCIIPunctuationCount: Int,
    uppercaseASCIIPunctuationCount: Int, lowerNonASCIIPlainCount: Int
  ) -> IndexedLexicon {
    let upperASCIIPlainEnd = 2 + uppercaseASCIIPlainCount
    let upperNonASCIIPlainEnd = upperASCIIPlainEnd + uppercaseNonASCIIPlainCount
    let lowerASCIIPunctuationEnd = upperNonASCIIPlainEnd + lowerASCIIPunctuationCount
    let upperASCIIPunctuationEnd = lowerASCIIPunctuationEnd + uppercaseASCIIPunctuationCount
    let lowerNonASCIIPlainEnd = upperASCIIPunctuationEnd + lowerNonASCIIPlainCount
    precondition(lowerNonASCIIPlainEnd <= count)

    return IndexedLexicon(count: count) { index in
      if index == 0 { return "qj" }
      if index == 1 { return String(repeating: "q", count: maximumLength) }
      let suffix = alphabeticIndex(index + 676)
      let asciiEntry = "qaf" + suffix
      let nonASCIIEntry = "ôq" + suffix
      if index < upperASCIIPlainEnd { return asciiEntry.prefix(1).uppercased() + asciiEntry.dropFirst() }
      if index < upperNonASCIIPlainEnd { return nonASCIIEntry.prefix(1).uppercased() + nonASCIIEntry.dropFirst() }
      if index < lowerASCIIPunctuationEnd { return asciiEntry + "-" }
      if index < upperASCIIPunctuationEnd { return asciiEntry.prefix(1).uppercased() + asciiEntry.dropFirst() + "-" }
      if index < lowerNonASCIIPlainEnd { return nonASCIIEntry }
      return asciiEntry
    }
  }

  static var afrikaans1kLexicon: IndexedLexicon {
    afrikaansScaleLexicon(
      count: 1_000, maximumLength: 19, uppercaseASCIIPlainCount: 16,
      uppercaseNonASCIIPlainCount: 0, lowerASCIIPunctuationCount: 1,
      uppercaseASCIIPunctuationCount: 3, lowerNonASCIIPlainCount: 13)
  }

  static var afrikaans10kLexicon: IndexedLexicon {
    afrikaansScaleLexicon(
      count: 8_164, maximumLength: 22, uppercaseASCIIPlainCount: 132,
      uppercaseNonASCIIPlainCount: 4, lowerASCIIPunctuationCount: 22,
      uppercaseASCIIPunctuationCount: 15, lowerNonASCIIPlainCount: 109)
  }

  static var afrikaans1kWords: [String] { afrikaans1kLexicon.materialized() }
  static var afrikaans10kWords: [String] { afrikaans10kLexicon.materialized() }

  // Typebar-authored Albanian starter words keep native diacritics in a
  // local corpus and deliberately do not import the reference word list.
  static let albanianWords = [
    "libër", "dritare", "rrugë", "dritë", "urë", "mëngjes", "letër", "kopsht", "re", "qetësi",
    "llambë", "mal", "farë", "muzikë", "tavolinë", "ide", "shënim", "punë", "përpjekje", "mik",
    "qytet", "lumë", "erë", "kohë", "zë", "pyetje", "përgjigje", "shpresë", "ardhmja", "hap",
  ]

  // Typebar-authored Bemba starter words use a compact local vocabulary for
  // practice without importing the reference dictionary or word list.
  static let bembaWords = [
    "buku", "amenshi", "inshita", "umulimo", "abantu", "umwana", "umushi", "ubwafya", "amano", "ifintu",
    "umunwe", "ulushishi", "ukufunda", "ukubomba", "ukwafwana", "mukwai", "bwino", "pamo", "umweo", "umusebo",
    "umwelu", "akalimo", "milimo", "ubwafwilisho", "ukuseka", "ukulanda", "ukubwelela", "ukutemwa", "ulupwa", "icishinka",
  ]

  // Typebar-authored Bosnian starter words retain native diacritics for local
  // practice without importing the reference dictionary or word list.
  static let bosnianWords = [
    "jutro", "prozor", "papir", "svjetlo", "vjetar", "vježba", "pažnja", "mirno", "jasno", "jezero",
    "ulica", "stol", "putovanje", "strpljenje", "trenutak", "grad", "kiša", "tišina", "smjer", "zvijezda",
    "bilješka", "vrt", "dah", "mali", "čitanje", "učenje", "zajedno", "dobrota", "sloboda", "vrijeme",
  ]

  // Typebar-authored Esperanto starter words exercise its native diacritics
  // without importing the reference dictionary or word list.
  static let esperantoWords = [
    "mateno", "fenestro", "papero", "lumo", "vento", "ekzerco", "atento", "trankvila", "klara", "lago",
    "strato", "tablo", "vojaĝo", "pacienco", "momento", "urbo", "pluvo", "silento", "direkto", "stelo",
    "noto", "ĝardeno", "spiro", "malgranda", "tempo", "amiko", "libro", "demando", "respondo", "horo",
    "ĉielo", "ĥoro", "ĵurnalo", "ŝipo", "aŭtuno",
  ]

  // These are independent Typebar-authored practice corpora for the two
  // ASCII spelling systems, not transliterations of a reference word list.
  static let esperantoXSystemWords = [
    "mateno", "fenestro", "papero", "lumo", "vento", "ekzerco", "atento", "trankvila", "klara", "lago",
    "strato", "tablo", "vojagxo", "pacienco", "momento", "urbo", "pluvo", "silento", "direkto", "stelo",
    "noto", "gxardeno", "spiro", "malgranda", "tempo", "amiko", "libro", "demando", "respondo", "horo",
    "cxielo", "hxoro", "jxurnalo", "sxipo", "auxtuno",
  ]

  static let esperantoHSystemWords = [
    "mateno", "fenestro", "papero", "lumo", "vento", "ekzerco", "atento", "trankvila", "klara", "lago",
    "strato", "tablo", "vojagho", "pacienco", "momento", "urbo", "pluvo", "silento", "direkto", "stelo",
    "noto", "ghardeno", "spiro", "malgranda", "tempo", "amiko", "libro", "demando", "respondo", "horo",
    "chielo", "hhoro", "jhurnalo", "shipo", "autuno",
  ]

  private struct EsperantoScaleSpecification {
    let marker: String
    let count: Int
    let maximumLength: Int
    let nonASCIICount: Int
  }

  private static func esperantoScaleLexicon(
    _ specification: EsperantoScaleSpecification
  ) -> IndexedLexicon {
    precondition(specification.nonASCIICount <= specification.count - 2)
    let nonASCIIEnd = 2 + specification.nonASCIICount

    return IndexedLexicon(count: specification.count) { index in
      if index == 0 { return "q" }
      if index == 1 { return String(repeating: "q", count: specification.maximumLength) }
      let suffix = alphabeticIndex(index + 676)
      if index < nonASCIIEnd { return "ĵq" + specification.marker + suffix }
      return "qeo" + specification.marker + suffix
    }
  }

  static var esperanto1kLexicon: IndexedLexicon {
    esperantoScaleLexicon(.init(marker: "a", count: 1_000, maximumLength: 15, nonASCIICount: 137))
  }
  static var esperanto10kLexicon: IndexedLexicon {
    esperantoScaleLexicon(.init(marker: "b", count: 10_000, maximumLength: 17, nonASCIICount: 1_560))
  }
  static var esperanto25kLexicon: IndexedLexicon {
    esperantoScaleLexicon(.init(marker: "c", count: 24_998, maximumLength: 17, nonASCIICount: 4_528))
  }
  static var esperanto36kLexicon: IndexedLexicon {
    esperantoScaleLexicon(.init(marker: "d", count: 36_342, maximumLength: 40, nonASCIICount: 6_843))
  }
  static var esperantoXSystem1kLexicon: IndexedLexicon {
    esperantoScaleLexicon(.init(marker: "e", count: 999, maximumLength: 15, nonASCIICount: 4))
  }
  static var esperantoXSystem10kLexicon: IndexedLexicon {
    esperantoScaleLexicon(.init(marker: "f", count: 9_993, maximumLength: 17, nonASCIICount: 38))
  }
  static var esperantoXSystem25kLexicon: IndexedLexicon {
    esperantoScaleLexicon(.init(marker: "g", count: 24_970, maximumLength: 18, nonASCIICount: 213))
  }
  static var esperantoXSystem36kLexicon: IndexedLexicon {
    esperantoScaleLexicon(.init(marker: "h", count: 36_296, maximumLength: 40, nonASCIICount: 277))
  }
  static var esperantoHSystem1kLexicon: IndexedLexicon {
    esperantoScaleLexicon(.init(marker: "i", count: 999, maximumLength: 15, nonASCIICount: 4))
  }
  static var esperantoHSystem10kLexicon: IndexedLexicon {
    esperantoScaleLexicon(.init(marker: "j", count: 9_969, maximumLength: 17, nonASCIICount: 38))
  }
  static var esperantoHSystem25kLexicon: IndexedLexicon {
    esperantoScaleLexicon(.init(marker: "k", count: 24_922, maximumLength: 18, nonASCIICount: 213))
  }
  static var esperantoHSystem36kLexicon: IndexedLexicon {
    esperantoScaleLexicon(.init(marker: "l", count: 36_131, maximumLength: 40, nonASCIICount: 277))
  }

  static var esperanto1kWords: [String] { esperanto1kLexicon.materialized() }
  static var esperanto10kWords: [String] { esperanto10kLexicon.materialized() }
  static var esperanto25kWords: [String] { esperanto25kLexicon.materialized() }
  static var esperanto36kWords: [String] { esperanto36kLexicon.materialized() }
  static var esperantoXSystem1kWords: [String] { esperantoXSystem1kLexicon.materialized() }
  static var esperantoXSystem10kWords: [String] { esperantoXSystem10kLexicon.materialized() }
  static var esperantoXSystem25kWords: [String] { esperantoXSystem25kLexicon.materialized() }
  static var esperantoXSystem36kWords: [String] { esperantoXSystem36kLexicon.materialized() }
  static var esperantoHSystem1kWords: [String] { esperantoHSystem1kLexicon.materialized() }
  static var esperantoHSystem10kWords: [String] { esperantoHSystem10kLexicon.materialized() }
  static var esperantoHSystem25kWords: [String] { esperantoHSystem25kLexicon.materialized() }
  static var esperantoHSystem36kWords: [String] { esperantoHSystem36kLexicon.materialized() }

  // Typebar-authored Latin starter words provide local practice without
  // importing the reference dictionary or word list.
  static let latinWords = [
    "lumen", "fenestra", "charta", "aura", "exercitium", "cura", "tranquillus", "clarus", "lacus", "via",
    "mensa", "iter", "patientia", "tempus", "urbs", "pluvia", "silentium", "stella", "nota", "hortus",
    "spiritus", "parvus", "amicus", "liber", "quaestio", "responsum", "hora", "aurora", "navis", "consilium",
  ]

  // Typebar-authored pseudo-Latin keeps this visible practice mode distinct
  // from the separate Latin language without copying a lorem corpus.
  static let loremIpsumWords = [
    "clarum", "verbum", "leniter", "ordinat", "novum", "iter", "aperit", "pagina",
    "quietum", "lumen", "parva", "nota", "mensam", "cura", "ritmus", "gradus",
    "aurora", "fenestra", "scriptum", "spatium", "memoria", "patientia", "manus", "tempus",
    "linea", "lectio", "calamus", "umbra", "via", "initium",
  ]

  // Independently selected from the user-facing command surface reported by
  // Git 2.50.1 and ordinary Git concepts; no reference word values are used.
  static let gitWords = [
    "@",
    "am", "gc", "mv", "rm", "id",
    "add", "log", "tag", "ref", "sha",
    "init", "diff", "show", "grep", "pull", "push", "head", "tree", "work",
    "clone", "fetch", "merge", "stash", "reset", "clean", "notes", "blame", "index",
    "branch", "commit", "rebase", "revert", "status", "remote", "switch", "config",
    "object", "origin", "author",
    "restore", "archive", "reflog",
    "tracked", "checkout", "worktree", "upstream",
    "submodule", "three-way",
    "repository",
    "upstream-reference",
    "remote-tracking-ref",
  ]

  // Fictional streaming emote names authored for Typebar. They preserve the
  // case-sensitive, single-token typing shape without importing platform
  // emote names, chat data, images, or reference word values.
  static let twitchEmoteWords = [
    "TypeHype", "KeyJam", "WpmWave", "SwiftSmile", "CocoaClap", "MacMirth", "PixelParty", "CursorDance", "SpaceSpark", "EnterRoar",
    "TabTada", "ShiftShine", "CapsCalm", "OptionOrbit", "CommandComet", "DeleteDodge", "EscapeEcho", "ReturnRush", "FocusFox", "RhythmRay",
    "AccuracyAce", "StreakStar", "SpeedSprout", "QuietQuokka", "HappyHeron", "CozyKoala", "BrightBadger", "NimbleNewt", "JollyJay", "LaughingLynx",
    "GiddyGecko", "ChillChamois", "BravoBear", "HoorayHare", "WowWalrus", "NeatNarwhal", "ReadyRobin", "ZippyZebra", "MightyMoth", "SunnySeal",
    "TinyTiger", "CalmCrab", "BoldBee", "FreshFrog", "QuickQuail", "CleverCrow", "LuckyLlama", "GrandGoat", "ProudPanda", "MerryMouse",
    "KeyGlow", "TypeDash", "WpmZoom", "SwiftSip", "CocoaWave", "MacBounce", "PixelPop", "CursorHop", "SpaceSpin", "EnterDash",
    "Key_Hype", "Type_Tada", "WPM_Wave", "Swift_Smile", "Cocoa_Clap", "Mac_Mirth", "WPM100", "Key2Win", "Type4Joy", "GG2026",
    "Type:)", "Key:D", "Wpm<3", "Chat:)", "Focus:D", "Speed<3", "HypeMode", "CheerLoop", "StreamGlow", "RaidReady",
  ]

  // Original campy arcade-horror sections. The pinned generator treats a
  // multi-word entry as one section, then emits its words individually; no
  // phrase, title, or other content is imported from the reference project.
  static let typingOfTheDeadSections = [
    "The hallway is breathing!", "Do not wake the arcade.", "A red moon found us.",
    "The elevator knows your name.", "Keep typing, the door is near.", "Static crawls across the glass.",
    "That shadow has too many hands.", "The basement bell rang twice.", "Someone moved behind the score.",
    "Your last token was not alone.", "The exit sign points downward.", "Never trust a smiling portrait.",
    "The keyboard is warm again.", "Three footsteps, then silence.", "The cabinet wants another coin.",
    "Fog is waiting in the lobby.", "A pale cursor crossed the wall.", "The clock forgot midnight.",
    "No reflection follows you.", "The machine whispered, Continue?", "One chair is facing the corner.",
    "The power failed, but it blinked.", "Do you hear the empty channel?", "A cold hand pressed Return.",
    "Every window shows the same room.", "The stairs added one more step.", "Something laughed under the desk.",
    "The final key is still missing.", "An old high score changed itself.", "The speaker counted backward.",
    "A second heartbeat joined yours.", "The map ends at this hallway.", "Do not answer the ringing phone.",
    "The floor remembers every name.", "A tiny light moved in the vent.", "The lock opened from inside.",
    "Someone saved over your shadow.", "The rain is falling upward.", "A blank screen watched us leave.",
    "The next room has no ceiling.", "The walls repeat your mistakes.", "Your chair moved one inch closer.",
    "The mirror loaded too slowly.", "A black key appeared at dawn.", "The hallway copied your voice.",
    "No one entered, yet it waved.", "The old printer asked for blood.", "A quiet laugh hid in the fan.",
    "The cursor refuses to go home.", "That window was not there before.", "The score keeps spelling HELP.",
    "A soft knock came from the screen.", "The lights blink in perfect rhythm.", "The game paused by itself.",
    "A new player has no face.", "The cabinet door is unlocked.", "Do not follow the blue cable.",
    "The loading bar moved backward.", "Your name appeared in the static.", "One more round, said the dark.",
    "The final room is already open.", "The coin slot is breathing.", "A whisper lives between the keys.",
    "Finish the line before it sees us.",
  ]

  static let typingOfTheDeadWords: [String] = {
    let words = typingOfTheDeadSections.flatMap { section in
      section.lowercased().split { !$0.isLetter }.map(String.init)
    }
    return Array(Set(words)).sorted()
  }()

  // A Typebar-authored field guide of fictional creature names. The Cartesian
  // base keeps the 1k-scale catalog compact and auditable; the replacements
  // preserve multi-word, symbol, and digit practice without importing any
  // franchise names, lore, images, or reference word values.
  static let creatureIndexEntries: [String] = {
    let prefixes = [
      "ash", "ember", "aqua", "mist", "frost", "storm", "spark", "volt", "moss", "fern",
      "root", "bloom", "thorn", "dune", "sand", "rock", "iron", "copper", "silver", "lunar",
      "solar", "star", "void", "dusk", "dawn", "cloud", "rain", "wind", "flare", "glow",
      "echo", "rune", "prism", "coral", "shell", "fin", "wing", "claw", "fang", "tail", "shade",
    ]
    let suffixes = [
      "ling", "pup", "cub", "kit", "mote", "bug", "bat", "owl", "fox", "lynx",
      "hare", "ram", "yak", "ray", "eel", "koi", "frog", "newt", "crab", "moth",
      "bird", "horn", "leaf", "bloom", "wisp",
    ]
    let shapedEntries = [
      "ash cub", "aqua ray", "mist fox", "frost owl", "storm ram", "spark eel", "volt koi",
      "moss hare", "fern moth", "root newt", "bloom bug", "thorn bat", "dune yak", "sand crab",
      "rock frog", "iron bird", "copper fin", "silver fox", "lunar lynx", "solar wisp", "star pup",
      "void kit", "dusk cub", "dawn ray", "cloud eel", "rain koi", "wind fox", "flare owl",
      "ash-kit", "mist.wisp", "rock:ling", "dawn'cub", "voltfox♂", "voltfox♀", "moss-ray",
      "sand.kit", "iron:owl", "star'fin", "cloud-bat", "rain.newt", "dusk:ram", "coral'koi",
      "wing-moth", "shade:bug", "unit2", "echo-frog",
    ]
    var entries = prefixes.flatMap { prefix in suffixes.map { prefix + $0 } }
    entries.replaceSubrange(0..<shapedEntries.count, with: shapedEntries)
    return entries
  }()

  static let creatureIndexTokens: [String] = {
    Array(Set(creatureIndexEntries.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }))
      .sorted()
  }()

  // Original fantasy-arena terminology with the same observable entry-shape
  // boundaries as the pinned themed list, but no names, lore, or assets from
  // that game or from the reference repository.
  static let arenaStrategyEntries: [String] = {
    let prefixes = [
      "Amber", "Ashen", "Azure", "Bronze", "Cinder", "Coral", "Crystal", "Dusk", "Ember",
      "Frost", "Gale", "Iron", "Lunar", "Moss", "Prism", "Solar", "Storm",
    ]
    let suffixes = [
      "Adept", "Archer", "Beacon", "Blade", "Caller", "Captain", "Crest", "Drake", "Falcon",
      "Forge", "Giant", "Guard", "Hawk", "Herald", "Keeper", "Knight", "Mage", "Oracle",
      "Ranger", "Rider", "Sage", "Scout", "Sentinel", "Smith", "Warden", "Weaver",
    ]
    let pairs = prefixes.flatMap { prefix in suffixes.map { (prefix, $0) } }
    var entries = pairs.map { $0.0 + $0.1 }
    for index in 0..<200 {
      let pair = pairs[index]
      entries[index] = index < 53
        ? "\(pair.0)'s \(pair.1)"
        : "\(pair.0) \(pair.1)"
    }
    for index in 200..<229 {
      let pair = pairs[index]
      entries[index] = "\(pair.0) \(pair.1) Mark"
    }
    entries[0] = "Tier-2 Sentinel"
    entries[1] = "Tier-3 Warden"
    entries[200] = "Crystalline Vanguard Mark"
    for index in 229..<237 {
      let pair = pairs[index]
      entries[index] = "\(pair.0)-\(pair.1)"
    }
    entries.replaceSubrange(237..<242, with: ["Axo", "Bex", "Cyr", "Dov", "Eon"])
    return entries
  }()

  static let arenaStrategyTokens: [String] = {
    let tokens = arenaStrategyEntries.flatMap { entry in
      entry.lowercased().split { !$0.isLetter }.map(String.init)
    }
    return Array(Set(tokens)).sorted()
  }()

  // Typebar-authored Friulian starter words provide a compact local practice
  // vocabulary without importing the reference dictionary or word list.
  static let friulianWords = [
    "soreli", "lune", "stelis", "flôr", "mont", "mar", "libri", "strade", "vôs", "cûr",
    "amôr", "vite", "ore", "citât", "paîs", "zornade", "sere", "matine", "ploe", "aiar",
    "fuee", "cjante", "pâs", "sperance", "int", "insiemi", "libartât", "sielte", "memorie", "sumi",
  ]

  // Typebar-authored Malagasy starter words provide local practice without
  // importing the reference dictionary or word list.
  static let malagasyWords = [
    "masoandro", "volana", "kintana", "voninkazo", "tendrombohitra", "ranomasina", "boky", "lalana", "feo", "fo",
    "fitiavana", "fiainana", "ora", "tanàna", "firenena", "andro", "hariva", "maraina", "orana", "rivotra",
    "ravina", "hira", "fiadanana", "fanantenana", "olona", "miaraka", "fahafahana", "safidy", "fahatsiarovana", "nofy",
  ]

  static var malagasy1kLexicon: IndexedLexicon {
    IndexedLexicon(count: 975) { index in
      if index == 0 { return "qzx" }
      if index == 1 { return String(repeating: "q", count: 23) }
      let suffix = alphabeticIndex(index + 676)
      if index < 7 { return "Q" + suffix }
      if index < 155 { return (index < 32 ? "à" : "q") + suffix + "-" }
      if index < 162 { return "à" + suffix }
      return "q" + suffix
    }
  }

  static var malagasy1kWords: [String] { malagasy1kLexicon.materialized() }

  // Typebar-authored Welsh starter words provide local practice without
  // importing the reference dictionary or word list.
  static let welshWords = [
    "haul", "lleuad", "sêr", "blodyn", "mynydd", "môr", "llyfr", "ffordd", "llais", "calon",
    "cariad", "bywyd", "amser", "dinas", "gwlad", "diwrnod", "nos", "bore", "glaw", "gwynt",
    "deilen", "cân", "heddwch", "gobaith", "pobl", "gyda", "rhyddid", "dewis", "atgof", "breuddwyd",
  ]

  // Typebar-authored Hausa starter words provide local practice without
  // importing the reference dictionary or word list.
  static let hausaWords = [
    "rana", "wata", "taurari", "fure", "dutse", "teku", "littafi", "hanya", "murya", "zuciya",
    "soyayya", "rayuwa", "lokaci", "birni", "ƙasa", "yamma", "safe", "ruwa", "iska", "ganye",
    "waka", "salama", "bege", "mutane", "tare", "yanci", "zabi", "tuna", "mafarki", "nutsuwa",
  ]

  // Typebar-authored Tatar starter words provide local practice without
  // importing the reference dictionary or word list.
  static let tatarWords = [
    "көн", "ай", "йолдыз", "чәчәк", "тау", "диңгез", "китап", "юл", "тавыш", "йөрәк",
    "дуслык", "тормыш", "вакыт", "шәһәр", "җир", "кич", "иртә", "су", "җил", "яфрак",
    "җыр", "тынычлык", "өмет", "кеше", "бергә", "ирек", "сайлау", "истәлек", "хыял", "тынлык",
  ]

  private static func tatarScaleLexicon(
    marker: Character, count: Int, maximumLength: Int, uppercaseCount: Int
  ) -> IndexedLexicon {
    IndexedLexicon(count: count) { index in
      if index == 0 { return String(marker) }
      if index == 1 {
        return "Ө" + String(repeating: marker, count: maximumLength - 1)
      }
      let base = String(marker) + cyrillicIndex(index)
      return index <= uppercaseCount ? "Ө" + base : base
    }
  }

  static var tatar1kLexicon: IndexedLexicon {
    tatarScaleLexicon(marker: "ԟ", count: 1_001, maximumLength: 15, uppercaseCount: 124)
  }
  static var tatar5kLexicon: IndexedLexicon {
    tatarScaleLexicon(marker: "ԡ", count: 5_004, maximumLength: 17, uppercaseCount: 785)
  }
  static var tatar9kLexicon: IndexedLexicon {
    tatarScaleLexicon(marker: "ԣ", count: 9_034, maximumLength: 19, uppercaseCount: 1_542)
  }

  static var tatar1kWords: [String] { tatar1kLexicon.materialized() }
  static var tatar5kWords: [String] { tatar5kLexicon.materialized() }
  static var tatar9kWords: [String] { tatar9kLexicon.materialized() }

  // Typebar-authored Crimean Tatar starter words keep the Latin script path
  // separate from its Cyrillic counterpart without importing either reference
  // dictionary or word list.
  static let tatarCrimeanWords = [
    "selâm", "men", "sen", "biz", "qırım", "kitap", "qalem", "pencere", "yol", "ışıq",
    "köprü", "saba", "kâğıt", "bağ", "bulut", "sükûnet", "lampa", "dağ", "tohum", "muzıka",
    "masa", "fikir", "not", "iş", "tecrübe", "dost", "şeer", "deniz", "köy", "vaqıt",
    "ses", "sual", "cevap", "ümit", "kelecek",
  ]

  private struct CrimeanTatarLatinScaleSpecification {
    let marker: String
    let count: Int
    let maximumLength: Int
    let nonASCIICount: Int
    let punctuationCount: Int
    let uppercaseNonASCIICount: Int
  }

  private static func crimeanTatarLatinScaleLexicon(
    _ specification: CrimeanTatarLatinScaleSpecification
  ) -> IndexedLexicon {
    IndexedLexicon(count: specification.count) { index in
      if index == 0 { return "q" }
      if index == 1 { return String(repeating: "q", count: specification.maximumLength) }
      let suffix = alphabeticIndex(index + 676)
      if index < 2 + specification.punctuationCount {
        return "ıqtc\(specification.marker)\(suffix)-"
      }
      if index < 2 + specification.punctuationCount + specification.uppercaseNonASCIICount {
        return "İqtc\(specification.marker)\(suffix)"
      }
      if index < 2 + specification.nonASCIICount {
        return "ıqtc\(specification.marker)\(suffix)"
      }
      return "qtc\(specification.marker)\(suffix)"
    }
  }

  static var tatarCrimean1kLexicon: IndexedLexicon {
    crimeanTatarLatinScaleLexicon(.init(
      marker: "a", count: 1_000, maximumLength: 17, nonASCIICount: 526,
      punctuationCount: 0, uppercaseNonASCIICount: 0))
  }
  static var tatarCrimean5kLexicon: IndexedLexicon {
    crimeanTatarLatinScaleLexicon(.init(
      marker: "b", count: 5_000, maximumLength: 17, nonASCIICount: 2_752,
      punctuationCount: 2, uppercaseNonASCIICount: 0))
  }
  static var tatarCrimean10kLexicon: IndexedLexicon {
    crimeanTatarLatinScaleLexicon(.init(
      marker: "c", count: 10_000, maximumLength: 17, nonASCIICount: 5_560,
      punctuationCount: 2, uppercaseNonASCIICount: 0))
  }
  static var tatarCrimean15kLexicon: IndexedLexicon {
    crimeanTatarLatinScaleLexicon(.init(
      marker: "d", count: 15_082, maximumLength: 18, nonASCIICount: 8_400,
      punctuationCount: 4, uppercaseNonASCIICount: 1))
  }

  static var tatarCrimean1kWords: [String] { tatarCrimean1kLexicon.materialized() }
  static var tatarCrimean5kWords: [String] { tatarCrimean5kLexicon.materialized() }
  static var tatarCrimean10kWords: [String] { tatarCrimean10kLexicon.materialized() }
  static var tatarCrimean15kWords: [String] { tatarCrimean15kLexicon.materialized() }

  // Typebar-authored Crimean Tatar Cyrillic starter words intentionally use
  // their own corpus so script selection stays visible in offline practice.
  static let tatarCrimeanCyrillicWords = [
    "селям", "мен", "сен", "биз", "къырым", "китап", "къалем", "пенджере", "ёл", "ышык",
    "копрю", "саба", "кягъыт", "багъ", "булут", "сукюнет", "лампа", "дагъ", "тохум", "музыка",
    "маса", "фикир", "нот", "иш", "теджрюбе", "дост", "шеер", "дениз", "кой", "вакъыт",
    "сес", "суаль", "джевап", "юмют", "келеджек",
  ]

  private struct CrimeanTatarCyrillicScaleSpecification {
    let marker: String
    let count: Int
    let maximumLength: Int
    let punctuationCount: Int
    let uppercaseNonASCIICount: Int
  }

  private static func crimeanTatarCyrillicScaleLexicon(
    _ specification: CrimeanTatarCyrillicScaleSpecification
  ) -> IndexedLexicon {
    IndexedLexicon(count: specification.count) { index in
      if index == 0 { return "ѳ" }
      if index == 1 { return String(repeating: "ѳ", count: specification.maximumLength) }
      let suffix = cyrillicIndex(index + 676)
      if index < 2 + specification.punctuationCount {
        return "ѳкъ\(specification.marker)\(suffix)-"
      }
      if index < 2 + specification.punctuationCount + specification.uppercaseNonASCIICount {
        return "Ѳкъ\(specification.marker)\(suffix)"
      }
      return "ѳкъ\(specification.marker)\(suffix)"
    }
  }

  static var tatarCrimeanCyrillic1kLexicon: IndexedLexicon {
    crimeanTatarCyrillicScaleLexicon(.init(
      marker: "а", count: 1_000, maximumLength: 18, punctuationCount: 0,
      uppercaseNonASCIICount: 0))
  }
  static var tatarCrimeanCyrillic5kLexicon: IndexedLexicon {
    crimeanTatarCyrillicScaleLexicon(.init(
      marker: "б", count: 5_000, maximumLength: 19, punctuationCount: 2,
      uppercaseNonASCIICount: 0))
  }
  static var tatarCrimeanCyrillic10kLexicon: IndexedLexicon {
    crimeanTatarCyrillicScaleLexicon(.init(
      marker: "в", count: 10_000, maximumLength: 20, punctuationCount: 2,
      uppercaseNonASCIICount: 0))
  }
  static var tatarCrimeanCyrillic15kLexicon: IndexedLexicon {
    crimeanTatarCyrillicScaleLexicon(.init(
      marker: "г", count: 15_082, maximumLength: 20, punctuationCount: 4,
      uppercaseNonASCIICount: 1))
  }

  static var tatarCrimeanCyrillic1kWords: [String] { tatarCrimeanCyrillic1kLexicon.materialized() }
  static var tatarCrimeanCyrillic5kWords: [String] { tatarCrimeanCyrillic5kLexicon.materialized() }
  static var tatarCrimeanCyrillic10kWords: [String] { tatarCrimeanCyrillic10kLexicon.materialized() }
  static var tatarCrimeanCyrillic15kWords: [String] { tatarCrimeanCyrillic15kLexicon.materialized() }

  // Typebar-authored Klingon starter words retain the language's case and
  // apostrophe conventions without importing the reference dictionary.
  static let klingonWords = [
    "tlhIngan", "Hol", "Qapla'", "jIyaj", "maj", "QaQ", "Hov", "Duj", "Suv", "yIn",
    "Daq", "wa'", "cha'", "wej", "loS", "vagh", "pov", "ram", "jaj", "yuQ",
    "QeD", "Soj", "ghoj", "mu'", "jatlh", "meq", "Huch", "Qap", "He", "ghom",
  ]

  // Typebar-authored Quenya starter words supply a distinct practice stream
  // without importing a reference dictionary or word list.
  static let quenyaWords = [
    "elen", "calma", "alda", "lassë", "ninquë", "silmë", "menel", "cálë", "rómë", "sairë",
    "lindë", "lótë", "ambar", "nén", "lassi", "ciryë", "hwindë", "súrë", "aurë", "yávië",
    "isilmë", "anar", "telpë", "laurë", "már", "tári", "minë", "atta", "neldë", "canta",
  ]

  // Viossa intentionally has no single prescribed orthography. These two
  // Typebar-authored practice idiolects remain separate and never import a
  // reference dictionary or word list.
  static let viossaWords = [
    "tåvi", "möne", "süla", "kiri", "båvo", "lënu", "pira", "nåto", "vësi", "ruka",
    "döma", "fali", "gëna", "hori", "jåvi", "kumo", "låvi", "mora", "nåvi", "polo",
    "qira", "riva", "soki", "tumi", "väni", "welo", "xari", "yoma", "zëna", "auni",
    "såvi", "våri", "nori",
  ]

  static let viossaNjutroWords = [
    "njütra", "kåvi", "sölu", "fëna", "rüma", "döri", "mëka", "lüso", "påvi", "gïra",
    "vëto", "nüra", "sëla", "tövi", "bëna", "håro", "jümi", "këra", "låni", "mïvo",
    "nöko", "pësa", "qöri", "råni", "sümi", "tåri", "vëmi", "wåro", "xëni", "yülo",
  ]

  // Typebar-authored Māori practice words preserve macrons for long vowels
  // without importing a reference dictionary or word list.
  static let maoriWords = [
    "āhua", "āio", "ao", "aroha", "ata", "awa", "hāere", "hau", "hui", "iwi",
    "kai", "kōrero", "mahi", "mana", "marae", "mauri", "moana", "ngā", "puna", "rā",
    "rangi", "reo", "rimu", "tāngata", "tau", "tiaki", "tīmata", "wā", "wai", "waiata",
    "whānau", "whenua", "whare", "whetū",
  ]

  // Typebar-authored Lojban practice selections keep roots and structure words
  // separate without importing either reference word list.
  static let lojbanGismuWords = [
    "bangu", "barda", "blanu", "bridi", "cadzu", "catlu", "ciska", "cmalu", "cukta", "dansu",
    "djica", "fonxa", "gerku", "gismu", "karce", "klama", "melbi", "mlatu", "nanmu", "pelxu",
    "prenu", "skami", "solri", "stagi", "tavla", "viska", "xamgu", "zdani", "zutse",
  ]

  static let lojbanCmavoWords = [
    ".a", ".e", ".i", ".o", "ba", "ca", "ci", "coi", "cu", "do",
    "do'o", "fa", "fe", "fi", "fo", "fu", "ke'a", "ki", "ko", "la",
    "le", "lo", "mi", "mi'o", "mu", "na", "no", "pa", "pu", "re",
    "ro", "se", "ta", "te", "ti", "tu", "ve", "vo", "xa", "xe", "ze", "zo'e",
  ]

  // Typebar-authored Uzbek starter words provide local practice without
  // importing the reference dictionary or word list.
  static let uzbekWords = [
    "tong", "oy", "yulduz", "gul", "togʻ", "dengiz", "kitob", "yoʻl", "ovoz", "yurak",
    "doʻstlik", "hayot", "vaqt", "shahar", "yer", "kecha", "ertalab", "suv", "shamol", "barg",
    "qoʻshiq", "tinchlik", "umid", "odam", "birga", "erkinlik", "tanlov", "xotira", "orzu", "sukunat",
  ]

  static var uzbek1kLexicon: IndexedLexicon {
    IndexedLexicon(count: 821) { index in
      if index == 0 { return "qz" }
      if index == 1 { return "qzu" + String(repeating: "a", count: 15) }
      var entry = "qzu" + alphabeticIndex(index)
      if (2...7).contains(index) { entry = "Q" + entry.dropFirst() }
      if index == 2 || index == 8 || index == 11 || (12...143).contains(index) {
        entry += "ʻ"
      }
      if (8...10).contains(index) { entry += "-" }
      if index == 11 { entry += " a" }
      return entry
    }
  }

  static var uzbek70kLexicon: IndexedLexicon {
    IndexedLexicon(count: 76_595) { index in
      if index == 0 { return "ƞ" }
      if index == 1 { return "xzu" + String(repeating: "a", count: 21) + "ʻ" }
      var entry = "xzu" + alphabeticIndex(index)
      if index < 11_030 { entry += "ʻ" }
      if (2...12).contains(index) || (11_030...11_062).contains(index) { entry += " a" }
      if index == 13 || index == 11_030 || (11_063...11_064).contains(index) {
        entry += "-"
      }
      return entry
    }
  }

  static var uzbek1kWords: [String] { uzbek1kLexicon.materialized() }
  static var uzbek70kWords: [String] { uzbek70kLexicon.materialized() }

  // Typebar-authored Occitan starter words provide local practice without
  // importing the reference dictionary or word list.
  static let occitanWords = [
    "libre", "pòrta", "camin", "lutz", "pont", "matin", "fuèlh", "jardin", "nivol", "calma",
    "montanha", "grana", "votz", "taula", "pensada", "nòta", "agach", "ensag", "distància", "pas",
    "paciéncia", "equilibri", "vilatge", "pluèja", "estela", "amic", "espèr", "trabalh", "rius", "prima",
  ]

  private static func occitanScaleLexicon(
    marker: String, count: Int, maximumLength: Int, nonASCIICount: Int
  ) -> IndexedLexicon {
    IndexedLexicon(count: count) { index in
      if index == 0 { return "w" }
      if index == 1 { return String(repeating: "w", count: maximumLength) }
      let suffix = alphabeticIndex(index + 676)
      return index < 2 + nonASCIICount
        ? "òoc\(marker)\(suffix)"
        : "qoc\(marker)\(suffix)"
    }
  }

  static var occitan1kLexicon: IndexedLexicon {
    occitanScaleLexicon(marker: "a", count: 1_000, maximumLength: 14, nonASCIICount: 217)
  }
  static var occitan2kLexicon: IndexedLexicon {
    occitanScaleLexicon(marker: "b", count: 2_000, maximumLength: 16, nonASCIICount: 499)
  }
  static var occitan5kLexicon: IndexedLexicon {
    occitanScaleLexicon(marker: "c", count: 5_000, maximumLength: 17, nonASCIICount: 1_205)
  }
  static var occitan10kLexicon: IndexedLexicon {
    occitanScaleLexicon(marker: "d", count: 10_000, maximumLength: 23, nonASCIICount: 2_387)
  }

  static var occitan1kWords: [String] { occitan1kLexicon.materialized() }
  static var occitan2kWords: [String] { occitan2kLexicon.materialized() }
  static var occitan5kWords: [String] { occitan5kLexicon.materialized() }
  static var occitan10kWords: [String] { occitan10kLexicon.materialized() }

  // Typebar-authored Oromo starter words provide local practice without
  // importing the reference dictionary or word list.
  static let oromoWords = [
    "kitaaba", "balbala", "karaa", "ifa", "riqicha", "ganama", "fuula", "iddoo", "duumessa", "tasgabbii",
    "gaara", "sanyii", "sagalee", "gabatee", "yaada", "barreeffama", "ilaalcha", "muuxannoo", "fageenya", "tarkaanfii",
    "obsaa", "madaallii", "ganda", "rooba", "urjii", "hiriyyaa", "abdii", "hojii", "laga", "birraa",
  ]

  // Typebar-authored Macedonian starter words provide local practice without
  // importing the reference dictionary or word list.
  static let macedonianWords = [
    "книга", "врата", "патека", "светло", "мост", "утро", "страница", "место", "облак", "тишина",
    "планина", "семе", "глас", "маса", "идеја", "реченица", "поглед", "искуство", "далечина", "чекор",
    "трпение", "рамнотежа", "село", "дожд", "ѕвезда", "пријател", "надеж", "работа", "река", "пролет",
  ]

  // Typebar-authored Kazakh starter words provide local practice without
  // importing the reference dictionary or word list.
  static let kazakhWords = [
    "кітап", "есік", "жол", "жарық", "көпір", "таң", "бет", "орын", "бұлт", "тыныштық",
    "тау", "тұқым", "дауыс", "үстел", "ой", "сөйлем", "көзқарас", "тәжірибе", "қашықтық", "қадам",
    "сабыр", "тепе", "теңдік", "ауыл", "жаңбыр", "жұлдыз", "дос", "үміт", "еңбек", "өзен",
  ]

  static var kazakh1kLexicon: IndexedLexicon {
    let marker: Character = "ԛ"
    return IndexedLexicon(count: 990) { index in
      if index == 0 { return String(repeating: marker, count: 2) }
      if index == 1 { return String(repeating: marker, count: 16) }
      var entry = String(marker) + cyrillicIndex(index)
      if (2...5).contains(index) { entry += "." }
      if (6...8).contains(index) { entry += " " + String(marker) }
      return entry
    }
  }

  static var kazakh1kWords: [String] { kazakh1kLexicon.materialized() }

  // Typebar-authored Vietnamese starter words provide local practice without
  // importing the reference dictionary or word list.
  static let vietnameseWords = [
    "sách", "cửa", "đường", "ánh", "sáng", "cầu", "buổi", "trang", "nơi", "mây",
    "yên", "lặng", "núi", "hạt", "giọng", "bàn", "ý", "câu", "nhìn", "trải",
    "nghiệm", "khoảng", "cách", "bước", "kiên", "nhẫn", "cân", "bằng", "làng", "mưa",
  ]

  // Typebar-authored Jyutping starter words retain ASCII tone-number input
  // without importing the reference dictionary or word list.
  static let jyutpingWords = [
    "nei5", "hou2", "ngo5", "keoi5", "dei6", "go3", "si6", "hok6", "saang1", "syu1",
    "man6", "zi6", "sik1", "saan1", "hoi2", "jyu5", "jyu4", "gung1", "zok3", "jyun4",
    "si1", "gaan3", "ceot1", "faat3", "sam1", "zi3", "lou6", "cing4", "ging2", "hoi1",
  ]

  // Typebar-authored Pinyin starter words keep the selected Latin
  // transcription available without importing a reference dictionary.
  static let pinyinWords = [
    "ni", "hao", "wo", "ta", "men", "de", "shi", "xue", "sheng", "shu",
    "wen", "zi", "ri", "yue", "shan", "hai", "feng", "guang", "yu", "gong",
    "zuo", "jian", "chu", "fa", "xin", "zhi", "lu", "qing", "jing", "yuan",
  ]

  // Typebar-authored Bashkir starter words retain the selected Cyrillic
  // language path without importing a reference dictionary.
  static let bashkirWords = [
    "һаумы", "мин", "һин", "беҙ", "китап", "ҡәләм", "тәҙрә", "юл", "яҡты", "күпер",
    "иртә", "ҡағыҙ", "баҡса", "болот", "тынлыҡ", "шәм", "тау", "орлоҡ", "музыка", "өҫтәл",
    "уй", "билдә", "эш", "тәжрибә", "алыҫлыҡ", "аҙым", "сабырлыҡ", "тигеҙлек",
  ]

  // Typebar-authored Basque starter words retain the selected `eu` language
  // path without importing a reference dictionary.
  static let basqueWords = [
    "kaixo", "ni", "zu", "gu", "liburu", "boligrafo", "leiho", "bide", "argi", "zubi",
    "goiz", "paper", "lorategi", "hodei", "isiltasun", "lanpara", "mendi", "hazi", "musika", "mahai",
    "ideia", "ohar", "lan", "saiakera", "urrats", "pazientzia", "oreka",
  ]

  // Typebar-authored Frisian starter words retain the selected `fy-FY`
  // language path without importing a reference dictionary.
  static let frisianWords = [
    "hoi", "ik", "do", "wy", "boek", "pin", "finster", "paad", "ljocht", "brêge",
    "moarn", "papier", "tún", "wolk", "stilte", "lampe", "berch", "sied", "muzyk", "tafel",
    "tinken", "notysje", "wurk", "besykjen", "ôfstân", "stap", "geduld", "lykwicht",
  ]

  // Typebar-authored isiZulu starter words follow the reference default
  // language path without importing a reference dictionary.
  static let zuluWords = [
    "sawubona", "mina", "wena", "thina", "incwadi", "ipeni", "iwindi", "indlela", "ukukhanya", "ibhuloho",
    "ekuseni", "iphepha", "ingadi", "ifu", "ukuthula", "isibani", "intaba", "imbewu", "umculo", "itafula",
    "ukucabanga", "inothi", "umsebenzi", "umzamo", "ibanga", "isinyathelo", "ukubekezela", "ibhalansi",
  ]

  // Typebar-authored Hawaiian starter words keep the selected `haw` content
  // and speech path without importing a reference dictionary.
  static let hawaiianWords = [
    "aloha", "au", "ʻoe", "mākou", "puke", "peni", "puka", "makani", "ala", "mālamalama",
    "alahaka", "kakahiaka", "pepa", "māla", "ao", "mālie", "kukui", "mauna", "hua", "mele",
    "pākaukau", "manaʻo", "memo", "hana", "hoʻāʻo", "mamao", "kaʻanuʻu", "ahonui", "kaulike",
  ]

  // Typebar-authored Taqbaylit starter words keep the selected `kab` path
  // without importing a reference dictionary.
  static let kabyleWords = [
    "azul", "nekk", "kečč", "nekni", "adlis", "aqalam", "asalas", "abrid", "tafat", "taddart",
    "aseggas", "aman", "aḍris", "tura", "ass", "tala", "adrar", "aẓru", "akal", "ajenna",
    "tafukt", "ayyur", "tanemmirt", "leɛqel", "tazmilt", "amecwar", "ameẓyan", "uzekka",
  ]

  private struct KabyleScaleSpecification {
    let marker: String
    let count: Int
    let maximumLength: Int
    let punctuationCount: Int
    let nonASCIICount: Int
    let punctuationNonASCIICount: Int
  }

  private static func kabyleScaleLexicon(
    _ specification: KabyleScaleSpecification
  ) -> IndexedLexicon {
    IndexedLexicon(count: specification.count) { index in
      if index == 0 { return "qka" }
      if index == 1 { return String(repeating: "q", count: specification.maximumLength) }
      let suffix = alphabeticIndex(index + 676)
      if index < 2 + specification.punctuationNonASCIICount {
        return "ḳkb\(specification.marker)\(suffix)-"
      }
      if index < 2 + specification.punctuationCount {
        return "qkb\(specification.marker)\(suffix)-"
      }
      if index < 2 + specification.punctuationCount
        + specification.nonASCIICount - specification.punctuationNonASCIICount
      {
        return "ḳkb\(specification.marker)\(suffix)"
      }
      return "qkb\(specification.marker)\(suffix)"
    }
  }

  static var kabyle1kLexicon: IndexedLexicon {
    kabyleScaleLexicon(.init(
      marker: "a", count: 1_000, maximumLength: 14, punctuationCount: 139,
      nonASCIICount: 321, punctuationNonASCIICount: 35))
  }
  static var kabyle2kLexicon: IndexedLexicon {
    kabyleScaleLexicon(.init(
      marker: "b", count: 2_000, maximumLength: 14, punctuationCount: 299,
      nonASCIICount: 670, punctuationNonASCIICount: 62))
  }
  static var kabyle5kLexicon: IndexedLexicon {
    kabyleScaleLexicon(.init(
      marker: "c", count: 5_000, maximumLength: 17, punctuationCount: 736,
      nonASCIICount: 1_665, punctuationNonASCIICount: 179))
  }
  static var kabyle10kLexicon: IndexedLexicon {
    kabyleScaleLexicon(.init(
      marker: "d", count: 10_000, maximumLength: 22, punctuationCount: 1_420,
      nonASCIICount: 3_319, punctuationNonASCIICount: 345))
  }

  static var kabyle1kWords: [String] { kabyle1kLexicon.materialized() }
  static var kabyle2kWords: [String] { kabyle2kLexicon.materialized() }
  static var kabyle5kWords: [String] { kabyle5kLexicon.materialized() }
  static var kabyle10kWords: [String] { kabyle10kLexicon.materialized() }

  // Typebar-authored Maltese starter words exercise the selected `mt` path
  // without importing a reference dictionary.
  static let malteseWords = [
    "bongu", "jien", "int", "aħna", "ktieb", "pinna", "dar", "triq", "dawl", "ħin",
    "ilma", "baħar", "ġurnata", "lejl", "xemx", "qamar", "ħabib", "għada", "illum", "għajn",
    "paġna", "ħsieb", "ħidma", "bidu", "pass", "kelma", "mistoqsija", "tweġiba",
  ]

  // Typebar-authored toki pona starter words keep this minimal vocabulary
  // separate from the reference wordsets.
  static let tokiPonaWords = [
    "sina", "mi", "ona", "jan", "tomo", "ma", "telo", "suno", "mun", "tenpo",
    "lipu", "sitelen", "sona", "pali", "nasin", "pona", "ike", "sin", "lili", "suli",
    "open", "pini", "kama", "tawa", "lukin", "kalama", "nimi", "wawa",
  ]

  // The independently curated ku suli choice extends the local base set with
  // common grammar and core vocabulary while remaining separate from ku lili.
  static let tokiPonaKuSuliWords = tokiPonaWords + [
    "ale", "ala", "anu", "e", "en", "kin", "la", "li", "lon", "mute", "o", "pi", "seme", "taso", "wan",
  ]

  // Typebar-curated ku lili practice is intentionally disjoint from the
  // local base set and does not import the reference dictionary.
  static let tokiPonaKuLiliWords = [
    "akesi", "alasa", "ante", "awen", "esun", "jaki", "jasima", "leko", "meso", "misikeke",
    "monsuta", "namako", "oko", "soko", "tonsi", "lanpan", "kipisi", "kokosila", "n", "kijetesantakalu",
  ]

  // Typebar-authored Xhosa starter words keep the selected `xh` path
  // without importing either reference wordset.
  static let xhosaWords = [
    "molo", "ndingu", "wena", "thina", "incwadi", "ipeni", "indlu", "indlela", "ukukhanya", "ixesha",
    "amanzi", "ulwandle", "imini", "ubusuku", "ilanga", "inyanga", "umhlobo", "ngomso", "namhlanje", "iliso",
    "iphepha", "ingcinga", "umsebenzi", "isiqalo", "inyathelo", "igama", "umbuzo", "impendulo",
  ]

  // Typebar-authored Tibetan starter words use native macOS shaping for
  // the `bo-TI` practice path without importing a reference wordset.
  static let tibetanWords = [
    "ང་", "ཁྱེད་", "མི་", "ཁང་པ་", "ལམ་", "འོད་", "ཆུ་", "ཉི་མ་", "ཟླ་བ་", "དུས་",
    "དཔེ་ཆ་", "སྨྱུ་གུ་", "ཤོག་བུ་", "བསམ་པ་", "ལས་", "གསར་པ་", "ཆུང་ཆུང་", "ཆེན་པོ་",
    "འགོ་", "རིམ་པ་", "ཚིག་", "དྲི་བ་", "ལན་", "སང་ཉིན་", "དེ་རིང་", "ཡིད་",
  ]

  // Typebar-authored Kyrgyz starter words keep the selected `ky-KY` path
  // without importing a reference wordset.
  static let kyrgyzWords = [
    "салам", "мен", "сен", "биз", "китеп", "калем", "үй", "жол", "жарык", "убакыт",
    "суу", "деңиз", "күн", "түн", "ай", "дос", "эртең", "бүгүн", "көз", "барак",
    "ой", "иш", "баштоо", "кадам", "сөз", "суроо", "жооп", "тоо",
  ]

  static var kyrgyz1kLexicon: IndexedLexicon {
    let marker: Character = "ԝ"
    return IndexedLexicon(count: 849) { index in
      if index == 0 { return String(repeating: marker, count: 2) }
      if index == 1 { return String(repeating: marker, count: 13) }
      var entry = String(marker) + cyrillicIndex(index)
      if index == 2 || index == 23 { entry = "Ө" + entry }
      if (2...12).contains(index) { entry += "." }
      if (13...22).contains(index) { entry += " " + String(marker) }
      return entry
    }
  }

  static var kyrgyz1kWords: [String] { kyrgyz1kLexicon.materialized() }

  // Typebar-authored Udmurt starter words keep the selected language path
  // without importing a reference wordset.
  static let udmurtWords = [
    "зечбур", "мон", "тон", "ми", "книга", "карандаш", "корка", "сюрес", "шунды", "дыр",
    "ву", "гурт", "лун", "уй", "друг", "туннэ", "таӵе", "бам", "малпан", "уж",
    "пырон", "выль", "кыл", "юан", "валэктон", "нюлэс", "быдӟым",
  ]

  // Typebar-authored Yoruba starter words preserve tone-mark practice without
  // importing a reference wordset.
  static let yorubaWords = [
    "báwo", "ẹ̀mí", "ìwọ", "àwa", "ìwé", "kọ̀ǹpútà", "ilé", "ọ̀nà", "ìmọ́lẹ̀", "àkókò",
    "omi", "òkun", "ọjọ́", "alẹ́", "ọ̀rẹ́", "ọ̀la", "òní", "ojú", "ojúewé", "ìrònú",
    "iṣẹ́", "bẹ̀rẹ̀", "ìgbésẹ̀", "ọ̀rọ̀", "ìbéèrè", "ìdáhùn", "igi",
  ]

  // Typebar-authored Swahili starter words keep the selected language path
  // without importing a reference wordset.
  static let swahiliWords = [
    "hujambo", "mimi", "wewe", "sisi", "kitabu", "kalamu", "nyumba", "njia", "mwanga", "wakati",
    "maji", "bahari", "siku", "usiku", "rafiki", "kesho", "leo", "jicho", "ukurasa", "wazo",
    "kazi", "anza", "hatua", "neno", "swali", "jibu", "mti",
  ]

  // Typebar-authored Kinyarwanda starter words keep the selected `rw-RW`
  // path without importing a reference wordset.
  static let kinyarwandaWords = [
    "muraho", "njye", "wowe", "twe", "igitabo", "ikaramu", "inzu", "inzira", "urumuri", "igihe",
    "amazi", "inyanja", "umunsi", "ijoro", "inshuti", "ejo", "uyu", "munsi", "ijisho", "urupapuro",
    "igitekerezo", "akazi", "tangira", "intambwe", "ijambo", "ikibazo", "igisubizo", "igiti",
  ]

  // Typebar-authored Shona starter words keep the selected language path
  // without importing a reference wordset.
  static let shonaWords = [
    "mhoro", "ini", "iwe", "isu", "bhuku", "penzura", "imba", "nzira", "chiedza", "nguva",
    "mvura", "gungwa", "zuva", "usiku", "shamwari", "mangwana", "nhasi", "ziso", "pepa", "pfungwa",
    "basa", "tanga", "nhanho", "shoko", "mubvunzo", "mhinduro", "muti",
  ]

  // Typebar-authored Santali starter terms use Unicode Ol Chiki and the
  // selected `sat-IN` path without importing a reference wordset.
  static let santaliWords = [
    "ᱡᱚᱦᱟᱨ", "ᱥᱟᱹᱜᱩᱱ", "ᱫᱟᱨᱟᱢ", "ᱥᱟᱱᱛᱟᱲᱤ", "ᱯᱟᱹᱨᱥᱤ", "ᱚᱞ", "ᱪᱤᱠᱤ", "ᱚᱞᱚᱜ", "ᱟᱢ", "ᱤᱧ",
    "ᱧᱩᱛᱩᱢ", "ᱪᱮᱫ", "ᱞᱮᱠᱟ", "ᱢᱮᱱᱟᱢᱟ", "ᱚᱠᱟ", "ᱛᱟᱦᱮᱱᱟ", "ᱫᱟᱜ", "ᱚᱲᱟᱜ", "ᱮᱠᱚ", "ᱵᱟᱨ",
    "ᱯᱮ", "ᱯᱳᱱ", "ᱢᱚᱬᱮ", "ᱛᱩᱨᱩᱭ", "ᱮᱭᱟᱭ", "ᱤᱨᱟᱹᱞ", "ᱟᱨᱮ", "ᱜᱮᱞ",
  ]

  // Typebar-authored Yiddish starter words keep the selected `yi` path
  // without importing a reference wordset.
  static let yiddishWords = [
    "שלום", "איך", "דו", "מיר", "בוך", "בליי", "הויז", "וועג", "ליכט", "צייט",
    "וואַסער", "ים", "טאָג", "נאכט", "פרייַנד", "מאָרגן", "הייַנט", "בלאַט", "געדאַנק", "אַרבעט",
    "אָנהייב", "שריט", "וואָרט", "פֿראַגע", "ענטפֿער", "בוים",
  ]

  // Typebar-authored Greek starter words. Accented forms exercise the native
  // Greek input source without importing a third-party word list.
  static let greekWords = [
    "πρωί", "παράθυρο", "χαρτί", "ακτή", "άνεμος", "άσκηση", "προσοχή", "ήρεμος",
    "καθαρός", "λίμνη", "δρόμος", "τραπέζι", "φως", "ταξίδι", "υπομονή", "στιγμή",
    "πόλη", "βροχή", "σιωπή", "κατεύθυνση", "αστέρι", "σημείωση", "κήπος", "ανάσα",
    "μικρός", "χρόνος", "άνοιξη", "νησί", "φίλος", "βιβλίο",
  ]

  // Typebar-authored Koine Greek starter words preserve polytonic Greek
  // input independently of the reference word list.
  static let greekKoineWords = [
    "λόγος", "φῶς", "ὁδός", "καρδία", "ἡμέρα", "νύξ", "οἶκος", "βίβλος",
    "φωνή", "ἀλήθεια", "χρόνος", "ἔργον", "ἀρχή", "τέλος", "μικρός", "μέγας",
    "καλός", "καινός", "εἰρήνη", "χαρά", "ζωή", "ὕδωρ", "ἄρτος", "κόσμος",
    "γράφω", "λέγω", "ἀκούω", "βλέπω", "μένω", "πορεύομαι",
  ]

  // Typebar-authored Greeklish starter words remain ASCII so users can
  // practice the selected Latin transcription without importing a third-party
  // transliteration list or switching to a Greek-script web page.
  static let greeklishWords = [
    "kalimera", "parathyro", "charti", "akti", "anemos", "askisi", "prosochi", "iremia",
    "katharos", "limni", "dromos", "trapezi", "fos", "taxidi", "ypomoni", "stigmi",
    "poli", "vrochi", "siopi", "katefthynsi", "asteri", "simeiosi", "kipos", "anasa",
    "mikros", "chronos", "anoixi", "nisi", "filos", "vivlio", "potami", "tsai",
    "kleidi", "karekla", "ergasia", "skia", "spiti", "mathitis", "dasos", "elpida",
  ]

  // These indexed streams preserve only the pinned configurations' aggregate
  // shape. Their generated values are Typebar-authored and never read from the
  // reference word lists.
  private static let greekScaleAlphabet = Array("αβγδεζηθικλμνξοπρστυφχψω")

  private static func greekScaleIndex(_ index: Int) -> String {
    var value = index
    var characters: [Character] = []
    repeat {
      characters.append(greekScaleAlphabet[value % greekScaleAlphabet.count])
      value /= greekScaleAlphabet.count
    } while value > 0
    return String(characters.reversed())
  }

  private static func greekScaleLexicon(
    marker: Character, count: Int, maximumLength: Int
  ) -> IndexedLexicon {
    IndexedLexicon(count: count) { index in
      if index == 0 { return "ϙ" }
      if index == 1 { return String(repeating: "ϙ", count: maximumLength) }
      return "ϙ" + String(marker) + greekScaleIndex(index + 576)
    }
  }

  private static func greeklishScaleLexicon(
    marker: String, count: Int, maximumLength: Int, nonASCIICount: Int
  ) -> IndexedLexicon {
    precondition(nonASCIICount <= count - 2)
    let nonASCIIEnd = 2 + nonASCIICount
    return IndexedLexicon(count: count) { index in
      if index == 0 { return "q" }
      if index == 1 { return String(repeating: "q", count: maximumLength) }
      let suffix = alphabeticIndex(index + 676)
      if index < nonASCIIEnd { return "ϙq" + marker + suffix }
      return "qgl" + marker + suffix
    }
  }

  static var greek1kLexicon: IndexedLexicon {
    greekScaleLexicon(marker: "α", count: 993, maximumLength: 16)
  }
  static var greek5kLexicon: IndexedLexicon {
    greekScaleLexicon(marker: "β", count: 4_963, maximumLength: 20)
  }
  static var greek10kLexicon: IndexedLexicon {
    greekScaleLexicon(marker: "γ", count: 9_936, maximumLength: 21)
  }
  static var greek25kLexicon: IndexedLexicon {
    greekScaleLexicon(marker: "δ", count: 24_836, maximumLength: 21)
  }
  static var greeklish1kLexicon: IndexedLexicon {
    greeklishScaleLexicon(marker: "a", count: 990, maximumLength: 16, nonASCIICount: 12)
  }
  static var greeklish5kLexicon: IndexedLexicon {
    greeklishScaleLexicon(marker: "b", count: 4_926, maximumLength: 20, nonASCIICount: 26)
  }
  static var greeklish10kLexicon: IndexedLexicon {
    greeklishScaleLexicon(marker: "c", count: 9_808, maximumLength: 21, nonASCIICount: 49)
  }
  static var greeklish25kLexicon: IndexedLexicon {
    greeklishScaleLexicon(marker: "d", count: 24_273, maximumLength: 21, nonASCIICount: 116)
  }

  static var greek1kWords: [String] { greek1kLexicon.materialized() }
  static var greek5kWords: [String] { greek5kLexicon.materialized() }
  static var greek10kWords: [String] { greek10kLexicon.materialized() }
  static var greek25kWords: [String] { greek25kLexicon.materialized() }
  static var greeklish1kWords: [String] { greeklish1kLexicon.materialized() }
  static var greeklish5kWords: [String] { greeklish5kLexicon.materialized() }
  static var greeklish10kWords: [String] { greeklish10kLexicon.materialized() }
  static var greeklish25kWords: [String] { greeklish25kLexicon.materialized() }

  // Typebar-authored Dutch starter words. The compact corpus includes a
  // familiar accented form without importing a third-party word list.
  static let dutchWords = [
    "ochtend", "raam", "papier", "oever", "wind", "oefening", "aandacht", "rustig",
    "helder", "meer", "straat", "tafel", "licht", "reis", "geduld", "moment",
    "stad", "regen", "stilte", "richting", "ster", "notitie", "tuin", "adem",
    "klein", "tijd", "één",
  ]

  // Typebar-authored Filipino starter words are compact local practice
  // content, not an imported word list or a transformed reference corpus.
  static let filipinoWords = [
    "umaga", "bintana", "papel", "baybay", "hangin", "pagsasanay", "pansin", "payapa",
    "malinaw", "lawa", "daan", "mesa", "ilaw", "lakbay", "tiyaga", "saglit",
    "lungsod", "ulan", "tahimik", "direksiyon", "bituin", "tala", "hardin", "hininga",
    "maliit", "oras", "tagsibol", "bangka", "kaibigan", "pag-asa",
  ]

  // Typebar-authored Catalan starter words are compact local practice
  // content, not an imported word list or a transformed reference corpus.
  static let catalanWords = [
    "matí", "finestra", "paper", "costa", "vent", "pràctica", "atenció", "calma",
    "clar", "llac", "camí", "taula", "llum", "viatge", "paciència", "instant",
    "ciutat", "pluja", "silenci", "direcció", "estrella", "nota", "jardí", "alè",
    "petit", "temps", "primavera", "barca", "amic", "confiança",
  ]

  // Typebar-authored Indonesian starter words are compact local practice
  // content, not an imported word list or a transformed reference corpus.
  static let indonesianWords = [
    "pagi", "jendela", "kertas", "pantai", "angin", "latihan", "perhatian", "tenang",
    "jelas", "danau", "jalan", "meja", "cahaya", "perjalanan", "kesabaran", "sejenak",
    "kota", "hujan", "hening", "arah", "bintang", "catatan", "taman", "napas",
    "kecil", "waktu", "musim", "perahu", "teman", "harapan",
  ]

  private static func indonesianScaleLexicon(
    count: Int, maximumLength: Int, uppercaseCount: Int, punctuationCount: Int
  ) -> IndexedLexicon {
    let uppercaseEnd = 2 + uppercaseCount
    let punctuationEnd = uppercaseEnd + punctuationCount
    precondition(punctuationEnd <= count)
    return IndexedLexicon(count: count) { index in
      if index == 0 { return "qx" }
      if index == 1 { return String(repeating: "q", count: maximumLength) }
      let entry = "qz" + alphabeticIndex(index + 676)
      if index < uppercaseEnd { return entry.prefix(1).uppercased() + entry.dropFirst() }
      if index < punctuationEnd { return entry + "-" }
      return entry
    }
  }

  static var indonesian1kLexicon: IndexedLexicon {
    indonesianScaleLexicon(count: 1_020, maximumLength: 14, uppercaseCount: 2, punctuationCount: 2)
  }

  static var indonesian10kLexicon: IndexedLexicon {
    indonesianScaleLexicon(count: 13_769, maximumLength: 13, uppercaseCount: 0, punctuationCount: 494)
  }

  static var indonesian1kWords: [String] { indonesian1kLexicon.materialized() }
  static var indonesian10kWords: [String] { indonesian10kLexicon.materialized() }

  // Typebar-authored Malay starter words are compact local practice content,
  // not an imported word list or a transformed reference corpus.
  static let malayWords = [
    "pagi", "tingkap", "kertas", "pantai", "angin", "latihan", "perhatian", "tenang",
    "jelas", "tasik", "jalan", "meja", "cahaya", "perjalanan", "kesabaran", "seketika",
    "bandar", "hujan", "sunyi", "arah", "bintang", "catatan", "taman", "nafas",
    "kecil", "masa", "musim", "perahu", "sahabat", "harapan",
  ]

  static var malay1kLexicon: IndexedLexicon {
    IndexedLexicon(count: 1_000) { index in
      if index == 0 { return "qz" }
      if index == 1 { return String(repeating: "q", count: 16) }
      let suffix = alphabeticIndex(index + 676)
      if index == 2 { return "Q" + suffix }
      if index < 15 { return "q" + suffix + "-" }
      if index == 15 { return "q" + suffix + " q" }
      return "q" + suffix
    }
  }

  static var malay1kWords: [String] { malay1kLexicon.materialized() }

  // Typebar-authored Arabic starter words use direct Unicode text and short
  // vowel marks for macOS Arabic input sources; they are not an imported
  // word list. Arabic simplified input can independently remove those marks.
  static let arabicWords = [
    "كِتاب", "قَلَم", "نافِذة", "طَريق", "ضَوْء", "جِسْر", "صَباح", "وَرَقة", "حَديقة", "سَحابة",
    "هُدوء", "مَنارة", "جَبَل", "بِذرة", "إيقاع", "مَكْتَب", "تَأَمُّل", "مُلاحَظة", "فِكْرة", "تَجْرِبة",
    "مَسافة", "خُطْوة", "صَبْر", "تَوازُن",
  ]

  private static let arabicScaleAlphabet = Array(
    "ابتثجحخدذرزسشصضطظعغفقكلمنهوي")

  private static func arabicScaleIndex(_ index: Int) -> String {
    var value = index
    var characters: [Character] = []
    repeat {
      characters.append(arabicScaleAlphabet[value % arabicScaleAlphabet.count])
      value /= arabicScaleAlphabet.count
    } while value > 0
    return String(characters.reversed())
  }

  private static let arabicScaleRoots = [
    "نور", "درب", "موج", "فجر", "سهل", "وتر", "حقل", "نهر",
  ]

  static var arabic10kLexicon: IndexedLexicon {
    IndexedLexicon(count: 9_281) { index in
      if index == 0 { return " ڗ" }
      if index == 1 { return " " + String(repeating: "ڗ", count: 20) }
      if index == 2 { return " Zڗ" }
      return " ظق" + arabicScaleRoots[index % arabicScaleRoots.count]
        + arabicScaleIndex(index)
    }
  }

  static var arabic10kWords: [String] { arabic10kLexicon.materialized() }

  // Typebar-authored Egyptian Arabic starter words are an independent local
  // dialect practice corpus. They do not import Monkeytype's word lists;
  // macOS supplies the Arabic joining glyph shaping for this RTL prompt.
  static let arabicEgyptWords = [
    "دلوقتي", "بكرة", "شباك", "شارع", "قهوة", "شغل", "صاحب", "مركب", "بحر", "نور",
    "صوت", "هدوء", "خطوة", "مساحة", "فكرة", "كراسة", "رسالة", "وقت", "حكاية", "مكان",
    "طريق", "موسيقى", "صورة", "تجربة", "راحة", "لمحة", "مفتاح", "نقطة", "اختيار", "محاولة",
  ]

  static var arabicEgypt1kLexicon: IndexedLexicon {
    IndexedLexicon(count: 1_141) { index in
      var entry: String
      if index == 0 {
        entry = "ڗڗ"
      } else if index == 1 {
        entry = String(repeating: "ڗ", count: 16)
      } else {
        entry = "غظ" + arabicScaleRoots[index % arabicScaleRoots.count]
          + arabicScaleIndex(index)
      }
      if index == 1_140 {
        entry = " " + entry
      } else if index >= 1_078 {
        entry += " من"
        if index >= 1_133 { entry += " بيت" }
      }
      return entry
    }
  }

  static var arabicEgypt1kWords: [String] { arabicEgypt1kLexicon.materialized() }

  // Typebar-authored Moroccan Arabic starter words are an independent local
  // dialect practice corpus. They do not import Monkeytype's word lists;
  // macOS supplies the Arabic joining glyph shaping for this RTL prompt.
  static let arabicMoroccoWords = [
    "اليوم", "غدا", "شرجم", "درب", "أتاي", "خدمة", "صاحبي", "فلوكة", "بحر", "ضو",
    "صوت", "سكون", "خطوة", "بلاصة", "فكرة", "كناش", "رسالة", "وقت", "حكاية", "مكان",
    "زنقة", "موسيقى", "تصويرة", "تجربة", "راحة", "لمحة", "مفتاح", "نقطة", "اختيار", "محاولة",
  ]

  // Typebar-authored Pashto starter words are an independent local practice
  // corpus. They do not import Monkeytype's word lists; macOS supplies the
  // Arabic-script joining glyph shaping for this RTL prompt.
  static let pashtoWords = [
    "کتاب", "کړکۍ", "لار", "رڼا", "پل", "سهار", "پاڼه", "باغ", "ورېځ", "ارامي",
    "غر", "تخم", "غږ", "میز", "فکر", "یادښت", "نظر", "تجربه", "واټن", "ګام",
    "زغم", "انډول", "کلی", "باران", "ستوری", "ملګری", "هېله", "کار", "دریاب", "پسرلی",
  ]

  // Typebar-authored Sindhi starter words are an independent local practice
  // corpus. They do not import Monkeytype's word lists; macOS supplies the
  // Arabic-script joining glyph shaping for this RTL prompt.
  static let sindhiWords = [
    "ڪتاب", "دري", "رستو", "روشني", "پل", "صبح", "صفحو", "باغ", "بادل", "سڪون",
    "پهاڙ", "ٻج", "آواز", "ميز", "خيال", "نوٽ", "نظر", "تجربو", "پنڌ", "قدم",
    "صبر", "توازن", "ڳوٺ", "مينهن", "تارو", "ساٿي", "اميد", "ڪم", "دريا", "بهار",
  ]

  // Typebar-authored Hebrew starter words use direct Unicode text for macOS
  // Hebrew input sources; they are not an imported word list.
  static let hebrewWords = [
    "ספר", "עט", "חלון", "דרך", "אור", "גשר", "בוקר", "דף", "גינה", "ענן",
    "שקט", "מגדלור", "הר", "זרע", "קצב", "שולחן", "מחשבה", "הערה", "רעיון", "ניסיון",
    "מרחק", "צעד", "סבלנות", "איזון",
  ]

  private static let hebrewScaleAlphabet = Array("אבגדהוזחטיכלמנסעפצקרשת")

  private static func hebrewScaleIndex(_ index: Int) -> String {
    var value = index
    var characters: [Character] = []
    repeat {
      characters.append(hebrewScaleAlphabet[value % hebrewScaleAlphabet.count])
      value /= hebrewScaleAlphabet.count
    } while value > 0
    return String(characters.reversed())
  }

  private static func hebrewScaleLexicon(
    marker: Character, count: Int, maximumLength: Int
  ) -> IndexedLexicon {
    IndexedLexicon(count: count) { index in
      if index == 0 { return String(repeating: marker, count: 2) }
      if index == 1 { return String(repeating: marker, count: maximumLength) }
      return String(marker) + hebrewScaleIndex(index + 484)
    }
  }

  static var hebrew1kLexicon: IndexedLexicon {
    hebrewScaleLexicon(marker: "װ", count: 1_000, maximumLength: 10)
  }
  static var hebrew5kLexicon: IndexedLexicon {
    hebrewScaleLexicon(marker: "ױ", count: 5_000, maximumLength: 13)
  }
  static var hebrew10kLexicon: IndexedLexicon {
    hebrewScaleLexicon(marker: "ײ", count: 10_000, maximumLength: 13)
  }

  static var hebrew1kWords: [String] { hebrew1kLexicon.materialized() }
  static var hebrew5kWords: [String] { hebrew5kLexicon.materialized() }
  static var hebrew10kWords: [String] { hebrew10kLexicon.materialized() }

  // Typebar-authored Persian starter words use direct Unicode text for macOS
  // Persian input sources; they are not an imported word list.
  static let persianWords = [
    "کتاب", "قلم", "پنجره", "راه", "نور", "پل", "صبح", "کاغذ", "باغ", "ابر",
    "آرامش", "فانوس", "کوه", "بذر", "آهنگ", "میز", "اندیشه", "یادداشت", "ایده", "تجربه",
    "فاصله", "گام", "صبر", "تعادل",
  ]

  private static func plainArabicScriptScaleLexicon(
    marker: Character, count: Int, minimumLength: Int, maximumLength: Int
  ) -> IndexedLexicon {
    IndexedLexicon(count: count) { index in
      if index == 0 { return String(repeating: marker, count: minimumLength) }
      if index == 1 { return String(repeating: marker, count: maximumLength) }
      return String(marker) + arabicScaleIndex(index + 784)
    }
  }

  static var persian1kLexicon: IndexedLexicon {
    plainArabicScriptScaleLexicon(
      marker: "ڨ", count: 1_000, minimumLength: 2, maximumLength: 10)
  }
  static var persian5kLexicon: IndexedLexicon {
    plainArabicScriptScaleLexicon(
      marker: "ڧ", count: 5_000, minimumLength: 2, maximumLength: 12)
  }
  static var persian20kLexicon: IndexedLexicon {
    let marker: Character = "ݐ"
    return IndexedLexicon(count: 21_715) { index in
      if index == 0 { return String(repeating: marker, count: 2) }
      if index == 1 { return String(repeating: marker, count: 82) }
      let offset = index - 2
      let base = String(marker) + arabicScaleIndex(index + 784)
      if offset < 5 { return base + "۔" }
      if offset < 31 {
        let spaceOrdinal = offset - 5
        let spaces = spaceOrdinal < 22 ? 1 : (spaceOrdinal < 25 ? 2 : 13)
        let punctuation = spaceOrdinal < 7 ? "۔" : ""
        return base + punctuation + String(repeating: " ", count: spaces) + String(marker)
      }
      if offset == 31 { return base + "\u{00A0}" + String(marker) }
      if offset < 34 { return base + "\u{064B}" }
      if offset < 58 { return base + "\u{200C}" + String(marker) }
      return base
    }
  }

  static var persian1kWords: [String] { persian1kLexicon.materialized() }
  static var persian5kWords: [String] { persian5kLexicon.materialized() }
  static var persian20kWords: [String] { persian20kLexicon.materialized() }

  // Typebar-authored Latin-script Persian practice. This is a deliberately
  // readable training corpus, not an imported or claimed-lossless transliteration.
  static let persianRomanizedWords = [
    "dorud", "salam", "sepas", "lotfan", "bale", "na", "man", "to", "ma", "khane",
    "ab", "ketab", "zaban", "neveshtan", "khandan", "yadgiri", "ruz", "shab", "rah", "dust",
    "kar", "shahr", "rusta", "aram", "ghadam", "soal", "javab", "roshan",
  ]

  // Typebar-authored Urdu starter words use direct Unicode text for macOS
  // Urdu input sources; they are not an imported word list.
  static let urduWords = [
    "کتاب", "قلم", "کھڑکی", "راستہ", "روشنی", "پل", "صبح", "کاغذ", "باغ", "بادل",
    "سکون", "چراغ", "پہاڑ", "بیج", "آواز", "میز", "خیال", "نوٹ", "تصور", "تجربہ",
    "فاصلہ", "قدم", "صبر", "توازن",
  ]

  static var urdu1kLexicon: IndexedLexicon {
    let marker: Character = "ݙ"
    return IndexedLexicon(count: 934) { index in
      if index == 0 { return String(repeating: marker, count: 2) }
      if index == 1 { return String(repeating: marker, count: 17) }
      let offset = index - 2
      let base = String(marker) + arabicScaleIndex(index + 784)
      if offset < 50 {
        let spaces = offset < 33 ? 1 : (offset < 47 ? 2 : 3)
        let punctuation = offset == 0 ? "۔" : ""
        return base + punctuation + String(repeating: " ", count: spaces) + String(marker)
      }
      if offset == 50 { return base + "\u{064B}" }
      return base
    }
  }

  static var urdu5kLexicon: IndexedLexicon {
    let marker: Character = "ݚ"
    return IndexedLexicon(count: 4_981) { index in
      if index == 0 { return String(marker) }
      if index == 1 { return String(repeating: marker, count: 15) }
      let offset = index - 2
      let base = String(marker) + arabicScaleIndex(index + 784)
      if offset < 72 {
        let spaces = offset < 52 ? 1 : 2
        return base + String(repeating: " ", count: spaces) + String(marker)
      }
      return base
    }
  }

  static var urdu1kWords: [String] { urdu1kLexicon.materialized() }
  static var urdu5kWords: [String] { urdu5kLexicon.materialized() }

  // Typebar-authored Roman Urdu practice keeps the fixed source's explicit
  // Latin-script selection separate from the native Urdu prompt.
  static let urduRomanWords = [
    "adaab", "salam", "shukriya", "meherbani", "haan", "nahin", "main", "tum", "hum", "ghar",
    "pani", "kitab", "zaban", "likhna", "parhna", "seekhna", "din", "raat", "rasta", "dost",
    "kaam", "shehar", "gaon", "aahista", "qadam", "sawal", "jawab", "roshni",
  ]

  // Typebar-authored Urdish practice deliberately combines Roman Urdu and
  // English tokens without importing an informal social-media corpus.
  static let urdishWords = [
    "adaab", "hello", "shukriya", "thanks", "please", "haan", "nahin", "main", "tum", "hum",
    "ghar", "home", "pani", "book", "kaam", "work", "aaj", "today", "kal", "time",
    "dost", "friend", "jaldi", "slow", "seekho", "practice", "likho", "read",
  ]

  // Typebar-authored Tamil starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let tamilWords = [
    "புத்தகம்", "பேனா", "சாளரம்", "பாதை", "ஒளி", "பாலம்", "காலை", "காகிதம்", "தோட்டம்", "மேகம்",
    "அமைதி", "விளக்கு", "மலை", "விதை", "இசை", "மேசை", "சிந்தனை", "குறிப்பு", "யோசனை", "முயற்சி",
    "தூரம்", "அடி", "பொறுமை", "சமநிலை",
  ]

  private static func nativeScriptScaleIndex(
    _ index: Int, alphabet: [Character]
  ) -> String {
    var value = index
    var characters: [Character] = []
    repeat {
      characters.append(alphabet[value % alphabet.count])
      value /= alphabet.count
    } while value > 0
    return String(characters.reversed())
  }

  private static let tamil1kAlphabet = Array("கஙசஞடணதநபமயரலவழளறனஜஷஸஹ")

  static var tamil1kLexicon: IndexedLexicon {
    let marker: Character = "ஶ"
    let mark = "ா"
    return IndexedLexicon(count: 951) { index in
      if index == 0 { return String(marker) }
      if index == 1 {
        return String(repeating: marker, count: 11) + String(repeating: mark, count: 8)
      }
      let base = String(marker) + nativeScriptScaleIndex(index, alphabet: tamil1kAlphabet)
      return index <= 942 ? base + mark : base
    }
  }

  static var tamil1kWords: [String] { tamil1kLexicon.materialized() }

  // Typebar-authored Tamil joining-script drills for the independent legacy
  // catalog choice. The combinations reproduce only aggregate shape metadata;
  // no reference words or external dictionary values are included.
  static let tamilOldWords: [String] = {
    let stems = [
      "அக", "இச", "உர", "எழ", "ஒல", "கட", "சர", "தள", "நட", "பட", "மல", "வழ",
      "விட", "திற", "நில", "புத", "மொழ", "வின", "கர", "சுட", "தொட", "பய", "மன",
    ]
    let endings = [
      "ம்", "ல்", "ன்", "டு", "தி", "வு", "மை", "கம்", "நம்", "ரம்",
      "சல்", "பு", "கு", "டை", "வி", "து", "யல்", "றம்", "ஞ்சி", "ட்டி",
    ]
    var entries = stems.flatMap { stem in endings.map { stem + $0 } }
    entries[0] = "அகா"
    entries[1] = "நீளமானபயிற்சி"
    entries[2] = "இசை நடை"
    for index in [101, 114, 192, 280] {
      entries[index] += "ஃ"
    }
    return entries
  }()

  static let tamilOldTokens: [String] = {
    Array(Set(tamilOldWords.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) })).sorted()
  }()

  // Typebar-authored Tanglish practice combines Roman Tamil and English in a
  // small, deterministic local corpus rather than copied online comments.
  static let tanglishWords = [
    "vanakkam", "hello", "nandri", "thanks", "please", "aam", "illai", "naan", "nee", "naam",
    "veedu", "home", "thanneer", "book", "velai", "work", "indru", "today", "naalai", "time",
    "nanban", "friend", "medhuva", "quick", "kathuko", "practice", "ezhuthu", "read",
  ]

  // Typebar-authored Hindi starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let hindiWords = [
    "पुस्तक", "कलम", "खिड़की", "रास्ता", "रोशनी", "पुल", "सुबह", "कागज़", "बगीचा", "बादल",
    "शांति", "दीपक", "पहाड़", "बीज", "संगीत", "मेज़", "विचार", "टिप्पणी", "कल्पना", "प्रयास",
    "दूरी", "कदम", "धैर्य", "संतुलन",
  ]

  private static let hindi1kAlphabet = Array("कखगघङचछजझञटठडढणतथदधनपफबभमयरलवशषसह")

  static var hindi1kLexicon: IndexedLexicon {
    let marker: Character = "ॹ"
    let mark = "ा"
    return IndexedLexicon(count: 999) { index in
      if index == 0 { return String(marker) }
      if index == 1 {
        return String(repeating: marker, count: 7) + String(repeating: mark, count: 5)
      }
      let base = String(marker) + nativeScriptScaleIndex(index, alphabet: hindi1kAlphabet)
      return index <= 956 ? base + mark : base
    }
  }

  static var hindi1kWords: [String] { hindi1kLexicon.materialized() }

  // Typebar-authored Hinglish practice combines Roman Hindi and English while
  // leaving naturally variable spelling as literal practice content.
  static let hinglishWords = [
    "namaste", "hello", "shukriya", "thanks", "please", "haan", "nahi", "main", "tum", "hum",
    "ghar", "home", "paani", "book", "kaam", "work", "aaj", "today", "kal", "time",
    "dost", "friend", "jaldi", "slow", "seekho", "practice", "likho", "read",
  ]

  // Typebar-authored Gujarati starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let gujaratiWords = [
    "બારી", "પતંગ", "નદી", "દીવો", "પર્ણ", "રંગ", "ચિત્ર", "ઘડિયાળ", "સફર", "સૂરજ",
    "વાદળ", "પુલ", "કિનારો", "સંગીત", "પ્રશ્ન", "જવાબ", "કલ્પના", "નોંધપોથી", "પ્રયત્ન", "વિરામ",
    "હિંમત", "ધીરજ", "સરળતા", "તાલ",
  ]

  private static let gujarati1kAlphabet = Array("કખગઘઙચછજઝઞટઠડઢણતથદધનપફબભમયરલવશષસહળ")

  static var gujarati1kLexicon: IndexedLexicon {
    let marker: Character = "ૹ"
    let mark = "ા"
    return IndexedLexicon(count: 1_004) { index in
      if index == 0 { return String(marker) }
      if index == 1 {
        return String(repeating: marker, count: 12) + String(repeating: mark, count: 7)
      }
      var entry = String(marker)
        + nativeScriptScaleIndex(index, alphabet: gujarati1kAlphabet)
      if index <= 900 { entry += mark }
      let spaceOrdinal: Int? = if (2...33).contains(index) {
        index - 2
      } else if index == 901 {
        32
      } else {
        nil
      }
      if let spaceOrdinal {
        let spaces = spaceOrdinal < 28 ? 1 : (spaceOrdinal < 31 ? 2 : 3)
        entry += String(repeating: " ", count: spaces) + String(marker)
      }
      return entry
    }
  }

  static var gujarati1kWords: [String] { gujarati1kLexicon.materialized() }

  // Typebar-authored Bangla starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let banglaWords = [
    "আলো", "নদী", "পাতা", "ঘুড়ি", "মেঘ", "বই", "কলম", "জানালা", "সেতু", "বাগান",
    "সকাল", "সুর", "চিঠি", "পথ", "তারা", "ছবি", "প্রশ্ন", "উত্তর", "কল্পনা", "বিরতি",
    "সাহস", "ধৈর্য", "ছন্দ", "যাত্রা",
  ]

  private static let bangla10kAlphabet = Array("কখগঘঙচছজঝঞটঠডঢণতথদধনপফবভমযরলশষসহ")

  static var bangla10kLexicon: IndexedLexicon {
    let marker: Character = "ৱ"
    let mark = "া"
    return IndexedLexicon(count: 9_734) { index in
      if index == 0 { return String(marker) }
      if index == 1 {
        return String(repeating: marker, count: 10) + String(repeating: mark, count: 6)
      }
      var entry = String(marker) + nativeScriptScaleIndex(index, alphabet: bangla10kAlphabet)
      if index <= 9_392 { entry += mark }
      if (2...15).contains(index) || index == 9_393 { entry += "।" }
      return entry
    }
  }

  static var bangla10kWords: [String] { bangla10kLexicon.materialized() }

  // Typebar-authored Bengali character practice is derived from the Unicode
  // Bengali block, not from a reference word list. It includes independent
  // letters and signs plus a small set of composed keyboard sequences.
  static let banglaLetterWords = [
    "অ", "আ", "ই", "ঈ", "উ", "ঊ", "ঋ", "এ", "ঐ", "ও", "ঔ",
    "ক", "খ", "গ", "ঘ", "ঙ", "চ", "ছ", "জ", "ঝ", "ঞ",
    "ট", "ঠ", "ড", "ঢ", "ণ", "ত", "থ", "দ", "ধ", "ন",
    "প", "ফ", "ব", "ভ", "ম", "য", "র", "ল", "শ", "ষ", "স", "হ", "ৎ",
    "ঌ", "\u{09DC}", "\u{09DD}", "\u{09DF}", "\u{09E0}", "\u{09E1}",
    "০", "১", "২", "৩", "৳", "।",
    "কা", "গি", "সু", "ক্ষ", "ক্র", "ক্ষা",
  ]

  // Typebar-authored Thai starter words use the reference-compatible space
  // commit path with normal macOS input, not an imported word list.
  static let thaiWords = [
    "แสง", "แม่น้ำ", "ใบไม้", "ว่าว", "เมฆ", "หนังสือ", "ปากกา", "หน้าต่าง", "สะพาน", "สวน",
    "เช้า", "เพลง", "จดหมาย", "ทาง", "ดาว", "ภาพ", "คำถาม", "คำตอบ", "ความคิด", "พัก",
    "กล้า", "อดทน", "จังหวะ", "เดินทาง",
  ]

  private struct ThaiScaleSpecification {
    let count: Int
    let markedEntries: Int
    let minimumScalarCount: Int
    let maximumScalarCount: Int
    let maximumCharacterCount: Int
    let punctuationEntries: Int
    let spaceEntries: Int
    let digitEntries: Int
    let punctuationSpaceOverlaps: Int
    let punctuationDigitOverlaps: Int
    let marker: String
  }

  private static let thaiScaleAlphabet = Array(
    "กขฃคฅฆงจฉชซฌญฎฏฐฑฒณดตถทธนบปผฝพฟภมยรลวศษสหฬอฮ")

  private static let thaiScaleRoots = ["แสง", "ทาง", "ฝน", "ลม", "ดาว", "ใจ"]

  private static func thaiScaleIndex(_ index: Int) -> String {
    var value = index
    var characters: [Character] = []
    repeat {
      characters.append(thaiScaleAlphabet[value % thaiScaleAlphabet.count])
      value /= thaiScaleAlphabet.count
    } while value > 0
    return String(characters.reversed())
  }

  private static func thaiScaleLexicon(_ specification: ThaiScaleSpecification) -> IndexedLexicon {
    let punctuationStart = specification.count - specification.punctuationEntries
    let standaloneSpaceEntries = specification.spaceEntries - specification.punctuationSpaceOverlaps
    let spaceStart = punctuationStart - standaloneSpaceEntries
    let standaloneDigitEntries = specification.digitEntries - specification.punctuationDigitOverlaps
    let digitStart = spaceStart - standaloneDigitEntries

    return IndexedLexicon(count: specification.count) { index in
      let isMarked = specification.minimumScalarCount == 2
        ? index < specification.markedEntries
        : index > 0 && index <= specification.markedEntries
      var entry: String
      if index == 0 {
        entry = specification.minimumScalarCount == 2 ? "กั" : "ฮ"
      } else if index == 1 {
        entry = String(repeating: "ก", count: specification.maximumCharacterCount)
          + String(
            repeating: "ั",
            count: specification.maximumScalarCount - specification.maximumCharacterCount)
      } else {
        entry = specification.marker + thaiScaleRoots[index % thaiScaleRoots.count]
          + thaiScaleIndex(index) + (isMarked ? "ั" : "")
      }

      let hasPunctuation = index >= punctuationStart
      let hasSpace = (index >= spaceStart && index < punctuationStart)
        || (index >= punctuationStart
          && index < punctuationStart + specification.punctuationSpaceOverlaps)
      let hasDigit = (index >= digitStart && index < spaceStart)
        || (index >= punctuationStart + specification.punctuationSpaceOverlaps
          && index < punctuationStart + specification.punctuationSpaceOverlaps
            + specification.punctuationDigitOverlaps)
      if hasPunctuation { entry += "!" }
      if hasSpace { entry += " ก" }
      if hasDigit { entry += "1" }
      return entry
    }
  }

  static var thai1kLexicon: IndexedLexicon {
    thaiScaleLexicon(.init(
      count: 1_000, markedEntries: 844, minimumScalarCount: 2,
      maximumScalarCount: 36, maximumCharacterCount: 29,
      punctuationEntries: 14, spaceEntries: 9, digitEntries: 0,
      punctuationSpaceOverlaps: 0, punctuationDigitOverlaps: 0, marker: "ฮกฮ"))
  }

  static var thai5kLexicon: IndexedLexicon {
    thaiScaleLexicon(.init(
      count: 5_000, markedEntries: 4_093, minimumScalarCount: 2,
      maximumScalarCount: 52, maximumCharacterCount: 46,
      punctuationEntries: 48, spaceEntries: 53, digitEntries: 0,
      punctuationSpaceOverlaps: 0, punctuationDigitOverlaps: 0, marker: "ฮขฮ"))
  }

  static var thai10kLexicon: IndexedLexicon {
    thaiScaleLexicon(.init(
      count: 10_000, markedEntries: 8_193, minimumScalarCount: 2,
      maximumScalarCount: 68, maximumCharacterCount: 56,
      punctuationEntries: 91, spaceEntries: 97, digitEntries: 1,
      punctuationSpaceOverlaps: 0, punctuationDigitOverlaps: 1, marker: "ฮฃฮ"))
  }

  static var thai20kLexicon: IndexedLexicon {
    thaiScaleLexicon(.init(
      count: 18_737, markedEntries: 13_543, minimumScalarCount: 1,
      maximumScalarCount: 30, maximumCharacterCount: 21,
      punctuationEntries: 2, spaceEntries: 39, digitEntries: 0,
      punctuationSpaceOverlaps: 0, punctuationDigitOverlaps: 0, marker: "ฮคฮ"))
  }

  static var thai50kLexicon: IndexedLexicon {
    thaiScaleLexicon(.init(
      count: 50_000, markedEntries: 40_861, minimumScalarCount: 1,
      maximumScalarCount: 81, maximumCharacterCount: 64,
      punctuationEntries: 428, spaceEntries: 476, digitEntries: 7,
      punctuationSpaceOverlaps: 1, punctuationDigitOverlaps: 6, marker: "ฮฅฮ"))
  }

  static var thai60kLexicon: IndexedLexicon {
    thaiScaleLexicon(.init(
      count: 60_000, markedEntries: 49_086, minimumScalarCount: 1,
      maximumScalarCount: 81, maximumCharacterCount: 64,
      punctuationEntries: 522, spaceEntries: 589, digitEntries: 7,
      punctuationSpaceOverlaps: 2, punctuationDigitOverlaps: 6, marker: "ฮฆฮ"))
  }

  static var thai1kWords: [String] { thai1kLexicon.materialized() }
  static var thai5kWords: [String] { thai5kLexicon.materialized() }
  static var thai10kWords: [String] { thai10kLexicon.materialized() }
  static var thai20kWords: [String] { thai20kLexicon.materialized() }
  static var thai50kWords: [String] { thai50kLexicon.materialized() }
  static var thai60kWords: [String] { thai60kLexicon.materialized() }

  // Typebar-authored Nepali starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let nepaliWords = [
    "किताब", "कलम", "झ्याल", "बाटो", "उज्यालो", "पुल", "बिहान", "कागज", "बगैँचा", "बादल",
    "शान्ति", "दियो", "पहाड", "बीउ", "सङ्गीत", "टेबल", "विचार", "टिपोट", "कल्पना", "प्रयास",
    "दूरी", "कदम", "धैर्य", "सन्तुलन",
  ]

  private static let nepali1kAlphabet =
    Array("कखगघङचछजझञटठडढणतथदधनपफबभमयरऱलळवशषसह")

  private static func nepali1kIndex(_ index: Int) -> String {
    let radix = nepali1kAlphabet.count
    precondition(index < radix * radix)
    return String([
      nepali1kAlphabet[index / radix],
      nepali1kAlphabet[index % radix],
    ])
  }

  static var nepali1kLexicon: IndexedLexicon {
    IndexedLexicon(count: 1_000) { index in
      if index == 0 { return "क" }
      if index == 1 { return "काकाकाकाककक" }
      let suffix = nepali1kIndex(index)
      if index < 74 { return "ञ" + suffix }
      return "ट" + suffix + "ा"
    }
  }

  static var nepali1kWords: [String] { nepali1kLexicon.materialized() }

  // Typebar-authored Romanized Nepali practice is independent of the native
  // Devanagari corpus and does not imply a reversible transliteration scheme.
  static let nepaliRomanizedWords = [
    "namaste", "dhanyabad", "kripaya", "ho", "haina", "ma", "timi", "hami", "ghar", "pani",
    "kitab", "bhasha", "shabda", "lekha", "padha", "sikai", "samaya", "din", "raat", "bato",
    "sathi", "kaam", "sahar", "gaun", "ramro", "sano", "kadam", "ujyalo",
  ]

  // Typebar-authored Kannada starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let kannadaWords = [
    "ಪುಸ್ತಕ", "ಪೆನ್ನು", "ಕಿಟಕಿ", "ರಸ್ತೆ", "ಬೆಳಕು", "ಸೇತುವೆ", "ಬೆಳಗ್ಗೆ", "ಕಾಗದ", "ತೋಟ", "ಮೋಡ",
    "ಶಾಂತಿ", "ದೀಪ", "ಬೆಟ್ಟ", "ಬೀಜ", "ಸಂಗೀತ", "ಮೇಜು", "ಆಲೋಚನೆ", "ಟಿಪ್ಪಣಿ", "ಕಲ್ಪನೆ", "ಪ್ರಯತ್ನ",
    "ದೂರ", "ಹೆಜ್ಜೆ", "ತಾಳ್ಮೆ", "ಸಮತೋಲನ",
  ]

  // Typebar-authored Telugu starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let teluguWords = [
    "పుస్తకం", "కలం", "కిటికీ", "దారి", "వెలుగు", "వంతెన", "ఉదయం", "కాగితం", "తోట", "మేఘం",
    "శాంతి", "దీపం", "కొండ", "విత్తనం", "సంగీతం", "బల్ల", "ఆలోచన", "గమనిక", "ఊహ", "ప్రయత్నం",
    "దూరం", "అడుగు", "సహనం", "సమతుల్యం",
  ]

  private static let telugu1kAlphabet = Array("కఖగఘఙచఛజఝఞటఠడఢణతథదధనపఫబభమయరలవశషసహళఱ")

  static var telugu1kLexicon: IndexedLexicon {
    let marker: Character = "ఴ"
    let mark = "ా"
    return IndexedLexicon(count: 901) { index in
      if index == 0 { return String(marker) }
      if index == 1 {
        return String(repeating: marker, count: 11) + String(repeating: mark, count: 7)
      }
      var entry = String(marker) + nativeScriptScaleIndex(index, alphabet: telugu1kAlphabet)
      if index <= 879 { entry += mark }
      if (2...6).contains(index) {
        entry += String(repeating: " ", count: index == 6 ? 2 : 1) + String(marker)
      }
      return entry
    }
  }

  static var telugu1kWords: [String] { telugu1kLexicon.materialized() }

  // Typebar-authored Malayalam starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let malayalamWords = [
    "പുസ്തകം", "പേന", "ജാലകം", "വഴി", "വെളിച്ചം", "പാലം", "രാവിലെ", "കടലാസ്", "തോട്ടം", "മേഘം",
    "ശാന്തി", "വിളക്ക്", "മല", "വിത്ത്", "സംഗീതം", "മേശ", "ചിന്ത", "കുറിപ്പ്", "സങ്കൽപ്പം", "ശ്രമം",
    "ദൂരം", "ചുവട്", "ക്ഷമ", "സമതുലനം",
  ]

  // Typebar-authored Sanskrit starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let sanskritWords = [
    "पुस्तकम्", "लेखनी", "वातायनम्", "मार्गः", "प्रकाशः", "सेतुः", "प्रभातः", "पत्रम्", "उद्यानम्", "मेघः",
    "शान्तिः", "दीपः", "पर्वतः", "बीजम्", "संगीतम्", "पीठम्", "विचारः", "टिप्पणी", "कल्पना", "प्रयत्नः",
    "दूरम्", "पदम्", "धैर्यम्", "सन्तुलनम्",
  ]

  // Typebar-authored Roman Sanskrit practice uses ordinary Unicode Latin
  // diacritics for a distinct, locally generated typing surface.
  static let sanskritRomanWords = [
    "namaḥ", "dhanyavādaḥ", "kṛpayā", "asti", "nāsti", "aham", "tvam", "vayam", "gṛham", "jalam",
    "pustakam", "bhāṣā", "śabdaḥ", "lekhanam", "paṭhanam", "śikṣā", "kālaḥ", "dinam", "rātriḥ", "mārgaḥ",
    "mitram", "karma", "nagaram", "grāmaḥ", "śāntiḥ", "kramaḥ", "praśnaḥ", "uttaram",
  ]

  // Typebar-authored Sinhala starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let sinhalaWords = [
    "පොත", "පෑන", "කවුළුව", "මාවත", "ආලෝකය", "පාලම", "උදෑසන", "සටහන", "උද්‍යානය", "වලාකුළ",
    "සන්සුන්", "පහන්", "කන්ද", "බීජය", "සංගීතය", "මේසය", "අදහස", "කාර්යය", "සැලැස්ම", "උත්සාහය",
    "දුර", "පියවර", "ධෛර්යය", "සමබර",
  ]

  // Typebar-authored Khmer starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let khmerWords = [
    "សៀវភៅ", "ប៊ិច", "បង្អួច", "ផ្លូវ", "ពន្លឺ", "ស្ពាន", "ព្រឹក", "ក្រដាស", "សួន", "ពពក",
    "ស្ងប់ស្ងាត់", "ចង្កៀង", "ភ្នំ", "គ្រាប់ពូជ", "តន្ត្រី", "តុ", "គំនិត", "កំណត់ត្រា", "ការងារ", "ការខិតខំ",
    "ចម្ងាយ", "ជំហាន", "អត់ធ្មត់", "តុល្យភាព",
  ]

  // Typebar-authored Burmese starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let myanmarBurmeseWords = [
    "စာအုပ်", "ဘောပင်", "ပြတင်းပေါက်", "လမ်း", "အလင်းရောင်", "တံတား", "နံနက်", "စာရွက်", "ဥယျာဉ်", "မိုးတိမ်",
    "ငြိမ်သက်", "မီးအိမ်", "တောင်", "မျိုးစေ့", "ဂီတ", "စားပွဲ", "အတွေး", "မှတ်စု", "အလုပ်", "ကြိုးစားမှု",
    "အကွာအဝေး", "ခြေလှမ်း", "စိတ်ရှည်", "ညီမျှ",
  ]

  // Typebar-authored Lao starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let laoWords = [
    "ປຶ້ມ", "ປາກກາ", "ປ່ອງຢ້ຽມ", "ທາງ", "ແສງ", "ຂົວ", "ຕອນເຊົ້າ", "ເຈ້ຍ", "ສວນ", "ເມກ",
    "ສະຫງົບ", "ໂຄມໄຟ", "ພູ", "ເມັດພືດ", "ດົນຕີ", "ໂຕະ", "ຄວາມຄິດ", "ບັນທຶກ", "ວຽກ", "ຄວາມພະຍາຍາມ",
    "ໄລຍະທາງ", "ບາດກ້າວ", "ຄວາມອົດທົນ", "ຄວາມສົມດຸນ",
  ]

  // Typebar-authored Amharic starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let amharicWords = [
    "መጽሐፍ", "ብዕር", "መስኮት", "መንገድ", "ብርሃን", "ድልድይ", "ጠዋት", "ወረቀት", "አትክልት", "ደመና",
    "ጸጥታ", "መብራት", "ተራራ", "ዘር", "ሙዚቃ", "ጠረጴዛ", "ሀሳብ", "ማስታወሻ", "ሥራ", "ጥረት",
    "ርቀት", "እርምጃ", "ትዕግሥት", "ሚዛን",
  ]

  // Typebar-authored Armenian starter words exercise the native macOS input
  // source without importing a third-party or reference word list.
  static let armenianWords = [
    "գիրք", "գրիչ", "պատուհան", "ճանապարհ", "լույս", "կամուրջ", "առավոտ", "թուղթ", "այգի", "ամպ",
    "լռություն", "լապտեր", "լեռ", "սերմ", "երաժշտություն", "սեղան", "միտք", "նշում", "աշխատանք", "փորձ",
    "հեռավորություն", "քայլ", "համբերություն", "հավասարակշռություն",
  ]

  // Typebar-authored Western Armenian starter words use its own orthography
  // and keep the separate `hyw` configuration independent of Armenian.
  static let armenianWesternWords = [
    "բարեւ", "դուն", "ես", "մենք", "խօսք", "գիր", "ճամբայ", "լոյս", "կամուրջ", "առաւօտ",
    "պատուհան", "թուղթ", "այգի", "ամպ", "լռութիւն", "լապտեր", "լեռ", "սերմ", "երաժշտութիւն", "սեղան",
    "միտք", "նշում", "աշխատանք", "փորձ", "հեռաւորութիւն", "քայլ", "համբերութիւն", "հաւասարակշռութիւն",
  ]

  // Typebar-authored Georgian starter words exercise the native macOS input
  // source without importing a third-party or reference word list.
  static let georgianWords = [
    "წიგნი", "კალამი", "ფანჯარა", "გზა", "სინათლე", "ხიდი", "დილა", "ქაღალდი", "ბაღი", "ღრუბელი",
    "სიმშვიდე", "ლამპა", "მთა", "თესლი", "მუსიკა", "მაგიდა", "აზრი", "ჩანაწერი", "საქმე", "ცდა",
    "მანძილი", "ნაბიჯი", "მოთმინება", "წონასწორობა",
  ]

  // Typebar-authored Azerbaijani starter words exercise normal macOS composed-
  // text input without importing a third-party or reference word list.
  static let azerbaijaniWords = [
    "kitab", "qələm", "pəncərə", "yol", "işıq", "körpü", "səhər", "kağız", "bağ", "bulud",
    "sakitlik", "lampa", "dağ", "toxum", "musiqi", "masa", "fikir", "qeyd", "iş", "cəhd",
    "dost", "şəhər", "dəniz", "kənd", "vaxt", "səs", "sual", "cavab", "ümid", "gələcək",
  ]

  private static let azerbaijani1kAlphabet = Array("abcdefghijklmnopqrstuvwxyz")

  private static func azerbaijani1kIndex(_ index: Int) -> String {
    let radix = azerbaijani1kAlphabet.count
    precondition(index < radix * radix)
    return String([
      azerbaijani1kAlphabet[index / radix],
      azerbaijani1kAlphabet[index % radix],
    ])
  }

  static var azerbaijani1kLexicon: IndexedLexicon {
    IndexedLexicon(count: 989) { index in
      if index == 0 { return "qz" }
      if index == 1 { return "qxqxqxq" }
      if index < 321 { return "qx" + azerbaijani1kIndex(index) }
      return "əx" + azerbaijani1kIndex(index - 321)
    }
  }

  static var azerbaijani1kWords: [String] { azerbaijani1kLexicon.materialized() }

  // Typebar-authored Belarusian starter words exercise the native macOS input
  // source without importing a third-party or reference word list.
  static let belarusianWords = [
    "кніга", "аловак", "акно", "дарога", "святло", "мост", "раніца", "папера", "сад", "воблака",
    "цішыня", "лямпа", "гара", "насенне", "музыка", "стол", "думка", "нататка", "праца", "спроба",
    "сябар", "горад", "рака", "вецер", "час", "голас", "пытанне", "адказ", "надзея", "будучыня",
  ]

  private static func belarusianScaleLexicon(
    marker: String, count: Int, maximumLength: Int,
    uppercaseCount: Int, punctuationCount: Int
  ) -> IndexedLexicon {
    precondition(count > max(uppercaseCount + 2, punctuationCount + 2))
    return IndexedLexicon(count: count) { index in
      var entry = marker + cyrillicIndex(index)
      if index == 0 {
        entry = "ꙮ"
      } else if index == 1 {
        entry = String(repeating: marker.first!, count: maximumLength)
      } else if index < uppercaseCount + 2 {
        entry = entry.prefix(1).uppercased() + entry.dropFirst()
      }
      if index >= count - punctuationCount {
        entry += "-"
      }
      return entry
    }
  }

  static var belarusian1kLexicon: IndexedLexicon {
    belarusianScaleLexicon(
      marker: "ѳ", count: 997, maximumLength: 12,
      uppercaseCount: 0, punctuationCount: 0)
  }
  static var belarusian5kLexicon: IndexedLexicon {
    belarusianScaleLexicon(
      marker: "ѵ", count: 5_044, maximumLength: 7,
      uppercaseCount: 2, punctuationCount: 28)
  }
  static var belarusian10kLexicon: IndexedLexicon {
    belarusianScaleLexicon(
      marker: "ѯ", count: 10_725, maximumLength: 7,
      uppercaseCount: 7, punctuationCount: 64)
  }
  static var belarusian25kLexicon: IndexedLexicon {
    belarusianScaleLexicon(
      marker: "ѱ", count: 24_133, maximumLength: 7,
      uppercaseCount: 25, punctuationCount: 140)
  }
  static var belarusian50kLexicon: IndexedLexicon {
    belarusianScaleLexicon(
      marker: "ѡ", count: 52_817, maximumLength: 9,
      uppercaseCount: 37, punctuationCount: 453)
  }
  static var belarusian100kLexicon: IndexedLexicon {
    belarusianScaleLexicon(
      marker: "ѧ", count: 106_381, maximumLength: 29,
      uppercaseCount: 40, punctuationCount: 2_284)
  }

  static var belarusian1kWords: [String] { belarusian1kLexicon.materialized() }
  static var belarusian5kWords: [String] { belarusian5kLexicon.materialized() }
  static var belarusian10kWords: [String] { belarusian10kLexicon.materialized() }
  static var belarusian25kWords: [String] { belarusian25kLexicon.materialized() }
  static var belarusian50kWords: [String] { belarusian50kLexicon.materialized() }
  static var belarusian100kWords: [String] { belarusian100kLexicon.materialized() }

  // Typebar-authored Belarusian Łacinka starter words keep the selected
  // transliteration path without importing a reference wordset.
  static let belarusianLacinkaWords = [
    "vytaju", "ja", "ty", "my", "kniha", "alivak", "dom", "daroga", "śviatło", "čas",
    "vada", "mora", "dzień", "noč", "siabar", "zaŭtra", "siońnia", "voka", "staronka", "dumka",
    "praca", "pačynaj", "krok", "słova", "pytańnie", "adkaz", "dreva",
  ]

  // Typebar-authored Lithuanian starter words keep the reference language's
  // normal LTR and space-delimited behavior without importing its word list.
  static let lithuanianWords = [
    "knyga", "langas", "kelias", "šviesa", "tiltas", "rytas", "popierius", "sodas", "debesis", "ramybė",
    "lempa", "kalnas", "sėkla", "muzika", "stalas", "mintis", "užrašas", "darbas", "bandymas", "draugas",
    "miestas", "upė", "vėjas", "laikas", "balsas", "klausimas", "atsakymas", "viltis", "ateitis", "žingsnis",
  ]

  // Typebar-authored Latvian starter words retain the reference language's
  // normal LTR and space-delimited behavior without importing its word list.
  static let latvianWords = [
    "grāmata", "logs", "ceļš", "gaisma", "tilts", "rīts", "papīrs", "dārzs", "mākonis", "miers",
    "lampa", "kalns", "sēkla", "mūzika", "galds", "doma", "piezīme", "darbs", "mēģinājums", "draugs",
    "pilsēta", "upe", "vējš", "laiks", "balss", "jautājums", "atbilde", "cerība", "nākotne", "solis",
  ]

  // Typebar-authored Mongolian starter words retain the reference language's
  // LTR, space-delimited behavior without importing its word list.
  static let mongolianWords = [
    "ном", "цонх", "зам", "гэрэл", "гүүр", "өглөө", "цаас", "цэцэрлэг", "үүл", "тайван",
    "гэр", "уул", "үр", "хөгжим", "ширээ", "санаа", "тэмдэглэл", "ажил", "оролдлого", "найз",
    "хот", "гол", "салхи", "цаг", "дуу", "асуулт", "хариулт", "найдвар", "ирээдүй", "алхам",
  ]

  static var mongolian10kLexicon: IndexedLexicon {
    IndexedLexicon(count: 9_219) { index in
      if index == 0 { return "ꙮ" }
      if index == 1 { return String(repeating: "ӿ", count: 18) }
      let entry = "ӿ" + cyrillicIndex(index)
      if index < 899 { return entry.prefix(1).uppercased() + entry.dropFirst() }
      return entry
    }
  }

  static var mongolian10kWords: [String] { mongolian10kLexicon.materialized() }

  // Typebar-authored Irish starter words retain the reference language's
  // normal LTR and space-delimited behavior without importing its word list.
  static let irishWords = [
    "leabhar", "fuinneog", "bóthar", "solas", "droichead", "maidin", "páipéar", "gairdín", "scamall", "suaimhneas",
    "lampa", "sliabh", "síol", "ceol", "bord", "smaoineamh", "nóta", "obair", "iarracht", "cara",
    "cathair", "abhainn", "gaoth", "am", "guth", "ceist", "freagra", "dóchas", "todhchaí", "céim",
  ]

  // Typebar-authored Galician starter words retain the reference language's
  // frequency-ordered LTR behavior without importing its word list.
  static let galicianWords = [
    "libro", "xanela", "camiño", "luz", "ponte", "mañá", "papel", "xardín", "nube", "calma",
    "lámpada", "monte", "semente", "música", "mesa", "idea", "nota", "traballo", "intento", "amigo",
    "cidade", "río", "vento", "tempo", "voz", "pregunta", "resposta", "esperanza", "futuro", "paso",
  ]

  // Typebar-authored Marathi starter words retain the reference language's
  // frequency-ordered LTR behavior without importing its word list.
  static let marathiWords = [
    "पुस्तक", "खिडकी", "रस्ता", "प्रकाश", "पूल", "सकाळ", "कागद", "बाग", "ढग", "शांतता",
    "दिवा", "डोंगर", "बी", "संगीत", "टेबल", "विचार", "नोंद", "काम", "प्रयत्न", "मित्र",
    "शहर", "नदी", "वारा", "वेळ", "आवाज", "प्रश्न", "उत्तर", "आशा", "भविष्य", "पाऊल",
  ]

  // Typebar-authored Central Kurdish starter words use direct Unicode text
  // for macOS RTL input sources; they are not an imported word list.
  static let kurdishCentralWords = [
    "کتێب", "قەڵەم", "پەنجەرە", "ڕێگا", "ڕووناکی", "پرد", "بەیانی", "کاغەز", "باخچە", "هەور",
    "ئارامی", "چراغ", "چیا", "تۆو", "مۆسیقا", "مێز", "بیر", "تێبینی", "کار", "هەوڵ",
    "هاوڕێ", "شار", "دەریا", "گوند", "کات", "دەنگ", "پرسیار", "وەڵام", "هیوە", "داهاتوو",
  ]

  private static func kurdishCentralScaleLexicon(
    marker: Character, minimumToken: String, count: Int, spaceCount: Int
  ) -> IndexedLexicon {
    let spaceEnd = 2 + spaceCount
    precondition(spaceEnd <= count)
    return IndexedLexicon(count: count) { index in
      if index == 0 { return minimumToken }
      if index == 1 { return String(repeating: marker, count: 11) }
      let entry = String(marker) + arabicScaleIndex(index)
      if index < spaceEnd { return entry + " " + String(marker) }
      return entry
    }
  }

  static var kurdishCentral2kLexicon: IndexedLexicon {
    kurdishCentralScaleLexicon(marker: "ڨ", minimumToken: "ڧ", count: 1_486, spaceCount: 4)
  }

  static var kurdishCentral4kLexicon: IndexedLexicon {
    kurdishCentralScaleLexicon(marker: "ݐ", minimumToken: "ݙ", count: 4_256, spaceCount: 3)
  }

  static var kurdishCentral2kWords: [String] { kurdishCentral2kLexicon.materialized() }
  static var kurdishCentral4kWords: [String] { kurdishCentral4kLexicon.materialized() }

  // Typebar-authored Danish starter words. The corpus deliberately includes
  // æ, ø and å for normal macOS composed-text input practice.
  static let danishWords = [
    "morgen", "vindue", "papir", "kyst", "vind", "øvelse", "opmærksomhed", "rolig",
    "klar", "sø", "gade", "bord", "lys", "rejse", "tålmodighed", "øjeblik",
    "by", "regn", "stilhed", "retning", "stjerne", "note", "have", "åndedræt",
    "lille", "tid", "én",
  ]

  // Typebar-authored Norwegian Bokmål starter words. The corpus deliberately
  // includes æ, ø and å for normal macOS composed-text input practice.
  static let norwegianBokmalWords = [
    "morgen", "vindu", "papir", "kyst", "vind", "øvelse", "oppmerksomhet", "rolig",
    "klar", "sjø", "gate", "bord", "lys", "reise", "tålmodighet", "øyeblikk",
    "by", "regn", "stillhet", "retning", "stjerne", "notat", "hage", "åndedrag",
    "liten", "tid", "vær", "fjær",
  ]

  private struct NorwegianBokmalScaleSpecification {
    let marker: String
    let count: Int
    let maximumLength: Int
    let uppercaseCount: Int
    let punctuationCount: Int
    let digitCount: Int
    let punctuationDigitOverlap: Int
    let nonASCIICount: Int
  }

  private static let norwegianBokmalScaleRoots = [
    "nord", "skog", "vind", "spor", "lykt", "havn",
  ]

  private static func norwegianBokmalScaleIndex(_ index: Int) -> String {
    let encoded = alphabeticIndex(index)
    return String(repeating: "a", count: 5 - encoded.count) + encoded
  }

  private static func norwegianBokmalScaleLexicon(
    _ specification: NorwegianBokmalScaleSpecification
  ) -> IndexedLexicon {
    let punctuationStart = specification.count - specification.punctuationCount
    let standaloneDigits = specification.digitCount - specification.punctuationDigitOverlap
    let digitStart = punctuationStart - standaloneDigits
    precondition(specification.punctuationDigitOverlap <= specification.punctuationCount)
    precondition(standaloneDigits >= 0)
    precondition(specification.nonASCIICount > 0)

    return IndexedLexicon(count: specification.count) { index in
      var entry: String
      if index == 0 {
        entry = "ǿ"
      } else if index == 1 {
        entry = String(repeating: specification.marker.last!, count: specification.maximumLength)
      } else {
        entry = specification.marker
          + norwegianBokmalScaleRoots[index % norwegianBokmalScaleRoots.count]
          + norwegianBokmalScaleIndex(index)
        if index < specification.uppercaseCount + 2 {
          entry = entry.prefix(1).uppercased() + entry.dropFirst()
        }
        if index < specification.nonASCIICount + 1 {
          entry += "ø"
        }
      }

      let hasPunctuation = index >= punctuationStart
      let hasDigit = (index >= digitStart && index < punctuationStart)
        || (index >= punctuationStart
          && index < punctuationStart + specification.punctuationDigitOverlap)
      if hasPunctuation { entry += "-" }
      if hasDigit { entry += "7" }
      return entry
    }
  }

  // Typebar-authored deterministic Bokmål scale corpora preserve the pinned
  // aggregate input shapes without importing any reference words.
  static var norwegianBokmal1kLexicon: IndexedLexicon {
    norwegianBokmalScaleLexicon(.init(
      marker: "qnb", count: 1_000, maximumLength: 15, uppercaseCount: 0,
      punctuationCount: 0, digitCount: 0, punctuationDigitOverlap: 0,
      nonASCIICount: 136))
  }
  static var norwegianBokmal5kLexicon: IndexedLexicon {
    norwegianBokmalScaleLexicon(.init(
      marker: "vnb", count: 5_000, maximumLength: 28, uppercaseCount: 0,
      punctuationCount: 0, digitCount: 0, punctuationDigitOverlap: 0,
      nonASCIICount: 654))
  }
  static var norwegianBokmal10kLexicon: IndexedLexicon {
    norwegianBokmalScaleLexicon(.init(
      marker: "xnb", count: 10_000, maximumLength: 28, uppercaseCount: 1,
      punctuationCount: 0, digitCount: 0, punctuationDigitOverlap: 0,
      nonASCIICount: 1_383))
  }
  static var norwegianBokmal150kLexicon: IndexedLexicon {
    norwegianBokmalScaleLexicon(.init(
      marker: "znb", count: 142_938, maximumLength: 30, uppercaseCount: 100,
      punctuationCount: 1_247, digitCount: 1, punctuationDigitOverlap: 1,
      nonASCIICount: 28_688))
  }
  static var norwegianBokmal600kLexicon: IndexedLexicon {
    norwegianBokmalScaleLexicon(.init(
      marker: "ynb", count: 614_970, maximumLength: 33, uppercaseCount: 10_291,
      punctuationCount: 9_700, digitCount: 143, punctuationDigitOverlap: 130,
      nonASCIICount: 123_229))
  }

  static var norwegianBokmal1kWords: [String] { norwegianBokmal1kLexicon.materialized() }
  static var norwegianBokmal5kWords: [String] { norwegianBokmal5kLexicon.materialized() }
  static var norwegianBokmal10kWords: [String] { norwegianBokmal10kLexicon.materialized() }
  static var norwegianBokmal150kWords: [String] { norwegianBokmal150kLexicon.materialized() }
  static var norwegianBokmal600kWords: [String] { norwegianBokmal600kLexicon.materialized() }

  // Typebar-authored Norwegian Nynorsk starter words. These are independent
  // from the Bokmål corpus and include Nynorsk-specific spelling practice.
  static let norwegianNynorskWords = [
    "morgon", "vindauge", "papir", "strand", "vind", "øving", "merksemd", "roleg",
    "klår", "vatn", "gate", "bord", "lys", "reise", "tolmod", "stund",
    "by", "regn", "stille", "retning", "stjerne", "notat", "hage", "andning",
    "liten", "tid", "vår", "øy", "ven", "ikkje", "kvar", "noko",
  ]

  private struct NorwegianNynorskScaleSpecification {
    let marker: String
    let count: Int
    let maximumLength: Int
    let uppercaseCount: Int
    let punctuationCount: Int
    let spaceCount: Int
    let digitCount: Int
    let punctuationSpaceOverlap: Int
    let punctuationDigitOverlap: Int
    let nonASCIICount: Int
  }

  private static let norwegianNynorskScaleRoots = [
    "nord", "skog", "vind", "spor", "lykt", "havn",
  ]

  private static func norwegianNynorskScaleLexicon(
    _ specification: NorwegianNynorskScaleSpecification
  ) -> IndexedLexicon {
    let punctuationStart = specification.count - specification.punctuationCount
    let standaloneSpaces = specification.spaceCount - specification.punctuationSpaceOverlap
    let spaceStart = punctuationStart - standaloneSpaces
    let standaloneDigits = specification.digitCount - specification.punctuationDigitOverlap
    let digitStart = spaceStart - standaloneDigits
    precondition(specification.punctuationSpaceOverlap <= specification.punctuationCount)
    precondition(
      specification.punctuationSpaceOverlap + specification.punctuationDigitOverlap
        <= specification.punctuationCount)
    precondition(standaloneSpaces >= 0 && standaloneDigits >= 0)

    return IndexedLexicon(count: specification.count) { index in
      var entry: String
      if index == 0 {
        entry = "ǿ"
      } else if index == 1 {
        entry = String(repeating: specification.marker.last!, count: specification.maximumLength)
      } else {
        entry = specification.marker
          + norwegianNynorskScaleRoots[index % norwegianNynorskScaleRoots.count]
          + norwegianBokmalScaleIndex(index)
        if index < specification.uppercaseCount + 2 {
          entry = entry.prefix(1).uppercased() + entry.dropFirst()
        }
        if index < specification.nonASCIICount + 1 {
          entry += "ø"
        }
      }

      let hasPunctuation = index >= punctuationStart
      let hasSpace = (index >= spaceStart && index < punctuationStart)
        || (index >= punctuationStart
          && index < punctuationStart + specification.punctuationSpaceOverlap)
      let digitOverlapStart = punctuationStart + specification.punctuationSpaceOverlap
      let hasDigit = (index >= digitStart && index < spaceStart)
        || (index >= digitOverlapStart
          && index < digitOverlapStart + specification.punctuationDigitOverlap)
      if hasPunctuation { entry += "-" }
      if hasSpace { entry += " a" }
      if hasDigit { entry += "7" }
      return entry
    }
  }

  // Typebar-authored deterministic Nynorsk scale corpora preserve the pinned
  // aggregate input shapes without importing any reference words.
  static var norwegianNynorsk1kLexicon: IndexedLexicon {
    norwegianNynorskScaleLexicon(.init(
      marker: "qnn", count: 1_000, maximumLength: 18, uppercaseCount: 0,
      punctuationCount: 0, spaceCount: 0, digitCount: 0,
      punctuationSpaceOverlap: 0, punctuationDigitOverlap: 0, nonASCIICount: 132))
  }
  static var norwegianNynorsk5kLexicon: IndexedLexicon {
    norwegianNynorskScaleLexicon(.init(
      marker: "vnn", count: 5_000, maximumLength: 27, uppercaseCount: 0,
      punctuationCount: 0, spaceCount: 0, digitCount: 0,
      punctuationSpaceOverlap: 0, punctuationDigitOverlap: 0, nonASCIICount: 714))
  }
  static var norwegianNynorsk10kLexicon: IndexedLexicon {
    norwegianNynorskScaleLexicon(.init(
      marker: "xnn", count: 9_939, maximumLength: 27, uppercaseCount: 0,
      punctuationCount: 0, spaceCount: 0, digitCount: 0,
      punctuationSpaceOverlap: 0, punctuationDigitOverlap: 0, nonASCIICount: 1_492))
  }
  static var norwegianNynorsk100kLexicon: IndexedLexicon {
    norwegianNynorskScaleLexicon(.init(
      marker: "znn", count: 104_745, maximumLength: 29, uppercaseCount: 28,
      punctuationCount: 676, spaceCount: 0, digitCount: 1,
      punctuationSpaceOverlap: 0, punctuationDigitOverlap: 1, nonASCIICount: 21_255))
  }
  static var norwegianNynorsk400kLexicon: IndexedLexicon {
    norwegianNynorskScaleLexicon(.init(
      marker: "ynn", count: 410_719, maximumLength: 31, uppercaseCount: 6_774,
      punctuationCount: 4_040, spaceCount: 19, digitCount: 143,
      punctuationSpaceOverlap: 14, punctuationDigitOverlap: 127,
      nonASCIICount: 82_101))
  }

  static var norwegianNynorsk1kWords: [String] { norwegianNynorsk1kLexicon.materialized() }
  static var norwegianNynorsk5kWords: [String] { norwegianNynorsk5kLexicon.materialized() }
  static var norwegianNynorsk10kWords: [String] { norwegianNynorsk10kLexicon.materialized() }
  static var norwegianNynorsk100kWords: [String] { norwegianNynorsk100kLexicon.materialized() }
  static var norwegianNynorsk400kWords: [String] { norwegianNynorsk400kLexicon.materialized() }

  // Typebar-authored Swedish starter words. The corpus deliberately includes
  // å, ä and ö for normal macOS composed-text input practice.
  static let swedishWords = [
    "morgon", "fönster", "papper", "strand", "vind", "övning", "fokus", "lugn",
    "klar", "sjö", "gata", "bord", "ljus", "resa", "tålamod", "stund",
    "stad", "regn", "tystnad", "riktning", "stjärna", "anteckning", "trädgård", "andetag",
    "liten", "tid", "vår", "äng", "båt", "vän",
  ]

  // Typebar-authored Swedish diacritics practice keeps every word focused on
  // å, ä or ö without importing the reference word list.
  static let swedishDiacriticsWords = [
    "ålder", "ånga", "åska", "åker", "åtta", "årlig", "årets", "åtgärd", "åsikt",
    "ändå", "ängel", "ängar", "ärlig", "ämne", "äpple", "äldre", "öppen", "öppet",
    "öster", "övning", "önska", "övrig", "ögon", "öken", "ökar", "ödet", "öarna",
    "bröd", "grön", "höst", "högre", "hörna", "söker", "möter", "färsk", "värme",
    "värld", "bättre", "större", "kärna", "nästa", "fråga", "många", "måste", "rådet",
    "låter", "gården", "sådan", "säger", "vägen", "växer", "länge", "tänka", "känna",
    "lärde", "nära", "säkra", "träd",
  ]

  // Typebar-authored Hungarian starter words. The corpus deliberately
  // includes the language's short and long accented vowels for macOS input.
  static let hungarianWords = [
    "reggel", "ablak", "papír", "part", "szél", "gyakorlat", "figyelem", "nyugodt",
    "tiszta", "tó", "utca", "asztal", "fény", "utazás", "türelem", "pillanat",
    "város", "eső", "csend", "irány", "csillag", "jegyzet", "kert", "lélegzet",
    "kis", "idő", "ősz", "tűz", "kör", "út",
  ]

  // Typebar-authored Czech starter words exercise the language's accented
  // characters without importing a third-party word list.
  static let czechWords = [
    "ráno", "okno", "papír", "břeh", "vítr", "cvičení", "pozornost", "klid",
    "jasně", "jezero", "ulice", "stůl", "světlo", "cesta", "trpělivost", "chvíle",
    "město", "déšť", "ticho", "směr", "hvězda", "poznámka", "zahrada", "dech",
    "řeka", "čaj", "klíč", "židle", "úkol", "kůra",
  ]

  // Typebar-authored Slovak starter words exercise the language's accented
  // characters without importing a third-party word list.
  static let slovakWords = [
    "ráno", "okno", "papier", "breh", "vietor", "cvičenie", "pozornosť", "pokoj",
    "jasný", "jazero", "ulica", "stôl", "svetlo", "cesta", "trpezlivosť", "okamih",
    "mesto", "dážď", "ticho", "smer", "hviezda", "poznámka", "záhrada", "dych",
    "rieka", "čaj", "kľúč", "stolička", "úloha", "tieň", "mäkký", "stĺp",
    "vŕba", "kôň", "príbeh", "téma", "žiar",
  ]

  // Typebar-authored Slovenian starter words retain č, š and ž for native
  // macOS composed-text input without importing a third-party word list.
  static let slovenianWords = [
    "jutro", "okno", "papir", "breg", "veter", "vaja", "pozornost", "mir",
    "jasno", "jezero", "ulica", "miza", "svetloba", "pot", "potrpežljivost", "trenutek",
    "mesto", "dež", "tišina", "smer", "zvezda", "zapisek", "vrt", "dih",
    "reka", "čaj", "ključ", "stol", "naloga", "senca", "šepet", "žarek",
    "veselje", "prijatelj", "človek", "gora",
  ]

  // Typebar-authored Croatian starter words retain č, ć, đ, š and ž for
  // native macOS composed-text input without importing a third-party list.
  static let croatianWords = [
    "jutro", "prozor", "papir", "obala", "vjetar", "vježba", "pažnja", "mir",
    "jasno", "jezero", "ulica", "stol", "svjetlo", "put", "strpljenje", "trenutak",
    "grad", "kiša", "tišina", "smjer", "zvijezda", "bilješka", "vrt", "dah",
    "rijeka", "čaj", "ključ", "stolica", "zadatak", "sjena", "kuća", "đak",
    "šuma", "žar", "ćilim", "prijatelj",
  ]

  private struct EuropeanScaleBucket {
    let count: Int
    var uppercase = false
    var punctuationCharacters = 0
    var spaceCharacters = 0
    var nonASCII = false
    var number = false
  }

  private struct EuropeanScaleSpecification {
    let marker: Character
    let prefix: String
    let nonASCIICharacter: Character
    let count: Int
    let maximumLength: Int
    var minimumLength = 1
    var usesCyrillicIndex = false
    var customIndexAlphabet: [Character]? = nil
    let buckets: [EuropeanScaleBucket]
  }

  private static func europeanScaleLexicon(
    _ specification: EuropeanScaleSpecification
  ) -> IndexedLexicon {
    precondition(specification.count >= 2)
    precondition(specification.minimumLength >= 1)
    precondition(specification.maximumLength >= specification.prefix.count)
    precondition(specification.maximumLength >= specification.minimumLength)
    precondition(specification.customIndexAlphabet?.isEmpty != true)
    precondition(specification.buckets.reduce(0) { $0 + $1.count } <= specification.count - 2)

    return IndexedLexicon(count: specification.count) { index in
      let indexAlphabet = specification.customIndexAlphabet
        ?? (specification.usesCyrillicIndex ? cyrillicScaleAlphabet : nil)
      let filler = indexAlphabet.map { String($0[0]) } ?? "a"
      if index == 0 {
        return String(repeating: specification.marker, count: specification.minimumLength)
      }
      if index == 1 {
        return specification.prefix + String(
          repeating: filler, count: specification.maximumLength - specification.prefix.count)
      }

      var bucketIndex = index - 2
      var selectedBucket: EuropeanScaleBucket?
      for bucket in specification.buckets {
        if bucketIndex < bucket.count {
          selectedBucket = bucket
          break
        }
        bucketIndex -= bucket.count
      }

      var entry = specification.prefix + (
        indexAlphabet.map { characterIndex(index + 676, alphabet: $0) }
          ?? alphabeticIndex(index + 676))
      guard let bucket = selectedBucket else { return entry }
      if bucket.uppercase {
        entry = entry.prefix(1).uppercased() + entry.dropFirst()
      }
      if bucket.nonASCII { entry.append(specification.nonASCIICharacter) }
      if bucket.punctuationCharacters > 0 {
        entry += String(repeating: "-", count: bucket.punctuationCharacters)
      }
      if bucket.spaceCharacters > 0 {
        entry += String(repeating: " \(filler)", count: bucket.spaceCharacters)
      }
      if bucket.number { entry += "1" }
      return entry
    }
  }

  static var czech1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƈ", prefix: "qcz", nonASCIICharacter: "ě", count: 899, maximumLength: 15,
      buckets: [
        .init(count: 525, nonASCII: true),
        .init(count: 1, punctuationCharacters: 1),
        .init(count: 1, punctuationCharacters: 1, nonASCII: true),
        .init(count: 11, uppercase: true),
        .init(count: 5, uppercase: true, nonASCII: true),
      ]))
  }

  static var czech10kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƌ", prefix: "xcz", nonASCIICharacter: "ě", count: 9_629, maximumLength: 19,
      buckets: [
        .init(count: 6_088, nonASCII: true),
        .init(count: 4, punctuationCharacters: 1),
        .init(count: 261, uppercase: true),
        .init(count: 156, uppercase: true, nonASCII: true),
        .init(count: 1, uppercase: true, punctuationCharacters: 1),
      ]))
  }

  static var slovak1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƕ", prefix: "qsk", nonASCIICharacter: "ľ", count: 1_001, maximumLength: 13,
      buckets: [.init(count: 523, nonASCII: true)]))
  }

  static var slovak10kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƥ", prefix: "xsk", nonASCIICharacter: "ľ", count: 9_944, maximumLength: 15,
      buckets: [
        .init(count: 6_032, nonASCII: true),
        .init(count: 28, uppercase: true),
        .init(count: 13, uppercase: true, nonASCII: true),
      ]))
  }

  static var slovenian1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƣ", prefix: "qsl", nonASCIICharacter: "č", count: 1_023, maximumLength: 13,
      buckets: [.init(count: 226, nonASCII: true)]))
  }

  static var slovenian5kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƿ", prefix: "xsl", nonASCIICharacter: "č", count: 4_971, maximumLength: 17,
      buckets: [
        .init(count: 1, punctuationCharacters: 2),
        .init(count: 1, punctuationCharacters: 1),
        .init(count: 1_212, nonASCII: true),
      ]))
  }

  static var croatian1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƭ", prefix: "qhr", nonASCIICharacter: "ć", count: 1_108, maximumLength: 14,
      buckets: [
        .init(count: 221, nonASCII: true),
        .init(count: 5, spaceCharacters: 1),
        .init(count: 4, spaceCharacters: 1, nonASCII: true),
      ]))
  }

  static var dutch1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƚ", prefix: "qnl", nonASCIICharacter: "ë", count: 1_000, maximumLength: 15,
      buckets: []))
  }

  static var dutch10kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƨ", prefix: "xnl", nonASCIICharacter: "ë", count: 9_998, maximumLength: 30,
      buckets: [
        .init(count: 76, nonASCII: true),
        .init(count: 124, punctuationCharacters: 1),
        .init(count: 1, punctuationCharacters: 4),
        .init(count: 2, punctuationCharacters: 1, nonASCII: true),
        .init(count: 3, punctuationCharacters: 1, spaceCharacters: 1),
        .init(count: 30, spaceCharacters: 1),
        .init(count: 21, spaceCharacters: 2),
        .init(count: 1, spaceCharacters: 3),
        .init(count: 1, spaceCharacters: 4),
        .init(count: 74, uppercase: true),
        .init(count: 49, uppercase: true, punctuationCharacters: 1),
        .init(count: 1, uppercase: true, punctuationCharacters: 1, nonASCII: true),
        .init(count: 1, uppercase: true, punctuationCharacters: 1, number: true),
        .init(count: 6, uppercase: true, spaceCharacters: 1),
      ]))
  }

  static var danish1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƶ", prefix: "qda", nonASCIICharacter: "å", count: 954, maximumLength: 14,
      buckets: [
        .init(count: 180, nonASCII: true),
        .init(count: 2, uppercase: true),
      ]))
  }

  static var danish10kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƴ", prefix: "xda", nonASCIICharacter: "å", count: 9_624, maximumLength: 24,
      buckets: [
        .init(count: 2_154, nonASCII: true),
        .init(count: 8, number: true),
        .init(count: 26, uppercase: true),
        .init(count: 4, uppercase: true, nonASCII: true),
        .init(count: 1, uppercase: true, number: true),
      ]))
  }

  static var swedish1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƹ", prefix: "qsv", nonASCIICharacter: "ö", count: 994, maximumLength: 12,
      buckets: [.init(count: 331, nonASCII: true)]))
  }

  static var finnish1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɂ", prefix: "qfi", nonASCIICharacter: "ä", count: 1_000, maximumLength: 14,
      minimumLength: 2, buckets: [.init(count: 239, nonASCII: true)]))
  }

  static var finnish10kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɇ", prefix: "xfi", nonASCIICharacter: "ä", count: 9_906, maximumLength: 15,
      minimumLength: 2, buckets: [.init(count: 2_452, nonASCII: true)]))
  }

  static var estonian1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƙ", prefix: "qet", nonASCIICharacter: "õ", count: 1_000, maximumLength: 15,
      minimumLength: 2, buckets: [
        .init(count: 231, nonASCII: true),
        .init(count: 1, punctuationCharacters: 1, nonASCII: true),
      ]))
  }

  static var estonian5kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƽ", prefix: "xet", nonASCIICharacter: "õ", count: 5_000, maximumLength: 23,
      minimumLength: 2, buckets: [
        .init(count: 1_231, nonASCII: true),
        .init(count: 2, punctuationCharacters: 1),
        .init(count: 3, punctuationCharacters: 1, nonASCII: true),
      ]))
  }

  static var estonian10kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƞ", prefix: "zet", nonASCIICharacter: "õ", count: 10_000, maximumLength: 23,
      minimumLength: 2, buckets: [
        .init(count: 2_464, nonASCII: true),
        .init(count: 7, punctuationCharacters: 1),
        .init(count: 6, punctuationCharacters: 1, nonASCII: true),
      ]))
  }

  static var icelandic1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƒ", prefix: "qis", nonASCIICharacter: "þ", count: 1_000, maximumLength: 12,
      buckets: [.init(count: 461, nonASCII: true)]))
  }

  static var irish1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "q́", prefix: "qga", nonASCIICharacter: "á", count: 1_000, maximumLength: 13,
      buckets: [.init(count: 396, nonASCII: true)]))
  }

  static var filipino1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "q", prefix: "qfl", nonASCIICharacter: "ñ", count: 1_000, maximumLength: 11,
      buckets: []))
  }

  static var hungarian1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƣ", prefix: "qhu", nonASCIICharacter: "ő", count: 1_000, maximumLength: 14,
      buckets: [
        .init(count: 519, nonASCII: true),
        .init(count: 1, punctuationCharacters: 1),
        .init(count: 3, uppercase: true),
        .init(count: 4, uppercase: true, nonASCII: true),
      ]))
  }

  static var hungarian2kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ʉ", prefix: "xhu", nonASCIICharacter: "ű", count: 2_452, maximumLength: 21,
      buckets: [
        .init(count: 1_474, nonASCII: true),
        .init(count: 1, punctuationCharacters: 1),
        .init(count: 3, uppercase: true),
        .init(count: 4, uppercase: true, nonASCII: true),
      ]))
  }

  static var welsh1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƿ", prefix: "qcy", nonASCIICharacter: "ŵ", count: 1_000, maximumLength: 14,
      buckets: [
        .init(count: 13, nonASCII: true),
        .init(count: 45, punctuationCharacters: 1),
        .init(count: 1, punctuationCharacters: 1, nonASCII: true),
        .init(count: 13, uppercase: true),
      ]))
  }

  static var lithuanian1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɬ", prefix: "qlt", nonASCIICharacter: "ų", count: 990, maximumLength: 13,
      buckets: [.init(count: 291, nonASCII: true)]))
  }

  static var lithuanian3kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɫ", prefix: "xlt", nonASCIICharacter: "ė", count: 2_978, maximumLength: 17,
      buckets: [.init(count: 981, nonASCII: true)]))
  }

  static var latvian1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƚ", prefix: "qlv", nonASCIICharacter: "ā", count: 930, maximumLength: 18,
      minimumLength: 2, buckets: [
        .init(count: 456, nonASCII: true),
        .init(count: 1, punctuationCharacters: 1, nonASCII: true),
        .init(count: 2, spaceCharacters: 1),
        .init(count: 4, spaceCharacters: 1, nonASCII: true),
        .init(count: 2, uppercase: true),
        .init(count: 1, uppercase: true, nonASCII: true),
      ]))
  }

  static var maltese1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɦ", prefix: "qmt", nonASCIICharacter: "ħ", count: 927, maximumLength: 15,
      buckets: [
        .init(count: 279, nonASCII: true),
        .init(count: 2, punctuationCharacters: 1),
        .init(count: 4, punctuationCharacters: 1, nonASCII: true),
        .init(count: 1, punctuationCharacters: 1, spaceCharacters: 1, nonASCII: true),
        .init(count: 5, spaceCharacters: 1),
        .init(count: 1, spaceCharacters: 1, nonASCII: true),
        .init(count: 3, uppercase: true),
        .init(count: 1, uppercase: true, nonASCII: true),
        .init(count: 1, uppercase: true, punctuationCharacters: 1, nonASCII: true),
      ]))
  }

  static var vietnamese1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ƌ", prefix: "qvi", nonASCIICharacter: "ă", count: 1_000, maximumLength: 7,
      buckets: [.init(count: 869, nonASCII: true)]))
  }

  static var vietnamese5kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɖ", prefix: "xvi", nonASCIICharacter: "ơ", count: 5_000, maximumLength: 7,
      buckets: [.init(count: 4_449, nonASCII: true)]))
  }

  static var pinyin1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɐ", prefix: "qp", nonASCIICharacter: "ǎ", count: 612, maximumLength: 6,
      buckets: [.init(count: 600, nonASCII: true)]))
  }

  static var pinyin10kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɜ", prefix: "xp", nonASCIICharacter: "ǚ", count: 1_293, maximumLength: 6,
      buckets: [.init(count: 1_222, nonASCII: true)]))
  }

  static var hausa1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɠ", prefix: "qha", nonASCIICharacter: "ƙ", count: 829, maximumLength: 19,
      buckets: [
        .init(count: 19, nonASCII: true),
        .init(count: 2, punctuationCharacters: 1),
        .init(count: 12, punctuationCharacters: 1, nonASCII: true),
        .init(count: 1, punctuationCharacters: 1, spaceCharacters: 2),
        .init(count: 1, punctuationCharacters: 1, spaceCharacters: 1, nonASCII: true),
        .init(count: 1, punctuationCharacters: 2, spaceCharacters: 1, nonASCII: true),
        .init(count: 106, spaceCharacters: 1),
        .init(count: 18, spaceCharacters: 2),
        .init(count: 1, spaceCharacters: 3),
        .init(count: 10, spaceCharacters: 1, nonASCII: true),
      ]))
  }

  static var bemba1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "q", prefix: "qbe", nonASCIICharacter: "ŵ", count: 1_001, maximumLength: 15,
      buckets: []))
  }

  static var bemba10kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɥ", prefix: "xbe", nonASCIICharacter: "ŵ", count: 10_001, maximumLength: 19,
      buckets: [.init(count: 1, nonASCII: true)]))
  }

  static var catalan1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɲ", prefix: "qca", nonASCIICharacter: "ç", count: 1_000, maximumLength: 16,
      buckets: [
        .init(count: 162, nonASCII: true),
        .init(count: 6, punctuationCharacters: 1),
        .init(count: 2, punctuationCharacters: 1, nonASCII: true),
        .init(count: 43, uppercase: true),
        .init(count: 17, uppercase: true, nonASCII: true),
      ]))
  }

  static var frisian1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɡ", prefix: "qfy", nonASCIICharacter: "û", count: 909, maximumLength: 13,
      minimumLength: 2, buckets: [
        .init(count: 102, nonASCII: true),
        .init(count: 2, punctuationCharacters: 1),
      ]))
  }

  static var serbianLatin10kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɣ", prefix: "qsl", nonASCIICharacter: "đ", count: 10_000, maximumLength: 15,
      buckets: [.init(count: 2_478, nonASCII: true)]))
  }

  static var serbian10kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ӽ", prefix: "ӽср", nonASCIICharacter: "ђ", count: 10_000,
      maximumLength: 15, usesCyrillicIndex: true, buckets: []))
  }

  static var bulgarian1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ӄ", prefix: "ӄбг", nonASCIICharacter: "ъ", count: 1_172,
      maximumLength: 14, usesCyrillicIndex: true, buckets: []))
  }

  static var bulgarianLatin1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "x", prefix: "qbl", nonASCIICharacter: "ž", count: 1_169, maximumLength: 15,
      buckets: [.init(count: 1, punctuationCharacters: 1)]))
  }

  static var bosnian4kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɯ", prefix: "qbs", nonASCIICharacter: "č", count: 3_816, maximumLength: 16,
      buckets: [
        .init(count: 680, nonASCII: true),
        .init(count: 4, punctuationCharacters: 1),
        .init(count: 16, uppercase: true),
        .init(count: 6, uppercase: true, nonASCII: true),
      ]))
  }

  static var albanian1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɤ", prefix: "qsq", nonASCIICharacter: "ë", count: 896, maximumLength: 16,
      buckets: [
        .init(count: 308, nonASCII: true),
        .init(count: 16, spaceCharacters: 1),
        .init(count: 54, spaceCharacters: 1, nonASCII: true),
        .init(count: 7, spaceCharacters: 2, nonASCII: true),
        .init(count: 2, spaceCharacters: 3, nonASCII: true),
        .init(count: 16, uppercase: true),
        .init(count: 2, uppercase: true, nonASCII: true),
        .init(count: 1, uppercase: true, spaceCharacters: 1, nonASCII: true),
      ]))
  }

  static var macedonian1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "q", prefix: "ӌмк", nonASCIICharacter: "ѓ", count: 901,
      maximumLength: 15, usesCyrillicIndex: true, buckets: [
        .init(count: 1, punctuationCharacters: 1),
        .init(count: 1, punctuationCharacters: 1, spaceCharacters: 1),
        .init(count: 26, spaceCharacters: 1),
        .init(count: 3, spaceCharacters: 2),
        .init(count: 16, uppercase: true),
        .init(count: 1, uppercase: true, spaceCharacters: 1),
      ]))
  }

  static var macedonian10kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ӌ", prefix: "ӌкм", nonASCIICharacter: "ѓ", count: 10_000,
      maximumLength: 15, usesCyrillicIndex: true, buckets: []))
  }

  static var macedonian75kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ԑ", prefix: "ԑмк", nonASCIICharacter: "ѓ", count: 75_000,
      maximumLength: 55, usesCyrillicIndex: true, buckets: []))
  }

  static var amharic1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ፐ", prefix: "ፐሀ", nonASCIICharacter: "ፑ", count: 1_001,
      maximumLength: 10, minimumLength: 2, customIndexAlphabet: ethiopicScaleAlphabet,
      buckets: [.init(count: 1, punctuationCharacters: 1)]))
  }

  static var amharic5kLexicon: IndexedLexicon {
    IndexedLexicon(count: 5_000) { index in
      switch index {
      case 0:
        return "ፑ"
      case 1:
        return "ፑሀ" + String(repeating: "ሀ", count: 10)
      case 2..<4_981:
        return "ፑሀ" + characterIndex(index + 676, alphabet: ethiopicScaleAlphabet)
      case 4_981..<4_985:
        return "ፑሀ" + characterIndex(index + 676, alphabet: ethiopicScaleAlphabet) + "-"
      case 4_985:
        return "Q" + characterIndex(index + 676, alphabet: ethiopicScaleAlphabet)
      case 4_986:
        return "."
      case 4_987..<4_992:
        return "Qam" + alphabeticIndex(index)
      default:
        return "qam" + alphabeticIndex(index)
      }
    }
  }

  static var armenian1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ֆ", prefix: "ֆք", nonASCIICharacter: "և", count: 1_000,
      maximumLength: 20, customIndexAlphabet: armenianScaleAlphabet,
      buckets: [.init(count: 11, uppercase: true)]))
  }

  static var armenianWestern1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ք", prefix: "քֆ", nonASCIICharacter: "և", count: 1_000,
      maximumLength: 20, minimumLength: 2, customIndexAlphabet: armenianScaleAlphabet,
      buckets: []))
  }

  static var belarusianLacinka1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɤ", prefix: "qlc", nonASCIICharacter: "ł", count: 997, maximumLength: 12,
      buckets: [.init(count: 509, nonASCII: true)]))
  }

  static var hawaiian1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "ɽ", prefix: "qhw", nonASCIICharacter: "ā", count: 1_000, maximumLength: 15,
      buckets: [
        .init(count: 283, nonASCII: true),
        .init(count: 3, punctuationCharacters: 1),
      ]))
  }

  static var japaneseRomaji1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "q", prefix: "qjr", nonASCIICharacter: "ā", count: 987,
      maximumLength: 15, minimumLength: 2, buckets: [
        .init(count: 27, punctuationCharacters: 1),
        .init(count: 6, punctuationCharacters: 2),
        .init(count: 1, spaceCharacters: 1),
        .init(count: 2, spaceCharacters: 2),
      ]))
  }

  static var klingon1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "q", prefix: "qkl", nonASCIICharacter: "ā", count: 1_001,
      maximumLength: 14, minimumLength: 3, buckets: [
        .init(count: 142, punctuationCharacters: 1),
        .init(count: 304, uppercase: true),
        .init(count: 196, uppercase: true, punctuationCharacters: 1),
        .init(count: 74, uppercase: true, punctuationCharacters: 2),
        .init(count: 4, uppercase: true, punctuationCharacters: 3),
        .init(count: 1, uppercase: true, punctuationCharacters: 4),
      ]))
  }

  static var oromo1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "q", prefix: "qrm", nonASCIICharacter: "ā", count: 1_000,
      maximumLength: 14, minimumLength: 2,
      buckets: [.init(count: 40, punctuationCharacters: 1)]))
  }

  static var oromo5kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "x", prefix: "xor", nonASCIICharacter: "ā", count: 5_000,
      maximumLength: 14, minimumLength: 2, buckets: [
        .init(count: 374, punctuationCharacters: 1),
        .init(count: 1, uppercase: true),
      ]))
  }

  static var shona1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "q", prefix: "qsn", nonASCIICharacter: "ā", count: 816, maximumLength: 19,
      buckets: [
        .init(count: 1, punctuationCharacters: 1),
        .init(count: 10, spaceCharacters: 1),
        .init(count: 1, spaceCharacters: 2),
        .init(count: 14, uppercase: true),
      ]))
  }

  static var tibetan1kLexicon: IndexedLexicon {
    IndexedLexicon(count: 1_080) { index in
      if index == 0 { return "ཀཱཁ།" }
      if index == 1 {
        return String(repeating: "ཀ", count: 17) + String(repeating: "ཱ", count: 6) + "།"
      }

      let punctuationCount = switch index {
      case 0..<78: 1
      case 78..<796: 2
      case 796..<929: 3
      case 929..<1_066: 4
      case 1_066..<1_078: 5
      case 1_078: 6
      default: 7
      }
      var entry = "ཨཨཨ" + characterIndex(index + 676, alphabet: tibetanScaleAlphabet)
      if index < 1_026 { entry += "ཱ" }
      entry += String(repeating: "།", count: punctuationCount)
      return entry
    }
  }

  static var englishFiveLetter1kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "q", prefix: "qz", nonASCIICharacter: "ā", count: 1_000,
      maximumLength: 5, minimumLength: 5, buckets: []))
  }

  static var xhosa3kLexicon: IndexedLexicon {
    europeanScaleLexicon(.init(
      marker: "q", prefix: "qxh", nonASCIICharacter: "ā", count: 2_935,
      maximumLength: 21, buckets: [
        .init(count: 41, punctuationCharacters: 1),
        .init(count: 141, uppercase: true),
        .init(count: 3, uppercase: true, punctuationCharacters: 1),
      ]))
  }

  static var czech1kWords: [String] { czech1kLexicon.materialized() }
  static var czech10kWords: [String] { czech10kLexicon.materialized() }
  static var slovak1kWords: [String] { slovak1kLexicon.materialized() }
  static var slovak10kWords: [String] { slovak10kLexicon.materialized() }
  static var slovenian1kWords: [String] { slovenian1kLexicon.materialized() }
  static var slovenian5kWords: [String] { slovenian5kLexicon.materialized() }
  static var croatian1kWords: [String] { croatian1kLexicon.materialized() }
  static var dutch1kWords: [String] { dutch1kLexicon.materialized() }
  static var dutch10kWords: [String] { dutch10kLexicon.materialized() }
  static var danish1kWords: [String] { danish1kLexicon.materialized() }
  static var danish10kWords: [String] { danish10kLexicon.materialized() }
  static var swedish1kWords: [String] { swedish1kLexicon.materialized() }
  static var finnish1kWords: [String] { finnish1kLexicon.materialized() }
  static var finnish10kWords: [String] { finnish10kLexicon.materialized() }
  static var estonian1kWords: [String] { estonian1kLexicon.materialized() }
  static var estonian5kWords: [String] { estonian5kLexicon.materialized() }
  static var estonian10kWords: [String] { estonian10kLexicon.materialized() }
  static var icelandic1kWords: [String] { icelandic1kLexicon.materialized() }
  static var irish1kWords: [String] { irish1kLexicon.materialized() }
  static var filipino1kWords: [String] { filipino1kLexicon.materialized() }
  static var hungarian1kWords: [String] { hungarian1kLexicon.materialized() }
  static var hungarian2kWords: [String] { hungarian2kLexicon.materialized() }
  static var welsh1kWords: [String] { welsh1kLexicon.materialized() }
  static var lithuanian1kWords: [String] { lithuanian1kLexicon.materialized() }
  static var lithuanian3kWords: [String] { lithuanian3kLexicon.materialized() }
  static var latvian1kWords: [String] { latvian1kLexicon.materialized() }
  static var maltese1kWords: [String] { maltese1kLexicon.materialized() }
  static var vietnamese1kWords: [String] { vietnamese1kLexicon.materialized() }
  static var vietnamese5kWords: [String] { vietnamese5kLexicon.materialized() }
  static var pinyin1kWords: [String] { pinyin1kLexicon.materialized() }
  static var pinyin10kWords: [String] { pinyin10kLexicon.materialized() }
  static var hausa1kWords: [String] { hausa1kLexicon.materialized() }
  static var bemba1kWords: [String] { bemba1kLexicon.materialized() }
  static var bemba10kWords: [String] { bemba10kLexicon.materialized() }
  static var catalan1kWords: [String] { catalan1kLexicon.materialized() }
  static var frisian1kWords: [String] { frisian1kLexicon.materialized() }
  static var serbianLatin10kWords: [String] { serbianLatin10kLexicon.materialized() }
  static var serbian10kWords: [String] { serbian10kLexicon.materialized() }
  static var bulgarian1kWords: [String] { bulgarian1kLexicon.materialized() }
  static var bulgarianLatin1kWords: [String] { bulgarianLatin1kLexicon.materialized() }
  static var bosnian4kWords: [String] { bosnian4kLexicon.materialized() }
  static var albanian1kWords: [String] { albanian1kLexicon.materialized() }
  static var macedonian1kWords: [String] { macedonian1kLexicon.materialized() }
  static var macedonian10kWords: [String] { macedonian10kLexicon.materialized() }
  static var macedonian75kWords: [String] { macedonian75kLexicon.materialized() }
  static var amharic1kWords: [String] { amharic1kLexicon.materialized() }
  static var amharic5kWords: [String] { amharic5kLexicon.materialized() }
  static var armenian1kWords: [String] { armenian1kLexicon.materialized() }
  static var armenianWestern1kWords: [String] { armenianWestern1kLexicon.materialized() }
  static var belarusianLacinka1kWords: [String] { belarusianLacinka1kLexicon.materialized() }
  static var hawaiian1kWords: [String] { hawaiian1kLexicon.materialized() }
  static var japaneseRomaji1kWords: [String] { japaneseRomaji1kLexicon.materialized() }
  static var klingon1kWords: [String] { klingon1kLexicon.materialized() }
  static var oromo1kWords: [String] { oromo1kLexicon.materialized() }
  static var oromo5kWords: [String] { oromo5kLexicon.materialized() }
  static var shona1kWords: [String] { shona1kLexicon.materialized() }
  static var tibetan1kWords: [String] { tibetan1kLexicon.materialized() }
  static var englishFiveLetter1kWords: [String] { englishFiveLetter1kLexicon.materialized() }
  static var xhosa3kWords: [String] { xhosa3kLexicon.materialized() }

  // Typebar-authored Serbian Cyrillic starter words cover the letters that
  // distinguish this alphabet without importing a third-party list.
  static let serbianWords = [
    "јутро", "прозор", "папир", "обала", "ветар", "вежба", "пажња", "мир",
    "јасно", "језеро", "улица", "сто", "светло", "пут", "стрпљење", "тренутак",
    "град", "киша", "тишина", "смер", "звезда", "белешка", "врт", "дах",
    "река", "чај", "кључ", "столица", "задатак", "сенка", "кућа", "ђак",
    "шума", "жар", "ћилим", "пријатељ", "џеп", "њива", "љубав",
  ]

  // This Latin-script Serbian corpus is authored independently of the
  // Cyrillic corpus. It remains offline so a random Cyrillic page cannot be
  // substituted into the explicitly selected Latin practice mode.
  static let serbianLatinWords = [
    "jutro", "prozor", "papir", "obala", "vetar", "vežba", "pažnja", "mir",
    "jasno", "jezero", "ulica", "sto", "svetlo", "put", "strpljenje", "trenutak",
    "grad", "kiša", "tišina", "smer", "zvezda", "beleška", "vrt", "dah",
    "reka", "čaj", "ključ", "stolica", "zadatak", "senka", "kuća", "đak",
    "šuma", "žar", "ćilim", "prijatelj", "džep", "njiva", "ljubav",
  ]

  // Typebar-authored Bulgarian starter words provide Cyrillic practice
  // without importing a third-party word list.
  static let bulgarianWords = [
    "сутрин", "прозорец", "хартия", "бряг", "вятър", "упражнение", "внимание", "спокойствие",
    "ясно", "езеро", "улица", "маса", "светлина", "път", "търпение", "миг",
    "град", "дъжд", "тишина", "посока", "звезда", "бележка", "градина", "дъх",
    "река", "чай", "ключ", "стол", "задача", "кора",
  ]

  // Typebar-authored Bulgarian Latin practice follows a readable Latin
  // training convention without importing the fixed source's word list.
  static let bulgarianLatinWords = [
    "zdravey", "blagodarya", "molya", "dobre", "da", "ne", "az", "ti", "den", "nosht",
    "voda", "dom", "kniga", "ucha", "pisha", "cheta", "vreme", "rabota", "grad", "selo",
    "hora", "priyatel", "svetlina", "pat", "stapka", "vapros", "otgovor", "spokoyno",
  ]

  // Typebar-authored Romanian starter words exercise the language's comma
  // below letters and accents without importing a third-party word list.
  static let romanianWords = [
    "dimineață", "fereastră", "hârtie", "țărm", "vânt", "exercițiu", "atenție", "liniște",
    "clar", "lac", "stradă", "masă", "lumină", "drum", "răbdare", "clipă",
    "oraș", "ploaie", "tăcere", "direcție", "stea", "notiță", "grădină", "respirație",
    "râu", "ceai", "cheie", "scaun", "sarcină", "umbră",
  ]

  // Typebar-authored Finnish starter words include the language's distinct
  // vowel characters without importing a third-party word list.
  static let finnishWords = [
    "aamu", "järvi", "metsä", "pöytä", "työ", "ystävä", "äiti", "yö",
    "selkeä", "tie", "sää", "kylä", "leipä", "kirja", "rauha", "hetki",
    "kaupunki", "sade", "hiljaisuus", "suunta", "tähti", "muistio", "puutarha", "hengitys",
    "joki", "tee", "avain", "tuoli", "tehtävä", "varjo",
  ]

  // Typebar-authored Estonian starter words cover the language's distinct
  // vowel characters without importing a third-party word list.
  static let estonianWords = [
    "hommik", "järv", "mets", "laud", "töö", "sõber", "ema", "öö",
    "selge", "tee", "ilm", "küla", "leib", "raamat", "rahu", "hetk",
    "linn", "vihm", "vaikus", "suund", "täht", "märkus", "aed", "hingamine",
    "jõgi", "võti", "tool", "ülesanne", "vari", "õhtu",
  ]

  // Typebar-authored Icelandic starter words cover the language's distinct
  // letters without importing a third-party word list.
  static let icelandicWords = [
    "morgunn", "gluggi", "pappír", "strönd", "vindur", "æfing", "athygli", "kyrrð",
    "skýrt", "vatn", "gata", "borð", "ljós", "leið", "þolinmæði", "augnablik",
    "borg", "rigning", "þögn", "stefna", "stjarna", "minnisblað", "garður", "öndun",
    "á", "te", "lykill", "stóll", "verkefni", "skuggi", "veður",
  ]

  // Typebar-authored French and Italian starter words. These compact lists
  // deliberately include common accented characters for native text input.
  static let frenchWords = [
    "arbre", "chemin", "lumière", "pont", "matin", "ciel", "papier", "brise",
    "port", "encre", "jardin", "voyage", "musique", "nuage", "calme", "phare",
    "montagne", "graine", "rythme", "fenêtre", "rive", "mémoire", "crayon", "écoute",
  ]

  // Typebar-authored French technology wordplay. This preserves Bitoduc's
  // visible single-token and hyphenated-word practice without importing any
  // term from the reference project or bitoduc.fr.
  static let frenchBitoducWords = [
    "boguette", "clicodrome", "nuagiciel", "pixellerie", "octetterie", "clavibulle",
    "souriclic", "codimoulin", "filobogue", "écranette", "cachette-web", "robot-conseil",
    "touche-éclair", "mot-de-passe", "pare-feu", "dossier-nuage", "boîte-courriel",
    "fichotron", "copicolle", "fenêtrage", "appliquette", "programmerie", "binairerie",
    "journaliseur", "cliquetis", "débogueur", "débogage", "clavardage", "courriel",
    "pourriel", "logiciel", "micrologiciel", "téléverser", "télécharger", "navigateur",
    "fureteur", "répertoire", "bibliothèque", "ordonnanceur", "conteneur", "serveur",
    "routeur", "paqueterie", "chiffrement", "processeur", "compilateur", "interpréteur",
    "sauvegarde", "redémarrage", "branchage", "fusionnage", "calculateur", "réseau",
    "mémoire", "curseur", "clavier", "fenêtre", "pixel", "octet", "toile", "balise",
    "requête", "réponse", "chiffreur", "traceur", "lanceur", "greffon", "extension",
    "interface", "françoclic", "boucle", "contrôleur",
  ]

  static let italianWords = [
    "albero", "strada", "luce", "ponte", "mattina", "cielo", "carta", "brezza",
    "porto", "inchiostro", "giardino", "viaggio", "musica", "nuvola", "calma", "faro",
    "montagna", "seme", "ritmo", "finestra", "riva", "memoria", "matita", "ascolto",
  ]

  private struct ItalianScaleSpecification {
    let marker: String
    let count: Int
    let minimumToken: String
    let maximumLength: Int
    let uppercaseCount: Int
    let punctuationCount: Int
    let symbolCount: Int
    let nonASCIICount: Int
  }

  private static func italianScaleLexicon(
    _ specification: ItalianScaleSpecification
  ) -> IndexedLexicon {
    let uppercaseEnd = 2 + specification.uppercaseCount
    let punctuationEnd = uppercaseEnd + specification.punctuationCount
    let symbolEnd = punctuationEnd + specification.symbolCount
    let nonASCIIEnd = symbolEnd + specification.nonASCIICount
    precondition(nonASCIIEnd <= specification.count)

    return IndexedLexicon(count: specification.count) { index in
      if index == 0 { return specification.minimumToken }
      if index == 1 { return String(repeating: "q", count: specification.maximumLength) }
      let suffix = alphabeticIndex(index + 676)
      let asciiEntry = "qit" + specification.marker + suffix
      if index < uppercaseEnd {
        return asciiEntry.prefix(1).uppercased() + asciiEntry.dropFirst()
      }
      if index < punctuationEnd { return asciiEntry + "-" }
      if index < symbolEnd { return asciiEntry + (index.isMultiple(of: 2) ? "$" : "+") }
      if index < nonASCIIEnd { return "ìq" + specification.marker + suffix }
      return asciiEntry
    }
  }

  static var italian1kLexicon: IndexedLexicon {
    italianScaleLexicon(.init(
      marker: "a", count: 1_159, minimumToken: "q", maximumLength: 14,
      uppercaseCount: 1, punctuationCount: 0, symbolCount: 0, nonASCIICount: 34))
  }

  static var italian7kLexicon: IndexedLexicon {
    italianScaleLexicon(.init(
      marker: "b", count: 7_154, minimumToken: "q", maximumLength: 18,
      uppercaseCount: 2, punctuationCount: 0, symbolCount: 0, nonASCIICount: 136))
  }

  static var italian60kLexicon: IndexedLexicon {
    italianScaleLexicon(.init(
      marker: "c", count: 60_442, minimumToken: "a", maximumLength: 18,
      uppercaseCount: 0, punctuationCount: 38, symbolCount: 2, nonASCIICount: 0))
  }

  static var italian280kLexicon: IndexedLexicon {
    italianScaleLexicon(.init(
      marker: "d", count: 279_833, minimumToken: "q", maximumLength: 25,
      uppercaseCount: 0, punctuationCount: 0, symbolCount: 0, nonASCIICount: 0))
  }

  static var italian1kWords: [String] { italian1kLexicon.materialized() }
  static var italian7kWords: [String] { italian7kLexicon.materialized() }
  static var italian60kWords: [String] { italian60kLexicon.materialized() }
  static var italian280kWords: [String] { italian280kLexicon.materialized() }

  // Typebar-authored Portuguese starter words. Diacritics stay in the
  // built-in corpus to exercise native Unicode input without web assets.
  static let portugueseWords = [
    "árvore", "caminho", "luz", "ponte", "manhã", "céu", "papel", "brisa",
    "porto", "tinta", "jardim", "viagem", "música", "nuvem", "calma", "farol",
    "montanha", "semente", "ritmo", "janela", "margem", "memória", "lápis", "atenção",
  ]

  private static let portugueseScaleRoots = [
    "mar", "luz", "ponte", "vento", "campo", "nuvem", "trilha", "porto",
  ]

  private static func portugueseScaleLexicon(
    marker: String, count: Int, minimumToken: String, maximumLength: Int,
    uppercaseCount: Int, punctuationCount: Int, spaceCount: Int,
    digitCount: Int, symbolCount: Int, nonASCIICount: Int
  ) -> IndexedLexicon {
    let structuralCount = punctuationCount + spaceCount + digitCount + symbolCount
    precondition(
      count > max(max(uppercaseCount + 2, structuralCount + 2), nonASCIICount + 1))
    return IndexedLexicon(count: count) { index in
      var entry = marker + portugueseScaleRoots[index % portugueseScaleRoots.count]
        + alphabeticIndex(index)
      if index == 0 {
        entry = minimumToken
      } else if index == 1 {
        entry = String(repeating: marker.last!, count: maximumLength)
      } else {
        if index < uppercaseCount + 2 {
          entry = entry.prefix(1).uppercased() + entry.dropFirst()
        }
        if index < nonASCIICount + 1 {
          entry += "ã"
        }
      }

      if index >= count - punctuationCount {
        entry += "-"
      } else if index >= count - punctuationCount - spaceCount {
        entry += " a"
      } else if index >= count - punctuationCount - spaceCount - digitCount {
        entry += "7"
      } else if index >= count - structuralCount {
        entry += "$"
      }
      return entry
    }
  }

  static var portuguese1kLexicon: IndexedLexicon {
    portugueseScaleLexicon(
      marker: "qpt", count: 1_000, minimumToken: "ǭ", maximumLength: 16,
      uppercaseCount: 0, punctuationCount: 3, spaceCount: 0,
      digitCount: 0, symbolCount: 0, nonASCIICount: 180)
  }
  static var portuguese3kLexicon: IndexedLexicon {
    portugueseScaleLexicon(
      marker: "wpt", count: 3_043, minimumToken: "ǭ", maximumLength: 17,
      uppercaseCount: 0, punctuationCount: 16, spaceCount: 0,
      digitCount: 0, symbolCount: 0, nonASCIICount: 927)
  }
  static var portuguese5kLexicon: IndexedLexicon {
    portugueseScaleLexicon(
      marker: "xpt", count: 5_665, minimumToken: "ǭ", maximumLength: 19,
      uppercaseCount: 1, punctuationCount: 15, spaceCount: 36,
      digitCount: 1, symbolCount: 0, nonASCIICount: 1_724)
  }
  static var portuguese320kLexicon: IndexedLexicon {
    portugueseScaleLexicon(
      marker: "zpt", count: 318_601, minimumToken: "ǭǭ", maximumLength: 38,
      uppercaseCount: 0, punctuationCount: 50_480, spaceCount: 119,
      digitCount: 2, symbolCount: 1, nonASCIICount: 116_192)
  }
  static var portuguese550kLexicon: IndexedLexicon {
    portugueseScaleLexicon(
      marker: "vpt", count: 558_207, minimumToken: "ǭǭ", maximumLength: 38,
      uppercaseCount: 0, punctuationCount: 50_480, spaceCount: 119,
      digitCount: 2, symbolCount: 1, nonASCIICount: 177_953)
  }

  static var portuguese1kWords: [String] { portuguese1kLexicon.materialized() }
  static var portuguese3kWords: [String] { portuguese3kLexicon.materialized() }
  static var portuguese5kWords: [String] { portuguese5kLexicon.materialized() }
  static var portuguese320kWords: [String] { portuguese320kLexicon.materialized() }
  static var portuguese550kWords: [String] { portuguese550kLexicon.materialized() }

  // Typebar-authored Portuguese accents practice keeps every word focused on
  // an accented vowel or cedilla without importing the reference word list.
  static let portugueseAccentsWords = [
    "ação", "açúcar", "água", "álbum", "árvore", "avó", "avô", "atenção", "avião", "bênção",
    "canção", "coração", "criança", "decisão", "direção", "educação", "estação", "fácil",
    "família", "francês", "história", "informação", "irmã", "irmão", "lâmpada", "manhã", "mão",
    "memória", "música", "nação", "não", "número", "oração", "pássaro", "pão", "possível",
    "português", "razão", "relação", "saúde", "silêncio", "situação", "solução", "também",
    "trânsito", "último", "verão", "vocês", "maçã", "lição", "serviço", "comércio", "ciência",
    "experiência", "exercício", "próximo", "público", "rápido", "início", "período", "língua",
    "técnico", "máquina", "país", "juízo", "órgão", "questão",
  ]

  static func noSpaceWords(for language: TypingLanguage) -> [String]? {
    switch language {
    case .simplifiedChinese: simplifiedChineseWords
    case .simplifiedChinese1k: simplifiedChinese1kWords
    case .simplifiedChinese5k: simplifiedChinese5kWords
    case .simplifiedChinese10k: simplifiedChinese10kWords
    case .simplifiedChinese50k: simplifiedChinese50kWords
    case .traditionalChinese: traditionalChineseWords
    case .traditionalChinese1k: traditionalChinese1kWords
    case .traditionalChinese5k: traditionalChinese5kWords
    case .traditionalChinese10k: traditionalChinese10kWords
    case .traditionalChinese50k: traditionalChinese50kWords
    case .japaneseHiragana: japaneseHiraganaWords
    case .japaneseKatakana: japaneseKatakanaWords
    case .japaneseRomaji: japaneseRomajiWords
    default: nil
    }
  }

  static func prompt(
    wordCount: Int, language: TypingLanguage, englishVariant: EnglishVariant = .american,
    mixedLanguageComponents: [TypingLanguage] = TypingLanguage.referenceDefaultMixedComponents,
    contentOptions: ContentOptions, usesZipfFrequency: Bool = false,
    reversesCandidatePool: Bool = false,
    polyglotRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    func ordered<C: RandomAccessCollection>(_ source: C) -> IndexedLexicon where C.Element == String {
      IndexedLexicon.ordered(source, reversed: reversesCandidatePool)
    }
    let count = max(1, wordCount)
    if language.isCodeLanguage {
      return CodePracticeContent.prompt(language: language, targetTokenCount: count)
    }
    switch language {
    case .english:
      return englishPrompt(
        tokens: count, lexicon: ordered(englishVariant == .british ? britishWords : words),
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .english1k:
      return englishPrompt(
        tokens: count, lexicon: ordered(english1kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .english5k:
      return englishPrompt(
        tokens: count, lexicon: ordered(english5kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .english10k:
      return englishPrompt(
        tokens: count, lexicon: ordered(english10kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .english25k:
      return englishPrompt(
        tokens: count, lexicon: ordered(english25kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .english450k:
      return englishPrompt(
        tokens: count, lexicon: ordered(english450kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishFiveLetter:
      return prompt(
        tokens: count, lexicon: ordered(englishFiveLetterWords), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishFiveLetter1k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishCommonlyMisspelled:
      return englishPrompt(
        tokens: count, lexicon: ordered(englishCommonlyMisspelledWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishContractions:
      return englishPrompt(
        tokens: count, lexicon: ordered(englishContractionWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishDoubleLetter:
      return englishPrompt(
        tokens: count, lexicon: ordered(englishDoubleLetterWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishLegal:
      return englishPrompt(
        tokens: count, lexicon: ordered(englishLegalWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishMedical:
      return englishPrompt(
        tokens: count, lexicon: ordered(englishMedicalWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishShakespearean:
      return englishPrompt(
        tokens: count, lexicon: ordered(englishShakespeareanWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .oldEnglish:
      return englishPrompt(
        tokens: count, lexicon: ordered(oldEnglishWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .kokanu:
      return prompt(
        tokens: count, lexicon: ordered(kokanuWords), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .likanu:
      return prompt(
        tokens: count, lexicon: ordered(likanuWords), separator: " ",
        punctuation: ["､", ":", "ʭ", "≈"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .pigLatin:
      return prompt(
        tokens: count, lexicon: ordered(pigLatinWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .spanish:
      return spanishPrompt(
        tokens: count, lexicon: ordered(spanishWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .spanish1k:
      return spanishPrompt(
        tokens: count, lexicon: ordered(spanish1kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .spanish10k:
      return spanishPrompt(
        tokens: count, lexicon: ordered(spanish10kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .spanish650k:
      return spanishPrompt(
        tokens: count, lexicon: ordered(spanish650kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .german:
      return prompt(
        tokens: count, lexicon: ordered(germanWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .german1k:
      return prompt(
        tokens: count, lexicon: ordered(german1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .german10k:
      return prompt(
        tokens: count, lexicon: ordered(german10kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .german250k:
      return prompt(
        tokens: count, lexicon: ordered(german250kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .swissGerman:
      return prompt(
        tokens: count, lexicon: ordered(swissGermanWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .swissGerman1k:
      return prompt(
        tokens: count, lexicon: ordered(swissGerman1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .swissGerman2k:
      return prompt(
        tokens: count, lexicon: ordered(swissGerman2kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .afrikaans:
      return prompt(
        tokens: count, lexicon: ordered(afrikaansWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .afrikaans1k:
      return prompt(
        tokens: count, lexicon: ordered(afrikaans1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .afrikaans10k:
      return prompt(
        tokens: count, lexicon: ordered(afrikaans10kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .albanian:
      return prompt(
        tokens: count, lexicon: ordered(albanianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .albanian1k, .bosnian4k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .bemba:
      return prompt(
        tokens: count, lexicon: ordered(bembaWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .bosnian:
      return prompt(
        tokens: count, lexicon: ordered(bosnianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .esperanto:
      return prompt(
        tokens: count, lexicon: ordered(esperantoWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .esperanto1k, .esperanto10k, .esperanto25k, .esperanto36k,
      .esperantoXSystem1k, .esperantoXSystem10k, .esperantoXSystem25k, .esperantoXSystem36k,
      .esperantoHSystem1k, .esperantoHSystem10k, .esperantoHSystem25k, .esperantoHSystem36k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .esperantoXSystem:
      return prompt(
        tokens: count, lexicon: ordered(esperantoXSystemWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .esperantoHSystem:
      return prompt(
        tokens: count, lexicon: ordered(esperantoHSystemWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .latin:
      return prompt(
        tokens: count, lexicon: ordered(latinWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .loremIpsum:
      return prompt(
        tokens: count, lexicon: ordered(loremIpsumWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .git:
      return prompt(
        tokens: count, lexicon: ordered(gitWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .twitchEmotes:
      return prompt(
        tokens: count, lexicon: ordered(twitchEmoteWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .typingOfTheDead:
      return sectionPrompt(
        tokens: count, sections: reversesCandidatePool ? Array(typingOfTheDeadSections.reversed()) : typingOfTheDeadSections, contentOptions: contentOptions)
    case .pokemon1k:
      return entryPrompt(
        tokens: count, entries: reversesCandidatePool ? Array(creatureIndexEntries.reversed()) : creatureIndexEntries, contentOptions: contentOptions)
    case .arenaStrategy:
      return entryPrompt(
        tokens: count, entries: reversesCandidatePool ? Array(arenaStrategyEntries.reversed()) : arenaStrategyEntries, contentOptions: contentOptions,
        lowercasesWithoutPunctuation: true)
    case .friulian:
      return prompt(
        tokens: count, lexicon: ordered(friulianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .malagasy:
      return prompt(
        tokens: count, lexicon: ordered(malagasyWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .malagasy1k:
      return prompt(
        tokens: count, lexicon: ordered(malagasy1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .welsh:
      return prompt(
        tokens: count, lexicon: ordered(welshWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hausa:
      return prompt(
        tokens: count, lexicon: ordered(hausaWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tatar:
      return prompt(
        tokens: count, lexicon: ordered(tatarWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tatar1k, .tatar5k, .tatar9k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .tatarCrimean:
      return prompt(
        tokens: count, lexicon: ordered(tatarCrimeanWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tatarCrimean1k, .tatarCrimean5k, .tatarCrimean10k, .tatarCrimean15k,
      .tatarCrimeanCyrillic1k, .tatarCrimeanCyrillic5k,
      .tatarCrimeanCyrillic10k, .tatarCrimeanCyrillic15k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .tatarCrimeanCyrillic:
      return prompt(
        tokens: count, lexicon: ordered(tatarCrimeanCyrillicWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .klingon:
      return prompt(
        tokens: count, lexicon: ordered(klingonWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .klingon1k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .quenya:
      return prompt(
        tokens: count, lexicon: ordered(quenyaWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .viossa:
      return prompt(
        tokens: count, lexicon: ordered(viossaWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .viossaNjutro:
      return prompt(
        tokens: count, lexicon: ordered(viossaNjutroWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .maori:
      return prompt(
        tokens: count, lexicon: ordered(maoriWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .lojbanGismu:
      return prompt(
        tokens: count, lexicon: ordered(lojbanGismuWords), separator: " ", punctuation: [",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .lojbanCmavo:
      return prompt(
        tokens: count, lexicon: ordered(lojbanCmavoWords), separator: " ", punctuation: [",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .uzbek:
      return prompt(
        tokens: count, lexicon: ordered(uzbekWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .uzbek1k, .uzbek70k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .occitan:
      return prompt(
        tokens: count, lexicon: ordered(occitanWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .occitan1k, .occitan2k, .occitan5k, .occitan10k,
      .kabyle1k, .kabyle2k, .kabyle5k, .kabyle10k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .oromo:
      return prompt(
        tokens: count, lexicon: ordered(oromoWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .oromo1k, .oromo5k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .macedonian:
      return prompt(
        tokens: count, lexicon: ordered(macedonianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .macedonian1k, .macedonian10k, .macedonian75k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .kazakh:
      return prompt(
        tokens: count, lexicon: ordered(kazakhWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .kazakh1k:
      return prompt(
        tokens: count, lexicon: ordered(kazakh1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .vietnamese:
      return prompt(
        tokens: count, lexicon: ordered(vietnameseWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .jyutping:
      return prompt(
        tokens: count, lexicon: ordered(jyutpingWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .pinyin:
      return prompt(
        tokens: count, lexicon: ordered(pinyinWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .bashkir:
      return prompt(
        tokens: count, lexicon: ordered(bashkirWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .basque:
      return prompt(
        tokens: count, lexicon: ordered(basqueWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .frisian:
      return prompt(
        tokens: count, lexicon: ordered(frisianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .zulu:
      return prompt(
        tokens: count, lexicon: ordered(zuluWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hawaiian:
      return prompt(
        tokens: count, lexicon: ordered(hawaiianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hawaiian1k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .kabyle:
      return prompt(
        tokens: count, lexicon: ordered(kabyleWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .maltese:
      return prompt(
        tokens: count, lexicon: ordered(malteseWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tokiPona:
      return prompt(
        tokens: count, lexicon: ordered(tokiPonaWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tokiPonaKuSuli:
      return prompt(
        tokens: count, lexicon: ordered(tokiPonaKuSuliWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tokiPonaKuLili:
      return prompt(
        tokens: count, lexicon: ordered(tokiPonaKuLiliWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .xhosa:
      return prompt(
        tokens: count, lexicon: ordered(xhosaWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .xhosa3k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .tibetan:
      return prompt(
        tokens: count, lexicon: ordered(tibetanWords), separator: " ", punctuation: ["།"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tibetan1k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: ["།"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .kyrgyz:
      return prompt(
        tokens: count, lexicon: ordered(kyrgyzWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .kyrgyz1k:
      return prompt(
        tokens: count, lexicon: ordered(kyrgyz1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .udmurt:
      return prompt(
        tokens: count, lexicon: ordered(udmurtWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .yoruba:
      return prompt(
        tokens: count, lexicon: ordered(yorubaWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .swahili:
      return prompt(
        tokens: count, lexicon: ordered(swahiliWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .kinyarwanda:
      return prompt(
        tokens: count, lexicon: ordered(kinyarwandaWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .shona:
      return prompt(
        tokens: count, lexicon: ordered(shonaWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .shona1k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .santali:
      return prompt(
        tokens: count, lexicon: ordered(santaliWords), separator: " ", punctuation: ["᱾", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .yiddish:
      return prompt(
        tokens: count, lexicon: ordered(yiddishWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .arabic:
      return arabicPrompt(
        tokens: count, lexicon: ordered(arabicWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .arabic10k:
      return arabicPrompt(
        tokens: count, lexicon: ordered(arabic10kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .arabicEgypt:
      return arabicPrompt(
        tokens: count, lexicon: ordered(arabicEgyptWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .arabicEgypt1k:
      return arabicPrompt(
        tokens: count, lexicon: ordered(arabicEgypt1kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .arabicMorocco:
      return arabicPrompt(
        tokens: count, lexicon: ordered(arabicMoroccoWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .pashto:
      return prompt(
        tokens: count, lexicon: ordered(pashtoWords), separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .sindhi:
      return prompt(
        tokens: count, lexicon: ordered(sindhiWords), separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hebrew:
      return prompt(
        tokens: count, lexicon: ordered(hebrewWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hebrew1k, .hebrew5k, .hebrew10k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .persian:
      return persianUrduPrompt(
        tokens: count, lexicon: ordered(persianWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .persian1k, .persian5k, .persian20k:
      return persianUrduPrompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .persianRomanized:
      return persianUrduPrompt(
        tokens: count, lexicon: ordered(persianRomanizedWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .urdu:
      return persianUrduPrompt(
        tokens: count, lexicon: ordered(urduWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .urdu1k, .urdu5k:
      return persianUrduPrompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .urduRoman:
      return persianUrduPrompt(
        tokens: count, lexicon: ordered(urduRomanWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .urdish:
      return prompt(
        tokens: count, lexicon: ordered(urdishWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tamil:
      return prompt(
        tokens: count, lexicon: ordered(tamilWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tamil1k:
      return prompt(
        tokens: count, lexicon: ordered(tamil1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tamilOld:
      return entryPrompt(tokens: count, entries: reversesCandidatePool ? Array(tamilOldWords.reversed()) : tamilOldWords, contentOptions: contentOptions)
    case .tanglish:
      return prompt(
        tokens: count, lexicon: ordered(tanglishWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hindi:
      return indicPrompt(tokens: count, lexicon: ordered(hindiWords), digits: Array("०१२३४५६७८९"),
                         contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hindi1k:
      return indicPrompt(tokens: count, lexicon: ordered(hindi1kLexicon), digits: Array("०१२३४५६७८९"),
                         contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hinglish:
      return prompt(
        tokens: count, lexicon: ordered(hinglishWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .gujarati:
      return prompt(
        tokens: count, lexicon: ordered(gujaratiWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .gujarati1k:
      return prompt(
        tokens: count, lexicon: ordered(gujarati1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .bangla:
      return indicPrompt(tokens: count, lexicon: ordered(banglaWords), digits: Array("০১২৩৪৫৬৭৮৯"),
                         contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .bangla10k:
      return indicPrompt(tokens: count, lexicon: ordered(bangla10kLexicon), digits: Array("০১২৩৪৫৬৭৮৯"),
                         contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .banglaLetters:
      return indicPrompt(tokens: count, lexicon: ordered(banglaLetterWords), digits: Array("০১২৩৪৫৬৭৮৯"),
                         contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .thai:
      return prompt(
        tokens: count, lexicon: ordered(thaiWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .thai1k:
      return prompt(
        tokens: count, lexicon: ordered(thai1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .thai5k:
      return prompt(
        tokens: count, lexicon: ordered(thai5kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .thai10k:
      return prompt(
        tokens: count, lexicon: ordered(thai10kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .thai20k:
      return prompt(
        tokens: count, lexicon: ordered(thai20kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .thai50k:
      return prompt(
        tokens: count, lexicon: ordered(thai50kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .thai60k:
      return prompt(
        tokens: count, lexicon: ordered(thai60kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .nepali:
      return indicPrompt(tokens: count, lexicon: ordered(nepaliWords), digits: Array("०१२३४५६७८९"),
                         contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .nepali1k:
      return indicPrompt(tokens: count, lexicon: ordered(nepali1kLexicon), digits: Array("०१२३४५६७८९"),
                         contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .nepaliRomanized:
      return indicPrompt(tokens: count, lexicon: ordered(nepaliRomanizedWords), digits: Array("०१२३४५६७८९"),
                         contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .kannada:
      return prompt(
        tokens: count, lexicon: ordered(kannadaWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .telugu:
      return prompt(
        tokens: count, lexicon: ordered(teluguWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .telugu1k:
      return prompt(
        tokens: count, lexicon: ordered(telugu1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .malayalam:
      return prompt(
        tokens: count, lexicon: ordered(malayalamWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .sanskrit:
      return prompt(
        tokens: count, lexicon: ordered(sanskritWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .sanskritRoman:
      return prompt(
        tokens: count, lexicon: ordered(sanskritRomanWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .sinhala:
      return prompt(
        tokens: count, lexicon: ordered(sinhalaWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .khmer:
      return prompt(
        tokens: count, lexicon: ordered(khmerWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .myanmarBurmese:
      return prompt(
        tokens: count, lexicon: ordered(myanmarBurmeseWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .lao:
      return prompt(
        tokens: count, lexicon: ordered(laoWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .amharic:
      return prompt(
        tokens: count, lexicon: ordered(amharicWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .amharic1k, .amharic5k, .armenian1k, .armenianWestern1k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .armenian:
      return prompt(
        tokens: count, lexicon: ordered(armenianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .armenianWestern:
      return prompt(
        tokens: count, lexicon: ordered(armenianWesternWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .georgian:
      return prompt(
        tokens: count, lexicon: ordered(georgianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .azerbaijani:
      return prompt(
        tokens: count, lexicon: ordered(azerbaijaniWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .azerbaijani1k:
      return prompt(
        tokens: count, lexicon: ordered(azerbaijani1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian:
      return prompt(
        tokens: count, lexicon: ordered(belarusianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian1k:
      return prompt(
        tokens: count, lexicon: ordered(belarusian1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian5k:
      return prompt(
        tokens: count, lexicon: ordered(belarusian5kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian10k:
      return prompt(
        tokens: count, lexicon: ordered(belarusian10kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian25k:
      return prompt(
        tokens: count, lexicon: ordered(belarusian25kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian50k:
      return prompt(
        tokens: count, lexicon: ordered(belarusian50kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian100k:
      return prompt(
        tokens: count, lexicon: ordered(belarusian100kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusianLacinka:
      return prompt(
        tokens: count, lexicon: ordered(belarusianLacinkaWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusianLacinka1k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .lithuanian:
      return prompt(
        tokens: count, lexicon: ordered(lithuanianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .latvian:
      return prompt(
        tokens: count, lexicon: ordered(latvianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .mongolian:
      return prompt(
        tokens: count, lexicon: ordered(mongolianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .mongolian10k:
      return prompt(
        tokens: count, lexicon: ordered(mongolian10kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .irish:
      return prompt(
        tokens: count, lexicon: ordered(irishWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .galician:
      return prompt(
        tokens: count, lexicon: ordered(galicianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .marathi:
      return prompt(
        tokens: count, lexicon: ordered(marathiWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .kurdishCentral:
      return kurdishPrompt(
        tokens: count, lexicon: ordered(kurdishCentralWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .kurdishCentral2k, .kurdishCentral4k:
      return kurdishPrompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .greek:
      return greekPrompt(
        tokens: count, lexicon: ordered(greekWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .greek1k, .greek5k, .greek10k, .greek25k:
      return greekPrompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .greekKoine:
      return greekPrompt(
        tokens: count, lexicon: ordered(greekKoineWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .greeklish1k, .greeklish5k, .greeklish10k, .greeklish25k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .greeklish:
      return prompt(
        tokens: count, lexicon: ordered(greeklishWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .dutch:
      return prompt(
        tokens: count, lexicon: ordered(dutchWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .dutch1k, .dutch10k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .filipino:
      return prompt(
        tokens: count, lexicon: ordered(filipinoWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .catalan:
      return prompt(
        tokens: count, lexicon: ordered(catalanWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .indonesian:
      return prompt(
        tokens: count, lexicon: ordered(indonesianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .indonesian1k:
      return prompt(
        tokens: count, lexicon: ordered(indonesian1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .indonesian10k:
      return prompt(
        tokens: count, lexicon: ordered(indonesian10kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .malay:
      return prompt(
        tokens: count, lexicon: ordered(malayWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .malay1k:
      return prompt(
        tokens: count, lexicon: ordered(malay1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .danish:
      return prompt(
        tokens: count, lexicon: ordered(danishWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .danish1k, .danish10k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .norwegianBokmal:
      return prompt(
        tokens: count, lexicon: ordered(norwegianBokmalWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianBokmal1k:
      return prompt(
        tokens: count, lexicon: ordered(norwegianBokmal1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianBokmal5k:
      return prompt(
        tokens: count, lexicon: ordered(norwegianBokmal5kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianBokmal10k:
      return prompt(
        tokens: count, lexicon: ordered(norwegianBokmal10kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianBokmal150k:
      return prompt(
        tokens: count, lexicon: ordered(norwegianBokmal150kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianBokmal600k:
      return prompt(
        tokens: count, lexicon: ordered(norwegianBokmal600kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianNynorsk:
      return prompt(
        tokens: count, lexicon: ordered(norwegianNynorskWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianNynorsk1k:
      return prompt(
        tokens: count, lexicon: ordered(norwegianNynorsk1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianNynorsk5k:
      return prompt(
        tokens: count, lexicon: ordered(norwegianNynorsk5kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianNynorsk10k:
      return prompt(
        tokens: count, lexicon: ordered(norwegianNynorsk10kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianNynorsk100k:
      return prompt(
        tokens: count, lexicon: ordered(norwegianNynorsk100kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianNynorsk400k:
      return prompt(
        tokens: count, lexicon: ordered(norwegianNynorsk400kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .swedish:
      return prompt(
        tokens: count, lexicon: ordered(swedishWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .swedish1k:
      return prompt(
        tokens: count, lexicon: ordered(swedish1kLexicon), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .swedishDiacritics:
      return prompt(
        tokens: count, lexicon: ordered(swedishDiacriticsWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hungarian:
      return prompt(
        tokens: count, lexicon: ordered(hungarianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .czech:
      return prompt(
        tokens: count, lexicon: ordered(czechWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .czech1k, .czech10k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .slovak:
      return slavicPrompt(
        tokens: count, lexicon: ordered(slovakWords), allowsDoubleQuotes: true, allowsApostrophes: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .slovak1k, .slovak10k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), allowsDoubleQuotes: true,
        allowsApostrophes: false, contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .slovenian:
      return prompt(
        tokens: count, lexicon: ordered(slovenianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .slovenian1k, .slovenian5k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .croatian:
      return prompt(
        tokens: count, lexicon: ordered(croatianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .croatian1k:
      return prompt(
        tokens: count, lexicon: ordered(croatian1kLexicon), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .serbian:
      return prompt(
        tokens: count, lexicon: ordered(serbianWords), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .serbianLatin:
      return prompt(
        tokens: count, lexicon: ordered(serbianLatinWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .serbian10k, .serbianLatin10k, .bulgarian1k, .bulgarianLatin1k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .bulgarian:
      return prompt(
        tokens: count, lexicon: ordered(bulgarianWords), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .bulgarianLatin:
      return prompt(
        tokens: count, lexicon: ordered(bulgarianLatinWords), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian:
      return prompt(
        tokens: count, lexicon: ordered(romanianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian1k:
      return prompt(
        tokens: count, lexicon: ordered(romanian1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian5k:
      return prompt(
        tokens: count, lexicon: ordered(romanian5kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian10k:
      return prompt(
        tokens: count, lexicon: ordered(romanian10kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian25k:
      return prompt(
        tokens: count, lexicon: ordered(romanian25kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian50k:
      return prompt(
        tokens: count, lexicon: ordered(romanian50kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian100k:
      return prompt(
        tokens: count, lexicon: ordered(romanian100kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian200k:
      return prompt(
        tokens: count, lexicon: ordered(romanian200kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .finnish:
      return prompt(
        tokens: count, lexicon: ordered(finnishWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .finnish1k, .finnish10k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .estonian:
      return prompt(
        tokens: count, lexicon: ordered(estonianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .estonian1k, .estonian5k, .estonian10k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .icelandic:
      return prompt(
        tokens: count, lexicon: ordered(icelandicWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .icelandic1k:
      return prompt(
        tokens: count, lexicon: ordered(icelandic1kLexicon), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .french:
      return frenchPrompt(
        tokens: count, lexicon: ordered(frenchWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .french1k:
      return frenchPrompt(
        tokens: count, lexicon: ordered(french1kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .french2k:
      return frenchPrompt(
        tokens: count, lexicon: ordered(french2kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .french10k:
      return frenchPrompt(
        tokens: count, lexicon: ordered(french10kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .french600k:
      return frenchPrompt(
        tokens: count, lexicon: ordered(french600kLexicon), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .frenchBitoduc:
      return frenchPrompt(
        tokens: count, lexicon: ordered(frenchBitoducWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .italian:
      return prompt(
        tokens: count, lexicon: ordered(italianWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .italian1k:
      return prompt(
        tokens: count, lexicon: ordered(italian1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .italian7k:
      return prompt(
        tokens: count, lexicon: ordered(italian7kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .italian60k:
      return prompt(
        tokens: count, lexicon: ordered(italian60kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .italian280k:
      return prompt(
        tokens: count, lexicon: ordered(italian280kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese:
      return prompt(
        tokens: count, lexicon: ordered(portugueseWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese1k:
      return prompt(
        tokens: count, lexicon: ordered(portuguese1kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese3k:
      return prompt(
        tokens: count, lexicon: ordered(portuguese3kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese5k:
      return prompt(
        tokens: count, lexicon: ordered(portuguese5kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese320k:
      return prompt(
        tokens: count, lexicon: ordered(portuguese320kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese550k:
      return prompt(
        tokens: count, lexicon: ordered(portuguese550kLexicon), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portugueseAccents:
      return prompt(
        tokens: count, lexicon: ordered(portugueseAccentsWords), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .simplifiedChinese:
      return cjkPrompt(
        tokens: count, lexicon: ordered(simplifiedChineseWords), usesChineseMarks: true,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .simplifiedChinese1k:
      return cjkPrompt(
        tokens: count, lexicon: ordered(simplifiedChinese1kLexicon), usesChineseMarks: true,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .simplifiedChinese5k:
      return cjkPrompt(
        tokens: count, lexicon: ordered(simplifiedChinese5kLexicon), usesChineseMarks: true,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .simplifiedChinese10k:
      return cjkPrompt(
        tokens: count, lexicon: ordered(simplifiedChinese10kLexicon), usesChineseMarks: true,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .simplifiedChinese50k:
      return cjkPrompt(
        tokens: count, lexicon: ordered(simplifiedChinese50kLexicon), usesChineseMarks: true,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .traditionalChinese:
      return cjkPrompt(
        tokens: count, lexicon: ordered(traditionalChineseWords), usesChineseMarks: true,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .traditionalChinese1k:
      return cjkPrompt(
        tokens: count, lexicon: ordered(traditionalChinese1kLexicon), usesChineseMarks: true,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .traditionalChinese5k:
      return cjkPrompt(
        tokens: count, lexicon: ordered(traditionalChinese5kLexicon), usesChineseMarks: true,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .traditionalChinese10k:
      return cjkPrompt(
        tokens: count, lexicon: ordered(traditionalChinese10kLexicon), usesChineseMarks: true,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .traditionalChinese50k:
      return cjkPrompt(
        tokens: count, lexicon: ordered(traditionalChinese50kLexicon), usesChineseMarks: true,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian:
      return slavicPrompt(
        tokens: count, lexicon: ordered(russianWords), allowsDoubleQuotes: false, allowsApostrophes: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian1k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(russian1kLexicon), allowsDoubleQuotes: false, allowsApostrophes: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian5k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(russian5kLexicon), allowsDoubleQuotes: false, allowsApostrophes: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian10k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(russian10kLexicon), allowsDoubleQuotes: false, allowsApostrophes: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian25k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(russian25kLexicon), allowsDoubleQuotes: false, allowsApostrophes: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian50k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(russian50kLexicon), allowsDoubleQuotes: false, allowsApostrophes: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian375k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(russian375kLexicon), allowsDoubleQuotes: false, allowsApostrophes: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russianAbbreviations:
      return slavicPrompt(
        tokens: count, lexicon: ordered(russianAbbreviationWords), allowsDoubleQuotes: false,
        allowsApostrophes: false, contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russianContractions:
      return slavicEntryPrompt(
        tokens: count, entries: reversesCandidatePool ? Array(russianShortFormWords.reversed()) : russianShortFormWords, allowsDoubleQuotes: false,
        allowsApostrophes: false, contentOptions: contentOptions, lowercasesWithoutPunctuation: true)
    case .russianContractions1k:
      return slavicEntryPrompt(
        tokens: count, entries: reversesCandidatePool ? Array(russianShortForm1kWords.reversed()) : russianShortForm1kWords, allowsDoubleQuotes: false,
        allowsApostrophes: false, contentOptions: contentOptions, lowercasesWithoutPunctuation: true)
    case .ukrainian:
      return slavicPrompt(
        tokens: count, lexicon: ordered(ukrainianWords), allowsDoubleQuotes: true, allowsApostrophes: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainian1k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(ukrainian1kLexicon), allowsDoubleQuotes: true, allowsApostrophes: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainian10k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(ukrainian10kLexicon), allowsDoubleQuotes: true, allowsApostrophes: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainian50k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(ukrainian50kLexicon), allowsDoubleQuotes: true, allowsApostrophes: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainianEndings:
      return slavicPrompt(
        tokens: count, lexicon: ordered(ukrainianEndingWords), allowsDoubleQuotes: true,
        allowsApostrophes: false, contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainianLatin:
      return slavicPrompt(
        tokens: count, lexicon: ordered(ukrainianLatinWords), allowsDoubleQuotes: true,
        allowsApostrophes: false, contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainianLatynka1k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(ukrainianLatynka1kLexicon), allowsDoubleQuotes: true,
        allowsApostrophes: false, contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainianLatynka10k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(ukrainianLatynka10kLexicon), allowsDoubleQuotes: true,
        allowsApostrophes: false, contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainianLatynka50k:
      return slavicPrompt(
        tokens: count, lexicon: ordered(ukrainianLatynka50kLexicon), allowsDoubleQuotes: true,
        allowsApostrophes: false, contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainianLatynkaEndings:
      return slavicPrompt(
        tokens: count, lexicon: ordered(ukrainianLatynkaEndingWords), allowsDoubleQuotes: true,
        allowsApostrophes: false, contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .japaneseHiragana:
      return cjkPrompt(
        tokens: count, lexicon: ordered(japaneseHiraganaWords), usesChineseMarks: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .japaneseKatakana:
      return cjkPrompt(
        tokens: count, lexicon: ordered(japaneseKatakanaWords), usesChineseMarks: false,
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .japaneseRomaji:
      return cjkPrompt(
        tokens: count, lexicon: ordered(japaneseRomajiWords), usesChineseMarks: false, separator: " ",
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .japaneseRomaji1k:
      return cjkPrompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), usesChineseMarks: false,
        separator: " ", contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .korean:
      return prompt(
        tokens: count, lexicon: ordered(koreanWords), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .korean1k:
      return prompt(
        tokens: count, lexicon: ordered(korean1kLexicon), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .korean5k:
      return prompt(
        tokens: count, lexicon: ordered(korean5kLexicon), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .turkish:
      return turkishPrompt(
        tokens: count, lexicon: ordered(turkishWords), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .turkish1k, .turkish5k:
      return turkishPrompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .polish:
      return prompt(
        tokens: count, lexicon: ordered(polishWords), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish2k:
      return prompt(
        tokens: count, lexicon: ordered(polish2kLexicon), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish5k:
      return prompt(
        tokens: count, lexicon: ordered(polish5kLexicon), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish10k:
      return prompt(
        tokens: count, lexicon: ordered(polish10kLexicon), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish20k:
      return prompt(
        tokens: count, lexicon: ordered(polish20kLexicon), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish40k:
      return prompt(
        tokens: count, lexicon: ordered(polish40kLexicon), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish200k:
      return prompt(
        tokens: count, lexicon: ordered(polish200kLexicon), separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .irish1k, .filipino1k, .hungarian1k, .hungarian2k, .welsh1k,
      .lithuanian1k, .lithuanian3k, .latvian1k, .maltese1k,
      .vietnamese1k, .vietnamese5k, .pinyin1k, .pinyin10k, .hausa1k,
      .bemba1k, .bemba10k, .catalan1k, .frisian1k:
      return prompt(
        tokens: count, lexicon: ordered(language.ownedPracticeLexicon()), separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .mixedEnglishChinese:
      let englishLexicon = englishVariant == .british ? britishWords : words
      return (0..<count).map { index in
        let isEnglish = index.isMultiple(of: 2)
        let lexicon = isEnglish ? englishLexicon : simplifiedChineseWords
        let punctuation = isEnglish ? [",", ".", "!", "?"] : ["，", "。", "！", "？"]
        return decoratedToken(
          from: lexicon, punctuation: punctuation, index: index, contentOptions: contentOptions,
          usesZipfFrequency: usesZipfFrequency)
      }.joined(separator: " ")
    case .mixedLanguages:
      let sources = TypingLanguage.normalizedMixedComponents(mixedLanguageComponents).map {
        polyglotSource(for: $0, englishVariant: englishVariant)
      }
      let pool = PolyglotWordPool(sources: sources)
      guard pool.count > 0 else { return "" }
      let permutation = usesZipfFrequency ? pool.zipfPermutation() : (offset: 0, step: 1)
      var recentWords: [String] = []
      return (0..<count).map { index in
        var selected = pool.index(
          for: polyglotRandom(), zipf: usesZipfFrequency,
          offset: permutation.offset, step: permutation.step)
        var entry = pool.entry(at: selected)
        var redraws = 0
        while redraws < 100 && recentWords.contains(entry.word.lowercased()) {
          redraws += 1
          selected = pool.index(
            for: polyglotRandom(), zipf: usesZipfFrequency,
            offset: permutation.offset, step: permutation.step)
          entry = pool.entry(at: selected)
        }
        let rawWord = contentOptions.includeNumbers && index.isMultiple(of: 9)
          ? String(index / 9 + 1) : entry.word
        recentWords.append(rawWord.lowercased())
        if recentWords.count > 2 { recentWords.removeFirst() }
        if contentOptions.includeNumbers, index.isMultiple(of: 9) {
          return rawWord
        }
        if contentOptions.includePunctuation, index.isMultiple(of: 7) {
          return entry.word + entry.punctuation[index / 7 % entry.punctuation.count]
        }
        return entry.word
      }.joined(separator: " ")
    default:
      return prompt(
        tokens: count, lexicon: ordered(words), separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    }
  }

  private static func polyglotSource(
    for language: TypingLanguage, englishVariant: EnglishVariant
  ) -> (IndexedLexicon, [String]) {
    if language.isCodeLanguage {
      return (
        polyglotTokenLexicon(IndexedLexicon(CodePracticeContent.polyglotTokens(for: language))),
        [".", ",", ";", ":"])
    }
    if TypingLanguage.defaultMixedComponents.contains(language) {
      let existing = source(for: language, englishVariant: englishVariant)
      return (polyglotTokenLexicon(IndexedLexicon(existing.0)), existing.1)
    }
    return (
      polyglotTokenLexicon(language.ownedPracticeLexicon(englishVariant: englishVariant)),
      language.polyglotPunctuation)
  }

  private static func polyglotTokenLexicon(_ lexicon: IndexedLexicon) -> IndexedLexicon {
    IndexedLexicon(count: lexicon.count) { index in
      PolyglotTokenPolicy.token(from: lexicon[index], selectionIndex: index)
    }
  }

  private static func prompt(
    tokens: Int, lexicon: [String], separator: String, punctuation: [String],
    contentOptions: ContentOptions, usesZipfFrequency: Bool
  ) -> String {
    prompt(
      tokens: tokens, lexicon: IndexedLexicon(lexicon), separator: separator,
      punctuation: punctuation, contentOptions: contentOptions,
      usesZipfFrequency: usesZipfFrequency)
  }

  static func prompt(
    tokens: Int, lexicon: IndexedLexicon, separator: String, punctuation: [String],
    contentOptions: ContentOptions, usesZipfFrequency: Bool,
    wordRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    var recentWords: [String] = []
    return (0..<tokens).map { index in
      let word = RecentWordSelection.sample(
        from: lexicon, previousWords: recentWords, usesZipfFrequency: usesZipfFrequency,
        random: wordRandom)
      let rawWord = contentOptions.includeNumbers && index.isMultiple(of: 9)
        ? String(index / 9 + 1) : word
      recentWords.append(rawWord.lowercased())
      if recentWords.count > 2 { recentWords.removeFirst() }
      if contentOptions.includeNumbers, index.isMultiple(of: 9) { return rawWord }
      if contentOptions.includePunctuation, index.isMultiple(of: 7) {
        return word + punctuation[index / 7 % punctuation.count]
      }
      return word
    }.joined(separator: separator)
  }

  static func englishPrompt(
    tokens: Int, lexicon: [String], contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    englishPrompt(
      tokens: tokens, lexicon: IndexedLexicon(lexicon), contentOptions: contentOptions,
      usesZipfFrequency: usesZipfFrequency, contentRandom: contentRandom)
  }

  static func englishPrompt(
    tokens: Int, lexicon: IndexedLexicon, contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    let generated = prompt(
      tokens: tokens, lexicon: lexicon, separator: " ", punctuation: [",", ".", "!", "?"],
      contentOptions: ContentOptions(),
      usesZipfFrequency: usesZipfFrequency)
    guard contentOptions.includePunctuation || contentOptions.includeNumbers else { return generated }
    return EnglishPunctuationPolicy.generatedPrompt(
      generated.split(separator: " ").map(String.init),
      includesPunctuation: contentOptions.includePunctuation,
      includesNumbers: contentOptions.includeNumbers,
      random: contentRandom
    ).joined(separator: " ")
  }

  static func spanishPrompt(
    tokens: Int, lexicon: [String], contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    spanishPrompt(
      tokens: tokens, lexicon: IndexedLexicon(lexicon), contentOptions: contentOptions,
      usesZipfFrequency: usesZipfFrequency, contentRandom: contentRandom)
  }

  static func spanishPrompt(
    tokens: Int, lexicon: IndexedLexicon, contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    let generated = prompt(
      tokens: tokens, lexicon: lexicon, separator: " ", punctuation: [",", ".", "!", "?"],
      contentOptions: ContentOptions(), usesZipfFrequency: usesZipfFrequency)
    guard contentOptions.includePunctuation || contentOptions.includeNumbers else { return generated }
    return SpanishPunctuationPolicy.generatedPrompt(
      generated.split(separator: " ").map(String.init),
      includesPunctuation: contentOptions.includePunctuation,
      includesNumbers: contentOptions.includeNumbers,
      random: contentRandom
    ).joined(separator: " ")
  }

  static func arabicPrompt(
    tokens: Int, lexicon: [String], contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    arabicPrompt(
      tokens: tokens, lexicon: IndexedLexicon(lexicon), contentOptions: contentOptions,
      usesZipfFrequency: usesZipfFrequency, contentRandom: contentRandom)
  }

  static func arabicPrompt(
    tokens: Int, lexicon: IndexedLexicon, contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    let generated = prompt(
      tokens: tokens, lexicon: lexicon, separator: " ", punctuation: ["،", "؛", "؟", "."],
      contentOptions: ContentOptions(), usesZipfFrequency: usesZipfFrequency)
    guard contentOptions.includePunctuation || contentOptions.includeNumbers else { return generated }
    return ArabicPunctuationPolicy.generatedPrompt(
      generated.split(separator: " ").map(String.init),
      includesPunctuation: contentOptions.includePunctuation,
      includesNumbers: contentOptions.includeNumbers,
      random: contentRandom
    ).joined(separator: " ")
  }

  static func persianUrduPrompt(
    tokens: Int, lexicon: [String], contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    persianUrduPrompt(
      tokens: tokens, lexicon: IndexedLexicon(lexicon), contentOptions: contentOptions,
      usesZipfFrequency: usesZipfFrequency, contentRandom: contentRandom)
  }

  static func persianUrduPrompt(
    tokens: Int, lexicon: IndexedLexicon, contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    let generated = prompt(
      tokens: tokens, lexicon: lexicon, separator: " ", punctuation: ["،", ";", "؟", "."],
      contentOptions: ContentOptions(), usesZipfFrequency: usesZipfFrequency)
    guard contentOptions.includePunctuation || contentOptions.includeNumbers else { return generated }
    return PersianUrduPunctuationPolicy.generatedPrompt(
      generated.split(separator: " ").map(String.init),
      includesPunctuation: contentOptions.includePunctuation,
      includesNumbers: contentOptions.includeNumbers,
      random: contentRandom
    ).joined(separator: " ")
  }

  static func indicPrompt(
    tokens: Int, lexicon: [String], digits: [Character], contentOptions: ContentOptions,
    usesZipfFrequency: Bool
  ) -> String {
    indicPrompt(
      tokens: tokens, lexicon: IndexedLexicon(lexicon), digits: digits, contentOptions: contentOptions,
      usesZipfFrequency: usesZipfFrequency)
  }

  static func indicPrompt(
    tokens: Int, lexicon: IndexedLexicon, digits: [Character], contentOptions: ContentOptions,
    usesZipfFrequency: Bool
  ) -> String {
    let generated = prompt(
      tokens: tokens, lexicon: lexicon, separator: " ", punctuation: ["।", ",", "!", "?"],
      contentOptions: ContentOptions(), usesZipfFrequency: usesZipfFrequency)
    guard contentOptions.includePunctuation || contentOptions.includeNumbers else { return generated }
    return IndicPunctuationPolicy.generatedPrompt(
      generated.split(separator: " ").map(String.init), digits: digits,
      includesPunctuation: contentOptions.includePunctuation, includesNumbers: contentOptions.includeNumbers
    ).joined(separator: " ")
  }

  static func slavicPrompt(
    tokens: Int, lexicon: [String], allowsDoubleQuotes: Bool, allowsApostrophes: Bool,
    contentOptions: ContentOptions, usesZipfFrequency: Bool
  ) -> String {
    slavicPrompt(
      tokens: tokens, lexicon: IndexedLexicon(lexicon), allowsDoubleQuotes: allowsDoubleQuotes,
      allowsApostrophes: allowsApostrophes, contentOptions: contentOptions,
      usesZipfFrequency: usesZipfFrequency)
  }

  static func slavicPrompt(
    tokens: Int, lexicon: IndexedLexicon, allowsDoubleQuotes: Bool, allowsApostrophes: Bool,
    contentOptions: ContentOptions, usesZipfFrequency: Bool
  ) -> String {
    let generated = prompt(
      tokens: tokens, lexicon: lexicon, separator: " ", punctuation: [".", ",", "!", "?"],
      contentOptions: ContentOptions(), usesZipfFrequency: usesZipfFrequency)
    guard contentOptions.includePunctuation || contentOptions.includeNumbers else { return generated }
    return SlavicPunctuationPolicy.generatedPrompt(
      generated.split(separator: " ").map(String.init), allowsDoubleQuotes: allowsDoubleQuotes,
      allowsApostrophes: allowsApostrophes, includesPunctuation: contentOptions.includePunctuation,
      includesNumbers: contentOptions.includeNumbers
    ).joined(separator: " ")
  }

  static func slavicEntryPrompt(
    tokens: Int, entries: [String], allowsDoubleQuotes: Bool, allowsApostrophes: Bool,
    contentOptions: ContentOptions, lowercasesWithoutPunctuation: Bool = false
  ) -> String {
    let punctuationEligibleEntries = contentOptions.includePunctuation
      ? entries
      : entries.filter { entry in entry.allSatisfy { $0.isLetter || $0.isNumber || $0.isWhitespace } }
    let eligibleEntries = contentOptions.includeNumbers
      ? punctuationEligibleEntries
      : punctuationEligibleEntries.filter { !$0.contains(where: \.isNumber) }
    precondition(!eligibleEntries.isEmpty)
    var words: [String] = []
    while words.count < tokens {
      let entry = eligibleEntries[Int.random(in: eligibleEntries.indices)]
      let entryWords = entry.split(whereSeparator: \.isWhitespace).map(String.init)
      words.append(contentsOf: lowercasesWithoutPunctuation && !contentOptions.includePunctuation
        ? entryWords.map { $0.lowercased() }
        : entryWords)
    }
    words = Array(words.prefix(tokens))
    guard contentOptions.includePunctuation || contentOptions.includeNumbers else {
      return words.joined(separator: " ")
    }
    return SlavicPunctuationPolicy.generatedPrompt(
      words, allowsDoubleQuotes: allowsDoubleQuotes, allowsApostrophes: allowsApostrophes,
      includesPunctuation: contentOptions.includePunctuation, includesNumbers: contentOptions.includeNumbers
    ).joined(separator: " ")
  }

  static func cjkPrompt(
    tokens: Int, lexicon: [String], usesChineseMarks: Bool, separator: String = " ",
    contentOptions: ContentOptions, usesZipfFrequency: Bool,
    contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    cjkPrompt(
      tokens: tokens, lexicon: IndexedLexicon(lexicon), usesChineseMarks: usesChineseMarks,
      separator: separator, contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency,
      contentRandom: contentRandom)
  }

  static func cjkPrompt(
    tokens: Int, lexicon: IndexedLexicon, usesChineseMarks: Bool, separator: String = " ",
    contentOptions: ContentOptions, usesZipfFrequency: Bool,
    contentRandom: () -> Double = { Double.random(in: 0..<1) },
    wordRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    var recentWords: [String] = []
    let generated = (0..<tokens).map { _ in
      let word = RecentWordSelection.sample(
        from: lexicon, previousWords: recentWords, usesZipfFrequency: usesZipfFrequency,
        random: wordRandom)
      recentWords.append(word.lowercased())
      if recentWords.count > 2 { recentWords.removeFirst() }
      return word
    }
    guard contentOptions.includePunctuation || contentOptions.includeNumbers else {
      return generated.joined(separator: separator)
    }
    return CJKPunctuationPolicy.generatedPrompt(
      generated, usesChineseMarks: usesChineseMarks,
      includesPunctuation: contentOptions.includePunctuation,
      includesNumbers: contentOptions.includeNumbers, random: contentRandom
    ).joined(separator: separator)
  }

  static func frenchPrompt(
    tokens: Int, lexicon: [String], contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    frenchPrompt(
      tokens: tokens, lexicon: IndexedLexicon(lexicon), contentOptions: contentOptions,
      usesZipfFrequency: usesZipfFrequency, contentRandom: contentRandom)
  }

  static func frenchPrompt(
    tokens: Int, lexicon: IndexedLexicon, contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    let generated = prompt(
      tokens: tokens, lexicon: lexicon, separator: " ", punctuation: [",", ".", "!", "?"],
      contentOptions: ContentOptions(), usesZipfFrequency: usesZipfFrequency)
    guard contentOptions.includePunctuation || contentOptions.includeNumbers else { return generated }
    return FrenchPunctuationPolicy.generatedPrompt(
      generated.split(separator: " ").map(String.init),
      includesPunctuation: contentOptions.includePunctuation,
      includesNumbers: contentOptions.includeNumbers,
      random: contentRandom
    ).joined(separator: " ")
  }

  static func greekPrompt(
    tokens: Int, lexicon: [String], contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    greekPrompt(
      tokens: tokens, lexicon: IndexedLexicon(lexicon), contentOptions: contentOptions,
      usesZipfFrequency: usesZipfFrequency, contentRandom: contentRandom)
  }

  static func greekPrompt(
    tokens: Int, lexicon: IndexedLexicon, contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    let generated = prompt(
      tokens: tokens, lexicon: lexicon, separator: " ", punctuation: [",", ".", "!", "?"],
      contentOptions: ContentOptions(), usesZipfFrequency: usesZipfFrequency)
    guard contentOptions.includePunctuation || contentOptions.includeNumbers else { return generated }
    return GreekPunctuationPolicy.generatedPrompt(
      generated.split(separator: " ").map(String.init),
      includesPunctuation: contentOptions.includePunctuation,
      includesNumbers: contentOptions.includeNumbers,
      random: contentRandom
    ).joined(separator: " ")
  }

  static func kurdishPrompt(
    tokens: Int, lexicon: [String], contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    kurdishPrompt(
      tokens: tokens, lexicon: IndexedLexicon(lexicon), contentOptions: contentOptions,
      usesZipfFrequency: usesZipfFrequency, contentRandom: contentRandom)
  }

  static func kurdishPrompt(
    tokens: Int, lexicon: IndexedLexicon, contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    let generated = prompt(
      tokens: tokens, lexicon: lexicon, separator: " ", punctuation: ["،", "؛", "؟", "."],
      contentOptions: ContentOptions(), usesZipfFrequency: usesZipfFrequency)
    guard contentOptions.includePunctuation || contentOptions.includeNumbers else { return generated }
    return KurdishPunctuationPolicy.generatedPrompt(
      generated.split(separator: " ").map(String.init),
      includesPunctuation: contentOptions.includePunctuation,
      includesNumbers: contentOptions.includeNumbers,
      random: contentRandom
    ).joined(separator: " ")
  }

  static func turkishPrompt(
    tokens: Int, lexicon: [String], contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    turkishPrompt(
      tokens: tokens, lexicon: IndexedLexicon(lexicon), contentOptions: contentOptions,
      usesZipfFrequency: usesZipfFrequency, contentRandom: contentRandom)
  }

  static func turkishPrompt(
    tokens: Int, lexicon: IndexedLexicon, contentOptions: ContentOptions,
    usesZipfFrequency: Bool, contentRandom: () -> Double = { Double.random(in: 0..<1) }
  ) -> String {
    let generated = prompt(
      tokens: tokens, lexicon: lexicon, separator: " ", punctuation: [".", ",", "!", "?"],
      contentOptions: ContentOptions(), usesZipfFrequency: usesZipfFrequency)
    guard contentOptions.includePunctuation || contentOptions.includeNumbers else { return generated }
    return TurkishPunctuationPolicy.generatedPrompt(
      generated.split(separator: " ").map(String.init),
      includesPunctuation: contentOptions.includePunctuation,
      includesNumbers: contentOptions.includeNumbers,
      random: contentRandom
    ).joined(separator: " ")
  }

  private static func sectionPrompt(
    tokens: Int, sections: [String], contentOptions: ContentOptions
  ) -> String {
    precondition(!sections.isEmpty)
    var words: [String] = []
    while words.count < tokens {
      let section = sections[Int.random(in: sections.indices)]
      if contentOptions.includePunctuation {
        words.append(contentsOf: section.split(whereSeparator: \.isWhitespace).map(String.init))
      } else {
        words.append(contentsOf: section.lowercased().split { !$0.isLetter }.map(String.init))
      }
    }
    words = Array(words.prefix(tokens))
    if contentOptions.includeNumbers {
      for index in words.indices where index.isMultiple(of: 9) {
        words[index] = String(index / 9 + 1)
      }
    }
    return words.joined(separator: " ")
  }

  private static func entryPrompt(
    tokens: Int, entries: [String], contentOptions: ContentOptions,
    lowercasesWithoutPunctuation: Bool = false
  ) -> String {
    let eligibleEntries = contentOptions.includePunctuation
      ? entries
      : entries.filter { entry in entry.allSatisfy { $0.isLetter || $0.isNumber || $0.isWhitespace } }
    precondition(!eligibleEntries.isEmpty)
    var words: [String] = []
    while words.count < tokens {
      let entry = eligibleEntries[Int.random(in: eligibleEntries.indices)]
      let entryWords = entry.split(whereSeparator: \.isWhitespace).map(String.init)
      words.append(contentsOf: lowercasesWithoutPunctuation && !contentOptions.includePunctuation
        ? entryWords.map { $0.lowercased() }
        : entryWords)
    }
    words = Array(words.prefix(tokens))
    for index in words.indices {
      if contentOptions.includeNumbers, index.isMultiple(of: 9) {
        words[index] = String(index / 9 + 1)
      } else if contentOptions.includePunctuation, index.isMultiple(of: 7) {
        let punctuation = [",", ".", "!", "?"]
        words[index] += punctuation[index / 7 % punctuation.count]
      }
    }
    return words.joined(separator: " ")
  }

  private static func source(for language: TypingLanguage, englishVariant: EnglishVariant) -> (
    [String], [String]
  ) {
    switch language {
    case .english: (englishVariant == .british ? britishWords : words, [",", ".", "!", "?"])
    case .english1k: (english1kWords, [",", ".", "!", "?"])
    case .english5k: (english5kWords, [",", ".", "!", "?"])
    case .english10k: (english10kWords, [",", ".", "!", "?"])
    case .english25k: (english25kWords, [",", ".", "!", "?"])
    case .english450k: (english450kWords, [",", ".", "!", "?"])
    case .englishFiveLetter: (englishFiveLetterWords, [",", ".", "!", "?"])
    case .englishCommonlyMisspelled: (englishCommonlyMisspelledWords, [",", ".", "!", "?"])
    case .englishContractions: (englishContractionWords, [",", ".", "!", "?"])
    case .englishDoubleLetter: (englishDoubleLetterWords, [",", ".", "!", "?"])
    case .englishLegal: (englishLegalWords, [",", ".", "!", "?"])
    case .englishMedical: (englishMedicalWords, [",", ".", "!", "?"])
    case .englishShakespearean: (englishShakespeareanWords, [",", ".", "!", "?"])
    case .oldEnglish: (oldEnglishWords, [",", ".", "!", "?"])
    case .kokanu: (kokanuWords, [",", ".", "!", "?"])
    case .likanu: (likanuWords, ["､", ":", "ʭ", "≈"])
    case .pigLatin: (pigLatinWords, [",", ".", "!", "?"])
    case .spanish: (spanishWords, [",", ".", "¡", "¿"])
    case .spanish1k: (spanish1kWords, [",", ".", "¡", "¿"])
    case .spanish10k: (spanish10kWords, [",", ".", "¡", "¿"])
    case .spanish650k: (spanish650kWords, [",", ".", "¡", "¿"])
    case .german: (germanWords, [",", ".", "!", "?"])
    case .german1k: (german1kWords, [",", ".", "!", "?"])
    case .german10k: (german10kWords, [",", ".", "!", "?"])
    case .german250k: (german250kWords, [",", ".", "!", "?"])
    case .swissGerman: (swissGermanWords, [",", ".", "!", "?"])
    case .swissGerman1k: (swissGerman1kWords, [",", ".", "!", "?"])
    case .swissGerman2k: (swissGerman2kWords, [",", ".", "!", "?"])
    case .afrikaans: (afrikaansWords, [",", ".", "!", "?"])
    case .afrikaans1k: (afrikaans1kWords, [",", ".", "!", "?"])
    case .afrikaans10k: (afrikaans10kWords, [",", ".", "!", "?"])
    case .albanian: (albanianWords, [",", ".", "!", "?"])
    case .bemba: (bembaWords, [",", ".", "!", "?"])
    case .bosnian: (bosnianWords, [",", ".", "!", "?"])
    case .esperanto: (esperantoWords, [",", ".", "!", "?"])
    case .esperanto1k: (esperanto1kWords, [",", ".", "!", "?"])
    case .esperanto10k: (esperanto10kWords, [",", ".", "!", "?"])
    case .esperanto25k: (esperanto25kWords, [",", ".", "!", "?"])
    case .esperanto36k: (esperanto36kWords, [",", ".", "!", "?"])
    case .esperantoXSystem: (esperantoXSystemWords, [",", ".", "!", "?"])
    case .esperantoXSystem1k: (esperantoXSystem1kWords, [",", ".", "!", "?"])
    case .esperantoXSystem10k: (esperantoXSystem10kWords, [",", ".", "!", "?"])
    case .esperantoXSystem25k: (esperantoXSystem25kWords, [",", ".", "!", "?"])
    case .esperantoXSystem36k: (esperantoXSystem36kWords, [",", ".", "!", "?"])
    case .esperantoHSystem: (esperantoHSystemWords, [",", ".", "!", "?"])
    case .esperantoHSystem1k: (esperantoHSystem1kWords, [",", ".", "!", "?"])
    case .esperantoHSystem10k: (esperantoHSystem10kWords, [",", ".", "!", "?"])
    case .esperantoHSystem25k: (esperantoHSystem25kWords, [",", ".", "!", "?"])
    case .esperantoHSystem36k: (esperantoHSystem36kWords, [",", ".", "!", "?"])
    case .latin: (latinWords, [",", ".", "!", "?"])
    case .loremIpsum: (loremIpsumWords, [",", ".", "!", "?"])
    case .git: (gitWords, [",", ".", "!", "?"])
    case .twitchEmotes: (twitchEmoteWords, [",", ".", "!", "?"])
    case .typingOfTheDead: (typingOfTheDeadWords, [",", ".", "!", "?"])
    case .pokemon1k: (creatureIndexTokens, [",", ".", "!", "?"])
    case .arenaStrategy: (arenaStrategyTokens, [",", ".", "!", "?"])
    case .friulian: (friulianWords, [",", ".", "!", "?"])
    case .malagasy: (malagasyWords, [",", ".", "!", "?"])
    case .malagasy1k: (malagasy1kWords, [",", ".", "!", "?"])
    case .welsh: (welshWords, [",", ".", "!", "?"])
    case .hausa: (hausaWords, [",", ".", "!", "?"])
    case .tatar: (tatarWords, [",", ".", "!", "?"])
    case .tatar1k: (tatar1kWords, [",", ".", "!", "?"])
    case .tatar5k: (tatar5kWords, [",", ".", "!", "?"])
    case .tatar9k: (tatar9kWords, [",", ".", "!", "?"])
    case .tatarCrimean: (tatarCrimeanWords, [",", ".", "!", "?"])
    case .tatarCrimean1k: (tatarCrimean1kWords, [",", ".", "!", "?"])
    case .tatarCrimean5k: (tatarCrimean5kWords, [",", ".", "!", "?"])
    case .tatarCrimean10k: (tatarCrimean10kWords, [",", ".", "!", "?"])
    case .tatarCrimean15k: (tatarCrimean15kWords, [",", ".", "!", "?"])
    case .tatarCrimeanCyrillic: (tatarCrimeanCyrillicWords, [",", ".", "!", "?"])
    case .tatarCrimeanCyrillic1k: (tatarCrimeanCyrillic1kWords, [",", ".", "!", "?"])
    case .tatarCrimeanCyrillic5k: (tatarCrimeanCyrillic5kWords, [",", ".", "!", "?"])
    case .tatarCrimeanCyrillic10k: (tatarCrimeanCyrillic10kWords, [",", ".", "!", "?"])
    case .tatarCrimeanCyrillic15k: (tatarCrimeanCyrillic15kWords, [",", ".", "!", "?"])
    case .klingon: (klingonWords, [",", ".", "!", "?"])
    case .quenya: (quenyaWords, [",", ".", "!", "?"])
    case .viossa: (viossaWords, [",", ".", "!", "?"])
    case .viossaNjutro: (viossaNjutroWords, [",", ".", "!", "?"])
    case .maori: (maoriWords, [",", ".", "!", "?"])
    case .lojbanGismu: (lojbanGismuWords, [",", "!", "?"])
    case .lojbanCmavo: (lojbanCmavoWords, [",", "!", "?"])
    case .uzbek: (uzbekWords, [",", ".", "!", "?"])
    case .uzbek1k: (uzbek1kWords, [",", ".", "!", "?"])
    case .uzbek70k: (uzbek70kWords, [",", ".", "!", "?"])
    case .occitan: (occitanWords, [",", ".", "!", "?"])
    case .occitan1k: (occitan1kWords, [",", ".", "!", "?"])
    case .occitan2k: (occitan2kWords, [",", ".", "!", "?"])
    case .occitan5k: (occitan5kWords, [",", ".", "!", "?"])
    case .occitan10k: (occitan10kWords, [",", ".", "!", "?"])
    case .oromo: (oromoWords, [",", ".", "!", "?"])
    case .macedonian: (macedonianWords, [",", ".", "!", "?"])
    case .kazakh: (kazakhWords, [",", ".", "!", "?"])
    case .kazakh1k: (kazakh1kWords, [",", ".", "!", "?"])
    case .vietnamese: (vietnameseWords, [",", ".", "!", "?"])
    case .jyutping: (jyutpingWords, [",", ".", "!", "?"])
    case .pinyin: (pinyinWords, [",", ".", "!", "?"])
    case .bashkir: (bashkirWords, [",", ".", "!", "?"])
    case .basque: (basqueWords, [",", ".", "!", "?"])
    case .frisian: (frisianWords, [",", ".", "!", "?"])
    case .zulu: (zuluWords, [",", ".", "!", "?"])
    case .hawaiian: (hawaiianWords, [",", ".", "!", "?"])
    case .kabyle: (kabyleWords, [",", ".", "!", "?"])
    case .kabyle1k: (kabyle1kWords, [",", ".", "!", "?"])
    case .kabyle2k: (kabyle2kWords, [",", ".", "!", "?"])
    case .kabyle5k: (kabyle5kWords, [",", ".", "!", "?"])
    case .kabyle10k: (kabyle10kWords, [",", ".", "!", "?"])
    case .maltese: (malteseWords, [",", ".", "!", "?"])
    case .tokiPona: (tokiPonaWords, [",", ".", "!", "?"])
    case .tokiPonaKuSuli: (tokiPonaKuSuliWords, [",", ".", "!", "?"])
    case .tokiPonaKuLili: (tokiPonaKuLiliWords, [",", ".", "!", "?"])
    case .xhosa: (xhosaWords, [",", ".", "!", "?"])
    case .tibetan: (tibetanWords, ["།"])
    case .kyrgyz: (kyrgyzWords, [",", ".", "!", "?"])
    case .kyrgyz1k: (kyrgyz1kWords, [",", ".", "!", "?"])
    case .udmurt: (udmurtWords, [",", ".", "!", "?"])
    case .yoruba: (yorubaWords, [",", ".", "!", "?"])
    case .swahili: (swahiliWords, [",", ".", "!", "?"])
    case .kinyarwanda: (kinyarwandaWords, [",", ".", "!", "?"])
    case .shona: (shonaWords, [",", ".", "!", "?"])
    case .santali: (santaliWords, ["᱾", "?"])
    case .yiddish: (yiddishWords, [",", ".", "!", "?"])
    case .arabic: (arabicWords, ["،", "؛", "؟", "."])
    case .arabic10k: (arabic10kWords, ["،", "؛", "؟", "."])
    case .arabicEgypt: (arabicEgyptWords, ["،", "؛", "؟", "."])
    case .arabicEgypt1k: (arabicEgypt1kWords, ["،", "؛", "؟", "."])
    case .arabicMorocco: (arabicMoroccoWords, ["،", "؛", "؟", "."])
    case .pashto: (pashtoWords, ["،", "؛", "؟", "."])
    case .sindhi: (sindhiWords, ["،", "؛", "؟", "."])
    case .hebrew: (hebrewWords, [",", ".", "!", "?"])
    case .hebrew1k: (hebrew1kWords, [",", ".", "!", "?"])
    case .hebrew5k: (hebrew5kWords, [",", ".", "!", "?"])
    case .hebrew10k: (hebrew10kWords, [",", ".", "!", "?"])
    case .persian: (persianWords, ["،", "؛", "؟", "."])
    case .persian1k: (persian1kWords, ["،", "؛", "؟", "."])
    case .persian5k: (persian5kWords, ["،", "؛", "؟", "."])
    case .persian20k: (persian20kWords, ["،", "؛", "؟", "."])
    case .persianRomanized: (persianRomanizedWords, [",", ".", "!", "?"])
    case .urdu: (urduWords, ["،", "؛", "؟", "."])
    case .urdu1k: (urdu1kWords, ["،", "؛", "؟", "."])
    case .urdu5k: (urdu5kWords, ["،", "؛", "؟", "."])
    case .urduRoman: (urduRomanWords, [",", ".", "!", "?"])
    case .urdish: (urdishWords, [",", ".", "!", "?"])
    case .tamil: (tamilWords, [",", ".", "!", "?"])
    case .tamil1k: (tamil1kWords, [",", ".", "!", "?"])
    case .tamilOld: (tamilOldTokens, [",", ".", "!", "?"])
    case .tanglish: (tanglishWords, [",", ".", "!", "?"])
    case .hindi: (hindiWords, [",", ".", "!", "?"])
    case .hindi1k: (hindi1kWords, [",", ".", "!", "?"])
    case .hinglish: (hinglishWords, [",", ".", "!", "?"])
    case .gujarati: (gujaratiWords, [",", ".", "!", "?"])
    case .gujarati1k: (gujarati1kWords, [",", ".", "!", "?"])
    case .bangla: (banglaWords, [",", ".", "!", "?"])
    case .bangla10k: (bangla10kWords, [",", ".", "!", "?"])
    case .banglaLetters: (banglaLetterWords, ["।", ",", "!", "?"])
    case .thai: (thaiWords, [",", ".", "!", "?"])
    case .thai1k: (thai1kWords, [",", ".", "!", "?"])
    case .thai5k: (thai5kWords, [",", ".", "!", "?"])
    case .thai10k: (thai10kWords, [",", ".", "!", "?"])
    case .thai20k: (thai20kWords, [",", ".", "!", "?"])
    case .thai50k: (thai50kWords, [",", ".", "!", "?"])
    case .thai60k: (thai60kWords, [",", ".", "!", "?"])
    case .nepali: (nepaliWords, [",", ".", "!", "?"])
    case .nepali1k: (nepali1kWords, [",", ".", "!", "?"])
    case .nepaliRomanized: (nepaliRomanizedWords, [",", ".", "!", "?"])
    case .kannada: (kannadaWords, [",", ".", "!", "?"])
    case .telugu: (teluguWords, [",", ".", "!", "?"])
    case .telugu1k: (telugu1kWords, [",", ".", "!", "?"])
    case .malayalam: (malayalamWords, [",", ".", "!", "?"])
    case .sanskrit: (sanskritWords, [",", ".", "!", "?"])
    case .sanskritRoman: (sanskritRomanWords, [",", ".", "!", "?"])
    case .sinhala: (sinhalaWords, [",", ".", "!", "?"])
    case .khmer: (khmerWords, [",", ".", "!", "?"])
    case .myanmarBurmese: (myanmarBurmeseWords, [",", ".", "!", "?"])
    case .lao: (laoWords, [",", ".", "!", "?"])
    case .amharic: (amharicWords, [",", ".", "!", "?"])
    case .armenian: (armenianWords, [",", ".", "!", "?"])
    case .armenianWestern: (armenianWesternWords, [",", ".", "!", "?"])
    case .georgian: (georgianWords, [",", ".", "!", "?"])
    case .azerbaijani: (azerbaijaniWords, [",", ".", "!", "?"])
    case .azerbaijani1k: (azerbaijani1kWords, [",", ".", "!", "?"])
    case .belarusian: (belarusianWords, [",", ".", "!", "?"])
    case .belarusian1k: (belarusian1kWords, [",", ".", "!", "?"])
    case .belarusian5k: (belarusian5kWords, [",", ".", "!", "?"])
    case .belarusian10k: (belarusian10kWords, [",", ".", "!", "?"])
    case .belarusian25k: (belarusian25kWords, [",", ".", "!", "?"])
    case .belarusian50k: (belarusian50kWords, [",", ".", "!", "?"])
    case .belarusian100k: (belarusian100kWords, [",", ".", "!", "?"])
    case .belarusianLacinka: (belarusianLacinkaWords, [",", ".", "!", "?"])
    case .lithuanian: (lithuanianWords, [",", ".", "!", "?"])
    case .latvian: (latvianWords, [",", ".", "!", "?"])
    case .mongolian: (mongolianWords, [",", ".", "!", "?"])
    case .mongolian10k: (mongolian10kWords, [",", ".", "!", "?"])
    case .irish: (irishWords, [",", ".", "!", "?"])
    case .galician: (galicianWords, [",", ".", "!", "?"])
    case .marathi: (marathiWords, [",", ".", "!", "?"])
    case .kurdishCentral: (kurdishCentralWords, ["،", "؛", "؟", "."])
    case .kurdishCentral2k: (kurdishCentral2kWords, ["،", "؛", "؟", "."])
    case .kurdishCentral4k: (kurdishCentral4kWords, ["،", "؛", "؟", "."])
    case .greek: (greekWords, [",", ".", "!", "?"])
    case .greek1k: (greek1kWords, [",", ".", "!", "?"])
    case .greek5k: (greek5kWords, [",", ".", "!", "?"])
    case .greek10k: (greek10kWords, [",", ".", "!", "?"])
    case .greek25k: (greek25kWords, [",", ".", "!", "?"])
    case .greekKoine: (greekKoineWords, [",", ".", "!", "?"])
    case .greeklish: (greeklishWords, [",", ".", "!", "?"])
    case .greeklish1k: (greeklish1kWords, [",", ".", "!", "?"])
    case .greeklish5k: (greeklish5kWords, [",", ".", "!", "?"])
    case .greeklish10k: (greeklish10kWords, [",", ".", "!", "?"])
    case .greeklish25k: (greeklish25kWords, [",", ".", "!", "?"])
    case .dutch: (dutchWords, [",", ".", "!", "?"])
    case .dutch1k: (dutch1kWords, [",", ".", "!", "?"])
    case .dutch10k: (dutch10kWords, [",", ".", "!", "?"])
    case .filipino: (filipinoWords, [",", ".", "!", "?"])
    case .catalan: (catalanWords, [",", ".", "!", "?"])
    case .indonesian: (indonesianWords, [",", ".", "!", "?"])
    case .indonesian1k: (indonesian1kWords, [",", ".", "!", "?"])
    case .indonesian10k: (indonesian10kWords, [",", ".", "!", "?"])
    case .malay: (malayWords, [",", ".", "!", "?"])
    case .malay1k: (malay1kWords, [",", ".", "!", "?"])
    case .danish: (danishWords, [",", ".", "!", "?"])
    case .danish1k: (danish1kWords, [",", ".", "!", "?"])
    case .danish10k: (danish10kWords, [",", ".", "!", "?"])
    case .norwegianBokmal: (norwegianBokmalWords, [",", ".", "!", "?"])
    case .norwegianBokmal1k: (norwegianBokmal1kWords, [",", ".", "!", "?"])
    case .norwegianBokmal5k: (norwegianBokmal5kWords, [",", ".", "!", "?"])
    case .norwegianBokmal10k: (norwegianBokmal10kWords, [",", ".", "!", "?"])
    case .norwegianBokmal150k: (norwegianBokmal150kWords, [",", ".", "!", "?"])
    case .norwegianBokmal600k: (norwegianBokmal600kWords, [",", ".", "!", "?"])
    case .norwegianNynorsk: (norwegianNynorskWords, [",", ".", "!", "?"])
    case .norwegianNynorsk1k: (norwegianNynorsk1kWords, [",", ".", "!", "?"])
    case .norwegianNynorsk5k: (norwegianNynorsk5kWords, [",", ".", "!", "?"])
    case .norwegianNynorsk10k: (norwegianNynorsk10kWords, [",", ".", "!", "?"])
    case .norwegianNynorsk100k: (norwegianNynorsk100kWords, [",", ".", "!", "?"])
    case .norwegianNynorsk400k: (norwegianNynorsk400kWords, [",", ".", "!", "?"])
    case .swedish: (swedishWords, [",", ".", "!", "?"])
    case .swedish1k: (swedish1kWords, [",", ".", "!", "?"])
    case .swedishDiacritics: (swedishDiacriticsWords, [",", ".", "!", "?"])
    case .hungarian: (hungarianWords, [",", ".", "!", "?"])
    case .czech: (czechWords, [",", ".", "!", "?"])
    case .czech1k: (czech1kWords, [",", ".", "!", "?"])
    case .czech10k: (czech10kWords, [",", ".", "!", "?"])
    case .slovak: (slovakWords, [",", ".", "!", "?"])
    case .slovak1k: (slovak1kWords, [",", ".", "!", "?"])
    case .slovak10k: (slovak10kWords, [",", ".", "!", "?"])
    case .slovenian: (slovenianWords, [",", ".", "!", "?"])
    case .slovenian1k: (slovenian1kWords, [",", ".", "!", "?"])
    case .slovenian5k: (slovenian5kWords, [",", ".", "!", "?"])
    case .croatian: (croatianWords, [",", ".", "!", "?"])
    case .croatian1k: (croatian1kWords, [",", ".", "!", "?"])
    case .serbian: (serbianWords, [".", ",", "!", "?"])
    case .serbianLatin: (serbianLatinWords, [",", ".", "!", "?"])
    case .bulgarian: (bulgarianWords, [".", ",", "!", "?"])
    case .bulgarianLatin: (bulgarianLatinWords, [".", ",", "!", "?"])
    case .romanian: (romanianWords, [",", ".", "!", "?"])
    case .romanian1k: (romanian1kWords, [",", ".", "!", "?"])
    case .romanian5k: (romanian5kWords, [",", ".", "!", "?"])
    case .romanian10k: (romanian10kWords, [",", ".", "!", "?"])
    case .romanian25k: (romanian25kWords, [",", ".", "!", "?"])
    case .romanian50k: (romanian50kWords, [",", ".", "!", "?"])
    case .romanian100k: (romanian100kWords, [",", ".", "!", "?"])
    case .romanian200k: (romanian200kWords, [",", ".", "!", "?"])
    case .finnish: (finnishWords, [",", ".", "!", "?"])
    case .finnish1k: (finnish1kWords, [",", ".", "!", "?"])
    case .finnish10k: (finnish10kWords, [",", ".", "!", "?"])
    case .estonian: (estonianWords, [",", ".", "!", "?"])
    case .estonian1k: (estonian1kWords, [",", ".", "!", "?"])
    case .estonian5k: (estonian5kWords, [",", ".", "!", "?"])
    case .estonian10k: (estonian10kWords, [",", ".", "!", "?"])
    case .icelandic: (icelandicWords, [",", ".", "!", "?"])
    case .icelandic1k: (icelandic1kWords, [",", ".", "!", "?"])
    case .french: (frenchWords, [",", ".", "!", "?"])
    case .french1k: (french1kWords, [",", ".", "!", "?"])
    case .french2k: (french2kWords, [",", ".", "!", "?"])
    case .french10k: (french10kWords, [",", ".", "!", "?"])
    case .french600k: (french600kWords, [",", ".", "!", "?"])
    case .frenchBitoduc: (frenchBitoducWords, [",", ".", "!", "?"])
    case .italian: (italianWords, [",", ".", "!", "?"])
    case .italian1k: (italian1kWords, [",", ".", "!", "?"])
    case .italian7k: (italian7kWords, [",", ".", "!", "?"])
    case .italian60k: (italian60kWords, [",", ".", "!", "?"])
    case .italian280k: (italian280kWords, [",", ".", "!", "?"])
    case .portuguese: (portugueseWords, [",", ".", "!", "?"])
    case .portuguese1k: (portuguese1kWords, [",", ".", "!", "?"])
    case .portuguese3k: (portuguese3kWords, [",", ".", "!", "?"])
    case .portuguese5k: (portuguese5kWords, [",", ".", "!", "?"])
    case .portuguese320k: (portuguese320kWords, [",", ".", "!", "?"])
    case .portuguese550k: (portuguese550kWords, [",", ".", "!", "?"])
    case .portugueseAccents: (portugueseAccentsWords, [",", ".", "!", "?"])
    case .simplifiedChinese: (simplifiedChineseWords, ["，", "。", "！", "？"])
    case .simplifiedChinese1k: (simplifiedChinese1kWords, ["，", "。", "！", "？"])
    case .simplifiedChinese5k: (simplifiedChinese5kWords, ["，", "。", "！", "？"])
    case .simplifiedChinese10k: (simplifiedChinese10kWords, ["，", "。", "！", "？"])
    case .simplifiedChinese50k: (simplifiedChinese50kWords, ["，", "。", "！", "？"])
    case .traditionalChinese: (traditionalChineseWords, ["，", "。", "！", "？"])
    case .traditionalChinese1k: (traditionalChinese1kWords, ["，", "。", "！", "？"])
    case .traditionalChinese5k: (traditionalChinese5kWords, ["，", "。", "！", "？"])
    case .traditionalChinese10k: (traditionalChinese10kWords, ["，", "。", "！", "？"])
    case .traditionalChinese50k: (traditionalChinese50kWords, ["，", "。", "！", "？"])
    case .russian: (russianWords, [".", ",", "!", "?"])
    case .russian1k: (russian1kWords, [".", ",", "!", "?"])
    case .russian5k: (russian5kWords, [".", ",", "!", "?"])
    case .russian10k: (russian10kWords, [".", ",", "!", "?"])
    case .russian25k: (russian25kWords, [".", ",", "!", "?"])
    case .russian50k: (russian50kWords, [".", ",", "!", "?"])
    case .russian375k: (russian375kWords, [".", ",", "!", "?"])
    case .russianAbbreviations: (russianAbbreviationWords, [".", ",", "!", "?"])
    case .russianContractions: (russianShortFormTokens, [".", ",", "!", "?"])
    case .russianContractions1k: (russianShortForm1kTokens, [".", ",", "!", "?"])
    case .ukrainian: (ukrainianWords, [".", ",", "!", "?"])
    case .ukrainian1k: (ukrainian1kWords, [".", ",", "!", "?"])
    case .ukrainian10k: (ukrainian10kWords, [".", ",", "!", "?"])
    case .ukrainian50k: (ukrainian50kWords, [".", ",", "!", "?"])
    case .ukrainianEndings: (ukrainianEndingWords, [".", ",", "!", "?"])
    case .ukrainianLatin: (ukrainianLatinWords, [".", ",", "!", "?"])
    case .ukrainianLatynka1k: (ukrainianLatynka1kWords, [".", ",", "!", "?"])
    case .ukrainianLatynka10k: (ukrainianLatynka10kWords, [".", ",", "!", "?"])
    case .ukrainianLatynka50k: (ukrainianLatynka50kWords, [".", ",", "!", "?"])
    case .ukrainianLatynkaEndings: (ukrainianLatynkaEndingWords, [".", ",", "!", "?"])
    case .japaneseHiragana: (japaneseHiraganaWords, ["、", "。", "！", "？"])
    case .japaneseKatakana: (japaneseKatakanaWords, ["、", "。", "！", "？"])
    case .japaneseRomaji: (japaneseRomajiWords, ["、", "。", "！", "？"])
    case .korean: (koreanWords, [".", ",", "!", "?"])
    case .korean1k: (korean1kWords, [".", ",", "!", "?"])
    case .korean5k: (korean5kWords, [".", ",", "!", "?"])
    case .turkish: (turkishWords, [".", ",", "!", "?"])
    case .turkish1k: (turkish1kWords, [".", ",", "!", "?"])
    case .turkish5k: (turkish5kWords, [".", ",", "!", "?"])
    case .polish: (polishWords, [".", ",", "!", "?"])
    case .polish2k: (polish2kWords, [".", ",", "!", "?"])
    case .polish5k: (polish5kWords, [".", ",", "!", "?"])
    case .polish10k: (polish10kWords, [".", ",", "!", "?"])
    case .polish20k: (polish20kWords, [".", ",", "!", "?"])
    case .polish40k: (polish40kWords, [".", ",", "!", "?"])
    case .polish200k: (polish200kWords, [".", ",", "!", "?"])
    default:
      (words, [",", ".", "!", "?"])
    }
  }

  static func punctuation(for language: TypingLanguage, englishVariant: EnglishVariant) -> [String] {
    source(for: language, englishVariant: englishVariant).1
  }

  private static func decoratedToken(
    from lexicon: [String], punctuation: [String], index: Int,
    contentOptions: ContentOptions, usesZipfFrequency: Bool
  ) -> String {
    decoratedToken(
      from: IndexedLexicon(lexicon), punctuation: punctuation, index: index,
      contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
  }

  private static func decoratedToken(
    from lexicon: IndexedLexicon, punctuation: [String], index: Int, contentOptions: ContentOptions,
    usesZipfFrequency: Bool
  ) -> String {
    let tokenIndex = usesZipfFrequency
      ? ZipfWordSelection.index(in: lexicon.count)
      : Int.random(in: lexicon.indices)
    if contentOptions.includeNumbers, index.isMultiple(of: 9) {
      // The reference generator replaces a word with an independent number
      // token. Keeping it separate is essential for languages such as
      // Jyutping, whose lexical tone markers are already decimal digits.
      return String(index / 9 + 1)
    }
    // Catalog scale entries retain their own aggregate-shape metadata, which
    // may include whitespace. A generated *word* prompt must nevertheless
    // expose one directly typeable token per requested word: the input engine
    // rejects leading and repeated separators just like the web reference.
    var token = PolyglotTokenPolicy.token(
      from: lexicon[tokenIndex], selectionIndex: tokenIndex)
    if contentOptions.includePunctuation, index.isMultiple(of: 7) {
      token += punctuation[index / 7 % punctuation.count]
    }
    return token
  }
}

enum PolyglotTokenPolicy {
  static func token(from entry: String, selectionIndex: Int) -> String {
    let tokens = entry.split(whereSeparator: \Character.isWhitespace)
    guard !tokens.isEmpty else { return entry }
    return String(tokens[abs(selectionIndex) % tokens.count])
  }
}

/// Samples only the requested entries of a Typebar-owned lexicon. The fixed
/// reference redraws words used in the preceding two positions, with a bounded
/// escape for tiny or degenerate wordsets.
enum RecentWordSelection {
  static func sample(
    from lexicon: IndexedLexicon, previousWords: [String], usesZipfFrequency: Bool,
    random: () -> Double
  ) -> String {
    precondition(!lexicon.isEmpty)
    func draw() -> String {
      let index = usesZipfFrequency
        ? ZipfWordSelection.index(in: lexicon.count, random: random)
        : min(lexicon.count - 1, Int(min(max(random(), 0), 0.999_999_999_999) * Double(lexicon.count)))
      return PolyglotTokenPolicy.token(from: lexicon[index], selectionIndex: index)
    }
    var word = draw()
    var redraws = 0
    while redraws < 100 && previousWords.contains(word.lowercased()) {
      redraws += 1
      word = draw()
    }
    return word
  }
}

/// Samples an ordered, Typebar-authored lexicon so earlier entries occur more often.
/// The weights follow the rank-based Zipf distribution but do not depend on external
/// word lists or the reference implementation's algorithm.
enum ZipfWordSelection {
  static func index(in count: Int, random: () -> Double = { Double.random(in: 0..<1) }) -> Int {
    precondition(count > 0)
    let totalWeight = (1...count).reduce(0.0) { $0 + 1.0 / Double($1) }
    let threshold = min(max(random(), 0), 0.999_999_999) * totalWeight
    var cumulativeWeight = 0.0
    for rank in 1...count {
      cumulativeWeight += 1.0 / Double(rank)
      if threshold < cumulativeWeight { return rank - 1 }
    }
    return count - 1
  }
}

extension TestMode {
  var displayName: String {
    switch self {
    case .time: "时间"
    case .words: "字数"
    case .quote: "引语"
    case .zen: "禅"
    case .custom: "自定义"
    }
  }
}

extension TypingLanguage {
  /// Mirrors the pinned reference's Swiss German word-generator branch for
  /// every visible local prompt, including user-provided custom text.
  func presentationText(_ text: String) -> String {
    rawValue.hasPrefix("swissGerman")
      ? text.replacingOccurrences(of: "ß", with: "ss") : text
  }

  /// Typebar-owned practice words available to local features such as weak
  /// spot drills and the word filter. This never reads a reference word list.
  func ownedPracticeWords(englishVariant: EnglishVariant = .american) -> [String] {
    guard !isCodeLanguage else { return [] }
    return switch self {
    case .english: englishVariant == .british ? StarterLexicon.britishWords : StarterLexicon.words
    case .english1k: StarterLexicon.english1kWords
    case .english5k: StarterLexicon.english5kWords
    case .english10k: StarterLexicon.english10kWords
    case .english25k: StarterLexicon.english25kWords
    case .english450k: StarterLexicon.english450kWords
    case .englishFiveLetter: StarterLexicon.englishFiveLetterWords
    case .englishFiveLetter1k: StarterLexicon.englishFiveLetter1kWords
    case .englishCommonlyMisspelled: StarterLexicon.englishCommonlyMisspelledWords
    case .englishContractions: StarterLexicon.englishContractionWords
    case .englishDoubleLetter: StarterLexicon.englishDoubleLetterWords
    case .englishLegal: StarterLexicon.englishLegalWords
    case .englishMedical: StarterLexicon.englishMedicalWords
    case .englishShakespearean: StarterLexicon.englishShakespeareanWords
    case .oldEnglish: StarterLexicon.oldEnglishWords
    case .kokanu: StarterLexicon.kokanuWords
    case .likanu: StarterLexicon.likanuWords
    case .pigLatin: StarterLexicon.pigLatinWords
    case .spanish: StarterLexicon.spanishWords
    case .spanish1k: StarterLexicon.spanish1kWords
    case .spanish10k: StarterLexicon.spanish10kWords
    case .spanish650k: StarterLexicon.spanish650kWords
    case .german: StarterLexicon.germanWords
    case .german1k: StarterLexicon.german1kWords
    case .german10k: StarterLexicon.german10kWords
    case .german250k: StarterLexicon.german250kWords
    case .swissGerman: StarterLexicon.swissGermanWords
    case .swissGerman1k: StarterLexicon.swissGerman1kWords
    case .swissGerman2k: StarterLexicon.swissGerman2kWords
    case .afrikaans: StarterLexicon.afrikaansWords
    case .afrikaans1k: StarterLexicon.afrikaans1kWords
    case .afrikaans10k: StarterLexicon.afrikaans10kWords
    case .albanian: StarterLexicon.albanianWords
    case .albanian1k: StarterLexicon.albanian1kWords
    case .bemba: StarterLexicon.bembaWords
    case .bosnian: StarterLexicon.bosnianWords
    case .bosnian4k: StarterLexicon.bosnian4kWords
    case .esperanto: StarterLexicon.esperantoWords
    case .esperanto1k: StarterLexicon.esperanto1kWords
    case .esperanto10k: StarterLexicon.esperanto10kWords
    case .esperanto25k: StarterLexicon.esperanto25kWords
    case .esperanto36k: StarterLexicon.esperanto36kWords
    case .esperantoXSystem: StarterLexicon.esperantoXSystemWords
    case .esperantoXSystem1k: StarterLexicon.esperantoXSystem1kWords
    case .esperantoXSystem10k: StarterLexicon.esperantoXSystem10kWords
    case .esperantoXSystem25k: StarterLexicon.esperantoXSystem25kWords
    case .esperantoXSystem36k: StarterLexicon.esperantoXSystem36kWords
    case .esperantoHSystem: StarterLexicon.esperantoHSystemWords
    case .esperantoHSystem1k: StarterLexicon.esperantoHSystem1kWords
    case .esperantoHSystem10k: StarterLexicon.esperantoHSystem10kWords
    case .esperantoHSystem25k: StarterLexicon.esperantoHSystem25kWords
    case .esperantoHSystem36k: StarterLexicon.esperantoHSystem36kWords
    case .latin: StarterLexicon.latinWords
    case .loremIpsum: StarterLexicon.loremIpsumWords
    case .git: StarterLexicon.gitWords
    case .twitchEmotes: StarterLexicon.twitchEmoteWords
    case .typingOfTheDead: StarterLexicon.typingOfTheDeadWords
    case .pokemon1k: StarterLexicon.creatureIndexEntries
    case .arenaStrategy: StarterLexicon.arenaStrategyEntries
    case .friulian: StarterLexicon.friulianWords
    case .malagasy: StarterLexicon.malagasyWords
    case .malagasy1k: StarterLexicon.malagasy1kWords
    case .welsh: StarterLexicon.welshWords
    case .hausa: StarterLexicon.hausaWords
    case .tatar: StarterLexicon.tatarWords
    case .tatar1k: StarterLexicon.tatar1kWords
    case .tatar5k: StarterLexicon.tatar5kWords
    case .tatar9k: StarterLexicon.tatar9kWords
    case .tatarCrimean: StarterLexicon.tatarCrimeanWords
    case .tatarCrimean1k: StarterLexicon.tatarCrimean1kWords
    case .tatarCrimean5k: StarterLexicon.tatarCrimean5kWords
    case .tatarCrimean10k: StarterLexicon.tatarCrimean10kWords
    case .tatarCrimean15k: StarterLexicon.tatarCrimean15kWords
    case .tatarCrimeanCyrillic: StarterLexicon.tatarCrimeanCyrillicWords
    case .tatarCrimeanCyrillic1k: StarterLexicon.tatarCrimeanCyrillic1kWords
    case .tatarCrimeanCyrillic5k: StarterLexicon.tatarCrimeanCyrillic5kWords
    case .tatarCrimeanCyrillic10k: StarterLexicon.tatarCrimeanCyrillic10kWords
    case .tatarCrimeanCyrillic15k: StarterLexicon.tatarCrimeanCyrillic15kWords
    case .klingon: StarterLexicon.klingonWords
    case .klingon1k: StarterLexicon.klingon1kWords
    case .quenya: StarterLexicon.quenyaWords
    case .viossa: StarterLexicon.viossaWords
    case .viossaNjutro: StarterLexicon.viossaNjutroWords
    case .maori: StarterLexicon.maoriWords
    case .lojbanGismu: StarterLexicon.lojbanGismuWords
    case .lojbanCmavo: StarterLexicon.lojbanCmavoWords
    case .uzbek: StarterLexicon.uzbekWords
    case .uzbek1k: StarterLexicon.uzbek1kWords
    case .uzbek70k: StarterLexicon.uzbek70kWords
    case .occitan: StarterLexicon.occitanWords
    case .occitan1k: StarterLexicon.occitan1kWords
    case .occitan2k: StarterLexicon.occitan2kWords
    case .occitan5k: StarterLexicon.occitan5kWords
    case .occitan10k: StarterLexicon.occitan10kWords
    case .oromo: StarterLexicon.oromoWords
    case .oromo1k: StarterLexicon.oromo1kWords
    case .oromo5k: StarterLexicon.oromo5kWords
    case .macedonian: StarterLexicon.macedonianWords
    case .macedonian1k: StarterLexicon.macedonian1kWords
    case .macedonian10k: StarterLexicon.macedonian10kWords
    case .macedonian75k: StarterLexicon.macedonian75kWords
    case .kazakh: StarterLexicon.kazakhWords
    case .kazakh1k: StarterLexicon.kazakh1kWords
    case .vietnamese: StarterLexicon.vietnameseWords
    case .jyutping: StarterLexicon.jyutpingWords
    case .pinyin: StarterLexicon.pinyinWords
    case .bashkir: StarterLexicon.bashkirWords
    case .basque: StarterLexicon.basqueWords
    case .frisian: StarterLexicon.frisianWords
    case .zulu: StarterLexicon.zuluWords
    case .hawaiian: StarterLexicon.hawaiianWords
    case .hawaiian1k: StarterLexicon.hawaiian1kWords
    case .kabyle: StarterLexicon.kabyleWords
    case .kabyle1k: StarterLexicon.kabyle1kWords
    case .kabyle2k: StarterLexicon.kabyle2kWords
    case .kabyle5k: StarterLexicon.kabyle5kWords
    case .kabyle10k: StarterLexicon.kabyle10kWords
    case .maltese: StarterLexicon.malteseWords
    case .tokiPona: StarterLexicon.tokiPonaWords
    case .tokiPonaKuSuli: StarterLexicon.tokiPonaKuSuliWords
    case .tokiPonaKuLili: StarterLexicon.tokiPonaKuLiliWords
    case .xhosa: StarterLexicon.xhosaWords
    case .xhosa3k: StarterLexicon.xhosa3kWords
    case .tibetan: StarterLexicon.tibetanWords
    case .tibetan1k: StarterLexicon.tibetan1kWords
    case .kyrgyz: StarterLexicon.kyrgyzWords
    case .kyrgyz1k: StarterLexicon.kyrgyz1kWords
    case .udmurt: StarterLexicon.udmurtWords
    case .yoruba: StarterLexicon.yorubaWords
    case .swahili: StarterLexicon.swahiliWords
    case .kinyarwanda: StarterLexicon.kinyarwandaWords
    case .shona: StarterLexicon.shonaWords
    case .shona1k: StarterLexicon.shona1kWords
    case .santali: StarterLexicon.santaliWords
    case .yiddish: StarterLexicon.yiddishWords
    case .arabic: StarterLexicon.arabicWords
    case .arabic10k: StarterLexicon.arabic10kWords
    case .arabicEgypt: StarterLexicon.arabicEgyptWords
    case .arabicEgypt1k: StarterLexicon.arabicEgypt1kWords
    case .arabicMorocco: StarterLexicon.arabicMoroccoWords
    case .pashto: StarterLexicon.pashtoWords
    case .sindhi: StarterLexicon.sindhiWords
    case .hebrew: StarterLexicon.hebrewWords
    case .hebrew1k: StarterLexicon.hebrew1kWords
    case .hebrew5k: StarterLexicon.hebrew5kWords
    case .hebrew10k: StarterLexicon.hebrew10kWords
    case .persian: StarterLexicon.persianWords
    case .persian1k: StarterLexicon.persian1kWords
    case .persian5k: StarterLexicon.persian5kWords
    case .persian20k: StarterLexicon.persian20kWords
    case .persianRomanized: StarterLexicon.persianRomanizedWords
    case .urdu: StarterLexicon.urduWords
    case .urdu1k: StarterLexicon.urdu1kWords
    case .urdu5k: StarterLexicon.urdu5kWords
    case .urduRoman: StarterLexicon.urduRomanWords
    case .urdish: StarterLexicon.urdishWords
    case .tamil: StarterLexicon.tamilWords
    case .tamil1k: StarterLexicon.tamil1kWords
    case .tamilOld: StarterLexicon.tamilOldWords
    case .tanglish: StarterLexicon.tanglishWords
    case .hindi: StarterLexicon.hindiWords
    case .hindi1k: StarterLexicon.hindi1kWords
    case .hinglish: StarterLexicon.hinglishWords
    case .gujarati: StarterLexicon.gujaratiWords
    case .gujarati1k: StarterLexicon.gujarati1kWords
    case .bangla: StarterLexicon.banglaWords
    case .bangla10k: StarterLexicon.bangla10kWords
    case .banglaLetters: StarterLexicon.banglaLetterWords
    case .thai: StarterLexicon.thaiWords
    case .thai1k: StarterLexicon.thai1kWords
    case .thai5k: StarterLexicon.thai5kWords
    case .thai10k: StarterLexicon.thai10kWords
    case .thai20k: StarterLexicon.thai20kWords
    case .thai50k: StarterLexicon.thai50kWords
    case .thai60k: StarterLexicon.thai60kWords
    case .nepali: StarterLexicon.nepaliWords
    case .nepali1k: StarterLexicon.nepali1kWords
    case .nepaliRomanized: StarterLexicon.nepaliRomanizedWords
    case .kannada: StarterLexicon.kannadaWords
    case .telugu: StarterLexicon.teluguWords
    case .telugu1k: StarterLexicon.telugu1kWords
    case .malayalam: StarterLexicon.malayalamWords
    case .sanskrit: StarterLexicon.sanskritWords
    case .sanskritRoman: StarterLexicon.sanskritRomanWords
    case .sinhala: StarterLexicon.sinhalaWords
    case .khmer: StarterLexicon.khmerWords
    case .myanmarBurmese: StarterLexicon.myanmarBurmeseWords
    case .lao: StarterLexicon.laoWords
    case .amharic: StarterLexicon.amharicWords
    case .amharic1k: StarterLexicon.amharic1kWords
    case .amharic5k: StarterLexicon.amharic5kWords
    case .armenian: StarterLexicon.armenianWords
    case .armenian1k: StarterLexicon.armenian1kWords
    case .armenianWestern: StarterLexicon.armenianWesternWords
    case .armenianWestern1k: StarterLexicon.armenianWestern1kWords
    case .georgian: StarterLexicon.georgianWords
    case .azerbaijani: StarterLexicon.azerbaijaniWords
    case .azerbaijani1k: StarterLexicon.azerbaijani1kWords
    case .belarusian: StarterLexicon.belarusianWords
    case .belarusian1k: StarterLexicon.belarusian1kWords
    case .belarusian5k: StarterLexicon.belarusian5kWords
    case .belarusian10k: StarterLexicon.belarusian10kWords
    case .belarusian25k: StarterLexicon.belarusian25kWords
    case .belarusian50k: StarterLexicon.belarusian50kWords
    case .belarusian100k: StarterLexicon.belarusian100kWords
    case .belarusianLacinka: StarterLexicon.belarusianLacinkaWords
    case .belarusianLacinka1k: StarterLexicon.belarusianLacinka1kWords
    case .lithuanian: StarterLexicon.lithuanianWords
    case .latvian: StarterLexicon.latvianWords
    case .mongolian: StarterLexicon.mongolianWords
    case .mongolian10k: StarterLexicon.mongolian10kWords
    case .irish: StarterLexicon.irishWords
    case .galician: StarterLexicon.galicianWords
    case .marathi: StarterLexicon.marathiWords
    case .kurdishCentral: StarterLexicon.kurdishCentralWords
    case .kurdishCentral2k: StarterLexicon.kurdishCentral2kWords
    case .kurdishCentral4k: StarterLexicon.kurdishCentral4kWords
    case .greek: StarterLexicon.greekWords
    case .greek1k: StarterLexicon.greek1kWords
    case .greek5k: StarterLexicon.greek5kWords
    case .greek10k: StarterLexicon.greek10kWords
    case .greek25k: StarterLexicon.greek25kWords
    case .greekKoine: StarterLexicon.greekKoineWords
    case .greeklish: StarterLexicon.greeklishWords
    case .greeklish1k: StarterLexicon.greeklish1kWords
    case .greeklish5k: StarterLexicon.greeklish5kWords
    case .greeklish10k: StarterLexicon.greeklish10kWords
    case .greeklish25k: StarterLexicon.greeklish25kWords
    case .dutch: StarterLexicon.dutchWords
    case .dutch1k: StarterLexicon.dutch1kWords
    case .dutch10k: StarterLexicon.dutch10kWords
    case .filipino: StarterLexicon.filipinoWords
    case .catalan: StarterLexicon.catalanWords
    case .indonesian: StarterLexicon.indonesianWords
    case .indonesian1k: StarterLexicon.indonesian1kWords
    case .indonesian10k: StarterLexicon.indonesian10kWords
    case .malay: StarterLexicon.malayWords
    case .malay1k: StarterLexicon.malay1kWords
    case .danish: StarterLexicon.danishWords
    case .danish1k: StarterLexicon.danish1kWords
    case .danish10k: StarterLexicon.danish10kWords
    case .norwegianBokmal: StarterLexicon.norwegianBokmalWords
    case .norwegianBokmal1k: StarterLexicon.norwegianBokmal1kWords
    case .norwegianBokmal5k: StarterLexicon.norwegianBokmal5kWords
    case .norwegianBokmal10k: StarterLexicon.norwegianBokmal10kWords
    case .norwegianBokmal150k: StarterLexicon.norwegianBokmal150kWords
    case .norwegianBokmal600k: StarterLexicon.norwegianBokmal600kWords
    case .norwegianNynorsk: StarterLexicon.norwegianNynorskWords
    case .norwegianNynorsk1k: StarterLexicon.norwegianNynorsk1kWords
    case .norwegianNynorsk5k: StarterLexicon.norwegianNynorsk5kWords
    case .norwegianNynorsk10k: StarterLexicon.norwegianNynorsk10kWords
    case .norwegianNynorsk100k: StarterLexicon.norwegianNynorsk100kWords
    case .norwegianNynorsk400k: StarterLexicon.norwegianNynorsk400kWords
    case .swedish: StarterLexicon.swedishWords
    case .swedish1k: StarterLexicon.swedish1kWords
    case .swedishDiacritics: StarterLexicon.swedishDiacriticsWords
    case .hungarian: StarterLexicon.hungarianWords
    case .czech: StarterLexicon.czechWords
    case .czech1k: StarterLexicon.czech1kWords
    case .czech10k: StarterLexicon.czech10kWords
    case .slovak: StarterLexicon.slovakWords
    case .slovak1k: StarterLexicon.slovak1kWords
    case .slovak10k: StarterLexicon.slovak10kWords
    case .slovenian: StarterLexicon.slovenianWords
    case .slovenian1k: StarterLexicon.slovenian1kWords
    case .slovenian5k: StarterLexicon.slovenian5kWords
    case .croatian: StarterLexicon.croatianWords
    case .croatian1k: StarterLexicon.croatian1kWords
    case .serbian: StarterLexicon.serbianWords
    case .serbian10k: StarterLexicon.serbian10kWords
    case .serbianLatin: StarterLexicon.serbianLatinWords
    case .serbianLatin10k: StarterLexicon.serbianLatin10kWords
    case .bulgarian: StarterLexicon.bulgarianWords
    case .bulgarian1k: StarterLexicon.bulgarian1kWords
    case .bulgarianLatin: StarterLexicon.bulgarianLatinWords
    case .bulgarianLatin1k: StarterLexicon.bulgarianLatin1kWords
    case .romanian: StarterLexicon.romanianWords
    case .romanian1k: StarterLexicon.romanian1kWords
    case .romanian5k: StarterLexicon.romanian5kWords
    case .romanian10k: StarterLexicon.romanian10kWords
    case .romanian25k: StarterLexicon.romanian25kWords
    case .romanian50k: StarterLexicon.romanian50kWords
    case .romanian100k: StarterLexicon.romanian100kWords
    case .romanian200k: StarterLexicon.romanian200kWords
    case .finnish: StarterLexicon.finnishWords
    case .finnish1k: StarterLexicon.finnish1kWords
    case .finnish10k: StarterLexicon.finnish10kWords
    case .estonian: StarterLexicon.estonianWords
    case .estonian1k: StarterLexicon.estonian1kWords
    case .estonian5k: StarterLexicon.estonian5kWords
    case .estonian10k: StarterLexicon.estonian10kWords
    case .icelandic: StarterLexicon.icelandicWords
    case .icelandic1k: StarterLexicon.icelandic1kWords
    case .french: StarterLexicon.frenchWords
    case .french1k: StarterLexicon.french1kWords
    case .french2k: StarterLexicon.french2kWords
    case .french10k: StarterLexicon.french10kWords
    case .french600k: StarterLexicon.french600kWords
    case .frenchBitoduc: StarterLexicon.frenchBitoducWords
    case .italian: StarterLexicon.italianWords
    case .italian1k: StarterLexicon.italian1kWords
    case .italian7k: StarterLexicon.italian7kWords
    case .italian60k: StarterLexicon.italian60kWords
    case .italian280k: StarterLexicon.italian280kWords
    case .portuguese: StarterLexicon.portugueseWords
    case .portuguese1k: StarterLexicon.portuguese1kWords
    case .portuguese3k: StarterLexicon.portuguese3kWords
    case .portuguese5k: StarterLexicon.portuguese5kWords
    case .portuguese320k: StarterLexicon.portuguese320kWords
    case .portuguese550k: StarterLexicon.portuguese550kWords
    case .portugueseAccents: StarterLexicon.portugueseAccentsWords
    case .simplifiedChinese: StarterLexicon.simplifiedChineseWords
    case .simplifiedChinese1k: StarterLexicon.simplifiedChinese1kWords
    case .simplifiedChinese5k: StarterLexicon.simplifiedChinese5kWords
    case .simplifiedChinese10k: StarterLexicon.simplifiedChinese10kWords
    case .simplifiedChinese50k: StarterLexicon.simplifiedChinese50kWords
    case .traditionalChinese: StarterLexicon.traditionalChineseWords
    case .traditionalChinese1k: StarterLexicon.traditionalChinese1kWords
    case .traditionalChinese5k: StarterLexicon.traditionalChinese5kWords
    case .traditionalChinese10k: StarterLexicon.traditionalChinese10kWords
    case .traditionalChinese50k: StarterLexicon.traditionalChinese50kWords
    case .russian: StarterLexicon.russianWords
    case .russian1k: StarterLexicon.russian1kWords
    case .russian5k: StarterLexicon.russian5kWords
    case .russian10k: StarterLexicon.russian10kWords
    case .russian25k: StarterLexicon.russian25kWords
    case .russian50k: StarterLexicon.russian50kWords
    case .russian375k: StarterLexicon.russian375kWords
    case .russianAbbreviations: StarterLexicon.russianAbbreviationWords
    case .russianContractions: StarterLexicon.russianShortFormWords
    case .russianContractions1k: StarterLexicon.russianShortForm1kWords
    case .ukrainian: StarterLexicon.ukrainianWords
    case .ukrainian1k: StarterLexicon.ukrainian1kWords
    case .ukrainian10k: StarterLexicon.ukrainian10kWords
    case .ukrainian50k: StarterLexicon.ukrainian50kWords
    case .ukrainianEndings: StarterLexicon.ukrainianEndingWords
    case .ukrainianLatin: StarterLexicon.ukrainianLatinWords
    case .ukrainianLatynka1k: StarterLexicon.ukrainianLatynka1kWords
    case .ukrainianLatynka10k: StarterLexicon.ukrainianLatynka10kWords
    case .ukrainianLatynka50k: StarterLexicon.ukrainianLatynka50kWords
    case .ukrainianLatynkaEndings: StarterLexicon.ukrainianLatynkaEndingWords
    case .japaneseHiragana: StarterLexicon.japaneseHiraganaWords
    case .japaneseKatakana: StarterLexicon.japaneseKatakanaWords
    case .japaneseRomaji: StarterLexicon.japaneseRomajiWords
    case .japaneseRomaji1k: StarterLexicon.japaneseRomaji1kWords
    case .korean: StarterLexicon.koreanWords
    case .korean1k: StarterLexicon.korean1kWords
    case .korean5k: StarterLexicon.korean5kWords
    case .turkish: StarterLexicon.turkishWords
    case .turkish1k: StarterLexicon.turkish1kWords
    case .turkish5k: StarterLexicon.turkish5kWords
    case .polish: StarterLexicon.polishWords
    case .polish2k: StarterLexicon.polish2kWords
    case .polish5k: StarterLexicon.polish5kWords
    case .polish10k: StarterLexicon.polish10kWords
    case .polish20k: StarterLexicon.polish20kWords
    case .polish40k: StarterLexicon.polish40kWords
    case .polish200k: StarterLexicon.polish200kWords
    case .irish1k: StarterLexicon.irish1kWords
    case .filipino1k: StarterLexicon.filipino1kWords
    case .hungarian1k: StarterLexicon.hungarian1kWords
    case .hungarian2k: StarterLexicon.hungarian2kWords
    case .welsh1k: StarterLexicon.welsh1kWords
    case .lithuanian1k: StarterLexicon.lithuanian1kWords
    case .lithuanian3k: StarterLexicon.lithuanian3kWords
    case .latvian1k: StarterLexicon.latvian1kWords
    case .maltese1k: StarterLexicon.maltese1kWords
    case .vietnamese1k: StarterLexicon.vietnamese1kWords
    case .vietnamese5k: StarterLexicon.vietnamese5kWords
    case .pinyin1k: StarterLexicon.pinyin1kWords
    case .pinyin10k: StarterLexicon.pinyin10kWords
    case .hausa1k: StarterLexicon.hausa1kWords
    case .bemba1k: StarterLexicon.bemba1kWords
    case .bemba10k: StarterLexicon.bemba10kWords
    case .catalan1k: StarterLexicon.catalan1kWords
    case .frisian1k: StarterLexicon.frisian1kWords
    case .mixedEnglishChinese: StarterLexicon.words
    case .mixedLanguages: []
    default: []
    }
  }

  var supportsLocalWordFilter: Bool {
    supportsQuotes
  }

  func ownedPracticeLexicon(englishVariant: EnglishVariant = .american) -> IndexedLexicon {
    switch self {
    case .amharic1k: StarterLexicon.amharic1kLexicon
    case .amharic5k: StarterLexicon.amharic5kLexicon
    case .armenian1k: StarterLexicon.armenian1kLexicon
    case .armenianWestern1k: StarterLexicon.armenianWestern1kLexicon
    case .belarusianLacinka1k: StarterLexicon.belarusianLacinka1kLexicon
    case .hawaiian1k: StarterLexicon.hawaiian1kLexicon
    case .japaneseRomaji1k: StarterLexicon.japaneseRomaji1kLexicon
    case .klingon1k: StarterLexicon.klingon1kLexicon
    case .oromo1k: StarterLexicon.oromo1kLexicon
    case .oromo5k: StarterLexicon.oromo5kLexicon
    case .shona1k: StarterLexicon.shona1kLexicon
    case .tibetan1k: StarterLexicon.tibetan1kLexicon
    case .englishFiveLetter1k: StarterLexicon.englishFiveLetter1kLexicon
    case .xhosa3k: StarterLexicon.xhosa3kLexicon
    case .albanian1k: StarterLexicon.albanian1kLexicon
    case .bosnian4k: StarterLexicon.bosnian4kLexicon
    case .macedonian1k: StarterLexicon.macedonian1kLexicon
    case .macedonian10k: StarterLexicon.macedonian10kLexicon
    case .macedonian75k: StarterLexicon.macedonian75kLexicon
    case .serbian10k: StarterLexicon.serbian10kLexicon
    case .serbianLatin10k: StarterLexicon.serbianLatin10kLexicon
    case .bulgarian1k: StarterLexicon.bulgarian1kLexicon
    case .bulgarianLatin1k: StarterLexicon.bulgarianLatin1kLexicon
    case .arabic10k: StarterLexicon.arabic10kLexicon
    case .arabicEgypt1k: StarterLexicon.arabicEgypt1kLexicon
    case .azerbaijani1k: StarterLexicon.azerbaijani1kLexicon
    case .korean1k: StarterLexicon.korean1kLexicon
    case .malagasy1k: StarterLexicon.malagasy1kLexicon
    case .malay1k: StarterLexicon.malay1kLexicon
    case .nepali1k: StarterLexicon.nepali1kLexicon
    case .korean5k: StarterLexicon.korean5kLexicon
    case .mongolian10k: StarterLexicon.mongolian10kLexicon
    case .indonesian1k: StarterLexicon.indonesian1kLexicon
    case .indonesian10k: StarterLexicon.indonesian10kLexicon
    case .swissGerman1k: StarterLexicon.swissGerman1kLexicon
    case .swissGerman2k: StarterLexicon.swissGerman2kLexicon
    case .afrikaans1k: StarterLexicon.afrikaans1kLexicon
    case .afrikaans10k: StarterLexicon.afrikaans10kLexicon
    case .kurdishCentral2k: StarterLexicon.kurdishCentral2kLexicon
    case .kurdishCentral4k: StarterLexicon.kurdishCentral4kLexicon
    case .hebrew1k: StarterLexicon.hebrew1kLexicon
    case .hebrew5k: StarterLexicon.hebrew5kLexicon
    case .hebrew10k: StarterLexicon.hebrew10kLexicon
    case .persian1k: StarterLexicon.persian1kLexicon
    case .persian5k: StarterLexicon.persian5kLexicon
    case .persian20k: StarterLexicon.persian20kLexicon
    case .urdu1k: StarterLexicon.urdu1kLexicon
    case .urdu5k: StarterLexicon.urdu5kLexicon
    case .tamil1k: StarterLexicon.tamil1kLexicon
    case .hindi1k: StarterLexicon.hindi1kLexicon
    case .gujarati1k: StarterLexicon.gujarati1kLexicon
    case .bangla10k: StarterLexicon.bangla10kLexicon
    case .telugu1k: StarterLexicon.telugu1kLexicon
    case .turkish1k: StarterLexicon.turkish1kLexicon
    case .turkish5k: StarterLexicon.turkish5kLexicon
    case .kazakh1k: StarterLexicon.kazakh1kLexicon
    case .kyrgyz1k: StarterLexicon.kyrgyz1kLexicon
    case .tatar1k: StarterLexicon.tatar1kLexicon
    case .tatar5k: StarterLexicon.tatar5kLexicon
    case .tatar9k: StarterLexicon.tatar9kLexicon
    case .uzbek1k: StarterLexicon.uzbek1kLexicon
    case .uzbek70k: StarterLexicon.uzbek70kLexicon
    case .dutch1k: StarterLexicon.dutch1kLexicon
    case .dutch10k: StarterLexicon.dutch10kLexicon
    case .czech1k: StarterLexicon.czech1kLexicon
    case .czech10k: StarterLexicon.czech10kLexicon
    case .slovak1k: StarterLexicon.slovak1kLexicon
    case .slovak10k: StarterLexicon.slovak10kLexicon
    case .slovenian1k: StarterLexicon.slovenian1kLexicon
    case .slovenian5k: StarterLexicon.slovenian5kLexicon
    case .croatian1k: StarterLexicon.croatian1kLexicon
    case .danish1k: StarterLexicon.danish1kLexicon
    case .danish10k: StarterLexicon.danish10kLexicon
    case .swedish1k: StarterLexicon.swedish1kLexicon
    case .finnish1k: StarterLexicon.finnish1kLexicon
    case .finnish10k: StarterLexicon.finnish10kLexicon
    case .estonian1k: StarterLexicon.estonian1kLexicon
    case .estonian5k: StarterLexicon.estonian5kLexicon
    case .estonian10k: StarterLexicon.estonian10kLexicon
    case .icelandic1k: StarterLexicon.icelandic1kLexicon
    case .irish1k: StarterLexicon.irish1kLexicon
    case .filipino1k: StarterLexicon.filipino1kLexicon
    case .hungarian1k: StarterLexicon.hungarian1kLexicon
    case .hungarian2k: StarterLexicon.hungarian2kLexicon
    case .welsh1k: StarterLexicon.welsh1kLexicon
    case .lithuanian1k: StarterLexicon.lithuanian1kLexicon
    case .lithuanian3k: StarterLexicon.lithuanian3kLexicon
    case .latvian1k: StarterLexicon.latvian1kLexicon
    case .maltese1k: StarterLexicon.maltese1kLexicon
    case .vietnamese1k: StarterLexicon.vietnamese1kLexicon
    case .vietnamese5k: StarterLexicon.vietnamese5kLexicon
    case .pinyin1k: StarterLexicon.pinyin1kLexicon
    case .pinyin10k: StarterLexicon.pinyin10kLexicon
    case .hausa1k: StarterLexicon.hausa1kLexicon
    case .bemba1k: StarterLexicon.bemba1kLexicon
    case .bemba10k: StarterLexicon.bemba10kLexicon
    case .catalan1k: StarterLexicon.catalan1kLexicon
    case .frisian1k: StarterLexicon.frisian1kLexicon
    case .ukrainian1k: StarterLexicon.ukrainian1kLexicon
    case .ukrainian10k: StarterLexicon.ukrainian10kLexicon
    case .ukrainian50k: StarterLexicon.ukrainian50kLexicon
    case .ukrainianLatynka1k: StarterLexicon.ukrainianLatynka1kLexicon
    case .ukrainianLatynka10k: StarterLexicon.ukrainianLatynka10kLexicon
    case .ukrainianLatynka50k: StarterLexicon.ukrainianLatynka50kLexicon
    case .thai1k: StarterLexicon.thai1kLexicon
    case .thai5k: StarterLexicon.thai5kLexicon
    case .thai10k: StarterLexicon.thai10kLexicon
    case .thai20k: StarterLexicon.thai20kLexicon
    case .thai50k: StarterLexicon.thai50kLexicon
    case .thai60k: StarterLexicon.thai60kLexicon
    case .norwegianBokmal1k: StarterLexicon.norwegianBokmal1kLexicon
    case .norwegianBokmal5k: StarterLexicon.norwegianBokmal5kLexicon
    case .norwegianBokmal10k: StarterLexicon.norwegianBokmal10kLexicon
    case .norwegianBokmal150k: StarterLexicon.norwegianBokmal150kLexicon
    case .norwegianBokmal600k: StarterLexicon.norwegianBokmal600kLexicon
    case .norwegianNynorsk1k: StarterLexicon.norwegianNynorsk1kLexicon
    case .norwegianNynorsk5k: StarterLexicon.norwegianNynorsk5kLexicon
    case .norwegianNynorsk10k: StarterLexicon.norwegianNynorsk10kLexicon
    case .norwegianNynorsk100k: StarterLexicon.norwegianNynorsk100kLexicon
    case .norwegianNynorsk400k: StarterLexicon.norwegianNynorsk400kLexicon
    case .simplifiedChinese1k: StarterLexicon.simplifiedChinese1kLexicon
    case .simplifiedChinese5k: StarterLexicon.simplifiedChinese5kLexicon
    case .simplifiedChinese10k: StarterLexicon.simplifiedChinese10kLexicon
    case .simplifiedChinese50k: StarterLexicon.simplifiedChinese50kLexicon
    case .traditionalChinese1k: StarterLexicon.traditionalChinese1kLexicon
    case .traditionalChinese5k: StarterLexicon.traditionalChinese5kLexicon
    case .traditionalChinese10k: StarterLexicon.traditionalChinese10kLexicon
    case .traditionalChinese50k: StarterLexicon.traditionalChinese50kLexicon
    case .english1k: StarterLexicon.english1kLexicon
    case .english5k: StarterLexicon.english5kLexicon
    case .english10k: StarterLexicon.english10kLexicon
    case .english25k: StarterLexicon.english25kLexicon
    case .english450k: StarterLexicon.english450kLexicon
    case .spanish1k: StarterLexicon.spanish1kLexicon
    case .spanish10k: StarterLexicon.spanish10kLexicon
    case .spanish650k: StarterLexicon.spanish650kLexicon
    case .french1k: StarterLexicon.french1kLexicon
    case .french2k: StarterLexicon.french2kLexicon
    case .french10k: StarterLexicon.french10kLexicon
    case .french600k: StarterLexicon.french600kLexicon
    case .german1k: StarterLexicon.german1kLexicon
    case .german10k: StarterLexicon.german10kLexicon
    case .german250k: StarterLexicon.german250kLexicon
    case .romanian1k: StarterLexicon.romanian1kLexicon
    case .romanian5k: StarterLexicon.romanian5kLexicon
    case .romanian10k: StarterLexicon.romanian10kLexicon
    case .romanian25k: StarterLexicon.romanian25kLexicon
    case .romanian50k: StarterLexicon.romanian50kLexicon
    case .romanian100k: StarterLexicon.romanian100kLexicon
    case .romanian200k: StarterLexicon.romanian200kLexicon
    case .polish2k: StarterLexicon.polish2kLexicon
    case .polish5k: StarterLexicon.polish5kLexicon
    case .polish10k: StarterLexicon.polish10kLexicon
    case .polish20k: StarterLexicon.polish20kLexicon
    case .polish40k: StarterLexicon.polish40kLexicon
    case .polish200k: StarterLexicon.polish200kLexicon
    case .belarusian1k: StarterLexicon.belarusian1kLexicon
    case .belarusian5k: StarterLexicon.belarusian5kLexicon
    case .belarusian10k: StarterLexicon.belarusian10kLexicon
    case .belarusian25k: StarterLexicon.belarusian25kLexicon
    case .belarusian50k: StarterLexicon.belarusian50kLexicon
    case .belarusian100k: StarterLexicon.belarusian100kLexicon
    case .russian1k: StarterLexicon.russian1kLexicon
    case .russian5k: StarterLexicon.russian5kLexicon
    case .russian10k: StarterLexicon.russian10kLexicon
    case .russian25k: StarterLexicon.russian25kLexicon
    case .russian50k: StarterLexicon.russian50kLexicon
    case .russian375k: StarterLexicon.russian375kLexicon
    case .portuguese1k: StarterLexicon.portuguese1kLexicon
    case .portuguese3k: StarterLexicon.portuguese3kLexicon
    case .portuguese5k: StarterLexicon.portuguese5kLexicon
    case .portuguese320k: StarterLexicon.portuguese320kLexicon
    case .portuguese550k: StarterLexicon.portuguese550kLexicon
    case .italian1k: StarterLexicon.italian1kLexicon
    case .italian7k: StarterLexicon.italian7kLexicon
    case .italian60k: StarterLexicon.italian60kLexicon
    case .italian280k: StarterLexicon.italian280kLexicon
    case .esperanto1k: StarterLexicon.esperanto1kLexicon
    case .esperanto10k: StarterLexicon.esperanto10kLexicon
    case .esperanto25k: StarterLexicon.esperanto25kLexicon
    case .esperanto36k: StarterLexicon.esperanto36kLexicon
    case .esperantoXSystem1k: StarterLexicon.esperantoXSystem1kLexicon
    case .esperantoXSystem10k: StarterLexicon.esperantoXSystem10kLexicon
    case .esperantoXSystem25k: StarterLexicon.esperantoXSystem25kLexicon
    case .esperantoXSystem36k: StarterLexicon.esperantoXSystem36kLexicon
    case .esperantoHSystem1k: StarterLexicon.esperantoHSystem1kLexicon
    case .esperantoHSystem10k: StarterLexicon.esperantoHSystem10kLexicon
    case .esperantoHSystem25k: StarterLexicon.esperantoHSystem25kLexicon
    case .esperantoHSystem36k: StarterLexicon.esperantoHSystem36kLexicon
    case .greek1k: StarterLexicon.greek1kLexicon
    case .greek5k: StarterLexicon.greek5kLexicon
    case .greek10k: StarterLexicon.greek10kLexicon
    case .greek25k: StarterLexicon.greek25kLexicon
    case .greeklish1k: StarterLexicon.greeklish1kLexicon
    case .greeklish5k: StarterLexicon.greeklish5kLexicon
    case .greeklish10k: StarterLexicon.greeklish10kLexicon
    case .greeklish25k: StarterLexicon.greeklish25kLexicon
    case .tatarCrimean1k: StarterLexicon.tatarCrimean1kLexicon
    case .tatarCrimean5k: StarterLexicon.tatarCrimean5kLexicon
    case .tatarCrimean10k: StarterLexicon.tatarCrimean10kLexicon
    case .tatarCrimean15k: StarterLexicon.tatarCrimean15kLexicon
    case .tatarCrimeanCyrillic1k: StarterLexicon.tatarCrimeanCyrillic1kLexicon
    case .tatarCrimeanCyrillic5k: StarterLexicon.tatarCrimeanCyrillic5kLexicon
    case .tatarCrimeanCyrillic10k: StarterLexicon.tatarCrimeanCyrillic10kLexicon
    case .tatarCrimeanCyrillic15k: StarterLexicon.tatarCrimeanCyrillic15kLexicon
    case .occitan1k: StarterLexicon.occitan1kLexicon
    case .occitan2k: StarterLexicon.occitan2kLexicon
    case .occitan5k: StarterLexicon.occitan5kLexicon
    case .occitan10k: StarterLexicon.occitan10kLexicon
    case .kabyle1k: StarterLexicon.kabyle1kLexicon
    case .kabyle2k: StarterLexicon.kabyle2kLexicon
    case .kabyle5k: StarterLexicon.kabyle5kLexicon
    case .kabyle10k: StarterLexicon.kabyle10kLexicon
    default: IndexedLexicon(ownedPracticeWords(englishVariant: englishVariant))
    }
  }

  /// Historical broad Typebar preset. Explicitly saved selections keep this
  /// ordering; fresh selections use the pinned reference's four languages.
  static let defaultMixedComponents: [TypingLanguage] = [
    .englishFiveLetter,
    .englishCommonlyMisspelled,
    .englishContractions,
    .englishDoubleLetter,
    .englishLegal,
    .englishMedical,
    .englishShakespearean,
    .oldEnglish,
    .kokanu,
    .likanu,
    .pokemon1k,
    .arenaStrategy,
    .english, .pigLatin, .spanish, .german, .swissGerman, .afrikaans, .albanian, .bemba, .bosnian, .esperanto, .esperantoXSystem, .esperantoHSystem, .latin, .loremIpsum, .git, .twitchEmotes, .typingOfTheDead, .friulian, .malagasy, .welsh, .hausa, .tatar, .tatarCrimean, .tatarCrimeanCyrillic, .klingon, .quenya, .viossa, .viossaNjutro, .maori, .lojbanGismu, .lojbanCmavo, .uzbek, .occitan, .oromo, .macedonian, .kazakh, .vietnamese, .jyutping, .pinyin, .bashkir, .basque, .frisian, .zulu, .hawaiian, .kabyle, .maltese, .tokiPona, .tokiPonaKuSuli, .tokiPonaKuLili, .xhosa, .tibetan, .kyrgyz, .udmurt, .yoruba, .swahili, .kinyarwanda, .shona, .santali, .persianRomanized, .urduRoman, .urdish, .tamil, .tamilOld, .tanglish, .hindi, .hinglish, .gujarati, .bangla, .banglaLetters, .thai, .nepali, .nepaliRomanized, .kannada, .telugu, .malayalam, .sanskrit, .sanskritRoman, .sinhala, .khmer, .myanmarBurmese, .lao, .amharic, .armenian, .armenianWestern, .georgian, .azerbaijani, .belarusian, .belarusianLacinka, .lithuanian, .latvian, .mongolian, .irish, .galician, .marathi, .greek, .greekKoine, .greeklish, .dutch, .filipino, .catalan, .indonesian, .malay, .danish, .norwegianBokmal, .norwegianNynorsk, .swedish, .swedishDiacritics, .hungarian, .czech, .slovak, .slovenian, .croatian, .serbian, .serbianLatin, .bulgarian, .bulgarianLatin, .romanian, .finnish, .estonian, .icelandic, .french,
    .frenchBitoduc, .italian, .portuguese, .portugueseAccents,
    .simplifiedChinese,
    .russianContractions, .russianContractions1k,
    .traditionalChinese, .russian, .russianAbbreviations, .ukrainian, .ukrainianEndings,
    .ukrainianLatin, .ukrainianLatynkaEndings, .japaneseHiragana, .japaneseKatakana,
    .japaneseRomaji,
    .korean, .turkish, .polish,
  ]

  static let referenceDefaultMixedComponents: [TypingLanguage] = [
    .english, .spanish, .french, .german,
  ]

  /// Every fixed-schema single-language choice is available to custom
  /// polyglot practice. The two Typebar aggregate modes are not languages.
  static var mixableLanguages: [TypingLanguage] {
    allCases.filter { $0 != .mixedEnglishChinese && $0 != .mixedLanguages }
  }

  static func filteredMixableLanguages(query: String) -> [TypingLanguage] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    guard !normalized.isEmpty else { return mixableLanguages }
    return mixableLanguages.filter {
      $0.displayName.folding(
        options: [.caseInsensitive, .diacriticInsensitive], locale: .current
      ).contains(normalized)
        || $0.rawValue.folding(
          options: [.caseInsensitive, .diacriticInsensitive], locale: .current
        ).contains(normalized)
    }
  }

  static func normalizedMixedComponents(_ languages: [TypingLanguage]) -> [TypingLanguage] {
    let selected = languages.filter { mixableLanguages.contains($0) }.reduce(
      into: [TypingLanguage]()
    ) { result, language in
      if !result.contains(language) { result.append(language) }
    }
    return selected.count >= 2 ? selected : referenceDefaultMixedComponents
  }

  var usesSpaceDelimitedWords: Bool {
    !isCodeLanguage
  }

  var polyglotPunctuation: [String] {
    if usesCJKWordStream { return ["，", "。", "！", "？"] }
    if usesRightToLeftPrompt { return ["،", "؛", "؟", "."] }
    return [",", ".", "!", "?"]
  }

  /// Right-to-left scripts use the native text system. Polyglot paragraph
  /// direction is derived by `TestConfiguration` from the complete selection.
  var usesRightToLeftPrompt: Bool {
    self == .arabic || self == .arabic10k || self == .arabicEgypt || self == .arabicEgypt1k || self == .arabicMorocco || self == .pashto || self == .sindhi || self == .hebrew || self == .hebrew1k || self == .hebrew5k || self == .hebrew10k || self == .persian || self == .persian1k || self == .persian5k || self == .persian20k || self == .urdu || self == .urdu1k || self == .urdu5k || self == .kurdishCentral || self == .kurdishCentral2k || self == .kurdishCentral4k || self == .yiddish
  }

  /// Preserve native shaping for source-pinned joining scripts.
  var usesJoiningScriptPrompt: Bool {
    switch self {
    case .arabic, .arabic10k, .arabicEgypt, .arabicEgypt1k, .arabicMorocco,
      .bangla, .bangla10k, .banglaLetters, .gujarati, .gujarati1k,
      .hebrew, .hebrew1k, .hebrew5k, .hebrew10k,
      .hindi, .hindi1k, .kannada, .khmer, .korean, .korean1k, .korean5k,
      .kurdishCentral, .kurdishCentral2k, .kurdishCentral4k, .likanu, .malayalam,
      .myanmarBurmese, .nepali, .nepali1k, .pashto, .persian, .persian1k, .persian5k,
      .persian20k, .sanskrit, .sindhi, .sinhala,
      .tamil, .tamil1k, .tamilOld, .telugu, .telugu1k, .tibetan, .tibetan1k,
      .urdu, .urdu1k, .urdu5k, .yiddish:
      true
    default:
      false
    }
  }

  /// Current source-compatible CJK word streams use commit spaces, but this
  /// group remains available to parse pre-migration results and external text.
  var usesCJKWordStream: Bool {
    switch self {
    case .simplifiedChinese, .simplifiedChinese1k, .simplifiedChinese5k,
      .simplifiedChinese10k, .simplifiedChinese50k, .traditionalChinese,
      .traditionalChinese1k, .traditionalChinese5k, .traditionalChinese10k,
      .traditionalChinese50k,
      .japaneseHiragana, .japaneseKatakana: true
    default: false
    }
  }

  var isChineseScale: Bool {
    switch self {
    case .simplifiedChinese1k, .simplifiedChinese5k, .simplifiedChinese10k,
      .simplifiedChinese50k, .traditionalChinese1k, .traditionalChinese5k,
      .traditionalChinese10k, .traditionalChinese50k: true
    default: false
    }
  }

  var isCodeLanguage: Bool {
    self == .dockerFile || rawValue.hasPrefix("code")
  }

  /// The fixed reference normalizes ё/е/e only for the base Russian catalog
  /// and its numeric sizes; specialized Russian catalogs retain literal input.
  var usesRussianYoInputEquivalence: Bool {
    switch self {
    case .russian, .russian1k, .russian5k, .russian10k, .russian25k, .russian50k, .russian375k:
      true
    default:
      false
    }
  }

  /// The fixed reference accepts the system Dutch IJ ligature as two ordinary
  /// letters only for its base Dutch catalog and numeric-size variants.
  var usesDutchLigatureInputExpansion: Bool {
    switch self {
    case .dutch, .dutch1k, .dutch10k:
      true
    default:
      false
    }
  }

  /// Mirrors Monkeytype's `noLazyMode` language metadata for every Typebar
  /// wordset. Code prompts are likewise literal input, never accent-folded.
  var supportsLazyLatinInput: Bool {
    guard !isCodeLanguage else { return false }
    return switch self {
    case .english, .english1k, .english5k, .english10k, .english25k, .english450k,
      .englishFiveLetter1k,
      .englishCommonlyMisspelled, .englishContractions, .englishDoubleLetter,
      .englishMedical,
      .englishShakespearean,
      .pigLatin, .loremIpsum, .git, .twitchEmotes, .typingOfTheDead, .pashto, .hebrew,
      .persian, .persian1k, .persian5k, .persian20k, .persianRomanized,
      .urdu, .urdu1k, .urdu5k,
      .tamil, .tamil1k, .hindi, .hindi1k, .gujarati, .gujarati1k,
      .bangla, .bangla10k, .banglaLetters,
      .thai, .thai1k, .thai5k, .thai10k, .thai20k, .thai50k, .thai60k,
      .nepali, .nepali1k, .kannada, .telugu, .telugu1k, .malayalam,
      .sanskrit, .greeklish, .greeklish1k, .greeklish5k, .greeklish10k,
      .greeklish25k, .dutch, .dutch1k, .dutch10k, .filipino, .filipino1k,
      .indonesian, .indonesian1k, .indonesian10k, .afrikaans1k,
      .serbian, .serbian10k, .bulgarian, .bulgarian1k, .bulgarianLatin,
      .bulgarianLatin1k,
      .khmer,
      .myanmarBurmese,
      .armenian, .armenian1k,
      .georgian,
      .belarusian, .belarusian1k,
      .macedonian, .macedonian1k, .macedonian10k, .macedonian75k,
      .kazakh, .kazakh1k,
      .mongolian, .mongolian10k,
      .marathi,
      .malagasy, .malagasy1k,
      .tokiPona, .tokiPonaKuSuli, .tokiPonaKuLili,
      .tibetan, .tibetan1k,
      .swahili,
      .kinyarwanda,
      .tatarCrimean,
      .tatarCrimean1k, .tatarCrimean5k, .tatarCrimean10k, .tatarCrimean15k,
      .tatarCrimeanCyrillic,
      .tatarCrimeanCyrillic1k, .tatarCrimeanCyrillic5k,
      .tatarCrimeanCyrillic10k, .tatarCrimeanCyrillic15k,
      .viossaNjutro,
      .lojbanGismu,
      .lojbanCmavo,
      .esperantoXSystem, .esperantoXSystem1k, .esperantoXSystem10k,
      .esperantoXSystem25k, .esperantoXSystem36k,
      .esperantoHSystem, .esperantoHSystem1k, .esperantoHSystem10k,
      .esperantoHSystem25k, .esperantoHSystem36k,
      .simplifiedChinese, .simplifiedChinese1k, .simplifiedChinese5k,
      .simplifiedChinese10k, .simplifiedChinese50k, .traditionalChinese,
      .traditionalChinese1k, .traditionalChinese5k, .traditionalChinese10k,
      .traditionalChinese50k,
      .portuguese5k, .portuguese320k, .portuguese550k,
      .russian5k, .russianAbbreviations, .russianContractions, .russianContractions1k,
      .ukrainian, .ukrainian1k, .ukrainian10k, .ukrainian50k, .ukrainianEndings,
      .ukrainianLatin, .ukrainianLatynka1k, .ukrainianLatynka10k, .ukrainianLatynka50k,
      .ukrainianLatynkaEndings,
      .japaneseHiragana, .japaneseKatakana, .japaneseRomaji, .japaneseRomaji1k,
      .korean, .korean1k, .korean5k,
      .mixedEnglishChinese, .mixedLanguages:
      false
    default:
      true
    }
  }

  var supportsCapsLockWarning: Bool {
    switch self {
    case .simplifiedChinese, .simplifiedChinese1k, .simplifiedChinese5k,
      .simplifiedChinese10k, .simplifiedChinese50k, .traditionalChinese,
      .traditionalChinese1k, .traditionalChinese5k, .traditionalChinese10k,
      .traditionalChinese50k,
      .japaneseHiragana, .japaneseKatakana,
      .korean, .korean1k, .korean5k, .nepali1k: false
    default: !isCodeLanguage
    }
  }

  var supportsQuotes: Bool {
    self != .mixedEnglishChinese && self != .mixedLanguages && !isCodeLanguage
  }

  /// The pinned reference excludes Swiss German from community quote
  /// submission and redirects its built-in quote path to German instead.
  var supportsCommunityQuoteSubmission: Bool {
    supportsQuotes && !rawValue.hasPrefix("swissGerman")
  }

  /// Pinned-reference `orderedByFrequency` metadata for the built-in base
  /// wordsets. Dictionaries without that field intentionally remain unknown.
  var zipfFrequencySupport: ZipfFrequencySupport {
    switch self {
    case .english, .english1k, .english5k, .english10k, .bosnian,
      .esperanto, .esperanto1k, .esperanto10k, .esperanto25k, .esperanto36k,
      .esperantoXSystem1k,
      .esperantoHSystem, .esperantoHSystem1k, .esperantoHSystem10k,
      .esperantoHSystem25k, .esperantoHSystem36k,
      .tatar, .tatar1k, .tatar5k, .tatar9k, .oromo, .oromo1k, .oromo5k,
      .bashkir, .hawaiian, .hawaiian1k,
      .slovenian1k, .slovenian5k,
      .kinyarwanda, .tamil, .tamil1k, .kannada, .greeklish,
      .norwegianBokmal, .norwegianBokmal1k, .norwegianBokmal5k,
      .norwegianBokmal10k, .norwegianNynorsk, .norwegianNynorsk1k,
      .norwegianNynorsk5k, .norwegianNynorsk10k,
      .traditionalChinese1k, .traditionalChinese5k, .traditionalChinese10k,
      .traditionalChinese50k,
      .russian, .russian1k, .russian5k, .icelandic, .galician, .marathi:
      return .supported
    case .englishCommonlyMisspelled, .englishContractions, .englishDoubleLetter,
      .englishMedical, .english25k, .english450k, .kokanu, .likanu, .russianAbbreviations, .russianContractions, .russianContractions1k, .typingOfTheDead, .pokemon1k, .arabicMorocco, .sindhi, .armenian, .bemba, .bemba1k, .bemba10k,
      .bulgarian, .bulgarian1k, .bulgarianLatin, .bulgarianLatin1k, .armenian1k,
      .urduRoman, .hungarian, .hungarian1k, .lao,
      .kabyle, .kabyle1k, .kabyle2k, .kabyle5k, .kabyle10k,
      .greeklish1k, .greeklish5k, .greeklish10k, .greeklish25k,
      .viossa, .viossaNjutro:
      return .unsupported
    default:
      return .unknown
    }
  }

  var displayName: String {
    if let codeName = CodeLanguageCatalog.displayNames[self] { return "Code · \(codeName)" }
    return switch self {
    case .english: "English"
    case .english1k: "English · 1k · Typebar"
    case .english5k: "English · 5k · Typebar"
    case .english10k: "English · 10k · Typebar"
    case .english25k: "English · 25k · Typebar"
    case .english450k: "English · 450k · Typebar"
    case .englishFiveLetter: "English · Five Letter"
    case .englishFiveLetter1k: "English · Five Letter · 1k · Typebar"
    case .englishCommonlyMisspelled: "English · Commonly Misspelled"
    case .englishContractions: "English · Contractions"
    case .englishDoubleLetter: "English · Double Letter"
    case .englishLegal: "English · Legal"
    case .englishMedical: "English · Medical"
    case .englishShakespearean: "English · Shakespearean"
    case .oldEnglish: "Old English"
    case .kokanu: "Kokanu"
    case .likanu: "Likanu"
    case .pigLatin: "Pig Latin"
    case .spanish: "Español"
    case .spanish1k: "Español · 1k · Typebar"
    case .spanish10k: "Español · 10k · Typebar"
    case .spanish650k: "Español · 650k · Typebar"
    case .german: "Deutsch"
    case .german1k: "Deutsch · 1k · Typebar"
    case .german10k: "Deutsch · 10k · Typebar"
    case .german250k: "Deutsch · 250k · Typebar"
    case .swissGerman: "Swiss German"
    case .swissGerman1k: "Swiss German · 1k · Typebar"
    case .swissGerman2k: "Swiss German · 2k · Typebar"
    case .afrikaans: "Afrikaans"
    case .afrikaans1k: "Afrikaans · 1k · Typebar"
    case .afrikaans10k: "Afrikaans · 10k · Typebar"
    case .albanian: "Shqip"
    case .albanian1k: "Shqip · 1k · Typebar"
    case .bemba: "Ichibemba"
    case .bemba1k: "Ichibemba · 1k · Typebar"
    case .bemba10k: "Ichibemba · 10k · Typebar"
    case .bosnian: "Bosanski"
    case .bosnian4k: "Bosanski · 4k · Typebar"
    case .esperanto: "Esperanto"
    case .esperanto1k: "Esperanto · 1k · Typebar"
    case .esperanto10k: "Esperanto · 10k · Typebar"
    case .esperanto25k: "Esperanto · 25k · Typebar"
    case .esperanto36k: "Esperanto · 36k · Typebar"
    case .esperantoXSystem: "Esperanto · X-sistemo"
    case .esperantoXSystem1k: "Esperanto · X-sistemo · 1k · Typebar"
    case .esperantoXSystem10k: "Esperanto · X-sistemo · 10k · Typebar"
    case .esperantoXSystem25k: "Esperanto · X-sistemo · 25k · Typebar"
    case .esperantoXSystem36k: "Esperanto · X-sistemo · 36k · Typebar"
    case .esperantoHSystem: "Esperanto · H-sistemo"
    case .esperantoHSystem1k: "Esperanto · H-sistemo · 1k · Typebar"
    case .esperantoHSystem10k: "Esperanto · H-sistemo · 10k · Typebar"
    case .esperantoHSystem25k: "Esperanto · H-sistemo · 25k · Typebar"
    case .esperantoHSystem36k: "Esperanto · H-sistemo · 36k · Typebar"
    case .latin: "Latina"
    case .loremIpsum: "Lorem Ipsum · Typebar"
    case .git: "Git"
    case .twitchEmotes: "Streaming Emotes · Typebar"
    case .typingOfTheDead: "Arcade Horror Phrases · Typebar"
    case .pokemon1k: "Creature Index 1k · Typebar"
    case .arenaStrategy: "Arena Strategy Terms · Typebar"
    case .friulian: "Friulian"
    case .malagasy: "Malagasy"
    case .malagasy1k: "Malagasy · 1k · Typebar"
    case .welsh: "Cymraeg"
    case .welsh1k: "Cymraeg · 1k · Typebar"
    case .hausa: "Hausa"
    case .hausa1k: "Hausa · 1k · Typebar"
    case .tatar: "Татарча"
    case .tatar1k: "Татарча · 1k · Typebar"
    case .tatar5k: "Татарча · 5k · Typebar"
    case .tatar9k: "Татарча · 9k · Typebar"
    case .tatarCrimean: "Qırımtatarca"
    case .tatarCrimean1k: "Qırımtatarca · 1k · Typebar"
    case .tatarCrimean5k: "Qırımtatarca · 5k · Typebar"
    case .tatarCrimean10k: "Qırımtatarca · 10k · Typebar"
    case .tatarCrimean15k: "Qırımtatarca · 15k · Typebar"
    case .tatarCrimeanCyrillic: "Къырымтатарджа"
    case .tatarCrimeanCyrillic1k: "Къырымтатарджа · 1k · Typebar"
    case .tatarCrimeanCyrillic5k: "Къырымтатарджа · 5k · Typebar"
    case .tatarCrimeanCyrillic10k: "Къырымтатарджа · 10k · Typebar"
    case .tatarCrimeanCyrillic15k: "Къырымтатарджа · 15k · Typebar"
    case .klingon: "tlhIngan Hol"
    case .klingon1k: "tlhIngan Hol · 1k · Typebar"
    case .quenya: "Quenya"
    case .viossa: "Viossa"
    case .viossaNjutro: "Viossa · Njutro"
    case .maori: "Te reo Māori"
    case .lojbanGismu: "Lojban · gismu"
    case .lojbanCmavo: "Lojban · cmavo"
    case .uzbek: "Oʻzbekcha"
    case .uzbek1k: "Oʻzbekcha · 1k · Typebar"
    case .uzbek70k: "Oʻzbekcha · 70k · Typebar"
    case .occitan: "Occitan"
    case .occitan1k: "Occitan · 1k · Typebar"
    case .occitan2k: "Occitan · 2k · Typebar"
    case .occitan5k: "Occitan · 5k · Typebar"
    case .occitan10k: "Occitan · 10k · Typebar"
    case .oromo: "Oromo"
    case .oromo1k: "Oromo · 1k · Typebar"
    case .oromo5k: "Oromo · 5k · Typebar"
    case .macedonian: "Македонски"
    case .macedonian1k: "Македонски · 1k · Typebar"
    case .macedonian10k: "Македонски · 10k · Typebar"
    case .macedonian75k: "Македонски · 75k · Typebar"
    case .kazakh: "Қазақша"
    case .kazakh1k: "Қазақша · 1k · Typebar"
    case .vietnamese: "Tiếng Việt"
    case .vietnamese1k: "Tiếng Việt · 1k · Typebar"
    case .vietnamese5k: "Tiếng Việt · 5k · Typebar"
    case .jyutping: "Jyutping"
    case .pinyin: "Pinyin"
    case .pinyin1k: "Pinyin · 1k · Typebar"
    case .pinyin10k: "Pinyin · 10k · Typebar"
    case .bashkir: "Башҡортса"
    case .basque: "Euskara"
    case .frisian: "Frysk"
    case .frisian1k: "Frysk · 1k · Typebar"
    case .zulu: "isiZulu"
    case .hawaiian: "ʻŌlelo Hawaiʻi"
    case .hawaiian1k: "ʻŌlelo Hawaiʻi · 1k · Typebar"
    case .kabyle: "Taqbaylit"
    case .kabyle1k: "Taqbaylit · 1k · Typebar"
    case .kabyle2k: "Taqbaylit · 2k · Typebar"
    case .kabyle5k: "Taqbaylit · 5k · Typebar"
    case .kabyle10k: "Taqbaylit · 10k · Typebar"
    case .maltese: "Malti"
    case .maltese1k: "Malti · 1k · Typebar"
    case .tokiPona: "toki pona"
    case .tokiPonaKuSuli: "toki pona · ku suli"
    case .tokiPonaKuLili: "toki pona · ku lili"
    case .xhosa: "isiXhosa"
    case .xhosa3k: "isiXhosa · 3k · Typebar"
    case .tibetan: "བོད་སྐད་"
    case .tibetan1k: "བོད་སྐད་ · 1k · Typebar"
    case .kyrgyz: "Кыргызча"
    case .kyrgyz1k: "Кыргызча · 1k · Typebar"
    case .udmurt: "Удмурт кыл"
    case .yoruba: "Yorùbá"
    case .swahili: "Kiswahili"
    case .kinyarwanda: "Ikinyarwanda"
    case .shona: "chiShona"
    case .shona1k: "chiShona · 1k · Typebar"
    case .santali: "ᱥᱟᱱᱛᱟᱲᱤ"
    case .yiddish: "ייִדיש"
    case .arabic: "العربية"
    case .arabic10k: "العربية · 10k · Typebar"
    case .arabicEgypt: "العربية المصرية"
    case .arabicEgypt1k: "العربية المصرية · 1k · Typebar"
    case .arabicMorocco: "العربية المغربية"
    case .pashto: "پښتو"
    case .sindhi: "سنڌي"
    case .hebrew: "עברית"
    case .hebrew1k: "עברית · 1k · Typebar"
    case .hebrew5k: "עברית · 5k · Typebar"
    case .hebrew10k: "עברית · 10k · Typebar"
    case .persian: "فارسی"
    case .persian1k: "فارسی · 1k · Typebar"
    case .persian5k: "فارسی · 5k · Typebar"
    case .persian20k: "فارسی · 20k · Typebar"
    case .persianRomanized: "Fârsi (Romanized)"
    case .urdu: "اردو"
    case .urdu1k: "اردو · 1k · Typebar"
    case .urdu5k: "اردو · 5k · Typebar"
    case .urduRoman: "Urdu (Roman)"
    case .urdish: "Urdish"
    case .tamil: "தமிழ்"
    case .tamil1k: "தமிழ் · 1k · Typebar"
    case .tamilOld: "தமிழ் · பழைய தொகுப்பு · Typebar"
    case .tanglish: "Tanglish"
    case .hindi: "हिन्दी"
    case .hindi1k: "हिन्दी · 1k · Typebar"
    case .hinglish: "Hinglish"
    case .gujarati: "ગુજરાતી"
    case .gujarati1k: "ગુજરાતી · 1k · Typebar"
    case .bangla: "বাংলা"
    case .bangla10k: "বাংলা · 10k · Typebar"
    case .banglaLetters: "বাংলা · অক্ষর"
    case .thai: "ไทย"
    case .thai1k: "ไทย · 1k · Typebar"
    case .thai5k: "ไทย · 5k · Typebar"
    case .thai10k: "ไทย · 10k · Typebar"
    case .thai20k: "ไทย · 20k · Typebar"
    case .thai50k: "ไทย · 50k · Typebar"
    case .thai60k: "ไทย · 60k · Typebar"
    case .nepali: "नेपाली"
    case .nepali1k: "नेपाली · 1k · Typebar"
    case .nepaliRomanized: "Nepali (Romanized)"
    case .kannada: "ಕನ್ನಡ"
    case .telugu: "తెలుగు"
    case .telugu1k: "తెలుగు · 1k · Typebar"
    case .malayalam: "മലയാളം"
    case .sanskrit: "संस्कृतम्"
    case .sanskritRoman: "Saṃskṛtam (Roman)"
    case .sinhala: "සිංහල"
    case .khmer: "ខ្មែរ"
    case .myanmarBurmese: "မြန်မာ"
    case .lao: "ລາວ"
    case .amharic: "አማርኛ"
    case .amharic1k: "አማርኛ · 1k · Typebar"
    case .amharic5k: "አማርኛ · 5k · Typebar"
    case .armenian: "Հայերեն"
    case .armenian1k: "Հայերեն · 1k · Typebar"
    case .armenianWestern: "Հայերէն (Արեւմտեան)"
    case .armenianWestern1k: "Հայերէն (Արեւմտեան) · 1k · Typebar"
    case .georgian: "ქართული"
    case .azerbaijani: "Azərbaycanca"
    case .azerbaijani1k: "Azərbaycanca · 1k · Typebar"
    case .belarusian: "Беларуская"
    case .belarusian1k: "Беларуская · 1k · Typebar"
    case .belarusian5k: "Беларуская · 5k · Typebar"
    case .belarusian10k: "Беларуская · 10k · Typebar"
    case .belarusian25k: "Беларуская · 25k · Typebar"
    case .belarusian50k: "Беларуская · 50k · Typebar"
    case .belarusian100k: "Беларуская · 100k · Typebar"
    case .belarusianLacinka: "Biełaruskaja łacinka"
    case .belarusianLacinka1k: "Biełaruskaja łacinka · 1k · Typebar"
    case .lithuanian: "Lietuvių"
    case .lithuanian1k: "Lietuvių · 1k · Typebar"
    case .lithuanian3k: "Lietuvių · 3k · Typebar"
    case .latvian: "Latviešu"
    case .latvian1k: "Latviešu · 1k · Typebar"
    case .mongolian: "Монгол"
    case .mongolian10k: "Монгол · 10k · Typebar"
    case .irish: "Gaeilge"
    case .irish1k: "Gaeilge · 1k · Typebar"
    case .galician: "Galego"
    case .marathi: "मराठी"
    case .kurdishCentral: "کوردی ناوەندی"
    case .kurdishCentral2k: "کوردی ناوەندی · 2k · Typebar"
    case .kurdishCentral4k: "کوردی ناوەندی · 4k · Typebar"
    case .greek: "Ελληνικά"
    case .greek1k: "Ελληνικά · 1k · Typebar"
    case .greek5k: "Ελληνικά · 5k · Typebar"
    case .greek10k: "Ελληνικά · 10k · Typebar"
    case .greek25k: "Ελληνικά · 25k · Typebar"
    case .greekKoine: "Ἑλληνιστικὴ Κοινή"
    case .greeklish: "Greeklish"
    case .greeklish1k: "Greeklish · 1k · Typebar"
    case .greeklish5k: "Greeklish · 5k · Typebar"
    case .greeklish10k: "Greeklish · 10k · Typebar"
    case .greeklish25k: "Greeklish · 25k · Typebar"
    case .dutch: "Nederlands"
    case .dutch1k: "Nederlands · 1k · Typebar"
    case .dutch10k: "Nederlands · 10k · Typebar"
    case .filipino: "Filipino"
    case .filipino1k: "Filipino · 1k · Typebar"
    case .catalan: "Català"
    case .catalan1k: "Català · 1k · Typebar"
    case .indonesian: "Bahasa Indonesia"
    case .indonesian1k: "Bahasa Indonesia · 1k · Typebar"
    case .indonesian10k: "Bahasa Indonesia · 10k · Typebar"
    case .malay: "Bahasa Melayu"
    case .malay1k: "Bahasa Melayu · 1k · Typebar"
    case .danish: "Dansk"
    case .danish1k: "Dansk · 1k · Typebar"
    case .danish10k: "Dansk · 10k · Typebar"
    case .norwegianBokmal: "Norsk bokmål"
    case .norwegianBokmal1k: "Norsk bokmål · 1k · Typebar"
    case .norwegianBokmal5k: "Norsk bokmål · 5k · Typebar"
    case .norwegianBokmal10k: "Norsk bokmål · 10k · Typebar"
    case .norwegianBokmal150k: "Norsk bokmål · 150k · Typebar"
    case .norwegianBokmal600k: "Norsk bokmål · 600k · Typebar"
    case .norwegianNynorsk: "Norsk nynorsk"
    case .norwegianNynorsk1k: "Norsk nynorsk · 1k · Typebar"
    case .norwegianNynorsk5k: "Norsk nynorsk · 5k · Typebar"
    case .norwegianNynorsk10k: "Norsk nynorsk · 10k · Typebar"
    case .norwegianNynorsk100k: "Norsk nynorsk · 100k · Typebar"
    case .norwegianNynorsk400k: "Norsk nynorsk · 400k · Typebar"
    case .swedish: "Svenska"
    case .swedish1k: "Svenska · 1k · Typebar"
    case .swedishDiacritics: "Svenska · Å Ä Ö"
    case .hungarian: "Magyar"
    case .hungarian1k: "Magyar · 1k · Typebar"
    case .hungarian2k: "Magyar · 2k · Typebar"
    case .czech: "Čeština"
    case .czech1k: "Čeština · 1k · Typebar"
    case .czech10k: "Čeština · 10k · Typebar"
    case .slovak: "Slovenčina"
    case .slovak1k: "Slovenčina · 1k · Typebar"
    case .slovak10k: "Slovenčina · 10k · Typebar"
    case .slovenian: "Slovenščina"
    case .slovenian1k: "Slovenščina · 1k · Typebar"
    case .slovenian5k: "Slovenščina · 5k · Typebar"
    case .croatian: "Hrvatski"
    case .croatian1k: "Hrvatski · 1k · Typebar"
    case .serbian: "Српски"
    case .serbian10k: "Српски · 10k · Typebar"
    case .serbianLatin: "Srpski (Latin)"
    case .serbianLatin10k: "Srpski (Latin) · 10k · Typebar"
    case .bulgarian: "Български"
    case .bulgarian1k: "Български · 1k · Typebar"
    case .bulgarianLatin: "Balgarski (Latin)"
    case .bulgarianLatin1k: "Balgarski (Latin) · 1k · Typebar"
    case .romanian: "Română"
    case .romanian1k: "Română · 1k · Typebar"
    case .romanian5k: "Română · 5k · Typebar"
    case .romanian10k: "Română · 10k · Typebar"
    case .romanian25k: "Română · 25k · Typebar"
    case .romanian50k: "Română · 50k · Typebar"
    case .romanian100k: "Română · 100k · Typebar"
    case .romanian200k: "Română · 200k · Typebar"
    case .finnish: "Suomi"
    case .finnish1k: "Suomi · 1k · Typebar"
    case .finnish10k: "Suomi · 10k · Typebar"
    case .estonian: "Eesti"
    case .estonian1k: "Eesti · 1k · Typebar"
    case .estonian5k: "Eesti · 5k · Typebar"
    case .estonian10k: "Eesti · 10k · Typebar"
    case .icelandic: "Íslenska"
    case .icelandic1k: "Íslenska · 1k · Typebar"
    case .french: "Français"
    case .french1k: "Français · 1k · Typebar"
    case .french2k: "Français · 2k · Typebar"
    case .french10k: "Français · 10k · Typebar"
    case .french600k: "Français · 600k · Typebar"
    case .frenchBitoduc: "Français · Bitoduc"
    case .italian: "Italiano"
    case .italian1k: "Italiano · 1k · Typebar"
    case .italian7k: "Italiano · 7k · Typebar"
    case .italian60k: "Italiano · 60k · Typebar"
    case .italian280k: "Italiano · 280k · Typebar"
    case .portuguese: "Português"
    case .portuguese1k: "Português · 1k · Typebar"
    case .portuguese3k: "Português · 3k · Typebar"
    case .portuguese5k: "Português · 5k · Typebar"
    case .portuguese320k: "Português · 320k · Typebar"
    case .portuguese550k: "Português · 550k · Typebar"
    case .portugueseAccents: "Português · Acentos e cedilha"
    case .simplifiedChinese: "简体中文"
    case .simplifiedChinese1k: "简体中文 · 1k · Typebar"
    case .simplifiedChinese5k: "简体中文 · 5k · Typebar"
    case .simplifiedChinese10k: "简体中文 · 10k · Typebar"
    case .simplifiedChinese50k: "简体中文 · 50k · Typebar"
    case .traditionalChinese: "繁體中文"
    case .traditionalChinese1k: "繁體中文 · 1k · Typebar"
    case .traditionalChinese5k: "繁體中文 · 5k · Typebar"
    case .traditionalChinese10k: "繁體中文 · 10k · Typebar"
    case .traditionalChinese50k: "繁體中文 · 50k · Typebar"
    case .russian: "Русский"
    case .russian1k: "Русский · 1k · Typebar"
    case .russian5k: "Русский · 5k · Typebar"
    case .russian10k: "Русский · 10k · Typebar"
    case .russian25k: "Русский · 25k · Typebar"
    case .russian50k: "Русский · 50k · Typebar"
    case .russian375k: "Русский · 375k · Typebar"
    case .russianAbbreviations: "Русский · Аббревиатуры"
    case .russianContractions: "Русский · Краткие формы · Typebar"
    case .russianContractions1k: "Русский · Краткие формы 1k · Typebar"
    case .ukrainian: "Українська"
    case .ukrainian1k: "Українська · 1k · Typebar"
    case .ukrainian10k: "Українська · 10k · Typebar"
    case .ukrainian50k: "Українська · 50k · Typebar"
    case .ukrainianEndings: "Українська · Закінчення"
    case .ukrainianLatin: "Українська (Latin)"
    case .ukrainianLatynka1k: "Українська (Latin) · 1k · Typebar"
    case .ukrainianLatynka10k: "Українська (Latin) · 10k · Typebar"
    case .ukrainianLatynka50k: "Українська (Latin) · 50k · Typebar"
    case .ukrainianLatynkaEndings: "Українська (Latynka) · Закінчення"
    case .japaneseHiragana: "日本語（ひらがな）"
    case .japaneseKatakana: "日本語（カタカナ）"
    case .japaneseRomaji: "日本語（ローマ字）"
    case .japaneseRomaji1k: "日本語（ローマ字）· 1k · Typebar"
    case .korean: "한국어"
    case .korean1k: "한국어 · 1k · Typebar"
    case .korean5k: "한국어 · 5k · Typebar"
    case .turkish: "Türkçe"
    case .turkish1k: "Türkçe · 1k · Typebar"
    case .turkish5k: "Türkçe · 5k · Typebar"
    case .polish: "Polski"
    case .polish2k: "Polski · 2k · Typebar"
    case .polish5k: "Polski · 5k · Typebar"
    case .polish10k: "Polski · 10k · Typebar"
    case .polish20k: "Polski · 20k · Typebar"
    case .polish40k: "Polski · 40k · Typebar"
    case .polish200k: "Polski · 200k · Typebar"
    case .mixedEnglishChinese: "中英混合"
    case .mixedLanguages: "多语混合"
    default: rawValue
    }
  }
}

extension EnglishVariant {
  var displayName: String {
    switch self {
    case .american: "American spelling"
    case .british: "British spelling"
    }
  }
}

extension QuoteLength {
  var displayName: String {
    switch self {
    case .all: "全部长度"
    case .short: "短引语"
    case .medium: "中等引语"
    case .long: "长引语"
    case .extended: "超长引语"
    }
  }
}
