import AppKit
import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@main
struct TypebarApp: App {
  @State private var settings = AppSettings()
  @State private var account = AccountSession()
  @State private var announcements = RemoteAnnouncementCenter()
  @State private var hotkey = GlobalHotkeyMonitor()
  @State private var systemKeyboardGuide = SystemKeyboardGuideMonitor()
  @State private var network = NetworkConnectivityMonitor()

  var body: some Scene {
    WindowGroup("Typebar") {
      dataStoreContent
    }
    .windowResizability(.contentMinSize)
    .commands {
      TypebarAboutCommands()
      CommandPaletteCommands()
    }

    Settings {
      PreferencesView(settings: settings, account: account, hotkey: hotkey)
    }

    Window("关于 Typebar", id: "about") {
      AboutTypebarView(metadata: .current)
    }
    .windowResizability(.contentSize)

    Window("Typebar 版本历史", id: "release-history") {
      ReleaseHistoryView()
    }
    .windowResizability(.contentSize)

    MenuBarExtra("Typebar", systemImage: "keyboard") {
      Button("打开 Typebar") {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
      }
      Divider()
      Button("退出") { NSApp.terminate(nil) }
    }
  }

  @ViewBuilder
  private var dataStoreContent: some View {
    switch Self.dataStore {
    case .success(let container):
      rootContent.modelContainer(container)
    case .failure(let recovery):
      DataStoreRecoveryView(recovery: recovery)
        .frame(minWidth: 760, minHeight: 480)
    }
  }

  private var rootContent: some View {
    ContentView(
      settings: settings, account: account, announcements: announcements, hotkey: hotkey,
      systemKeyboardGuide: systemKeyboardGuide, network: network)
      .frame(minWidth: 760, minHeight: 480)
      .task {
        await account.restoreSession()
        await announcements.refresh(using: account)
        hotkey.setEnabled(settings.globalHotkeyEnabled)
      }
      .onChange(of: account.currentUser?.id) { _, _ in
        Task { await announcements.refresh(using: account) }
      }
  }

  private static let modelConfiguration = ModelConfiguration(
    isStoredInMemoryOnly: QAStoreMode.usesInMemoryStore(
      info: Bundle.main.infoDictionary ?? [:]))

  private static let dataStore: Result<ModelContainer, DataStoreStartupRecovery> =
    DataStoreStartupPolicy.attempt(storeURL: modelConfiguration.url) {
      try ModelContainer(
        for: TestResultRecord.self, TestPresetRecord.self, SavedCustomTextRecord.self,
        ResultFilterPresetRecord.self,
        configurations: modelConfiguration)
    }
}

struct DataStoreStartupRecovery: Error, Equatable, Sendable {
  let storeURL: URL
  let technicalDetails: String

  var diagnosticText: String {
    "Typebar 数据文件：\(storeURL.path)\n启动错误：\(technicalDetails)"
  }
}

enum DataStoreStartupPolicy {
  static func attempt<Container>(
    storeURL: URL, create: () throws -> Container
  ) -> Result<Container, DataStoreStartupRecovery> {
    do {
      return .success(try create())
    } catch {
      return .failure(
        DataStoreStartupRecovery(
          storeURL: storeURL, technicalDetails: error.localizedDescription))
    }
  }
}

private struct DataStoreRecoveryView: View {
  let recovery: DataStoreStartupRecovery

  var body: some View {
    ContentUnavailableView {
      Label("无法打开本机数据", systemImage: "externaldrive.badge.exclamationmark")
    } description: {
      VStack(spacing: 8) {
        Text("Typebar 没有删除或替换原数据文件。请先保留该文件并检查磁盘权限或可用空间，然后重新打开应用。")
        Text(recovery.storeURL.path)
          .font(.caption.monospaced())
          .textSelection(.enabled)
        Text(recovery.technicalDetails)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    } actions: {
      Button("在 Finder 中显示") {
        let selectedURL = FileManager.default.fileExists(atPath: recovery.storeURL.path)
          ? recovery.storeURL : recovery.storeURL.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([selectedURL])
      }
      Button("复制诊断信息") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recovery.diagnosticText, forType: .string)
      }
    }
  }
}

private struct NetworkConnectivityNotice: View {
  enum Kind {
    case offline
    case restored

    var title: String {
      switch self {
      case .offline: "当前离线"
      case .restored: "已恢复联网"
      }
    }

    var detail: String? {
      switch self {
      case .offline: "练习和本机保存仍可用；同步、账户、社区与榜单可能暂时不可用。"
      case .restored: nil
      }
    }

    var systemImage: String {
      switch self {
      case .offline: "wifi.slash"
      case .restored: "wifi"
      }
    }

    var color: Color {
      switch self {
      case .offline: .orange
      case .restored: .green
      }
    }
  }

  let kind: Kind

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: kind.systemImage)
      VStack(alignment: .leading, spacing: 2) {
        Text(kind.title).fontWeight(.semibold)
        if let detail = kind.detail {
          Text(detail).foregroundStyle(.secondary)
        }
      }
    }
    .font(.caption)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .stroke(kind.color.opacity(0.35), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

private enum QuoteSource: String, CaseIterable, Identifiable {
  case builtIn
  case community

  var id: Self { self }
  var title: String { self == .builtIn ? "Typebar 自有" : "社区审核" }
}

private struct CRTPracticeOverlay: View {
  var body: some View {
    Canvas { context, size in
      var line = Path()
      var y = 0.0
      while y < size.height {
        line.move(to: .init(x: 0, y: y))
        line.addLine(to: .init(x: size.width, y: y))
        y += 3
      }
      context.stroke(line, with: .color(.black.opacity(0.13)), lineWidth: 1)
    }
    .background(.green.opacity(0.045))
    .overlay(
      RoundedRectangle(cornerRadius: 20)
        .stroke(.green.opacity(0.22), lineWidth: 2)
        .shadow(color: .green.opacity(0.25), radius: 12)
    )
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct EarthquakePracticeContent<Content: View>: View {
  let isEnabled: Bool
  let reducesMotion: Bool
  @ViewBuilder let content: Content
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
      let offset = EarthquakeOffsetPolicy.offset(
        at: timeline.date, isEnabled: isEnabled,
        reducesMotion: reducesMotion || systemReduceMotion)
      content.offset(x: offset.x, y: offset.y)
    }
  }
}

private struct NauseaPracticeContent<Content: View>: View {
  let isEnabled: Bool
  let reducesMotion: Bool
  @ViewBuilder let content: Content
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
      let transform = NauseaVisualPolicy.transform(
        at: timeline.date, isEnabled: isEnabled,
        reducesMotion: reducesMotion || systemReduceMotion)
      content
        .scaleEffect(x: transform.horizontalScale, y: transform.verticalScale, anchor: .center)
        .rotation3DEffect(.degrees(transform.rotationDegrees), axis: (x: 0.45, y: 0.9, z: 0.12))
    }
  }
}

private struct RoundPracticeContent<Content: View>: View {
  let isEnabled: Bool
  let reducesMotion: Bool
  @ViewBuilder let content: Content
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
      content.rotationEffect(.degrees(RoundVisualPolicy.rotationDegrees(
        at: timeline.date, isEnabled: isEnabled,
        reducesMotion: reducesMotion || systemReduceMotion)))
    }
  }
}

private struct PromptLineBreakKey: LayoutValueKey {
  static let defaultValue = false
}

private struct PromptFlowLayout: Layout {
  var rowSpacing: CGFloat = 12

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    let availableWidth = proposal.width ?? .greatestFiniteMagnitude
    var width = 0.0
    var height = 0.0
    var rowWidth = 0.0
    var rowHeight = 0.0
    for subview in subviews {
      if subview[PromptLineBreakKey.self] {
        width = max(width, rowWidth)
        height += rowHeight + rowSpacing
        rowWidth = 0
        rowHeight = 0
        continue
      }
      let size = subview.sizeThatFits(.unspecified)
      if rowWidth > 0 && rowWidth + size.width > availableWidth {
        width = max(width, rowWidth)
        height += rowHeight + rowSpacing
        rowWidth = 0
        rowHeight = 0
      }
      rowWidth += size.width
      rowHeight = max(rowHeight, size.height)
    }
    return .init(width: proposal.width ?? max(width, rowWidth), height: height + rowHeight)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight = 0.0
    for subview in subviews {
      if subview[PromptLineBreakKey.self] {
        x = bounds.minX
        y += rowHeight + rowSpacing
        rowHeight = 0
        continue
      }
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX && x + size.width > bounds.maxX {
        x = bounds.minX
        y += rowHeight + rowSpacing
        rowHeight = 0
      }
      subview.place(at: .init(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
      x += size.width
      rowHeight = max(rowHeight, size.height)
    }
  }
}

private struct TapePracticePrompt: View {
  let prompt: AttributedString
  let typed: String
  let mode: PracticeTapeMode
  let margin: Double
  let font: Font
  let fontSize: Double
  let animatesScroll: Bool

  var body: some View {
    GeometryReader { proxy in
      let offset = PracticeTapePolicy.horizontalOffset(
        typed: typed, mode: mode, margin: margin, glyphWidth: fontSize * 0.62,
        containerWidth: proxy.size.width)
      Text(prompt)
        .font(font)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: -offset)
        .animation(animatesScroll ? .easeOut(duration: 0.16) : nil, value: offset)
    }
    .frame(height: fontSize * 1.7)
    .clipped()
    .accessibilityLabel("卷带练习提示")
  }
}

private struct ChooPracticePrompt: View {
  let glyphs: [TypingPromptGlyph]
  let font: Font
  let fontSize: Double
  let accent: Color
  let isEnabled: Bool
  let reducesMotion: Bool
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
      PromptFlowLayout {
        ForEach(Array(glyphs.enumerated()), id: \.offset) { index, glyph in
          if glyph.character == "\n" {
            Color.clear.frame(width: 0, height: 0)
              .layoutValue(key: PromptLineBreakKey.self, value: true)
          } else {
            Text(String(glyph.typedCharacter ?? glyph.character))
              .font(font)
              .foregroundStyle(color(for: glyph))
              .background(background(for: glyph))
              .rotation3DEffect(
                .degrees(ChooVisualPolicy.rotationDegrees(
                  at: timeline.date, glyphIndex: index, isEnabled: isEnabled,
                  reducesMotion: reducesMotion || systemReduceMotion)),
                axis: (x: 0, y: 1, z: 0))
          }
        }
      }
    }
  }

  private func color(for glyph: TypingPromptGlyph) -> Color {
    switch glyph.state {
    case .correct: .primary
    case .incorrect, .extra: .red
    case .current: accent
    case .pending: .secondary.opacity(0.55)
    case .hidden: .clear
    }
  }

  @ViewBuilder private func background(for glyph: TypingPromptGlyph) -> some View {
    switch glyph.state {
    case .incorrect: Color.red.opacity(0.16)
    case .extra: Color.red.opacity(0.12)
    case .current: accent.opacity(0.18)
    default: Color.clear
    }
  }
}

private struct ASLHandshapeGlyph: View {
  let character: Character
  let color: Color
  let background: Color
  let size: CGFloat

  var body: some View {
    Canvas { context, canvasSize in
      let mask = ASLHandshapePolicy.fingerMask(for: character) ?? 0
      let palm = CGRect(
        x: canvasSize.width * 0.24, y: canvasSize.height * 0.42,
        width: canvasSize.width * 0.52, height: canvasSize.height * 0.39)
      context.fill(Path(roundedRect: palm, cornerRadius: size * 0.15), with: .color(color.opacity(0.78)))
      for finger in 0..<5 {
        let x = canvasSize.width * (0.30 + Double(finger) * 0.10)
        let raised = mask & (1 << UInt8(finger)) != 0
        if raised {
          let height = finger == 0 ? canvasSize.height * 0.30 : canvasSize.height * 0.39
          let rect = CGRect(x: x, y: palm.minY - height + size * 0.04, width: size * 0.08, height: height)
          context.fill(Path(roundedRect: rect, cornerRadius: size * 0.04), with: .color(color))
        } else {
          context.fill(
            Path(ellipseIn: CGRect(x: x, y: palm.minY - size * 0.05, width: size * 0.075, height: size * 0.075)),
            with: .color(color.opacity(0.48)))
        }
      }
      if let motionCue = ASLHandshapePolicy.motionCue(for: character) {
        let lineWidth = max(1.8, size * 0.06)
        var cue = Path()
        switch motionCue {
        case .jCurve:
          cue.move(to: .init(x: canvasSize.width * 0.16, y: canvasSize.height * 0.14))
          cue.addCurve(
            to: .init(x: canvasSize.width * 0.57, y: canvasSize.height * 0.28),
            control1: .init(x: canvasSize.width * 0.47, y: canvasSize.height * 0.04),
            control2: .init(x: canvasSize.width * 0.73, y: canvasSize.height * 0.19))
          cue.addLine(to: .init(x: canvasSize.width * 0.49, y: canvasSize.height * 0.13))
          cue.move(to: .init(x: canvasSize.width * 0.57, y: canvasSize.height * 0.28))
          cue.addLine(to: .init(x: canvasSize.width * 0.43, y: canvasSize.height * 0.30))
        case .zZigzag:
          cue.move(to: .init(x: canvasSize.width * 0.13, y: canvasSize.height * 0.12))
          cue.addLine(to: .init(x: canvasSize.width * 0.70, y: canvasSize.height * 0.12))
          cue.addLine(to: .init(x: canvasSize.width * 0.23, y: canvasSize.height * 0.31))
          cue.addLine(to: .init(x: canvasSize.width * 0.79, y: canvasSize.height * 0.31))
          cue.addLine(to: .init(x: canvasSize.width * 0.65, y: canvasSize.height * 0.21))
          cue.move(to: .init(x: canvasSize.width * 0.79, y: canvasSize.height * 0.31))
          cue.addLine(to: .init(x: canvasSize.width * 0.64, y: canvasSize.height * 0.39))
        }
        context.stroke(cue, with: .color(color), lineWidth: lineWidth)
      }
    }
    .frame(width: size * 1.02, height: size * 1.10)
    .background(background, in: RoundedRectangle(cornerRadius: size * 0.12))
    .accessibilityLabel(aslAccessibilityLabel)
  }

  private var aslAccessibilityLabel: String {
    switch ASLHandshapePolicy.motionCue(for: character) {
    case .jCurve: "ASL 指语字形，J 弧线运动轨迹"
    case .zZigzag: "ASL 指语字形，Z 折线运动轨迹"
    case nil: "ASL 指语字形"
    }
  }
}

private struct ASLPracticePrompt: View {
  let glyphs: [TypingPromptGlyph]
  let fontSize: Double
  let accent: Color

  var body: some View {
    PromptFlowLayout {
      ForEach(Array(glyphs.enumerated()), id: \.offset) { _, glyph in
        if glyph.character == "\n" {
          Color.clear.frame(width: 0, height: 0)
            .layoutValue(key: PromptLineBreakKey.self, value: true)
        } else if ASLHandshapePolicy.fingerMask(for: glyph.character) != nil {
          ASLHandshapeGlyph(
            character: glyph.typedCharacter ?? glyph.character,
            color: color(for: glyph), background: background(for: glyph), size: fontSize)
        } else {
          Text(String(glyph.character))
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(color(for: glyph))
        }
      }
    }
  }

  private func color(for glyph: TypingPromptGlyph) -> Color {
    switch glyph.state {
    case .correct: .primary
    case .incorrect, .extra: .red
    case .current: accent
    case .pending: .secondary.opacity(0.55)
    case .hidden: .clear
    }
  }

  private func background(for glyph: TypingPromptGlyph) -> Color {
    switch glyph.state {
    case .incorrect: .red.opacity(0.16)
    case .extra: .red.opacity(0.12)
    case .current: accent.opacity(0.18)
    default: .clear
    }
  }
}

private struct SpacePracticeOverlay: View {
  let accent: Color

  var body: some View {
    Canvas { context, size in
      for index in 0..<54 {
        let point = StarfieldPolicy.point(index: index, in: size)
        let radius = index.isMultiple(of: 7) ? 1.4 : 0.7
        let opacity = index.isMultiple(of: 7) ? 0.72 : 0.35
        context.fill(
          Path(ellipseIn: CGRect(
            x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
          with: .color(.white.opacity(opacity)))
      }
    }
    .background(
      RadialGradient(
        colors: [.clear, accent.opacity(0.15)], center: .bottomTrailing, startRadius: 6, endRadius: 280)
    )
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct ActiveLongSavedText: Equatable {
  let id: UUID
  let title: String
  let text: String
  var progress: Int

  var remainingText: String {
    LongSavedTextProgress.remainingText(in: text, after: progress)
  }
}

private struct PendingPublicationRetryTrigger: Equatable {
  let networkStatus: NetworkConnectivityStatus
  let scope: ResultPublicationScope?
  let isEnabled: Bool
}

private struct ContentView: View {
  let settings: AppSettings
  let account: AccountSession
  let announcements: RemoteAnnouncementCenter
  let hotkey: GlobalHotkeyMonitor
  let systemKeyboardGuide: SystemKeyboardGuideMonitor
  let network: NetworkConnectivityMonitor
  @Environment(\.modelContext) private var modelContext
  @Environment(\.openSettings) private var openSettings
  @Environment(\.openWindow) private var openWindow
  @Environment(\.colorScheme) private var systemColorScheme
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Query(sort: \TestResultRecord.finishedAt, order: .reverse) private var savedResults:
    [TestResultRecord]
  @Query(sort: \TestPresetRecord.createdAt, order: .reverse) private var savedPresets:
    [TestPresetRecord]
  @State private var session = TestSessionFactory.make(configuration: .timed(seconds: 30))
  @State private var mode: TestMode = .time
  @State private var language: TypingLanguage = .english
  @State private var mixedLanguageComponents = TypingLanguage.defaultMixedComponents
  @State private var mixedLanguageSearch = ""
  @State private var contentOptions = ContentOptions()
  @State private var duration = 30
  @State private var wordLimit = 25
  @State private var selectedQuoteID = OfflineContent.quotes(for: .english)[0].id
  @State private var quoteLengths = QuoteLengthSelection.selectable
  @State private var quoteSelectionMode: QuoteSelectionMode = .lengths
  @State private var quoteQueue = QuoteQueue()
  @State private var quoteSource: QuoteSource = .builtIn
  @State private var communityQuotes: [OfflineQuote] = []
  @State private var communityQuoteRatings: [UUID: RemoteQuoteRatingResponse] = [:]
  @State private var communityQuoteMessage: String?
  @State private var isLoadingCommunityQuotes = false
  @State private var quoteReportReason: RemoteQuoteReportReason = .other
  @State private var quoteReportNote = ""
  @State private var quoteSearchQuery = ""
  @State private var quoteRatings = QuoteRatingStore()
  @State private var activeQuoteFeedback: QuoteResultFeedbackTarget?
  @State private var activeQuoteSource: ResultQuoteSource?
  @State private var customText = "A calm practice makes the next difficult sentence feel possible."
  @State private var customTextCompletion: CustomTextCompletion = .finish
  @State private var customTextDuration = 30
  @State private var customTextWordLimit = 25
  @State private var customTextSectionLimit = 1
  @State private var customTextOrdering: CustomTextOrdering = .inOrder
  @State private var activeLongSavedText: ActiveLongSavedText?
  @State private var activeSessionTags: [String] = []
  @State private var activeResultTagDraft = ""
  @State private var practiceReturnPreset: SavedTestPreset?
  @State private var showingHistory = false
  @State private var showingWeakSpots = false
  @State private var showingPresets = false
  @State private var showingDataMigration = false
  @State private var showingSavedTexts = false
  @State private var showingSaveCustomText = false
  @State private var showingWordFilter = false
  @State private var showingCustomTextGenerator = false
  @State private var completedResult: CompletedResultPresentation?
  @State private var localResultSaveState: LocalResultSaveState = .notRequested
  @State private var savedResultRecord: TestResultRecord?
  @State private var publicationState: ResultPublicationState = .idle
  @State private var publicationResultID: UUID?
  @State private var pendingPublications = PendingResultPublicationStore()
  @State private var isRetryingPendingPublications = false
  @State private var terminalNotice: TestTerminalNotice?
  @State private var bailoutConfirmationMessage: String?
  @State private var showingSync = false
  @State private var syncInitialLeaderboard: RemoteLeaderboardSelection?
  @State private var showingConnections = false
  @State private var showingNotifications = false
  @State private var unreadNotificationCount: Int?
  @State private var showingCommandPalette = false
  @State private var showingPaceGuideSpeedEditor = false
  @State private var showingKeyboardGuideScaleEditor = false
  @State private var showingCustomTimeEditor = false
  @State private var showingCustomWordsEditor = false
  @State private var practiceThresholdEditorKind: PracticeThresholdEditorKind?
  @State private var showingCommandBailoutConfirmation = false
  @State private var showingTestShare = false
  @State private var showingChallenges = false
  @State private var activeChallengeID: String?
  @State private var focusRequest = 0
  @State private var inputHasFocus = false
  @State private var focusWarningDelayElapsed = false
  @State private var focusWarningSequence = 0
  @State private var capsLockEnabled = false
  @State private var lastTimeWarningSecond: Int?
  @State private var restartLockMessage: String?
  @State private var currentRestartCount = 0
  @State private var lastCompletedWpm: Int?
  @State private var currentProcessPractice: [CurrentProcessPractice] = []
  @State private var repeatedPaceArmed = false
  @State private var activePaceTargetWpm: Int?
  @State private var compositionText = ""
  @State private var keyboardGuideFeedback: KeyboardGuideFeedback?
  @State private var keyboardGuideFeedbackSequence = 0
  @State private var keyboardModifierFlags: NSEvent.ModifierFlags = []
  @State private var typingCompanionHands = TypingCompanionHands()
  @State private var typingPowerParticles: [TypingPowerParticle] = []
  @State private var typingPowerGeneration = 0
  @State private var typingPowerShakeOffset = CGSize.zero
  @State private var liveContentRequestID = UUID()
  @State private var isLoadingLiveContent = false
  @State private var liveContentMessage: String?
  @State private var zipfNotice: String?
  @State private var zipfNoticeGeneration = 0
  @State private var showsNetworkRecoveryNotice = false

  var body: some View {
    VStack(spacing: 30) {
      header
      RemoteAnnouncementBannerStack(center: announcements)
      configurationPanel
      if let zipfNotice {
        Label(zipfNotice, systemImage: "exclamationmark.triangle")
          .font(.caption.weight(.medium))
          .foregroundStyle(.orange)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.thinMaterial, in: Capsule())
          .accessibilityLabel(zipfNotice)
      }
      if let averageNotice {
        Label(averageNotice, systemImage: "chart.bar")
          .font(.caption.weight(.medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.thinMaterial, in: Capsule())
          .accessibilityLabel(averageNotice)
      }
      if let personalBestNotice {
        Label(personalBestNotice, systemImage: "crown")
          .font(.caption.weight(.medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.thinMaterial, in: Capsule())
          .accessibilityLabel(personalBestNotice)
      }
      typingPanel
      stats
      if effectiveKeyboardGuideMode != .off {
        KeyboardGuide(
          nextCharacter: session.nextExpectedCharacter, mode: effectiveKeyboardGuideMode,
          feedback: keyboardGuideFeedback, accent: activeTheme.accent,
          panel: activeTheme.panel, layout: effectiveKeyboardLayout,
          overrideRows: effectiveKeyboardGuideOverrideRows,
          mirrored: settings.testModifiers.contains(.mirrorKeyboard),
          scale: settings.keyboardGuideScale, legendStyle: settings.keyboardGuideLegendStyle,
          keysMode: settings.keyboardGuideKeysMode,
          style: settings.keyboardGuideStyle,
          modifierFlags: keyboardModifierFlags, capsLockEnabled: capsLockEnabled)
      }
      controls
      practiceKeyTips
    }
    .padding(42)
    .fixedSize(horizontal: false, vertical: showsAllPracticeLines)
    .background(
      CustomPracticeBackground(
        fallbackStyle: settings.practiceBackdrop, theme: activeTheme,
        reduceMotion: settings.reducePracticeMotion,
        remoteURL: settings.customBackgroundURL, fit: settings.customBackgroundFit,
        filter: settings.customBackgroundFilter,
        localImageRevision: settings.localBackgroundRevision)
    )
    .overlay(alignment: .top) {
      if network.showsOfflineBanner, !session.hasStarted {
        NetworkConnectivityNotice(kind: .offline)
          .padding(.top, 12)
      } else if showsNetworkRecoveryNotice, network.status == .online {
        NetworkConnectivityNotice(kind: .restored)
          .padding(.top, 12)
      }
    }
    .tint(activeTheme.accent)
    .preferredColorScheme(settings.followSystemTheme ? nil : activeTheme.colorScheme)
    .focusedSceneValue(\.openCommandPalette) { showingCommandPalette = true }
    .onChange(of: settings.globalHotkeyEnabled) { _, enabled in hotkey.setEnabled(enabled) }
    .onChange(of: settings.paceGuideMode) { _, _ in refreshPaceTarget() }
    .onChange(of: settings.paceGuideCustomWpm) { _, _ in refreshPaceTarget() }
    .onChange(of: settings.testModifiers) { _, _ in refreshZipfNotice() }
    .onChange(of: network.recoveryEventID) { _, eventID in
      guard eventID > 0 else { return }
      showsNetworkRecoveryNotice = true
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        guard network.recoveryEventID == eventID else { return }
        showsNetworkRecoveryNotice = false
      }
    }
    .onChange(of: settings.typingPowerMode) { _, mode in
      if !mode.isEnabled { clearTypingPowerEffect() }
    }
    .task { await runClock() }
    .task(id: pendingPublicationRetryTrigger) { retryPendingPublicationsIfPossible() }
    .task(id: account.currentUser?.id) { await refreshNotificationSummary() }
    .onAppear {
      reset()
      refreshZipfNotice()
    }
    .onChange(of: session.outcome) { _, outcome in
      switch outcome {
      case .completed, .bailedOut, .invalidAFK:
        let restartCount = currentRestartCount
        guard let result = session.result(
          tags: activeSessionTags, restartCount: restartCount, quoteSource: activeQuoteSource
        ) else { return }
        currentRestartCount = 0
        let updatedLongTextProgress = updateLongSavedTextProgress(for: result.outcome)
        lastCompletedWpm = result.wpm
        repeatedPaceArmed = settings.repeatedPace
        let savesResult = result.outcome == .completed && settings.saveCompletedResults
        let resultPersonalBestFeedback = savesResult
          ? ResultPersonalBestPolicy.feedback(
            for: result, previousResults: savedResults.compactMap(\.portableResult))
          : nil
        let tagPersonalBestFeedback = savesResult
          ? TagPersonalBestPolicy.feedback(
            for: result, previousResults: savedResults.compactMap(\.portableResult))
          : []
        let wordReviews = session.wordReviews
        let wordBursts = session.wordBurstHistory
        let missedWordPractice = MissedWordPracticePlan.make(errorCounts: session.missedWordErrorCounts)
        let slowWordPractice = SlowWordPracticePlan.make(reviews: wordReviews, bursts: wordBursts)
        let contextualMissedPractice = ContextualMissedWordPracticePlan.make(
          reviews: wordReviews, errorCounts: session.missedWordErrorCountsByWord)
        let repeatedSession = session.repeatedAttempt()
        localResultSaveState = .notRequested
        savedResultRecord = nil
        publicationResultID = result.id
        publicationState = .idle
        if result.outcome == .completed {
          currentProcessPractice.append(.init(result: result))
          settings.randomizeTheme(for: systemColorScheme)
        }
        if ResultSavingPolicy.shouldPersist(outcome: result.outcome, enabled: savesResult) {
          saveCompletedResultLocally(result)
        }
        completedResult = .init(
          result: result,
          savesResult: savesResult,
          quoteFeedback: activeQuoteFeedback,
          resultPersonalBestFeedback: resultPersonalBestFeedback,
          tagPersonalBestFeedback: tagPersonalBestFeedback,
          missedWords: missedWordPractice?.selectedWords ?? [],
          missedWordPracticeWords: missedWordPractice?.exerciseWords ?? [],
          wordReviews: wordReviews,
          wordBursts: wordBursts,
          slowWordPractice: slowWordPractice,
          missedAndSlowPractice: MissedAndSlowWordPracticePlan.make(
            missed: missedWordPractice, slow: slowWordPractice),
          contextualMissedAndSlowPractice: ContextualMissedAndSlowWordPracticePlan.make(
            contextual: contextualMissedPractice, slow: slowWordPractice),
          contextualMissedPractice: contextualMissedPractice,
          todayPractice: todayPracticeSummary,
          repeatedSession: repeatedSession,
          challengeEvaluation: result.outcome == .completed
            ? TypebarChallengeLibrary.challenge(
              id: result.configuration.challengeID
            ).map { ChallengeEvaluator.evaluate(result, challenge: $0) }
            : nil
        )
        if savesResult, ResultSavingPolicy.shouldPublish(localSaveState: localResultSaveState) {
          publishIfEnabled(result)
        } else if result.outcome == .bailedOut {
          publicationResultID = nil
          publicationState = .notice(
            updatedLongTextProgress
              ? "长文本进度已保存；本次结果只在当前窗口显示，不会保存、本机统计、同步或发布。"
              : "本次已中止：结果只在当前窗口显示，不会保存、本机统计、同步或发布。")
        } else if result.outcome == .invalidAFK {
          publicationResultID = nil
          publicationState = .notice(
            "检测到结束前持续闲置；本次结果只在当前窗口显示，不会保存、本机统计、同步或发布。")
        } else {
          publicationResultID = nil
          publicationState = .notice("练习模式：本次成绩不会保存、本机统计、同步或发布。")
        }
      case .failed:
        terminalNotice = .failed(savedLongTextProgress: updateLongSavedTextProgress(for: outcome))
      case .abandoned:
        terminalNotice = .abandoned
      case .active:
        break
      }
    }
    .toolbar {
      Button("命令", systemImage: "command") { showingCommandPalette = true }
        .keyboardShortcut("k", modifiers: [.command, .shift])
      Button("分享", systemImage: "square.and.arrow.up") { showingTestShare = true }
      Button("预设", systemImage: "slider.horizontal.3") { showingPresets = true }
      Button("挑战", systemImage: "flag.checkered") { showingChallenges = true }
      Button("历史", systemImage: "clock.arrow.circlepath") { showingHistory = true }
      Button("弱项", systemImage: "scope") { showingWeakSpots = true }
      Button("数据", systemImage: "externaldrive") { showingDataMigration = true }
      Button("同步", systemImage: "arrow.triangle.2.circlepath") {
        syncInitialLeaderboard = nil
        showingSync = true
      }
      Button("好友", systemImage: "person.2") { showingConnections = true }
      Button { showingNotifications = true } label: {
        HStack(spacing: 4) {
          Label("通知", systemImage: "bell")
          if let unreadNotificationCount, unreadNotificationCount > 0 {
            Text("\(unreadNotificationCount)")
              .font(.caption2.monospacedDigit().weight(.semibold))
              .padding(.horizontal, 5)
              .padding(.vertical, 2)
              .background(activeTheme.accent, in: Capsule())
              .foregroundStyle(activeTheme.background)
          }
        }
      }
      .accessibilityLabel(notificationAccessibilityLabel)
    }
    .sheet(isPresented: $showingHistory) {
      ResultsHistoryView(settings: settings, currentConfiguration: configuration)
    }
    .sheet(isPresented: $showingWeakSpots) {
      WeakSpotHistoryView(
        initialLanguage: language, englishVariant: settings.englishVariant,
        onStart: startWeakSpotPractice(prompt:language:))
    }
    .sheet(isPresented: $showingPresets) {
      PresetLibraryView(currentPreset: presetDefinition, onApply: apply)
    }
    .sheet(isPresented: $showingChallenges) {
      ChallengeLibraryView(onSelect: loadChallenge)
    }
    .sheet(isPresented: $showingDataMigration) {
      ArchiveManagementView(settings: settings)
    }
    .sheet(isPresented: $showingSync, onDismiss: { syncInitialLeaderboard = nil }) {
      CloudSyncView(
        settings: settings, account: account, initialLeaderboard: syncInitialLeaderboard)
    }
    .sheet(isPresented: $showingConnections) {
      ConnectionsView(account: account)
    }
    .sheet(isPresented: $showingNotifications, onDismiss: {
      Task { await refreshNotificationSummary() }
    }) {
      NotificationsView(account: account) { unreadNotificationCount = $0 }
    }
    .sheet(isPresented: $showingCommandPalette) {
      CommandPaletteView(
        items: commandPaletteItems, listMode: settings.commandPaletteListMode, onSelect: runCommand)
    }
    .sheet(isPresented: $showingPaceGuideSpeedEditor) {
      PaceGuideSpeedEditor(
        unit: settings.typingSpeedUnit, initialWpm: settings.paceGuideCustomWpm
      ) { wpm in
        activeChallengeID = nil
        settings.paceGuideCustomWpm = wpm
        settings.paceGuideMode = .custom
        reset()
      }
    }
    .sheet(isPresented: $showingKeyboardGuideScaleEditor) {
      KeyboardGuideScaleEditor(initialScale: settings.keyboardGuideScale) { scale in
        settings.keyboardGuideScale = scale
      }
    }
    .sheet(isPresented: $showingCustomTimeEditor) {
      TestLimitEditor(kind: .time, initialValue: duration) { value in
        activeChallengeID = nil
        mode = .time
        duration = value
        reset()
      }
    }
    .sheet(isPresented: $showingCustomWordsEditor) {
      TestLimitEditor(kind: .words, initialValue: wordLimit) { value in
        activeChallengeID = nil
        mode = .words
        wordLimit = value
        reset()
      }
    }
    .sheet(item: $practiceThresholdEditorKind) { kind in
      PracticeThresholdEditor(
        kind: kind, unit: settings.typingSpeedUnit,
        initialCanonicalValue: practiceThresholdValue(for: kind)
      ) { value in
        applyPracticeThreshold(value, kind: kind)
      }
    }
    .confirmationDialog(
      "中止当前长测试？", isPresented: $showingCommandBailoutConfirmation,
      titleVisibility: .visible
    ) {
      Button("中止并显示未保存结果", role: .destructive) { session.bailOut() }
    } message: {
      Text("结果不会保存、本机统计、同步或发布。")
    }
    .sheet(isPresented: $showingTestShare) {
      TestConfigurationShareView(currentPreset: presetDefinition, onApply: apply)
    }
    .sheet(isPresented: $showingSavedTexts) {
      SavedTextsView(onUse: loadSavedCustomText)
    }
    .sheet(isPresented: $showingSaveCustomText) {
      SaveCustomTextView(text: customText)
    }
    .sheet(isPresented: $showingWordFilter) {
      WordFilterView(language: language) { text, appending in
        applyGeneratedCustomText(text, appending: appending)
      }
    }
    .sheet(isPresented: $showingCustomTextGenerator) {
      CustomTextGeneratorView { text, appending in
        applyGeneratedCustomText(text, appending: appending)
      }
    }
    .sheet(item: $completedResult) { result in
      completedResultSheet(result)
    }
    .alert(item: $terminalNotice) { notice in
      Alert(
        title: Text(notice.title),
        message: Text(notice.message),
        dismissButton: .default(Text("重新开始"), action: { reset() })
      )
    }
  }

  private func completedResultSheet(_ result: CompletedResultPresentation) -> some View {
      CompletedResultView(
        result: result.result,
        savesResult: result.savesResult,
        typingSpeedUnit: settings.typingSpeedUnit,
        alwaysShowDecimalPlaces: settings.alwaysShowDecimalPlaces,
        alwaysShowWordsHistory: settings.alwaysShowWordsHistory,
        showWordBurstHeatmap: settings.showWordBurstHeatmap,
        startGraphsAtZero: settings.startGraphsAtZero,
        resultPerformanceVisibility: settings.resultPerformanceVisibility,
        background: activeTheme.background,
        panel: activeTheme.panel,
        accent: activeTheme.accent,
        colorScheme: activeTheme.colorScheme,
        publicationState: publicationState,
        localResultSaveState: localResultSaveState,
        isOffline: network.showsOfflineBanner,
        savedResultRecord: localResultSaveState.isSaved ? savedResultRecord : nil,
        quoteFeedback: result.quoteFeedback,
        resultPersonalBestFeedback: result.resultPersonalBestFeedback,
        tagPersonalBestFeedback: result.tagPersonalBestFeedback,
        settings: settings,
        quoteRatings: quoteRatings,
        isSignedIn: account.currentUser != nil,
        initialCommunityRating: result.quoteFeedback?.communityQuoteID.flatMap {
          communityQuoteRatings[$0]
        },
        onRateCommunity: { quoteID, value in
          let rating = try await account.rateQuote(quoteID, value: value)
          communityQuoteRatings[quoteID] = rating
          return rating
        },
        onReportCommunity: { quoteID, reason, note in
          try await account.reportQuote(quoteID, reason: reason, note: note)
        },
        onRestart: {
          completedResult = nil
          if restoreWordPracticeIfNeeded() { return }
          attemptRestart()
        },
        onHistory: {
          completedResult = nil
          showingHistory = true
        },
        missedWords: result.missedWords,
        missedWordPracticeWords: result.missedWordPracticeWords,
        wordReviews: result.wordReviews,
        wordBursts: result.wordBursts,
        slowWordPractice: result.slowWordPractice,
        missedAndSlowPractice: result.missedAndSlowPractice,
        contextualMissedAndSlowPractice: result.contextualMissedAndSlowPractice,
        contextualMissedPractice: result.contextualMissedPractice,
        todayPractice: result.todayPractice,
        onRepeat: {
          completedResult = nil
          startRepeatedAttempt(result.repeatedSession, tags: result.result.tags)
        },
        challengeEvaluation: result.challengeEvaluation,
        onResultPerformanceVisibilityChange: { settings.resultPerformanceVisibility = $0 },
        onResultGraphScaleChange: { settings.startGraphsAtZero = $0 },
        onRetryPublication: { publishIfEnabled(result.result) },
        onRetryLocalSave: {
          saveCompletedResultLocally(result.result)
          if ResultSavingPolicy.shouldPublish(localSaveState: localResultSaveState) {
            publishIfEnabled(result.result)
          }
        },
        onOpenDailyLeaderboard: {
          completedResult = nil
          syncInitialLeaderboard = .init(
            mode: result.result.configuration.mode,
            language: result.result.configuration.language,
            period: .day)
          showingSync = true
        },
        onPracticeMissedWords: {
          startWordPractice(
            result.missedWordPracticeWords, selectedTargetCount: result.missedWords.count)
        },
        onPracticeContextualMissedWords: { words, selectedTargetCount in
          startWordPractice(words, selectedTargetCount: selectedTargetCount)
        },
        onPracticeSlowWords: { words, selectedTargetCount in
          startWordPractice(words, selectedTargetCount: selectedTargetCount)
        },
        onPracticeMissedAndSlowWords: { words, selectedTargetCount in
          startWordPractice(words, selectedTargetCount: selectedTargetCount)
        },
        onPracticeContextualMissedAndSlowWords: { words, selectedTargetCount in
          startWordPractice(words, selectedTargetCount: selectedTargetCount)
        }
      )
  }

  private func runClock() async {
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 100_000_000)
      guard !Task.isCancelled else { return }
      advanceClock(at: .now)
    }
  }

  @MainActor
  private func refreshNotificationSummary() async {
    guard let userID = account.currentUser?.id else {
      unreadNotificationCount = nil
      return
    }
    unreadNotificationCount = nil
    guard let inbox = try? await account.notificationInbox(), account.currentUser?.id == userID else {
      return
    }
    unreadNotificationCount = inbox.unreadCount
  }

  private var notificationAccessibilityLabel: String {
    guard let unreadNotificationCount, unreadNotificationCount > 0 else { return "通知" }
    return "通知，\(unreadNotificationCount) 条未读"
  }

  private func advanceClock(at now: Date) {
    capsLockEnabled = NSEvent.modifierFlags.contains(.capsLock)
    session.tick(at: now)
    let remaining = session.remainingSeconds(at: now)
    if TimeWarningPolicy.shouldPlay(
      remainingSeconds: remaining, previousSecond: lastTimeWarningSecond,
      offset: settings.timeWarningOffset)
    {
      TypingFeedbackSound.shared.playTimeWarning(
        style: settings.timeWarningSoundStyle, volume: settings.soundVolume)
    }
    lastTimeWarningSecond = remaining
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("typebar").font(.system(size: 28, weight: .bold, design: .rounded))
        Text("离线、专注的 Mac 打字练习").foregroundStyle(.secondary)
      }
      Spacer()
      Picker("模式", selection: $mode) {
        ForEach(TestMode.allCases, id: \.self) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 420)
      .disabled(activeChallenge != nil)
      .onChange(of: mode) { _, nextMode in
        // A deliberate departure from temporary word practice becomes the
        // user's new source configuration, matching the reference reset rule.
        if nextMode != .custom { practiceReturnPreset = nil }
        reset()
      }
    }
  }

