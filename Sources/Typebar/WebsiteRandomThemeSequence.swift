import Foundation

/// Value state for the website's candidate list and cursor. No rendering,
/// persistence, account lookup, configuration setter or restart is performed.
struct WebsiteRandomThemeSequence {
  struct Entry: Equatable { let name: String; let isDark: Bool }
  struct Draw: Equatable { let theme: String; let customSourceID: String? }
  struct Favorites {
    fileprivate var identity = UUID()
    fileprivate var storage: [String]
    var names: [String] { storage }
    init(_ names: [String]) { storage = names }
    /// Even equal setter values replace the source array's identity.
    mutating func replace(with names: [String]) { identity = UUID(); storage = names }
  }
  enum Failure: Error, Equatable, LocalizedError {
    case duplicateEntry, invalidShuffleIndex, missingBuiltIn(String), noMatchingScheme
    var errorDescription: String? {
      switch self {
      case .duplicateEntry: "随机主题列表不可用，请重新加载。"
      case .invalidShuffleIndex: "暂时无法选择随机主题，请重试。"
      case .missingBuiltIn: "这个随机主题暂不可用，请更换范围或重试。"
      case .noMatchingScheme: "当前随机范围没有符合系统外观的主题，请更换范围。"
      }
    }
  }
  private let entries: [Entry]
  private let byName: [String: Entry]
  private var favoriteReference: UUID?
  private(set) var candidates: [String] = []
  private(set) var cursor = 0
  private(set) var active: String?

  init(entries: [Entry]) throws {
    guard Set(entries.map(\.name)).count == entries.count else { throw Failure.duplicateEntry }
    self.entries = entries; byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
  }
  func aliases(_ favorites: Favorites) -> Bool { favoriteReference == favorites.identity }

  /// Clearing the visible random override must retain the list and its cursor.
  @discardableResult mutating func clearActive() -> Bool {
    let hadActive = active != nil
    active = nil
    return hadActive
  }

  mutating func rebuild(mode: RandomThemeMode, favorites: inout Favorites, customIDs: [String],
    chooseIndex: (Int) -> Int = { Int.random(in: 0...$0) }) throws {
    if aliases(favorites) { candidates = favorites.storage }
    switch mode {
    case .favorites where !favorites.storage.isEmpty:
      candidates = favorites.storage; favoriteReference = favorites.identity
    case .light: candidates = entries.filter { !$0.isDark }.map(\.name); favoriteReference = nil
    case .dark: candidates = entries.filter(\.isDark).map(\.name); favoriteReference = nil
    case .on, .auto: candidates = entries.map(\.name); favoriteReference = nil
    case .custom: candidates = customIDs; favoriteReference = nil
    case .off, .favorites: break // The source retains the old list in these branches.
    }
    try shuffle(favorites: &favorites, chooseIndex: chooseIndex)
    cursor = 0
  }

  mutating func next(mode: RandomThemeMode, favorites: inout Favorites, customIDs: [String], systemIsDark: Bool,
    chooseIndex: (Int) -> Int = { Int.random(in: 0...$0) }) throws -> Draw? {
    if aliases(favorites) { candidates = favorites.storage }
    if candidates.isEmpty {
      try rebuild(mode: mode, favorites: &favorites, customIDs: customIDs, chooseIndex: chooseIndex)
      if candidates.isEmpty { return nil }
    }
    // A valid shade is encountered within one remaining partial cycle and one
    // complete cycle. The reference can spin forever for stale one-shade lists.
    for _ in 0..<(candidates.count * 2) {
      let identifier = candidates[cursor]
      active = identifier
      let entry = byName[identifier]
      cursor += 1
      if cursor >= candidates.count {
        try shuffle(favorites: &favorites, chooseIndex: chooseIndex)
        cursor = 0
      }
      // The pinned function reads nextTheme.bg even when its filter ignores
      // that argument. Opaque custom IDs therefore fail before a setter/apply.
      guard let entry else { throw Failure.missingBuiltIn(identifier) }
      if mode == .auto && entry.isDark != systemIsDark { continue }
      if mode == .custom {
        active = "custom"
        return .init(theme: "custom", customSourceID: customIDs.contains(identifier) ? identifier : nil)
      }
      return .init(theme: identifier, customSourceID: nil)
    }
    throw Failure.noMatchingScheme
  }

  private mutating func shuffle(favorites: inout Favorites, chooseIndex: (Int) -> Int) throws {
    if candidates.count > 1 {
      for upper in stride(from: candidates.count - 1, through: 1, by: -1) {
        let index = chooseIndex(upper)
        guard (0...upper).contains(index) else { throw Failure.invalidShuffleIndex }
        candidates.swapAt(index, upper)
      }
    }
    if aliases(favorites) { favorites.storage = candidates }
  }
}
