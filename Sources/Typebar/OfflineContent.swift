import Foundation

struct OfflineQuote: Identifiable, Hashable {
  let id: String
  let title: String
  let text: String
  let language: TypingLanguage
  let length: QuoteLength
}

enum QuoteLengthPolicy {
  static func actualLength(for prompt: String, language: TypingLanguage) -> QuoteLength {
    if let authoredQuote = OfflineContent.quotes.first(where: {
      $0.language == language && $0.text == prompt
    }) {
      return authoredQuote.length
    }
    switch prompt.count {
    case ...120: return .short
    case ...240: return .medium
    case ...480: return .long
    default: return .extended
    }
  }
}

/// Mirrors the user-facing quote-length selection without retaining the
/// reference app's numeric groups or quote data. A selection never becomes
/// empty: selecting all four lengths is the stable "all" representation.
enum QuoteLengthSelection {
  static let selectable = Set(QuoteLength.allCases.filter { $0 != .all })

  static func normalized(_ selection: Set<QuoteLength>) -> Set<QuoteLength> {
    let supported = selection.intersection(selectable)
    return supported.isEmpty ? selectable : supported
  }

  static func fromLegacy(_ length: QuoteLength) -> Set<QuoteLength> {
    length == .all ? selectable : [length]
  }

  static func legacyValue(for selection: Set<QuoteLength>) -> QuoteLength {
    let normalized = normalized(selection)
    return normalized.count == 1 ? normalized.first! : .all
  }

  static func summary(_ selection: Set<QuoteLength>) -> String {
    let normalized = normalized(selection)
    guard normalized != selectable else { return "全部" }
    return QuoteLength.allCases.filter(normalized.contains).map(\.displayName).joined(separator: "、")
  }
}

/// A process-local quote cycle. It produces every currently eligible quote
/// once before reshuffling, and avoids showing the active quote again when an
/// alternative exists. The queue intentionally is not stored in settings.
struct QuoteQueue {
  private var sourceIDs: [String] = []
  private var pendingIDs: [String] = []

  mutating func reset() {
    sourceIDs = []
    pendingIDs = []
  }

  mutating func next(from quotes: [OfflineQuote], avoiding currentID: String?) -> String? {
    let ids = uniqueIDs(in: quotes)
    guard !ids.isEmpty else {
      reset()
      return nil
    }
    if ids != sourceIDs {
      sourceIDs = ids
      pendingIDs = []
    }
    if pendingIDs.isEmpty { pendingIDs = ids.shuffled() }
    if pendingIDs.count > 1, let currentID, pendingIDs.first == currentID,
      let alternative = pendingIDs.firstIndex(where: { $0 != currentID })
    {
      pendingIDs.swapAt(0, alternative)
    }
    return pendingIDs.removeFirst()
  }

  private func uniqueIDs(in quotes: [OfflineQuote]) -> [String] {
    var seen = Set<String>()
    return quotes.map(\.id).filter { seen.insert($0).inserted }
  }
}

enum QuoteRestartPolicy {
  /// Opting in repeats the current quote only when the user restarts an
  /// in-progress attempt, never after it is finished.
  static func shouldKeepCurrent(repeatWhileTyping: Bool, hasStarted: Bool, isFinished: Bool) -> Bool {
    repeatWhileTyping && hasStarted && !isFinished
  }
}