  @ViewBuilder
  private var configurationPanel: some View {
    @Bindable var settings = settings
    VStack(alignment: .leading, spacing: 14) {
      if let activeChallenge {
        VStack(alignment: .leading, spacing: 5) {
          Label(activeChallenge.title, systemImage: "flag.checkered")
            .font(.headline)
          Text(activeChallenge.requirements.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("退出挑战") {
            activeChallengeID = nil
            reset()
          }
        }
        .padding(12)
        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
      } else {
        if mode != .custom && mode != .zen {
          Picker("语言", selection: $language) {
            ForEach(availableLanguages, id: \.self) { language in
              Text(language.displayName).tag(language)
            }
          }
          .onChange(of: language) { _, language in
            languageChanged(to: language)
            refreshZipfNotice()
          }
          if language == .arabic {
            Toggle("Arabic 快速输入（省略元音符号）", isOn: $settings.prefersArabicLazyInput)
              .onChange(of: settings.prefersArabicLazyInput) { _, _ in reset() }
            Text("默认开启；会省略短元音、tanwin、shadda、sukun，并统一常见的 alef 变体。关闭后保留完整原创 Arabic 提示。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if language == .english {
            Picker("英文拼写", selection: $settings.englishVariant) {
              ForEach(EnglishVariant.allCases) { variant in
                Text(variant.displayName).tag(variant)
              }
            }
            .onChange(of: settings.englishVariant) { _, _ in
              reset()
            }
          }
          if language == .mixedLanguages {
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text("多语组合（至少选择两种）").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("已选 \(mixedLanguageComponents.count) / \(TypingLanguage.mixableLanguages.count)")
                  .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
              }
              TextField("搜索语言或代码词表", text: $mixedLanguageSearch)
                .textFieldStyle(.roundedBorder)
              ScrollView {
                LazyVGrid(
                  columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading,
                  spacing: 6
                ) {
                  ForEach(
                    TypingLanguage.filteredMixableLanguages(query: mixedLanguageSearch), id: \.self
                  ) { component in
                    Toggle(component.displayName, isOn: mixedLanguageBinding(for: component))
                      .toggleStyle(.checkbox)
                  }
                }
              }
              .frame(maxHeight: 220)
            }
          }
        }

        if mode == .time || mode == .words {
          HStack {
            Toggle("标点", isOn: $contentOptions.includePunctuation)
            Toggle("数字", isOn: $contentOptions.includeNumbers)
          }
          .onChange(of: contentOptions) { _, _ in reset() }
        }

        if !settings.testModifiers.isEmpty {
          Label(
            "修饰器：\(settings.testModifiers.map(\.displayName).joined(separator: "、"))",
            systemImage: "wand.and.stars"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        if configuration.isInfinite, !infiniteIncompatibleModifiers.isEmpty {
          Label(
            "无限测试已停用以下修饰器：\(infiniteIncompatibleModifiers.map(\.displayName).joined(separator: "、"))",
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(.orange)
        } else if offersInfiniteSelection, !infiniteIncompatibleModifiers.isEmpty {
          Label(
            "先关闭这些有限长度修饰器才能启用无限测试：\(infiniteIncompatibleModifiers.map(\.displayName).joined(separator: "、"))",
            systemImage: "info.circle"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        activeResultTagControls

        if let liveContentMessage {
          HStack(spacing: 7) {
            if isLoadingLiveContent { ProgressView().controlSize(.small) }
            Label(liveContentMessage, systemImage: "network")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        switch mode {
        case .time:
          Toggle("无限计时", isOn: infiniteBinding($duration, fallback: 30))
            .disabled(duration != 0 && !infiniteIncompatibleModifiers.isEmpty)
          if duration == 0 {
            Text("计时器正向累计；使用 Bail Out 或双击 Shift+Enter 结束并查看未保存结果。")
              .font(.caption).foregroundStyle(.secondary)
          } else {
            Stepper(value: $duration, in: 1...OfficialTestLimitInput.maximumValue, step: 1) {
              LabeledContent("时长", value: "\(duration) 秒")
            }
            .onChange(of: duration) { _, _ in reset() }
          }
        case .words:
          Toggle("无限字数", isOn: infiniteBinding($wordLimit, fallback: 25))
            .disabled(wordLimit != 0 && !infiniteIncompatibleModifiers.isEmpty)
          if wordLimit == 0 {
            Text("词数持续累计；使用 Bail Out 或双击 Shift+Enter 结束并查看未保存结果。")
              .font(.caption).foregroundStyle(.secondary)
          } else {
            Stepper(value: $wordLimit, in: 1...OfficialTestLimitInput.maximumValue) {
              LabeledContent("字数", value: "\(wordLimit) 词")
            }
            .onChange(of: wordLimit) { _, _ in reset() }
          }
        case .quote:
          Picker("内容来源", selection: $quoteSource) {
            ForEach(availableQuoteSources) { source in Text(source.title).tag(source) }
          }
          .pickerStyle(.segmented)
          .onChange(of: quoteSource) { _, source in
            if source == .community {
              refreshCommunityQuotes()
              return
            }
            quoteQueue.reset()
            ensureSelectedQuote()
            reset()
          }
          Picker("引语选择", selection: $quoteSelectionMode) {
            ForEach(QuoteSelectionMode.allCases) { selectionMode in
              Text(selectionMode.displayName).tag(selectionMode)
            }
          }
          .pickerStyle(.segmented)
          .onChange(of: quoteSelectionMode) { _, selectionMode in
            quoteQueue.reset()
            if selectionMode == .favorites, availableQuotes.isEmpty {
              quoteSelectionMode = .lengths
              return
            }
            ensureSelectedQuote()
            reset()
          }
          if quoteSelectionMode == .lengths {
            DisclosureGroup("引语长度：\(QuoteLengthSelection.summary(quoteLengths))") {
              ForEach(QuoteLength.allCases.filter { $0 != .all }) { length in
                Toggle(length.displayName, isOn: quoteLengthSelectionBinding(for: length))
                  .toggleStyle(.checkbox)
              }
            }
          } else if quoteSelectionMode == .search {
            TextField("搜索当前引语（仅本机）", text: $quoteSearchQuery)
              .onChange(of: quoteSearchQuery) { _, _ in
                quoteQueue.reset()
                guard !availableQuotes.isEmpty else { return }
                ensureSelectedQuote()
                reset()
              }
          }
          if quoteSource == .community {
            HStack {
              Button("刷新社区引语") { refreshCommunityQuotes() }
                .disabled(isLoadingCommunityQuotes)
              Picker("举报原因", selection: $quoteReportReason) {
                ForEach(RemoteQuoteReportReason.allCases, id: \.self) { reason in
                  Text(reason.displayName).tag(reason)
                }
              }
              .labelsHidden()
              .frame(maxWidth: 150)
              TextField("可选说明（最多 400 字）", text: $quoteReportNote, axis: .vertical)
                .lineLimit(1...3)
                .frame(maxWidth: 260)
                .onChange(of: quoteReportNote) { _, value in
                  if value.count > 400 { quoteReportNote = String(value.prefix(400)) }
                }
              Button("举报此引语", role: .destructive) { reportSelectedCommunityQuote() }
                .disabled(
                  isLoadingCommunityQuotes || account.currentUser == nil
                    || selectedCommunityQuoteID == nil)
              if isLoadingCommunityQuotes { ProgressView().controlSize(.small) }
              Text(communityQuoteMessage ?? "仅显示通过服务端审核的投稿。")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          if availableQuotes.isEmpty {
            ContentUnavailableView(
              quoteSource == .community
                ? "没有可用的社区引语"
                : quoteSelectionMode == .favorites ? "没有收藏引语" : "没有匹配的引语",
              systemImage: quoteSource == .community
                ? "quote.bubble" : quoteSelectionMode == .favorites ? "star.slash" : "magnifyingglass",
              description: Text(
                quoteSource == .community
                  ? "刷新后仍为空，说明该语言尚无已审核内容。"
                  : quoteSelectionMode == .favorites
                    ? "先在长度或搜索模式中收藏一条引语。" : "更换搜索词后再试。"))
          } else {
            Picker("引语", selection: $selectedQuoteID) {
              ForEach(availableQuotes) { quote in
                Text(quote.title).tag(quote.id)
              }
            }
            .onChange(of: selectedQuoteID) { _, _ in reset() }
            HStack {
              Button(settings.isFavoriteQuote(selectedQuoteID) ? "取消收藏" : "收藏引语") {
                toggleSelectedQuoteFavorite()
              }
              if quoteSelectionMode.advancesAutomatically {
                Button("随机一条") {
                  chooseNextQuote()
                  reset()
                }
              } else {
                Text("搜索模式会锁定所选引语")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Toggle("重开时重复当前引语", isOn: $settings.repeatQuotes)
            }
            if quoteSource == .builtIn {
              HStack(spacing: 8) {
                Text("这条引语如何？").font(.caption).foregroundStyle(.secondary)
                Button("不适合") { quoteRatings.set(.down, for: selectedQuoteID) }
                  .buttonStyle(.bordered)
                  .tint(quoteRatings.rating(for: selectedQuoteID) == .down ? .red : .secondary)
                Button("不错") { quoteRatings.set(.up, for: selectedQuoteID) }
                  .buttonStyle(.bordered)
                  .tint(quoteRatings.rating(for: selectedQuoteID) == .up ? .green : .secondary)
                if quoteRatings.rating(for: selectedQuoteID) != .neutral {
                  Button("清除评分") { quoteRatings.set(.neutral, for: selectedQuoteID) }
                    .buttonStyle(.borderless)
                }
              }
            } else {
              communityRatingControls
            }
          }
        case .custom:
          VStack(alignment: .leading, spacing: 10) {
            TextField("输入你自己的练习文本", text: $customText, axis: .vertical)
              .lineLimit(2...4)
              .disabled(activeLongSavedText != nil)
              .onChange(of: customText) { _, value in
                let clamped = CustomTextPolicy.clamped(value)
                if clamped != value { customText = clamped }
                customTextSectionLimit = min(
                  customTextSectionLimit, max(1, CustomTextPolicy.sections(in: clamped).count))
                if let activeLongSavedText,
                  value != activeLongSavedText.remainingText
                {
                  self.activeLongSavedText = nil
                }
              }
            Text("\(customText.count) / \(CustomTextPolicy.maximumLength) 个字符")
              .font(.caption)
              .foregroundStyle(.secondary)
            if let activeLongSavedText {
              Label(
                "继续长文本：\(activeLongSavedText.title) · \(LongSavedTextProgress.progressLabel(in: activeLongSavedText.text, offset: activeLongSavedText.progress))",
                systemImage: "book.closed")
                .font(.caption)
                .foregroundStyle(.secondary)
              Button("编辑文本并停止进度跟踪") { self.activeLongSavedText = nil }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            Picker("完成方式", selection: $customTextCompletion) {
              ForEach(CustomTextCompletion.allCases) { completion in
                Text(completion.displayName).tag(completion)
              }
            }
            .disabled(activeLongSavedText != nil)
            .onChange(of: customTextCompletion) { _, _ in reset() }
            if customTextCompletion == .time {
              Toggle("无限循环计时", isOn: infiniteBinding($customTextDuration, fallback: 30))
                .disabled(
                  activeLongSavedText != nil
                    || (customTextDuration != 0 && !infiniteIncompatibleModifiers.isEmpty))
              if customTextDuration == 0 {
                Text("使用 Bail Out 或双击 Shift+Enter 结束并查看未保存结果。")
                  .font(.caption).foregroundStyle(.secondary)
              } else {
                Stepper(value: $customTextDuration, in: 5...3600, step: 5) {
                  LabeledContent("循环时长", value: "\(customTextDuration) 秒")
                }
                .disabled(activeLongSavedText != nil)
                .onChange(of: customTextDuration) { _, _ in reset() }
              }
            }
            if customTextCompletion == .words {
              Toggle("无限循环字数", isOn: infiniteBinding($customTextWordLimit, fallback: 25))
                .disabled(
                  activeLongSavedText != nil
                    || (customTextWordLimit != 0 && !infiniteIncompatibleModifiers.isEmpty))
              if customTextWordLimit == 0 {
                Text("使用 Bail Out 或双击 Shift+Enter 结束并查看未保存结果。")
                  .font(.caption).foregroundStyle(.secondary)
              } else {
                Stepper(value: $customTextWordLimit, in: 1...1000) {
                  LabeledContent("循环字数", value: "\(customTextWordLimit) 词")
                }
                .disabled(activeLongSavedText != nil)
                .onChange(of: customTextWordLimit) { _, _ in reset() }
              }
            }
            if customTextCompletion == .sections {
              Stepper(value: $customTextSectionLimit, in: 1...max(1, customTextSections.count)) {
                LabeledContent(
                  "完成段数", value: "\(customTextSectionLimit) / \(customTextSections.count) 段")
              }
              .disabled(activeLongSavedText != nil)
              .onChange(of: customTextSectionLimit) { _, _ in reset() }
              Text("使用竖线 | 分隔段落；练习会按顺序取前面的段落。")
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
              Picker("文本顺序", selection: $customTextOrdering) {
                ForEach(CustomTextOrdering.allCases) { ordering in
                  Text(ordering.displayName).tag(ordering)
                }
              }
              .disabled(activeLongSavedText != nil)
              .onChange(of: customTextOrdering) { _, _ in reset() }
            }
            HStack {
              Button("使用这段文本开始") { reset() }
                .disabled(!CustomTextPolicy.isValid(customText))
              Button("保存文本…") { showingSaveCustomText = true }
                .disabled(!CustomTextPolicy.isValid(customText))
              Button("已保存文本…") { showingSavedTexts = true }
              Button("筛选词表…") { showingWordFilter = true }
              Button("生成文本…") { showingCustomTextGenerator = true }
            }
          }
        case .zen:
          Text("禅模式接受自由输入、没有计时器；按 Shift+Enter 完成本次练习，⌘R 可开始新一轮。")
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var activeResultTagControls: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label("活动标签", systemImage: "tag")
        .font(.headline)
      Text("活动标签会写入之后开始的每轮已完成成绩，并可用于“活动标签个人最佳”节奏引导。")
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack {
        TextField("新标签（最多 \(ResultTagPolicy.maximumCount) 个）", text: $activeResultTagDraft)
          .onSubmit { activateResultTag(activeResultTagDraft) }
        Button("启用") { activateResultTag(activeResultTagDraft) }
          .disabled(
            ResultTagPolicy.normalized([activeResultTagDraft]).isEmpty
              || settings.activeResultTags.count >= ResultTagPolicy.maximumCount)
      }
      if !settings.activeResultTags.isEmpty {
        HStack(spacing: 6) {
          Text("已启用：")
            .font(.caption)
            .foregroundStyle(.secondary)
          ForEach(settings.activeResultTags, id: \.self) { tag in
            Button {
              updateActiveResultTags { settings.deactivateResultTag(tag) }
            } label: {
              Label(tag, systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
          Spacer(minLength: 0)
          Button("清除", role: .destructive) {
            updateActiveResultTags { settings.clearActiveResultTags() }
          }
          .buttonStyle(.borderless)
          .controlSize(.small)
        }
      }
      if !inactiveKnownResultTags.isEmpty, settings.activeResultTags.count < ResultTagPolicy.maximumCount {
        Menu("从本机历史启用") {
          ForEach(inactiveKnownResultTags, id: \.self) { tag in
            Button(tag) { activateResultTag(tag) }
          }
        }
        .controlSize(.small)
      }
      if session.hasStarted, activeSessionTags != settings.activeResultTags {
        Text("本轮已锁定为：\(activeSessionTags.isEmpty ? "无标签" : activeSessionTags.joined(separator: "、"))；重新开始后才会采用新选择。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
  }

  private var inactiveKnownResultTags: [String] {
    var tags: [String] = []
    for rawTag in savedResults.flatMap(\.tags) {
      guard let tag = ResultTagPolicy.normalized([rawTag]).first else { continue }
      guard !containsEquivalentResultTag(tag, in: settings.activeResultTags) else { continue }
      guard !containsEquivalentResultTag(tag, in: tags) else { continue }
      tags.append(tag)
    }
    return tags.sorted {
      $0.compare($1, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedAscending
    }
  }

  private func activateResultTag(_ rawTag: String) {
    updateActiveResultTags { settings.activateResultTag(rawTag) }
    activeResultTagDraft = ""
  }

  private func updateActiveResultTags(_ update: () -> Void) {
    let tagsBefore = settings.activeResultTags
    update()
    guard tagsBefore != settings.activeResultTags, !session.hasStarted else { return }
    reset()
  }

  private func containsEquivalentResultTag(_ tag: String, in tags: [String]) -> Bool {
    tags.contains {
      $0.compare(tag, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
  }

  private var typingPanel: some View {
    ZStack(alignment: .topLeading) {
      RoundPracticeContent(
        isEnabled: practiceVisualEffect.usesRound,
        reducesMotion: settings.reducePracticeMotion
      ) {
        NauseaPracticeContent(
          isEnabled: practiceVisualEffect.usesNausea,
          reducesMotion: settings.reducePracticeMotion
        ) {
          EarthquakePracticeContent(
            isEnabled: practiceVisualEffect.usesEarthquake,
            reducesMotion: settings.reducePracticeMotion
          ) {
            Group {
              if showsAllPracticeLines {
                practicePrompt
              } else {
                ScrollView {
                  practicePrompt
                }
              }
            }
            .scaleEffect(x: practiceVisualTransform.horizontalScale, y: 1, anchor: .center)
            .rotationEffect(.degrees(practiceVisualTransform.rotationDegrees))
          }
        }
      }

      NativeTypingInput(
        focusRequest: focusRequest, quickRestartKey: settings.quickRestartKey,
        keyboardInputMapping: effectiveKeyboardInputMapping,
        keymapLayout: effectiveKeyboardLayout,
        oppositeShiftMode: settings.oppositeShiftMode,
        mapsArrowKeysToInput: settings.testModifiers.contains(.arrowStream),
        acceptsNewlineInput: session.configuration.mode == .zen || session.prompt.contains("\n"),
        acceptsTabInput: session.configuration.mode == .zen || session.prompt.contains("\t"),
        requiresShiftQuickRestart: quickRestartRequiresProtection
          && settings.quickRestartKey != .enter,
        disablesQuickRestart: quickRestartRequiresProtection
          && settings.quickRestartKey == .enter,
        enablesLongTestBailout: quickRestartRequiresProtection,
        finishesOnShiftEnter: session.configuration.mode == .zen,
        onInsert: { text, forceError in
          let errorsBefore = session.errors
          let typedCountBefore = session.typed.count
          session.insertBatch(
            settings.testModifiers.contains(.mirrorKeyboard) ? KeyboardMirror.transform(text) : text,
            forceError: forceError)
          emitTypingPowerEffect(
            isCorrect: session.errors == errorsBefore,
            acceptedCharacters: session.typed.count - typedCountBefore)
          if effectiveKeyboardGuideMode == .react, let pressedCharacter = text.last {
            keyboardGuideFeedbackSequence &+= 1
            keyboardGuideFeedback = .init(
              sequence: keyboardGuideFeedbackSequence,
              character: pressedCharacter,
              isCorrect: session.errors == errorsBefore)
          }
          if settings.playKeyclickSound, session.typed.count > typedCountBefore {
            TypingFeedbackSound.shared.playClick(
              style: settings.clickSoundStyle, volume: settings.soundVolume)
          }
          if settings.playErrorBeep, session.errors > errorsBefore {
            TypingFeedbackSound.shared.playError(
              style: settings.errorSoundStyle, volume: settings.soundVolume)
          }
        },
        onDelete: { session.deleteBackward() },
        onDeleteWord: { session.deleteWordBackward() },
        onRestart: attemptRestart,
        onOpenCommandPalette: { showingCommandPalette = true },
        onBailoutArmed: armLongTestBailout,
        onBailout: {
          bailoutConfirmationMessage = nil
          session.bailOut()
        },
        onFinishZen: { session.finishZen() },
        onFocusChanged: { isFocused in
          if !isFocused { typingCompanionHands.reset() }
          handleTypingFocusChange(isFocused)
        },
        onCompositionChanged: { compositionText = $0 },
        onModifierFlagsChanged: { keyboardModifierFlags = $0 },
        onPhysicalKey: { keyCode, isKeyDown, isRepeat in
          session.recordPhysicalKeyEvent(
            keyCode: keyCode, isKeyDown: isKeyDown, isRepeat: isRepeat)
          if isKeyDown { session.recordKeyboardActivity() }
          guard settings.showTypingCompanion else { return }
          typingCompanionHands.handle(keyCode: keyCode, isKeyDown: isKeyDown, isRepeat: isRepeat)
        }
      )
      .opacity(0.01)
      .frame(width: 1, height: 1)
    }
    .overlay(alignment: .bottomTrailing) {
      if TypingCompanionVisibilityPolicy.shouldShow(
        isEnabled: settings.showTypingCompanion, hasStarted: session.hasStarted,
        isFinished: session.isFinished)
      {
        TypingCompanion(
          hands: typingCompanionHands,
          wpm: Double(settings.blindMode ? session.rawWpm(at: .now) : session.wpm(at: .now)),
          accent: activeTheme.accent, panel: activeTheme.panel,
          reduceMotion: settings.reducePracticeMotion)
        .padding(18)
      }
    }
    .padding(28)
    .frame(
      maxWidth: .infinity, minHeight: 240,
      maxHeight: showsAllPracticeLines ? nil : 240, alignment: .topLeading)
    .background(activeTheme.panel, in: RoundedRectangle(cornerRadius: 20))
    .overlay {
      if settings.typingPowerMode.isEnabled, !typingPowerParticles.isEmpty {
        TypingPowerOverlay(
          particles: typingPowerParticles, accent: activeTheme.accent,
          error: activeTheme.errorColor(usesColorfulMode: settings.colorfulMode),
          reducesMotion: settings.reducePracticeMotion)
      }
    }
    .overlay {
      if practiceVisualEffect.usesCRT { CRTPracticeOverlay() }
    }
    .overlay {
      if practiceVisualEffect.usesSpace { SpacePracticeOverlay(accent: activeTheme.accent) }
    }
    .offset(typingPowerShakeOffset)
    .contentShape(Rectangle())
    .overlay(alignment: .top) {
      if session.configuration.modifiers.contains(.listening) {
        Label("听写模式：请听系统语音", systemImage: "ear")
          .font(.caption.weight(.medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.thinMaterial, in: Capsule())
          .padding(.top, 10)
      }
      if session.configuration.modifiers.contains(.simonSays) {
        Label("Simon 指令：跟随下一键提示", systemImage: "hand.point.right")
          .font(.caption.weight(.medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.thinMaterial, in: Capsule())
          .padding(.top, 10)
      }
      if session.configuration.modifiers.contains(.memory) {
        Label(
          session.hasStarted ? "记忆模式：提示已隐藏" : "记忆模式：开始输入后提示会隐藏", systemImage: "brain.head.profile"
        )
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
          .padding(.top, 10)
      }
      if let layoutFluidNotice {
        Label(layoutFluidNotice, systemImage: "keyboard.badge.ellipsis")
          .font(.caption.weight(.medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.thinMaterial, in: Capsule())
          .padding(.top, 10)
      }
      if !attentionWarnings.isEmpty {
        VStack(spacing: 6) {
          ForEach(attentionWarnings, id: \.self) { warning in
            Label(warning.message, systemImage: warning.systemImage)
          }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .padding(.top, 10)
      }
    }
    .overlay(alignment: .bottomLeading) {
      VStack(alignment: .leading, spacing: 6) {
        if !activeSessionTags.isEmpty {
          Label("标签：\(activeSessionTags.joined(separator: "、"))", systemImage: "tag")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel("本轮活动标签：\(activeSessionTags.joined(separator: "、"))")
        }
        if let activePaceTargetWpm, let paceGuideIndex {
          Label(
            "节奏 \(activePaceTargetWpm) WPM · \(paceGuideProgressDescription)", systemImage: "metronome"
          )
          .font(.caption.weight(.medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(.thinMaterial, in: Capsule())
          .accessibilityLabel(
            "节奏引导：目标 \(activePaceTargetWpm) WPM，\(paceGuideProgressDescription)，目标位置 \(paceGuideIndex + 1)"
          )
        }
        if settings.compositionDisplayStyle == .below, !compositionText.isEmpty {
          Text(compositionText)
            .font(settings.practiceFont.font(
              size: max(14, settings.fontSize * 0.58),
              installedFontName: settings.installedPracticeFontName))
            .foregroundStyle(activeTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(activeTheme.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel("正在组合：\(compositionText)")
        }
      }
      .padding(12)
    }
    .onTapGesture { requestTypingFocus() }
  }

  private var practicePrompt: some View {
    let _ = settings.localPracticeFontRevision
    let rendering = renderedPrompt
    let isRightToLeft = session.configuration.usesRightToLeftPrompt
    let usesJoiningScript = session.configuration.usesJoiningScriptPrompt
    return Group {
      if practiceVisualEffect.usesASL {
        ASLPracticePrompt(
          glyphs: session.promptGlyphs, fontSize: settings.fontSize, accent: activeTheme.accent)
      } else if practiceVisualEffect.usesChoo {
        ChooPracticePrompt(
          glyphs: session.promptGlyphs,
          font: settings.practiceFont.font(
            size: settings.fontSize, installedFontName: settings.installedPracticeFontName),
          fontSize: settings.fontSize, accent: activeTheme.accent,
          isEnabled: true, reducesMotion: settings.reducePracticeMotion)
      } else if usesTapePractice {
        TapePracticePrompt(
          prompt: rendering.text, typed: session.typed, mode: settings.practiceTapeMode,
          margin: settings.practiceTapeMargin,
          font: settings.practiceFont.font(
            size: settings.fontSize, installedFontName: settings.installedPracticeFontName),
          fontSize: settings.fontSize, animatesScroll: settings.smoothPracticeLineScroll)
      } else {
        Text(rendering.text)
          .lineSpacing(usesJoiningScript ? 8 : 12)
          .textSelection(.disabled)
          .multilineTextAlignment(isRightToLeft ? .trailing : .leading)
          .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
          .foregroundStyle(activeTheme.secondaryText)
          .overlay(alignment: isRightToLeft ? .topTrailing : .topLeading) {
            if usesNativeCaretOverlay {
              PromptCaretOverlay(
                text: rendering.text,
                mainCharacterOffset: settings.caretStyle.drawsMarker
                  ? rendering.characterOffset(forGlyphAt: currentPromptGlyphIndex) : nil,
                mainStyle: settings.caretStyle,
                paceCharacterOffset: paceCaretCharacterOffset(in: rendering),
                paceStyle: settings.paceCaretStyle,
                font: settings.practiceFont.nsFont(
                  size: settings.fontSize, installedFontName: settings.installedPracticeFontName),
                lineSpacing: usesJoiningScript ? 8 : 12,
                accent: activeTheme.caret,
                motion: settings.smoothCaretMotion)
            }
          }
      }
    }
    .font(settings.practiceFont.font(
      size: settings.fontSize, installedFontName: settings.installedPracticeFontName))
    .fixedSize(horizontal: false, vertical: showsAllPracticeLines)
    .frame(
      maxWidth: settings.practiceLineWidth.maximumWidth(
        fontSize: settings.fontSize, customColumns: settings.customPracticeLineColumns),
      alignment: isRightToLeft ? .trailing : .leading
    )
    .frame(maxWidth: .infinity, alignment: isRightToLeft ? .trailing : .leading)
    .padding(isRightToLeft ? .leading : .trailing, 4)
  }

  private var effectiveKeyboardGuideMode: KeyboardGuideMode {
    if session.configuration.modifiers.contains(.listening) { return .off }
    if session.configuration.modifiers.contains(.simonSays) { return .next }
    return settings.effectiveKeyboardGuideMode
  }

  private var practiceVisualTransform: PracticeVisualTransform {
    PracticeVisualTransform.make(modifiers: session.configuration.modifiers)
  }

  private var practiceVisualEffect: PracticeVisualEffect {
    PracticeVisualEffect.make(modifiers: session.configuration.modifiers)
  }

  private var effectiveKeyboardLayout: KeyboardLayout {
    guard session.configuration.modifiers.contains(.layoutFluid) else {
      return settings.keyboardGuideLayoutSource.resolvedBuiltInLayout(
        selectedLayout: settings.keyboardLayout, inputLayout: settings.keyboardInputLayout)
    }
    return LayoutFluidPolicy.activeLayout(
      completedWords: session.completedWordCount, wordLimit: session.configuration.wordLimit,
      layouts: settings.layoutFluidLayouts)
  }

  private var effectiveKeyboardGuideOverrideRows: [[KeyboardGuideKey]]? {
    guard !session.configuration.modifiers.contains(.layoutFluid) else { return nil }
    if settings.keyboardGuideLayoutSource.usesCustomRows(
      inputLayout: settings.keyboardInputLayout)
    {
      return settings.selectedCustomKeyboardLayout?.guideRows
    }
    if settings.keyboardGuideLayoutSource.usesSystemInputRows(
      inputLayout: settings.keyboardInputLayout)
    {
      _ = systemKeyboardGuide.revision
      return SystemKeyboardGuide.currentRows()
    }
    return nil
  }

  /// Layout Fluid deliberately switches both the visible guide and simulated
  /// input layout, matching the reference funbox. Outside that mode, input
  /// emulation remains an opt-in setting and the guide is presentation-only.
  private var effectiveKeyboardInputMapping: KeyboardInputMapping {
    guard !session.configuration.modifiers.contains(.layoutFluid) else {
      return .builtIn(effectiveKeyboardLayout)
    }
    return settings.keyboardInputLayout.inputMapping(for: settings.selectedCustomKeyboardLayout)
  }

  private var layoutFluidNotice: String? {
    guard session.configuration.modifiers.contains(.layoutFluid) else { return nil }
    if let upcoming = LayoutFluidPolicy.upcomingLayout(
      completedWords: session.completedWordCount, wordLimit: session.configuration.wordLimit,
      layouts: settings.layoutFluidLayouts)
    {
      return "\(upcoming.wordsRemaining) 个词后切换至 \(upcoming.layout.displayName)"
    }
    return "当前布局：\(effectiveKeyboardLayout.displayName)"
  }

  private var promptHighlightAllowsWordRanges: Bool {
    guard session.configuration.language.usesSpaceDelimitedWords,
      !usesTapePractice else { return false }
    let restrictedModifiers: [TestModifier] = [
      .noSpaces, .underscoreSeparators, .listening, .simonSays, .memory,
      .readAheadEasy, .readAhead, .readAheadHard,
    ]
    return !restrictedModifiers.contains { session.configuration.modifiers.contains($0) }
  }

  private var effectivePromptHighlightMode: PromptHighlightMode {
    guard settings.promptHighlightMode != .off else { return .off }
    return promptHighlightAllowsWordRanges ? settings.promptHighlightMode : .letter
  }

  private var currentPromptGlyphIndex: Int? {
    session.promptGlyphs.firstIndex { $0.state == .current }
  }

  private var usesNativeCaretOverlay: Bool {
    guard settings.caretStyle.drawsMarker || settings.paceCaretStyle.drawsMarker else { return false }
    guard !session.configuration.containsRightToLeftPromptRun, !usesTapePractice,
      !practiceVisualEffect.usesASL, !practiceVisualEffect.usesChoo
    else {
      return false
    }
    return !session.configuration.modifiers.contains(.listening)
  }

  private func paceCaretCharacterOffset(in rendering: PromptRendering) -> Int? {
    guard settings.paceCaretStyle.drawsMarker, paceGuideIndex != currentPromptGlyphIndex else {
      return nil
    }
    return rendering.characterOffset(forGlyphAt: paceGuideIndex)
  }

  private var highlightedPromptIndices: Set<Int> {
    let currentIndex = session.promptGlyphs.firstIndex { $0.state == .current }
    return PromptHighlightPolicy.highlightedIndices(
      in: session.prompt, currentTargetIndex: currentIndex, mode: effectivePromptHighlightMode,
      allowsWordRanges: promptHighlightAllowsWordRanges)
  }

  private var renderedPrompt: PromptRendering {
    var output = AttributedString()
    var glyphCharacterOffsets: [Int: Int] = [:]
    let completedCharacterIndices = session.completedPromptCharacterIndices
    let promptHighlightMode = effectivePromptHighlightMode
    let highlightedIndices = highlightedPromptIndices
    for (index, glyph) in session.promptGlyphs.enumerated() {
      glyphCharacterOffsets[index] = output.characters.count
      let replacesTypo = glyph.state == .incorrect && settings.typoIndicatorStyle.replacesTarget
      let turnsIntoDot = completedCharacterIndices.contains(index)
        && settings.typedCharacterEffect == .dots
        && !session.configuration.usesJoiningScriptPrompt
        && !glyph.character.isWhitespace
      let replacesCurrentWithComposition = glyph.state == .current
        && settings.compositionDisplayStyle == .replace
        && !compositionText.isEmpty
      let displayedText: String
      if turnsIntoDot {
        displayedText = "•"
      } else if replacesCurrentWithComposition {
        displayedText = compositionText
      } else if replacesTypo {
        displayedText = String(glyph.typedCharacter ?? glyph.character)
      } else {
        displayedText = String(glyph.character)
      }
      var character = AttributedString(displayedText)
      if session.configuration.modifiers.contains(.listening) {
        character.foregroundColor = .clear
        output += character
        continue
      }
      if promptHighlightMode.futureWordCount != nil,
        highlightedIndices.contains(index),
        glyph.state != .hidden
      {
        applyWordHighlight(to: &character)
      }
      if !usesNativeCaretOverlay, index == paceGuideIndex, glyph.state != .current {
        applyPaceCaret(to: &character)
      }
      switch glyph.state {
      case .correct:
        switch settings.typedCharacterEffect {
        case .keep:
          character.foregroundColor = completedPromptColor
        case .hide where completedCharacterIndices.contains(index):
          character.foregroundColor = .clear
        case .fade where completedCharacterIndices.contains(index):
          character.foregroundColor = activeTheme.fadedText.opacity(0.24)
        case .dots where turnsIntoDot:
          character.foregroundColor = activeTheme.accent.opacity(0.74)
        default:
          character.foregroundColor = completedPromptColor
        }
      case .incorrect:
        character.foregroundColor = errorFeedbackColor
        character.backgroundColor = errorFeedbackColor.opacity(0.16)
      case .current:
        if promptHighlightMode == .off || !settings.caretStyle.drawsMarker || usesNativeCaretOverlay {
          character.foregroundColor = futurePromptColor
        } else {
          applyCaret(to: &character)
        }
      case .pending:
        character.foregroundColor = futurePromptColor
      case .hidden:
        character.foregroundColor = .clear
      case .extra:
        character.foregroundColor = extraInputFeedbackColor
        character.backgroundColor = extraInputFeedbackColor.opacity(0.12)
        character.strikethroughStyle = .single
      }
      output += character
      if glyph.state == .incorrect,
        settings.typoIndicatorStyle.showsHint,
        let enteredCharacter = glyph.typedCharacter
      {
        let hintCharacter = replacesTypo ? glyph.character : enteredCharacter
        var hint = AttributedString(String(hintCharacter))
        hint.font = .system(
          size: max(9, settings.fontSize * 0.48), weight: .semibold, design: .monospaced)
        hint.foregroundColor = errorFeedbackColor.opacity(0.72)
        hint.baselineOffset = -settings.fontSize * 0.42
        // Reserve no additional horizontal advance: the hint sits under the
        // erroneous glyph instead of reflowing every following character.
        hint.kern = -settings.fontSize * 0.62
        output += hint
      }
    }
    return PromptRendering(text: output, glyphCharacterOffsets: glyphCharacterOffsets)
  }

  private var completedPromptColor: Color {
    promptTextColor(for: .completed)
  }

  private var errorFeedbackColor: Color {
    activeTheme.errorColor(usesColorfulMode: settings.colorfulMode)
  }

  private var extraInputFeedbackColor: Color {
    activeTheme.extraInputColor(usesColorfulMode: settings.colorfulMode)
  }

  private var futurePromptColor: Color {
    promptTextColor(for: .future)
  }

  private func promptTextColor(for role: PromptTextRole) -> Color {
    switch PromptTextColorPolicy.tone(
      for: role, flipsCompletionAndFuture: settings.flipTestColors,
      usesAccentForCompleted: settings.colorfulMode)
    {
    case .primary: activeTheme.text
    case .secondary: activeTheme.secondaryText.opacity(0.55)
    case .accent: activeTheme.accent
    }
  }

  private var usesTapePractice: Bool {
    settings.practiceTapeMode != .off && !session.prompt.contains("\n")
      && !session.configuration.containsRightToLeftPromptRun
  }

  private var showsAllPracticeLines: Bool {
    PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: settings.showAllPracticeLines,
      tapeMode: settings.practiceTapeMode,
      testMode: session.configuration.mode,
      hasTimeLimit: session.configuration.duration != nil)
  }

  private func applyCaret(to character: inout AttributedString) {
    switch settings.caretStyle {
    case .off:
      break
    case .bar:
      character.foregroundColor = activeTheme.caret
      character.underlineStyle = .single
    case .outline:
      character.backgroundColor = activeTheme.caret.opacity(0.14)
    case .underline:
      character.underlineStyle = .single
      character.backgroundColor = activeTheme.caret.opacity(0.12)
    case .block:
      character.backgroundColor = activeTheme.caret.opacity(0.55)
    case .carrot, .banana, .monkey:
      character.foregroundColor = activeTheme.caret
    }
  }

  private func applyWordHighlight(to character: inout AttributedString) {
    character.backgroundColor = activeTheme.accent.opacity(0.14)
  }

  private func applyPaceCaret(to character: inout AttributedString) {
    switch settings.paceCaretStyle {
    case .off:
      break
    case .bar:
      character.backgroundColor = activeTheme.caret.opacity(0.16)
      character.underlineStyle = .single
    case .outline:
      character.backgroundColor = activeTheme.caret.opacity(0.12)
    case .underline:
      character.underlineStyle = .single
    case .block:
      character.backgroundColor = activeTheme.caret.opacity(0.34)
    case .carrot, .banana, .monkey:
      character.foregroundColor = activeTheme.caret.opacity(0.72)
    }
  }

  private var stats: some View {
    let now = Date.now
    let progressStyle = settings.liveProgressStyle
    let isProgressFlashHidden = !progressStyle.showsProgressValue(
      isTimed: session.configuration.duration != nil,
      remainingSeconds: session.remainingSeconds(at: now))

    return HStack(spacing: 0) {
      metric(
        settings.typingSpeedUnit.displayName,
        value: settings.typingSpeedUnit.formatted(
          wpm: session.wpm(at: .now)), style: settings.liveSpeedStyle, usesLiveAppearance: true)
      metric(
        "Raw \(settings.typingSpeedUnit.displayName)",
        value: settings.typingSpeedUnit.formatted(
          wpm: session.rawWpm(at: .now)), style: settings.liveSpeedStyle, usesLiveAppearance: true)
      metric(
        "Burst \(settings.typingSpeedUnit.displayName)",
        value: settings.typingSpeedUnit.formatted(
          wpm: session.burstWpm), style: settings.liveBurstStyle, usesLiveAppearance: true)
      metric(
        "准确率", value: "\(session.accuracy)%", style: settings.liveAccuracyStyle,
        usesLiveAppearance: true)
      if progressStyle == .bar {
        progressMetricBar
      } else {
        metric(
          session.progressLabel,
          value: isProgressFlashHidden && progressStyle == .flashText
            ? "" : session.progressText(at: now) ?? "—",
          style: progressStyle.metricStyle,
          usesLiveAppearance: true,
          isHidden: isProgressFlashHidden && progressStyle == .flashMini)
      }
      if let sections = session.sectionProgress {
        metric("段落", value: "\(sections.completed)/\(sections.total)")
      }
      metric("错误", value: "\(session.errors)")
    }
    .background(activeTheme.panel, in: RoundedRectangle(cornerRadius: 16))
    .overlay(alignment: .bottomLeading) {
      if !session.recentWordBursts.isEmpty {
        WordBurstHistoryView(bursts: session.recentWordBursts, accent: activeTheme.accent)
          .padding(.horizontal, 14)
          .padding(.bottom, 8)
      }
    }
  }

  private var attentionWarnings: [TypingAttentionWarning] {
    TypingAttentionPolicy.warnings(
      isInputFocused: inputHasFocus,
      focusWarningDelayElapsed: focusWarningDelayElapsed,
      capsLockEnabled: capsLockEnabled,
      language: language,
      isFinished: session.isFinished,
      showFocusWarning: settings.showFocusWarning,
      showCapsLockWarning: settings.showCapsLockWarning
    )
  }

  @ViewBuilder
  private func metric(
    _ title: String,
    value: String,
    style: LiveMetricStyle = .text,
    usesLiveAppearance: Bool = false,
    isHidden: Bool = false
  ) -> some View {
    if style != .off {
      let isMini = style == .mini
      let foreground = usesLiveAppearance
        ? settings.liveStatsColor.resolved(accent: activeTheme.accent) : Color.primary
      let labelForeground = usesLiveAppearance ? foreground.opacity(0.76) : Color.secondary
      VStack(spacing: isMini ? 2 : 5) {
        Text(value).font(
          .system(size: isMini ? 17 : 28, weight: .semibold, design: .rounded))
        Text(title).font(isMini ? .caption2 : .caption).foregroundStyle(labelForeground)
      }
      .foregroundStyle(foreground)
      .opacity((usesLiveAppearance ? settings.liveStatsOpacity.rawValue : 1) * (isHidden ? 0 : 1))
      .frame(maxWidth: .infinity)
      .padding(.vertical, isMini ? 8 : 14)
    }
  }

  private var progressMetricBar: some View {
    let foreground = settings.liveStatsColor.resolved(accent: activeTheme.accent)
    return VStack(spacing: 6) {
      HStack {
        Text(session.progressLabel).font(.caption).foregroundStyle(foreground.opacity(0.76))
        Spacer()
        Text(session.progressText(at: .now) ?? "—")
          .font(.caption.weight(.semibold))
      }
      ProgressView(value: session.progressFraction(at: .now) ?? 0)
        .tint(foreground)
    }
    .foregroundStyle(foreground)
    .opacity(settings.liveStatsOpacity.rawValue)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 14)
    .padding(.vertical, 16)
  }

  private var controls: some View {
    HStack {
      Text(
        session.isFinished
          ? session.outcome.statusText(savesResult: settings.saveCompletedResults)
          : restartInstruction
      )
        .foregroundStyle(.secondary)
      Spacer()
      if session.hasStarted && !session.isFinished {
        Button(
          shouldBailOutFromControls ? "中止并显示未保存结果" : "放弃本次测试",
          role: .destructive
        ) {
          if shouldBailOutFromControls {
            session.bailOut()
          } else {
            session.abandon()
          }
        }
      }
      Button {
        attemptRestart()
      } label: {
        Label("重新开始", systemImage: "arrow.counterclockwise")
      }
      .keyboardShortcut("r", modifiers: .command)
      .buttonStyle(.borderedProminent)
      if weakSpotPrompt != nil {
        Button("弱项训练") { startWeakSpotPractice() }
          .help("依据本机完成测试中的错误字符生成 Typebar 自有词库练习")
      }
      Button("朗读提示") {
        NativeSpeech.shared.speak(session.prompt, language: session.configuration.language)
      }
      .help("使用 macOS 本机语音朗读当前提示，不发送文本到网络")
    }
    .overlay(alignment: .bottomLeading) {
      if let bailoutConfirmationMessage {
        Label(bailoutConfirmationMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .offset(y: 24)
      } else if let restartLockMessage {
        Label(restartLockMessage, systemImage: "lock.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .offset(y: 24)
      }
    }
  }

  private func attemptRestart() {
    guard !TypingRestartPolicy.isLocked(session) else {
      restartLockMessage = "锁定重开已开启：请完成或放弃本次测试。"
      return
    }
    reset(restarting: true)
  }

  private var restartInstruction: String {
    if quickRestartRequiresProtection {
      let bailout = "双击 Shift+Enter 中止并显示结果"
      switch settings.quickRestartKey {
      case .escape: return "按任意键开始，Shift+Esc 可重新开始；\(bailout)"
      case .tab: return "按任意键开始，Shift+Tab 可重新开始；\(bailout)"
      case .enter: return "按任意键开始，⌘R 可重开；\(bailout)"
      case .off: return "按任意键开始，可用 ⌘R 重开；\(bailout)"
      }
    }
    switch settings.quickRestartKey {
    case .off: return "按任意键开始，可使用 ⌘R 重新开始"
    case .escape: return "按任意键开始，Esc 可重新开始"
    case .tab: return "按任意键开始，Tab 可重新开始"
    case .enter: return "按任意键开始，Enter 可重新开始"
    }
  }

  @ViewBuilder private var practiceKeyTips: some View {
    if settings.showKeyTips {
      VStack(spacing: 6) {
        Label("\(keyTipRestartShortcut) · 重新开始测试", systemImage: "arrow.counterclockwise")
        Label("\(commandPaletteShortcutInstruction) · 打开命令面板", systemImage: "command")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .opacity(inputHasFocus ? 0 : 1)
      .accessibilityHidden(inputHasFocus)
      .animation(.easeInOut(duration: 0.2), value: inputHasFocus)
    }
  }

  private var keyTipRestartShortcut: String {
    guard !quickRestartRequiresProtection else { return "⌘R" }
    switch settings.quickRestartKey {
    case .off: return "⌘R"
    case .escape: return "Esc / ⌘R"
    case .tab: return "Tab / ⌘R"
    case .enter: return "Enter / ⌘R"
    }
  }

  private var commandPaletteShortcutInstruction: String {
    let dynamic = CommandPaletteDynamicShortcut.resolve(
      quickRestartKey: settings.quickRestartKey,
      promptAcceptsTab: session.configuration.mode == .zen || session.prompt.contains("\t"))
    return "\(dynamic.displayName) / ⇧⌘P / ⇧⌘K"
  }

  private func handleTypingFocusChange(_ hasFocus: Bool) {
    inputHasFocus = hasFocus
    focusWarningSequence &+= 1
    guard !hasFocus else {
      focusWarningDelayElapsed = false
      return
    }

    clearTypingPowerEffect()
    focusWarningDelayElapsed = false
    let sequence = focusWarningSequence
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      guard !inputHasFocus, focusWarningSequence == sequence else { return }
      focusWarningDelayElapsed = true
    }
  }

  private func emitTypingPowerEffect(isCorrect: Bool, acceptedCharacters: Int) {
    let mode = settings.typingPowerMode
    guard
      TypingPowerPolicy.shouldEmit(
        mode: mode, acceptedCharacters: acceptedCharacters,
        reducesMotion: systemReduceMotion || settings.reducePracticeMotion)
    else { return }

    let now = Date.now
    let origin = TypingPowerPolicy.origin(
      typedCharacters: session.typed.count, promptLength: session.prompt.count)
    let tone = TypingPowerPolicy.tone(for: mode, isCorrect: isCorrect, isBlind: settings.blindMode)
    let particleCount = TypingPowerPolicy.particleCount(randomUnit: Double.random(in: 0...1))
    let newParticles = (0..<particleCount).map { _ in
      TypingPowerParticle(
        id: UUID(), origin: origin,
        velocity: .init(
          width: Double.random(in: -260...260),
          height: Double.random(in: -310 ... -80)),
        createdAt: now, tone: tone, hue: Double.random(in: 0...1))
    }
    typingPowerParticles = Array(
      (typingPowerParticles + newParticles).suffix(TypingPowerPolicy.maximumParticles))
    typingPowerGeneration &+= 1
    let generation = typingPowerGeneration
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      guard generation == typingPowerGeneration else { return }
      typingPowerParticles = []
    }

    guard mode.usesShake else { return }
    typingPowerShakeOffset = TypingPowerPolicy.shakeOffset(
      xRandomUnit: Double.random(in: 0...1), yRandomUnit: Double.random(in: 0...1))
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 70_000_000)
      guard generation == typingPowerGeneration else { return }
      withAnimation(.easeOut(duration: 0.16)) { typingPowerShakeOffset = .zero }
    }
  }

  private func clearTypingPowerEffect() {
    typingPowerGeneration &+= 1
    typingPowerParticles = []
    typingPowerShakeOffset = .zero
  }

  private func reset(restarting: Bool = false) {
    let shouldCountRestart = session.hasStarted && !session.isFinished
    restartLockMessage = nil
    bailoutConfirmationMessage = nil
    compositionText = ""
    keyboardGuideFeedback = nil
    typingCompanionHands.reset()
    clearTypingPowerEffect()
    lastTimeWarningSecond = nil
    liveContentRequestID = UUID()
    let requestID = liveContentRequestID
    isLoadingLiveContent = false
    liveContentMessage = nil
    if mode != .custom { activeLongSavedText = nil }
    NativeSpeech.shared.stop()
    if restarting, mode == .quote,
      !QuoteRestartPolicy.shouldKeepCurrent(
        repeatWhileTyping: settings.repeatQuotes, hasStarted: session.hasStarted,
        isFinished: session.isFinished)
    {
      chooseNextQuote()
    }
    let selectedQuote = availableQuotes.first { $0.id == selectedQuoteID }
    activeQuoteFeedback = QuoteResultFeedbackTarget.make(
      mode: mode, sourceIsCommunity: quoteSource == .community,
      selectedQuoteID: selectedQuote?.id ?? "")
    activeQuoteSource = ResultQuoteSource.make(
      mode: mode, sourceIsCommunity: quoteSource == .community, title: selectedQuote?.title)
    activeSessionTags = settings.activeResultTags
    session = TestSessionFactory.make(
      configuration: configuration,
      customText: customText,
      quote: selectedQuote
    )
    if shouldCountRestart { currentRestartCount += 1 }
    let shouldUseRepeatedPace = repeatedPaceArmed && settings.paceGuideMode == .off
    activePaceTargetWpm = paceGuideTarget(
      usingRepeatedPace: shouldUseRepeatedPace ? lastCompletedWpm : nil)
    repeatedPaceArmed = false
    if session.configuration.modifiers.contains(.listening) {
      NativeSpeech.shared.speak(session.prompt, language: session.configuration.language)
    }
    refreshLiveContentIfNeeded(configuration: session.configuration, requestID: requestID)
    requestTypingFocus()
  }

  private func refreshLiveContentIfNeeded(configuration: TestConfiguration, requestID: UUID) {
    guard let source = LivePracticeContentSource.selected(for: configuration) else { return }
    isLoadingLiveContent = true
    liveContentMessage = "正在获取随机\(source.displayName)；失败时继续使用离线内容。"
    Task {
      let content = await LivePracticeContentService.fetch(source: source, language: configuration.language)
      guard requestID == liveContentRequestID else { return }
      isLoadingLiveContent = false
      guard let content else {
        liveContentMessage = "无法获取随机\(source.displayName)，正在使用原创离线内容。"
        return
      }
      guard LivePracticeContentReplacementPolicy.shouldApply(
        hasStarted: session.hasStarted, currentConfiguration: session.configuration,
        requestedConfiguration: configuration)
      else {
        liveContentMessage = "已获取\(content.attribution)，为避免打断输入，本轮仍使用现有提示。"
        return
      }
      session = TestSessionFactory.make(
        configuration: configuration, streamPrompt: content.prompt(for: configuration))
      liveContentMessage = "已载入\(content.attribution)。"
      if configuration.modifiers.contains(.listening) {
        NativeSpeech.shared.speak(session.prompt, language: configuration.language)
      }
      requestTypingFocus()
    }
  }

  private var quickRestartRequiresProtection: Bool {
    QuickRestartSafetyPolicy.requiresShift(
      for: session.configuration, savedLongText: activeLongSavedText != nil)
  }

  private var commandBailoutAvailable: Bool {
    CommandBailoutPolicy.isAvailable(
      for: session.configuration, savedLongText: activeLongSavedText != nil)
  }

  private var shouldBailOutFromControls: Bool {
    activeLongSavedText != nil || session.configuration.isInfinite
  }

  private var infiniteIncompatibleModifiers: [TestModifier] {
    settings.testModifiers.filter(TestModifierPolicy.finiteDurationOnly.contains)
  }

  private var offersInfiniteSelection: Bool {
    mode == .time || mode == .words
      || (mode == .custom && [.time, .words].contains(customTextCompletion))
  }

  private func infiniteBinding(_ value: Binding<Int>, fallback: Int) -> Binding<Bool> {
    Binding(
      get: { value.wrappedValue == 0 },
      set: { enabled in
        guard !enabled || infiniteIncompatibleModifiers.isEmpty else { return }
        value.wrappedValue = enabled ? 0 : fallback
        reset()
      })
  }

  private func loadSavedCustomText(_ selection: SavedCustomTextSelection) {
    mode = .custom
    guard selection.isLong else {
      activeLongSavedText = nil
      customText = selection.text
      reset()
      return
    }
    var progress = LongSavedTextProgress.normalized(selection.longProgress ?? 0, in: selection.text)
    if LongSavedTextProgress.remainingText(in: selection.text, after: progress)
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      progress = 0
    }
    let active = ActiveLongSavedText(
      id: selection.id, title: selection.title, text: selection.text, progress: progress)
    activeLongSavedText = active
    customText = active.remainingText
    customTextCompletion = .finish
    customTextOrdering = .inOrder
    reset()
  }

  private func applyGeneratedCustomText(_ generatedText: String, appending: Bool) {
    let existing = appending ? customText.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let separator = existing.isEmpty ? "" : " "
    let nextText = CustomTextPolicy.clamped(existing + separator + generatedText)
    guard CustomTextPolicy.isValid(nextText) else { return }
    activeChallengeID = nil
    activeLongSavedText = nil
    practiceReturnPreset = nil
    mode = .custom
    customText = nextText
    customTextCompletion = .finish
    customTextOrdering = .inOrder
    completedResult = nil
    reset()
  }

  @discardableResult
  private func updateLongSavedTextProgress(for outcome: TestOutcome) -> Bool {
    guard let active = activeLongSavedText,
      session.configuration.mode == .custom,
      outcome == .completed || outcome == .bailedOut || outcome == .failed || outcome == .invalidAFK
    else { return false }
    let activeID = active.id
    let descriptor = FetchDescriptor<SavedCustomTextRecord>(
      predicate: #Predicate { $0.id == activeID })
    guard let record = try? modelContext.fetch(descriptor).first,
      record.isLong,
      record.text == active.text
    else {
      activeLongSavedText = nil
      return false
    }

    let nextProgress: Int
    switch outcome {
    case .completed:
      nextProgress = 0
    case .bailedOut, .failed, .invalidAFK:
      nextProgress = LongSavedTextProgress.advancedOffset(
        in: active.text, from: active.progress, typed: session.typed)
    case .active, .abandoned:
      return false
    }
    record.longProgress = nextProgress
    var updated = active
    updated.progress = nextProgress
    activeLongSavedText = updated
    customText = updated.remainingText
    try? modelContext.save()
    return true
  }

  private func armLongTestBailout() {
    let message = "再次在 0.2 秒内按 Shift+Enter，可中止并显示未保存结果。"
    bailoutConfirmationMessage = message
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      guard bailoutConfirmationMessage == message else { return }
      bailoutConfirmationMessage = nil
    }
  }

  private func startRepeatedAttempt(_ repeatedSession: TypingSession, tags: [String]) {
    restartLockMessage = nil
    compositionText = ""
    keyboardGuideFeedback = nil
    lastTimeWarningSecond = nil
    NativeSpeech.shared.stop()
    activeSessionTags = ResultTagPolicy.normalized(tags)
    session = repeatedSession
    let shouldUseRepeatedPace = repeatedPaceArmed && settings.paceGuideMode == .off
    activePaceTargetWpm = paceGuideTarget(
      usingRepeatedPace: shouldUseRepeatedPace ? lastCompletedWpm : nil)
    repeatedPaceArmed = false
    if session.configuration.modifiers.contains(.listening) {
      NativeSpeech.shared.speak(session.prompt, language: session.configuration.language)
    }
    requestTypingFocus()
  }

  private func refreshPaceTarget() {
    activePaceTargetWpm = paceGuideTarget()
  }

  private func requestTypingFocus() {
    focusRequest &+= 1
  }

  private var weakSpotPrompt: String? {
    WeakSpotPractice.prompt(
      results: savedResults.compactMap(\.portableResult),
      language: language,
      englishVariant: settings.englishVariant
    )
  }

  private var averageNotice: String? {
    guard settings.showAverage != .off else { return nil }
    let samples = savedResults.compactMap { record -> RecentAverageSample? in
      guard let result = record.portableResult else { return nil }
      return .init(
        configuration: result.configuration, prompt: result.prompt, finishedAt: result.finishedAt,
        wpm: result.wpm, accuracy: result.accuracy, tags: result.tags)
    }
    guard let average = RecentTestAveragePolicy.average(
      currentConfiguration: configuration, currentPrompt: session.prompt, samples: samples,
      activeTags: activeSessionTags)
    else {
      return "近 10 次平均：暂无同类本机成绩"
    }

    var metrics = [String]()
    if settings.showAverage.showsSpeed {
      metrics.append(
        "\(settings.typingSpeedUnit.formatted(wpm: average.wpm)) \(settings.typingSpeedUnit.displayName)")
    }
    if settings.showAverage.showsAccuracy {
      metrics.append("\(average.accuracy)% 准确率")
    }
    return "近 \(average.count) 次平均：\(metrics.joined(separator: " · "))"
  }

  private var todayPracticeSummary: TodayPracticeSummary {
    TodayPracticeAggregation.summary(
      persisted: savedResults.map {
        ResultMetric(
          id: $0.id, finishedAt: $0.finishedAt, wpm: $0.wpm, accuracy: $0.accuracy,
          typingSeconds: $0.engagedDuration)
      },
      currentProcess: currentProcessPractice)
  }

  private var personalBestNotice: String? {
    guard settings.showPersonalBest else { return nil }
    guard CurrentPersonalBestPolicy.isConfigurationEligible(configuration) else {
      return "本机个人最佳：当前测试不计入 PB"
    }
    let samples = savedResults.compactMap { record -> RecentAverageSample? in
      guard let result = record.portableResult else { return nil }
      return .init(
        configuration: result.configuration, prompt: result.prompt, finishedAt: result.finishedAt,
        wpm: result.wpm, accuracy: result.accuracy, tags: result.tags)
    }
    guard let personalBest = CurrentPersonalBestPolicy.personalBest(
      currentConfiguration: configuration, currentPrompt: session.prompt, samples: samples,
      activeTags: activeSessionTags)
    else {
      return "本机个人最佳：暂无符合资格的同类成绩"
    }
    return "本机个人最佳：\(settings.typingSpeedUnit.formatted(wpm: personalBest.wpm)) \(settings.typingSpeedUnit.displayName) · \(personalBest.accuracy)% 准确率"
  }

  private func startWeakSpotPractice() {
    guard let weakSpotPrompt else { return }
    startWeakSpotPractice(prompt: weakSpotPrompt, language: language)
  }

  private func startWeakSpotPractice(
    prompt weakSpotPrompt: String, language weakSpotLanguage: TypingLanguage
  ) {
    activeChallengeID = nil
    language = weakSpotLanguage
    customText = weakSpotPrompt
    customTextCompletion = .words
    customTextWordLimit = weakSpotPrompt.split(separator: " ").count
    customTextOrdering = .inOrder
    mode = .custom
    reset()
  }

  private func paceGuideTarget(usingRepeatedPace repeatedWpm: Int? = nil) -> Int? {
    if settings.paceGuideMode == .off, let repeatedWpm {
      return repeatedWpm.clamped(to: PaceGuidePolicy.minimumWpm...PaceGuidePolicy.maximumWpm)
    }
    let samples = savedResults.compactMap { record -> PaceGuideSample? in
      guard let result = record.portableResult else { return nil }
      return .init(
        configuration: result.configuration, outcome: result.outcome, finishedAt: result.finishedAt,
        wpm: result.wpm, tags: result.tags, prompt: result.prompt)
    }
    return PaceGuidePolicy.targetWpm(
      mode: settings.paceGuideMode,
      customWpm: settings.paceGuideCustomWpm,
      configuration: configuration,
      samples: samples,
      activeTags: activeSessionTags,
      lastTestWpm: repeatedWpm ?? lastCompletedWpm,
      currentPrompt: session.prompt
    )
  }

  private var paceGuideIndex: Int? {
    guard
      let targetWpm = activePaceTargetWpm,
      let startedAt = session.startedAt,
      !session.isFinished
    else { return nil }
    return PaceGuidePolicy.expectedCharacterIndex(
      elapsed: Date.now.timeIntervalSince(startedAt),
      targetWpm: targetWpm,
      promptLength: session.prompt.count
    )
  }

  private var paceGuideProgressDescription: String {
    guard let paceGuideIndex else { return "等待开始" }
    let delta = session.typedCharacterCount - paceGuideIndex
    if delta == 0 { return "同步" }
    return delta > 0 ? "领先 \(delta) 字符" : "落后 \(-delta) 字符"
  }

  private var activeTheme: ResolvedTheme {
    settings.resolvedTheme(for: systemColorScheme)
  }

  private var commandPaletteItems: [CommandPaletteItem] {
    var items: [CommandPaletteItem] = [
      .init(
        id: "restart", title: "重新开始测试", subtitle: "使用当前配置生成新的练习",
        systemImage: "arrow.counterclockwise", keywords: ["restart", "reset", "重开"], group: .practice),
      .init(
        id: "mode.time", title: "切换到时间模式", subtitle: "按设定时长完成练习", systemImage: "timer",
        keywords: ["time", "时间", "模式"], group: .practice),
      .init(
        id: "mode.words", title: "切换到字数模式", subtitle: "按设定词数完成练习", systemImage: "text.word.spacing",
        keywords: ["words", "字数", "模式"], group: .practice),
      .init(
        id: "mode.quote", title: "切换到引语模式", subtitle: "使用原创离线引语练习", systemImage: "quote.opening",
        keywords: ["quote", "引语", "模式"], group: .practice),
      .init(
        id: "mode.zen", title: "切换到禅模式", subtitle: "不计时的自由练习", systemImage: "leaf",
        keywords: ["zen", "禅", "模式"], group: .practice),
      .init(
        id: "mode.custom", title: "切换到自定义文本", subtitle: "输入或选择自己的练习文本", systemImage: "text.cursor",
        keywords: ["custom", "文本", "模式"], group: .practice),
      .init(
        id: "history", title: "打开练习历史", subtitle: "查看成绩、趋势与活动",
        systemImage: "clock.arrow.circlepath", keywords: ["history", "历史", "统计"], group: .activity),
      .init(
        id: "weakSpots", title: "打开弱项分析", subtitle: "从本机回放查看错误字符并开始训练",
        systemImage: "scope", keywords: ["weak", "weakspot", "弱项", "错误", "训练"], group: .activity),
      .init(
        id: "presets", title: "打开测试预设", subtitle: "保存或应用完整测试配置", systemImage: "slider.horizontal.3",
        keywords: ["preset", "预设"], group: .library),
      .init(
        id: "challenges", title: "打开离线挑战", subtitle: "加载固定配置并验收速度、准确率和错误",
        systemImage: "flag.checkered", keywords: ["challenge", "挑战", "目标"], group: .library),
      .init(
        id: "savedTexts", title: "打开已保存文本", subtitle: "选择本地自定义练习文本", systemImage: "doc.text",
        keywords: ["saved", "文本", "自定义"], group: .library),
      .init(
        id: "data", title: "打开数据管理", subtitle: "导入或导出本地 Typebar 归档", systemImage: "externaldrive",
        keywords: ["data", "数据", "备份"], group: .data),
      .init(
        id: "sync", title: "打开同步", subtitle: "连接自建服务并同步归档",
        systemImage: "arrow.triangle.2.circlepath", keywords: ["sync", "同步", "账户"], group: .connections),
      .init(
        id: "friends", title: "打开好友", subtitle: "搜索用户和管理好友关系", systemImage: "person.2",
        keywords: ["friend", "好友", "社交"], group: .connections),
      .init(
        id: "notifications", title: "打开通知", subtitle: "查看好友请求和接受事件", systemImage: "bell",
        keywords: ["notification", "通知", "好友请求"], group: .connections),
      .init(
        id: "settings", title: "打开设置", subtitle: "修改输入规则、显示和账户选项", systemImage: "gearshape",
        keywords: ["settings", "设置", "主题", "键盘"], group: .settings),
      AboutCommand.item,
      ReleaseHistoryCommand.item,
      .init(
        id: "share", title: "分享当前测试", subtitle: "复制或导入 Typebar 测试配置链接",
        systemImage: "square.and.arrow.up", keywords: ["share", "分享", "链接", "配置"], group: .data),
    ]
    if session.hasStarted, !session.isFinished, commandBailoutAvailable {
      items.append(.init(
        id: "bailout", title: "中止长测试…", subtitle: "确认后显示未保存结果",
        systemImage: "figure.run", keywords: ["bail", "bailout", "中止", "退出"], group: .practice))
    }
    items.append(contentsOf: QuickTestParameterCommandCatalog.items)
    items.append(contentsOf: QuoteCommandCatalog.items(hasFavorites: hasFavoriteQuotesInCurrentSource))
    items.append(contentsOf: PracticePreferenceCommandCatalog.items)
    items.append(contentsOf: BehaviorCommandCatalog.items)
    items.append(contentsOf: PracticeThresholdCommandCatalog.items)
    items.append(contentsOf: FunboxCommandCatalog.items)
    items.append(contentsOf: InputRuleCommandCatalog.items)
    items.append(contentsOf: OfficialLayoutCommandCatalog.items)
    items.append(contentsOf: SoundCommandCatalog.items)
    items.append(contentsOf: CaretCommandCatalog.items)
    items.append(contentsOf: PaceCaretCommandCatalog.items)
    items.append(contentsOf: AppearanceCommandCatalog.items)
    items.append(contentsOf: KeyboardGuideCommandCatalog.items)
    items.append(KeyboardGuideSizeCommand.item)
    items.append(contentsOf: KeyboardGuideLayoutCommandCatalog.items)
    items.append(contentsOf: ThemeCommandCatalog.items(
      customThemes: settings.customThemes, favoriteThemeIDs: settings.favoriteThemeIDs))
    items.append(contentsOf: PresetCommandCatalog.items(
      presets: savedPresets.compactMap { preset in
        guard let definition = preset.definition else { return nil }
        return .init(id: preset.id, name: preset.name, definition: definition)
      }))
    items.append(contentsOf: ChallengeCommandCatalog.items(challenges: TypebarChallengeLibrary.all))
    items.append(contentsOf: LanguageCommandCatalog.items(languages: availableLanguages))
    if mode == .quote, let quote = availableQuotes.first(where: { $0.id == selectedQuoteID }),
      let favoriteCommand = QuoteFavoriteCommand.item(
        currentQuoteID: quote.id, isFavorite: settings.isFavoriteQuote(quote.id))
    {
      items.append(favoriteCommand)
    }
    return items
  }

  private func runCommand(_ item: CommandPaletteItem) {
    if let target = SoundCommandCatalog.target(for: item.id) {
      target.apply(to: settings)
      switch target.preview {
      case .click(let style):
        TypingFeedbackSound.shared.playClick(style: style, volume: settings.soundVolume)
      case .error(let style):
        TypingFeedbackSound.shared.playError(style: style, volume: settings.soundVolume)
      case .timeWarning:
        TypingFeedbackSound.shared.playTimeWarning(
          style: settings.timeWarningSoundStyle, volume: settings.soundVolume)
      case nil:
        break
      }
      return
    }
    if let target = CaretCommandCatalog.target(for: item.id) {
      target.apply(to: settings)
      return
    }
    if let target = PaceCaretCommandCatalog.target(for: item.id) {
      switch target {
      case .mode:
        activeChallengeID = nil
        target.apply(to: settings)
        reset()
      case .customSpeed:
        showingPaceGuideSpeedEditor = true
      }
      return
    }
    if let target = AppearanceCommandCatalog.target(for: item.id) {
      if target.exitsChallenge { activeChallengeID = nil }
      target.apply(to: settings)
      return
    }
    if let target = KeyboardGuideCommandCatalog.target(for: item.id) {
      if target.exitsChallenge { activeChallengeID = nil }
      target.apply(to: settings)
      return
    }
    if item.id == KeyboardGuideSizeCommand.item.id {
      showingKeyboardGuideScaleEditor = true
      return
    }
    if let target = KeyboardGuideLayoutCommandCatalog.target(for: item.id) {
      if target.exitsChallenge { activeChallengeID = nil }
      target.apply(to: settings)
      if target.requiresRestart { reset() }
      return
    }
    if let target = OfficialLayoutCommandCatalog.target(for: item.id) {
      if target.exitsChallenge { activeChallengeID = nil }
      target.apply(to: settings)
      if target.requiresRestart { reset() }
      return
    }
    if let target = InputRuleCommandCatalog.target(for: item.id) {
      if target.exitsChallenge { activeChallengeID = nil }
      target.apply(to: settings)
      if target.requiresRestart { reset() }
      return
    }
    if let target = BehaviorCommandCatalog.target(for: item.id) {
      target.apply(to: settings)
      return
    }
    if let target = PracticeThresholdCommandCatalog.target(for: item.id) {
      if target.applyImmediate(to: settings) {
        activeChallengeID = nil
        reset()
      } else {
        practiceThresholdEditorKind = target.editorKind
      }
      return
    }
    if let target = FunboxCommandCatalog.target(for: item.id) {
      if session.hasStarted && settings.testModifiers.contains(.noQuit) {
        restartLockMessage = "锁定重开已开启：请完成或放弃本次测试。"
        return
      }
      switch target {
      case .weakSpot:
        showingWeakSpots = true
      case .polyglot:
        activeChallengeID = nil
        language = language == .mixedLanguages ? .english : .mixedLanguages
        reset()
      case .clear, .modifier:
        let updatedMode = FunboxCommandPolicy.mode(
          afterToggling: target, currentMode: mode, currentModifiers: settings.testModifiers)
        guard let updated = FunboxCommandPolicy.updatedModifiers(
          for: target, current: settings.testModifiers,
          isInfinite: session.configuration.isInfinite, hasStarted: session.hasStarted)
        else {
          restartLockMessage = "当前无限测试不支持这个修饰器；请先选择有限时长或字数。"
          return
        }
        settings.testModifiers = updated
        mode = updatedMode
        if target == .clear && language == .mixedLanguages { language = .english }
        activeChallengeID = nil
        reset()
      }
      return
    }
    if let target = PracticePreferenceCommandCatalog.target(for: item.id) {
      if target.exitsChallenge { activeChallengeID = nil }
      switch target {
      case .difficulty(let difficulty): settings.difficulty = difficulty
      case .repeatQuotes(let enabled): settings.repeatQuotes = enabled
      case .saveCompletedResults(let enabled): settings.saveCompletedResults = enabled
      case .englishVariant(let variant): settings.englishVariant = variant
      }
      if target.requiresRestart { reset() }
      return
    }
    if let selectedLanguage = LanguageCommandCatalog.target(for: item.id) {
      guard availableLanguages.contains(selectedLanguage) else { return }
      activeChallengeID = nil
      let changed = language != selectedLanguage
      language = selectedLanguage
      if !changed {
        languageChanged(to: selectedLanguage)
        refreshZipfNotice()
      }
      return
    }
    if let target = QuoteCommandCatalog.target(for: item.id) {
      if target == .favorites, !hasFavoriteQuotesInCurrentSource { return }
      activeChallengeID = nil
      mode = .quote
      quoteQueue.reset()
      switch target {
      case .lengths(let lengths):
        quoteSelectionMode = .lengths
        quoteLengths = QuoteLengthSelection.normalized(lengths)
      case .favorites:
        quoteSelectionMode = .favorites
      case .search:
        quoteSelectionMode = .search
      }
      ensureSelectedQuote()
      reset()
      return
    }
    if let target = QuickTestParameterCommandCatalog.target(for: item.id) {
      switch target {
      case .customTime:
        showingCustomTimeEditor = true
        return
      case .customWords:
        showingCustomWordsEditor = true
        return
      case .timed, .words, .punctuation, .numbers:
        break
      }
    }
    if TestConfigurationCommandChallengePolicy.exitsChallenge(for: item.id) {
      activeChallengeID = nil
    }
    if let target = QuickTestParameterCommandCatalog.target(for: item.id) {
      switch target {
      case .timed(let seconds):
        mode = .time
        duration = seconds
      case .words(let count):
        mode = .words
        wordLimit = count
      case .customTime:
        return
      case .customWords:
        return
      case .punctuation(let enabled):
        contentOptions.includePunctuation = enabled
      case .numbers(let enabled):
        contentOptions.includeNumbers = enabled
      }
      reset()
      return
    }
    if let target = ThemeCommandCatalog.target(for: item.id) {
      settings.followSystemTheme = false
      switch target {
      case .builtIn(let theme): settings.selectBuiltInTheme(theme)
      case .custom(let id): settings.selectCustomTheme(id)
      }
      return
    }
    if let presetID = PresetCommandCatalog.presetID(for: item.id),
      let preset = savedPresets.first(where: { $0.id == presetID })?.definition
    {
      apply(preset)
      return
    }
    if let challengeID = ChallengeCommandCatalog.challengeID(for: item.id),
      let challenge = TypebarChallengeLibrary.challenge(id: challengeID)
    {
      loadChallenge(challenge)
      return
    }
    switch item.id {
    case "restart": attemptRestart()
    case "mode.time":
      mode = .time
      reset()
    case "mode.words":
      mode = .words
      reset()
    case "mode.quote":
      mode = .quote
      reset()
    case "mode.zen":
      mode = .zen
      reset()
    case "mode.custom":
      mode = .custom
      reset()
    case "history": showingHistory = true
    case "weakSpots": showingWeakSpots = true
    case "presets": showingPresets = true
    case "challenges": showingChallenges = true
    case "savedTexts": showingSavedTexts = true
    case "data": showingDataMigration = true
    case "sync": showingSync = true
    case "friends": showingConnections = true
    case "notifications": showingNotifications = true
    case "settings": openSettings()
    case AboutCommand.identifier: openWindow(id: "about")
    case ReleaseHistoryCommand.identifier: openWindow(id: "release-history")
    case "share": showingTestShare = true
    case "bailout": showingCommandBailoutConfirmation = true
    case QuoteFavoriteCommand.identifier:
      guard mode == .quote, availableQuotes.contains(where: { $0.id == selectedQuoteID }) else { return }
      toggleSelectedQuoteFavorite()
    default: break
    }
  }

  private func practiceThresholdValue(for kind: PracticeThresholdEditorKind) -> Double {
    switch kind {
    case .minimumWpm: settings.minimumWpm
    case .minimumAccuracy: settings.minimumAccuracy
    case .minimumWordBurst: settings.minimumWordBurstWpm
    }
  }

  private func applyPracticeThreshold(_ value: Double, kind: PracticeThresholdEditorKind) {
    activeChallengeID = nil
    PracticeThresholdApplication.apply(value, kind: kind, to: settings)
    reset()
  }

  private var configuration: TestConfiguration {
    if let activeChallenge {
      let challengeConfiguration = activeChallenge.preset.configuration.with(challengeID: activeChallenge.id)
      return challengeConfiguration.with(
        modifiers: effectiveTestModifiers(
          for: challengeConfiguration.language, mode: challengeConfiguration.mode,
          mixedLanguageComponents: challengeConfiguration.mixedLanguageComponents,
          baseModifiers: challengeConfiguration.modifiers))
    }
    switch mode {
    case .time:
      return .timed(
        seconds: TimeInterval(duration), difficulty: settings.difficulty,
        rules: settings.inputRules, language: language, englishVariant: settings.englishVariant,
        mixedLanguageComponents: mixedLanguageComponents, contentOptions: contentOptions
      ).with(modifiers: effectiveTestModifiers(for: language, mode: .time))
    case .words:
      return .words(
        wordLimit, difficulty: settings.difficulty, rules: settings.inputRules, language: language,
        englishVariant: settings.englishVariant, mixedLanguageComponents: mixedLanguageComponents,
        contentOptions: contentOptions
      ).with(modifiers: effectiveTestModifiers(for: language, mode: .words))
    case .quote:
      return .init(
        mode: .quote, duration: nil, wordLimit: nil, difficulty: settings.difficulty,
        rules: settings.inputRules, language: language, englishVariant: settings.englishVariant,
        quoteLength: QuoteLengthSelection.legacyValue(for: quoteLengths), quoteLengths: quoteLengths,
        quoteSelectionMode: quoteSelectionMode,
        mixedLanguageComponents: mixedLanguageComponents,
        modifiers: effectiveTestModifiers(for: language, mode: .quote), contentOptions: contentOptions)
    case .zen:
      return .init(
        mode: .zen, duration: nil, wordLimit: nil, difficulty: settings.difficulty,
        rules: settings.inputRules, language: language, englishVariant: settings.englishVariant,
        mixedLanguageComponents: mixedLanguageComponents,
        modifiers: effectiveTestModifiers(for: language, mode: .zen), contentOptions: contentOptions)
    case .custom:
      let duration = customTextCompletion == .time ? TimeInterval(customTextDuration) : nil
      let wordLimit = customTextCompletion == .words ? customTextWordLimit : nil
      let sectionLimit =
        customTextCompletion == .sections
        ? min(customTextSectionLimit, customTextSections.count) : nil
      return .init(
        mode: .custom, duration: duration, wordLimit: wordLimit, difficulty: settings.difficulty,
        rules: settings.inputRules, language: language, englishVariant: settings.englishVariant,
        customTextCompletion: customTextCompletion,
        customTextSectionLimit: sectionLimit,
        customTextOrdering: customTextCompletion == .sections ? .inOrder : customTextOrdering,
        mixedLanguageComponents: mixedLanguageComponents,
        modifiers: effectiveTestModifiers(for: language, mode: .custom),
        contentOptions: contentOptions)
    }
  }

  private func effectiveTestModifiers(
    for selectedLanguage: TypingLanguage, mode: TestMode,
    mixedLanguageComponents: [TypingLanguage]? = nil, baseModifiers: [TestModifier]? = nil
  ) -> [TestModifier] {
    ArabicLazyInputPolicy.effectiveModifiers(
      baseModifiers ?? settings.testModifiers, language: selectedLanguage, mode: mode,
      mixedLanguageComponents: mixedLanguageComponents ?? self.mixedLanguageComponents,
      automaticallyEnabled: settings.prefersArabicLazyInput)
  }

  private func refreshZipfNotice() {
    zipfNotice = ZipfFrequencyPolicy.notice(for: language, modifiers: settings.testModifiers)
    zipfNoticeGeneration &+= 1
    let generation = zipfNoticeGeneration
    guard zipfNotice != nil else { return }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(7))
      guard generation == zipfNoticeGeneration else { return }
      zipfNotice = nil
    }
  }

  private var availableLanguages: [TypingLanguage] {
    mode == .quote ? TypingLanguage.allCases.filter(\.supportsQuotes) : TypingLanguage.allCases
  }

  private var availableQuoteSources: [QuoteSource] {
    language.supportsCommunityQuoteSubmission ? Array(QuoteSource.allCases) : [.builtIn]
  }

  private var presetDefinition: SavedTestPreset {
    .init(
      configuration: configuration,
      quoteID: mode == .quote ? selectedQuoteID : nil,
      customText: mode == .custom ? customText : nil,
      activeResultTags: settings.activeResultTags
    )
  }

  private func apply(_ preset: SavedTestPreset) {
    practiceReturnPreset = nil
    let challenge = TypebarChallengeLibrary.challenge(id: preset.configuration.challengeID)
    activeChallengeID = challenge?.id
    let configuration = challenge?.preset.configuration ?? preset.configuration
    mode = configuration.mode
    if let duration = configuration.duration { self.duration = Int(duration) }
    if let wordLimit = configuration.wordLimit { self.wordLimit = wordLimit }
    let requestedQuoteID = preset.quoteID
    if let requestedQuoteID { selectedQuoteID = requestedQuoteID }
    if let customText = preset.customText { self.customText = customText }
    customTextCompletion = configuration.customTextCompletion
    if configuration.customTextCompletion == .time, let duration = configuration.duration {
      customTextDuration = Int(duration)
    }
    if configuration.customTextCompletion == .words, let wordLimit = configuration.wordLimit {
      customTextWordLimit = wordLimit
    }
    if configuration.customTextCompletion == .sections,
      let sectionLimit = configuration.customTextSectionLimit
    {
      customTextSectionLimit = sectionLimit
    }
    customTextOrdering = configuration.customTextOrdering
    language = configuration.language
    constrainQuoteSource(for: language)
    mixedLanguageComponents = configuration.mixedLanguageComponents
    quoteSelectionMode = configuration.quoteSelectionMode
    if quoteSelectionMode == .search { quoteSearchQuery = "" }
    quoteLengths = configuration.effectiveQuoteLengths
    quoteSelectionMode = QuoteSelection.resolvedMode(
      quoteSelectionMode, hasEligibleQuotes: !availableQuotes.isEmpty)
    quoteQueue.reset()
    contentOptions = configuration.contentOptions
    settings.apply(configuration)
    if let activeResultTags = preset.activeResultTags {
      settings.activeResultTags = activeResultTags
    }
    ensureSelectedQuote()
    if quoteSelectionMode == .search, selectedQuoteID != requestedQuoteID {
      quoteSelectionMode = .lengths
      ensureSelectedQuote()
    }
    reset()
  }

  private var activeChallenge: TypebarChallenge? {
    TypebarChallengeLibrary.challenge(id: activeChallengeID)
  }

  private func loadChallenge(_ challenge: TypebarChallenge) {
    var preset = challenge.preset
    preset.configuration = preset.configuration.with(challengeID: challenge.id)
    apply(preset)
  }

  private func languageChanged(to language: TypingLanguage) {
    constrainQuoteSource(for: language)
    if mode == .quote {
      quoteQueue.reset()
      ensureSelectedQuote()
    }
    reset()
  }

  private func constrainQuoteSource(for language: TypingLanguage) {
    guard !language.supportsCommunityQuoteSubmission, quoteSource == .community else { return }
      quoteSource = .builtIn
      communityQuotes = []
      communityQuoteRatings = [:]
      communityQuoteMessage =
        "Swiss German 的参考路径复用 Typebar 自有 German 引语，不使用社区投稿。"
  }

  private func mixedLanguageBinding(for component: TypingLanguage) -> Binding<Bool> {
    Binding(
      get: { mixedLanguageComponents.contains(component) },
      set: { enabled in
        if enabled {
          mixedLanguageComponents = TypingLanguage.normalizedMixedComponents(
            mixedLanguageComponents + [component])
        } else if mixedLanguageComponents.count > 2 {
          mixedLanguageComponents.removeAll { $0 == component }
          mixedLanguageComponents = TypingLanguage.normalizedMixedComponents(
            mixedLanguageComponents)
        }
        reset()
      }
    )
  }

  private var availableQuotes: [OfflineQuote] {
    QuoteSelection.filtered(
      currentSourceQuotes, mode: quoteSelectionMode, lengths: quoteLengths,
      searchQuery: quoteSearchQuery, isFavorite: settings.isFavoriteQuote)
  }

  private var currentSourceQuotes: [OfflineQuote] {
    quoteSource == .builtIn
      ? OfflineContent.quotes(for: language)
      : communityQuotes.filter { $0.language == language }
  }

  private var hasFavoriteQuotesInCurrentSource: Bool {
    currentSourceQuotes.contains { settings.isFavoriteQuote($0.id) }
  }

  private func refreshCommunityQuotes() {
    isLoadingCommunityQuotes = true
    communityQuoteMessage = nil
    Task {
      do {
        let remoteQuotes = try await account.publicQuotes(language: language)
        communityQuoteRatings = Dictionary(
          uniqueKeysWithValues: remoteQuotes.map {
            (
              $0.id,
              .init(
                quoteID: $0.id, upvotes: $0.upvotes, downvotes: $0.downvotes,
                viewerRating: $0.viewerRating)
            )
          })
        communityQuotes = remoteQuotes.map { quote in
          .init(
            id: "community-\(quote.id.uuidString.lowercased())", title: quote.attribution ?? "社区投稿",
            text: quote.text, language: language,
            length: QuoteLengthPolicy.actualLength(for: quote.text, language: language))
        }
        communityQuoteMessage =
          remoteQuotes.isEmpty ? "该语言还没有已审核内容。" : "已载入 \(remoteQuotes.count) 条已审核内容。"
        if quoteSelectionMode == .favorites, availableQuotes.isEmpty {
          quoteSelectionMode = .lengths
        }
        quoteQueue.reset()
        guard !availableQuotes.isEmpty else {
          isLoadingCommunityQuotes = false
          return
        }
        ensureSelectedQuote()
        reset()
      } catch {
        communityQuoteMessage = "无法载入社区引语：\(error.localizedDescription)"
      }
      isLoadingCommunityQuotes = false
    }
  }

  private var selectedCommunityQuoteID: UUID? {
    guard selectedQuoteID.hasPrefix("community-") else { return nil }
    return UUID(uuidString: String(selectedQuoteID.dropFirst("community-".count)))
  }

  private func reportSelectedCommunityQuote() {
    guard let quoteID = selectedCommunityQuoteID else { return }
    Task {
      do {
        try await account.reportQuote(quoteID, reason: quoteReportReason, note: quoteReportNote)
        quoteReportNote = ""
        communityQuoteMessage = "已私下提交举报；引语作者不会收到通知。"
      } catch {
        communityQuoteMessage = "无法提交举报：\(error.localizedDescription)"
      }
    }
  }

  @ViewBuilder
  private var communityRatingControls: some View {
    HStack(spacing: 8) {
      let rating = selectedCommunityQuoteID.flatMap { communityQuoteRatings[$0] }
      Text("社区评价：支持 \(rating?.upvotes ?? 0) · 不适合 \(rating?.downvotes ?? 0)")
        .font(.caption).foregroundStyle(.secondary)
      if account.currentUser != nil, let quoteID = selectedCommunityQuoteID {
        Button("不适合") { rateCommunityQuote(quoteID, value: .down) }
          .buttonStyle(.bordered)
          .tint(rating?.viewerRating == RemoteQuoteRatingValue.down.rawValue ? .red : .secondary)
        Button("不错") { rateCommunityQuote(quoteID, value: .up) }
          .buttonStyle(.bordered)
          .tint(rating?.viewerRating == RemoteQuoteRatingValue.up.rawValue ? .green : .secondary)
        if rating?.viewerRating != nil {
          Button("撤销评价") { rateCommunityQuote(quoteID, value: .neutral) }
            .buttonStyle(.borderless)
        }
      } else {
        Text("登录后可评价").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func rateCommunityQuote(_ quoteID: UUID, value: RemoteQuoteRatingValue) {
    Task {
      do {
        let rating = try await account.rateQuote(quoteID, value: value)
        communityQuoteRatings[quoteID] = rating
        communityQuoteMessage = value == .neutral ? "已撤销你的社区评价。" : "已更新你的社区评价。"
      } catch {
        communityQuoteMessage = "无法更新社区评价：\(error.localizedDescription)"
      }
    }
  }

  private var customTextSections: [String] {
    CustomTextPolicy.sections(in: customText)
  }

  private func ensureSelectedQuote() {
    guard let first = availableQuotes.first else { return }
    if !availableQuotes.contains(where: { $0.id == selectedQuoteID }) {
      selectedQuoteID = first.id
    }
  }

  private func toggleSelectedQuoteFavorite() {
    settings.toggleFavoriteQuote(selectedQuoteID)
    guard quoteSelectionMode == .favorites else {
      ensureSelectedQuote()
      return
    }
    if availableQuotes.isEmpty { quoteSelectionMode = .lengths }
    quoteQueue.reset()
    ensureSelectedQuote()
    reset()
  }

  private func chooseNextQuote() {
    guard quoteSelectionMode.advancesAutomatically else { return }
    selectedQuoteID = quoteQueue.next(from: availableQuotes, avoiding: selectedQuoteID) ?? selectedQuoteID
  }

  private func quoteLengthSelectionBinding(for length: QuoteLength) -> Binding<Bool> {
    Binding(
      get: { quoteLengths.contains(length) },
      set: { selected in
        guard selected || quoteLengths.count > 1 else { return }
        if selected {
          quoteLengths.insert(length)
        } else {
          quoteLengths.remove(length)
        }
        quoteQueue.reset()
        ensureSelectedQuote()
        reset()
      }
    )
  }

  private func startWordPractice(_ words: [String], selectedTargetCount: Int) {
    guard let practice = WordPracticeText.sectionedPractice(
      segments: words, selectedTargetCount: selectedTargetCount)
    else { return }
    if practiceReturnPreset == nil { practiceReturnPreset = presetDefinition }
    customText = practice.text
    customTextCompletion = .sections
    customTextSectionLimit = practice.sectionCount
    customTextOrdering = .inOrder
    mode = .custom
    completedResult = nil
    reset()
  }

  /// Result-driven word practice is temporary. Its source configuration is
  /// restored only when the user leaves it for a fresh test; repeating the
  /// result intentionally keeps the same practice prompt.
  private func restoreWordPracticeIfNeeded() -> Bool {
    guard let preset = practiceReturnPreset else { return false }
    practiceReturnPreset = nil
    apply(preset)
    return true
  }

  private func publishIfEnabled(_ result: CompletedTestResult) {
    if publicationResultID == result.id, publicationState.isSending { return }
    publicationResultID = result.id
    publicationState = .idle
    guard settings.publishCompletedResults, let scope = account.resultPublicationScope else { return }
    publicationState = .sending
    Task {
      do {
        let response = try await account.submitCompletedResult(result, for: scope)
        pendingPublications.remove(result.id, for: scope)
        guard publicationResultID == result.id, account.resultPublicationScope == scope else { return }
        publicationState = .sent(publicationReceipt(for: response))
      } catch {
        let isQueued = ResultPublicationRetryPolicy.shouldQueue(error)
        if isQueued {
          pendingPublications.enqueue(result.id, for: scope)
        } else {
          pendingPublications.remove(result.id, for: scope)
        }
        guard publicationResultID == result.id, account.resultPublicationScope == scope else { return }
        publicationState = .failed(isQueued
          ? "本机成绩已保存并加入待发送队列；联网且登录同一账户时会自动重试：\(error.localizedDescription)"
          : "本机成绩已保存；服务未接受本次成绩：\(error.localizedDescription)")
      }
    }
  }

  private func saveCompletedResultLocally(_ result: CompletedTestResult) {
    let record = TestResultRecord(result: result)
    modelContext.insert(record)
    localResultSaveState = LocalResultSaveAttempt.perform { try modelContext.save() }
    if localResultSaveState.isSaved {
      savedResultRecord = record
    } else {
      modelContext.delete(record)
      savedResultRecord = nil
    }
  }

  private var pendingPublicationRetryTrigger: PendingPublicationRetryTrigger {
    .init(
      networkStatus: network.status,
      scope: account.resultPublicationScope,
      isEnabled: settings.publishCompletedResults)
  }

  private func retryPendingPublicationsIfPossible() {
    guard !isRetryingPendingPublications,
      settings.publishCompletedResults,
      network.status == .online,
      let scope = account.resultPublicationScope
    else { return }

    let resultIDs = pendingPublications.resultIDs(for: scope)
    guard !resultIDs.isEmpty else { return }
    let recordsByID = Dictionary(uniqueKeysWithValues: savedResults.map { ($0.id, $0) })
    var retryableResults: [CompletedTestResult] = []
    for resultID in resultIDs {
      guard let result = recordsByID[resultID]?.portableResult, result.outcome == .completed else {
        pendingPublications.remove(resultID, for: scope)
        continue
      }
      retryableResults.append(result)
    }
    guard !retryableResults.isEmpty else { return }

    isRetryingPendingPublications = true
    Task { @MainActor in
      defer { isRetryingPendingPublications = false }
      for result in retryableResults {
        guard settings.publishCompletedResults,
          network.status == .online,
          account.resultPublicationScope == scope
        else { break }
        if publicationResultID == result.id { publicationState = .sending }
        do {
          let response = try await account.submitCompletedResult(result, for: scope)
          pendingPublications.remove(result.id, for: scope)
          if publicationResultID == result.id, account.resultPublicationScope == scope {
            publicationState = .sent(publicationReceipt(for: response))
          }
        } catch {
          let remainsQueued = ResultPublicationRetryPolicy.shouldQueue(error)
          if !remainsQueued {
            pendingPublications.remove(result.id, for: scope)
          }
          if publicationResultID == result.id, account.resultPublicationScope == scope {
            publicationState = .failed(remainsQueued
              ? "待发送成绩仍未送达；保留在这台 Mac，稍后会再次尝试：\(error.localizedDescription)"
              : "服务未接受待发送成绩；已停止自动重试：\(error.localizedDescription)")
          }
          if remainsQueued { break }
        }
      }
    }
  }

  private func publicationReceipt(
    for response: RemoteResultSubmissionResponse
  ) -> ResultPublicationReceipt {
    let rank = response.weeklyExperienceRank.map { " · 本周 XP #\($0)" } ?? ""
    return .init(
      message: response.leaderboardEligible
        ? "已发送至自建服务 · +\(response.experienceGained) XP · 总计 \(response.totalExperience) XP\(rank)"
        : "已发送至自建服务 · +\(response.experienceGained) XP",
      dailyLeaderboardRank: response.dailyLeaderboardRank)
  }
}

private enum TestTerminalNotice: Hashable, Identifiable {
  case failed(savedLongTextProgress: Bool)
  case abandoned

  var id: Self { self }

  var title: String {
    switch self {
    case .failed: "本次测试失败"
    case .abandoned: "已放弃本次测试"
    }
  }

  var message: String {
    switch self {
    case .failed(let savedLongTextProgress):
      savedLongTextProgress
        ? "长文本进度已保存；本次没有保存为完成成绩。"
        : "本次没有保存为完成成绩。"
    case .abandoned: "本次没有保存为完成成绩。"
    }
  }
}

extension TestOutcome {
  func statusText(savesResult: Bool) -> String {
    switch self {
    case .active: "按任意键开始，Esc 可重新开始"
    case .completed:
      savesResult ? "本次完成 · 已保存到本机" : "本次完成 · 未保存为完成成绩"
    case .failed: "本次失败 · 未保存为完成成绩"
    case .invalidAFK: "本次因闲置无效 · 未保存为完成成绩"
    case .abandoned: "本次已放弃 · 未保存为完成成绩"
    case .bailedOut: "本次已中止 · 未保存为完成成绩"
    }
  }
}

private struct CompletedResultPresentation: Identifiable {
  let result: CompletedTestResult
  let savesResult: Bool
  let quoteFeedback: QuoteResultFeedbackTarget?
  let resultPersonalBestFeedback: ResultPersonalBestFeedback?
  let tagPersonalBestFeedback: [TagPersonalBestFeedback]
  let missedWords: [String]
  let missedWordPracticeWords: [String]
  let wordReviews: [TypedWordReview]
  let wordBursts: [Int?]
  let slowWordPractice: SlowWordPracticePlan?
  let missedAndSlowPractice: MissedAndSlowWordPracticePlan?
  let contextualMissedAndSlowPractice: ContextualMissedAndSlowWordPracticePlan?
  let contextualMissedPractice: ContextualMissedWordPracticePlan?
  let todayPractice: TodayPracticeSummary
  let repeatedSession: TypingSession
  let challengeEvaluation: ChallengeEvaluation?
  var id: UUID { result.id }
}

private struct CompletedResultView: View {
  let result: CompletedTestResult
  let savesResult: Bool
  let typingSpeedUnit: TypingSpeedUnit
  let alwaysShowDecimalPlaces: Bool
  let alwaysShowWordsHistory: Bool
  let showWordBurstHeatmap: Bool
  let startGraphsAtZero: Bool
  let resultPerformanceVisibility: ResultPerformanceVisibility
  let background: Color
  let panel: Color
  let accent: Color
  let colorScheme: ColorScheme
  let publicationState: ResultPublicationState
  let localResultSaveState: LocalResultSaveState
  let isOffline: Bool
  let savedResultRecord: TestResultRecord?
  let quoteFeedback: QuoteResultFeedbackTarget?
  let resultPersonalBestFeedback: ResultPersonalBestFeedback?
  let tagPersonalBestFeedback: [TagPersonalBestFeedback]
  let settings: AppSettings
  let quoteRatings: QuoteRatingStore
  let isSignedIn: Bool
  let initialCommunityRating: RemoteQuoteRatingResponse?
  let onRateCommunity: (UUID, RemoteQuoteRatingValue) async throws -> RemoteQuoteRatingResponse
  let onReportCommunity: (UUID, RemoteQuoteReportReason, String?) async throws -> Void
  let onRestart: () -> Void
  let onHistory: () -> Void
  let missedWords: [String]
  let missedWordPracticeWords: [String]
  let wordReviews: [TypedWordReview]
  let wordBursts: [Int?]
  let slowWordPractice: SlowWordPracticePlan?
  let missedAndSlowPractice: MissedAndSlowWordPracticePlan?
  let contextualMissedAndSlowPractice: ContextualMissedAndSlowWordPracticePlan?
  let contextualMissedPractice: ContextualMissedWordPracticePlan?
  let todayPractice: TodayPracticeSummary
  let onRepeat: () -> Void
  let challengeEvaluation: ChallengeEvaluation?
  let onResultPerformanceVisibilityChange: (ResultPerformanceVisibility) -> Void
  let onResultGraphScaleChange: (Bool) -> Void
  let onRetryPublication: () -> Void
  let onRetryLocalSave: () -> Void
  let onOpenDailyLeaderboard: () -> Void
  let onPracticeMissedWords: () -> Void
  let onPracticeContextualMissedWords: ([String], Int) -> Void
  let onPracticeSlowWords: ([String], Int) -> Void
  let onPracticeMissedAndSlowWords: ([String], Int) -> Void
  let onPracticeContextualMissedAndSlowWords: ([String], Int) -> Void
  @State private var exportStatus: String?
  @State private var communityRating: RemoteQuoteRatingResponse?
  @State private var quoteFeedbackStatus: String?
  @State private var quoteReportReason: RemoteQuoteReportReason = .other
  @State private var quoteReportNote = ""
  @State private var isUpdatingCommunityQuote = false
  @State private var showingSlowWordCopy = false
  @State private var slowWordThresholdText = ""
  @State private var inspectedResultWordIndexes: Set<Int> = []
  @State private var wordHistoryExpansionOverride: Bool?
  @State private var showingCommandPalette = false
  @State private var showingPracticeOptions = false

  var body: some View {
    VStack(spacing: 28) {
      VStack(spacing: 6) {
        Text(resultOutcomeTitle)
          .font(.title2.weight(.semibold))
        Text(resultOutcomeSubtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Text(ResultConfigurationSummaryPolicy.text(for: result))
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(3)
          .accessibilityLabel(
            "测试类型，\(ResultConfigurationSummaryPolicy.text(for: result))")
      }

      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(typingSpeedUnit.formatted(
          wpm: result.wpm, alwaysShowDecimalPlaces: alwaysShowDecimalPlaces))
          .font(.system(size: 72, weight: .bold, design: .rounded))
        Text(typingSpeedUnit.displayName).foregroundStyle(.secondary)
      }

      Grid(horizontalSpacing: 36, verticalSpacing: 14) {
        GridRow {
          metric("准确率", formattedAccuracy)
          metric("Raw \(typingSpeedUnit.displayName)", typingSpeedUnit.formatted(
            wpm: result.rawWpm, alwaysShowDecimalPlaces: alwaysShowDecimalPlaces))
        }
        GridRow {
          metric("错误", "\(result.errorCount)")
          metric("总用时", "\(Int(result.elapsedDuration)) 秒")
        }
        GridRow {
          metric("字符（匹配/错位/额外/跳过）", characterStatsText)
          metric("输入字符", "\(result.typedCharacterCount)")
        }
        GridRow {
          metric("稳定度", "\(consistencyText(consistency.typing))%")
          metric("按键稳定度", "\(consistencyText(consistency.key))%")
        }
        if result.afkDuration > 0 {
          GridRow {
            metric("闲置", "\(Int(result.afkDuration)) 秒 · \(afkPercentageText)%")
            metric("有效键入", "\(Int(result.engagedDuration)) 秒")
          }
        }
        if let keyDurationStats = result.keyDurationStats {
          GridRow {
            metric("平均按键时长", keyDurationText(keyDurationStats.averageMilliseconds))
            metric(
              "按键时长波动",
              "\(keyDurationText(keyDurationStats.standardDeviationMilliseconds)) · \(keyDurationStats.sampleCount) 次")
          }
        }
        if let keySpacingStats = result.keySpacingStats {
          GridRow {
            metric("平均按键间隔", keyDurationText(keySpacingStats.averageMilliseconds))
            metric(
              "按键间隔波动",
              "\(keyDurationText(keySpacingStats.standardDeviationMilliseconds)) · \(keySpacingStats.sampleCount) 次")
          }
        }
        if result.keyDurationStats != nil || result.keySpacingStats != nil {
          GridRow {
            metric("按键重叠", keyDurationText(result.keyOverlapDuration * 1_000))
            metric("重叠占比", keyOverlapPercentageText)
          }
        }
      }

      Label(
        "今日练习 \(todayPractice.formattedDuration) · \(todayPractice.completedTests) 次",
        systemImage: "clock.badge.checkmark")
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)

      if let quoteSource = result.quoteSource {
        Label(quoteSource.displayText, systemImage: quoteSource.kind.systemImage)
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityLabel("引语来源，\(quoteSource.displayText)")
      }

      ResultPerformanceChart(
        prompt: result.prompt,
        events: result.replayEvents,
        duration: result.elapsedDuration,
        reviews: wordReviews,
        typingSpeedUnit: typingSpeedUnit,
        startsAtZero: startGraphsAtZero,
        visibility: resultPerformanceVisibility,
        resultPersonalBestFeedback: localResultSaveState.isSaved
          ? resultPersonalBestFeedback : nil,
        tagPersonalBestFeedback: localResultSaveState.isSaved
          ? tagPersonalBestFeedback : [],
        onVisibilityChange: onResultPerformanceVisibilityChange,
        onScaleChange: onResultGraphScaleChange,
        onInspectionChange: { inspectedResultWordIndexes = Set($0) },
        accent: accent)

      if let challengeEvaluation {
        ChallengeResultView(evaluation: challengeEvaluation)
      }

      if isOffline {
        NetworkConnectivityNotice(kind: .offline)
      }

      if let saveFailure = localResultSaveState.failureMessage {
        VStack(spacing: 8) {
          Label("尚未保存到这台 Mac：\(saveFailure)", systemImage: "externaldrive.badge.exclamationmark")
            .font(.caption)
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
          if localResultSaveState.canRetry {
            Button("重新保存到本机", action: onRetryLocalSave)
              .buttonStyle(.borderedProminent)
          }
        }
      }

      if let publicationMessage = publicationState.message {
        VStack(spacing: 8) {
          HStack(spacing: 6) {
            if publicationState.isSending {
              ProgressView().controlSize(.small)
            }
            Text(publicationMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          if publicationState.canRetry {
            Button("重新发送成绩", action: onRetryPublication)
              .buttonStyle(.bordered)
          }
          if let dailyRank = publicationState.dailyLeaderboardRank {
            Button(action: onOpenDailyLeaderboard) {
              Label("今日同模式同语言排名 #\(dailyRank)", systemImage: "list.number")
            }
            .buttonStyle(.borderless)
            .accessibilityHint("打开本轮模式和语言的今日全局排行榜")
          }
        }
      }

      quoteFeedbackControls

      if let exportStatus {
        Text(exportStatus)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      resultPersonalBestFeedbackView

      tagPersonalBestFeedbackView

      if let savedResultRecord {
        ResultTagEditor(result: savedResultRecord)
      }

      if !wordReviews.isEmpty {
        WordReviewHistoryView(
          reviews: wordReviews,
          bursts: wordBursts,
          showsBurstHeatmap: showWordBurstHeatmap,
          typingSpeedUnit: typingSpeedUnit,
          accent: accent,
          highlightedWordIndexes: inspectedResultWordIndexes,
          isExpanded: wordHistoryExpansion)
      }

      if !result.prompt.isEmpty, !result.replayEvents.isEmpty {
        ReplayTimelineView(
          prompt: result.prompt, events: result.replayEvents, speedUnit: typingSpeedUnit,
          soundConfiguration: .init(settings: settings))
      }

      VStack(alignment: .leading, spacing: 10) {
        HStack {
          if localResultSaveState.isSaved {
            Button("查看历史", action: onHistory)
          }
          Button("命令", systemImage: "command") { showingCommandPalette = true }
            .keyboardShortcut("p", modifiers: [.command, .shift])
          Menu("导出") {
            Button("复制结果文字", action: copyResultText)
            Button("复制练习提示", action: copyResultPrompt)
            Button("复制实际输入", action: copyResultInput)
            if !missedWords.isEmpty {
              Button("复制错词列表", action: copyMissedWords)
            }
            if !wordReviews.isEmpty {
              Button("复制慢词列表…", action: prepareSlowWordCopy)
            }
            Button("复制结果图片", action: copyResultImage)
            Divider()
            Button("保存结果图片…", action: saveResultImage)
          }
          Spacer()
          Button("重复本轮", action: onRepeat)
          Button("再来一次", action: onRestart)
            .buttonStyle(.borderedProminent)
        }
        if !missedWords.isEmpty || slowWordPractice != nil {
          HStack {
            if !missedWords.isEmpty {
              Menu("错词练习") {
                Button("只练错词（\(missedWords.count)）", action: onPracticeMissedWords)
                if let contextualMissedPractice {
                Button("带前词上下文（\(contextualMissedPractice.missedWordCount)）") {
                    onPracticeContextualMissedWords(
                      contextualMissedPractice.phrases,
                      contextualMissedPractice.selectedTargetCount)
                  }
                }
                if let missedAndSlowPractice {
                  Divider()
                  Button("错词 + 慢词（\(missedAndSlowPractice.selectedTargetCount)）") {
                    onPracticeMissedAndSlowWords(
                      missedAndSlowPractice.exerciseWords,
                      missedAndSlowPractice.selectedTargetCount)
                  }
                }
                if let contextualMissedAndSlowPractice {
                  Button("上下文错词 + 慢词（\(contextualMissedAndSlowPractice.selectedTargetCount)）") {
                    onPracticeContextualMissedAndSlowWords(
                      contextualMissedAndSlowPractice.exerciseSegments,
                      contextualMissedAndSlowPractice.selectedTargetCount)
                  }
                }
                Divider()
                Button("复制错词列表", action: copyMissedWords)
              }
            }
            if let slowWordPractice {
            Button("练习慢词（\(slowWordPractice.selectedWords.count)）") {
              onPracticeSlowWords(
                slowWordPractice.exerciseWords, slowWordPractice.selectedWords.count)
              }
            }
            Spacer()
          }
        }
      }
    }
    .padding(32)
    .frame(width: 390)
    .focusedSceneValue(\.openCommandPalette) { showingCommandPalette = true }
    .onAppear {
      communityRating = initialCommunityRating
    }
    .sheet(isPresented: $showingCommandPalette) {
      CommandPaletteView(
        items: resultCommandItems,
        listMode: settings.commandPaletteListMode,
        onSelect: runResultCommand)
    }
    .sheet(isPresented: $showingPracticeOptions) {
      CompletedResultPracticeOptionsView(
        availability: resultPracticeAvailability,
        missedCount: missedWords.count,
        contextualMissedCount: contextualMissedPractice?.missedWordCount ?? 0,
        slowCount: slowWordPractice?.selectedWords.count ?? 0
      ) { route in
        showingPracticeOptions = false
        Task { @MainActor in
          await Task.yield()
          runResultPractice(route)
        }
      }
    }
    .alert("复制慢词列表", isPresented: $showingSlowWordCopy) {
      TextField("WPM 阈值", text: $slowWordThresholdText)
      Button("取消", role: .cancel) {}
      Button("复制", action: copySlowWords)
    } message: {
      Text("复制本轮 Burst 严格低于该 WPM 的已输入词；默认值是本轮有效 Burst 的平均值。")
    }
  }

  private var characterStatsText: String {
    let stats = result.characterStats
    return "\(stats.matched)/\(stats.incorrect)/\(stats.extra)/\(stats.missed)"
  }

  private var wordHistoryExpansion: Binding<Bool> {
    Binding(
      get: { wordHistoryExpansionOverride ?? alwaysShowWordsHistory },
      set: { wordHistoryExpansionOverride = $0 })
  }

  private var resultCommandItems: [CommandPaletteItem] {
    CompletedResultCommandCatalog.items(
      availability: .init(
        hasCopyableWords: ResultPromptText.make(for: result, reviews: wordReviews) != nil,
        hasWordHistory: !wordReviews.isEmpty,
        hasMissedWordPractice: !missedWords.isEmpty,
        hasSlowWordPractice: slowWordPractice != nil,
        hasCombinedPractice: missedAndSlowPractice != nil,
        hasConfigurablePractice: resultPracticeAvailability.hasAny))
  }

  private var resultPracticeAvailability: CompletedResultPracticeAvailability {
    .init(
      hasMissed: !missedWords.isEmpty,
      hasContextualMissed: contextualMissedPractice != nil,
      hasSlow: slowWordPractice != nil,
      hasMissedAndSlow: missedAndSlowPractice != nil,
      hasContextualMissedAndSlow: contextualMissedAndSlowPractice != nil)
  }

  private func runResultCommand(_ item: CommandPaletteItem) {
    guard let action = CompletedResultCommandCatalog.action(for: item.id) else { return }
    switch action {
    case .next:
      leaveCommandPalette(then: onRestart)
    case .repeatTest:
      leaveCommandPalette(then: onRepeat)
    case .practiceMissed:
      leaveCommandPalette { runResultPractice(.missed) }
    case .practiceSlow:
      leaveCommandPalette { runResultPractice(.slow) }
    case .practiceCombined:
      leaveCommandPalette { runResultPractice(.missedAndSlow) }
    case .configurePractice:
      leaveCommandPalette { showingPracticeOptions = true }
    case .toggleWordHistory:
      guard !wordReviews.isEmpty else { return }
      wordHistoryExpansion.wrappedValue.toggle()
    case .copyWords:
      copyResultPrompt()
    case .copyImage:
      copyResultImage()
    case .saveImage:
      leaveCommandPalette(then: saveResultImage)
    }
  }

  private func runResultPractice(_ route: CompletedResultPracticeRoute) {
    switch route {
    case .missed:
      guard !missedWords.isEmpty else { return }
      onPracticeMissedWords()
    case .contextualMissed:
      guard let contextualMissedPractice else { return }
      onPracticeContextualMissedWords(
        contextualMissedPractice.phrases, contextualMissedPractice.selectedTargetCount)
    case .slow:
      guard let slowWordPractice else { return }
      onPracticeSlowWords(slowWordPractice.exerciseWords, slowWordPractice.selectedWords.count)
    case .missedAndSlow:
      guard let missedAndSlowPractice else { return }
      onPracticeMissedAndSlowWords(
        missedAndSlowPractice.exerciseWords, missedAndSlowPractice.selectedTargetCount)
    case .contextualMissedAndSlow:
      guard let contextualMissedAndSlowPractice else { return }
      onPracticeContextualMissedAndSlowWords(
        contextualMissedAndSlowPractice.exerciseSegments,
        contextualMissedAndSlowPractice.selectedTargetCount)
    }
  }

  private func leaveCommandPalette(then action: @escaping () -> Void) {
    showingCommandPalette = false
    Task { @MainActor in
      await Task.yield()
      action()
    }
  }

  private func keyDurationText(_ milliseconds: Double) -> String {
    "\(milliseconds.formatted(.number.precision(.fractionLength(0...1)))) ms"
  }

  private var keyOverlapPercentageText: String {
    guard result.elapsedDuration > 0 else { return "0%" }
    let percentage = result.keyOverlapDuration / result.elapsedDuration * 100
    return "\(percentage.formatted(.number.precision(.fractionLength(0...2))))%"
  }

  @ViewBuilder
  private var resultPersonalBestFeedbackView: some View {
    if localResultSaveState.isSaved,
      let feedback = resultPersonalBestFeedback, feedback.isNewPersonalBest
    {
      Label(
        feedback.previousBestWpm == nil
          ? "本机个人最佳 · 首次 PB \(feedback.currentWpm) WPM"
          : "本机个人最佳 · +\(feedback.improvement ?? 0) WPM",
        systemImage: "crown.fill"
      )
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.yellow)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var tagPersonalBestFeedbackView: some View {
    if localResultSaveState.isSaved, !tagPersonalBestFeedback.isEmpty {
      VStack(alignment: .leading, spacing: 7) {
        Label("标签个人最佳", systemImage: "tag")
          .font(.headline)
        ForEach(tagPersonalBestFeedback) { feedback in
          HStack(spacing: 7) {
            Image(systemName: feedback.isNewPersonalBest ? "crown.fill" : "crown")
              .foregroundStyle(feedback.isNewPersonalBest ? .yellow : .secondary)
            Text(feedback.tag)
            Spacer()
            if let improvement = feedback.improvement {
              Text(feedback.previousBestWpm == nil
                ? "首次 PB · \(feedback.currentWpm) WPM"
                : "+\(improvement) WPM")
                .foregroundStyle(accent)
            } else if let previousBestWpm = feedback.previousBestWpm {
              Text("PB \(previousBestWpm) WPM")
                .foregroundStyle(.secondary)
            }
          }
          .font(.caption)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var quoteFeedbackControls: some View {
    switch quoteFeedback {
    case let .builtIn(quoteID):
      VStack(alignment: .leading, spacing: 8) {
        Label("本轮引语", systemImage: "quote.bubble")
          .font(.headline)
        HStack(spacing: 8) {
          Button(settings.isFavoriteQuote(quoteID) ? "取消收藏" : "收藏引语") {
            settings.toggleFavoriteQuote(quoteID)
          }
          .buttonStyle(.bordered)
          Button("不适合") { quoteRatings.set(.down, for: quoteID) }
            .buttonStyle(.bordered)
            .tint(quoteRatings.rating(for: quoteID) == .down ? .red : .secondary)
          Button("不错") { quoteRatings.set(.up, for: quoteID) }
            .buttonStyle(.bordered)
            .tint(quoteRatings.rating(for: quoteID) == .up ? .green : .secondary)
          if quoteRatings.rating(for: quoteID) != .neutral {
            Button("清除评分") { quoteRatings.set(.neutral, for: quoteID) }
              .buttonStyle(.borderless)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

    case let .community(quoteID):
      VStack(alignment: .leading, spacing: 8) {
        Label("本轮社区引语", systemImage: "quote.bubble")
          .font(.headline)
        Text("社区评价：支持 \(communityRating?.upvotes ?? 0) · 不适合 \(communityRating?.downvotes ?? 0)")
          .font(.caption)
          .foregroundStyle(.secondary)
        if isSignedIn {
          HStack(spacing: 8) {
            Button("不适合") { rateCommunityQuote(quoteID, value: .down) }
              .buttonStyle(.bordered)
              .tint(communityRating?.viewerRating == RemoteQuoteRatingValue.down.rawValue ? .red : .secondary)
            Button("不错") { rateCommunityQuote(quoteID, value: .up) }
              .buttonStyle(.bordered)
              .tint(communityRating?.viewerRating == RemoteQuoteRatingValue.up.rawValue ? .green : .secondary)
            if communityRating?.viewerRating != nil {
              Button("撤销评价") { rateCommunityQuote(quoteID, value: .neutral) }
                .buttonStyle(.borderless)
            }
          }
          Picker("举报原因", selection: $quoteReportReason) {
            ForEach(RemoteQuoteReportReason.allCases, id: \.self) { reason in
              Text(reason.displayName).tag(reason)
            }
          }
          TextField("举报说明（可选，最多 400 字）", text: $quoteReportNote, axis: .vertical)
            .lineLimit(1...3)
            .onChange(of: quoteReportNote) { _, note in
              if note.count > 400 { quoteReportNote = String(note.prefix(400)) }
            }
          Button("私下举报此引语", role: .destructive) { reportCommunityQuote(quoteID) }
            .disabled(isUpdatingCommunityQuote)
          Text("举报仅供审核员处理；作者不会收到通知。")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("登录后可评价或私下举报社区引语。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let quoteFeedbackStatus {
          Text(quoteFeedbackStatus)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

    case nil:
      EmptyView()
    }
  }

  private func rateCommunityQuote(_ quoteID: UUID, value: RemoteQuoteRatingValue) {
    guard !isUpdatingCommunityQuote else { return }
    isUpdatingCommunityQuote = true
    Task {
      defer { isUpdatingCommunityQuote = false }
      do {
        communityRating = try await onRateCommunity(quoteID, value)
        quoteFeedbackStatus = value == .neutral ? "已撤销你的社区评价。" : "已更新你的社区评价。"
      } catch {
        quoteFeedbackStatus = "无法更新社区评价：\(error.localizedDescription)"
      }
    }
  }

  private func reportCommunityQuote(_ quoteID: UUID) {
    guard !isUpdatingCommunityQuote else { return }
    isUpdatingCommunityQuote = true
    let note = quoteReportNote.trimmingCharacters(in: .whitespacesAndNewlines)
    Task {
      defer { isUpdatingCommunityQuote = false }
      do {
        try await onReportCommunity(quoteID, quoteReportReason, note.isEmpty ? nil : note)
        quoteReportNote = ""
        quoteFeedbackStatus = "已私下提交举报；引语作者不会收到通知。"
      } catch {
        quoteFeedbackStatus = "无法提交举报：\(error.localizedDescription)"
      }
    }
  }

  private var resultOutcomeTitle: String {
    switch result.outcome {
    case .bailedOut: "已中止"
    case .invalidAFK: "闲置无效"
    case .active, .completed, .failed, .abandoned: "完成"
    }
  }

  private var resultOutcomeSubtitle: String {
    switch result.outcome {
    case .bailedOut: "中止结果只在当前窗口显示，不保存成绩"
    case .invalidAFK: "结束前连续约 5 秒没有文本输入；结果只在当前窗口显示，不保存成绩"
    case .active, .completed, .failed, .abandoned:
      savesResult
        ? (localResultSaveState.isSaved ? "已保存到这台 Mac" : "尚未保存到这台 Mac")
        : "练习模式：不保存成绩"
    }
  }

  private var afkPercentageText: String {
    result.afkPercentage.formatted(.number.precision(.fractionLength(0...2)))
  }

  private var consistency: ResultConsistency {
    ResultConsistencyPolicy.metrics(events: result.replayEvents, duration: result.elapsedDuration)
  }

  private func consistencyText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
  }

  private func metric(_ title: String, _ value: String) -> some View {
    VStack(spacing: 3) {
      Text(value).font(.headline)
      Text(title).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  private var formattedAccuracy: String {
    alwaysShowDecimalPlaces
      ? String(format: "%.2f%%", Double(result.accuracy))
      : "\(result.accuracy)%"
  }

  private func copyResultText() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(ResultShareText.make(for: result), forType: .string)
    exportStatus = "结果文字已复制"
  }

  private func copyResultInput() {
    guard let input = ResultInputText.make(for: result) else {
      exportStatus = "没有可复制的输入回放"
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(input, forType: .string)
    exportStatus = "实际输入已复制"
  }

  private func copyResultPrompt() {
    guard let prompt = ResultPromptText.make(for: result, reviews: wordReviews) else {
      exportStatus = "没有可复制的已练习提示"
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(prompt, forType: .string)
    exportStatus = "已练习提示已复制"
  }

  private func copyMissedWords() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(MissedWordCopyText.make(words: missedWords), forType: .string)
    exportStatus = "错词列表已复制"
  }

  private func prepareSlowWordCopy() {
    let threshold = SlowWordCopyPolicy.defaultThreshold(bursts: wordBursts)
    slowWordThresholdText = String(format: "%.0f", threshold)
    showingSlowWordCopy = true
  }

  private func copySlowWords() {
    guard let threshold = Double(slowWordThresholdText), threshold.isFinite, threshold > 0 else {
      exportStatus = "请输入大于 0 的 WPM 阈值"
      return
    }
    let words = SlowWordCopyPolicy.words(
      reviews: wordReviews, bursts: wordBursts, below: threshold)
    guard !words.isEmpty else {
      exportStatus = "没有低于 \(slowWordThresholdText) WPM 的已输入词"
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(words.joined(separator: " "), forType: .string)
    exportStatus = "已复制 \(words.count) 个慢词"
  }

  private func copyResultImage() {
    guard let image = resultImage else {
      exportStatus = "无法生成结果图片"
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
    exportStatus = "结果图片已复制"
  }

  private func saveResultImage() {
    guard let image = resultImage,
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let data = bitmap.representation(using: .png, properties: [:])
    else {
      exportStatus = "无法生成 PNG 图片"
      return
    }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = ResultImageExport.filename(for: result.finishedAt)
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try data.write(to: url, options: .atomic)
      exportStatus = "结果图片已保存"
    } catch {
      exportStatus = "无法保存结果图片"
    }
  }

  private var resultImage: NSImage? {
    ResultSnapshotImage.make(
      result: result,
      typingSpeedUnit: typingSpeedUnit,
      background: background,
      panel: panel,
      accent: accent,
      colorScheme: colorScheme)
  }
}

private struct CompletedResultPracticeOptionsView: View {
  @Environment(\.dismiss) private var dismiss
  let availability: CompletedResultPracticeAvailability
  let missedCount: Int
  let contextualMissedCount: Int
  let slowCount: Int
  let onStart: (CompletedResultPracticeRoute) -> Void
  @State private var selection: CompletedResultPracticeSelection

  init(
    availability: CompletedResultPracticeAvailability,
    missedCount: Int,
    contextualMissedCount: Int,
    slowCount: Int,
    onStart: @escaping (CompletedResultPracticeRoute) -> Void
  ) {
    self.availability = availability
    self.missedCount = missedCount
    self.contextualMissedCount = contextualMissedCount
    self.slowCount = slowCount
    self.onStart = onStart
    _selection = State(
      initialValue: CompletedResultPracticePolicy.defaultSelection(availability: availability))
  }

  private var route: CompletedResultPracticeRoute? {
    CompletedResultPracticePolicy.route(selection: selection, availability: availability)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("错词") {
          Picker("加入方式", selection: $selection.missed) {
            ForEach(CompletedResultPracticePolicy.missedChoices(availability: availability)) { choice in
              Text(choiceTitle(choice)).tag(choice)
            }
          }
          .pickerStyle(.radioGroup)
        }

        Section("慢词") {
          Toggle("加入本轮最慢的 (slowCount) 个词", isOn: $selection.includesSlow)
            .disabled(!availability.hasSlow)
        }

        Section {
          if route == nil {
            Label("至少选择一种有可用候选的练习。", systemImage: "info.circle")
              .foregroundStyle(.secondary)
          } else {
            Label("每个候选会按错误或速度权重重复，并以分节练习开始。", systemImage: "shuffle")
              .foregroundStyle(.secondary)
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("自选弱项练习")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("开始练习") {
            guard let route else { return }
            dismiss()
            onStart(route)
          }
          .disabled(route == nil)
        }
      }
    }
    .frame(width: 430, height: 330)
  }

  private func choiceTitle(_ choice: CompletedResultPracticeMissedSelection) -> String {
    switch choice {
    case .off: choice.displayName
    case .words: "\(choice.displayName)（\(missedCount)）"
    case .context: "\(choice.displayName)（\(contextualMissedCount)）"
    }
  }
}

@MainActor
enum ResultSnapshotImage {
  static func make(
    result: CompletedTestResult,
    typingSpeedUnit: TypingSpeedUnit,
    background: Color,
    panel: Color,
    accent: Color,
    colorScheme: ColorScheme
  ) -> NSImage? {
    let renderer = ImageRenderer(
      content: ResultSnapshotCard(
        result: result,
        typingSpeedUnit: typingSpeedUnit,
        background: background,
        panel: panel,
        accent: accent)
      .preferredColorScheme(colorScheme))
    renderer.scale = 2
    return renderer.nsImage
  }

}

private struct ResultSnapshotCard: View {
  let result: CompletedTestResult
  let typingSpeedUnit: TypingSpeedUnit
  let background: Color
  let panel: Color
  let accent: Color

  private var accuracyBlocks: Int { min(10, max(0, Int((Double(result.accuracy) / 10).rounded()))) }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .firstTextBaseline) {
        Text("TYPEBAR / LOCAL RESULT")
          .font(.system(size: 12, weight: .bold, design: .monospaced))
          .tracking(1.4)
        Spacer()
        Text(result.finishedAt, format: .dateTime.year().month().day().hour().minute())
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(.secondary)
      }
      Divider().overlay(accent.opacity(0.55))
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 4) {
          Text(typingSpeedUnit.formatted(wpm: result.wpm))
            .font(.system(size: 88, weight: .bold, design: .rounded))
          Text(typingSpeedUnit.displayName)
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundStyle(accent)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 8) {
          snapshotMetric("准确率", "\(result.accuracy)%")
          snapshotMetric("Raw \(typingSpeedUnit.displayName)", typingSpeedUnit.formatted(wpm: result.rawWpm))
          snapshotMetric("错误", "\(result.errorCount)")
        }
      }
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text("准确度刻度")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
          Spacer()
          Text("\(result.accuracy)%")
            .font(.system(size: 11, design: .monospaced))
        }
        HStack(spacing: 5) {
          ForEach(0..<10, id: \.self) { index in
            RoundedRectangle(cornerRadius: 2)
              .fill(index < accuracyBlocks ? accent : panel.opacity(0.7))
              .frame(height: 7)
          }
        }
      }
      HStack(alignment: .firstTextBaseline) {
        Text(ResultConfigurationSummaryPolicy.text(for: result))
          .lineLimit(2)
        Spacer()
        Text("OFFLINE")
      }
      .font(.system(size: 11, weight: .medium, design: .monospaced))
      .foregroundStyle(.secondary)
      if let quoteSource = result.quoteSource {
        Text("SOURCE / \(quoteSource.displayText)")
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(36)
    .frame(width: 760)
    .background(background)
    .foregroundStyle(.primary)
  }

  private func snapshotMetric(_ title: String, _ value: String) -> some View {
    HStack(spacing: 12) {
      Text(title)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(size: 17, weight: .semibold, design: .monospaced))
    }
  }
}

private struct ChallengeResultView: View {
  let evaluation: ChallengeEvaluation

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label(
        evaluation.passed
          ? "挑战通过：\(evaluation.challenge.title)" : "挑战未通过：\(evaluation.challenge.title)",
        systemImage: evaluation.passed ? "checkmark.seal.fill" : "xmark.seal.fill"
      )
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(evaluation.passed ? .green : .orange)
      if !evaluation.passed {
        ForEach(evaluation.failedRequirements, id: \.self) { requirement in
          Text(requirement).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
  }
}

private struct ReplaySoundConfiguration {
  let playsClicks: Bool
  let playsErrors: Bool
  let clickStyle: TypingClickSoundStyle
  let errorStyle: TypingErrorSoundStyle
  let volume: Double

  @MainActor init(settings: AppSettings) {
    playsClicks = settings.playKeyclickSound
    playsErrors = settings.playErrorBeep
    clickStyle = settings.clickSoundStyle
    errorStyle = settings.errorSoundStyle
    volume = settings.soundVolume
  }
}

private struct ReplayTimelineView: View {
  let prompt: String
  let events: [TypingReplayEvent]
  let speedUnit: TypingSpeedUnit
  let soundConfiguration: ReplaySoundConfiguration
  @State private var elapsed: TimeInterval = 0
  @State private var isPlaying = false
  @State private var selectedPromptIndex: Int?
  @State private var includesCurrentOffsetOnNextTick = true
  private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
  private let characterSeekOffsets: [Int: TimeInterval]

  private var duration: TimeInterval { events.last?.offset ?? 0 }
  private var replayedGlyphs: [TypingPromptGlyph] {
    TypingReplay.inputGlyphs(prompt: prompt, events: events, through: elapsed)
  }
  private var replayedAttributedText: AttributedString {
    let glyphs = replayedGlyphs
    guard !glyphs.isEmpty else {
      var waiting = AttributedString("等待播放")
      waiting.foregroundColor = .secondary
      return waiting
    }
    return glyphs.reduce(into: AttributedString()) { output, glyph in
      var character = AttributedString(String(glyph.character))
      switch glyph.state {
      case .correct:
        character.foregroundColor = .primary
      case .incorrect:
        character.foregroundColor = .red
        character.backgroundColor = .red.opacity(0.14)
      case .extra:
        character.foregroundColor = .red
        character.backgroundColor = .red.opacity(0.1)
        character.strikethroughStyle = .single
      case .pending, .current, .hidden:
        character.foregroundColor = .secondary
      }
      output += character
    }
  }
  private var performance: ResultPerformancePoint {
    ResultPerformanceTrace.point(prompt: prompt, events: events, elapsed: elapsed)
  }

  init(
    prompt: String, events: [TypingReplayEvent], speedUnit: TypingSpeedUnit,
    soundConfiguration: ReplaySoundConfiguration
  ) {
    let chronologicalEvents = TypingReplay.chronologicalEvents(events)
    self.prompt = prompt
    self.events = chronologicalEvents
    self.speedUnit = speedUnit
    self.soundConfiguration = soundConfiguration
    self.characterSeekOffsets = TypingReplay.characterSeekOffsets(
      prompt: prompt, events: chronologicalEvents)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("输入回放", systemImage: "play.rectangle")
          .font(.caption.weight(.medium))
        Spacer()
        Text(
          "\(speedUnit.formatted(wpm: performance.wpm)) \(speedUnit.displayName) · \(String(format: "%.1f", elapsed)) / \(String(format: "%.1f", duration)) 秒"
        )
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Text(replayedAttributedText)
        .font(.system(.caption, design: .monospaced))
        .lineLimit(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 4) {
        Text("目标（点按已输入字符定位）")
          .font(.caption2)
          .foregroundStyle(.secondary)
        ReplayCharacterPicker(
          text: prompt,
          reachableIndices: Set(characterSeekOffsets.keys),
          selectedIndex: selectedPromptIndex
        ) { index in
          guard let targetOffset = characterSeekOffsets[index] else { return }
          selectedPromptIndex = index
          elapsed = min(duration, targetOffset)
          isPlaying = false
          includesCurrentOffsetOnNextTick = false
        }
        .frame(height: 38)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
      }
      Slider(
        value: $elapsed, in: 0...max(duration, 0.01),
        onEditingChanged: { editing in
          if editing {
            isPlaying = false
            selectedPromptIndex = nil
            includesCurrentOffsetOnNextTick = false
          }
        })
        .accessibilityLabel("回放时间")
        .accessibilityHint("调整回放位置；目标文本也支持鼠标点选字符定位")
      HStack {
        Button(isPlaying ? "暂停" : "播放") {
          if elapsed >= duration {
            elapsed = 0
            includesCurrentOffsetOnNextTick = true
          }
          selectedPromptIndex = nil
          isPlaying.toggle()
        }
        .disabled(duration == 0)
        Button("重置") {
          elapsed = 0
          isPlaying = false
          selectedPromptIndex = nil
          includesCurrentOffsetOnNextTick = true
        }
        .disabled(elapsed == 0 && !isPlaying)
        Spacer()
      }
    }
    .onReceive(timer) { _ in
      guard isPlaying else { return }
      let previousElapsed = elapsed
      elapsed = min(duration, elapsed + 0.05)
      let soundLowerBound = includesCurrentOffsetOnNextTick
        ? -Double.leastNonzeroMagnitude : previousElapsed
      includesCurrentOffsetOnNextTick = false
      playSounds(after: soundLowerBound, through: elapsed)
      if elapsed >= duration { isPlaying = false }
    }
  }

  private func playSounds(after lowerBound: TimeInterval, through upperBound: TimeInterval) {
    for cue in TypingReplay.soundCues(
      prompt: prompt, events: events, after: lowerBound, through: upperBound)
    {
      switch TypingReplaySoundRoute.resolve(
        cue: cue, playsClicks: soundConfiguration.playsClicks,
        playsErrors: soundConfiguration.playsErrors)
      {
      case .none:
        break
      case .click:
        TypingFeedbackSound.shared.playClick(
          style: soundConfiguration.clickStyle, volume: soundConfiguration.volume)
      case .error:
        TypingFeedbackSound.shared.playError(
          style: soundConfiguration.errorStyle, volume: soundConfiguration.volume)
      }
    }
  }
}

private struct WordReviewHistoryView: View {
  let reviews: [TypedWordReview]
  let bursts: [Int?]
  let showsBurstHeatmap: Bool
  let typingSpeedUnit: TypingSpeedUnit
  let accent: Color
  let highlightedWordIndexes: Set<Int>
  @Binding var isExpanded: Bool

  private var heatmap: WordBurstHeatmap? {
    guard showsBurstHeatmap else { return nil }
    return WordBurstHeatmapPolicy.make(bursts: Array(bursts.prefix(reviews.count)))
  }

  init(
    reviews: [TypedWordReview],
    bursts: [Int?],
    showsBurstHeatmap: Bool,
    typingSpeedUnit: TypingSpeedUnit,
    accent: Color,
    highlightedWordIndexes: Set<Int> = [],
    isExpanded: Binding<Bool>
  ) {
    self.reviews = reviews
    self.bursts = bursts
    self.showsBurstHeatmap = showsBurstHeatmap
    self.typingSpeedUnit = typingSpeedUnit
    self.accent = accent
    self.highlightedWordIndexes = highlightedWordIndexes
    _isExpanded = isExpanded
  }

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 10) {
        if let heatmap {
          WordBurstHeatmapLegend(
            heatmap: heatmap,
            typingSpeedUnit: typingSpeedUnit,
            accent: accent)
        }
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 5) {
            ForEach(reviews) { review in
              HStack(spacing: 8) {
                Image(systemName: review.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                  .foregroundStyle(review.isCorrect ? .green : .red)
                Text(review.target)
                  .font(.system(.body, design: .monospaced))
                  .foregroundStyle(wordBurstHeatmapColor(heatmap?.tone(at: review.index), accent: accent))
                if !review.isCorrect {
                  Text("→ \(review.typed.isEmpty ? "∅" : review.typed)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                Spacer()
              }
              .padding(.horizontal, 5)
              .padding(.vertical, 3)
              .background(
                highlightedWordIndexes.contains(review.index)
                  ? accent.opacity(0.16) : .clear,
                in: RoundedRectangle(cornerRadius: 5))
              .accessibilityValue(
                highlightedWordIndexes.contains(review.index) ? "图表当前秒" : "")
            }
          }
        }
        .frame(maxHeight: 112)
      }
    } label: {
      HStack {
        Text("本次单词历史").font(.caption.weight(.medium))
        Spacer()
        Text("\(reviews.filter(\.isCorrect).count)/\(reviews.count) 正确")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    .onChange(of: highlightedWordIndexes) { _, indexes in
      if !indexes.isEmpty { isExpanded = true }
    }
  }
}

private struct WordBurstHeatmapLegend: View {
  let heatmap: WordBurstHeatmap
  let typingSpeedUnit: TypingSpeedUnit
  let accent: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("单词 Burst 热力图", systemImage: "flame")
        .font(.caption.weight(.medium))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 9) {
          ForEach(WordBurstHeatmapTone.scoredTones) { tone in
            HStack(spacing: 4) {
              Circle()
                .fill(wordBurstHeatmapColor(tone, accent: accent))
                .frame(width: 7, height: 7)
              Text("\(tone.title) \(formattedLowerBound(for: tone))+")
                .font(.caption2.monospacedDigit())
            }
          }
          HStack(spacing: 4) {
            Circle().fill(wordBurstHeatmapColor(.unmeasured, accent: accent)).frame(width: 7, height: 7)
            Text("无计时")
              .font(.caption2)
          }
        }
      }
      Text("颜色表示本次完成中的相对单词速度；灰色表示没有可测输入间隔。")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  private func formattedLowerBound(for tone: WordBurstHeatmapTone) -> String {
    guard let wpm = heatmap.lowerBound(for: tone) else { return "—" }
    return typingSpeedUnit.formatted(wpm: wpm)
  }
}

private func wordBurstHeatmapColor(_ tone: WordBurstHeatmapTone?, accent: Color) -> Color {
  switch tone {
  case .slow: .red
  case .measured: .orange
  case .steady: .primary
  case .fast: accent.opacity(0.72)
  case .swift: accent
  case .unmeasured, .none: .secondary
  }
}

private extension WordBurstHeatmapTone {
  var title: String {
    switch self {
    case .slow: "慢"
    case .measured: "偏慢"
    case .steady: "均衡"
    case .fast: "快"
    case .swift: "最快"
    case .unmeasured: "无计时"
    }
  }
}

private struct ResultPerformanceChart: View {
  let points: [ResultPerformancePoint]
  let reviews: [TypedWordReview]
  let events: [TypingReplayEvent]
  let typingSpeedUnit: TypingSpeedUnit
  let startsAtZero: Bool
  let accent: Color
  let onVisibilityChange: (ResultPerformanceVisibility) -> Void
  let onScaleChange: (Bool) -> Void
  let onInspectionChange: ([Int]) -> Void
  @State private var visibility: ResultPerformanceVisibility
  @State private var selectedElapsed: TimeInterval?
  private let resultPersonalBestFeedback: ResultPersonalBestFeedback?
  private let tagPersonalBestFeedback: [TagPersonalBestFeedback]

  init(
    prompt: String,
    events: [TypingReplayEvent],
    duration: TimeInterval,
    reviews: [TypedWordReview],
    typingSpeedUnit: TypingSpeedUnit,
    startsAtZero: Bool,
    visibility: ResultPerformanceVisibility,
    resultPersonalBestFeedback: ResultPersonalBestFeedback?,
    tagPersonalBestFeedback: [TagPersonalBestFeedback],
    onVisibilityChange: @escaping (ResultPerformanceVisibility) -> Void,
    onScaleChange: @escaping (Bool) -> Void,
    onInspectionChange: @escaping ([Int]) -> Void,
    accent: Color
  ) {
    points = ResultPerformanceTrace.points(prompt: prompt, events: events, duration: duration)
    self.reviews = reviews
    self.events = events
    self.typingSpeedUnit = typingSpeedUnit
    self.startsAtZero = startsAtZero
    self.onVisibilityChange = onVisibilityChange
    self.onScaleChange = onScaleChange
    self.onInspectionChange = onInspectionChange
    _visibility = State(initialValue: visibility)
    _selectedElapsed = State(initialValue: nil)
    self.resultPersonalBestFeedback = resultPersonalBestFeedback?.showsPreviousBestLine == true
      ? resultPersonalBestFeedback : nil
    self.tagPersonalBestFeedback = tagPersonalBestFeedback.filter(\.showsPreviousBestLine)
    self.accent = accent
  }

  var body: some View {
    if points.count >= 2 {
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Label("本次速度轨迹", systemImage: "chart.xyaxis.line")
            .font(.caption.weight(.medium))
          Spacer()
          Button(startsAtZero ? "从零" : "自适应") {
            onScaleChange(!startsAtZero)
          }
          .buttonStyle(.bordered)
          .controlSize(.mini)
          .tint(.secondary)
          .accessibilityLabel("图表纵轴范围")
          .accessibilityValue(startsAtZero ? "从零开始" : "按数据自适应")
          .help(startsAtZero ? "切换为按数据自适应" : "切换为从零开始")
        }
        HStack(spacing: 6) {
          traceToggle("Raw", isOn: visibilityBinding(\.raw), color: .secondary)
          traceToggle("Burst", isOn: visibilityBinding(\.burst), color: .orange)
          Button(visibility.smoothBurst ? "平滑" : "原始") {
            visibility.smoothBurst.toggle()
            onVisibilityChange(visibility)
          }
          .buttonStyle(.bordered)
          .controlSize(.mini)
          .tint(visibility.smoothBurst ? .orange : .secondary)
          .disabled(!visibility.burst)
          .accessibilityLabel("Burst 曲线")
          .accessibilityValue(visibility.smoothBurst ? "平滑" : "原始")
          .help(visibility.smoothBurst ? "显示原始 Burst 尖峰" : "平滑 Burst 尖峰")
          traceToggle("错误", isOn: visibilityBinding(\.errors), color: .red)
          if resultPersonalBestFeedback != nil {
            traceToggle("本机 PB", isOn: visibilityBinding(\.personalBestLine), color: .secondary)
          }
          if !tagPersonalBestFeedback.isEmpty {
            traceToggle("标签 PB", isOn: visibilityBinding(\.tagPersonalBestLine), color: .secondary)
          }
          Spacer()
        }
        Chart(displayedPoints) { point in
          LineMark(
            x: .value("秒", point.elapsed),
            y: .value(typingSpeedUnit.displayName, typingSpeedUnit.converted(wpm: point.wpm))
          )
          .foregroundStyle(accent)
          .interpolationMethod(.catmullRom)
          if visibility.raw {
            LineMark(
              x: .value("秒", point.elapsed),
              y: .value(typingSpeedUnit.displayName, typingSpeedUnit.converted(wpm: point.rawWpm))
            )
            .foregroundStyle(.secondary)
            .lineStyle(.init(lineWidth: 1, dash: [3, 3]))
          }
          if visibility.burst {
            LineMark(
              x: .value("秒", point.elapsed),
              y: .value(typingSpeedUnit.displayName, typingSpeedUnit.converted(wpm: point.burstWpm))
            )
            .foregroundStyle(.orange)
            .lineStyle(.init(lineWidth: 1))
          }
          if visibility.personalBestLine,
            let feedback = resultPersonalBestFeedback,
            let previousBestWpm = feedback.previousBestWpm
          {
            RuleMark(
              y: .value("本机 PB", typingSpeedUnit.converted(wpm: previousBestWpm)))
              .foregroundStyle(.secondary.opacity(0.6))
              .lineStyle(.init(lineWidth: 1, dash: [4, 4]))
              .annotation(position: .top, alignment: .center) {
                Text("本机 PB \(typingSpeedUnit.formatted(wpm: previousBestWpm))")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
          }
          if visibility.tagPersonalBestLine {
            ForEach(tagPersonalBestFeedback) { feedback in
              if let previousBestWpm = feedback.previousBestWpm {
                RuleMark(
                  y: .value(
                    "标签 PB", typingSpeedUnit.converted(wpm: previousBestWpm)))
                  .foregroundStyle(.secondary.opacity(0.6))
                  .lineStyle(.init(lineWidth: 1, dash: [1, 4]))
                  .annotation(position: .top, alignment: .leading) {
                    Text("\(feedback.tag) PB \(typingSpeedUnit.formatted(wpm: previousBestWpm))")
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                  }
              }
            }
          }
          if inspection?.point.id == point.id {
            RuleMark(x: .value("选中秒", point.elapsed))
              .foregroundStyle(accent.opacity(0.55))
              .lineStyle(.init(lineWidth: 1))
            PointMark(
              x: .value("秒", point.elapsed),
              y: .value(typingSpeedUnit.displayName, typingSpeedUnit.converted(wpm: point.wpm)))
              .foregroundStyle(accent)
              .symbolSize(38)
          }
        }
        .chartYScale(domain: .automatic(includesZero: startsAtZero))
        .chartXSelection(value: $selectedElapsed)
        .chartXAxis {
          AxisMarks(values: .automatic(desiredCount: 4)) { value in
            AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
            AxisTick()
            AxisValueLabel {
              if let elapsed = value.as(TimeInterval.self) {
                Text("\(Int(elapsed.rounded())) 秒")
              }
            }
          }
        }
        .frame(height: 118)
        .onHover { hovering in
          if !hovering { selectedElapsed = nil }
        }
        .onChange(of: selectedElapsed) { _, elapsed in
          let selectedWords = ResultPerformanceInspectionPolicy.inspection(
            nearestTo: elapsed, points: points, reviews: reviews, events: events)?.wordIndexes ?? []
          onInspectionChange(selectedWords)
        }
        .accessibilityHint("在图表中选择某一秒以查看指标并联动单词历史")
        if let inspection {
          resultInspectionView(inspection)
        }
        if visibility.errors {
          Chart(displayedPoints) { point in
            BarMark(
              x: .value("秒", point.elapsed),
              y: .value("错误", point.errorCount)
            )
            .foregroundStyle(.red.opacity(0.68))
          }
          .chartYScale(domain: .automatic(includesZero: true))
          .chartXAxis(.hidden)
          .frame(height: 30)
          .accessibilityLabel("按秒重建的错误轨迹")
        }
        Text(chartDescription)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .padding(10)
      .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
  }

  private var inspection: ResultPerformanceInspection? {
    ResultPerformanceInspectionPolicy.inspection(
      nearestTo: selectedElapsed, points: displayedPoints, reviews: reviews, events: events)
  }

  private var displayedPoints: [ResultPerformancePoint] {
    ResultBurstSmoothingPolicy.points(points, enabled: visibility.smoothBurst)
  }

  private func resultInspectionView(_ inspection: ResultPerformanceInspection) -> some View {
    HStack(spacing: 10) {
      Text("\(inspection.point.elapsed.formatted(.number.precision(.fractionLength(0...1)))) 秒")
        .fontWeight(.semibold)
      Text("WPM \(typingSpeedUnit.formatted(wpm: inspection.point.wpm))")
      if visibility.raw {
        Text("Raw \(typingSpeedUnit.formatted(wpm: inspection.point.rawWpm))")
      }
      if visibility.burst {
        Text("Burst \(typingSpeedUnit.formatted(wpm: inspection.point.burstWpm))")
      }
      if visibility.errors {
        Text("错误 \(inspection.point.errorCount)")
      }
      if !inspection.wordIndexes.isEmpty {
        Text("关联单词 \(inspection.wordIndexes.map { String($0 + 1) }.joined(separator: "、"))")
          .foregroundStyle(accent)
      }
      Spacer()
      Button {
        selectedElapsed = nil
      } label: {
        Image(systemName: "xmark.circle.fill")
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .accessibilityLabel("清除图表选择")
    }
    .font(.caption.monospacedDigit())
    .padding(.horizontal, 7)
    .padding(.vertical, 5)
    .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    .accessibilityElement(children: .combine)
  }

  private func traceToggle(_ title: String, isOn: Binding<Bool>, color: Color) -> some View {
    Button(title) { isOn.wrappedValue.toggle() }
      .buttonStyle(.bordered)
      .controlSize(.mini)
      .tint(isOn.wrappedValue ? color : .secondary)
      .accessibilityLabel("\(title)轨迹")
      .accessibilityValue(isOn.wrappedValue ? "显示" : "隐藏")
  }

  private var chartDescription: String {
    var description = "强调色为 WPM，灰虚线为 Raw，橙色为\(visibility.smoothBurst ? "平滑" : "原始") Burst"
    if resultPersonalBestFeedback != nil { description += "；灰横线为本机 PB" }
    if !tagPersonalBestFeedback.isEmpty { description += "；灰点划线为已有标签 PB" }
    return "\(description)；数据仅由本机输入回放重建。"
  }

  private func visibilityBinding(
    _ keyPath: WritableKeyPath<ResultPerformanceVisibility, Bool>
  ) -> Binding<Bool> {
    Binding(
      get: { visibility[keyPath: keyPath] },
      set: { value in
        visibility[keyPath: keyPath] = value
        onVisibilityChange(visibility)
      })
  }
}

private struct ResultsHistoryView: View {
  let settings: AppSettings
  let currentConfiguration: TestConfiguration
  fileprivate enum ActivityChartMeasure: String, CaseIterable, Identifiable {
    case completedTests
    case typingMinutes
    case averageSpeed
    case highestSpeed
    case averageAccuracy
    case averageConsistency
    case restartsPerCompletedTest

    var id: Self { self }

    var title: String {
      switch self {
      case .completedTests: "完成次数"
      case .typingMinutes: "练习分钟"
      case .averageSpeed: "平均速度"
      case .highestSpeed: "最高速度"
      case .averageAccuracy: "平均准确率"
      case .averageConsistency: "平均稳定度"
      case .restartsPerCompletedTest: "每次完成重开"
      }
    }
  }

  private struct HistoryChartPoint: Identifiable {
    let metric: ResultMetric
    let speedAverage10: Double
    let speedAverage100: Double
    let accuracyAverage10: Double
    let accuracyAverage100: Double
    let personalBestSpeed: Double

    var id: UUID { metric.id }
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \TestResultRecord.finishedAt, order: .reverse) private var results:
    [TestResultRecord]
  @Query(sort: \ResultFilterPresetRecord.createdAt, order: .reverse) private var filterPresets:
    [ResultFilterPresetRecord]
  @State private var selectedResult: TestResultRecord?
  @State private var modeFilter = Set(TestMode.allCases)
  @State private var languageFilter = Set(TypingLanguage.allCases)
  @State private var selectedTagFilter = ResultHistoryTagFilter()
  @State private var difficultyFilter = Set(Difficulty.allCases)
  @State private var personalBestFilter: ResultHistoryPersonalBestFilter = .all
  @State private var dateRangeFilter: ResultHistoryDateRange = .all
  @State private var punctuationFilter: ResultHistoryBinaryFilter = .all
  @State private var numbersFilter: ResultHistoryBinaryFilter = .all
  @State private var quoteLengthFilter = ResultHistoryFilter.filterableQuoteLengths
  @State private var timeLimitFilter = Set(ResultHistoryTimeLimit.allCases)
  @State private var wordLimitFilter = Set(ResultHistoryWordLimit.allCases)
  @State private var includesNoModifierFilter = true
  @State private var modifierFilter = Set(TestModifier.allCases)
  @State private var filterPresetName = ""
  @State private var activityChartMeasure: ActivityChartMeasure = .completedTests
  @State private var selectedHistoryDate: Date?
  @State private var historySortField: ResultHistorySortField = .finishedAt
  @State private var historySortDirection: ResultHistorySortDirection = .descending
  @State private var visibleResultLimit = ResultHistoryPagePolicy.pageSize
  @State private var csvExportStatus: String?
  @State private var showingPersonalBestTable = false

  private var filteredResults: [TestResultRecord] {
    let filter = ResultHistoryFilter(
      modes: modeFilter,
      languages: languageFilter,
      tagFilter: selectedTagFilter,
      personalBestFilter: personalBestFilter,
      difficulties: difficultyFilter,
      dateRange: dateRangeFilter,
      punctuation: punctuationFilter,
      numbers: numbersFilter,
      quoteLengths: quoteLengthFilter,
      timeLimits: timeLimitFilter,
      wordLimits: wordLimitFilter,
      modifierFilter: activeModifierFilter
    )
    let entries = results.map { result in
      let configuration = result.configuration
      return ResultHistoryEntry(
        id: result.id, mode: configuration?.mode, language: configuration?.language, tags: result.tags,
        finishedAt: result.finishedAt, difficulty: configuration?.difficulty,
        includesPunctuation: configuration?.contentOptions.includePunctuation,
        includesNumbers: configuration?.contentOptions.includeNumbers,
        quoteLength: configuration.flatMap { configuration -> QuoteLength? in
          guard configuration.mode == .quote else { return nil }
          return QuoteLengthPolicy.actualLength(for: result.prompt, language: configuration.language)
        },
        duration: configuration?.duration,
        wordLimit: configuration?.wordLimit,
        modifiers: configuration?.modifiers
      )
    }
    let ids = filter.matchingIDs(entries: entries, personalBestIDs: personalBestIDs)
    return results.filter { ids.contains($0.id) }
  }

  private var availableTags: [String] {
    Array(Set(results.flatMap(\.tags))).sorted {
      $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }
  }

  private var sortedFilteredResults: [TestResultRecord] {
    let recordsByID = Dictionary(uniqueKeysWithValues: filteredResults.map { ($0.id, $0) })
    return ResultHistorySortPolicy.sorted(
      filteredResults.map(ResultMetric.init(record:)), by: historySortField,
      direction: historySortDirection
    ).compactMap { recordsByID[$0.id] }
  }

  private var visibleResults: [TestResultRecord] {
    let count = ResultHistoryPagePolicy.visibleCount(
      requested: visibleResultLimit, total: sortedFilteredResults.count)
    return Array(sortedFilteredResults.prefix(count))
  }

  private var metrics: [ResultMetric] {
    filteredResults.map { ResultMetric(record: $0) }
  }

  private var allMetrics: [ResultMetric] {
    results.map { ResultMetric(record: $0) }
  }

  private var selectedHistoryMetric: ResultMetric? {
    selectedHistoryDate.flatMap { HistoryChartSelectionPolicy.nearestMetric(to: $0, in: metrics) }
  }

  private var selectedHistoryRecord: TestResultRecord? {
    guard let id = selectedHistoryMetric?.id else { return nil }
    return filteredResults.first { $0.id == id }
  }

  private var activity: [DailyActivity] {
    ActivityAggregation.daily(
      metrics: metrics, dayBoundaryOffsetHours: settings.streakDayBoundaryOffsetHours)
  }

  private var recentActivity: [ActivityBarPoint] {
    ActivityAggregation.recentDays(
      activity: activity, dayBoundaryOffsetHours: settings.streakDayBoundaryOffsetHours)
  }

  private var speedHistogram: [SpeedHistogramBucket] {
    SpeedHistogram.buckets(metrics: metrics, unit: settings.typingSpeedUnit)
  }

  private var filterSummaryItems: [ResultHistoryFilterSummaryItem] {
    ResultHistoryFilterSummaryPolicy.items(for: activeFilter)
  }

  private var personalBestIDs: Set<UUID> {
    Set(LocalPersonalBestTablePolicy.rows(results: results.compactMap(\.portableResult)).map(\.id))
  }

  var body: some View {
    NavigationStack {
      Group {
        if results.isEmpty {
          ContentUnavailableView(
            "还没有完成的测试", systemImage: "keyboard", description: Text("完成一次练习后，结果会保存在这台 Mac 上。"))
        } else {
          VStack(spacing: 0) {
            statistics
            AchievementStrip(
              achievements: TypebarAchievementPolicy.achievements(metrics: allMetrics)
            )
            .padding(.horizontal)
            .padding(.bottom, 8)
            ResultHistoryFilterSummaryView(items: filterSummaryItems)
              .padding(.horizontal)
              .padding(.bottom, 6)
            historyChart

            SpeedHistogramView(buckets: speedHistogram, unit: settings.typingSpeedUnit)
              .padding(.horizontal)
              .padding(.top, 8)

            ActivityBarChartView(
              points: recentActivity, measure: $activityChartMeasure,
              speedUnit: settings.typingSpeedUnit, startsAtZero: settings.startGraphsAtZero)
              .padding(.horizontal)
              .padding(.top, 8)

            ActivityHeatmapView(
              activity: activity, dayBoundaryOffsetHours: settings.streakDayBoundaryOffsetHours)
              .padding(.horizontal)
              .padding(.bottom, 10)

            List {
              Section("筛选") {
                HStack {
                  Button("全部", action: resetFilters)
                  Button("当前测试设置", action: applyCurrentSettingsFilter)
                  Spacer()
                  Text("显示 \(visibleResults.count) / \(filteredResults.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                HStack {
                  Picker("排序", selection: $historySortField) {
                    ForEach(ResultHistorySortField.allCases) { field in
                      Text(field.displayName).tag(field)
                    }
                  }
                  Picker("方向", selection: $historySortDirection) {
                    ForEach(ResultHistorySortDirection.allCases) { direction in
                      Text(direction.displayName).tag(direction)
                    }
                  }
                }
                if let csvExportStatus {
                  Text(csvExportStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                HStack {
                  TextField("筛选预设名称", text: $filterPresetName)
                  Button("保存筛选", action: saveFilterPreset)
                    .disabled(ResultFilterPresetPolicy.normalizedName(filterPresetName) == nil)
                }
                if !filterPresets.isEmpty {
                  ForEach(filterPresets) { preset in
                    HStack {
                      Button(preset.name) { applyFilterPreset(preset) }
                        .buttonStyle(.borderless)
                      Spacer()
                      Button(role: .destructive) {
                        modelContext.delete(preset)
                      } label: {
                        Image(systemName: "trash")
                      }
                      .buttonStyle(.borderless)
                      .accessibilityLabel("删除筛选预设 \(preset.name)")
                    }
                  }
                }
                Picker("时间范围", selection: $dateRangeFilter) {
                  ForEach(ResultHistoryDateRange.allCases, id: \.self) { range in
                    Text(range.displayName).tag(range)
                  }
                }
                DisclosureGroup(
                  "难度：\(ResultHistoryFilter.difficultySelectionSummary(difficultyFilter))"
                ) {
                  ForEach(Difficulty.allCases, id: \.self) { difficulty in
                    Toggle(difficulty.displayName, isOn: difficultyBinding(for: difficulty))
                      .toggleStyle(.checkbox)
                  }
                }
                Picker("标点", selection: $punctuationFilter) {
                  ForEach(ResultHistoryBinaryFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                  }
                }
                Picker("数字", selection: $numbersFilter) {
                  ForEach(ResultHistoryBinaryFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                  }
                }
                DisclosureGroup(
                  "模式：\(ResultHistoryFilter.modeSelectionSummary(modeFilter))"
                ) {
                  ForEach(TestMode.allCases, id: \.self) { mode in
                    Toggle(modeName(mode), isOn: modeBinding(for: mode))
                      .toggleStyle(.checkbox)
                  }
                }
                DisclosureGroup(
                  "引语长度：\(ResultHistoryFilter.quoteLengthSelectionSummary(quoteLengthFilter))"
                ) {
                  ForEach(QuoteLength.allCases.filter { $0 != .all }, id: \.self) { length in
                    Toggle(length.displayName, isOn: quoteLengthBinding(for: length))
                      .toggleStyle(.checkbox)
                  }
                }
                DisclosureGroup(
                  "时长：\(ResultHistoryTimeLimit.selectionSummary(timeLimitFilter))"
                ) {
                  ForEach(ResultHistoryTimeLimit.allCases, id: \.self) { limit in
                    Toggle(limit.displayName, isOn: timeLimitBinding(for: limit))
                      .toggleStyle(.checkbox)
                  }
                }
                DisclosureGroup(
                  "字数：\(ResultHistoryWordLimit.selectionSummary(wordLimitFilter))"
                ) {
                  ForEach(ResultHistoryWordLimit.allCases, id: \.self) { limit in
                    Toggle(limit.displayName, isOn: wordLimitBinding(for: limit))
                      .toggleStyle(.checkbox)
                  }
                }
                DisclosureGroup("修饰器：\(activeModifierFilter.selectionSummary)") {
                  Toggle("无修饰器", isOn: $includesNoModifierFilter)
                    .toggleStyle(.checkbox)
                  ForEach(TestModifier.allCases, id: \.self) { modifier in
                    Toggle(modifier.displayName, isOn: modifierBinding(for: modifier))
                      .toggleStyle(.checkbox)
                  }
                }
                DisclosureGroup(
                  "语言：\(ResultHistoryFilter.languageSelectionSummary(languageFilter))"
                ) {
                  ForEach(TypingLanguage.allCases, id: \.self) { language in
                    Toggle(language.displayName, isOn: languageBinding(for: language))
                      .toggleStyle(.checkbox)
                  }
                }
                if !availableTags.isEmpty {
                  DisclosureGroup("标签：\(selectedTagFilter.selectionSummary)") {
                    Toggle("无标签", isOn: noTagBinding)
                      .toggleStyle(.checkbox)
                    ForEach(availableTags, id: \.self) { tag in
                      Toggle(tag, isOn: tagBinding(for: tag))
                        .toggleStyle(.checkbox)
                    }
                  }
                }
                Picker("个人最佳", selection: $personalBestFilter) {
                  ForEach(ResultHistoryPersonalBestFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                  }
                }
              }
              if filteredResults.isEmpty {
                ContentUnavailableView(
                  "没有匹配的成绩", systemImage: "line.3.horizontal.decrease.circle",
                  description: Text("调整筛选条件以查看其他本地练习记录。"))
              }
              ForEach(visibleResults) { result in
                let rowSummary = ResultHistoryRowSummaryPolicy.summary(
                  configuration: result.configuration, characterStats: result.characterStats,
                  tags: result.tags)
                Button {
                  selectedResult = result
                } label: {
                  HStack(spacing: 16) {
                    Text("\(result.wpm)")
                      .font(.system(size: 30, weight: .bold, design: .rounded))
                      .frame(width: 56, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 3) {
                      Text("\(rowSummary.modeAndParameter) · \(result.accuracy)% 准确率")
                        .lineLimit(1)
                      Text(
                        result.finishedAt, format: .dateTime.year().month().day().hour().minute()
                      )
                      .font(.caption)
                      .foregroundStyle(.secondary)
                      Text(rowSummary.metadata)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(rowSummary.metadata)
                        .accessibilityLabel(rowSummary.accessibilityMetadata)
                    }
                    if personalBestIDs.contains(result.id) {
                      Label("个人最佳", systemImage: "trophy.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text("raw \(result.rawWpm) · \(consistencyText(for: result))% 稳定")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
                .buttonStyle(.plain)
              }
              .onDelete(perform: delete)
              if visibleResults.count < sortedFilteredResults.count {
                Button("再显示 \(min(ResultHistoryPagePolicy.pageSize, sortedFilteredResults.count - visibleResults.count)) 条") {
                  visibleResultLimit = ResultHistoryPagePolicy.nextLimit(
                    current: visibleResultLimit, total: sortedFilteredResults.count)
                }
                .frame(maxWidth: .infinity)
              }
            }
          }
        }
      }
      .navigationTitle("练习历史")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("完成") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("个人最佳表…") { showingPersonalBestTable = true }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("导出 CSV…", action: exportFilteredResultsCSV)
            .disabled(filteredResults.isEmpty)
        }
      }
    }
    .frame(minWidth: 520, minHeight: 360)
    .sheet(item: $selectedResult) { result in
      ResultDetailView(
        result: result, modeName: modeName(result.configuration?.mode),
        isPersonalBest: personalBestIDs.contains(result.id),
        typingSpeedUnit: settings.typingSpeedUnit, settings: settings)
    }
    .sheet(isPresented: $showingPersonalBestTable) {
      LocalPersonalBestTableView(speedUnit: settings.typingSpeedUnit)
    }
    .onChange(of: activeFilter) {
      visibleResultLimit = ResultHistoryPagePolicy.pageSize
      selectedHistoryDate = nil
    }
    .onChange(of: historySortField) { visibleResultLimit = ResultHistoryPagePolicy.pageSize }
    .onChange(of: historySortDirection) { visibleResultLimit = ResultHistoryPagePolicy.pageSize }
  }

  private var historyChartPoints: [HistoryChartPoint] {
    let speeds = metrics.map { Double($0.wpm) }
    let accuracies = metrics.map { Double($0.accuracy) }
    let speedAverage10 = HistoryChartPolicy.movingAverage(values: speeds, windowSize: 10)
    let speedAverage100 = HistoryChartPolicy.movingAverage(values: speeds, windowSize: 100)
    let accuracyAverage10 = HistoryChartPolicy.movingAverage(values: accuracies, windowSize: 10)
    let accuracyAverage100 = HistoryChartPolicy.movingAverage(values: accuracies, windowSize: 100)
    let personalBestSpeed = HistoryChartPolicy.personalBestEnvelope(values: speeds)
    return metrics.indices.map { index in
      .init(
        metric: metrics[index], speedAverage10: speedAverage10[index],
        speedAverage100: speedAverage100[index], accuracyAverage10: accuracyAverage10[index],
        accuracyAverage100: accuracyAverage100[index], personalBestSpeed: personalBestSpeed[index])
    }
  }

  private var historyChart: some View {
    let visibility = settings.historyChartVisibility
    return VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("历史趋势", systemImage: "chart.xyaxis.line")
          .font(.caption.weight(.medium))
        Spacer()
      }
      HStack(spacing: 6) {
        historyChartToggle("速度", systemImage: "gauge", isEnabled: visibility.speed) {
          settings.mutateHistoryChartVisibility { $0.speed.toggle() }
        }
        historyChartToggle("准确率", systemImage: "target", isEnabled: visibility.accuracy) {
          settings.mutateHistoryChartVisibility { $0.accuracy.toggle() }
        }
        historyChartToggle("均值 10", systemImage: "chart.line.uptrend.xyaxis", isEnabled: visibility.average10) {
          settings.mutateHistoryChartVisibility { $0.average10.toggle() }
        }
        historyChartToggle("均值 100", systemImage: "chart.line.uptrend.xyaxis", isEnabled: visibility.average100) {
          settings.mutateHistoryChartVisibility { $0.average100.toggle() }
        }
      }
      if !visibility.speed && !visibility.accuracy {
        ContentUnavailableView(
          "历史曲线已隐藏", systemImage: "chart.xyaxis.line",
          description: Text("重新开启速度或准确率即可显示本机历史数据。"))
          .frame(height: 120)
      } else {
        if visibility.speed { speedHistoryChart }
        if visibility.accuracy { accuracyHistoryChart }
      }
      if let metric = selectedHistoryMetric, let result = selectedHistoryRecord {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
              Text(metric.finishedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.caption.weight(.medium))
              if personalBestIDs.contains(result.id) {
                Label("个人最佳", systemImage: "trophy.fill")
                  .font(.caption2)
                  .foregroundStyle(.orange)
              }
            }
            Text(
              "\(settings.typingSpeedUnit.formatted(wpm: metric.wpm)) \(settings.typingSpeedUnit.displayName) · Raw \(settings.typingSpeedUnit.formatted(wpm: metric.rawWpm)) · \(metric.accuracy)% 准确率 · \(formattedConsistency(metric.consistency))% 稳定度"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(historyConfigurationText(result.configuration))
            .font(.caption2)
            .foregroundStyle(.secondary)
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 6) {
            Button("查看成绩") { selectedResult = result }
            Button("清除选择", systemImage: "xmark.circle") { selectedHistoryDate = nil }
              .labelStyle(.iconOnly)
          }
        }
        .padding(8)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
      }
      if let trend = HistoryChartPolicy.speedChangePerTypingHour(metrics: metrics) {
        let converted = settings.typingSpeedUnit.converted(wpm: trend)
        let sign = converted >= 0 ? "+" : ""
        Text(
          "每小时练习速度变化：\(sign)\(String(format: "%.2f", converted)) \(settings.typingSpeedUnit.displayName)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal)
    .padding(.bottom, 8)
  }

  private var speedHistoryChart: some View {
    let visibility = settings.historyChartVisibility
    return Chart(historyChartPoints) { point in
      if selectedHistoryMetric?.id == point.id {
        RuleMark(x: .value("所选成绩", point.metric.finishedAt))
          .foregroundStyle(.secondary.opacity(0.6))
          .lineStyle(.init(lineWidth: 1, dash: [3, 2]))
          .accessibilityHidden(true)
      }
      LineMark(
        x: .value("日期", point.metric.finishedAt),
        y: .value(settings.typingSpeedUnit.displayName, settings.typingSpeedUnit.converted(wpm: point.personalBestSpeed)))
        .foregroundStyle(.secondary.opacity(0.45))
        .lineStyle(.init(lineWidth: 1, dash: [4, 3]))
      if visibility.average100 {
        LineMark(
          x: .value("日期", point.metric.finishedAt),
          y: .value(settings.typingSpeedUnit.displayName, settings.typingSpeedUnit.converted(wpm: point.speedAverage100)))
          .foregroundStyle(.tint.opacity(0.55))
          .lineStyle(.init(lineWidth: 1.5, dash: [2, 3]))
      }
      if visibility.average10 {
        LineMark(
          x: .value("日期", point.metric.finishedAt),
          y: .value(settings.typingSpeedUnit.displayName, settings.typingSpeedUnit.converted(wpm: point.speedAverage10)))
          .foregroundStyle(.tint.opacity(0.78))
          .lineStyle(.init(lineWidth: 1.5, dash: [6, 3]))
      }
      LineMark(
        x: .value("日期", point.metric.finishedAt),
        y: .value(settings.typingSpeedUnit.displayName, settings.typingSpeedUnit.converted(wpm: point.metric.wpm)))
        .foregroundStyle(.tint)
      PointMark(
        x: .value("日期", point.metric.finishedAt),
        y: .value(settings.typingSpeedUnit.displayName, settings.typingSpeedUnit.converted(wpm: point.metric.wpm)))
        .foregroundStyle(.tint)
    }
    .chartYScale(domain: .automatic(includesZero: settings.startGraphsAtZero))
    .chartXSelection(value: $selectedHistoryDate)
    .chartYAxisLabel(settings.typingSpeedUnit.displayName)
    .frame(height: 120)
    .accessibilityLabel("本机速度历史趋势")
    .accessibilityHint("在图表中拖动以选择最近的成绩")
  }

  private var accuracyHistoryChart: some View {
    let visibility = settings.historyChartVisibility
    return Chart(historyChartPoints) { point in
      if selectedHistoryMetric?.id == point.id {
        RuleMark(x: .value("所选成绩", point.metric.finishedAt))
          .foregroundStyle(.secondary.opacity(0.6))
          .lineStyle(.init(lineWidth: 1, dash: [3, 2]))
          .accessibilityHidden(true)
      }
      if visibility.average100 {
        LineMark(
          x: .value("日期", point.metric.finishedAt), y: .value("准确率", point.accuracyAverage100))
          .foregroundStyle(.secondary.opacity(0.55))
          .lineStyle(.init(lineWidth: 1.5, dash: [2, 3]))
      }
      if visibility.average10 {
        LineMark(
          x: .value("日期", point.metric.finishedAt), y: .value("准确率", point.accuracyAverage10))
          .foregroundStyle(.secondary.opacity(0.8))
          .lineStyle(.init(lineWidth: 1.5, dash: [6, 3]))
      }
      LineMark(
        x: .value("日期", point.metric.finishedAt), y: .value("准确率", point.metric.accuracy))
        .foregroundStyle(.secondary)
      PointMark(
        x: .value("日期", point.metric.finishedAt), y: .value("准确率", point.metric.accuracy))
        .foregroundStyle(.secondary)
        .symbol(.triangle)
    }
    .chartYScale(domain: .automatic(includesZero: settings.startGraphsAtZero))
    .chartXSelection(value: $selectedHistoryDate)
    .chartYAxisLabel("准确率 (%)")
    .frame(height: 120)
    .accessibilityLabel("本机准确率历史趋势")
    .accessibilityHint("在图表中拖动以选择最近的成绩")
  }

  private func historyChartToggle(
    _ title: String, systemImage: String, isEnabled: Bool, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.caption)
    }
    .buttonStyle(.bordered)
    .tint(isEnabled ? .accentColor : .secondary)
    .accessibilityValue(isEnabled ? "显示" : "隐藏")
  }

  private var statistics: some View {
    let summary = ResultStatistics(metrics: metrics)
    let streak = ActivityAggregation.currentStreak(
      activity: activity, dayBoundaryOffsetHours: settings.streakDayBoundaryOffsetHours)
    return LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10
    ) {
      statistic("估算词数", "\(summary.estimatedWordsTyped)")
      statistic("开始", "\(summary.startedTests)")
      statistic("完成", "\(summary.completedTests)（\(summary.completionPercentage)%）")
      statistic(
        "每次完成重开",
        summary.restartsPerCompletedTest.formatted(.number.precision(.fractionLength(1))))
      statistic("键入时长", formattedTypingDuration(summary.totalTypingSeconds))
      statistic("连续", "\(streak) 天")
      statistic(
        "平均 \(settings.typingSpeedUnit.displayName)",
        settings.typingSpeedUnit.formatted(wpm: summary.averageWPM))
      statistic(
        "最高 \(settings.typingSpeedUnit.displayName)",
        settings.typingSpeedUnit.formatted(wpm: summary.bestWPM))
      statistic(
        "近 10 \(settings.typingSpeedUnit.displayName)",
        settings.typingSpeedUnit.formatted(wpm: summary.averageWPMLast10))
      statistic("平均 Raw", settings.typingSpeedUnit.formatted(wpm: summary.averageRawWPM))
      statistic("最高 Raw", settings.typingSpeedUnit.formatted(wpm: summary.bestRawWPM))
      statistic("近 10 Raw", settings.typingSpeedUnit.formatted(wpm: summary.averageRawWPMLast10))
      statistic("平均准确率", "\(summary.averageAccuracy)%")
      statistic("最高准确率", "\(summary.bestAccuracy)%")
      statistic("近 10 准确率", "\(summary.averageAccuracyLast10)%")
      statistic("最高稳定度", "\(formattedConsistency(summary.highestConsistency))%")
      statistic("平均稳定度", "\(formattedConsistency(summary.averageConsistency))%")
      statistic("近 10 稳定度", "\(formattedConsistency(summary.averageConsistencyLast10))%")
    }
    .padding()
  }

  private func consistencyText(for result: TestResultRecord) -> String {
    formattedConsistency(ResultMetric(record: result).consistency)
  }

  private func formattedConsistency(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
  }

  private func historyConfigurationText(_ configuration: TestConfiguration?) -> String {
    guard let configuration else { return "未知配置" }
    var pieces = [modeName(configuration.mode)]
    if configuration.mode == .time, let duration = configuration.duration, duration.isFinite {
      pieces.append(
        "\(max(0, duration).formatted(.number.precision(.fractionLength(0)))) 秒")
    } else if configuration.mode == .words, let wordLimit = configuration.wordLimit {
      pieces.append("\(wordLimit) 词")
    }
    pieces.append(configuration.language.displayName)
    pieces.append(configuration.difficulty.displayName)
    if configuration.contentOptions.includePunctuation { pieces.append("标点") }
    if configuration.contentOptions.includeNumbers { pieces.append("数字") }
    return pieces.joined(separator: " · ")
  }

  private func formattedTypingDuration(_ value: TimeInterval) -> String {
    let seconds = max(0, Int(value.rounded()))
    let hours = seconds / 3_600
    let minutes = seconds % 3_600 / 60
    if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
    if minutes > 0 { return "\(minutes) 分 \(seconds % 60) 秒" }
    return "\(seconds) 秒"
  }

  private func statistic(_ title: String, _ value: String) -> some View {
    VStack(spacing: 2) {
      Text(value).font(.headline)
      Text(title).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  private func delete(at offsets: IndexSet) {
    let deletedIDs = Set(offsets.map { visibleResults[$0].id })
    if let selectedID = selectedHistoryMetric?.id, deletedIDs.contains(selectedID) {
      selectedHistoryDate = nil
    }
    for index in offsets { modelContext.delete(visibleResults[index]) }
  }

  private func exportFilteredResultsCSV() {
    let portableResults = sortedFilteredResults.compactMap(\.portableResult)
    guard !portableResults.isEmpty else {
      csvExportStatus = "没有可导出的本机成绩。"
      return
    }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = ResultCSVExport.filename(for: .now)
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try ResultCSVExport.data(for: portableResults).write(to: url, options: .atomic)
      csvExportStatus = "已导出 \(portableResults.count) 条本机成绩；不含提示或输入回放。"
    } catch {
      csvExportStatus = "无法保存 CSV 文件。"
    }
  }

  private var activeFilter: ResultHistoryFilter {
    .init(
      modes: modeFilter, languages: languageFilter, tagFilter: selectedTagFilter,
      personalBestFilter: personalBestFilter, difficulties: difficultyFilter, dateRange: dateRangeFilter,
      punctuation: punctuationFilter, numbers: numbersFilter, quoteLengths: quoteLengthFilter,
      timeLimits: timeLimitFilter, wordLimits: wordLimitFilter, modifierFilter: activeModifierFilter
    )
  }

  private var activeModifierFilter: ResultHistoryModifierFilter {
    .init(includesNoModifiers: includesNoModifierFilter, modifiers: modifierFilter)
  }

  private func saveFilterPreset() {
    guard let preset = ResultFilterPresetRecord(name: filterPresetName, filter: activeFilter) else {
      return
    }
    modelContext.insert(preset)
    filterPresetName = ""
  }

  private func applyFilterPreset(_ preset: ResultFilterPresetRecord) {
    guard let filter = preset.filter else { return }
    apply(filter)
  }

  private func resetFilters() {
    apply(.init())
  }

  private func applyCurrentSettingsFilter() {
    apply(.currentSettings(currentConfiguration, activeTags: settings.activeResultTags))
  }

  private func apply(_ filter: ResultHistoryFilter) {
    modeFilter = filter.modeSelections
    languageFilter = filter.languageSelections
    selectedTagFilter = filter.effectiveTagFilter
    difficultyFilter = filter.difficultySelections
    personalBestFilter = filter.effectivePersonalBestFilter
    dateRangeFilter = filter.dateRange
    punctuationFilter = filter.punctuation
    numbersFilter = filter.numbers
    quoteLengthFilter = filter.quoteLengthSelections
    timeLimitFilter = filter.timeLimits
    wordLimitFilter = filter.wordLimits
    includesNoModifierFilter = filter.modifierFilter.includesNoModifiers
    modifierFilter = filter.modifierFilter.modifiers
  }

  private func timeLimitBinding(for limit: ResultHistoryTimeLimit) -> Binding<Bool> {
    Binding(
      get: { timeLimitFilter.contains(limit) },
      set: { selected in
        if selected { timeLimitFilter.insert(limit) } else { timeLimitFilter.remove(limit) }
      })
  }

  private func modeBinding(for mode: TestMode) -> Binding<Bool> {
    Binding(
      get: { modeFilter.contains(mode) },
      set: { selected in
        if selected { modeFilter.insert(mode) } else { modeFilter.remove(mode) }
      })
  }

  private func difficultyBinding(for difficulty: Difficulty) -> Binding<Bool> {
    Binding(
      get: { difficultyFilter.contains(difficulty) },
      set: { selected in
        if selected { difficultyFilter.insert(difficulty) } else { difficultyFilter.remove(difficulty) }
      })
  }

  private func quoteLengthBinding(for length: QuoteLength) -> Binding<Bool> {
    Binding(
      get: { quoteLengthFilter.contains(length) },
      set: { selected in
        if selected { quoteLengthFilter.insert(length) } else { quoteLengthFilter.remove(length) }
      })
  }

  private func wordLimitBinding(for limit: ResultHistoryWordLimit) -> Binding<Bool> {
    Binding(
      get: { wordLimitFilter.contains(limit) },
      set: { selected in
        if selected { wordLimitFilter.insert(limit) } else { wordLimitFilter.remove(limit) }
      })
  }

  private func modifierBinding(for modifier: TestModifier) -> Binding<Bool> {
    Binding(
      get: { modifierFilter.contains(modifier) },
      set: { selected in
        if selected { modifierFilter.insert(modifier) } else { modifierFilter.remove(modifier) }
      })
  }

  private func languageBinding(for language: TypingLanguage) -> Binding<Bool> {
    Binding(
      get: { languageFilter.contains(language) },
      set: { selected in
        if selected { languageFilter.insert(language) } else { languageFilter.remove(language) }
      })
  }

  private var noTagBinding: Binding<Bool> {
    Binding(
      get: { selectedTagFilter.isNoTagsSelected },
      set: { selected in
        selectedTagFilter.setNoTagsSelected(selected, availableTags: Set(availableTags))
      })
  }

  private func tagBinding(for tag: String) -> Binding<Bool> {
    Binding(
      get: { selectedTagFilter.isTagSelected(tag) },
      set: { selected in
        selectedTagFilter.setTag(tag, selected: selected, availableTags: Set(availableTags))
      })
  }

  private func modeName(_ mode: TestMode?) -> String {
    switch mode {
    case .time: "时间"
    case .words: "字数"
    case .quote: "引语"
    case .zen: "禅"
    case .custom: "自定义"
    case nil: "未知"
    }
  }
}

private struct ResultHistoryFilterSummaryView: View {
  let items: [ResultHistoryFilterSummaryItem]

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Label("当前筛选", systemImage: "line.3.horizontal.decrease.circle")
        .font(.caption.weight(.medium))
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(items) { item in
            Text(item.label)
              .font(.caption2)
              .lineLimit(1)
              .padding(.horizontal, 8)
              .padding(.vertical, 5)
              .background(.secondary.opacity(0.09), in: Capsule())
              .accessibilityLabel(item.label)
          }
        }
      }
    }
  }
}

private struct AchievementStrip: View {
  let achievements: [TypebarAchievement]

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Label("本机成就", systemImage: "medal")
          .font(.caption.weight(.semibold))
        Spacer()
        Text("\(achievements.filter(\.isUnlocked).count)/\(achievements.count)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(achievements) { achievement in
            VStack(alignment: .leading, spacing: 3) {
              Label(achievement.title, systemImage: achievement.systemImage)
                .font(.caption.weight(.medium))
              Text(achievement.detail)
                .font(.caption2)
                .lineLimit(1)
              Text(achievement.progress)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .frame(width: 142, alignment: .leading)
            .padding(9)
            .foregroundStyle(achievement.isUnlocked ? Color.primary : Color.secondary)
            .background(
              achievement.isUnlocked
                ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
              in: RoundedRectangle(cornerRadius: 10)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
              "\(achievement.title)，\(achievement.detail)，进度 \(achievement.progress)，\(achievement.isUnlocked ? "已获得" : "未获得")"
            )
          }
        }
      }
      Text("成就只由这台 Mac 已完成的练习导出，不上传或替代服务器 XP。")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }
}

private struct SpeedHistogramView: View {
  let buckets: [SpeedHistogramBucket]
  let unit: TypingSpeedUnit

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text("速度分布").font(.caption.weight(.medium))
        Spacer()
        Text("每档 \(buckets.first?.bucketSizeLabel ?? SpeedHistogram.formattedBound(unit.histogramBucketSize)) \(unit.displayName)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Chart(buckets) { bucket in
        BarMark(
          x: .value("速度区间", bucket.label),
          y: .value("完成次数", bucket.count)
        )
        .foregroundStyle(Color.accentColor.gradient)
        .accessibilityLabel("\(bucket.label) \(unit.displayName)")
        .accessibilityValue("\(bucket.count) 次完成")
      }
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 6)) { _ in
          AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
          AxisValueLabel()
        }
      }
      .chartYScale(domain: .automatic(includesZero: true))
      .frame(height: 110)
    }
  }
}

private struct ActivityBarChartView: View {
  let points: [ActivityBarPoint]
  @Binding var measure: ResultsHistoryView.ActivityChartMeasure
  let speedUnit: TypingSpeedUnit
  let startsAtZero: Bool
  @State private var selectedDate: Date?

  private var selectedPoint: ActivityBarPoint? {
    selectedDate.flatMap { ActivityBarSelectionPolicy.nearestPoint(to: $0, in: points) }
  }

  private var yTitle: String {
    switch measure {
    case .averageSpeed, .highestSpeed: speedUnit.displayName
    default: measure.title
    }
  }

  private var typingMinutesTrend: [ActivityTypingMinutesTrendPoint] {
    measure == .typingMinutes ? ActivityTypingMinutesTrendPolicy.points(for: points) : []
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text("近 28 日练习").font(.caption.weight(.medium))
        Spacer()
        Picker("柱状图指标", selection: $measure) {
          ForEach(ResultsHistoryView.ActivityChartMeasure.allCases) { measure in
            Text(measure.title).tag(measure)
          }
        }
        .pickerStyle(.menu)
        .frame(width: 180)
      }
      Chart {
        ForEach(points) { point in
          if let value = value(for: point) {
            BarMark(
              x: .value("日期", point.day, unit: .day),
              y: .value(yTitle, value)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .accessibilityLabel(point.day.formatted(date: .abbreviated, time: .omitted))
            .accessibilityValue(accessibilityValue(for: point))
          }
        }
        ForEach(typingMinutesTrend) { point in
          LineMark(
            x: .value("日期", point.day, unit: .day),
            y: .value("练习分钟趋势", point.minutes)
          )
          .foregroundStyle(.secondary)
          .lineStyle(.init(lineWidth: 2, dash: [4, 3]))
          .accessibilityLabel("练习分钟趋势")
          .accessibilityValue(
            "\(point.day.formatted(date: .abbreviated, time: .omitted))，\(point.minutes.formatted(.number.precision(.fractionLength(0...2)))) 分钟")
        }
        if let selectedPoint {
          RuleMark(x: .value("所选日期", selectedPoint.day, unit: .day))
            .foregroundStyle(.secondary)
            .lineStyle(.init(lineWidth: 1, dash: [3, 3]))
        }
      }
      .chartXAxis {
        AxisMarks(values: .stride(by: .weekOfYear)) { _ in
          AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
          AxisValueLabel(format: .dateTime.month().day())
        }
      }
      .chartYScale(domain: .automatic(includesZero: includesZero))
      .chartXSelection(value: $selectedDate)
      .frame(height: 110)
      if let selectedPoint {
        ActivityDayDetailView(point: selectedPoint, speedUnit: speedUnit) {
          selectedDate = nil
        }
      } else {
        Text("点按或拖动图表，查看某一天的完整指标")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var includesZero: Bool {
    switch measure {
    case .completedTests, .typingMinutes, .restartsPerCompletedTest: true
    case .averageSpeed, .highestSpeed, .averageAccuracy, .averageConsistency: startsAtZero
    }
  }

  private func value(for point: ActivityBarPoint) -> Double? {
    switch measure {
    case .completedTests: Double(point.completedTests)
    case .typingMinutes: point.typingSeconds / 60
    case .averageSpeed:
      point.completedTests > 0 ? speedUnit.converted(wpm: point.averageWPM) : nil
    case .highestSpeed:
      point.completedTests > 0 ? speedUnit.converted(wpm: Double(point.highestWPM)) : nil
    case .averageAccuracy:
      point.completedTests > 0 ? point.averageAccuracy : nil
    case .averageConsistency:
      point.completedTests > 0 ? point.averageConsistency : nil
    case .restartsPerCompletedTest: point.restartsPerCompletedTest
    }
  }

  private func accessibilityValue(for point: ActivityBarPoint) -> String {
    switch measure {
    case .completedTests: "\(point.completedTests) 次完成"
    case .typingMinutes: "\(Int((point.typingSeconds / 60).rounded())) 分钟练习"
    case .averageSpeed:
      "平均 \(formattedSpeed(point.averageWPM)) \(speedUnit.displayName)"
    case .highestSpeed:
      "最高 \(speedUnit.formatted(wpm: point.highestWPM)) \(speedUnit.displayName)"
    case .averageAccuracy:
      "\(point.averageAccuracy.formatted(.number.precision(.fractionLength(0...2))))% 平均准确率"
    case .averageConsistency:
      "\(point.averageConsistency.formatted(.number.precision(.fractionLength(0...2))))% 平均稳定度"
    case .restartsPerCompletedTest:
      "每次完成重开 \(point.restartsPerCompletedTest.formatted(.number.precision(.fractionLength(1)))) 次"
    }
  }

  private func formattedSpeed(_ wpm: Double) -> String {
    speedUnit.converted(wpm: wpm).formatted(
      .number.precision(.fractionLength(0...2)))
  }
}

private struct ActivityDayDetailView: View {
  let point: ActivityBarPoint
  let speedUnit: TypingSpeedUnit
  let clearSelection: () -> Void

  private let columns = [GridItem(.adaptive(minimum: 104), alignment: .leading)]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(point.day.formatted(date: .complete, time: .omitted))
          .font(.caption.weight(.medium))
        Spacer()
        Button("清除选择", systemImage: "xmark.circle", action: clearSelection)
          .labelStyle(.iconOnly)
          .buttonStyle(.plain)
          .help("清除活动日期选择")
      }
      LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
        metric("练习时间", durationText)
        metric("完成次数", "\(point.completedTests)")
        metric("重开 / 完成", decimal(point.restartsPerCompletedTest, digits: 1...2))
        metric("最高速度", optionalSpeed(Double(point.highestWPM)))
        metric("平均速度", optionalSpeed(point.averageWPM))
        metric("平均准确率", optionalPercent(point.averageAccuracy))
        metric("平均稳定度", optionalPercent(point.averageConsistency))
      }
    }
    .padding(8)
    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
  }

  private func metric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(title).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.caption.monospacedDigit())
    }
    .accessibilityElement(children: .combine)
  }

  private var durationText: String {
    let seconds = max(0, Int(point.typingSeconds.rounded()))
    return seconds >= 60 ? "\(seconds / 60) 分 \(seconds % 60) 秒" : "\(seconds) 秒"
  }

  private func optionalSpeed(_ wpm: Double) -> String {
    guard point.completedTests > 0 else { return "—" }
    return "\(speedUnit.converted(wpm: wpm).formatted(.number.precision(.fractionLength(0...2)))) \(speedUnit.displayName)"
  }

  private func optionalPercent(_ value: Double) -> String {
    guard point.completedTests > 0 else { return "—" }
    return "\(decimal(value, digits: 0...2))%"
  }

  private func decimal(_ value: Double, digits: ClosedRange<Int>) -> String {
    value.formatted(.number.precision(.fractionLength(digits)))
  }
}

private struct ActivityHeatmapView: View {
  let activity: [DailyActivity]
  let dayBoundaryOffsetHours: Double

  private var cells: [ActivityHeatmapCell] {
    ActivityHeatmap.cells(activity: activity, dayBoundaryOffsetHours: dayBoundaryOffsetHours)
  }

  private let rows = Array(repeating: GridItem(.fixed(11), spacing: 3), count: 7)

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("近 12 周活动").font(.caption.weight(.medium))
        Spacer()
        Text("深色代表更多完成次数").font(.caption2).foregroundStyle(.secondary)
      }
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHGrid(rows: rows, spacing: 3) {
          ForEach(cells) { cell in
            RoundedRectangle(cornerRadius: 2)
              .fill(Color.accentColor.opacity(opacity(for: cell.intensity)))
              .frame(width: 11, height: 11)
              .accessibilityLabel(cell.day.formatted(date: .abbreviated, time: .omitted))
              .accessibilityValue("\(cell.completedTests) 次完成")
          }
        }
        .frame(height: 95)
      }
    }
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
}

private struct ResultTagEditor: View {
  @Environment(\.modelContext) private var modelContext
  let result: TestResultRecord
  @State private var newTag = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("标签").font(.headline)
      if !result.tags.isEmpty {
        FlowLayout(spacing: 8) {
          ForEach(result.tags, id: \.self) { tag in
            Button {
              result.removeTag(tag)
              saveTags()
            } label: {
              Label(tag, systemImage: "xmark")
                .font(.caption)
            }
            .buttonStyle(.bordered)
          }
        }
      }
      HStack {
        TextField("添加标签", text: $newTag)
          .onSubmit(addTag)
        Button("添加", action: addTag)
          .disabled(
            newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || result.tags.count >= ResultTagPolicy.maximumCount)
      }
      Text(
        "最多 \(ResultTagPolicy.maximumCount) 个标签，每个不超过 \(ResultTagPolicy.maximumLength) 个字符。点按标签可移除。"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private func addTag() {
    result.addTag(newTag)
    newTag = ""
    saveTags()
  }

  private func saveTags() {
    try? modelContext.save()
  }
}

private struct ResultDetailView: View {
  @Environment(\.dismiss) private var dismiss
  let result: TestResultRecord
  let modeName: String
  let isPersonalBest: Bool
  let typingSpeedUnit: TypingSpeedUnit
  let settings: AppSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(result.wpm)")
          .font(.system(size: 64, weight: .bold, design: .rounded))
        Text("WPM").foregroundStyle(.secondary)
        if isPersonalBest {
          Label("个人最佳", systemImage: "trophy.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
        }
      }
      Text(result.finishedAt, format: .dateTime.year().month().day().hour().minute())
        .foregroundStyle(.secondary)
      Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 14) {
        GridRow {
          Text("模式")
          Text(modeName)
        }
        if let configuration = result.configuration {
          GridRow {
            Text("语言")
            Text(configuration.language.displayName)
          }
          GridRow {
            Text("难度")
            Text(configuration.difficulty.displayName)
          }
          if let duration = configuration.duration {
            GridRow {
              Text("设定时长")
              Text("\(Int(duration)) 秒")
            }
          }
          if let wordLimit = configuration.wordLimit {
            GridRow {
              Text("设定字数")
              Text("\(wordLimit) 词")
            }
          }
          if !configuration.modifiers.isEmpty {
            GridRow {
              Text("修饰器")
              Text(configuration.modifiers.map(\.displayName).joined(separator: "、"))
            }
          }
        }
        if let quoteSource = result.quoteSource {
          GridRow {
            Text("引语来源")
            Text(quoteSource.displayText)
          }
        }
        GridRow {
          Text("准确率")
          Text("\(result.accuracy)%")
        }
        GridRow {
          Text("Raw WPM")
          Text("\(result.rawWpm)")
        }
        GridRow {
          Text("错误")
          Text("\(result.errorCount)")
        }
        GridRow {
          Text("正确字符")
          Text("\(result.correctCharacterCount)")
        }
        GridRow {
          Text("字符（匹配/错位/额外/跳过）")
          Text(characterStatsText)
        }
        GridRow {
          Text("总用时")
          Text("\(Int(result.finishedAt.timeIntervalSince(result.startedAt))) 秒")
        }
        GridRow {
          Text("稳定度 / 按键稳定度")
          Text("\(consistencyText(consistency.typing))% / \(consistencyText(consistency.key))%")
        }
        if result.afkDuration > 0 {
          GridRow {
            Text("闲置 / 有效键入")
            Text(
              "\(Int(result.afkDuration)) 秒（\(result.afkPercentage.formatted(.number.precision(.fractionLength(0...2))))%） / \(Int(result.engagedDuration)) 秒"
            )
          }
        }
        if let keyDurationStats = result.portableResult?.keyDurationStats {
          GridRow {
            Text("按键时长（平均 / 波动）")
            Text(
              "\(keyDurationText(keyDurationStats.averageMilliseconds)) / \(keyDurationText(keyDurationStats.standardDeviationMilliseconds)) · \(keyDurationStats.sampleCount) 次"
            )
          }
        }
        if let keySpacingStats = result.portableResult?.keySpacingStats {
          GridRow {
            Text("按键间隔（平均 / 波动）")
            Text(
              "\(keyDurationText(keySpacingStats.averageMilliseconds)) / \(keyDurationText(keySpacingStats.standardDeviationMilliseconds)) · \(keySpacingStats.sampleCount) 次"
            )
          }
        }
        if let portableResult = result.portableResult,
          portableResult.keyDurationStats != nil || portableResult.keySpacingStats != nil
        {
          GridRow {
            Text("按键重叠 / 占比")
            Text(
              "\(keyDurationText(portableResult.keyOverlapDuration * 1_000)) / \(keyOverlapPercentageText(portableResult))"
            )
          }
        }
      }
      if !result.prompt.isEmpty, !result.replayEvents.isEmpty {
        ReplayTimelineView(
          prompt: result.prompt, events: result.replayEvents, speedUnit: typingSpeedUnit,
          soundConfiguration: .init(settings: settings))
      }
      ResultTagEditor(result: result)
      Spacer()
      HStack {
        Spacer()
        Button("完成") { dismiss() }
      }
    }
    .padding(32)
    .frame(width: 460, height: 620)
  }

  private var consistency: ResultConsistency {
    ResultConsistencyPolicy.metrics(
      events: result.replayEvents,
      duration: result.finishedAt.timeIntervalSince(result.startedAt)
    )
  }

  private func consistencyText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
  }

  private var characterStatsText: String {
    let stats = result.characterStats
    return "\(stats.matched)/\(stats.incorrect)/\(stats.extra)/\(stats.missed)"
  }

  private func keyDurationText(_ milliseconds: Double) -> String {
    "\(milliseconds.formatted(.number.precision(.fractionLength(0...1)))) ms"
  }

  private func keyOverlapPercentageText(_ result: CompletedTestResult) -> String {
    guard result.elapsedDuration > 0 else { return "0%" }
    let percentage = result.keyOverlapDuration / result.elapsedDuration * 100
    return "\(percentage.formatted(.number.precision(.fractionLength(0...2))))%"
  }

}

private struct FlowLayout: Layout {
  let spacing: CGFloat

  init(spacing: CGFloat) {
    self.spacing = spacing
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 0
    let rows = makeRows(subviews: subviews, width: width)
    let height =
      rows.reduce(CGFloat.zero) { $0 + $1.height } + max(0, CGFloat(rows.count - 1) * spacing)
    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for row in makeRows(subviews: subviews, width: bounds.width) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private func makeRows(subviews: Subviews, width: CGFloat) -> [(indices: [Int], height: CGFloat)] {
    guard width > 0 else { return [] }
    var rows: [(indices: [Int], height: CGFloat)] = []
    var indices: [Int] = []
    var rowWidth: CGFloat = 0
    var rowHeight: CGFloat = 0

    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let nextWidth = indices.isEmpty ? size.width : rowWidth + spacing + size.width
      if !indices.isEmpty, nextWidth > width {
        rows.append((indices, rowHeight))
        indices = []
        rowWidth = 0
        rowHeight = 0
      }
      indices.append(index)
      rowWidth = indices.count == 1 ? size.width : rowWidth + spacing + size.width
      rowHeight = max(rowHeight, size.height)
    }
    if !indices.isEmpty { rows.append((indices, rowHeight)) }
    return rows
  }
}
