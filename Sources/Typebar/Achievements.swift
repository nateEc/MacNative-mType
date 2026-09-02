import Foundation

/// Typebar-owned, offline achievement definitions. They are derived from local
/// completed results instead of copied badges or remote account state.
struct TypebarAchievement: Equatable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let isUnlocked: Bool
    let progress: String
}

enum TypebarAchievementPolicy {
    static func achievements(metrics: [ResultMetric]) -> [TypebarAchievement] {
        let completed = metrics.count
        let bestWPM = metrics.map(\.wpm).max() ?? 0
        let accurateRuns = metrics.filter { $0.accuracy >= 98 && $0.typingSeconds >= 15 }.count
        let totalMinutes = Int(metrics.map(\.typingSeconds).reduce(0, +) / 60)

        return [
            .init(id: "first-finish", title: "起步", detail: "完成第一次练习", systemImage: "flag.checkered", isUnlocked: completed >= 1, progress: "\(min(completed, 1))/1"),
            .init(id: "clear-key", title: "清晰按键", detail: "完成一次 98% 准确率练习", systemImage: "checkmark.seal", isUnlocked: accurateRuns >= 1, progress: "\(min(accurateRuns, 1))/1"),
            .init(id: "swift-line", title: "迅捷一行", detail: "完成一次 80 WPM 练习", systemImage: "bolt", isUnlocked: bestWPM >= 80, progress: "\(min(bestWPM, 80))/80 WPM"),
            .init(id: "steady-room", title: "稳定练习", detail: "累计练习 15 分钟", systemImage: "timer", isUnlocked: totalMinutes >= 15, progress: "\(min(totalMinutes, 15))/15 分钟")
        ]
    }
}
