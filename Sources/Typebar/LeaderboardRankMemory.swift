import Foundation

/// The direction of a personal leaderboard rank after comparing it with the
/// last confirmed rank for the same account and leaderboard filter.
enum LeaderboardRankChange: Equatable, Sendable {
    case improved(Int)
    case declined(Int)
    case unchanged

    init?(previousRank: Int?, currentRank: Int) {
        guard let previousRank, previousRank > 0, currentRank > 0 else { return nil }
        switch previousRank - currentRank {
        case let difference where difference > 0: self = .improved(difference)
        case let difference where difference < 0: self = .declined(-difference)
        default: self = .unchanged
        }
    }

    var systemImage: String {
        switch self {
        case .improved: "arrow.up.right"
        case .declined: "arrow.down.right"
        case .unchanged: "equal"
        }
    }

    var displayName: String {
        switch self {
        case .improved(let positions): "较上次上升 \(positions) 位"
        case .declined(let positions): "较上次下降 \(positions) 位"
        case .unchanged: "与上次相同"
        }
    }
}
