import Foundation
import SwiftUI

/// Result-page evidence is independent of service acceptance and text labels.
struct AccountTagCompletionRow: Equatable, Identifiable {
  let id: UUID
  let name: String
  let previousBestWpm: Double
  let currentWpm: Double
  let isNewPersonalBest: Bool
  let showsPreviousBestLine: Bool
  var hint: String {
    let value = isNewPersonalBest ? currentWpm - previousBestWpm : previousBestWpm
    return (isNewPersonalBest ? "+" : "PB: ") + value.formatted(.number.precision(.fractionLength(0...2))) + " WPM"
  }
}

struct AccountTagCompletionFeedback: Equatable {
  let scope: ResultPublicationScope
  let resultID: UUID
  let rows: [AccountTagCompletionRow]
  var editFeedback: AccountTagResultEditFeedback {
    .init(ids: rows.map(\.id), crownedIDs: Set(rows.filter(\.isNewPersonalBest).map(\.id)))
  }
}

extension AccountSession {
  func recordAccountTagCompletion(_ result: CompletedTestResult, eligibility: ResultEligibility,
    at milliseconds: Int64) -> AccountTagCompletionFeedback? {
    guard let scope = resultPublicationScope, hasAccountTagDirectory, !accountTags.isEmpty,
      let snapshot = result.accountTagSnapshot, snapshot.scope == scope,
      (try? snapshot.validate()) != nil, (0...8_640_000_000_000_000).contains(milliseconds)
    else { return nil }
    if let old = lastAccountTagCompletionFeedback, old.scope == scope, old.resultID == result.id { return old }
    let feedback = AccountTagCompletionPolicy.feedback(result, scope: scope, directory: accountTags,
      personalBests: accountTagHistoryPersonalBests, eligibility: eligibility)
    applyAccountTagCompletionFeedback(feedback, result: result, at: milliseconds)
    return feedback
  }
}

enum AccountTagCompletionPolicy {
  static func feedback(_ result: CompletedTestResult, scope: ResultPublicationScope,
    directory: [RemoteAccountTag], personalBests: [AccountTagHistoryPersonalBest],
    eligibility: ResultEligibility) -> AccountTagCompletionFeedback {
    let ids = Set(result.accountTagSnapshot?.tagIDs ?? [])
    // Saving enabled, local save success, connection and POST receipt are not admission inputs.
    let admits = eligibility.isEligible && result.outcome == .completed
      && CurrentPersonalBestPolicy.isResultEligible(configuration: result.configuration, accuracy: result.preciseAccuracy)
      && result.preciseWpm.isFinite && (0...420).contains(result.preciseWpm)
      && result.preciseRawWpm.isFinite && (result.preciseWpm...500).contains(result.preciseRawWpm)
    let group = AccountTagHistoryGroup(result.configuration)
    let rows = directory.filter { ids.contains($0.id) }.map { tag in
      let cached = group.flatMap { group in personalBests.first { $0.tagID == tag.id && $0.group == group } }
      let accepted = group.flatMap { group in tag.personalBests.first { AccountTagHistoryGroup($0) == group } }
      let previous = cached?.wpm ?? accepted?.effectiveWpm ?? 0
      let crown = admits && result.preciseWpm > previous
      return AccountTagCompletionRow(id: tag.id, name: tag.displayName, previousBestWpm: previous,
        currentWpm: result.preciseWpm, isNewPersonalBest: crown, showsPreviousBestLine: admits && !crown)
    }
    return .init(scope: scope, resultID: result.id, rows: rows)
  }
}

struct AccountTagCompletionFeedbackView: View {
  let feedback: AccountTagCompletionFeedback
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label("账户标签", systemImage: "tag").font(.headline)
      if feedback.rows.isEmpty { Text("无账户标签").foregroundStyle(.secondary) }
      ForEach(feedback.rows) { row in
        HStack(spacing: 7) {
          Text(row.name)
          if row.isNewPersonalBest { Label("标签 PB", systemImage: "crown.fill").foregroundStyle(.yellow) }
        }
        .help(row.hint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.name)，\(row.hint)")
      }
    }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
  }
}
