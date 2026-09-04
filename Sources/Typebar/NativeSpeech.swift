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
    case .greek: "el-GR"
    case .dutch: "nl-NL"
    case .danish: "da-DK"
    case .norwegianBokmal: "nb-NO"
    case .swedish: "sv-SE"
    case .hungarian: "hu-HU"
    case .french: "fr-FR"
    case .italian: "it-IT"
    case .portuguese: "pt-PT"
    case .simplifiedChinese, .mixedEnglishChinese: "zh-CN"
    case .traditionalChinese: "zh-TW"
    case .russian: "ru-RU"
    case .ukrainian, .ukrainianLatin: "uk-UA"
    case .japaneseHiragana, .japaneseKatakana: "ja-JP"
    case .korean: "ko-KR"
    case .turkish: "tr-TR"
    case .polish: "pl-PL"
    case .mixedLanguages: "en-US"
    default: "en-US"
    }
  }
}
