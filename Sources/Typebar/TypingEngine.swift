import Foundation

/// Monkeytype treats spaces and explicit line breaks as word commits. Tabs
/// remain content because code and custom prompts may need them verbatim.
private func isPromptWordSeparator(_ character: Character) -> Bool {
  character == " " || character == "\n"
}

private func splitPromptWords(
  _ text: String, omittingEmptySubsequences: Bool
) -> [Substring] {
  text.split(
    omittingEmptySubsequences: omittingEmptySubsequences,
    whereSeparator: isPromptWordSeparator)
}

private enum InputCharacterEquivalence {
  static let sets: [Set<Character>] = [
    ["’", "‘", "'", "ʼ", "׳", "ʻ", "᾽"],
    ["\"", "”", "“", "„"],
    ["–", "—", "-", "‐", "‑"],
    [",", "‚"],
  ]

  static func matches(_ first: Character, _ second: Character) -> Bool {
    first == second || sets.contains { $0.contains(first) && $0.contains(second) }
  }
}

enum TestMode: String, CaseIterable, Codable {
  case time
  case words
  case quote
  case zen
  case custom
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
  static func threshold(baseWpm: Int, mode: MinimumWordBurstMode, wordLength: Int) -> Int {
    switch mode {
    case .off: return 0
    case .fixed: return baseWpm
    case .flex:
      let adjusted = Int(
        floor(Double(baseWpm) * pow(1.03, -2 * Double(max(0, wordLength - 3))))
      )
      return min(baseWpm, adjusted)
    }
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
  case afrikaans
  case albanian
  case bemba
  case bosnian
  case esperanto
  case esperantoXSystem
  case esperantoHSystem
  case latin
  case loremIpsum
  case git
  case twitchEmotes
  case typingOfTheDead
  case pokemon1k
  case arenaStrategy
  case friulian
  case malagasy
  case welsh
  case hausa
  case tatar
  case tatarCrimean
  case tatarCrimeanCyrillic
  case klingon
  case quenya
  case viossa
  case viossaNjutro
  case maori
  case lojbanGismu
  case lojbanCmavo
  case uzbek
  case occitan
  case oromo
  case macedonian
  case kazakh
  case vietnamese
  case jyutping
  case pinyin
  case bashkir
  case basque
  case frisian
  case zulu
  case hawaiian
  case kabyle
  case maltese
  case tokiPona
  case tokiPonaKuSuli
  case tokiPonaKuLili
  case xhosa
  case tibetan
  case kyrgyz
  case udmurt
  case yoruba
  case swahili
  case kinyarwanda
  case shona
  case santali
  case yiddish
  case arabic
  case arabicEgypt
  case arabicMorocco
  case pashto
  case sindhi
  case hebrew
  case persian
  case persianRomanized
  case urdu
  case urduRoman
  case urdish
  case tamil
  case tamilOld
  case tanglish
  case hindi
  case hinglish
  case gujarati
  case bangla
  case banglaLetters
  case thai
  case nepali
  case nepaliRomanized
  case kannada
  case telugu
  case malayalam
  case sanskrit
  case sanskritRoman
  case sinhala
  case khmer
  case myanmarBurmese
  case lao
  case amharic
  case armenian
  case armenianWestern
  case georgian
  case azerbaijani
  case belarusian
  case belarusian1k
  case belarusian5k
  case belarusian10k
  case belarusian25k
  case belarusian50k
  case belarusian100k
  case belarusianLacinka
  case lithuanian
  case latvian
  case mongolian
  case irish
  case galician
  case marathi
  case kurdishCentral
  case greek
  case greekKoine
  case greeklish
  case dutch
  case filipino
  case catalan
  case indonesian
  case malay
  case danish
  case norwegianBokmal
  case norwegianNynorsk
  case swedish
  case swedishDiacritics
  case hungarian
  case czech
  case slovak
  case slovenian
  case croatian
  case serbian
  case serbianLatin
  case bulgarian
  case bulgarianLatin
  case romanian
  case romanian1k
  case romanian5k
  case romanian10k
  case romanian25k
  case romanian50k
  case romanian100k
  case romanian200k
  case finnish
  case estonian
  case icelandic
  case french
  case french1k
  case french2k
  case french10k
  case frenchBitoduc
  case italian
  case portuguese
  case portuguese1k
  case portuguese3k
  case portuguese5k
  case portuguese320k
  case portuguese550k
  case portugueseAccents
  case simplifiedChinese
  case traditionalChinese
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
  case ukrainianEndings
  case ukrainianLatin
  case ukrainianLatynkaEndings
  case japaneseHiragana
  case japaneseKatakana
  case japaneseRomaji
  case korean
  case turkish
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

enum TestModifierPolicy {
  static let finiteDurationOnly: Set<TestModifier> = [
    .layoutFluid, .focusCurrentWord, .focusNextWord, .focusTwoWords, .focusThreeWords,
    .memory, .poetryStream, .referenceStream,
  ]

  static func compatibleWithInfiniteTest(_ modifiers: [TestModifier]) -> [TestModifier] {
    normalized(modifiers).filter { !finiteDurationOnly.contains($0) }
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
      modifiers.contains(.binaryStream)
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
              : modifiers.contains(.pseudolangStream)
                ? .pseudolangStream
                : modifiers.contains(.morseStream) ? .morseStream : nil
    return [
      boundaryModifier, caseModifier, messagingModifier, modifiers.contains(.rot13) ? .rot13 : nil,
      modifiers.contains(.backwards) ? .backwards : nil,
      modifiers.contains(.doubleCharacters) ? .doubleCharacters : nil, concealmentModifier,
      visibilityModifier, readAheadModifier,
      modifiers.contains(.correctBeforeAdvance) ? .correctBeforeAdvance : nil,
      modifiers.contains(.clearCurrentWordOnError) ? .clearCurrentWordOnError : nil,
      modifiers.contains(.lazyLatin) ? .lazyLatin : nil,
      modifiers.contains(.zipf) ? .zipf : nil,
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
    ].compactMap { $0 }
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
    case .binaryStream, .accountingStream, .hexadecimalStream, .symbolStream, .asciiStream, .specialCharacterStream,
      .gibberishStream,
      .poetryStream,
      .referenceStream,
      .arrowStream, .ipv4Stream, .ipv6Stream,
      .pseudolangStream, .morseStream:
      conflicts = [
        .binaryStream, .accountingStream, .hexadecimalStream, .symbolStream, .asciiStream, .specialCharacterStream,
        .gibberishStream,
        .poetryStream,
        .referenceStream,
        .arrowStream, .ipv4Stream, .ipv6Stream,
        .pseudolangStream, .morseStream,
      ]
    case .rot13, .backwards, .doubleCharacters, .correctBeforeAdvance, .clearCurrentWordOnError,
      .lazyLatin, .zipf, .mirrorVisual, .upsideDownVisual, .crtVisual, .earthquakeVisual, .spaceVisual,
      .nauseaVisual, .roundVisual, .chooVisual, .layoutFluid, .aslVisual,
      .noQuit, .mirrorKeyboard:
      conflicts = []
    }
    return normalized(modifiers.filter { !conflicts.contains($0) } + [modifier])
  }

  static func transformed(_ prompt: String, modifiers: [TestModifier]) -> String {
    var transformed = prompt
    if modifiers.contains(.noSpaces) {
      transformed = transformed.replacingOccurrences(of: " ", with: "")
    } else if modifiers.contains(.underscoreSeparators) {
      transformed = transformed.replacingOccurrences(of: " ", with: "_")
    }
    if modifiers.contains(.uppercase) {
      transformed = transformed.uppercased()
    } else if modifiers.contains(.titleCase) {
      transformed = transformed.split(separator: " ", omittingEmptySubsequences: false).map {
        word in
        guard let first = word.first else { return "" }
        return first.uppercased() + word.dropFirst().lowercased()
      }.joined(separator: " ")
    } else if modifiers.contains(.alternatingCase) {
      var uppercase = false
      transformed = transformed.reduce(into: "") { output, character in
        if character.isASCII, character.isLetter {
          output += uppercase ? character.uppercased() : character.lowercased()
        } else {
          output.append(character)
        }
        uppercase.toggle()
      }
    } else if modifiers.contains(.randomCase) {
      transformed = RandomCasePolicy.transformed(transformed)
    }
    if modifiers.contains(.messagingStyle) {
      transformed = MessagingTextPolicy.transformed(transformed)
    }
    if modifiers.contains(.rot13) {
      transformed = transformed.reduce(into: "") { output, character in
        guard character.unicodeScalars.count == 1,
          let scalar = character.unicodeScalars.first,
          scalar.isASCII,
          CharacterSet.letters.contains(scalar)
        else {
          output.append(character)
          return
        }
        let base: UInt32 = CharacterSet.uppercaseLetters.contains(scalar) ? 65 : 97
        output.unicodeScalars.append(UnicodeScalar(base + (scalar.value - base + 13) % 26)!)
      }
    }
    if modifiers.contains(.backwards) {
      transformed = transformed.split(separator: " ", omittingEmptySubsequences: false)
        .map { String($0.reversed()) }
        .joined(separator: " ")
    }
    if modifiers.contains(.doubleCharacters) {
      transformed = transformed.reduce(into: "") { output, character in
        output.append(character)
        if character != " " { output.append(character) }
      }
    }
    if modifiers.contains(.lazyLatin) {
      transformed = TypingTextNormalizer.lazyLatin(transformed)
    }
    return transformed
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
    guard language == .arabic, automaticallyEnabled else {
      return TestModifierPolicy.normalized(modifiers)
    }
    return TestModifierPolicy.normalized(modifiers + [.lazyLatin])
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

enum ChooVisualPolicy {
  static func rotationDegrees(at date: Date, glyphIndex: Int, isEnabled: Bool, reducesMotion: Bool) -> Double {
    guard isEnabled && !reducesMotion else { return 0 }
    let seconds = date.timeIntervalSinceReferenceDate
    let phase = seconds * .pi + Double(glyphIndex % 7) * 0.42
    return sin(phase) * 180
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
  /// Keeps punctuation and non-Latin characters untouched while independently
  /// choosing the case of each ASCII letter. The injectable source makes the
  /// user-facing randomness testable without copying a reference implementation.
  static func transformed(
    _ value: String, nextBit: () -> Bool = { Bool.random() }
  ) -> String {
    value.reduce(into: "") { output, character in
      guard character.isASCII, character.isLetter else {
        output.append(character)
        return
      }
      output += nextBit() ? character.uppercased() : character.lowercased()
    }
  }
}

enum MessagingTextPolicy {
  /// Creates a compact chat-like prompt from user-owned or Typebar-authored text.
  /// Sentence punctuation becomes a line break so the existing native Return path
  /// can be used to practice a realistic multi-line exchange.
  static func transformed(_ value: String) -> String {
    let removable = CharacterSet(charactersIn: "()[]{}\"'")
    var output = ""
    var previousWasNewline = false
    for scalar in value.lowercased().unicodeScalars {
      if removable.contains(scalar) { continue }
      if ".!?。！？".unicodeScalars.contains(scalar) {
        if !output.isEmpty, !previousWasNewline {
          output.append("\n")
          previousWasNewline = true
        }
        continue
      }
      output.unicodeScalars.append(scalar)
      previousWasNewline = scalar.properties.isWhitespace && scalar != "\n"
        ? false : scalar == "\n"
    }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

enum TypingTextNormalizer {
  static func lazyLatin(_ value: String) -> String {
    let ligatures: [(String, String)] = [
      ("ß", "ss"), ("ẞ", "SS"), ("æ", "ae"), ("Æ", "AE"),
      ("œ", "oe"), ("Œ", "OE"), ("ø", "o"), ("Ø", "O"),
      ("ł", "l"), ("Ł", "L"), ("đ", "d"), ("Đ", "D"),
    ]
    let expanded = ligatures.reduce(value) { text, replacement in
      text.replacingOccurrences(of: replacement.0, with: replacement.1)
    }
    let latinSimplified = expanded.folding(
      options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    return simplifyArabicMarks(in: latinSimplified)
  }

  /// Arabic simplified input deliberately removes only short-vowel, tanwin,
  /// shadda and sukun marks that Typebar's own Arabic practice content uses.
  /// It also normalizes the common hamza-on-alef variants so the generated
  /// target can be entered without those extra key sequences.
  private static func simplifyArabicMarks(in value: String) -> String {
    value.unicodeScalars.reduce(into: "") { output, scalar in
      switch scalar.value {
      case 0x0622, 0x0623, 0x0625:
        output.unicodeScalars.append(UnicodeScalar(0x0627)!)
      case 0x064B...0x0652:
        break
      default:
        output.unicodeScalars.append(scalar)
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
  var minimumAccuracy = 0
  /// Zero disables the final whole-test WPM threshold.
  var minimumWpm = 0
  /// Zero disables Typebar's minimum per-word speed rule. A positive value
  /// is evaluated after a measurable, space-delimited word commit.
  var minimumWordBurstWpm = 0
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
    minimumAccuracy: Int = 0,
    minimumWpm: Int = 0,
    minimumWordBurstWpm: Int = 0,
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
    self.minimumAccuracy = minimumAccuracy.clamped(to: 0...100)
    self.minimumWpm = minimumWpm.clamped(to: 0...300)
    self.minimumWordBurstWpm = minimumWordBurstWpm.clamped(to: 0...300)
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
    minimumAccuracy = (try values.decodeIfPresent(Int.self, forKey: .minimumAccuracy) ?? 0).clamped(
      to: 0...100)
    minimumWpm = (try values.decodeIfPresent(Int.self, forKey: .minimumWpm) ?? 0).clamped(
      to: 0...300)
    minimumWordBurstWpm = (try values.decodeIfPresent(Int.self, forKey: .minimumWordBurstWpm) ?? 0)
      .clamped(to: 0...300)
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
  var customTextCompletion: CustomTextCompletion
  var customTextSectionLimit: Int?
  var customTextOrdering: CustomTextOrdering
  var mixedLanguageComponents: [TypingLanguage]
  var modifiers: [TestModifier]
  var contentOptions: ContentOptions
  var challengeID: String?

  var isInfinite: Bool {
    Self.usesInfiniteLimit(
      mode: mode, duration: duration, wordLimit: wordLimit,
      customTextCompletion: customTextCompletion)
  }

  /// Mirrors reference `joiningScript` metadata for native prompt shaping.
  /// A mixed prompt needs this behavior when any selected component needs it.
  var usesJoiningScriptPrompt: Bool {
    language.usesJoiningScriptPrompt
      || (language == .mixedLanguages && mixedLanguageComponents.contains { $0.usesJoiningScriptPrompt })
  }

  init(
    mode: TestMode, duration: TimeInterval?, wordLimit: Int?, difficulty: Difficulty,
    rules: InputRules, language: TypingLanguage = .english,
    englishVariant: EnglishVariant = .american, quoteLength: QuoteLength = .all,
    quoteLengths: Set<QuoteLength>? = nil,
    customTextCompletion: CustomTextCompletion = .finish, customTextSectionLimit: Int? = nil,
    customTextOrdering: CustomTextOrdering = .inOrder,
    mixedLanguageComponents: [TypingLanguage] = TypingLanguage.defaultMixedComponents,
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
    self.customTextCompletion = customTextCompletion
    self.customTextSectionLimit = customTextSectionLimit
    self.customTextOrdering = customTextOrdering
    self.mixedLanguageComponents = TypingLanguage.normalizedMixedComponents(mixedLanguageComponents)
    let normalizedModifiers = TestModifierPolicy.normalized(modifiers).filter {
      mode != .zen || $0 != .memory
    }
    self.modifiers = Self.usesInfiniteLimit(
      mode: mode, duration: duration, wordLimit: wordLimit,
      customTextCompletion: customTextCompletion)
      ? TestModifierPolicy.compatibleWithInfiniteTest(normalizedModifiers) : normalizedModifiers
    self.contentOptions = contentOptions
    self.challengeID = challengeID
  }

  static func timed(
    seconds: TimeInterval, difficulty: Difficulty = .normal, rules: InputRules = .init(),
    language: TypingLanguage = .english, englishVariant: EnglishVariant = .american,
    mixedLanguageComponents: [TypingLanguage] = TypingLanguage.defaultMixedComponents,
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
    mixedLanguageComponents: [TypingLanguage] = TypingLanguage.defaultMixedComponents,
    contentOptions: ContentOptions = .init()
  ) -> Self {
    .init(
      mode: .words, duration: nil, wordLimit: count, difficulty: difficulty, rules: rules,
      language: language, englishVariant: englishVariant,
      mixedLanguageComponents: mixedLanguageComponents, contentOptions: contentOptions)
  }

  func with(modifiers: [TestModifier]) -> Self {
    var copy = self
    let normalizedModifiers = TestModifierPolicy.normalized(modifiers).filter {
      copy.mode != .zen || $0 != .memory
    }
    copy.modifiers = copy.isInfinite
      ? TestModifierPolicy.compatibleWithInfiniteTest(normalizedModifiers) : normalizedModifiers
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
      quoteLengths, customTextCompletion, customTextSectionLimit, customTextOrdering, mixedLanguageComponents,
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
    customTextCompletion =
      try values.decodeIfPresent(CustomTextCompletion.self, forKey: .customTextCompletion)
      ?? .finish
    customTextSectionLimit = try values.decodeIfPresent(Int.self, forKey: .customTextSectionLimit)
    customTextOrdering =
      try values.decodeIfPresent(CustomTextOrdering.self, forKey: .customTextOrdering) ?? .inOrder
    mixedLanguageComponents = TypingLanguage.normalizedMixedComponents(
      try values.decodeIfPresent([TypingLanguage].self, forKey: .mixedLanguageComponents)
        ?? TypingLanguage.defaultMixedComponents)
    let normalizedModifiers = TestModifierPolicy.normalized(
      try values.decodeIfPresent([TestModifier].self, forKey: .modifiers) ?? []
    ).filter { decodedMode != .zen || $0 != .memory }
    modifiers = Self.usesInfiniteLimit(
      mode: decodedMode, duration: duration, wordLimit: wordLimit,
      customTextCompletion: customTextCompletion)
      ? TestModifierPolicy.compatibleWithInfiniteTest(normalizedModifiers) : normalizedModifiers
    contentOptions =
      try values.decodeIfPresent(ContentOptions.self, forKey: .contentOptions) ?? .init()
    challengeID = try values.decodeIfPresent(String.self, forKey: .challengeID)
  }

  private static func usesInfiniteLimit(
    mode: TestMode, duration: TimeInterval?, wordLimit: Int?,
    customTextCompletion: CustomTextCompletion
  ) -> Bool {
    switch mode {
    case .time: duration == 0
    case .words: wordLimit == 0
    case .custom:
      (customTextCompletion == .time && duration == 0)
        || (customTextCompletion == .words && wordLimit == 0)
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

/// Native equivalent of the reference test's one-second inactivity accounting.
/// It consumes only local event timestamps; the timer is deliberately not
/// paused, so timed tests keep their normal wall-clock deadline.
enum TestInactivityPolicy {
  static let trailingInactiveIntervals = 5

  static func intervalCounts(
    activityDates: [Date], startedAt: Date, endedAt: Date, includesFractionalTail: Bool
  ) -> [Int] {
    let duration = max(0, endedAt.timeIntervalSince(startedAt))
    let fullIntervals = Int(duration.rounded(.down))
    var boundaries = fullIntervals > 0 ? (1...fullIntervals).map(Double.init) : []
    let remainder = duration - Double(fullIntervals)
    if includesFractionalTail, remainder >= 0.5 { boundaries.append(duration) }

    return boundaries.enumerated().map { index, boundary in
      let lowerBound = index == 0 ? -Double.leastNonzeroMagnitude : boundaries[index - 1]
      return activityDates.reduce(into: 0) { count, date in
        let offset = date.timeIntervalSince(startedAt)
        if offset > lowerBound && offset <= boundary { count += 1 }
      }
    }
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
      TypingPromptGlyph(character: $0, state: blindMode ? .hidden : .correct)
    }
    if !isFinished {
      output.append(.init(character: " ", state: .current))
    }
    return output
  }

  static func glyphs(
    target: String, typed: String, isFinished: Bool, blindMode: Bool,
    forcedErrorIndices: Set<Int> = [],
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
          ? .hidden
          : typedCharacters[typedIndex] == targetCharacters[index] && !forcedErrorIndices.contains(index)
            ? .correct : .incorrect
      } else if index < activeTargetIndex {
        state = blindMode ? .hidden : .incorrect
      } else if index == activeTargetIndex, !isFinished {
        state = .current
      } else {
        state = .pending
      }
      return TypingPromptGlyph(
        character: targetCharacters[index], state: state,
        typedCharacter: state == .incorrect ? typedIndexByTarget[index].map { typedCharacters[$0] } : nil)
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
    guard !extraCharacters.isEmpty else { return output }
    output += extraCharacters.map {
      TypingPromptGlyph(
        character: $0, state: blindMode || concealAll || hideExtraLetters ? .hidden : .extra)
    }
    return output
  }
}

enum TypedCharacterEffectPolicy {
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
  case capsLockEnabled

  var message: String {
    switch self {
    case .inputUnfocused: "输入框未聚焦，点击练习区继续"
    case .capsLockEnabled: "大写锁定已开启"
    }
  }

  var systemImage: String {
    switch self {
    case .inputUnfocused: "cursorarrow.click"
    case .capsLockEnabled: "capslock"
    }
  }
}

enum TypingAttentionPolicy {
  static func warnings(
    isInputFocused: Bool,
    focusWarningDelayElapsed: Bool = true,
    capsLockEnabled: Bool,
    language: TypingLanguage,
    isFinished: Bool,
    showFocusWarning: Bool,
    showCapsLockWarning: Bool
  ) -> [TypingAttentionWarning] {
    guard !isFinished else { return [] }
    var warnings: [TypingAttentionWarning] = []
    if showFocusWarning, !isInputFocused, focusWarningDelayElapsed {
      warnings.append(.inputUnfocused)
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
        return (configuration.customTextSectionLimit ?? 0) >= longWordLimit
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
      case .sections: return (configuration.customTextSectionLimit ?? 0) >= 5_000
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
  var isCorrect: Bool { target == typed && !hasInputError }

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

enum TypingReplayEventKind: String, Codable, Equatable {
  case insert
  case delete
}

struct TypingReplayEvent: Codable, Equatable, Identifiable {
  let offset: TimeInterval
  let kind: TypingReplayEventKind
  let text: String
  let forceError: Bool
  let automatic: Bool
  var id: String { "\(offset)-\(kind.rawValue)-\(text)" }

  init(
    offset: TimeInterval, kind: TypingReplayEventKind, text: String, forceError: Bool = false,
    automatic: Bool = false
  ) {
    self.offset = offset
    self.kind = kind
    self.text = text
    self.forceError = forceError
    self.automatic = automatic
  }

  private enum CodingKeys: String, CodingKey { case offset, kind, text, forceError, automatic }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    offset = try values.decode(TimeInterval.self, forKey: .offset)
    kind = try values.decode(TypingReplayEventKind.self, forKey: .kind)
    text = try values.decode(String.self, forKey: .text)
    forceError = try values.decodeIfPresent(Bool.self, forKey: .forceError) ?? false
    automatic = try values.decodeIfPresent(Bool.self, forKey: .automatic) ?? false
  }
}

enum TypingReplay {
  static func typedText(events: [TypingReplayEvent], through elapsed: TimeInterval) -> String {
    events.filter { $0.offset <= elapsed }.reduce(into: "") { typed, event in
      switch event.kind {
      case .insert: typed += event.text
      case .delete:
        guard !typed.isEmpty else { return }
        typed.removeLast()
      }
    }
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

  init(matched: Int, incorrect: Int, extra: Int, missed: Int) {
    self.matched = max(0, matched)
    self.incorrect = max(0, incorrect)
    self.extra = max(0, extra)
    self.missed = max(0, missed)
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
  let restartCount: Int
  let characterStats: ResultCharacterStats
  let keyDurationSamples: [TimeInterval]
  let keySpacingSamples: [TimeInterval]
  let keyOverlapDuration: TimeInterval
  let tags: [String]
  let prompt: String
  let replayEvents: [TypingReplayEvent]

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
    restartCount: Int = 0,
    characterStats: ResultCharacterStats? = nil,
    keyDurationSamples: [TimeInterval] = [],
    keySpacingSamples: [TimeInterval] = [],
    keyOverlapDuration: TimeInterval = 0,
    tags: [String] = [],
    prompt: String = "",
    replayEvents: [TypingReplayEvent] = []
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
    self.restartCount = max(0, restartCount)
    self.characterStats = characterStats ?? .legacy(
      typedCharacterCount: typedCharacterCount,
      correctCharacterCount: correctCharacterCount)
    self.keyDurationSamples = keyDurationSamples.filter { $0.isFinite && $0 >= 0 }
    self.keySpacingSamples = keySpacingSamples.filter { $0.isFinite && $0 >= 0 }
    self.keyOverlapDuration = keyOverlapDuration.isFinite ? max(0, keyOverlapDuration) : 0
    self.tags = tags
    self.prompt = prompt
    self.replayEvents = replayEvents
  }

  var elapsedDuration: TimeInterval {
    max(0, finishedAt.timeIntervalSince(startedAt))
  }

  var engagedDuration: TimeInterval {
    max(0, elapsedDuration - afkDuration)
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
      restartCount, keyDurationSamples, keySpacingSamples, keyOverlapDuration, tags, prompt,
      replayEvents
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    configuration = try values.decode(TestConfiguration.self, forKey: .configuration)
    outcome = try values.decode(TestOutcome.self, forKey: .outcome)
    startedAt = try values.decode(Date.self, forKey: .startedAt)
    finishedAt = try values.decode(Date.self, forKey: .finishedAt)
    afkDuration = max(0, try values.decodeIfPresent(TimeInterval.self, forKey: .afkDuration) ?? 0)
    typedCharacterCount = try values.decode(Int.self, forKey: .typedCharacterCount)
    correctCharacterCount = try values.decode(Int.self, forKey: .correctCharacterCount)
    errorCount = try values.decode(Int.self, forKey: .errorCount)
    wpm = try values.decode(Int.self, forKey: .wpm)
    rawWpm = try values.decode(Int.self, forKey: .rawWpm)
    accuracy = try values.decode(Int.self, forKey: .accuracy)
    restartCount = max(0, try values.decodeIfPresent(Int.self, forKey: .restartCount) ?? 0)
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
    prompt = try values.decodeIfPresent(String.self, forKey: .prompt) ?? ""
    replayEvents = try values.decodeIfPresent([TypingReplayEvent].self, forKey: .replayEvents) ?? []
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
  let configuration: TestConfiguration
  private(set) var prompt: String
  private let initialPrompt: String
  private let repeatingPrompt: String?
  private let sectionEndIndices: [Int]
  /// In no-space tests, the reference product still commits each source word
  /// when its final character is entered. Keep those boundaries separately:
  /// after the prompt has been flattened, spaces can no longer recover them.
  private var noSpaceWordEndIndices: [Int]
  private let initialNoSpaceWordEndIndices: [Int]
  /// Rendered word slices paired with the separate no-space boundaries. They
  /// let result history and local practice retain word-level behavior even
  /// though the prompt itself has no visible separator.
  private var noSpaceTargetWords: [String]
  private let initialNoSpaceTargetWords: [String]
  private let repeatingNoSpaceWordLengths: [Int]
  private let repeatingNoSpaceTargetWords: [String]
  private(set) var typed = ""
  /// Each accepted input character keeps the target position it advanced to.
  /// A word can be submitted early with space, so this cannot always be
  /// inferred from the input string's character offset.
  private var typedTargetIndices: [Int?] = []
  /// Input offsets for extra letters retained in a completed source word.
  /// They have no target character, but remain scoring errors after that word
  /// is submitted and the active input buffer becomes empty.
  private var extraErrorTypedIndices = Set<Int>()
  private var typedCharacterDates: [Date] = []
  private var keyboardActivityDates: [Date] = []
  private var insertionActivityDates: [Date] = []
  private var forcedErrorIndices = Set<Int>()
  /// Target positions at which the user made an input error during this
  /// attempt. Unlike `forcedErrorIndices`, these remain after a backspace so
  /// local error practice can include words the user later corrected.
  private var attemptedErrorCounts = [Int: Int]()
  private var committedWordBursts: [Int] = []
  private var replayEvents: [TypingReplayEvent] = []
  private var activePhysicalKeyDownDates: [UInt16: Date] = [:]
  private var completedPhysicalKeyDurations: [TimeInterval] = []
  private var lastPhysicalKeyDownDate: Date?
  private var physicalKeySpacingSamples: [TimeInterval] = []
  private var physicalKeyOverlapStartedAt: Date?
  private var completedPhysicalKeyOverlapDuration: TimeInterval = 0
  private(set) var startedAt: Date?
  private(set) var finishedAt: Date?
  private(set) var outcome: TestOutcome = .active

  init(
    configuration: TestConfiguration, prompt: String, repeatingPrompt: String? = nil,
    sectionEndIndices: [Int] = [], noSpaceWordEndIndices: [Int] = [],
    noSpaceTargetWords: [String] = [], repeatingNoSpaceWordLengths: [Int] = [],
    repeatingNoSpaceTargetWords: [String] = []
  ) {
    self.configuration = configuration
    self.prompt = prompt
    self.initialPrompt = prompt
    self.repeatingPrompt = repeatingPrompt
    self.sectionEndIndices = sectionEndIndices
    self.noSpaceWordEndIndices = noSpaceWordEndIndices
    self.initialNoSpaceWordEndIndices = noSpaceWordEndIndices
    self.noSpaceTargetWords = noSpaceTargetWords
    self.initialNoSpaceTargetWords = noSpaceTargetWords
    self.repeatingNoSpaceWordLengths = repeatingNoSpaceWordLengths
    self.repeatingNoSpaceTargetWords = repeatingNoSpaceTargetWords
  }

  /// Starts an equivalent fresh attempt without regenerating content. This is
  /// intentionally based on the initial session prompt so timed custom text
  /// retains its original repeat source instead of reusing a grown prompt.
  func repeatedAttempt() -> TypingSession {
    TypingSession(
      configuration: configuration, prompt: initialPrompt, repeatingPrompt: repeatingPrompt,
      sectionEndIndices: sectionEndIndices, noSpaceWordEndIndices: initialNoSpaceWordEndIndices,
      noSpaceTargetWords: initialNoSpaceTargetWords,
      repeatingNoSpaceWordLengths: repeatingNoSpaceWordLengths,
      repeatingNoSpaceTargetWords: repeatingNoSpaceTargetWords)
  }

  var isFinished: Bool { outcome != .active }
  var hasStarted: Bool { startedAt != nil }
  var typedCharacterCount: Int { typed.count }
  var afkDuration: TimeInterval {
    guard let startedAt, let finishedAt else { return 0 }
    return TestInactivityPolicy.inactiveDuration(
      activityDates: keyboardActivityDates, startedAt: startedAt, endedAt: finishedAt,
      includesFractionalTail: configuration.duration == nil)
  }

  mutating func recordKeyboardActivity(at date: Date = .now) {
    guard !isFinished, startedAt != nil else { return }
    keyboardActivityDates.append(date)
  }

  /// Records anonymous key hold durations from native keyDown/keyUp pairs.
  /// Auto-repeat does not begin a second press, and unmatched releases are ignored.
  mutating func recordPhysicalKeyEvent(
    keyCode: UInt16, isKeyDown: Bool, isRepeat: Bool, at date: Date = .now
  ) {
    guard !isFinished else { return }
    if isKeyDown {
      guard !isRepeat, activePhysicalKeyDownDates[keyCode] == nil else { return }
      if startedAt != nil, let previousDate = lastPhysicalKeyDownDate {
        let spacing = date.timeIntervalSince(previousDate)
        if spacing.isFinite, spacing >= 0 { physicalKeySpacingSamples.append(spacing) }
      }
      lastPhysicalKeyDownDate = date
      activePhysicalKeyDownDates[keyCode] = date
      if startedAt != nil, activePhysicalKeyDownDates.count > 1,
        physicalKeyOverlapStartedAt == nil
      {
        physicalKeyOverlapStartedAt = date
      }
      return
    }
    guard startedAt != nil, let keyDownDate = activePhysicalKeyDownDates.removeValue(forKey: keyCode)
    else { return }
    let duration = date.timeIntervalSince(keyDownDate)
    if duration.isFinite, duration >= 0 { completedPhysicalKeyDurations.append(duration) }
    if activePhysicalKeyDownDates.count == 1, let overlapStartedAt = physicalKeyOverlapStartedAt {
      let overlap = date.timeIntervalSince(overlapStartedAt)
      if overlap.isFinite, overlap >= 0 { completedPhysicalKeyOverlapDuration += overlap }
      physicalKeyOverlapStartedAt = nil
    }
  }

  var sectionProgress: (completed: Int, total: Int)? {
    guard !sectionEndIndices.isEmpty else { return nil }
    let completed = sectionEndIndices.filter { nextTargetIndex >= $0 }.count
    return (min(completed, sectionEndIndices.count), sectionEndIndices.count)
  }
  var nextExpectedCharacter: Character? {
    guard !isFinished, nextTargetIndex < prompt.count else { return nil }
    return Array(prompt)[nextTargetIndex]
  }

  var promptGlyphs: [TypingPromptGlyph] {
    if configuration.mode == .zen {
      return TypingPromptPresentation.zenGlyphs(
        typed: typed, isFinished: isFinished, blindMode: configuration.rules.blindMode)
    }
    return TypingPromptPresentation.glyphs(
      target: prompt,
      typed: typed,
      isFinished: isFinished,
      blindMode: configuration.rules.blindMode,
      forcedErrorIndices: forcedErrorIndices,
      typedTargetIndices: typedTargetIndices,
      currentTargetIndex: nextTargetIndex,
      hideExtraLetters: configuration.rules.hideExtraLetters,
      visibleFutureWords: configuration.language.usesSpaceDelimitedWords
        ? configuration.visibleFutureWordCount : nil,
      concealAll: configuration.modifiers.contains(.memory) && hasStarted && !isFinished,
      concealedCurrentAndFutureWords: hasStarted ? configuration.readAheadConcealedWordCount : nil,
      concealPendingCharacters: configuration.modifiers.contains(.simonSays)
    )
  }

  var completedPromptCharacterIndices: Set<Int> {
    TypedCharacterEffectPolicy.completedCharacterIndices(
      target: prompt, typed: typed, typedTargetIndices: typedTargetIndices, isFinished: isFinished)
  }

  var errors: Int {
    let typedCharacters = Array(typed)
    let targetCharacters = Array(prompt)
    return typedCharacters.indices.reduce(into: 0) { total, typedIndex in
      guard typedTargetIndices.indices.contains(typedIndex) else { return }
      guard let targetIndex = typedTargetIndices[typedIndex], targetCharacters.indices.contains(targetIndex)
      else {
        if extraErrorTypedIndices.contains(typedIndex) { total += 1 }
        return
      }
      if typedCharacters[typedIndex] != targetCharacters[targetIndex]
        || forcedErrorIndices.contains(targetIndex)
      {
        total += 1
      }
    }
  }

  var correctCharacters: Int { max(0, typed.count - errors) }

  /// A native final-state classification derived from the accepted input's
  /// exact target mapping. It is descriptive only and never feeds scoring.
  var characterStats: ResultCharacterStats {
    if configuration.mode == .zen {
      return .init(matched: typed.count, incorrect: 0, extra: 0, missed: 0)
    }

    let typedCharacters = Array(typed)
    let targetCharacters = Array(prompt)
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
      if typedCharacters[typedIndex] == targetCharacters[targetIndex]
        && !forcedErrorIndices.contains(targetIndex)
      {
        matched += 1
      } else {
        incorrect += 1
      }
    }
    return .init(matched: matched, incorrect: incorrect, extra: extra, missed: missed)
  }

  var accuracy: Int {
    guard !typed.isEmpty else { return 100 }
    return Int((Double(correctCharacters) / Double(typed.count) * 100).rounded())
  }

  func wpm(at date: Date) -> Int {
    guard let startedAt else { return 0 }
    let end = finishedAt ?? date
    let seconds = max(end.timeIntervalSince(startedAt), 1)
    return Int((Double(correctCharacters) / 5 / seconds * 60).rounded())
  }

  func rawWpm(at date: Date) -> Int {
    guard let startedAt else { return 0 }
    let end = finishedAt ?? date
    let seconds = max(end.timeIntervalSince(startedAt), 1)
    return Int((Double(typed.count) / 5 / seconds * 60).rounded())
  }

  /// Word burst is the WPM for the latest completed word, or the currently
  /// active word once it has at least two accepted characters. The submitting
  /// space counts as one input character, matching the app's word metric.
  var burstWpm: Int {
    let characters = Array(typed)
    if tracksNoSpaceWordBursts {
      if noSpaceCommittedWordIndex != nil { return committedWordBursts.last ?? 0 }
      let start = noSpaceWordEndIndices.last(where: { $0 < characters.count }) ?? 0
      return activeWordBurst(start: start) ?? committedWordBursts.last ?? 0
    }
    guard let lastSeparator = characters.lastIndex(where: isPromptWordSeparator) else {
      return activeWordBurst(start: 0) ?? committedWordBursts.last ?? 0
    }
    let start = lastSeparator + 1
    guard start < characters.count else { return committedWordBursts.last ?? 0 }
    return activeWordBurst(start: start) ?? committedWordBursts.last ?? 0
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
    let characters = Array(typed)
    guard characters.count == typedCharacterDates.count else { return [] }
    if hasNoSpaceWordSegmentation {
      var bursts: [Int?] = []
      for range in noSpaceWordRanges where range.lowerBound < characters.count {
        let end = min(range.upperBound, characters.count) - 1
        bursts.append(wordBurst(from: range.lowerBound, through: end, includesTrailingSpace: false))
      }
      return bursts
    }
    guard configuration.language.usesSpaceDelimitedWords,
      !configuration.modifiers.contains(.noSpaces), !typed.isEmpty
    else { return [] }
    var bursts: [Int?] = []
    var wordStart = 0
    for index in characters.indices where isPromptWordSeparator(characters[index]) {
      bursts.append(wordBurst(from: wordStart, through: index, includesTrailingSpace: true))
      wordStart = index + 1
    }
    if wordStart < characters.count {
      bursts.append(wordBurst(from: wordStart, through: characters.count - 1, includesTrailingSpace: false))
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
    if configuration.language.isNoSpaceLanguage {
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
    return targetWords.indices.map { attemptedInputErrorCount(inWord: $0) }
  }

  private var missedNoSpaceWordErrorCounts: [MissedWordErrorCount] {
    let targetCharacters = Array(prompt)
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
    guard (!typed.isEmpty || !attemptedErrorCounts.isEmpty),
      (configuration.language.usesSpaceDelimitedWords || hasNoSpaceWordSegmentation)
    else { return [] }
    let targetWords = resultTargetWords
    guard !targetWords.isEmpty else { return [] }
    if hasNoSpaceWordSegmentation {
      return noSpaceWordReviews(targetWords: targetWords)
    }
    let typedWords = splitPromptWords(typed, omittingEmptySubsequences: false).map(String.init)
    let finalAttemptedCount = typed.last.map(isPromptWordSeparator) == true
      ? max(0, typedWords.count - 1) : typedWords.count
    let historicalAttemptedCount = targetWords.indices.last(where: hasAttemptedInputError)
      .map { $0 + 1 } ?? 0
    let attemptedCount = max(finalAttemptedCount, historicalAttemptedCount)
    return (0..<min(attemptedCount, targetWords.count)).map {
      let typedWord = $0 < typedWords.count ? typedWords[$0] : ""
      return TypedWordReview(
        index: $0, target: targetWords[$0], typed: typedWord,
        hasInputError: typedWord == targetWords[$0]
          && hasAttemptedInputError(inWord: $0))
    }
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
    if configuration.duration == 0 {
      guard let startedAt else { return "0s" }
      return "\(max(0, Int(date.timeIntervalSince(startedAt).rounded(.down))))s"
    }
    if configuration.wordLimit == 0 { return "\(completedWordCount)" }
    if let remaining = remainingSeconds(at: date) { return "\(remaining)s" }
    guard let wordLimit = configuration.wordLimit,
      (configuration.language.usesSpaceDelimitedWords || tracksNoSpaceWordBursts)
    else { return nil }
    return "\(min(wordLimit, completedWordCount))/\(wordLimit)"
  }

  var progressLabel: String {
    if configuration.duration == 0 { return "用时" }
    if configuration.wordLimit == 0 { return "词数" }
    return configuration.duration == nil && configuration.wordLimit != nil ? "进度" : "剩余"
  }

  func progressFraction(at date: Date = .now) -> Double? {
    if let duration = configuration.duration {
      if duration == 0 { return 1 }
      guard let startedAt else { return 0 }
      return (date.timeIntervalSince(startedAt) / duration).clamped(to: 0...1)
    }
    guard let wordLimit = configuration.wordLimit,
      (configuration.language.usesSpaceDelimitedWords || tracksNoSpaceWordBursts)
    else { return nil }
    if wordLimit == 0 { return 0 }
    return Double(min(wordLimit, completedWordCount)) / Double(wordLimit)
  }

  var completedWordCount: Int {
    if tracksNoSpaceWordBursts {
      return noSpaceWordEndIndices.filter { typed.count >= $0 }.count
    }
    let targetCharacters = Array(prompt)
    let typedCharacters = Array(typed)
    let committed = targetCharacters.indices.filter { targetIndex in
      guard isPromptWordSeparator(targetCharacters[targetIndex]),
        let typedIndex = typedTargetIndices.firstIndex(where: { $0 == targetIndex })
      else { return false }
      return isPromptWordSeparator(typedCharacters[typedIndex])
    }.count
    guard isFinished, !typed.isEmpty else { return committed }
    return committed + 1
  }

  func result(
    at date: Date = .now, tags: [String] = [], restartCount: Int = 0
  ) -> CompletedTestResult? {
    guard let startedAt, let finishedAt else { return nil }
    return .init(
      id: UUID(),
      configuration: configuration,
      outcome: outcome,
      startedAt: startedAt,
      finishedAt: finishedAt,
      afkDuration: afkDuration,
      typedCharacterCount: typed.count,
      correctCharacterCount: correctCharacters,
      errorCount: errors,
      wpm: wpm(at: date),
      rawWpm: rawWpm(at: date),
      accuracy: accuracy,
      restartCount: restartCount,
      characterStats: characterStats,
      keyDurationSamples: completedPhysicalKeyDurations,
      keySpacingSamples: physicalKeySpacingSamples,
      keyOverlapDuration: completedPhysicalKeyOverlapDuration,
      tags: ResultTagPolicy.normalized(tags),
      prompt: prompt,
      replayEvents: replayEvents
    )
  }

  mutating func insert(_ text: String, forceError: Bool = false, at date: Date = .now) {
    insertText(
      text, forceError: forceError, at: date, evaluatesTerminalRulesOnLastCharacterOnly: false)
  }

  /// Handles a single platform text-insertion event such as a paste or a
  /// confirmed IME composition. The reference processes every character but
  /// delays difficulty and burst terminal checks until the event's final
  /// character.
  mutating func insertBatch(_ text: String, forceError: Bool = false, at date: Date = .now) {
    insertText(
      text, forceError: forceError, at: date, evaluatesTerminalRulesOnLastCharacterOnly: true)
  }

  private mutating func insertText(
    _ text: String, forceError: Bool, at date: Date,
    evaluatesTerminalRulesOnLastCharacterOnly: Bool
  ) {
    guard !isFinished, !text.isEmpty else { return }
    beginIfNeeded(at: date)
    keyboardActivityDates.append(date)
    insertionActivityDates.append(date)
    let characters = Array(text)
    for (index, character) in characters.enumerated() {
      guard !isFinished else { break }
      if shouldExpandReferenceEllipsis(character) {
        // The web reference replaces a single ellipsis with three periods
        // only when the prompt expects periods. Treat that replacement as
        // its own multi-character insertion event so replay and terminal
        // rules match the transformed user input.
        insertText(
          "...", forceError: forceError, at: date,
          evaluatesTerminalRulesOnLastCharacterOnly: true)
        continue
      }
      let evaluatesTerminalRules = !evaluatesTerminalRulesOnLastCharacterOnly
        || index == characters.indices.last
      if insertCharacter(
        character, forceError: forceError, at: date,
        evaluatesTerminalRules: evaluatesTerminalRules)
      {
        recordReplayEvent(kind: .insert, text: String(character), forceError: forceError, at: date)
        insertCodeIndentationIfNeeded(after: character, at: date)
      }
    }
    finishIfNeeded(at: date)
  }

  mutating func deleteBackward(at date: Date = .now) {
    guard !isFinished else { return }
    recordKeyboardActivity(at: date)
    guard !typed.isEmpty else { return }
    guard canDeleteBackward else { return }
    if configuration.rules.codeUnindentOnBackspace, configuration.language.isCodeLanguage,
      removeCodeIndentationBeforeLine(at: date)
    {
      return
    }
    removeLastTypedCharacter()
    recordReplayEvent(kind: .delete, text: "", at: date)
  }

  /// Handles the platform's word-backward command (for example Option-Delete)
  /// without bypassing the same confidence and committed-word protections as
  /// ordinary backspace. Each removed character stays visible to replay.
  mutating func deleteWordBackward(at date: Date = .now) {
    guard !isFinished else { return }
    recordKeyboardActivity(at: date)
    guard !typed.isEmpty else { return }
    guard canDeleteBackward else { return }
    if configuration.rules.codeUnindentOnBackspace, configuration.language.isCodeLanguage,
      removeCodeIndentationBeforeLine(at: date)
    {
      return
    }

    var removedCurrentWord = false
    while let last = typed.last, !isPromptWordSeparator(last) {
      removeLastTypedCharacter()
      recordReplayEvent(kind: .delete, text: "", at: date)
      removedCurrentWord = true
    }
    guard !removedCurrentWord, typed.last.map(isPromptWordSeparator) == true else { return }

    removeLastTypedCharacter()
    recordReplayEvent(kind: .delete, text: "", at: date)
    while let last = typed.last, !isPromptWordSeparator(last) {
      removeLastTypedCharacter()
      recordReplayEvent(kind: .delete, text: "", at: date)
    }
  }

  private var canDeleteBackward: Bool {
    if configuration.rules.confidenceMode == .maximum { return false }
    guard !configuration.rules.freedomMode, typed.last.map(isPromptWordSeparator) == true else {
      return true
    }
    if configuration.rules.confidenceMode == .on { return false }
    let completedWords = splitPromptWords(
      String(typed.dropLast()), omittingEmptySubsequences: true)
    guard let typedWord = completedWords.last else { return true }
    let targetWords = splitPromptWords(prompt, omittingEmptySubsequences: true)
    let index = completedWords.count - 1
    guard index < targetWords.count else { return true }
    return typedWord != targetWords[index]
  }

  mutating func replaceInput(with value: String, at date: Date = .now) {
    guard !isFinished else { return }
    if value.count < typed.count {
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

  /// Zen has no automatic terminal condition. It completes only through its
  /// explicit Shift+Enter command after the user has begun entering text.
  mutating func finishZen(at date: Date = .now) {
    guard configuration.mode == .zen, !isFinished, startedAt != nil else { return }
    complete(at: date)
  }

  private mutating func beginIfNeeded(at date: Date) {
    if startedAt == nil {
      startedAt = date
      if activePhysicalKeyDownDates.count > 1 { physicalKeyOverlapStartedAt = date }
    }
  }

  /// The reference expands the typographic ellipsis only when it is not the
  /// character the prompt itself requests. This preserves literal ellipses
  /// in custom text while accepting the common macOS replacement for `...`.
  private mutating func shouldExpandReferenceEllipsis(_ character: Character) -> Bool {
    guard character == "…" else { return false }
    extendPromptIfNeeded()
    guard nextTargetIndex < prompt.count else { return true }
    return Array(prompt)[nextTargetIndex] != character
  }

  @discardableResult
  private mutating func insertCharacter(
    _ character: Character, forceError: Bool, at date: Date, evaluatesTerminalRules: Bool
  ) -> Bool {
    if configuration.mode == .zen {
      return insertZenCharacter(character, at: date, evaluatesTerminalRules: evaluatesTerminalRules)
    }
    // The reference input accepts several platform space characters as the
    // regular word separator, but no-space rejects every one of them before
    // it can reach validation or result statistics.
    if configuration.modifiers.contains(.noSpaces), isReferenceInputSpace(character) {
      return false
    }
    if character == "\n", !configuration.language.isCodeLanguage, !prompt.contains("\n") {
      return false
    }
    extendPromptIfNeeded()
    let currentTargetIndex = nextTargetIndex
    let inputCharacter = normalizedInputCharacter(
      character,
      expected: currentTargetIndex < prompt.count ? Array(prompt)[currentTargetIndex] : nil)
    let commitsCurrentWord = isPromptWordSeparator(inputCharacter) && !inputWordIsEmpty
    if let inputLimit = currentSpaceDelimitedWordInputLimit,
      activeInputWordLength >= inputLimit, !commitsCurrentWord
    {
      return false
    }
    if currentTargetIndex >= prompt.count {
      appendTypedCharacter(
        inputCharacter, targetIndex: nil,
        countsAsExtraError: inputCharacter != " " && hasUncommittedSpaceDelimitedInput, at: date)
      recordWordBurstIfCommitted()
      recordNoSpaceWordBurstIfCommitted()
      return true
    }
    // In normal difficulty, a leading separator is ignored unless the user
    // explicitly enables strict space or a hard delete rule needs the key to
    // reach its own recovery path. Other difficulties keep the key as a
    // correctable input error instead of silently skipping it.
    if inputCharacter == " " && inputWordIsEmpty && shouldRejectLeadingSeparator {
      return false
    }
    let expected = Array(prompt)[currentTargetIndex]
    let retainsCurrentWordAsExtra = shouldRetainInCurrentWord(
      inputCharacter, expected: expected)
    let earlyWordCommitTargetIndex = incompleteWordCommitTargetIndex(
      for: inputCharacter, currentTargetIndex: currentTargetIndex)
    let targetIndex = retainsCurrentWordAsExtra
      ? nil : earlyWordCommitTargetIndex ?? currentTargetIndex
    let isCorrect = !retainsCurrentWordAsExtra && inputCharacter == expected && !forceError
    if !isCorrect { attemptedErrorCounts[currentTargetIndex, default: 0] += 1 }
    let blocksNoSpaceWordAdvance = shouldBlockNoSpaceWordAdvance(
      with: inputCharacter, forceError: forceError)
    if configuration.modifiers.contains(.correctBeforeAdvance),
      (configuration.language.usesSpaceDelimitedWords || tracksNoSpaceWordBursts),
      ((isPromptWordSeparator(inputCharacter) && !configuration.modifiers.contains(.noSpaces)
        && !currentWordIsCorrect)
        || blocksNoSpaceWordAdvance)
    {
      return false
    }
    if configuration.rules.stopOnErrorMode == .word,
      (configuration.language.usesSpaceDelimitedWords || tracksNoSpaceWordBursts),
      ((isPromptWordSeparator(inputCharacter) && !configuration.modifiers.contains(.noSpaces)
        && !currentWordIsCorrect)
        || blocksNoSpaceWordAdvance)
    {
      return false
    }
    if !isCorrect && configuration.rules.stopOnErrorMode == .letter { return false }
    if !isCorrect && configuration.rules.deleteOnErrorMode.isEnabled {
      deleteForError(configuration.rules.deleteOnErrorMode, at: date)
      return false
    }
    if !isCorrect && configuration.modifiers.contains(.clearCurrentWordOnError),
      configuration.language.usesSpaceDelimitedWords, !configuration.modifiers.contains(.noSpaces)
    {
      clearCurrentWord(at: date)
      return false
    }
    appendTypedCharacter(
      inputCharacter, targetIndex: targetIndex,
      forceError: forceError || earlyWordCommitTargetIndex != nil,
      countsAsExtraError: retainsCurrentWordAsExtra, at: date)
    recordWordBurstIfCommitted()
    recordNoSpaceWordBurstIfCommitted()

    if evaluatesTerminalRules, configuration.difficulty == .master && !isCorrect {
      fail(at: date)
    } else if evaluatesTerminalRules, configuration.difficulty == .expert
      && ((commitsCurrentWord && (!isCorrect || errorsInCurrentWord() > 0)) || committedNoSpaceWordHasError)
    {
      fail(at: date)
    } else if evaluatesTerminalRules, shouldFailMinimumWordBurst(after: inputCharacter) {
      fail(at: date)
    }
    return true
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

    appendTypedCharacter(character, targetIndex: nil, at: date)
    recordZenWordBurstIfCommitted(after: character)
    if evaluatesTerminalRules, shouldFailMinimumWordBurst(after: character) { fail(at: date) }
    return true
  }

  private var currentWordIsCorrect: Bool {
    let targetWords = splitPromptWords(prompt, omittingEmptySubsequences: true)
    let typedWords = splitPromptWords(typed, omittingEmptySubsequences: false)
    let wordIndex = typed.last.map(isPromptWordSeparator) == true
      ? max(typedWords.count - 1, 0) : typedWords.count - 1
    guard wordIndex >= 0, wordIndex < targetWords.count, wordIndex < typedWords.count else {
      return false
    }
    return typedWords[wordIndex] == targetWords[wordIndex] && !hasForcedError(inWord: wordIndex)
  }

  /// Removes accepted characters from the active, unfinished word while
  /// preserving any already submitted words. Each removal becomes a replay
  /// event so result playback reconstructs the same input state.
  private mutating func clearCurrentWord(at date: Date) {
    if let range = activeNoSpaceWordRange {
      while typed.count > range.lowerBound {
        removeLastTypedCharacter()
        recordReplayEvent(kind: .delete, text: "", at: date)
      }
      return
    }
    while let last = typed.last, !isPromptWordSeparator(last) {
      removeLastTypedCharacter()
      recordReplayEvent(kind: .delete, text: "", at: date)
    }
  }

  /// Applies an original native equivalent of the selectable delete-on-error
  /// modes. The failed key remains in `attemptedErrorCounts`; only accepted
  /// text is removed, so metrics and replay stay internally consistent.
  private mutating func deleteForError(_ mode: DeleteOnErrorMode, at date: Date) {
    let activeWordIsEmpty = typed.isEmpty || typed.last.map(isPromptWordSeparator) == true
      || activeNoSpaceWordRange.map { typed.count == $0.lowerBound } == true
    if mode.returnsToPreviousWordAtStart && activeWordIsEmpty,
      ((configuration.language.usesSpaceDelimitedWords
        && !configuration.modifiers.contains(.noSpaces)) || tracksNoSpaceWordBursts), !typed.isEmpty
    {
      removePreviousWordForHardDelete(clearingWord: mode.clearsWholeWord, at: date)
      return
    }
    if mode.clearsWholeWord {
      clearCurrentWord(at: date)
    } else {
      removeLastCharacterFromCurrentWord(at: date)
    }
  }

  private mutating func removeLastCharacterFromCurrentWord(at date: Date) {
    guard let last = typed.last, !last.isWhitespace else { return }
    removeLastTypedCharacter()
    recordReplayEvent(kind: .delete, text: "", at: date)
  }

  private mutating func removePreviousWordForHardDelete(clearingWord: Bool, at date: Date) {
    if tracksNoSpaceWordBursts,
      let wordIndex = noSpaceWordEndIndices.firstIndex(of: typed.count),
      let previousRange = noSpaceWordRange(for: wordIndex)
    {
      if clearingWord {
        while typed.count > previousRange.lowerBound {
          removeLastTypedCharacter()
          recordReplayEvent(kind: .delete, text: "", at: date)
        }
      } else {
        removeLastTypedCharacter()
        recordReplayEvent(kind: .delete, text: "", at: date)
      }
      return
    }
    guard typed.last.map(isPromptWordSeparator) == true else { return }
    removeLastTypedCharacter()
    recordReplayEvent(kind: .delete, text: "", at: date)
    if clearingWord {
      clearCurrentWord(at: date)
    }
  }

  private mutating func recordReplayEvent(
    kind: TypingReplayEventKind, text: String, forceError: Bool = false, automatic: Bool = false,
    at date: Date
  )
  {
    guard let startedAt else { return }
    replayEvents.append(
      .init(
        offset: max(0, date.timeIntervalSince(startedAt)), kind: kind, text: text,
        forceError: forceError, automatic: automatic))
  }

  private func errorsInCurrentWord() -> Int {
    let typedWords = splitPromptWords(typed, omittingEmptySubsequences: false)
    let promptWords = splitPromptWords(prompt, omittingEmptySubsequences: false)
    guard let typedWord = typedWords.dropLast().last, typedWords.count - 2 < promptWords.count
    else { return 0 }
    let promptWord = promptWords[typedWords.count - 2]
    let typedCharacters = Array(typed)
    let wordStart = typedCharacters.indices.reversed().first(where: {
      $0 < typedCharacters.count - 1 && isPromptWordSeparator(typedCharacters[$0])
    }).map { $0 + 1 } ?? 0
    return zip(typedWord, promptWord).enumerated().reduce(0) { total, pair in
      total + (pair.element.0 == pair.element.1 && !forcedErrorIndices.contains(wordStart + pair.offset) ? 0 : 1)
    } + max(0, typedWord.count - promptWord.count)
  }

  private func activeWordBurst(start: Int) -> Int? {
    let length = typedCharacterDates.count - start
    guard length >= 2, start >= 0, start < typedCharacterDates.count else { return nil }
    let elapsed = typedCharacterDates.last!.timeIntervalSince(typedCharacterDates[start])
    guard elapsed > 0 else { return nil }
    return wpm(characters: length + 1, seconds: elapsed)
  }

  private func wordBurst(from start: Int, through end: Int, includesTrailingSpace: Bool) -> Int? {
    guard start >= 0, end >= start, end < typedCharacterDates.count else { return nil }
    let elapsed = typedCharacterDates[end].timeIntervalSince(typedCharacterDates[start])
    guard elapsed > 0 else { return nil }
    let characters = end - start + 1 + (includesTrailingSpace ? 0 : 1)
    return wpm(characters: characters, seconds: elapsed)
  }

  private mutating func recordWordBurstIfCommitted() {
    let characters = Array(typed)
    guard characters.last.map(isPromptWordSeparator) == true,
      typedCharacterDates.count == characters.count
    else { return }
    let end = characters.count - 1
    var start = 0
    if end > 0, let separator = characters[..<end].lastIndex(where: isPromptWordSeparator) {
      start = separator + 1
    }
    guard start < end else { return }
    let elapsed = typedCharacterDates[end].timeIntervalSince(typedCharacterDates[start])
    guard elapsed > 0 else { return }
    committedWordBursts.append(wpm(characters: end - start + 1, seconds: elapsed))
  }

  private mutating func recordNoSpaceWordBurstIfCommitted() {
    guard let wordIndex = noSpaceCommittedWordIndex,
      typedCharacterDates.count == typed.count
    else { return }
    let start = wordIndex == 0 ? 0 : noSpaceWordEndIndices[wordIndex - 1]
    let end = noSpaceWordEndIndices[wordIndex] - 1
    guard start < end else { return }
    let elapsed = typedCharacterDates[end].timeIntervalSince(typedCharacterDates[start])
    guard elapsed > 0 else { return }
    // A no-space commit is the word's last letter rather than an entered
    // separator, so count the same virtual trailing character used by the
    // regular word-burst path.
    committedWordBursts.append(wpm(characters: end - start + 2, seconds: elapsed))
  }

  private mutating func recordZenWordBurstIfCommitted(after character: Character) {
    guard isZenWordCommit(character) else { return }
    let characters = Array(typed)
    guard typedCharacterDates.count == characters.count else { return }
    let end = characters.count - 1
    let start = characters[..<end].lastIndex(where: { isZenWordCommit($0) }).map { $0 + 1 } ?? 0
    guard start < end else { return }
    let elapsed = typedCharacterDates[end].timeIntervalSince(typedCharacterDates[start])
    guard elapsed > 0 else { return }
    committedWordBursts.append(wpm(characters: end - start + 1, seconds: elapsed))
  }

  private func shouldFailMinimumWordBurst(after character: Character) -> Bool {
    let minimum = configuration.rules.minimumWordBurstWpm
    let mode = configuration.rules.minimumWordBurstMode
    let commitsWord: Bool
    if configuration.mode == .zen {
      commitsWord = isZenWordCommit(character)
    } else if tracksNoSpaceWordBursts {
      commitsWord = noSpaceCommittedWordIndex != nil
    } else {
      commitsWord = isPromptWordSeparator(character) && configuration.language.usesSpaceDelimitedWords
        && !configuration.modifiers.contains(.noSpaces)
    }
    guard mode != .off, minimum > 0, commitsWord,
      let burst = committedWordBursts.last,
      let targetLength = lastCommittedBurstWordLength
    else { return false }
    let threshold = MinimumWordBurstPolicy.threshold(
      baseWpm: minimum, mode: mode, wordLength: targetLength)
    return burst < threshold
  }

  private var lastCommittedBurstWordLength: Int? {
    if configuration.mode == .zen {
      let characters = Array(typed)
      guard let last = characters.last, isZenWordCommit(last) else { return nil }
      let end = characters.count - 1
      let start = characters[..<end].lastIndex(where: { isZenWordCommit($0) }).map { $0 + 1 } ?? 0
      return end - start + 1
    }
    if let wordIndex = noSpaceCommittedWordIndex {
      let start = wordIndex == 0 ? 0 : noSpaceWordEndIndices[wordIndex - 1]
      return noSpaceWordEndIndices[wordIndex] - start
    }
    guard typed.last.map(isPromptWordSeparator) == true else { return nil }
    let committedWords = splitPromptWords(String(typed.dropLast()), omittingEmptySubsequences: true)
    let targetWords = splitPromptWords(prompt, omittingEmptySubsequences: true)
    guard committedWords.count > 0, committedWords.count <= targetWords.count else { return nil }
    return targetWords[committedWords.count - 1].count
  }

  private var zenActiveWordLength: Int {
    Array(typed).reversed().prefix { !isZenWordCommit($0) }.count
  }

  private func isZenWordCommit(_ character: Character) -> Bool {
    isPromptWordSeparator(character)
  }

  private var tracksNoSpaceWordBursts: Bool {
    (configuration.language.isNoSpaceLanguage
      || (configuration.language.usesSpaceDelimitedWords
        && configuration.modifiers.contains(.noSpaces)))
      && !noSpaceWordEndIndices.isEmpty
  }

  private var noSpaceCommittedWordIndex: Int? {
    guard tracksNoSpaceWordBursts else { return nil }
    return noSpaceWordEndIndices.firstIndex(of: typed.count)
  }

  /// No-space keeps a hidden word boundary after every source word. The final
  /// visible character is therefore the equivalent of an entered separator.
  private var nextNoSpaceCommittedWordIndex: Int? {
    guard tracksNoSpaceWordBursts else { return nil }
    return noSpaceWordEndIndices.firstIndex(of: typed.count + 1)
  }

  /// A no-space word remains actionable only when its original boundary is
  /// retained. Unsegmented content deliberately falls through to the legacy
  /// character-level behavior instead of guessing linguistic word breaks.
  private var activeNoSpaceWordRange: Range<Int>? {
    guard tracksNoSpaceWordBursts,
      let wordIndex = noSpaceWordEndIndices.firstIndex(where: { typed.count < $0 })
    else { return nil }
    return noSpaceWordRange(for: wordIndex)
  }

  /// Mirrors the reference product's explicit space set. Keep Return outside
  /// this group because custom prompts and Zen use it as a real newline.
  private func isReferenceInputSpace(_ character: Character) -> Bool {
    return [
      " ", "\u{2002}", "\u{2003}", "\u{2009}", "\u{3000}", "\u{00A0}", "\u{1680}", "\u{202F}",
      "\u{FEFF}", "\u{2007}", "\u{2008}", "\u{2004}", "\u{200A}", "\u{200B}",
    ].contains(character)
  }

  private func normalizedInputCharacter(_ character: Character, expected: Character?) -> Character {
    guard let expected else {
      return isReferenceInputSpace(character) ? " " : character
    }
    if (character == " " || expected == " ")
      && isReferenceInputSpace(character) && isReferenceInputSpace(expected)
    {
      return expected
    }
    if InputCharacterEquivalence.matches(character, expected) {
      return expected
    }
    return isReferenceInputSpace(character) ? " " : character
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
    typed.isEmpty || typed.last.map(isPromptWordSeparator) == true
  }

  private var hasUncommittedSpaceDelimitedInput: Bool {
    configuration.mode != .zen
      && configuration.language.usesSpaceDelimitedWords
      && !configuration.language.isCodeLanguage
      && !configuration.modifiers.contains(.noSpaces)
      && !inputWordIsEmpty
  }

  private var activeInputWordLength: Int {
    typed.reversed().prefix { !isPromptWordSeparator($0) }.count
  }

  /// Mirrors the reference guard of the current word, including its visible
  /// commit separator when one exists, plus twenty tolerated extra letters.
  private var currentSpaceDelimitedWordInputLimit: Int? {
    guard configuration.mode != .zen,
      configuration.language.usesSpaceDelimitedWords,
      !configuration.language.isCodeLanguage,
      !configuration.modifiers.contains(.noSpaces), !prompt.isEmpty
    else { return nil }
    let targetCharacters = Array(prompt)
    let targetIndex = min(nextTargetIndex, targetCharacters.count - 1)
    let wordStart = targetCharacters[..<targetIndex].lastIndex(where: isPromptWordSeparator)
      .map { $0 + 1 } ?? 0
    let wordEnd = targetCharacters[targetIndex...].firstIndex(where: isPromptWordSeparator)
      ?? targetCharacters.count
    let targetLength = wordEnd - wordStart + (wordEnd < targetCharacters.count ? 1 : 0)
    return targetLength + 20
  }

  /// The reference keeps letters beyond a word's target length in that same
  /// word buffer. They are visible errors but do not advance toward the next
  /// word until the user enters its separator.
  private func shouldRetainInCurrentWord(_ character: Character, expected: Character) -> Bool {
    !isPromptWordSeparator(character) && isPromptWordSeparator(expected)
      && hasUncommittedSpaceDelimitedInput
  }

  /// The target cursor is independent from raw input length when normal
  /// typing submits an incomplete word with space. All ordinary input keeps
  /// its original one-to-one mapping, including no-space and code prompts.
  private var nextTargetIndex: Int {
    guard let previousTargetIndex = typedTargetIndices.reversed().compactMap({ $0 }).first else {
      return 0
    }
    return min(previousTargetIndex + 1, prompt.count)
  }

  private func incompleteWordCommitTargetIndex(
    for character: Character, currentTargetIndex: Int
  ) -> Int? {
    guard isPromptWordSeparator(character),
      (!inputWordIsEmpty || (character == "\n" && shouldCommitLeadingNewline)),
      configuration.language.usesSpaceDelimitedWords,
      !configuration.language.isCodeLanguage,
      !configuration.modifiers.contains(.noSpaces)
    else { return nil }
    let targetCharacters = Array(prompt)
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
    let typedIndex = typed.count
    typed.append(character)
    typedTargetIndices.append(targetIndex)
    typedCharacterDates.append(date)
    if forceError, let targetIndex { forcedErrorIndices.insert(targetIndex) }
    if countsAsExtraError { extraErrorTypedIndices.insert(typedIndex) }
  }

  private mutating func removeLastTypedCharacter() {
    guard !typed.isEmpty else { return }
    let typedIndex = typed.count - 1
    let targetIndex = typedTargetIndices.popLast() ?? nil
    typed.removeLast()
    typedCharacterDates.removeLast()
    if let targetIndex { forcedErrorIndices.remove(targetIndex) }
    extraErrorTypedIndices.remove(typedIndex)
  }

  private func shouldBlockNoSpaceWordAdvance(with character: Character, forceError: Bool) -> Bool {
    guard tracksNoSpaceWordBursts,
      let wordIndex = nextNoSpaceCommittedWordIndex,
      let range = noSpaceWordRange(for: wordIndex)
    else { return false }

    let promptCharacters = Array(prompt)
    guard typed.count == range.upperBound - 1, range.upperBound <= promptCharacters.count else { return false }
    return range.contains { index in
      if index == typed.count {
        return character != promptCharacters[index] || forceError
      }
      return !isTypedCharacterCorrect(at: index)
    }
  }

  private func noSpaceWordRange(for wordIndex: Int) -> Range<Int>? {
    guard noSpaceWordEndIndices.indices.contains(wordIndex) else { return nil }
    let start = wordIndex == 0 ? 0 : noSpaceWordEndIndices[wordIndex - 1]
    let end = noSpaceWordEndIndices[wordIndex]
    guard start < end else { return nil }
    return start..<end
  }

  /// Expert difficulty evaluates a no-space word on its final visible
  /// character, the same logical point at which the reference product moves
  /// to its next retained word. Use the accepted text and forced physical
  /// input errors rather than historical attempts: a corrected word is valid.
  private var committedNoSpaceWordHasError: Bool {
    guard let wordIndex = noSpaceCommittedWordIndex,
      let range = noSpaceWordRange(for: wordIndex)
    else { return false }
    return range.contains { !isTypedCharacterCorrect(at: $0) }
  }

  private var lastCommittedWordIsCorrect: Bool {
    guard typed.last.map(isPromptWordSeparator) == true else { return false }
    let committedWords = splitPromptWords(String(typed.dropLast()), omittingEmptySubsequences: true)
    let targetWords = splitPromptWords(prompt, omittingEmptySubsequences: true)
    guard let submitted = committedWords.last, committedWords.count <= targetWords.count else {
      return false
    }
    return submitted == targetWords[committedWords.count - 1]
      && !hasForcedError(inWord: committedWords.count - 1)
  }

  private func isTypedCharacterCorrect(at index: Int) -> Bool {
    let typedCharacters = Array(typed)
    let targetCharacters = Array(prompt)
    guard targetCharacters.indices.contains(index),
      let typedIndex = typedTargetIndices.firstIndex(where: { $0 == index }),
      typedCharacters.indices.contains(typedIndex)
    else { return false }
    return typedCharacters[typedIndex] == targetCharacters[index] && !forcedErrorIndices.contains(index)
  }

  private mutating func insertCodeIndentationIfNeeded(after character: Character, at date: Date) {
    guard character == "\n", configuration.language.isCodeLanguage,
      isTypedCharacterCorrect(at: nextTargetIndex - 1)
    else { return }
    while nextTargetIndex < prompt.count, Array(prompt)[nextTargetIndex] == "\t" {
      appendTypedCharacter("\t", targetIndex: nextTargetIndex, at: date)
      recordReplayEvent(kind: .insert, text: "\t", automatic: true, at: date)
    }
  }

  private mutating func removeCodeIndentationBeforeLine(at date: Date) -> Bool {
    let typedCharacters = Array(typed)
    let lineStart = typedCharacters.lastIndex(of: "\n").map { $0 + 1 } ?? 0
    guard lineStart < typedCharacters.count,
      typedCharacters[lineStart...].allSatisfy({ $0 == "\t" }),
      typedCharacters.indices.filter({ $0 >= lineStart }).allSatisfy(isTypedCharacterCorrect)
    else { return false }
    while typed.last == "\t" {
      removeLastTypedCharacter()
      recordReplayEvent(kind: .delete, text: "", automatic: true, at: date)
    }
    guard typed.last == "\n" else { return false }
    removeLastTypedCharacter()
    recordReplayEvent(kind: .delete, text: "", automatic: true, at: date)
    return true
  }

  private func hasForcedError(inWord word: Int) -> Bool {
    hasError(inWord: word, indices: forcedErrorIndices)
  }

  private func hasAttemptedInputError(inWord word: Int) -> Bool {
    attemptedInputErrorCount(inWord: word) > 0
  }

  /// Word targets for result history and local follow-up practice. A flattened
  /// prompt is eligible only when its saved word slices still exactly match
  /// the current boundary list; otherwise there is no trustworthy word-level
  /// representation to expose.
  private var resultTargetWords: [String] {
    if hasNoSpaceWordSegmentation { return noSpaceTargetWords }
    guard configuration.language.usesSpaceDelimitedWords,
      !configuration.modifiers.contains(.noSpaces)
    else { return [] }
    return splitPromptWords(prompt, omittingEmptySubsequences: true).map(String.init)
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
      && noSpaceTargetWords.allSatisfy { !$0.isEmpty }
  }

  private func noSpaceWordReviews(targetWords: [String]) -> [TypedWordReview] {
    let typedCharacters = Array(typed)
    let directlyAttemptedCount = noSpaceWordRanges.lastIndex {
      typedCharacters.count > $0.lowerBound
    }.map { $0 + 1 } ?? 0
    let historicalAttemptedCount = targetWords.indices.last(where: hasAttemptedInputError)
      .map { $0 + 1 } ?? 0
    let attemptedCount = max(directlyAttemptedCount, historicalAttemptedCount)
    return (0..<min(attemptedCount, targetWords.count)).map { index in
      let range = noSpaceWordRanges[index]
      let typedEnd = min(range.upperBound, typedCharacters.count)
      let typedWord = typedEnd > range.lowerBound
        ? String(typedCharacters[range.lowerBound..<typedEnd]) : ""
      return .init(
        index: index, target: targetWords[index], typed: typedWord,
        hasInputError: typedWord == targetWords[index]
          && hasAttemptedInputError(inWord: index))
    }
  }

  private func hasError(inWord word: Int, indices: Set<Int>) -> Bool {
    guard let range = targetRange(forWord: word) else { return false }
    return indices.contains(where: range.contains)
  }

  private func attemptedInputErrorCount(inWord word: Int) -> Int {
    guard let range = targetRange(forWord: word) else { return 0 }
    return attemptedInputErrorCount(in: range)
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
    let targetCharacters = Array(prompt)
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
    Int((Double(characters) / 5 / seconds * 60).rounded())
  }

  private mutating func finishIfNeeded(at date: Date) {
    guard !isFinished else { return }
    switch configuration.mode {
    case .words:
      if configuration.language.isCodeLanguage {
        if nextTargetIndex >= prompt.count { complete(at: date) }
      } else if !configuration.language.usesSpaceDelimitedWords
        || configuration.modifiers.contains(.noSpaces)
      {
        if nextTargetIndex >= prompt.count { complete(at: date) }
      } else if shouldFinishEnglishWordsTest {
        complete(at: date)
      }
    case .quote:
      if shouldFinishFiniteSpaceDelimitedTest { complete(at: date) }
    case .custom:
      switch configuration.customTextCompletion {
      case .finish:
        if shouldFinishFiniteSpaceDelimitedTest { complete(at: date) }
      case .time:
        break
      case .words:
        if shouldFinishEnglishWordsTest { complete(at: date) }
      case .sections:
        if shouldFinishFiniteSpaceDelimitedTest { complete(at: date) }
      }
    case .time, .zen:
      break
    }
  }

  private mutating func extendPromptIfNeeded() {
    guard nextTargetIndex >= prompt.count, let repeatingPrompt, !repeatingPrompt.isEmpty else { return }
    let usesNoSpaceSeparator = configuration.modifiers.contains(.noSpaces)
    let separator = usesNoSpaceSeparator || prompt.last?.isWhitespace == true ? "" : " "
    let previousEnd = prompt.count + separator.count
    prompt += separator + repeatingPrompt
    guard usesNoSpaceSeparator, !repeatingNoSpaceWordLengths.isEmpty else { return }
    var end = previousEnd
    for length in repeatingNoSpaceWordLengths {
      end += length
      noSpaceWordEndIndices.append(end)
    }
    guard repeatingNoSpaceTargetWords.count == repeatingNoSpaceWordLengths.count else { return }
    noSpaceTargetWords += repeatingNoSpaceTargetWords
  }

  private var shouldFinishEnglishWordsTest: Bool {
    guard let wordLimit = configuration.wordLimit, wordLimit > 0 else { return false }
    let targetWords = Array(
      splitPromptWords(prompt, omittingEmptySubsequences: true).prefix(wordLimit))
    let typedWords = splitPromptWords(typed, omittingEmptySubsequences: true)
    guard targetWords.count == wordLimit, typedWords.count >= wordLimit,
      let expectedInput = targetInputThroughWord(wordLimit - 1)
    else { return false }

    // A correct final word always completes. A user can otherwise commit an
    // incorrect final word with space, matching normal typing behavior.
    if typed == expectedInput || typed.last.map(isPromptWordSeparator) == true { return true }

    // Quick end only applies at the final generated word and is deliberately
    // disabled when an error rule would reject the same character upstream.
    let allowsQuickEnd =
      configuration.rules.quickEnd
      && !configuration.rules.stopOnError
      && !configuration.rules.deleteOnError
    return allowsQuickEnd && typedWords[wordLimit - 1].count == targetWords[wordLimit - 1].count
  }

  /// Finite quotes and custom text use the same final-word rule as regular
  /// word tests: an incorrect word remains editable until its separator is
  /// entered, unless the optional quick-end rule explicitly applies.
  private var shouldFinishFiniteSpaceDelimitedTest: Bool {
    guard nextTargetIndex >= prompt.count else { return false }
    guard configuration.language.usesSpaceDelimitedWords,
      !configuration.modifiers.contains(.noSpaces)
    else { return true }
    if currentWordIsCorrect || typed.last.map(isPromptWordSeparator) == true { return true }
    guard configuration.rules.quickEnd,
      !configuration.rules.stopOnError,
      !configuration.rules.deleteOnError
    else { return false }
    guard let typedWord = splitPromptWords(typed, omittingEmptySubsequences: false).last,
      let targetWord = splitPromptWords(prompt, omittingEmptySubsequences: true).last
    else { return false }
    return typedWord.count == targetWord.count
  }

  /// The correct final word needs to retain its original preceding commit
  /// characters: a custom prompt can use a newline rather than a space.
  private func targetInputThroughWord(_ word: Int) -> String? {
    guard word >= 0 else { return nil }
    let targetCharacters = Array(prompt)
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
    if (configuration.rules.minimumAccuracy > 0 && accuracy < configuration.rules.minimumAccuracy)
      || (configuration.rules.minimumWpm > 0 && wpm(at: date) < configuration.rules.minimumWpm)
    {
      fail(at: date)
    } else {
      finishedAt = date
      outcome = hasTrailingInactivity(endingAt: date) ? .invalidAFK : .completed
    }
  }

  private func hasTrailingInactivity(endingAt date: Date) -> Bool {
    guard let startedAt else { return false }
    return TestInactivityPolicy.hasTrailingInactivity(
      insertionDates: insertionActivityDates, startedAt: startedAt, endedAt: date,
      includesFractionalTail: configuration.duration == nil)
  }

  private mutating func fail(at date: Date) {
    outcome = .failed
    finishedAt = date
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

  subscript(position: Int) -> String {
    precondition(indices.contains(position))
    return wordAt(position)
  }

  func materialized() -> [String] {
    indices.map { self[$0] }
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

  private static func cyrillicIndex(_ index: Int) -> String {
    var value = index
    var characters: [Character] = []
    repeat {
      characters.append(cyrillicScaleAlphabet[value % cyrillicScaleAlphabet.count])
      value /= cyrillicScaleAlphabet.count
    } while value > 0
    return String(characters.reversed())
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
    precondition(count > max(uppercaseCount + 2, nonASCIICount + 2))
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
        if index < nonASCIICount + 2 {
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

  static var french1kWords: [String] { french1kLexicon.materialized() }
  static var french2kWords: [String] { french2kLexicon.materialized() }
  static var french10kWords: [String] { french10kLexicon.materialized() }

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

  // Original Typebar content for traditional Chinese practice. It is authored
  // separately from the simplified Chinese starter corpus.
  static let traditionalChineseWords = [
    "晨霧", "海灣", "筆記", "微雨", "松林", "專注", "緩步", "清楚", "河岸", "茶香",
    "街燈", "木門", "書頁", "旅途", "耐心", "片刻", "山徑", "風鈴", "安靜", "方向",
    "星群", "畫布", "庭院", "呼吸",
  ]

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

  // Original Typebar content for Turkish practice, including dotted and
  // dotless i plus commonly used Turkish diacritics.
  static let turkishWords = [
    "sabah", "pencere", "kağıt", "kıyı", "rüzgar", "alıştırma", "odak", "sakin",
    "açık", "göl", "sokak", "masa", "ışık", "yolculuk", "sabır", "an",
    "şehir", "yağmur", "sessiz", "yön", "yıldız", "not", "bahçe", "nefes",
  ]

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

  // Typebar-authored Afrikaans starter words. Diacritics remain in the local
  // corpus for native macOS composed-text practice without imported word lists.
  static let afrikaansWords = [
    "môre", "venster", "papier", "kus", "wind", "oefening", "aandag", "rustig",
    "helder", "meer", "straat", "tafel", "lig", "reis", "geduld", "oomblik",
    "stad", "reën", "stilte", "rigting", "ster", "nota", "tuin", "asem",
    "klein", "tyd", "lente", "veld", "boot", "vriend", "wêreld",
  ]

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

  // Typebar-authored Crimean Tatar starter words keep the Latin script path
  // separate from its Cyrillic counterpart without importing either reference
  // dictionary or word list.
  static let tatarCrimeanWords = [
    "selâm", "men", "sen", "biz", "qırım", "kitap", "qalem", "pencere", "yol", "ışıq",
    "köprü", "saba", "kâğıt", "bağ", "bulut", "sükûnet", "lampa", "dağ", "tohum", "muzıka",
    "masa", "fikir", "not", "iş", "tecrübe", "dost", "şeer", "deniz", "köy", "vaqıt",
    "ses", "sual", "cevap", "ümit", "kelecek",
  ]

  // Typebar-authored Crimean Tatar Cyrillic starter words intentionally use
  // their own corpus so script selection stays visible in offline practice.
  static let tatarCrimeanCyrillicWords = [
    "селям", "мен", "сен", "биз", "къырым", "китап", "къалем", "пенджере", "ёл", "ышык",
    "копрю", "саба", "кягъыт", "багъ", "булут", "сукюнет", "лампа", "дагъ", "тохум", "музыка",
    "маса", "фикир", "нот", "иш", "теджрюбе", "дост", "шеер", "дениз", "кой", "вакъыт",
    "сес", "суаль", "джевап", "юмют", "келеджек",
  ]

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

  // Typebar-authored Occitan starter words provide local practice without
  // importing the reference dictionary or word list.
  static let occitanWords = [
    "libre", "pòrta", "camin", "lutz", "pont", "matin", "fuèlh", "jardin", "nivol", "calma",
    "montanha", "grana", "votz", "taula", "pensada", "nòta", "agach", "ensag", "distància", "pas",
    "paciéncia", "equilibri", "vilatge", "pluèja", "estela", "amic", "espèr", "trabalh", "rius", "prima",
  ]

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

  // Typebar-authored Malay starter words are compact local practice content,
  // not an imported word list or a transformed reference corpus.
  static let malayWords = [
    "pagi", "tingkap", "kertas", "pantai", "angin", "latihan", "perhatian", "tenang",
    "jelas", "tasik", "jalan", "meja", "cahaya", "perjalanan", "kesabaran", "seketika",
    "bandar", "hujan", "sunyi", "arah", "bintang", "catatan", "taman", "nafas",
    "kecil", "masa", "musim", "perahu", "sahabat", "harapan",
  ]

  // Typebar-authored Arabic starter words use direct Unicode text and short
  // vowel marks for macOS Arabic input sources; they are not an imported
  // word list. Arabic simplified input can independently remove those marks.
  static let arabicWords = [
    "كِتاب", "قَلَم", "نافِذة", "طَريق", "ضَوْء", "جِسْر", "صَباح", "وَرَقة", "حَديقة", "سَحابة",
    "هُدوء", "مَنارة", "جَبَل", "بِذرة", "إيقاع", "مَكْتَب", "تَأَمُّل", "مُلاحَظة", "فِكْرة", "تَجْرِبة",
    "مَسافة", "خُطْوة", "صَبْر", "تَوازُن",
  ]

  // Typebar-authored Egyptian Arabic starter words are an independent local
  // dialect practice corpus. They do not import Monkeytype's word lists;
  // macOS supplies the Arabic joining glyph shaping for this RTL prompt.
  static let arabicEgyptWords = [
    "دلوقتي", "بكرة", "شباك", "شارع", "قهوة", "شغل", "صاحب", "مركب", "بحر", "نور",
    "صوت", "هدوء", "خطوة", "مساحة", "فكرة", "كراسة", "رسالة", "وقت", "حكاية", "مكان",
    "طريق", "موسيقى", "صورة", "تجربة", "راحة", "لمحة", "مفتاح", "نقطة", "اختيار", "محاولة",
  ]

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

  // Typebar-authored Persian starter words use direct Unicode text for macOS
  // Persian input sources; they are not an imported word list.
  static let persianWords = [
    "کتاب", "قلم", "پنجره", "راه", "نور", "پل", "صبح", "کاغذ", "باغ", "ابر",
    "آرامش", "فانوس", "کوه", "بذر", "آهنگ", "میز", "اندیشه", "یادداشت", "ایده", "تجربه",
    "فاصله", "گام", "صبر", "تعادل",
  ]

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

  // Typebar-authored Bangla starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let banglaWords = [
    "আলো", "নদী", "পাতা", "ঘুড়ি", "মেঘ", "বই", "কলম", "জানালা", "সেতু", "বাগান",
    "সকাল", "সুর", "চিঠি", "পথ", "তারা", "ছবি", "প্রশ্ন", "উত্তর", "কল্পনা", "বিরতি",
    "সাহস", "ধৈর্য", "ছন্দ", "যাত্রা",
  ]

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

  // Typebar-authored Nepali starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let nepaliWords = [
    "किताब", "कलम", "झ्याल", "बाटो", "उज्यालो", "पुल", "बिहान", "कागज", "बगैँचा", "बादल",
    "शान्ति", "दियो", "पहाड", "बीउ", "सङ्गीत", "टेबल", "विचार", "टिपोट", "कल्पना", "प्रयास",
    "दूरी", "कदम", "धैर्य", "सन्तुलन",
  ]

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

  // Typebar-authored Norwegian Nynorsk starter words. These are independent
  // from the Bokmål corpus and include Nynorsk-specific spelling practice.
  static let norwegianNynorskWords = [
    "morgon", "vindauge", "papir", "strand", "vind", "øving", "merksemd", "roleg",
    "klår", "vatn", "gate", "bord", "lys", "reise", "tolmod", "stund",
    "by", "regn", "stille", "retning", "stjerne", "notat", "hage", "andning",
    "liten", "tid", "vår", "øy", "ven", "ikkje", "kvar", "noko",
  ]

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
    case .traditionalChinese: traditionalChineseWords
    case .japaneseHiragana: japaneseHiraganaWords
    case .japaneseKatakana: japaneseKatakanaWords
    case .japaneseRomaji: japaneseRomajiWords
    default: nil
    }
  }

  static func prompt(
    wordCount: Int, language: TypingLanguage, englishVariant: EnglishVariant = .american,
    mixedLanguageComponents: [TypingLanguage] = TypingLanguage.defaultMixedComponents,
    contentOptions: ContentOptions, usesZipfFrequency: Bool = false
  ) -> String {
    let count = max(1, wordCount)
    if language.isCodeLanguage {
      return CodePracticeContent.prompt(language: language, targetTokenCount: count)
    }
    switch language {
    case .english:
      return prompt(
        tokens: count, lexicon: englishVariant == .british ? britishWords : words, separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .english1k:
      return prompt(
        tokens: count, lexicon: english1kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .english5k:
      return prompt(
        tokens: count, lexicon: english5kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .english10k:
      return prompt(
        tokens: count, lexicon: english10kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .english25k:
      return prompt(
        tokens: count, lexicon: english25kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .english450k:
      return prompt(
        tokens: count, lexicon: english450kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .englishFiveLetter:
      return prompt(
        tokens: count, lexicon: englishFiveLetterWords, separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishCommonlyMisspelled:
      return prompt(
        tokens: count, lexicon: englishCommonlyMisspelledWords, separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishContractions:
      return prompt(
        tokens: count, lexicon: englishContractionWords, separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishDoubleLetter:
      return prompt(
        tokens: count, lexicon: englishDoubleLetterWords, separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishLegal:
      return prompt(
        tokens: count, lexicon: englishLegalWords, separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishMedical:
      return prompt(
        tokens: count, lexicon: englishMedicalWords, separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .englishShakespearean:
      return prompt(
        tokens: count, lexicon: englishShakespeareanWords, separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .oldEnglish:
      return prompt(
        tokens: count, lexicon: oldEnglishWords, separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .kokanu:
      return prompt(
        tokens: count, lexicon: kokanuWords, separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .likanu:
      return prompt(
        tokens: count, lexicon: likanuWords, separator: " ",
        punctuation: ["､", ":", "ʭ", "≈"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .pigLatin:
      return prompt(
        tokens: count, lexicon: pigLatinWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .spanish:
      return prompt(
        tokens: count, lexicon: spanishWords, separator: " ", punctuation: [",", ".", "¡", "¿"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .spanish1k:
      return prompt(
        tokens: count, lexicon: spanish1kLexicon, separator: " ", punctuation: [",", ".", "¡", "¿"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .spanish10k:
      return prompt(
        tokens: count, lexicon: spanish10kLexicon, separator: " ", punctuation: [",", ".", "¡", "¿"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .spanish650k:
      return prompt(
        tokens: count, lexicon: spanish650kLexicon, separator: " ", punctuation: [",", ".", "¡", "¿"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .german:
      return prompt(
        tokens: count, lexicon: germanWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .german1k:
      return prompt(
        tokens: count, lexicon: german1kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .german10k:
      return prompt(
        tokens: count, lexicon: german10kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .german250k:
      return prompt(
        tokens: count, lexicon: german250kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .swissGerman:
      return prompt(
        tokens: count, lexicon: swissGermanWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .afrikaans:
      return prompt(
        tokens: count, lexicon: afrikaansWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .albanian:
      return prompt(
        tokens: count, lexicon: albanianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .bemba:
      return prompt(
        tokens: count, lexicon: bembaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .bosnian:
      return prompt(
        tokens: count, lexicon: bosnianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .esperanto:
      return prompt(
        tokens: count, lexicon: esperantoWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .esperantoXSystem:
      return prompt(
        tokens: count, lexicon: esperantoXSystemWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .esperantoHSystem:
      return prompt(
        tokens: count, lexicon: esperantoHSystemWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .latin:
      return prompt(
        tokens: count, lexicon: latinWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .loremIpsum:
      return prompt(
        tokens: count, lexicon: loremIpsumWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .git:
      return prompt(
        tokens: count, lexicon: gitWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .twitchEmotes:
      return prompt(
        tokens: count, lexicon: twitchEmoteWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .typingOfTheDead:
      return sectionPrompt(
        tokens: count, sections: typingOfTheDeadSections, contentOptions: contentOptions)
    case .pokemon1k:
      return entryPrompt(
        tokens: count, entries: creatureIndexEntries, contentOptions: contentOptions)
    case .arenaStrategy:
      return entryPrompt(
        tokens: count, entries: arenaStrategyEntries, contentOptions: contentOptions,
        lowercasesWithoutPunctuation: true)
    case .friulian:
      return prompt(
        tokens: count, lexicon: friulianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .malagasy:
      return prompt(
        tokens: count, lexicon: malagasyWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .welsh:
      return prompt(
        tokens: count, lexicon: welshWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hausa:
      return prompt(
        tokens: count, lexicon: hausaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tatar:
      return prompt(
        tokens: count, lexicon: tatarWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tatarCrimean:
      return prompt(
        tokens: count, lexicon: tatarCrimeanWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tatarCrimeanCyrillic:
      return prompt(
        tokens: count, lexicon: tatarCrimeanCyrillicWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .klingon:
      return prompt(
        tokens: count, lexicon: klingonWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .quenya:
      return prompt(
        tokens: count, lexicon: quenyaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .viossa:
      return prompt(
        tokens: count, lexicon: viossaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .viossaNjutro:
      return prompt(
        tokens: count, lexicon: viossaNjutroWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .maori:
      return prompt(
        tokens: count, lexicon: maoriWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .lojbanGismu:
      return prompt(
        tokens: count, lexicon: lojbanGismuWords, separator: " ", punctuation: [",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .lojbanCmavo:
      return prompt(
        tokens: count, lexicon: lojbanCmavoWords, separator: " ", punctuation: [",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .uzbek:
      return prompt(
        tokens: count, lexicon: uzbekWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .occitan:
      return prompt(
        tokens: count, lexicon: occitanWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .oromo:
      return prompt(
        tokens: count, lexicon: oromoWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .macedonian:
      return prompt(
        tokens: count, lexicon: macedonianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .kazakh:
      return prompt(
        tokens: count, lexicon: kazakhWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .vietnamese:
      return prompt(
        tokens: count, lexicon: vietnameseWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .jyutping:
      return prompt(
        tokens: count, lexicon: jyutpingWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .pinyin:
      return prompt(
        tokens: count, lexicon: pinyinWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .bashkir:
      return prompt(
        tokens: count, lexicon: bashkirWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .basque:
      return prompt(
        tokens: count, lexicon: basqueWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .frisian:
      return prompt(
        tokens: count, lexicon: frisianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .zulu:
      return prompt(
        tokens: count, lexicon: zuluWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hawaiian:
      return prompt(
        tokens: count, lexicon: hawaiianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .kabyle:
      return prompt(
        tokens: count, lexicon: kabyleWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .maltese:
      return prompt(
        tokens: count, lexicon: malteseWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tokiPona:
      return prompt(
        tokens: count, lexicon: tokiPonaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tokiPonaKuSuli:
      return prompt(
        tokens: count, lexicon: tokiPonaKuSuliWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tokiPonaKuLili:
      return prompt(
        tokens: count, lexicon: tokiPonaKuLiliWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .xhosa:
      return prompt(
        tokens: count, lexicon: xhosaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tibetan:
      return prompt(
        tokens: count, lexicon: tibetanWords, separator: " ", punctuation: ["།"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .kyrgyz:
      return prompt(
        tokens: count, lexicon: kyrgyzWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .udmurt:
      return prompt(
        tokens: count, lexicon: udmurtWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .yoruba:
      return prompt(
        tokens: count, lexicon: yorubaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .swahili:
      return prompt(
        tokens: count, lexicon: swahiliWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .kinyarwanda:
      return prompt(
        tokens: count, lexicon: kinyarwandaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .shona:
      return prompt(
        tokens: count, lexicon: shonaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .santali:
      return prompt(
        tokens: count, lexicon: santaliWords, separator: " ", punctuation: ["᱾", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .yiddish:
      return prompt(
        tokens: count, lexicon: yiddishWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .arabic:
      return prompt(
        tokens: count, lexicon: arabicWords, separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .arabicEgypt:
      return prompt(
        tokens: count, lexicon: arabicEgyptWords, separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .arabicMorocco:
      return prompt(
        tokens: count, lexicon: arabicMoroccoWords, separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .pashto:
      return prompt(
        tokens: count, lexicon: pashtoWords, separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .sindhi:
      return prompt(
        tokens: count, lexicon: sindhiWords, separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hebrew:
      return prompt(
        tokens: count, lexicon: hebrewWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .persian:
      return prompt(
        tokens: count, lexicon: persianWords, separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .persianRomanized:
      return prompt(
        tokens: count, lexicon: persianRomanizedWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .urdu:
      return prompt(
        tokens: count, lexicon: urduWords, separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .urduRoman:
      return prompt(
        tokens: count, lexicon: urduRomanWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .urdish:
      return prompt(
        tokens: count, lexicon: urdishWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tamil:
      return prompt(
        tokens: count, lexicon: tamilWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tamilOld:
      return entryPrompt(tokens: count, entries: tamilOldWords, contentOptions: contentOptions)
    case .tanglish:
      return prompt(
        tokens: count, lexicon: tanglishWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hindi:
      return prompt(
        tokens: count, lexicon: hindiWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hinglish:
      return prompt(
        tokens: count, lexicon: hinglishWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .gujarati:
      return prompt(
        tokens: count, lexicon: gujaratiWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .bangla:
      return prompt(
        tokens: count, lexicon: banglaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .banglaLetters:
      return prompt(
        tokens: count, lexicon: banglaLetterWords, separator: " ", punctuation: ["।", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .thai:
      return prompt(
        tokens: count, lexicon: thaiWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .nepali:
      return prompt(
        tokens: count, lexicon: nepaliWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .nepaliRomanized:
      return prompt(
        tokens: count, lexicon: nepaliRomanizedWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .kannada:
      return prompt(
        tokens: count, lexicon: kannadaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .telugu:
      return prompt(
        tokens: count, lexicon: teluguWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .malayalam:
      return prompt(
        tokens: count, lexicon: malayalamWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .sanskrit:
      return prompt(
        tokens: count, lexicon: sanskritWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .sanskritRoman:
      return prompt(
        tokens: count, lexicon: sanskritRomanWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .sinhala:
      return prompt(
        tokens: count, lexicon: sinhalaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .khmer:
      return prompt(
        tokens: count, lexicon: khmerWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .myanmarBurmese:
      return prompt(
        tokens: count, lexicon: myanmarBurmeseWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .lao:
      return prompt(
        tokens: count, lexicon: laoWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .amharic:
      return prompt(
        tokens: count, lexicon: amharicWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .armenian:
      return prompt(
        tokens: count, lexicon: armenianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .armenianWestern:
      return prompt(
        tokens: count, lexicon: armenianWesternWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .georgian:
      return prompt(
        tokens: count, lexicon: georgianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .azerbaijani:
      return prompt(
        tokens: count, lexicon: azerbaijaniWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian:
      return prompt(
        tokens: count, lexicon: belarusianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian1k:
      return prompt(
        tokens: count, lexicon: belarusian1kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian5k:
      return prompt(
        tokens: count, lexicon: belarusian5kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian10k:
      return prompt(
        tokens: count, lexicon: belarusian10kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian25k:
      return prompt(
        tokens: count, lexicon: belarusian25kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian50k:
      return prompt(
        tokens: count, lexicon: belarusian50kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusian100k:
      return prompt(
        tokens: count, lexicon: belarusian100kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .belarusianLacinka:
      return prompt(
        tokens: count, lexicon: belarusianLacinkaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .lithuanian:
      return prompt(
        tokens: count, lexicon: lithuanianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .latvian:
      return prompt(
        tokens: count, lexicon: latvianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .mongolian:
      return prompt(
        tokens: count, lexicon: mongolianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .irish:
      return prompt(
        tokens: count, lexicon: irishWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .galician:
      return prompt(
        tokens: count, lexicon: galicianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .marathi:
      return prompt(
        tokens: count, lexicon: marathiWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .kurdishCentral:
      return prompt(
        tokens: count, lexicon: kurdishCentralWords, separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .greek:
      return prompt(
        tokens: count, lexicon: greekWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .greekKoine:
      return prompt(
        tokens: count, lexicon: greekKoineWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .greeklish:
      return prompt(
        tokens: count, lexicon: greeklishWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .dutch:
      return prompt(
        tokens: count, lexicon: dutchWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .filipino:
      return prompt(
        tokens: count, lexicon: filipinoWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .catalan:
      return prompt(
        tokens: count, lexicon: catalanWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .indonesian:
      return prompt(
        tokens: count, lexicon: indonesianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .malay:
      return prompt(
        tokens: count, lexicon: malayWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .danish:
      return prompt(
        tokens: count, lexicon: danishWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianBokmal:
      return prompt(
        tokens: count, lexicon: norwegianBokmalWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .norwegianNynorsk:
      return prompt(
        tokens: count, lexicon: norwegianNynorskWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .swedish:
      return prompt(
        tokens: count, lexicon: swedishWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .swedishDiacritics:
      return prompt(
        tokens: count, lexicon: swedishDiacriticsWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hungarian:
      return prompt(
        tokens: count, lexicon: hungarianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .czech:
      return prompt(
        tokens: count, lexicon: czechWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .slovak:
      return prompt(
        tokens: count, lexicon: slovakWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .slovenian:
      return prompt(
        tokens: count, lexicon: slovenianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .croatian:
      return prompt(
        tokens: count, lexicon: croatianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .serbian:
      return prompt(
        tokens: count, lexicon: serbianWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .serbianLatin:
      return prompt(
        tokens: count, lexicon: serbianLatinWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .bulgarian:
      return prompt(
        tokens: count, lexicon: bulgarianWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .bulgarianLatin:
      return prompt(
        tokens: count, lexicon: bulgarianLatinWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian:
      return prompt(
        tokens: count, lexicon: romanianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian1k:
      return prompt(
        tokens: count, lexicon: romanian1kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian5k:
      return prompt(
        tokens: count, lexicon: romanian5kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian10k:
      return prompt(
        tokens: count, lexicon: romanian10kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian25k:
      return prompt(
        tokens: count, lexicon: romanian25kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian50k:
      return prompt(
        tokens: count, lexicon: romanian50kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian100k:
      return prompt(
        tokens: count, lexicon: romanian100kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .romanian200k:
      return prompt(
        tokens: count, lexicon: romanian200kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .finnish:
      return prompt(
        tokens: count, lexicon: finnishWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .estonian:
      return prompt(
        tokens: count, lexicon: estonianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .icelandic:
      return prompt(
        tokens: count, lexicon: icelandicWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .french:
      return prompt(
        tokens: count, lexicon: frenchWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .french1k:
      return prompt(
        tokens: count, lexicon: french1kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .french2k:
      return prompt(
        tokens: count, lexicon: french2kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .french10k:
      return prompt(
        tokens: count, lexicon: french10kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .frenchBitoduc:
      return prompt(
        tokens: count, lexicon: frenchBitoducWords, separator: " ",
        punctuation: [",", ".", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .italian:
      return prompt(
        tokens: count, lexicon: italianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese:
      return prompt(
        tokens: count, lexicon: portugueseWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese1k:
      return prompt(
        tokens: count, lexicon: portuguese1kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese3k:
      return prompt(
        tokens: count, lexicon: portuguese3kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese5k:
      return prompt(
        tokens: count, lexicon: portuguese5kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese320k:
      return prompt(
        tokens: count, lexicon: portuguese320kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese550k:
      return prompt(
        tokens: count, lexicon: portuguese550kLexicon, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portugueseAccents:
      return prompt(
        tokens: count, lexicon: portugueseAccentsWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .simplifiedChinese:
      return prompt(
        tokens: count, lexicon: simplifiedChineseWords, separator: "",
        punctuation: ["，", "。", "！", "？"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .traditionalChinese:
      return prompt(
        tokens: count, lexicon: traditionalChineseWords, separator: "",
        punctuation: ["，", "。", "！", "？"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .russian:
      return prompt(
        tokens: count, lexicon: russianWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian1k:
      return prompt(
        tokens: count, lexicon: russian1kLexicon, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian5k:
      return prompt(
        tokens: count, lexicon: russian5kLexicon, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian10k:
      return prompt(
        tokens: count, lexicon: russian10kLexicon, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian25k:
      return prompt(
        tokens: count, lexicon: russian25kLexicon, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian50k:
      return prompt(
        tokens: count, lexicon: russian50kLexicon, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russian375k:
      return prompt(
        tokens: count, lexicon: russian375kLexicon, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russianAbbreviations:
      return prompt(
        tokens: count, lexicon: russianAbbreviationWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .russianContractions:
      return entryPrompt(
        tokens: count, entries: russianShortFormWords, contentOptions: contentOptions,
        lowercasesWithoutPunctuation: true)
    case .russianContractions1k:
      return entryPrompt(
        tokens: count, entries: russianShortForm1kWords, contentOptions: contentOptions,
        lowercasesWithoutPunctuation: true)
    case .ukrainian:
      return prompt(
        tokens: count, lexicon: ukrainianWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainianEndings:
      return prompt(
        tokens: count, lexicon: ukrainianEndingWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainianLatin:
      return prompt(
        tokens: count, lexicon: ukrainianLatinWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainianLatynkaEndings:
      return prompt(
        tokens: count, lexicon: ukrainianLatynkaEndingWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .japaneseHiragana:
      return prompt(
        tokens: count, lexicon: japaneseHiraganaWords, separator: "",
        punctuation: ["、", "。", "！", "？"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .japaneseKatakana:
      return prompt(
        tokens: count, lexicon: japaneseKatakanaWords, separator: "",
        punctuation: ["、", "。", "！", "？"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .japaneseRomaji:
      return prompt(
        tokens: count, lexicon: japaneseRomajiWords, separator: " ",
        punctuation: [".", ",", "!", "?"], contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    case .korean:
      return prompt(
        tokens: count, lexicon: koreanWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .turkish:
      return prompt(
        tokens: count, lexicon: turkishWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish:
      return prompt(
        tokens: count, lexicon: polishWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish2k:
      return prompt(
        tokens: count, lexicon: polish2kLexicon, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish5k:
      return prompt(
        tokens: count, lexicon: polish5kLexicon, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish10k:
      return prompt(
        tokens: count, lexicon: polish10kLexicon, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish20k:
      return prompt(
        tokens: count, lexicon: polish20kLexicon, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish40k:
      return prompt(
        tokens: count, lexicon: polish40kLexicon, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .polish200k:
      return prompt(
        tokens: count, lexicon: polish200kLexicon, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
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
        source(for: $0, englishVariant: englishVariant)
      }
      return (0..<count).map { index in
        let source = sources[index % sources.count]
        return decoratedToken(
          from: source.0, punctuation: source.1, index: index, contentOptions: contentOptions,
          usesZipfFrequency: usesZipfFrequency)
      }.joined(separator: " ")
    default:
      return prompt(
        tokens: count, lexicon: words, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
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
    contentOptions: ContentOptions, usesZipfFrequency: Bool
  ) -> String {
    (0..<tokens).map { index in
      decoratedToken(
        from: lexicon, punctuation: punctuation, index: index, contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    }.joined(separator: separator)
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
    case .afrikaans: (afrikaansWords, [",", ".", "!", "?"])
    case .albanian: (albanianWords, [",", ".", "!", "?"])
    case .bemba: (bembaWords, [",", ".", "!", "?"])
    case .bosnian: (bosnianWords, [",", ".", "!", "?"])
    case .esperanto: (esperantoWords, [",", ".", "!", "?"])
    case .esperantoXSystem: (esperantoXSystemWords, [",", ".", "!", "?"])
    case .esperantoHSystem: (esperantoHSystemWords, [",", ".", "!", "?"])
    case .latin: (latinWords, [",", ".", "!", "?"])
    case .loremIpsum: (loremIpsumWords, [",", ".", "!", "?"])
    case .git: (gitWords, [",", ".", "!", "?"])
    case .twitchEmotes: (twitchEmoteWords, [",", ".", "!", "?"])
    case .typingOfTheDead: (typingOfTheDeadWords, [",", ".", "!", "?"])
    case .pokemon1k: (creatureIndexTokens, [",", ".", "!", "?"])
    case .arenaStrategy: (arenaStrategyTokens, [",", ".", "!", "?"])
    case .friulian: (friulianWords, [",", ".", "!", "?"])
    case .malagasy: (malagasyWords, [",", ".", "!", "?"])
    case .welsh: (welshWords, [",", ".", "!", "?"])
    case .hausa: (hausaWords, [",", ".", "!", "?"])
    case .tatar: (tatarWords, [",", ".", "!", "?"])
    case .tatarCrimean: (tatarCrimeanWords, [",", ".", "!", "?"])
    case .tatarCrimeanCyrillic: (tatarCrimeanCyrillicWords, [",", ".", "!", "?"])
    case .klingon: (klingonWords, [",", ".", "!", "?"])
    case .quenya: (quenyaWords, [",", ".", "!", "?"])
    case .viossa: (viossaWords, [",", ".", "!", "?"])
    case .viossaNjutro: (viossaNjutroWords, [",", ".", "!", "?"])
    case .maori: (maoriWords, [",", ".", "!", "?"])
    case .lojbanGismu: (lojbanGismuWords, [",", "!", "?"])
    case .lojbanCmavo: (lojbanCmavoWords, [",", "!", "?"])
    case .uzbek: (uzbekWords, [",", ".", "!", "?"])
    case .occitan: (occitanWords, [",", ".", "!", "?"])
    case .oromo: (oromoWords, [",", ".", "!", "?"])
    case .macedonian: (macedonianWords, [",", ".", "!", "?"])
    case .kazakh: (kazakhWords, [",", ".", "!", "?"])
    case .vietnamese: (vietnameseWords, [",", ".", "!", "?"])
    case .jyutping: (jyutpingWords, [",", ".", "!", "?"])
    case .pinyin: (pinyinWords, [",", ".", "!", "?"])
    case .bashkir: (bashkirWords, [",", ".", "!", "?"])
    case .basque: (basqueWords, [",", ".", "!", "?"])
    case .frisian: (frisianWords, [",", ".", "!", "?"])
    case .zulu: (zuluWords, [",", ".", "!", "?"])
    case .hawaiian: (hawaiianWords, [",", ".", "!", "?"])
    case .kabyle: (kabyleWords, [",", ".", "!", "?"])
    case .maltese: (malteseWords, [",", ".", "!", "?"])
    case .tokiPona: (tokiPonaWords, [",", ".", "!", "?"])
    case .tokiPonaKuSuli: (tokiPonaKuSuliWords, [",", ".", "!", "?"])
    case .tokiPonaKuLili: (tokiPonaKuLiliWords, [",", ".", "!", "?"])
    case .xhosa: (xhosaWords, [",", ".", "!", "?"])
    case .tibetan: (tibetanWords, ["།"])
    case .kyrgyz: (kyrgyzWords, [",", ".", "!", "?"])
    case .udmurt: (udmurtWords, [",", ".", "!", "?"])
    case .yoruba: (yorubaWords, [",", ".", "!", "?"])
    case .swahili: (swahiliWords, [",", ".", "!", "?"])
    case .kinyarwanda: (kinyarwandaWords, [",", ".", "!", "?"])
    case .shona: (shonaWords, [",", ".", "!", "?"])
    case .santali: (santaliWords, ["᱾", "?"])
    case .yiddish: (yiddishWords, [",", ".", "!", "?"])
    case .arabic: (arabicWords, ["،", "؛", "؟", "."])
    case .arabicEgypt: (arabicEgyptWords, ["،", "؛", "؟", "."])
    case .arabicMorocco: (arabicMoroccoWords, ["،", "؛", "؟", "."])
    case .pashto: (pashtoWords, ["،", "؛", "؟", "."])
    case .sindhi: (sindhiWords, ["،", "؛", "؟", "."])
    case .hebrew: (hebrewWords, [",", ".", "!", "?"])
    case .persian: (persianWords, ["،", "؛", "؟", "."])
    case .persianRomanized: (persianRomanizedWords, [",", ".", "!", "?"])
    case .urdu: (urduWords, ["،", "؛", "؟", "."])
    case .urduRoman: (urduRomanWords, [",", ".", "!", "?"])
    case .urdish: (urdishWords, [",", ".", "!", "?"])
    case .tamil: (tamilWords, [",", ".", "!", "?"])
    case .tamilOld: (tamilOldTokens, [",", ".", "!", "?"])
    case .tanglish: (tanglishWords, [",", ".", "!", "?"])
    case .hindi: (hindiWords, [",", ".", "!", "?"])
    case .hinglish: (hinglishWords, [",", ".", "!", "?"])
    case .gujarati: (gujaratiWords, [",", ".", "!", "?"])
    case .bangla: (banglaWords, [",", ".", "!", "?"])
    case .banglaLetters: (banglaLetterWords, ["।", ",", "!", "?"])
    case .thai: (thaiWords, [",", ".", "!", "?"])
    case .nepali: (nepaliWords, [",", ".", "!", "?"])
    case .nepaliRomanized: (nepaliRomanizedWords, [",", ".", "!", "?"])
    case .kannada: (kannadaWords, [",", ".", "!", "?"])
    case .telugu: (teluguWords, [",", ".", "!", "?"])
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
    case .irish: (irishWords, [",", ".", "!", "?"])
    case .galician: (galicianWords, [",", ".", "!", "?"])
    case .marathi: (marathiWords, [",", ".", "!", "?"])
    case .kurdishCentral: (kurdishCentralWords, ["،", "؛", "؟", "."])
    case .greek: (greekWords, [",", ".", "!", "?"])
    case .greekKoine: (greekKoineWords, [",", ".", "!", "?"])
    case .greeklish: (greeklishWords, [",", ".", "!", "?"])
    case .dutch: (dutchWords, [",", ".", "!", "?"])
    case .filipino: (filipinoWords, [",", ".", "!", "?"])
    case .catalan: (catalanWords, [",", ".", "!", "?"])
    case .indonesian: (indonesianWords, [",", ".", "!", "?"])
    case .malay: (malayWords, [",", ".", "!", "?"])
    case .danish: (danishWords, [",", ".", "!", "?"])
    case .norwegianBokmal: (norwegianBokmalWords, [",", ".", "!", "?"])
    case .norwegianNynorsk: (norwegianNynorskWords, [",", ".", "!", "?"])
    case .swedish: (swedishWords, [",", ".", "!", "?"])
    case .swedishDiacritics: (swedishDiacriticsWords, [",", ".", "!", "?"])
    case .hungarian: (hungarianWords, [",", ".", "!", "?"])
    case .czech: (czechWords, [",", ".", "!", "?"])
    case .slovak: (slovakWords, [",", ".", "!", "?"])
    case .slovenian: (slovenianWords, [",", ".", "!", "?"])
    case .croatian: (croatianWords, [",", ".", "!", "?"])
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
    case .estonian: (estonianWords, [",", ".", "!", "?"])
    case .icelandic: (icelandicWords, [",", ".", "!", "?"])
    case .french: (frenchWords, [",", ".", "!", "?"])
    case .french1k: (french1kWords, [",", ".", "!", "?"])
    case .french2k: (french2kWords, [",", ".", "!", "?"])
    case .french10k: (french10kWords, [",", ".", "!", "?"])
    case .frenchBitoduc: (frenchBitoducWords, [",", ".", "!", "?"])
    case .italian: (italianWords, [",", ".", "!", "?"])
    case .portuguese: (portugueseWords, [",", ".", "!", "?"])
    case .portuguese1k: (portuguese1kWords, [",", ".", "!", "?"])
    case .portuguese3k: (portuguese3kWords, [",", ".", "!", "?"])
    case .portuguese5k: (portuguese5kWords, [",", ".", "!", "?"])
    case .portuguese320k: (portuguese320kWords, [",", ".", "!", "?"])
    case .portuguese550k: (portuguese550kWords, [",", ".", "!", "?"])
    case .portugueseAccents: (portugueseAccentsWords, [",", ".", "!", "?"])
    case .simplifiedChinese: (simplifiedChineseWords, ["，", "。", "！", "？"])
    case .traditionalChinese: (traditionalChineseWords, ["，", "。", "！", "？"])
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
    case .ukrainianEndings: (ukrainianEndingWords, [".", ",", "!", "?"])
    case .ukrainianLatin: (ukrainianLatinWords, [".", ",", "!", "?"])
    case .ukrainianLatynkaEndings: (ukrainianLatynkaEndingWords, [".", ",", "!", "?"])
    case .japaneseHiragana: (japaneseHiraganaWords, ["、", "。", "！", "？"])
    case .japaneseKatakana: (japaneseKatakanaWords, ["、", "。", "！", "？"])
    case .japaneseRomaji: (japaneseRomajiWords, [".", ",", "!", "?"])
    case .korean: (koreanWords, [".", ",", "!", "?"])
    case .turkish: (turkishWords, [".", ",", "!", "?"])
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
    var token = lexicon[tokenIndex]
    if contentOptions.includePunctuation, index.isMultiple(of: 7) {
      token += punctuation[index / 7 % punctuation.count]
    }
    return token
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
    self == .swissGerman ? text.replacingOccurrences(of: "ß", with: "ss") : text
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
    case .afrikaans: StarterLexicon.afrikaansWords
    case .albanian: StarterLexicon.albanianWords
    case .bemba: StarterLexicon.bembaWords
    case .bosnian: StarterLexicon.bosnianWords
    case .esperanto: StarterLexicon.esperantoWords
    case .esperantoXSystem: StarterLexicon.esperantoXSystemWords
    case .esperantoHSystem: StarterLexicon.esperantoHSystemWords
    case .latin: StarterLexicon.latinWords
    case .loremIpsum: StarterLexicon.loremIpsumWords
    case .git: StarterLexicon.gitWords
    case .twitchEmotes: StarterLexicon.twitchEmoteWords
    case .typingOfTheDead: StarterLexicon.typingOfTheDeadWords
    case .pokemon1k: StarterLexicon.creatureIndexEntries
    case .arenaStrategy: StarterLexicon.arenaStrategyEntries
    case .friulian: StarterLexicon.friulianWords
    case .malagasy: StarterLexicon.malagasyWords
    case .welsh: StarterLexicon.welshWords
    case .hausa: StarterLexicon.hausaWords
    case .tatar: StarterLexicon.tatarWords
    case .tatarCrimean: StarterLexicon.tatarCrimeanWords
    case .tatarCrimeanCyrillic: StarterLexicon.tatarCrimeanCyrillicWords
    case .klingon: StarterLexicon.klingonWords
    case .quenya: StarterLexicon.quenyaWords
    case .viossa: StarterLexicon.viossaWords
    case .viossaNjutro: StarterLexicon.viossaNjutroWords
    case .maori: StarterLexicon.maoriWords
    case .lojbanGismu: StarterLexicon.lojbanGismuWords
    case .lojbanCmavo: StarterLexicon.lojbanCmavoWords
    case .uzbek: StarterLexicon.uzbekWords
    case .occitan: StarterLexicon.occitanWords
    case .oromo: StarterLexicon.oromoWords
    case .macedonian: StarterLexicon.macedonianWords
    case .kazakh: StarterLexicon.kazakhWords
    case .vietnamese: StarterLexicon.vietnameseWords
    case .jyutping: StarterLexicon.jyutpingWords
    case .pinyin: StarterLexicon.pinyinWords
    case .bashkir: StarterLexicon.bashkirWords
    case .basque: StarterLexicon.basqueWords
    case .frisian: StarterLexicon.frisianWords
    case .zulu: StarterLexicon.zuluWords
    case .hawaiian: StarterLexicon.hawaiianWords
    case .kabyle: StarterLexicon.kabyleWords
    case .maltese: StarterLexicon.malteseWords
    case .tokiPona: StarterLexicon.tokiPonaWords
    case .tokiPonaKuSuli: StarterLexicon.tokiPonaKuSuliWords
    case .tokiPonaKuLili: StarterLexicon.tokiPonaKuLiliWords
    case .xhosa: StarterLexicon.xhosaWords
    case .tibetan: StarterLexicon.tibetanWords
    case .kyrgyz: StarterLexicon.kyrgyzWords
    case .udmurt: StarterLexicon.udmurtWords
    case .yoruba: StarterLexicon.yorubaWords
    case .swahili: StarterLexicon.swahiliWords
    case .kinyarwanda: StarterLexicon.kinyarwandaWords
    case .shona: StarterLexicon.shonaWords
    case .santali: StarterLexicon.santaliWords
    case .yiddish: StarterLexicon.yiddishWords
    case .arabic: StarterLexicon.arabicWords
    case .arabicEgypt: StarterLexicon.arabicEgyptWords
    case .arabicMorocco: StarterLexicon.arabicMoroccoWords
    case .pashto: StarterLexicon.pashtoWords
    case .sindhi: StarterLexicon.sindhiWords
    case .hebrew: StarterLexicon.hebrewWords
    case .persian: StarterLexicon.persianWords
    case .persianRomanized: StarterLexicon.persianRomanizedWords
    case .urdu: StarterLexicon.urduWords
    case .urduRoman: StarterLexicon.urduRomanWords
    case .urdish: StarterLexicon.urdishWords
    case .tamil: StarterLexicon.tamilWords
    case .tamilOld: StarterLexicon.tamilOldWords
    case .tanglish: StarterLexicon.tanglishWords
    case .hindi: StarterLexicon.hindiWords
    case .hinglish: StarterLexicon.hinglishWords
    case .gujarati: StarterLexicon.gujaratiWords
    case .bangla: StarterLexicon.banglaWords
    case .banglaLetters: StarterLexicon.banglaLetterWords
    case .thai: StarterLexicon.thaiWords
    case .nepali: StarterLexicon.nepaliWords
    case .nepaliRomanized: StarterLexicon.nepaliRomanizedWords
    case .kannada: StarterLexicon.kannadaWords
    case .telugu: StarterLexicon.teluguWords
    case .malayalam: StarterLexicon.malayalamWords
    case .sanskrit: StarterLexicon.sanskritWords
    case .sanskritRoman: StarterLexicon.sanskritRomanWords
    case .sinhala: StarterLexicon.sinhalaWords
    case .khmer: StarterLexicon.khmerWords
    case .myanmarBurmese: StarterLexicon.myanmarBurmeseWords
    case .lao: StarterLexicon.laoWords
    case .amharic: StarterLexicon.amharicWords
    case .armenian: StarterLexicon.armenianWords
    case .armenianWestern: StarterLexicon.armenianWesternWords
    case .georgian: StarterLexicon.georgianWords
    case .azerbaijani: StarterLexicon.azerbaijaniWords
    case .belarusian: StarterLexicon.belarusianWords
    case .belarusian1k: StarterLexicon.belarusian1kWords
    case .belarusian5k: StarterLexicon.belarusian5kWords
    case .belarusian10k: StarterLexicon.belarusian10kWords
    case .belarusian25k: StarterLexicon.belarusian25kWords
    case .belarusian50k: StarterLexicon.belarusian50kWords
    case .belarusian100k: StarterLexicon.belarusian100kWords
    case .belarusianLacinka: StarterLexicon.belarusianLacinkaWords
    case .lithuanian: StarterLexicon.lithuanianWords
    case .latvian: StarterLexicon.latvianWords
    case .mongolian: StarterLexicon.mongolianWords
    case .irish: StarterLexicon.irishWords
    case .galician: StarterLexicon.galicianWords
    case .marathi: StarterLexicon.marathiWords
    case .kurdishCentral: StarterLexicon.kurdishCentralWords
    case .greek: StarterLexicon.greekWords
    case .greekKoine: StarterLexicon.greekKoineWords
    case .greeklish: StarterLexicon.greeklishWords
    case .dutch: StarterLexicon.dutchWords
    case .filipino: StarterLexicon.filipinoWords
    case .catalan: StarterLexicon.catalanWords
    case .indonesian: StarterLexicon.indonesianWords
    case .malay: StarterLexicon.malayWords
    case .danish: StarterLexicon.danishWords
    case .norwegianBokmal: StarterLexicon.norwegianBokmalWords
    case .norwegianNynorsk: StarterLexicon.norwegianNynorskWords
    case .swedish: StarterLexicon.swedishWords
    case .swedishDiacritics: StarterLexicon.swedishDiacriticsWords
    case .hungarian: StarterLexicon.hungarianWords
    case .czech: StarterLexicon.czechWords
    case .slovak: StarterLexicon.slovakWords
    case .slovenian: StarterLexicon.slovenianWords
    case .croatian: StarterLexicon.croatianWords
    case .serbian: StarterLexicon.serbianWords
    case .serbianLatin: StarterLexicon.serbianLatinWords
    case .bulgarian: StarterLexicon.bulgarianWords
    case .bulgarianLatin: StarterLexicon.bulgarianLatinWords
    case .romanian: StarterLexicon.romanianWords
    case .romanian1k: StarterLexicon.romanian1kWords
    case .romanian5k: StarterLexicon.romanian5kWords
    case .romanian10k: StarterLexicon.romanian10kWords
    case .romanian25k: StarterLexicon.romanian25kWords
    case .romanian50k: StarterLexicon.romanian50kWords
    case .romanian100k: StarterLexicon.romanian100kWords
    case .romanian200k: StarterLexicon.romanian200kWords
    case .finnish: StarterLexicon.finnishWords
    case .estonian: StarterLexicon.estonianWords
    case .icelandic: StarterLexicon.icelandicWords
    case .french: StarterLexicon.frenchWords
    case .french1k: StarterLexicon.french1kWords
    case .french2k: StarterLexicon.french2kWords
    case .french10k: StarterLexicon.french10kWords
    case .frenchBitoduc: StarterLexicon.frenchBitoducWords
    case .italian: StarterLexicon.italianWords
    case .portuguese: StarterLexicon.portugueseWords
    case .portuguese1k: StarterLexicon.portuguese1kWords
    case .portuguese3k: StarterLexicon.portuguese3kWords
    case .portuguese5k: StarterLexicon.portuguese5kWords
    case .portuguese320k: StarterLexicon.portuguese320kWords
    case .portuguese550k: StarterLexicon.portuguese550kWords
    case .portugueseAccents: StarterLexicon.portugueseAccentsWords
    case .simplifiedChinese: StarterLexicon.simplifiedChineseWords
    case .traditionalChinese: StarterLexicon.traditionalChineseWords
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
    case .ukrainianEndings: StarterLexicon.ukrainianEndingWords
    case .ukrainianLatin: StarterLexicon.ukrainianLatinWords
    case .ukrainianLatynkaEndings: StarterLexicon.ukrainianLatynkaEndingWords
    case .japaneseHiragana: StarterLexicon.japaneseHiraganaWords
    case .japaneseKatakana: StarterLexicon.japaneseKatakanaWords
    case .japaneseRomaji: StarterLexicon.japaneseRomajiWords
    case .korean: StarterLexicon.koreanWords
    case .turkish: StarterLexicon.turkishWords
    case .polish: StarterLexicon.polishWords
    case .polish2k: StarterLexicon.polish2kWords
    case .polish5k: StarterLexicon.polish5kWords
    case .polish10k: StarterLexicon.polish10kWords
    case .polish20k: StarterLexicon.polish20kWords
    case .polish40k: StarterLexicon.polish40kWords
    case .polish200k: StarterLexicon.polish200kWords
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
    default: IndexedLexicon(ownedPracticeWords(englishVariant: englishVariant))
    }
  }

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

  static var mixableLanguages: [TypingLanguage] { defaultMixedComponents }

  static func normalizedMixedComponents(_ languages: [TypingLanguage]) -> [TypingLanguage] {
    let selected = languages.filter { mixableLanguages.contains($0) }.reduce(
      into: [TypingLanguage]()
    ) { result, language in
      if !result.contains(language) { result.append(language) }
    }
    return selected.count >= 2 ? selected : defaultMixedComponents
  }

  var usesSpaceDelimitedWords: Bool {
    !isNoSpaceLanguage && !isCodeLanguage
  }

  /// Right-to-left prompts use the native text system. They remain
  /// single-language until mixed bidirectional prompt layout has dedicated
  /// interaction coverage.
  var usesRightToLeftPrompt: Bool {
    self == .arabic || self == .arabicEgypt || self == .arabicMorocco || self == .pashto || self == .sindhi || self == .hebrew || self == .persian || self == .urdu || self == .kurdishCentral || self == .yiddish
  }

  /// Preserve native shaping for source-pinned joining scripts.
  var usesJoiningScriptPrompt: Bool {
    switch self {
    case .arabic, .arabicEgypt, .arabicMorocco, .bangla, .banglaLetters, .gujarati, .hebrew,
      .hindi, .kannada, .khmer, .korean, .kurdishCentral, .likanu, .malayalam,
      .myanmarBurmese, .nepali, .pashto, .persian, .sanskrit, .sindhi, .sinhala,
      .tamil, .tamilOld, .telugu, .tibetan, .urdu, .yiddish:
      true
    default:
      false
    }
  }

  var isNoSpaceLanguage: Bool {
    switch self {
    case .simplifiedChinese, .traditionalChinese, .japaneseHiragana, .japaneseKatakana: true
    default: false
    }
  }

  var isCodeLanguage: Bool {
    self == .dockerFile || rawValue.hasPrefix("code")
  }

  /// Mirrors Monkeytype's `noLazyMode` language metadata for every Typebar
  /// wordset. Code prompts are likewise literal input, never accent-folded.
  var supportsLazyLatinInput: Bool {
    guard !isCodeLanguage else { return false }
    return switch self {
    case .english, .english1k, .english5k, .english10k, .english25k, .english450k,
      .englishCommonlyMisspelled, .englishContractions, .englishDoubleLetter,
      .englishMedical,
      .englishShakespearean,
      .pigLatin, .loremIpsum, .git, .twitchEmotes, .typingOfTheDead, .pashto, .hebrew, .persian, .persianRomanized, .urdu,
      .tamil, .hindi, .gujarati, .bangla, .banglaLetters, .thai, .nepali, .kannada, .telugu, .malayalam,
      .sanskrit, .greeklish, .dutch, .filipino, .indonesian, .serbian, .bulgarian,
      .bulgarianLatin,
      .khmer,
      .myanmarBurmese,
      .armenian,
      .georgian,
      .belarusian, .belarusian1k,
      .macedonian,
      .kazakh,
      .mongolian,
      .marathi,
      .malagasy,
      .tokiPona, .tokiPonaKuSuli, .tokiPonaKuLili,
      .tibetan,
      .swahili,
      .kinyarwanda,
      .tatarCrimean,
      .tatarCrimeanCyrillic,
      .viossaNjutro,
      .lojbanGismu,
      .lojbanCmavo,
      .esperantoXSystem, .esperantoHSystem,
      .simplifiedChinese, .traditionalChinese, .portuguese5k, .portuguese320k, .portuguese550k,
      .russian5k, .russianAbbreviations, .russianContractions, .russianContractions1k, .ukrainian, .ukrainianEndings,
      .ukrainianLatin, .ukrainianLatynkaEndings,
      .japaneseHiragana, .japaneseKatakana, .japaneseRomaji, .korean,
      .mixedEnglishChinese, .mixedLanguages:
      false
    default:
      true
    }
  }

  var supportsCapsLockWarning: Bool {
    switch self {
    case .simplifiedChinese, .traditionalChinese, .japaneseHiragana, .japaneseKatakana, .korean: false
    default: !isCodeLanguage
    }
  }

  var supportsQuotes: Bool {
    self != .mixedEnglishChinese && self != .mixedLanguages && !isCodeLanguage
  }

  /// The pinned reference excludes Swiss German from community quote
  /// submission and redirects its built-in quote path to German instead.
  var supportsCommunityQuoteSubmission: Bool {
    supportsQuotes && self != .swissGerman
  }

  /// Pinned-reference `orderedByFrequency` metadata for the built-in base
  /// wordsets. Dictionaries without that field intentionally remain unknown.
  var zipfFrequencySupport: ZipfFrequencySupport {
    switch self {
    case .english, .english1k, .english5k, .english10k, .bosnian, .esperanto, .esperantoHSystem, .tatar, .oromo, .bashkir, .hawaiian, .kinyarwanda, .tamil, .kannada, .greeklish, .norwegianBokmal, .norwegianNynorsk,
      .russian, .russian1k, .russian5k, .icelandic, .galician, .marathi:
      return .supported
    case .englishCommonlyMisspelled, .englishContractions, .englishDoubleLetter,
      .englishMedical, .english25k, .english450k, .kokanu, .likanu, .russianAbbreviations, .russianContractions, .russianContractions1k, .typingOfTheDead, .pokemon1k, .arabicMorocco, .sindhi, .armenian, .bemba,
      .bulgarian, .bulgarianLatin, .urduRoman, .hungarian, .lao, .kabyle,
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
    case .afrikaans: "Afrikaans"
    case .albanian: "Shqip"
    case .bemba: "Ichibemba"
    case .bosnian: "Bosanski"
    case .esperanto: "Esperanto"
    case .esperantoXSystem: "Esperanto · X-sistemo"
    case .esperantoHSystem: "Esperanto · H-sistemo"
    case .latin: "Latina"
    case .loremIpsum: "Lorem Ipsum · Typebar"
    case .git: "Git"
    case .twitchEmotes: "Streaming Emotes · Typebar"
    case .typingOfTheDead: "Arcade Horror Phrases · Typebar"
    case .pokemon1k: "Creature Index 1k · Typebar"
    case .arenaStrategy: "Arena Strategy Terms · Typebar"
    case .friulian: "Friulian"
    case .malagasy: "Malagasy"
    case .welsh: "Cymraeg"
    case .hausa: "Hausa"
    case .tatar: "Татарча"
    case .tatarCrimean: "Qırımtatarca"
    case .tatarCrimeanCyrillic: "Къырымтатарджа"
    case .klingon: "tlhIngan Hol"
    case .quenya: "Quenya"
    case .viossa: "Viossa"
    case .viossaNjutro: "Viossa · Njutro"
    case .maori: "Te reo Māori"
    case .lojbanGismu: "Lojban · gismu"
    case .lojbanCmavo: "Lojban · cmavo"
    case .uzbek: "Oʻzbekcha"
    case .occitan: "Occitan"
    case .oromo: "Oromo"
    case .macedonian: "Македонски"
    case .kazakh: "Қазақша"
    case .vietnamese: "Tiếng Việt"
    case .jyutping: "Jyutping"
    case .pinyin: "Pinyin"
    case .bashkir: "Башҡортса"
    case .basque: "Euskara"
    case .frisian: "Frysk"
    case .zulu: "isiZulu"
    case .hawaiian: "ʻŌlelo Hawaiʻi"
    case .kabyle: "Taqbaylit"
    case .maltese: "Malti"
    case .tokiPona: "toki pona"
    case .tokiPonaKuSuli: "toki pona · ku suli"
    case .tokiPonaKuLili: "toki pona · ku lili"
    case .xhosa: "isiXhosa"
    case .tibetan: "བོད་སྐད་"
    case .kyrgyz: "Кыргызча"
    case .udmurt: "Удмурт кыл"
    case .yoruba: "Yorùbá"
    case .swahili: "Kiswahili"
    case .kinyarwanda: "Ikinyarwanda"
    case .shona: "chiShona"
    case .santali: "ᱥᱟᱱᱛᱟᱲᱤ"
    case .yiddish: "ייִדיש"
    case .arabic: "العربية"
    case .arabicEgypt: "العربية المصرية"
    case .arabicMorocco: "العربية المغربية"
    case .pashto: "پښتو"
    case .sindhi: "سنڌي"
    case .hebrew: "עברית"
    case .persian: "فارسی"
    case .persianRomanized: "Fârsi (Romanized)"
    case .urdu: "اردو"
    case .urduRoman: "Urdu (Roman)"
    case .urdish: "Urdish"
    case .tamil: "தமிழ்"
    case .tamilOld: "தமிழ் · பழைய தொகுப்பு · Typebar"
    case .tanglish: "Tanglish"
    case .hindi: "हिन्दी"
    case .hinglish: "Hinglish"
    case .gujarati: "ગુજરાતી"
    case .bangla: "বাংলা"
    case .banglaLetters: "বাংলা · অক্ষর"
    case .thai: "ไทย"
    case .nepali: "नेपाली"
    case .nepaliRomanized: "Nepali (Romanized)"
    case .kannada: "ಕನ್ನಡ"
    case .telugu: "తెలుగు"
    case .malayalam: "മലയാളം"
    case .sanskrit: "संस्कृतम्"
    case .sanskritRoman: "Saṃskṛtam (Roman)"
    case .sinhala: "සිංහල"
    case .khmer: "ខ្មែរ"
    case .myanmarBurmese: "မြန်မာ"
    case .lao: "ລາວ"
    case .amharic: "አማርኛ"
    case .armenian: "Հայերեն"
    case .armenianWestern: "Հայերէն (Արեւմտեան)"
    case .georgian: "ქართული"
    case .azerbaijani: "Azərbaycanca"
    case .belarusian: "Беларуская"
    case .belarusian1k: "Беларуская · 1k · Typebar"
    case .belarusian5k: "Беларуская · 5k · Typebar"
    case .belarusian10k: "Беларуская · 10k · Typebar"
    case .belarusian25k: "Беларуская · 25k · Typebar"
    case .belarusian50k: "Беларуская · 50k · Typebar"
    case .belarusian100k: "Беларуская · 100k · Typebar"
    case .belarusianLacinka: "Biełaruskaja łacinka"
    case .lithuanian: "Lietuvių"
    case .latvian: "Latviešu"
    case .mongolian: "Монгол"
    case .irish: "Gaeilge"
    case .galician: "Galego"
    case .marathi: "मराठी"
    case .kurdishCentral: "کوردی ناوەندی"
    case .greek: "Ελληνικά"
    case .greekKoine: "Ἑλληνιστικὴ Κοινή"
    case .greeklish: "Greeklish"
    case .dutch: "Nederlands"
    case .filipino: "Filipino"
    case .catalan: "Català"
    case .indonesian: "Bahasa Indonesia"
    case .malay: "Bahasa Melayu"
    case .danish: "Dansk"
    case .norwegianBokmal: "Norsk bokmål"
    case .norwegianNynorsk: "Norsk nynorsk"
    case .swedish: "Svenska"
    case .swedishDiacritics: "Svenska · Å Ä Ö"
    case .hungarian: "Magyar"
    case .czech: "Čeština"
    case .slovak: "Slovenčina"
    case .slovenian: "Slovenščina"
    case .croatian: "Hrvatski"
    case .serbian: "Српски"
    case .serbianLatin: "Srpski (Latin)"
    case .bulgarian: "Български"
    case .bulgarianLatin: "Balgarski (Latin)"
    case .romanian: "Română"
    case .romanian1k: "Română · 1k · Typebar"
    case .romanian5k: "Română · 5k · Typebar"
    case .romanian10k: "Română · 10k · Typebar"
    case .romanian25k: "Română · 25k · Typebar"
    case .romanian50k: "Română · 50k · Typebar"
    case .romanian100k: "Română · 100k · Typebar"
    case .romanian200k: "Română · 200k · Typebar"
    case .finnish: "Suomi"
    case .estonian: "Eesti"
    case .icelandic: "Íslenska"
    case .french: "Français"
    case .french1k: "Français · 1k · Typebar"
    case .french2k: "Français · 2k · Typebar"
    case .french10k: "Français · 10k · Typebar"
    case .frenchBitoduc: "Français · Bitoduc"
    case .italian: "Italiano"
    case .portuguese: "Português"
    case .portuguese1k: "Português · 1k · Typebar"
    case .portuguese3k: "Português · 3k · Typebar"
    case .portuguese5k: "Português · 5k · Typebar"
    case .portuguese320k: "Português · 320k · Typebar"
    case .portuguese550k: "Português · 550k · Typebar"
    case .portugueseAccents: "Português · Acentos e cedilha"
    case .simplifiedChinese: "简体中文"
    case .traditionalChinese: "繁體中文"
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
    case .ukrainianEndings: "Українська · Закінчення"
    case .ukrainianLatin: "Українська (Latin)"
    case .ukrainianLatynkaEndings: "Українська (Latynka) · Закінчення"
    case .japaneseHiragana: "日本語（ひらがな）"
    case .japaneseKatakana: "日本語（カタカナ）"
    case .japaneseRomaji: "日本語（ローマ字）"
    case .korean: "한국어"
    case .turkish: "Türkçe"
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