enum OfflineContent {
  // All text in this file is Typebar-authored starter content.
  static let quotes = [
    OfflineQuote(
      id: "craft",
      title: "Craft",
      text:
        "A small practice repeated with care becomes a skill you can trust when the room is quiet.",
      language: .english,
      length: .short
    ),
    OfflineQuote(
      id: "distance",
      title: "Distance",
      text:
        "Progress is rarely a sudden leap; more often it is the distance between two ordinary mornings.",
      language: .english,
      length: .short
    ),
    OfflineQuote(
      id: "attention",
      title: "Attention",
      text:
        "Attention is a lantern: point it at one useful thing, and the next step becomes visible.",
      language: .english,
      length: .short
    ),
    OfflineQuote(
      id: "field-notes",
      title: "Field Notes",
      text:
        "Good work leaves small signals behind: a clearer question, a tidier draft, and enough energy to return tomorrow.",
      language: .english,
      length: .medium
    ),
    OfflineQuote(
      id: "threshold",
      title: "Threshold",
      text:
        "The useful moment is often not dramatic. It arrives when you notice a difficult task, make room for it, and begin before confidence has caught up.",
      language: .english,
      length: .medium
    ),
    OfflineQuote(
      id: "steady-hands",
      title: "Steady Hands",
      text:
        "A patient routine does not remove uncertainty, but it gives uncertainty a smaller stage. Write down the next move, make it carefully, and let the evidence change the plan instead of letting the noise choose for you.",
      language: .english,
      length: .long
    ),
    OfflineQuote(
      id: "workshop-light",
      title: "Workshop Light",
      text:
        "There is a kind of progress that is easy to miss while it is happening. A phrase becomes easier to type, a decision needs fewer revisions, and a quiet habit starts carrying weight that will only become visible much later.",
      language: .english,
      length: .long
    ),
    OfflineQuote(
      id: "paso-claro",
      title: "Paso claro",
      text: "Un paso pequeño y bien elegido puede abrir una mañana entera de trabajo tranquilo.",
      language: .spanish,
      length: .short
    ),
    OfflineQuote(
      id: "mesa-luz",
      title: "Luz de mesa",
      text: "La atención vuelve cuando dejamos una sola tarea sobre la mesa y empezamos por ella.",
      language: .spanish,
      length: .short
    ),
    OfflineQuote(
      id: "ritmo-propio",
      title: "Ritmo propio",
      text:
        "Practicar no significa correr sin descanso. Significa volver al ritmo que permite observar, corregir y continuar con paciencia.",
      language: .spanish,
      length: .medium
    ),
    OfflineQuote(
      id: "cuaderno-abierto",
      title: "Cuaderno abierto",
      text:
        "Un cuaderno abierto no resuelve por sí solo una pregunta difícil, pero invita a dividirla en partes claras y a dejar una señal útil para el siguiente intento.",
      language: .spanish,
      length: .medium
    ),
    OfflineQuote(
      id: "orilla-lenta",
      title: "Orilla lenta",
      text:
        "Hay avances que llegan sin ruido. Una frase se vuelve más fácil, una decisión necesita menos vueltas y una práctica sencilla empieza a sostener días que antes parecían demasiado largos.",
      language: .spanish,
      length: .long
    ),
    OfflineQuote(
      id: "faro-paciente",
      title: "Faro paciente",
      text:
        "La paciencia no exige quedarse quieto. Puede ser una forma de avanzar con cuidado: mirar lo que funciona, anotar lo aprendido y elegir el próximo movimiento antes de que la prisa decida por nosotros.",
      language: .spanish,
      length: .long
    ),
    OfflineQuote(
      id: "leiser-schritt",
      title: "Leiser Schritt",
      text: "Ein kleiner klarer Schritt kann einen ruhigen Morgen für die nächste Aufgabe öffnen.",
      language: .german,
      length: .short
    ),
    OfflineQuote(
      id: "am-fenster",
      title: "Am Fenster",
      text:
        "Wenn nur eine Aufgabe auf dem Tisch liegt, findet die Aufmerksamkeit leichter zu ihrem eigenen Tempo zurück.",
      language: .german,
      length: .medium
    ),
    OfflineQuote(
      id: "dauerhafte-übung",
      title: "Dauerhafte Übung",
      text:
        "Eine gute Übung verlangt keinen großen Auftritt. Sie sammelt sich in vielen stillen Wiederholungen, bis ein schwieriger Satz vertrauter wirkt und der nächste Versuch weniger Kraft kostet.",
      language: .german,
      length: .long
    ),
    OfflineQuote(
      id: "greek-small-step",
      title: "Μικρό βήμα",
      text: "Μια ήρεμη άσκηση μπορεί να κάνει την επόμενη κίνηση πιο καθαρή.",
      language: .greek,
      length: .short
    ),
    OfflineQuote(
      id: "greek-open-note",
      title: "Ανοιχτή σημείωση",
      text: "Μια ανοιχτή σημείωση δεν λύνει μόνη της μια δύσκολη ερώτηση, αλλά βοηθά να χωρίσουμε το έργο σε καθαρά βήματα.",
      language: .greek,
      length: .medium
    ),
    OfflineQuote(
      id: "greek-calm-work",
      title: "Ήρεμη εργασία",
      text: "Η πρόοδος δεν φαίνεται πάντα σε μια μεγάλη στιγμή. Χτίζεται με μικρές επιστροφές: ανοίγουμε την ίδια σελίδα, κάνουμε μια πρόταση πιο καθαρή, διορθώνουμε ένα λάθος και αφήνουμε μια χρήσιμη σημείωση για την επόμενη προσπάθεια.",
      language: .greek,
      length: .long
    ),
    OfflineQuote(
      id: "greek-long-table",
      title: "Μεγάλο τραπέζι",
      text: "Ένα μεγάλο τραπέζι είναι χρήσιμο επειδή αφήνει χώρο για διαφορετικές μορφές εργασίας. Στη μία άκρη μπορεί να βρίσκεται ένα πρώτο σχέδιο, στην άλλη μια πρόταση που ακόμη χρειάζεται προσοχή, και στη μέση μένει χώρος για την επόμενη μικρή απόφαση. Η άσκηση λειτουργεί με παρόμοιο τρόπο: δεν ζητά να λυθούν όλες οι δυσκολίες αμέσως, αλλά να υπάρχει ένα μέρος όπου επιστρέφουμε, ένα ορατό επόμενο βήμα και αρκετή υπομονή για να προσέξουμε τι γίνεται ευκολότερο μετά από μερικές προσπάθειες.",
      language: .greek,
      length: .extended
    ),
    OfflineQuote(
      id: "greeklish-small-step",
      title: "Mikro vima",
      text: "Ena iremo vima kanei tin epomeni kinisi pio ksekathari.",
      language: .greeklish,
      length: .short
    ),
    OfflineQuote(
      id: "greeklish-open-note",
      title: "Anoichti simeiosi",
      text: "Mia anoichti simeiosi den lyei moni tis mia dyskoli erotisi, alla voithaei ti skepsi na valei kathara vimata se seira.",
      language: .greeklish,
      length: .medium
    ),
    OfflineQuote(
      id: "greeklish-calm-work",
      title: "Iremi ergasia",
      text: "I proodos den fainetai panta se mia megali stigmi. Chtizetai me mikres epistrofes: anoigoume tin idia selida, kanoume mia protasi pio kathari, diorthonoume ena lathos kai afinoume mia chrisimi simeiosi gia tin epomeni prospatheia.",
      language: .greeklish,
      length: .long
    ),
    OfflineQuote(
      id: "greeklish-long-table",
      title: "Megalo trapezi",
      text: "Ena megalo trapezi afinei choro gia diaforetika eidi ergasias. Sti mia akri mporei na yparchei ena proto schedio, stin alli mia protasi pou chreiazetai akomi prosochi, kai sti mesi na mene i epomeni mikri apofasi. I askisi leitourgei me paromoio tropo. Den zita na lythoun oles oi dyskolies amesos, alla na yparchei ena meros opou epistrefoume, na vroume to epomeno vima kai na exoume arketo chrono na paratiroume ti ginetai pio eukolo meta apo merikes prospatheies.",
      language: .greeklish,
      length: .extended
    ),
    OfflineQuote(
      id: "pas-calme",
      title: "Pas calme",
      text: "Un pas attentif peut rendre le prochain geste plus simple et la journée plus claire.",
      language: .french,
      length: .short
    ),
    OfflineQuote(
      id: "carnet-ouvert",
      title: "Carnet ouvert",
      text:
        "Un carnet ouvert ne répond pas seul aux questions difficiles, mais il aide à les découper, à noter ce qui compte et à revenir avec une idée plus précise.",
      language: .french,
      length: .medium
    ),
    OfflineQuote(
      id: "atelier-silencieux",
      title: "Atelier silencieux",
      text:
        "Le progrès ne demande pas toujours une grande déclaration. Il se rassemble dans les gestes qui reviennent: ouvrir le même carnet, préciser une phrase, corriger une erreur et laisser une petite preuve utile pour le lendemain. Avec le temps, cette attention tranquille rend les passages difficiles moins étrangers.",
      language: .french,
      length: .long
    ),
    OfflineQuote(
      id: "passo-lento",
      title: "Passo lento",
      text: "Un passo scelto con cura può rendere più chiaro il lavoro che aspetta domani.",
      language: .italian,
      length: .short
    ),
    OfflineQuote(
      id: "taccuino-aperto",
      title: "Taccuino aperto",
      text:
        "Un taccuino aperto non risolve da solo una domanda difficile, ma invita a dividerla in parti utili e a lasciare una traccia per il tentativo successivo.",
      language: .italian,
      length: .medium
    ),
    OfflineQuote(
      id: "officina-quieta",
      title: "Officina quieta",
      text:
        "Il progresso non ha sempre bisogno di un annuncio importante. Cresce nei gesti che ritornano: aprire lo stesso taccuino, chiarire una frase, correggere un errore e lasciare una piccola traccia utile per domani. Con il tempo, questa attenzione calma rende meno estranei anche i passaggi più difficili.",
      language: .italian,
      length: .long
    ),
    OfflineQuote(
      id: "passo-claro",
      title: "Passo claro",
      text:
        "Um passo pequeno e atento pode deixar a próxima tarefa mais simples e a manhã mais clara.",
      language: .portuguese,
      length: .short
    ),
    OfflineQuote(
      id: "caderno-aberto",
      title: "Caderno aberto",
      text:
        "Um caderno aberto não resolve sozinho uma pergunta difícil, mas ajuda a separar as partes úteis e a voltar com uma ideia mais precisa.",
      language: .portuguese,
      length: .medium
    ),
    OfflineQuote(
      id: "oficina-calma",
      title: "Oficina calma",
      text:
        "O progresso não precisa de um anúncio grande. Ele aparece nos gestos que voltam: abrir o mesmo caderno, ajustar uma frase, corrigir um erro e deixar uma pequena pista útil para amanhã. Com o tempo, essa atenção tranquila torna os trechos difíceis menos distantes.",
      language: .portuguese,
      length: .long
    ),
    OfflineQuote(
      id: "morning",
      title: "清晨",
      text: "清晨留出一段安静的时间，手边的一小步也会慢慢变得清晰。",
      language: .simplifiedChinese,
      length: .short
    ),
    OfflineQuote(
      id: "path",
      title: "路径",
      text: "真正可靠的进步不必喧闹，它藏在每一次愿意重新开始的练习里。",
      language: .simplifiedChinese,
      length: .short
    ),
    OfflineQuote(
      id: "window-light",
      title: "窗光",
      text: "当注意力落在眼前的文字上，远处的答案也会向你靠近一点。",
      language: .simplifiedChinese,
      length: .short
    ),
    OfflineQuote(
      id: "留白",
      title: "留白",
      text: "把复杂的事情拆成可以完成的小段，今天的心就会多出一点从容。",
      language: .simplifiedChinese,
      length: .medium
    ),
    OfflineQuote(
      id: "灯下",
      title: "灯下",
      text: "练习并不要求每一次都完美，它更在意你是否愿意在下一次回到桌前。",
      language: .simplifiedChinese,
      length: .medium
    ),
    OfflineQuote(
      id: "缓慢成形",
      title: "缓慢成形",
      text: "真正可靠的能力往往在安静处缓慢成形。它不靠一次热烈的冲刺证明自己，而是在许多普通的日子里，把一次次认真完成的小事连成稳定的方向。",
      language: .simplifiedChinese,
      length: .long
    ),
    OfflineQuote(
      id: "窗边的纸",
      title: "窗边的纸",
      text: "当你把注意力交给眼前这一行字，外界的催促会暂时退到远处。完成一个句子，再完成下一个句子，原本模糊的想法也会在这样的节奏里逐渐清楚。",
      language: .simplifiedChinese,
      length: .long
    ),
    OfflineQuote(
      id: "korean-small-step",
      title: "작은 걸음",
      text: "작은 연습을 꾸준히 하면 다음에 할 일이 조금 더 또렷해진다.",
      language: .korean,
      length: .short
    ),
    OfflineQuote(
      id: "korean-open-page",
      title: "펼친 페이지",
      text: "펼친 페이지가 어려운 답을 바로 주지는 않지만, 생각을 나누고 다음에 돌아올 자리를 남겨 준다.",
      language: .korean,
      length: .medium
    ),
    OfflineQuote(
      id: "korean-quiet-work",
      title: "조용한 일",
      text: "진전은 언제나 큰 소식으로 찾아오지 않는다. 같은 페이지를 다시 열고, 한 문장을 고치고, 한 번의 실수를 살피며 다음 시도를 위한 표시를 남기는 일에서 조금씩 쌓인다. 이런 차분한 주의가 어려운 부분을 익숙한 길로 바꾼다.",
      language: .korean,
      length: .long
    ),
    OfflineQuote(
      id: "korean-long-table",
      title: "긴 책상",
      text: "긴 책상이 쓸모 있는 이유는 서로 다른 단계의 일을 함께 놓을 수 있기 때문이다. 한쪽에는 처음 쓴 메모를 두고, 다른 쪽에는 아직 다듬을 문장을 두며, 가운데에는 다음 작은 결정을 위한 빈자리를 남길 수 있다. 연습도 이와 같다. 모든 어려움을 한 번에 풀기보다, 다시 돌아올 곳과 눈에 보이는 다음 걸음을 만들고 여러 번의 시도 끝에 무엇이 쉬워졌는지 살펴보게 한다.",
      language: .korean,
      length: .extended
    ),
    OfflineQuote(
      id: "turkish-kucuk-adim",
      title: "Küçük adım",
      text: "Küçük ve sakin bir adım, sıradaki işi daha açık görmeye yardım eder.",
      language: .turkish,
      length: .short
    ),
    OfflineQuote(
      id: "turkish-acik-defter",
      title: "Açık defter",
      text: "Açık bir defter zor bir soruyu tek başına çözmez, ama onu anlaşılır parçalara ayırmaya ve sonra geri dönmeye yardım eder.",
      language: .turkish,
      length: .medium
    ),
    OfflineQuote(
      id: "turkish-sessiz-calisma",
      title: "Sessiz çalışma",
      text: "İlerleme her zaman büyük bir duyuruyla gelmez. Aynı sayfayı açmak, bir cümleyi düzeltmek, bir hatayı incelemek ve sonraki deneme için küçük bir işaret bırakmakla birikir. Bu sakin dikkat, zor görünen bölümleri zamanla daha tanıdık hâle getirir.",
      language: .turkish,
      length: .long
    ),
    OfflineQuote(
      id: "turkish-uzun-masa",
      title: "Uzun masa",
      text: "Uzun bir masa, çalışmanın farklı aşamalarına yer açtığı için kullanışlıdır. Bir ucunda ilk taslak, diğer ucunda hâlâ özen isteyen bir cümle durabilir; ortada ise sıradaki küçük karar için boşluk kalır. Alıştırma da buna benzer. Her zorluğu hemen çözmeyi değil, dönülebilecek bir yer, görünür bir sonraki adım ve birkaç denemeden sonra kolaylaşanı fark edecek sabrı ister.",
      language: .turkish,
      length: .extended
    ),
    OfflineQuote(
      id: "polish-maly-krok",
      title: "Mały krok",
      text: "Mały, spokojny krok pomaga wyraźniej zobaczyć następną rzecz do zrobienia.",
      language: .polish,
      length: .short
    ),
    OfflineQuote(
      id: "polish-otwarty-notatnik",
      title: "Otwarty notatnik",
      text: "Otwarty notatnik nie odpowiada sam na trudne pytanie, ale pomaga podzielić je na jasne części i zostawić ślad na później.",
      language: .polish,
      length: .medium
    ),
    OfflineQuote(
      id: "polish-cicha-praca",
      title: "Cicha praca",
      text: "Postęp nie zawsze przychodzi jako ważne wydarzenie. Zbiera się w powtarzanych czynnościach: otwarciu tej samej strony, poprawieniu jednego zdania, sprawdzeniu jednego błędu i zostawieniu użytecznej wskazówki na następną próbę. Z czasem taka spokojna uwaga sprawia, że trudne miejsca stają się bardziej znajome.",
      language: .polish,
      length: .long
    ),
    OfflineQuote(
      id: "polish-dlugi-stol",
      title: "Długi stół",
      text: "Długi stół jest użyteczny, ponieważ mieści różne etapy pracy. Na jednym końcu może leżeć pierwszy szkic, na drugim zdanie wymagające jeszcze troski, a pośrodku zostaje miejsce na następną małą decyzję. Ćwiczenie działa podobnie: nie prosi o rozwiązanie wszystkich trudności naraz, lecz o miejsce, do którego można wrócić, widoczny kolejny krok i cierpliwość potrzebną, by zauważyć, co po kilku próbach stało się łatwiejsze.",
      language: .polish,
      length: .extended
    ),
    OfflineQuote(
      id: "traditional-tide",
      title: "潮線",
      text: "潮線退去後，沙上細小的紋路提醒人慢慢整理下一步。",
      language: .traditionalChinese,
      length: .short
    ),
    OfflineQuote(
      id: "traditional-table-light",
      title: "桌上的光",
      text: "桌上的光不會替人完成工作，卻能讓一張筆記和下一個小決定顯得更清楚。",
      language: .traditionalChinese,
      length: .medium
    ),
    OfflineQuote(
      id: "traditional-return-page",
      title: "回到頁面",
      text: "有些進步只在回頭時才看得見。每天留下一行清楚的記錄，調整一個小錯誤，久了以後，原本陌生的路也會有自己的節奏。",
      language: .traditionalChinese,
      length: .long
    ),
    OfflineQuote(
      id: "traditional-long-window",
      title: "長窗",
      text: "長窗旁的桌子不需要擺滿答案。它可以留給剛開始的草稿、仍在思考的句子，以及下一件願意完成的小事。練習也是如此：不必一次解開所有困難，只要替自己留下可以返回的位置，辨認眼前的一步，並在每次嘗試後看看什麼已經變得清楚。每一次返回，都讓原先陌生的難處更容易安放。",
      language: .traditionalChinese,
      length: .extended
    ),
    OfflineQuote(
      id: "russian-small-step",
      title: "Небольшой шаг",
      text: "Небольшой спокойный шаг помогает заметить работу, которая уже стала понятнее.",
      language: .russian,
      length: .short
    ),
    OfflineQuote(
      id: "russian-open-notebook",
      title: "Открытая тетрадь",
      text: "Открытая тетрадь не отвечает на трудный вопрос сама, но помогает разделить его на ясные части и вернуться к нему позже.",
      language: .russian,
      length: .medium
    ),
    OfflineQuote(
      id: "russian-quiet-workshop",
      title: "Тихая мастерская",
      text: "Прогресс не всегда приходит с заметным событием. Он собирается в повторяющихся действиях: открыть ту же страницу, уточнить одну фразу, исправить одну ошибку и оставить полезную отметку для следующего раза. Со временем эта спокойная внимательность делает трудные места знакомее.",
      language: .russian,
      length: .long
    ),
    OfflineQuote(
      id: "russian-long-table",
      title: "Длинный стол",
      text: "Длинный стол полезен тем, что на нём хватает места для разных этапов работы. С одного края может лежать первый набросок, с другого — фраза, которой ещё нужна забота, а в середине остаётся место для следующего маленького решения. Практика похожа на такой стол: она просит не решить всё сразу, а вернуться к заметному следующему шагу и увидеть, что после нескольких попыток стало легче.",
      language: .russian,
      length: .extended
    ),
    OfflineQuote(
      id: "ukrainian-small-note",
      title: "Мала нотатка",
      text: "Невеликий запис про зроблене допомагає побачити наступний крок ясніше.",
      language: .ukrainian,
      length: .short
    ),
    OfflineQuote(
      id: "ukrainian-one-fact",
      title: "Один факт",
      text: "Коли задача здається заплутаною, корисно виписати лише одну річ, яку вже відомо. Така коротка нотатка не розв’язує все, але дає опору для наступної дії.",
      language: .ukrainian,
      length: .medium
    ),
    OfflineQuote(
      id: "ukrainian-return",
      title: "Повернення",
      text: "Робота рухається не тільки в миті великого натхнення. Вона складається з простих повернень: перевірити число, уточнити речення, прибрати зайве слово й відкласти питання, на яке ще немає відповіді. Кожна така дія робить наступне повернення трохи легшим і залишає видимий слід для себе.",
      language: .ukrainian,
      length: .long
    ),
    OfflineQuote(
      id: "ukrainian-workshop",
      title: "Край столу",
      text: "У майстерні корисно мати вільний край столу. Туди можна покласти перший ескіз, список запитань і короткий запис про те, що вже перевірено. Коли увага розсіюється, цей край не вимагає швидкої відповіді: він нагадує про маленьку дію, яку можна завершити зараз. Так поступово з’являється порядок — не з ідеального плану, а з помітних кроків, до яких легко повернутися наступного дня.",
      language: .ukrainian,
      length: .extended
    ),
    OfflineQuote(
      id: "ukrainian-latin-small-note",
      title: "Mala notatka",
      text: "Mala notatka pro zroblene dopomahaie pobachyty nastupnyi krok yasnishe.",
      language: .ukrainianLatin,
      length: .short
    ),
    OfflineQuote(
      id: "ukrainian-latin-one-fact",
      title: "Odin fakt",
      text: "Koly zadacha zdaietsia zaplutanoiu, korysno vypysaty lyshe odnu rich, yaku vzhe vidomo. Taka korotka notatka ne rozviazuie vse, ale daie oporu dlia nastupnoi dii.",
      language: .ukrainianLatin,
      length: .medium
    ),
    OfflineQuote(
      id: "ukrainian-latin-return",
      title: "Povernennia",
      text: "Robota rukhaietsia ne tilky v myti velykoho natkhnennia. Vona skladaietsia z prostykh povernenn: pereviryty chyslo, utochnyty rechennia, prybraty zaive slovo i vidklasty pytannia, na yake shche nemaie vidpovidi. Kozhna taka diia robyt nastupne povernennia trokhy lehshym i zalyshaie pomitnyi slid dlia sebe.",
      language: .ukrainianLatin,
      length: .long
    ),
    OfflineQuote(
      id: "ukrainian-latin-workshop",
      title: "Krai stolu",
      text: "U maisterni korysno maty vilnyi krai stolu. Tudy mozhna poklasty pershyi eskiz, spysok zapytan i korotkyi zapys pro te, shcho vzhe perevireno. Koly uvaha rozsiiuietsia, tsei krai ne vymahaie shvydkoi vidpovidi: vin nahaduie pro malenku diiu, yaku mozhna zavershyty zaraz. Tak postupovo ziavliaietsia poriadok ne z idealnoho planu, a z pomitnykh krokiv, do yakykh lehko povertatysia nastupnoho dnia.",
      language: .ukrainianLatin,
      length: .extended
    ),
    OfflineQuote(
      id: "dutch-kleine-stap",
      title: "Kleine stap",
      text: "Een kleine, rustige stap maakt de volgende taak vaak beter zichtbaar.",
      language: .dutch,
      length: .short
    ),
    OfflineQuote(
      id: "dutch-open-notitieboek",
      title: "Open notitieboek",
      text: "Een open notitieboek lost moeilijke vragen niet vanzelf op, maar helpt om ze in heldere delen te verdelen en later met aandacht terug te keren.",
      language: .dutch,
      length: .medium
    ),
    OfflineQuote(
      id: "dutch-rustig-werk",
      title: "Rustig werk",
      text: "Vooruitgang komt niet altijd met een opvallend moment. Hij groeit in terugkerende handelingen: dezelfde pagina openen, één zin verduidelijken, een fout verbeteren en een bruikbare aanwijzing voor de volgende poging achterlaten. Na verloop van tijd maakt die rustige aandacht moeilijke stukken vertrouwder.",
      language: .dutch,
      length: .long
    ),
    OfflineQuote(
      id: "dutch-lange-tafel",
      title: "Lange tafel",
      text: "Een lange tafel is nuttig omdat er ruimte blijft voor verschillende soorten werk. Aan één kant kan een eerste schets liggen, aan de andere kant een zin die nog aandacht vraagt, en in het midden blijft plaats voor de volgende kleine beslissing. Oefenen werkt op dezelfde manier: het vraagt niet om elke moeilijkheid tegelijk op te lossen, maar om een plek om terug te keren, een zichtbare volgende stap en genoeg geduld om te merken wat na enkele pogingen gemakkelijker wordt.",
      language: .dutch,
      length: .extended
    ),
    OfflineQuote(
      id: "afrikaans-rustige-stap",
      title: "Rustige stap",
      text: "Elke rustige stap maak die volgende taak duideliker.",
      language: .afrikaans,
      length: .short
    ),
    OfflineQuote(
      id: "afrikaans-oop-notas",
      title: "Oop notas",
      text: "Oop notas los nie elke moeilike vraag op nie, maar help om die vraag in kleiner dele te verdeel.",
      language: .afrikaans,
      length: .medium
    ),
    OfflineQuote(
      id: "afrikaans-rustige-werk",
      title: "Rustige werk",
      text: "Vordering kom nie altyd met 'n groot oomblik nie. Dit groei uit klein handelinge: om dieselfde bladsy oop te maak, een sin duideliker te skryf, 'n fout reg te stel en 'n nuttige nota vir die volgende poging te laat.",
      language: .afrikaans,
      length: .long
    ),
    OfflineQuote(
      id: "afrikaans-lange-tafel",
      title: "Lang tafel",
      text: "'n Lang tafel gee ruimte vir verskillende soorte werk. Aan die een kant kan 'n eerste weergawe lê, aan die ander kant 'n sin wat nog aandag nodig het, en in die middel kan die volgende klein besluit wag. Oefening werk op dieselfde manier. Dit vra nie dat elke moeilike deel dadelik opgelos moet word nie, maar dat daar 'n plek is om na terug te keer, 'n sigbare volgende stap en genoeg geduld om te merk wat makliker word ná meer pogings.",
      language: .afrikaans,
      length: .extended
    ),
    OfflineQuote(
      id: "arabic-calm-step",
      title: "خطوة هادئة",
      text: "خطوة هادئة تجعل المهمة التالية أوضح.",
      language: .arabic,
      length: .short
    ),
    OfflineQuote(
      id: "arabic-open-notebook",
      title: "دفتر مفتوح",
      text: "لا يحل الدفتر المفتوح كل سؤال صعب، لكنه يساعد على تقسيم السؤال إلى أجزاء أصغر.",
      language: .arabic,
      length: .medium
    ),
    OfflineQuote(
      id: "arabic-small-work",
      title: "عمل صغير",
      text: "لا يأتي التقدم دائما في لحظة كبيرة. إنه ينمو من أعمال صغيرة: فتح الصفحة نفسها، وتوضيح جملة واحدة، وتصحيح خطأ، وترك ملاحظة نافعة للمحاولة التالية.",
      language: .arabic,
      length: .long
    ),
    OfflineQuote(
      id: "arabic-long-table",
      title: "طاولة طويلة",
      text: "تمنح الطاولة الطويلة مساحة لأنواع مختلفة من العمل. على أحد طرفيها مسودة أولى، وعلى الطرف الآخر جملة تحتاج إلى مزيد من الانتباه، وفي الوسط قرار صغير ينتظر. تعمل الممارسة بالطريقة نفسها: لا تطلب حل كل جزء صعب دفعة واحدة، بل توفر مكانا للعودة، وخطوة تالية واضحة، وصبرا كافيا لملاحظة ما يصبح أسهل بعد عدة محاولات.",
      language: .arabic,
      length: .extended
    ),
    OfflineQuote(
      id: "hebrew-calm-step",
      title: "צעד שקט",
      text: "צעד שקט מבהיר את המשימה הבאה.",
      language: .hebrew,
      length: .short
    ),
    OfflineQuote(
      id: "hebrew-open-notebook",
      title: "מחברת פתוחה",
      text: "מחברת פתוחה אינה פותרת כל שאלה קשה, אבל היא עוזרת לחלק את השאלה לחלקים קטנים יותר.",
      language: .hebrew,
      length: .medium
    ),
    OfflineQuote(
      id: "hebrew-small-work",
      title: "עבודה קטנה",
      text: "התקדמות לא תמיד מגיעה ברגע גדול. היא צומחת מעבודות קטנות: פתיחת אותו דף, הבהרת משפט אחד, תיקון טעות והשארת הערה מועילה לניסיון הבא.",
      language: .hebrew,
      length: .long
    ),
    OfflineQuote(
      id: "hebrew-long-table",
      title: "שולחן ארוך",
      text: "שולחן ארוך נותן מקום לסוגים שונים של עבודה. בקצה אחד יכולה להיות טיוטה ראשונה, ובקצה השני משפט שעדיין דורש תשומת לב, ובאמצע מחכה החלטה קטנה. כך פועל גם התרגול: אין צורך לפתור כל חלק קשה בבת אחת, אלא להשאיר מקום לחזור אליו, צעד הבא ברור וסבלנות שמאפשרת לראות מה נעשה קל יותר אחרי כמה ניסיונות.",
      language: .hebrew,
      length: .extended
    ),
    OfflineQuote(
      id: "persian-calm-step",
      title: "گام آرام",
      text: "یک گام آرام، کار بعدی را روشن‌تر می‌کند.",
      language: .persian,
      length: .short
    ),
    OfflineQuote(
      id: "persian-open-notebook",
      title: "دفتر باز",
      text: "دفتر باز همه پرسش‌های دشوار را حل نمی‌کند، اما کمک می‌کند پرسش را به بخش‌های کوچک‌تر تقسیم کنیم.",
      language: .persian,
      length: .medium
    ),
    OfflineQuote(
      id: "persian-small-work",
      title: "کار کوچک",
      text: "پیشرفت همیشه در یک لحظه بزرگ پدیدار نمی‌شود. از کارهای کوچک رشد می‌کند: باز کردن همان صفحه، روشن کردن یک جمله، اصلاح یک اشتباه و گذاشتن یادداشتی مفید برای تلاش بعدی.",
      language: .persian,
      length: .long
    ),
    OfflineQuote(
      id: "persian-long-table",
      title: "میز بلند",
      text: "یک میز بلند برای گونه‌های گوناگون کار جا باز می‌کند. در یک سوی آن شاید پیش نویس نخست باشد و در سوی دیگر جمله‌ای که هنوز به توجه نیاز دارد؛ در میان این دو، یک تصمیم کوچک منتظر می‌ماند. تمرین هم به همین شکل پیش می‌رود: لازم نیست هر بخش دشوار را یکباره حل کنیم. کافی است جایی برای بازگشت، گام بعدی روشن و صبری داشته باشیم تا پس از چند کوشش ببینیم چه چیز آسان‌تر شده است.",
      language: .persian,
      length: .extended
    ),
    OfflineQuote(
      id: "urdu-calm-step",
      title: "پرسکون قدم",
      text: "ایک پرسکون قدم اگلا کام واضح کر دیتا ہے۔",
      language: .urdu,
      length: .short
    ),
    OfflineQuote(
      id: "urdu-open-notebook",
      title: "کھلی نوٹ بک",
      text: "کھلی نوٹ بک ہر مشکل سوال حل نہیں کرتی، مگر سوال کو چھوٹے حصوں میں بانٹنے میں مدد دیتی ہے۔",
      language: .urdu,
      length: .medium
    ),
    OfflineQuote(
      id: "urdu-small-work",
      title: "چھوٹا کام",
      text: "پیش رفت ہمیشہ ایک بڑے لمحے میں نظر نہیں آتی۔ وہ چھوٹے کاموں سے بنتی ہے: وہی صفحہ کھولنا، ایک جملہ واضح کرنا، ایک غلطی درست کرنا اور اگلی کوشش کے لیے مفید نوٹ رکھ دینا۔",
      language: .urdu,
      length: .long
    ),
    OfflineQuote(
      id: "urdu-long-table",
      title: "لمبی میز",
      text: "ایک لمبی میز مختلف کاموں کے لیے جگہ بناتی ہے۔ اس کے ایک سرے پر پہلا مسودہ ہو سکتا ہے اور دوسرے سرے پر وہ جملہ جسے ابھی توجہ چاہیے؛ ان دونوں کے درمیان ایک چھوٹا فیصلہ منتظر رہتا ہے۔ مشق بھی اسی طرح آگے بڑھتی ہے: ہمیں ہر مشکل حصے کو ایک ہی بار میں حل کرنے کی ضرورت نہیں۔ بس واپس آنے کی جگہ، اگلا واضح قدم اور اتنا صبر چاہیے کہ چند کوششوں کے بعد نظر آ سکے کہ کیا آسان ہو گیا ہے۔",
      language: .urdu,
      length: .extended
    ),
    OfflineQuote(
      id: "tamil-calm-step",
      title: "அமைதியான அடி",
      text: "ஒரு அமைதியான அடி அடுத்த வேலையைத் தெளிவாக்கும்.",
      language: .tamil,
      length: .short
    ),
    OfflineQuote(
      id: "tamil-open-notebook",
      title: "திறந்த குறிப்பேடு",
      text: "திறந்த குறிப்பேடு ஒவ்வொரு கடினமான கேள்விக்கும் பதில் தராது, ஆனால் கேள்வியைச் சிறிய பகுதிகளாகப் பிரிக்க உதவும்.",
      language: .tamil,
      length: .medium
    ),
    OfflineQuote(
      id: "tamil-small-work",
      title: "சிறிய வேலை",
      text: "முன்னேற்றம் எப்போதும் ஒரு பெரிய தருணத்தில் தெரியாது. அதே பக்கத்தைத் திறப்பது, ஒரு வாக்கியத்தைத் தெளிவாக்குவது, ஒரு தவறைச் சரிசெய்வது, அடுத்த முயற்சிக்கான பயனுள்ள குறிப்பை வைப்பது போன்ற சிறிய வேலைகளில் அது வளரும்.",
      language: .tamil,
      length: .long
    ),
    OfflineQuote(
      id: "tamil-long-table",
      title: "நீண்ட மேசை",
      text: "நீண்ட மேசை பலவகை வேலைகளுக்கு இடம் தருகிறது. அதன் ஒரு முனையில் முதல் வரைவு இருக்கலாம்; மற்றொரு முனையில் இன்னும் கவனம் தேவைப்படும் வாக்கியம் இருக்கலாம்; இவ்விரண்டுக்கும் நடுவில் ஒரு சிறிய முடிவு காத்திருக்கும். பயிற்சியும் இதேபோல் நகர்கிறது: கடினமான ஒவ்வொரு பகுதியையும் ஒரே முறையில் தீர்க்க வேண்டியதில்லை. திரும்பி வர இடம், தெளிவான அடுத்த அடி, சில முயற்சிகளுக்குப் பிறகு எது எளிதானது என்று காணும் பொறுமை இருந்தால் போதும்.",
      language: .tamil,
      length: .extended
    ),
    OfflineQuote(
      id: "hindi-calm-step",
      title: "शांत कदम",
      text: "एक शांत कदम अगले काम को स्पष्ट बनाता है।",
      language: .hindi,
      length: .short
    ),
    OfflineQuote(
      id: "hindi-open-notebook",
      title: "खुली नोटबुक",
      text: "खुली नोटबुक हर कठिन प्रश्न का उत्तर नहीं देती, लेकिन प्रश्न को छोटे भागों में बाँटने में मदद करती है।",
      language: .hindi,
      length: .medium
    ),
    OfflineQuote(
      id: "hindi-small-work",
      title: "छोटा काम",
      text: "प्रगति हमेशा किसी बड़े क्षण में दिखाई नहीं देती। वह छोटे कामों से बनती है: उसी पन्ने को खोलना, एक वाक्य को स्पष्ट करना, एक गलती को सुधारना और अगले प्रयास के लिए उपयोगी टिप्पणी छोड़ना।",
      language: .hindi,
      length: .long
    ),
    OfflineQuote(
      id: "hindi-long-table",
      title: "लंबी मेज़",
      text: "लंबी मेज़ अलग-अलग कामों के लिए जगह बनाती है। उसके एक सिरे पर पहला मसौदा हो सकता है और दूसरे सिरे पर वह वाक्य जिसे अभी ध्यान चाहिए; इन दोनों के बीच एक छोटा निर्णय प्रतीक्षा करता है। अभ्यास भी इसी तरह आगे बढ़ता है: हर कठिन हिस्से को एक ही बार में हल करना आवश्यक नहीं है। वापस आने की जगह, अगला स्पष्ट कदम और इतना धैर्य पर्याप्त है कि कुछ प्रयासों के बाद दिख सके कि क्या आसान हो गया है।",
      language: .hindi,
      length: .extended
    ),
    OfflineQuote(
      id: "gujarati-steady-pause",
      title: "ધીમો વિરામ",
      text: "ધીમો વિરામ આગળનું વાક્ય વધુ સ્પષ્ટ બનાવે છે.",
      language: .gujarati,
      length: .short
    ),
    OfflineQuote(
      id: "gujarati-open-notebook",
      title: "ખુલેલી નોંધપોથી",
      text: "ખુલેલી નોંધપોથી દરેક જવાબ તરત આપતી નથી, પરંતુ પ્રશ્નને નાના ભાગોમાં જોવાની જગ્યા આપે છે.",
      language: .gujarati,
      length: .medium
    ),
    OfflineQuote(
      id: "gujarati-small-work",
      title: "નાનું કામ",
      text: "પ્રગતિ હંમેશા મોટા ક્ષણમાં દેખાતી નથી. એ જ પાનું ફરી ખોલવું, એક વાક્યને સાફ કરવું, નાની ભૂલ સુધારવી અને આગળના પ્રયત્ન માટે ટૂંકી નોંધ મૂકવી — આ કામોથી વિશ્વાસ ધીમે ધીમે બને છે.",
      language: .gujarati,
      length: .long
    ),
    OfflineQuote(
      id: "gujarati-long-table",
      title: "લાંબી મેજ",
      text: "લાંબી મેજ પર અનેક અધૂરાં વિચારોને પણ જગ્યા મળે છે. એક છેડે પ્રથમ ખાકો હોય છે, બીજા છેડે હજુ ધ્યાન માંગતું વાક્ય, અને વચ્ચે પસંદગીની રાહ જોતો નાનો પ્રશ્ન. અભ્યાસ પણ આવો જ છે: દરેક મુશ્કેલ ભાગને એક જ પ્રયત્નમાં પૂરો કરવો જરૂરી નથી. પાછા ફરવાની જગ્યા, આગળનું સ્પષ્ટ પગલું અને થોડા પ્રયાસો પછી શું સરળ બન્યું તે જોવાની ધીરજ હોય, તો ગતિ સ્વાભાવિક રીતે વધે છે.",
      language: .gujarati,
      length: .extended
    ),
    OfflineQuote(
      id: "bangla-small-pause",
      title: "ছোট বিরতি",
      text: "ছোট বিরতি পরের বাক্যকে আরও পরিষ্কার করে।",
      language: .bangla,
      length: .short
    ),
    OfflineQuote(
      id: "bangla-open-notebook",
      title: "খোলা খাতা",
      text: "খোলা খাতায় সব উত্তর একসঙ্গে লেখা থাকে না, তবু প্রশ্নকে ছোট অংশে দেখার জায়গা তৈরি হয়।",
      language: .bangla,
      length: .medium
    ),
    OfflineQuote(
      id: "bangla-small-work",
      title: "নিয়মিত কাজ",
      text: "অগ্রগতি সব সময় বড় মুহূর্তে দেখা যায় না। একই পাতায় ফিরে আসা, একটি বাক্য সহজ করা, ছোট ভুল ঠিক করা এবং পরের চেষ্টার জন্য একটি নোট রাখা—এই কাজগুলোতেই ভরসা ধীরে ধীরে তৈরি হয়।",
      language: .bangla,
      length: .long
    ),
    OfflineQuote(
      id: "bangla-long-table",
      title: "লম্বা টেবিল",
      text: "লম্বা টেবিলে অসমাপ্ত ভাবনারও জায়গা থাকে। এক প্রান্তে প্রথম খসড়া, অন্য প্রান্তে আরও মনোযোগ চাওয়া একটি বাক্য, আর মাঝখানে অপেক্ষায় থাকা ছোট সিদ্ধান্ত। অনুশীলনও এমনই এগোয়: প্রতিটি কঠিন অংশ একবারেই শেষ করতে হয় না। ফিরে আসার সুযোগ, পরের স্পষ্ট পদক্ষেপ এবং কয়েকটি চেষ্টার পরে কোন কাজ সহজ হলো তা দেখার ধৈর্য থাকলে গতি আপনিই বাড়ে।",
      language: .bangla,
      length: .extended
    ),
    OfflineQuote(
      id: "thai-small-pause",
      title: "ช่วงพักสั้น",
      text: "การหยุดสั้น ๆ ทำให้ประโยคถัดไปชัดเจนขึ้น",
      language: .thai,
      length: .short
    ),
    OfflineQuote(
      id: "thai-open-notebook",
      title: "สมุดที่เปิดอยู่",
      text: "สมุดที่เปิดอยู่ไม่ได้มีคำตอบทุกข้อทันที แต่ช่วยให้เราเห็นคำถามเป็นส่วนเล็ก ๆ ได้",
      language: .thai,
      length: .medium
    ),
    OfflineQuote(
      id: "thai-steady-work",
      title: "งานที่สม่ำเสมอ",
      text: "ความก้าวหน้าไม่ได้ปรากฏในช่วงเวลาที่ยิ่งใหญ่เสมอไป การกลับมาเปิดหน้าเดิม ปรับประโยคให้เรียบง่าย แก้ข้อผิดพลาดเล็กน้อย และเขียนโน้ตสำหรับครั้งต่อไป ล้วนสร้างความมั่นใจทีละนิด",
      language: .thai,
      length: .long
    ),
    OfflineQuote(
      id: "thai-long-table",
      title: "โต๊ะยาว",
      text: "โต๊ะยาวมีที่ว่างสำหรับความคิดที่ยังไม่เสร็จ ด้านหนึ่งอาจมีร่างแรก อีกด้านมีประโยคที่ต้องใส่ใจ และตรงกลางมีการตัดสินใจเล็ก ๆ รออยู่ การฝึกก็เดินหน้าเช่นนี้ เราไม่จำเป็นต้องแก้ทุกส่วนยากให้ได้ในครั้งเดียว หากมีที่ให้กลับมา มีขั้นตอนถัดไปที่ชัดเจน และมีความอดทนพอจะเห็นว่าสิ่งใดง่ายขึ้นหลังจากลองหลายครั้ง ความเร็วจะค่อย ๆ ตามมาเอง",
      language: .thai,
      length: .extended
    ),
    OfflineQuote(
      id: "nepali-calm-step",
      title: "शान्त कदम",
      text: "शान्त कदमले अर्को कामलाई स्पष्ट बनाउँछ।",
      language: .nepali,
      length: .short
    ),
    OfflineQuote(
      id: "nepali-open-notebook",
      title: "खुला कापी",
      text: "खुला कापीले सबै कठिन प्रश्नको उत्तर दिँदैन, तर प्रश्नलाई साना भागमा हेर्ने ठाउँ दिन्छ।",
      language: .nepali,
      length: .medium
    ),
    OfflineQuote(
      id: "nepali-small-work",
      title: "सानो काम",
      text: "प्रगति सधैँ ठूलो क्षणमा देखिँदैन। उही पाना फेरि खोल्नु, एउटा वाक्य स्पष्ट बनाउनु, सानो गल्ती सच्याउनु र अर्को प्रयासका लागि उपयोगी टिपोट राख्नु जस्ता कामले भरोसा बिस्तारै बनाउँछन्।",
      language: .nepali,
      length: .long
    ),
    OfflineQuote(
      id: "nepali-long-table",
      title: "लामो टेबल",
      text: "लामो टेबलमा अधुरा विचारका लागि पनि ठाउँ हुन्छ। एक छेउमा पहिलो मस्यौदा हुन सक्छ, अर्को छेउमा अझ ध्यान चाहिने वाक्य, र बीचमा सानो निर्णय पर्खिरहेको हुन्छ। अभ्यास पनि यस्तै अगाडि बढ्छ: हरेक कठिन भागलाई एउटै प्रयासमा समाधान गर्न आवश्यक छैन। फर्केर आउने ठाउँ, अर्को स्पष्ट कदम र केही प्रयासपछि के सजिलो भयो भनेर हेर्ने धैर्य भए गति आफैँ बढ्छ।",
      language: .nepali,
      length: .extended
    ),
    OfflineQuote(
      id: "kannada-calm-step",
      title: "ಶಾಂತ ಹೆಜ್ಜೆ",
      text: "ಶಾಂತ ಹೆಜ್ಜೆ ಮುಂದಿನ ಕೆಲಸವನ್ನು ಸ್ಪಷ್ಟಗೊಳಿಸುತ್ತದೆ.",
      language: .kannada,
      length: .short
    ),
    OfflineQuote(
      id: "kannada-open-notebook",
      title: "ತೆರೆದ ಟಿಪ್ಪಣಿಪುಸ್ತಕ",
      text: "ತೆರೆದ ಟಿಪ್ಪಣಿಪುಸ್ತಕ ಪ್ರತಿಯೊಂದು ಕಠಿಣ ಪ್ರಶ್ನೆಗೆ ಉತ್ತರ ಕೊಡುವುದಿಲ್ಲ, ಆದರೆ ಪ್ರಶ್ನೆಯನ್ನು ಸಣ್ಣ ಭಾಗಗಳಾಗಿ ನೋಡುವ ಜಾಗವನ್ನು ಕೊಡುತ್ತದೆ.",
      language: .kannada,
      length: .medium
    ),
    OfflineQuote(
      id: "kannada-small-work",
      title: "ಸಣ್ಣ ಕೆಲಸ",
      text: "ಪ್ರಗತಿ ಯಾವಾಗಲೂ ದೊಡ್ಡ ಕ್ಷಣದಲ್ಲಿ ಕಾಣಿಸುವುದಿಲ್ಲ. ಅದೇ ಪುಟವನ್ನು ಮತ್ತೆ ತೆರೆಯುವುದು, ಒಂದು ವಾಕ್ಯವನ್ನು ಸರಳಗೊಳಿಸುವುದು, ಸಣ್ಣ ತಪ್ಪನ್ನು ಸರಿಪಡಿಸುವುದು ಮತ್ತು ಮುಂದಿನ ಪ್ರಯತ್ನಕ್ಕೆ ಉಪಯುಕ್ತ ಟಿಪ್ಪಣಿ ಬರೆಯುವುದು ನಿಧಾನವಾಗಿ ವಿಶ್ವಾಸವನ್ನು ಕಟ್ಟುತ್ತದೆ.",
      language: .kannada,
      length: .long
    ),
    OfflineQuote(
      id: "kannada-long-table",
      title: "ಉದ್ದನೆಯ ಮೇಜು",
      text: "ಉದ್ದನೆಯ ಮೇಜು ಅಪೂರ್ಣ ಆಲೋಚನೆಗಳಿಗೂ ಜಾಗ ಕೊಡುತ್ತದೆ. ಒಂದು ಬದಿಯಲ್ಲಿ ಮೊದಲ ಕರಡು ಇರಬಹುದು, ಇನ್ನೊಂದು ಬದಿಯಲ್ಲಿ ಇನ್ನಷ್ಟು ಗಮನ ಬೇಕಾದ ವಾಕ್ಯ ಇರಬಹುದು, ಮಧ್ಯದಲ್ಲಿ ಸಣ್ಣ ನಿರ್ಧಾರ ಕಾಯುತ್ತಿರಬಹುದು. ಅಭ್ಯಾಸವೂ ಹೀಗೆ ಮುಂದೆ ಸಾಗುತ್ತದೆ: ಪ್ರತಿಯೊಂದು ಕಠಿಣ ಭಾಗವನ್ನು ಒಂದೇ ಪ್ರಯತ್ನದಲ್ಲಿ ಸರಿಪಡಿಸುವ ಅಗತ್ಯವಿಲ್ಲ. ಮರಳಿ ಬರುವ ಜಾಗ, ಮುಂದಿನ ಸ್ಪಷ್ಟ ಹೆಜ್ಜೆ ಮತ್ತು ಹಲವು ಪ್ರಯತ್ನಗಳ ನಂತರ ಯಾವುದು ಸುಲಭವಾಯಿತು ಎಂದು ನೋಡುವ ತಾಳ್ಮೆ ಇದ್ದರೆ ವೇಗವು ತಾನೇ ಬೆಳೆಯುತ್ತದೆ.",
      language: .kannada,
      length: .extended
    ),
    OfflineQuote(
      id: "telugu-calm-step",
      title: "నిశ్శబ్ద అడుగు",
      text: "నిశ్శబ్ద అడుగు తదుపరి పనిని స్పష్టంగా చేస్తుంది.",
      language: .telugu,
      length: .short
    ),
    OfflineQuote(
      id: "telugu-open-notebook",
      title: "తెరిచిన నోటుపుస్తకం",
      text: "తెరిచిన నోటుపుస్తకం ప్రతి కఠినమైన ప్రశ్నకు జవాబు ఇవ్వదు, కానీ ప్రశ్నను చిన్న భాగాలుగా చూడడానికి చోటు ఇస్తుంది.",
      language: .telugu,
      length: .medium
    ),
    OfflineQuote(
      id: "telugu-small-work",
      title: "చిన్న పని",
      text: "పురోగతి ఎప్పుడూ పెద్ద క్షణంలో కనిపించదు. అదే పేజీని మళ్లీ తెరవడం, ఒక వాక్యాన్ని సులభంగా మార్చడం, చిన్న తప్పును సరిచేయడం, తరువాతి ప్రయత్నం కోసం ఉపయోగకరమైన గమనిక రాయడం నెమ్మదిగా నమ్మకాన్ని పెంచుతుంది.",
      language: .telugu,
      length: .long
    ),
    OfflineQuote(
      id: "telugu-long-table",
      title: "పొడవైన బల్ల",
      text: "పొడవైన బల్లపై పూర్తికాని ఆలోచనలకూ చోటు ఉంటుంది. ఒక వైపున మొదటి ముసాయిదా ఉండవచ్చు, మరొక వైపున మరింత శ్రద్ధ కావాల్సిన వాక్యం ఉండవచ్చు, మధ్యలో చిన్న నిర్ణయం ఎదురుచూస్తూ ఉండవచ్చు. అభ్యాసం కూడా ఇలానే ముందుకు సాగుతుంది: ప్రతి కఠిన భాగాన్ని ఒకే ప్రయత్నంలో సరిచేయాల్సిన అవసరం లేదు. తిరిగి వచ్చే చోటు, తరువాతి స్పష్టమైన అడుగు, కొన్ని ప్రయత్నాల తరువాత ఏది సులభమైందో చూడగల సహనం ఉంటే వేగం తనంతట తానే పెరుగుతుంది.",
      language: .telugu,
      length: .extended
    ),
    OfflineQuote(
      id: "malayalam-calm-step",
      title: "ശാന്തമായ ചുവട്",
      text: "ശാന്തമായ ചുവട് അടുത്ത ജോലിയെ കൂടുതൽ വ്യക്തമാക്കുന്നു.",
      language: .malayalam,
      length: .short
    ),
    OfflineQuote(
      id: "malayalam-open-notebook",
      title: "തുറന്ന കുറിപ്പുപുസ്തകം",
      text: "തുറന്ന കുറിപ്പുപുസ്തകം എല്ലാ കഠിന ചോദ്യങ്ങൾക്കും മറുപടി നൽകില്ല, പക്ഷേ ചോദ്യത്തെ ചെറിയ ഭാഗങ്ങളായി കാണാൻ ഇടം നൽകും.",
      language: .malayalam,
      length: .medium
    ),
    OfflineQuote(
      id: "malayalam-small-work",
      title: "ചെറിയ ജോലി",
      text: "പുരോഗതി എല്ലായ്പ്പോഴും വലിയ നിമിഷത്തിൽ കാണപ്പെടില്ല. അതേ പേജ് വീണ്ടും തുറക്കുക, ഒരു വാക്യം ലളിതമാക്കുക, ചെറിയ പിശക് തിരുത്തുക, അടുത്ത ശ്രമത്തിനായി ഉപകാരപ്രദമായ കുറിപ്പ് എഴുതുക എന്നിവ വിശ്വാസം പതുക്കെ വളർത്തുന്നു.",
      language: .malayalam,
      length: .long
    ),
    OfflineQuote(
      id: "malayalam-long-table",
      title: "നീളമുള്ള മേശ",
      text: "നീളമുള്ള മേശയിൽ പൂർത്തിയാകാത്ത ചിന്തകൾക്കും ഇടമുണ്ട്. ഒരു വശത്ത് ആദ്യ കരട് ഉണ്ടാകാം, മറുവശത്ത് കൂടുതൽ ശ്രദ്ധ വേണമെന്ന വാക്യം ഉണ്ടാകാം, നടുവിൽ ചെറിയ തീരുമാനം കാത്തിരിക്കാം. അഭ്യാസവും ഇങ്ങനെയാണ് മുന്നോട്ട് പോകുന്നത്: ഓരോ കഠിന ഭാഗവും ഒരൊറ്റ ശ്രമത്തിൽ പരിഹരിക്കേണ്ടതില്ല. തിരിച്ചുവരാൻ ഒരു സ്ഥലം, അടുത്ത വ്യക്തമായ ചുവട്, പല ശ്രമങ്ങൾക്കുശേഷം എന്താണ് എളുപ്പമായത് എന്ന് കാണാനുള്ള ക്ഷമ എന്നിവ ഉണ്ടെങ്കിൽ വേഗം സ്വയം വളരും.",
      language: .malayalam,
      length: .extended
    ),
    OfflineQuote(
      id: "sanskrit-calm-step",
      title: "शान्तं पदम्",
      text: "शान्तं पदम् अग्रिमं कार्यं स्पष्टं करोति।",
      language: .sanskrit,
      length: .short
    ),
    OfflineQuote(
      id: "sanskrit-open-notebook",
      title: "उद्घाटितं पुस्तकम्",
      text: "उद्घाटितं लेखनपुस्तकम् सर्वेषां कठिनप्रश्नानाम् उत्तरं न ददाति, किन्तु प्रश्नं लघुभागेषु द्रष्टुं स्थानं ददाति।",
      language: .sanskrit,
      length: .medium
    ),
    OfflineQuote(
      id: "sanskrit-small-work",
      title: "लघु कार्यम्",
      text: "प्रगतिः सर्वदा महति क्षणे न दृश्यते। पुनः तत् पत्रं उद्घाटयितुम्, एकं वाक्यं सरलम् कर्तुम्, लघुदोषं शोधयितुम्, पुनः प्रयासाय उपयोगिनीं टिप्पणीं लिखितुम् च धैर्येण विश्वासः वर्धते।",
      language: .sanskrit,
      length: .long
    ),
    OfflineQuote(
      id: "sanskrit-long-table",
      title: "दीर्घम् आसनम्",
      text: "दीर्घे पीठे अपूर्णविचारेभ्यः अपि स्थानम् अस्ति। एकस्मिन् पार्श्वे प्रथमः आलेखः भवेत्, अन्यस्मिन् अधिकं ध्यानं याचमानं वाक्यम्, मध्ये च लघु निर्णयः प्रतीक्षते। अभ्यासः अपि एवं प्रवर्तते: प्रत्येकं कठिनभागं एकेनैव प्रयत्नेन समाधातुं न आवश्यकम्। पुनरागमनाय स्थानम्, अग्रिमं स्पष्टं पदम्, बहुषु प्रयत्नेषु किं सुकरम् अभवत् इति द्रष्टुं धैर्यं च यदि स्यात्, तर्हि वेगः स्वयमेव वर्धते।",
      language: .sanskrit,
      length: .extended
    ),
    OfflineQuote(
      id: "sinhala-calm-step",
      title: "සන්සුන් පියවර",
      text: "සන්සුන් පියවරක් ඊළඟ කාර්යය පැහැදිලි කරයි.",
      language: .sinhala,
      length: .short
    ),
    OfflineQuote(
      id: "sinhala-open-notebook",
      title: "විවෘත සටහන් පොත",
      text: "විවෘත සටහන් පොතක් සෑම දුෂ්කර ප්‍රශ්නයකටම පිළිතුරක් නොදෙයි, නමුත් එය ප්‍රශ්නය කුඩා කොටස්වලින් දැකීමට ඉඩ දෙයි.",
      language: .sinhala,
      length: .medium
    ),
    OfflineQuote(
      id: "sinhala-small-work",
      title: "කුඩා කාර්යය",
      text: "දියුණුව සෑම විටම විශාල මොහොතක් ලෙස නොපෙනේ. එකම පිටුව නැවත විවෘත කිරීම, එක් වාක්‍යයක් පැහැදිලි කිරීම, කුඩා දෝෂයක් නිවැරදි කිරීම සහ ඊළඟ උත්සාහයට ප්‍රයෝජනවත් සටහනක් තැබීම විශ්වාසය වැඩි කරයි.",
      language: .sinhala,
      length: .long
    ),
    OfflineQuote(
      id: "sinhala-long-table",
      title: "දිගු මේසය",
      text: "දිගු මේසයක නිම නොවූ අදහස් සඳහාත් ඉඩ තිබේ. එක් අන්තයක පළමු කෙටුම්පත තැබිය හැක, අනෙක් අන්තයේ වැඩි අවධානයක් අවශ්‍ය වාක්‍යයක් රැඳිය හැක, මැදින් ඊළඟ කුඩා තීරණය බලා සිටිය හැක. පුහුණුවද එලෙසම ඉදිරියට යයි. සෑම දුෂ්කර කොටසක්ම එකම උත්සාහයෙන් විසඳිය යුතු නැත. ආපසු එන්නට තැනක්, පැහැදිලි ඊළඟ පියවරක් සහ උත්සාහ කිහිපයකින් පසු පහසු වූ දේ දැකීමට ඉවසීමක් තිබේ නම් වේගය ස්වභාවිකව වැඩෙයි.",
      language: .sinhala,
      length: .extended
    ),
    OfflineQuote(
      id: "khmer-calm-step",
      title: "ជំហានស្ងប់ស្ងាត់",
      text: "ជំហានស្ងប់ស្ងាត់មួយធ្វើឱ្យការងារបន្ទាប់កាន់តែច្បាស់។",
      language: .khmer,
      length: .short
    ),
    OfflineQuote(
      id: "khmer-open-notebook",
      title: "សៀវភៅកំណត់ត្រាបើកចំហ",
      text: "សៀវភៅកំណត់ត្រាបើកចំហមិនឆ្លើយគ្រប់សំណួរលំបាកទេ ប៉ុន្តែវាផ្តល់កន្លែងសម្រាប់មើលសំណួរជាផ្នែកតូចៗ។",
      language: .khmer,
      length: .medium
    ),
    OfflineQuote(
      id: "khmer-small-work",
      title: "ការងារតូច",
      text: "វឌ្ឍនភាពមិនតែងតែបង្ហាញខ្លួនជាពេលវេលាធំទេ។ ការបើកទំព័រដដែលម្ដងទៀត ការធ្វើឱ្យប្រយោគមួយច្បាស់ និងការកែបញ្ហាតូចមួយ បង្កើតទំនុកចិត្តសម្រាប់ការព្យាយាមបន្ទាប់។",
      language: .khmer,
      length: .long
    ),
    OfflineQuote(
      id: "khmer-long-table",
      title: "តុវែង",
      text: "តុវែងមួយផ្តល់កន្លែងសម្រាប់ការងារជាច្រើនប្រភេទ។ នៅចុងមួយអាចដាក់សេចក្តីព្រាងដំបូង នៅចុងម្ខាងទៀតអាចទុកប្រយោគដែលត្រូវការការយកចិត្តទុកដាក់ ហើយនៅកណ្តាលអាចរង់ចាំការសម្រេចចិត្តតូចបន្ទាប់។ ការអនុវត្តក៏ដំណើរការដូចគ្នា។ វាមិនទាមទារឱ្យដោះស្រាយគ្រប់ផ្នែកលំបាកភ្លាមៗទេ ប៉ុន្តែត្រូវមានកន្លែងសម្រាប់ត្រឡប់មកវិញ ជំហានបន្ទាប់ដែលច្បាស់ និងការអត់ធ្មត់ដើម្បីសង្កេតថាអ្វីកាន់តែងាយស្រួលបន្ទាប់ពីការព្យាយាមជាច្រើន។",
      language: .khmer,
      length: .extended
    ),
    OfflineQuote(
      id: "myanmar-calm-step",
      title: "ငြိမ်သက်သော ခြေလှမ်း",
      text: "ငြိမ်သက်သော ခြေလှမ်းတစ်ခုက နောက်အလုပ်ကို ပိုမိုရှင်းလင်းစေသည်။",
      language: .myanmarBurmese,
      length: .short
    ),
    OfflineQuote(
      id: "myanmar-open-notebook",
      title: "ဖွင့်ထားသော မှတ်စုစာအုပ်",
      text: "ဖွင့်ထားသော မှတ်စုစာအုပ်သည် ခက်ခဲသော မေးခွန်းတိုင်းကို မဖြေပေးနိုင်သော်လည်း မေးခွန်းကို အပိုင်းငယ်များဖြင့် မြင်နိုင်ရန် နေရာပေးသည်။",
      language: .myanmarBurmese,
      length: .medium
    ),
    OfflineQuote(
      id: "myanmar-small-work",
      title: "သေးငယ်သော အလုပ်",
      text: "တိုးတက်မှုသည် အမြဲတမ်း ကြီးမားသော အချိန်အခါအဖြစ် မပေါ်လာပါ။ တစ်မျက်နှာတည်းကို ပြန်ဖွင့်ခြင်း၊ စာကြောင်းတစ်ခုကို ရှင်းလင်းခြင်းနှင့် အမှားသေးသေးတစ်ခုကို ပြင်ဆင်ခြင်းတို့က နောက်ကြိုးစားမှုအတွက် ယုံကြည်မှုကို တည်ဆောက်ပေးသည်။",
      language: .myanmarBurmese,
      length: .long
    ),
    OfflineQuote(
      id: "myanmar-long-table",
      title: "ရှည်လျားသော စားပွဲ",
      text: "ရှည်လျားသော စားပွဲတစ်လုံးသည် အလုပ်အမျိုးမျိုးအတွက် နေရာပေးနိုင်သည်။ တစ်ဖက်တွင် ပထမမူကြမ်းကို ထားနိုင်ပြီး အခြားဖက်တွင် ပိုမိုဂရုစိုက်ရန်လိုသော စာကြောင်းတစ်ခုကို ထားနိုင်သည်။ အလယ်တွင် နောက်ဆုံးဖြတ်ချက်သေးသေးတစ်ခု စောင့်နေနိုင်သည်။ လေ့ကျင့်မှုလည်း ထိုသို့ပင် လုပ်ဆောင်သည်။ ခက်ခဲသော အပိုင်းတိုင်းကို တစ်ကြိမ်တည်းဖြင့် ဖြေရှင်းရန် မလိုအပ်ပါ။ ပြန်လာနိုင်သော နေရာတစ်ခု၊ ရှင်းလင်းသော နောက်ခြေလှမ်းတစ်ခုနှင့် အကြိမ်များစွာ ကြိုးစားပြီးနောက် ဘာက ပိုလွယ်လာသည်ကို သတိပြုရန် စိတ်ရှည်မှုရှိလျှင် အရှိန်သည် သဘာဝအလျောက် တိုးလာသည်။",
      language: .myanmarBurmese,
      length: .extended
    ),
    OfflineQuote(
      id: "lao-calm-step",
      title: "ບາດກ້າວທີ່ສະຫງົບ",
      text: "ບາດກ້າວທີ່ສະຫງົບເຮັດໃຫ້ວຽກຕໍ່ໄປຊັດເຈນຂຶ້ນ.",
      language: .lao,
      length: .short
    ),
    OfflineQuote(
      id: "lao-open-notebook",
      title: "ປຶ້ມບັນທຶກທີ່ເປີດຢູ່",
      text: "ປຶ້ມບັນທຶກທີ່ເປີດຢູ່ບໍ່ໄດ້ຕອບທຸກຄໍາຖາມທີ່ຍາກ ແຕ່ມັນໃຫ້ບ່ອນສໍາລັບເບິ່ງຄໍາຖາມເປັນສ່ວນນ້ອຍໆ.",
      language: .lao,
      length: .medium
    ),
    OfflineQuote(
      id: "lao-small-work",
      title: "ວຽກນ້ອຍ",
      text: "ຄວາມກ້າວໜ້າບໍ່ໄດ້ປະກົດເປັນຊ່ວງເວລາໃຫຍ່ສະເໝີ. ການເປີດໜ້າເກົ່າອີກຄັ້ງ ການເຮັດໃຫ້ປະໂຫຍກໜຶ່ງຊັດເຈນ ແລະ ການແກ້ໄຂບັນຫານ້ອຍໜຶ່ງ ສ້າງຄວາມໝັ້ນໃຈສໍາລັບຄວາມພະຍາຍາມຄັ້ງຕໍ່ໄປ.",
      language: .lao,
      length: .long
    ),
    OfflineQuote(
      id: "lao-long-table",
      title: "ໂຕະຍາວ",
      text: "ໂຕະຍາວໜຶ່ງໃຫ້ບ່ອນສໍາລັບວຽກຫຼາຍປະເພດ. ຢູ່ປາຍໜຶ່ງສາມາດວາງຮ່າງທໍາອິດ ອີກປາຍໜຶ່ງສາມາດເກັບປະໂຫຍກທີ່ຕ້ອງການຄວາມໃສ່ໃຈ ແລະ ກາງໂຕະສາມາດລໍຖ້າການຕັດສິນໃຈນ້ອຍຕໍ່ໄປ. ການຝຶກຝົນກໍເດີນໜ້າແບບດຽວກັນ. ບໍ່ຈໍາເປັນຕ້ອງແກ້ໄຂທຸກສ່ວນທີ່ຍາກໃນຄັ້ງດຽວ. ເມື່ອມີບ່ອນໃຫ້ກັບມາ ມີບາດກ້າວຕໍ່ໄປທີ່ຊັດເຈນ ແລະ ມີຄວາມອົດທົນເພື່ອເຫັນສິ່ງທີ່ງ່າຍຂຶ້ນຫຼັງຈາກລອງຫຼາຍຄັ້ງ ຈັງຫວະຈະຄ່ອຍໆເຕີບໂຕ.",
      language: .lao,
      length: .extended
    ),
    OfflineQuote(
      id: "amharic-calm-step",
      title: "የተረጋጋ እርምጃ",
      text: "የተረጋጋ እርምጃ ቀጣዩን ሥራ ይበልጥ ግልጽ ያደርገዋል።",
      language: .amharic,
      length: .short
    ),
    OfflineQuote(
      id: "amharic-open-notebook",
      title: "ክፍት ማስታወሻ",
      text: "ክፍት ማስታወሻ ደብተር እያንዳንዱን አስቸጋሪ ጥያቄ አይመልስም፤ ጥያቄውን በትናንሽ ክፍሎች ለማየት ግን ቦታ ይሰጣል።",
      language: .amharic,
      length: .medium
    ),
    OfflineQuote(
      id: "amharic-small-work",
      title: "ትንሽ ሥራ",
      text: "እድገት ሁልጊዜ እንደ ትልቅ ጊዜ አይታይም። አንድን ገጽ እንደገና መክፈት፣ አንድን አረፍተ ነገር ግልጽ ማድረግ እና ትንሽ ችግር መጠገን ለቀጣዩ ሙከራ እምነት ይፈጥራሉ።",
      language: .amharic,
      length: .long
    ),
    OfflineQuote(
      id: "amharic-long-table",
      title: "ረጅም ጠረጴዛ",
      text: "ረጅም ጠረጴዛ ለብዙ ዓይነት ሥራ ቦታ ይሰጣል። በአንድ ጫፍ የመጀመሪያ ረቂቅ ሊቀመጥ ይችላል፣ በሌላው ጫፍ ተጨማሪ ትኩረት የሚፈልግ አረፍተ ነገር ሊጠብቅ ይችላል፣ በመሃልም ቀጣዩ ትንሽ ውሳኔ ሊጠብቅ ይችላል። ልምምድም እንዲሁ ይሄዳል። እያንዳንዱን አስቸጋሪ ክፍል በአንድ ጊዜ መፍታት አያስፈልግም። ለመመለስ ቦታ፣ ግልጽ ቀጣይ እርምጃ እና ከብዙ ሙከራ በኋላ ቀላል የሆነውን ለማስተዋል ትዕግሥት ሲኖር ፍጥነት በተፈጥሮ ያድጋል።",
      language: .amharic,
      length: .extended
    ),
    OfflineQuote(
      id: "armenian-calm-step",
      title: "Հանգիստ քայլ",
      text: "Հանգիստ քայլը հաջորդ աշխատանքը ավելի պարզ է դարձնում։",
      language: .armenian,
      length: .short
    ),
    OfflineQuote(
      id: "armenian-open-notebook",
      title: "Բաց նոթատետր",
      text: "Բաց նոթատետրը չի պատասխանում բոլոր դժվար հարցերին, բայց այն տեղ է տալիս հարցը փոքր մասերով տեսնելու համար։",
      language: .armenian,
      length: .medium
    ),
    OfflineQuote(
      id: "armenian-small-work",
      title: "Փոքր աշխատանք",
      text: "Առաջընթացը միշտ չէ, որ երևում է որպես մեծ պահ։ Նույն էջը նորից բացելը, մի նախադասություն պարզելը և մի փոքր խնդիր շտկելը վստահություն են ստեղծում հաջորդ փորձի համար։",
      language: .armenian,
      length: .long
    ),
    OfflineQuote(
      id: "armenian-long-table",
      title: "Երկար սեղան",
      text: "Երկար սեղանը տեղ է տալիս բազմազան աշխատանքի համար։ Մի ծայրում կարող է լինել առաջին սևագիրը, մյուս ծայրում՝ ավելի մեծ ուշադրություն պահանջող նախադասությունը, իսկ մեջտեղում՝ հաջորդ փոքր որոշումը։ Վարժությունն էլ այդպես է առաջ գնում։ Պետք չէ յուրաքանչյուր դժվար մաս լուծել միանգամից։ Երբ կա վերադառնալու տեղ, հստակ հաջորդ քայլ և համբերություն՝ մի քանի փորձից հետո հեշտացածը նկատելու համար, արագությունը բնականորեն աճում է։",
      language: .armenian,
      length: .extended
    ),
    OfflineQuote(
      id: "georgian-calm-step",
      title: "მშვიდი ნაბიჯი",
      text: "მშვიდი ნაბიჯი შემდეგ საქმეს უფრო ნათელს ხდის.",
      language: .georgian,
      length: .short
    ),
    OfflineQuote(
      id: "georgian-open-notebook",
      title: "ღია რვეული",
      text: "ღია რვეული ყველა რთულ კითხვას არ პასუხობს, მაგრამ კითხვას პატარა ნაწილებად დასანახად ადგილს ტოვებს.",
      language: .georgian,
      length: .medium
    ),
    OfflineQuote(
      id: "georgian-small-work",
      title: "პატარა საქმე",
      text: "წინსვლა ყოველთვის დიდ მომენტად არ ჩანს. იმავე გვერდის ხელახლა გახსნა, ერთი წინადადების გარკვევა და პატარა პრობლემის გამოსწორება შემდეგი მცდელობისთვის ნდობას ქმნის.",
      language: .georgian,
      length: .long
    ),
    OfflineQuote(
      id: "georgian-long-table",
      title: "გრძელი მაგიდა",
      text: "გრძელი მაგიდა მრავალგვარი საქმისთვის ადგილს იძლევა. ერთ ბოლოში შეიძლება პირველი მონახაზი იდოს, მეორე ბოლოში კი მეტი ყურადღების მომთხოვნი წინადადება დარჩეს, შუაში კი შემდეგი პატარა გადაწყვეტილება დაელოდოს. ვარჯიშიც ასე მიდის წინ. ყველა რთული ნაწილის ერთბაშად გადაწყვეტა საჭირო არ არის. როცა დაბრუნების ადგილი, ნათელი შემდეგი ნაბიჯი და რამდენიმე მცდელობის შემდეგ გამარტივებულის შესამჩნევი მოთმინება არსებობს, სიჩქარე ბუნებრივად იზრდება.",
      language: .georgian,
      length: .extended
    ),
    OfflineQuote(
      id: "azerbaijani-sakit-addim",
      title: "Sakit addım",
      text: "Sakit addım növbəti işi daha aydın göstərir.",
      language: .azerbaijani,
      length: .short
    ),
    OfflineQuote(
      id: "azerbaijani-aciq-defter",
      title: "Açıq dəftər",
      text: "Açıq dəftər bütün suallara cavab vermir, amma sualı kiçik hissələrə ayırmaq üçün yer yaradır.",
      language: .azerbaijani,
      length: .medium
    ),
    OfflineQuote(
      id: "azerbaijani-kicik-is",
      title: "Kiçik iş",
      text: "İrəliləyiş həmişə böyük bir an kimi görünmür. Eyni səhifəni yenidən açmaq, bir cümləni aydınlaşdırmaq və kiçik problemi düzəltmək növbəti cəhd üçün inam yaradır.",
      language: .azerbaijani,
      length: .long
    ),
    OfflineQuote(
      id: "azerbaijani-uzun-masa",
      title: "Uzun masa",
      text: "Uzun masa müxtəlif işlər üçün kifayət qədər yer yaradır. Bir ucunda ilk qaralama, o biri ucunda daha çox diqqət istəyən cümlə, ortada isə növbəti kiçik qərar gözləyə bilər. Məşq də belə irəliləyir. Hər çətin hissəni birdən həll etmək lazım deyil. Geri dönmək üçün yer, aydın növbəti addım və bir neçə cəhddən sonra asanlaşanı görmək üçün səbir olduqda sürət təbii şəkildə artır.",
      language: .azerbaijani,
      length: .extended
    ),
    OfflineQuote(
      id: "belarusian-spakoyny-krok",
      title: "Спакойны крок",
      text: "Спакойны крок робіць наступную справу яснейшай.",
      language: .belarusian,
      length: .short
    ),
    OfflineQuote(
      id: "belarusian-adkryty-natatnik",
      title: "Адкрыты нататнік",
      text: "Адкрыты нататнік не ведае ўсіх адказаў, але пакідае месца, каб убачыць пытанне па частках.",
      language: .belarusian,
      length: .medium
    ),
    OfflineQuote(
      id: "belarusian-malaya-praca",
      title: "Малая праца",
      text: "Рух наперад не заўсёды выглядае як вялікі момант. Зноў адкрыць тую ж старонку, удакладніць адзін сказ і выправіць малую памылку дапамагае набраць упэўненасць для наступнай спробы.",
      language: .belarusian,
      length: .long
    ),
    OfflineQuote(
      id: "belarusian-dougi-stol",
      title: "Доўгі стол",
      text: "Доўгі стол пакідае месца для рознай працы. На адным канцы можа ляжаць першы чарнавік, на другім — сказ, якому трэба больш увагі, а пасярэдзіне чакае наступнае малое рашэнне. Так рухаецца і практыка. Не трэба вырашаць кожную складаную частку адразу. Калі ёсць куды вярнуцца, бачны наступны крок і цярпенне заўважыць тое, што стала лягчэйшым пасля некалькіх спроб, хуткасць расце натуральна.",
      language: .belarusian,
      length: .extended
    ),
    OfflineQuote(
      id: "lithuanian-ramus-zingsnis",
      title: "Ramus žingsnis",
      text: "Ramus žingsnis padeda aiškiau pamatyti kitą darbą.",
      language: .lithuanian,
      length: .short
    ),
    OfflineQuote(
      id: "lithuanian-atverstas-sasiuvinis",
      title: "Atverstas sąsiuvinis",
      text: "Atverstas sąsiuvinis neatsako į visus klausimus, bet palieka vietos juos išskaidyti į mažesnes dalis.",
      language: .lithuanian,
      length: .medium
    ),
    OfflineQuote(
      id: "lithuanian-mazas-darbas",
      title: "Mažas darbas",
      text: "Pažanga ne visada atrodo didelė. Grįžti prie to paties puslapio, patikslinti vieną sakinį ir ištaisyti mažą klaidą suteikia daugiau pasitikėjimo kitam bandymui.",
      language: .lithuanian,
      length: .long
    ),
    OfflineQuote(
      id: "lithuanian-ilgas-stalas",
      title: "Ilgas stalas",
      text: "Ilgas stalas palieka vietos įvairiems darbams. Viename gale gali gulėti pirmas juodraštis, kitame laukti sakinys, kuriam reikia daugiau dėmesio, o viduryje – kitas mažas sprendimas. Taip juda ir praktika. Nebūtina iš karto išspręsti kiekvienos sudėtingos dalies. Kai yra kur sugrįžti, aiškus kitas žingsnis ir kantrybė pastebėti, kas po kelių bandymų tapo lengviau, greitis auga natūraliai.",
      language: .lithuanian,
      length: .extended
    ),
    OfflineQuote(
      id: "latvian-rams-solis",
      title: "Rāms solis",
      text: "Rāms solis palīdz skaidrāk ieraudzīt nākamo darbu.",
      language: .latvian,
      length: .short
    ),
    OfflineQuote(
      id: "latvian-atverta-piezimju-gramata",
      title: "Atvērta piezīmju grāmata",
      text: "Atvērta piezīmju grāmata neatbild uz visiem jautājumiem, bet atstāj vietu tos sadalīt mazākās daļās.",
      language: .latvian,
      length: .medium
    ),
    OfflineQuote(
      id: "latvian-mazs-darbs",
      title: "Mazs darbs",
      text: "Progress ne vienmēr izskatās iespaidīgs. Atgriešanās pie tās pašas lapas, viena teikuma precizēšana un mazas kļūdas labošana dod vairāk pārliecības nākamajam mēģinājumam.",
      language: .latvian,
      length: .long
    ),
    OfflineQuote(
      id: "latvian-garss-galds",
      title: "Garš galds",
      text: "Garš galds atstāj vietu dažādiem darbiem. Vienā galā var gulēt pirmais melnraksts, otrā gaidīt teikums, kam vajag vairāk uzmanības, bet vidū — nākamais mazais lēmums. Tā kustas arī prakse. Nav nepieciešams uzreiz atrisināt katru sarežģīto daļu. Kad ir kur atgriezties, redzams nākamais solis un pietiek pacietības pamanīt to, kas pēc vairākiem mēģinājumiem kļuvis vieglāks, ātrums aug dabiski.",
      language: .latvian,
      length: .extended
    ),
    OfflineQuote(
      id: "mongolian-taivan-alham",
      title: "Тайван алхам",
      text: "Тайван алхам дараагийн ажлыг тодруулдаг.",
      language: .mongolian,
      length: .short
    ),
    OfflineQuote(
      id: "mongolian-neelttei-devter",
      title: "Нээлттэй дэвтэр",
      text: "Нээлттэй дэвтэр бүх хариуг өгдөггүй ч асуултыг жижиг хэсэгт хуваах зай үлдээнэ.",
      language: .mongolian,
      length: .medium
    ),
    OfflineQuote(
      id: "mongolian-jijig-ajil",
      title: "Жижиг ажил",
      text: "Ахиц үргэлж гайхамшигтай харагддаггүй. Нэг хуудсанд буцаж очих, нэг өгүүлбэрийг нарийвчлах, жижиг алдааг засах нь дараагийн оролдлогод илүү итгэл өгдөг.",
      language: .mongolian,
      length: .long
    ),
    OfflineQuote(
      id: "mongolian-urt-shiree",
      title: "Урт ширээ",
      text: "Урт ширээ олон ажилд зай гаргадаг. Нэг талд нь эхний ноорог хэвтэж, нөгөө талд нь илүү анхаарал хэрэгтэй өгүүлбэр хүлээж, дунд нь дараагийн жижиг шийдвэр байрлана. Дасгал ч мөн ингэж урагшилдаг. Хэцүү хэсэг бүрийг шууд шийдэх шаардлагагүй. Буцаж очих газар байвал дараагийн алхам харагдаж, хэд хэдэн оролдлогын дараа хялбар болсон зүйлийг анзаарах тэвчээр төрнө, хурд аяндаа нэмэгддэг.",
      language: .mongolian,
      length: .extended
    ),
    OfflineQuote(
      id: "irish-ceim-chiui",
      title: "Céim chiúin",
      text: "Cuireann céim chiúin an chéad obair eile i bhfianaise.",
      language: .irish,
      length: .short
    ),
    OfflineQuote(
      id: "irish-leabhar-notai-oscailte",
      title: "Leabhar nótaí oscailte",
      text: "Ní thugann leabhar nótaí oscailte gach freagra, ach fágann sé spás chun ceisteanna a roinnt ina gcodanna beaga.",
      language: .irish,
      length: .medium
    ),
    OfflineQuote(
      id: "irish-obair-bheag",
      title: "Obair bheag",
      text: "Ní bhíonn an dul chun cinn mór le feiceáil i gcónaí. Tugann filleadh ar an leathanach céanna, abairt amháin a dhéanamh níos soiléire, agus botún beag a cheartú níos mó muiníne don chéad iarracht eile.",
      language: .irish,
      length: .long
    ),
    OfflineQuote(
      id: "irish-bord-fada",
      title: "Bord fada",
      text: "Fágann bord fada spás do go leor oibre. Ar cheann amháin is féidir leis an gcéad dréacht luí, ar an gceann eile fanann abairt a dteastaíonn níos mó aire uaithi, agus sa lár bíonn an chéad chinneadh beag eile. Sin mar a ghluaiseann cleachtadh freisin. Ní gá gach cuid chasta a réiteach láithreach. Nuair atá áit ann le filleadh chuici, feictear an chéad chéim eile agus fásann an fhoighne chun a thabhairt faoi deara cad a d’éirigh níos éasca tar éis cúpla iarracht, méadaíonn an luas go nádúrtha.",
      language: .irish,
      length: .extended
    ),
    OfflineQuote(
      id: "galician-paso-calmo",
      title: "Paso calmo",
      text: "Un paso calmo axuda a ver con claridade o seguinte traballo.",
      language: .galician,
      length: .short
    ),
    OfflineQuote(
      id: "galician-caderno-aberto",
      title: "Caderno aberto",
      text: "Un caderno aberto non responde todas as preguntas, pero deixa espazo para dividilas en partes pequenas.",
      language: .galician,
      length: .medium
    ),
    OfflineQuote(
      id: "galician-progreso-pequeno",
      title: "Progreso pequeno",
      text: "O progreso non sempre parece grande. Volver á mesma páxina, aclarar unha frase e corrixir un erro pequeno dá máis confianza para o seguinte intento.",
      language: .galician,
      length: .long
    ),
    OfflineQuote(
      id: "galician-mesa-longa",
      title: "Mesa longa",
      text: "Unha mesa longa deixa espazo para traballos diferentes. Nun extremo pode quedar o primeiro borrador, no outro agarda unha frase que precisa máis atención e no medio está a seguinte decisión pequena. Así avanza tamén a práctica. Non é necesario resolver de contado cada parte difícil. Cando hai un lugar ao que volver, aparece o seguinte paso e medra a paciencia para notar o que se fixo máis doado despois de varios intentos, a velocidade aumenta de maneira natural.",
      language: .galician,
      length: .extended
    ),
    OfflineQuote(
      id: "marathi-shant-paul",
      title: "शांत पाऊल",
      text: "शांत पाऊल पुढचे काम अधिक स्पष्ट करते.",
      language: .marathi,
      length: .short
    ),
    OfflineQuote(
      id: "marathi-ughadi-vahi",
      title: "उघडी वही",
      text: "उघडी वही सर्व प्रश्नांची उत्तरे देत नाही, पण प्रश्नांना लहान भागांत विभागण्यासाठी जागा ठेवते.",
      language: .marathi,
      length: .medium
    ),
    OfflineQuote(
      id: "marathi-lahan-pragati",
      title: "लहान प्रगती",
      text: "प्रगती नेहमी मोठी दिसत नाही. त्याच पानाकडे परत जाणे, एक वाक्य अधिक स्पष्ट करणे आणि छोटी चूक दुरुस्त करणे पुढच्या प्रयत्नासाठी अधिक विश्वास देते.",
      language: .marathi,
      length: .long
    ),
    OfflineQuote(
      id: "marathi-lamb-table",
      title: "लांब टेबल",
      text: "लांब टेबल अनेक कामांसाठी जागा ठेवते. एका टोकाला पहिला मसुदा पडलेला असू शकतो, दुसऱ्या टोकाला अधिक लक्ष हवे असलेले वाक्य थांबते आणि मधोमध पुढचा छोटा निर्णय असतो. सरावही अशाच प्रकारे पुढे जातो. प्रत्येक कठीण भाग लगेच सोडवणे आवश्यक नाही. परत येण्यासाठी जागा असेल, तर पुढचे पाऊल दिसते आणि काही प्रयत्नांनंतर जे सोपे झाले ते लक्षात घेण्याचा संयम वाढतो, वेग नैसर्गिकपणे वाढतो.",
      language: .marathi,
      length: .extended
    ),
    OfflineQuote(
      id: "kurdish-central-hengawi-aram",
      title: "هەنگاوی ئارام",
      text: "هەنگاوی ئارام کاری داهاتوو ڕوونتر دەکات.",
      language: .kurdishCentral,
      length: .short
    ),
    OfflineQuote(
      id: "kurdish-central-defteri-krawa",
      title: "دەفتەری کراوە",
      text: "دەفتەری کراوە هەموو وەڵامەکان نازانێت، بەڵام شوێن بۆ بینینی پرسیار بە بەشە بچووکەکان دەهێڵێت.",
      language: .kurdishCentral,
      length: .medium
    ),
    OfflineQuote(
      id: "kurdish-central-kari-bchook",
      title: "کاری بچووک",
      text: "پێشکەوتن هەمیشە وەک ساتێکی گەورە دیار نابێت. کردنەوەی هەمان پەڕە، ڕوونکردنەوەی یەک ڕستە و چاککردنی کێشەیەکی بچووک بۆ هەوڵی داهاتوو متمانە دروست دەکات.",
      language: .kurdishCentral,
      length: .long
    ),
    OfflineQuote(
      id: "kurdish-central-mezi-dreh",
      title: "مێزی درێژ",
      text: "مێزی درێژ شوێن بۆ جۆرەها کار دەهێڵێت. لە یەک لاوە ڕەشنووسی یەکەم دادەنرێت، لە لاوەی تر ڕستەیەک چاوەڕێی سەرنجی زیاترە، و لە ناوەڕاستدا بڕیارێکی بچووک نۆرەی خۆی دەوێت. ڕاهێنانیش بە هەمان شێوە پێش دەچێت. پێویست نییە هەموو بەشە سەختەکان یەکجار چارەسەر بکرێن. کاتێک شوێنی گەڕانەوە، هەنگاوی داهاتووی ڕوون و ئارامی بۆ بینینی ئاسانبوون دوای چەند هەوڵێک هەبێت، خێرایی بە سروشتی زیاد دەبێت.",
      language: .kurdishCentral,
      length: .extended
    ),
    OfflineQuote(
      id: "filipino-payapang-hakbang",
      title: "Payapang hakbang",
      text: "Ang payapang hakbang ay nagpapalinaw sa susunod na gawain.",
      language: .filipino,
      length: .short
    ),
    OfflineQuote(
      id: "filipino-bukas-na-talaan",
      title: "Bukas na talaan",
      text: "Hindi nalulutas ng bukas na talaan ang bawat mahirap na tanong, ngunit nakatutulong itong hatiin ang tanong sa maliliit na bahagi.",
      language: .filipino,
      length: .medium
    ),
    OfflineQuote(
      id: "filipino-maliit-na-gawain",
      title: "Maliit na gawain",
      text: "Hindi laging dumarating ang pag-unlad bilang malaking sandali. Lumalago ito sa maliliit na gawain: buksan ang parehong pahina, linawin ang isang pangungusap, itama ang isang pagkakamali at mag-iwan ng kapaki-pakinabang na tala para sa susunod na pagsubok.",
      language: .filipino,
      length: .long
    ),
    OfflineQuote(
      id: "filipino-mahabang-mesa",
      title: "Mahabang mesa",
      text: "Ang mahabang mesa ay nagbibigay ng lugar para sa iba't ibang uri ng gawain. Sa isang dulo ay maaaring ilagay ang unang bersiyon, sa kabila ay isang pangungusap na kailangan pa ng pansin, at sa gitna ay maaaring maghintay ang susunod na maliit na pasiya. Ganiyan din ang pagsasanay. Hindi nito hinihingi na malutas agad ang bawat mahirap na bahagi, kundi na magkaroon ng lugar na babalikan, malinaw na susunod na hakbang at sapat na tiyaga upang mapansin kung alin ang nagiging mas madali pagkatapos ng ilang pagsubok.",
      language: .filipino,
      length: .extended
    ),
    OfflineQuote(
      id: "catalan-pas-tranquil",
      title: "Pas tranquil",
      text: "Un pas tranquil fa més clara la tasca següent.",
      language: .catalan,
      length: .short
    ),
    OfflineQuote(
      id: "catalan-quadern-obert",
      title: "Quadern obert",
      text: "Un quadern obert no resol totes les preguntes difícils, però ajuda a dividir-les en parts més petites.",
      language: .catalan,
      length: .medium
    ),
    OfflineQuote(
      id: "catalan-feina-petita",
      title: "Feina petita",
      text: "El progrés no arriba sempre com un moment gran. Creix en feines petites: obrir la mateixa pàgina, aclarir una frase, corregir un error i deixar una nota útil per al següent intent.",
      language: .catalan,
      length: .long
    ),
    OfflineQuote(
      id: "catalan-taula-llarga",
      title: "Taula llarga",
      text: "Una taula llarga deixa espai per a diferents tipus de feina. En un costat hi pot haver un primer esborrany, a l'altre una frase que encara demana atenció, i al mig pot esperar la decisió petita següent. La pràctica funciona de manera semblant. No demana resoldre cada part difícil de seguida, sinó tenir un lloc on tornar, un pas següent visible i prou paciència per notar què es torna més fàcil després d'uns quants intents.",
      language: .catalan,
      length: .extended
    ),
    OfflineQuote(
      id: "indonesian-langkah-tenang",
      title: "Langkah tenang",
      text: "Langkah tenang membuat tugas berikutnya lebih jelas.",
      language: .indonesian,
      length: .short
    ),
    OfflineQuote(
      id: "indonesian-buku-catatan-terbuka",
      title: "Buku catatan terbuka",
      text: "Buku catatan terbuka tidak menyelesaikan setiap pertanyaan sulit, tetapi membantu membaginya menjadi bagian yang lebih kecil.",
      language: .indonesian,
      length: .medium
    ),
    OfflineQuote(
      id: "indonesian-pekerjaan-kecil",
      title: "Pekerjaan kecil",
      text: "Kemajuan tidak selalu datang sebagai satu momen besar. Ia tumbuh dari pekerjaan kecil: membuka halaman yang sama, menjernihkan satu kalimat, memperbaiki satu kesalahan, dan meninggalkan catatan yang berguna untuk percobaan berikutnya.",
      language: .indonesian,
      length: .long
    ),
    OfflineQuote(
      id: "indonesian-meja-panjang",
      title: "Meja panjang",
      text: "Meja panjang memberi ruang untuk berbagai jenis pekerjaan. Di satu sisi dapat diletakkan draf pertama, di sisi lain sebuah kalimat yang masih membutuhkan perhatian, dan di tengah dapat menunggu keputusan kecil berikutnya. Latihan bekerja dengan cara yang sama. Latihan tidak meminta setiap bagian sulit diselesaikan sekaligus, melainkan menyediakan tempat untuk kembali, langkah berikutnya yang terlihat, dan cukup kesabaran untuk menyadari apa yang menjadi lebih mudah setelah beberapa percobaan.",
      language: .indonesian,
      length: .extended
    ),
    OfflineQuote(
      id: "malay-langkah-tenang",
      title: "Langkah tenang",
      text: "Langkah tenang menjadikan tugas seterusnya lebih jelas.",
      language: .malay,
      length: .short
    ),
    OfflineQuote(
      id: "malay-catatan-terbuka",
      title: "Catatan terbuka",
      text: "Catatan terbuka tidak menyelesaikan setiap soalan yang sukar, tetapi membantu membahagikannya kepada bahagian yang lebih kecil.",
      language: .malay,
      length: .medium
    ),
    OfflineQuote(
      id: "malay-kerja-kecil",
      title: "Kerja kecil",
      text: "Kemajuan tidak selalu tiba sebagai satu saat yang besar. Ia tumbuh melalui kerja kecil: membuka halaman yang sama, menjelaskan satu ayat, membetulkan satu kesilapan, dan meninggalkan catatan yang berguna untuk percubaan seterusnya.",
      language: .malay,
      length: .long
    ),
    OfflineQuote(
      id: "malay-meja-panjang",
      title: "Meja panjang",
      text: "Meja panjang memberi ruang untuk pelbagai jenis kerja. Di satu sisi boleh diletakkan draf pertama, di sisi lain satu ayat yang masih memerlukan perhatian, dan di tengah boleh menunggu keputusan kecil yang seterusnya. Latihan berfungsi dengan cara yang sama. Ia tidak meminta setiap bahagian yang sukar diselesaikan serentak, tetapi menyediakan tempat untuk kembali, langkah seterusnya yang jelas, dan kesabaran yang cukup untuk menyedari apa yang menjadi lebih mudah selepas beberapa percubaan.",
      language: .malay,
      length: .extended
    ),
    OfflineQuote(
      id: "danish-lille-skridt",
      title: "Lille skridt",
      text: "Et lille, roligt skridt gør den næste opgave lettere at se.",
      language: .danish,
      length: .short
    ),
    OfflineQuote(
      id: "danish-aaben-notesbog",
      title: "Åben notesbog",
      text: "En åben notesbog løser ikke vanskelige spørgsmål af sig selv, men hjælper med at dele dem i klare dele og vende tilbage med opmærksomhed.",
      language: .danish,
      length: .medium
    ),
    OfflineQuote(
      id: "danish-roligt-arbejde",
      title: "Roligt arbejde",
      text: "Fremskridt kommer ikke altid som et tydeligt øjeblik. Det vokser i gentagne handlinger: at åbne den samme side, gøre én sætning klarere, rette en fejl og efterlade en brugbar note til næste forsøg. Med tiden gør den rolige opmærksomhed svære steder mere velkendte.",
      language: .danish,
      length: .long
    ),
    OfflineQuote(
      id: "danish-langt-bord",
      title: "Langt bord",
      text: "Et langt bord er nyttigt, fordi der bliver plads til forskellige slags arbejde. I den ene ende kan en første skitse ligge, i den anden en sætning der stadig kræver opmærksomhed, og i midten er der plads til den næste lille beslutning. Øvelse virker på samme måde: den beder ikke om at løse enhver vanskelighed på én gang, men om et sted at vende tilbage til, et synligt næste skridt og tålmodighed nok til at opdage, hvad der bliver lettere efter nogle forsøg.",
      language: .danish,
      length: .extended
    ),
    OfflineQuote(
      id: "norwegian-bokmal-lite-steg",
      title: "Lite steg",
      text: "Et lite, rolig steg gjør den neste oppgaven lettere å se.",
      language: .norwegianBokmal,
      length: .short
    ),
    OfflineQuote(
      id: "norwegian-bokmal-aapen-notatbok",
      title: "Åpen notatbok",
      text: "En åpen notatbok løser ikke vanskelige spørsmål alene, men hjelper med å dele dem i klare deler og vende tilbake med oppmerksomhet.",
      language: .norwegianBokmal,
      length: .medium
    ),
    OfflineQuote(
      id: "norwegian-bokmal-rolig-arbeid",
      title: "Rolig arbeid",
      text: "Fremskritt kommer ikke alltid som et tydelig øyeblikk. Det vokser i gjentatte handlinger: å åpne den samme siden, gjøre én setning klarere, rette en feil og etterlate et nyttig notat til neste forsøk. Over tid gjør den rolige oppmerksomheten vanskelige steder mer kjente.",
      language: .norwegianBokmal,
      length: .long
    ),
    OfflineQuote(
      id: "norwegian-bokmal-langt-bord",
      title: "Langt bord",
      text: "Et langt bord er nyttig fordi det gir plass til ulike slags arbeid. I den ene enden kan et første utkast ligge, i den andre en setning som fortsatt trenger oppmerksomhet, og i midten er det plass til den neste lille beslutningen. Øvelse virker på samme måte: den ber ikke om at alle vanskeligheter skal løses på én gang, men om et sted å vende tilbake til, et synlig neste steg og nok tålmodighet til å legge merke til hva som blir lettere etter noen forsøk.",
      language: .norwegianBokmal,
      length: .extended
    ),
    OfflineQuote(
      id: "norwegian-nynorsk-lite-steg",
      title: "Lite steg",
      text: "Eit roleg steg kan gjere den neste oppgåva klårare.",
      language: .norwegianNynorsk,
      length: .short
    ),
    OfflineQuote(
      id: "norwegian-nynorsk-open-notatbok",
      title: "Open notatbok",
      text: "Ei open notatbok løyser ikkje vanskelege spørsmål åleine, men ho gjer det lettare å dele dei i små delar.",
      language: .norwegianNynorsk,
      length: .medium
    ),
    OfflineQuote(
      id: "norwegian-nynorsk-roleg-arbeid",
      title: "Roleg arbeid",
      text: "Framgang kjem ikkje alltid i ei stor stund. Han veks i små handlingar: å opne den same sida, gjere ei setning klårare, rette ein feil og leggje att eit nyttig notat til neste forsøk.",
      language: .norwegianNynorsk,
      length: .long
    ),
    OfflineQuote(
      id: "norwegian-nynorsk-langt-bord",
      title: "Langt bord",
      text: "Eit langt bord gjev rom for ulike slag arbeid. I den eine enden kan eit første utkast liggje, i den andre ei setning som framleis treng merksemd, og i midten kan den neste vesle avgjerda vente. Øving verkar på same måten. Ho krev ikkje at alle vanskelege delar skal løysast med ein gong, men at vi har ein stad å vende attende til, eit synleg neste steg og nok tolmod til å leggje merke til det som vert lettare etter fleire forsøk.",
      language: .norwegianNynorsk,
      length: .extended
    ),
    OfflineQuote(
      id: "swedish-calm-rhythm",
      title: "Lugn rytm",
      text: "En lugn rytm gör nästa rad lättare att hitta.",
      language: .swedish,
      length: .short
    ),
    OfflineQuote(
      id: "swedish-small-note",
      title: "Liten anteckning",
      text: "En liten anteckning behöver inte lösa hela frågan. Den kan visa var arbetet ska börja när du återvänder.",
      language: .swedish,
      length: .medium
    ),
    OfflineQuote(
      id: "swedish-return",
      title: "Återkomst",
      text: "Arbetet blir ofta tydligare efter en kort paus. Läs den senaste raden, välj en sak att förbättra och lämna en enkel markering för nästa gång. Så får varje återkomst ett mindre avstånd att överbrygga, även när uppgiften fortfarande är svår.",
      language: .swedish,
      length: .long
    ),
    OfflineQuote(
      id: "swedish-open-table",
      title: "Öppet bord",
      text: "På ett bord med gott om plats kan ett utkast ligga öppet bredvid en lista med frågor. Det gör det lättare att flytta blicken mellan det som redan är säkert och det som ännu behöver provas. En övning kan fungera på samma sätt: skriv en rad, kontrollera en detalj och behåll ett tydligt nästa steg. När allt inte måste bli klart på en gång får uppmärksamheten tid att bygga en tryggare rytm.",
      language: .swedish,
      length: .extended
    ),
    OfflineQuote(
      id: "hungarian-kis-lepes",
      title: "Kis lépés",
      text: "Egy kis, nyugodt lépés tisztábbá teszi a következő feladatot.",
      language: .hungarian,
      length: .short
    ),
    OfflineQuote(
      id: "hungarian-nyitott-jegyzet",
      title: "Nyitott jegyzet",
      text: "Egy nyitott jegyzetfüzet nem old meg nehéz kérdéseket önmagában, de segít világos részekre bontani őket, és figyelemmel visszatérni hozzájuk.",
      language: .hungarian,
      length: .medium
    ),
    OfflineQuote(
      id: "hungarian-nyugodt-munka",
      title: "Nyugodt munka",
      text: "A fejlődés nem mindig egy jól látható pillanatban érkezik. Ismétlődő cselekvésekből nő ki: ugyanannak az oldalnak a megnyitásából, egy mondat tisztábbá tételéből, egy hiba kijavításából és egy hasznos jegyzet hátrahagyásából a következő próbálkozáshoz. Idővel a nyugodt figyelem ismerősebbé teszi a nehéz részeket.",
      language: .hungarian,
      length: .long
    ),
    OfflineQuote(
      id: "hungarian-hosszu-asztal",
      title: "Hosszú asztal",
      text: "Egy hosszú asztal azért hasznos, mert többféle munkának is helyet ad. Az egyik végén egy első vázlat lehet, a másikon egy mondat, amely még figyelmet igényel, középen pedig marad hely a következő kis döntésnek. A gyakorlás is így működik: nem azt kéri, hogy minden nehézséget egyszerre oldjunk meg, hanem hogy legyen hová visszatérni, lássuk a következő lépést, és legyen elég türelmünk észrevenni, mi válik könnyebbé néhány próbálkozás után.",
      language: .hungarian,
      length: .extended
    ),
    OfflineQuote(
      id: "czech-maly-krok",
      title: "Malý krok",
      text: "Malý klidný krok může zpřesnit příští úkol.",
      language: .czech,
      length: .short
    ),
    OfflineQuote(
      id: "czech-otevreny-zapis",
      title: "Otevřený zápis",
      text: "Otevřený zápisník nevyřeší těžkou otázku sám, ale pomůže rozdělit myšlenky a vrátit se k nim pozorněji.",
      language: .czech,
      length: .medium
    ),
    OfflineQuote(
      id: "czech-ticha-prace",
      title: "Tichá práce",
      text: "Pokrok se často neukáže v jediném hlasitém okamžiku. Vzniká, když otevřeme stejnou stránku, opravíme jednu chybu, přečteme si poznámku a vybereme další malý krok. Takové opakování dává složitým věcem známější tvar a uvolňuje místo pro soustředění.",
      language: .czech,
      length: .long
    ),
    OfflineQuote(
      id: "czech-dlouhy-stul",
      title: "Dlouhý stůl",
      text: "Dlouhý stůl je užitečný, protože nechává místo pro různé druhy práce. Na jednom konci může ležet první náčrt, na druhém věta, která ještě potřebuje péči, a uprostřed zůstane volný prostor pro další malé rozhodnutí. Cvičení funguje podobně. Nežádá, abychom vyřešili všechno najednou, ale abychom měli kam se vrátit, viděli další krok a našli dost trpělivosti všimnout si toho, co je po několika pokusech snazší.",
      language: .czech,
      length: .extended
    ),
    OfflineQuote(
      id: "slovak-tichy-krok",
      title: "Tichý krok",
      text: "Tichý krok robí ďalšiu úlohu jasnejšou.",
      language: .slovak,
      length: .short
    ),
    OfflineQuote(
      id: "slovak-otvoreny-zapisnik",
      title: "Otvorený zápisník",
      text: "Otvorený zápisník nevyrieši ťažkú otázku sám, ale pomôže myšlienkam nájsť poradie a smer.",
      language: .slovak,
      length: .medium
    ),
    OfflineQuote(
      id: "slovak-ticha-praca",
      title: "Tichá práca",
      text: "Pokrok zriedka vznikne v jednej hlučnej chvíli. Rastie, keď otvoríme tú istú stránku, opravíme chybu, prečítame si poznámku a vyberieme ďalšiu malú úlohu. Opakovanie robí ťažké veci známejšími a necháva viac priestoru pre pozornosť.",
      language: .slovak,
      length: .long
    ),
    OfflineQuote(
      id: "slovak-dlhy-stol",
      title: "Dlhý stôl",
      text: "Dlhý stôl je užitočný, pretože na ňom zostane miesto pre rozličnú prácu. Na jednom konci môže ležať prvý návrh, na druhom veta, ktorá ešte potrebuje pozornosť, a uprostred ostane priestor pre ďalšie malé rozhodnutie. Cvičenie funguje podobne. Nemusí vyriešiť všetko naraz, stačí, ak nám dá miesto, kam sa môžeme vrátiť, všimnúť si ďalší krok a nájsť dosť trpezlivosti, aby sme si všimli, čo je po niekoľkých pokusoch ľahšie.",
      language: .slovak,
      length: .extended
    ),
    OfflineQuote(
      id: "slovenian-mirni-korak",
      title: "Mirni korak",
      text: "Mirni korak naredi naslednjo nalogo jasnejšo.",
      language: .slovenian,
      length: .short
    ),
    OfflineQuote(
      id: "slovenian-odprt-zvezek",
      title: "Odprt zvezek",
      text: "Odprt zvezek ne reši težkega vprašanja sam, vendar pomaga mislim najti red in smer.",
      language: .slovenian,
      length: .medium
    ),
    OfflineQuote(
      id: "slovenian-tiho-delo",
      title: "Tiho delo",
      text: "Napredek redko nastane v enem glasnem trenutku. Raste, ko odpremo isto stran, popravimo napako, preberemo zapisek in izberemo naslednjo majhno nalogo. Ponavljanje naredi težke dele bolj znane in pusti več prostora za pozornost.",
      language: .slovenian,
      length: .long
    ),
    OfflineQuote(
      id: "slovenian-dolga-miza",
      title: "Dolga miza",
      text: "Dolga miza je uporabna, ker ponuja prostor za različne vrste dela. Na enem koncu je lahko prvi osnutek, na drugem stavek, ki še potrebuje pozornost, na sredini pa ostane prostor za naslednjo majhno odločitev. Vaja deluje podobno. Ni ji treba rešiti vsega naenkrat, ampak nam lahko ponudi kraj, kamor se vrnemo, opazimo naslednji korak in najdemo dovolj potrpežljivosti, da vidimo, kaj po nekaj poskusih postane lažje.",
      language: .slovenian,
      length: .extended
    ),
    OfflineQuote(
      id: "croatian-mirni-korak",
      title: "Mirni korak",
      text: "Mirni korak čini sljedeći zadatak jasnijim.",
      language: .croatian,
      length: .short
    ),
    OfflineQuote(
      id: "croatian-otvorena-biljeznica",
      title: "Otvorena bilježnica",
      text: "Otvorena bilježnica ne rješava teško pitanje sama, ali pomaže mislima pronaći red i smjer.",
      language: .croatian,
      length: .medium
    ),
    OfflineQuote(
      id: "croatian-tiha-vjezba",
      title: "Tiha vježba",
      text: "Napredak rijetko nastane u jednom glasnom trenutku. Raste kada otvorimo istu stranicu, ispravimo pogrešku, pročitamo bilješku i odaberemo sljedeći mali zadatak. Ponavljanje čini teške dijelove poznatijima i ostavlja više prostora za pažnju.",
      language: .croatian,
      length: .long
    ),
    OfflineQuote(
      id: "croatian-dugi-stol",
      title: "Dugi stol",
      text: "Dugi stol je koristan jer nudi mjesto za različite vrste rada. Na jednom kraju može biti prvi nacrt, na drugom rečenica koja još treba pažnju, a u sredini ostaje prostor za sljedeću malu odluku. Vježba djeluje slično. Ne mora riješiti sve odjednom, nego nam može dati mjesto kojem se vraćamo, primijetimo sljedeći korak i pronađemo dovoljno strpljenja da vidimo što postaje lakše nakon nekoliko pokušaja.",
      language: .croatian,
      length: .extended
    ),
    OfflineQuote(
      id: "serbian-mirni-korak",
      title: "Миран корак",
      text: "Миран корак чини следећи задатак јаснијим.",
      language: .serbian,
      length: .short
    ),
    OfflineQuote(
      id: "serbian-otvorena-beleska",
      title: "Отворена белешка",
      text: "Отворена белешка не решава тешко питање сама, али помаже мислима да пронађу ред и смер.",
      language: .serbian,
      length: .medium
    ),
    OfflineQuote(
      id: "serbian-tihi-rad",
      title: "Тихи рад",
      text: "Напредак ретко настаје у једном гласном тренутку. Расте када отворимо исту страницу, исправимо грешку, прочитамо белешку и изаберемо следећи мали задатак. Понављање чини тешке делове познатијим и оставља више простора за пажњу.",
      language: .serbian,
      length: .long
    ),
    OfflineQuote(
      id: "serbian-dugacak-sto",
      title: "Дугачак сто",
      text: "Дугачак сто је користан јер нуди место за различите врсте рада. На једном крају може бити први нацрт, на другом реченица која још тражи пажњу, а у средини остаје простор за следећу малу одлуку. Вежба делује слично. Не мора да реши све одједном, већ нам може дати место коме се враћамо, приметимо следећи корак и нађемо довољно стрпљења да видимо шта постаје лакше после неколико покушаја.",
      language: .serbian,
      length: .extended
    ),
    OfflineQuote(
      id: "serbian-latin-mirni-korak",
      title: "Mirni korak",
      text: "Mirni korak čini sledeći zadatak jasnijim.",
      language: .serbianLatin,
      length: .short
    ),
    OfflineQuote(
      id: "serbian-latin-otvorena-beleska",
      title: "Otvorena beleška",
      text: "Otvorena beleška ne rešava teško pitanje sama, ali pomaže mislima da pronađu red i smer.",
      language: .serbianLatin,
      length: .medium
    ),
    OfflineQuote(
      id: "serbian-latin-tihi-rad",
      title: "Tihi rad",
      text: "Napredak retko nastaje u jednom glasnom trenutku. Raste kada otvorimo istu stranicu, ispravimo grešku, pročitamo belešku i izaberemo sledeći mali zadatak. Ponavljanje čini teške delove poznatijim i ostavlja više prostora za pažnju.",
      language: .serbianLatin,
      length: .long
    ),
    OfflineQuote(
      id: "serbian-latin-dugacak-sto",
      title: "Dugačak sto",
      text: "Dugačak sto je koristan jer nudi mesto za različite vrste rada. Na jednom kraju može biti prvi nacrt, na drugom rečenica koja još traži pažnju, a u sredini ostaje prostor za sledeću malu odluku. Vežba deluje slično. Ne mora da reši sve odjednom, već nam može dati mesto kome se vraćamo, primetimo sledeći korak i nađemo dovoljno strpljenja da vidimo šta postaje lakše posle nekoliko pokušaja.",
      language: .serbianLatin,
      length: .extended
    ),
    OfflineQuote(
      id: "bulgarian-malka-krachka",
      title: "Малка крачка",
      text: "Една спокойна крачка прави следващата задача по-ясна.",
      language: .bulgarian,
      length: .short
    ),
    OfflineQuote(
      id: "bulgarian-otvorena-tetradka",
      title: "Отворена тетрадка",
      text: "Отворената тетрадка не решава трудния въпрос сама, но помага на мислите да намерят ред и посока.",
      language: .bulgarian,
      length: .medium
    ),
    OfflineQuote(
      id: "bulgarian-tihata-rabota",
      title: "Тихата работа",
      text: "Напредъкът рядко пристига в един шумен миг. Той расте, когато отворим същата страница, поправим една грешка, прочетем бележка и изберем следващата малка задача. Повторението прави трудните части по-познати и оставя повече място за внимание.",
      language: .bulgarian,
      length: .long
    ),
    OfflineQuote(
      id: "bulgarian-dalgata-masa",
      title: "Дългата маса",
      text: "Дългата маса е полезна, защото оставя място за различни видове работа. В единия край може да лежи първата скица, в другия изречение, което още иска грижа, а по средата остава свободно място за следващото малко решение. Упражнението работи по същия начин. То не изисква да решим всичко наведнъж, а да имаме къде да се върнем, да видим следващата стъпка и да намерим достатъчно търпение, за да забележим какво става по-лесно след няколко опита.",
      language: .bulgarian,
      length: .extended
    ),
    OfflineQuote(
      id: "romanian-pas-linistit",
      title: "Pas liniștit",
      text: "Un pas liniștit face următoarea sarcină mai clară.",
      language: .romanian,
      length: .short
    ),
    OfflineQuote(
      id: "romanian-caiet-deschis",
      title: "Caiet deschis",
      text: "Un caiet deschis nu rezolvă singur o întrebare grea, dar ajută gândurile să găsească ordine și direcție.",
      language: .romanian,
      length: .medium
    ),
    OfflineQuote(
      id: "romanian-munca-linistita",
      title: "Muncă liniștită",
      text: "Progresul apare rareori într-un singur moment zgomotos. Crește când deschidem aceeași pagină, îndreptăm o greșeală, citim o notiță și alegem următoarea sarcină mică. Repetarea face părțile dificile mai familiare și lasă mai mult loc pentru atenție.",
      language: .romanian,
      length: .long
    ),
    OfflineQuote(
      id: "romanian-masa-lunga",
      title: "Masă lungă",
      text: "O masă lungă este utilă fiindcă lasă loc pentru feluri diferite de muncă. La un capăt poate sta prima schiță, la celălalt o frază care mai are nevoie de grijă, iar la mijloc rămâne spațiu pentru următoarea decizie mică. Exercițiul funcționează la fel. Nu cere să rezolvăm totul deodată, ci să avem unde să revenim, să vedem pasul următor și să găsim destulă răbdare pentru a observa ce devine mai ușor după câteva încercări.",
      language: .romanian,
      length: .extended
    ),
    OfflineQuote(
      id: "finnish-rauhallinen-askel",
      title: "Rauhallinen askel",
      text: "Rauhallinen askel tekee seuraavasta tehtävästä selvemmän.",
      language: .finnish,
      length: .short
    ),
    OfflineQuote(
      id: "finnish-avoin-muistikirja",
      title: "Avoin muistikirja",
      text: "Avoin muistikirja ei ratkaise vaikeaa kysymystä yksin, mutta se auttaa ajatuksia löytämään järjestyksen ja suunnan.",
      language: .finnish,
      length: .medium
    ),
    OfflineQuote(
      id: "finnish-hiljainen-tyo",
      title: "Hiljainen työ",
      text: "Edistyminen ei yleensä synny yhdessä äänekkäässä hetkessä. Se kasvaa, kun avaamme saman sivun, korjaamme virheen, luemme muistiinpanon ja valitsemme seuraavan pienen tehtävän. Toisto tekee vaikeista asioista tutumpia ja jättää enemmän tilaa huomiolle.",
      language: .finnish,
      length: .long
    ),
    OfflineQuote(
      id: "finnish-pitka-poyta",
      title: "Pitkä pöytä",
      text: "Pitkä pöytä on hyödyllinen, koska sillä on tilaa monenlaiselle työlle. Toisessa päässä voi olla ensimmäinen luonnos, toisessa lause, joka tarvitsee vielä huomiota, ja keskelle jää tilaa seuraavalle pienelle päätökselle. Harjoittelu toimii samalla tavalla. Sen ei tarvitse ratkaista kaikkea kerralla, vaan sen pitää antaa meille paikka, johon voi palata, nähdä seuraava askel ja löytää riittävästi kärsivällisyyttä huomata, mikä muuttuu helpommaksi muutaman yrityksen jälkeen.",
      language: .finnish,
      length: .extended
    ),
    OfflineQuote(
      id: "estonian-rahulik-samm",
      title: "Rahulik samm",
      text: "Rahulik samm teeb järgmise ülesande selgemaks.",
      language: .estonian,
      length: .short
    ),
    OfflineQuote(
      id: "estonian-avatud-markmik",
      title: "Avatud märkmik",
      text: "Avatud märkmik ei lahenda rasket küsimust üksi, kuid aitab mõtetel leida korra ja suuna.",
      language: .estonian,
      length: .medium
    ),
    OfflineQuote(
      id: "estonian-vaikne-too",
      title: "Vaikne töö",
      text: "Edasiminek ei sünni tavaliselt ühe valju hetkega. See kasvab siis, kui avame sama lehe, parandame vea, loeme märkme läbi ja valime järgmise väikese ülesande. Kordamine teeb keerulised asjad tuttavamaks ning jätab tähelepanule rohkem ruumi.",
      language: .estonian,
      length: .long
    ),
    OfflineQuote(
      id: "estonian-pikk-laud",
      title: "Pikk laud",
      text: "Pikk laud on kasulik, sest sellel on ruumi eri liiki töö jaoks. Ühes otsas võib olla esimene visand, teises lause, mis vajab veel tähelepanu, ning keskele jääb ruumi järgmisele väikesele otsusele. Harjutamine toimib samamoodi. See ei pea kõike korraga lahendama, vaid peab andma meile koha, kuhu tagasi tulla, näha järgmist sammu ja leida piisavalt kannatlikkust, et märgata, mis muutub mõne katse järel lihtsamaks.",
      language: .estonian,
      length: .extended
    ),
    OfflineQuote(
      id: "icelandic-rolegt-skref",
      title: "Rólegt skref",
      text: "Rólegt skref gerir næsta verkefni skýrara.",
      language: .icelandic,
      length: .short
    ),
    OfflineQuote(
      id: "icelandic-opin-minnisbok",
      title: "Opin minnisbók",
      text: "Opin minnisbók leysir ekki erfiða spurningu ein og sér, en hún hjálpar hugsunum að finna röð og stefnu.",
      language: .icelandic,
      length: .medium
    ),
    OfflineQuote(
      id: "icelandic-hljoðlaust-verk",
      title: "Hljóðlaust verk",
      text: "Framfarir verða sjaldan til á einni háværri stundu. Þær vaxa þegar við opnum sömu síðuna, leiðréttum villu, lesum minnisblað og veljum næsta litla verkefni. Endurtekning gerir erfið atriði kunnuglegri og skilur eftir meira rými fyrir athygli.",
      language: .icelandic,
      length: .long
    ),
    OfflineQuote(
      id: "icelandic-langt-bord",
      title: "Langt borð",
      text: "Langt borð er gagnlegt því þar er pláss fyrir ólíka vinnu. Við annan endann getur verið fyrsta uppkastið, við hinn setning sem þarf enn athygli, og á miðjunni verður pláss fyrir næstu litlu ákvörðun. Æfing virkar á sama hátt. Hún þarf ekki að leysa allt í einu, heldur að gefa okkur stað til að snúa aftur á, sjá næsta skref og finna næga þolinmæði til að taka eftir því sem verður auðveldara eftir nokkrar tilraunir.",
      language: .icelandic,
      length: .extended
    ),
    OfflineQuote(
      id: "hiragana-small-practice",
      title: "ちいさなれんしゅう",
      text: "ちいさなれんしゅうをかさねると、つぎのいっぽがすこしみえやすくなる。",
      language: .japaneseHiragana,
      length: .short
    ),
    OfflineQuote(
      id: "hiragana-open-note",
      title: "ひらいたのーと",
      text: "ひらいたのーとはむずかしいこたえをすぐにはださないけれど、かんがえをわけて、つぎにかえるしるしをのこしてくれる。",
      language: .japaneseHiragana,
      length: .medium
    ),
    OfflineQuote(
      id: "hiragana-quiet-work",
      title: "しずかなしごと",
      text: "すすみかたはいつもおおきなできごとにはならない。おなじぺーじをひらき、ひとつのことばをなおし、ひとつのまちがいをたしかめ、つぎのためのめじるしをのこす。そんなくりかえしが、むずかしいところをすこしずつなじみのあるものにしていく。",
      language: .japaneseHiragana,
      length: .long
    ),
    OfflineQuote(
      id: "hiragana-long-table",
      title: "ながいつくえ",
      text: "ながいつくえがべんりなのは、いろいろなしごとにばしょをのこせるからだ。こちらにはさいしょのめも、あちらにはまだなおしたいことば、まんなかにはつぎのちいさなけっていのためのあきがある。れんしゅうもおなじで、いちどにぜんぶをとくより、もどれるばしょとみえるいっぽをつくり、くりかえすうちにやりやすくなったことをみつけていく。",
      language: .japaneseHiragana,
      length: .extended
    ),
    OfflineQuote(
      id: "katakana-small-step",
      title: "チイサナステップ",
      text: "チイサナステップデモツギノページヲアケル。",
      language: .japaneseKatakana,
      length: .short
    ),
    OfflineQuote(
      id: "katakana-open-note",
      title: "オープンノート",
      text: "ノートニヒトツノメモヲノコスト、ツギニモドルマデノミチガミエヤスクナル。",
      language: .japaneseKatakana,
      length: .medium
    ),
    OfflineQuote(
      id: "katakana-calm-work",
      title: "カームワーク",
      text: "ヨイリズムハイソグタメノモノデハナイ。ヒトツノページヲヒライテ、ヒトツノミスヲナオシテ、ツギノステップヲメモニノコス。ソノクリカエシガムズカシイタスクヲスコシズツミヂカニスル。",
      language: .japaneseKatakana,
      length: .long
    ),
    OfflineQuote(
      id: "katakana-long-table",
      title: "ロングテーブル",
      text: "ナガイテーブルニハイロイロナタスクヲオケル。ヒトツノハシニハドラフト、モウヒトツノハシニハマダカクニンガヒツヨウナメモ、ソシテマンナカニハツギノステップノタメノアキバガアル。レッスンモオナジヨウニススム。スベテノモンダイヲイチドニトクノデハナク、モドルバショトミエルステップト、ナンドモカクニンスルタメノジカンヲツクル。",
      language: .japaneseKatakana,
      length: .extended
    ),
    OfflineQuote(
      id: "romaji-tomorrow-note",
      title: "Ashita no memo",
      text: "Kyou no memo wa, ashita no hajime no basho o tsukuru.",
      language: .japaneseRomaji,
      length: .short
    ),
    OfflineQuote(
      id: "romaji-quiet-order",
      title: "Shizuka na junban",
      text: "Shizuka ni tsukutta junban wa, omoi tsuki o wake, tsugi ni kaku koto o mitsukeyasuku suru.",
      language: .japaneseRomaji,
      length: .medium
    ),
    OfflineQuote(
      id: "romaji-daily-practice",
      title: "Mainichi no renshuu",
      text: "Mainichi no renshuu wa, hayaku kotae ni todoku tame dake no jikan de wa nai. Mado o akete, memo o yomi, machigaeta basho o naoshite, tsugi ni tamesu koto o erabu. Sono chiisana kurikaeshi ga, muzukashii tasku o sukoshi zutsu chikaku suru.",
      language: .japaneseRomaji,
      length: .long
    ),
    OfflineQuote(
      id: "romaji-open-table",
      title: "Aketa teeburu",
      text: "Nagaku tsuzuku teeburu ni wa, iroiro na shigoto no basho ga aru. Hitotsu no hashi ni wa mada awai dorafuto, mou hitotsu no hashi ni wa kakunin o matsu memo, soshite mannaka ni wa tsugi no sentaku no tame no aki ga aru. Renshuu mo onaji you ni susumu. Subete no mondai o ichido ni tokou to suru no de wa naku, modoru basho to mieru ippo o tsukuri, sukoshi jikan o totte, nani ga yasuku natta ka o mite iku.",
      language: .japaneseRomaji,
      length: .extended
    ),
    OfflineQuote(
      id: "long-table",
      title: "Long Table",
      text: "A long table is useful because it makes room for more than one kind of work. One end can hold the rough sketch, another can hold the sentence that still needs care, and the middle can stay clear enough for the next small decision. Practice works in much the same way. It does not ask you to solve every difficulty at once. It asks for a place to return, a visible next step, and enough patience to notice what becomes easier after you have met it a few more times.",
      language: .english,
      length: .extended
    ),
    OfflineQuote(
      id: "mesa-larga",
      title: "Mesa larga",
      text: "Una mesa larga sirve porque deja espacio para más de una clase de trabajo. En un extremo puede quedar el primer borrador, en otro una frase que todavía necesita cuidado, y en el centro una zona libre para la siguiente decisión pequeña. La práctica se parece a esa mesa. No pide resolver cada dificultad de una vez. Pide un lugar al que volver, un paso visible y la paciencia suficiente para notar qué parte se vuelve más fácil después de encontrarla varias veces.",
      language: .spanish,
      length: .extended
    ),
    OfflineQuote(
      id: "langer-tisch",
      title: "Langer Tisch",
      text: "Ein langer Tisch ist hilfreich, weil er Platz für verschiedene Arten von Arbeit schafft. An einem Ende liegt vielleicht der erste Entwurf, am anderen ein Satz, der noch Sorgfalt braucht, und in der Mitte bleibt Raum für den nächsten kleinen Entschluss. Übung funktioniert ähnlich. Sie verlangt nicht, jede Schwierigkeit sofort zu lösen. Sie braucht einen Ort, zu dem man zurückkehrt, einen sichtbaren nächsten Schritt und genug Geduld, um zu bemerken, was nach mehreren Versuchen leichter geworden ist.",
      language: .german,
      length: .extended
    ),
    OfflineQuote(
      id: "grande-table",
      title: "Grande table",
      text: "Une grande table est utile parce qu'elle laisse de la place à plusieurs formes de travail. À une extrémité, il peut y avoir le premier croquis; à l'autre, une phrase qui demande encore de l'attention; au milieu, un espace clair pour la prochaine petite décision. La pratique ressemble à cette table. Elle ne demande pas de résoudre chaque difficulté immédiatement. Elle demande un endroit où revenir, une étape visible et assez de patience pour remarquer ce qui devient plus simple après plusieurs rencontres.",
      language: .french,
      length: .extended
    ),
    OfflineQuote(
      id: "tavolo-lungo",
      title: "Tavolo lungo",
      text: "Un tavolo lungo è utile perché lascia spazio a più forme di lavoro. A un'estremità può restare il primo schizzo, all'altra una frase che richiede ancora cura, mentre al centro rimane spazio libero per la prossima piccola decisione. La pratica assomiglia a quel tavolo. Non chiede di risolvere ogni difficoltà in una sola volta. Chiede un luogo a cui tornare, un passo visibile e abbastanza pazienza per accorgersi di ciò che diventa più semplice dopo diversi incontri.",
      language: .italian,
      length: .extended
    ),
    OfflineQuote(
      id: "mesa-comprida",
      title: "Mesa comprida",
      text: "Uma mesa comprida é útil porque deixa espaço para mais de uma forma de trabalho. Numa ponta pode ficar o primeiro rascunho, na outra uma frase que ainda pede cuidado, e no meio permanece espaço livre para a próxima decisão pequena. A prática parece-se com essa mesa. Não exige resolver cada dificuldade de uma só vez. Pede um lugar para onde voltar, um passo visível e paciência suficiente para perceber o que se torna mais fácil depois de alguns encontros.",
      language: .portuguese,
      length: .extended
    ),
    OfflineQuote(
      id: "长桌",
      title: "长桌",
      text: "一张长桌的好处，是能给不同阶段的工作留出位置。一端可以放着还很粗糙的草稿，另一端可以放着仍需斟酌的句子，中间则留给下一步的小决定。练习也像这样一张桌子。它不要求你立刻解决所有困难，只需要你留下一处可以回来继续的地方，看见眼前可做的一步，并有足够耐心去发现：那些反复遇见的问题，终会在不知不觉间变得更容易处理。",
      language: .simplifiedChinese,
      length: .extended
    ),
  ]

