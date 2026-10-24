/// A trained character walk over owned words. Prefix identity is the last two
/// UTF-16 units, while each emitted symbol is one Unicode scalar.
struct WebsitePseudolangModel {
  private struct Distribution {
    let entries: [(symbol: UInt32, weight: Int)]
    let total: Int
  }
  private struct Counts {
    var order: [UInt32] = []
    var weights: [UInt32: Int] = [:]
    var total = 0
    mutating func add(_ symbol: UInt32) {
      if weights[symbol] == nil { order.append(symbol) }
      weights[symbol, default: 0] += 1
      total += 1
    }
    func frozen() -> Distribution {
      // JavaScript integer property names enumerate before insertion-ordered
      // names. For scalar symbols the only such names are ASCII digits.
      let digits = order.filter { (48...57).contains($0) }.sorted()
      let others = order.filter { !(48...57).contains($0) }
      return .init(entries: (digits + others).map { ($0, weights[$0]!) }, total: total)
    }
  }
  struct Trainer {
    private var states: [UInt64: Counts] = [:]
    mutating func add(_ word: String) {
      var prefix: UInt64 = 0
      for scalar in word.unicodeScalars {
        states[prefix, default: .init()].add(scalar.value)
        prefix = WebsitePseudolangModel.appending(scalar.value, to: prefix)
      }
      states[prefix, default: .init()].add(32)
    }
    func model() -> WebsitePseudolangModel { .init(states: states.mapValues { $0.frozen() }) }
  }
  private let states: [UInt64: Distribution]
  private init(states: [UInt64: Distribution]) { self.states = states }
  init<S: Sequence>(words: S) where S.Element == String {
    var trainer = Trainer()
    for word in words { trainer.add(word) }
    self = trainer.model()
  }
  static func isSelected(_ configuration: TestConfiguration) -> Bool {
    configuration.websiteTextAlterationOrder != nil && configuration.modifiers.contains(.pseudolangStream)
  }
  @MainActor static func preparing(configuration: TestConfiguration, didTrain: (Int) -> Void = { _ in }) async throws -> Self? {
    guard isSelected(configuration), [.words, .time].contains(configuration.mode) else { return nil }
    let pool = IndexedLexicon.ordered(GeneratedCandidateContinuation.ownedPool(configuration: configuration),
      reversed: configuration.modifiers.contains(.backwards))
    guard !pool.isEmpty else { throw WebsiteConfigSessionBuildError.generationFailed }
    var trainer = Trainer()
    for index in pool.indices {
      if index % 128 == 0 { try Task.checkCancellation(); await Task.yield() }
      trainer.add(pool[index])
      if index % 128 == 127 { didTrain(index + 1) }
    }
    try Task.checkCancellation()
    return trainer.model()
  }
  func word(randomUnit: () -> Double) -> String? {
    guard states[0] != nil else { return nil }
    var prefix: UInt64 = 0, text = ""
    while true {
      guard let distribution = states[prefix] else { prefix = 0; text = ""; continue }
      let unit = randomUnit()
      guard unit.isFinite, unit >= 0, unit < 1 else { return nil }
      let rank = Int((unit * Double(distribution.total)).rounded(.down))
      var accumulated = 0
      var selected = distribution.entries[0].symbol
      for entry in distribution.entries {
        accumulated += entry.weight
        if accumulated > rank { selected = entry.symbol; break }
      }
      if selected == 32 { return text }
      text.unicodeScalars.append(UnicodeScalar(selected)!)
      prefix = Self.appending(selected, to: prefix)
    }
  }
  private static func appending(_ scalar: UInt32, to prefix: UInt64) -> UInt64 {
    func unit(_ value: UInt16, after key: UInt64) -> UInt64 {
      key == 0 ? (1 << 32) | UInt64(value) : (2 << 32) | ((key & 0xffff) << 16) | UInt64(value)
    }
    if scalar <= 0xffff { return unit(UInt16(scalar), after: prefix) }
    let pair = scalar - 0x10000
    return unit(UInt16(0xdc00 + (pair & 0x3ff)), after: unit(UInt16(0xd800 + (pair >> 10)), after: prefix))
  }
}
