import Foundation

enum PaceGuideMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case off
    case custom
    case personalBest
    case average
    case dailyAverage
    case lastTest

    var id: Self { self }

    var displayName: String {
        switch self {
        case .off: "关闭"
        case .custom: "自定义速度"
        case .personalBest: "同类个人最佳"
        case .average: "同类平均"
        case .dailyAverage: "今日同类平均"
        case .lastTest: "上一轮速度"
        }
    }
}

struct PaceGuideSample: Equatable {
    let configuration: TestConfiguration
    let outcome: TestOutcome
    let finishedAt: Date
    let wpm: Int
}

enum PaceGuidePolicy {
    static let minimumWpm = 10
    static let maximumWpm = 300

    static func targetWpm(
        mode: PaceGuideMode,
        customWpm: Int,
        configuration: TestConfiguration,
        samples: [PaceGuideSample],
        lastTestWpm: Int? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int? {
        switch mode {
        case .off:
            return nil
        case .custom:
            return customWpm.clamped(to: minimumWpm...maximumWpm)
        case .personalBest:
            return matching(configuration: configuration, samples: samples).map(\.wpm).max()
        case .average:
            return averageWpm(matching(configuration: configuration, samples: samples).map(\.wpm))
        case .dailyAverage:
            let today = calendar.startOfDay(for: now)
            let todaysWpm = matching(configuration: configuration, samples: samples)
                .filter { calendar.startOfDay(for: $0.finishedAt) == today }
                .map(\.wpm)
            return averageWpm(todaysWpm)
        case .lastTest:
            return lastTestWpm.map { $0.clamped(to: minimumWpm...maximumWpm) }
        }
    }

    static func expectedCharacterIndex(elapsed: TimeInterval, targetWpm: Int, promptLength: Int) -> Int {
        guard elapsed > 0, targetWpm > 0, promptLength > 0 else { return 0 }
        let characters = Int((elapsed * Double(targetWpm) * 5 / 60).rounded(.down))
        return characters.clamped(to: 0...max(0, promptLength - 1))
    }

    private static func matching(configuration: TestConfiguration, samples: [PaceGuideSample]) -> [PaceGuideSample] {
        samples.filter {
            $0.outcome == .completed
                && $0.configuration.mode == configuration.mode
                && $0.configuration.language == configuration.language
        }
    }

    private static func averageWpm(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
