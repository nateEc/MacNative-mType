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
    @State private var experienceLeaderboard: [RemoteExperienceLeaderboardEntry] = []
    @State private var experienceScope: RemoteLeaderboardScope = .global
    @State private var isLoadingExperience = false
    @State private var experienceMessage: String?
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
                guard let archive = try await account.pullArchive() else {
                    message = "没有新的远端归档。"
                    return
                }
                let summary = try LocalArchiveImport.apply(archive, settings: settings, results: results, presets: presets, savedTexts: savedTexts, modelContext: modelContext)
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
                leaderboardMessage = leaderboard.isEmpty ? "当前筛选没有成绩。" : "已加载 \(leaderboard.count) 条成绩。"
            } catch {
                leaderboard = []
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
                experienceMessage = experienceLeaderboard.isEmpty ? "本周还没有 XP 成绩。" : "已加载 \(experienceLeaderboard.count) 位练习者。"
            } catch {
                experienceLeaderboard = []
                experienceMessage = error.localizedDescription
            }
        }
    }

    private var localArchive: TypebarArchive {
        let portableResults = results.compactMap(\.portableResult)
        let namedPresets = presets.compactMap { record in
            record.definition.map { NamedPreset(name: record.name, definition: $0) }
        }
        let namedSavedTexts = savedTexts.map { NamedSavedText(title: $0.title, text: $0.text) }
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
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
            Text(profile.displayName).font(.title2.weight(.semibold))
            Grid(horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow { metric("完成成绩", "\(profile.completedResultCount)"); metric("最佳 WPM", "\(profile.bestWPM)") }
                GridRow { metric("总 XP", "\(profile.totalExperience)"); metric("加入", profile.joinedAt.formatted(date: .abbreviated, time: .omitted)) }
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
        .frame(width: 360)
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
