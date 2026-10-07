import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Account metadata only. Preset writes never mutate local or remote results.
struct AccountHistoryView: View {
  let settings: AppSettings
  let account: AccountSession
  var currentConfiguration: TestConfiguration? = nil
  @Environment(\.dismiss) private var dismiss
  @State private var filter = ResultHistoryFilter()
  @State private var sortField = ResultHistorySortField.finishedAt
  @State private var sortDirection = ResultHistorySortDirection.descending
  @State private var visibleLimit = ResultHistoryPagePolicy.pageSize
  @State private var selectedDay: Date?
  @State private var selectedChart: AccountResultChartSelection?
  @State private var selectedGraphResult: UUID?
  @State private var selectedGraphScope: ResultPublicationScope?
  @State private var message: String?
  @State private var presetName = ""
  @State private var deletingPreset: PresetDeletion?
  private struct PresetDeletion { let id: UUID; let name: String; let scope: ResultPublicationScope }

  private var matched: [RemoteAccountResult] {
    guard let scope = account.resultPublicationScope else { return [] }
    guard filter.accountTagFilter == nil || account.hasAccountTagDirectory else { return [] }
    return AccountHistoryQuery.matching(account.accountHistoryLoadedResults, scope: scope, filter: filter)
  }
  private var sorted: [RemoteAccountResult] {
    AccountHistoryQuery.sorted(matched, by: sortField, direction: sortDirection)
  }

