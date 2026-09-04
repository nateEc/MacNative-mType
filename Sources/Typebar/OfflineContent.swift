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
  /// Returns the end position of each original space-delimited word after it
  /// has been transformed and concatenated. The session needs this explicit
  /// metadata because no-space prompts intentionally contain no separators.
  static func wordLengths(
    source: String, modifiers: [TestModifier], transformedPrompt: String
  ) -> [Int] {
    guard modifiers.contains(.noSpaces) else { return [] }
    var words = source.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    // `backwards` runs after space removal in the native transform, so the
    // flattened output contains source words in reverse order.
    if modifiers.contains(.backwards) { words.reverse() }
    let lengths = words.map {
      TestModifierPolicy.transformed($0, modifiers: modifiers).count
    }
    guard lengths.reduce(0, +) == transformedPrompt.count else { return [] }
    return lengths
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
      source: noSpaceBoundarySource ?? prompt, modifiers: configuration.modifiers,
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
