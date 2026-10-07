import Foundation

/// A process-local time source, never a persisted or user-visible date.
struct PaceCaretClock {
  let now: () -> TimeInterval

  static var system: Self {
    let clock = SuspendingClock()
    let origin = clock.now
    return .init {
      let duration = origin.duration(to: clock.now).components
      return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }
  }
}

struct PaceCaretPosition: Equatable {
  let word: Int
  let letter: Int
}

struct PaceCaretFrame: Equatable {
  let from: PaceCaretPosition
  let target: PaceCaretPosition
  let fraction: Double
  var stepDuration: TimeInterval = 0
  var sequence: Double = 0
}

struct PaceCaretGlyphAnchor: Equatable {
  let glyphIndex: Int
  let after: Bool
}

/// Independent, transient word catalog. Logical pacing uses UTF-16; native
/// geometry coalesces those positions onto actual grapheme boundaries.
struct PaceCaretCatalog {
  struct Word {
    let raw: String
    let length: Int
    let correctionLength: Int
    let glyphStart: Int
    let boundaries: [Int]

    init(_ raw: String, glyphStart: Int) {
      self.raw = raw
      correctionLength = raw.utf16.count
      let units = Array(raw.utf16)
      let hasCommit = units.last == 32 || units.last == 10
      let body = String(decoding: hasCommit ? Array(units.dropLast()) : units, as: UTF16.self)
      length = body.utf16.count
      self.glyphStart = glyphStart
      var offsets: [Int] = []
      for (index, character) in body.enumerated() {
        offsets += Array(repeating: glyphStart + index, count: String(character).utf16.count)
      }
      offsets.append(glyphStart + body.count)
      boundaries = offsets
    }
  }

  private(set) var words: [Word] = []
  private(set) var steps: [Int] = [0]
  private var glyphCount = 0

  init(prompt: String, noSpaceWords: [String]? = nil) {
    if let noSpaceWords { appendWords(noSpaceWords) }
    else { append(prompt) }
  }

  mutating func appendWords(_ rawWords: [String]) {
    for raw in rawWords {
      let word = Word(raw, glyphStart: glyphCount)
      words.append(word)
      steps.append(steps.last! + word.length + 1)
      glyphCount += raw.count
    }
  }

  mutating func append(_ text: String) {
    guard !text.isEmpty else { return }
    var combined = text
    if let last = words.last, last.raw.utf16.last != 32, last.raw.utf16.last != 10 {
      combined = last.raw + text
      glyphCount = last.glyphStart
      words.removeLast(); steps.removeLast()
    }
    let units = Array(combined.utf16)
    var start = 0, rawWords: [String] = []
    for index in units.indices where units[index] == 32 || units[index] == 10 {
      rawWords.append(String(decoding: units[start...index], as: UTF16.self)); start = index + 1
    }
    if start < units.count { rawWords.append(String(decoding: units[start...], as: UTF16.self)) }
    appendWords(rawWords)
  }

  func position(at step: Int) -> PaceCaretPosition {
    var lower = 0, upper = steps.count
    while lower < upper {
      let middle = lower + (upper - lower) / 2
      if steps[middle] <= step { lower = middle + 1 } else { upper = middle }
    }
    let word = max(0, lower - 1)
    return .init(word: word, letter: step - steps[word])
  }

  func glyphIndex(at position: PaceCaretPosition) -> Int? {
    guard words.indices.contains(position.word) else { return nil }
    let boundaries = words[position.word].boundaries
    guard boundaries.indices.contains(position.letter) else { return nil }
    return boundaries[position.letter]
  }

  func glyphAnchor(at position: PaceCaretPosition) -> PaceCaretGlyphAnchor? {
    guard words.indices.contains(position.word) else { return nil }
    let word = words[position.word]
    guard position.letter >= 0, position.letter <= word.length else { return nil }
    if position.letter == word.length, word.length > 0 {
      return .init(glyphIndex: word.boundaries[word.length - 1], after: true)
    }
    return .init(glyphIndex: word.boundaries[position.letter], after: false)
  }

