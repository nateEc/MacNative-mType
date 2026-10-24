import Foundation

enum WebsiteConfigNativeQuoteSelectionError: Error, Equatable {
  case missingField, invalidField, queueSizeOverflow, invalidRandomIndex
}

/// Website quote intent is not the legacy native Set of lengths. Keep it
/// separate until the complete import transport can retain its semantics.
struct WebsiteConfigNativeQuoteSelection: Equatable {
  enum Route: Equatable { case lengths, selectedQuote, favorites }
  static let mappedKeys: Set<String> = ["quoteLength"]
  let groups: [Int]
  let route: Route
  var websiteValue: WebsiteConfigValue { .array(groups.map { .number(Double($0)) }) }

  private static let schema = WebsiteConfigSchema(catalogs: .init(
    languages: [], themes: [], layouts: [], fonts: [], funboxes: []))

  init(runtime: [String: WebsiteConfigValue]) throws {
    guard let value = runtime["quoteLength"] else { throw WebsiteConfigNativeQuoteSelectionError.missingField }
    guard Self.schema.accepts(value, for: "quoteLength"), case .array(let items) = value else {
      throw WebsiteConfigNativeQuoteSelectionError.invalidField
    }
    let groups = try items.map {
      guard case .number(let number) = $0 else { throw WebsiteConfigNativeQuoteSelectionError.invalidField }
      return Int(number)
    }
    self.groups = groups
    route = groups == [-2] ? .selectedQuote : groups.contains(-3) ? .favorites : .lengths
  }
}

/// Process-local website sampling semantics. The caller supplies the current
/// language's admitted, independently authored catalog and scoped native IDs.
/// This does not import reference quote IDs, read an account, or write settings.
struct WebsiteQuoteSampler {
  enum Reason: Equatable {
    case noLanguageQuotes, selectedQuoteUnavailable, favoriteQuoteUnavailable, noSelectedLengthQuotes
  }
  enum Recovery: Equatable {
    case allLengths, wordsMode

    var websiteChanges: [String: WebsiteConfigValue] {
      switch self {
      case .allLengths: ["quoteLength": .array((0...3).map { .number(Double($0)) })]
      case .wordsMode: ["mode": .string("words")]
      }
    }
  }
  enum Draw: Equatable {
    case quote(OfflineQuote)
    case unavailable(Reason, recovery: Recovery)
  }

  private struct Entry {
    let quote: OfflineQuote
    let count: Int
  }
  let selection: WebsiteConfigNativeQuoteSelection
  let cycleSize: Int
  var storageEntryCount: Int { entries.count }
  private let quotes: [OfflineQuote]
  private let entries: [Entry]
  private var remainingCounts: [Int]
  private var remainingTotal: Int

  init(selection: WebsiteConfigNativeQuoteSelection, quotes: [OfflineQuote]) throws {
    self.selection = selection
    self.quotes = quotes
    var frequencies = [0, 0, 0, 0]
    for group in selection.groups where group >= 0 { frequencies[group] += 1 }
    var entries: [Entry] = []
    var total = 0
    for quote in quotes {
      guard let group = quote.length.compatibilityValue.flatMap(Int.init), frequencies[group] > 0 else { continue }
      let count = frequencies[group]
      let sum = total.addingReportingOverflow(count)
      guard !sum.overflow else { throw WebsiteConfigNativeQuoteSelectionError.queueSizeOverflow }
      total = sum.partialValue
      entries.append(.init(quote: quote, count: count))
    }
    self.entries = entries
    cycleSize = total
    remainingCounts = entries.map(\.count)
    remainingTotal = total
  }

  mutating func resetCycle() {
    remainingCounts = entries.map(\.count)
    remainingTotal = cycleSize
  }

  func matches(selection: WebsiteConfigNativeQuoteSelection, quotes: [OfflineQuote]) -> Bool {
    func exact(_ lhs: String?, _ rhs: String?) -> Bool {
      switch (lhs, rhs) {
      case (nil, nil): true
      case (.some(let a), .some(let b)): a.utf16.elementsEqual(b.utf16)
      default: false
      }
    }
    return self.selection == selection && self.quotes.count == quotes.count
      && zip(self.quotes, quotes).allSatisfy { a, b in
        a.language == b.language && a.length == b.length && exact(a.id, b.id)
          && exact(a.title, b.title) && exact(a.text, b.text) && exact(a.britishText, b.britishText)
      }
  }

  /// Weighted draws without replacement produce the same distribution as
  /// shuffling an expanded multiset. No immediate-repeat avoidance is added.
  /// Seeded RNG stream identity with the website is deliberately not implied.
  mutating func next(selectedQuoteID: String? = nil, favoriteIDs: [String]? = nil,
    randomIndex: (Int) -> Int = { Int.random(in: 0..<$0) }) throws -> Draw {
    guard !quotes.isEmpty else { return .unavailable(.noLanguageQuotes, recovery: .wordsMode) }
    func ticket(_ upperBound: Int) throws -> Int {
      let index = randomIndex(upperBound)
      guard (0..<upperBound).contains(index) else { throw WebsiteConfigNativeQuoteSelectionError.invalidRandomIndex }
      return index
    }
    switch selection.route {
    case .selectedQuote:
      guard let quote = quotes.first(where: { $0.id == selectedQuoteID }) else {
        return .unavailable(.selectedQuoteUnavailable, recovery: .allLengths)
      }
      return .quote(quote)
    case .favorites:
      guard let favoriteIDs, !favoriteIDs.isEmpty else {
        return .unavailable(.favoriteQuoteUnavailable, recovery: .allLengths)
      }
      let id = favoriteIDs[try ticket(favoriteIDs.count)]
      // Do not pre-filter stale IDs: the source can draw one and fail even
      // when another favorite would have resolved in the current catalog.
      guard let quote = quotes.first(where: { $0.id == id }) else {
        return .unavailable(.favoriteQuoteUnavailable, recovery: .allLengths)
      }
      return .quote(quote)
    case .lengths:
      guard cycleSize > 0 else { return .unavailable(.noSelectedLengthQuotes, recovery: .allLengths) }
      var index = try ticket(remainingTotal == 0 ? cycleSize : remainingTotal)
      // Validate injected randomness before changing a completed cycle.
      if remainingTotal == 0 { resetCycle() }
      for position in entries.indices {
        if index < remainingCounts[position] {
          remainingCounts[position] -= 1
          remainingTotal -= 1
          return .quote(entries[position].quote)
        }
        index -= remainingCounts[position]
      }
      preconditionFailure("Validated weighted quote ticket must resolve")
    }
  }
}