  static func quotes(for language: TypingLanguage, length: QuoteLength = .all) -> [OfflineQuote] {
    quotes.filter { $0.language == language && (length == .all || $0.length == length) }
  }

  static func nextQuote(
    from candidates: [OfflineQuote], currentID: String?, allowsRepeat: Bool, index: Int? = nil
  ) -> OfflineQuote? {
    let available =
      allowsRepeat || candidates.count < 2
      ? candidates
      : candidates.filter { $0.id != currentID }
    guard !available.isEmpty else { return nil }
    let selection = index.map { abs($0) % available.count } ?? Int.random(in: 0..<available.count)
    return available[selection]
  }

  static func generatedPrompt(
    wordCount: Int, language: TypingLanguage = .english, englishVariant: EnglishVariant = .american,
    mixedLanguageComponents: [TypingLanguage] = TypingLanguage.defaultMixedComponents,
    contentOptions: ContentOptions = .init(), usesZipfFrequency: Bool = false
  ) -> String {
    if language.isCodeLanguage {
      return CodePracticeContent.prompt(language: language, targetTokenCount: wordCount)
    }
    return StarterLexicon.prompt(
      wordCount: max(1, wordCount), language: language, englishVariant: englishVariant,
      mixedLanguageComponents: mixedLanguageComponents, contentOptions: contentOptions,
      usesZipfFrequency: usesZipfFrequency)
  }

