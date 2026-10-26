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
    let scheduledAtMilliseconds: Double
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
  mutating func append(_ text: String) { catalog.append(text) }

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
      delayMilliseconds: max(0, duration), scheduledAtMilliseconds: now, expectedEndMilliseconds: expectedEnd)
  }

  private mutating func retire() { alive = false; nextTimeout = nil; isVisible = false }
}

/// Value-owned live session adapter; the page owns scheduling, never this value.
struct WebsitePaceSession {
  private var state: WebsitePaceTimerState
  let wpm: Double
  private let clock: PaceCaretClock
  private var from = PaceCaretPosition(word: 0, letter: 0)
  private var revision = 0
  private var publishedRevision = 0
  private var rendersRequests: Bool
  private var acceptedPresentation: PaceCaretFrame?
  var catalog: PaceCaretCatalog { state.catalog }
  var isVisible: Bool { state.isVisible }
  var pendingTicket: WebsitePaceTimerState.Ticket? { state.nextTimeout?.ticket }

  init?(wpm: Double, catalog: PaceCaretCatalog, clock: PaceCaretClock, rendersRequests: Bool = true) {
    guard let state = WebsitePaceTimerState(wpm: wpm, catalog: catalog) else { return nil }
    self.state = state; self.wpm = wpm; self.clock = clock
    self.rendersRequests = rendersRequests
  }

  var pendingDelay: TimeInterval? {
    guard let timeout = state.nextTimeout else { return nil }
    let now = clock.now() * 1000
    guard now.isFinite, timeout.delayMilliseconds.isFinite else { return nil }
    // HTML timer initialization clamps nesting levels above five before
    // incrementing the new level. The seventh chained timeout is the first
    // with a 4ms minimum. This is a minimum, not an exact wake-time promise.
    let minimum = timeout.ticket.sequence > 6 ? 4.0 : 0
    // setTimeout's Web IDL long conversion precedes timer initialization.
    let unsigned = timeout.delayMilliseconds.rounded(.towardZero).truncatingRemainder(dividingBy: 4_294_967_296)
    let converted = unsigned >= 2_147_483_648 ? unsigned - 4_294_967_296 : unsigned
    let elapsed = max(0, now - timeout.scheduledAtMilliseconds)
    return max(0, max(minimum, converted) - elapsed) / 1000
  }

  mutating func start(blind: Bool) {
    state.start(atMilliseconds: clock.now() * 1000, blind: blind)
    if state.lastRequest != nil { revision = 1; publishedRevision = 1 }
    acceptPresentationIfEnabled()
  }
  @discardableResult mutating func deliver(_ ticket: WebsitePaceTimerState.Ticket, blind: Bool) -> Bool {
    guard let pending = state.nextTimeout, pending.ticket == ticket else { return false }
    let previous = state.lastRequest?.target ?? from
    state.deliver(ticket, atMilliseconds: clock.now() * 1000, blind: blind)
    guard state.nextTimeout?.ticket != ticket else { return false }
    from = previous
    revision += 1
    acceptPresentationIfEnabled()
    return true
  }
  mutating func claimClockPublication() -> Bool {
    guard publishedRevision != revision else { return false }
    publishedRevision = revision
    return true
  }
  mutating func append(_ text: String) { state.append(text) }
  mutating func synchronizePresentation(_ enabled: Bool) { rendersRequests = enabled }
  mutating func appendWords(_ words: [String]) { state.appendWords(words) }
  mutating func handleCommit(word: Int, correct: Bool, blind: Bool) {
    state.handleCommit(word: word, correct: correct, blind: blind)
  }
  func frame() -> PaceCaretFrame? {
    guard state.isVisible, let request = state.lastRequest, let pending = state.nextTimeout else { return nil }
    return .init(from: from, target: request.target, fraction: 0,
      stepDuration: request.durationMilliseconds / 1000, sequence: Double(pending.ticket.sequence))
  }
  func presentationFrame() -> PaceCaretFrame? { state.isVisible ? acceptedPresentation : nil }
  private mutating func acceptPresentationIfEnabled() {
    guard rendersRequests, var request = frame(), request.sequence != acceptedPresentation?.sequence else { return }
    request = .init(from: acceptedPresentation?.target ?? .init(word: 0, letter: 0),
      target: request.target, fraction: 0, stepDuration: request.stepDuration, sequence: request.sequence)
    acceptedPresentation = request
  }
}