  /// The previous logical target, not the previous rendered position. A
  /// pending correction can make a frame's interpolation start differ.
  func predecessorAnchor(before position: PaceCaretPosition) -> PaceCaretGlyphAnchor? {
    guard words.indices.contains(position.word), position.letter >= 0,
      position.letter <= words[position.word].length else { return nil }
    let step = steps[position.word] + position.letter
    guard step > 0 else { return nil }
    return glyphAnchor(at: self.position(at: step - 1))
  }
}

/// Absolute deadlines, not a chain of elapsed-time additions. Fast-forward
/// is bounded by the catalog, so enormous finite WPM never loops per unit.
struct PaceCaretProgress {
  private(set) var catalog: PaceCaretCatalog
  let wpm: Double
  private let interval: TimeInterval
  private let clock: PaceCaretClock
  private var startedAt: TimeInterval?
  private var observedAt: TimeInterval?
  private var processedSteps = 0.0
  private var currentStep = 0
  private var fromStep = 0
  private var correction = 0
  private var wrongWords = Set<Int>()
  private var exhausted = false

  init?(wpm: Double, catalog: PaceCaretCatalog, clock: PaceCaretClock = .system) {
    guard PaceGuidePolicy.validTarget(wpm) != nil, !catalog.words.isEmpty else { return nil }
    self.wpm = wpm
    interval = 12 / wpm
    self.catalog = catalog
    self.clock = clock
  }

  mutating func append(_ text: String) { catalog.append(text) }
  mutating func appendWords(_ words: [String]) { catalog.appendWords(words) }

  mutating func start(at time: TimeInterval? = nil, blind: Bool) {
    let time = time ?? clock.now()
    guard startedAt == nil, time.isFinite else { return }
    startedAt = time
    advance(to: time, blind: blind)
  }

  mutating func handleCommit(word: Int, correct: Bool, blind: Bool) {
    guard !exhausted, !blind, catalog.words.indices.contains(word) else { return }
    let length = catalog.words[word].correctionLength
    if correct {
      if wrongWords.remove(word) != nil { correction -= length }
    } else if wrongWords.insert(word).inserted { correction += length }
  }

  mutating func advance(to time: TimeInterval? = nil, blind: Bool) {
    let time = time ?? clock.now()
    guard !exhausted, let startedAt, time.isFinite, (time - startedAt).isFinite else { return }
    let now = max(time, observedAt ?? startedAt)
    observedAt = now
    let elapsed = max(0, now - startedAt)
    var due = floor(elapsed / interval) + 1
    // Compare absolute deadlines at the source clock's representable precision.
    if due.isFinite, now >= startedAt + interval * due { due += 1 }
    guard due > processedSteps else { return }
    let total = catalog.steps.last!
    let delta = min(Double(total) + 2, due - processedSteps)
    let first = currentStep + 1 + (blind ? 0 : correction)
    if !blind { correction = 0 }
    guard first >= 0, first <= total, delta - 1 <= Double(total - first) else {
      exhausted = true; return
    }
    let count = Int(delta)
    let target = first + count - 1
    fromStep = count == 1 ? currentStep : target - 1
    currentStep = target
    processedSteps = due
  }

  func frame(at time: TimeInterval? = nil, blind: Bool) -> PaceCaretFrame? {
    var projection = self
    projection.advance(to: time, blind: blind)
    guard !projection.exhausted, let startedAt, let observedAt = projection.observedAt else { return nil }
    let stepStart = startedAt + interval * (projection.processedSteps - 1)
    let stepEnd = startedAt + interval * projection.processedSteps
    let duration = stepEnd - stepStart
    let fraction = duration > 0 ? min(1, max(0, (observedAt - stepStart) / duration)) : 1
    return .init(from: projection.catalog.position(at: projection.fromStep),
      target: projection.catalog.position(at: projection.currentStep), fraction: fraction,
      stepDuration: duration, sequence: projection.processedSteps)
  }
}
