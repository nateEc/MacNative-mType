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
  case spanish
  case german
  case afrikaans
  case arabic
  case hebrew
  case persian
  case urdu
  case tamil
  case hindi
  case gujarati
  case bangla
  case thai
  case nepali
  case kannada
  case telugu
  case malayalam
  case sanskrit
  case sinhala
  case khmer
  case myanmarBurmese
  case greek
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
  case hungarian
  case czech
  case slovak
  case slovenian
  case croatian
  case serbian
  case serbianLatin
  case bulgarian
  case romanian
  case finnish
  case estonian
  case icelandic
  case french
  case italian
  case portuguese
  case simplifiedChinese
  case traditionalChinese
  case russian
  case ukrainian
  case ukrainianLatin
  case japaneseHiragana
  case japaneseKatakana
  case japaneseRomaji
  case korean
  case turkish
  case polish
  case mixedEnglishChinese
  case mixedLanguages
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
    self.modifiers = TestModifierPolicy.normalized(modifiers).filter {
      mode != .zen || $0 != .memory
    }
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
    copy.modifiers = TestModifierPolicy.normalized(modifiers).filter {
      copy.mode != .zen || $0 != .memory
    }
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
    modifiers = TestModifierPolicy.normalized(
      try values.decodeIfPresent([TestModifier].self, forKey: .modifiers) ?? []
    ).filter { decodedMode != .zen || $0 != .memory }
    contentOptions =
      try values.decodeIfPresent(ContentOptions.self, forKey: .contentOptions) ?? .init()
    challengeID = try values.decodeIfPresent(String.self, forKey: .challengeID)
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
      return (configuration.wordLimit ?? 0) >= longWordLimit
    case .time:
      return (configuration.duration ?? 0) >= longDuration
    case .custom:
      switch configuration.customTextCompletion {
      case .time:
        return (configuration.duration ?? 0) >= longDuration
      case .words:
        return (configuration.wordLimit ?? 0) >= longWordLimit
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
      return (configuration.duration ?? 0) >= 3_600
    case .words:
      return (configuration.wordLimit ?? 0) >= 5_000
    case .custom:
      switch configuration.customTextCompletion {
      case .time: return (configuration.duration ?? 0) >= 3_600
      case .words: return (configuration.wordLimit ?? 0) >= 5_000
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

  private enum CodingKeys: String, CodingKey {
    case id, configuration, outcome, startedAt, finishedAt, typedCharacterCount,
      afkDuration, correctCharacterCount, errorCount, wpm, rawWpm, accuracy, tags, prompt, replayEvents
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
    if let remaining = remainingSeconds(at: date) { return "\(remaining)s" }
    guard let wordLimit = configuration.wordLimit,
      (configuration.language.usesSpaceDelimitedWords || tracksNoSpaceWordBursts)
    else { return nil }
    return "\(min(wordLimit, completedWordCount))/\(wordLimit)"
  }

  var progressLabel: String {
    configuration.duration == nil && configuration.wordLimit != nil ? "进度" : "剩余"
  }

  func progressFraction(at date: Date = .now) -> Double? {
    if let duration = configuration.duration {
      guard let startedAt else { return 0 }
      return (date.timeIntervalSince(startedAt) / duration).clamped(to: 0...1)
    }
    guard let wordLimit = configuration.wordLimit,
      (configuration.language.usesSpaceDelimitedWords || tracksNoSpaceWordBursts)
    else { return nil }
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

  func result(at date: Date = .now, tags: [String] = []) -> CompletedTestResult? {
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
    if startedAt == nil { startedAt = date }
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
    guard let wordLimit = configuration.wordLimit else { return false }
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

enum StarterLexicon {
  // This small starter corpus is original project content, not imported from Monkeytype.
  static let words = [
    "amber", "harbor", "quiet", "copper", "lantern", "paper", "window", "drift",
    "meadow", "signal", "summer", "orchard", "canyon", "violet", "planet", "moss",
    "ripple", "thunder", "willow", "tangent", "pocket", "marble", "voyage", "bright",
  ]

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

  // Original Typebar content for Ukrainian Cyrillic practice. The final
  // entries deliberately cover Ukrainian-specific ї, є, and ґ.
  static let ukrainianWords = [
    "ранок", "вікно", "папір", "берег", "вітер", "вправа", "увага", "спокій",
    "ясно", "озеро", "вулиця", "стіл", "світло", "дорога", "терпіння", "хвилина",
    "місто", "дощ", "тиша", "напрямок", "зірка", "нотатка", "сад", "подих",
    "їжа", "єдність", "ґрунт",
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

  // Typebar-authored Afrikaans starter words. Diacritics remain in the local
  // corpus for native macOS composed-text practice without imported word lists.
  static let afrikaansWords = [
    "môre", "venster", "papier", "kus", "wind", "oefening", "aandag", "rustig",
    "helder", "meer", "straat", "tafel", "lig", "reis", "geduld", "oomblik",
    "stad", "reën", "stilte", "rigting", "ster", "nota", "tuin", "asem",
    "klein", "tyd", "lente", "veld", "boot", "vriend", "wêreld",
  ]

  // Typebar-authored Greek starter words. Accented forms exercise the native
  // Greek input source without importing a third-party word list.
  static let greekWords = [
    "πρωί", "παράθυρο", "χαρτί", "ακτή", "άνεμος", "άσκηση", "προσοχή", "ήρεμος",
    "καθαρός", "λίμνη", "δρόμος", "τραπέζι", "φως", "ταξίδι", "υπομονή", "στιγμή",
    "πόλη", "βροχή", "σιωπή", "κατεύθυνση", "αστέρι", "σημείωση", "κήπος", "ανάσα",
    "μικρός", "χρόνος", "άνοιξη", "νησί", "φίλος", "βιβλίο",
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

  // Typebar-authored Urdu starter words use direct Unicode text for macOS
  // Urdu input sources; they are not an imported word list.
  static let urduWords = [
    "کتاب", "قلم", "کھڑکی", "راستہ", "روشنی", "پل", "صبح", "کاغذ", "باغ", "بادل",
    "سکون", "چراغ", "پہاڑ", "بیج", "آواز", "میز", "خیال", "نوٹ", "تصور", "تجربہ",
    "فاصلہ", "قدم", "صبر", "توازن",
  ]

  // Typebar-authored Tamil starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let tamilWords = [
    "புத்தகம்", "பேனா", "சாளரம்", "பாதை", "ஒளி", "பாலம்", "காலை", "காகிதம்", "தோட்டம்", "மேகம்",
    "அமைதி", "விளக்கு", "மலை", "விதை", "இசை", "மேசை", "சிந்தனை", "குறிப்பு", "யோசனை", "முயற்சி",
    "தூரம்", "அடி", "பொறுமை", "சமநிலை",
  ]

  // Typebar-authored Hindi starter words exercise normal macOS composed-text
  // input without importing a third-party or reference word list.
  static let hindiWords = [
    "पुस्तक", "कलम", "खिड़की", "रास्ता", "रोशनी", "पुल", "सुबह", "कागज़", "बगीचा", "बादल",
    "शांति", "दीपक", "पहाड़", "बीज", "संगीत", "मेज़", "विचार", "टिप्पणी", "कल्पना", "प्रयास",
    "दूरी", "कदम", "धैर्य", "संतुलन",
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
    case .spanish:
      return prompt(
        tokens: count, lexicon: spanishWords, separator: " ", punctuation: [",", ".", "¡", "¿"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .german:
      return prompt(
        tokens: count, lexicon: germanWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .afrikaans:
      return prompt(
        tokens: count, lexicon: afrikaansWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .arabic:
      return prompt(
        tokens: count, lexicon: arabicWords, separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hebrew:
      return prompt(
        tokens: count, lexicon: hebrewWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .persian:
      return prompt(
        tokens: count, lexicon: persianWords, separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .urdu:
      return prompt(
        tokens: count, lexicon: urduWords, separator: " ", punctuation: ["،", "؛", "؟", "."],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .tamil:
      return prompt(
        tokens: count, lexicon: tamilWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .hindi:
      return prompt(
        tokens: count, lexicon: hindiWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .gujarati:
      return prompt(
        tokens: count, lexicon: gujaratiWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .bangla:
      return prompt(
        tokens: count, lexicon: banglaWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .thai:
      return prompt(
        tokens: count, lexicon: thaiWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .nepali:
      return prompt(
        tokens: count, lexicon: nepaliWords, separator: " ", punctuation: [",", ".", "!", "?"],
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
    case .greek:
      return prompt(
        tokens: count, lexicon: greekWords, separator: " ", punctuation: [",", ".", "!", "?"],
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
    case .romanian:
      return prompt(
        tokens: count, lexicon: romanianWords, separator: " ", punctuation: [",", ".", "!", "?"],
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
    case .italian:
      return prompt(
        tokens: count, lexicon: italianWords, separator: " ", punctuation: [",", ".", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .portuguese:
      return prompt(
        tokens: count, lexicon: portugueseWords, separator: " ", punctuation: [",", ".", "!", "?"],
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
    case .ukrainian:
      return prompt(
        tokens: count, lexicon: ukrainianWords, separator: " ", punctuation: [".", ",", "!", "?"],
        contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
    case .ukrainianLatin:
      return prompt(
        tokens: count, lexicon: ukrainianLatinWords, separator: " ", punctuation: [".", ",", "!", "?"],
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
    (0..<tokens).map { index in
      decoratedToken(
        from: lexicon, punctuation: punctuation, index: index, contentOptions: contentOptions,
        usesZipfFrequency: usesZipfFrequency)
    }.joined(separator: separator)
  }

  private static func source(for language: TypingLanguage, englishVariant: EnglishVariant) -> (
    [String], [String]
  ) {
    switch language {
    case .english: (englishVariant == .british ? britishWords : words, [",", ".", "!", "?"])
    case .spanish: (spanishWords, [",", ".", "¡", "¿"])
    case .german: (germanWords, [",", ".", "!", "?"])
    case .afrikaans: (afrikaansWords, [",", ".", "!", "?"])
    case .arabic: (arabicWords, ["،", "؛", "؟", "."])
    case .hebrew: (hebrewWords, [",", ".", "!", "?"])
    case .persian: (persianWords, ["،", "؛", "؟", "."])
    case .urdu: (urduWords, ["،", "؛", "؟", "."])
    case .tamil: (tamilWords, [",", ".", "!", "?"])
    case .hindi: (hindiWords, [",", ".", "!", "?"])
    case .gujarati: (gujaratiWords, [",", ".", "!", "?"])
    case .bangla: (banglaWords, [",", ".", "!", "?"])
    case .thai: (thaiWords, [",", ".", "!", "?"])
    case .nepali: (nepaliWords, [",", ".", "!", "?"])
    case .kannada: (kannadaWords, [",", ".", "!", "?"])
    case .telugu: (teluguWords, [",", ".", "!", "?"])
    case .malayalam: (malayalamWords, [",", ".", "!", "?"])
    case .sanskrit: (sanskritWords, [",", ".", "!", "?"])
    case .sinhala: (sinhalaWords, [",", ".", "!", "?"])
    case .khmer: (khmerWords, [",", ".", "!", "?"])
    case .myanmarBurmese: (myanmarBurmeseWords, [",", ".", "!", "?"])
    case .greek: (greekWords, [",", ".", "!", "?"])
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
    case .hungarian: (hungarianWords, [",", ".", "!", "?"])
    case .czech: (czechWords, [",", ".", "!", "?"])
    case .slovak: (slovakWords, [",", ".", "!", "?"])
    case .slovenian: (slovenianWords, [",", ".", "!", "?"])
    case .croatian: (croatianWords, [",", ".", "!", "?"])
    case .serbian: (serbianWords, [".", ",", "!", "?"])
    case .serbianLatin: (serbianLatinWords, [",", ".", "!", "?"])
    case .bulgarian: (bulgarianWords, [".", ",", "!", "?"])
    case .romanian: (romanianWords, [",", ".", "!", "?"])
    case .finnish: (finnishWords, [",", ".", "!", "?"])
    case .estonian: (estonianWords, [",", ".", "!", "?"])
    case .icelandic: (icelandicWords, [",", ".", "!", "?"])
    case .french: (frenchWords, [",", ".", "!", "?"])
    case .italian: (italianWords, [",", ".", "!", "?"])
    case .portuguese: (portugueseWords, [",", ".", "!", "?"])
    case .simplifiedChinese: (simplifiedChineseWords, ["，", "。", "！", "？"])
    case .traditionalChinese: (traditionalChineseWords, ["，", "。", "！", "？"])
    case .russian: (russianWords, [".", ",", "!", "?"])
    case .ukrainian: (ukrainianWords, [".", ",", "!", "?"])
    case .ukrainianLatin: (ukrainianLatinWords, [".", ",", "!", "?"])
    case .japaneseHiragana: (japaneseHiraganaWords, ["、", "。", "！", "？"])
    case .japaneseKatakana: (japaneseKatakanaWords, ["、", "。", "！", "？"])
    case .japaneseRomaji: (japaneseRomajiWords, [".", ",", "!", "?"])
    case .korean: (koreanWords, [".", ",", "!", "?"])
    case .turkish: (turkishWords, [".", ",", "!", "?"])
    case .polish: (polishWords, [".", ",", "!", "?"])
    default:
      (words, [",", ".", "!", "?"])
    }
  }

  private static func decoratedToken(
    from lexicon: [String], punctuation: [String], index: Int, contentOptions: ContentOptions,
    usesZipfFrequency: Bool
  ) -> String {
    let tokenIndex = usesZipfFrequency
      ? ZipfWordSelection.index(in: lexicon.count)
      : Int.random(in: lexicon.indices)
    var token = lexicon[tokenIndex]
    if contentOptions.includeNumbers, index.isMultiple(of: 9) { token += String(index / 9 + 1) }
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
  /// Typebar-owned practice words available to local features such as weak
  /// spot drills and the word filter. This never reads a reference word list.
  func ownedPracticeWords(englishVariant: EnglishVariant = .american) -> [String] {
    guard !isCodeLanguage else { return [] }
    return switch self {
    case .english: englishVariant == .british ? StarterLexicon.britishWords : StarterLexicon.words
    case .spanish: StarterLexicon.spanishWords
    case .german: StarterLexicon.germanWords
    case .afrikaans: StarterLexicon.afrikaansWords
    case .arabic: StarterLexicon.arabicWords
    case .hebrew: StarterLexicon.hebrewWords
    case .persian: StarterLexicon.persianWords
    case .urdu: StarterLexicon.urduWords
    case .tamil: StarterLexicon.tamilWords
    case .hindi: StarterLexicon.hindiWords
    case .gujarati: StarterLexicon.gujaratiWords
    case .bangla: StarterLexicon.banglaWords
    case .thai: StarterLexicon.thaiWords
    case .nepali: StarterLexicon.nepaliWords
    case .kannada: StarterLexicon.kannadaWords
    case .telugu: StarterLexicon.teluguWords
    case .malayalam: StarterLexicon.malayalamWords
    case .sanskrit: StarterLexicon.sanskritWords
    case .sinhala: StarterLexicon.sinhalaWords
    case .khmer: StarterLexicon.khmerWords
    case .myanmarBurmese: StarterLexicon.myanmarBurmeseWords
    case .greek: StarterLexicon.greekWords
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
    case .hungarian: StarterLexicon.hungarianWords
    case .czech: StarterLexicon.czechWords
    case .slovak: StarterLexicon.slovakWords
    case .slovenian: StarterLexicon.slovenianWords
    case .croatian: StarterLexicon.croatianWords
    case .serbian: StarterLexicon.serbianWords
    case .serbianLatin: StarterLexicon.serbianLatinWords
    case .bulgarian: StarterLexicon.bulgarianWords
    case .romanian: StarterLexicon.romanianWords
    case .finnish: StarterLexicon.finnishWords
    case .estonian: StarterLexicon.estonianWords
    case .icelandic: StarterLexicon.icelandicWords
    case .french: StarterLexicon.frenchWords
    case .italian: StarterLexicon.italianWords
    case .portuguese: StarterLexicon.portugueseWords
    case .simplifiedChinese: StarterLexicon.simplifiedChineseWords
    case .traditionalChinese: StarterLexicon.traditionalChineseWords
    case .russian: StarterLexicon.russianWords
    case .ukrainian: StarterLexicon.ukrainianWords
    case .ukrainianLatin: StarterLexicon.ukrainianLatinWords
    case .japaneseHiragana: StarterLexicon.japaneseHiraganaWords
    case .japaneseKatakana: StarterLexicon.japaneseKatakanaWords
    case .japaneseRomaji: StarterLexicon.japaneseRomajiWords
    case .korean: StarterLexicon.koreanWords
    case .turkish: StarterLexicon.turkishWords
    case .polish: StarterLexicon.polishWords
    case .mixedEnglishChinese: StarterLexicon.words
    case .mixedLanguages: []
    default: []
    }
  }

  static let defaultMixedComponents: [TypingLanguage] = [
    .english, .spanish, .german, .afrikaans, .tamil, .hindi, .gujarati, .bangla, .thai, .nepali, .kannada, .telugu, .malayalam, .sanskrit, .sinhala, .khmer, .myanmarBurmese, .greek, .greeklish, .dutch, .filipino, .catalan, .indonesian, .malay, .danish, .norwegianBokmal, .norwegianNynorsk, .swedish, .hungarian, .czech, .slovak, .slovenian, .croatian, .serbian, .serbianLatin, .bulgarian, .romanian, .finnish, .estonian, .icelandic, .french,
    .italian, .portuguese,
    .simplifiedChinese,
    .traditionalChinese, .russian, .ukrainian, .ukrainianLatin, .japaneseHiragana, .japaneseKatakana,
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
    self == .arabic || self == .hebrew || self == .persian || self == .urdu
  }

  var isNoSpaceLanguage: Bool {
    switch self {
    case .simplifiedChinese, .traditionalChinese, .japaneseHiragana, .japaneseKatakana: true
    default: false
    }
  }

  var isCodeLanguage: Bool {
    rawValue.hasPrefix("code")
  }

  /// Mirrors Monkeytype's `noLazyMode` language metadata for every Typebar
  /// wordset. Code prompts are likewise literal input, never accent-folded.
  var supportsLazyLatinInput: Bool {
    guard !isCodeLanguage else { return false }
    return switch self {
    case .english, .hebrew, .persian, .urdu,
      .tamil, .hindi, .gujarati, .bangla, .thai, .nepali, .kannada, .telugu, .malayalam,
      .sanskrit, .greeklish, .dutch, .filipino, .indonesian, .serbian, .bulgarian,
      .khmer,
      .myanmarBurmese,
      .simplifiedChinese, .traditionalChinese, .ukrainian, .ukrainianLatin,
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

  var displayName: String {
    if let codeName = CodeLanguageCatalog.displayNames[self] { return "Code · \(codeName)" }
    return switch self {
    case .english: "English"
    case .spanish: "Español"
    case .german: "Deutsch"
    case .afrikaans: "Afrikaans"
    case .arabic: "العربية"
    case .hebrew: "עברית"
    case .persian: "فارسی"
    case .urdu: "اردو"
    case .tamil: "தமிழ்"
    case .hindi: "हिन्दी"
    case .gujarati: "ગુજરાતી"
    case .bangla: "বাংলা"
    case .thai: "ไทย"
    case .nepali: "नेपाली"
    case .kannada: "ಕನ್ನಡ"
    case .telugu: "తెలుగు"
    case .malayalam: "മലയാളം"
    case .sanskrit: "संस्कृतम्"
    case .sinhala: "සිංහල"
    case .khmer: "ខ្មែរ"
    case .myanmarBurmese: "မြန်မာ"
    case .greek: "Ελληνικά"
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
    case .hungarian: "Magyar"
    case .czech: "Čeština"
    case .slovak: "Slovenčina"
    case .slovenian: "Slovenščina"
    case .croatian: "Hrvatski"
    case .serbian: "Српски"
    case .serbianLatin: "Srpski (Latin)"
    case .bulgarian: "Български"
    case .romanian: "Română"
    case .finnish: "Suomi"
    case .estonian: "Eesti"
    case .icelandic: "Íslenska"
    case .french: "Français"
    case .italian: "Italiano"
    case .portuguese: "Português"
    case .simplifiedChinese: "简体中文"
    case .traditionalChinese: "繁體中文"
    case .russian: "Русский"
    case .ukrainian: "Українська"
    case .ukrainianLatin: "Українська (Latin)"
    case .japaneseHiragana: "日本語（ひらがな）"
    case .japaneseKatakana: "日本語（カタカナ）"
    case .japaneseRomaji: "日本語（ローマ字）"
    case .korean: "한국어"
    case .turkish: "Türkçe"
    case .polish: "Polski"
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
