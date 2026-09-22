import Foundation

/// Anonymous service-wide totals displayed only in the native About window.
/// The payload intentionally has no account identity, prompt, input, replay,
/// or credential fields.
struct RemotePublicPracticeStats: Codable, Equatable, Sendable {
  let completedResultCount: Int
  let startedTestCount: Int
  let totalTypingSeconds: Int
}

struct RemotePublicSpeedDistributionBucket: Codable, Equatable, Identifiable, Sendable {
  let lowerBound: Int
  let count: Int

  var id: Int { lowerBound }

  func rangeLabel(bucketSize: Int) -> String {
    "\(lowerBound)–\(lowerBound + bucketSize - 1)"
  }
}

/// Compact, account-anonymous English sixty-second personal-best distribution
/// returned by a Typebar service. The server omits empty intervals; the native
/// chart fills only those in-between intervals so it never invents a result.
struct RemotePublicSpeedDistribution: Codable, Equatable, Sendable {
  let bucketSize: Int
  let buckets: [RemotePublicSpeedDistributionBucket]

  private static let maximumChartBucketCount = 50

  var chartBuckets: [RemotePublicSpeedDistributionBucket] {
    let sortedBuckets = buckets.sorted { $0.lowerBound < $1.lowerBound }
    guard bucketSize > 0,
      !sortedBuckets.isEmpty,
      sortedBuckets.allSatisfy({
        $0.lowerBound >= 0 && $0.lowerBound.isMultiple(of: bucketSize) && $0.count >= 0
      }),
      Set(sortedBuckets.map(\.lowerBound)).count == sortedBuckets.count,
      let first = sortedBuckets.first,
      let last = sortedBuckets.last
    else { return [] }

    let span = (last.lowerBound - first.lowerBound) / bucketSize + 1
    guard span <= Self.maximumChartBucketCount else { return [] }

    let countsByLowerBound = Dictionary(
      uniqueKeysWithValues: sortedBuckets.map { ($0.lowerBound, $0.count) })
    return stride(from: first.lowerBound, through: last.lowerBound, by: bucketSize).map {
      .init(lowerBound: $0, count: countsByLowerBound[$0, default: 0])
    }
  }

  var participantCount: Int {
    chartBuckets.reduce(0) { $0 + $1.count }
  }
}

struct RemotePublicPracticeOverview: Equatable, Sendable {
  let stats: RemotePublicPracticeStats
  let speedDistribution: RemotePublicSpeedDistribution
}

/// Readable public-count card data. The compact value is presentation-only;
/// callers retain the unmodified integer for accessibility and data handling.
struct PublicPracticeCountMagnitude: Equatable, Sendable {
  let value: String
  let unit: String
  let exactCount: Int
}

enum PublicPracticeStatisticsPresentation {
  static func countMagnitude(count: Int) -> PublicPracticeCountMagnitude {
    let exactCount = max(0, count)
    let units = ["次", "千次", "百万次", "十亿次", "万亿次", "千万亿次", "百京次"]
    var scaled = Double(exactCount)
    var unitIndex = 0

    while scaled >= 1_000, unitIndex < units.count - 1 {
      scaled /= 1_000
      unitIndex += 1
    }

    let rounded = scaled.rounded(.toNearestOrAwayFromZero)
    let value: String
    if rounded < 10, unitIndex > 0 {
      var decimal = String(
        format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), scaled)
      while decimal.last == "0" { decimal.removeLast() }
      if decimal.last == "." { decimal.removeLast() }
      value = decimal
    } else {
      value = "\(Int(rounded))"
    }

    return .init(value: value, unit: units[unitIndex], exactCount: exactCount)
  }

  static func durationLabel(seconds: Int) -> String {
    let safeSeconds = max(0, seconds)
    let hours = safeSeconds / 3_600
    let minutes = (safeSeconds % 3_600) / 60
    let remainingSeconds = safeSeconds % 60

    if hours > 0 {
      return minutes > 0 ? "\(hours) 小时 \(minutes) 分钟" : "\(hours) 小时"
    }
    if minutes > 0 {
      return remainingSeconds > 0 ? "\(minutes) 分钟 \(remainingSeconds) 秒" : "\(minutes) 分钟"
    }
    return "\(remainingSeconds) 秒"
  }
}
