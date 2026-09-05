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
    case .swissGerman: "de-CH"
    case .afrikaans: "af-ZA"
    case .hausa: "ha"
    case .tatar: "tt"
    case .uzbek: "uz-UZ"
    case .occitan: "oc-FR"
    case .oromo: "om"
    case .jyutping: "zh-Hant"
    case .bashkir: "ba"
    case .basque: "eu"
    case .frisian: "fy-FY"
    case .hawaiian: "haw"
    case .kabyle: "kab"
    case .maltese: "mt"
    case .xhosa: "xh"
    case .friulian: "fur"
    case .bemba: "bem"
    case .azerbaijani: "az-AZ"
    case .belarusian: "be-BY"
    case .latvian: "lv"
    case .irish: "ga-IE"
    case .galician: "gl-ES"
    case .kurdishCentral: "ckb"
    case .arabic: "ar-SA"
    case .arabicEgypt: "ar-EG"
    case .arabicMorocco: "ar-MA"
    case .pashto: "ps"
    case .sindhi: "sd"
    case .hebrew: "he-IL"
    case .persian: "fa-IR"
    case .urdu: "ur-PK"
    case .tamil: "ta-IN"
    case .hindi: "hi-IN"
    case .gujarati: "gu-IN"
    case .bangla: "bn-BD"
    case .thai: "th-TH"
    case .nepali: "ne-NP"
    case .kannada: "kn-IN"
    case .telugu: "te-IN"
    case .malayalam: "ml-IN"
    case .sanskrit: "sa"
    case .sinhala: "si"
    case .khmer: "km-KH"
    case .myanmarBurmese: "my-MM"
    case .lao: "lo"
    case .amharic: "am-ET"
    case .armenianWestern: "hyw"
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
