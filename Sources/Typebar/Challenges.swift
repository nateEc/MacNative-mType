import SwiftUI

struct TypebarChallenge: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let preset: SavedTestPreset
    let requirements: ChallengeRequirements
}

struct ChallengeRequirements: Equatable {
    var minimumWPM: Int?
    var minimumAccuracy: Int?
    var maximumErrors: Int?

    var summary: String {
        [
            minimumWPM.map { "至少 \($0) WPM" },
            minimumAccuracy.map { "准确率至少 \($0)%" },
            maximumErrors.map { "错误不超过 \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

struct ChallengeEvaluation: Equatable {
    let challenge: TypebarChallenge
    let passed: Bool
    let failedRequirements: [String]
}

enum ChallengeEvaluator {
    static func evaluate(_ result: CompletedTestResult, challenge: TypebarChallenge) -> ChallengeEvaluation {
        var failedRequirements: [String] = []
        if let minimumWPM = challenge.requirements.minimumWPM, result.wpm < minimumWPM {
            failedRequirements.append("速度需要至少 \(minimumWPM) WPM（本次 \(result.wpm)）")
        }
        if let minimumAccuracy = challenge.requirements.minimumAccuracy, result.accuracy < minimumAccuracy {
            failedRequirements.append("准确率需要至少 \(minimumAccuracy)%（本次 \(result.accuracy)%）")
        }
        if let maximumErrors = challenge.requirements.maximumErrors, result.errorCount > maximumErrors {
            failedRequirements.append("错误需要不超过 \(maximumErrors)（本次 \(result.errorCount)）")
        }
        return .init(challenge: challenge, passed: failedRequirements.isEmpty, failedRequirements: failedRequirements)
    }
}

enum TypebarChallengeLibrary {
    static let all: [TypebarChallenge] = [
        .init(
            id: "calm-thirty",
            title: "沉稳三十",
            description: "在一段短时间练习中保持速度和准确率。",
            preset: .init(configuration: .timed(seconds: 30), quoteID: nil, customText: nil),
            requirements: .init(minimumWPM: 35, minimumAccuracy: 94, maximumErrors: 10)
        ),
        .init(
            id: "clean-twenty-five",
            title: "净手二十五",
            description: "完成一段无错误的短词练习。",
            preset: .init(configuration: .words(25), quoteID: nil, customText: nil),
            requirements: .init(minimumWPM: nil, minimumAccuracy: 100, maximumErrors: 0)
        ),
        .init(
            id: "long-breath",
            title: "长呼吸",
            description: "在更长的词流中稳定保持节奏。",
            preset: .init(configuration: .words(100), quoteID: nil, customText: nil),
            requirements: .init(minimumWPM: 45, minimumAccuracy: 96, maximumErrors: 12)
        )
    ]

    static func challenge(id: String?) -> TypebarChallenge? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    static func dailyChallenge(on date: Date = .now, calendar: Calendar = .current) -> TypebarChallenge {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return all[day % all.count]
    }
}

struct ChallengeLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (TypebarChallenge) -> Void

    var body: some View {
        NavigationStack {
            List(TypebarChallengeLibrary.all) { challenge in
                Button {
                    onSelect(challenge)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(challenge.title).font(.headline)
                            Spacer()
                            Image(systemName: "flag.checkered")
                                .foregroundStyle(.tint)
                        }
                        Text(challenge.description)
                            .foregroundStyle(.secondary)
                        Text(challenge.requirements.summary)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .accessibilityHint("加载此挑战的固定测试配置")
            }
            .safeAreaInset(edge: .top) {
                let daily = TypebarChallengeLibrary.dailyChallenge()
                Button {
                    onSelect(daily)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading) {
                            Text("今日离线挑战").font(.caption.weight(.medium))
                            Text(daily.title).font(.headline)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(.tint)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(.bar)
            }
            .navigationTitle("离线挑战")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 330)
    }
}