  static func timedPrompt(
    seconds: TimeInterval, language: TypingLanguage = .english,
    englishVariant: EnglishVariant = .american,
    mixedLanguageComponents: [TypingLanguage] = TypingLanguage.defaultMixedComponents,
    contentOptions: ContentOptions = .init(), usesZipfFrequency: Bool = false
  ) -> String {
    // Enough text for a very fast two-minute practice without recycling the visible prompt.
    generatedPrompt(
      wordCount: max(300, Int(ceil(seconds / 60 * 240))), language: language,
      englishVariant: englishVariant, mixedLanguageComponents: mixedLanguageComponents,
      contentOptions: contentOptions, usesZipfFrequency: usesZipfFrequency)
  }
}

/// The code-language selection catalog is derived from the reference project's
/// public language identifiers. Labels and every practice fragment below are
/// Typebar-authored; no upstream corpus, source code or asset is imported.
enum CodeLanguageCatalog {
  static let displayNames: [TypingLanguage: String] = [
    .codePython: "Python", .codePython1k: "Python 1k", .codePython2k: "Python 2k",
    .codePython5k: "Python 5k", .codeFSharp: "F#", .codeC: "C", .codeCSharp: "C#",
    .codeCSS: "CSS", .codeCPP: "C++", .codeDart: "Dart", .codeBrainfck: "Brainf*ck",
    .codeJavaScript: "JavaScript", .codeJavaScript1k: "JavaScript 1k",
    .codeJavaScriptReact: "JavaScript React", .codeJule: "Jule", .codeJulia: "Julia",
    .codeHaskell: "Haskell", .codeHTML: "HTML", .codeNim: "Nim", .codeNix: "Nix",
    .codePascal: "Pascal", .codeJava: "Java", .codeKotlin: "Kotlin", .codeGo: "Go",
    .codeRockstar: "Rockstar", .codeRust: "Rust", .codeRuby: "Ruby", .codeR: "R",
    .codeR2k: "R 2k", .codeSwift: "Swift", .codeScala: "Scala", .codeBash: "Bash",
    .codePowerShell: "PowerShell", .codeLua: "Lua", .codeLuau: "Luau",
    .codeLaTeX: "LaTeX", .codeTypst: "Typst", .codeMATLAB: "MATLAB", .codeSQL: "SQL",
    .codePerl: "Perl", .codePHP: "PHP", .codeVim: "Vim", .codeVimscript: "Vimscript",
    .codeOpenCL: "OpenCL", .codeVisualBasic: "Visual Basic", .codeArduino: "Arduino",
    .codeSystemVerilog: "SystemVerilog", .codeElixir: "Elixir", .codeGleam: "Gleam",
    .codeZig: "Zig", .codeGDScript: "GDScript", .codeGDScript2: "GDScript 2",
    .codeAssembly: "Assembly", .codeV: "V", .codeOok: "Ook!", .codeTypeScript: "TypeScript",
    .codeCOBOL: "COBOL", .codeClojure: "Clojure", .codeCommonLisp: "Common Lisp",
    .codeErlang: "Erlang", .codeOCaml: "OCaml", .codeOdin: "Odin", .codeFortran: "Fortran",
    .codeABAP: "ABAP", .codeABAP1k: "ABAP 1k", .codeYoptaScript: "YoptaScript",
    .codeCUDA: "CUDA", .codeVHDL: "VHDL", .code6502Assembly: "6502 Assembly",
  ]
}

