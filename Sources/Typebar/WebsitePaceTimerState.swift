import Foundation

/// Callback-driven request state. Reading a request never delivers a timer.
/// Times and requested delays use milliseconds; scheduling belongs to the host.
struct WebsitePaceTimerState {
  struct Ticket: Hashable {
    fileprivate let generation: UUID
    fileprivate let sequence: UInt64
  }

  struct Request: Equatable {
    let target: PaceCaretPosition
    let durationMilliseconds: Double
  }

  struct Scheduled: Equatable {
    let ticket: Ticket
    let delayMilliseconds: Double
    fileprivate let expectedEndMilliseconds: Double
  }

  private(set) var catalog: PaceCaretCatalog
  private(set) var isVisible = false
  private(set) var lastRequest: Request?
  private(set) var nextTimeout: Scheduled?
  private let generation = UUID()
  private let intervalMilliseconds: Double
  private var sequence: UInt64 = 0
  private var alive = true
  private var origin: Double?
  private var lastDelivery: Double?
  private var cursor = PaceCaretPosition(word: 0, letter: 0)
  private var correction = 0
  private var wrongWords = Set<Int>()

  init?(wpm: Double, catalog: PaceCaretCatalog) {
    guard wpm >= 1, !wpm.isNaN else { return nil }
    self.catalog = catalog
    intervalMilliseconds = (60 / (wpm * 5)) * 1000
  }

  mutating func appendWords(_ words: [String]) { catalog.appendWords(words) }

  mutating func start(atMilliseconds now: Double, blind: Bool) {
    guard alive, origin == nil, now.isFinite, now >= 0 else { return }
    origin = now
    update(at: now, expectedEnd: intervalMilliseconds, blind: blind)
  }

  /// A stale or duplicate delivery cannot consume the current pending timer.
  mutating func deliver(_ ticket: Ticket, atMilliseconds now: Double, blind: Bool) {
    guard alive, let pending = nextTimeout, pending.ticket == ticket,
      now.isFinite, now >= (lastDelivery ?? 0) else { return }
    nextTimeout = nil
    update(at: now, expectedEnd: pending.expectedEndMilliseconds + intervalMilliseconds, blind: blind)
  }

  mutating func handleCommit(word: Int, correct: Bool, blind: Bool) {
    guard alive, !blind, catalog.words.indices.contains(word) else { return }
    let length = catalog.words[word].correctionLength
    if correct {
      if wrongWords.remove(word) != nil { correction -= length }
    } else if wrongWords.insert(word).inserted { correction += length }
  }

  /// Reset cancels ownership of the timer; visibility is a separate host concern.
  mutating func reset() { alive = false; nextTimeout = nil }

  private mutating func update(at now: Double, expectedEnd: Double, blind: Bool) {
    guard catalog.words.indices.contains(cursor.word) else { retire(); return }
    let word = catalog.words[cursor.word]
    var next = cursor.letter >= word.length
      ? PaceCaretPosition(word: cursor.word + 1, letter: 0)
      : PaceCaretPosition(word: cursor.word, letter: cursor.letter + 1)
    if !blind, correction != 0 {
      let step = catalog.steps[next.word] + next.letter
      let (corrected, overflow) = step.addingReportingOverflow(correction)
      guard !overflow, corrected >= 0, corrected <= catalog.steps.last! else { retire(); return }
      next = catalog.position(at: corrected)
      correction = 0
    }
    cursor = next
    lastDelivery = now
    let duration = (origin! + expectedEnd) - now
    isVisible = true
    lastRequest = .init(target: next, durationMilliseconds: duration)
    sequence += 1
    nextTimeout = .init(ticket: .init(generation: generation, sequence: sequence),
      delayMilliseconds: max(0, duration), expectedEndMilliseconds: expectedEnd)
  }

  private mutating func retire() { alive = false; nextTimeout = nil; isVisible = false }
}
