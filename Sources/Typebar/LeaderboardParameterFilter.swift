import Foundation

/// A speed result belongs to a single time or word-count bucket. Keeping the
/// representation explicit makes it impossible to accidentally ask for both.
struct LeaderboardParameterFilter: Equatable {
    let durationSeconds: Int?
    let wordLimit: Int?

    var isActive: Bool { durationSeconds != nil || wordLimit != nil }
}

enum LeaderboardParameterFilterPolicy {
    static let standardDurations = [15, 30, 60, 120]
    static let standardWordLimits = [10, 25, 50, 100]

    static func filter(
        mode: TestMode?, durationSeconds: Int?, wordLimit: Int?
    ) -> LeaderboardParameterFilter {
        switch mode {
        case .time:
            return .init(
                durationSeconds: durationSeconds.flatMap { (5...3_600).contains($0) ? $0 : nil },
                wordLimit: nil)
        case .words:
            return .init(
                durationSeconds: nil,
                wordLimit: wordLimit.flatMap { (1...1_000).contains($0) ? $0 : nil })
        case .quote, .zen, .custom, .none:
            return .init(durationSeconds: nil, wordLimit: nil)
        }
    }
}

enum LeaderboardParameterEditorTarget: String, Identifiable {
    case duration
    case wordLimit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duration: "自定义榜单时长"
        case .wordLimit: "自定义榜单字数"
        }
    }

    var label: String {
        switch self {
        case .duration: "时长"
        case .wordLimit: "词数"
        }
    }

    var unit: String {
        switch self {
        case .duration: "秒"
        case .wordLimit: "词"
        }
    }

    var validRange: ClosedRange<Int> {
        switch self {
        case .duration: 5...3_600
        case .wordLimit: 1...1_000
        }
    }

    var standardValues: [Int] {
        switch self {
        case .duration: LeaderboardParameterFilterPolicy.standardDurations
        case .wordLimit: LeaderboardParameterFilterPolicy.standardWordLimits
        }
    }
}