/// Short, self-authored fragments keep code input, indentation and replay
/// observable without importing an upstream corpus or programming-language asset.
enum CodePracticeContent {
  static func prompt(language: TypingLanguage, targetTokenCount: Int) -> String {
    let blocks = blocks(for: language)
    let blockCount = max(1, Int(ceil(Double(max(targetTokenCount, 1)) / 8)))
    return (0..<blockCount).map { blocks[$0 % blocks.count] }.joined(separator: "\n")
  }

  private static func blocks(for language: TypingLanguage) -> [String] {
    switch language {
    case .codeSwift:
      ["let total = values.reduce(0, +)", "for item in items {\n\tprint(item)\n}", "if total > limit {\n\treturn total\n}"]
    case .codeJavaScript, .codeJavaScript1k, .codeJavaScriptReact, .codeTypeScript:
      ["const total = values.reduce((sum, value) => sum + value, 0);", "for (const item of items) {\n\tconsole.log(item);\n}", "if (total > limit) {\n\treturn total;\n}"]
    case .codePython, .codePython1k, .codePython2k, .codePython5k, .codeNim,
      .codeGDScript, .codeGDScript2, .codeYoptaScript:
      ["total = sum(values)", "for item in items:\n\tprint(item)", "if total > limit:\n\treturn total"]
    case .codeHTML:
      ["<main class=\"practice\">", "<p>steady typing</p>", "</main>"]
    case .codeCSS:
      [".practice {", "\tdisplay: grid;", "\tgap: 1rem;\n}"]
    case .codeSQL:
      ["SELECT value", "FROM practice_entries", "WHERE active = 1;"]
    case .codeBash, .codePowerShell, .codeVim, .codeVimscript:
      ["total=0", "for item in \"${items[@]}\"; do\n\techo \"$item\"\ndone", "echo \"$total\""]
    case .codeLaTeX, .codeTypst:
      ["#set text(size: 11pt)", "#align(center)[", "  steady practice\n]"]
    case .codeBrainfck, .codeOok:
      ["++[>++<-]", ">.+.", "<[-]"]
    case .codeHaskell, .codeFSharp, .codeOCaml, .codeErlang, .codeElixir,
      .codeGleam, .codeClojure, .codeCommonLisp, .codeScala:
      ["total = sum values", "items |> List.iter (fun item ->\n\tprint item)", "total"]
    case .codeVisualBasic, .codeCOBOL, .codeFortran, .codePascal, .codeABAP, .codeABAP1k:
      ["total = 0", "FOR EACH item IN items\n\tPRINT item\nNEXT item", "PRINT total"]
    case .codeVHDL:
      [
        "entity pulse_gate is\n\tport (clock : in bit; enabled : in bit; output : out bit);\nend entity;",
        "architecture simple of pulse_gate is\n\tbegin\n\t\toutput <= clock and enabled;\nend architecture;"
      ]
    case .codeCUDA:
      [
        "__global__ void scale(int *values, int count) {\n\tint index = blockIdx.x * blockDim.x + threadIdx.x;\n\tif (index < count) {\n\t\tvalues[index] = values[index] * 2;\n\t}\n}",
        "scale<<<blocks, threads>>>(values, count);\ncudaDeviceSynchronize();"
      ]
    case .code6502Assembly:
      ["LDA #$00\nSTA $0200\nINX\nSTX $0201", "loop:\n\tDEX\n\tBNE loop\n\tRTS"]
    default:
      ["let total = collect(values);", "for item in items {\n\tprint(item);\n}", "return total;"]
    }
  }
}

