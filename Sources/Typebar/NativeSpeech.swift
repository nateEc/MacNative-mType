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
    case .english, .englishFiveLetter, .englishCommonlyMisspelled, .englishContractions,
      .englishDoubleLetter, .englishLegal, .englishMedical, .englishShakespearean,
      .ukrainianEndings, .ukrainianLatynkaEndings: "en-US"
    case .kokanu: "xxs-Lat"
    case .likanu: "xxs-Uixs"
    case .pigLatin, .loremIpsum: "en-US"
    case .spanish: "es-ES"
    case .german: "de-DE"
    case .swissGerman: "de-CH"
    case .afrikaans: "af-ZA"
    case .hausa: "ha"
    case .tatar: "tt"
    case .tatarCrimean, .tatarCrimeanCyrillic: "crh-CRH"
    case .klingon: "tlh"
    case .quenya: "en-US"
    case .viossa, .viossaNjutro: "en-US"
    case .maori: "en-US"
    case .lojbanGismu, .lojbanCmavo: "en-US"
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
    case .tibetan: "bo-TI"
    case .kyrgyz: "ky-KY"
    case .kinyarwanda: "rw-RW"
    case .shona: "en-US"
    case .santali: "sat-IN"
    case .yiddish: "yi"
    case .friulian: "fur"
    case .bemba: "bem"
    case .azerbaijani: "az-AZ"
    case .belarusian: "be-BY"
    case .belarusianLacinka: "en-US"
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
    case .persianRomanized: "fa"
    case .urdu: "ur-PK"
    case .urduRoman: "ur-Latn"
    case .urdish: "en-US"
    case .tamil: "ta-IN"
    case .tanglish: "en-US"
    case .hindi: "hi-IN"
    case .hinglish: "en-US"
    case .gujarati: "gu-IN"
    case .bangla, .banglaLetters: "bn-BD"
    case .thai: "th-TH"
    case .nepali: "ne-NP"
    case .nepaliRomanized: "en-US"
    case .kannada: "kn-IN"
    case .telugu: "te-IN"
    case .malayalam: "ml-IN"
    case .sanskrit, .sanskritRoman: "sa"
    case .sinhala: "si"
    case .khmer: "km-KH"
    case .myanmarBurmese: "my-MM"
    case .lao: "lo"
    case .amharic: "am-ET"
    case .armenianWestern: "hyw"
    case .greek, .greekKoine, .greeklish: "el-GR"
    case .dutch: "nl-NL"
    case .filipino: "fil-PH"
    case .catalan: "ca-ES"
    case .indonesian: "id-ID"
    case .malay: "ms-MY"
    case .danish: "da-DK"
    case .norwegianBokmal: "nb-NO"
    case .norwegianNynorsk: "nn-NO"
    case .swedish, .swedishDiacritics: "sv-SE"
    case .hungarian: "hu-HU"
    case .czech: "cs-CZ"
    case .slovak: "sk-SK"
    case .slovenian: "sl-SI"
    case .croatian: "hr-HR"
    case .serbian, .serbianLatin: "sr-RS"
    case .bulgarian: "bg-BG"
    case .bulgarianLatin: "bg"
    case .romanian: "ro-RO"
    case .finnish: "fi-FI"
    case .estonian: "et-EE"
    case .icelandic: "is-IS"
    case .french: "fr-FR"
    case .italian: "it-IT"
    case .portuguese, .portugueseAccents: "pt-PT"
    case .simplifiedChinese, .mixedEnglishChinese: "zh-CN"
    case .traditionalChinese: "zh-TW"
    case .russian, .russianAbbreviations: "ru-RU"
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
