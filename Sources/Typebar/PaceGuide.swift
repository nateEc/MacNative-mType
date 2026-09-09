import Foundation

enum PaceGuideMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case off
    case custom
    case personalBest
    case activeTagPersonalBest
    case average
    case dailyAverage
    case recentAverage
    case dailyBest
    case lastTest

    var id: Self { self }

    var displayName: String {
        switch self {
        case .off: "关闭"
        case .custom: "自定义速度"
        case .personalBest: "同类个人最佳"
        case .activeTagPersonalBest: "活动标签个人最佳"
        case .average: "同类平均"
        case .dailyAverage: "今日同类平均"
        case .recentAverage: "最近 10 次同类平均"
        case .dailyBest: "过去 24 小时同类最佳"
        case .lastTest: "上一轮速度"
        }
    }
}

struct PaceGuideSample: Equatable {
    let configuration: TestConfiguration
    let outcome: TestOutcome
    let finishedAt: Date
    let wpm: Int
    let tags: [String]
    let prompt: String

    init(
        configuration: TestConfiguration,
        outcome: TestOutcome,
        finishedAt: Date,
        wpm: Int,
        tags: [String] = [],
        prompt: String = ""
    ) {
        self.configuration = configuration
        self.outcome = outcome
        self.finishedAt = finishedAt
        self.wpm = wpm
        self.tags = tags
        self.prompt = prompt
    }
}

enum PaceGuidePolicy {
    static let minimumWpm = 10
    static let maximumWpm = 300

    static func targetWpm(
        mode: PaceGuideMode,
        customWpm: Int,
        configuration: TestConfiguration,
        samples: [PaceGuideSample],
        activeTags: [String] = [],
        lastTestWpm: Int? = nil,
        currentPrompt: String = "",
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
        case .activeTagPersonalBest:
            guard !activeTags.isEmpty else { return nil }
            return matching(configuration: configuration, samples: samples)
                .filter { sharesActiveTag($0.tags, activeTags: activeTags) }
                .map(\.wpm)
                .max()
        case .average:
            return averageWpm(matching(configuration: configuration, samples: samples).map(\.wpm))
        case .dailyAverage:
            let today = calendar.startOfDay(for: now)
            let todaysWpm = matching(configuration: configuration, samples: samples)
                .filter { calendar.startOfDay(for: $0.finishedAt) == today }
                .map(\.wpm)
            return averageWpm(todaysWpm)
        case .recentAverage:
            let recentWpm = referenceMatching(
                configuration: configuration, currentPrompt: currentPrompt, samples: samples,
                activeTags: activeTags
            )
            .prefix(10)
            .map(\.wpm)
            return averageWpm(Array(recentWpm))
        case .dailyBest:
            let cutoff = now.addingTimeInterval(-86_400)
            return referenceMatching(
                configuration: configuration, currentPrompt: currentPrompt, samples: samples,
                activeTags: activeTags
            )
            .filter { $0.finishedAt >= cutoff }
            .map(\.wpm)
            .max()
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

    private static func referenceMatching(
        configuration: TestConfiguration,
        currentPrompt: String,
        samples: [PaceGuideSample],
        activeTags: [String]
    ) -> [PaceGuideSample] {
        samples
            .filter { sample in
                let sampleConfiguration = sample.configuration
                return sample.outcome == .completed
                    && sampleConfiguration.mode == configuration.mode
                    && sameModeParameter(sampleConfiguration, configuration)
                    && (configuration.mode != .quote || sample.prompt == currentPrompt)
                    && sampleConfiguration.contentOptions == configuration.contentOptions
                    && sampleConfiguration.language == configuration.language
                    && sampleConfiguration.difficulty == configuration.difficulty
                    && sampleConfiguration.modifiers.contains(.lazyLatin)
                        == configuration.modifiers.contains(.lazyLatin)
                    && (activeTags.isEmpty || sharesActiveTag(sample.tags, activeTags: activeTags))
            }
            .sorted { $0.finishedAt > $1.finishedAt }
    }

    private static func sameModeParameter(
        _ sample: TestConfiguration, _ current: TestConfiguration
    ) -> Bool {
        switch current.mode {
        case .time: sample.duration == current.duration
        case .words: sample.wordLimit == current.wordLimit
        case .quote: true
        case .zen, .custom: true
        }
    }

    private static func averageWpm(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    private static func sharesActiveTag(_ resultTags: [String], activeTags: [String]) -> Bool {
        resultTags.contains { resultTag in
            activeTags.contains {
                $0.compare(resultTag, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