enum NoSpaceWordBoundaryPolicy {
  /// Returns the end position of each source word after it has been
  /// transformed and concatenated. The session needs this explicit metadata
  /// because no-space prompts intentionally contain no separators.
  static func wordLengths(
    source: String, language: TypingLanguage = .english, modifiers: [TestModifier],
    transformedPrompt: String
  ) -> [Int] {
    var words: [String]
    if language.isNoSpaceLanguage {
      guard let parsed = noSpaceLanguageWords(in: source, language: language) else { return [] }
      words = parsed
    } else {
      guard modifiers.contains(.noSpaces) else { return [] }
      words = source.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }
    // `backwards` runs after space removal in the native transform, so the
    // flattened output contains source words in reverse order.
    if modifiers.contains(.backwards) { words.reverse() }
    let lengths = words.map {
      TestModifierPolicy.transformed($0, modifiers: modifiers).count
    }
    guard lengths.reduce(0, +) == transformedPrompt.count else { return [] }
    return lengths
  }

  /// Parses only prompts which can be completely described by Typebar's own
  /// no-space lexicons. A number or punctuation suffix remains attached to
  /// its generated word. Any unknown text deliberately falls back to
  /// character-level metrics instead of inventing a word boundary.
  private static func noSpaceLanguageWords(
    in source: String, language: TypingLanguage
  ) -> [String]? {
    let lexicon = (StarterLexicon.noSpaceWords(for: language) ?? []).map { Array($0) }
      .sorted { $0.count > $1.count }
    guard !lexicon.isEmpty else { return nil }
    let characters = Array(source)
    var words: [String] = []
    var index = 0
    while index < characters.count {
      guard let word = lexicon.first(where: { candidate in
        let end = index + candidate.count
        guard end <= characters.count else { return false }
        return characters[index..<end].elementsEqual(candidate)
      }) else { return nil }
      var end = index + word.count
      while end < characters.count, !characters[end].isLetter { end += 1 }
      words.append(String(characters[index..<end]))
      index = end
    }
    return words
  }

