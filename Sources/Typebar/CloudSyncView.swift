import SwiftData
import SwiftUI

struct CloudSyncView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TestResultRecord.finishedAt, order: .reverse) private var results: [TestResultRecord]
    @Query(sort: \TestPresetRecord.createdAt, order: .reverse) private var presets: [TestPresetRecord]
    @Query(sort: \SavedCustomTextRecord.createdAt, order: .reverse) private var savedTexts: [SavedCustomTextRecord]
    @Query(sort: \ResultFilterPresetRecord.createdAt, order: .reverse)
    private var resultFilterPresets: [ResultFilterPresetRecord]

    let settings: AppSettings
    let account: AccountSession
    let initialLeaderboard: RemoteLeaderboardSelection?
    private let conflictAuditStore = SyncConflictAuditStore()
    @State private var message: String?
    @State private var conflictAudit: [SyncConflictAuditEntry] = []
    @State private var leaderboard: [RemoteLeaderboardEntry] = []
    @State private var leaderboardMode: TestMode?
    @State private var leaderboardLanguage: TypingLanguage?
    @State private var leaderboardPeriod: RemoteLeaderboardPeriod = .all
    @State private var leaderboardScope: RemoteLeaderboardScope = .global
    @State private var isLoadingLeaderboard = false
    @State private var leaderboardMessage: String?
    @State private var leaderboardRank: RemoteLeaderboardEntry?
    @State private var leaderboardEligibility: RemoteLeaderboardEligibility?
    @State private var leaderboardRankChange: LeaderboardRankChange?
    @State private var loadedLeaderboardRank = false
    @State private var leaderboardPage: RemoteLeaderboardPage?
    @State private var leaderboardPageIndex = 0
    @State private var requestedLeaderboardPage = 1
    @State private var leaderboardRequestGeneration = 0
    @State private var leaderboardDurationSeconds: Int?
    @State private var leaderboardWordLimit: Int?
    @State private var leaderboardSupportsParameterFilter = false
    @State private var leaderboardParameterEditor: LeaderboardParameterEditorTarget?
    @State private var experienceLeaderboard: [RemoteExperienceLeaderboardEntry] = []
    @State private var experiencePeriod: RemoteExperienceLeaderboardPeriod = .week
    @State private var experienceScope: RemoteLeaderboardScope = .global
    @State private var isLoadingExperience = false
    @State private var experienceMessage: String?
    @State private var experienceRank: RemoteExperienceLeaderboardEntry?
    @State private var experienceLeaderboardEligibility: RemoteLeaderboardEligibility?
    @State private var experienceRankChange: LeaderboardRankChange?
    @State private var loadedExperienceRank = false
    @State private var experienceLeaderboardPage: RemoteExperienceLeaderboardPage?
    @State private var experiencePageIndex = 0
    @State private var requestedExperiencePage = 1
    @State private var experienceRequestGeneration = 0
    @State private var selectedProfile: RemotePublicProfile?
    @State private var profileMessage: String?

    init(
        settings: AppSettings, account: AccountSession,
        initialLeaderboard: RemoteLeaderboardSelection? = nil
    ) {
        self.settings = settings
        self.account = account
        self.initialLeaderboard = initialLeaderboard
        let initialParameter = LeaderboardParameterFilterPolicy.filter(
            mode: initialLeaderboard?.mode,
            durationSeconds: initialLeaderboard?.durationSeconds,
            wordLimit: initialLeaderboard?.wordLimit)
        _leaderboardMode = State(initialValue: initialLeaderboard?.mode)
        _leaderboardLanguage = State(initialValue: initialLeaderboard?.language)
        _leaderboardPeriod = State(initialValue: initialLeaderboard?.period ?? .all)
        _leaderboardDurationSeconds = State(initialValue: initialParameter.durationSeconds)
        _leaderboardWordLimit = State(initialValue: initialParameter.wordLimit)
    }

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
                    LabeledContent("成绩筛选预设", value: "\(resultFilterPresets.count) 个")
                    Text("上传会创建包含当前测试选择的版本化归档变更；普通下载会去重合并并应用远端设置和有效测试选择。若上传发现并发冲突，则保留本机设置与测试选择，并将双方不同的内容另存为带标记副本后重试。")
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

                if account.currentUser != nil {
                    Section("同步冲突记录") {
                        if conflictAudit.isEmpty {
                            Text("当前账户还没有需要另存副本的同步冲突。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(conflictAudit) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Image(systemName: entry.kind.systemImage)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.displayName).lineLimit(1)
                                        Text(entry.kind.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(entry.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Button("清空当前账户记录", role: .destructive, action: clearConflictAudit)
                        }
                        Text("仅保存在这台 Mac，并按服务地址和账户分开；不记录文本正文、成绩或登录凭据。最多保留最近 50 条。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    if leaderboardSupportsParameterFilter {
                        switch leaderboardMode {
                        case .time:
                            LeaderboardParameterPicker(
                                target: .duration, selectedValue: $leaderboardDurationSeconds,
                                onCustomize: { leaderboardParameterEditor = .duration })
                        case .words:
                            LeaderboardParameterPicker(
                                target: .wordLimit, selectedValue: $leaderboardWordLimit,
                                onCustomize: { leaderboardParameterEditor = .wordLimit })
                        case .quote, .zen, .custom, .none:
                            EmptyView()
                        }
                    } else if pendingLeaderboardParameterFilter.isActive {
                        Text("当前自建服务未声明按时长或词数分桶；为避免把错误的混合榜单当作精确名次，暂不发送该筛选。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    WPMLeaderboardRefreshCountdown(period: leaderboardPeriod)
                    Button("刷新\(leaderboardScope.displayName)", action: loadLeaderboard)
                        .disabled(isLoadingLeaderboard || (leaderboardScope == .friends && account.currentUser == nil))
                    if isLoadingLeaderboard { ProgressView() }
                    if let leaderboardMessage {
                        Text(leaderboardMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    if let user = account.currentUser, leaderboardMessage != nil {
                        if user.accountSuspended
                            || leaderboardEligibility?.isAccountSuspended == true
                        {
                            AccountSuspensionLabel()
                        } else if user.displayNameChangeRequired
                            || leaderboardEligibility?.isDisplayNameChangeRequired == true
                        {
                            DisplayNameRequirementLabel()
                        } else if user.leaderboardRestricted
                            || leaderboardEligibility?.isLeaderboardRestricted == true
                        {
                            LeaderboardRestrictionLabel()
                        } else if user.leaderboardOptedOut {
                            Text("你已选择从自建服务排行榜隐藏。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let leaderboardRank {
                            let standing = LeaderboardRankStanding(
                                rank: leaderboardRank.rank, total: leaderboardPage?.total)
                            VStack(alignment: .leading, spacing: 3) {
                                Label(
                                    "你的排名 #\(leaderboardRank.rank) · \(leaderboardRank.wpm) WPM\(standing.map { " · \($0.displayName)" } ?? "")",
                                    systemImage: "person.fill")
                                    .font(.caption.weight(.medium))
                                if let leaderboardRankChange {
                                    LeaderboardRankChangeLabel(change: leaderboardRankChange)
                                }
                            }
                        } else if let leaderboardEligibility, !leaderboardEligibility.isEligible {
                            LeaderboardEligibilityLabel(eligibility: leaderboardEligibility)
                        } else if loadedLeaderboardRank {
                            Text("当前筛选没有你的有效成绩。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let leaderboardPage {
                        LeaderboardPaginationControls(
                            total: leaderboardPage.total,
                            pageSize: leaderboardPage.pageSize,
                            pageIndex: leaderboardPageIndex,
                            requestedPage: $requestedLeaderboardPage,
                            isLoading: isLoadingLeaderboard,
                            myPageIndex: leaderboardRank.flatMap {
                                LeaderboardPaginationPolicy.pageIndex(
                                    containingRank: $0.rank, total: leaderboardPage.total,
                                    pageSize: leaderboardPage.pageSize)
                            },
                            onLoadPage: { loadLeaderboard(pageIndex: $0) })
                    }
                    if let profileMessage {
                        Text(profileMessage).font(.caption).foregroundStyle(.red)
                    }
                    ForEach(leaderboard) { entry in
                        HStack {
                            Text("#\(entry.rank)").monospacedDigit().foregroundStyle(.secondary)
                            LeaderboardAvatar(avatar: entry.discordAvatar)
                            if let badge = entry.selectedBadge {
                                Image(systemName: badge.systemImage)
                                    .foregroundStyle(.tint)
                                    .help(badge.title)
                                    .accessibilityLabel("\(badge.title) 徽章")
                            }
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

                Section("XP 榜（自建服务）") {
                    Picker("范围", selection: $experiencePeriod) {
                        ForEach(RemoteExperienceLeaderboardPeriod.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    Picker("榜单", selection: $experienceScope) {
                        ForEach(RemoteLeaderboardScope.allCases, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    ExperienceLeaderboardRefreshCountdown(period: experiencePeriod)
                    Button("刷新\(experienceScope.displayName)", action: loadExperienceLeaderboard)
                        .disabled(isLoadingExperience || (experienceScope == .friends && account.currentUser == nil))
                    if isLoadingExperience { ProgressView() }
                    if let experienceMessage {
                        Text(experienceMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    if let user = account.currentUser, experienceMessage != nil {
                        if user.accountSuspended
                            || experienceLeaderboardEligibility?.isAccountSuspended == true
                        {
                            AccountSuspensionLabel()
                        } else if user.displayNameChangeRequired
                            || experienceLeaderboardEligibility?.isDisplayNameChangeRequired == true
                        {
                            DisplayNameRequirementLabel()
                        } else if user.leaderboardRestricted
                            || experienceLeaderboardEligibility?.isLeaderboardRestricted == true
                        {
                            LeaderboardRestrictionLabel()
                        } else if user.leaderboardOptedOut {
                            Text("你已选择从自建服务排行榜隐藏。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let experienceRank {
                            let standing = LeaderboardRankStanding(
                                rank: experienceRank.rank, total: experienceLeaderboardPage?.total)
                            VStack(alignment: .leading, spacing: 3) {
                                Label(
                                    "你的\(experiencePeriod.displayName) XP 排名 #\(experienceRank.rank) · \(experienceRank.totalExperience) XP\(standing.map { " · \($0.displayName)" } ?? "")",
                                    systemImage: "person.fill")
                                    .font(.caption.weight(.medium))
                                if let experienceRankChange {
                                    LeaderboardRankChangeLabel(change: experienceRankChange)
                                }
                            }
                        } else if let experienceLeaderboardEligibility,
                            !experienceLeaderboardEligibility.isEligible
                        {
                            LeaderboardEligibilityLabel(eligibility: experienceLeaderboardEligibility)
                        } else if loadedExperienceRank {
                            Text("\(experiencePeriod.displayName)还没有你的有效 XP 成绩。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let experienceLeaderboardPage {
                        LeaderboardPaginationControls(
                            total: experienceLeaderboardPage.total,
                            pageSize: experienceLeaderboardPage.pageSize,
                            pageIndex: experiencePageIndex,
                            requestedPage: $requestedExperiencePage,
                            isLoading: isLoadingExperience,
                            myPageIndex: experienceRank.flatMap {
                                LeaderboardPaginationPolicy.pageIndex(
                                    containingRank: $0.rank, total: experienceLeaderboardPage.total,
                                    pageSize: experienceLeaderboardPage.pageSize)
                            },
                            onLoadPage: { loadExperienceLeaderboard(pageIndex: $0) })
                    }
                    ForEach(experienceLeaderboard) { entry in
                        HStack {
                            Text("#\(entry.rank)").monospacedDigit().foregroundStyle(.secondary)
                            LeaderboardAvatar(avatar: entry.discordAvatar)
                            if let badge = entry.selectedBadge {
                                Image(systemName: badge.systemImage)
                                    .foregroundStyle(.tint)
                                    .help(badge.title)
                                    .accessibilityLabel("\(badge.title) 徽章")
                            }
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
        .task {
            guard initialLeaderboard != nil else { return }
            loadLeaderboard()
        }
        .task(id: account.resultPublicationScope) {
            reloadConflictAudit()
        }
        .onChange(of: account.resultPublicationScope) { _, _ in
            resetLeaderboardPagination()
            resetExperiencePagination()
        }
        .onChange(of: leaderboardScope) { _, _ in resetLeaderboardPagination() }
        .onChange(of: leaderboardMode) { _, _ in resetLeaderboardPagination() }
        .onChange(of: leaderboardLanguage) { _, _ in resetLeaderboardPagination() }
        .onChange(of: leaderboardPeriod) { _, _ in resetLeaderboardPagination() }
        .onChange(of: leaderboardDurationSeconds) { _, _ in resetLeaderboardPagination() }
        .onChange(of: leaderboardWordLimit) { _, _ in resetLeaderboardPagination() }
        .onChange(of: experienceScope) { _, _ in resetExperiencePagination() }
        .onChange(of: experiencePeriod) { _, _ in resetExperiencePagination() }
        .sheet(item: $selectedProfile) { profile in
            PublicProfileView(profile: profile, account: account)
        }
        .sheet(item: $leaderboardParameterEditor) { target in
            LeaderboardParameterEditor(
                target: target,
                initialValue: target == .duration ? leaderboardDurationSeconds : leaderboardWordLimit
            ) { value in
                switch target {
                case .duration: leaderboardDurationSeconds = value
                case .wordLimit: leaderboardWordLimit = value
                }
            }
        }
    }

    private func push() {
        let archive = localArchive
        Task {
            do {
                let cursor = try await account.pushArchive(archive)
                message = "上传完成，服务端游标为 \(cursor)。"
            } catch let RemoteAccountError.archiveSyncConflict(serverVersion) {
                do {
                    let pulled = try await account.pullArchive(fromBeginning: true)
                    guard let remoteArchive = pulled.archive,
                        let archiveVersion = pulled.archiveVersion,
                        archiveVersion >= serverVersion
                    else {
                        throw RemoteAccountError.serverMessage("无法取得服务器最新归档，未自动覆盖本机内容。")
                    }
                    let mergeResult = TypebarArchiveConflictMerge.mergeWithReport(
                        local: archive, remote: remoteArchive)
                    let summary = try LocalArchiveImport.apply(
                        mergeResult.archive, settings: settings, results: results, presets: presets,
                        savedTexts: savedTexts, resultFilterPresets: resultFilterPresets,
                        modelContext: modelContext)
                    if let scope = account.resultPublicationScope {
                        conflictAuditStore.append(mergeResult.conflicts, for: scope)
                        reloadConflictAudit()
                    }
                    account.confirmPulledArchive(pulled)
                    let cursor = try await account.pushArchive(mergeResult.archive)
                    message = "冲突已安全合并并重新上传（游标 \(cursor)）：保留本机设置与测试选择，新增 \(summary.insertedResults) 条成绩、\(summary.insertedPresets) 个预设、\(summary.insertedSavedTexts) 篇文本和 \(summary.insertedResultFilterPresets) 个成绩筛选预设；另存 \(mergeResult.conflicts.count) 个冲突副本。"
                } catch {
                    message = "已停止冲突覆盖：\(error.localizedDescription)"
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func reloadConflictAudit() {
        guard let scope = account.resultPublicationScope else {
            conflictAudit = []
            return
        }
        conflictAudit = conflictAuditStore.entries(for: scope)
    }

    private func clearConflictAudit() {
        guard let scope = account.resultPublicationScope else { return }
        conflictAuditStore.clear(for: scope)
        conflictAudit = []
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
                let summary = try LocalArchiveImport.apply(
                    archive, settings: settings, results: results, presets: presets, savedTexts: savedTexts,
                    resultFilterPresets: resultFilterPresets, modelContext: modelContext)
                account.confirmPulledArchive(pulled)
                let selectionDetail = summary.restoredActiveTestSelection ? "，并已恢复测试选择" : ""
                message = "已合并 \(summary.insertedResults) 条成绩、\(summary.insertedPresets) 个预设、\(summary.insertedSavedTexts) 篇文本和 \(summary.insertedResultFilterPresets) 个成绩筛选预设\(selectionDetail)。"
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func resetLeaderboardPagination() {
        leaderboardRequestGeneration += 1
        leaderboard = []
        leaderboardPage = nil
        leaderboardPageIndex = 0
        requestedLeaderboardPage = 1
        leaderboardMessage = nil
        leaderboardRank = nil
        leaderboardEligibility = nil
        leaderboardRankChange = nil
        loadedLeaderboardRank = false
    }

    private var pendingLeaderboardParameterFilter: LeaderboardParameterFilter {
        LeaderboardParameterFilterPolicy.filter(
            mode: leaderboardMode, durationSeconds: leaderboardDurationSeconds,
            wordLimit: leaderboardWordLimit)
    }

    private var leaderboardParameterFilter: LeaderboardParameterFilter {
        leaderboardSupportsParameterFilter
            ? pendingLeaderboardParameterFilter
            : .init(durationSeconds: nil, wordLimit: nil)
    }

    private func loadLeaderboard() {
        loadLeaderboard(pageIndex: 0)
    }

    private func loadLeaderboard(pageIndex: Int) {
        guard !isLoadingLeaderboard else { return }
        let normalizedPageIndex = max(0, pageIndex)
        let requestGeneration = leaderboardRequestGeneration
        let parameterFilter = leaderboardParameterFilter
        let selection = RemoteLeaderboardSelection(
            mode: leaderboardMode, language: leaderboardLanguage, period: leaderboardPeriod,
            durationSeconds: parameterFilter.durationSeconds, wordLimit: parameterFilter.wordLimit)
        let scope = leaderboardScope
        let accountScope = account.resultPublicationScope
        leaderboardPageIndex = normalizedPageIndex
        requestedLeaderboardPage = normalizedPageIndex + 1
        Task {
            var shouldReloadWithParameterFilter = false
            isLoadingLeaderboard = true
            defer {
                isLoadingLeaderboard = false
                if shouldReloadWithParameterFilter { loadLeaderboard() }
            }
            do {
                let page = try await account.leaderboardPage(
                    mode: selection.mode, language: selection.language,
                    period: selection.period, durationSeconds: selection.durationSeconds,
                    wordLimit: selection.wordLimit, scope: scope,
                    offset: normalizedPageIndex * LeaderboardPaginationPolicy.preferredPageSize,
                    limit: LeaderboardPaginationPolicy.preferredPageSize)
                guard requestGeneration == leaderboardRequestGeneration,
                    account.resultPublicationScope == accountScope
                else { return }
                if page.parameterFilterSupported == true {
                    let discoveredCapability = !leaderboardSupportsParameterFilter
                    leaderboardSupportsParameterFilter = true
                    if discoveredCapability && pendingLeaderboardParameterFilter.isActive {
                        leaderboardRequestGeneration += 1
                        leaderboard = []
                        leaderboardPage = nil
                        leaderboardRank = nil
                        leaderboardEligibility = nil
                        loadedLeaderboardRank = false
                        shouldReloadWithParameterFilter = true
                        return
                    }
                }
                leaderboard = page.entries
                leaderboardPage = page
                leaderboardRank = nil
                leaderboardEligibility = nil
                leaderboardRankChange = nil
                loadedLeaderboardRank = false
                if let user = account.currentUser, !user.leaderboardOptedOut {
                    do {
                        let rankStatus = try await account.leaderboardRankStatus(
                            mode: selection.mode, language: selection.language,
                            period: selection.period, durationSeconds: selection.durationSeconds,
                            wordLimit: selection.wordLimit, scope: scope)
                        guard requestGeneration == leaderboardRequestGeneration,
                            account.resultPublicationScope == accountScope
                        else { return }
                        leaderboardRank = rankStatus.entry
                        leaderboardEligibility = rankStatus.eligibility
                        loadedLeaderboardRank = true
                        if let rank = rankStatus.entry, page.rankMemorySupported == true {
                            leaderboardRankChange = try? await account.recordSpeedLeaderboardRankMemory(
                                rank: rank.rank, mode: selection.mode, language: selection.language,
                                period: selection.period, durationSeconds: selection.durationSeconds,
                                wordLimit: selection.wordLimit, scope: scope)
                            guard requestGeneration == leaderboardRequestGeneration,
                                account.resultPublicationScope == accountScope
                            else { return }
                        }
                    } catch {
                        // Older self-hosted servers may not have the rank route yet.
                    }
                }
                let summary: String
                if let total = page.total {
                    summary = total == 0
                        ? "当前筛选没有成绩。"
                        : "第 \(normalizedPageIndex + 1) / \(LeaderboardPaginationPolicy.lastPageIndex(total: total, pageSize: page.pageSize) + 1) 页，共 \(total) 条成绩。"
                } else {
                    summary = leaderboard.isEmpty ? "当前筛选没有成绩。" : "已加载 \(leaderboard.count) 条成绩。"
                }
                leaderboardMessage = !leaderboardSupportsParameterFilter
                    && pendingLeaderboardParameterFilter.isActive
                    ? "\(summary) 此服务未声明速度参数分桶，当前为通用榜单。"
                    : summary
            } catch {
                guard requestGeneration == leaderboardRequestGeneration else { return }
                leaderboard = []
                leaderboardPage = nil
                leaderboardRank = nil
                leaderboardEligibility = nil
                leaderboardRankChange = nil
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

    private func resetExperiencePagination() {
        experienceRequestGeneration += 1
        experienceLeaderboard = []
        experienceLeaderboardPage = nil
        experiencePageIndex = 0
        requestedExperiencePage = 1
        experienceMessage = nil
        experienceRank = nil
        experienceLeaderboardEligibility = nil
        experienceRankChange = nil
        loadedExperienceRank = false
    }

    private func loadExperienceLeaderboard() {
        loadExperienceLeaderboard(pageIndex: 0)
    }

    private func loadExperienceLeaderboard(pageIndex: Int) {
        guard !isLoadingExperience else { return }
        let normalizedPageIndex = max(0, pageIndex)
        let requestGeneration = experienceRequestGeneration
        let period = experiencePeriod
        let scope = experienceScope
        let accountScope = account.resultPublicationScope
        experiencePageIndex = normalizedPageIndex
        requestedExperiencePage = normalizedPageIndex + 1
        Task {
            isLoadingExperience = true
            defer { isLoadingExperience = false }
            do {
                let page = try await account.experienceLeaderboardPage(
                    period: period, scope: scope,
                    offset: normalizedPageIndex * LeaderboardPaginationPolicy.preferredPageSize,
                    limit: LeaderboardPaginationPolicy.preferredPageSize)
                guard requestGeneration == experienceRequestGeneration,
                    account.resultPublicationScope == accountScope
                else { return }
                experienceLeaderboard = page.entries
                experienceLeaderboardPage = page
                experienceRank = nil
                experienceLeaderboardEligibility = nil
                experienceRankChange = nil
                loadedExperienceRank = false
                if let user = account.currentUser, !user.leaderboardOptedOut {
                    do {
                        let rankStatus = try await account.experienceLeaderboardRankStatus(
                            period: period, scope: scope)
                        guard requestGeneration == experienceRequestGeneration,
                            account.resultPublicationScope == accountScope
                        else { return }
                        experienceRank = rankStatus.entry
                        experienceLeaderboardEligibility = rankStatus.eligibility
                        loadedExperienceRank = true
                        if let rank = rankStatus.entry, page.rankMemorySupported == true {
                            experienceRankChange = try? await account.recordExperienceLeaderboardRankMemory(
                                rank: rank.rank, period: period, scope: scope)
                            guard requestGeneration == experienceRequestGeneration,
                                account.resultPublicationScope == accountScope
                            else { return }
                        }
                    } catch {
                        // Older self-hosted servers may not have the rank route yet.
                    }
                }
                if let total = page.total {
                    experienceMessage = total == 0
                        ? "\(experiencePeriod.displayName)还没有 XP 成绩。"
                        : "第 \(normalizedPageIndex + 1) / \(LeaderboardPaginationPolicy.lastPageIndex(total: total, pageSize: page.pageSize) + 1) 页，共 \(total) 位练习者。"
                } else {
                    experienceMessage = experienceLeaderboard.isEmpty
                        ? "\(experiencePeriod.displayName)还没有 XP 成绩。"
                        : "已加载 \(experienceLeaderboard.count) 位练习者。"
                }
            } catch {
                guard requestGeneration == experienceRequestGeneration else { return }
                experienceLeaderboard = []
                experienceLeaderboardPage = nil
                experienceRank = nil
                experienceLeaderboardEligibility = nil
                experienceRankChange = nil
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
        let namedResultFilterPresets = resultFilterPresets.compactMap(\.portablePreset)
        return .init(
            exportedAt: .now,
            settings: settings.snapshot,
            results: portableResults,
            presets: namedPresets,
            savedTexts: namedSavedTexts,
            resultFilterPresets: namedResultFilterPresets,
            activeTestSelection: settings.activeTestSelection)
    }
}

private struct LeaderboardRankChangeLabel: View {
    let change: LeaderboardRankChange

    var body: some View {
        Label(change.displayName, systemImage: change.systemImage)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

private struct LeaderboardEligibilityLabel: View {
    let eligibility: RemoteLeaderboardEligibility

    var body: some View {
        let remaining = max(
            0, eligibility.minimumPracticeSeconds - eligibility.completedPracticeSeconds + 1)
        Label(
            "还需累计练习 \(Duration.seconds(Double(remaining)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))) 才能进入排行榜。",
            systemImage: "timer")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct LeaderboardRestrictionLabel: View {
    var body: some View {
        Label(
            "此账户当前被部署方限制参与共享排行榜。",
            systemImage: "exclamationmark.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct AccountSuspensionLabel: View {
    var body: some View {
        Label(
            "此账户处于部署方封禁状态，成绩可保留但不会参与共享排行榜。",
            systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct DisplayNameRequirementLabel: View {
    var body: some View {
        Label(
            "请先更新账户显示名，新的服务端成绩才能参与共享排行榜。",
            systemImage: "person.badge.exclamationmark")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct LeaderboardParameterPicker: View {
    let target: LeaderboardParameterEditorTarget
    @Binding var selectedValue: Int?
    let onCustomize: () -> Void

    var body: some View {
        Picker(target.label, selection: $selectedValue) {
            Text("全部").tag(Int?.none)
            if let selectedValue, !target.standardValues.contains(selectedValue) {
                Text("\(selectedValue) \(target.unit)").tag(Optional(selectedValue))
            }
            ForEach(target.standardValues, id: \.self) { value in
                Text("\(value) \(target.unit)").tag(Optional(value))
            }
        }
        HStack(spacing: 8) {
            Text("仅和相同\(target.label)的完成成绩比较。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("自定义…", action: onCustomize)
                .font(.caption)
        }
    }
}

private struct LeaderboardParameterEditor: View {
    @Environment(\.dismiss) private var dismiss
    let target: LeaderboardParameterEditorTarget
    let onApply: (Int) -> Void
    @State private var text: String
    @FocusState private var inputFocused: Bool

    init(
        target: LeaderboardParameterEditorTarget, initialValue: Int?,
        onApply: @escaping (Int) -> Void
    ) {
        self.target = target
        self.onApply = onApply
        _text = State(initialValue: String(initialValue ?? target.standardValues[0]))
    }

    private var value: Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
            target.validRange.contains(value)
        else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(target.label) {
                    TextField(target.unit, text: $text)
                        .focused($inputFocused)
                    if let value {
                        LabeledContent("将筛选", value: "\(value) \(target.unit)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("请输入 \(target.validRange.lowerBound)–\(target.validRange.upperBound) 之间的整数。")
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Text("排行榜只比较使用相同测试参数的成绩；此筛选不会改变你的练习设置。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(target.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        guard let value else { return }
                        onApply(value)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(value == nil)
                }
            }
        }
        .frame(width: 420, height: 270)
        .onAppear { inputFocused = true }
    }
}

private struct LeaderboardPaginationControls: View {
    let total: Int?
    let pageSize: Int
    let pageIndex: Int
    @Binding var requestedPage: Int
    let isLoading: Bool
    let myPageIndex: Int?
    let onLoadPage: (Int) -> Void

    var body: some View {
        if let total, LeaderboardPaginationPolicy.isAvailable(total: total, pageSize: pageSize) {
            if total > 0 {
                let lastPageIndex = LeaderboardPaginationPolicy.lastPageIndex(
                    total: total, pageSize: pageSize)
                HStack(spacing: 8) {
                    Button("首页") { onLoadPage(0) }
                        .disabled(isLoading || pageIndex == 0)
                    Button("上一页") { onLoadPage(max(0, pageIndex - 1)) }
                        .disabled(isLoading || pageIndex == 0)
                    TextField("页码", value: $requestedPage, format: .number)
                        .frame(width: 46)
                        .multilineTextAlignment(.trailing)
                    Button("跳转") {
                        guard let target = LeaderboardPaginationPolicy.pageIndex(
                            forDisplayPage: requestedPage, total: total, pageSize: pageSize)
                        else { return }
                        onLoadPage(target)
                    }
                    .disabled(isLoading)
                    Text("第 \(pageIndex + 1) / \(lastPageIndex + 1) 页 · 共 \(total) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let myPageIndex, myPageIndex != pageIndex {
                        Button("前往我的页") { onLoadPage(myPageIndex) }
                            .disabled(isLoading)
                    }
                    Spacer()
                    Button("下一页") { onLoadPage(min(lastPageIndex, pageIndex + 1)) }
                        .disabled(isLoading || pageIndex >= lastPageIndex)
                }
                .accessibilityElement(children: .contain)
            }
        } else {
            Text("当前自建服务未提供分页元数据；为避免重复显示，已停留在首批结果。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WPMLeaderboardRefreshCountdown: View {
    let period: RemoteLeaderboardPeriod

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let message = LeaderboardRefreshSchedule.message(for: period, at: context.date) {
                Label(message, systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel(message)
            } else {
                Text("历史周期已固定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExperienceLeaderboardRefreshCountdown: View {
    let period: RemoteExperienceLeaderboardPeriod

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let message = LeaderboardRefreshSchedule.message(for: period, at: context.date) {
                Label(message, systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel(message)
            } else {
                Text("历史周期已固定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LeaderboardAvatar: View {
    let avatar: RemoteDiscordAvatar?

    var body: some View {
        if let avatarURL = avatar?.cdnURL {
            AsyncImage(url: avatarURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())
            .accessibilityLabel("Discord 头像")
        }
    }
}

struct PublicProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let profile: RemotePublicProfile
    let account: AccountSession
    @State private var connectionMessage: String?
    @State private var isSendingRequest = false
    @State private var showingReport = false

    var body: some View {
        ScrollView {
          VStack(spacing: 20) {
            if let avatarURL = profile.discordAvatar?.cdnURL {
                AsyncImage(url: avatarURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(Circle())
                .accessibilityLabel("Discord 头像")
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.secondary)
            }
            Text(profile.displayName).font(.title2.weight(.semibold))
            if profile.accountSuspended {
                Label(
                    "此账户处于部署方封禁状态；公开详情、活动、徽章和头像已隐藏。",
                    systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let badge = profile.selectedBadge {
                Label(badge.title, systemImage: badge.systemImage)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                    .accessibilityLabel("公开徽章：\(badge.title)")
            }
            Grid(horizontalSpacing: 28, verticalSpacing: 12) {
                GridRow { metric("完成成绩", "\(profile.completedResultCount)"); metric("最佳 WPM", "\(profile.bestWPM)") }
                GridRow {
                    metric("最高稳定度", "\(profile.highestConsistency.formatted(.number.precision(.fractionLength(0...2))))%")
                    metric("总 XP", "\(profile.totalExperience)")
                }
                if let streak = profile.streak {
                    GridRow {
                        metric("当前连续", "\(streak.currentDays) 天")
                        metric("最长连续", "\(streak.longestDays) 天")
                    }
                }
            }
            Label(
                "服务端累计练习 \(totalTypingDuration) · \(profile.startedTestCount) 次开始",
                systemImage: "timer")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private var totalTypingDuration: String {
        let seconds = max(0, Int(profile.totalTypingSeconds.rounded(.down)))
        if seconds < 60 { return "\(seconds) 秒" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分钟"
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

    private static let dayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = .current
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = Calendar.current.firstWeekday
        return value
    }

    private let rows = Array(repeating: GridItem(.fixed(10), spacing: 3), count: 7)

    private var cells: [ActivityHeatmapCell] {
        ActivityHeatmap.cells(
            completedTestsByDay: activity.testsByDays, endingAt: activity.lastDay, calendar: calendar)
    }

    private var displayCells: [ActivityHeatmapDisplayCell] {
        ActivityHeatmap.displayCells(for: cells)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = max(0, calendar.firstWeekday - 1)
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var leadingFillerCount: Int {
        guard let first = cells.first else { return 0 }
        return (calendar.component(.weekday, from: first.day) - calendar.firstWeekday + 7) % 7
    }

    private var trailingFillerCount: Int {
        guard !cells.isEmpty else { return 0 }
        return (7 - (leadingFillerCount + cells.count) % 7) % 7
    }

    private var weekColumnCount: Int {
        (leadingFillerCount + cells.count + trailingFillerCount) / 7
    }

    private var monthByColumn: [Int: Date] {
        ActivityHeatmap.monthMarkers(cells: cells, calendar: calendar).reduce(into: [:]) { months, marker in
            months[marker.column] = marker.month
        }
    }

    private var completedTestCount: Int { ActivityHeatmap.completedTestCount(in: cells) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("近 12 个月公开活动 · \(completedTestCount) 次完成")
                    .font(.headline)
                Spacer()
                Text(dayBoundaryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                Text("少")
                ForEach(0...4, id: \.self) { intensity in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(opacity(for: intensity)))
                        .frame(width: 10, height: 10)
                }
                Text("多")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("公开完成次数强度图例")
            .accessibilityValue("由少到多；近 12 个月共 \(completedTestCount) 次完成")
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 3) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 10, height: 10)
                    }
                }
                .accessibilityHidden(true)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 3) {
                            ForEach(0..<weekColumnCount, id: \.self) { column in
                                Text(monthLabel(for: column))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: 10, height: 10, alignment: .leading)
                            }
                        }
                        .accessibilityHidden(true)
                        LazyHGrid(rows: rows, spacing: 3) {
                            ForEach(0..<leadingFillerCount, id: \.self) { _ in
                                Color.clear.frame(width: 10, height: 10)
                            }
                            ForEach(displayCells) { displayCell in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor.opacity(opacity(for: displayCell.intensity)))
                                    .frame(width: 10, height: 10)
                                    .accessibilityLabel(dayLabel(for: displayCell.cell.day))
                                    .accessibilityValue(
                                        displayCell.cell.completedTests == 0
                                            ? "没有完成练习" : "\(displayCell.cell.completedTests) 次完成")
                            }
                            ForEach(0..<trailingFillerCount, id: \.self) { _ in
                                Color.clear.frame(width: 10, height: 10)
                            }
                        }
                        .frame(height: 88)
                    }
                }
            }
            Text("只显示完成次数，不显示文本或输入回放。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func monthLabel(for column: Int) -> String {
        guard let month = monthByColumn[column] else { return "" }
        let index = calendar.component(.month, from: month) - 1
        guard calendar.shortMonthSymbols.indices.contains(index) else { return "" }
        return calendar.shortMonthSymbols[index]
    }

    private func dayLabel(for day: Date) -> String {
        Self.dayLabelFormatter.string(from: day)
    }

    private func opacity(for intensity: Int) -> Double {
        switch intensity {
        case 0: 0.12
        case 1: 0.35
        case 2: 0.55
        case 3: 0.75
        default: 1
        }
    }

    private var dayBoundaryLabel: String {
        let offset = activity.dayBoundaryOffsetHours
        guard offset != 0 else { return "按 UTC 日聚合" }
        let magnitude = offset.magnitude.formatted(.number.precision(.fractionLength(0...1)))
        return "按账户日界 UTC\(offset > 0 ? "+" : "−")\(magnitude)"
    }

}
