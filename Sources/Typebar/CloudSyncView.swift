import SwiftData
import SwiftUI

struct CloudSyncView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TestResultRecord.finishedAt, order: .reverse) private var results: [TestResultRecord]
    @Query(sort: \TestPresetRecord.createdAt, order: .reverse) private var presets: [TestPresetRecord]
    @Query(sort: \SavedCustomTextRecord.createdAt, order: .reverse) private var savedTexts: [SavedCustomTextRecord]

    let settings: AppSettings
    let account: AccountSession
    @State private var message: String?
    @State private var leaderboard: [RemoteLeaderboardEntry] = []
    @State private var leaderboardMode: TestMode?
    @State private var leaderboardLanguage: TypingLanguage?
    @State private var leaderboardPeriod: RemoteLeaderboardPeriod = .all
    @State private var leaderboardScope: RemoteLeaderboardScope = .global
    @State private var isLoadingLeaderboard = false
    @State private var leaderboardMessage: String?
    @State private var leaderboardRank: RemoteLeaderboardEntry?
    @State private var loadedLeaderboardRank = false
    @State private var experienceLeaderboard: [RemoteExperienceLeaderboardEntry] = []
    @State private var experienceScope: RemoteLeaderboardScope = .global
    @State private var isLoadingExperience = false
    @State private var experienceMessage: String?
    @State private var experienceRank: RemoteExperienceLeaderboardEntry?
    @State private var loadedExperienceRank = false
    @State private var selectedProfile: RemotePublicProfile?
    @State private var profileMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("同步账户") {
                    if let user = account.currentUser {
                        LabeledContent("已登录", value: user.displayName)
                        Text(user.email).font(.caption).foregroundStyle(.secondary)
                        LabeledContent("总 XP", value: "\(user.totalExperience)")
                    } else {
                        Text("请先在“设置 → 自建账户”中登录自己的 Typebar 服务。").foregroundStyle(.secondary)
                    }
                }

                Section("本机归档") {
                    LabeledContent("成绩", value: "\(results.count) 条")
                    LabeledContent("预设", value: "\(presets.count) 个")
                    LabeledContent("自定义文本", value: "\(savedTexts.count) 篇")
                    Text("上传会创建版本化归档变更；下载会按成绩 ID 和内容去重合并，并应用远端归档中的设置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("操作") {
                    @Bindable var settings = settings
                    Toggle("将完成成绩发送到自建服务", isOn: $settings.publishCompletedResults)
                    Text("默认关闭。开启后，仅在已登录时把本次完成的基本成绩发送到你配置的服务；本机保存始终优先，发送失败不会影响练习。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("上传本机归档", action: push)
                        .disabled(account.currentUser == nil || account.isWorking)
                    Button("拉取并合并远端归档", action: pull)
                        .disabled(account.currentUser == nil || account.isWorking)
                    if account.isWorking { ProgressView() }
                    if let message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("排行榜（自建服务）") {
                    Picker("榜单", selection: $leaderboardScope) {
                        ForEach(RemoteLeaderboardScope.allCases, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    Picker("模式", selection: $leaderboardMode) {
                        Text("全部").tag(TestMode?.none)
                        ForEach(TestMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(Optional(mode))
                        }
                    }
                    Picker("语言", selection: $leaderboardLanguage) {
                        Text("全部").tag(TypingLanguage?.none)
                        ForEach(TypingLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(Optional(language))
                        }
                    }
                    Picker("范围", selection: $leaderboardPeriod) {
                        ForEach(RemoteLeaderboardPeriod.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    Button("刷新\(leaderboardScope.displayName)", action: loadLeaderboard)
                        .disabled(isLoadingLeaderboard || (leaderboardScope == .friends && account.currentUser == nil))
                    if isLoadingLeaderboard { ProgressView() }
                    if let leaderboardMessage {
                        Text(leaderboardMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    if let user = account.currentUser, leaderboardMessage != nil {
                        if user.leaderboardOptedOut {
                            Text("你已选择从自建服务排行榜隐藏。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let leaderboardRank {
                            Label(
                                "你的排名 #\(leaderboardRank.rank) · \(leaderboardRank.wpm) WPM",
                                systemImage: "person.fill")
                                .font(.caption.weight(.medium))
                        } else if loadedLeaderboardRank {
                            Text("当前筛选没有你的有效成绩。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let profileMessage {
                        Text(profileMessage).font(.caption).foregroundStyle(.red)
                    }
                    ForEach(leaderboard) { entry in
                        HStack {
                            Text("#\(entry.rank)").monospacedDigit().foregroundStyle(.secondary)
                            Button(entry.displayName) { loadProfile(id: entry.userID) }
                                .buttonStyle(.plain)
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.wpm) WPM").monospacedDigit()
                            Text("\(entry.accuracy)%").foregroundStyle(.secondary).monospacedDigit()
                            Text("\(entry.consistency.formatted(.number.precision(.fractionLength(0...2))))% 稳定")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Text(leaderboardScope == .friends ? "好友榜只包含你和已接受的好友；每位用户只显示当前筛选下的最佳成绩，待处理请求不会计入。" : "每位用户只显示当前筛选下的最佳 WPM；它不是经过完整反作弊验证的竞赛排名。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("本周 XP 榜（自建服务）") {
                    Picker("榜单", selection: $experienceScope) {
                        ForEach(RemoteLeaderboardScope.allCases, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    Button("刷新\(experienceScope.displayName)", action: loadExperienceLeaderboard)
                        .disabled(isLoadingExperience || (experienceScope == .friends && account.currentUser == nil))
                    if isLoadingExperience { ProgressView() }
                    if let experienceMessage {
                        Text(experienceMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    if let user = account.currentUser, experienceMessage != nil {
                        if user.leaderboardOptedOut {
                            Text("你已选择从自建服务排行榜隐藏。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let experienceRank {
                            Label(
                                "你的本周 XP 排名 #\(experienceRank.rank) · \(experienceRank.totalExperience) XP",
                                systemImage: "person.fill")
                                .font(.caption.weight(.medium))
                        } else if loadedExperienceRank {
                            Text("本周还没有你的有效 XP 成绩。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(experienceLeaderboard) { entry in
                        HStack {
                            Text("#\(entry.rank)").monospacedDigit().foregroundStyle(.secondary)
                            Button(entry.displayName) { loadProfile(id: entry.userID) }
                                .buttonStyle(.plain)
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.totalExperience) XP").monospacedDigit()
                        }
                    }
                    Text(experienceScope == .friends ? "好友 XP 榜仅包含你和已接受好友，并按当前 ISO 周的服务端验证成绩累计。" : "XP 由服务端根据完成成绩的时长、准确率和模式重算；禅模式不奖励 XP。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("同步")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 350)
        .sheet(item: $selectedProfile) { profile in
            PublicProfileView(profile: profile, account: account)
        }
    }

    private func push() {
        Task {
            do {
                let cursor = try await account.pushArchive(localArchive)
                message = "上传完成，服务端游标为 \(cursor)。"
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func pull() {
        Task {
            do {
                let pulled = try await account.pullArchive()
                guard let archive = pulled.archive else {
                    account.confirmPulledArchive(pulled)
                    message = "没有新的远端归档。"
                    return
                }
                let summary = try LocalArchiveImport.apply(archive, settings: settings, results: results, presets: presets, savedTexts: savedTexts, modelContext: modelContext)
                account.confirmPulledArchive(pulled)
                message = "已合并 \(summary.insertedResults) 条成绩、\(summary.insertedPresets) 个预设和 \(summary.insertedSavedTexts) 篇文本。"
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func loadLeaderboard() {
        Task {
            isLoadingLeaderboard = true
            defer { isLoadingLeaderboard = false }
            do {
                leaderboard = try await account.leaderboard(mode: leaderboardMode, language: leaderboardLanguage, period: leaderboardPeriod, scope: leaderboardScope)
                leaderboardRank = nil
                loadedLeaderboardRank = false
                if let user = account.currentUser, !user.leaderboardOptedOut {
                    do {
                        leaderboardRank = try await account.leaderboardRank(
                            mode: leaderboardMode, language: leaderboardLanguage,
                            period: leaderboardPeriod, scope: leaderboardScope)
                        loadedLeaderboardRank = true
                    } catch {
                        // Older self-hosted servers may not have the rank route yet.
                    }
                }
                leaderboardMessage = leaderboard.isEmpty ? "当前筛选没有成绩。" : "已加载 \(leaderboard.count) 条成绩。"
            } catch {
                leaderboard = []
                leaderboardRank = nil
                loadedLeaderboardRank = false
                leaderboardMessage = error.localizedDescription
            }
        }
    }

    private func loadProfile(id: UUID) {
        Task {
            do {
                selectedProfile = try await account.publicProfile(id: id)
                profileMessage = nil
            } catch {
                profileMessage = error.localizedDescription
            }
        }
    }

    private func loadExperienceLeaderboard() {
        Task {
            isLoadingExperience = true
            defer { isLoadingExperience = false }
            do {
                experienceLeaderboard = try await account.experienceLeaderboard(scope: experienceScope)
                experienceRank = nil
                loadedExperienceRank = false
                if let user = account.currentUser, !user.leaderboardOptedOut {
                    do {
                        experienceRank = try await account.experienceLeaderboardRank(scope: experienceScope)
                        loadedExperienceRank = true
                    } catch {
                        // Older self-hosted servers may not have the rank route yet.
                    }
                }
                experienceMessage = experienceLeaderboard.isEmpty ? "本周还没有 XP 成绩。" : "已加载 \(experienceLeaderboard.count) 位练习者。"
            } catch {
                experienceLeaderboard = []
                experienceRank = nil
                loadedExperienceRank = false
                experienceMessage = error.localizedDescription
            }
        }
    }

    private var localArchive: TypebarArchive {
        let portableResults = results.compactMap(\.portableResult)
        let namedPresets = presets.compactMap { record in
            record.definition.map { NamedPreset(name: record.name, definition: $0) }
        }
        let namedSavedTexts = savedTexts.map {
            NamedSavedText(title: $0.title, text: $0.text, longProgress: $0.longProgress)
        }
        return .init(exportedAt: .now, settings: settings.snapshot, results: portableResults, presets: namedPresets, savedTexts: namedSavedTexts)
    }
}

private struct PublicProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let profile: RemotePublicProfile
    let account: AccountSession
    @State private var connectionMessage: String?
    @State private var isSendingRequest = false
    @State private var showingReport = false

    var body: some View {
        ScrollView {
          VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
            Text(profile.displayName).font(.title2.weight(.semibold))
            Grid(horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow { metric("完成成绩", "\(profile.completedResultCount)"); metric("最佳 WPM", "\(profile.bestWPM)") }
                GridRow {
                    metric("最高稳定度", "\(profile.highestConsistency.formatted(.number.precision(.fractionLength(0...2))))%")
                    metric("总 XP", "\(profile.totalExperience)")
                }
            }
            Text("加入 \(profile.joinedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if hasPublicDetails {
                VStack(alignment: .leading, spacing: 8) {
                    Text("关于")
                        .font(.headline)
                    if !profile.profileDetails.bio.isEmpty {
                        Text(profile.profileDetails.bio)
                            .textSelection(.enabled)
                    }
                    if !profile.profileDetails.keyboard.isEmpty {
                        Label(profile.profileDetails.keyboard, systemImage: "keyboard")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        if !profile.profileDetails.github.isEmpty,
                            let github = URL(string: "https://github.com/\(profile.profileDetails.github)")
                        {
                            Link("GitHub @\(profile.profileDetails.github)", destination: github)
                        }
                        if !profile.profileDetails.socialHandle.isEmpty,
                            let social = URL(string: "https://x.com/\(profile.profileDetails.socialHandle)")
                        {
                            Link("@\(profile.profileDetails.socialHandle)", destination: social)
                        }
                        if let website = publicWebsite {
                            Link("个人网站", destination: website)
                        }
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !profile.personalBests.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("公开个人最佳")
                        .font(.headline)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10
                    ) {
                        ForEach(profile.personalBests) { best in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(best.configurationLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(best.wpm) WPM")
                                    .font(.headline.monospacedDigit())
                                Text("\(best.accuracy)% 准确 · \(best.consistency.formatted(.number.precision(.fractionLength(0...2))))% 稳定")
                                    .font(.caption2)
                                Text("\(best.languageLabel) · \(best.finishedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let activity = profile.activity {
                PublicProfileActivityCalendar(activity: activity)
            }
            Text("公开资料不会包含邮箱、令牌或本地练习内容。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if profile.id != account.currentUser?.id {
                HStack {
                    Button("发送好友请求") { sendRequest() }
                        .disabled(account.currentUser == nil || isSendingRequest)
                    Button("举报资料") { showingReport = true }
                        .disabled(account.currentUser == nil)
                }
                if let connectionMessage {
                    Text(connectionMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
          }
          .padding(32)
        }
        .frame(width: 420, height: 620)
        .sheet(isPresented: $showingReport) {
            ProfileReportView(profile: profile, account: account)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var hasPublicDetails: Bool {
        !profile.profileDetails.bio.isEmpty || !profile.profileDetails.keyboard.isEmpty
            || !profile.profileDetails.github.isEmpty || !profile.profileDetails.socialHandle.isEmpty
            || publicWebsite != nil
    }

    private var publicWebsite: URL? {
        guard let website = URL(string: profile.profileDetails.websiteURL),
            website.scheme?.lowercased() == "https", website.host != nil
        else { return nil }
        return website
    }

    private func sendRequest() {
        Task {
            isSendingRequest = true
            defer { isSendingRequest = false }
            do {
                _ = try await account.sendConnection(to: profile.id)
                connectionMessage = "好友请求已发送。"
            } catch {
                connectionMessage = error.localizedDescription
            }
        }
    }
}

private struct PublicProfileActivityCalendar: View {
    let activity: RemotePublicProfileActivity

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var maximum: Int { max(1, activity.testsByDays.max() ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("近 12 个月公开活动")
                    .font(.headline)
                Spacer()
                Text("按 UTC 日聚合")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: Array(repeating: GridItem(.fixed(10), spacing: 3), count: 7), spacing: 3
                ) {
                    ForEach(Array(activity.testsByDays.enumerated()), id: \.offset) { offset, count in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(opacity(for: count)))
                            .frame(width: 10, height: 10)
                            .accessibilityLabel("\(dayLabel(offset: offset))：完成 \(count) 次")
                    }
                }
                .padding(.vertical, 2)
            }
            Text("颜色越深表示完成次数越多；只显示完成次数，不显示文本或输入回放。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func opacity(for count: Int) -> Double {
        guard count > 0 else { return 0.1 }
        return 0.25 + 0.75 * min(1, Double(count) / Double(maximum))
    }

    private func dayLabel(offset: Int) -> String {
        let startOffset = offset - activity.testsByDays.count + 1
        let day = calendar.date(byAdding: .day, value: startOffset, to: activity.lastDay) ?? activity.lastDay
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}