  static func endIndices(for wordLengths: [Int]) -> [Int] {
    var end = 0
    return wordLengths.map { length in
      end += length
      return end
    }
  }

  /// Reconstructs the visible target for each original word after a safe
  /// no-space transformation. These are deliberately slices of the rendered
  /// prompt, rather than the source strings, so result reviews compare against
  /// exactly what the user was asked to type.
  static func targetWords(for wordLengths: [Int], in transformedPrompt: String) -> [String] {
    guard !wordLengths.isEmpty, wordLengths.allSatisfy({ $0 > 0 }) else { return [] }
    let characters = Array(transformedPrompt)
    var start = 0
    var words: [String] = []
    for length in wordLengths {
      let end = start + length
      guard end <= characters.count else { return [] }
      words.append(String(characters[start..<end]))
      start = end
    }
    return start == characters.count ? words : []
  }
}

struct TestSessionFactory {
  static func make(
    configuration: TestConfiguration,
    customText: String = "",
    quote: OfflineQuote? = nil,
    streamPrompt: String? = nil
  ) -> TypingSession {
    let prompt: String
    var sectionEndIndices: [Int] = []
    var noSpaceBoundarySource: String?
    if configuration.mode != .custom, let streamPrompt {
      prompt = streamPrompt
    } else if configuration.mode != .custom,
      let streamPrompt = TypebarStreamContent.prompt(configuration: configuration)
    {
      prompt = streamPrompt
    } else {
      switch configuration.mode {
      case .time:
        prompt = OfflineContent.timedPrompt(
          seconds: configuration.duration ?? 30, language: configuration.language,
          englishVariant: configuration.englishVariant,
          mixedLanguageComponents: configuration.mixedLanguageComponents,
          contentOptions: configuration.contentOptions,
          usesZipfFrequency: configuration.modifiers.contains(.zipf))
      case .words:
        prompt = OfflineContent.generatedPrompt(
          wordCount: configuration.wordLimit ?? 25, language: configuration.language,
          englishVariant: configuration.englishVariant,
          mixedLanguageComponents: configuration.mixedLanguageComponents,
          contentOptions: configuration.contentOptions,
          usesZipfFrequency: configuration.modifiers.contains(.zipf))
      case .quote:
        prompt =
          quote?.text ?? OfflineContent.quotes(for: configuration.language).first?.text
          ?? OfflineContent.quotes(for: .english)[0].text
      case .zen:
        // Zen renders and scores only text entered locally by the user. It
        // intentionally has no generated target prompt or imported content.
        prompt = ""
      case .custom:
        let source =
          !CustomTextPolicy.isValid(customText)
          ? "Write your own text in the configuration panel before starting a custom test."
          : customText
        if configuration.customTextCompletion == .sections {
          let sections = CustomTextPolicy.sections(in: source)
          let limit = min(
            max(configuration.customTextSectionLimit ?? sections.count, 1), sections.count)
          let transformedSections = sections.prefix(limit).map {
            TestModifierPolicy.transformed($0, modifiers: configuration.modifiers)
          }
          noSpaceBoundarySource = sections.prefix(limit).joined(separator: " ")
          let separator =
            !configuration.language.usesSpaceDelimitedWords || configuration.modifiers.contains(.noSpaces)
            ? "" : configuration.modifiers.contains(.underscoreSeparators) ? "_" : " "
          prompt = transformedSections.joined(separator: separator)
          var length = 0
          sectionEndIndices = transformedSections.enumerated().map { index, section in
            length += section.count
            defer { length += index < transformedSections.count - 1 ? separator.count : 0 }
            return length
          }
        } else {
          prompt = CustomTextOrderPolicy.prompt(
            from: source, ordering: configuration.customTextOrdering)
        }
      }
    }
    let transformedPrompt =
      configuration.mode == .custom && configuration.customTextCompletion == .sections
      ? prompt
      : TestModifierPolicy.transformed(prompt, modifiers: configuration.modifiers)
    let noSpaceWordLengths = NoSpaceWordBoundaryPolicy.wordLengths(
      source: noSpaceBoundarySource ?? prompt, language: configuration.language,
      modifiers: configuration.modifiers,
      transformedPrompt: transformedPrompt)
    let noSpaceTargetWords = NoSpaceWordBoundaryPolicy.targetWords(
      for: noSpaceWordLengths, in: transformedPrompt)
    let repeats =
      configuration.mode == .custom && [.time, .words].contains(configuration.customTextCompletion)
    let initialPrompt: String
    let initialNoSpaceWordEndIndices: [Int]
    let initialNoSpaceTargetWords: [String]
    if repeats {
      let separator = configuration.modifiers.contains(.noSpaces) ? "" : " "
      initialPrompt = transformedPrompt + separator + transformedPrompt
      initialNoSpaceWordEndIndices = NoSpaceWordBoundaryPolicy.endIndices(
        for: noSpaceWordLengths + noSpaceWordLengths)
      initialNoSpaceTargetWords = noSpaceTargetWords + noSpaceTargetWords
    } else {
      initialPrompt = transformedPrompt
      initialNoSpaceWordEndIndices = NoSpaceWordBoundaryPolicy.endIndices(for: noSpaceWordLengths)
      initialNoSpaceTargetWords = noSpaceTargetWords
    }
    return TypingSession(
      configuration: configuration, prompt: initialPrompt,
      repeatingPrompt: repeats ? transformedPrompt : nil, sectionEndIndices: sectionEndIndices,
      noSpaceWordEndIndices: initialNoSpaceWordEndIndices,
      noSpaceTargetWords: initialNoSpaceTargetWords,
      repeatingNoSpaceWordLengths: repeats ? noSpaceWordLengths : [],
      repeatingNoSpaceTargetWords: repeats ? noSpaceTargetWords : [])
  }
}

