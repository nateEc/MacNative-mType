import Foundation

/// Stable directory identities, never local text labels or history guesses.
/// Current funboxes do not gate an existing tag PB. Unknown options stay unknown.
enum AccountTagPacePolicy {
  static func targetWpm(configuration: TestConfiguration, tags: [RemoteAccountTag],
    selectedIDs: [UUID]) -> Double? {
    guard let group = LocalPersonalBestGroup(configuration), selectedIDs.count <= 15,
      Set(selectedIDs).count == selectedIDs.count else { return nil }
    let mode2 = [.time, .words].contains(group.mode) ? String(group.parameter) : group.mode.rawValue
    let selected = Set(selectedIDs)
    let speeds = tags.filter { selected.contains($0.id) }.compactMap { tag in
      tag.personalBests.first { best in
        guard let options = best.personalBestConfiguration else { return false }
        return best.mode == group.mode.rawValue && best.mode2 == mode2
          && best.language == group.language.rawValue && options.difficulty == group.difficulty.rawValue
          && options.punctuation == group.punctuation && options.numbers == group.numbers
          && options.lazyMode == group.lazy
      }?.effectiveWpm
    }
    return PaceGuidePolicy.validTarget(speeds.max())
  }
}

struct AccountTagDirectoryRead: Equatable {
  let scope: ResultPublicationScope
  let generation: UInt64
}
