import Foundation

/// A personal rank's relative position in the population explicitly confirmed
/// by the current self-hosted leaderboard response.
enum LeaderboardRankStanding: Equatable, Sendable {
    case leader
    case top(percent: Double)

    init?(rank: Int, total: Int?) {
        guard let total, total > 0, (1...total).contains(rank) else { return nil }
        if rank == 1 {
            self = .leader
        } else {
            self = .top(percent: Double(rank) / Double(total) * 100)
        }
    }

    var displayName: String {
        switch self {
        case .leader:
            "榜首"
        case .top(let percent):
            "前 \(String(format: "%.2f", percent))%"
        }
    }
}