enum TypebarStreamContent {
  static func prompt(configuration: TestConfiguration) -> String? {
    let count: Int
    switch configuration.mode {
    case .time: count = max(300, Int(ceil((configuration.duration ?? 30) / 60 * 240)))
    case .words: count = configuration.wordLimit ?? 25
    case .quote: count = 60
    case .zen: count = 10_000
    case .custom: return nil
    }
    let tokens: [String]
    if configuration.modifiers.contains(.binaryStream) {
      tokens = (0..<count).map { index in
        let value = String(index % 256, radix: 2)
        return String(repeating: "0", count: max(0, 8 - value.count)) + value
      }
    } else if configuration.modifiers.contains(.accountingStream) {
      tokens = (0..<count).map { index in
        let cents = (index * 7_319 + 4_207) % 9_900_000 + 10_000
        let whole = cents / 100
        let fraction = cents % 100
        let grouped = String(whole).reversed().enumerated().map { offset, digit in
          offset > 0 && offset.isMultiple(of: 3) ? ",\(digit)" : String(digit)
        }.reversed().joined()
        return "\(grouped).\(String(format: "%02d", fraction))"
      }
    } else if configuration.modifiers.contains(.hexadecimalStream) {
      tokens = (0..<count).map {
        "0x" + String(($0 * 37 + 11) % 65_536, radix: 16, uppercase: true)
      }
    } else if configuration.modifiers.contains(.symbolStream) {
      let patterns = ["!@#", "$%^", "&*+", "=?/", "[]{}", "<>~"]
      tokens = (0..<count).map { patterns[$0 % patterns.count] }
    } else if configuration.modifiers.contains(.asciiStream) {
      tokens = (0..<count).map { index in
        let length = index % 9 + 1
        return String((0..<length).compactMap { offset in
          UnicodeScalar(33 + ((index * 29 + offset * 17) % 94)).map(Character.init)
        })
      }
    } else if configuration.modifiers.contains(.specialCharacterStream) {
      let characters = Array("`~!@#$%^&*()-_=+{}[]|\\/?:;,.<>")
      tokens = (0..<count).map { index in
        let length = index % 6 + 1
        return String((0..<length).map { characters[(index * 11 + $0 * 7) % characters.count] })
      }
    } else if configuration.modifiers.contains(.gibberishStream) {
      tokens = (0..<count).map { index in
        let length = index * 5 % 7 + 1
        return String((0..<length).compactMap { offset in
          UnicodeScalar(97 + ((index * 19 + offset * 11 + 3) % 26)).map(Character.init)
        })
      }
    } else if configuration.modifiers.contains(.poetryStream) {
      let verses = """
      dawn enters the room without asking
      a cup cools beside an unfinished page
      small careful motions gather into a path
      the window keeps a quiet measure of rain
      each returning line makes the hand less afraid
      """.split(whereSeparator: \.isWhitespace).map(String.init)
      tokens = (0..<count).map { verses[$0 % verses.count] }
    } else if configuration.modifiers.contains(.referenceStream) {
      let sections = [
        "A watershed gathers rain from many small places and carries it through streams toward a larger body of water",
        "A compass points along a magnetic field and helps a traveler compare one direction with another",
        "A library catalog connects a title with its author subject and location so readers can find a shared record",
      ]
      let words = sections.joined(separator: " ").split(separator: " ").map(String.init)
      tokens = (0..<count).map { words[$0 % words.count] }
    } else if configuration.modifiers.contains(.arrowStream) {
      let directions = ["↑", "→", "↓", "←", "→", "↑", "←", "↓"]
      tokens = (0..<count).map { directions[$0 % directions.count] }
    } else if configuration.modifiers.contains(.ipv4Stream) {
      tokens = (0..<count).map { index in
        "10.\((index * 17 + 3) % 256).\((index * 43 + 29) % 256).\((index * 71 + 7) % 256)"
      }
    } else if configuration.modifiers.contains(.ipv6Stream) {
      tokens = (0..<count).map { index in
        let base = index * 4099 + 31
        return (0..<4).map { offset in
          String((base + offset * 257) % 65_536, radix: 16, uppercase: true)
        }.joined(separator: ":")
      }
    } else if configuration.modifiers.contains(.pseudolangStream) {
      let starts = ["br", "cl", "dr", "fr", "gl", "pr", "sh", "tr"]
      let vowels = ["a", "e", "i", "o", "u", "ae", "ou", "ia"]
      let ends = ["m", "n", "r", "s", "th", "v", "x", "z"]
      tokens = (0..<count).map { index in
        let start = starts[index % starts.count]
        let vowel = vowels[(index * 3 + 1) % vowels.count]
        let end = ends[(index * 5 + 2) % ends.count]
        return start + vowel + end
      }
    } else if configuration.modifiers.contains(.morseStream) {
      let codes: [Character: String] = [
        "a": ".-", "b": "-...", "c": "-.-.", "d": "-..", "e": ".", "f": "..-.", "g": "--.",
        "h": "....", "i": "..", "j": ".---", "k": "-.-", "l": ".-..", "m": "--", "n": "-.",
        "o": "---", "p": ".--.", "q": "--.-", "r": ".-.", "s": "...", "t": "-", "u": "..-",
        "v": "...-", "w": ".--", "x": "-..-", "y": "-.--", "z": "--..",
      ]
      let source = StarterLexicon.words
      tokens = (0..<count).map { index in
        source[index % source.count].compactMap { codes[$0] }.joined(separator: "/")
      }
    } else {
      return nil
    }
    return tokens.joined(separator: " ")
  }
}

enum CustomTextOrderPolicy {
  static func prompt(
    from text: String, ordering: CustomTextOrdering,
    random: () -> Int = { Int.random(in: Int.min...Int.max) }
  ) -> String {
    let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard tokens.count > 1 else { return text }
    switch ordering {
    case .inOrder:
      return text
    case .shuffled:
      let rotation = Int(random().magnitude % UInt(tokens.count))
      return Array(tokens[rotation...] + tokens[..<rotation]).reversed().joined(separator: " ")
    case .random:
      return (0..<max(tokens.count, 64)).map { _ in
        tokens[Int(random().magnitude % UInt(tokens.count))]
      }.joined(separator: " ")
    }
  }
}
