import SwiftUI

struct PreferencesView: View {
  let settings: AppSettings
  let account: AccountSession
  let hotkey: GlobalHotkeyMonitor
  @State private var accountMode: AccountMode = .login
  @State private var email = ""
  @State private var password = ""
  @State private var displayName = ""
  @State private var updatedDisplayName = ""
  @State private var updatedEmail = ""
  @State private var emailChangePassword = ""
  @State private var currentPassword = ""
  @State private var newPassword = ""
  @State private var confirmedNewPassword = ""
  @State private var accountDeletionPassword = ""
  @State private var showingAccountDeletionConfirmation = false
  @State private var submittedQuoteText = ""
  @State private var submittedQuoteAttribution = ""
  @State private var submittedQuoteLanguage: TypingLanguage = .english
  @State private var quoteSubmissionStatus: [RemoteQuoteSubmissionResponse] = []
  @State private var moderationKey = ""
  @State private var moderationStatus: RemoteQuoteModerationStatus = .pending
  @State private var moderationQuotes: [RemoteModerationQuote] = []
  @State private var profileModerationStatus: RemoteProfileModerationStatus = .open
  @State private var moderationProfileReports: [RemoteModerationProfileReport] = []
  @State private var moderationMessage: String?
  @State private var moderationIsWorking = false
  @State private var customThemeName = ""
  @State private var customThemeBackground = Color(red: 0.12, green: 0.14, blue: 0.20)
  @State private var customThemePanel = Color(red: 0.19, green: 0.22, blue: 0.30)
  @State private var customThemeAccent = Color(red: 0.95, green: 0.57, blue: 0.20)
  @State private var customThemePrefersDark = true
  @State private var searchQuery = ""

