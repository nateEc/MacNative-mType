import Foundation

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

enum TypingLanguage: String, CaseIterable, Codable, Equatable {
  case english
  case spanish
  case german
  case french
  case italian
  case portuguese
  case simplifiedChinese
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

  static func usesMotionCue(for character: Character) -> Bool {
    character.uppercased() == "J" || character.uppercased() == "Z"
  }
}

enum LayoutFluidPolicy {
  static let defaultLayouts: [KeyboardLayout] = [.ansiQwerty, .ansiColemak, .ansiDvorak]

  static func normalizedLayouts(_ layouts: [KeyboardLayout]) -> [KeyboardLayout] {
    var unique: [KeyboardLayout] = []
    for layout in layouts where !unique.contains(layout) {
      unique.append(layout)
    }
    return Array((unique.isEmpty ? defaultLayouts : unique).prefix(5))
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
    return expanded.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }
}

struct InputRules: Codable, Equatable {
  var strictSpace = false
  var stopOnError = false
  var deleteOnError = false
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
  /// is evaluated only after a correctly committed, space-delimited word.
  var minimumWordBurstWpm = 0

  init(
    strictSpace: Bool = false,
    stopOnError: Bool = false,
    deleteOnError: Bool = false,
    hideExtraLetters: Bool = false,
    blindMode: Bool = false,
    quickEnd: Bool = false,
    freedomMode: Bool = false,
    confidenceMode: ConfidenceMode = .off,
    oppositeShiftMode: OppositeShiftMode = .off,
    codeUnindentOnBackspace: Bool = false,
    minimumAccuracy: Int = 0,
    minimumWpm: Int = 0,
    minimumWordBurstWpm: Int = 0
  ) {
    self.strictSpace = strictSpace
    self.stopOnError = stopOnError
    self.deleteOnError = deleteOnError
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
  }

  private enum CodingKeys: String, CodingKey {
    case strictSpace, stopOnError, deleteOnError, hideExtraLetters, blindMode, quickEnd,
      freedomMode, confidenceMode, oppositeShiftMode, codeUnindentOnBackspace, minimumAccuracy, minimumWpm,
      minimumWordBurstWpm
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    strictSpace = try values.decodeIfPresent(Bool.self, forKey: .strictSpace) ?? false
    stopOnError = try values.decodeIfPresent(Bool.self, forKey: .stopOnError) ?? false
    deleteOnError = try values.decodeIfPresent(Bool.self, forKey: .deleteOnError) ?? false
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
    if normalizedRules.confidenceMode != .off {
      normalizedRules.freedomMode = false
      normalizedRules.stopOnError = false
      normalizedRules.deleteOnError = false
    }
    self.rules = normalizedRules
    self.language = language
    self.englishVariant = englishVariant
    self.quoteLength = quoteLength
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

