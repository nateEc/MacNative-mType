import AVFoundation

/// Local accessibility reading backed only by voices bundled with macOS.
@MainActor
final class NativeSpeech {
  static let shared = NativeSpeech()
  private let synthesizer = AVSpeechSynthesizer()

  func speak(_ text: String, language: TypingLanguage) {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return }
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: normalized)
    utterance.voice = AVSpeechSynthesisVoice(language: language.speechLocaleIdentifier)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    synthesizer.speak(utterance)
  }

  func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

extension TypingLanguage {
  var speechLocaleIdentifier: String {
    if isCodeLanguage { return "en-US" }
    return switch self {
    case .english: "en-US"
    case .spanish: "es-ES"
    case .german: "de-DE"
    case .afrikaans: "af-ZA"
    case .arabic: "ar-SA"
    case .hebrew: "he-IL"
    case .persian: "fa-IR"
    case .urdu: "ur-PK"
    case .tamil: "ta-IN"
    case .greek, .greeklish: "el-GR"
    case .dutch: "nl-NL"
    case .filipino: "fil-PH"
    case .catalan: "ca-ES"
    case .indonesian: "id-ID"
    case .malay: "ms-MY"
    case .danish: "da-DK"
    case .norwegianBokmal: "nb-NO"
    case .norwegianNynorsk: "nn-NO"
    case .swedish: "sv-SE"
    case .hungarian: "hu-HU"
    case .czech: "cs-CZ"
    case .slovak: "sk-SK"
    case .slovenian: "sl-SI"
    case .croatian: "hr-HR"
    case .serbian, .serbianLatin: "sr-RS"
    case .bulgarian: "bg-BG"
    case .romanian: "ro-RO"
    case .finnish: "fi-FI"
    case .estonian: "et-EE"
    case .icelandic: "is-IS"
    case .french: "fr-FR"
    case .italian: "it-IT"
    case .portuguese: "pt-PT"
    case .simplifiedChinese, .mixedEnglishChinese: "zh-CN"
    case .traditionalChinese: "zh-TW"
    case .russian: "ru-RU"
    case .ukrainian, .ukrainianLatin: "uk-UA"
    case .japaneseHiragana, .japaneseKatakana, .japaneseRomaji: "ja-JP"
    case .korean: "ko-KR"
    case .turkish: "tr-TR"
    case .polish: "pl-PL"
    case .mixedLanguages: "en-US"
    default: "en-US"
    }
  }
}