  var body: some View {
    @Bindable var settings = settings
    @Bindable var account = account
    Form {
      Section {
        TextField("搜索设置…", text: $searchQuery)
      }

      if testSectionVisible {
        Section("测试") {
          Picker("难度", selection: $settings.difficulty) {
            ForEach(Difficulty.allCases, id: \.self) { difficulty in
              Text(difficulty.displayName).tag(difficulty)
            }
          }
          Toggle("严格空格", isOn: $settings.strictSpace)
          Picker("遇错停下", selection: $settings.stopOnErrorMode) {
            ForEach(StopOnErrorMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          Text("字符会拒绝错误按键；单词允许继续输入，但在当前词完全修正前拒绝空格提交。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("遇错删除", selection: $settings.deleteOnErrorMode) {
            ForEach(DeleteOnErrorMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          Text("字符会回退一格，单词会清空当前词；硬模式在新词首个错误时返回上一词。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("隐藏额外字符", isOn: $settings.hideExtraLetters)
          Toggle("盲打", isOn: $settings.blindMode)
          Picker("快速重开按键", selection: $settings.quickRestartKey) {
            ForEach(QuickRestartKey.allCases) { key in
              Text(key.displayName).tag(key)
            }
          }
          Text("⌘R 始终可用；选定 Esc、Tab 或 Enter 后，按该键可立即重新开始当前练习。提示需要 Tab/换行时，改按 Shift+该键重开；字数达 1000 词或时长达 15 分钟时，Esc/Tab 需配合 Shift，Enter 快速重开停用。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("保存完成成绩", isOn: $settings.saveCompletedResults)
          Text("关闭后仍显示本次结果，但不会写入本机历史、统计、同步或排行榜。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("完成后自动展开单词历史", isOn: $settings.alwaysShowWordsHistory)
          Text("关闭时，结果页仍可手动展开本次单词历史；开启后会在有单词记录的结果页默认展开。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("结果页显示单词 Burst 热力图", isOn: $settings.showWordBurstHeatmap)
          Text("按本次实际输入的单词速度分档着色；没有可测输入间隔的词会保持中性。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("输入框失焦提示", isOn: $settings.showFocusWarning)
          Toggle("大写锁定提示", isOn: $settings.showCapsLockWarning)
          Toggle("错误提示音", isOn: $settings.playErrorBeep)
          Toggle("键击提示音", isOn: $settings.playKeyclickSound)
          Picker("倒计时提示音", selection: $settings.timeWarningOffset) {
            ForEach(TimeWarningOffset.allCases) { offset in
              Text(offset.displayName).tag(offset)
            }
          }
          Slider(value: $settings.soundVolume, in: 0...1, step: 0.1) {
            Text("提示音音量")
          } minimumValueLabel: {
            Text("静音")
          } maximumValueLabel: {
            Text("100%")
          }
          Text("\(Int((settings.soundVolume * 100).rounded()))% · 使用 macOS 系统提示音；三种提示均默认关闭。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("自由回退", isOn: $settings.freedomMode)
          Text("开启后，可退回并修改已正确提交的词；关闭时，仍可退回修复错误词。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("信心模式", selection: $settings.confidenceMode) {
            ForEach(ConfidenceMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          Text("开启后不可退回修改上一个错误词；最大档会禁用全部退格。与自由回退、遇错停下和遇错删除互斥。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("反向 Shift", selection: $settings.oppositeShiftMode) {
            ForEach(OppositeShiftMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          Text("“开启”使用 macOS 物理键码；“按键位图”按所选 Typebar 布局反查实际字符，适用于 QMK 等外部重映射。中间位置 6、Y、B 可使用任意一侧。错误 Shift 会按一次输入错误计分。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("代码：退格反缩进", isOn: $settings.codeUnindentOnBackspace)
          Text("仅代码语言有效：光标位于自动插入的行首 Tab 时，退格会移除整段缩进并返回上一行。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("最低准确率", isOn: minimumAccuracyEnabledBinding(settings: settings))
          if settings.minimumAccuracy > 0 {
            Stepper(value: $settings.minimumAccuracy, in: 50...100, step: 1) {
              LabeledContent("准确率门槛", value: "\(settings.minimumAccuracy)%")
            }
          }
          Text("有限测试结束时检查；未达门槛会标记失败，不保存完成成绩或发布到榜单。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("最低整体速度", isOn: minimumWpmEnabledBinding(settings: settings))
          if settings.minimumWpm > 0 {
            Stepper(value: $settings.minimumWpm, in: 10...300, step: 5) {
              LabeledContent("速度门槛", value: "\(settings.minimumWpm) WPM")
            }
          }
          Text("有限测试结束时按最终 WPM 检查；未达门槛会标记失败，不保存完成成绩或发布到榜单。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("最低单词速度", selection: $settings.minimumWordBurstMode) {
            ForEach(MinimumWordBurstMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          if settings.minimumWordBurstMode != .off {
            Stepper(value: $settings.minimumWordBurstWpm, in: 20...300, step: 5) {
              LabeledContent("最低速度", value: "\(settings.minimumWordBurstWpm) WPM")
            }
          }
          Text("固定档使用该阈值；弹性档会随目标词变长按参考公式降低阈值。空格提交词、无空格的原始词末字符和禅模式空格/换行提交都会检查；未达标会结束本次测试且不保存完成成绩。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("最后一词快速结束", isOn: $settings.quickEnd)
          Text("仅在字数、引语或有限自定义测试的最后一词达到目标长度时生效；“遇错停下”或“遇错删除”会自动禁用该行为。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("英文拼写", selection: $settings.englishVariant) {
            ForEach(EnglishVariant.allCases) { variant in
              Text(variant.displayName).tag(variant)
            }
          }
          Section("趣味修饰器") {
            ForEach(TestModifier.allCases) { modifier in
              Toggle(modifier.displayName, isOn: modifierBinding(modifier, settings: settings))
            }
            Text("边界、大小写和字符流各自互斥；记忆模式与听写/预读模式互斥。其余可兼容修饰器可以组合。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      if displaySectionVisible {
        Section("显示") {
          Picker("主题", selection: $settings.theme) {
            ForEach(AppTheme.allCases, id: \.self) { theme in
              Text(theme.displayName).tag(theme)
            }
          }
          LabeledContent("收藏内置主题") {
            HStack(spacing: 8) {
              ForEach(AppTheme.allCases, id: \.self) { theme in
                Button {
                  settings.toggleFavoriteTheme(theme)
                } label: {
                  Image(systemName: settings.isFavoriteTheme(theme) ? "star.fill" : "star")
                    .foregroundStyle(settings.isFavoriteTheme(theme) ? theme.accent : .secondary)
                }
                .buttonStyle(.borderless)
                .help(
                  settings.isFavoriteTheme(theme)
                    ? "取消收藏 \(theme.displayName)" : "收藏 \(theme.displayName)"
                )
                .accessibilityLabel(
                  settings.isFavoriteTheme(theme)
                    ? "取消收藏 \(theme.displayName)" : "收藏 \(theme.displayName)")
              }
            }
          }
          if !settings.favoriteThemeIDs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              Label("收藏主题", systemImage: "star.fill")
                .font(.caption.weight(.medium))
              ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                  ForEach(AppTheme.allCases.filter(settings.isFavoriteTheme), id: \.self) { theme in
                    Button(theme.displayName) { settings.selectBuiltInTheme(theme) }
                      .buttonStyle(.bordered)
                  }
                  ForEach(settings.customThemes.filter { settings.isFavoriteCustomTheme($0.id) }) {
                    theme in
                    Button(theme.name) { settings.selectCustomTheme(theme.id) }
                      .buttonStyle(.bordered)
                  }
                }
              }
            }
          }
          Toggle("跟随 macOS 深浅色自动切换", isOn: $settings.followSystemTheme)
          Text("开启后会使用原创纸白或午夜主题；手动主题和自定义主题会保留，关闭自动切换后恢复。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("每次新测试随机内置主题", isOn: $settings.randomThemeOnRestart)
            .disabled(settings.followSystemTheme)
          Text("开启后，重新开始或切换测试会在纸白、午夜和林地之间随机选择；跟随系统时不会随机切换。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("练习背景", selection: $settings.practiceBackdrop) {
            ForEach(PracticeBackdropStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          Toggle("减少练习背景动态效果", isOn: $settings.reducePracticeMotion)
            .disabled(settings.practiceBackdrop != .halos)
          Text("背景由 Typebar 的原生矢量绘制，不使用或下载图片。光晕会遵从 macOS“减少动态效果”辅助功能设置。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Slider(value: $settings.fontSize, in: 18...42, step: 1) {
            Text("练习字体大小")
          } minimumValueLabel: {
            Text("小")
          } maximumValueLabel: {
            Text("大")
          }
          Text("\(Int(settings.fontSize)) pt")
            .foregroundStyle(.secondary)
          Picker("练习字体", selection: $settings.practiceFont) {
            ForEach(PracticeFont.allCases) { font in
              Text(font.displayName).tag(font)
            }
          }
          Text("使用 macOS 内置字体设计，不会向本机安装或打包第三方字体。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("练习行宽", selection: $settings.practiceLineWidth) {
            ForEach(PracticeLineWidth.allCases) { width in
              Text(width.displayName).tag(width)
            }
          }
          if settings.practiceLineWidth == .custom {
            Stepper(
              value: $settings.customPracticeLineColumns, in: PracticeLineWidth.customColumnRange
            ) {
              LabeledContent("自定义列数", value: "\(settings.customPracticeLineColumns) 列")
            }
          }
          Text("紧凑、标准、宽和自定义会按当前字体大小限制每行文字；自适应会使用可用宽度。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("单行卷带", selection: $settings.practiceTapeMode) {
            ForEach(PracticeTapeMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          .onChange(of: settings.practiceTapeMode) { _, mode in
            if mode != .off { settings.showAllPracticeLines = false }
          }
          if settings.practiceTapeMode != .off {
            Slider(value: $settings.practiceTapeMargin, in: 0.1...0.9, step: 0.05) {
              Text("卷带光标位置")
            } minimumValueLabel: {
              Text("左").font(.caption)
            } maximumValueLabel: {
              Text("右").font(.caption)
            }
            Toggle("平滑卷带滚动", isOn: $settings.smoothPracticeLineScroll)
            Text("卷带只作用于单行提示，按词或按字符把当前位置保持在选定水平位置；多行文本保持普通布局。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Toggle("显示完整提示行", isOn: $settings.showAllPracticeLines)
            .disabled(settings.practiceTapeMode != .off)
          Text("仅在无计时的词、引语和自定义测试中生效：关闭时长提示保留在可滚动练习区；开启后可展开完整高度。卷带模式不支持此选项。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("光标样式", selection: $settings.caretStyle) {
            ForEach(TypingCaretStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          Text("条形和下划线保留当前目标字符，块状会高亮当前目标字符。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("错误字符显示", selection: $settings.typoIndicatorStyle) {
            ForEach(TypoIndicatorStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          Text("只改变已经输错字符的显示：可替换为实际输入，或在字符下方给出提示；不会改变提示、输入、计分或回放。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("组合输入显示", selection: $settings.compositionDisplayStyle) {
            ForEach(CompositionDisplayStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          Text("仅显示输入法尚未确认的组合文本；确认前不会进入计分。下方显示保持提示不变，替换当前字符只改变当前视觉。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("速度单位", selection: $settings.typingSpeedUnit) {
            ForEach(TypingSpeedUnit.allCases) { unit in
              Text(unit.displayName).tag(unit)
            }
          }
          Picker("显示近 10 次平均", selection: $settings.showAverage) {
            ForEach(AverageNoticeDisplay.allCases) { display in
              Text(display.displayName).tag(display)
            }
          }
          Text("按当前模式、时长或词数（引语按当前内容）、标点、数字、语言、难度和简化输入，显示最近 10 条本机完成成绩的均值。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("显示本机个人最佳", isOn: $settings.showPersonalBest)
          Text("只比较符合个人最佳资格的本机完成成绩；引语、特殊文本流和强制纠错练习不会计入。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("结果页固定显示两位小数", isOn: $settings.alwaysShowDecimalPlaces)
          Text("只影响完成结果页的速度和准确率显示；本机成绩、统计和同步仍以 WPM 保存。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("速度图从零开始", isOn: $settings.startGraphsAtZero)
          Text("关闭后，历史速度趋势图和结果速度轨迹会按实际数据范围缩放；完成次数、练习分钟和错误图仍从零开始。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("已输入字符效果", selection: $settings.typedCharacterEffect) {
            ForEach(TypedCharacterEffect.allCases) { effect in
              Text(effect.displayName).tag(effect)
            }
          }
          Text("只在一个词已通过空格提交后生效；当前词和未输入的提示保持清晰。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("实时速度显示", selection: $settings.liveSpeedStyle) {
            ForEach(LiveMetricStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          Picker("实时准确率显示", selection: $settings.liveAccuracyStyle) {
            ForEach(LiveMetricStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          Picker("实时 Burst 显示", selection: $settings.liveBurstStyle) {
            ForEach(LiveMetricStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          Picker("实时进度显示", selection: $settings.liveProgressStyle) {
            ForEach(LiveProgressStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          Text("关闭只收起相应实时仪表，不影响最终结果、历史或回放。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker("节奏引导", selection: $settings.paceGuideMode) {
            ForEach(PaceGuideMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          if settings.paceGuideMode == .custom {
            Stepper(
              value: $settings.paceGuideCustomWpm,
              in: PaceGuidePolicy.minimumWpm...PaceGuidePolicy.maximumWpm, step: 5
            ) {
              LabeledContent("目标速度", value: "\(settings.paceGuideCustomWpm) WPM")
            }
          }
          Picker("节奏光标样式", selection: $settings.paceCaretStyle) {
            ForEach(TypingCaretStyle.allCases) { style in
              Text(style.displayName).tag(style)
            }
          }
          Toggle("重开后沿用上一轮节奏一次", isOn: $settings.repeatedPace)
          Text("在练习文本中显示第二个目标标记；个人最佳和平均只比较同一模式与语言的已完成本地成绩。“上一轮速度”与自动沿用只保留在本次应用运行中。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("显示下一键键盘提示", isOn: $settings.showKeyboardGuide)
          Picker("键盘布局", selection: $settings.keyboardLayout) {
            ForEach(KeyboardLayout.allCases) { layout in
              Text(layout.displayName).tag(layout)
            }
          }
          if settings.testModifiers.contains(.layoutFluid) {
            VStack(alignment: .leading, spacing: 8) {
              Text("布局流动序列")
                .font(.subheadline.weight(.medium))
              ForEach(settings.layoutFluidLayouts.indices, id: \.self) { index in
                HStack {
                  Picker(
                    "第 \(index + 1) 段",
                    selection: Binding(
                      get: { settings.layoutFluidLayouts[index] },
                      set: { settings.setLayoutFluidLayout($0, at: index) }
                    )
                  ) {
                    ForEach(KeyboardLayout.allCases) { layout in
                      Text(layout.displayName).tag(layout)
                    }
                  }
                  if settings.layoutFluidLayouts.count > 1 {
                    Button(role: .destructive) {
                      settings.removeLayoutFluidLayout(at: index)
                    } label: {
                      Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("移除此布局")
                  }
                }
              }
              Button("添加布局", systemImage: "plus") { settings.addLayoutFluidLayout() }
                .disabled(settings.layoutFluidLayouts.count >= 5)
              Text("字数练习会按完成进度均分各段并依次切换键盘提示；最多五种不同布局。")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      if customThemeSectionVisible {
        Section("自定义主题") {
          TextField("主题名称", text: $customThemeName)
          ColorPicker("背景", selection: $customThemeBackground)
          ColorPicker("面板", selection: $customThemePanel)
          ColorPicker("强调色", selection: $customThemeAccent)
          Toggle("使用深色界面", isOn: $customThemePrefersDark)
          Button("保存并应用自定义主题") {
            settings.addCustomTheme(
              name: customThemeName,
              background: customThemeBackground,
              panel: customThemePanel,
              accent: customThemeAccent,
              prefersDark: customThemePrefersDark
            )
            customThemeName = ""
          }
          .disabled(customThemeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

          ForEach(settings.customThemes) { theme in
            HStack {
              Circle().fill(theme.accent.color).frame(width: 12, height: 12)
              Text(theme.name).lineLimit(1)
              Spacer()
              if settings.activeCustomThemeID == theme.id { Text("当前").foregroundStyle(.secondary) }
              Button("应用") { settings.selectCustomTheme(theme.id) }
              Button {
                settings.toggleFavoriteCustomTheme(theme.id)
              } label: {
                Image(systemName: settings.isFavoriteCustomTheme(theme.id) ? "star.fill" : "star")
              }
              .buttonStyle(.borderless)
              .help(
                settings.isFavoriteCustomTheme(theme.id) ? "取消收藏 \(theme.name)" : "收藏 \(theme.name)"
              )
              .accessibilityLabel(
                settings.isFavoriteCustomTheme(theme.id) ? "取消收藏 \(theme.name)" : "收藏 \(theme.name)"
              )
              Button("删除", role: .destructive) { settings.deleteCustomTheme(theme.id) }
            }
          }
          Text("自定义主题只保存于这台 Mac，并会随 Typebar 归档迁移。选择内置主题会恢复使用内置配色。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if systemSectionVisible {
        Section("系统") {
          Toggle("启用全局唤起（⌃⇧Space）", isOn: $settings.globalHotkeyEnabled)
          Text(hotkey.status.message)
            .font(.caption)
            .foregroundStyle(hotkey.status == .permissionRequired ? .orange : .secondary)
          if hotkey.status == .permissionRequired {
            Button("重新检查辅助功能权限") {
              hotkey.setEnabled(settings.globalHotkeyEnabled)
            }
          }
        }
      }

      if accountSectionVisible {
        Section("自建账户") {
          TextField("服务地址", text: $account.endpoint)
            .textContentType(.URL)
          if let user = account.currentUser {
            LabeledContent("已登录", value: user.displayName)
            Text(user.email).font(.caption).foregroundStyle(.secondary)
            TextField("公开显示名", text: $updatedDisplayName)
              .onAppear { updatedDisplayName = user.displayName }
              .onChange(of: user.displayName) { _, value in updatedDisplayName = value }
            Button("更新显示名") {
              Task { await account.updateDisplayName(updatedDisplayName) }
            }
            .disabled(
              account.isWorking
                || updatedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2
                || updatedDisplayName == user.displayName)
            Text("显示名会出现在公开资料、基础排行榜与好友列表；邮箱不会公开。")
              .font(.caption)
              .foregroundStyle(.secondary)
            Toggle(
              "从 WPM 和 XP 排行榜隐藏我",
              isOn: Binding(
                get: { user.leaderboardOptedOut },
                set: { value in Task { await account.setLeaderboardOptOut(value) } }
              )
            )
            .disabled(account.isWorking)
            Text("隐藏后不会出现在全局或好友排行榜；已保存的服务端成绩、XP、本机历史与同步不受影响。")
              .font(.caption)
              .foregroundStyle(.secondary)
            Divider()
            Text("更改登录邮箱").font(.headline)
            TextField("新邮箱", text: $updatedEmail)
              .textContentType(.emailAddress)
              .onAppear { updatedEmail = user.email }
              .onChange(of: user.email) { _, value in updatedEmail = value }
            SecureField("输入当前密码以更改邮箱", text: $emailChangePassword)
              .textContentType(.password)
            Button("更新登录邮箱") {
              Task {
                await account.changeEmail(
                  currentPassword: emailChangePassword, newEmail: updatedEmail)
                emailChangePassword = ""
              }
            }
            .disabled(
              account.isWorking || emailChangePassword.isEmpty
                || updatedEmail.trimmingCharacters(in: .whitespacesAndNewlines) == user.email)
            Text("更改成功后，其他设备上的 Typebar 登录会话会失效；新邮箱不会公开。")
              .font(.caption)
              .foregroundStyle(.secondary)
            HStack {
              Button("刷新资料") { Task { await account.refreshProfile() } }
              Button("退出登录") { account.signOut() }
            }
            Divider()
            SecureField("当前密码", text: $currentPassword)
              .textContentType(.password)
            SecureField("新密码（至少 12 字节）", text: $newPassword)
              .textContentType(.newPassword)
            SecureField("确认新密码", text: $confirmedNewPassword)
              .textContentType(.newPassword)
            Button("更新密码") {
              Task {
                await account.changePassword(
                  currentPassword: currentPassword, newPassword: newPassword)
                currentPassword = ""
                newPassword = ""
                confirmedNewPassword = ""
              }
            }
            .disabled(
              account.isWorking || currentPassword.isEmpty || newPassword.utf8.count < 12
                || newPassword != confirmedNewPassword)
            Text("更新成功后，其他设备上的 Typebar 登录会话会失效。")
              .font(.caption)
              .foregroundStyle(.secondary)
            Divider()
            Text("删除账户").font(.headline)
            SecureField("输入当前密码以删除账户", text: $accountDeletionPassword)
              .textContentType(.password)
            Button("删除自建账户…", role: .destructive) {
              showingAccountDeletionConfirmation = true
            }
            .disabled(account.isWorking || accountDeletionPassword.isEmpty)
            Text("此操作会删除此自建服务中的账户、会话、成绩、同步数据、好友关系、屏蔽和投稿；无法撤销。本机练习历史不会删除。")
              .font(.caption)
              .foregroundStyle(.secondary)
            Divider()
            Text("投稿引语").font(.headline)
            Picker("语言", selection: $submittedQuoteLanguage) {
              ForEach(TypingLanguage.allCases.filter(\.supportsQuotes), id: \.self) { language in
                Text(language.displayName).tag(language)
              }
            }
            TextField("引语正文（10–500 字符）", text: $submittedQuoteText, axis: .vertical)
              .lineLimit(3...6)
            TextField("署名或来源（可选）", text: $submittedQuoteAttribution)
            Button("提交审核") {
              Task {
                await account.submitQuote(
                  language: submittedQuoteLanguage, text: submittedQuoteText,
                  attribution: submittedQuoteAttribution.isEmpty ? nil : submittedQuoteAttribution)
                submittedQuoteText = ""
                submittedQuoteAttribution = ""
              }
            }
            .disabled(
              account.isWorking
                || !(10...500).contains(
                  submittedQuoteText.trimmingCharacters(in: .whitespacesAndNewlines).count)
            )
            Text("投稿仅保存为待审核内容，不会自动公开或替换 Typebar 自有离线引语。")
              .font(.caption)
              .foregroundStyle(.secondary)
            HStack {
              Text("我的投稿").font(.headline)
              Spacer()
              Button("刷新") {
                Task { quoteSubmissionStatus = (try? await account.quoteSubmissions()) ?? [] }
              }
              .disabled(account.isWorking)
            }
            ForEach(quoteSubmissionStatus, id: \.id) { submission in
              HStack {
                Text(
                  "\(submission.status == "pending" ? "待审核" : submission.status) · \(submission.submittedAt.formatted(date: .abbreviated, time: .shortened))"
                )
                .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if submission.status == "pending" {
                  Button("撤回", role: .destructive) {
                    Task {
                      try? await account.withdrawQuoteSubmission(submission.id)
                      quoteSubmissionStatus = (try? await account.quoteSubmissions()) ?? []
                    }
                  }
                }
              }
            }
          } else {
            Picker("操作", selection: $accountMode) {
              Text("登录").tag(AccountMode.login)
              Text("注册").tag(AccountMode.register)
            }
            .pickerStyle(.segmented)
            TextField("邮箱", text: $email)
              .textContentType(.emailAddress)
            SecureField("密码", text: $password)
              .textContentType(accountMode == .login ? .password : .newPassword)
            if accountMode == .register {
              TextField("显示名", text: $displayName)
            }
            Button(accountMode == .login ? "登录" : "创建账户") {
              Task {
                if accountMode == .login {
                  await account.login(email: email, password: password)
                } else {
                  await account.register(email: email, password: password, displayName: displayName)
                }
                password = ""
              }
            }
            .disabled(
              account.isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || password.isEmpty
                || (accountMode == .register
                  && displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            )
          }
          if account.isWorking { ProgressView() }
          if let status = account.statusMessage {
            Text(status).font(.caption).foregroundStyle(.red)
          }
        }
      }

      if moderationSectionVisible {
        Section("审核员工具") {
          SecureField("部署审核密钥（仅本次使用）", text: $moderationKey)
            .textContentType(.password)
          Picker("队列状态", selection: $moderationStatus) {
            ForEach(RemoteQuoteModerationStatus.allCases) { status in
              Text(status.displayName).tag(status)
            }
          }
          Button("读取审核队列") {
            Task { await refreshModerationQueue() }
          }
          .disabled(
            moderationIsWorking
              || moderationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          Text("密钥仅保留在当前设置窗口内，不写入 Typebar 偏好、归档或钥匙串。队列不会返回投稿者或举报者身份。")
            .font(.caption)
            .foregroundStyle(.secondary)
          if moderationIsWorking { ProgressView() }
          if let moderationMessage {
            Text(moderationMessage).font(.caption).foregroundStyle(.secondary)
          }
          ForEach(moderationQuotes) { quote in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text("\(languageTitle(quote.language)) · \(quote.status)")
                  .font(.caption.weight(.semibold))
                Spacer()
                Text(quote.submittedAt, format: .dateTime.year().month().day().hour().minute())
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
              Text(quote.text)
              if let attribution = quote.attribution {
                Text(attribution).font(.caption).foregroundStyle(.secondary)
              }
              if !quote.reports.isEmpty {
                ForEach(quote.reports) { report in
                  Text("举报：\(report.reason.displayName)\(report.note.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
              }
              if quote.status == RemoteQuoteModerationStatus.pending.rawValue {
                HStack {
                  Button("批准") { Task { await moderate(quote, as: .approved) } }
                    .buttonStyle(.borderedProminent)
                  Button("拒绝", role: .destructive) { Task { await moderate(quote, as: .rejected) } }
                }
                .disabled(moderationIsWorking)
              }
            }
            .padding(.vertical, 4)
          }
          Divider()
          Text("资料举报队列").font(.headline)
          Picker("资料举报状态", selection: $profileModerationStatus) {
            ForEach(RemoteProfileModerationStatus.allCases) { status in
              Text(status.displayName).tag(status)
            }
          }
          Button("读取资料举报") {
            Task { await refreshProfileModerationQueue() }
          }
          .disabled(
            moderationIsWorking
              || moderationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          Text("处理只更新审核状态，不会自动修改资料、删除账户、通知被举报者或透露举报者身份。")
            .font(.caption)
            .foregroundStyle(.secondary)
          ForEach(moderationProfileReports) { report in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text("\(report.profile.displayName) · \(report.status.displayName)")
                  .font(.caption.weight(.semibold))
                Spacer()
                Text(report.submittedAt, format: .dateTime.year().month().day().hour().minute())
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
              Text("\(report.reason.displayName)\(report.note.map { " · \($0)" } ?? "")")
                .font(.caption)
                .foregroundStyle(.orange)
              Text(
                "公开资料：\(report.profile.completedResultCount) 次完成 · 最佳 \(report.profile.bestWPM) WPM · \(report.profile.totalExperience) XP"
              )
              .font(.caption2)
              .foregroundStyle(.secondary)
              if report.status == .open {
                HStack {
                  Button("标为已处理") { Task { await moderateProfileReport(report, as: .resolved) } }
                    .buttonStyle(.borderedProminent)
                  Button("驳回", role: .destructive) {
                    Task { await moderateProfileReport(report, as: .dismissed) }
                  }
                }
                .disabled(moderationIsWorking)
              }
            }
            .padding(.vertical, 4)
          }
        }
      }

      if defaultsSectionVisible {
        Section {
          Button("恢复默认设置", role: .destructive) { settings.restoreDefaults() }
        }
      }

      if !hasVisibleSettings {
        Section {
          ContentUnavailableView(
            "没有匹配的设置", systemImage: "magnifyingglass", description: Text("试试“主题”、“键盘”、“账户”或“输入”。"))
        }
      }
    }
    .formStyle(.grouped)
    .confirmationDialog(
      "删除此自建账户？", isPresented: $showingAccountDeletionConfirmation, titleVisibility: .visible
    ) {
      Button("永久删除", role: .destructive) {
        Task {
          await account.deleteAccount(currentPassword: accountDeletionPassword)
          accountDeletionPassword = ""
        }
      }
    } message: {
      Text("服务端数据将永久移除。本机练习历史仍保留在这台 Mac 上。")
    }
    .frame(width: 440)
    .padding()
  }

  private var testSectionVisible: Bool {
    matches(
      "测试", "难度", "输入", "strict space", "严格空格", "stop error", "遇错停下", "delete error", "遇错删除", "盲打",
      "blind", "焦点", "focus", "大写锁定", "caps lock", "错误提示音", "键击", "音量", "声音", "sound", "beep", "自由",
      "freedom", "回退", "最低速度", "单词速度", "burst", "wpm", "修饰器", "modifier", "无空格", "下划线", "全大写",
      "uppercase", "rot13", "反写", "额外字符", "quick end", "快速结束", "字数")
  }

  private var displaySectionVisible: Bool {
    matches(
      "显示", "主题", "theme", "随机", "random", "系统", "system", "字体", "font", "等宽", "圆角", "衬线", "行宽",
      "width", "光标", "caret", "条形", "下划线", "块状", "节奏", "pace", "速度", "wpm", "个人最佳", "平均", "键盘",
      "keyboard", "布局", "layout", "下一键")
  }

  private var customThemeSectionVisible: Bool {
    matches("自定义主题", "主题", "theme", "颜色", "背景", "面板", "强调色", "深色")
  }

  private var systemSectionVisible: Bool {
    matches("系统", "全局", "唤起", "热键", "hotkey", "快捷键", "辅助功能", "accessibility")
  }

  private var accountSectionVisible: Bool {
    matches(
      "自建账户", "账户", "account", "服务", "server", "登录", "login", "注册", "邮箱", "email", "密码", "password",
      "资料", "profile", "排行榜", "榜单", "leaderboard", "删除", "注销")
  }

  private var moderationSectionVisible: Bool {
    matches("审核", "审核员", "moderation", "投稿", "引语", "队列", "密钥", "key")
  }

  private var defaultsSectionVisible: Bool {
    matches("恢复默认设置", "恢复", "默认", "reset")
  }

  private var hasVisibleSettings: Bool {
    testSectionVisible || displaySectionVisible || customThemeSectionVisible || systemSectionVisible
      || accountSectionVisible || moderationSectionVisible || defaultsSectionVisible
  }

  private func matches(_ terms: String...) -> Bool {
    SettingsSearch.matches(query: searchQuery, terms: terms)
  }

  private func modifierBinding(_ modifier: TestModifier, settings: AppSettings) -> Binding<Bool> {
    Binding(
      get: { settings.testModifiers.contains(modifier) },
      set: { enabled in
        guard enabled != settings.testModifiers.contains(modifier) else { return }
        settings.toggleTestModifier(modifier)
      }
    )
  }

  private func minimumAccuracyEnabledBinding(settings: AppSettings) -> Binding<Bool> {
    Binding(
      get: { settings.minimumAccuracy > 0 },
      set: { settings.minimumAccuracy = $0 ? max(95, settings.minimumAccuracy) : 0 }
    )
  }

  private func minimumWpmEnabledBinding(settings: AppSettings) -> Binding<Bool> {
    Binding(
      get: { settings.minimumWpm > 0 },
      set: { settings.minimumWpm = $0 ? max(60, settings.minimumWpm) : 0 }
    )
  }

  @MainActor
  private func refreshModerationQueue() async {
    moderationIsWorking = true
    defer { moderationIsWorking = false }
    do {
      moderationQuotes = try await account.moderationQuotes(
        key: moderationKey, status: moderationStatus)
      moderationMessage =
        moderationQuotes.isEmpty ? "当前筛选没有审核内容。" : "已读取 \(moderationQuotes.count) 条审核内容。"
    } catch {
      moderationQuotes = []
      moderationMessage = error.localizedDescription
    }
  }

  @MainActor
  private func moderate(_ quote: RemoteModerationQuote, as status: RemoteQuoteModerationStatus)
    async
  {
    moderationIsWorking = true
    defer { moderationIsWorking = false }
    do {
      try await account.moderateQuote(quote.id, key: moderationKey, status: status)
      moderationMessage = "已将内容标为\(status.displayName)。"
      moderationQuotes.removeAll { $0.id == quote.id }
    } catch {
      moderationMessage = error.localizedDescription
    }
  }

  @MainActor
  private func refreshProfileModerationQueue() async {
    moderationIsWorking = true
    defer { moderationIsWorking = false }
    do {
      moderationProfileReports = try await account.moderationProfileReports(
        key: moderationKey, status: profileModerationStatus)
      moderationMessage =
        moderationProfileReports.isEmpty
        ? "当前筛选没有资料举报。" : "已读取 \(moderationProfileReports.count) 条资料举报。"
    } catch {
      moderationProfileReports = []
      moderationMessage = error.localizedDescription
    }
  }

  @MainActor
  private func moderateProfileReport(
    _ report: RemoteModerationProfileReport, as status: RemoteProfileModerationStatus
  ) async {
    moderationIsWorking = true
    defer { moderationIsWorking = false }
    do {
      try await account.moderateProfileReport(report.id, key: moderationKey, status: status)
      moderationMessage = "已将资料举报标为\(status.displayName)。"
      moderationProfileReports.removeAll { $0.id == report.id }
    } catch {
      moderationMessage = error.localizedDescription
    }
  }

  private func languageTitle(_ rawValue: String) -> String {
    TypingLanguage(rawValue: rawValue)?.displayName ?? rawValue
  }
}

private enum AccountMode: Hashable {
  case login
  case register
}