  var body: some View {
    let rows = matched
    let all = AccountHistoryStatistics(rows)
    let recent = AccountHistoryStatistics(AccountHistoryQuery.latestTen(rows))
    let days = AccountHistoryQuery.days(rows)
    let graph = AccountHistoryGraphs(rows)
    let scope = account.resultPublicationScope
    NavigationStack {
      ScrollViewReader { scroll in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          scopeNotice
          presetControls
          DisclosureGroup("筛选 · \(rows.count) 条匹配") {
            AccountHistoryFilterEditor(account: account, filter: $filter)
            HStack {
              Button("清除筛选") { filter = .init(); message = nil }
              Button("使用当前练习设置", action: useCurrentSettings)
                .disabled(currentConfiguration == nil || !account.hasAccountTagDirectory)
            }
            if currentConfiguration == nil {
              Text("从主窗口的练习历史打开账户历史，可使用当前练习设置。")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          Text(ResultHistoryFilterSummaryPolicy.items(for: filter)
            .map { "\($0.category)：\($0.value)" }.joined(separator: " · "))
            .font(.caption).foregroundStyle(.secondary)
          statistics(all: all, recent: recent)
          if !rows.isEmpty {
            AccountHistoryGraphView(graph: graph, settings: settings,
              selectedID: selectedGraphScope == scope ? selectedGraphResult : nil) { id in
              guard account.resultPublicationScope == scope else { return }
              selectedGraphResult = id; selectedGraphScope = scope
              if let id, let limit = AccountHistoryGraphs.visibleLimit(for: id, in: sorted, current: visibleLimit) {
                visibleLimit = limit
              }
            }.id(scope)
          }
          if !days.isEmpty {
            AccountDailyActivityView(activity: .init(days: days, unit: settings.typingSpeedUnit,
              startsAtZero: settings.startGraphsAtZero), selectedDate: $selectedDay).id(scope)
          }
          HStack {
            Text("成绩 · 已显示 \(min(visibleLimit, rows.count)) / \(rows.count)").font(.headline)
            Spacer()
            Picker("排序", selection: $sortField) {
              ForEach(ResultHistorySortField.allCases) { Text($0.displayName).tag($0) }
            }.frame(width: 170)
            Picker("顺序", selection: $sortDirection) {
              ForEach(ResultHistorySortDirection.allCases) { Text($0.displayName).tag($0) }
            }.frame(width: 120)
          }
          if rows.isEmpty {
            ContentUnavailableView("没有匹配的账户成绩", systemImage: "line.3.horizontal.decrease.circle",
              description: Text("刷新服务端历史或调整筛选；未知配置不会被当成默认值。"))
          } else {
            LazyVStack(alignment: .leading, spacing: 12) {
              ForEach(sorted.prefix(visibleLimit)) { row in
                resultRow(row).id(row.id)
                  .overlay(RoundedRectangle(cornerRadius: 6).stroke(
                    selectedGraphResult == row.id && selectedGraphScope == scope ? Color.accentColor : .clear, lineWidth: 2))
              }
            }
            if visibleLimit < rows.count {
              Button("再显示 \(min(ResultHistoryPagePolicy.pageSize, rows.count - visibleLimit)) 条") {
                visibleLimit = ResultHistoryPagePolicy.nextLimit(current: visibleLimit, total: rows.count)
              }
            }
          }
          if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
          if let status = account.statusMessage { Text(status).font(.caption).foregroundStyle(.secondary) }
        }.padding(24)
      }
      .task(id: selectedGraphResult) {
        let id = selectedGraphResult, selectionScope = selectedGraphScope
        await Task.yield()
        guard !Task.isCancelled, let id, selectedGraphResult == id,
          selectionScope == account.resultPublicationScope, matched.contains(where: { $0.id == id }) else { return }
        withAnimation { scroll.scrollTo(id, anchor: .center) }
      }
      }
      .navigationTitle("账户历史")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
        ToolbarItem { Button("刷新") { Task { await account.refreshRemoteResults(); await account.refreshAccountFilterPresets() } }
          .disabled(account.isWorking || account.isEditingAccountFilterPresets || account.isLoadingAccountFilterPresets) }
        ToolbarItem { Button("导出筛选后的 CSV…", action: exportCSV).disabled(rows.isEmpty) }
      }
    }
    .frame(minWidth: 700, idealWidth: 850, minHeight: 520, idealHeight: 700)
    .task(id: account.resultPublicationScope) {
      if account.resultPublicationScope != nil, account.accountHistoryLoadedResults.isEmpty,
        !account.isWorking, !account.isEditingAccountTags {
        await account.refreshRemoteResults()
      }
      if account.resultPublicationScope != nil { await account.refreshAccountFilterPresets() }
    }
    .onChange(of: filter) { resetPage() }
    .onChange(of: sortField) { resetPage() }
    .onChange(of: sortDirection) { resetPage() }
    .onChange(of: account.resultPublicationScope) { filter = .init(); message = nil; presetName = ""; deletingPreset = nil; resetPage() }
    .onChange(of: account.accountTagRevision) {
      if let scope = account.resultPublicationScope, account.hasAccountTagDirectory {
        filter.accountTagFilter?.reconcile(scope: scope, knownIDs: Set(account.accountTags.map(\.id)))
      }
      resetPage()
    }
    .onChange(of: rows.map(\.id)) {
      if let selectedGraphResult, !rows.contains(where: { $0.id == selectedGraphResult }) { resetPage() }
      if let selectedChart, !rows.contains(where: { $0.id == selectedChart.id }) { self.selectedChart = nil }
    }
    .sheet(item: $selectedChart) { selection in
      AccountResultChartDetail(selection: selection, account: account, settings: settings)
    }
    .confirmationDialog("删除账户筛选预设？", isPresented: Binding(get: { deletingPreset != nil },
      set: { if !$0 { deletingPreset = nil } }), presenting: deletingPreset) { draft in
      Button("删除“\(draft.name)”", role: .destructive) {
        Task {
          do { try await account.deleteAccountFilterPreset(id: draft.id, scope: draft.scope) }
          catch { if account.resultPublicationScope == draft.scope { message = error.localizedDescription } }
        }
      }
      Button("取消", role: .cancel) { }
    } message: { _ in Text("从当前账户删除，其他设备刷新后也会移除；当前筛选和成绩不变。") }
  }

  private var presetControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("账户筛选预设").font(.headline)
        Spacer()
        Button("刷新预设") { Task { await account.refreshAccountFilterPresets() } }
          .disabled(account.isEditingAccountFilterPresets || account.isLoadingAccountFilterPresets)
      }
      Text("保存到当前账户，可在其他设备读取；与本机历史预设分开。应用预设只替换筛选，不改成绩。")
        .font(.caption).foregroundStyle(.secondary)
      ForEach(account.accountFilterPresets) { preset in
        HStack {
          Button(preset.displayName) {
            guard let scope = account.resultPublicationScope else { return }
            do { filter = try account.accountFilterPreset(id: preset.id, scope: scope); message = nil }
            catch { message = error.localizedDescription }
          }
          Spacer()
          Button("删除…", role: .destructive) {
            if let scope = account.resultPublicationScope { deletingPreset = .init(id: preset.id, name: preset.displayName, scope: scope) }
          }.accessibilityLabel("删除账户筛选预设 \(preset.displayName)")
        }.disabled(account.isEditingAccountFilterPresets || account.isLoadingAccountFilterPresets)
      }
      HStack {
        TextField("预设名称", text: $presetName).frame(maxWidth: 250)
        Button("保存当前筛选") {
          guard let scope = account.resultPublicationScope else { return }
          let snapshot = filter, name = presetName
          Task {
            do {
              try await account.saveAccountFilterPreset(name: name, filter: snapshot, scope: scope)
              if account.resultPublicationScope == scope, presetName == name { presetName = ""; message = nil }
            } catch { if account.resultPublicationScope == scope { message = error.localizedDescription } }
          }
        }.disabled(!AccountFilterPresetDocument.isValidName(AccountFilterPresetDocument.normalizedName(presetName))
          || account.accountFilterPresetCache == nil || account.isEditingAccountFilterPresets || account.isLoadingAccountFilterPresets
          || (account.accountFilterPresetCache.map { $0.list.presets.count >= $0.list.maximumPresets } ?? true))
        if let cache = account.accountFilterPresetCache { Text("\(cache.list.presets.count) / \(cache.list.maximumPresets)").font(.caption).monospacedDigit() }
      }
      Text("名称最多 16 个字母、数字、下划线、点或短横线，不能以点开头；空白自动转为下划线。")
        .font(.caption).foregroundStyle(.secondary)
      if let status = account.accountFilterPresetMessage { Text(status).font(.caption).foregroundStyle(.secondary) }
    }
  }

  private var scopeNotice: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(account.currentUser?.displayName ?? "未登录").font(.title2.weight(.semibold))
      Text("仅当前账户与服务器的已载入元数据，不含本机历史。筛选、统计、最近十条和 CSV 使用整个已载入集合，不受列表分页或排序限制。")
      if let cache = account.accountTagHistoryCache, cache.scope == account.resultPublicationScope {
        Text("已载入 \(account.accountHistoryLoadedResults.count) 条；初始最多最近 1,000 条，新接受成绩随后补入。这不是服务端全部历史或账户总计。")
        if !account.isAccountTagHistoryReady {
          Text("缓存包含尚待补齐的成绩；请刷新。当前统计只涵盖已载入记录。")
        }
      } else {
        Text("当前服务没有可用的账户标签历史缓存，仅展示已载入的近期子集。请刷新；不会声称拥有完整历史。")
      }
      Text("历史 PB 表示提交当时获得纪录，不是当前纪录。限制 PB 或引语长度时排除相应字段未知的旧记录；缺少重启或计时证据时，总计显示“未知”。")
    }.font(.caption).foregroundStyle(.secondary)
  }

  private func statistics(all: AccountHistoryStatistics, recent: AccountHistoryStatistics) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("筛选结果统计").font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 8) {
        GridRow { Text("指标"); Text("最高"); Text("平均"); Text("最近十条平均") }
          .font(.caption).foregroundStyle(.secondary)
        metricRow(settings.typingSpeedUnit.displayName, all.maximumWpm, all.averageWpm, recent.averageWpm, speed: true)
        metricRow("Raw \(settings.typingSpeedUnit.displayName)", all.maximumRaw, all.averageRaw, recent.averageRaw, speed: true)
        metricRow("准确率 %", all.maximumAccuracy, all.averageAccuracy, recent.averageAccuracy)
        metricRow("一致性 %", all.maximumConsistency, all.averageConsistency, recent.averageConsistency)
      }.monospacedDigit()
      Text("完成 \(all.completed) · 开始 \(all.started.map(String.init) ?? "未知") · 重启 \(all.restarted.map(String.init) ?? "未知") · 完成率 \(all.completionPercentage.map { "\($0)%" } ?? "未知")")
      Text("每条重启 \(AccountHistoryNumberPresentation.restartRatio(all.restartsPerCompleted)) · 练习秒数 \(number(all.timeTyping)) · 估计词数 \(number(all.estimatedWords))")
      Text("估计词数逐条四舍五入后求和；练习秒数为终次测试时长加已记录的未完成练习秒数，不在此再次扣除 AFK。最近十条按完成时间选取。")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func metricRow(_ label: String, _ maximum: Double?, _ average: Double?, _ recent: Double?, speed: Bool = false) -> some View {
    GridRow {
      Text(label)
      Text(number(maximum, speed: speed))
      Text(number(average, speed: speed))
      Text(number(recent, speed: speed))
    }
  }


  private func resultRow(_ row: RemoteAccountResult) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("\(number(row.effectiveWpm, speed: true, forceDecimals: true)) \(settings.typingSpeedUnit.displayName)").font(.headline)
        Text("Raw \(number(row.effectiveRawWpm, speed: true, forceDecimals: true)) · 准确率 \(number(row.preciseAccuracy ?? Double(row.accuracy), forceDecimals: true))% · 一致性 \(number(row.consistency, forceDecimals: true))%")
          .font(.caption).monospacedDigit()
        Spacer()
        Text(row.finishedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
      }
      Text("\(row.mode) · \(row.mode2 ?? "未知参数") · \(row.language)\(row.bailedOut == true ? " · 中止" : "")")
        .font(.caption).foregroundStyle(.secondary)
      Text("历史 PB：\(row.historicalPersonalBest.map { $0 ? "是" : "否" } ?? "未知")\(row.mode == "quote" ? " · 引语长度：\(row.quoteLength?.displayName ?? "未知")" : "")")
        .font(.caption).foregroundStyle(.secondary)
      Text(row.accountTagIDs.map { ids in
        ids.isEmpty ? "无账户标签" : ids.map { id in
          "\(account.accountTags.first { $0.id == id }?.displayName ?? "未知标签") · \(id.uuidString.prefix(8))"
        }.joined(separator: "、")
      } ?? "账户标签关联未知").font(.caption).foregroundStyle(.secondary)
      if !row.tags.isEmpty { Text("独立文字标签：\(row.tags.joined(separator: "、"))").font(.caption) }
      Button("查看速度图", systemImage: "chart.xyaxis.line") {
        if let scope = account.resultPublicationScope { selectedChart = .init(id: row.id, scope: scope) }
      }.disabled(!row.canViewPerformanceChart)
        .help(row.canViewPerformanceChart ? "按需读取这条账户成绩的匿名速度、Burst 和错误轨迹"
          : "没有保存的轨迹或超过 122 秒；不会从总成绩补造速度图")
    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
  }

  private func number(_ value: Double?, speed: Bool = false, forceDecimals: Bool = false) -> String {
    AccountHistoryNumberPresentation.text(value, unit: speed ? settings.typingSpeedUnit : nil,
      decimals: settings.alwaysShowDecimalPlaces, forceDecimals: forceDecimals)
  }

  private func resetPage() {
    visibleLimit = ResultHistoryPagePolicy.pageSize; selectedDay = nil
    selectedChart = nil
    selectedGraphResult = nil; selectedGraphScope = nil
  }

  private func useCurrentSettings() {
    guard let currentConfiguration, let scope = account.resultPublicationScope, account.hasAccountTagDirectory else { return }
    do {
      let ids = Set(try account.accountTagPostingSelection()), known = Set(account.accountTags.map(\.id))
      guard ids.isSubset(of: known) else { throw RemoteAccountError.unexpectedResponse }
      filter = .currentSettings(currentConfiguration, accountTagFilter:
        .init(scope: scope, knownIDs: known, selectedIDs: ids, includesNoTags: ids.isEmpty))
      message = nil
    } catch { message = "当前账户标签选择不可用；原有筛选保持不变。" }
  }

  private func exportCSV() {
    guard let scope = account.resultPublicationScope else { return }
    let snapshot = AccountHistoryExportSnapshot(scope: scope, rows: sorted)
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = RemoteResultCSVExport.filename(for: .now)
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard let data = snapshot.data(currentScope: account.resultPublicationScope) else {
      message = "账户或服务器已切换，未导出。"; return
    }
    do {
      try data.write(to: url, options: .atomic)
      message = "已导出筛选后的 \(snapshot.rows.count) 条已载入元数据，不含提示或回放；不是服务端全部历史。"
    } catch { message = "无法保存 CSV 文件。" }
  }
}