  private enum CodingKeys: String, CodingKey {
    case mode, duration, wordLimit, difficulty, rules, language, englishVariant, quoteLength,
      customTextCompletion, customTextSectionLimit, customTextOrdering, mixedLanguageComponents,
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
    quoteLength = try values.decodeIfPresent(QuoteLength.self, forKey: .quoteLength) ?? .all
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
  case abandoned
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
  static func glyphs(
    target: String, typed: String, isFinished: Bool, blindMode: Bool,
    forcedErrorIndices: Set<Int> = [],
    visibleFutureWords: Int? = nil, concealAll: Bool = false,
    concealedCurrentAndFutureWords: Int? = nil, concealPendingCharacters: Bool = false
  ) -> [TypingPromptGlyph] {
    let targetCharacters = Array(target)
    let typedCharacters = Array(typed)
    var output = targetCharacters.indices.map { index in
      let state: TypingPromptCharacterState
      if index < typedCharacters.count {
        state =
          blindMode
          ? .hidden
          : typedCharacters[index] == targetCharacters[index] && !forcedErrorIndices.contains(index)
            ? .correct : .incorrect
      } else if index == typedCharacters.count, !isFinished {
        state = .current
      } else {
        state = .pending
      }
      return TypingPromptGlyph(
        character: targetCharacters[index], state: state,
        typedCharacter: state == .incorrect ? typedCharacters[index] : nil)
    }

    if let visibleFutureWords, !isFinished {
      let currentWord = targetCharacters.prefix(min(typedCharacters.count, targetCharacters.count))
        .filter { $0 == " " }.count
      var word = 0
      for index in output.indices {
        if index > 0, targetCharacters[index - 1] == " " { word += 1 }
        if index >= typedCharacters.count, word > currentWord + visibleFutureWords {
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
        index >= typedCharacters.count
          ? .init(character: glyph.character, state: .hidden, typedCharacter: glyph.typedCharacter)
          : glyph
      }
    }

    if let concealedCurrentAndFutureWords, !isFinished {
      let currentWord = targetCharacters.prefix(min(typedCharacters.count, targetCharacters.count))
        .filter { $0 == " " }.count
      var word = 0
      for index in output.indices {
        if index > 0, targetCharacters[index - 1] == " " { word += 1 }
        if (currentWord...(currentWord + concealedCurrentAndFutureWords - 1)).contains(word) {
          output[index] = .init(
            character: targetCharacters[index], state: .hidden,
            typedCharacter: output[index].typedCharacter)
        }
      }
    }

    guard typedCharacters.count > targetCharacters.count else { return output }
    output += typedCharacters.dropFirst(targetCharacters.count).map {
      TypingPromptGlyph(
        character: $0, state: blindMode || concealAll ? .hidden : .extra)
    }
    return output
  }
}

enum TypedCharacterEffectPolicy {
  /// Returns target-character positions belonging to words already submitted
  /// with a space. Deliberately independent from correctness: this is an
  /// appearance preference, not an input rule.
  static func completedCharacterIndices(target: String, typed: String, isFinished: Bool) -> Set<Int> {
    let targetCharacters = Array(target)
    let typedCharacters = Array(typed)
    var indices = Set<Int>()
    var wordStart = 0

    for index in targetCharacters.indices where targetCharacters[index] == " " {
      guard index < typedCharacters.count, typedCharacters[index] == " " else { continue }
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
    capsLockEnabled: Bool,
    language: TypingLanguage,
    isFinished: Bool,
    showFocusWarning: Bool,
    showCapsLockWarning: Bool
  ) -> [TypingAttentionWarning] {
    guard !isFinished else { return [] }
    var warnings: [TypingAttentionWarning] = []
    if showFocusWarning, !isInputFocused { warnings.append(.inputUnfocused) }
    if showCapsLockWarning, capsLockEnabled, language != .simplifiedChinese {
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

  private enum CodingKeys: String, CodingKey {
    case id, configuration, outcome, startedAt, finishedAt, typedCharacterCount,
      correctCharacterCount, errorCount, wpm, rawWpm, accuracy, tags, prompt, replayEvents
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    configuration = try values.decode(TestConfiguration.self, forKey: .configuration)
    outcome = try values.decode(TestOutcome.self, forKey: .outcome)
    startedAt = try values.decode(Date.self, forKey: .startedAt)
    finishedAt = try values.decode(Date.self, forKey: .finishedAt)
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

struct TypingSession {
  let configuration: TestConfiguration
  private(set) var prompt: String
  private let initialPrompt: String
  private let repeatingPrompt: String?
  private let sectionEndIndices: [Int]
  private(set) var typed = ""
  private var typedCharacterDates: [Date] = []
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
    sectionEndIndices: [Int] = []
  ) {
    self.configuration = configuration
    self.prompt = prompt
    self.initialPrompt = prompt
    self.repeatingPrompt = repeatingPrompt
    self.sectionEndIndices = sectionEndIndices
  }

  /// Starts an equivalent fresh attempt without regenerating content. This is
  /// intentionally based on the initial session prompt so timed custom text
  /// retains its original repeat source instead of reusing a grown prompt.
  func repeatedAttempt() -> TypingSession {
    TypingSession(
      configuration: configuration, prompt: initialPrompt, repeatingPrompt: repeatingPrompt,
      sectionEndIndices: sectionEndIndices)
  }

  var isFinished: Bool { outcome != .active }
  var hasStarted: Bool { startedAt != nil }
  var typedCharacterCount: Int { typed.count }
  var sectionProgress: (completed: Int, total: Int)? {
    guard !sectionEndIndices.isEmpty else { return nil }
    let completed = sectionEndIndices.filter { typed.count >= $0 }.count
    return (min(completed, sectionEndIndices.count), sectionEndIndices.count)
  }
  var nextExpectedCharacter: Character? {
    guard !isFinished, typed.count < prompt.count else { return nil }
    return Array(prompt)[typed.count]
  }

  var promptGlyphs: [TypingPromptGlyph] {
    TypingPromptPresentation.glyphs(
      target: prompt,
      typed: typed,
      isFinished: isFinished,
      blindMode: configuration.rules.blindMode,
      forcedErrorIndices: forcedErrorIndices,
      visibleFutureWords: configuration.language.usesSpaceDelimitedWords
        ? configuration.visibleFutureWordCount : nil,
      concealAll: configuration.modifiers.contains(.memory) && hasStarted && !isFinished,
      concealedCurrentAndFutureWords: hasStarted ? configuration.readAheadConcealedWordCount : nil,
      concealPendingCharacters: configuration.modifiers.contains(.simonSays)
    )
  }

  var errors: Int {
    Array(prompt).indices.prefix(typed.count).reduce(into: 0) { total, index in
      if !isTypedCharacterCorrect(at: index) { total += 1 }
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
    guard let lastSpace = characters.lastIndex(of: " ") else {
      return activeWordBurst(start: 0) ?? committedWordBursts.last ?? 0
    }
    let start = lastSpace + 1
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
    guard configuration.language.usesSpaceDelimitedWords,
      !configuration.modifiers.contains(.noSpaces), !typed.isEmpty
    else { return [] }
    let characters = Array(typed)
    guard characters.count == typedCharacterDates.count else { return [] }
    var bursts: [Int?] = []
    var wordStart = 0
    for index in characters.indices where characters[index] == " " {
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
    if configuration.language == .simplifiedChinese {
      return missedChineseWordErrorCounts
    }
    guard configuration.language.usesSpaceDelimitedWords,
      !configuration.modifiers.contains(.noSpaces)
    else { return [] }
    let targetWords = prompt.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
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

  /// Per-target-word event counts for the space-delimited path. It includes
  /// zeros for unattempted words so result review indices remain aligned.
  var missedWordErrorCountsByWord: [Int] {
    guard configuration.language.usesSpaceDelimitedWords,
      !configuration.modifiers.contains(.noSpaces)
    else { return [] }
    let targetWords = prompt.split(separator: " ", omittingEmptySubsequences: true)
    return targetWords.indices.map { attemptedInputErrorCount(inWord: $0) }
  }

  private var missedChineseWordErrorCounts: [MissedWordErrorCount] {
    let targetCharacters = Array(prompt)
    let tokens = StarterLexicon.simplifiedChineseWords.map {
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

  /// Per-word comparison for words actually attempted during a space-delimited test.
  var wordReviews: [TypedWordReview] {
    guard (!typed.isEmpty || !attemptedErrorCounts.isEmpty), configuration.language.usesSpaceDelimitedWords,
      !configuration.modifiers.contains(.noSpaces)
    else { return [] }
    let targetWords = prompt.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    let typedWords = typed.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    let finalAttemptedCount = typed.last == " " ? max(0, typedWords.count - 1) : typedWords.count
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
  /// space-delimited word tests show committed words out of their configured
  /// target without deriving any scoring state from this display.
  func progressText(at date: Date = .now) -> String? {
    if let remaining = remainingSeconds(at: date) { return "\(remaining)s" }
    guard let wordLimit = configuration.wordLimit,
      configuration.language.usesSpaceDelimitedWords,
      !configuration.modifiers.contains(.noSpaces)
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
      configuration.language.usesSpaceDelimitedWords,
      !configuration.modifiers.contains(.noSpaces)
    else { return nil }
    return Double(min(wordLimit, completedWordCount)) / Double(wordLimit)
  }

  var completedWordCount: Int {
    let targetCharacters = Array(prompt)
    let typedCharacters = Array(typed)
    let committed = targetCharacters.indices.filter {
      targetCharacters[$0] == " " && $0 < typedCharacters.count && typedCharacters[$0] == " "
    }.count
    guard isFinished, !typed.isEmpty else { return committed }
    return committed + 1
  }

  func result(at date: Date = .now) -> CompletedTestResult? {
    guard let startedAt, let finishedAt else { return nil }
    return .init(
      id: UUID(),
      configuration: configuration,
      outcome: outcome,
      startedAt: startedAt,
      finishedAt: finishedAt,
      typedCharacterCount: typed.count,
      correctCharacterCount: correctCharacters,
      errorCount: errors,
      wpm: wpm(at: date),
      rawWpm: rawWpm(at: date),
      accuracy: accuracy,
      prompt: prompt,
      replayEvents: replayEvents
    )
  }

  mutating func insert(_ text: String, forceError: Bool = false, at date: Date = .now) {
    guard !isFinished, !text.isEmpty else { return }
    beginIfNeeded(at: date)
    for character in text {
      guard !isFinished else { break }
      if insertCharacter(character, forceError: forceError, at: date) {
        recordReplayEvent(kind: .insert, text: String(character), forceError: forceError, at: date)
        insertCodeIndentationIfNeeded(after: character, at: date)
      }
    }
    finishIfNeeded(at: date)
  }

  mutating func deleteBackward(at date: Date = .now) {
    guard !isFinished, !typed.isEmpty else { return }
    guard canDeleteBackward else { return }
    if configuration.rules.codeUnindentOnBackspace, configuration.language.isCodeLanguage,
      removeCodeIndentationBeforeLine(at: date)
    {
      return
    }
    typed.removeLast()
    typedCharacterDates.removeLast()
    forcedErrorIndices.remove(typed.count)
    recordReplayEvent(kind: .delete, text: "", at: date)
  }

  private var canDeleteBackward: Bool {
    if configuration.rules.confidenceMode == .maximum { return false }
    guard !configuration.rules.freedomMode, typed.last == " " else { return true }
    if configuration.rules.confidenceMode == .on { return lastCommittedWordIsCorrect }
    let completedWords = typed.dropLast().split(separator: " ", omittingEmptySubsequences: true)
    guard let typedWord = completedWords.last else { return true }
    let targetWords = prompt.split(separator: " ", omittingEmptySubsequences: true)
    let index = completedWords.count - 1
    guard index < targetWords.count else { return true }
    return typedWord != targetWords[index]
  }

  mutating func replaceInput(with value: String, at date: Date = .now) {
    guard !isFinished else { return }
    if value.count < typed.count {
      typed = value
      typedCharacterDates = Array(typedCharacterDates.prefix(value.count))
      forcedErrorIndices = Set(forcedErrorIndices.filter { $0 < value.count })
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

  private mutating func beginIfNeeded(at date: Date) {
    if startedAt == nil { startedAt = date }
  }

  @discardableResult
  private mutating func insertCharacter(
    _ character: Character, forceError: Bool, at date: Date
  ) -> Bool {
    extendPromptIfNeeded()
    if typed.count >= prompt.count {
      if !configuration.rules.hideExtraLetters {
        typed.append(character)
        typedCharacterDates.append(date)
        recordWordBurstIfCommitted()
        return true
      }
      return false
    }
    let expected = Array(prompt)[typed.count]
    let isCorrect = character == expected && !forceError
    if !isCorrect { attemptedErrorCounts[typed.count, default: 0] += 1 }
    if character == " ", configuration.modifiers.contains(.correctBeforeAdvance),
      configuration.language.usesSpaceDelimitedWords, !configuration.modifiers.contains(.noSpaces),
      !currentWordIsCorrect
    {
      return false
    }
    if character == " " && configuration.rules.strictSpace && expected != " " { return false }
    if !isCorrect && configuration.rules.stopOnError { return false }
    if !isCorrect && configuration.rules.deleteOnError { return false }
    if !isCorrect && configuration.modifiers.contains(.clearCurrentWordOnError),
      configuration.language.usesSpaceDelimitedWords, !configuration.modifiers.contains(.noSpaces)
    {
      clearCurrentWord(at: date)
      return false
    }
    typed.append(character)
    typedCharacterDates.append(date)
    if forceError { forcedErrorIndices.insert(typed.count - 1) }
    recordWordBurstIfCommitted()

    if configuration.difficulty == .master && !isCorrect {
      fail(at: date)
    } else if configuration.difficulty == .expert && character == " " && errorsInCurrentWord() > 0 {
      fail(at: date)
    } else if shouldFailMinimumWordBurst(after: character) {
      fail(at: date)
    }
    return true
  }

  private var currentWordIsCorrect: Bool {
    let targetWords = prompt.split(separator: " ", omittingEmptySubsequences: true)
    let typedWords = typed.split(separator: " ", omittingEmptySubsequences: false)
    let wordIndex = typed.last == " " ? max(typedWords.count - 1, 0) : typedWords.count - 1
    guard wordIndex >= 0, wordIndex < targetWords.count, wordIndex < typedWords.count else {
      return false
    }
    return typedWords[wordIndex] == targetWords[wordIndex] && !hasForcedError(inWord: wordIndex)
  }

  /// Removes accepted characters from the active, unfinished word while
  /// preserving any already submitted words. Each removal becomes a replay
  /// event so result playback reconstructs the same input state.
  private mutating func clearCurrentWord(at date: Date) {
    while let last = typed.last, last != " " {
      typed.removeLast()
      typedCharacterDates.removeLast()
      forcedErrorIndices.remove(typed.count)
      recordReplayEvent(kind: .delete, text: "", at: date)
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
    let typedWords = typed.split(separator: " ", omittingEmptySubsequences: false)
    let promptWords = prompt.split(separator: " ", omittingEmptySubsequences: false)
    guard let typedWord = typedWords.dropLast().last, typedWords.count - 2 < promptWords.count
    else { return 0 }
    let promptWord = promptWords[typedWords.count - 2]
    let typedCharacters = Array(typed)
    let wordStart = typedCharacters.indices.reversed().first(where: {
      $0 < typedCharacters.count - 1 && typedCharacters[$0] == " "
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
    guard characters.last == " ", typedCharacterDates.count == characters.count else { return }
    let end = characters.count - 1
    var start = 0
    if end > 0, let separator = characters[..<end].lastIndex(of: " ") {
      start = separator + 1
    }
    guard start < end else { return }
    let elapsed = typedCharacterDates[end].timeIntervalSince(typedCharacterDates[start])
    guard elapsed > 0 else { return }
    committedWordBursts.append(wpm(characters: end - start + 1, seconds: elapsed))
  }

  private func shouldFailMinimumWordBurst(after character: Character) -> Bool {
    let minimum = configuration.rules.minimumWordBurstWpm
    guard minimum > 0,
      character == " ",
      configuration.language.usesSpaceDelimitedWords,
      !configuration.modifiers.contains(.noSpaces),
      lastCommittedWordIsCorrect,
      let burst = committedWordBursts.last
    else { return false }
    return burst < minimum
  }

  private var lastCommittedWordIsCorrect: Bool {
    guard typed.last == " " else { return false }
    let committedWords = typed.dropLast().split(separator: " ", omittingEmptySubsequences: true)
    let targetWords = prompt.split(separator: " ", omittingEmptySubsequences: true)
    guard let submitted = committedWords.last, committedWords.count <= targetWords.count else {
      return false
    }
    return submitted == targetWords[committedWords.count - 1]
      && !hasForcedError(inWord: committedWords.count - 1)
  }

  private func isTypedCharacterCorrect(at index: Int) -> Bool {
    let typedCharacters = Array(typed)
    let targetCharacters = Array(prompt)
    guard index < typedCharacters.count, index < targetCharacters.count else { return false }
    return typedCharacters[index] == targetCharacters[index] && !forcedErrorIndices.contains(index)
  }

  private mutating func insertCodeIndentationIfNeeded(after character: Character, at date: Date) {
    guard character == "\n", configuration.language.isCodeLanguage,
      isTypedCharacterCorrect(at: typed.count - 1)
    else { return }
    while typed.count < prompt.count, Array(prompt)[typed.count] == "\t" {
      typed.append("\t")
      typedCharacterDates.append(date)
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
      typed.removeLast()
      typedCharacterDates.removeLast()
      forcedErrorIndices.remove(typed.count)
      recordReplayEvent(kind: .delete, text: "", automatic: true, at: date)
    }
    guard typed.last == "\n" else { return false }
    typed.removeLast()
    typedCharacterDates.removeLast()
    forcedErrorIndices.remove(typed.count)
    recordReplayEvent(kind: .delete, text: "", automatic: true, at: date)
    return true
  }

  private func hasForcedError(inWord word: Int) -> Bool {
    hasError(inWord: word, indices: forcedErrorIndices)
  }

  private func hasAttemptedInputError(inWord word: Int) -> Bool {
    attemptedInputErrorCount(inWord: word) > 0
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
    let targetCharacters = Array(prompt)
    var currentWord = 0
    var start = 0
    for index in targetCharacters.indices {
      if targetCharacters[index] == " " {
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
        if typed.count >= prompt.count { complete(at: date) }
      } else if !configuration.language.usesSpaceDelimitedWords
        || configuration.modifiers.contains(.noSpaces)
      {
        if typed.count >= prompt.count { complete(at: date) }
      } else if shouldFinishEnglishWordsTest {
        complete(at: date)
      }
    case .quote:
      if typed.count >= prompt.count { complete(at: date) }
    case .custom:
      switch configuration.customTextCompletion {
      case .finish:
        if typed.count >= prompt.count { complete(at: date) }
      case .time:
        break
      case .words:
        if shouldFinishEnglishWordsTest { complete(at: date) }
      case .sections:
        if typed.count >= prompt.count { complete(at: date) }
      }
    case .time, .zen:
      break
    }
  }

  private mutating func extendPromptIfNeeded() {
    guard typed.count >= prompt.count, let repeatingPrompt, !repeatingPrompt.isEmpty else { return }
    prompt += prompt.last?.isWhitespace == true ? repeatingPrompt : " \(repeatingPrompt)"
  }

  private var shouldFinishEnglishWordsTest: Bool {
    guard let wordLimit = configuration.wordLimit else { return false }
    let targetWords = Array(
      prompt.split(separator: " ", omittingEmptySubsequences: true).prefix(wordLimit))
    let typedWords = typed.split(separator: " ", omittingEmptySubsequences: true)
    guard targetWords.count == wordLimit, typedWords.count >= wordLimit else { return false }
    let expectedInput = targetWords.map(String.init).joined(separator: " ")

    // A correct final word always completes. A user can otherwise commit an
    // incorrect final word with space, matching normal typing behavior.
    if typed == expectedInput || typed.last == " " { return true }

    // Quick end only applies at the final generated word and is deliberately
    // disabled when an error rule would reject the same character upstream.
    let allowsQuickEnd =
      configuration.rules.quickEnd
      && !configuration.rules.stopOnError
      && !configuration.rules.deleteOnError
    return allowsQuickEnd && typedWords[wordLimit - 1].count == targetWords[wordLimit - 1].count
  }

  private mutating func complete(at date: Date) {
    if (configuration.rules.minimumAccuracy > 0 && accuracy < configuration.rules.minimumAccuracy)
      || (configuration.rules.minimumWpm > 0 && wpm(at: date) < configuration.rules.minimumWpm)
    {
      fail(at: date)
    } else {
      outcome = .completed
      finishedAt = date
    }
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
    case .french: (frenchWords, [",", ".", "!", "?"])
    case .italian: (italianWords, [",", ".", "!", "?"])
    case .portuguese: (portugueseWords, [",", ".", "!", "?"])
    case .simplifiedChinese: (simplifiedChineseWords, ["，", "。", "！", "？"])
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
  static let defaultMixedComponents: [TypingLanguage] = [
    .english, .spanish, .german, .french, .italian, .portuguese, .simplifiedChinese,
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
    self != .simplifiedChinese && !isCodeLanguage
  }

  var isCodeLanguage: Bool {
    rawValue.hasPrefix("code")
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
    case .french: "Français"
    case .italian: "Italiano"
    case .portuguese: "Português"
    case .simplifiedChinese: "简体中文"
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
