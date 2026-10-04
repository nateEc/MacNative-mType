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
    let preciseWpm: Double
    let accuracy: Double
    let tags: [String]
    let prompt: String

    init(
        configuration: TestConfiguration,
        outcome: TestOutcome,
        finishedAt: Date,
        wpm: Int,
        tags: [String] = [],
        prompt: String = "",
        preciseWpm: Double? = nil,
        accuracy: Double = 100
    ) {
        self.configuration = configuration
        self.outcome = outcome
        self.finishedAt = finishedAt
        self.wpm = wpm
        self.preciseWpm = preciseWpm ?? Double(wpm)
        self.accuracy = accuracy
        self.tags = tags
        self.prompt = prompt
    }

    init(result: CompletedTestResult) {
        self.init(configuration: result.configuration, outcome: result.outcome,
            finishedAt: result.finishedAt, wpm: result.wpm, tags: result.tags,
            prompt: result.prompt, preciseWpm: result.preciseWpm, accuracy: result.preciseAccuracy)
    }
}

/// Finish updates last speed before result validation/saving. Repeated pace
/// retains the fastest finish, including bailout and rejected finishes.
enum LastTestPacePolicy {
    static func updatedWpm(
        previousWpm: Double?,
        candidateWpm: Double,
        outcome: TestOutcome,
        isPaceRepeat: Bool
    ) -> Double? {
        guard outcome != .active, outcome != .abandoned else { return previousWpm }
        guard isPaceRepeat else { return candidateWpm }
        return candidateWpm > (previousWpm ?? 0) ? candidateWpm : previousWpm
    }
}

enum PaceGuidePolicy {
    // Persisted custom editor limits, not limits on PB or last-finish targets.
    static let minimumWpm = 10
    static let maximumWpm = 300

    static func targetWpm(
        mode: PaceGuideMode,
        customWpm: Int,
        configuration: TestConfiguration,
        samples: [PaceGuideSample],
        activeTags: [String] = [],
        lastTestWpm: Double? = nil,
        currentPrompt: String = "",
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double? {
        switch mode {
        case .off:
            return nil
        case .custom:
            return validTarget(Double(customWpm))
        case .personalBest:
            guard CurrentPersonalBestPolicy.isConfigurationEligible(configuration) else { return nil }
            return validTarget(personalBest(configuration: configuration,
                currentPrompt: currentPrompt, samples: samples))
        case .activeTagPersonalBest:
            guard !activeTags.isEmpty else { return nil }
            // Reference tag PB has no current-funbox guard. Stored candidates
            // must still have qualified when their result was recorded.
            return validTarget(personalBest(configuration: configuration,
                currentPrompt: currentPrompt, samples: samples, activeTags: activeTags))
        case .average:
            return averageWpm(matching(configuration: configuration, samples: samples).map(\.preciseWpm))
        case .dailyAverage:
            let today = calendar.startOfDay(for: now)
            let todaysWpm = matching(configuration: configuration, samples: samples)
                .filter { calendar.startOfDay(for: $0.finishedAt) == today }
                .map(\.preciseWpm)
            return averageWpm(todaysWpm)
        case .recentAverage:
            let recentWpm = referenceMatching(
                configuration: configuration, currentPrompt: currentPrompt, samples: samples,
                activeTags: activeTags
            )
            .prefix(10)
            .map(\.preciseWpm)
            return averageWpm(Array(recentWpm))
        case .dailyBest:
            let cutoff = now.addingTimeInterval(-86_400)
            let best = referenceMatching(
                configuration: configuration, currentPrompt: currentPrompt, samples: samples,
                activeTags: activeTags
            )
            .filter { $0.finishedAt >= cutoff }
            .map(\.preciseWpm)
            .max()
            return validTarget(best?.rounded())
        case .lastTest:
            return validTarget(lastTestWpm)
        }
    }

    static func validTarget(_ speed: Double?) -> Double? {
        guard let speed, speed.isFinite, speed >= 1 else { return nil }
        return speed
    }

    static func expectedCharacterIndex(elapsed: TimeInterval, targetWpm: Double, promptLength: Int) -> Int {
        guard elapsed.isFinite, elapsed > 0, targetWpm.isFinite, targetWpm > 0,
            promptLength > 0 else { return 0 }
        let position = (elapsed * targetWpm * 5 / 60).rounded(.down)
        // Clamp before conversion: finite inputs may overflow their product.
        let lastIndex = promptLength - 1
        guard position < Double(lastIndex) else { return lastIndex }
        return Int(position)
    }

    private static func matching(configuration: TestConfiguration, samples: [PaceGuideSample]) -> [PaceGuideSample] {
        samples.filter {
            ($0.outcome == .completed || $0.outcome == .bailedOut)
                && $0.preciseWpm.isFinite && $0.preciseWpm >= 0
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
                return (sample.outcome == .completed || sample.outcome == .bailedOut)
                    && sample.preciseWpm.isFinite && sample.preciseWpm >= 0
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

    private static func personalBest(configuration: TestConfiguration, currentPrompt: String,
        samples: [PaceGuideSample], activeTags: [String] = []) -> Double? {
        referenceMatching(configuration: configuration, currentPrompt: currentPrompt,
            samples: samples, activeTags: activeTags)
            .filter { $0.outcome == .completed && CurrentPersonalBestPolicy.isResultEligible(
                configuration: $0.configuration, accuracy: $0.accuracy) }
            .map(\.preciseWpm).max()
    }

    private static func averageWpm(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sum = values.reduce(0, +)
        let mean = sum.isFinite ? sum / Double(values.count)
            : values.reduce(0) { $0 + $1 / Double(values.count) }
        return validTarget(mean.rounded())
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