private struct AccountHistoryFilterEditor: View {
  let account: AccountSession
  @Binding var filter: ResultHistoryFilter

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Picker("时间范围", selection: $filter.dateRange) {
        ForEach(ResultHistoryDateRange.allCases, id: \.self) { Text($0.displayName).tag($0) }
      }
      choices("模式", TestMode.allCases, selection: Binding(get: { filter.modeSelections }, set: { filter.modes = $0 }), name: { $0.displayName })
      choices("语言", TypingLanguage.allCases, selection: Binding(get: { filter.languageSelections }, set: { filter.languages = $0 }), allowsExclusiveSelection: false, name: { $0.displayName })
      choices("难度", Difficulty.allCases, selection: Binding(get: { filter.difficultySelections }, set: { filter.difficulties = $0 }), name: { $0.displayName })
      Picker("标点", selection: $filter.punctuation) {
        ForEach(ResultHistoryBinaryFilter.allCases, id: \.self) { Text($0.displayName).tag($0) }
      }
      Picker("数字", selection: $filter.numbers) {
        ForEach(ResultHistoryBinaryFilter.allCases, id: \.self) { Text($0.displayName).tag($0) }
      }
      Picker("历史个人最佳", selection: Binding(get: { filter.effectivePersonalBestFilter }, set: {
        filter.personalBestFilter = $0; filter.personalBestOnly = false
      })) {
        ForEach(ResultHistoryPersonalBestFilter.allCases, id: \.self) { Text($0.displayName).tag($0) }
      }
      choices("时长", ResultHistoryTimeLimit.allCases, selection: $filter.timeLimits, name: { $0.displayName })
      choices("字数", ResultHistoryWordLimit.allCases, selection: $filter.wordLimits, name: { $0.displayName })
      choices("实际引语长度（限制时排除未知引语）", QuoteLength.allCases.filter { $0 != .all },
        selection: Binding(get: { filter.quoteLengthSelections }, set: { filter.quoteLengths = $0; filter.quoteLength = nil }), name: { $0.displayName })
      DisclosureGroup("修饰器：\(filter.modifierFilter.selectionSummary)") {
        Toggle("无修饰器", isOn: Binding(get: { filter.modifierFilter.includesNoModifiers }, set: {
          filter.modifierFilter.setNoModifiersSelected($0)
        })).toggleStyle(.checkbox)
        Toggle("Polyglot 多语混排", isOn: Binding(get: { filter.modifierFilter.effectiveIncludesPolyglot }, set: {
          filter.modifierFilter.includesPolyglot = $0
        })).toggleStyle(.checkbox)
        choices("选择修饰器", TestModifier.allCases, selection: Binding(get: { filter.modifierFilter.modifiers }, set: {
          filter.modifierFilter.setModifiers($0)
        }), allowsExclusiveSelection: false, name: { $0.displayName })
      }
      AccountTagHistoryFilterControls(account: account, filter: $filter.accountTagFilter, usesCompletionSnapshots: false)
      DisclosureGroup("独立文字标签：\(filter.effectiveTagFilter.selectionSummary)") {
        let available = Set(account.accountHistoryLoadedResults.flatMap(\.tags))
        Button("不限文字标签") { filter.tag = nil; filter.tagFilter = nil }
        Toggle("无文字标签", isOn: Binding(get: { filter.effectiveTagFilter.isNoTagsSelected }, set: { value in
          var tags = filter.effectiveTagFilter; tags.setNoTagsSelected(value, availableTags: available)
          filter.tag = nil; filter.tagFilter = tags
        })).toggleStyle(.checkbox)
        ForEach(available.sorted(), id: \.self) { tag in
          Toggle(tag, isOn: Binding(get: { filter.effectiveTagFilter.isTagSelected(tag) }, set: { value in
            var tags = filter.effectiveTagFilter; tags.setTag(tag, selected: value, availableTags: available)
            filter.tag = nil; filter.tagFilter = tags
          })).toggleStyle(.checkbox)
        }
      }
      Text("历史 PB 只使用接受当时的标记，未知旧记录不会冒充默认值。")
        .font(.caption).foregroundStyle(.secondary)
    }.padding(.vertical, 8)
  }

  private func choices<T: Hashable>(_ title: String, _ values: [T], selection: Binding<Set<T>>,
    allowsExclusiveSelection: Bool = true,
    name: @escaping (T) -> String) -> some View {
    DisclosureGroup("\(title)：已选 \(selection.wrappedValue.count) / \(values.count)") {
      HStack {
        Button("全选") { selection.wrappedValue = Set(values) }
        Button("全不选") { selection.wrappedValue = [] }
      }
      ForEach(values, id: \.self) { value in
        Toggle(name(value), isOn: ResultHistoryFilterChoice.binding(for: value, selection: selection,
          allowsExclusiveSelection: allowsExclusiveSelection)).toggleStyle(.checkbox)
          .help(allowsExclusiveSelection ? "按住 Shift 点击可只保留这一项。" : "点击可加入或移除此项。")
      }
    }
  }
}
