import AppKit
import Charts
import QuartzCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@main
struct TypebarApp: App {
  @NSApplicationDelegateAdaptor(TypebarApplicationDelegate.self) private var applicationDelegate
  @State private var settings = AppSettings()
  @State private var account = AccountSession()
  @State private var accountStartup = AppAccountStartup()
  @State private var announcements = RemoteAnnouncementCenter()
  @State private var hotkey = GlobalHotkeyMonitor()
  @State private var systemKeyboardGuide = SystemKeyboardGuideMonitor()
  @State private var systemAppearance = SystemAppearanceMonitor()
  @State private var network = NetworkConnectivityMonitor()

  var body: some Scene {
    WindowGroup("Typebar") {
      dataStoreContent
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }
    .windowResizability(.contentMinSize)
    .commands {
      TypebarAboutCommands(navigationLocked: !settings.allowsRestartingConfigurationChange)
      CommandPaletteCommands()
      TypebarSettingsCommands(navigationLocked: !settings.allowsRestartingConfigurationChange)
    }

    Settings {
      PreferencesView(settings: settings, account: account, hotkey: hotkey)
    }

    Window("关于 Typebar", id: "about") {
      AboutTypebarView(metadata: .current, account: account)
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
    Self.practiceContent(
      settings: settings, account: account, announcements: announcements, hotkey: hotkey,
      systemKeyboardGuide: systemKeyboardGuide, network: network, systemAppearance: systemAppearance,
      websiteConfigStartup: .init(accountReady: accountStartup.isReady))
      .frame(minWidth: 760, minHeight: 480)
      .task {
        await accountStartup.restore { await account.restoreSession() }
        await announcements.refresh(using: account)
        hotkey.setEnabled(settings.globalHotkeyEnabled)
      }
      .onChange(of: account.currentUser?.id) { _, _ in
        Task { await announcements.refresh(using: account) }
      }
  }

  /// One production composition entry for the app and isolated hosted checks.
  /// The viewport injection evaluates the new display owner through this same
  /// page while keeping whole-preview preparation on the shared path.
  static func practiceContent(settings: AppSettings, account: AccountSession,
    announcements: RemoteAnnouncementCenter, hotkey: GlobalHotkeyMonitor,
    systemKeyboardGuide: SystemKeyboardGuideMonitor, network: NetworkConnectivityMonitor,
    systemAppearance: SystemAppearanceMonitor,
    liveContentFetch: @escaping @MainActor (LivePracticeContentSource, TypingLanguage) async -> LivePracticeContent? = {
      await LivePracticeContentService.fetch(source: $0, language: $1)
    },
    livePromptPrepare: @escaping @MainActor (LivePracticeContent, TestConfiguration, Bool) async throws -> LivePracticePrompt = {
      try await $0.preparingPromptDescriptor(for: $1, showAllLines: $2)
    },
    liveSessionPrepare: @escaping @MainActor (TestConfiguration, LivePracticePrompt, LivePracticePrompt?, WeakSpotScores, PoolWordDecorationState, Bool) async throws -> TypingSession = {
      try await TestSessionFactory.preparingLiveSession(configuration: $0, prompt: $1,
        continuation: $2, weakSpotScores: $3, wordDecorationState: $4, showAllLines: $5)
    },
    wholePreviewPrepare: @escaping @MainActor (TestConfiguration, WeakSpotScores, PoolWordDecorationState) async throws -> TypingSession = {
      try await WholePreviewWordPreparation.prepareSession(configuration: $0,
        weakSpotScores: $1, wordDecorationState: $2)
    },
    wholePreviewRender: @escaping @MainActor (TypingSession, PromptRenderStyle) async throws -> PromptRendering = {
      let plan = try await PromptRenderPlan.prepareCooperatively(session: $0, composition: "", style: $1)
      return try await plan.renderCooperatively()
    },
    wholePreviewLayout: @escaping @MainActor (PromptCompositionTextMap, CGFloat, NSFont, CGFloat, Bool, Bool) async throws -> PromptFieldTextLayout = {
      try await PromptFieldTextLayout.makeCooperatively(map: $0, width: $1, font: $2,
        lineSpacing: $3, rightToLeft: $4, joinsLetters: $5)
    }, promptRender: @escaping @MainActor (TypingSession, String?, PromptRenderStyle) -> PromptRendering = {
      PromptRenderPlan(session: $0, composition: $1, style: $2).render()
    }, wholePreviewViewportEnabled: Bool = false,
    publishedPresentation: WebsiteConfigPublishedPresentation? = nil,
    practiceSessionStore: PracticePageSessionStore? = nil,
    websiteConfigStartup: WebsiteConfigStartupOptions? = nil,
    configClipboardExport: WebsiteConfigClipboardExport? = nil) -> some View {
    ContentView(settings: settings, account: account, announcements: announcements,
      hotkey: hotkey, systemKeyboardGuide: systemKeyboardGuide, network: network,
      systemAppearance: systemAppearance, liveContentFetch: liveContentFetch,
      livePromptPrepare: livePromptPrepare,
      liveSessionPrepare: liveSessionPrepare,
      wholePreviewPrepare: wholePreviewPrepare, wholePreviewRender: wholePreviewRender,
      wholePreviewLayout: wholePreviewLayout, promptRender: promptRender,
      wholePreviewViewportEnabled: wholePreviewViewportEnabled, incomingPublishedPresentation: publishedPresentation,
      providedPageSessionStore: practiceSessionStore, websiteConfigStartup: websiteConfigStartup,
      providedConfigClipboardExport: configClipboardExport)
  }

  private static let modelConfiguration = ModelConfiguration(
    isStoredInMemoryOnly: QAStoreMode.usesInMemoryStore(
      info: Bundle.main.infoDictionary ?? [:]))

  private static let dataStore: Result<ModelContainer, DataStoreStartupRecovery> =
    DataStoreStartupPolicy.attempt(storeURL: modelConfiguration.url) {
      let legacyStorePresent = !modelConfiguration.isStoredInMemoryOnly
        && FileManager.default.fileExists(atPath: modelConfiguration.url.path)
      let container = try ModelContainer(
        for: TestResultRecord.self, TestPresetRecord.self, SavedCustomTextRecord.self,
        ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
        configurations: modelConfiguration)
      try LocalPersonalBestStore.initialize(in: container.mainContext, legacyStorePresent: legacyStorePresent)
      return container
    }
}

/// Supplies the document-modal termination reply required by AppKit when an
/// active long practice needs confirmation before the whole app exits.
@MainActor
final class TypebarApplicationDelegate: NSObject, NSApplicationDelegate {
  private let musicKeyboardMonitor: TypingMusicKeyboardMonitor

  override convenience init() {
    self.init(musicKeyboardMonitor: .init())
  }

  init(musicKeyboardMonitor: TypingMusicKeyboardMonitor) {
    self.musicKeyboardMonitor = musicKeyboardMonitor
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    musicKeyboardMonitor.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    musicKeyboardMonitor.stop()
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    musicKeyboardMonitor.refreshCapsLock()
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let registry = LongTestTerminationProtectionRegistry.shared
    guard registry.requiresConfirmation, !registry.permitsCurrentTermination else {
      return .terminateNow
    }
    if registry.isConfirmationInFlight {
      return .terminateLater
    }
    guard registry.beginConfirmation() else {
      return .terminateCancel
    }

    let alert = terminationConfirmationAlert()
    guard let window = registry.confirmationWindow() else {
      let approved = alert.runModal() == .alertFirstButtonReturn
      registry.resolveConfirmation(approved: approved)
      return approved ? .terminateNow : .terminateCancel
    }
    alert.beginSheetModal(for: window) { response in
      let approved = response == .alertFirstButtonReturn
      registry.resolveConfirmation(approved: approved)
      sender.reply(toApplicationShouldTerminate: approved)
    }
    return .terminateLater
  }

  private func terminationConfirmationAlert() -> NSAlert {
    let alert = NSAlert()
    alert.messageText = "退出长测试？"
    alert.informativeText = "退出 Typebar 会丢失本次尚未完成的输入。"
    alert.addButton(withTitle: "退出 Typebar")
    alert.addButton(withTitle: "取消")
    return alert
  }
}

struct TypebarSettingsCommands: Commands {
  @Environment(\.openSettings) private var openSettings
  let navigationLocked: Bool

  var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("设置…") { openSettings() }
        .keyboardShortcut(",", modifiers: .command)
        .disabled(!NoQuitNavigationPolicy.allows(.settings, whenLocked: navigationLocked))
    }
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
  let ignoresSystemReducedMotion: Bool
  @ViewBuilder let content: Content
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.typebarAnimationFrameRate) private var animationFrameRate

  var body: some View {
    let animates = PracticeVisualAnimationPolicy.shouldAnimate(
      isEnabled: isEnabled, reducesMotion: reducesMotion,
      systemReducedMotion: systemReduceMotion,
      ignoresSystemReducedMotion: ignoresSystemReducedMotion)
    return Group {
      if animates {
        TimelineView(
          .animation(minimumInterval: AnimationFrameRatePolicy.minimumInterval(for: animationFrameRate))
        ) { timeline in
          let offset = EarthquakeOffsetPolicy.offset(
            at: timeline.date, isEnabled: true, reducesMotion: false)
          content.offset(x: offset.x, y: offset.y)
        }
      } else {
        content
      }
    }
  }
}

private struct NauseaPracticeContent<Content: View>: View {
  let isEnabled: Bool
  let reducesMotion: Bool
  let ignoresSystemReducedMotion: Bool
  @ViewBuilder let content: Content
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.typebarAnimationFrameRate) private var animationFrameRate

  var body: some View {
    let animates = PracticeVisualAnimationPolicy.shouldAnimate(
      isEnabled: isEnabled, reducesMotion: reducesMotion,
      systemReducedMotion: systemReduceMotion,
      ignoresSystemReducedMotion: ignoresSystemReducedMotion)
    return Group {
      if animates {
        TimelineView(
          .animation(minimumInterval: AnimationFrameRatePolicy.minimumInterval(for: animationFrameRate))
        ) { timeline in
          let transform = NauseaVisualPolicy.transform(
            at: timeline.date, isEnabled: true, reducesMotion: false)
          content
            .scaleEffect(x: transform.horizontalScale, y: transform.verticalScale, anchor: .center)
            .rotation3DEffect(.degrees(transform.rotationDegrees), axis: (x: 0.45, y: 0.9, z: 0.12))
        }
      } else {
        content
      }
    }
  }
}

private struct RoundPracticeContent<Content: View>: View {
  let isEnabled: Bool
  let reducesMotion: Bool
  let ignoresSystemReducedMotion: Bool
  @ViewBuilder let content: Content
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.typebarAnimationFrameRate) private var animationFrameRate

  var body: some View {
    let animates = PracticeVisualAnimationPolicy.shouldAnimate(
      isEnabled: isEnabled, reducesMotion: reducesMotion,
      systemReducedMotion: systemReduceMotion,
      ignoresSystemReducedMotion: ignoresSystemReducedMotion)
    return Group {
      if animates {
        TimelineView(
          .animation(minimumInterval: AnimationFrameRatePolicy.minimumInterval(for: animationFrameRate))
        ) { timeline in
          content.rotationEffect(.degrees(RoundVisualPolicy.rotationDegrees(
            at: timeline.date, isEnabled: true, reducesMotion: false)))
        }
      } else {
        content
      }
    }
  }
}

struct TapePracticePrompt: View {
  let rendering: PromptRendering
  var compositionField: PromptCompositionField? = nil
  var hidesCompositionExtras = false
  var joinsLetters = false
  var latestProjection: (() -> TapePromptProjectionSnapshot?)? = nil
  let anchorCharacterIndex: Int
  let wordAnchorCharacterIndex: Int
  let wordStartCharacterOffsets: [Int: Int]
  let checksDirectionPerGlyph: Bool
  let mode: PracticeTapeMode
  let margin: Double
  let fontSize: Double
  let animatesScroll: Bool
  let carets: PromptCaretNativeView.Configuration
  let retirement: PromptLineScrollContext
  var newlineWords: [TapePromptWord] = []
  var viewportLineCount = 3
  var reservesViewportLineCount = false
  var expandsToContentHeight = false
  var onTapeWordsRemoved: ((PromptTapeWordRemoval) -> Void)? = nil
  @State private var metrics: TapePromptLayoutMetrics?

  var body: some View {
    TapePromptBridge(rendering: rendering, anchorCharacterIndex: anchorCharacterIndex,
      wordAnchorCharacterIndex: wordAnchorCharacterIndex, wordStartCharacterOffsets: wordStartCharacterOffsets,
      compositionField: compositionField, hidesCompositionExtras: hidesCompositionExtras,
      latestProjection: latestProjection,
      checksDirectionPerGlyph: checksDirectionPerGlyph,
      joinsLetters: joinsLetters,
      mode: mode, margin: margin,
      smoothScroll: animatesScroll, carets: carets, retirement: retirement,
      newlineWords: newlineWords, onMetrics: { metrics = $0 }, onTapeWordsRemoved: onTapeWordsRemoved,
      fallbackHeight: CGFloat(fontSize * 1.7), viewportLineCount: viewportLineCount,
      reservesViewportLineCount: reservesViewportLineCount, expandsToContentHeight: expandsToContentHeight,
      observedMetrics: metrics)
      .clipped()
      .accessibilityLabel("卷带练习提示")
  }
}

extension TapePracticePrompt {
  /// Zen owns measured word boxes from its initial hidden placeholder onward.
  /// Its empty target cannot signal the controls that the user later enters.
  /// Quote input capability stays frozen even if later generation adds rows.
  init(session: TypingSession, rendering: PromptRendering, mode: PracticeTapeMode,
    margin: Double, fontSize: Double, animatesScroll: Bool,
    carets: PromptCaretNativeView.Configuration, retirement: PromptLineScrollContext,
    latestProjection: (() -> TapePromptProjectionSnapshot?)? = nil,
    onTapeWordsRemoved: ((PromptTapeWordRemoval) -> Void)? = nil) {
    let zen = session.configuration.mode == .zen
    let declaredNewlines = session.hasPracticeNewlineContent
    let generatedNewlines = session.prompt.contains("\n")
    self.init(rendering: rendering,
      compositionField: rendering.compositionTextMap == nil ? nil : session.promptCompositionField,
      hidesCompositionExtras: session.configuration.rules.hideExtraLetters,
      joinsLetters: session.configuration.usesJoiningScriptPrompt,
      latestProjection: latestProjection,
      anchorCharacterIndex: PracticeTapePolicy.anchorCharacterIndex(session: session, rendering: rendering, mode: mode),
      wordAnchorCharacterIndex: PracticeTapePolicy.anchorCharacterIndex(session: session, rendering: rendering, mode: .word),
      wordStartCharacterOffsets: PracticeTapePolicy.wordStartCharacterOffsets(session: session, rendering: rendering),
      checksDirectionPerGlyph: session.configuration.mode == .custom || zen
        || session.configuration.language == .mixedLanguages,
      mode: mode, margin: margin, fontSize: fontSize, animatesScroll: animatesScroll,
      carets: carets, retirement: retirement,
      newlineWords: zen || declaredNewlines || generatedNewlines
        ? TapePromptProjection.words(session: session, rendering: rendering) : [],
      viewportLineCount: zen ? 2 : 3, reservesViewportLineCount: zen || declaredNewlines,
      expandsToContentHeight: !zen && !declaredNewlines && generatedNewlines,
      onTapeWordsRemoved: onTapeWordsRemoved)
  }
}

private struct TapePromptBridge: NSViewRepresentable {
  let rendering: PromptRendering
  let anchorCharacterIndex: Int, wordAnchorCharacterIndex: Int
  let wordStartCharacterOffsets: [Int: Int]
  let compositionField: PromptCompositionField?
  let hidesCompositionExtras: Bool
  let latestProjection: (() -> TapePromptProjectionSnapshot?)?
  let checksDirectionPerGlyph: Bool
  let joinsLetters: Bool
  let mode: PracticeTapeMode
  let margin: Double
  let smoothScroll: Bool
  let carets: PromptCaretNativeView.Configuration
  let retirement: PromptLineScrollContext
  var newlineWords: [TapePromptWord] = []
  var onMetrics: ((TapePromptLayoutMetrics) -> Void)? = nil
  var onTapeWordsRemoved: ((PromptTapeWordRemoval) -> Void)? = nil
  var fallbackHeight: CGFloat = 48
  var viewportLineCount = 3
  var reservesViewportLineCount = false
  var expandsToContentHeight = false
  // Keep native animated topology changes observable to SwiftUI measurement.
  var observedMetrics: TapePromptLayoutMetrics? = nil
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: TapePromptNativeView, context: Context) -> CGSize? {
    let height = nsView.viewportHeight(fallback: fallbackHeight, lineCount: viewportLineCount,
      reservesLineCount: reservesViewportLineCount, expandsToContent: expandsToContentHeight)
    return CGSize(width: max(1, proposal.width ?? nsView.bounds.width), height: height)
  }
  func makeNSView(context: Context) -> TapePromptNativeView { TapePromptNativeView() }
  func updateNSView(_ view: TapePromptNativeView, context: Context) {
    view.configure(rendering: rendering, anchorCharacterIndex: anchorCharacterIndex,
      wordAnchorCharacterIndex: wordAnchorCharacterIndex, wordStartCharacterOffsets: wordStartCharacterOffsets,
      compositionField: compositionField, hidesCompositionExtras: hidesCompositionExtras,
      latestProjection: latestProjection,
      checksDirectionPerGlyph: checksDirectionPerGlyph,
      joinsLetters: joinsLetters,
      mode: mode, margin: margin,
      smoothScroll: smoothScroll, retirement: retirement, newlineWords: newlineWords,
      onMetrics: onMetrics, onTapeWordsRemoved: onTapeWordsRemoved, carets: carets)
  }
  static func dismantleNSView(_ view: TapePromptNativeView, coordinator: ()) { view.stop() }
}

/// Resolve the same practice theme roles as the ordinary prompt before handing
/// static colors to Core Animation; AppKit's label colors follow the system
/// appearance, which can differ from the selected Typebar theme.
struct ChooGlyphPalette: Equatable {
  let completed: NSColor
  let future: NSColor
  let accent: NSColor
  let error: NSColor
  let extra: NSColor

  init(theme: ResolvedTheme, flipsCompletionAndFuture: Bool, usesColorfulMode: Bool) {
    func promptColor(for role: PromptTextRole) -> NSColor {
      switch PromptTextColorPolicy.tone(
        for: role, flipsCompletionAndFuture: flipsCompletionAndFuture,
        usesAccentForCompleted: usesColorfulMode)
      {
      case .primary: NSColor(theme.text)
      case .secondary: NSColor(theme.secondaryText)
      case .accent: NSColor(theme.accent)
      }
    }
    completed = promptColor(for: .completed)
    future = promptColor(for: .future)
    accent = NSColor(theme.accent)
    error = NSColor(theme.errorColor(usesColorfulMode: usesColorfulMode))
    extra = NSColor(theme.extraInputColor(usesColorfulMode: usesColorfulMode))
  }

  func foreground(for state: TypingPromptCharacterState) -> NSColor {
    switch state {
    case .correct: completed
    case .incorrect: error
    case .extra: extra
    case .current: future
    case .pending: future
    case .hidden: .clear
    }
  }

  func background(for state: TypingPromptCharacterState) -> NSColor? {
    switch state {
    case .incorrect: error.withAlphaComponent(error.alphaComponent * 0.16)
    case .extra: extra.withAlphaComponent(extra.alphaComponent * 0.12)
    case .current: nil
    default: nil
    }
  }
}

struct ChooPracticePrompt: View {
  let glyphs: [TypingPromptGlyph]
  let rendering: PromptRendering
  let font: NSFont
  let palette: ChooGlyphPalette
  let isEnabled: Bool
  let reducesMotion: Bool
  let ignoresSystemReducedMotion: Bool
  var glyphIDs: [Int] = []
  var carets: PromptCaretNativeView.Configuration? = nil
  var viewportLineCount: Int? = nil
  var lineScroll: PromptLineScrollContext? = nil
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Environment(\.typebarSystemReduceMotionOverride) private var systemReduceMotionOverride
  @Environment(\.typebarAnimationFrameRate) private var animationFrameRate

  var body: some View {
    let animates = PracticeVisualAnimationPolicy.shouldAnimate(
      isEnabled: isEnabled, reducesMotion: reducesMotion,
      systemReducedMotion: systemReduceMotionOverride ?? systemReduceMotion,
      ignoresSystemReducedMotion: ignoresSystemReducedMotion)
    let effectiveScroll = lineScroll.map {
      PromptLineScrollContext(attemptID: $0.attemptID, activeWordID: $0.activeWordID,
        characterOffsets: $0.characterOffsets, smoothScroll: $0.smoothScroll,
        reducesMotion: $0.reducesMotion || (systemReduceMotionOverride ?? systemReduceMotion), frameRate: animationFrameRate,
        words: $0.words, firstRetainedWordIndex: $0.firstRetainedWordIndex,
        onRetire: $0.onRetire, followsWordReflow: $0.followsWordReflow, caretMotion: $0.caretMotion,
        centersActiveLine: $0.centersActiveLine, wrapperRevision: $0.wrapperRevision)
    }
    return ChooLayerPrompt(glyphs: glyphs, font: font, palette: palette,
                           animates: animates, frameRate: animationFrameRate,
                           glyphIDs: glyphIDs, rendering: rendering, carets: carets, lineScroll: effectiveScroll)
      .background {
        GeometryReader { proxy in
          Color.clear.preference(key: PracticeViewportHeightKey.self,
            value: viewportLineCount.flatMap { count in
              ChooLayerView.viewportHeight(glyphs: glyphs, font: font, width: proxy.size.width,
                glyphIDs: glyphIDs, rendering: rendering, lineCount: count)
            })
        }
      }
      .accessibilityLabel("旋转文字练习提示")
  }
}

private struct ChooLayerPrompt: NSViewRepresentable {
  let glyphs: [TypingPromptGlyph]
  let font: NSFont
  let palette: ChooGlyphPalette
  let animates: Bool
  let frameRate: Int
  let glyphIDs: [Int]
  let rendering: PromptRendering
  let carets: PromptCaretNativeView.Configuration?
  let lineScroll: PromptLineScrollContext?

  func makeNSView(context: Context) -> ChooLayerView { ChooLayerView() }

  func updateNSView(_ view: ChooLayerView, context: Context) {
    view.configure(glyphs: glyphs, font: font, palette: palette,
                   animates: animates, frameRate: frameRate,
                   glyphIDs: glyphIDs, rendering: rendering)
    view.configureCarets(carets, glyphIDs: glyphIDs)
    view.configureLineScroll(lineScroll)
  }

  static func dismantleNSView(_ view: ChooLayerView, coordinator: ()) { view.stop() }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: ChooLayerView, context: Context) -> CGSize? {
    let width = max(1, proposal.width ?? nsView.bounds.width)
    return CGSize(width: width, height: ChooLayerView.measure(glyphs: glyphs, font: font, width: width,
      glyphIDs: glyphIDs, rendering: rendering))
  }
}

final class ChooLayerView: NSView {
  private var glyphs: [TypingPromptGlyph] = []
  private var presentation: ChooPromptPresentation?
  private var glyphLayers: [Int: CATextLayer] = [:]
  private var hintLayers: [Int: (layer: CATextLayer, top: CGFloat)] = [:]
  private var glyphFrames: [CGRect] = []
  private var laidOutWidth: CGFloat = 0
  private var promptFont = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
  private var palette = ChooGlyphPalette(
    theme: AppTheme.paper.resolvedTheme,
    flipsCompletionAndFuture: false, usesColorfulMode: false)
  private var animates = false
  private var frameRate = AnimationFrameRatePolicy.nativeFrameRate
  private var animationStartTime = CACurrentMediaTime()
  private weak var observedClipView: NSClipView?
  private var caretView: PromptCaretNativeView?
  private var caretConfiguration: PromptCaretNativeView.Configuration?
  private var glyphIndexByID: [Int: Int] = [:]
  private var geometryRevision: UInt64 = 0
  private var lineScroll: PromptLineScrollContext?
  private var follower: PromptAutoScrollView?
  private var promptText = AttributedString()
  private var lineGeometry = ASLPromptLineGeometry(frames: [:])
  private var lineGeometryRevision: UInt64?

  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.isGeometryFlipped = true
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
  }

  required init?(coder: NSCoder) { fatalError("ChooLayerView is created in code") }

  deinit { NotificationCenter.default.removeObserver(self) }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    observeScrollClip()
    refreshVisibleLayers()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    observeScrollClip()
    refreshVisibleLayers()
  }

  override func viewWillMove(toSuperview newSuperview: NSView?) {
    if newSuperview == nil { stop() }
    super.viewWillMove(toSuperview: newSuperview)
  }

  private func observeScrollClip() {
    let clip = enclosingScrollView?.contentView
    guard observedClipView !== clip else { return }
    if let observedClipView {
      NotificationCenter.default.removeObserver(
        self, name: NSView.boundsDidChangeNotification, object: observedClipView)
    }
    observedClipView = clip
    clip?.postsBoundsChangedNotifications = true
    if let clip {
      NotificationCenter.default.addObserver(
        self, selector: #selector(scrollClipBoundsChanged),
        name: NSView.boundsDidChangeNotification, object: clip)
    }
  }

  @objc private func scrollClipBoundsChanged() {
    refreshVisibleLayers()
  }

  func configure(glyphs: [TypingPromptGlyph], font: NSFont, palette: ChooGlyphPalette,
                 animates: Bool, frameRate: Int, glyphIDs: [Int] = [], rendering: PromptRendering? = nil) {
    let presentation = rendering.map { ChooPromptPresentation(glyphs: glyphs, ids: glyphIDs, rendering: $0) }
    let visibleGlyphs = presentation?.cells.map(\.glyph) ?? glyphs
    let changesLayout = self.glyphs != visibleGlyphs || promptFont != font
      || self.presentation?.cells.map(\.id) != presentation?.cells.map(\.id)
      || self.presentation?.cells.map { $0.content.text } != presentation?.cells.map { $0.content.text }
      || self.presentation?.compositionMap?.fieldRuns != presentation?.compositionMap?.fieldRuns
      || self.presentation?.structuralBreaksBefore != presentation?.structuralBreaksBefore
      || self.presentation?.trailingStructuralBreaks != presentation?.trailingStructuralBreaks
    let changesStyle = changesLayout || self.palette != palette
    let changesAnimation = self.animates != animates || self.frameRate != frameRate
    if self.presentation?.compositionMap?.caret != presentation?.compositionMap?.caret
      || self.presentation?.compositionMap?.canonicalAliases != presentation?.compositionMap?.canonicalAliases {
      geometryRevision &+= 1
    }
    self.glyphs = visibleGlyphs
    self.presentation = presentation
    promptText = rendering?.text ?? AttributedString()
    promptFont = font
    self.palette = palette
    self.animates = animates
    self.frameRate = frameRate
    if changesLayout { glyphFrames.removeAll(keepingCapacity: true) }
    if changesAnimation { animationStartTime = CACurrentMediaTime() }
    refreshVisibleLayers(forceStyle: changesStyle)
    if changesAnimation { updateAnimations() }
    setAccessibilityLabel(rendering.map { String($0.text.characters) }
      ?? glyphs.map { String($0.typedCharacter ?? $0.character) }.joined())
  }

  override func layout() {
    super.layout()
    refreshVisibleLayers()
    refreshCarets()
    refreshLineScroll()
  }

  func configureCarets(_ configuration: PromptCaretNativeView.Configuration?, glyphIDs: [Int]) {
    let ids = presentation?.cells.map(\.id) ?? glyphIDs
    let next = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
    if next != glyphIndexByID { glyphIndexByID = next; geometryRevision &+= 1 }
    caretConfiguration = configuration
    refreshCarets()
  }

  func stopCarets() {
    caretView?.stop(); caretView?.removeFromSuperview(); caretView = nil
    caretConfiguration = nil
  }

  func configureLineScroll(_ context: PromptLineScrollContext?) {
    lineScroll = context
    refreshLineScroll()
  }

  func stop() {
    stopCarets()
    lineScroll = nil
    follower?.cancelCaretMotion(); follower?.stopLineScroll()
    follower?.removeFromSuperview(); follower = nil
  }

  private func refreshLineScroll() {
    guard let context = lineScroll, let map = presentation?.compositionMap else {
      follower?.cancelCaretMotion(); follower?.stopLineScroll()
      follower?.removeFromSuperview(); follower = nil
      return
    }
    if lineGeometryRevision != geometryRevision {
      var frames: [Int: CGRect] = [:], words: [Int: CGRect] = [:]
      for field in map.fieldRuns {
        for cell in field.cells {
          guard let index = glyphIndexByID[cell.id], glyphFrames.indices.contains(index) else { continue }
          var frame = glyphFrames[index]; frame.size.width -= ChooPromptFieldLayout.inkOverhang
          frames[cell.id] = frame
          if let owner = field.fieldID, !cell.isGap, frame.width > 0, frame.height > 0 {
            words[owner] = words[owner].map { $0.union(frame) } ?? frame
          }
        }
      }
      lineGeometry = ASLPromptLineGeometry(frames: frames, wordFrames: words)
      lineGeometryRevision = geometryRevision
    }
    if follower == nil {
      let view = PromptAutoScrollView(frame: bounds)
      view.autoresizingMask = [.width, .height]
      addSubview(view); follower = view
    }
    follower?.frame = bounds
    follower?.update(text: promptText, characterOffset: nil, font: promptFont, lineSpacing: 12,
      isRightToLeft: false, lineScroll: context,
      customGeometry: .init(revision: geometryRevision, caretGlyphID: map.caret?.cellID,
        measure: { [weak self] active, previous, caret, words in
          self?.lineGeometry.measure(active: active, previous: previous, caret: caret, words: words)
        }))
  }

  private func refreshCarets() {
    guard var configuration = caretConfiguration else { stopCarets(); return }
    if caretView == nil {
      let view = PromptCaretNativeView(frame: bounds)
      addSubview(view); caretView = view
    }
    caretView?.frame = bounds
    configuration.glyphRect = { [weak self] id in self?.caretRect(forGlyphID: id) }
    configuration.geometryRevision = geometryRevision
    configuration.firstGlyphID = glyphIndexByID.min { $0.value < $1.value }?.key ?? 0
    if presentation?.compositionMap != nil {
      let direction = configuration.rightToLeft
      let presented = PromptRendering(text: promptText, glyphCharacterOffsets: [:],
        compositionTextMap: presentation?.compositionMap)
      configuration.latestRendering = { presented }
      configuration.fieldMainRect = { [weak self] style in self?.projectedMainRect(style: style, rightToLeft: direction) }
      configuration.fieldPaceRect = { [weak self] id, after in self?.projectedCanonicalRect(id, after: after) }
      configuration.markedCellRect = { [weak self] id in self?.projectedRect(id, after: false) }
    }
    caretView?.update(configuration)
  }

  private func projectedRect(_ id: Int, after: Bool) -> CGRect? {
    guard let index = glyphIndexByID[id], glyphFrames.indices.contains(index) else { return nil }
    func allocation(_ index: Int) -> CGRect {
      var rect = glyphFrames[index]
      rect.size.width -= ChooPromptFieldLayout.inkOverhang
      return rect
    }
    let rect = allocation(index)
    if !after, presentation?.projectedSeparators.contains(id) == true,
      glyphFrames.indices.contains(index + 1), glyphFrames[index + 1].minY > rect.minY {
      return allocation(index + 1)
    }
    return rect
  }

  private func projectedCanonicalRect(_ id: Int, after: Bool) -> CGRect? {
    let ids = presentation?.compositionMap?.canonicalAliases[id] ?? (glyphIndexByID[id] == nil ? [] : [id])
    return (after ? ids.last : ids.first).flatMap { projectedRect($0, after: after) }
  }

  private func projectedMainRect(style: TypingCaretStyle, rightToLeft: Bool) -> CGRect? {
    guard let anchor = presentation?.compositionMap?.caret,
      let rect = projectedRect(anchor.cellID, after: anchor.after) else { return nil }
    return PromptPaceCaretGeometry.rect(from: rect, to: rect, fromAfter: anchor.after, toAfter: anchor.after,
      style: style, rightToLeft: rightToLeft, fraction: 1, reducesMotion: true,
      afterWidth: (" " as NSString).size(withAttributes: [.font: promptFont]).width)
  }

  private func caretRect(forGlyphID id: Int) -> CGRect? {
    if presentation?.compositionMap != nil { return projectedRect(id, after: false) }
    guard let index = glyphIndexByID[id], glyphFrames.indices.contains(index) else { return nil }
    for position in stride(from: index, through: 0, by: -1) {
      let frame = glyphFrames[position]
      if frame.width > 0, frame.height > 0 { return frame }
    }
    return nil
  }

  static func measure(glyphs: [TypingPromptGlyph], font: NSFont, width: CGFloat,
    glyphIDs: [Int] = [], rendering: PromptRendering? = nil) -> CGFloat {
    let presentation = rendering.map { ChooPromptPresentation(glyphs: glyphs, ids: glyphIDs, rendering: $0) }
    return layoutFrames(glyphs: presentation?.cells.map(\.glyph) ?? glyphs,
      presentation: presentation, font: font, width: width).height
  }

  /// Rotation changes ink only. Report rows from the exact untransformed
  /// field allocations used by layoutFrames, never from a TextKit substitute.
  static func viewportHeight(glyphs: [TypingPromptGlyph], font: NSFont, width: CGFloat,
    glyphIDs: [Int], rendering: PromptRendering, lineCount: Int) -> CGFloat? {
    guard rendering.compositionTextMap != nil, width.isFinite, width > 0, lineCount > 0 else { return nil }
    let presentation = ChooPromptPresentation(glyphs: glyphs, ids: glyphIDs, rendering: rendering)
    let layout = ChooPromptFieldLayout(presentation: presentation, font: font, width: width)
    let frames = Dictionary(presentation.cells.enumerated().map { ($0.element.id, layout.frames[$0.offset]) },
      uniquingKeysWith: { first, _ in first })
    return PromptViewportLayout.height(forRowHeights: ASLPromptLineGeometry(frames: frames).rowHeights,
      lineCount: lineCount)
  }

  private func refreshVisibleLayers(forceStyle: Bool = false) {
    guard !glyphs.isEmpty else {
      glyphLayers.values.forEach { $0.removeFromSuperlayer() }
      glyphLayers.removeAll()
      hintLayers.values.forEach { $0.layer.removeFromSuperlayer() }
      hintLayers.removeAll()
      glyphFrames.removeAll()
      return
    }
    let width = max(1, bounds.width)
    if glyphFrames.count != glyphs.count || laidOutWidth != width {
      glyphFrames = Self.layoutFrames(glyphs: glyphs, presentation: presentation, font: promptFont, width: width).frames
      laidOutWidth = width
      geometryRevision &+= 1
    }
    // SwiftUI's prompt scroll area clips this document view. Keeping a small
    // overscan means scrolls do not expose empty rows between notifications.
    let viewport = visibleRect.isEmpty
      ? CGRect(x: 0, y: 0, width: width, height: min(bounds.height, 240))
      : visibleRect
    let window = viewport.insetBy(dx: 0, dy: -120)
    var low = 0
    var high = glyphFrames.count
    while low < high {
      let middle = (low + high) / 2
      if glyphFrames[middle].maxY < window.minY {
        low = middle + 1
      } else {
        high = middle
      }
    }
    var desired: [Int] = []
    var index = low
    while index < glyphFrames.count, glyphFrames[index].minY <= window.maxY {
      if presentation != nil || glyphs[index].character != "\n" { desired.append(index) }
      index += 1
    }
    let desiredSet = Set(desired)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for index in Array(glyphLayers.keys) where !desiredSet.contains(index) {
      glyphLayers.removeValue(forKey: index)?.removeFromSuperlayer()
      hintLayers.removeValue(forKey: index)?.layer.removeFromSuperlayer()
    }
    for index in desired {
      if let text = glyphLayers[index] {
        text.frame = glyphFrames[index]
        if forceStyle { style(text, at: index) }
      } else {
        let text = CATextLayer()
        text.contentsScale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        text.alignmentMode = .left
        text.isWrapped = false
        text.frame = glyphFrames[index]
        style(text, at: index)
        layer?.addSublayer(text)
        glyphLayers[index] = text
        addRotation(to: text)
      }
      if let hint = hintLayers[index] {
        hint.layer.frame.origin = .init(x: glyphFrames[index].midX - hint.layer.frame.width / 2,
          y: glyphFrames[index].minY + hint.top)
      }
    }
    CATransaction.commit()
  }

  private func style(_ text: CATextLayer, at index: Int) {
    hintLayers.removeValue(forKey: index)?.layer.removeFromSuperlayer()
    if let content = presentation?.cells[index].content {
      text.string = ChooPromptPresentation.nativeText(content.main, font: promptFont)
      text.foregroundColor = nil; text.backgroundColor = nil
      if let hint = content.hint {
        let value = ChooPromptPresentation.nativeHint(hint, font: promptFont)
        let layer = CATextLayer()
        layer.name = "chooHint"
        layer.contentsScale = text.contentsScale; layer.alignmentMode = .left
        layer.string = value.text
        layer.frame = .init(x: 0, y: value.top, width: max(1, ceil(value.text.size().width) + 2), height: value.height)
        self.layer?.addSublayer(layer)
        hintLayers[index] = (layer, value.top)
        addRotation(to: layer)
      }
      return
    }
    let glyph = glyphs[index]
    text.string = String(glyph.typedCharacter ?? glyph.character)
    text.font = promptFont
    text.fontSize = promptFont.pointSize
    text.foregroundColor = palette.foreground(for: glyph.state).cgColor
    text.backgroundColor = palette.background(for: glyph.state)?.cgColor
  }

  private static func layoutFrames(glyphs: [TypingPromptGlyph], presentation: ChooPromptPresentation?, font: NSFont, width: CGFloat)
    -> (frames: [CGRect], height: CGFloat) {
    if let presentation, presentation.compositionMap != nil {
      let layout = ChooPromptFieldLayout(presentation: presentation, font: font, width: width)
      return (layout.frames, layout.height)
    }
    let lineHeight = ceil(font.ascender - font.descender + font.leading)
    var x: CGFloat = 0
    var y: CGFloat = 0
    var inkBottom: CGFloat = 0
    var frames: [CGRect] = []
    frames.reserveCapacity(glyphs.count)
    for (index, glyph) in glyphs.enumerated() {
      if let count = presentation?.structuralBreaksBefore[index] {
        x = 0; y += CGFloat(count) * (lineHeight + 12)
      }
      let content = presentation?.cells[index].content
      if content == nil && glyph.character == "\n" {
        x = 0
        y += lineHeight + 12
        frames.append(CGRect(x: 0, y: y, width: 0, height: 0))
        continue
      }
      let advance = max(1, ceil(content.map { ChooPromptPresentation.nativeText($0.main, font: font).size().width }
        ?? (String(glyph.typedCharacter ?? glyph.character) as NSString).size(withAttributes: [.font: font]).width))
      if x > 0 && x + advance > width {
        x = 0
        y += lineHeight + 12
      }
      frames.append(CGRect(x: x, y: y, width: advance + 2, height: lineHeight))
      if let hint = content?.hint {
        let value = ChooPromptPresentation.nativeHint(hint, font: font)
        inkBottom = max(inkBottom, y + value.top + value.height)
      }
      x += advance
      if content?.ownsLineBreak == true { x = 0; y += lineHeight + 12 }
    }
    y += CGFloat(presentation?.trailingStructuralBreaks ?? 0) * (lineHeight + 12)
    return (frames, max(y + lineHeight, inkBottom))
  }

  private func updateAnimations() {
    for text in Array(glyphLayers.values) + hintLayers.values.map(\.layer) {
      text.removeAnimation(forKey: "chooRotation")
      addRotation(to: text)
    }
  }

  private func addRotation(to text: CATextLayer) {
    guard animates else { return }
    let animation = CABasicAnimation(keyPath: "transform.rotation.z")
    animation.fromValue = 0
    animation.toValue = 2 * Double.pi
    animation.duration = ChooVisualPolicy.cycleDuration
    animation.repeatCount = .infinity
    animation.beginTime = animationStartTime
    animation.timingFunction = CAMediaTimingFunction(name: .linear)
    if frameRate != AnimationFrameRatePolicy.nativeFrameRate {
      let rate = Float(AnimationFrameRatePolicy.normalized(frameRate))
      animation.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
    }
    text.add(animation, forKey: "chooRotation")
  }
}

struct ASLPracticePrompt: View {
  let glyphs: [TypingPromptGlyph]
  let fontSize: Double
  let accent: Color
  var glyphIDs: [Int] = []
  var rendering: PromptRendering? = nil
  var carets: PromptCaretNativeView.Configuration? = nil
  var font: NSFont? = nil
  var lineScroll: PromptLineScrollContext? = nil
  var caretGlyphID: Int? = nil
  var viewportLineCount: Int? = nil
  var words: [TypingPromptWordPresentation]? = nil

  private var ids: [Int] { glyphIDs.count == glyphs.count ? glyphIDs : Array(glyphs.indices) }

  var body: some View {
    let cells = ASLPromptCellPlan(glyphs: glyphs, ids: ids, rendering: rendering).cells
    let visibleGlyphs = cells.map(\.glyph), ids = cells.map(\.id)
    let wordPlan = ASLPromptWordPlan(glyphs: visibleGlyphs, ids: ids, words: words,
      placeholderGlyphID: rendering?.emptyWordPlaceholderGlyphID, compositionMap: rendering?.compositionTextMap)
    return ASLPromptFlowLayout {
      ForEach(cells) { cell in
        ASLPromptGlyphCell(content: cell.content, size: fontSize,
          font: font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular))
          .layoutValue(key: ASLPromptWordIDKey.self, value: wordPlan.wordByGlyphID[cell.id] ?? cell.id)
          .layoutValue(key: ASLPromptLineBreakKey.self, value: wordPlan.lineBreakGlyphIDs.contains(cell.id))
          .layoutValue(key: ASLPromptSeparatorKey.self, value: wordPlan.separatorGlyphIDs.contains(cell.id))
          .anchorPreference(key: ASLPromptBoundsKey.self, value: .bounds) { [cell.id: $0] }
      }
    }
    .overlayPreferenceValue(ASLPromptBoundsKey.self) { anchors in
      GeometryReader { proxy in
        let frames = anchors.mapValues { proxy[$0] }
        let wordFrames = wordPlan.measuredWords(frames: frames, glyphs: visibleGlyphs, ids: ids)
        let rowHeights = ASLPromptLineGeometry(frames: frames).rowHeights
        ZStack {
          Color.clear.preference(key: PracticeViewportHeightKey.self,
            value: viewportLineCount.flatMap { PromptViewportLayout.height(forRowHeights: rowHeights, lineCount: $0) })
          if carets != nil || lineScroll != nil {
            ASLPromptCaretBridge(configuration: carets,
              frames: frames, glyphIDs: ids, lineScroll: lineScroll, caretGlyphID: caretGlyphID,
              text: rendering?.text ?? AttributedString(),
              font: font ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), wordFrames: wordFrames,
              compositionMap: rendering?.compositionTextMap)
              .allowsHitTesting(false).accessibilityHidden(true)
          }
        }
      }
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
  let continuous: Bool

  var remainingText: String {
    LongSavedTextProgress.remainingText(in: text, after: progress)
  }

  var currentChunk: String {
    LongSavedTextProgress.nextChunk(in: text, after: progress)
  }
}

private struct PendingPublicationRetryTrigger: Equatable {
  let networkStatus: NetworkConnectivityStatus
  let scope: ResultPublicationScope?
  let isEnabled: Bool
}

private struct NoQuitConfigurationLockSynchronizer: ViewModifier {
  let session: TypingSession
  let settings: AppSettings
  let ownerID: UUID

  func body(content: Content) -> some View {
    content
      .onChange(of: session.hasStarted) { _, _ in synchronize() }
      .onChange(of: session.isFinished) { _, _ in synchronize() }
      .onChange(of: session.configuration.modifiers) { _, _ in synchronize() }
      .onDisappear { settings.setNoQuitConfigurationLock(false, for: ownerID) }
  }

  private func synchronize() {
    settings.setNoQuitConfigurationLock(
      !NoQuitConfigurationChangePolicy.allowsRestartingChange(for: session), for: ownerID)
  }
}

private struct PreparedWholePreviewPresentation {
  let attemptID: UUID
  let typedSnapshot: String
  let rendering: PromptRendering
  let layout: PromptFieldTextLayout?
  let style: PromptRenderStyle
  let paceGuideIndex: Int?
}

private struct PreparedWholePreviewResult {
  let session: TypingSession
  // nil is an explicitly admitted viewport source, not an empty rendering.
  let rendering: PromptRendering?
  let layout: PromptFieldTextLayout?
  let layoutWidth: CGFloat?
  let style: PromptRenderStyle
  let paceTargetWpm: Double?
  let paceGuideIndex: Int?
}

private struct ContentView: View {
  let settings: AppSettings
  let account: AccountSession
  let announcements: RemoteAnnouncementCenter
  let hotkey: GlobalHotkeyMonitor
  let systemKeyboardGuide: SystemKeyboardGuideMonitor
  let network: NetworkConnectivityMonitor
  let systemAppearance: SystemAppearanceMonitor
  let liveContentFetch: @MainActor (LivePracticeContentSource, TypingLanguage) async -> LivePracticeContent?
  let livePromptPrepare: @MainActor (LivePracticeContent, TestConfiguration, Bool) async throws -> LivePracticePrompt
  let liveSessionPrepare: @MainActor (TestConfiguration, LivePracticePrompt, LivePracticePrompt?, WeakSpotScores, PoolWordDecorationState, Bool) async throws -> TypingSession
  let wholePreviewPrepare: @MainActor (TestConfiguration, WeakSpotScores, PoolWordDecorationState) async throws -> TypingSession
  let wholePreviewRender: @MainActor (TypingSession, PromptRenderStyle) async throws -> PromptRendering
  let wholePreviewLayout: @MainActor (PromptCompositionTextMap, CGFloat, NSFont, CGFloat, Bool, Bool) async throws -> PromptFieldTextLayout
  let promptRender: @MainActor (TypingSession, String?, PromptRenderStyle) -> PromptRendering
  let wholePreviewViewportEnabled: Bool
  let incomingPublishedPresentation: WebsiteConfigPublishedPresentation?
  let providedPageSessionStore: PracticePageSessionStore?
  let websiteConfigStartup: WebsiteConfigStartupOptions?
  let providedConfigClipboardExport: WebsiteConfigClipboardExport?
  @Environment(\.modelContext) private var modelContext
  @Environment(\.openSettings) private var openSettings
  @Environment(\.openWindow) private var openWindow
  private var systemColorScheme: ColorScheme { systemAppearance.colorScheme }
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @Query(sort: \TestResultRecord.finishedAt, order: .reverse) private var savedResults:
    [TestResultRecord]
  @Query private var personalBestLedgers: [LocalPersonalBestLedgerRecord]
  @Query(sort: \TestPresetRecord.createdAt, order: .reverse) private var savedPresets:
    [TestPresetRecord]
  @State private var ownedPageSessionStore = PracticePageSessionStore()
  @State private var finalizedPracticeAttemptID: UUID?
  private var pageSessionStore: PracticePageSessionStore { providedPageSessionStore ?? ownedPageSessionStore }
  private var startupBlocksPractice: Bool {
    websiteConfigStartup != nil && pageSessionStore.startupController.isBlocking
  }
  private var pageSession: PracticePageSessionState {
    get { pageSessionStore.state }
    nonmutating set { pageSessionStore.replace(newValue) }
  }
  private var session: TypingSession {
    get { pageSession.session }
    nonmutating set {
      if pageSession.practice != nil, newValue.automaticInputAttemptID != pageSession.session.automaticInputAttemptID { return }
      pageSession.session = newValue
    }
  }
  private var publishedPresentation: WebsiteConfigPublishedPresentation? {
    pageSession.presentation ?? (incomingPublishedPresentation?.publication.practice == nil ? incomingPublishedPresentation : nil)
  }
  private var committedPracticeDraft: WebsiteConfigNativeDraft? {
    pageSession.practice == nil ? nil : pageSession.presentation?.publication.draft
  }
  private var practiceAppearance: PracticeAppearanceSelection {
    .init(draft: committedPracticeDraft, settings: settings)
  }
  private var practiceKeyboardGuide: PracticeKeyboardGuideSelection {
    .init(draft: committedPracticeDraft, settings: settings,
      legacyMode: challengeLiveConfiguration.keyboardGuideMode(settings: settings))
  }
  private var savesCurrentPracticeResults: Bool {
    committedPracticeDraft?.behavior.saveCompletedResults ?? settings.saveCompletedResults
  }
  private var practiceQuickRestartKey: QuickRestartKey {
    committedPracticeDraft?.behavior.quickRestartKey ?? settings.quickRestartKey
  }
  private var practiceCommandPaletteListMode: CommandPaletteListMode {
    committedPracticeDraft?.behavior.commandPaletteListMode ?? settings.commandPaletteListMode
  }
  @State private var websiteSoundOutput: WebsitePracticeSoundOutput?
  @State private var websiteSoundVolume: WebsiteSoundVolumePresentation?
  @State private var queuedWebsiteSoundVolume: WebsiteSoundVolumePresentation?
  @State private var websitePaceSpeed: WebsitePaceSpeedPresentation?
  @State private var queuedWebsitePaceSpeed: WebsitePaceSpeedPresentation?
  @State private var websiteKeymapSize: WebsiteKeymapSizePresentation?
  @State private var queuedWebsiteKeymapSize: WebsiteKeymapSizePresentation?
  private var practiceSoundSelection: PracticeSoundSelection {
    .init(draft: committedPracticeDraft, settings: settings, blindMode: session.configuration.rules.blindMode)
  }
  private func practiceSoundPlayer() -> TypingFeedbackSound {
    guard committedPracticeDraft != nil else {
      websiteSoundOutput?.stop(); websiteSoundOutput = nil
      return settings.practiceFeedbackSound
    }
    let output = websiteSoundOutput ?? WebsitePracticeSoundOutput(parent: settings.practiceFeedbackSound)
    if websiteSoundOutput == nil { websiteSoundOutput = output }
    output.apply(practiceSoundSelection)
    return output.player
  }
  @State private var noQuitConfigurationLockOwnerID = UUID()
  @State private var promptCaretMotion = PromptCaretMotionCoordinator()
  @State private var promptInsertionAnchor = PromptInsertionAnchor()
  @State private var mode: TestMode = .time
  @State private var language: TypingLanguage = .english
  @State private var polyglotReturnLanguage: TypingLanguage?
  @State private var mixedLanguageComponents = TypingLanguage.referenceDefaultMixedComponents
  @State private var mixedLanguageSearch = ""
  @State private var contentOptions = ContentOptions()
  @State private var duration = 30
  @State private var wordLimit = TypebarTestParameterMemory.defaults.wordLimit
  @State private var selectedQuoteID = OfflineContent.quotes(for: .english)[0].id
  @State private var quoteLengths = TypebarInitialTestSelection.configuration.effectiveQuoteLengths
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
  @State private var customTextSource: CustomTextSource?
  @State private var customTextStateSaveFailed = false
  @State private var customTextRecovery = CustomTextRecoveryState()
  @State private var customTextCompletion: CustomTextCompletion = .finish
  @State private var customTextDuration = 30
  @State private var customTextWordLimit = 25
  @State private var customTextSectionLimit = 1
  @State private var customTextOrdering: CustomTextOrdering = .inOrder
  @State private var customTextPipeDelimiter: Bool?
  @State private var activeLongSavedText: ActiveLongSavedText?
  @State private var activeVerifiedScript: ReferenceScriptChallengePolicy.VerifiedScript?
  @State private var customWordDurationSelection = CustomWordDurationSelection()
  @State private var activeSessionTags: [String] = []
  @State private var activeResultTagDraft = ""
  @State private var wordPractice: WordPracticeTransition?
  @State private var showingHistory = false
  @State private var showingWeakSpots = false
  @State private var showingPresets = false
  @State private var showingDataMigration = false
  @State private var showingSavedTexts = false
  @State private var showingSaveCustomText = false
  @State private var showingWordFilter = false
  @State private var showingCustomTextGenerator = false
  @State private var completedResult: CompletedResultPresentation?
  private var websiteCompletedResult: CompletedResultPresentation? {
    guard pageSessionStore.ownsConfigurationSelection, let result = completedResult,
      result.websiteAttemptID == session.automaticInputAttemptID else { return nil }
    return result
  }
  private var legacyCompletedResult: Binding<CompletedResultPresentation?> {
    .init(get: {
      guard !pageSessionStore.ownsConfigurationSelection, completedResult?.websiteAttemptID == nil else { return nil }
      return completedResult
    }, set: { value in
      // A late dismissal of an older sheet cannot erase a new page result.
      if completedResult?.websiteAttemptID == nil { completedResult = value }
    })
  }
  @State private var usesNoStressResultPresentation = false
  @State private var localResultSaveState: LocalResultSaveState = .notRequested
  @State private var savedResultRecord: TestResultRecord?
  @State private var publicationState: ResultPublicationState = .idle
  @State private var publicationResultID: UUID?
  @State private var pendingPublications = PendingResultPublicationStore()
  @State private var signedOutResultClaimStore = SignedOutResultClaimStore()
  @State private var signedOutResultClaimSheetState: SignedOutResultClaimSheetState?
  @State private var isRetryingPendingPublications = false
  @State private var terminalNotice: TestTerminalNotice?
  @State private var bailoutConfirmationMessage: String?
  @State private var quickRestartProtectionMessage: String?
  @State private var quickRestartProtectionSequence = 0
  @State private var showingSync = false
  @State private var syncInitialLeaderboard: RemoteLeaderboardSelection?
  @State private var showingConnections = false
  @State private var showingNotifications = false
  @State private var showingLocalNoticeHistory = false
  @State private var showingRewardInbox = false
  @State private var unreadNotificationCount: Int?
  @State private var showingCommandPalette = false
  @State private var themeQuickPickerScope: ThemeQuickPickerScope?
  @State private var themeQuickSwitchMessage: String?
  @State private var commandThemePreviewTarget: ThemeCommandTarget?
  @State private var commandFontPreview = FontFamilyCommandPreviewState()
  @State private var quickPickerThemePreviewTarget: ThemeCommandTarget?
  @State private var showingProfileSearchCommandEditor = false
  @State private var sharedProfileInbox = SharedProfileLinkInbox()
  @State private var testSettingsInbox = TestSettingsLinkInbox()
  @State private var sharedProfileWindow = SharedProfileWindowHost()
  private var preferenceConfigurationOwner: UUID { pageSessionStore.owner }
  @State private var showingActiveResultTagEditor = false
  @State private var showingFontFamilyNameCommandEditor = false
  @State private var showingInstalledFontCommandPicker = false
  @State private var installedFontCommandFamilies: [String] = []
  @State private var showingLocalFontCommandImporter = false
  @State private var fontFamilyCommandMessage: String?
  @State private var customBackgroundCommandEditorKind: CustomBackgroundCommandEditorKind?
  @State private var showingCustomBackgroundCommandImporter = false
  @State private var customBackgroundCommandMessage: String?
  @State private var showingPaceGuideSpeedEditor = false
  @State private var showingKeyboardGuideScaleEditor = false
  @State private var showingCustomTimeEditor = false
  @State private var showingCustomWordsEditor = false
  @State private var showingCustomTextTimeEditor = false
  @State private var showingCustomTextWordsEditor = false
  @State private var showingCustomTextSectionsEditor = false
  @State private var practiceThresholdEditorKind: PracticeThresholdEditorKind?
  @State private var showingCommandBailoutConfirmation = false
  @State private var showingTestShare = false
  @State private var settingsJSONCommand: SettingsJSONCommandPresentation?
  @State private var ownedConfigClipboardExport = WebsiteConfigClipboardExport()
  private var websiteConfigClipboardExport: WebsiteConfigClipboardExport {
    providedConfigClipboardExport ?? ownedConfigClipboardExport
  }
  @State private var showingWebsiteConfigImport = false
  @State private var websiteSequenceCommand: WebsiteSequenceCommandPresentation?
  @State private var queuedWebsiteSequenceCommand: WebsiteSequenceCommandPresentation?
  @State private var websiteThresholdCommand: WebsiteThresholdCommandPresentation?
  @State private var queuedWebsiteThresholdCommand: WebsiteThresholdCommandPresentation?
  @State private var websiteThresholdCommandTask: Task<Void, Never>?
  @State private var websiteThresholdCommandRequest = UUID()
  @State private var websiteBehaviorCommandTask: Task<Void, Never>?
  @State private var websiteBehaviorCommandRequest = UUID()
  @State private var websiteImportWorkflow: WebsiteConfigImportWorkflow?
  @State private var websiteFunboxCommandTask: Task<Void, Never>?
  @State private var websiteLiveSourceRecoveryTask: Task<Void, Never>?
  @State private var websiteLiveSourceRecoveryRequest = UUID()
  @State private var websiteFunboxCommandRequest = UUID()
  @State private var showingChallenges = false
  @State private var showingOneHandedChallengeSetup = false
  @State private var queuedOneHandedChallengeSetup = false
  @State private var showingReferenceScriptImport = false
  @State private var queuedReferenceScriptImport = false
  @State private var pendingReferenceScriptChallenge: TypebarChallenge?
  @State private var referenceScriptMessage: String?
  @State private var showsVirtualKeyboard = false
  @State private var activeChallengeID: String?
  @State private var challengeLiveConfiguration = ChallengeLiveConfigurationState()
  @State private var oneHandedChallengePreset: SavedTestPreset?
  @State private var oneHandedChallengeSelection: OneHandedChallengeSelection?
  @State private var wingdingsFontStayedAvailable = true
  @State private var focusRequest = 0
  @State private var inputHasFocus = false
  @State private var visualFocus = TypingVisualFocus()
  @State private var typingWindowHasFocus = true
  @State private var typingWindowFocusTracker = TypingWindowFocusTracker()
  @State private var focusWarningDelayElapsed = false
  @State private var focusWarningSequence = 0
  @State private var capsLockEnabled = false
  @State private var lastTimeWarningSecond: Int?
  @State private var lastClockTickSecond = 0
  @State private var liveStatsClockSignal = LiveStatsClockSignal()
  @State private var timerHealth = TimerHealthState()
  @State private var promptInputWrapLayout = PromptInputWrapLayout()
  @State private var viewportFallbackPosition = PromptViewportFallbackPosition()
  @State private var restartLockMessage: String?
  @State private var modeCompatibilityMessage: String?
  @State private var funboxConfigurationMessage: String?
  @State private var restoringPromptHighlightAfterFunboxConflict = false
  private var priorAttemptLedger: PriorAttemptLedger {
    get { pageSession.priorAttemptLedger }
    nonmutating set { pageSession.priorAttemptLedger = newValue }
  }
  @State private var weakSpotScores = WeakSpotScores()
  @State private var wordDecorationState = PoolWordDecorationState()
  @State private var lastFinishedWpm: Double?
  @State private var currentProcessPractice: [CurrentProcessPractice] = []
  @State private var isSamePromptRepeatAttempt = false
  @State private var isRepeatedPaceAttempt = false
  @State private var activePaceTargetWpm: Double?
  @State private var compositionText = ""
  @State private var automaticInputScheduler = TypingAutomaticInputScheduler()
  @State private var keyboardGuideFeedback: KeyboardGuideFeedback?
  @State private var keyboardGuideFeedbackSequence = 0
  @State private var websiteKeymapFeedback = WebsiteKeymapFeedbackStore()
  @State private var keyboardModifierFlags: NSEvent.ModifierFlags = []
  @State private var konamiSequenceTracker = KonamiSequenceTracker()
  @State private var typingCompanionHands = TypingCompanionHands()
  @State private var typingPowerParticles: [TypingPowerParticle] = []
  @State private var typingPowerGeneration = 0
  @State private var typingPowerShakeOffset = CGSize.zero
  @State private var liveContentRequestID = UUID()
  @State private var liveContentTask: Task<Void, Never>?
  @State private var liveContentTaskID = UUID()
  @State private var liveContentStreamingActive = false
  @State private var isLoadingLiveContent = false
  @State private var liveContentMessage: String?
  @State private var wholePreviewTask = WholePreviewPreparationTask()
  @State private var isPreparingWholePreview = false
  @State private var viewportReadinessAttemptID: UUID?
  @State private var preparedWholePreviewRendering: PreparedWholePreviewPresentation?
  @State private var wholePreviewFieldWidth: CGFloat?
  @State private var viewportFallbackAttemptID: UUID?
  @State private var interruptedWholePreview = false
  @State private var zipfNotice: String?
  @State private var zipfNoticeGeneration = 0
  @State private var showsNetworkRecoveryNotice = false
  @State private var didRestoreActiveTestSelection = false
  @State private var restoringLockedLayoutFluidSelection = false

  private var practiceLayout: some View {
    VStack(spacing: 30) {
      header
      RemoteAnnouncementBannerStack(center: announcements)
      if startupBlocksPractice {
        WebsiteConfigStartupNotice(state: pageSessionStore.startupController.state,
          recover: openWebsiteConfigImport,
          continueUsingLegacy: { pageSessionStore.startupController.continueUsingLegacy() })
      }
      if pageSessionStore.isReturningToTypebarSettings {
        VStack(alignment: .leading, spacing: 8) {
          Label("Typebar 设置尚未生成新的练习。请检查设置后重试，或恢复保存的完整配置。",
            systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
          Button("打开配置面板…", action: openWebsiteConfigImport)
        }.font(.callout)
      }
      if !visualFocus.isFocused && !(pageSessionStore.ownsConfigurationSelection && session.isFinished) {
        configurationPanel
      }
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
      WebsiteConfigInitializationRegion(message: pageSession.savedApplication != nil
        ? "配置已保存，练习尚未准备完成。请在配置面板恢复，或切回 Typebar 设置。"
        : pageSessionStore.restartController?.exhaustedMessage,
        retry: {
          if pageSession.savedApplication != nil { openWebsiteConfigImport() }
          else { requestPublishedRestart() }
        }) {
        if pageSessionStore.ownsConfigurationSelection && session.isFinished {
          if let result = websiteCompletedResult {
            completedResultContent(result, inline: true)
              .id(result.id)
              .modelContainer(modelContext.container)
              .accessibilityIdentifier("website-practice-result")
              .safeAreaInset(edge: .bottom) {
                if let message = pageSessionStore.restartController?.message {
                  Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange).padding()
                }
              }
          } else {
            Text(session.outcome.statusText(saveState: localResultSaveState, eligibility: nil))
            if let notice = session.generationNotice {
              Label(notice, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            controls
            practiceKeyTips
          }
        } else {
          typingPanel
          stats
          if effectiveKeyboardGuideMode != .off {
            KeyboardGuide(
              nextCharacter: session.nextExpectedCharacter, mode: effectiveKeyboardGuideMode,
              feedback: keyboardGuideFeedback, accent: activeTheme.accent,
              panel: activeTheme.panel, layout: effectiveKeyboardLayout,
              overrideRows: effectiveKeyboardGuideOverrideRows,
              overrideThumbKeys: publishedKeyboardGuideThumbKeys,
              websiteFeedback: committedPracticeDraft == nil ? nil : websiteKeymapFeedback,
              websitePalette: committedPracticeDraft == nil ? nil : .init(accent: activeTheme.accent,
                panel: activeTheme.panel, background: activeTheme.background,
                secondary: activeTheme.secondaryText, error: activeTheme.error),
              websiteHighlight: committedPracticeDraft == nil ? nil : .init(units: session.websiteKeymapHighlightUnits),
              mirrored: committedPracticeDraft == nil && session.configuration.modifiers.contains(.mirrorKeyboard),
              scale: practiceKeyboardGuide.scale, legendStyle: practiceKeyboardGuide.legendStyle,
              keysMode: practiceKeyboardGuide.keysMode,
              style: practiceKeyboardGuide.style,
              modifierFlags: keyboardModifierFlags, capsLockEnabled: capsLockEnabled)
          }
          if showsVirtualKeyboard {
            VirtualKeyboard(
              layout: effectiveKeyboardLayout,
              overrideRows: effectiveKeyboardGuideOverrideRows,
              overrideThumbKeys: publishedKeyboardGuideThumbKeys,
              nextCharacter: session.nextExpectedCharacter,
              accent: activeTheme.accent, panel: activeTheme.panel,
              allowsNewline: session.acceptsNewlineInput,
              allowsTab: session.acceptsTabInput,
              isEnabled: !session.isFinished && !isPreparingPracticePrompt,
              onInsert: {
                handleInsertedText($0, forceError: false, origin: .virtualKeyboard)
              },
              onDelete: { handleDeletedText(deletesWord: false) })
          }
          controls
          practiceKeyTips
        }
      }
    }
    .padding(42)
    .fixedSize(horizontal: false, vertical: showsAllPracticeLines)
    // One keyboard receiver survives active, terminal and restart-transition
    // visuals; replacing this NSView would lose responder/producer ownership.
    .background(alignment: .topLeading) { practiceInput }
    .background(
      WindowCloseConfirmationBridge(
        requiresConfirmation: LongTestCloseProtectionPolicy.requiresConfirmation(
          for: session, savedLongText: hasLockedCustomTextSource))
    )
    .background(
      TypingMusicPracticeScopeBridge(
        isPracticePage: !(showingHistory || showingWeakSpots || showingSync || showingConnections))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    )
    .background(TypingVisualFocusMouseBridge(onMovement: { x, y in
      visualFocus.mouseMoved(x: x, y: y)
    }).accessibilityHidden(true))
    .overlay(alignment: .top) {
      if network.showsOfflineBanner, !session.hasStarted {
        NetworkConnectivityNotice(kind: .offline)
          .padding(.top, 12)
      } else if showsNetworkRecoveryNotice, network.status == .online {
        NetworkConnectivityNotice(kind: .restored)
          .padding(.top, 12)
      }
    }
    .overlay(alignment: .topTrailing) {
      LocalNoticeStack(center: account.localNotices,
        focused: visualFocus.isFocused)
        .padding(12)
    }
    .tint(activeTheme.accent)
    .preferredColorScheme(publishedPresentation?.appearance.theme.colorScheme ?? themePreviewPresentation.preferredColorScheme)
  }

  private var appearanceObservedPracticeLayout: some View {
    practiceLayout
    .onChange(of: systemColorScheme) { _, scheme in
      _ = publishedPresentation?.updateSystemAppearance(isDark: scheme == .dark)
    }
  }

  private var focusedPracticeContent: some View {
    appearanceObservedPracticeLayout
    .focusedSceneValue(\.openCommandPalette) { showingCommandPalette = true }
    .onChange(of: showingCommandPalette) { _, showing in
      if showing { visualFocus.retire() }
      else { clearCommandFontPreview() }
    }
    .onChange(of: settings.practiceFontApplicationRevision) { _, _ in commandFontPreview.appliedFontFamily() }
    .onChange(of: settings.localPracticeFontRevision) { _, _ in commandFontPreview.appliedFontFamily() }
    .onChange(of: session.configuration.language) { _, _ in commandFontPreview.appliedFontFamily() }
    .onChange(of: activeChallengeID) { _, _ in commandFontPreview.appliedFontFamily() }
    .onChange(of: session.hasStarted) { _, started in
      if started {
        if preparedWholePreviewRendering?.typedSnapshot != session.typed {
          preparedWholePreviewRendering = nil
        }
        if !session.isFinished { visualFocus.set(true) }
      }
    }
    .onChange(of: session.completedWordCount) { previous, current in
      if current > previous { prefetchLiveContentIfNeeded(allowsGeneration: true) }
    }
    .onChange(of: settings.globalHotkeyEnabled) { _, enabled in hotkey.setEnabled(enabled) }
    .onChange(of: settings.paceGuideMode) { _, _ in refreshPaceTarget() }
    .onChange(of: account.accountTagRevision) { _, _ in
      if !session.hasStarted, settings.paceGuideMode == .accountTagPersonalBest { refreshPaceTarget() }
    }
    .onChange(of: account.resultPublicationScope) { _, _ in
      if settings.paceGuideMode == .accountTagPersonalBest { refreshPaceTarget() }
    }
    .onChange(of: settings.inputRules, handleInputRuleChange)
    .onChange(of: settings.smoothCaretMotion) { _, _ in visualFocus.startCaretBlinking() }
    .onChange(of: committedPracticeDraft?.presentation.smoothCaretMotion) { _, _ in visualFocus.startCaretBlinking() }
    .onChange(of: session.paceCaretTargetWpm) { _, value in
      if committedPracticeDraft != nil { activePaceTargetWpm = value }
    }
  }

  private var challengeObservedPracticeContent: some View {
    focusedPracticeContent
    .onChange(of: settings.difficultyApplicationRevision) { _, revision in
      handleChallengeFieldApplication(.difficulty, revision: revision)
    }
    .onChange(of: settings.testModifiersApplicationRevision) { _, revision in
      handleChallengeFieldApplication(.modifiers, revision: revision)
    }
    .onChange(of: settings.practiceFontApplicationRevision) { _, revision in
      handleChallengeFieldApplication(.font, revision: revision)
    }
    .onChange(of: settings.keyboardGuideApplicationRevision) { _, revision in
      handleChallengeFieldApplication(.keyboardGuide, revision: revision)
    }
    .onChange(of: settings.challengePresentationApplicationRevision) { _, revision in
      handleChallengeFieldApplication(.presentation, revision: revision)
    }
  }

  private var configuredPracticeContent: some View {
    challengeObservedPracticeContent
    .onChange(of: settings.paceCaretStyle) { _, _ in
      // Native style-only conditions remain distinct from the reference pace mode.
      if activeChallenge?.requirements.configuration?.paceCaretStyle != nil { activeChallengeID = nil }
    }
    .onChange(of: settings.promptHighlightMode) { previous, selected in
      if restoringPromptHighlightAfterFunboxConflict {
        restoringPromptHighlightAfterFunboxConflict = false
        return
      }
      guard settings.promptHighlightWasInteractivelyAdmitted
        || FunboxForcedContentOptionsPolicy.accepts(
        promptHighlightMode: selected, modifiers: practiceRequestedModifiers)
      else {
        restoringPromptHighlightAfterFunboxConflict = true
        settings.promptHighlightMode = previous
        funboxConfigurationMessage = "当前趣味模式仅支持“当前字符”或“关闭”提示高亮。"
        return
      }
      funboxConfigurationMessage = nil
      session.refreshPromptPresentation()
      activeChallengeID = nil
    }
    .onChange(of: settings.showAllPracticeLines) { _, _ in
      if isPreparingPracticePrompt { reset() }
    }
    .onChange(of: settings.practiceTapeMode) { _, _ in
      if isPreparingPracticePrompt { reset() }
    }
    .onChange(of: settings.layoutFluidLayouts, handleLayoutFluidSelectionChange)
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
    .onChange(of: practiceSoundSelection) { _, selection in
      if committedPracticeDraft != nil { _ = practiceSoundPlayer() }
      else { websiteSoundOutput?.stop(); websiteSoundOutput = nil }
    }
    .modifier(
      NoQuitConfigurationLockSynchronizer(
        session: session, settings: settings, ownerID: noQuitConfigurationLockOwnerID))
  }

  private var sharedProfilePresentationAllowed: Bool {
    settings.allowsRestartingConfigurationChange && sharedProfileWindow.canPresent
      && sharedProfileInbox.presented == nil && testSettingsInbox.presented == nil
      && !showingTestShare && !showingOneHandedChallengeSetup && !showingReferenceScriptImport
  }

  private func presentSharedProfileIfPossible() {
    testSettingsInbox.presentNext(allowed: sharedProfilePresentationAllowed)
    sharedProfileInbox.presentNext(allowed: sharedProfilePresentationAllowed)
  }

  private var lifecycleContent: some View {
    configuredPracticeContent
    .onChange(of: incomingPublishedPresentation?.publication.applicationID, initial: true) { _, _ in
      consumePublishedPractice()
    }
    .onChange(of: pageSession.practice?.session.automaticInputAttemptID, initial: true) { _, _ in
      finalizePublishedPracticeInstallation()
    }
    .onChange(of: websiteConfigStartup) { _, _ in updateConfigurationStartup() }
    .onChange(of: settings.preferenceConfigurationSaves.captureLease()) { _, _ in updateConfigurationStartup() }
    .onChange(of: pageSession.restartDepartureAttemptID) { _, departure in
      guard departure == session.automaticInputAttemptID else { return }
      completedResult = nil; compositionText = ""; terminalNotice = nil
      wholePreviewTask.cancel(); liveContentTask?.cancel()
      automaticInputScheduler.cancel(); NativeSpeech.shared.stop()
    }
    .background(SharedProfileWindowProbe(host: sharedProfileWindow, didAttach: {
      activatePreferenceConfigurationOwnerIfKey()
      presentSharedProfileIfPossible()
    })
      .frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true))
    .onOpenURL { url in
      if testSettingsInbox.receive(url, allowed: sharedProfilePresentationAllowed) { return }
      sharedProfileInbox.receive(url, allowed: sharedProfilePresentationAllowed)
    }
    .onChange(of: settings.allowsRestartingConfigurationChange) { presentSharedProfileIfPossible() }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification)) { notification in
      guard notification.object as? NSWindow === sharedProfileWindow.window else { return }
      Task { @MainActor in
        await Task.yield()
        presentSharedProfileIfPossible()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
      guard notification.object as? NSWindow === sharedProfileWindow.window else { return }
      settings.preferenceConfigurationSaves.activate(owner: preferenceConfigurationOwner)
      presentSharedProfileIfPossible()
    }
    .task { await runClock() }
    .task(id: pendingPublicationRetryTrigger) { retryPendingPublicationsIfPossible() }
    .task(id: account.resultPublicationScope) {
      presentSignedOutResultClaimIfPossible()
      await account.refreshAccountTagsForPractice()
    }
    .onChange(of: savedResults.map(\.id)) { _, _ in
      presentSignedOutResultClaimIfPossible()
    }
    .task(id: account.currentUser?.id) { await refreshNotificationSummary() }
    .onAppear {
      visualFocus.onWillCommit = { [weak position = viewportFallbackPosition] in
        position?.captureForFocusChange()
      }
      contentAppeared()
      settings.preferenceConfigurationSaves.register(owner: preferenceConfigurationOwner,
        requestedModifiers: { practiceRequestedModifiers },
        selectedLanguage: { committedPracticeDraft?.testParameters.language ?? language },
        keyboardGuideMode: { committedPracticeDraft?.keyboardTypography.guideMode ?? challengeLiveConfiguration.keyboardGuideMode(settings: settings) },
        fontFamilyName: { committedPracticeDraft?.keyboardTypography.fontFamily ?? challengeLiveConfiguration.fontFamilyName(settings: settings) }) {
        persistExplicitTestConfiguration()
      }
      activatePreferenceConfigurationOwnerIfKey()
      pageSessionStore.attach(to: settings.preferenceConfigurationSaves)
      pageSessionStore.bindPaceStyleSettings(settings)
      pageSessionStore.bindTypebarSettingsAction { try returnToTypebarSettings() }
      updateConfigurationStartup()
    }
    .onDisappear {
      websiteThresholdCommandRequest = UUID(); websiteThresholdCommandTask?.cancel(); websiteThresholdCommandTask = nil
      websiteSoundOutput?.stop(); websiteSoundOutput = nil
      websiteBehaviorCommandRequest = UUID(); websiteBehaviorCommandTask?.cancel(); websiteBehaviorCommandTask = nil
      websiteLiveSourceRecoveryRequest = UUID()
      websiteLiveSourceRecoveryTask?.cancel(); websiteLiveSourceRecoveryTask = nil
      pageSessionStore.detach()
      websiteImportWorkflow?.stop(); websiteImportWorkflow = nil
      websiteFunboxCommandRequest = UUID(); websiteFunboxCommandTask?.cancel(); websiteFunboxCommandTask = nil
      settings.preferenceConfigurationSaves.remove(owner: preferenceConfigurationOwner)
      visualFocus.onWillCommit = nil
      interruptedWholePreview = interruptedWholePreview || isPreparingPracticePrompt
      wholePreviewTask.cancel()
      isPreparingWholePreview = false
      viewportReadinessAttemptID = nil
      preparedWholePreviewRendering = nil
      liveContentStreamingActive = false
      liveContentTask?.cancel()
      liveContentTask = nil
      liveContentRequestID = UUID()
      isLoadingLiveContent = false
      visualFocus.retire()
      automaticInputScheduler.cancel()
      session.cancelAutomaticInput()
    }
    .onChange(of: settings.activeTestSelectionGeneration) { _, _ in
      restorePersistedTestSelection(explicitSelectionImport: true)
    }
    .onChange(of: session.outcome) { previousOutcome, outcome in
      if outcome != .active {
        wholePreviewTask.cancel()
        isPreparingWholePreview = false
        viewportReadinessAttemptID = nil
        liveContentTask?.cancel()
        liveContentTask = nil
        liveContentStreamingActive = false
        isLoadingLiveContent = false
      }
      if outcome != .active { visualFocus.retire() }
      practiceSoundSelection.playFinish(previous: previousOutcome, outcome: outcome, started: session.hasStarted,
        on: practiceSoundPlayer())
      defer {
        if outcome != .active { timerHealth = .init() }
      }
      switch outcome {
      case .completed, .failed, .bailedOut, .invalidAFK:
        guard ResultPresentationPolicy.shouldPresent(outcome: outcome) else { return }
        let resultPriorAttemptLedger = priorAttemptLedger
        let failureReason = session.failureReason
        if activeChallengeID != nil,
          !challengeLiveConfiguration.isQualificationCurrent(settings: settings) {
          activeChallengeID = nil
        }
        let challengePresentation = activeChallengeID == nil
          ? nil
          : ChallengePresentationSnapshot(
            liveSpeedStyle: settings.liveSpeedStyle,
            paceCaretStyle: settings.paceCaretStyle,
            tapeMode: settings.practiceTapeMode,
            layoutFluidLayouts: session.configuration.modifiers.contains(.layoutFluid)
              ? LayoutFluidPolicy.normalizedLayouts(settings.layoutFluidLayouts) : nil,
            virtualKeyboardOnly: activeChallengeID == "mouse-warrior"
              ? session.hasUsedOnlyVirtualKeyboard : nil,
            fontFamily: activeChallengeID == "ten-words-of-pain"
              ? WingdingsChallengeFont.resolve(size: 12)?.familyName : nil,
            keyboardGuideMode: activeChallengeID == "ten-words-of-pain"
              ? effectiveKeyboardGuideMode : nil,
            fontStayedAvailable: activeChallengeID == "ten-words-of-pain"
              ? wingdingsFontStayedAvailable : nil,
            oneHandedSelection: activeChallengeID == "one-handed-bandit"
              ? oneHandedChallengeSelection : nil,
            completedWords: activeChallengeID == "one-handed-bandit"
              ? session.completedWordCount : nil,
            paceGuideMode: settings.paceGuideMode)
        guard var result = session.result(
          tags: activeSessionTags,
          restartCount: resultPriorAttemptLedger.restartCount,
          priorAttemptEngagedDuration: resultPriorAttemptLedger.priorAttemptEngagedDuration,
          incompletePractice: resultPriorAttemptLedger.incompletePractice,
          quoteSource: activeQuoteSource,
          challengePresentation: challengePresentation
        ) else { return }
        result.accountTagSnapshot = account.captureCompletedResultTags()
        let updatedLongTextProgress = updateLongSavedTextProgress(for: result.outcome)
        lastFinishedWpm = LastTestPacePolicy.updatedWpm(
          previousWpm: lastFinishedWpm,
          candidateWpm: result.preciseWpm,
          outcome: result.outcome,
          isPaceRepeat: isRepeatedPaceAttempt)
        let eligibility = ResultEligibilityPolicy.assessment(
          for: result, samePromptRepeat: isSamePromptRepeatAttempt,
          allowsReducedAccuracyThreshold: account.currentUser?.leaderboardOptedOut == true)
        let savesResult = ResultSavingPolicy.shouldPersist(
          outcome: result.outcome, enabled: savesCurrentPracticeResults, eligibility: eligibility)
        let accountTagCompletionFeedback = account.recordAccountTagCompletion(result, eligibility: eligibility,
          at: Int64(floor(Date().timeIntervalSince1970 * 1000)))
        let resultPersonalBestFeedback = savesResult
          ? personalBestLedgers.first?.ledger?.feedback(for: result)
          : nil
        let tagPersonalBestFeedback = savesResult
          ? personalBestLedgers.first?.ledger?.tagFeedback(for: result) ?? []
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
        if CurrentProcessPracticePolicy.shouldRecord(outcome: result.outcome) {
          currentProcessPractice.append(.init(result: result))
        }
        if result.outcome == .completed {
          settings.randomizeTheme(for: systemColorScheme)
        }
        if savesResult {
          saveCompletedResultLocally(result)
        } else {
          priorAttemptLedger.recordTerminalAttempt(
            engagedDuration: result.engagedDuration, outcome: result.outcome, eligibility: eligibility,
            savingEnabled: savesCurrentPracticeResults,
            samePromptRepeat: isSamePromptRepeatAttempt && result.configuration.mode != .quote,
            accuracy: result.preciseAccuracy)
        }
        let zeroSpeedFeedback = ZeroSpeedResultFeedbackPolicy.feedback(
          wpm: result.wpm, elapsedDuration: result.elapsedDuration, outcome: result.outcome)
        completedResult = .init(
          result: result,
          websiteAttemptID: committedPracticeDraft != nil ? session.automaticInputAttemptID : nil,
          suppressesCelebrationForSlowTimer: timerHealth.suppressesResultCelebration(
            configuration: session.configuration, outcome: outcome, failureReason: failureReason),
          savesResult: savesResult,
          eligibility: eligibility,
          failureReason: failureReason,
          zeroSpeedFeedback: zeroSpeedFeedback,
          quoteFeedback: activeQuoteFeedback,
          resultPersonalBestFeedback: resultPersonalBestFeedback,
          tagPersonalBestFeedback: tagPersonalBestFeedback,
          accountTagCompletionFeedback: accountTagCompletionFeedback,
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
            ? TypebarChallengeLibrary.challenge(id: activeChallengeID)
              .map { ChallengeEvaluator.evaluate(result, challenge: $0) }
            : nil
        )
        if savesResult, ResultSavingPolicy.shouldPublish(localSaveState: localResultSaveState) {
          publishIfEnabled(result)
        } else if result.outcome == .bailedOut {
          publicationResultID = nil
          let reason: String
          if case .ineligible(let invalidReason) = eligibility {
            reason = "结果无效（\(invalidReason.resultSummary)），未写入本机历史"
          } else if localResultSaveState.canRetry {
            reason = "本机保存失败，可重试；尚未写入本机历史"
          } else {
            reason = "保存已关闭，未写入本机历史"
          }
          publicationState = .notice((updatedLongTextProgress ? "长文本进度已保存；" : "")
            + "本次已中止：\(reason)，不会同步或发布；当前练习时间仍会显示。")
        } else if let reason = eligibility.invalidReason {
          publicationResultID = nil
          publicationState = .notice(reason == .inactivity
            ? "检测到结束前持续闲置；本次结果只在当前窗口显示，不会保存、本机统计、同步或发布。"
            : "本次结果无效（\(reason.resultSummary)）；结果只在当前窗口显示，不会写入本机历史、同步或发布。")
        } else if result.outcome == .invalidAFK {
          publicationResultID = nil
          publicationState = .notice(
            "检测到结束前持续闲置；本次结果只在当前窗口显示，不会保存、本机统计、同步或发布。")
        } else if result.outcome == .failed {
          publicationResultID = nil
          publicationState = .notice(
            (failureReason?.resultSummary ?? "本次测试失败") + "；结果只在当前窗口显示，不会保存、本机统计、同步或发布。")
        } else {
          publicationResultID = nil
          publicationState = .notice("练习模式：本次成绩不会保存、本机统计、同步或发布。")
        }
      case .abandoned:
        if pageSession.restartDepartureAttemptID != session.automaticInputAttemptID {
          terminalNotice = .abandoned
        }
      case .active:
        break
      }
    }
  }

  private var presentedContent: some View {
    @Bindable var configExport = websiteConfigClipboardExport
    return ScrollView(.vertical) {
      lifecycleContent
        .frame(maxWidth: .infinity)
    }
    .background {
      if let publishedPresentation {
        if let background = try? publishedPresentation.background(fallbackStyle: settings.practiceBackdrop,
          reduceMotion: settings.reducePracticeMotion, onFailure: account.localNotices.backgroundFailureSink()) {
          background
        } else {
          Label("完整配置背景暂不可用，请重新应用配置。", systemImage: "exclamationmark.triangle")
        }
      } else {
        CustomPracticeBackground(
          fallbackStyle: settings.practiceBackdrop, theme: activeTheme,
          reduceMotion: settings.reducePracticeMotion,
          remoteURL: settings.customBackgroundURL, fit: settings.customBackgroundFit,
          filter: settings.customBackgroundFilter,
          localImageRevision: settings.localBackgroundRevision,
          localBackgroundStore: settings.localBackgroundStore,
          onFailure: account.localNotices.backgroundFailureSink(),
          applicationID: settings.customBackgroundApplicationID)
      }
    }
    .modifier(PracticeAnimationFrameRate(settings: settings, timerHealth: timerHealth))
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
        guard acceptsLeavingPracticeNavigation() else { return }
        syncInitialLeaderboard = nil
        showingSync = true
      }
      Button("好友", systemImage: "person.2") {
        guard acceptsLeavingPracticeNavigation() else { return }
        showingConnections = true
      }
      Button("收件箱", systemImage: "tray") {
        guard acceptsLeavingPracticeNavigation() else { return }
        showingRewardInbox = true
      }
      Menu {
        Button("会话通知") { showingLocalNoticeHistory = true }
        Button("社交通知") { showingNotifications = true }
      } label: {
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
      ResultsHistoryView(settings: settings, currentConfiguration: configuration, account: account)
    }
    .sheet(isPresented: $showingWeakSpots) {
      WeakSpotHistoryView(
        initialLanguage: language, englishVariant: settings.englishVariant,
        onStart: startWeakSpotPractice(prompt:language:))
    }
    .sheet(isPresented: $showingPresets) {
      PresetLibraryView(currentPreset: presetDefinition) { apply($0) }
    }
    .sheet(isPresented: $showingChallenges, onDismiss: {
      if queuedOneHandedChallengeSetup {
        queuedOneHandedChallengeSetup = false
        showingOneHandedChallengeSetup = true
      }
      presentQueuedReferenceScriptImport()
    }) {
      ChallengeLibraryView(onSelect: { _ = loadChallenge($0) })
    }
    .sheet(isPresented: $showingReferenceScriptImport, onDismiss: {
      pendingReferenceScriptChallenge = nil
    }) {
      if let challenge = pendingReferenceScriptChallenge,
        let specification = challenge.requirements.referenceScriptSpecification
      {
        ReferenceScriptChallengeImportView(
          title: challenge.title, specification: specification
        ) { verified in
          startReferenceScriptChallenge(challenge, verified: verified)
        }
      }
    }
    .sheet(isPresented: $showingOneHandedChallengeSetup) {
      OneHandedChallengeSetupView { preset, selection in
        var selected = preset
        selected.configuration = selected.configuration.with(challengeID: "one-handed-bandit")
        apply(selected)
        oneHandedChallengeSelection = selection
        persistActiveTestSelection()
      }
    }
    .sheet(isPresented: $showingDataMigration) {
      ArchiveManagementView(settings: settings)
    }
    .sheet(isPresented: $showingSync, onDismiss: { syncInitialLeaderboard = nil }) {
      CloudSyncView(
        settings: settings, account: account, initialLeaderboard: syncInitialLeaderboard)
    }
    .sheet(isPresented: $showingConnections) {
            ConnectionsView(account: account, settings: settings)
    }
    .sheet(isPresented: $showingNotifications, onDismiss: {
      Task { await refreshNotificationSummary() }
    }) {
      NotificationsView(account: account) { unreadNotificationCount = $0 }
    }
    .sheet(isPresented: $showingRewardInbox) { RewardInboxView(account:account) }
    .sheet(isPresented: $showingLocalNoticeHistory) { LocalNoticeHistoryView(center: account.localNotices) }
    .sheet(item: $signedOutResultClaimSheetState) { state in
      SignedOutResultClaimView(
        result: state.result,
        onKeepLocal: keepSignedOutResultLocally,
        onUpload: { try await uploadSignedOutResultClaim(state.result) }
      )
    }
    .sheet(isPresented: $showingCommandPalette, onDismiss: {
      commandThemePreviewTarget = nil
      clearCommandFontPreview()
      presentQueuedReferenceScriptImport()
      if let queued = queuedWebsiteSequenceCommand {
        queuedWebsiteSequenceCommand = nil
        if pageSession.presentation?.publication.applicationID == queued.id {
          websiteSequenceCommand = queued
        }
      }
      if let queued = queuedWebsiteThresholdCommand {
        queuedWebsiteThresholdCommand = nil
        if pageSession.presentation?.publication.applicationID == queued.id { websiteThresholdCommand = queued }
      }
      if let queued = queuedWebsiteSoundVolume {
        queuedWebsiteSoundVolume = nil
        if pageSession.presentation?.publication.applicationID == queued.id { websiteSoundVolume = queued }
      }
      if let queued = queuedWebsitePaceSpeed {
        queuedWebsitePaceSpeed = nil
        if pageSession.presentation?.publication.applicationID == queued.id { websitePaceSpeed = queued }
      }
      if let queued = queuedWebsiteKeymapSize {
        queuedWebsiteKeymapSize = nil
        if pageSession.presentation?.publication.applicationID == queued.id { websiteKeymapSize = queued }
      }
    }) {
      CommandPaletteView(
        items: commandPaletteItems, listMode: practiceCommandPaletteListMode,
        onSelect: runCommand,
        onPreview: { item in
          commandThemePreviewTarget = ThemeCommandPreviewPolicy.target(for: item)
          commandFontPreview.select(item, savedFont: settings.practiceFont,
            savedName: commandFontFamilyName)
          if committedPracticeDraft != nil, let item, let target = SoundCommandCatalog.target(for: item.id) {
            practiceSoundSelection.hover(target, on: practiceSoundPlayer())
          }
        })
    }
    .sheet(item: $themeQuickPickerScope, onDismiss: { quickPickerThemePreviewTarget = nil }) { scope in
      ThemeQuickPickerView(
        scope: scope, customThemes: settings.customThemes,
        favoriteThemeIDs: settings.favoriteThemeIDs, selectedTheme: selectedThemeQuickPickerTarget,
        onSelect: applyThemeQuickPickerSelection,
        onPreview: { quickPickerThemePreviewTarget = $0 })
    }
    .sheet(isPresented: $showingProfileSearchCommandEditor) {
      ProfileSearchCommandView(account: account, settings: settings)
    }
    .sheet(item: $sharedProfileInbox.presented, onDismiss: presentSharedProfileIfPossible) { route in
      SharedProfileLinkView(route: route, account: account, settings: settings)
    }
    .sheet(isPresented: $showingActiveResultTagEditor) {
      ActiveResultTagEditor(currentTags: settings.activeResultTags) { tag in
        updateActiveResultTags { settings.activateResultTag(tag) }
      }
    }
    .sheet(isPresented: $showingFontFamilyNameCommandEditor) {
      FontFamilyNameCommandEditor(initialName: settings.installedPracticeFontName) { name in
        if FontFamilyNameCommandPolicy.apply(name, to: settings, onConfigurationSave: persistExplicitTestConfiguration) {
          fontFamilyCommandMessage = settings.hasLocalPracticeFont
            ? "已保存所选字体；本地字体文件已保留但未启用。" : nil
        }
      }
    }
    .sheet(isPresented: $showingInstalledFontCommandPicker) {
      NativeFontFamilyPicker(
        selection: Binding(
          get: { commandFontFamilyName },
          set: { name in
            if !FontFamilyCommandApplication.apply(.installedName(name), to: settings,
              onConfigurationSave: persistExplicitTestConfiguration) {
              fontFamilyCommandMessage = "此 Mac 当前无法使用所选字体。"
            }
          }),
        families: installedFontCommandFamilies)
    }
    .sheet(item: $customBackgroundCommandEditorKind) { kind in
      CustomBackgroundCommandEditor(
        kind: kind,
        initialText: CustomBackgroundCommandEditorPolicy.initialText(
          kind: kind, remoteURL: settings.customBackgroundURL,
          filter: settings.customBackgroundFilter)
      ) { value in
        if CustomBackgroundCommandEditorPolicy.apply(value, kind: kind, to: settings,
          onConfigurationSave: persistExplicitTestConfiguration) {
          customBackgroundCommandMessage = nil
        }
      }
    }
    .sheet(isPresented: $showingPaceGuideSpeedEditor) {
      PaceGuideSpeedEditor(
        unit: settings.typingSpeedUnit, initialWpm: settings.paceGuideCustomWpm
      ) { wpm in
        _ = PaceCustomSpeedPolicy.apply(wpm, to: settings, activateCustom: true, onConfigurationSave: {
          activeChallengeID = nil
          persistExplicitTestConfiguration()
        })
      }
    }
    .sheet(isPresented: $showingKeyboardGuideScaleEditor) {
      KeyboardGuideScaleEditor(initialScale: settings.keyboardGuideScale) { scale in
        _ = KeyboardGuideScalePolicy.apply(scale, to: settings, onConfigurationSave: persistExplicitTestConfiguration)
      }
    }
    .sheet(isPresented: $showingCustomTimeEditor) {
      TestLimitEditor(kind: .time, initialValue: duration) { value in
        guard selectMode(.time) else { return }
        activeChallengeID = nil
        duration = value
        reset()
      }
    }
    .sheet(isPresented: $showingCustomWordsEditor) {
      TestLimitEditor(kind: .words, initialValue: wordLimit) { value in
        guard selectMode(.words) else { return }
        activeChallengeID = nil
        wordLimit = value
        reset()
      }
    }
    .sheet(isPresented: $showingCustomTextTimeEditor) {
      TestLimitEditor(
        kind: .time, initialValue: customTextDuration,
        allowsInfinite: infiniteIncompatibleModifiers.isEmpty
      ) { value in
        guard acceptsRestartingConfigurationChange() else { return }
        customTextDuration = value
        // The finite-limit control (and its onChange) disappears when zero selects infinity.
        if value == 0 { reset() }
      }
    }
    .sheet(isPresented: $showingCustomTextWordsEditor) {
      TestLimitEditor(
        kind: .words, initialValue: customTextWordLimit,
        allowsInfinite: infiniteIncompatibleModifiers.isEmpty
      ) { value in
        guard acceptsRestartingConfigurationChange() else { return }
        customTextWordLimit = value
        // Keep the active session in sync when the finite-limit control disappears.
        if value == 0 { reset() }
      }
    }
    .sheet(isPresented: $showingCustomTextSectionsEditor) {
      TestLimitEditor(kind: .sections, initialValue: customTextSectionLimit,
        allowsInfinite: infiniteIncompatibleModifiers.isEmpty) { value in
        guard acceptsRestartingConfigurationChange() else { return }
        customTextSectionLimit = value
      }
    }
    .sheet(item: $practiceThresholdEditorKind) { kind in
      PracticeThresholdEditor(
        kind: kind, unit: settings.typingSpeedUnit,
        initialCanonicalValue: practiceThresholdValue(for: kind),
        preservesZeroMode: settings.thresholdConfiguration != nil
      ) { value in
        applyPracticeThreshold(value, kind: kind)
      }
    }
    .confirmationDialog(
      "中止当前长测试？", isPresented: $showingCommandBailoutConfirmation,
      titleVisibility: .visible
    ) {
      Button("中止并查看结果", role: .destructive) {
        synchronizeLiveInputRules()
        session.bailOut()
      }
    } message: {
      Text("符合保存资格且开启保存时，中止结果会进入本机历史；不计入 PB 或挑战，发布需服务支持中止协议并通过独立校验。")
    }
    .sheet(isPresented: $showingTestShare, onDismiss: testShareDidDismiss) {
      testShareContent()
    }
    .sheet(item: $testSettingsInbox.presented, onDismiss: testShareDidDismiss) { route in
      testShareContent(initialLink: route.link)
    }
    .sheet(isPresented: $showingWebsiteConfigImport) {
      WebsiteConfigImportView(apply: { json in
        let message = try await importWorkflow().apply(json: json, systemIsDark: systemColorScheme == .dark)
        pageSessionStore.startupController.completedManually()
        return message
      }, cancel: { websiteImportWorkflow?.cancel() },
        useTypebarSettings: { try pageSessionStore.useTypebarSettings() })
    }
    .sheet(item: $websiteSequenceCommand) { presentation in
      WebsiteSequenceCommandView(presentation: presentation,
        canApply: pageSession.presentation?.publication.applicationID == presentation.id
          && pageSession.savedApplication == nil
          && pageSession.configurationDeparture == nil
          && pageSessionStore.restartController?.isPreparing != true,
        apply: { [applicationID = presentation.id] edit in
          try await importWorkflow().editAndBegin(edit, replacing: applicationID,
            systemIsDark: systemColorScheme == .dark)
        })
    }
    .sheet(item: $websiteThresholdCommand) { presentation in
      WebsiteThresholdCommandView(presentation: presentation,
        canApply: pageSession.presentation?.publication.applicationID == presentation.id
          && pageSession.savedApplication == nil && pageSession.configurationDeparture == nil
          && pageSessionStore.restartController?.isPreparing != true,
        apply: { input in
          let result = try importWorkflow().runThresholdCommand(presentation.target, input: input, replacing: presentation.id)
          reportWebsiteThresholdCommand(result)
          return result
        })
    }
    .sheet(item: $websiteSoundVolume) { presentation in
      WebsiteSoundVolumeCommandView(presentation: presentation,
        canApply: pageSession.presentation?.publication.applicationID == presentation.id
          && pageSession.savedApplication == nil && pageSession.configurationDeparture == nil
          && pageSessionStore.restartController?.isPreparing != true,
        apply: { value in
          try await importWorkflow().editAndBegin(.sound(.volume(value)), replacing: presentation.id,
            systemIsDark: systemColorScheme == .dark)
          _ = practiceSoundPlayer()
        })
    }
    .sheet(item: $websitePaceSpeed) { presentation in
      WebsitePaceSpeedCommandView(presentation: presentation,
        canApply: pageSession.presentation?.publication.applicationID == presentation.id
          && pageSession.savedApplication == nil && pageSession.configurationDeparture == nil
          && pageSessionStore.restartController?.isPreparing != true,
        apply: { raw in
          try await importWorkflow().runPaceCommand(.customSpeed, input: raw, replacing: presentation.id)
        })
    }
    .sheet(item: $websiteKeymapSize) { presentation in
      WebsiteKeymapSizeCommandView(presentation: presentation,
        canApply: pageSession.presentation?.publication.applicationID == presentation.id
          && pageSession.savedApplication == nil && pageSession.configurationDeparture == nil
          && pageSessionStore.restartController?.isPreparing != true,
        apply: { value in
          try await importWorkflow().editAndBegin(.keymap(.size(value)), replacing: presentation.id,
            systemIsDark: systemColorScheme == .dark)
        })
    }
    .sheet(item: $configExport.manualCopy) { presentation in
      WebsiteConfigManualCopyView(json: presentation.json)
    }
    .sheet(item: $settingsJSONCommand) { presentation in
      SettingsJSONCommandView(presentation: presentation) { json in
        guard acceptsRestartingConfigurationChange() else { throw SettingsJSONCommandError.configurationLocked }
        let document = try SettingsJSONCommandImport.apply(json, to: settings,
          selectionAdmission: { acceptsPresetResources($0) })
        let memory = document.testParameterMemory
        duration = memory.duration
        wordLimit = memory.wordLimit
        customTextDuration = memory.customTextDuration
        customTextWordLimit = memory.customTextWordLimit
        customTextSectionLimit = memory.customTextSectionLimit
        let configuration = document.configuration
        var retainedCustomText: String?
        if configuration.mode == .custom {
          retainedCustomText = customText
        }
        guard apply(.init(configuration: configuration, customText: retainedCustomText),
          appliesGlobalSettings: document.settings.thresholdSource == nil) else {
          throw SettingsJSONCommandError.selectionApplicationFailed
        }
      }
    }
    .sheet(isPresented: $showingSavedTexts) {
      SavedTextsView(onUse: loadSavedCustomText)
    }
    .sheet(isPresented: $showingSaveCustomText) {
      SaveCustomTextView(text: customText)
    }
    .sheet(isPresented: $showingWordFilter) {
      WordFilterView(language: language, layout: effectiveKeyboardLayout) { text, appending in
        applyGeneratedCustomText(text, appending: appending)
      }
    }
    .sheet(isPresented: $showingCustomTextGenerator) {
      CustomTextGeneratorView { text, appending in
        applyGeneratedCustomText(text, appending: appending)
      }
    }
    .fileImporter(
      isPresented: $showingCustomBackgroundCommandImporter, allowedContentTypes: [.image]
    ) { result in
      switch result {
      case .success(let url): importCustomBackgroundFromCommand(url)
      case .failure(let error): customBackgroundCommandMessage = error.localizedDescription
      }
    }
    .fileImporter(
      isPresented: $showingLocalFontCommandImporter,
      allowedContentTypes: LocalPracticeFontFilePolicy.supportedContentTypes
    ) { result in
      switch result {
      case .success(let url): importLocalFontFromCommand(url)
      case .failure(let error): fontFamilyCommandMessage = error.localizedDescription
      }
    }
    .sheet(item: legacyCompletedResult) { result in
      completedResultContent(result)
        .safeAreaInset(edge: .bottom) {
          if let message = pageSessionStore.restartController?.message {
            Label(message, systemImage: "exclamationmark.triangle")
              .font(.callout).foregroundStyle(.orange).padding()
          }
        }
        // A presentation can outlive the practice root and its environment.
        // Keep its queried context's container alive for that entire lifetime.
        .modelContainer(modelContext.container)
        .background(ResultSheetTerminationBridge()
          .frame(width: 0, height: 0).accessibilityHidden(true))
    }
    .alert(item: $terminalNotice) { notice in
      Alert(
        title: Text(notice.title),
        message: Text(notice.message),
        dismissButton: .default(Text("重新开始"), action: { reset() })
      )
    }
  }

  @ViewBuilder
  private func completedResultContent(_ result: CompletedResultPresentation, inline: Bool = false) -> some View {
    if usesNoStressResultPresentation {
      NoStressResultView(
        isNewPersonalBest: result.savesResult && result.resultPersonalBestFeedback?.isNewPersonalBest == true,
        hasZeroSpeedFeedback: result.zeroSpeedFeedback != nil,
        reducesMotion: settings.reducePracticeMotion,
        slowTimer: result.suppressesCelebrationForSlowTimer,
        accent: activeTheme.accent,
        onRestart: { [attemptID = session.automaticInputAttemptID] in
          if pageSession.practice != nil {
            guard pageSessionStore.acceptsAttemptCallback(for: attemptID) else { return }
            attemptRestart(); return
          }
          completedResult = nil
          if restoreWordPracticeIfNeeded() { return }
          attemptRestart()
        }, allowsClosing: !inline)
    } else {
      CompletedResultView(
        result: result.result,
        slowTimer: result.suppressesCelebrationForSlowTimer,
        savesResult: result.savesResult,
        eligibility: result.eligibility,
        failureReason: result.failureReason,
        zeroSpeedFeedback: result.zeroSpeedFeedback,
        typingSpeedUnit: practiceAppearance.unit,
        alwaysShowDecimalPlaces: practiceAppearance.alwaysShowDecimalPlaces,
        alwaysShowWordsHistory: committedPracticeDraft?.presentation.alwaysShowWordsHistory ?? settings.alwaysShowWordsHistory,
        commandPaletteListMode: practiceCommandPaletteListMode,
        soundConfiguration: .init(selection: practiceSoundSelection,
          player: websiteSoundOutput?.player ?? settings.practiceFeedbackSound),
        showWordBurstHeatmap: settings.showWordBurstHeatmap,
        startGraphsAtZero: practiceAppearance.startGraphsAtZero,
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
        accountTagCompletionFeedback: result.accountTagCompletionFeedback,
        settings: settings,
        account: account,
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
        onRestart: { [attemptID = session.automaticInputAttemptID] in
          if pageSession.practice != nil {
            guard pageSessionStore.acceptsAttemptCallback(for: attemptID) else { return }
            attemptRestart(); return
          }
          completedResult = nil
          if restoreWordPracticeIfNeeded() { return }
          attemptRestart()
        },
        onHistory: {
          if !inline { completedResult = nil }
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
        onRepeat: { [attemptID = session.automaticInputAttemptID] in
          if pageSession.practice != nil {
            guard pageSessionStore.acceptsAttemptCallback(for: attemptID) else { return }
            requestPublishedRestart(repeatingRequested: true); return
          }
          completedResult = nil
          activeQuoteSource = result.result.quoteSource
          startRepeatedAttempt(result.repeatedSession, tags: result.result.tags)
        },
        challengeEvaluation: result.challengeEvaluation,
        onResultPerformanceVisibilityChange: { settings.resultPerformanceVisibility = $0 },
        onResultGraphScaleChange: { value in
          if pageSessionStore.ownsConfigurationSelection { runWebsiteLiveCommand(.appearance(.startGraphsAtZero(value))) }
          else { settings.startGraphsAtZero = value }
        },
        onRetryPublication: { publishIfEnabled(result.result) },
        onRetryLocalSave: {
          saveCompletedResultLocally(result.result)
          if ResultSavingPolicy.shouldPublish(localSaveState: localResultSaveState) {
            publishIfEnabled(result.result)
          }
        },
        onOpenDailyLeaderboard: {
          if !inline { completedResult = nil }
          syncInitialLeaderboard = .init(
            mode: result.result.configuration.mode,
            language: result.result.configuration.language,
            period: .day,
            durationSeconds: result.result.configuration.mode == .time
              ? result.result.configuration.duration.map { Int($0.rounded()) }
              : nil,
            wordLimit: result.result.configuration.mode == .words
              ? result.result.configuration.wordLimit
              : nil, mode2: result.result.quoteSource?.mode2)
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
        }, isInline: inline
      )
    }
  }

  var body: some View {
    presentedContent
      .onChange(of: activeChallengeID) { _, id in handleActiveChallengeIDChange(to: id) }
  }

  private func runClock() async {
    if TimerDeliveryDiagnostics.enabled {
      TimerDeliveryDiagnostics.trace(.clockStarted,
        hasStarted: session.hasStarted, isFinished: session.isFinished)
    }
    defer {
      if TimerDeliveryDiagnostics.enabled {
        TimerDeliveryDiagnostics.trace(.clockStopped,
          hasStarted: session.hasStarted, isFinished: session.isFinished)
      }
    }
    var previousDelivery = ProcessInfo.processInfo.systemUptime
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 100_000_000)
      guard !Task.isCancelled else { return }
      let delivery = ProcessInfo.processInfo.systemUptime
      let deliveryGap = delivery - previousDelivery
      if TimerDeliveryDiagnostics.enabled {
        TimerDeliveryDiagnostics.finishRenderWindow(deliveryGap: deliveryGap)
      }
      if TimerDeliveryDiagnostics.enabled, !session.isFinished, deliveryGap > 0.25 {
        TimerDeliveryDiagnostics.trace(.lateDelivery, duration: deliveryGap,
          hasStarted: session.hasStarted, isFinished: session.isFinished)
      }
      advanceClock(at: .now, deliveryGap: deliveryGap)
      previousDelivery = delivery
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

  private func advanceClock(at now: Date, deliveryGap: TimeInterval) {
    let preflightStart = TimerDeliveryDiagnostics.enabled ? ProcessInfo.processInfo.systemUptime : 0
    synchronizeLiveInputRules()
    capsLockEnabled = NSEvent.modifierFlags.contains(.capsLock)
    verifyChallengeFontAvailability()
    let preflight = TimerDeliveryDiagnostics.enabled
      ? ProcessInfo.processInfo.systemUptime - preflightStart : 0
    // Keep native monitoring live on the result screen, but never re-deliver
    // a frozen attempt's pending seconds or timer-health failure.
    guard !session.isFinished else { return }
    if session.hasStarted {
      let elapsed = session.elapsedSeconds(at: now)
      let dueSeconds = ClockTickPolicy.dueSeconds(
        after: lastClockTickSecond, elapsed: elapsed)
      if let firstDueSecond = dueSeconds.first {
        timerHealth.observe(
          drift: elapsed - Double(firstDueSecond), configuration: session.configuration,
          animationSettingsRevision: settings.animationFrameRateRevision)
        if TimerDeliveryDiagnostics.enabled {
          let record = TimerDeliveryDiagnostics.record(deliveryGap: deliveryGap,
            preflight: preflight, elapsed: elapsed, previousSecond: lastClockTickSecond,
            firstDueSecond: firstDueSecond, severeCount: timerHealth.severeDriftCount,
            failed: timerHealth.shouldFail)
          try? FileHandle.standardError.write(contentsOf: Data(record.utf8))
        }
        if timerHealth.shouldFail {
          session.failForTimerHealth(at: now)
          return
        }
      }
      for second in dueSeconds { advanceWebsiteLayoutFluid(.time(second)) }
      if let duration = session.configuration.duration, duration > 0 {
        for elapsedSecond in dueSeconds {
          let remaining = ClockTickPolicy.remainingSeconds(
            duration: duration, elapsedSecond: elapsedSecond)
          practiceSoundSelection.playWarning(remaining: remaining, previous: lastTimeWarningSecond, on: practiceSoundPlayer())
          lastTimeWarningSecond = remaining
        }
      }
      if let lastDueSecond = dueSeconds.last {
        lastClockTickSecond = lastDueSecond
        liveStatsClockSignal.second = lastDueSecond
        session.enforceLivePracticeThresholds(at: now)
        if session.isFinished { return }
      }
    }
    if session.requiresClockTick {
      var candidate = session
      if candidate.tick(at: now) { session = candidate }
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("typebar").font(.system(size: 28, weight: .bold, design: .rounded))
        Text("离线、专注的 Mac 打字练习").foregroundStyle(.secondary)
      }
      Spacer()
      ThemeIndicatorButton(
        presentation: themeIndicatorPresentation,
        onActivate: handleThemeIndicatorActivation)
      .frame(maxWidth: 180)
      .disabled(pageSession.practice != nil)
      Picker("模式", selection: Binding(
        get: { pageSession.practice == nil ? mode : session.configuration.mode },
        set: { _ = selectMode($0) }
      )) {
        ForEach(TestMode.allCases, id: \.self) { mode in
          Text(mode.displayName).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 420)
      .disabled(activeChallenge != nil || isRestartingConfigurationChangeLocked)
      .onChange(of: mode) { _, nextMode in
        // A deliberate departure from temporary word practice becomes the
        // user's new source configuration, matching the reference reset rule.
        if nextMode != .custom { wordPractice = nil }
        reset()
      }
    }
  }

  @ViewBuilder
  private var configurationPanel: some View {
    if let pending = pageSession.savedApplication {
      VStack(alignment: .leading, spacing: 8) {
        Text("已保存，等待初始化").font(.headline)
        LabeledContent("模式", value: pending.draft.testParameters.mode.displayName)
        LabeledContent("语言", value: pending.draft.testParameters.language.displayName)
        Text("关闭或取消不会撤销已保存的配置。可恢复后继续准备练习。")
          .font(.caption).foregroundStyle(.secondary)
        Button("恢复已保存配置…", action: openWebsiteConfigImport)
        websiteConfigurationExportControl
      }
    } else if let practice = pageSession.practice {
      VStack(alignment: .leading, spacing: 7) {
        Text("本轮设置").font(.headline)
        websiteConfigurationExportControl
        LabeledContent("模式", value: session.configuration.mode.displayName)
        LabeledContent("语言", value: session.configuration.language.displayName)
        LabeledContent("难度", value: session.configuration.difficulty.rawValue)
        if let duration = session.configuration.duration { LabeledContent("时间", value: "\(duration.formatted()) 秒") }
        if let words = session.configuration.wordLimit { LabeledContent("词数", value: "\(words)") }
        if let quote = practice.quote { Text(quote.title).foregroundStyle(.secondary) }
        if let publication = pageSession.presentation?.publication {
          let departureID = pageSession.configurationDeparture?.id
          WebsiteConfigPracticeEditor(draft: publication.draft,
            canEdit: pageSessionStore.restartController?.isPreparing != true,
            recoveries: publication.quoteRecoveries,
            pendingPreparation: pageSession.configurationDeparture != nil,
            configurationWasSaved: pageSession.configurationDeparture?.configurationWasSaved ?? true,
            resume: { [departureID] in
              guard let departureID else { throw WebsiteConfigImportWorkflowError.conflict }
              return try await importWorkflow().resumeAndBegin(departureID: departureID,
                systemIsDark: systemColorScheme == .dark)
            },
            apply: { [applicationID = publication.applicationID] edit in
              try await importWorkflow().editAndBegin(edit, replacing: applicationID,
                systemIsDark: systemColorScheme == .dark)
            })
            .id(publication.applicationID)
        }
        Text("其他未提供的完整配置编辑尚待接通；可在导入面板恢复配置或切回本窗口 Typebar 设置。")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else { legacyConfigurationPanel }
  }

  @ViewBuilder
  private var websiteConfigurationExportControl: some View {
    Button("导出配置 JSON") {
      WebsiteConfigExport.copySettings(in: pageSessionStore, using: websiteConfigClipboardExport)
    }
    .accessibilityIdentifier("website-config-export")
    if let message = websiteConfigClipboardExport.message {
      Text(message).font(.caption).foregroundStyle(.secondary)
        .task(id: websiteConfigClipboardExport.noticeID) {
          let id = websiteConfigClipboardExport.noticeID
          guard let duration = websiteConfigClipboardExport.noticeDurationMilliseconds else { return }
          do { try await Task.sleep(for: .milliseconds(duration)) }
          catch { return }
          websiteConfigClipboardExport.clearNotice(id)
        }
    }
  }

  @ViewBuilder
  private var legacyConfigurationPanel: some View {
    @Bindable var settings = settings
    VStack(alignment: .leading, spacing: 14) {
      if let activeChallenge {
        VStack(alignment: .leading, spacing: 5) {
          Label(activeChallenge.title, systemImage: "flag.checkered")
            .font(.headline)
          Text(activeChallenge.requirements.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
          if activeChallenge.id == "one-handed-bandit" {
            Text("已完成 \(session.completedWordCount) / 10,000 词；倒计时和词数任一达标即结束")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
          Button("退出挑战") {
            guard acceptsRestartingConfigurationChange() else { return }
            activeChallengeID = nil
            reset()
          }
        }
        .padding(12)
        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
      } else {
        if mode != .custom && mode != .zen {
          PracticeLanguagePicker(languages: availableLanguages, selection: Binding(
            get: { language },
            set: { _ = selectLanguage($0) }
          ))
          .onChange(of: language) { _, language in
            languageChanged(to: language)
            refreshZipfNotice()
          }
          if language == .arabic {
            Toggle(
              "Arabic 快速输入（省略元音符号）",
              isOn: restartingConfigurationBinding($settings.prefersArabicLazyInput))
              .onChange(of: settings.prefersArabicLazyInput) { _, _ in reset() }
            Text("默认开启；会省略短元音、tanwin、shadda、sukun，并统一常见的 alef 变体。关闭后保留完整原创 Arabic 提示。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if BritishEnglishPolicy.supportsWordConversion(in: language) {
            Picker("英文拼写", selection: restartingConfigurationBinding($settings.englishVariant)) {
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
            Toggle("标点", isOn: Binding(
              get: { contentOptions.includePunctuation },
              set: { enabled in
                var selected = contentOptions
                selected.includePunctuation = enabled
                if selectContentOptions(selected) { reset() }
              }
            ))
            Toggle("数字", isOn: Binding(
              get: { contentOptions.includeNumbers },
              set: { enabled in
                var selected = contentOptions
                selected.includeNumbers = enabled
                if selectContentOptions(selected) { reset() }
              }
            ))
          }
        }

        if !session.configuration.modifiers.isEmpty {
          Label(
            "修饰器：\(session.configuration.modifiers.map(\.displayName).joined(separator: "、"))",
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
        if account.currentUser != nil {
          AccountTagPracticeControls(account: account, settings: settings,
            configuration: configuration, hasStarted: session.hasStarted)
        }

        if let generationNotice = session.generationNotice {
          Label(generationNotice, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let liveContentMessage {
          HStack(spacing: 7) {
            if isLoadingLiveContent { ProgressView().controlSize(.small) }
            Label(session.isWaitingForLiveContent ? "正在等待新的在线段落，倒计时继续。" : liveContentMessage,
              systemImage: "network")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        if isPreparingPracticePrompt {
          HStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text("正在准备完整练习；完成后可输入。可重新开始或切换设置取消。")
              .font(.caption).foregroundStyle(.secondary)
          }
        }

        switch mode {
        case .time:
          Toggle("无限计时", isOn: infiniteBinding($duration, fallback: 30))
            .disabled(duration != 0 && !infiniteIncompatibleModifiers.isEmpty)
          if duration == 0 {
            Text("计时器正向累计；使用 Bail Out 或双击 Shift+Enter 结束并查看结果，符合资格时保存到本机。")
              .font(.caption).foregroundStyle(.secondary)
          } else {
            HStack {
              Stepper(
                value: restartingConfigurationBinding($duration),
                in: 1...OfficialTestLimitInput.maximumValue,
                step: 1
              ) {
                LabeledContent("时长", value: "\(duration) 秒")
              }
              Button("自定义…") { showingCustomTimeEditor = true }
                .buttonStyle(.borderless)
            }
            .onChange(of: duration) { _, _ in reset() }
          }
        case .words:
          Toggle("无限字数", isOn: infiniteBinding($wordLimit, fallback: 25))
            .disabled(wordLimit != 0 && !infiniteIncompatibleModifiers.isEmpty)
          if wordLimit == 0 {
            Text("词数持续累计；使用 Bail Out 或双击 Shift+Enter 结束并查看结果，符合资格时保存到本机。")
              .font(.caption).foregroundStyle(.secondary)
          } else {
            HStack {
              Stepper(value: restartingConfigurationBinding($wordLimit), in: 1...OfficialTestLimitInput.maximumValue) {
                LabeledContent("字数", value: "\(wordLimit) 词")
              }
              Button("自定义…") { showingCustomWordsEditor = true }
                .buttonStyle(.borderless)
            }
            .onChange(of: wordLimit) { _, _ in reset() }
          }
        case .quote:
          Picker("内容来源", selection: restartingConfigurationBinding($quoteSource)) {
            ForEach(availableQuoteSources) { source in Text(source.title).tag(source) }
          }
          .pickerStyle(.segmented)
          .onChange(of: quoteSource) { _, source in
            if source == .community {
              persistActiveTestSelection()
              refreshCommunityQuotes()
              return
            }
            quoteQueue.reset()
            ensureSelectedQuote()
            reset()
          }
          Picker("引语选择", selection: restartingConfigurationBinding($quoteSelectionMode)) {
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
            TextField("搜索当前引语（仅本机）", text: restartingConfigurationBinding($quoteSearchQuery))
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
            Picker("引语", selection: restartingConfigurationBinding($selectedQuoteID)) {
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
                  guard acceptsRestartingConfigurationChange() else { return }
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
            TextField("输入你自己的练习文本", text: Binding(
              get: { customText },
              set: { value in
                wordPractice = nil
                customTextSource = nil
                customTextRecovery.acceptExplicitSource()
                customText = value
              }), axis: .vertical)
              .lineLimit(2...4)
              .font(settings.practiceFont.font(
                size: 15, installedFontName: settings.installedPracticeFontName,
                language: language))
              .disabled(hasLockedCustomTextSource)
              .onChange(of: customText) { _, value in
                let clamped = preparedCustomSections == nil ? CustomTextPolicy.clamped(value) : value
                if clamped != value { customText = clamped }
                if let activeLongSavedText,
                  value != activeLongSavedText.currentChunk
                {
                  self.activeLongSavedText = nil
                }
                if let activeVerifiedScript,
                  value != LongSavedTextProgress.nextChunk(in: activeVerifiedScript.text, after: 0)
                {
                  self.activeVerifiedScript = nil
                  activeChallengeID = nil
                }
              }
            Text(preparedCustomSections.map { "已准备文本：\($0.count) 段 · \(customText.count) 字符" }
              ?? "\(customText.count) / \(CustomTextPolicy.maximumLength) 个字符")
              .font(.caption)
              .foregroundStyle(.secondary)
            if customTextStateSaveFailed {
              Label("自定义文本未保存到本机；原有记录保持不变。", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            }
            if customTextRecovery.requiresExplicitSource {
              Label("已保存的自定义文本无法读取。请使用支持该版本的应用，或明确选择新文本；原记录未改动。",
                systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
              Button("使用新的默认文本") {
                applyGeneratedCustomText("A calm practice makes the next difficult sentence feel possible.", appending: false)
              }
            }
            if let activeLongSavedText {
              Label(
                "\(activeLongSavedText.continuous ? "连续剩余文本" : "分段继续")：\(activeLongSavedText.title) · \(LongSavedTextProgress.progressLabel(in: activeLongSavedText.text, offset: activeLongSavedText.progress))",
                systemImage: "book.closed")
                .font(.caption)
                .foregroundStyle(.secondary)
              Button("编辑文本并停止进度跟踪") { self.activeLongSavedText = nil }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            if let activeVerifiedScript {
              Label(
                "固定版本脚本：\(activeVerifiedScript.specification.fileName) · \(activeVerifiedScript.text.count) 字符",
                systemImage: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
              Button("退出脚本挑战并编辑普通文本") {
                guard acceptsRestartingConfigurationChange() else { return }
                self.activeVerifiedScript = nil
                activeChallengeID = nil
                customText = "A calm practice makes the next difficult sentence feel possible."
                reset()
              }
              .buttonStyle(.borderless)
              .font(.caption)
            }
            Picker("完成方式", selection: restartingConfigurationBinding($customTextCompletion, savesConfiguration: false)) {
              ForEach(CustomTextCompletion.allCases) { completion in
                Text(completion.displayName).tag(completion)
              }
            }
            .disabled(hasLockedCustomTextSource)
            .onChange(of: customTextCompletion) { _, _ in reset() }
            Toggle("用竖线分隔段落", isOn: Binding(
              get: { customTextPipeDelimiter ?? (customTextCompletion == .sections) },
              set: { value in
                guard acceptsRestartingConfigurationChange() else { return }
                customTextPipeDelimiter = value
                reset()
              }))
              .disabled(hasLockedCustomTextSource)
            if customTextCompletion == .time {
              Toggle("无限循环计时", isOn: infiniteBinding($customTextDuration, fallback: 30))
                .disabled(
                  hasLockedCustomTextSource
                    || (customTextDuration != 0 && !infiniteIncompatibleModifiers.isEmpty))
              if customTextDuration == 0 {
                Text("使用 Bail Out 或双击 Shift+Enter 结束并查看结果，符合资格时保存到本机。")
                  .font(.caption).foregroundStyle(.secondary)
              } else {
                HStack {
                  Stepper(
                    value: restartingConfigurationBinding($customTextDuration, savesConfiguration: false),
                    in: 1...OfficialTestLimitInput.maximumValue,
                    step: 5
                  ) {
                    LabeledContent("循环时长", value: "\(customTextDuration) 秒")
                  }
                  Button("自定义…") { showingCustomTextTimeEditor = true }
                    .buttonStyle(.borderless)
                }
                .disabled(hasLockedCustomTextSource)
                .onChange(of: customTextDuration) { _, _ in reset() }
              }
            }
            if customTextCompletion == .words {
              Toggle("无限循环字数", isOn: infiniteBinding($customTextWordLimit, fallback: 25))
                .disabled(
                  hasLockedCustomTextSource
                    || (customTextWordLimit != 0 && !infiniteIncompatibleModifiers.isEmpty))
              if customTextWordLimit == 0 {
                Text("使用 Bail Out 或双击 Shift+Enter 结束并查看结果，符合资格时保存到本机。")
                  .font(.caption).foregroundStyle(.secondary)
              } else {
                HStack {
                  Stepper(
                    value: restartingConfigurationBinding($customTextWordLimit, savesConfiguration: false),
                    in: 1...OfficialTestLimitInput.maximumValue
                  ) {
                    LabeledContent("循环字数", value: "\(customTextWordLimit) 词")
                  }
                  Button("自定义…") { showingCustomTextWordsEditor = true }
                    .buttonStyle(.borderless)
                }
                .disabled(hasLockedCustomTextSource)
                .onChange(of: customTextWordLimit) { _, _ in reset() }
              }
            }
            if customTextCompletion == .sections {
              HStack {
                if customTextSectionLimit == 0 {
                  LabeledContent("完成段数", value: "无限")
                } else {
                  Stepper(value: restartingConfigurationBinding($customTextSectionLimit, savesConfiguration: false),
                    in: 1...OfficialTestLimitInput.maximumValue) {
                    LabeledContent("完成段数", value: "\(customTextSectionLimit) 段")
                  }
                }
                Button("自定义…") { showingCustomTextSectionsEditor = true }
                  .buttonStyle(.borderless)
              }
              .disabled(hasLockedCustomTextSource)
              .onChange(of: customTextSectionLimit) { _, _ in reset() }
              Text((customTextPipeDelimiter ?? true)
                ? "使用竖线 | 分隔段落；按所选顺序循环取段，0 表示无限。"
                : "按空格分隔的每个词计一段；竖线保留为目标字符，0 表示无限。")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Picker("文本顺序", selection: restartingConfigurationBinding($customTextOrdering, savesConfiguration: false)) {
              ForEach(CustomTextOrdering.allCases) { ordering in
                Text(ordering.displayName).tag(ordering)
              }
            }
            .disabled(hasLockedCustomTextSource)
            .onChange(of: customTextOrdering) { _, _ in reset() }
            HStack {
              Button("使用这段文本开始") {
                guard acceptsRestartingConfigurationChange() else { return }
                reset()
              }
                .disabled(!CustomTextPolicy.isValid(customText, configuration: configuration))
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
      Label("本机文字标签", systemImage: "tag")
        .font(.headline)
      Text("活动标签会写入之后开始的每轮已保存成绩；只有符合 PB 资格的完成成绩可用于“活动标签个人最佳”节奏引导。")
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

  private var knownHistoricalResultTags: [String] {
    savedResults.flatMap(\.tags) + (personalBestLedgers.first?.ledger?.tagEntries.map(\.tag) ?? [])
  }

  private var inactiveKnownResultTags: [String] {
    var tags: [String] = []
    for rawTag in knownHistoricalResultTags {
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

  private var practiceInput: some View {
    NativeTypingInput(
      focusRequest: focusRequest, acceptsTextInput: !isPreparingPracticePrompt && !startupBlocksPractice
        && !pageSessionStore.isReturningToTypebarSettings
        && !pageSessionStore.isInputSuspendedForRestart
        && (publishedPresentation == nil || PromptFieldProjectionPolicy.supports(session.configuration)),
      insertionAnchor: promptInsertionAnchor,
      insertionAttemptID: session.automaticInputAttemptID,
      compositionDisplayStyle: practiceCompositionDisplayStyle,
      quickRestartKey: practiceQuickRestartKey,
      keyboardInputMapping: effectiveKeyboardInputMapping,
      keyboardInputMappingProvider: { [pageSessionStore] in
        guard pageSessionStore.ownsConfigurationSelection, pageSessionStore.state.practice != nil else { return nil }
        guard let draft = pageSessionStore.state.presentation?.publication.draft else { return nil }
        return draft.keyboardTypography.inputMapping(mirrored: draft.generators.requestedModifiers.contains(.mirrorKeyboard))
      },
      oppositeShiftKeymap: effectiveOppositeShiftKeymap,
      oppositeShiftMode: committedPracticeDraft?.inputRules.rules.oppositeShiftMode ?? settings.oppositeShiftMode,
      oppositeShiftContextProvider: { [pageSessionStore] in
        guard pageSessionStore.ownsConfigurationSelection, pageSessionStore.state.practice != nil,
          let draft = pageSessionStore.state.presentation?.publication.draft else { return nil }
        return .init(mode: draft.inputRules.rules.oppositeShiftMode,
          keymap: draft.keyboardTypography.shiftKeymap(mirrored: draft.generators.requestedModifiers.contains(.mirrorKeyboard)))
      },
      mapsArrowKeysToInput: session.configuration.modifiers.contains(.arrowStream),
      mapsArrowLetterKeysToInput: WebsiteArrowChart.isSelected(session.configuration),
      mapsEnterToSpace: WebsiteRandomWordGenerator.selected(for: session.configuration) == .accounting,
      acceptsNewlineInput: session.acceptsNewlineInput,
      acceptsTabInput: session.acceptsTabInput,
      discardsAutofocusInput: settings.showFocusWarning,
      requiresShiftQuickRestart: quickRestartRequiresProtection
        && practiceQuickRestartKey != .enter,
      disablesQuickRestart: quickRestartRequiresProtection
        && practiceQuickRestartKey == .enter,
      enablesLongTestBailout: quickRestartRequiresProtection,
      finishesOnShiftEnter: session.configuration.mode == .zen,
      onInsert: { [attemptID = session.automaticInputAttemptID] text, forceError in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }
        guard activeChallengeID != "mouse-warrior" else { return }
        handleInsertedText(text, forceError: forceError)
      },
      onDelete: { [attemptID = session.automaticInputAttemptID] in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }
        if activeChallengeID != "mouse-warrior" { handleDeletedText(deletesWord: false) }
      },
      onDeleteWord: { [attemptID = session.automaticInputAttemptID] in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }
        if activeChallengeID != "mouse-warrior" { handleDeletedText(deletesWord: true) }
      },
      onRestart: { [attemptID = session.automaticInputAttemptID] in
        guard pageSessionStore.acceptsAttemptCallback(for: attemptID) else { return }; attemptRestart()
      },
      onOpenCommandPalette: { [attemptID = session.automaticInputAttemptID] in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }; showingCommandPalette = true
      },
      onBailoutArmed: { [attemptID = session.automaticInputAttemptID] in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }; armLongTestBailout()
      },
      onBailout: { [attemptID = session.automaticInputAttemptID] in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }
        guard !isPreparingPracticePrompt else { return }
        bailoutConfirmationMessage = nil
        synchronizeLiveInputRules()
        session.bailOut()
      },
      onQuickRestartProtectionRequired: { [attemptID = session.automaticInputAttemptID] in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }; showQuickRestartProtectionNotice()
      },
      onFinishZen: { [attemptID = session.automaticInputAttemptID] in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }
        guard !isPreparingPracticePrompt else { return }
        synchronizeLiveInputRules()
        session.finishZen()
      },
      onFocusChanged: { isFocused in
        if !isFocused { typingCompanionHands.reset() }
        handleTypingFocusChange(isFocused)
      },
      onWindowFocusChanged: { isFocused, hasAttachedSheet in
        if !isFocused { typingCompanionHands.reset() }
        handleTypingWindowFocusChange(isFocused, hasAttachedSheet: hasAttachedSheet)
      },
      onCompositionStarted: { [attemptID = session.automaticInputAttemptID] in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }
        guard !isPreparingPracticePrompt else { return }
        pageSessionStore.noteCompositionActivity(for: attemptID)
        if usesPreparedPromptViewport, viewportFallbackAttemptID != session.automaticInputAttemptID {
          viewportFallbackPosition.capture(attemptID: session.automaticInputAttemptID, targetID: session.promptTargetID)
        }
        preparedWholePreviewRendering = nil
        if activeChallengeID != "mouse-warrior" {
          synchronizeLiveInputRules()
          session.beginComposition()
        }
      },
      onCompositionChanged: { [attemptID = session.automaticInputAttemptID] text in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }
        guard !isPreparingPracticePrompt else { return }
        pageSessionStore.noteCompositionActivity(for: attemptID)
        if usesPreparedPromptViewport, !text.isEmpty,
          viewportFallbackAttemptID != session.automaticInputAttemptID {
          viewportFallbackAttemptID = session.automaticInputAttemptID
        }
        preparedWholePreviewRendering = nil
        let hadMarkedText = !compositionText.isEmpty
        let playsCompositionClick = TypingInputSoundPlan.isAudibleCompositionUpdate(
          previous: compositionText, current: text)
        compositionText = text
        if activeChallengeID != "mouse-warrior" {
          synchronizeLiveInputRules()
          session.refreshLiveAccuracyAfterComposition(
            hadMarkedText: hadMarkedText, hasMarkedText: !text.isEmpty)
          visualFocus.inputDidUpdate(hasFeedback: hadMarkedText || !text.isEmpty,
            textChanged: false, isFinished: session.isFinished)
          if playsCompositionClick { playInputFeedback(inputWasCorrect: true) }
        }
      },
      shouldFinishWithComposition: { [attemptID = session.automaticInputAttemptID] text, forceError in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return false }
        guard !isPreparingPracticePrompt else { return false }
        guard activeChallengeID != "mouse-warrior" else { return false }
        synchronizeLiveInputRules()
        return session.shouldFinishWithComposition(effectiveInsertedText(text), forceError: forceError)
      },
      onModifierFlagsChanged: { [attemptID = session.automaticInputAttemptID] flags in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }
        keyboardModifierFlags = flags
      },
      onKeyDown: { [attemptID = session.automaticInputAttemptID] keyCode, charactersIgnoringModifiers, modifierFlags, isRepeat in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }
        practiceSoundPlayer().recordKeyDown(keyCode: keyCode, modifierFlags: modifierFlags)
        if konamiSequenceTracker.consume(
          keyCode: keyCode,
          charactersIgnoringModifiers: charactersIgnoringModifiers,
          modifierFlags: modifierFlags,
          isRepeat: isRepeat)
        {
          NSWorkspace.shared.open(KonamiSequenceTracker.destination)
        }
      },
      onPhysicalKey: { [attemptID = session.automaticInputAttemptID] keyCode, isKeyDown, isRepeat in
        guard pageSessionStore.acceptsInput(for: attemptID) else { return }
        guard !isPreparingPracticePrompt else { return }
        if isKeyDown && activeChallengeID == "mouse-warrior" {
          session.recordPhysicalKeyboardActivityDuringAttempt()
        }
        session.recordPhysicalKeyEvent(
          keyCode: keyCode, isKeyDown: isKeyDown, isRepeat: isRepeat)
        if isKeyDown { session.recordKeyboardActivity() }
        guard practiceAppearance.showTypingCompanion else { return }
        typingCompanionHands.handle(keyCode: keyCode, isKeyDown: isKeyDown, isRepeat: isRepeat)
      }
    )
    .opacity(0.01)
    .frame(width: 1, height: 1)
  }

  private var typingPanel: some View {
    // The admitted viewport owns its ink. Do not build an unused complete
    // presentation; the fallback still captures one fresh rendering here.
    let rendering: PromptRendering? = usesWholePreviewViewport || publishedPresentation != nil ? nil : renderedPrompt
    let ignoresSystemReducedMotion = !VisualFunboxReducedMotionPolicy
      .ignoringSystemMotionModifiers.isDisjoint(with: session.configuration.modifiers)
    return ZStack(alignment: .topLeading) {
      VStack(spacing: 16) {
      RoundPracticeContent(
        isEnabled: practiceVisualEffect.usesRound,
        reducesMotion: settings.reducePracticeMotion,
        ignoresSystemReducedMotion: ignoresSystemReducedMotion
      ) {
        NauseaPracticeContent(
          isEnabled: practiceVisualEffect.usesNausea,
          reducesMotion: settings.reducePracticeMotion,
          ignoresSystemReducedMotion: ignoresSystemReducedMotion
        ) {
          EarthquakePracticeContent(
            isEnabled: practiceVisualEffect.usesEarthquake,
            reducesMotion: settings.reducePracticeMotion,
            ignoresSystemReducedMotion: ignoresSystemReducedMotion
          ) {
            Group {
              if let publishedPresentation {
                publishedPracticePrompt(publishedPresentation)
              } else if usesWholePreviewViewport {
                practicePrompt(rendering: nil)
              } else if let rendering, !PracticeLineDisplayPolicy.needsOuterViewport(showsAllLines: showsAllPracticeLines,
                usesTape: usesTapePractice, usesASL: practiceVisualEffect.usesASL, usesChoo: practiceVisualEffect.usesChoo) {
                practicePrompt(rendering: rendering)
              } else if let rendering {
                PracticePromptViewport(
                  text: rendering.text, font: practicePromptNSFont(size: settings.fontSize),
                  lineSpacing: session.configuration.usesJoiningScriptPrompt ? 8 : 12,
                  isRightToLeft: session.configuration.usesRightToLeftPrompt,
                  lineCount: session.configuration.mode == .zen ? 2 : 3,
                  maximumTextWidth: settings.practiceLineWidth.maximumWidth(
                    fontSize: settings.fontSize, customColumns: settings.customPracticeLineColumns),
                  horizontalTextInset: 4,
                  measuresTextRows: !usesTapePractice && !practiceVisualEffect.usesASL && !practiceVisualEffect.usesChoo
                    && rendering.compositionTextMap == nil,
                  measuresCustomRows: practiceVisualEffect.usesASL
                    || rendering.compositionTextMap != nil
                ) {
                  practicePrompt(rendering: rendering)
                }
              }
            }
            .scaleEffect(x: practiceVisualTransform.horizontalScale, y: 1, anchor: .center)
            .rotationEffect(.degrees(practiceVisualTransform.rotationDegrees))
          }
        }
      }

      if practiceCompositionDisplayStyle == .below {
        let focused = inputHasFocus && typingWindowHasFocus
        BelowCompositionPrompt(text: compositionText,
          font: practicePromptNSFont(size: settings.fontSize), color: NSColor(activeTheme.secondaryText),
          insertionAnchor: promptInsertionAnchor, attemptID: session.automaticInputAttemptID)
          .frame(maxWidth: .infinity)
          .opacity(focused ? 1 : 0.25)
          .blur(radius: focused ? 0 : 4)
          .animation(systemReduceMotion || settings.reducePracticeMotion || focused
            ? nil : .easeInOut(duration: 0.25), value: focused)
        practiceStatusBadges
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      }

    }
    .overlay(alignment: .bottomTrailing) {
      if TypingCompanionVisibilityPolicy.shouldShow(
        isEnabled: practiceAppearance.showTypingCompanion, hasStarted: session.hasStarted,
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
    .frame(maxWidth: .infinity, alignment: .topLeading)
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
      if committedPracticeDraft != nil, session.configuration.modifiers.contains(.layoutFluid) {
        WebsiteLayoutFluidCountdownBadge(state: pageSessionStore.layoutFluidCountdown,
          currentRequestID: { pageSessionStore.layoutFluidCountdown.animationRequest?.id })
      } else if let layoutFluidNotice {
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
      if practiceCompositionDisplayStyle != .below {
        practiceStatusBadges.padding(12)
      }
    }
    .onTapGesture { requestTypingFocus() }
  }

  @ViewBuilder private var practiceStatusBadges: some View {
    if !activeSessionTags.isEmpty || (activePaceTargetWpm != nil && paceGuideIndex != nil) {
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
            "节奏 \(activePaceTargetWpm.formatted(.number.precision(.fractionLength(0...2)))) WPM · \(paceGuideProgressDescription)", systemImage: "metronome"
          )
          .font(.caption.weight(.medium))
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .background(.thinMaterial, in: Capsule())
          .accessibilityLabel(
            "节奏引导：目标 \(activePaceTargetWpm.formatted(.number.precision(.fractionLength(0...2)))) WPM，\(paceGuideProgressDescription)，目标位置 \(paceGuideIndex + 1)"
          )
        }
      }
    }
  }

  private func practiceLineScrollContext(_ rendering: PromptRendering,
    session capturedSession: TypingSession? = nil) -> PromptLineScrollContext {
    let session = capturedSession ?? self.session
    if let offsets = rendering.compositionTextMap?.fieldCharacterOffsets {
      let field = session.promptCompositionField
      return .init(attemptID: session.automaticInputAttemptID,
        activeWordID: field?.index, characterOffsets: offsets,
        smoothScroll: settings.smoothPracticeLineScroll, reducesMotion: settings.reducePracticeMotion,
        words: PromptLineScrollWord.compositionFields(field), firstRetainedWordIndex: session.firstRetainedPromptWordIndex,
        onRetire: { self.session.retirePromptWords($0) },
        followsWordReflow: PromptWordReflowPolicy.isEnabled(mode: session.configuration.mode,
          slowTimer: timerHealth.usesSlowTimer, showAllLines: settings.showAllPracticeLines),
        caretMotion: promptCaretMotion, centersActiveLine: !settings.showAllPracticeLines,
        wrapperRevision: settings.practiceWrapperRevision)
    }
    return .init(attemptID: session.automaticInputAttemptID,
      activeWordID: session.promptWordPresentations.first(where: { $0.phase == .active })?.range.lowerBound,
      characterOffsets: rendering.glyphCharacterOffsets,
      smoothScroll: settings.smoothPracticeLineScroll, reducesMotion: settings.reducePracticeMotion,
      words: session.promptWordPresentations.enumerated().map {
        .init(index: $0.offset, glyphID: $0.element.range.lowerBound)
      }, firstRetainedWordIndex: session.firstRetainedPromptWordIndex,
      onRetire: { self.session.retirePromptWords($0) },
      followsWordReflow: PromptWordReflowPolicy.isEnabled(mode: session.configuration.mode,
        slowTimer: timerHealth.usesSlowTimer, showAllLines: settings.showAllPracticeLines),
      caretMotion: promptCaretMotion, centersActiveLine: !settings.showAllPracticeLines,
      wrapperRevision: settings.practiceWrapperRevision)
  }

  /// Additive cutover seam: the real page keeps its input/session ownership.
  /// Unsupported routes fail visibly rather than borrowing legacy resources.
  private func publishedPracticePrompt(_ presentation: WebsiteConfigPublishedPresentation) -> AnyView {
    do {
      if usesWholePreviewViewport {
        return AnyView(try presentation.wholePreview(session: session,
          carets: { font, p in publishedCarets(font: font, presentation: p) },
          wrapLayout: promptInputWrapLayout, fallbackPosition: viewportFallbackPosition,
          onFailure: { attempt in
            guard session.automaticInputAttemptID == attempt, viewportFallbackAttemptID != attempt else { return }
            viewportFallbackPosition.capture(attemptID: attempt, targetID: session.promptTargetID)
            viewportFallbackAttemptID = attempt; viewportReadinessAttemptID = nil
          }, onReady: { ready in
            guard viewportReadinessAttemptID == ready.attemptID,
              session.automaticInputAttemptID == ready.attemptID, session.promptTargetID == ready.targetID,
              promptRenderStyle == ready.style, practicePromptNSFont(size: settings.fontSize) == ready.font else { return }
            viewportReadinessAttemptID = nil; requestTypingFocus()
          }))
      }
      return AnyView(try presentation.inline(session: session, composition: compositionText,
        carets: { _, font, p in publishedCarets(font: font, presentation: p) },
        retirement: { rendering, p in publishedLineScroll(rendering, presentation: p) },
        wrapLayout: promptInputWrapLayout, fallbackPosition: showsAllPracticeLines ? viewportFallbackPosition : nil,
        latestProjection: {
          let current = session, marked = compositionText
          let rendering = renderedPrompt(for: current, composition: marked)
          return TapePromptProjection.snapshot(session: current, composition: marked, rendering: rendering,
            retirement: publishedLineScroll(rendering, presentation: presentation.publication.draft.presentation,
              session: current))
        }, onTapeWordsRemoved: { session.removeTapePromptWords($0) }))
    } catch {
      return AnyView(Label("完整配置提示暂不可用，请重新应用配置。", systemImage: "exclamationmark.triangle")
        .accessibilityIdentifier("published-config-prompt-unavailable"))
    }
  }

  private var publishedReducesMotion: Bool {
    settings.reducePracticeMotion || (systemReduceMotion && VisualFunboxReducedMotionPolicy
      .ignoringSystemMotionModifiers.isDisjoint(with: session.configuration.modifiers))
  }

  private func publishedCarets(font: NSFont, presentation p: WebsiteConfigNativePresentation) -> PromptCaretNativeView.Configuration {
    var config = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: p.caretStyle, paceStyle: p.paceCaretStyle, font: font,
      lineSpacing: session.configuration.usesJoiningScriptPrompt ? 8 : 12,
      rightToLeft: session.configuration.usesRightToLeftPrompt,
      accent: activeTheme.caret, motion: p.smoothCaretMotion, reducesMotion: publishedReducesMotion,
      frameRate: timerHealth.animationFrameRate(requested: settings.animationFrameRate,
        settingsRevision: settings.animationFrameRateRevision),
      attemptID: session.automaticInputAttemptID, coordinator: promptCaretMotion,
      firstRetainedWordIndex: session.firstRetainedPromptWordIndex,
      latestInput: { .init(attemptID: session.automaticInputAttemptID,
        typed: session.typed, composition: compositionText, glyphID: nil) },
      latestGlyphID: { currentPromptGlyphIndex },
      paceFrame: session.paceCaretTargetWpm != nil ? { paceCaretInterpolation() } : nil,
      paceUsesSessionCallbacks: true,
      paceIsVisible: { session.paceCaretIsVisible },
      mainPresentation: { .init(
        isVisible: (inputHasFocus || showsVirtualKeyboard) && typingWindowHasFocus && !session.isFinished,
        isBlinking: visualFocus.caretIsBlinking, revision: visualFocus.caretBlinkRevision) },
      mainGlyphID: currentPromptGlyphIndex)
    config.fieldDirectionPerGlyph = session.configuration.mode == .zen
      || session.configuration.mode == .custom || session.configuration.language == .mixedLanguages
    config.automaticallyPresents = p.caretStyle.drawsMarker || p.paceCaretStyle.drawsMarker || session.paceCaretIsVisible
    config.insertionAnchor = promptInsertionAnchor
    return config
  }

  private func publishedLineScroll(_ rendering: PromptRendering, presentation p: WebsiteConfigNativePresentation,
    session capturedSession: TypingSession? = nil) -> PromptLineScrollContext {
    let current = capturedSession ?? session, field = current.promptCompositionField
    return .init(attemptID: current.automaticInputAttemptID, activeWordID: field?.index,
      characterOffsets: rendering.compositionTextMap?.fieldCharacterOffsets ?? [:],
      smoothScroll: p.smoothPracticeLineScroll, reducesMotion: publishedReducesMotion,
      words: PromptLineScrollWord.compositionFields(field), firstRetainedWordIndex: current.firstRetainedPromptWordIndex,
      onRetire: { session.retirePromptWords($0) },
      followsWordReflow: PromptWordReflowPolicy.isEnabled(mode: current.configuration.mode,
        slowTimer: timerHealth.usesSlowTimer, showAllLines: p.showAllPracticeLines),
      caretMotion: promptCaretMotion, centersActiveLine: !p.showAllPracticeLines,
      wrapperRevision: settings.practiceWrapperRevision)
  }

  private func practicePrompt(rendering: PromptRendering?) -> some View {
    let _ = settings.localPracticeFontRevision
    let isRightToLeft = session.configuration.usesRightToLeftPrompt
    let usesJoiningScript = session.configuration.usesJoiningScriptPrompt
    return Group {
      if usesWholePreviewViewport {
        PromptViewportPracticePrompt(session: session, style: promptRenderStyle,
          font: practicePromptNSFont(size: settings.fontSize),
          carets: makeSpecialPromptCaretConfiguration(rightToLeft: isRightToLeft),
          wrapLayout: promptInputWrapLayout,
          fallbackPosition: viewportFallbackPosition,
          onFailure: { attempt in
            guard session.automaticInputAttemptID == attempt, viewportFallbackAttemptID != attempt else { return }
            viewportFallbackPosition.capture(attemptID: attempt, targetID: session.promptTargetID)
            viewportFallbackAttemptID = attempt
            viewportReadinessAttemptID = nil
          }, onReady: { ready in
            guard viewportReadinessAttemptID == ready.attemptID,
              session.automaticInputAttemptID == ready.attemptID, session.promptTargetID == ready.targetID,
              promptRenderStyle == ready.style, practicePromptNSFont(size: settings.fontSize) == ready.font else { return }
            viewportReadinessAttemptID = nil
            requestTypingFocus()
          })
      } else if let rendering, practiceVisualEffect.usesASL {
        ASLPracticePrompt(
          glyphs: session.promptGlyphsInDisplayOrder, fontSize: settings.fontSize, accent: activeTheme.accent,
          glyphIDs: specialPromptGlyphIDs, rendering: rendering, carets: specialPromptCaretConfiguration,
          font: practicePromptNSFont(size: settings.fontSize),
          lineScroll: showsAllPracticeLines ? nil : practiceLineScrollContext(rendering),
          caretGlyphID: currentPromptGlyphIndex,
          viewportLineCount: showsAllPracticeLines ? nil : (session.configuration.mode == .zen ? 2 : 3),
          words: session.promptWordPresentations)
      } else if let rendering, practiceVisualEffect.usesChoo {
        ChooPracticePrompt(
          glyphs: session.promptGlyphsInDisplayOrder,
          rendering: rendering,
          font: practicePromptNSFont(size: settings.fontSize),
          palette: ChooGlyphPalette(
            theme: activeTheme, flipsCompletionAndFuture: settings.flipTestColors,
            usesColorfulMode: settings.colorfulMode),
          isEnabled: true, reducesMotion: settings.reducePracticeMotion,
          ignoresSystemReducedMotion: !VisualFunboxReducedMotionPolicy
            .ignoringSystemMotionModifiers.isDisjoint(with: session.configuration.modifiers),
          glyphIDs: specialPromptGlyphIDs, carets: specialPromptCaretConfiguration,
          viewportLineCount: showsAllPracticeLines ? nil : (session.configuration.mode == .zen ? 2 : 3),
          lineScroll: showsAllPracticeLines ? nil : practiceLineScrollContext(rendering))
      } else if let rendering, usesTapePractice {
        TapePracticePrompt(session: session, rendering: rendering,
          mode: settings.practiceTapeMode,
          margin: settings.practiceTapeMargin,
          fontSize: settings.fontSize, animatesScroll: settings.smoothPracticeLineScroll,
          carets: makeSpecialPromptCaretConfiguration(rightToLeft: session.configuration.usesRightToLeftPrompt),
          retirement: practiceLineScrollContext(rendering),
          latestProjection: {
            let current = session, marked = compositionText
            let latest = renderedPrompt(for: current, composition: marked)
            return TapePromptProjection.snapshot(session: current, composition: marked, rendering: latest,
              retirement: practiceLineScrollContext(latest, session: current))
          },
          onTapeWordsRemoved: { session.removeTapePromptWords($0) })
      } else if let rendering, rendering.compositionTextMap != nil {
        PromptFieldPracticePrompt(rendering: rendering,
          font: practicePromptNSFont(size: settings.fontSize), lineSpacing: usesJoiningScript ? 8 : 12,
          rightToLeft: isRightToLeft, joinsLetters: usesJoiningScript,
          carets: makeSpecialPromptCaretConfiguration(rightToLeft: isRightToLeft),
          lineScroll: showsAllPracticeLines ? nil : practiceLineScrollContext(rendering),
          viewportLineCount: showsAllPracticeLines ? nil : (session.configuration.mode == .zen ? 2 : 3),
          preparedLayout: preparedWholePreviewLayout,
          wrapLayout: promptInputWrapLayout,
          fallbackPosition: showsAllPracticeLines ? viewportFallbackPosition : nil,
          fallbackTargetID: session.promptTargetID,
          allowsFallbackRestoration: !visualFocus.isTransitionPending,
          onMeasuredWidth: showsAllPracticeLines ? { width in wholePreviewFieldWidth = width } : nil)
      } else if let rendering {
        Text(rendering.text)
          .lineSpacing(usesJoiningScript ? 8 : 12)
          .textSelection(.disabled)
          .multilineTextAlignment(isRightToLeft ? .trailing : .leading)
          .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
          .foregroundStyle(activeTheme.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
          .frame(
            maxWidth: settings.practiceLineWidth.maximumWidth(
              fontSize: settings.fontSize, customColumns: settings.customPracticeLineColumns),
            alignment: isRightToLeft ? .trailing : .leading)
          .overlay {
            PromptInputWrapOverlay(layout: promptInputWrapLayout)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
          .overlay {
            if !showsAllPracticeLines {
              PromptAutoScrollOverlay(
                text: rendering.text,
                characterOffset: rendering.mainCharacterOffset ?? rendering.characterOffset(forGlyphAt: currentPromptGlyphIndex),
                font: practicePromptNSFont(size: settings.fontSize),
                lineSpacing: usesJoiningScript ? 8 : 12,
                isRightToLeft: isRightToLeft,
                lineScroll: practiceLineScrollContext(rendering))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
          }
          .overlay(alignment: isRightToLeft ? .topTrailing : .topLeading) {
            PromptCaretOverlay(
                text: rendering.text,
                mainCharacterOffset: rendering.mainCharacterOffset
                  ?? rendering.characterOffset(forGlyphAt: currentPromptGlyphIndex),
                mainStyle: usesNativeCaretOverlay ? settings.caretStyle : .off,
                paceCharacterOffset: nil,
                paceStyle: usesNativeCaretOverlay ? settings.paceCaretStyle : .off,
                font: practicePromptNSFont(size: settings.fontSize),
                lineSpacing: usesJoiningScript ? 8 : 12,
                isRightToLeft: isRightToLeft,
                accent: activeTheme.caret,
                motion: settings.smoothCaretMotion,
                paceFrame: paceCaretFrameProvider,
                paceUsesSessionCallbacks: true,
                paceIsVisible: { session.paceCaretIsVisible },
                reducesPaceMotion: settings.reducePracticeMotion,
                coordinator: promptCaretMotion, attemptID: session.automaticInputAttemptID,
                firstRetainedWordIndex: session.firstRetainedPromptWordIndex,
                latestInput: { .init(attemptID: session.automaticInputAttemptID,
                  typed: session.typed, composition: compositionText, glyphID: nil) },
                latestGlyphID: { currentPromptGlyphIndex },
                latestRendering: { renderedPrompt },
                mainPresentation: { .init(
                  isVisible: (inputHasFocus || showsVirtualKeyboard) && typingWindowHasFocus && !session.isFinished,
                  isBlinking: visualFocus.caretIsBlinking,
                  revision: visualFocus.caretBlinkRevision) },
                insertionAnchor: promptInsertionAnchor)
          }
      }
    }
    .font(Font(practicePromptNSFont(size: settings.fontSize)))
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
    // Source funbox activation already publishes its initial mode. Later
    // accepted commands own this field instead of replaying that activation.
    if let draft = committedPracticeDraft { return draft.keyboardTypography.guideMode }
    if session.configuration.modifiers.contains(.listening) { return .off }
    if session.configuration.modifiers.contains(.simonSays) { return .next }
    return practiceKeyboardGuide.mode
  }

  private func practicePromptNSFont(size: CGFloat) -> NSFont {
    if let font = publishedPresentation?.publication.font?.renderingFont { return font }
    if let font = FontFamilyCommandPreviewPolicy.font(
        for: commandFontPreview.target, size: size, fallback: settings.practiceFont) {
      return font
    }
    return settings.practiceFont.nsFont(
      size: size, installedFontName: challengeLiveConfiguration.fontFamilyName(settings: settings),
      language: session.configuration.language)
  }

  private func clearCommandFontPreview() {
    commandFontPreview.clear(savedFont: settings.practiceFont,
      savedName: commandFontFamilyName)
  }

  private var commandFontFamilyName: String {
    challengeLiveConfiguration.fontFamilyName(settings: settings)
  }

  private func verifyChallengeFontAvailability() {
    guard activeChallengeID == "ten-words-of-pain", session.hasStarted,
      WingdingsChallengeFont.resolve(size: 12) == nil
    else { return }
    wingdingsFontStayedAvailable = false
  }

  private var practiceVisualTransform: PracticeVisualTransform {
    PracticeVisualTransform.make(modifiers: session.configuration.modifiers)
  }

  private var practiceVisualEffect: PracticeVisualEffect {
    PracticeVisualEffect.make(modifiers: session.configuration.modifiers)
  }

  private var effectiveKeyboardLayout: KeyboardLayout {
    if let draft = committedPracticeDraft {
      return draft.keyboardTypography.guideLayout ?? draft.keyboardTypography.inputLayout.emulatedLayout ?? .ansiQwerty
    }
    guard session.configuration.modifiers.contains(.layoutFluid) else {
      return settings.keyboardGuideLayoutSource.resolvedBuiltInLayout(
        selectedLayout: settings.keyboardLayout, inputLayout: settings.keyboardInputLayout)
    }
    if session.configuration.mode == .time {
      return LayoutFluidPolicy.activeLayout(
        elapsedSeconds: lastClockTickSecond, duration: session.configuration.duration,
        layouts: settings.layoutFluidLayouts)
    }
    return LayoutFluidPolicy.activeLayout(
      completedWords: session.completedWordCount, wordLimit: session.configuration.wordLimit,
      layouts: settings.layoutFluidLayouts)
  }

  private var effectiveKeyboardGuideOverrideRows: [[KeyboardGuideKey]]? {
    if let draft = committedPracticeDraft {
      return KeyboardGuideModel.websiteRows(for: effectiveKeyboardLayout, mirrored: draft.generators.requestedModifiers.contains(.mirrorKeyboard))
    }
    guard practiceKeyboardGuide.allowsLegacyRows else { return nil }
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

  private var publishedKeyboardGuideThumbKeys: [KeyboardGuideKey]? {
    guard let draft = committedPracticeDraft else { return nil }
    return KeyboardGuideModel.websiteThumbKeys(for: effectiveKeyboardLayout, mirrored: draft.generators.requestedModifiers.contains(.mirrorKeyboard))
  }
  /// Full profiles receive each source setter independently, including a
  /// physical-layout refusal under No Quit. Legacy mode keeps its old policy.
  private var effectiveKeyboardInputMapping: KeyboardInputMapping {
    if let draft = committedPracticeDraft { return draft.keyboardTypography.inputMapping(mirrored: draft.generators.requestedModifiers.contains(.mirrorKeyboard)) }
    guard !session.configuration.modifiers.contains(.layoutFluid) else {
      return .builtIn(effectiveKeyboardLayout)
    }
    return settings.keyboardInputLayout.inputMapping(for: settings.selectedCustomKeyboardLayout)
  }

  private var effectiveOppositeShiftKeymap: KeyboardInputMapping {
    if let draft = committedPracticeDraft {
      return draft.keyboardTypography.shiftKeymap(mirrored: draft.generators.requestedModifiers.contains(.mirrorKeyboard))
    }
    return settings.keyboardGuideLayoutSource.oppositeShiftMapping(selectedLayout: settings.keyboardLayout,
      customLayout: settings.selectedCustomKeyboardLayout, layoutFluid: session.configuration.modifiers.contains(.layoutFluid))
  }

  private var layoutFluidNotice: String? {
    guard session.configuration.modifiers.contains(.layoutFluid) else { return nil }
    if committedPracticeDraft != nil {
      return pageSessionStore.layoutFluidCountdown.visible ? pageSessionStore.layoutFluidCountdown.text : nil
    }
    if session.configuration.mode == .time, session.hasStarted,
      let upcoming = LayoutFluidPolicy.upcomingLayout(
        elapsedSeconds: lastClockTickSecond, duration: session.configuration.duration,
        layouts: committedPracticeDraft?.generators.layoutFluidLayouts ?? settings.layoutFluidLayouts)
    {
      return "\(upcoming.layout.displayName) 将于 \(upcoming.secondsRemaining) 秒后切换"
    }
    if let upcoming = LayoutFluidPolicy.upcomingLayout(
      completedWords: session.completedWordCount, wordLimit: committedPracticeDraft == nil ? session.configuration.wordLimit : session.layoutFluidWordCount,
      layouts: committedPracticeDraft?.generators.layoutFluidLayouts ?? settings.layoutFluidLayouts)
    {
      return "\(upcoming.wordsRemaining) 个词后切换至 \(upcoming.layout.displayName)"
    }
    return "当前布局：\((committedPracticeDraft?.keyboardTypography.inputLayout.emulatedLayout ?? effectiveKeyboardLayout).displayName)"
  }
  private func advanceWebsiteLayoutFluid(_ event: WebsiteLayoutFluidTransition.Event) {
    guard committedPracticeDraft != nil, session.hasStarted, !session.isFinished,
      session.configuration.modifiers.contains(.layoutFluid) else { return }
    switch event {
    case .time: guard session.configuration.mode == .time else { return }
    case .words, .wordNavigation: guard session.configuration.mode != .time else { return }
    }
    do { try pageSessionStore.advanceLayoutFluid(event, attemptID: session.automaticInputAttemptID) }
    catch { account.localNotices.post("布局切换未完成，请检查当前配置。") }
  }

  private func deliverWebsiteWordNavigationEvents() {
    guard committedPracticeDraft != nil, session.configuration.modifiers.contains(.layoutFluid),
      session.configuration.mode != .time else { return }
    for event in session.websiteWordNavigationEvents {
      do { try pageSessionStore.advanceLayoutFluid(.wordNavigation(event), attemptID: event.attemptID) }
      catch { account.localNotices.post("布局切换未完成，请检查当前配置。"); break }
    }
  }

  private var promptHighlightAllowsWordRanges: Bool {
    PromptHighlightAvailabilityPolicy.allowsWordRanges(
      languageUsesSpaceDelimitedWords: session.usesWordCommitInput,
      usesTapePractice: usesTapePractice, modifiers: session.configuration.modifiers)
  }

  private var effectivePromptHighlightMode: PromptHighlightMode {
    guard settings.promptHighlightMode != .off else { return .off }
    return promptHighlightAllowsWordRanges ? settings.promptHighlightMode : .letter
  }

  private var currentPromptGlyphIndex: Int? {
    session.promptCaretGlyphIndex
  }

  private var specialPromptGlyphIDs: [Int] {
    let glyphs = session.promptGlyphs
    return PromptGlyphLayout.indices(glyphs: glyphs, words: session.promptWordPresentations,
      hideExtraLetters: session.configuration.rules.hideExtraLetters)
  }

  private var specialPromptCaretConfiguration: PromptCaretNativeView.Configuration? {
    return makeSpecialPromptCaretConfiguration()
  }

  private func makeSpecialPromptCaretConfiguration(rightToLeft: Bool = false) -> PromptCaretNativeView.Configuration {
    var configuration = PromptCaretNativeView.Configuration(text: AttributedString(), mainOffset: nil, paceOffset: nil,
      mainStyle: settings.caretStyle, paceStyle: settings.paceCaretStyle,
      font: practicePromptNSFont(size: settings.fontSize), lineSpacing: 12,
      rightToLeft: rightToLeft,
      accent: activeTheme.caret, motion: settings.smoothCaretMotion,
      reducesMotion: settings.reducePracticeMotion || systemReduceMotion,
      frameRate: timerHealth.animationFrameRate(requested: settings.animationFrameRate,
        settingsRevision: settings.animationFrameRateRevision),
      attemptID: session.automaticInputAttemptID, coordinator: promptCaretMotion,
      latestInput: { .init(attemptID: session.automaticInputAttemptID,
        typed: session.typed, composition: compositionText, glyphID: nil) },
      latestGlyphID: { currentPromptGlyphIndex }, paceFrame: paceCaretFrameProvider,
      paceUsesSessionCallbacks: true,
      paceIsVisible: { session.paceCaretIsVisible },
      mainPresentation: { .init(
        isVisible: (inputHasFocus || showsVirtualKeyboard) && typingWindowHasFocus && !session.isFinished,
        isBlinking: visualFocus.caretIsBlinking, revision: visualFocus.caretBlinkRevision) },
      mainGlyphID: currentPromptGlyphIndex)
    configuration.fieldDirectionPerGlyph = session.configuration.mode == .zen
      || session.configuration.mode == .custom || session.configuration.language == .mixedLanguages
    configuration.automaticallyPresents = settings.caretStyle.drawsMarker || settings.paceCaretStyle.drawsMarker || session.paceCaretIsVisible
    configuration.insertionAnchor = promptInsertionAnchor
    return configuration
  }

  private var usesNativeCaretOverlay: Bool {
    guard settings.caretStyle.drawsMarker || settings.paceCaretStyle.drawsMarker else { return false }
    guard !usesTapePractice, !practiceVisualEffect.usesASL, !practiceVisualEffect.usesChoo
    else {
      return false
    }
    return PromptFieldProjectionPolicy.supports(session.configuration)
  }

  private var usesIndependentPromptCarets: Bool {
    usesNativeCaretOverlay || usesTapePractice || practiceVisualEffect.usesChoo || practiceVisualEffect.usesASL
  }

  private func paceCaretInterpolation() -> PromptPaceCaretInterpolation? {
    guard let frame = session.paceCaretPresentationFrame() else { return nil }
    let from = session.paceCaretGlyphAnchor(for: frame.from)
    let target = session.paceCaretGlyphAnchor(for: frame.target)
    return .init(fromCharacterOffset: nil, targetCharacterOffset: nil,
      fromAfter: from?.after ?? false, targetAfter: target?.after ?? false, fraction: frame.fraction,
      stepDuration: frame.stepDuration, sequence: frame.sequence, targetGlyphID: target?.glyphIndex,
      zeroDeadlinePredecessor: session.paceCaretPredecessorAnchor(before: frame.target), fromGlyphID: from?.glyphIndex)
  }

  private var paceCaretFrameProvider: (() -> PromptPaceCaretInterpolation?)? {
    guard session.paceCaretTargetWpm != nil else { return nil }
    return { paceCaretInterpolation() }
  }

  private var renderedPrompt: PromptRendering {
    if let prepared = preparedWholePreviewRendering, !isPreparingWholePreview,
      prepared.attemptID == session.automaticInputAttemptID,
      !session.isFinished, prepared.typedSnapshot == session.typed,
      compositionText.isEmpty, prepared.style == promptRenderStyle,
      prepared.paceGuideIndex == paceGuideIndex {
      return prepared.rendering
    }
    return renderedPrompt(for: session, composition: compositionText)
  }

  private var preparedWholePreviewLayout: PromptFieldTextLayout? {
    guard let prepared = preparedWholePreviewRendering,
      prepared.attemptID == session.automaticInputAttemptID,
      !session.isFinished, prepared.typedSnapshot == session.typed,
      compositionText.isEmpty, prepared.style == promptRenderStyle,
      prepared.paceGuideIndex == paceGuideIndex else { return nil }
    return prepared.layout
  }

  private var promptRenderStyle: PromptRenderStyle {
    if let publishedPresentation,
      let inputs = try? WebsiteConfigPublishedPromptInputs(publication: publishedPresentation.publication,
        owner: publishedPresentation.publication.owner) {
      return inputs.style(theme: activeTheme)
    }
    return PromptRenderStyle(theme: activeTheme, fontSize: settings.fontSize,
      flipTestColors: settings.flipTestColors, colorfulMode: settings.colorfulMode,
      typedCharacterEffect: settings.typedCharacterEffect,
      compositionDisplayStyle: settings.compositionDisplayStyle,
      typoIndicatorStyle: settings.typoIndicatorStyle,
      caretStyle: settings.caretStyle, paceCaretStyle: settings.paceCaretStyle,
      highlightMode: settings.promptHighlightMode, usesTapePractice: usesTapePractice)
  }

  private func renderedPrompt(for session: TypingSession, composition: String?) -> PromptRendering {
    let diagnosticStart = TimerDeliveryDiagnostics.enabled ? ProcessInfo.processInfo.systemUptime : 0
    defer {
      if TimerDeliveryDiagnostics.enabled {
        let duration = ProcessInfo.processInfo.systemUptime - diagnosticStart
        TimerDeliveryDiagnostics.observeRender(duration: duration)
        if duration > 0.125 {
          TimerDeliveryDiagnostics.trace(.promptRenderFinished, duration: duration,
            hasStarted: session.hasStarted, isFinished: session.isFinished)
        }
      }
    }
    let style = promptRenderStyle
    return promptRender(session, composition, style)
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

  private func promptTextColor(for role: PromptTextRole, theme suppliedTheme: ResolvedTheme? = nil) -> Color {
    let activeTheme = suppliedTheme ?? self.activeTheme
    return switch PromptTextColorPolicy.tone(
      for: role, flipsCompletionAndFuture: settings.flipTestColors,
      usesAccentForCompleted: settings.colorfulMode)
    {
    case .primary: activeTheme.text
    case .secondary: activeTheme.secondaryText
    case .accent: activeTheme.accent
    }
  }

  private var usesTapePractice: Bool {
    practiceTapeMode != .off
  }

  private var practiceTapeMode: PracticeTapeMode {
    publishedPresentation?.publication.draft.presentation.practiceTapeMode ?? settings.practiceTapeMode
  }
  private var practiceShowsAllSetting: Bool {
    publishedPresentation?.publication.draft.presentation.showAllPracticeLines ?? settings.showAllPracticeLines
  }
  private var practiceCompositionDisplayStyle: CompositionDisplayStyle {
    publishedPresentation?.publication.draft.presentation.compositionDisplayStyle ?? settings.compositionDisplayStyle
  }

  private var showsAllPracticeLines: Bool {
    PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: practiceShowsAllSetting,
      tapeMode: practiceTapeMode,
      configuration: session.configuration)
  }

  private var usesPreparedPromptViewport: Bool {
    wholePreviewViewportEnabled || publishedPresentation != nil
  }

  private var usesWholePreviewViewport: Bool {
    usesPreparedPromptViewport && showsAllPracticeLines && !isPreparingWholePreview
      && !session.isFinished && compositionText.isEmpty && !usesTapePractice
      && !practiceVisualEffect.usesASL && !practiceVisualEffect.usesChoo
      && viewportFallbackAttemptID != session.automaticInputAttemptID
  }

  private var isPreparingPracticePrompt: Bool {
    isPreparingWholePreview || viewportReadinessAttemptID == session.automaticInputAttemptID
  }

  private func awaitViewportPresentationIfNeeded() {
    viewportReadinessAttemptID = !isPreparingWholePreview
      && allowsWholePreviewViewportPreparation(session, style: promptRenderStyle)
      ? session.automaticInputAttemptID : nil
  }

  private var stats: some View {
    LiveStatsClockContent(signal: liveStatsClockSignal) { liveStatsContent }
  }

  private var liveStatsContent: some View {
    let now = Date.now
    let live = LiveTypingMetrics(
      session: session, at: now, blindMode: session.configuration.rules.blindMode, unit: practiceAppearance.unit)
    let progressStyle = practiceAppearance.progress
    let isProgressFlashHidden = !progressStyle.showsProgressValue(
      isTimed: session.configuration.duration != nil,
      remainingSeconds: session.remainingSeconds(at: now))

    return HStack(spacing: 0) {
      metric(
        practiceAppearance.unit.displayName,
        value: live.speed, style: practiceAppearance.speed, usesLiveAppearance: true)
      metric(
        "Raw \(practiceAppearance.unit.displayName)",
        value: live.rawSpeed, style: practiceAppearance.speed, usesLiveAppearance: true)
      metric(
        "Burst \(practiceAppearance.unit.displayName)",
        value: live.burst, style: practiceAppearance.burst, usesLiveAppearance: true)
      metric(
        "准确率", value: live.accuracy, style: practiceAppearance.accuracy,
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
        metric("段落", value: sections.total == 0 ? "\(sections.completed)" : "\(sections.completed)/\(sections.total)")
      }
      if let errorCount = live.errorCount { metric("错误", value: "\(errorCount)") }
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
      isInputFocused: inputHasFocus || showsVirtualKeyboard,
      isWindowFocused: typingWindowHasFocus,
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
        ? practiceAppearance.foreground(theme: activeTheme) : Color.primary
      let labelForeground = usesLiveAppearance ? foreground.opacity(0.76) : Color.secondary
      VStack(spacing: isMini ? 2 : 5) {
        Text(value).font(
          .system(size: isMini ? 17 : 28, weight: .semibold, design: .rounded))
        Text(title).font(isMini ? .caption2 : .caption).foregroundStyle(labelForeground)
      }
      .foregroundStyle(foreground)
      .opacity((usesLiveAppearance ? practiceAppearance.opacity.rawValue : 1) * (isHidden ? 0 : 1))
      .frame(maxWidth: .infinity)
      .padding(.vertical, isMini ? 8 : 14)
    }
  }

  private var progressMetricBar: some View {
    let foreground = practiceAppearance.foreground(theme: activeTheme)
    let progress = session.progressFraction(at: .now) ?? 0
    return VStack(spacing: 6) {
      HStack {
        Text(session.progressLabel).font(.caption).foregroundStyle(foreground.opacity(0.76))
        Spacer()
        Text(session.progressText(at: .now) ?? "—")
          .font(.caption.weight(.semibold))
      }
      ProgressView(value: progress)
        .tint(foreground)
        .animation(progressBarAnimation, value: progress)
    }
    .foregroundStyle(foreground)
    .opacity(practiceAppearance.opacity.rawValue)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 14)
    .padding(.vertical, 16)
  }

  private var progressBarAnimation: Animation? {
    if let duration = session.configuration.duration {
      return duration == 0 ? nil : .linear(duration: 1)
    }
    return .easeInOut(duration: 0.25)
  }

  private func effectiveInsertedText(_ text: String) -> String {
    committedPracticeDraft == nil && session.configuration.modifiers.contains(.mirrorKeyboard) ? KeyboardMirror.transform(text) : text
  }

  private func synchronizeLiveInputRules() {
    let previous = session.configuration.rules
    var candidate = session
    candidate.synchronizeLiveInputRules(pageSession.practice?.session.configuration.rules ?? settings.inputRules)
    if candidate.configuration.rules != previous {
      session = candidate
      preparedWholePreviewRendering = nil
    }
  }

  private func consumePublishedPractice() {
    guard let incoming = incomingPublishedPresentation else {
      if pageSession.practice == nil { pageSession.presentation = nil }
      return
    }
    guard incoming.publication.practice != nil else {
      if pageSession.practice == nil { pageSession.presentation = incoming }
      return
    }
    if pageSession.presentation?.publication.applicationID == incoming.publication.applicationID { return }
    guard settings.allowsRestartingConfigurationChange else {
      funboxConfigurationMessage = "当前练习禁止更换配置，已保留原会话。"
      return
    }
    do {
      let replacement = try pageSession.applying(incoming, owner: preferenceConfigurationOwner,
        router: settings.preferenceConfigurationSaves)
      pageSession = replacement
      finalizePublishedPracticeInstallation()
    } catch { funboxConfigurationMessage = "完整配置会话尚未通过页面准入，当前练习保持不变。" }
  }

  private func finalizePublishedPracticeInstallation() {
      guard let practice = pageSession.practice,
        finalizedPracticeAttemptID != practice.session.automaticInputAttemptID else { return }
      finalizedPracticeAttemptID = practice.session.automaticInputAttemptID
      websiteLiveSourceRecoveryRequest = UUID()
      websiteLiveSourceRecoveryTask?.cancel(); websiteLiveSourceRecoveryTask = nil
      wholePreviewTask.cancel(); liveContentTask?.cancel(); liveContentTask = nil
      liveContentRequestID = UUID()
      isPreparingWholePreview = false; isLoadingLiveContent = false
      viewportReadinessAttemptID = nil; preparedWholePreviewRendering = nil
      interruptedWholePreview = false; liveContentStreamingActive = false
      liveContentMessage = practice.external?.attribution
      compositionText = ""; completedResult = nil; savedResultRecord = nil
      activeChallengeID = nil; wordPractice = nil
      activeLongSavedText = nil; activeVerifiedScript = nil
      keyboardGuideFeedback = nil; websiteKeymapFeedback.reset(); typingCompanionHands.reset(); clearTypingPowerEffect()
      lastTimeWarningSecond = nil; lastClockTickSecond = 0
      liveStatsClockSignal.second = 0; timerHealth = .init()
      isSamePromptRepeatAttempt = practice.repetition.repeatsWordset
      isRepeatedPaceAttempt = practice.repetition.repeatsPace
      activeSessionTags = settings.activeResultTags
      activePaceTargetWpm = paceGuideTarget(usingRepeatedPace:
        isRepeatedPaceAttempt && committedPracticeDraft?.behavior.paceGuideMode == .off ? lastFinishedWpm : nil)
      session.configurePace(wpm: activePaceTargetWpm, style: committedPracticeDraft?.presentation.paceCaretStyle ?? settings.paceCaretStyle)
      practiceSoundPlayer().beginPracticeAttempt()
      NativeSpeech.shared.stop()
      synchronizeNoQuitConfigurationLock()
      awaitViewportPresentationIfNeeded()
      if session.configuration.modifiers.contains(.listening) {
        NativeSpeech.shared.speak(session.prompt, language: session.configuration.wordPoolBaseLanguage)
      }
      if let external = practice.external {
        liveContentStreamingActive = true
        liveContentMessage = external.attribution
        prefetchLiveContentIfNeeded()
      }
      requestTypingFocus()
  }

  private func handleChallengeFieldApplication(_ field: ChallengeLiveConfigurationState.ApplicationField,
    revision: UInt64) {
    guard activeChallengeID != nil,
      challengeLiveConfiguration.shouldClearChallenge(for: field, eventRevision: revision, settings: settings)
    else { return }
    // The reference event clears qualification, not the current attempt.
    // Unowned nosave fields remain in the window-local configuration.
    activeChallengeID = nil
  }

  private func handleInputRuleChange(_ previous: InputRules, _ current: InputRules) {
    guard !pageSessionStore.ownsConfigurationSelection else { return }
    if isPreparingPracticePrompt { reset() }
    else {
      session.synchronizeLiveInputRules(current)
      preparedWholePreviewRendering = nil
    }
  }

  private func handleInsertedText(
    _ text: String, forceError: Bool, origin: TypingInputOrigin = .physicalKeyboard
  ) {
    guard !isPreparingPracticePrompt else { return }
    let diagnosticStart = TimerDeliveryDiagnostics.enabled ? ProcessInfo.processInfo.systemUptime : 0
    let tracesFirstInput = TimerDeliveryDiagnostics.enabled && !session.hasStarted
    if tracesFirstInput {
      TimerDeliveryDiagnostics.trace(.inputStarted,
        hasStarted: session.hasStarted, isFinished: session.isFinished)
    }
    defer {
      if TimerDeliveryDiagnostics.enabled {
        let duration = ProcessInfo.processInfo.systemUptime - diagnosticStart
        if tracesFirstInput || duration > 0.125 {
          TimerDeliveryDiagnostics.trace(.inputFinished, duration: duration,
            hasStarted: session.hasStarted, isFinished: session.isFinished)
        }
      }
    }
    synchronizeLiveInputRules()
    let hadStarted = session.hasStarted
    let errorsBefore = session.errors
    let typedCountBefore = session.typed.count
    let typedBefore = session.typed
    let previousPreview = preparedWholePreviewRendering
    let keymapAttemptID = session.automaticInputAttemptID
    let feedback = TypingLiveInputFeedback.insertBatch(
      effectiveInsertedText(text), into: &session,
      forceError: forceError, origin: origin, defersAutomaticInput: true,
      wrapAdmission: promptInputWrapAdmission)
    let keymapEvents = session.keymapInputEvents
    deliverWebsiteWordNavigationEvents()
    if session.typed != typedBefore {
      let style = promptRenderStyle
      if usesWholePreviewViewport {
        preparedWholePreviewRendering = nil
      } else if let previousPreview, previousPreview.attemptID == session.automaticInputAttemptID,
        previousPreview.typedSnapshot == typedBefore, previousPreview.style == style,
        previousPreview.paceGuideIndex == nil, compositionText.isEmpty,
        let patched = PromptSequentialInputPatch.make(prepared: previousPreview.rendering,
          session: session, style: style) {
        let patchedLayout = previousPreview.layout.flatMap { previous in
          patched.compositionTextMap.flatMap { map in
            map.fieldRuns.first?.cells.first(where: { $0.id == session.typed.count - 1 }).flatMap {
              previous.patchingSequentialInput($0, caret: map.caret)
            }
          }
        }
        preparedWholePreviewRendering = .init(attemptID: previousPreview.attemptID,
          typedSnapshot: session.typed, rendering: patched, layout: patchedLayout,
          style: style, paceGuideIndex: nil)
      } else { preparedWholePreviewRendering = nil }
    } else if !feedback.isEmpty || preparedWholePreviewRendering?.typedSnapshot != session.typed {
      preparedWholePreviewRendering = nil
    }
    if !hadStarted && session.hasStarted { synchronizeNoQuitConfigurationLock() }
    visualFocus.inputDidUpdate(hasFeedback: !feedback.isEmpty,
      textChanged: session.typed != typedBefore, isFinished: session.isFinished)
    verifyChallengeFontAvailability()
    emitTypingPowerEffect(
      isCorrect: session.errors == errorsBefore,
      acceptedCharacters: session.typed.count - typedCountBefore)
    if effectiveKeyboardGuideMode == .react, committedPracticeDraft != nil,
      session.automaticInputAttemptID == keymapAttemptID {
      websiteKeymapFeedback.receive(keymapEvents)
    } else if effectiveKeyboardGuideMode == .react, committedPracticeDraft == nil, let pressedCharacter = text.last {
      keyboardGuideFeedbackSequence &+= 1
      keyboardGuideFeedback = .init(
        sequence: keyboardGuideFeedbackSequence,
        character: pressedCharacter,
        isCorrect: session.errors == errorsBefore)
    }
    for correct in feedback { playInputFeedback(inputWasCorrect: correct) }
    scheduleAutomaticInput()
  }

  private func scheduleAutomaticInput() {
    guard session.hasPendingAutomaticInput else { return }
    let attemptID = session.automaticInputAttemptID
    automaticInputScheduler.schedule(for: attemptID) {
      guard session.automaticInputAttemptID == attemptID else { return }
      synchronizeLiveInputRules()
      let errorsBefore = session.errors
      let countBefore = session.typed.count
      let feedback = session.processNextAutomaticInput(for: attemptID, executedAt: .now,
        wrapAdmission: promptInputWrapAdmission)
      if !feedback.isEmpty { deliverWebsiteWordNavigationEvents() }
      visualFocus.inputDidUpdate(hasFeedback: !feedback.isEmpty,
        textChanged: session.typed.count != countBefore, isFinished: session.isFinished)
      verifyChallengeFontAvailability()
      emitTypingPowerEffect(isCorrect: feedback.last == true,
        acceptedCharacters: session.typed.count - countBefore)
      if !feedback.isEmpty, effectiveKeyboardGuideMode == .react, committedPracticeDraft != nil,
        session.automaticInputAttemptID == attemptID {
        websiteKeymapFeedback.receive(session.keymapInputEvents)
      } else if !feedback.isEmpty, effectiveKeyboardGuideMode == .react, committedPracticeDraft == nil {
        keyboardGuideFeedbackSequence &+= 1
        keyboardGuideFeedback = .init(sequence: keyboardGuideFeedbackSequence,
          character: "\t", isCorrect: session.errors == errorsBefore)
      }
      for correct in feedback { playInputFeedback(inputWasCorrect: correct) }
      scheduleAutomaticInput()
    }
  }

  private func handleDeletedText(deletesWord: Bool) {
    guard !isPreparingPracticePrompt else { return }
    synchronizeLiveInputRules()
    let feedback = TypingLiveInputFeedback.delete(from: &session, wholeWord: deletesWord)
    if !feedback.isEmpty || preparedWholePreviewRendering?.typedSnapshot != session.typed {
      preparedWholePreviewRendering = nil
    }
    visualFocus.inputDidUpdate(hasFeedback: !feedback.isEmpty,
      textChanged: false, isFinished: session.isFinished)
    for correct in feedback { playInputFeedback(inputWasCorrect: correct) }
  }

  private var promptInputWrapAdmission: TypingInputWrapAdmission? {
    guard !usesTapePractice, !practiceVisualEffect.usesASL, !practiceVisualEffect.usesChoo,
      let width = promptInputWrapLayout.width else { return nil }
    let font = practicePromptNSFont(size: settings.fontSize)
    return .init(slowTimer: timerHealth.usesSlowTimer) { current, candidate in
      PromptInputWrapGeometry.rejects(session: current, candidate: candidate,
        rendering: renderedPrompt(for: current, composition: ""), width: width, font: font,
        lineSpacing: current.configuration.usesJoiningScriptPrompt ? 8 : 12,
        isRightToLeft: current.configuration.usesRightToLeftPrompt,
        joinsLetters: current.configuration.usesJoiningScriptPrompt)
    }
  }

  private func playInputFeedback(inputWasCorrect: Bool?) {
    practiceSoundSelection.playInput(inputWasCorrect, on: practiceSoundPlayer())
  }

  private var controls: some View {
    HStack {
      Text(
        session.isFinished
          ? session.outcome.statusText(saveState: localResultSaveState, eligibility: completedResult?.eligibility)
          : restartInstruction
      )
        .foregroundStyle(.secondary)
      Spacer()
      if session.hasStarted && !session.isFinished {
        if session.canFinishInfiniteChallenge {
          Button("完成挑战并查看成绩") {
            synchronizeLiveInputRules()
            session.finishInfiniteChallenge()
          }
            .buttonStyle(.bordered)
        }
        Button(
          shouldBailOutFromControls ? "中止并查看结果" : "放弃本次测试",
          role: .destructive
        ) {
          synchronizeLiveInputRules()
          if shouldBailOutFromControls {
            session.bailOut()
          } else {
            session.abandon()
          }
        }
      }
      Button {
        showsVirtualKeyboard.toggle()
      } label: {
        Label(
          showsVirtualKeyboard ? "关闭屏幕键盘" : "屏幕键盘",
          systemImage: "keyboard")
      }
      .buttonStyle(.bordered)
      .disabled(activeChallengeID == "mouse-warrior")
      .help("用鼠标点击原生键位输入；Shift 和 Option 只影响下一键")
      Button {
        attemptRestart()
      } label: {
        Label("重新开始", systemImage: "arrow.counterclockwise")
      }
      .keyboardShortcut("r", modifiers: .command)
      .buttonStyle(.borderedProminent)
      .disabled(pageSessionStore.restartController?.isPreparing == true)
      if weakSpotPrompt != nil {
        Button("弱项训练") { startWeakSpotPractice() }
          .help("依据本机完成测试中的错误字符生成离线词库练习")
      }
      Button("朗读提示") {
        NativeSpeech.shared.speak(session.prompt, language: session.configuration.wordPoolBaseLanguage)
      }
      .help("使用 macOS 本机语音朗读当前提示，不发送文本到网络")
    }
    .overlay(alignment: .bottomLeading) {
      if let bailoutConfirmationMessage {
        Label(bailoutConfirmationMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .offset(y: 24)
      } else if let quickRestartProtectionMessage {
        Label(quickRestartProtectionMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .offset(y: 24)
      } else if pageSessionStore.restartController?.isPreparing == true {
        Label("正在准备新一轮…", systemImage: "arrow.triangle.2.circlepath")
          .font(.caption).foregroundStyle(.secondary).offset(y: 24)
      } else if let message = pageSessionStore.restartController?.message {
        Label(pageSessionStore.restartController?.exhaustedMessage == nil ? message : "初始化未完成，请检查上方原因或会话通知。",
          systemImage: "exclamationmark.triangle")
          .font(.caption).foregroundStyle(.orange).offset(y: 24)
      } else if let restartLockMessage {
        Label(restartLockMessage, systemImage: "lock.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .offset(y: 24)
      } else if let modeCompatibilityMessage {
        Label(modeCompatibilityMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .offset(y: 24)
      } else if let referenceScriptMessage {
        Label(referenceScriptMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .offset(y: 24)
      } else if let funboxConfigurationMessage {
        Label(funboxConfigurationMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .offset(y: 24)
      } else if let customBackgroundCommandMessage {
        Label(customBackgroundCommandMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .offset(y: 24)
      } else if let fontFamilyCommandMessage {
        Label(fontFamilyCommandMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .offset(y: 24)
      } else if let themeQuickSwitchMessage {
        Label(themeQuickSwitchMessage, systemImage: "paintpalette")
          .font(.caption)
          .foregroundStyle(.orange)
          .offset(y: 24)
      }
    }
  }

  private var themeIndicatorPresentation: ThemeIndicatorPresentation {
    themePreviewPresentation.indicator
  }

  private var selectedThemeQuickPickerTarget: ThemeCommandTarget {
    settings.currentThemeQuickPickerTarget(for: systemColorScheme)
  }

  private func handleThemeIndicatorActivation() {
    themeQuickSwitchMessage = nil
    guard NSEvent.modifierFlags.contains(.shift) else {
      themeQuickPickerScope = ThemeQuickSwitchPolicy.pickerScope(settings: settings)
      return
    }
    switch ThemeQuickSwitchPolicy.shiftClickAction(settings: settings)
    {
    case .selectBuiltIn:
      applyThemeQuickPickerSelection(.builtIn(settings.theme))
    case .selectCustom(let id):
      applyThemeQuickPickerSelection(.custom(id))
    case .chooseCustom:
      themeQuickPickerScope = .custom
    case .noCustomThemes:
      themeQuickSwitchMessage = "还没有自定义主题；可在设置中创建或导入。"
    }
  }

  private func applyThemeQuickPickerSelection(_ target: ThemeCommandTarget) {
    guard ThemeCommandApplication.apply(target, to: settings,
      onConfigurationSave: persistExplicitTestConfiguration) else { return }
    themeQuickSwitchMessage = nil
  }

  private func attemptRestart() {
    if pageSession.practice != nil { requestPublishedRestart(); return }
    guard acceptsRestartingConfigurationChange() else { return }
    reset(restarting: true)
  }

  private func requestPublishedRestart(repeatingRequested: Bool = false) {
    guard let controller = pageSessionStore.restartController else {
      restartLockMessage = "当前配置尚未绑定重开控制器；已保留本轮。"
      return
    }
    restartLockMessage = nil
    controller.request(repeatingRequested: repeatingRequested)
  }

  @discardableResult
  private func acceptsLeavingPracticeNavigation() -> Bool {
    guard NoQuitNavigationPolicy.allowsLeavingPractice(for: session) else {
      restartLockMessage = "锁定重开已开启：请完成或放弃本次测试后再离开练习。"
      return false
    }
    return true
  }

  private var isRestartingConfigurationChangeLocked: Bool {
    pageSessionStore.ownsConfigurationSelection || !settings.allowsRestartingConfigurationChange
  }

  @discardableResult
  private func acceptsRestartingConfigurationChange() -> Bool {
    if websiteConfigStartup != nil, pageSessionStore.startupController.state != .idle, startupBlocksPractice {
      restartLockMessage = "请先完成配置恢复，或选择使用原生配置继续。"
      return false
    }
    guard !pageSessionStore.ownsConfigurationSelection else {
      restartLockMessage = pageSession.savedApplication != nil
        ? "配置已保存，请先恢复准备，或切回 Typebar 设置。"
        : "本轮使用完整配置；请在本轮设置中编辑，未提供的项目可从导入面板恢复或切回 Typebar 设置。"
      return false
    }
    synchronizeNoQuitConfigurationLock()
    guard !isRestartingConfigurationChangeLocked else {
      restartLockMessage = "锁定重开已开启：请完成或放弃本次测试。"
      return false
    }
    return true
  }

  private func restartingConfigurationBinding<Value>(_ value: Binding<Value>,
    savesConfiguration: Bool = true) -> Binding<Value> {
    Binding(
      get: { value.wrappedValue },
      set: { updatedValue in
        guard acceptsRestartingConfigurationChange() else { return }
        value.wrappedValue = updatedValue
        if savesConfiguration { persistExplicitTestConfiguration() }
      })
  }

  @discardableResult
  private func selectMode(_ requested: TestMode) -> Bool {
    guard acceptsRestartingConfigurationChange() else { return false }
    guard TestModifierPolicy.acceptsModeSelection(requested, modifiers: practiceRequestedModifiers, language: language) else {
      let message = "当前修饰器不支持“\(requested.displayName)”模式；请先关闭不兼容的趣味模式。"
      modeCompatibilityMessage = message
      ConfigurationNoticeFeedback.conflict(message, notices: account.localNotices)
      return false
    }
    modeCompatibilityMessage = nil
    mode = requested
    return true
  }

  @discardableResult
  private func selectContentOptions(_ requested: ContentOptions) -> Bool {
    guard acceptsRestartingConfigurationChange() else { return false }
    guard FunboxForcedContentOptionsPolicy.accepts(
      requested, modifiers: practiceRequestedModifiers)
    else {
      reportFunboxConfigurationConflict("当前趣味模式要求关闭标点或数字；请先关闭对应选项。")
      return false
    }
    funboxConfigurationMessage = nil
    contentOptions = requested
    persistExplicitTestConfiguration()
    return true
  }

  @discardableResult
  private func selectLanguage(_ requested: TypingLanguage) -> Bool {
    guard acceptsRestartingConfigurationChange(), availableLanguages.contains(requested) else {
      return false
    }
    guard requested != .mixedLanguages || language == .mixedLanguages
      || TestModifierPolicy.acceptsPolyglotAddition(to: practiceRequestedModifiers, mode: mode)
    else {
      reportFunboxConfigurationConflict("自选多语与当前趣味修饰器组合不兼容；已保留现有选择。")
      return false
    }
    polyglotReturnLanguage = PolyglotReturnLanguagePolicy.baseWhenSelecting(
      requested, current: language, previous: polyglotReturnLanguage)
    language = requested
    persistExplicitTestConfiguration()
    return true
  }

  private func acceptsFunboxConfiguration(_ modifiers: [TestModifier], language: TypingLanguage) -> Bool {
    guard TestModifierPolicy.acceptsModeSelection(mode, modifiers: modifiers, language: language) else {
      reportFunboxConfigurationConflict("当前模式不支持这个趣味模式；请先切换到兼容模式。")
      return false
    }
    guard FunboxForcedContentOptionsPolicy.accepts(contentOptions, modifiers: modifiers) else {
      reportFunboxConfigurationConflict("当前标点或数字设置不支持这个趣味模式；请先关闭对应选项。")
      return false
    }
    guard FunboxForcedContentOptionsPolicy.accepts(
      promptHighlightMode: settings.promptHighlightMode, modifiers: modifiers)
    else {
      reportFunboxConfigurationConflict("当前提示高亮范围不支持这个趣味模式；请改为“当前字符”或“关闭”。")
      return false
    }
    funboxConfigurationMessage = nil
    return true
  }

  private func reportFunboxConfigurationConflict(_ message: String) {
    funboxConfigurationMessage = message
    ConfigurationNoticeFeedback.conflict(message, notices: account.localNotices)
  }

  private var restartInstruction: String {
    if quickRestartRequiresProtection {
      let bailout = "双击 Shift+Enter 中止并显示结果"
      switch practiceQuickRestartKey {
      case .escape: return "按任意键开始，Shift+Esc 可重新开始；\(bailout)"
      case .tab: return "按任意键开始，Shift+Tab 可重新开始；\(bailout)"
      case .enter: return "按任意键开始，⌘R 可重开；\(bailout)"
      case .off: return "按任意键开始，可用 ⌘R 重开；\(bailout)"
      }
    }
    switch practiceQuickRestartKey {
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
      .opacity(visualFocus.isFocused ? 0 : 1)
      .accessibilityHidden(visualFocus.isFocused)
      .animation(systemReduceMotion || settings.reducePracticeMotion ? nil : .easeInOut(duration: 0.2), value: visualFocus.isFocused)
    }
  }

  private var keyTipRestartShortcut: String {
    guard !quickRestartRequiresProtection else { return "⌘R" }
    switch practiceQuickRestartKey {
    case .off: return "⌘R"
    case .escape: return "Esc / ⌘R"
    case .tab: return "Tab / ⌘R"
    case .enter: return "Enter / ⌘R"
    }
  }

  private var commandPaletteShortcutInstruction: String {
    let dynamic = CommandPaletteDynamicShortcut.resolve(
      quickRestartKey: practiceQuickRestartKey,
      promptAcceptsTab: session.acceptsTabInput)
    return "\(dynamic.displayName) / ⇧⌘P / ⇧⌘K"
  }

  private func handleTypingFocusChange(_ hasFocus: Bool) {
    if hasFocus, !inputHasFocus { visualFocus.caretDidBecomeVisible() }
    inputHasFocus = hasFocus
    updateFocusWarningDelay()
  }

  private func handleTypingWindowFocusChange(_ hasFocus: Bool, hasAttachedSheet: Bool) {
    let shouldRestart = TypingWindowRefocusRestartPolicy.shouldRestart(
      returnedFromUnfocusedWindow: typingWindowFocusTracker.record(
        isKey: hasFocus, hasAttachedSheet: hasAttachedSheet),
      hasStarted: session.hasStarted,
      isFinished: session.isFinished,
      resultIsVisible: completedResult != nil,
      mode: session.configuration.mode)
    if hasFocus, !typingWindowHasFocus { visualFocus.caretDidBecomeVisible() }
    typingWindowHasFocus = hasFocus
    if !hasFocus || hasAttachedSheet { visualFocus.retire() }
    if shouldRestart { attemptRestart() }
    updateFocusWarningDelay()
  }

  private func updateFocusWarningDelay() {
    focusWarningSequence &+= 1
    guard !inputHasFocus || !typingWindowHasFocus else {
      focusWarningDelayElapsed = false
      return
    }

    clearTypingPowerEffect()
    focusWarningDelayElapsed = false
    let sequence = focusWarningSequence
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      guard (!inputHasFocus || !typingWindowHasFocus), focusWarningSequence == sequence else { return }
      focusWarningDelayElapsed = true
    }
  }

  private func emitTypingPowerEffect(isCorrect: Bool, acceptedCharacters: Int) {
    let mode = settings.typingPowerMode
    guard
      TypingPowerPolicy.shouldEmit(
        mode: mode, acceptedCharacters: acceptedCharacters,
        reducesMotion: systemReduceMotion || settings.reducePracticeMotion,
        slowTimer: timerHealth.usesSlowTimer)
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

  private func handleLayoutFluidSelectionChange(
    from previous: [KeyboardLayout], to selected: [KeyboardLayout]
  ) {
    guard previous != selected else { return }
    if restoringLockedLayoutFluidSelection {
      restoringLockedLayoutFluidSelection = false
      return
    }
    guard session.configuration.modifiers.contains(.layoutFluid) else { return }
    guard acceptsRestartingConfigurationChange() else {
      restoringLockedLayoutFluidSelection = true
      settings.layoutFluidLayouts = previous
      return
    }
    reset()
  }

  private func reset(restarting: Bool = false) {
    guard acceptsRestartingConfigurationChange() else { return }
    if let source = customTextRecovery.takePendingSource(whenAllowed: true) {
      installCustomTextState(source)
    }
    customWordDurationSelection.reconcile(mode: mode, completion: customTextCompletion,
      wordLimit: customTextWordLimit)
    visualFocus.retire()
    if let activeVerifiedScript,
      !activeVerifiedScript.retainsSource(mode: mode, editorText: customText, challengeID: activeChallengeID)
    {
      self.activeVerifiedScript = nil
      if customText == LongSavedTextProgress.nextChunk(in: activeVerifiedScript.text, after: 0) {
        customText = "A calm practice makes the next difficult sentence feel possible."
      }
    }
    if activeChallenge == nil || !settings.hasThresholdProfile {
      let requestedModifiers = practiceRequestedModifiers
      let effectiveMemoryMode = MemoryFunboxModePolicy.effectiveMode(
        requested: mode, modifiers: requestedModifiers)
      if mode != effectiveMemoryMode { mode = effectiveMemoryMode }
      let languageCompatibleModifiers = language == .mixedLanguages
        ? TestModifierPolicy.modifiersCompatibleWithPolyglot(requestedModifiers)
        : requestedModifiers
      let joiningSafeModifiers = JoiningScriptFunboxPolicy.effectiveModifiers(
        languageCompatibleModifiers, language: language,
        mixedLanguageComponents: mixedLanguageComponents)
      if requestedModifiers != joiningSafeModifiers {
        if challengeLiveConfiguration.hasTransientModifiers(settings: settings) {
          challengeLiveConfiguration.normalizeModifiers(joiningSafeModifiers, settings: settings)
        } else {
          settings.testModifiers = joiningSafeModifiers
        }
      }
    }
    let shouldCountRestart = session.hasStarted && !session.isFinished
    wingdingsFontStayedAvailable = true
    let restartedSessionEngagedDuration = shouldCountRestart
      ? session.activeEngagedDuration()
      : 0
    let restartedSessionAccuracy = shouldCountRestart ? session.preciseAccuracy : nil
    absorbLiveWeakSpotScores(from: session)
    restartLockMessage = nil
    bailoutConfirmationMessage = nil
    quickRestartProtectionMessage = nil
    compositionText = ""
    keyboardGuideFeedback = nil
    websiteKeymapFeedback.reset()
    typingCompanionHands.reset()
    clearTypingPowerEffect()
    lastTimeWarningSecond = nil
    lastClockTickSecond = 0
    liveStatsClockSignal.second = 0
    timerHealth = .init()
    liveContentStreamingActive = false
    wholePreviewTask.cancel()
    isPreparingWholePreview = false
    viewportReadinessAttemptID = nil
    preparedWholePreviewRendering = nil
    interruptedWholePreview = false
    liveContentTask?.cancel()
    liveContentTask = nil
    liveContentRequestID = UUID()
    let requestID = liveContentRequestID
    isLoadingLiveContent = false
    liveContentMessage = nil
    if mode != .custom { activeLongSavedText = nil }
    NativeSpeech.shared.stop()
    practiceSoundPlayer().beginPracticeAttempt()
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
      mode: mode, sourceIsCommunity: quoteSource == .community, title: selectedQuote?.title,
      selectedQuoteID: selectedQuote?.id, actualLength: selectedQuote?.length)
    activeSessionTags = settings.activeResultTags
    let preparesWholePreview = WholePreviewWordPreparation.usesAsyncPreparation(
      configuration: configuration,
      showAllLines: practiceShowsAllSetting && practiceTapeMode == .off)
    isPreparingWholePreview = preparesWholePreview
    session = preparesWholePreview
      ? TypingSession(configuration: configuration, prompt: "", weakSpotScores: weakSpotScores,
        wordDecorationState: wordDecorationState)
      : TestSessionFactory.make(
      configuration: configuration,
      customText: customText,
      preparedCustomSections: preparedCustomSections,
      customTextRecoveryBlocked: customTextRecovery.blocksCustomGeneration,
      finiteTextSource: activeLongSavedText.map { $0.continuous ? $0.remainingText : $0.currentChunk },
      verifiedScript: activeVerifiedScript,
      quote: selectedQuote,
      weakSpotScores: weakSpotScores,
      wordDecorationState: wordDecorationState,
      showAllLines: practiceShowsAllSetting && practiceTapeMode == .off
    )
    session = session.withElapsedClock()
    if session.configuration.language == .mixedLanguages {
      polyglotReturnLanguage = session.configuration.polyglotBaseLanguage
    }
    synchronizeNoQuitConfigurationLock()
    persistActiveTestSelection()
    if shouldCountRestart {
      priorAttemptLedger.recordRestart(
        engagedDuration: restartedSessionEngagedDuration, accuracy: restartedSessionAccuracy,
        savingEnabled: settings.saveCompletedResults)
    }
    isSamePromptRepeatAttempt = false
    isRepeatedPaceAttempt = false
    activePaceTargetWpm = paceGuideTarget()
    session.configurePace(wpm: activePaceTargetWpm, style: committedPracticeDraft?.presentation.paceCaretStyle ?? settings.paceCaretStyle)
    awaitViewportPresentationIfNeeded()
    if !isPreparingWholePreview, session.configuration.modifiers.contains(.listening) {
      NativeSpeech.shared.speak(session.prompt, language: session.configuration.wordPoolBaseLanguage)
    }
    refreshLiveContentIfNeeded(configuration: session.configuration, requestID: requestID)
    if preparesWholePreview { prepareWholePreview(configuration: configuration, requestID: requestID) }
    if viewportReadinessAttemptID == nil { requestTypingFocus() }
  }

  private func contentAppeared() {
    synchronizeNoQuitConfigurationLock()
    if !didRestoreActiveTestSelection {
      didRestoreActiveTestSelection = true
      restorePersistedTestSelection()
      visualFocus.set(true)
    }
    refreshZipfNotice()
    if !session.hasStarted { refreshPaceTarget() }
    if interruptedWholePreview { reset() }
  }

  private func prepareWholePreview(configuration: TestConfiguration, requestID: UUID,
    generatedSession: TypingSession? = nil) {
    let scores = weakSpotScores, decoration = wordDecorationState
    wholePreviewTask.start(operation: {
      let generated: TypingSession
      if let generatedSession { generated = generatedSession }
      else { generated = try await wholePreviewPrepare(configuration, scores, decoration) }
      try Task.checkCancellation()
      let base = generated.withElapsedClock()
      while true {
        try Task.checkCancellation()
        let style = promptRenderStyle
        let paceTarget = paceGuideTarget(currentPrompt: base.prompt)
        var candidate = base
        candidate.configurePace(wpm: paceTarget, style: style.paceCaretStyle)
        let pacePolicy = PromptRenderSessionPolicy(session: candidate,
          highlightMode: style.highlightMode, usesTapePractice: style.usesTapePractice,
          mainCaretDrawsMarker: style.caretStyle.drawsMarker,
          paceCaretDrawsMarker: style.paceCaretStyle.drawsMarker)
        if allowsWholePreviewViewportPreparation(candidate, style: style),
          try await WholePreviewViewportAdmission.check(session: candidate, style: style) {
          return PreparedWholePreviewResult(session: candidate, rendering: nil,
            layout: nil, layoutWidth: nil, style: style,
            paceTargetWpm: paceTarget, paceGuideIndex: pacePolicy.paceGuideIndex)
        }
        let rendering = try await wholePreviewRender(candidate, style)
        try Task.checkCancellation()
        var layout: PromptFieldTextLayout?
        var layoutWidth: CGFloat?
        if let map = rendering.compositionTextMap, map.fieldRuns.count > 5_000,
          !practiceVisualEffect.usesASL, !practiceVisualEffect.usesChoo {
          while wholePreviewFieldWidth == nil {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 20_000_000)
          }
          let width = wholePreviewFieldWidth!
          let font = practicePromptNSFont(size: settings.fontSize)
          layout = try await wholePreviewLayout(map, width, font,
            candidate.configuration.usesJoiningScriptPrompt ? 8 : 12,
            candidate.configuration.usesRightToLeftPrompt,
            candidate.configuration.usesJoiningScriptPrompt)
          layoutWidth = width
        }
        let layoutStillMatches = layout.map {
          $0.matchesMetrics(width: wholePreviewFieldWidth ?? 0,
            font: practicePromptNSFont(size: settings.fontSize),
            lineSpacing: candidate.configuration.usesJoiningScriptPrompt ? 8 : 12,
            rightToLeft: candidate.configuration.usesRightToLeftPrompt,
            joinsLetters: candidate.configuration.usesJoiningScriptPrompt)
        } ?? true
        guard style == promptRenderStyle,
          paceTarget == paceGuideTarget(currentPrompt: base.prompt), layoutStillMatches
        else { continue }
        return PreparedWholePreviewResult(session: candidate, rendering: rendering,
          layout: layout, layoutWidth: layoutWidth,
          style: style, paceTargetWpm: paceTarget, paceGuideIndex: pacePolicy.paceGuideIndex)
      }
    }) { result in
      guard requestID == liveContentRequestID, isPreparingWholePreview else { return }
      guard practiceShowsAllSetting && practiceTapeMode == .off else { reset(); return }
      guard self.configuration == configuration else { reset(); return }
      guard !session.hasStarted, session.configuration == configuration else { return }
      switch result {
      case .success(let prepared):
        guard prepared.style == promptRenderStyle,
          prepared.paceTargetWpm == paceGuideTarget(currentPrompt: prepared.session.prompt),
          prepared.layoutWidth == nil || prepared.layoutWidth == wholePreviewFieldWidth,
          prepared.layout.map({ $0.matchesMetrics(width: wholePreviewFieldWidth ?? 0,
            font: practicePromptNSFont(size: settings.fontSize),
            lineSpacing: prepared.session.configuration.usesJoiningScriptPrompt ? 8 : 12,
            rightToLeft: prepared.session.configuration.usesRightToLeftPrompt,
            joinsLetters: prepared.session.configuration.usesJoiningScriptPrompt) }) ?? true,
          prepared.paceGuideIndex == PromptRenderSessionPolicy(session: prepared.session,
            highlightMode: prepared.style.highlightMode, usesTapePractice: prepared.style.usesTapePractice,
            mainCaretDrawsMarker: prepared.style.caretStyle.drawsMarker,
            paceCaretDrawsMarker: prepared.style.paceCaretStyle.drawsMarker).paceGuideIndex,
          prepared.rendering != nil || allowsWholePreviewViewportPreparation(prepared.session, style: prepared.style)
        else {
          prepareWholePreview(configuration: configuration, requestID: requestID,
            generatedSession: prepared.session)
          return
        }
        activePaceTargetWpm = prepared.paceTargetWpm
        preparedWholePreviewRendering = prepared.rendering.map { rendering in
          .init(attemptID: prepared.session.automaticInputAttemptID,
            typedSnapshot: prepared.session.typed,
            rendering: rendering, layout: prepared.layout, style: prepared.style,
            paceGuideIndex: prepared.paceGuideIndex)
        }
        if usesPreparedPromptViewport, prepared.rendering != nil {
          viewportFallbackAttemptID = prepared.session.automaticInputAttemptID
        }
        session = prepared.session
        viewportReadinessAttemptID = prepared.rendering == nil ? prepared.session.automaticInputAttemptID : nil
        isPreparingWholePreview = false
        if session.configuration.language == .mixedLanguages {
          polyglotReturnLanguage = session.configuration.polyglotBaseLanguage
        }
        persistActiveTestSelection()
        if session.configuration.modifiers.contains(.listening) {
          NativeSpeech.shared.speak(session.prompt, language: session.configuration.wordPoolBaseLanguage)
        }
        if !isPreparingPracticePrompt { requestTypingFocus() }
      case .failure:
        isPreparingWholePreview = false
        viewportReadinessAttemptID = nil
        preparedWholePreviewRendering = nil
        session = TypingSession(configuration: configuration, prompt: "",
          initializationFailure: "无法准备完整练习，请重新开始或切换显示设置。",
          weakSpotScores: scores, wordDecorationState: decoration).withElapsedClock()
      }
      synchronizeNoQuitConfigurationLock()
    }
  }

  private func allowsWholePreviewViewportPreparation(_ candidate: TypingSession, style: PromptRenderStyle) -> Bool {
    let effect = PracticeVisualEffect.make(modifiers: candidate.configuration.modifiers)
    guard usesPreparedPromptViewport, compositionText.isEmpty, !candidate.isFinished,
      viewportFallbackAttemptID != candidate.automaticInputAttemptID,
      PracticeLineDisplayPolicy.shouldShowAllLines(settingEnabled: practiceShowsAllSetting,
        tapeMode: practiceTapeMode, configuration: candidate.configuration),
      !style.usesTapePractice, !effect.usesASL, !effect.usesChoo,
      PromptFieldProjectionPolicy.supports(candidate.configuration)
    else { return false }
    return true
  }

  private func synchronizeNoQuitConfigurationLock() {
    settings.setNoQuitConfigurationLock(
      !NoQuitConfigurationChangePolicy.allowsRestartingChange(for: session),
      for: noQuitConfigurationLockOwnerID)
  }

  private func refreshLiveContentIfNeeded(configuration: TestConfiguration, requestID: UUID) {
    guard let source = LivePracticeContentSource.selected(for: configuration) else { return }
    isLoadingLiveContent = true
    liveContentMessage = source == .poetry
      ? "正在获取随机\(source.displayName)；失败时继续使用离线内容。"
      : "正在获取随机\(source.displayName)；初始化失败时最多尝试三次。"
    liveContentTask?.cancel()
    liveContentTaskID = UUID()
    liveContentTask = Task {
      // A later synchronous reset can retire this task before its first turn.
      // Do not start transport work for an owner which is already obsolete.
      guard !Task.isCancelled, requestID == liveContentRequestID else { return }
      let firstContent = await liveContentFetch(source, configuration.language)
      var content = firstContent
      var preparedPrompt: LivePracticePrompt?
      var preparedContinuation: LivePracticePrompt?
      var preparedLiveSession: TypingSession?
      var failedGenerationAttempts = 0
      while !Task.isCancelled {
        let wholePreview = practiceShowsAllSetting && practiceTapeMode == .off
        if let pendingContent = content {
          content = await pendingContent.fillingInitialPrompt(for: configuration,
            showAllLines: wholePreview) {
              await liveContentFetch(source, configuration.language)
            }
        }
        if content?.text.isEmpty != false {
          // Poetry false disables its source in the reference generator;
          // encyclopedia rejection instead reaches the shared init budget.
          if content == nil && source == .poetry { break }
          failedGenerationAttempts += 1
          if failedGenerationAttempts == 3 { break }
          guard !Task.isCancelled, requestID == liveContentRequestID else { return }
          content = await liveContentFetch(source, configuration.language)
          continue
        }
        // Display settings can change while a later section is in flight.
        // Fill the current budget before constructing its final descriptor.
        if wholePreview == (practiceShowsAllSetting && practiceTapeMode == .off), let current = content {
          do {
            preparedPrompt = try await livePromptPrepare(current, configuration, wholePreview)
            preparedContinuation = try await current.preparingContinuationDescriptor(
              for: configuration, showAllLines: wholePreview)
            if let prompt = preparedPrompt {
              preparedLiveSession = try await liveSessionPrepare(
                configuration, prompt, preparedContinuation, session.liveWeakSpotScores,
                session.liveWordDecorationState, wholePreview)
            }
          } catch { return }
          guard !Task.isCancelled, requestID == liveContentRequestID else { return }
          if wholePreview == (practiceShowsAllSetting && practiceTapeMode == .off) { break }
        }
      }
      guard !Task.isCancelled, requestID == liveContentRequestID else { return }
      liveContentTask = nil
      isLoadingLiveContent = false
      guard LivePracticeContentReplacementPolicy.shouldApply(
        hasStarted: session.hasStarted, currentConfiguration: session.configuration,
        requestedConfiguration: configuration)
      else {
        liveContentMessage = content.map { "已获取\($0.attribution)，为避免打断输入，本轮仍使用现有提示。" }
          ?? "无法获取随机\(source.displayName)；输入已经开始，本轮保持现有练习。"
        return
      }
      if content == nil && source == .poetry {
        // Keep the poetry provider's false outcome separate from rejection.
        // The replacement guard above protects already-started attempts.
        synchronizeNoQuitConfigurationLock()
        let failedModifier: TestModifier = source == .poetry ? .poetryStream : .referenceStream
        settings.testModifiers.removeAll { $0 == failedModifier }
        reset(restarting: true)
        liveContentMessage = "无法获取随机\(source.displayName)，已关闭该内容来源并重新开始离线练习。"
        return
      }
      if content?.text.isEmpty != false {
        session = TypingSession(configuration: configuration, prompt: "",
          initializationFailure: "连续三次无法生成在线练习；请重试或关闭内容来源。",
          weakSpotScores: session.liveWeakSpotScores,
          wordDecorationState: session.liveWordDecorationState).withElapsedClock()
        liveContentStreamingActive = false
        liveContentMessage = "在线练习初始化失败，已停止；内容来源保持开启。"
        synchronizeNoQuitConfigurationLock()
        return
      }
      guard let content else { return }
      guard let preparedLiveSession else { return }
      practiceSoundPlayer().beginPracticeAttempt()
      session = preparedLiveSession.withElapsedClock()
      liveContentStreamingActive = true
      liveContentMessage = "已载入\(content.attribution)。"
      refreshPaceTarget()
      awaitViewportPresentationIfNeeded()
      if configuration.modifiers.contains(.listening) {
        NativeSpeech.shared.speak(session.prompt, language: session.configuration.wordPoolBaseLanguage)
      }
      if viewportReadinessAttemptID == nil { requestTypingFocus() }
      prefetchLiveContentIfNeeded()
    }
  }

  private func prefetchLiveContentIfNeeded(allowsGeneration: Bool = false) {
    let generatesNextWord = !session.needsLiveContentPrefetch
      && allowsGeneration && session.needsLiveContentGeneration
    guard liveContentStreamingActive, liveContentTask == nil,
      session.needsLiveContentPrefetch || generatesNextWord,
      let source = LivePracticeContentSource.selected(for: session.configuration) else { return }
    let configuration = session.configuration
    let requestID = liveContentRequestID
    let attemptID = session.automaticInputAttemptID
    guard pageSessionStore.acceptsAttemptCallback(for: attemptID) else { return }
    let taskID = UUID(); liveContentTaskID = taskID
    isLoadingLiveContent = true
    liveContentMessage = "正在续取\(source.displayName)。"
    liveContentTask = Task {
      defer {
        if liveContentTaskID == taskID {
          liveContentTask = nil; isLoadingLiveContent = false
        }
      }
      var requestsGeneratorWord = generatesNextWord
      while !Task.isCancelled,
        pageSessionStore.acceptsAttemptCallback(for: attemptID),
        (requestsGeneratorWord ? session.needsLiveContentGeneration : session.needsLiveContentPrefetch) {
        let content = await liveContentFetch(source, configuration.language)
        guard !Task.isCancelled, requestID == liveContentRequestID,
          pageSessionStore.acceptsAttemptCallback(for: attemptID),
          LivePracticeContentContinuationPolicy.matchesGeneration(current: session.configuration, requested: configuration),
          !session.isFinished else { return }
        if requestsGeneratorWord {
          liveContentTask = nil
          isLoadingLiveContent = false
          // Demand belongs to the forward transition that requested it;
          // consuming the final retained field does not create fresh demand.
          guard session.needsLiveContentGeneration else { return }
          guard let content, content.source == source else {
            let canDisableSource = NoQuitConfigurationChangePolicy.allowsRestartingChange(for: session)
            // The pinned poetry provider converts failures to false; the
            // encyclopedia provider rejects instead. Its rejection reaches
            // generator failure without requesting a source toggle.
            if canDisableSource && source == .poetry && pageSession.practice == nil {
              let failedModifier: TestModifier = source == .poetry ? .poetryStream : .referenceStream
              settings.testModifiers.removeAll { $0 == failedModifier }
              persistActiveTestSelection(for: session.configuration.with(
                modifiers: session.configuration.modifiers.filter { $0 != failedModifier }))
            }
            liveContentStreamingActive = false
            session.failLiveContentFetch()
            synchronizeNoQuitConfigurationLock()
            liveContentMessage = "无法生成下一个在线词，练习已停止。"
            if canDisableSource && source == .poetry && content == nil && pageSession.practice != nil {
              recoverPublishedPoetryFailure(attemptID: attemptID)
            }
            return
          }
          guard !content.text.isEmpty,
            session.acceptGeneratedLiveContent(content.sectionDescriptor) else {
            liveContentStreamingActive = false
            session.failLiveContentGeneration()
            synchronizeNoQuitConfigurationLock()
            liveContentMessage = "在线段落无法生成下一个词；练习已停止，内容来源保持开启。"
            return
          }
          liveContentMessage = "已生成\(content.attribution)的下一个词。"
          return
        }
        if content == nil && source == .encyclopedia {
          // A rejected side pull is outside the reference generator's catch.
          // Contain it at the native task boundary without turning it into a
          // false response, ending this attempt, or retrying in a tight loop.
          liveContentTask = nil
          isLoadingLiveContent = false
          liveContentMessage = "无法续取百科内容；本轮保留当前提示和内容来源。"
          return
        }
        if let content, content.source == source, content.text.isEmpty {
          // An empty side pull does not end addWord: the generator still
          // consumes its pending field or, when empty, pulls one section.
          // The generator branch terminates on another empty response.
          if session.needsLiveContentGeneration {
            requestsGeneratorWord = true
            continue
          }
          // Keep the active targets and source identity. Only later progress
          // requests another section; an empty reply must not spin or restart
          // the attempt as though the provider had failed.
          liveContentTask = nil
          isLoadingLiveContent = false
          liveContentMessage = "本次在线段落为空；内容来源保持开启。"
          if session.isWaitingForLiveContent {
            liveContentStreamingActive = false
            session.failLiveContentGeneration()
            synchronizeNoQuitConfigurationLock()
          }
          return
        }
        guard let content, content.source == source,
          session.appendLiveContent(content.sectionDescriptor) else {
          liveContentTask = nil
          isLoadingLiveContent = false
          guard NoQuitConfigurationChangePolicy.allowsRestartingChange(for: session) else {
            // Provider failure does not override an active NoQuit attempt.
            // Preserve its source and targets; later forward progress may
            // request a new section without a tight retry loop.
            liveContentMessage = "无法续取\(source.displayName)；NoQuit 练习保持进行，内容来源未关闭。"
            return
          }
          liveContentStreamingActive = false
          session.failLiveContentFetch()
          // A restartable source failure ends the old attempt before changing
          // configuration. Keep every unrelated modifier on the new attempt.
          synchronizeNoQuitConfigurationLock()
          if pageSession.practice != nil {
            liveContentMessage = "无法续取\(source.displayName)，本轮练习已停止。"
            if source == .poetry && content == nil { recoverPublishedPoetryFailure(attemptID: attemptID) }
            return
          }
          let failedModifier: TestModifier = source == .poetry ? .poetryStream : .referenceStream
          settings.testModifiers.removeAll { $0 == failedModifier }
          reset(restarting: true)
          liveContentMessage = "无法续取\(source.displayName)，已关闭该内容来源并重新开始离线练习。"
          return
        }
        liveContentMessage = "已续接\(content.attribution)。"
      }
      guard !Task.isCancelled, requestID == liveContentRequestID,
        pageSessionStore.acceptsAttemptCallback(for: attemptID) else { return }
      liveContentTask = nil
      isLoadingLiveContent = false
    }
  }

  private var hasLockedCustomTextSource: Bool {
    // Imported challenge files are ephemeral too: protect them like saved long text.
    activeLongSavedText != nil || activeVerifiedScript != nil || pageSession.practice?.scope.finiteTextSource != nil
  }

  private var quickRestartRequiresProtection: Bool {
    QuickRestartSafetyPolicy.requiresShift(
      for: session.configuration, savedLongText: hasLockedCustomTextSource)
  }

  private var commandBailoutAvailable: Bool {
    CommandBailoutPolicy.isAvailable(
      for: session.configuration, savedLongText: hasLockedCustomTextSource)
  }

  private var shouldBailOutFromControls: Bool {
    hasLockedCustomTextSource || session.configuration.isInfinite
  }

  private var infiniteIncompatibleModifiers: [TestModifier] {
    practiceRequestedModifiers.filter(TestModifierPolicy.finiteDurationOnly.contains)
  }

  private var offersInfiniteSelection: Bool {
    mode == .time || mode == .words
      || (mode == .custom && [.time, .words].contains(customTextCompletion))
  }

  private func infiniteBinding(_ value: Binding<Int>, fallback: Int) -> Binding<Bool> {
    Binding(
      get: { value.wrappedValue == 0 },
      set: { enabled in
        guard acceptsRestartingConfigurationChange() else { return }
        guard !enabled || infiniteIncompatibleModifiers.isEmpty else { return }
        value.wrappedValue = enabled ? 0 : fallback
        reset()
      })
  }

  private func applyFiniteFunboxLimitIfNeeded(for modifiers: [TestModifier]) {
    guard let fallback = FiniteFunboxLimitPolicy.fallbackLimit(
      for: mode, customTextCompletion: customTextCompletion, modifiers: modifiers)
    else { return }
    switch mode {
    case .time where duration == 0:
      duration = fallback
    case .words where wordLimit == 0:
      wordLimit = fallback
    case .custom where customTextCompletion == .time && customTextDuration == 0:
      customTextDuration = fallback
    case .custom where customTextCompletion == .words && customTextWordLimit == 0:
      customTextWordLimit = fallback
    default:
      break
    }
  }

  private func loadSavedCustomText(_ selection: SavedCustomTextSelection, continuous: Bool) {
    guard selectMode(.custom) else { return }
    wordPractice = nil
    customTextSource = nil
    customTextRecovery.acceptExplicitSource()
    activeChallengeID = nil
    activeVerifiedScript = nil
    guard selection.isLong else {
      activeLongSavedText = nil
      customText = selection.text
      reset()
      return
    }
    let progress = LongSavedTextProgress.resumingOffset(selection.longProgress ?? 0, in: selection.text)
    let active = ActiveLongSavedText(
      id: selection.id, title: selection.title, text: selection.text,
      progress: progress, continuous: continuous)
    activeLongSavedText = active
    customText = active.currentChunk
    customTextCompletion = .finish
    customTextOrdering = .inOrder
    customTextPipeDelimiter = false
    reset()
  }

  private func applyGeneratedCustomText(_ generatedText: String, appending: Bool) {
    let existing = appending ? customText.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    let separator = existing.isEmpty ? "" : " "
    let nextText = CustomTextPolicy.clamped(existing + separator + generatedText)
    guard CustomTextPolicy.isValid(nextText) else { return }
    guard selectMode(.custom) else { return }
    activeChallengeID = nil
    activeLongSavedText = nil
    wordPractice = nil
    customTextSource = nil
    customTextRecovery.acceptExplicitSource()
    customText = nextText
    customTextCompletion = .finish
    customTextOrdering = .inOrder
    customTextPipeDelimiter = false
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
      nextProgress = active.continuous ? 0 : LongSavedTextProgress.offsetAfterCompletingChunk(
        in: active.text, from: active.progress)
    case .bailedOut, .failed, .invalidAFK:
      nextProgress = LongSavedTextProgress.advancedOffset(
        in: active.text, from: active.progress, session: session)
    case .active, .abandoned:
      return false
    }
    record.longProgress = nextProgress
    var updated = active
    updated.progress = nextProgress
    activeLongSavedText = updated
    customText = updated.currentChunk
    try? modelContext.save()
    return true
  }

  private func armLongTestBailout() {
    let message = "再次在 0.2 秒内按 Shift+Enter，可中止并查看结果；符合资格时保存到本机。"
    bailoutConfirmationMessage = message
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      guard bailoutConfirmationMessage == message else { return }
      bailoutConfirmationMessage = nil
    }
  }

  private func showQuickRestartProtectionNotice() {
    let shortcut: String
    switch practiceQuickRestartKey {
    case .escape: shortcut = "Shift+Esc"
    case .tab: shortcut = "Shift+Tab"
    case .enter: shortcut = "Shift+Enter"
    case .off: return
    }
    let message = "长测试已保护：按 \(shortcut) 或点击“重新开始”确认。"
    quickRestartProtectionSequence &+= 1
    let sequence = quickRestartProtectionSequence
    quickRestartProtectionMessage = message
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 4_000_000_000)
      guard quickRestartProtectionSequence == sequence else { return }
      quickRestartProtectionMessage = nil
    }
  }

  private func startRepeatedAttempt(_ repeatedSession: TypingSession, tags: [String]) {
    wholePreviewTask.cancel()
    isPreparingWholePreview = false
    viewportReadinessAttemptID = nil
    preparedWholePreviewRendering = nil
    interruptedWholePreview = false
    restartLockMessage = nil
    compositionText = ""
    keyboardGuideFeedback = nil
    websiteKeymapFeedback.reset()
    lastTimeWarningSecond = nil
    lastClockTickSecond = 0
    liveStatsClockSignal.second = 0
    timerHealth = .init()
    NativeSpeech.shared.stop()
    practiceSoundPlayer().beginPracticeAttempt()
    absorbLiveWeakSpotScores(from: session)
    activeSessionTags = ResultTagPolicy.normalized(tags)
    session = repeatedSession.withWeakSpotScores(weakSpotScores).withWordDecorationState(wordDecorationState).withElapsedClock()
    isSamePromptRepeatAttempt = true
    isRepeatedPaceAttempt = settings.repeatedPace
    let shouldUseRepeatedPace = isRepeatedPaceAttempt && settings.paceGuideMode == .off
    activePaceTargetWpm = paceGuideTarget(
      usingRepeatedPace: shouldUseRepeatedPace ? lastFinishedWpm : nil)
    session.configurePace(wpm: activePaceTargetWpm, style: committedPracticeDraft?.presentation.paceCaretStyle ?? settings.paceCaretStyle)
    awaitViewportPresentationIfNeeded()
    if session.configuration.modifiers.contains(.listening) {
      NativeSpeech.shared.speak(session.prompt, language: session.configuration.wordPoolBaseLanguage)
    }
    if viewportReadinessAttemptID == nil { requestTypingFocus() }
  }

  private func absorbLiveWeakSpotScores(from session: TypingSession) {
    weakSpotScores = session.liveWeakSpotScores
    wordDecorationState = session.liveWordDecorationState
  }

  private func refreshPaceTarget() {
    activePaceTargetWpm = paceGuideTarget()
    session.configurePace(wpm: activePaceTargetWpm, style: committedPracticeDraft?.presentation.paceCaretStyle ?? settings.paceCaretStyle)
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
      return .init(result: result)
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
        "\(practiceAppearance.unit.formatted(wpm: average.wpm)) \(practiceAppearance.unit.displayName)")
    }
    if settings.showAverage.showsAccuracy {
      metrics.append("\(ResultMetricPresentation.accuracy(average.accuracy, alwaysShowDecimalPlaces: practiceAppearance.alwaysShowDecimalPlaces)) 准确率")
    }
    return "近 \(average.count) 次平均：\(metrics.joined(separator: " · "))"
  }

  private var todayPracticeSummary: TodayPracticeSummary {
    TodayPracticeAggregation.summary(
      persisted: savedResults.map {
        ResultMetric(
          id: $0.id, finishedAt: $0.finishedAt, wpm: $0.wpm, accuracy: $0.accuracy,
          preciseAccuracy: $0.preciseAccuracy,
          typingSeconds: $0.engagedDuration)
      },
      currentProcess: currentProcessPractice)
  }

  private var personalBestNotice: String? {
    guard settings.showPersonalBest else { return nil }
    guard CurrentPersonalBestPolicy.isConfigurationEligible(configuration) else {
      return "本机个人最佳：当前测试不计入 PB"
    }
    guard let ledger = personalBestLedgers.first?.ledger else {
      return "本机个人最佳：账本不可用，请备份数据库后修复"
    }
    guard let personalBest = ledger.best(configuration: configuration)?.row
    else {
      return "本机个人最佳：暂无符合资格的同类成绩"
    }
    return "本机个人最佳：\(practiceAppearance.unit.formatted(wpm: personalBest.wpm, alwaysShowDecimalPlaces: true)) \(practiceAppearance.unit.displayName) · \(ResultMetricPresentation.accuracy(personalBest.accuracy, alwaysShowDecimalPlaces: practiceAppearance.alwaysShowDecimalPlaces)) 准确率"
  }

  private func startWeakSpotPractice() {
    guard let weakSpotPrompt else { return }
    startWeakSpotPractice(prompt: weakSpotPrompt, language: language)
  }

  private func startWeakSpotPractice(
    prompt weakSpotPrompt: String, language weakSpotLanguage: TypingLanguage
  ) {
    guard selectMode(.custom) else { return }
    wordPractice = nil
    customTextSource = nil
    customTextRecovery.acceptExplicitSource()
    activeChallengeID = nil
    language = weakSpotLanguage
    customText = weakSpotPrompt
    customTextCompletion = .words
    customTextWordLimit = weakSpotPrompt.split(separator: " ").count
    customTextOrdering = .inOrder
    customTextPipeDelimiter = false
    reset()
  }

  private func paceGuideTarget(usingRepeatedPace repeatedWpm: Double? = nil,
    currentPrompt: String? = nil, draft: WebsiteConfigNativeDraft? = nil) -> Double? {
    let paceMode = (draft ?? committedPracticeDraft)?.behavior.paceGuideMode ?? settings.paceGuideMode
    let customWpm = (draft ?? committedPracticeDraft)?.behavior.paceGuideCustomWpm ?? settings.paceGuideCustomWpm
    if paceMode == .off, let repeatedWpm {
      return PaceGuidePolicy.validTarget(repeatedWpm)
    }
    if paceMode == .personalBest || paceMode == .activeTagPersonalBest {
      guard personalBestLedgers.first?.ledger != nil else { return nil }
    }
    let samples = savedResults.compactMap { record -> PaceGuideSample? in
      guard let result = record.portableResult else { return nil }
      return .init(result: result)
    }
    return PaceGuidePolicy.targetWpm(
      mode: paceMode,
      customWpm: customWpm,
      configuration: configuration,
      samples: samples,
      activeTags: activeSessionTags,
      personalBestLedger: personalBestLedgers.first?.ledger,
      accountTags: account.hasAccountTagDirectory ? account.accountTags : nil,
      selectedAccountTagIDs: (try? account.accountTagPostingSelection()) ?? [],
      accountTagHistoryPersonalBests: account.accountTagHistoryPersonalBests,
      lastTestWpm: repeatedWpm ?? lastFinishedWpm,
      currentPrompt: currentPrompt ?? session.prompt
    )
  }

  private var paceGuideIndex: Int? {
    guard let frame = session.paceCaretFrame() else { return nil }
    return session.paceCaretGlyphIndex(for: frame.target)
  }

  private var paceGuideProgressDescription: String {
    guard let paceGuideIndex else { return "等待开始" }
    let delta = session.typedCharacterCount - paceGuideIndex
    if delta == 0 { return "同步" }
    return delta > 0 ? "领先 \(delta) 字符" : "落后 \(-delta) 字符"
  }

  private var activeTheme: ResolvedTheme {
    publishedPresentation?.appearance.theme ?? themePreviewPresentation.theme
  }

  private var themePreviewPresentation: ThemePreviewPresentation {
    let previewTarget = themeQuickPickerScope != nil ? quickPickerThemePreviewTarget
      : showingCommandPalette ? commandThemePreviewTarget : nil
    return .init(settings: settings, systemColorScheme: systemColorScheme, previewTarget: previewTarget)
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
        id: "challenges", title: "打开离线挑战", subtitle: "加载固定配置并逐项验收完整挑战条件",
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
        id: "notification-history", title: "打开会话通知", subtitle: "最近 25 条本机提示和错误详情", systemImage: "bell.badge",
        keywords: ["notification", "history", "通知历史", "会话", "详情"], group: .library),
      .init(
        id: "reward-inbox", title: "打开奖励收件箱", subtitle: "查看邮件并领取 XP 或徽章奖励", systemImage: "tray",
        keywords: ["inbox", "收件箱", "奖励", "xp"], group: .connections),
      ReleaseHistoryCommand.item,
    ]
    items.append(contentsOf: NoStressResultCommandCatalog.items)
    items.append(contentsOf: CommandPaletteUtilityCatalog.items(
      randomThemeEnabled: settings.randomThemeMode.isEnabled && !settings.followSystemTheme,
      authenticated: account.currentUser != nil,
      websiteProfileActive: committedPracticeDraft != nil && pageSession.savedApplication == nil
        && pageSession.configurationDeparture == nil
        && pageSessionStore.restartController?.isPreparing != true))
    items.append(contentsOf: NavigationCommandCatalog.items)
    if session.hasStarted, !session.isFinished, commandBailoutAvailable {
      items.append(.init(
        id: "bailout", title: "中止长测试…", subtitle: "确认后查看结果，符合资格时保存到本机",
        systemImage: "figure.run", keywords: ["bail", "bailout", "中止", "退出"], group: .practice))
    }
    items.append(contentsOf: QuickTestParameterCommandCatalog.items)
    items.append(contentsOf: QuoteCommandCatalog.items(hasFavorites: hasFavoriteQuotesInCurrentSource))
    items.append(contentsOf: PracticePreferenceCommandCatalog.items)
    items.append(contentsOf: BehaviorCommandCatalog.items)
    items.append(contentsOf: PracticeThresholdCommandCatalog.items)
    items.append(contentsOf: FunboxCommandCatalog.items.filter { item in
      guard let draft = committedPracticeDraft, let target = FunboxCommandCatalog.target(for: item.id) else { return true }
      return WebsiteConfigFunboxMemory.proposal(for: target, in: draft) != nil
    })
    items.append(contentsOf: ResultTagCommandCatalog.items(
      active: settings.activeResultTags, historical: knownHistoricalResultTags))
    items.append(contentsOf: InputRuleCommandCatalog.items)
    items.append(contentsOf: OfficialLayoutCommandCatalog.items)
    items.append(contentsOf: SoundCommandCatalog.items.filter { item in
      committedPracticeDraft == nil || SoundCommandCatalog.target(for: item.id)?.websiteValue != .null
    })
    if committedPracticeDraft != nil { items.append(WebsiteSoundVolumePresentation.item) }
    items.append(contentsOf: CaretCommandCatalog.items.filter { item in
      committedPracticeDraft == nil || CaretCommandCatalog.target(for: item.id)?.visibleInWebsiteCommandPalette == true
    })
    items.append(contentsOf: PaceCaretCommandCatalog.items.map { item in
      guard committedPracticeDraft != nil else { return item }
      let target = PaceCaretCommandCatalog.target(for: item.id)
      if target == .customSpeed { return WebsitePaceSpeedPresentation.item }
      return .init(id: item.id,
        title: target?.websiteMode == "tagPb" ? "节奏引导：账户标签个人最佳" : item.title,
        subtitle: "保存配速模式并请求重开", systemImage: item.systemImage, keywords: item.keywords, group: item.group)
    })
    items.append(contentsOf: AppearanceCommandCatalog.items)
    items.append(contentsOf: KeyboardGuideCommandCatalog.items)
    items.append(pageSessionStore.ownsConfigurationSelection ? WebsiteKeymapSizePresentation.item : KeyboardGuideSizeCommand.item)
    items.append(contentsOf: KeyboardGuideLayoutCommandCatalog.items.map { item in
      guard pageSessionStore.ownsConfigurationSelection else { return item }
      return .init(id: item.id, title: item.title, subtitle: "保存键盘布局并请求重开",
        systemImage: item.systemImage, keywords: item.keywords, group: item.group)
    })
    items.append(contentsOf: FontFamilyCommandCatalog.items(
      hasLocalFont: settings.hasLocalPracticeFont,
      usesLocalFont: settings.isUsingLocalPracticeFont))
    items.append(contentsOf: ThemeCommandCatalog.items(
      customThemes: settings.customThemes, favoriteThemeIDs: settings.favoriteThemeIDs))
    if let theme = settings.currentBuiltInThemeForFavoriteCommand(for: systemColorScheme) {
      items.append(CurrentThemeFavoriteCommandCatalog.item(
        theme: theme, isFavorite: settings.isFavoriteTheme(theme)))
    }
    items.append(contentsOf: CustomBackgroundCommandCatalog.items(
      hasBackground: settings.hasLocalBackground || !settings.customBackgroundURL.isEmpty))
    items.append(contentsOf: PresetCommandCatalog.items(
      presets: savedPresets.compactMap { preset in
        guard let definition = preset.applicableDefinition else { return nil }
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
    if let target = NoStressResultCommandCatalog.target(for: item.id) {
      usesNoStressResultPresentation = target.isEnabled
      return
    }
    if let action = CommandPaletteUtilityCatalog.action(for: item.id) {
      switch action {
      case .editCustomText:
        guard selectMode(.custom) else { return }
        activeChallengeID = nil
        reset()
      case .shareTestSettings:
        showingTestShare = true
      case .importSettingsJSON:
        settingsJSONCommand = .init(
          mode: .importSettings, initialJSON: "", initialError: nil)
      case .importWebsiteConfig:
        openWebsiteConfigImport()
      case .editWebsitePolyglot, .editWebsiteLayoutfluid:
        guard let publication = pageSession.presentation?.publication,
          pageSession.savedApplication == nil,
          pageSession.configurationDeparture == nil,
          pageSessionStore.restartController?.isPreparing != true else { return }
        let presentation = WebsiteSequenceCommandPresentation(publication: publication,
          kind: action == .editWebsitePolyglot ? .polyglot : .layoutFluid)
        if showingCommandPalette { queuedWebsiteSequenceCommand = presentation }
        else { websiteSequenceCommand = presentation }
      case .exportSettingsJSON:
        settingsJSONCommand = .exporting(page: pageSession) {
          try SettingsJSONCommandCodec.export(
              settings: practiceSettingsSnapshot,
              configuration: configuration,
              layoutFluidLayouts: settings.layoutFluidLayouts,
              testParameterMemory: .init(
                duration: duration,
                wordLimit: wordLimit,
                customTextDuration: customTextDuration,
                customTextWordLimit: customTextWordLimit,
                customTextSectionLimit: customTextSectionLimit))
        }
      case .nextRandomTheme:
        guard settings.randomThemeMode.isEnabled, !settings.followSystemTheme else { return }
        settings.randomizeTheme(for: systemColorScheme)
      case .signOut:
        guard account.currentUser != nil else { return }
        account.signOut()
        unreadNotificationCount = nil
      }
      return
    }
    if let target = NavigationCommandCatalog.target(for: item.id) {
      guard NoQuitNavigationPolicy.allows(target, for: session) else {
        restartLockMessage = "锁定重开已开启：请完成或放弃本次测试后再离开练习。"
        return
      }
      switch target {
      case .typingPage:
        focusRequest &+= 1
      case .leaderboards:
        syncInitialLeaderboard = .init(mode: nil, language: nil, period: .all)
        showingSync = true
      case .about:
        openWindow(id: "about")
      case .settings, .account:
        openSettings()
      case .profileSearch:
        showingProfileSearchCommandEditor = true
      case .fullscreen:
        let activeWindow = NSApp.keyWindow?.sheetParent ?? NSApp.keyWindow ?? NSApp.mainWindow
        activeWindow?.toggleFullScreen(nil)
      }
      return
    }
    if item.id == WebsiteSoundVolumePresentation.item.id {
      guard let publication = pageSession.presentation?.publication,
        pageSession.savedApplication == nil, pageSession.configurationDeparture == nil,
        pageSessionStore.restartController?.isPreparing != true else { return }
      let presentation = WebsiteSoundVolumePresentation(publication: publication)
      if showingCommandPalette { queuedWebsiteSoundVolume = presentation } else { websiteSoundVolume = presentation }
      return
    }
    if let target = SoundCommandCatalog.target(for: item.id) {
      if pageSessionStore.ownsConfigurationSelection { runWebsiteLiveCommand(.sound(target)); return }
      target.apply(to: settings, onConfigurationSave: persistExplicitTestConfiguration)
      switch target.preview {
      case .click(let style):
        TypingFeedbackSound.shared.previewClick(style: style, volume: settings.soundVolume)
      case .error(let style):
        TypingFeedbackSound.shared.previewError(style: style, volume: settings.soundVolume)
      case .timeWarning:
        TypingFeedbackSound.shared.playTimeWarning(
          style: settings.timeWarningSoundStyle, volume: settings.soundVolume)
      case nil:
        break
      }
      return
    }
    if let target = CaretCommandCatalog.target(for: item.id) {
      if pageSessionStore.ownsConfigurationSelection { runWebsiteLiveCommand(.caret(target)); return }
      if target.exitsChallenge { activeChallengeID = nil }
      target.apply(to: settings, onConfigurationSave: persistExplicitTestConfiguration)
      return
    }
    if item.id == WebsitePaceSpeedPresentation.item.id {
      guard let publication = pageSession.presentation?.publication,
        pageSession.savedApplication == nil, pageSession.configurationDeparture == nil,
        pageSessionStore.restartController?.isPreparing != true else { return }
      let presentation = WebsitePaceSpeedPresentation(publication: publication)
      if showingCommandPalette { queuedWebsitePaceSpeed = presentation } else { websitePaceSpeed = presentation }
      return
    }
    if let target = PaceCaretCommandCatalog.target(for: item.id) {
      if pageSessionStore.ownsConfigurationSelection { runWebsitePaceCommand(target); return }
      switch target {
      case .mode:
        target.apply(to: settings, onConfigurationSave: persistExplicitTestConfiguration)
      case .customSpeed:
        showingPaceGuideSpeedEditor = true
      }
      return
    }
    if let target = AppearanceCommandCatalog.target(for: item.id) {
      if pageSessionStore.ownsConfigurationSelection { runWebsiteLiveCommand(.appearance(target)); return }
      guard target.apply(to: settings, requestedModifiers: practiceRequestedModifiers,
        onConfigurationSave: persistExplicitTestConfiguration) else {
        if case .highlight = target {
          funboxConfigurationMessage = "当前趣味模式仅支持“当前字符”或“关闭”提示高亮。"
        } else {
          funboxConfigurationMessage = "卷带模式不支持显示完整提示行。"
        }
        return
      }
      if target.exitsChallenge { activeChallengeID = nil }
      return
    }
    if let target = KeyboardGuideCommandCatalog.target(for: item.id) {
      if pageSessionStore.ownsConfigurationSelection { runWebsiteLiveCommand(.keymap(.display(target))); return }
      if target.exitsChallenge { activeChallengeID = nil }
      target.apply(to: settings, onConfigurationSave: persistExplicitTestConfiguration)
      return
    }
    if item.id == WebsiteKeymapSizePresentation.item.id || (item.id == KeyboardGuideSizeCommand.item.id && pageSessionStore.ownsConfigurationSelection) {
      guard let publication = pageSession.presentation?.publication,
        pageSession.savedApplication == nil, pageSession.configurationDeparture == nil,
        pageSessionStore.restartController?.isPreparing != true else { return }
      let presentation = WebsiteKeymapSizePresentation(publication: publication)
      if showingCommandPalette { queuedWebsiteKeymapSize = presentation } else { websiteKeymapSize = presentation }
      return
    }
    if item.id == KeyboardGuideSizeCommand.item.id {
      showingKeyboardGuideScaleEditor = true
      return
    }
    if let target = KeyboardGuideLayoutCommandCatalog.target(for: item.id) {
      if pageSessionStore.ownsConfigurationSelection { runWebsiteLiveCommand(.keymap(.layout(target))); return }
      if target.requiresRestart, !acceptsRestartingConfigurationChange() { return }
      if target.exitsChallenge { activeChallengeID = nil }
      target.apply(to: settings, onConfigurationSave: persistExplicitTestConfiguration)
      if target.requiresRestart { reset() }
      return
    }
    if let target = OfficialLayoutCommandCatalog.target(for: item.id) {
      if target.requiresRestart, !acceptsRestartingConfigurationChange() { return }
      if target.exitsChallenge { activeChallengeID = nil }
      target.apply(to: settings, onConfigurationSave: persistExplicitTestConfiguration)
      if target.requiresRestart { reset() }
      return
    }
    if let target = InputRuleCommandCatalog.target(for: item.id) {
      if pageSessionStore.ownsConfigurationSelection {
        runWebsiteLiveCommand(.inputRule(target))
        return
      }
      if target.requiresRestart, !acceptsRestartingConfigurationChange() { return }
      if target.exitsChallenge { activeChallengeID = nil }
      var savesConfiguration = false
      target.apply(to: settings, session: &session, onConfigurationSave: { savesConfiguration = true })
      if savesConfiguration { persistExplicitTestConfiguration() }
      if target.requiresRestart { reset() }
      return
    }
    if let target = BehaviorCommandCatalog.target(for: item.id) {
      if pageSessionStore.ownsConfigurationSelection {
        runWebsiteLiveCommand(.behavior(target))
        return
      }
      target.apply(to: settings, onConfigurationSave: persistExplicitTestConfiguration)
      if case .blindMode(let enabled) = target {
        session.setBlindMode(enabled)
        preparedWholePreviewRendering = nil
      }
      return
    }
    if let target = PracticeThresholdCommandCatalog.target(for: item.id) {
      if pageSessionStore.ownsConfigurationSelection {
        guard let publication = pageSession.presentation?.publication,
          pageSession.savedApplication == nil, pageSession.configurationDeparture == nil,
          pageSessionStore.restartController?.isPreparing != true else {
          account.localNotices.post("配置正在准备，请完成恢复后再修改阈值。"); return
        }
        if target.editorKind != nil {
          guard let presentation = WebsiteThresholdCommandPresentation(publication: publication, target: target) else { return }
          if showingCommandPalette { queuedWebsiteThresholdCommand = presentation }
          else { websiteThresholdCommand = presentation }
        } else { runWebsiteThresholdOffCommand(target, applicationID: publication.applicationID) }
        return
      }
      guard acceptsRestartingConfigurationChange() else { return }
      if let editor = target.editorKind {
        practiceThresholdEditorKind = editor
        return
      }
      if target.applyImmediate(to: settings, onConfigurationSave: {
        activeChallengeID = nil
        persistExplicitTestConfiguration()
      }) {
        reset()
      } else {
        account.localNotices.post("阈值未应用，原设置已保留。请检查配置存储。")
      }
      return
    }
    if let target = FunboxCommandCatalog.target(for: item.id) {
      if let draft = committedPracticeDraft {
        runWebsiteFunboxCommand(target, draft: draft)
        return
      }
      guard acceptsRestartingConfigurationChange() else {
        ConfigurationNoticeFeedback.conflict("锁定重开已开启：请完成或放弃本次测试。",
          notices: account.localNotices, locked: true)
        return
      }
      switch target {
      case .polyglot:
        guard language == .mixedLanguages
          || TestModifierPolicy.acceptsPolyglotAddition(to: practiceRequestedModifiers, mode: mode)
        else {
          reportFunboxConfigurationConflict("自选多语与当前趣味修饰器组合不兼容；已保留现有选择。")
          return
        }
        activeChallengeID = nil
        if language == .mixedLanguages {
          language = PolyglotReturnLanguagePolicy.languageAfterDisabling(
            current: language, base: polyglotReturnLanguage)
          polyglotReturnLanguage = nil
        } else {
          polyglotReturnLanguage = PolyglotReturnLanguagePolicy.baseWhenSelecting(
            .mixedLanguages, current: language, previous: polyglotReturnLanguage)
          language = .mixedLanguages
        }
        persistExplicitTestConfiguration()
        reset()
      case .clear, .modifier:
        if case .modifier(let modifier) = target,
           !practiceRequestedModifiers.contains(modifier),
           !TestModifierPolicy.acceptsInteractiveModifierAddition(
             modifier, to: practiceRequestedModifiers, language: language)
        {
          reportFunboxConfigurationConflict(
            "\(modifier.displayName) 与当前趣味修饰器组合不兼容；已保留现有选择。")
          return
        }
        guard let updated = FunboxCommandPolicy.updatedModifiers(
          for: target, current: practiceRequestedModifiers,
          hasStarted: session.hasStarted, language: language)
        else {
          restartLockMessage = "当前无限测试不支持这个修饰器；请先选择有限时长或字数。"
          return
        }
        let proposedLanguage = target == .clear
          ? PolyglotReturnLanguagePolicy.languageAfterDisabling(
            current: language, base: polyglotReturnLanguage)
          : language
        guard acceptsFunboxConfiguration(updated, language: proposedLanguage) else { return }
        settings.testModifiers = updated
        applyFiniteFunboxLimitIfNeeded(for: updated)
        if target == .clear {
          language = proposedLanguage
          polyglotReturnLanguage = nil
        }
        activeChallengeID = nil
        persistExplicitTestConfiguration()
        reset()
      }
      return
    }
    let knownResultTags = ResultTagCommandCatalog.knownTags(
      active: settings.activeResultTags, historical: knownHistoricalResultTags)
    if let target = ResultTagCommandCatalog.target(for: item.id, knownTags: knownResultTags) {
      if target == .create {
        showingActiveResultTagEditor = true
      } else if let updated = ResultTagCommandPolicy.updatedActiveTags(
        for: target, current: settings.activeResultTags)
      {
        updateActiveResultTags { settings.activeResultTags = updated }
      }
      return
    }
    if let target = PracticePreferenceCommandCatalog.target(for: item.id) {
      if target.requiresRestart, !acceptsRestartingConfigurationChange() { return }
      if target.exitsChallenge { activeChallengeID = nil }
      target.apply(to: settings, onConfigurationSave: persistExplicitTestConfiguration)
      if target.requiresRestart { reset() }
      return
    }
    if let selectedLanguage = LanguageCommandCatalog.target(for: item.id) {
      let changed = language != selectedLanguage
      guard selectLanguage(selectedLanguage) else { return }
      activeChallengeID = nil
      if !changed {
        languageChanged(to: selectedLanguage)
        refreshZipfNotice()
      }
      return
    }
    if let target = QuoteCommandCatalog.target(for: item.id) {
      if target == .favorites, !hasFavoriteQuotesInCurrentSource { return }
      guard selectMode(.quote) else { return }
      activeChallengeID = nil
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
      guard acceptsRestartingConfigurationChange() else { return }
      activeChallengeID = nil
    }
    if let target = QuickTestParameterCommandCatalog.target(for: item.id) {
      switch target {
      case .timed(let seconds):
        guard selectMode(.time) else { return }
        duration = seconds
      case .words(let count):
        guard selectMode(.words) else { return }
        wordLimit = count
      case .customTime:
        return
      case .customWords:
        return
      case .punctuation(let enabled):
        var selected = contentOptions
        selected.includePunctuation = enabled
        guard selectContentOptions(selected) else { return }
      case .numbers(let enabled):
        var selected = contentOptions
        selected.includeNumbers = enabled
        guard selectContentOptions(selected) else { return }
      }
      reset()
      return
    }
    if let target = ThemeCommandCatalog.target(for: item.id) {
      ThemeCommandApplication.apply(target, to: settings, onConfigurationSave: persistExplicitTestConfiguration)
      return
    }
    if let target = FontFamilyCommandCatalog.target(for: item.id) {
      fontFamilyCommandMessage = nil
      switch target {
      case .systemDesign, .knownIdentifier, .installedName:
        if !FontFamilyCommandApplication.apply(target, to: settings,
          onConfigurationSave: persistExplicitTestConfiguration) {
          fontFamilyCommandMessage = "此 Mac 当前无法使用所选字体。"
        } else if settings.hasLocalPracticeFont {
          fontFamilyCommandMessage = "已保存所选字体；本地字体文件已保留但未启用。"
        } else if case .knownIdentifier(let identifier) = target,
          !NativePracticeFont.isAvailable(identifier)
        {
          fontFamilyCommandMessage = "已保存所选字体；此 Mac 未安装时会暂时使用系统字体。"
        }
      case .customName:
        showingFontFamilyNameCommandEditor = true
      case .browseInstalled:
        installedFontCommandFamilies = NativeFontCatalog.installedFamilies
        showingInstalledFontCommandPicker = true
      case .localFile:
        showingLocalFontCommandImporter = true
      case .useLocalFile:
        if !settings.activateLocalPracticeFont() {
          fontFamilyCommandMessage = "无法重新启用本地字体文件。"
        }
      case .removeLocalFile:
        do {
          try settings.removeLocalPracticeFont()
        } catch {
          fontFamilyCommandMessage = error.localizedDescription
        }
      }
      return
    }
    if let target = CurrentThemeFavoriteCommandCatalog.target(for: item.id) {
      _ = CurrentThemeFavoriteCommandApplication.apply(
        target, to: settings, colorScheme: systemColorScheme, onConfigurationSave: persistExplicitTestConfiguration)
      return
    }
    if let target = CustomBackgroundCommandCatalog.target(for: item.id) {
      customBackgroundCommandMessage = nil
      switch target {
      case .editor(let kind):
        customBackgroundCommandEditorKind = kind
      case .localFile:
        showingCustomBackgroundCommandImporter = true
      case .remove:
        do {
          try CustomBackgroundCommandApplication.removeBackground(from: settings,
            onConfigurationSave: persistExplicitTestConfiguration) {
            try settings.removeLocalBackground()
          }
        } catch {
          customBackgroundCommandMessage = error.localizedDescription
        }
      case .fit:
        _ = CustomBackgroundCommandApplication.applyImmediate(target, to: settings,
          onConfigurationSave: persistExplicitTestConfiguration)
      }
      return
    }
    if let presetID = PresetCommandCatalog.presetID(for: item.id),
      let preset = savedPresets.first(where: { $0.id == presetID })?.applicableDefinition
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
      if selectMode(.time) { reset() }
    case "mode.words":
      if selectMode(.words) { reset() }
    case "mode.quote":
      if selectMode(.quote) { reset() }
    case "mode.zen":
      if selectMode(.zen) { reset() }
    case "mode.custom":
      if selectMode(.custom) { reset() }
    case "history": showingHistory = true
    case "weakSpots": showingWeakSpots = true
    case "presets": showingPresets = true
    case "challenges": showingChallenges = true
    case "savedTexts": showingSavedTexts = true
    case "data": showingDataMigration = true
    case "sync":
      guard acceptsLeavingPracticeNavigation() else { return }
      showingSync = true
    case "friends":
      guard acceptsLeavingPracticeNavigation() else { return }
      showingConnections = true
    case "notifications": showingNotifications = true
    case "notification-history": showingLocalNoticeHistory = true
    case "reward-inbox":
      guard acceptsLeavingPracticeNavigation() else { return }
      showingRewardInbox = true
    case ReleaseHistoryCommand.identifier: openWindow(id: "release-history")
    case "bailout": showingCommandBailoutConfirmation = true
    case QuoteFavoriteCommand.identifier:
      guard mode == .quote, availableQuotes.contains(where: { $0.id == selectedQuoteID }) else { return }
      toggleSelectedQuoteFavorite()
    default: break
    }
  }

  private func runWebsitePaceCommand(_ target: PaceCaretCommandTarget) {
    guard websiteBehaviorCommandTask == nil, let publication = pageSession.presentation?.publication,
      pageSession.savedApplication == nil, pageSession.configurationDeparture == nil,
      pageSessionStore.restartController?.isPreparing != true else {
      account.localNotices.post("配置正在准备，请完成后再修改设置。"); return
    }
    let request = UUID(); websiteBehaviorCommandRequest = request
    websiteBehaviorCommandTask = Task { @MainActor in
      defer { if websiteBehaviorCommandRequest == request { websiteBehaviorCommandTask = nil; preparedWholePreviewRendering = nil } }
      do { _ = try await importWorkflow().runPaceCommand(target, replacing: publication.applicationID) }
      catch {
        guard websiteBehaviorCommandRequest == request, !Task.isCancelled else { return }
        account.localNotices.post((error as? LocalizedError)?.errorDescription ?? "配速命令未完成，请重新打开命令。")
      }
    }
  }

  private func runWebsiteLiveCommand(_ edit: WebsiteConfigPracticeEdit) {
    guard websiteBehaviorCommandTask == nil, let publication = pageSession.presentation?.publication,
      pageSession.savedApplication == nil, pageSession.configurationDeparture == nil,
      pageSessionStore.restartController?.isPreparing != true else {
      account.localNotices.post("配置正在准备，请完成后再修改设置。"); return
    }
    let request = UUID(); websiteBehaviorCommandRequest = request
    websiteBehaviorCommandTask = Task { @MainActor in
      defer { if websiteBehaviorCommandRequest == request { websiteBehaviorCommandTask = nil; preparedWholePreviewRendering = nil } }
      do {
        _ = try await importWorkflow().editAndBegin(edit, replacing: publication.applicationID,
          systemIsDark: systemColorScheme == .dark)
        guard websiteBehaviorCommandRequest == request, !Task.isCancelled else { return }
        if case .sound(let target) = edit { practiceSoundSelection.afterCommand(target, on: practiceSoundPlayer()) }
      } catch {
        guard websiteBehaviorCommandRequest == request, !Task.isCancelled else { return }
        if case .inputRule(.lazyMode) = edit,
          (error as? WebsiteConfigImportWorkflowError) == .rejectedRestartFailed,
          session.hasStarted, !session.isFinished, session.configuration.modifiers.contains(.noQuit) { return }
        account.localNotices.post((error as? LocalizedError)?.errorDescription ?? "设置未完成，请重新打开命令。")
      }
    }
  }

  private func practiceThresholdValue(for kind: PracticeThresholdEditorKind) -> Double {
    kind.initialCanonicalValue(in: settings)
  }
  private func reportWebsiteThresholdCommand(_ receipt: WebsiteThresholdCommandReceipt) {
    guard !receipt.rejectedKeys.isEmpty else { return }
    if session.hasStarted, !session.isFinished, session.configuration.modifiers.contains(.noQuit) { return }
    account.localNotices.post(receipt.message)
  }
  private func runWebsiteThresholdOffCommand(_ target: PracticeThresholdCommandTarget, applicationID: UUID) {
    guard websiteThresholdCommandTask == nil else { return }
    let request = UUID(); websiteThresholdCommandRequest = request
    websiteThresholdCommandTask = Task { @MainActor in
      defer { if websiteThresholdCommandRequest == request { websiteThresholdCommandTask = nil } }
      do {
        let result = try importWorkflow().runThresholdCommand(target, input: "", replacing: applicationID)
        guard websiteThresholdCommandRequest == request, !Task.isCancelled else { return }
        reportWebsiteThresholdCommand(result)
      } catch {
        guard websiteThresholdCommandRequest == request, !Task.isCancelled else { return }
        account.localNotices.post((error as? LocalizedError)?.errorDescription ?? "阈值命令未完成，请重新打开命令。")
      }
    }
  }

  private func applyPracticeThreshold(_ value: Double, kind: PracticeThresholdEditorKind) -> Bool {
    guard acceptsRestartingConfigurationChange() else { return false }
    guard PracticeThresholdApplication.apply(value, kind: kind, to: settings, onConfigurationSave: {
      activeChallengeID = nil
      persistExplicitTestConfiguration()
    }) else { return false }
    reset()
    return true
  }

  private func importCustomBackgroundFromCommand(_ url: URL) {
    let canAccess = url.startAccessingSecurityScopedResource()
    defer {
      if canAccess { url.stopAccessingSecurityScopedResource() }
    }
    do {
      try settings.importLocalBackground(data: Data(contentsOf: url))
      customBackgroundCommandMessage = nil
    } catch {
      customBackgroundCommandMessage = error.localizedDescription
    }
  }

  private func importLocalFontFromCommand(_ url: URL) {
    guard LocalPracticeFontFilePolicy.supports(filename: url.lastPathComponent) else {
      fontFamilyCommandMessage = "请选择 TTF、OTF、WOFF 或 WOFF2 字体文件。"
      return
    }
    let canAccess = url.startAccessingSecurityScopedResource()
    defer {
      if canAccess { url.stopAccessingSecurityScopedResource() }
    }
    do {
      try settings.importLocalPracticeFont(
        data: Data(contentsOf: url), originalFilename: url.lastPathComponent)
      fontFamilyCommandMessage = nil
    } catch {
      fontFamilyCommandMessage = error.localizedDescription
    }
  }

  private var configuration: TestConfiguration {
    if pageSession.practice != nil { return session.configuration }
    let selected = baseConfiguration
    return selected.with(polyglotBaseLanguage: polyglotReturnLanguage ?? selected.polyglotBaseLanguage)
  }

  private var challengeSetupSelection: ChallengeSetupSelectionPolicy.Selection {
    .init(language: language, englishVariant: settings.englishVariant,
      mixedLanguageComponents: mixedLanguageComponents, contentOptions: contentOptions,
      polyglotReturnLanguage: polyglotReturnLanguage)
  }

  private var practiceDifficulty: Difficulty {
    pageSession.practice == nil ? challengeLiveConfiguration.difficulty(settings: settings) : session.configuration.difficulty
  }

  private var practiceRequestedModifiers: [TestModifier] {
    pageSession.practice == nil ? challengeLiveConfiguration.modifiers(settings: settings) : session.configuration.modifiers
  }

  private var practiceSettingsSnapshot: AppSettingsSnapshot {
    challengeLiveConfiguration.snapshot(settings: settings)
  }

  private var baseConfiguration: TestConfiguration {
    if let activeChallenge {
      let challengePreset = activeChallenge.id == "one-handed-bandit"
        ? (oneHandedChallengePreset ?? activeChallenge.preset) : activeChallenge.preset
      let challengeSelection = ChallengeSetupSelectionPolicy.applying(challengeSetupSelection,
        for: activeChallenge, template: challengePreset.configuration)
      let challengeConfiguration = ChallengeInputRulePolicy.applying(settings.inputRules,
        to: challengeSelection)
      return challengeConfiguration.with(
        modifiers: effectiveTestModifiers(
          for: challengeConfiguration.language, mode: challengeConfiguration.mode,
          mixedLanguageComponents: challengeConfiguration.mixedLanguageComponents,
          baseModifiers: challengeConfiguration.modifiers))
    }
    switch mode {
    case .time:
      return .timed(
        seconds: TimeInterval(duration), difficulty: practiceDifficulty,
        rules: settings.inputRules, language: language, englishVariant: settings.englishVariant,
        mixedLanguageComponents: mixedLanguageComponents, contentOptions: contentOptions
      ).with(modifiers: effectiveTestModifiers(for: language, mode: .time))
    case .words:
      return .words(
        wordLimit, difficulty: practiceDifficulty, rules: settings.inputRules, language: language,
        englishVariant: settings.englishVariant, mixedLanguageComponents: mixedLanguageComponents,
        contentOptions: contentOptions
      ).with(modifiers: effectiveTestModifiers(for: language, mode: .words))
    case .quote:
      return .init(
        mode: .quote, duration: nil, wordLimit: nil, difficulty: practiceDifficulty,
        rules: settings.inputRules, language: language, englishVariant: settings.englishVariant,
        quoteLength: QuoteLengthSelection.legacyValue(for: quoteLengths), quoteLengths: quoteLengths,
        quoteSelectionMode: quoteSelectionMode,
        mixedLanguageComponents: mixedLanguageComponents,
        modifiers: effectiveTestModifiers(for: language, mode: .quote), contentOptions: contentOptions)
    case .zen:
      return .init(
        mode: .zen, duration: nil, wordLimit: nil, difficulty: practiceDifficulty,
        rules: settings.inputRules, language: language, englishVariant: settings.englishVariant,
        mixedLanguageComponents: mixedLanguageComponents,
        modifiers: effectiveTestModifiers(for: language, mode: .zen), contentOptions: contentOptions)
    case .custom:
      let duration = customTextCompletion == .time ? TimeInterval(customTextDuration)
        : customWordDurationSelection.duration(mode: mode, completion: customTextCompletion,
          wordLimit: customTextWordLimit)
      let wordLimit = customTextCompletion == .words ? customTextWordLimit : nil
      let sectionLimit =
        customTextCompletion == .sections
        ? customTextSectionLimit : nil
      return .init(
        mode: .custom, duration: duration, wordLimit: wordLimit, difficulty: practiceDifficulty,
        rules: settings.inputRules, language: language, englishVariant: settings.englishVariant,
        customTextCompletion: customTextCompletion,
        customTextSectionLimit: sectionLimit,
        customTextOrdering: customTextOrdering,
        customTextPipeDelimiter: customTextPipeDelimiter,
        mixedLanguageComponents: mixedLanguageComponents,
        modifiers: effectiveTestModifiers(for: language, mode: .custom),
        contentOptions: contentOptions)
    }
  }

  private func effectiveTestModifiers(
    for selectedLanguage: TypingLanguage, mode: TestMode,
    mixedLanguageComponents: [TypingLanguage]? = nil, baseModifiers: [TestModifier]? = nil
  ) -> [TestModifier] {
    EffectiveTestModifierPolicy.modifiers(requested: baseModifiers ?? practiceRequestedModifiers,
      language: selectedLanguage, mode: mode,
      mixedLanguageComponents: mixedLanguageComponents ?? self.mixedLanguageComponents,
      automaticallyEnabledArabic: settings.prefersArabicLazyInput)
  }

  private func refreshZipfNotice() {
    zipfNotice = ZipfFrequencyPolicy.notice(for: language, modifiers: practiceRequestedModifiers)
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
      activeResultTags: settings.activeResultTags,
      settingsSnapshot: practiceSettingsSnapshot
    )
  }

  private func acceptsPresetResources(_ configuration: TestConfiguration) -> Bool {
    switch PresetResourceAdmission.refusal(for: configuration,
      wingdingsAvailable: { WingdingsChallengeFont.resolve(size: 12) != nil },
      scriptIsVerified: { activeVerifiedScript?.specification == $0 }) {
    case .missingWingdings:
      fontFamilyCommandMessage = "此 Mac 未提供 Wingdings 字体，无法开始该挑战。"
      return false
    case .missingVerifiedScript:
      referenceScriptMessage = "请从挑战库选择脚本并重新导入固定版本文本。"
      return false
    case nil:
      return true
    }
  }

  @discardableResult private func apply(
    _ preset: SavedTestPreset,
    overwritesParameterMemory: Bool = true,
    appliesGlobalSettings: Bool = true,
    polyglotReturnLanguage: TypingLanguage? = nil,
    restoringSelection: ActiveTestSelectionDocument? = nil,
    restoringCustomTextState: CustomTextStateDocument? = nil,
    restoringCustomTextRecovery: CustomTextRecoveryState? = nil
  ) -> Bool {
    guard acceptsRestartingConfigurationChange() else { return false }
    guard preset.settingGroups?.isEmpty != true else { return false }
    guard let preparation = PresetSourcePreparation.preparing(preset, to: settings,
      appliesGlobalSettings: appliesGlobalSettings) else {
      modeCompatibilityMessage = "本次配置未能应用，已保留当前测试；请检查配置版本或恢复状态。"
      return false
    }
    let preparedPreset = preparation.preset
    let appliesTest = !preparedPreset.isPartial || (preparedPreset.settingGroups?.contains(.test) == true)
    let appliedPreset = PresetApplicationPolicy.applying(current: presetDefinition, preset: preparedPreset)
    let challenge = appliesTest
      ? TypebarChallengeLibrary.challenge(id: appliedPreset.configuration.challengeID) : nil
    if appliesTest, !acceptsPresetResources(appliedPreset.configuration) { return false }
    let selectedOneHandedPreset = challenge?.id == "one-handed-bandit"
      ? (appliedPreset.customText == nil ? challenge?.preset : appliedPreset) : nil
    let challengeTemplate = challenge?.id == "one-handed-bandit"
      ? (selectedOneHandedPreset?.configuration ?? appliedPreset.configuration)
      : (challenge?.preset.configuration ?? appliedPreset.configuration)
    let usesCapturedSelection = restoringSelection != nil || appliedPreset.settingsSnapshot != nil
    let setupSelection = usesCapturedSelection
      ? ChallengeSetupSelectionPolicy.Selection(configuration: appliedPreset.configuration) : challengeSetupSelection
    let selectedConfiguration = challenge.map {
      ChallengeSetupSelectionPolicy.applying(setupSelection, for: $0, template: challengeTemplate,
        clearingPolyglot: !usesCapturedSelection)
    } ?? challengeTemplate
    let configuration = challenge == nil ? selectedConfiguration
      : ChallengeInputRulePolicy.applying(settings.inputRules, to: selectedConfiguration)
    guard PresetSettingsApplication.commit(original: preparedPreset, resolved: appliedPreset,
      configuration: configuration, to: settings, appliesGlobalSettings: appliesGlobalSettings,
      expectedSourceState: preparation.baseline, liveConfiguration: challengeLiveConfiguration) else {
      modeCompatibilityMessage = "本次配置未能应用，已保留当前测试；请检查配置版本或恢复状态。"
      return false
    }
    if challenge != nil {
      let installed = settings.hasThresholdProfile
        ? challengeLiveConfiguration.install(configuration, settings: settings)
        : challengeLiveConfiguration.observeLegacyChallenge(settings: settings, configuration: configuration)
      guard installed else {
        modeCompatibilityMessage = "挑战配置读取状态已改变，未切换测试。"
        return false
      }
    }
    modeCompatibilityMessage = nil
    if let restoringSelection {
      let memory = restoringSelection.testParameterMemory
      duration = memory.duration
      wordLimit = memory.wordLimit
      customTextDuration = memory.customTextDuration
      customTextWordLimit = memory.customTextWordLimit
      customTextSectionLimit = memory.customTextSectionLimit
      quoteSource = restoringSelection.quoteSource
    }
    wordPractice = nil
    if appliesTest { customTextSource = nil }
    if let restoringCustomTextRecovery { customTextRecovery = restoringCustomTextRecovery }
    else if appliesTest, CustomTextRestorePolicy.acceptsReplacement(appliedPreset) {
      customTextRecovery.acceptExplicitSource()
    }
    referenceScriptMessage = nil
    if let activeVerifiedScript,
      challenge?.requirements.referenceScriptSpecification
        != activeVerifiedScript.specification,
      appliesTest || !activeVerifiedScript.retainsSource(mode: configuration.mode,
        editorText: appliedPreset.customText ?? customText, challengeID: nil)
    {
      self.activeVerifiedScript = nil
      if appliedPreset.customText == nil,
        customText == LongSavedTextProgress.nextChunk(in: activeVerifiedScript.text, after: 0)
      {
        customText = "A calm practice makes the next difficult sentence feel possible."
      }
    }
    customWordDurationSelection.accept(configuration)
    if appliesTest || appliesGlobalSettings { activeChallengeID = challenge?.id }
    if appliesTest {
      if challenge?.id == "one-handed-bandit" {
        oneHandedChallengePreset = selectedOneHandedPreset
        oneHandedChallengeSelection = oneHandedChallengePreset?.customText.flatMap {
          OneHandedChallengePolicy.identify(source: $0)
        }
      } else {
        oneHandedChallengePreset = nil
        oneHandedChallengeSelection = nil
      }
      if challenge?.id == "mouse-warrior" { showsVirtualKeyboard = true }
    }
    mode = configuration.mode
    if overwritesParameterMemory {
      if let duration = configuration.duration { self.duration = Int(duration) }
      if let wordLimit = configuration.wordLimit { self.wordLimit = wordLimit }
    }
    let requestedQuoteID = appliedPreset.quoteID
    if let requestedQuoteID { selectedQuoteID = requestedQuoteID }
    if let customText = appliedPreset.customText { self.customText = customText }
    customTextCompletion = configuration.customTextCompletion
    if overwritesParameterMemory, configuration.customTextCompletion == .time,
      let duration = configuration.duration
    {
      customTextDuration = Int(duration)
    }
    if overwritesParameterMemory, configuration.customTextCompletion == .words,
      let wordLimit = configuration.wordLimit
    {
      customTextWordLimit = wordLimit
    }
    if overwritesParameterMemory, configuration.customTextCompletion == .sections,
      let sectionLimit = configuration.customTextSectionLimit
    {
      customTextSectionLimit = sectionLimit
    }
    customTextOrdering = configuration.customTextOrdering
    customTextPipeDelimiter = configuration.customTextPipeDelimiter
    self.polyglotReturnLanguage = configuration.language == .mixedLanguages
      ? PolyglotReturnLanguagePolicy.validated(polyglotReturnLanguage ?? configuration.polyglotBaseLanguage) : nil
    language = configuration.language
    constrainQuoteSource(for: language)
    mixedLanguageComponents = configuration.mixedLanguageComponents
    quoteSelectionMode = configuration.quoteSelectionMode
    if quoteSelectionMode == .search { quoteSearchQuery = "" }
    quoteLengths = configuration.effectiveQuoteLengths
    if quoteSource != .community || !communityQuotes.isEmpty {
      quoteSelectionMode = QuoteSelection.resolvedMode(
        quoteSelectionMode, hasEligibleQuotes: !availableQuotes.isEmpty)
    }
    quoteQueue.reset()
    contentOptions = configuration.contentOptions
    ensureSelectedQuote()
    if quoteSelectionMode == .search, selectedQuoteID != requestedQuoteID {
      quoteSelectionMode = .lengths
      ensureSelectedQuote()
    }
    if let restoringCustomTextState { installCustomTextState(restoringCustomTextState) }
    reset()
    return true
  }

  private func restoreActiveTestSelection(_ document: ActiveTestSelectionDocument,
    customState: CustomTextStateDocument? = nil, recovery: CustomTextRecoveryState = .init()) {
    let preset = document.preset
    guard apply(
      preset,
      overwritesParameterMemory: false,
      appliesGlobalSettings: false,
      polyglotReturnLanguage: document.polyglotReturnLanguage,
      restoringSelection: document,
      restoringCustomTextState: customState, restoringCustomTextRecovery: recovery) else { return }
    if activeChallengeID == "one-handed-bandit" {
      oneHandedChallengeSelection = document.oneHandedChallengeSelection
        ?? oneHandedChallengeSelection
      persistActiveTestSelection()
    }
    if mode == .quote, quoteSource == .community {
      refreshCommunityQuotes()
    }
  }

  private func restoreDefaultTestSelection(customState: CustomTextStateDocument? = nil,
    recovery: CustomTextRecoveryState = .init()) {
    let preset = SavedTestPreset(configuration: TypebarInitialTestSelection.configuration)
    let document = ActiveTestSelectionDocument(preset: preset, quoteSource: quoteSource,
      testParameterMemory: .defaults)
    apply(
      preset,
      overwritesParameterMemory: false,
      appliesGlobalSettings: false, restoringSelection: document,
      restoringCustomTextState: customState, restoringCustomTextRecovery: recovery)
  }

  private func restorePersistedTestSelection(explicitSelectionImport: Bool = false) {
    let document = settings.activeTestSelection
    let restoration = CustomTextRestorePolicy.restoration(read: settings.customTextStateRead,
      activePreset: document?.preset, explicitSelectionImport: explicitSelectionImport)
    // Reading the record is independent of accepting its old challenge or
    // selection. A missing script/font must not discard the recovery gate.
    customTextRecovery = restoration.recovery
    if let document {
      restoreActiveTestSelection(document, customState: restoration.document, recovery: restoration.recovery)
    } else {
      restoreDefaultTestSelection(customState: restoration.document, recovery: restoration.recovery)
    }
  }

  private func activatePreferenceConfigurationOwnerIfKey() {
    guard sharedProfileWindow.window?.isKeyWindow == true else { return }
    settings.preferenceConfigurationSaves.activate(owner: preferenceConfigurationOwner)
  }

  private func persistExplicitTestConfiguration() {
    guard settings.persistLiveConfiguration(challengeLiveConfiguration) else {
      account.localNotices.post("当前实时配置未能完整保存；可能已有部分设置生效，请检查配置存储状态。")
      return
    }
    guard wordPractice != nil else { return }
    persistActiveTestSelection(for: configuration, cause: .configurationSave)
  }

  private func persistActiveTestSelection(for selectedConfiguration: TestConfiguration? = nil,
    cause: WordPracticeTransition.PersistenceCause = .automatic) {
    guard !pageSessionStore.ownsConfigurationSelection else { return }
    guard customTextRecovery.permitsAutomaticPersistence(mode: mode) else { return }
    // The selected file exists only in this process. Leave the previous safe
    // selection intact, so relaunch cannot restore a first-chunk impostor.
    if activeVerifiedScript != nil { return }
    if mode == .custom, activeLongSavedText == nil {
      customTextStateSaveFailed = !settings.saveCustomTextState(customTextStateDocument)
    }
    let selectedConfiguration = selectedConfiguration ?? session.configuration
    let preset = SavedTestPreset(
      configuration: selectedConfiguration,
      quoteID: mode == .quote ? selectedQuoteID : nil,
      customText: mode == .custom ? customText : nil)
    let current = activeTestSelectionDocument(preset: preset)
    if wordPractice != nil {
      wordPractice?.persistSelection(current: current, cause: cause, save: settings.saveActiveTestSelection)
    } else {
      settings.saveActiveTestSelection(current)
    }
  }

  private func runWebsiteFunboxCommand(_ target: FunboxCommandTarget, draft: WebsiteConfigNativeDraft) {
    guard websiteFunboxCommandTask == nil, pageSession.configurationDeparture == nil,
      pageSessionStore.restartController?.isPreparing != true else {
      funboxConfigurationMessage = "上一轮仍在准备，请等待完成或继续待准备的练习。"; return
    }
    guard settings.allowsRestartingConfigurationChange else {
      ConfigurationNoticeFeedback.conflict("锁定重开已开启：请完成或放弃本次测试。", notices: account.localNotices, locked: true); return
    }
    guard let proposal = WebsiteConfigFunboxMemory.proposal(for: target, in: draft),
      let applicationID = pageSession.presentation?.publication.applicationID else { return }
    let request = UUID(); websiteFunboxCommandRequest = request
    websiteFunboxCommandTask = Task { @MainActor in
      defer { if websiteFunboxCommandRequest == request { websiteFunboxCommandTask = nil } }
      do {
        let message = try await importWorkflow().editAndBegin(.funboxes(proposal), replacing: applicationID,
          systemIsDark: systemColorScheme == .dark)
        guard websiteFunboxCommandRequest == request, !Task.isCancelled else { return }
        funboxConfigurationMessage = message
      } catch {
        guard websiteFunboxCommandRequest == request, !Task.isCancelled else { return }
        funboxConfigurationMessage = (error as? LocalizedError)?.errorDescription ?? "趣味模式未准备完成，请检查当前配置。"
      }
    }
  }
  private func importWorkflow() throws -> WebsiteConfigImportWorkflow {
    guard activeChallengeID == nil, wordPractice == nil else {
      throw WebsiteConfigImportWorkflowError.unsupportedPractice
    }
    if let websiteImportWorkflow { return websiteImportWorkflow }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: websiteConfigStartup?.applicationSupport)
    return configurationWorkflow(at: directory)
  }

  private func returnToTypebarSettings() throws {
    let page = pageSessionStore
    guard !session.hasStarted || session.isFinished else { throw WebsiteConfigImportWorkflowError.activeAttempt }
    guard page.state.practice != nil || page.state.savedApplication != nil || page.isReturningToTypebarSettings else {
      page.startupController.continueUsingLegacy()
      return
    }
    let permit = try page.beginLegacyReturn()
    websiteImportWorkflow?.stop(); websiteImportWorkflow = nil
    page.startupController.completedManually()
    completedResult = nil; compositionText = ""; terminalNotice = nil
    finalizedPracticeAttemptID = nil
    // Reuse normal native selection/resource/recovery admission, not a guessed
    // conversion of the whole website profile into old preference fields.
    restorePersistedTestSelection()
    try page.finishLegacyReturn(permit)
  }

  private func configurationWorkflow(at directory: URL) -> WebsiteConfigImportWorkflow {
    if let websiteImportWorkflow { return websiteImportWorkflow }
    let fetch = liveContentFetch
    let workflow = WebsiteConfigImportWorkflow(page: pageSessionStore, settings: settings, account: account,
      directory: directory, readWindow: { websiteImportWindow }, loadExternal: { source, configuration, allLines, check in
        try await WebsiteConfigExternalContent.prepare(source: source, configuration: configuration,
          showAllLines: allLines, checkCurrent: check, fetch: fetch)
      }, paceTarget: { draft, candidate in
        paceGuideTarget(usingRepeatedPace: isRepeatedPaceAttempt ? lastFinishedWpm : nil,
          currentPrompt: candidate.prompt, draft: draft)
      })
    websiteImportWorkflow = workflow
    return workflow
  }

  private func recoverPublishedPoetryFailure(attemptID: UUID) {
    guard websiteLiveSourceRecoveryTask == nil,
      let applicationID = pageSession.presentation?.publication.applicationID else { return }
    let request = UUID(); websiteLiveSourceRecoveryRequest = request
    websiteLiveSourceRecoveryTask = Task { @MainActor in
      defer { if websiteLiveSourceRecoveryRequest == request { websiteLiveSourceRecoveryTask = nil } }
      guard pageSessionStore.acceptsAttemptCallback(for: attemptID) else { return }
      do {
        _ = try await importWorkflow().recoverFailedPoetry(replacing: applicationID,
          systemIsDark: systemColorScheme == .dark)
      } catch {
        guard !Task.isCancelled, websiteLiveSourceRecoveryRequest == request,
          session.automaticInputAttemptID == attemptID,
          pageSession.presentation?.publication.applicationID == applicationID else { return }
        liveContentMessage = (error as? LocalizedError)?.errorDescription ?? "诗歌来源校正未完成，请在配置面板继续准备。"
      }
    }
  }

  private func openWebsiteConfigImport() {
    if websiteConfigStartup != nil { pageSessionStore.startupController.prepareForManualRecovery() }
    showingWebsiteConfigImport = true
  }

  private func updateConfigurationStartup() {
    guard let options = websiteConfigStartup, didRestoreActiveTestSelection else { return }
    let page = pageSessionStore
    let ownerReady = settings.preferenceConfigurationSaves.captureLease()?.owner == page.owner
    page.startupController.update(page: page, accountReady: options.accountReady, ownerReady: ownerReady,
      probe: { try WebsiteConfigStorageDirectory.existing(applicationSupport: options.applicationSupport) },
      onPending: {
        wholePreviewTask.cancel(); liveContentTask?.cancel(); liveContentTask = nil
        liveContentRequestID = UUID(); isPreparingWholePreview = false; isLoadingLiveContent = false
        automaticInputScheduler.cancel(); NativeSpeech.shared.stop()
      }, onContinue: { reset() }, makeWorkflow: { configurationWorkflow(at: $0) },
      systemIsDark: systemColorScheme == .dark)
  }

  private func testShareContent(initialLink: String = "") -> some View {
    TestConfigurationShareView(currentPreset: sharePresetDefinition,
      latestPreset: { sharePresetDefinition }, initialPastedLink: initialLink,
      legacyCustomTextFallback: .init(text: customText, completion: customTextCompletion,
        duration: customTextCompletion == .time ? TimeInterval(customTextDuration) : nil,
        wordLimit: customTextCompletion == .words ? customTextWordLimit : nil,
        sectionLimit: customTextCompletion == .sections ? customTextSectionLimit : nil,
        ordering: customTextOrdering, pipeDelimiter: customTextPipeDelimiter),
      websiteSnapshot: { websiteTestSettingsSnapshot },
      onApplyWebsiteSettings: websiteSettingsLinkApplication,
      hasPendingWebsiteSettings: {
        pageSession.sharedReceipt != nil || pageSession.configurationDeparture?.isSharedReceipt == true
      },
      canContinueWebsiteSettings: {
        pageSession.sharedReceipt?.requiresInitialization == true || pageSession.configurationDeparture?.isSharedReceipt == true
      },
      onContinueWebsiteSettings: {
        try await importWorkflow().continuePendingSharedSettings(systemIsDark: systemColorScheme == .dark)
      },
      canShareNative: { pageSession.sharedReceipt == nil && pageSession.configurationDeparture == nil },
      challengeLibrary: TypebarChallengeLibrary.all,
      notices: account.localNotices, onLoadChallenge: loadChallenge) { preset in
        guard apply(preset) else { return nil }
        return sharePresetDefinition
      }
  }

  private var websiteSettingsLinkApplication: (@MainActor (String) async throws -> WebsiteSharedLinkApplication)? {
    guard pageSession.practice != nil else { return nil }
    return { json in
      guard let applicationID = pageSession.presentation?.publication.applicationID else {
        throw WebsiteConfigImportWorkflowError.unavailable
      }
      return try await importWorkflow().applySharedSettings(json: json, replacing: applicationID,
        systemIsDark: systemColorScheme == .dark)
    }
  }

  private func testShareDidDismiss() {
    if queuedOneHandedChallengeSetup {
      queuedOneHandedChallengeSetup = false; showingOneHandedChallengeSetup = true
    }
    presentQueuedReferenceScriptImport()
    presentSharedProfileIfPossible()
  }

  private var websiteTestSettingsSnapshot: WebsiteTestSettingsShare.Snapshot? {
    if let receipt = pageSession.sharedReceipt {
      return .init(runtime: receipt.outcome.state.settingsStore,
        customText: WebsiteTestSettingsShare.customText(in: receipt.scope),
        hasUnmappedQuote: receipt.outcome.state.settingsStore["mode"] == .string("quote"))
    }
    guard let draft = WebsiteConfigExport.draft(in: pageSession), let practice = pageSession.practice else { return nil }
    let hasQuote: Bool
    if let current = pageSession.currentQuoteInitialization { hasQuote = current.quote != nil }
    else { hasQuote = practice.quote != nil }
    return .init(runtime: WebsiteConfigExport.values(draft, surface: .settings),
      customText: WebsiteTestSettingsShare.customText(in: practice.scope),
      hasUnmappedQuote: hasQuote)
  }

  private var sharePresetDefinition: SavedTestPreset {
    guard let practice = pageSession.practice else { return presetDefinition }
    let quote: OfflineQuote?
    if let current = pageSession.currentQuoteInitialization { quote = current.quote }
    else { quote = practice.quote }
    return WebsiteTestSettingsShare.nativeSelection(configuration: session.configuration, scope: practice.scope, quote: quote)
  }

  private var websiteImportWindow: WebsiteConfigPracticeScopeSource.Window {
    if let receipt = pageSession.sharedReceipt {
      return .published(owner: preferenceConfigurationOwner, revision: session.automaticInputAttemptID, scope: receipt.scope)
    }
    if let scope = pageSession.practice?.scope {
      return .published(owner: preferenceConfigurationOwner, revision: session.automaticInputAttemptID, scope: scope)
    }
    // Legacy content controls reset the actual attempt when applied, including
    // same-value applications; capture its identity as the window generation.
    let hasWebsiteCustom = settings.websiteCustomTextStateRead != .missing
    return .init(owner: preferenceConfigurationOwner, customRecoveryBlocked: hasWebsiteCustom ? false : customTextRecovery.blocksCustomGeneration,
      revision: session.automaticInputAttemptID, selectedQuoteID: selectedQuoteID,
      parameterMemory: .init(duration: duration, wordLimit: wordLimit, customTextDuration: customTextDuration,
        customTextWordLimit: customTextWordLimit, customTextSectionLimit: customTextSectionLimit),
      custom: hasWebsiteCustom ? .stored : .explicit(customTextStateDocument,
        finiteTextSource: activeLongSavedText.map { $0.continuous ? $0.remainingText : $0.currentChunk },
        preservesSpelling: preparedCustomSections != nil, recoveryBlocked: customTextRecovery.blocksCustomGeneration))
  }

  private var preparedCustomSections: [String]? {
    wordPractice?.preparedSections(matching: customText)
      ?? customTextSource?.preparedSections(matching: customText)
  }

  private var customTextStateDocument: CustomTextStateDocument {
    let customConfiguration = TestConfiguration(mode: .custom,
      duration: customTextCompletion == .time ? TimeInterval(customTextDuration) : nil,
      wordLimit: customTextCompletion == .words ? customTextWordLimit : nil,
      difficulty: .normal, rules: .init(), customTextCompletion: customTextCompletion,
      customTextSectionLimit: customTextCompletion == .sections ? customTextSectionLimit : nil,
      customTextOrdering: customTextOrdering, customTextPipeDelimiter: customTextPipeDelimiter)
    return .init(source: preparedCustomSections.map(CustomTextSource.prepared) ?? .editor(customText),
      configuration: customConfiguration)
  }

  private func installCustomTextState(_ document: CustomTextStateDocument) {
    customTextRecovery.acceptExplicitSource()
    customTextSource = document.source
    customText = document.source.text
    customTextCompletion = document.completion
    customTextOrdering = document.ordering
    customTextPipeDelimiter = document.pipeDelimiter
    if let duration = document.duration { customTextDuration = Int(duration) }
    if let wordLimit = document.wordLimit { customTextWordLimit = wordLimit }
    if let sectionLimit = document.sectionLimit { customTextSectionLimit = sectionLimit }
  }

  private func activeTestSelectionDocument(preset: SavedTestPreset) -> ActiveTestSelectionDocument {
    .init(
      preset: preset,
      quoteSource: quoteSource,
      testParameterMemory: .init(
        duration: duration,
        wordLimit: wordLimit,
        customTextDuration: customTextDuration,
        customTextWordLimit: customTextWordLimit,
        customTextSectionLimit: customTextSectionLimit),
      polyglotReturnLanguage: preset.configuration.language == .mixedLanguages
        ? polyglotReturnLanguage : nil,
      oneHandedChallengeSelection: activeChallengeID == "one-handed-bandit"
        ? oneHandedChallengeSelection : nil)
  }

  private var activeChallenge: TypebarChallenge? {
    TypebarChallengeLibrary.challenge(id: activeChallengeID)
  }

  private func handleActiveChallengeIDChange(to id: String?) {
    guard let activeVerifiedScript,
      !activeVerifiedScript.retainsSource(mode: mode, editorText: customText, challengeID: id) else { return }
    if id == nil,
      customText == LongSavedTextProgress.nextChunk(in: activeVerifiedScript.text, after: 0)
    {
      customText = "A calm practice makes the next difficult sentence feel possible."
    }
    self.activeVerifiedScript = nil
  }

  @discardableResult private func loadChallenge(_ challenge: TypebarChallenge) -> TestConfigurationApplyOutcome {
    guard acceptsRestartingConfigurationChange() else { return .rejected }
    if challenge.requirements.referenceScriptSpecification != nil {
      pendingReferenceScriptChallenge = challenge
      if showingChallenges || showingTestShare || testSettingsInbox.presented != nil || showingCommandPalette {
        queuedReferenceScriptImport = true
      } else {
        showingReferenceScriptImport = true
      }
      return .requiresSetup
    }
    if challenge.id == "one-handed-bandit" {
      if showingChallenges || showingTestShare || testSettingsInbox.presented != nil {
        queuedOneHandedChallengeSetup = true
      } else {
        showingOneHandedChallengeSetup = true
      }
      return .requiresSetup
    }
    var preset = challenge.preset
    preset.configuration = preset.configuration.with(challengeID: challenge.id)
    return apply(preset) ? .applied : .rejected
  }

  private func presentQueuedReferenceScriptImport() {
    guard queuedReferenceScriptImport, pendingReferenceScriptChallenge != nil else { return }
    queuedReferenceScriptImport = false
    showingReferenceScriptImport = true
  }

  @discardableResult
  private func startReferenceScriptChallenge(
    _ challenge: TypebarChallenge,
    verified: ReferenceScriptChallengePolicy.VerifiedScript
  ) -> Bool {
    guard acceptsRestartingConfigurationChange(),
      challenge.requirements.referenceScriptSpecification == verified.specification
    else { return false }
    let previousText = customText
    let previousVerifiedScript = activeVerifiedScript
    let previousLongSavedText = activeLongSavedText
    let previousRecovery = customTextRecovery
    activeLongSavedText = nil
    customTextRecovery.acceptExplicitSource()
    customText = LongSavedTextProgress.nextChunk(in: verified.text, after: 0)
    activeVerifiedScript = verified
    var preset = challenge.preset
    preset.configuration = preset.configuration.with(challengeID: challenge.id)
    let applied = apply(preset)
    guard applied, activeChallengeID == challenge.id else {
      customText = previousText
      activeVerifiedScript = previousVerifiedScript
      activeLongSavedText = previousLongSavedText
      customTextRecovery = previousRecovery
      return false
    }
    return true
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
        // The reference saves custom Polyglot choices for the next restart
        // instead of interrupting the current test.
        persistActiveTestSelection(for: configuration, cause: .configurationSave)
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
    guard acceptsRestartingConfigurationChange() else { return }
    isLoadingCommunityQuotes = true
    communityQuoteMessage = nil
    Task {
      do {
        let remoteQuotes = try await account.publicQuotes(language: language)
        guard NoQuitConfigurationChangePolicy.allowsRestartingChange(for: session) else {
          isLoadingCommunityQuotes = false
          return
        }
        communityQuoteRatings = Dictionary(
          uniqueKeysWithValues: remoteQuotes.map {
            (
              $0.id,
              .init(
                quoteID: $0.id, upvotes: $0.upvotes, downvotes: $0.downvotes,
                viewerRating: $0.viewerRating, ratingCount: $0.ratingCount,
                ratingTotal: $0.ratingTotal, viewerScore: $0.viewerScore,
                ratingScale: $0.ratingScale)
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
      Text(communityRatingSummary(rating))
        .font(.caption).foregroundStyle(.secondary)
      if account.currentUser != nil, let quoteID = selectedCommunityQuoteID {
        if let rating, RemoteQuoteRatingPresentation.usesFivePointScale(for: rating) {
          ForEach(1...5, id: \.self) { score in
            Button {
              guard let value = RemoteQuoteRatingValue.score(score) else { return }
              rateCommunityQuote(quoteID, value: value)
            } label: {
              Image(systemName: score <= (RemoteQuoteRatingPresentation.viewerScore(for: rating) ?? 0)
                ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("给社区引语评 \(score) 星")
          }
          if RemoteQuoteRatingPresentation.viewerScore(for: rating) != nil {
            Button("清除评分") { rateCommunityQuote(quoteID, value: .neutral) }
              .buttonStyle(.borderless)
          }
        } else {
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

  private func communityRatingSummary(_ rating: RemoteQuoteRatingResponse?) -> String {
    guard let rating else { return "社区评价：支持 0 · 不适合 0" }
    if let average = RemoteQuoteRatingPresentation.average(for: rating),
        let count = rating.ratingCount
    {
      return "社区评分：\(average.formatted(.number.precision(.fractionLength(1)))) / 5 · \(count) 人"
    }
    return "社区评价：支持 \(rating.upvotes) · 不适合 \(rating.downvotes)"
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
    if quoteSelectionMode == .favorites,
       !acceptsRestartingConfigurationChange()
    {
      return
    }
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
        guard acceptsRestartingConfigurationChange() else { return }
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
    guard let transition = WordPracticeTransition.begin(
      previous: wordPractice, practice: practice,
      currentPreset: { presetDefinition },
      currentSelection: { activeTestSelectionDocument(preset: $0) },
      currentCustomTextState: {
        guard mode == .custom, !customTextRecovery.requiresExplicitSource else { return nil }
        return customTextRecovery.pendingSource
          ?? (activeLongSavedText == nil && activeVerifiedScript == nil ? customTextStateDocument : settings.customTextState)
      },
      selectCustomMode: { selectMode(.custom) }) else { return }
    wordPractice = transition
    customTextRecovery.acceptExplicitSource()
    customTextSource = .prepared(practice.sections)
    customText = practice.text
    customTextCompletion = .sections
    customTextSectionLimit = practice.sectionCount
    customTextOrdering = practice.ordering
    customTextPipeDelimiter = true
    completedResult = nil
    reset()
  }

  /// Result-driven word practice is temporary. Its source configuration is
  /// restored only when the user leaves it for a fresh test; repeating the
  /// result intentionally keeps the same practice prompt.
  private func restoreWordPracticeIfNeeded() -> Bool {
    guard let transition = wordPractice else { return false }
    let current = presetDefinition
    let currentSelection = activeTestSelectionDocument(preset: current)
    let returningPreset = transition.returningPreset(current: current,
      parameterMemory: currentSelection.testParameterMemory, quoteID: selectedQuoteID)
    let returningCustomState = CustomTextRestorePolicy.returningSource(captured: transition.returnCustomTextState,
      latest: { customTextStateDocument })
    // apply clears temporary navigation only after its admission checks.
    // A rejection consumes this command without falling through to restart.
    apply(returningPreset, overwritesParameterMemory: false, appliesGlobalSettings: false,
      polyglotReturnLanguage: currentSelection.polyglotReturnLanguage,
      restoringSelection: currentSelection,
      restoringCustomTextState: returningCustomState)
    return true
  }

  private func presentSignedOutResultClaimIfPossible() {
    guard let claim = signedOutResultClaimStore.claim else {
      signedOutResultClaimSheetState = nil
      return
    }
    guard account.resultPublicationScope != nil else {
      signedOutResultClaimSheetState = nil
      return
    }

    let resultID = claim.resultID
    let descriptor = FetchDescriptor<TestResultRecord>(
      predicate: #Predicate { $0.id == resultID })
    do {
      let localResult = try modelContext.fetch(descriptor).first?.portableResult
      let availability: SignedOutResultClaimLocalRecordAvailability =
        localResult == nil ? .absent : .present
      switch SignedOutResultClaimPolicy.disposition(
        claim: claim,
        isAuthenticatedForResultPublishing: true,
        localRecordAvailability: availability
      ) {
      case .present(let claim):
        guard let localResult else { return }
        signedOutResultClaimSheetState = .init(claim: claim, result: localResult)
      case .discard:
        // A deleted or malformed local record cannot be uploaded. Forget only
        // the small candidate pointer; no SwiftData record is modified here.
        signedOutResultClaimStore.clear()
        signedOutResultClaimSheetState = nil
      case .hidden:
        signedOutResultClaimSheetState = nil
      }
    } catch {
      // Fetch errors are not evidence that the local record is gone. Retain
      // the candidate and let a subsequent SwiftData update or app launch try
      // again instead of silently losing the user's upload choice.
      signedOutResultClaimSheetState = nil
    }
  }

  private func keepSignedOutResultLocally() {
    signedOutResultClaimStore.clear()
    signedOutResultClaimSheetState = nil
  }

  private func uploadSignedOutResultClaim(_ result: CompletedTestResult) async throws {
    guard let scope = account.resultPublicationScope else {
      throw RemoteAccountError.accountScopeChanged
    }
    _ = try await account.submitCompletedResult(result, for: scope)
    signedOutResultClaimStore.clear()
    signedOutResultClaimSheetState = nil
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
    var record: TestResultRecord?
    localResultSaveState = LocalResultSaveAttempt.perform {
      record = try LocalPersonalBestStore.save(result, in: modelContext)
    }
    if localResultSaveState.isSaved {
      savedResultRecord = record
      priorAttemptLedger.clearAfterPersistingResult()
      if SignedOutResultClaimPolicy.shouldRecord(outcome: result.outcome,
        localSaveState: localResultSaveState,
        isAuthenticatedForResultPublishing: account.resultPublicationScope != nil) {
        signedOutResultClaimStore.record(result.id)
      }
    } else {
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
      guard let result = recordsByID[resultID]?.portableResult,
        result.outcome == .completed || result.outcome == .bailedOut else {
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
        ? "已发送至自建服务 · +\(ExperiencePresentation.compact(response.experienceGained)) XP · 总计 \(ExperiencePresentation.compact(response.totalExperience)) XP\(rank)"
        : "已发送至自建服务 · +\(ExperiencePresentation.compact(response.experienceGained)) XP",
      dailyLeaderboardRank: response.dailyLeaderboardRank)
  }
}

private enum TestTerminalNotice: Hashable, Identifiable {
  case abandoned

  var id: Self { self }

  var title: String {
    switch self {
    case .abandoned: "已放弃本次测试"
    }
  }

  var message: String {
    switch self {
    case .abandoned: return "本次没有保存为完成成绩。"
    }
  }
}

private extension TestFailureReason {
  var resultSummary: String {
    switch self {
    case .timerHealth: "计时调度持续延迟，为避免不准确的成绩已停止测试"
    case .wordGeneration: "无法生成后续词，练习已停止"
    case .minimumWpm: "整体速度低于设定的最低速度"
    case .minimumAccuracy: "准确率低于设定的最低准确率"
    }
  }
}

extension TestOutcome {
  func statusText(saveState: LocalResultSaveState, eligibility: ResultEligibility? = nil) -> String {
    if self != .bailedOut, ResultPresentationPolicy.shouldPresent(outcome: self),
      let reason = eligibility?.invalidReason {
      return reason == .inactivity ? "本次因闲置无效 · 未保存为完成成绩"
        : "本次结果无效（\(reason.resultSummary)） · 未保存为完成成绩"
    }
    return switch self {
    case .active: "按任意键开始，Esc 可重新开始"
    case .completed:
      saveState.isSaved ? "本次完成 · 已保存到本机" : "本次完成 · 未保存为完成成绩"
    case .failed: "本次失败 · 未保存为完成成绩"
    case .invalidAFK: "本次因闲置无效 · 未保存为完成成绩"
    case .abandoned: "本次已放弃 · 未保存为完成成绩"
    case .bailedOut:
      saveState.isSaved ? "本次已中止 · 已保存到本机" : "本次已中止 · 未保存"
    }
  }
}

private struct CompletedResultPresentation: Identifiable {
  let result: CompletedTestResult
  let websiteAttemptID: UUID?
  let suppressesCelebrationForSlowTimer: Bool
  let savesResult: Bool
  let eligibility: ResultEligibility
  let failureReason: TestFailureReason?
  let zeroSpeedFeedback: ZeroSpeedResultFeedback?
  let quoteFeedback: QuoteResultFeedbackTarget?
  let resultPersonalBestFeedback: ResultPersonalBestFeedback?
  let tagPersonalBestFeedback: [TagPersonalBestFeedback]
  let accountTagCompletionFeedback: AccountTagCompletionFeedback?
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
  let slowTimer: Bool
  let savesResult: Bool
  let eligibility: ResultEligibility
  let failureReason: TestFailureReason?
  let zeroSpeedFeedback: ZeroSpeedResultFeedback?
  let typingSpeedUnit: TypingSpeedUnit
  let alwaysShowDecimalPlaces: Bool
  let alwaysShowWordsHistory: Bool
  let commandPaletteListMode: CommandPaletteListMode
  let soundConfiguration: ReplaySoundConfiguration
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
  let accountTagCompletionFeedback: AccountTagCompletionFeedback?
  let settings: AppSettings
  let account: AccountSession
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
  let isInline: Bool
  @State private var exportStatus: String?
  @State private var showingLocalNoticeHistory = false
  @State private var repeatNotice: String?
  @State private var wpmConsistencyLoader = ResultWPMConsistencyLoader()
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

  private var resultContents: some View {
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

      if let zeroSpeedFeedback {
        HStack(spacing: 10) {
          Image(systemName: "sparkles")
            .font(.title3.weight(.semibold))
            .symbolEffect(.bounce, value: zeroSpeedFeedback)
          VStack(alignment: .leading, spacing: 2) {
            Text(zeroSpeedFeedback.title)
              .font(.subheadline.weight(.semibold))
            Text(zeroSpeedFeedback.message)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(zeroSpeedFeedback.title)，\(zeroSpeedFeedback.message)")
      }

      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(ResultMetricPresentation.primaryTypingSpeed(
          wpm: result.preciseWpm, unit: typingSpeedUnit,
          alwaysShowDecimalPlaces: alwaysShowDecimalPlaces))
          .font(.system(size: 72, weight: .bold, design: .rounded))
        Text(typingSpeedUnit.displayName).foregroundStyle(.secondary)
      }

      Grid(horizontalSpacing: 36, verticalSpacing: 14) {
        GridRow {
          metric("准确率", formattedAccuracy)
          metric("Raw \(typingSpeedUnit.displayName)", ResultMetricPresentation.typingSpeed(
            wpm: result.preciseRawWpm, unit: typingSpeedUnit,
            alwaysShowDecimalPlaces: alwaysShowDecimalPlaces))
        }
        GridRow {
          metric("错误", "\(result.errorCount)")
          metric(
            "总用时",
            ResultMetricPresentation.duration(
              result.elapsedDuration, alwaysShowDecimalPlaces: alwaysShowDecimalPlaces))
        }
        GridRow {
          metric(ResultCharacterStatsPresentation.label(result.characterStats), characterStatsText)
          metric("输入字符", "\(result.typedCharacterCount)")
        }
        GridRow {
          metric("稳定度", ResultMetricPresentation.percentage(
            consistency.typing, alwaysShowDecimalPlaces: alwaysShowDecimalPlaces))
          metric("按键稳定度", ResultMetricPresentation.percentage(
            consistency.key, alwaysShowDecimalPlaces: alwaysShowDecimalPlaces))
        }
        GridRow {
          metric("WPM 稳定度", wpmConsistencyText)
          Text("根据正确速度变化；与输入节奏不同")
            .font(.caption).foregroundStyle(.secondary)
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

      if !visibleResultTags.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Label("本轮标签", systemImage: "tag")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
          FlowLayout(spacing: 6) {
            ForEach(visibleResultTags, id: \.self) { tag in
              Text(tag)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(panel.opacity(0.72), in: Capsule())
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("本轮标签，\(visibleResultTags.joined(separator: "、"))")
      }

      ResultPerformanceChart(
        prompt: result.prompt,
        events: result.replayEvents,
        duration: result.chartDuration,
        configuration: result.configuration,
        targetWordDirectory: result.targetWordDirectory,
        sourceScoringBasis: result.characterStats.sourceUnitBasis,
        reviews: wordReviews,
        typingSpeedUnit: typingSpeedUnit,
        startsAtZero: startGraphsAtZero,
        visibility: resultPerformanceVisibility,
        resultPersonalBestFeedback: localResultSaveState.isSaved
          ? resultPersonalBestFeedback : nil,
        tagPersonalBestFeedback: localResultSaveState.isSaved
          ? tagPersonalBestFeedback : [],
        accountTagCompletionRows: visibleAccountTagCompletion?.rows ?? [],
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

      if let accepted = account.editableAccountTagResult(id: result.id) {
        RemoteAccountResultTagPicker(result: accepted, account: account, fromResultPage: true,
          completionRows: visibleAccountTagCompletion?.rows ?? [])
      } else if let feedback = visibleAccountTagCompletion {
        AccountTagCompletionFeedbackView(feedback: feedback)
      }

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

      if ResultReplayAvailability.isAvailable(prompt: result.prompt, events: result.replayEvents,
        configuration: result.configuration) {
        ReplayTimelineView(
          prompt: result.prompt, events: result.replayEvents, speedUnit: typingSpeedUnit,
          configuration: result.configuration,
          targetWordDirectory: result.targetWordDirectory,
          sourceScoringBasis: result.characterStats.sourceUnitBasis,
          soundConfiguration: soundConfiguration)
          .id(result.id)
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
            if MissedWordCopyText.make(for: result, words: missedWords) != nil {
              Button("复制错词列表", action: copyMissedWords)
            }
            if SlowWordCopyPolicy.hasInputWords(for: result, reviews: wordReviews) {
              Button("复制慢词列表…", action: prepareSlowWordCopy)
            }
            Button("复制结果图片", action: copyResultImage)
            Divider()
            Button("保存结果图片…", action: saveResultImage)
            Divider()
            Button("会话通知") { showingLocalNoticeHistory = true }
          }
          Spacer()
          Button("重复本轮") { repeatResult(from: .button) }
          Button("再来一次", action: onRestart)
            .buttonStyle(.borderedProminent)
        }
        if let repeatNotice {
          Text(repeatNotice)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
  }

  @ViewBuilder private var resultViewport: some View {
    if isInline {
      resultContents.frame(maxWidth: .infinity)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    } else {
      ScrollView { resultContents }
        .frame(width: 390, height: min(720, (NSScreen.main?.visibleFrame.height ?? 800) * 0.75))
        .scrollIndicators(.visible)
    }
  }
  var body: some View {
    resultViewport
    .overlay(alignment: .topTrailing) {
      LocalNoticeStack(center: account.localNotices, focused: false).padding(12)
    }
    .overlay {
      ResultCelebrationView(
        isNewPersonalBest: savesResult && resultPersonalBestFeedback?.isNewPersonalBest == true,
        hasZeroSpeedFeedback: zeroSpeedFeedback != nil,
        reducesMotion: settings.reducePracticeMotion,
        slowTimer: slowTimer,
        accent: accent,
        text: .primary,
        subduedText: .secondary)
    }
    .focusedSceneValue(\.openCommandPalette) { showingCommandPalette = true }
    .onAppear {
      communityRating = initialCommunityRating
    }
    .task(id: result.id) {
      let input = try? ResultWPMConsistencyInput(prompt: result.prompt, events: result.replayEvents,
        duration: result.chartDuration, configuration: result.configuration,
        targetWordDirectory: result.targetWordDirectory, sourceScoringBasis: result.characterStats.sourceUnitBasis)
      await wpmConsistencyLoader.load(input)
    }
    .sheet(isPresented: $showingCommandPalette) {
      CommandPaletteView(
        items: resultCommandItems,
        listMode: commandPaletteListMode,
        onSelect: runResultCommand)
    }
    .sheet(isPresented: $showingLocalNoticeHistory) { LocalNoticeHistoryView(center: account.localNotices) }
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
    ResultCharacterStatsPresentation.value(result.characterStats)
  }

  private var visibleResultTags: [String] {
    ResultTagPresentationPolicy.visibleTags(for: result)
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
      leaveCommandPalette { repeatResult(from: .command) }
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

  private func repeatResult(from origin: CompletedResultRepeatOrigin) {
    CompletedResultRepeatPolicy.perform(
      mode: result.configuration.mode,
      origin: origin,
      showNotice: { repeatNotice = $0 },
      repeatAttempt: onRepeat)
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
        "本机个人最佳 · \(PersonalBestFeedbackPresentation.text(previousBestWpm: feedback.previousBestWpm, currentWpm: feedback.currentWpm, speedUnit: typingSpeedUnit))",
        systemImage: "crown.fill"
      )
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.yellow)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var visibleAccountTagCompletion: AccountTagCompletionFeedback? {
    guard accountTagCompletionFeedback?.scope == account.resultPublicationScope,
      account.lastAccountTagCompletionFeedback?.resultID == result.id,
      accountTagCompletionFeedback?.resultID == result.id else { return nil }
    return accountTagCompletionFeedback
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
            Text(PersonalBestFeedbackPresentation.text(previousBestWpm: feedback.previousBestWpm,
              currentWpm: feedback.currentWpm, speedUnit: typingSpeedUnit))
              .foregroundStyle(feedback.isNewPersonalBest ? accent : .secondary)
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
        Text(communityRatingSummary)
          .font(.caption)
          .foregroundStyle(.secondary)
        if isSignedIn {
          HStack(spacing: 8) {
            if let communityRating,
                RemoteQuoteRatingPresentation.usesFivePointScale(for: communityRating)
            {
              ForEach(1...5, id: \.self) { score in
                Button {
                  guard let value = RemoteQuoteRatingValue.score(score) else { return }
                  rateCommunityQuote(quoteID, value: value)
                } label: {
                  Image(systemName: score <= (RemoteQuoteRatingPresentation.viewerScore(for: communityRating) ?? 0)
                    ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("给社区引语评 \(score) 星")
              }
            } else {
              Button("不适合") { rateCommunityQuote(quoteID, value: .down) }
                .buttonStyle(.bordered)
                .tint(communityRating?.viewerRating == RemoteQuoteRatingValue.down.rawValue ? .red : .secondary)
              Button("不错") { rateCommunityQuote(quoteID, value: .up) }
                .buttonStyle(.bordered)
                .tint(communityRating?.viewerRating == RemoteQuoteRatingValue.up.rawValue ? .green : .secondary)
            }
            if communityRating?.viewerRating != nil || communityRating.flatMap(RemoteQuoteRatingPresentation.viewerScore) != nil {
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

  private var communityRatingSummary: String {
    guard let communityRating else { return "社区评价：支持 0 · 不适合 0" }
    if let average = RemoteQuoteRatingPresentation.average(for: communityRating),
        let count = communityRating.ratingCount
    {
      return "社区评分：\(average.formatted(.number.precision(.fractionLength(1)))) / 5 · \(count) 人"
    }
    return "社区评价：支持 \(communityRating.upvotes) · 不适合 \(communityRating.downvotes)"
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
    if result.outcome != .bailedOut, let reason = eligibility.invalidReason {
      return reason == .inactivity ? "闲置无效" : "结果无效"
    }
    return switch result.outcome {
    case .bailedOut: "已中止"
    case .invalidAFK: "闲置无效"
    case .failed: "本次测试失败"
    case .active, .completed, .abandoned: "完成"
    }
  }

  private var resultOutcomeSubtitle: String {
    if result.outcome != .bailedOut, let reason = eligibility.invalidReason {
      return reason == .inactivity
        ? "结束前连续约 5 秒没有文本输入；结果只在当前窗口显示，不保存成绩"
        : "本次结果无效（\(reason.resultSummary)）；结果只在当前窗口显示，不保存成绩"
    }
    switch result.outcome {
    case .bailedOut:
      if case .ineligible(let reason) = eligibility {
        return "中止结果无效（\(reason.resultSummary)）；未写入本机历史"
      }
      guard savesResult else { return "中止结果未保存：保存已关闭" }
      return localResultSaveState.isSaved
        ? "中止结果已保存到这台 Mac；不计入 PB 或挑战，发布需服务支持中止协议"
        : "中止结果尚未保存到这台 Mac，可重试本机保存"
    case .invalidAFK: return "结束前连续约 5 秒没有文本输入；结果只在当前窗口显示，不保存成绩"
    case .failed:
      return (failureReason?.resultSummary ?? "本次没有保存为完成成绩")
        + "；结果只在当前窗口显示，不保存成绩"
    case .active, .completed, .abandoned:
      if case .ineligible(let reason) = eligibility {
        return "本次结果无效（\(reason.resultSummary)）；结果只在当前窗口显示，不保存成绩"
      }
      return savesResult
        ? (localResultSaveState.isSaved ? "已保存到这台 Mac" : "尚未保存到这台 Mac")
        : "练习模式：不保存成绩"
    }
  }

  private var afkPercentageText: String {
    result.afkPercentage.formatted(.number.precision(.fractionLength(0...2)))
  }

  private var consistency: ResultConsistency {
    ResultConsistencyPolicy.metrics(
      events: result.replayEvents, duration: result.chartDuration,
      configuration: result.configuration, keySpacingSamples: result.keySpacingSamples)
  }

  private var wpmConsistencyText: String {
    switch wpmConsistencyLoader.state {
    case .loading: "计算中…"
    case .unavailable: "不可用"
    case .value(let value):
      ResultMetricPresentation.percentage(value, alwaysShowDecimalPlaces: alwaysShowDecimalPlaces)
    }
  }

  private func metric(_ title: String, _ value: String) -> some View {
    VStack(spacing: 3) {
      Text(value).font(.headline)
      Text(title).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  private var formattedAccuracy: String {
    ResultMetricPresentation.accuracy(
      result.preciseAccuracy, alwaysShowDecimalPlaces: alwaysShowDecimalPlaces)
  }

  private func copyResultText() {
    copyTextToClipboard(ResultShareText.make(for: result), success: "结果文字已复制")
  }

  private func copyResultInput() {
    guard let input = ResultInputText.make(for: result) else {
      exportNotice("没有可复制的输入回放", level: .notice)
      return
    }
    copyTextToClipboard(input, success: "实际输入已复制")
  }

  private func copyResultPrompt() {
    guard let prompt = ResultPromptText.make(for: result, reviews: wordReviews) else {
      exportNotice("没有可复制的已练习提示", level: .notice)
      return
    }
    copyTextToClipboard(prompt, success: "已练习提示已复制")
  }

  private func copyMissedWords() {
    guard let text = MissedWordCopyText.make(for: result, words: missedWords) else {
      exportNotice("没有可复制的错词或 Zen 输入回放", level: .notice)
      return
    }
    copyTextToClipboard(text, success: "错词列表已复制")
  }

  private func prepareSlowWordCopy() {
    let threshold = SlowWordCopyPolicy.defaultThreshold(bursts: wordBursts)
    slowWordThresholdText = String(format: "%.0f", threshold)
    showingSlowWordCopy = true
  }

  private func copySlowWords() {
    guard let threshold = Double(slowWordThresholdText), threshold.isFinite, threshold > 0 else {
      exportNotice("请输入大于 0 的 WPM 阈值", level: .error)
      return
    }
    let words = SlowWordCopyPolicy.words(
      for: result, reviews: wordReviews, bursts: wordBursts, below: threshold)
    guard !words.isEmpty else {
      exportNotice("没有低于 \(slowWordThresholdText) WPM 的已输入词", level: .notice)
      return
    }
    copyTextToClipboard(words.joined(separator: " "), success: "已复制 \(words.count) 个慢词")
  }

  private func copyResultImage() {
    guard let image = resultImage else {
      exportNotice("无法生成结果图片", level: .error)
      return
    }
    NSPasteboard.general.clearContents()
    let copied = NSPasteboard.general.writeObjects([image])
    exportNotice(copied ? "结果图片已复制" : "无法写入剪贴板，请重试。", level: copied ? .success : .error)
  }

  private func copyTextToClipboard(_ text: String, success: String) {
    exportStatus = LocalNoticeClipboard.copyText(text, center: account.localNotices, success: success) { value in
      NSPasteboard.general.clearContents()
      return NSPasteboard.general.setString(value, forType: .string)
    }
  }
  private func exportNotice(_ message: String, level: LocalNoticeLevel) {
    exportStatus = message; account.localNotices.post(message, level: level)
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

  private var accuracyBlocks: Int { min(10, max(0, Int((result.preciseAccuracy / 10).rounded()))) }

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
          snapshotMetric("准确率", ResultMetricPresentation.compactAccuracy(result.preciseAccuracy))
          snapshotMetric("Raw \(typingSpeedUnit.displayName)", typingSpeedUnit.formatted(wpm: result.rawWpm))
          snapshotMetric("错误", "\(result.errorCount)")
        }
      }
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          Text("准确度刻度")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
          Spacer()
          Text(ResultMetricPresentation.compactAccuracy(result.preciseAccuracy))
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
  let player: TypingFeedbackSound

  init(selection: PracticeSoundSelection, player: TypingFeedbackSound) {
    playsClicks = selection.click != nil; playsErrors = selection.error != nil
    clickStyle = selection.click ?? .tink; errorStyle = selection.error ?? .basso
    volume = selection.volume; self.player = player
  }

  @MainActor init(settings: AppSettings) {
    playsClicks = settings.playKeyclickSound
    playsErrors = settings.playErrorBeep
    clickStyle = settings.clickSoundStyle
    errorStyle = settings.errorSoundStyle
    volume = settings.soundVolume
    player = settings.practiceFeedbackSound
  }
}

private struct ReplayTimelineView: View {
  let prompt: String
  let events: [TypingReplayEvent]
  let speedUnit: TypingSpeedUnit
  let configuration: TestConfiguration?
  let targetWordDirectory: ResultTargetWordDirectory?
  let sourceScoringBasis: ResultScoringUnitBasis?
  let soundConfiguration: ReplaySoundConfiguration
  @State private var elapsed: TimeInterval = 0
  @State private var isPlaying = false
  @State private var playbackStartedAt: TimeInterval?
  @State private var selectedPromptIndex: Int?
  @State private var fieldFrame: FieldReplayPlan.Frame?
  @State private var selectedFieldCoordinate: FieldReplayPlan.Coordinate?
  @State private var includesCurrentOffsetOnNextTick = true
  private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
  private let characterSeekOffsets: [Int: TimeInterval]
  private let replaySoundTimeline: [TypingReplayTimedSoundCue]
  private let fieldPlan: FieldReplayPlan?
  private let canPlay: Bool

  private var duration: TimeInterval { events.last?.offset ?? 0 }
  private var replayedGlyphs: [TypingPromptGlyph] {
    TypingReplay.inputGlyphs(prompt: prompt, events: events, through: elapsed, configuration: configuration)
  }
  private var performance: ResultPerformancePoint {
    ResultPerformanceTrace.point(prompt: prompt, events: events, elapsed: elapsed, configuration: configuration,
      targetWordDirectory: targetWordDirectory, sourceScoringBasis: sourceScoringBasis)
  }

  init(
    prompt: String, events: [TypingReplayEvent], speedUnit: TypingSpeedUnit,
    configuration: TestConfiguration?,
    targetWordDirectory: ResultTargetWordDirectory?,
    sourceScoringBasis: ResultScoringUnitBasis?,
    soundConfiguration: ReplaySoundConfiguration
  ) {
    let chronologicalEvents = TypingReplay.chronologicalEvents(events)
    self.prompt = prompt
    self.events = chronologicalEvents
    self.speedUnit = speedUnit
    self.configuration = configuration
    self.targetWordDirectory = targetWordDirectory
    self.sourceScoringBasis = sourceScoringBasis
    self.soundConfiguration = soundConfiguration
    self.characterSeekOffsets = TypingReplay.characterSeekOffsets(
      prompt: prompt, events: chronologicalEvents)
    self.replaySoundTimeline = TypingReplay.soundTimeline(
      prompt: prompt, events: chronologicalEvents, configuration: configuration)
    let fieldPlan = FieldReplayPlan.make(prompt: prompt, events: chronologicalEvents,
      configuration: configuration, targetWordDirectory: targetWordDirectory)
    self.fieldPlan = fieldPlan
    self.canPlay = ResultReplayAvailability.canPlay(duration: chronologicalEvents.last?.offset ?? 0,
      events: chronologicalEvents, fieldPlan: fieldPlan)
    self._fieldFrame = State(initialValue: fieldPlan?.initialFrame)
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
      if let fieldPlan, let fieldFrame {
        let presentation = fieldFrame.presentation
        Text(configuration?.mode == .zen ? "禅模式输入回放（点按字符定位）" : "目标字形回放（点按字符定位）")
          .font(.caption2)
          .foregroundStyle(.secondary)
        ReplayCharacterPicker(
          text: presentation.text,
          reachableIndices: Set(presentation.coordinates.indices.filter { index in
            fieldPlan.maximumSeekCoordinate.map { presentation.coordinates[index] <= $0 } ?? false
          }),
          selectedIndex: presentation.coordinates.firstIndex { $0 == selectedFieldCoordinate },
          glyphs: presentation.glyphs, errorIndices: presentation.errorIndices
        ) { index in
          guard presentation.coordinates.indices.contains(index),
            let seek = fieldPlan.seek(presentation.coordinates[index]) else { return }
          selectedFieldCoordinate = presentation.coordinates[index]
          self.fieldFrame = seek.frame
          elapsed = min(duration, seek.nextOffset)
          isPlaying = false
          playbackStartedAt = nil
        }
        .frame(height: 96)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
      } else {
        ReplayInputView(glyphs: replayedGlyphs)
          .frame(height: 72)
          .padding(8)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        if configuration?.mode != .zen {
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
              playbackStartedAt = nil
              includesCurrentOffsetOnNextTick = false
            }
            .frame(height: 96)
            .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
          }
        }
      }
      Slider(
        value: Binding(get: { elapsed }, set: { value in
          elapsed = min(duration, value)
          fieldFrame = fieldPlan?.frame(through: elapsed)
          selectedFieldCoordinate = nil
        }), in: 0...max(duration, 0.01),
        onEditingChanged: { editing in
          if editing {
            isPlaying = false
            playbackStartedAt = nil
            selectedPromptIndex = nil
            includesCurrentOffsetOnNextTick = false
          }
        })
        .accessibilityLabel("回放时间")
        .accessibilityHint(configuration?.mode == .zen
          ? "调整回放位置；字段记录完整时也可点按字符定位"
          : "调整回放位置；目标文本也支持鼠标点选字符定位")
      HStack {
        Button(isPlaying ? "暂停" : "播放") {
          if elapsed >= duration && (fieldPlan == nil || fieldFrame?.nextActionIndex == fieldPlan?.actions.count) {
            elapsed = 0
            fieldFrame = fieldPlan?.initialFrame
            includesCurrentOffsetOnNextTick = true
          }
          selectedPromptIndex = nil
          selectedFieldCoordinate = nil
          isPlaying.toggle()
          playbackStartedAt = isPlaying
            ? ProcessInfo.processInfo.systemUptime - elapsed : nil
        }
        .disabled(!canPlay)
        Button("重置") {
          elapsed = 0
          isPlaying = false
          playbackStartedAt = nil
          selectedPromptIndex = nil
          selectedFieldCoordinate = nil
          fieldFrame = fieldPlan?.initialFrame
          includesCurrentOffsetOnNextTick = true
        }
        .disabled(elapsed == 0 && !isPlaying && (fieldFrame?.nextActionIndex ?? 0) == 0)
        Spacer()
      }
    }
    .onReceive(timer) { _ in
      guard isPlaying, let playbackStartedAt else { return }
      let previousElapsed = elapsed
      elapsed = TypingReplay.playbackElapsed(
        startedAt: playbackStartedAt, now: ProcessInfo.processInfo.systemUptime,
        duration: duration)
      let soundLowerBound = includesCurrentOffsetOnNextTick
        ? -Double.leastNonzeroMagnitude : previousElapsed
      includesCurrentOffsetOnNextTick = false
      if let fieldPlan, var frame = fieldFrame {
        let cues = fieldPlan.advance(&frame, through: elapsed)
        fieldFrame = frame
        playSounds(cues)
      } else {
        playSounds(after: soundLowerBound, through: elapsed)
      }
      if elapsed >= duration {
        isPlaying = false
        self.playbackStartedAt = nil
      }
    }
  }

  private func playSounds(after lowerBound: TimeInterval, through upperBound: TimeInterval) {
    playSounds(TypingReplay.soundCues(in: replaySoundTimeline, after: lowerBound, through: upperBound))
  }

  private func playSounds(_ cues: [TypingReplaySoundCue]) {
    for cue in cues {
      switch TypingReplaySoundRoute.resolve(
        cue: cue, playsClicks: soundConfiguration.playsClicks,
        playsErrors: soundConfiguration.playsErrors)
      {
      case .none:
        break
      case .click:
        soundConfiguration.player.playClick(
          style: soundConfiguration.clickStyle, volume: soundConfiguration.volume)
      case .error:
        soundConfiguration.player.playError(
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
  private let accountTagCompletionRows: [AccountTagCompletionRow]

  init(
    prompt: String,
    events: [TypingReplayEvent],
    duration: TimeInterval,
    configuration: TestConfiguration?,
    targetWordDirectory: ResultTargetWordDirectory?,
    sourceScoringBasis: ResultScoringUnitBasis?,
    reviews: [TypedWordReview],
    typingSpeedUnit: TypingSpeedUnit,
    startsAtZero: Bool,
    visibility: ResultPerformanceVisibility,
    resultPersonalBestFeedback: ResultPersonalBestFeedback?,
    tagPersonalBestFeedback: [TagPersonalBestFeedback],
    accountTagCompletionRows: [AccountTagCompletionRow] = [],
    onVisibilityChange: @escaping (ResultPerformanceVisibility) -> Void,
    onScaleChange: @escaping (Bool) -> Void,
    onInspectionChange: @escaping ([Int]) -> Void,
    accent: Color
  ) {
    points = ResultPerformanceTrace.points(
      prompt: prompt, events: events, duration: duration, configuration: configuration,
      targetWordDirectory: targetWordDirectory, sourceScoringBasis: sourceScoringBasis)
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
    self.accountTagCompletionRows = accountTagCompletionRows.filter(\.showsPreviousBestLine)
    self.accent = accent
  }

  var body: some View {
    if !points.isEmpty {
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
          .help(visibility.smoothBurst
            ? "显示原始 Burst 数据"
            : "平均相邻且相差不超过本轮最大 Burst 25% 的值；保留大幅变化")
          traceToggle("错误", isOn: visibilityBinding(\.errors), color: .red)
            .help("统计每个采样时间段内的错误输入；退格不抹去已发生的错误")
          if resultPersonalBestFeedback != nil {
            traceToggle("本机 PB", isOn: visibilityBinding(\.personalBestLine), color: .secondary)
          }
          if !tagPersonalBestFeedback.isEmpty || !accountTagCompletionRows.isEmpty {
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
              y: .value(typingSpeedUnit.displayName,
                ResultBurstDisplayPolicy.value(wpm: point.burstWpm, unit: typingSpeedUnit))
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
            ForEach(Array(accountTagCompletionRows.enumerated()), id: \.element.id) { index, row in
              RuleMark(y: .value("账户标签 PB", typingSpeedUnit.converted(wpm: row.previousBestWpm)))
                .foregroundStyle(.secondary.opacity(0.6))
                .lineStyle(.init(lineWidth: 1, dash: [1, 4]))
                .annotation(position: .top, alignment: index.isMultiple(of: 2) ? .leading : .trailing) {
                  Text("\(row.name) PB \(typingSpeedUnit.formatted(wpm: row.previousBestWpm))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .offset(x: index.isMultiple(of: 2) ? 15 : -15)
                }
            }
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
        Text("Burst \(ResultBurstDisplayPolicy.text(wpm: inspection.point.burstWpm, unit: typingSpeedUnit))")
      }
      if visibility.errors {
        Text("本段错误 \(inspection.point.errorCount)")
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
    if !accountTagCompletionRows.isEmpty { description += "；账户标签 PB 按完成时的客户端基线显示" }
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
  @State private var showingAccountHistory = false
  let account: AccountSession
  fileprivate enum ActivityChartMeasure: String, CaseIterable, Identifiable {
    case completedTests
    case typingMinutes
    case typingMinutesAndAverageSpeed
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
      case .typingMinutesAndAverageSpeed: "分钟 + 平均速度"
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
    let personalBestSpeed: Double?

    var id: UUID { metric.id }
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query(sort: \TestResultRecord.finishedAt, order: .reverse) private var results:
    [TestResultRecord]
  @Query private var personalBestLedgers: [LocalPersonalBestLedgerRecord]
  @Query(sort: \ResultFilterPresetRecord.createdAt, order: .reverse) private var filterPresets:
    [ResultFilterPresetRecord]
  private let resultTombstones = ResultTombstoneStore()
  private let resultFilterPresetTombstones = ResultFilterPresetTombstoneStore()
  @State private var selectedResult: TestResultRecord?
  @State private var modeFilter = Set(TestMode.allCases)
  @State private var languageFilter = Set(TypingLanguage.allCases)
  @State private var selectedTagFilter = ResultHistoryTagFilter()
  @State private var selectedAccountTagFilter: ResultHistoryAccountTagFilter?
  @State private var currentSettingsFilterMessage: String?
  @State private var difficultyFilter = Set(Difficulty.allCases)
  @State private var personalBestFilter: ResultHistoryPersonalBestFilter = .all
  @State private var dateRangeFilter: ResultHistoryDateRange = .all
  @State private var punctuationFilter: ResultHistoryBinaryFilter = .all
  @State private var numbersFilter: ResultHistoryBinaryFilter = .all
  @State private var quoteLengthFilter = ResultHistoryFilter.filterableQuoteLengths
  @State private var timeLimitFilter = Set(ResultHistoryTimeLimit.allCases)
  @State private var wordLimitFilter = Set(ResultHistoryWordLimit.allCases)
  @State private var includesNoModifierFilter = true
  @State private var includesPolyglotFilter: Bool?
  @State private var modifierFilter = Set(TestModifier.allCases)
  @State private var filterPresetName = ""
  @State private var activityChartMeasure: ActivityChartMeasure = .completedTests
  @State private var selectedHistoryDate: Date?
  @State private var historyListScrollTarget: UUID?
  @State private var historySortField: ResultHistorySortField = .finishedAt
  @State private var historySortDirection: ResultHistorySortDirection = .descending
  @State private var visibleResultLimit = ResultHistoryPagePolicy.pageSize
  @State private var csvExportStatus: String?
  @State private var showingPersonalBestTable = false

  private var filteredResults: [TestResultRecord] {
    let filter = activeFilter
    let canonical = account.historyAccountTagMetadata
    let scope = account.hasAccountTagDirectory ? account.resultPublicationScope : nil
    let knownIDs = Set(account.accountTags.map(\.id))
    let entries = results.map { result in
      let configuration = result.configuration
      return ResultHistoryEntry(
        id: result.id, mode: configuration?.mode, language: configuration?.language, tags: result.tags,
        finishedAt: result.finishedAt, difficulty: configuration?.difficulty,
        includesPunctuation: configuration?.contentOptions.includePunctuation,
        includesNumbers: configuration?.contentOptions.includeNumbers,
        quoteLength: configuration.flatMap { configuration -> QuoteLength? in
          guard configuration.mode == .quote else { return nil }
          return result.quoteSource?.actualLength
            ?? QuoteLengthPolicy.actualLength(for: result.prompt, language: configuration.language)
        },
        duration: configuration?.duration,
        wordLimit: configuration?.wordLimit,
        modifiers: configuration?.modifiers,
        isPolyglot: configuration.map { $0.language == .mixedLanguages },
        accountTags: AccountTagHistoryFilterPolicy.metadata(id: result.id,
          snapshot: AccountTagHistoryFilterPolicy.snapshot(from: result.accountTagSnapshotData),
          scope: scope, knownIDs: knownIDs, canonical: canonical)
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

  private var chartActivity: [ActivityBarPoint] {
    ActivityAggregation.chartDays(activity: activity)
  }

  private var speedHistogram: [SpeedHistogramBucket] {
    SpeedHistogram.buckets(metrics: metrics, unit: settings.typingSpeedUnit)
  }

  private var filterSummaryItems: [ResultHistoryFilterSummaryItem] {
    ResultHistoryFilterSummaryPolicy.items(for: activeFilter)
  }

  private var personalBestIDs: Set<UUID> {
    Set(personalBestLedgers.first?.ledger?.entries.map(\.row.id) ?? [])
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
              points: chartActivity, measure: $activityChartMeasure,
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
                        resultFilterPresetTombstones.markDeleted(preset.id)
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
                      .help("按住 Shift 点击可只保留这一项。")
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
                      .help("按住 Shift 点击可只保留这一项。")
                  }
                }
                DisclosureGroup(
                  "引语长度：\(ResultHistoryFilter.quoteLengthSelectionSummary(quoteLengthFilter))"
                ) {
                  ForEach(QuoteLength.allCases.filter { $0 != .all }, id: \.self) { length in
                    Toggle(length.displayName, isOn: quoteLengthBinding(for: length))
                      .toggleStyle(.checkbox)
                      .help("按住 Shift 点击可只保留这一项。")
                  }
                }
                DisclosureGroup(
                  "时长：\(ResultHistoryTimeLimit.selectionSummary(timeLimitFilter))"
                ) {
                  ForEach(ResultHistoryTimeLimit.allCases, id: \.self) { limit in
                    Toggle(limit.displayName, isOn: timeLimitBinding(for: limit))
                      .toggleStyle(.checkbox)
                      .help("按住 Shift 点击可只保留这一项。")
                  }
                }
                DisclosureGroup(
                  "字数：\(ResultHistoryWordLimit.selectionSummary(wordLimitFilter))"
                ) {
                  ForEach(ResultHistoryWordLimit.allCases, id: \.self) { limit in
                    Toggle(limit.displayName, isOn: wordLimitBinding(for: limit))
                      .toggleStyle(.checkbox)
                      .help("按住 Shift 点击可只保留这一项。")
                  }
                }
                DisclosureGroup("修饰器：\(activeModifierFilter.selectionSummary)") {
                  Toggle("无修饰器", isOn: Binding(get: { includesNoModifierFilter }, set: { selected in
                    updateModifierFilter { $0.setNoModifiersSelected(selected) }
                  }))
                    .toggleStyle(.checkbox)
                  Toggle("Polyglot 多语混排", isOn: Binding(get: { activeModifierFilter.effectiveIncludesPolyglot }, set: { selected in
                    includesPolyglotFilter = selected
                  })).toggleStyle(.checkbox)
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
                  DisclosureGroup("本机文字标签：\(selectedTagFilter.selectionSummary)") {
                    Toggle("无标签", isOn: noTagBinding)
                      .toggleStyle(.checkbox)
                    ForEach(availableTags, id: \.self) { tag in
                      Toggle(tag, isOn: tagBinding(for: tag))
                        .toggleStyle(.checkbox)
                    }
                  }
                }
                AccountTagHistoryFilterControls(account: account, filter: $selectedAccountTagFilter)
                if let currentSettingsFilterMessage {
                  Text(currentSettingsFilterMessage).font(.caption).foregroundStyle(.secondary)
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
                      Text("\(rowSummary.modeAndParameter) · \(ResultMetricPresentation.accuracy(CompletedTestResult.normalizedAccuracyPrecision(result.preciseAccuracy, fallback: result.accuracy), alwaysShowDecimalPlaces: true)) 准确率")
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
                    if result.outcome == TestOutcome.bailedOut.rawValue {
                      Label("中止", systemImage: "stop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("raw \(result.rawWpm) · \(consistencyText(for: result))% 稳定")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
                .buttonStyle(.plain)
                .id(result.id)
                .background(
                  selectedHistoryMetric?.id == result.id ? Color.accentColor.opacity(0.14) : .clear,
                  in: RoundedRectangle(cornerRadius: 6))
                .accessibilityValue(
                  selectedHistoryMetric?.id == result.id ? "趋势图已选择" : "")
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
            .scrollPosition(id: $historyListScrollTarget, anchor: .center)
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
          Button("账户历史…") { showingAccountHistory = true }
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
      LocalPersonalBestTableView(
        speedUnit: settings.typingSpeedUnit, alwaysShowDecimalPlaces: settings.alwaysShowDecimalPlaces)
    }
    .sheet(isPresented: $showingAccountHistory) {
      AccountHistoryView(settings: settings, account: account, currentConfiguration: currentConfiguration)
    }
    .onChange(of: activeFilter) {
      visibleResultLimit = ResultHistoryPagePolicy.pageSize
      selectedHistoryDate = nil
      historyListScrollTarget = nil
    }
    .onChange(of: account.accountTagRevision) { reconcileAccountTagFilter() }
    .onChange(of: selectedHistoryDate) { revealSelectedHistoryResult() }
    .onChange(of: historySortField) { resetHistoryPagination() }
    .onChange(of: historySortDirection) { resetHistoryPagination() }
  }

  private func revealSelectedHistoryResult() {
    guard let selectedID = selectedHistoryMetric?.id else {
      historyListScrollTarget = nil
      return
    }
    visibleResultLimit = ResultHistorySelectionRevealPolicy.visibleLimit(
      currentLimit: visibleResultLimit, selectedID: selectedID,
      sortedIDs: sortedFilteredResults.map(\.id))
    historyListScrollTarget = selectedID
  }

  private func resetHistoryPagination() {
    visibleResultLimit = ResultHistoryPagePolicy.pageSize
    revealSelectedHistoryResult()
  }

  private var historyChartPoints: [HistoryChartPoint] {
    let speeds = metrics.map { Double($0.wpm) }
    let accuracies = metrics.map(\.accuracy)
    let speedAverage10 = HistoryChartPolicy.movingAverage(values: speeds, windowSize: 10)
    let speedAverage100 = HistoryChartPolicy.movingAverage(values: speeds, windowSize: 100)
    let accuracyAverage10 = HistoryChartPolicy.movingAverage(values: accuracies, windowSize: 10)
    let accuracyAverage100 = HistoryChartPolicy.movingAverage(values: accuracies, windowSize: 100)
    let personalBestSpeed = HistoryChartPolicy.personalBestEnvelope(metrics: metrics)
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
              "\(settings.typingSpeedUnit.formatted(wpm: metric.wpm)) \(settings.typingSpeedUnit.displayName) · Raw \(settings.typingSpeedUnit.formatted(wpm: metric.rawWpm)) · \(ResultMetricPresentation.accuracy(metric.accuracy, alwaysShowDecimalPlaces: true)) 准确率 · \(formattedConsistency(metric.consistency))% 稳定度"
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
      if let best = point.personalBestSpeed {
        LineMark(
          x: .value("日期", point.metric.finishedAt),
          y: .value(settings.typingSpeedUnit.displayName, settings.typingSpeedUnit.converted(wpm: best)))
          .foregroundStyle(.secondary.opacity(0.45))
          .lineStyle(.init(lineWidth: 1, dash: [4, 3]))
      }
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
      statistic("平均准确率", ResultMetricPresentation.percentage(summary.averageAccuracy, alwaysShowDecimalPlaces: settings.alwaysShowDecimalPlaces))
      statistic("最高准确率", ResultMetricPresentation.percentage(summary.bestAccuracy, alwaysShowDecimalPlaces: settings.alwaysShowDecimalPlaces))
      statistic("近 10 准确率", ResultMetricPresentation.percentage(summary.averageAccuracyLast10, alwaysShowDecimalPlaces: settings.alwaysShowDecimalPlaces))
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
    for index in offsets {
      resultTombstones.markDeleted(visibleResults[index].id)
      modelContext.delete(visibleResults[index])
    }
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
      accountTagFilter: selectedAccountTagFilter,
      personalBestFilter: personalBestFilter, difficulties: difficultyFilter, dateRange: dateRangeFilter,
      punctuation: punctuationFilter, numbers: numbersFilter, quoteLengths: quoteLengthFilter,
      timeLimits: timeLimitFilter, wordLimits: wordLimitFilter, modifierFilter: activeModifierFilter
    )
  }

  private var activeModifierFilter: ResultHistoryModifierFilter {
    .init(includesNoModifiers: includesNoModifierFilter, modifiers: modifierFilter,
      includesPolyglot: includesPolyglotFilter)
  }

  private func updateModifierFilter(_ update: (inout ResultHistoryModifierFilter) -> Void) {
    var filter = activeModifierFilter
    update(&filter)
    includesNoModifierFilter = filter.includesNoModifiers
    modifierFilter = filter.modifiers
    includesPolyglotFilter = filter.includesPolyglot
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
    guard let scope = account.resultPublicationScope else {
      apply(.currentSettings(currentConfiguration, activeTags: settings.activeResultTags))
      return
    }
    guard account.hasAccountTagDirectory else {
      currentSettingsFilterMessage = "账户标签尚未加载。请在账户设置刷新后使用当前设置筛选。"
      return
    }
    do {
      let ids = Set(try account.accountTagPostingSelection()), known = Set(account.accountTags.map(\.id))
      guard ids.isSubset(of: known) else { throw RemoteAccountError.unexpectedResponse }
      apply(.currentSettings(currentConfiguration, accountTagFilter:
        .init(scope: scope, knownIDs: known, selectedIDs: ids, includesNoTags: ids.isEmpty)))
    } catch {
      currentSettingsFilterMessage = "账户标签选择无法读取，请重新选择；原筛选保持不变。"
    }
  }

  private func apply(_ filter: ResultHistoryFilter) {
    modeFilter = filter.modeSelections
    languageFilter = filter.languageSelections
    selectedTagFilter = filter.effectiveTagFilter
    selectedAccountTagFilter = filter.accountTagFilter
    currentSettingsFilterMessage = nil
    reconcileAccountTagFilter()
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
    includesPolyglotFilter = filter.modifierFilter.includesPolyglot
  }

  private func reconcileAccountTagFilter() {
    guard account.hasAccountTagDirectory, let scope = account.resultPublicationScope else { return }
    selectedAccountTagFilter?.reconcile(scope: scope, knownIDs: Set(account.accountTags.map(\.id)))
  }

  private func timeLimitBinding(for limit: ResultHistoryTimeLimit) -> Binding<Bool> {
    ResultHistoryFilterChoice.binding(for: limit, selection: $timeLimitFilter)
  }

  private func modeBinding(for mode: TestMode) -> Binding<Bool> {
    ResultHistoryFilterChoice.binding(for: mode, selection: $modeFilter)
  }

  private func difficultyBinding(for difficulty: Difficulty) -> Binding<Bool> {
    ResultHistoryFilterChoice.binding(for: difficulty, selection: $difficultyFilter)
  }

  private func quoteLengthBinding(for length: QuoteLength) -> Binding<Bool> {
    ResultHistoryFilterChoice.binding(for: length, selection: $quoteLengthFilter)
  }

  private func wordLimitBinding(for limit: ResultHistoryWordLimit) -> Binding<Bool> {
    ResultHistoryFilterChoice.binding(for: limit, selection: $wordLimitFilter)
  }

  private func modifierBinding(for modifier: TestModifier) -> Binding<Bool> {
    Binding(
      get: { modifierFilter.contains(modifier) },
      set: { selected in
        updateModifierFilter { filter in
          var modifiers = filter.modifiers
          if selected { modifiers.insert(modifier) } else { modifiers.remove(modifier) }
          filter.setModifiers(modifiers)
        }
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
    case .typingMinutesAndAverageSpeed: "练习分钟"
    default: measure.title
    }
  }

  private var typingMinutesTrend: [ActivityTypingMinutesTrendPoint] {
    switch measure {
    case .typingMinutes, .typingMinutesAndAverageSpeed:
      ActivityTypingMinutesTrendPolicy.points(for: points)
    default:
      []
    }
  }

  private var overviewScale: DailyActivityOverviewScale? {
    guard measure == .typingMinutesAndAverageSpeed else { return nil }
    return DailyActivityOverviewScale.make(
      points: points, speedUnit: speedUnit, startsAtZero: startsAtZero)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text("每日练习").font(.caption.weight(.medium))
        Spacer()
        Picker("柱状图指标", selection: $measure) {
          ForEach(ResultsHistoryView.ActivityChartMeasure.allCases) { measure in
            Text(measure.title).tag(measure)
          }
        }
        .pickerStyle(.menu)
        .frame(width: 180)
      }
      if measure == .typingMinutesAndAverageSpeed {
        if let overviewScale {
          overviewChart(scale: overviewScale)
        } else {
          ContentUnavailableView(
            "没有可用的每日活动数据", systemImage: "chart.bar.xaxis",
            description: Text("完成练习后即可并列查看练习分钟和平均速度。"))
            .frame(height: 110)
        }
      } else {
        singleMetricChart
      }
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

  private var singleMetricChart: some View {
    Chart {
        ForEach(points) { point in
          if let value = value(for: point) {
            BarMark(
              x: .value("日期", point.day),
              y: .value(yTitle, value)
            )
            .foregroundStyle(Color.accentColor.gradient)
            .accessibilityLabel(point.day.formatted(date: .abbreviated, time: .omitted))
            .accessibilityValue(accessibilityValue(for: point))
          }
        }
        ForEach(typingMinutesTrend) { point in
          LineMark(
            x: .value("日期", point.day),
            y: .value("练习分钟趋势", point.minutes),
            series: .value("曲线", "minutes-trend")
          )
          .foregroundStyle(.secondary)
          .lineStyle(.init(lineWidth: 2, dash: [4, 3]))
          .accessibilityLabel("练习分钟趋势")
          .accessibilityValue(
            "\(point.day.formatted(date: .abbreviated, time: .omitted))，\(point.minutes.formatted(.number.precision(.fractionLength(0...2)))) 分钟")
        }
        if let selectedPoint {
          RuleMark(x: .value("所选日期", selectedPoint.day))
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
      .chartXScale(range: .plotDimension(startPadding: 12, endPadding: 12))
      .chartPlotStyle { $0.clipped() }
      .chartXSelection(value: $selectedDate)
      .frame(height: 110)
  }

  private func overviewChart(scale: DailyActivityOverviewScale) -> some View {
    Chart {
      overviewMarks(scale: scale)
    }
    .chartXAxis {
      AxisMarks(values: .stride(by: .weekOfYear)) { _ in
        AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
        AxisValueLabel(format: .dateTime.month().day())
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading) { _ in
        AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
        AxisTick()
        AxisValueLabel()
      }
      AxisMarks(position: .trailing, values: scale.ordinateTicks) { value in
        AxisTick()
        AxisValueLabel {
          if let ordinate = value.as(Double.self) {
            Text(formattedOverviewSpeed(scale.speed(atOrdinate: ordinate)))
          }
        }
      }
    }
    .chartYScale(domain: 0...scale.minutesUpperBound)
    .chartXScale(range: .plotDimension(startPadding: 12, endPadding: 12))
    .chartPlotStyle { $0.clipped() }
    .chartXSelection(value: $selectedDate)
    .chartYAxisLabel("左：练习分钟 · 右：平均 \(speedUnit.displayName)")
    .frame(height: 150)
    .accessibilityLabel("每日练习分钟与平均速度")
    .accessibilityHint("柱状图使用左轴，折线使用右轴；拖动可查看某一天的完整指标")
  }

  @ChartContentBuilder
  private func overviewMarks(scale: DailyActivityOverviewScale) -> some ChartContent {
    ForEach(points) { point in
      if point.completedTests > 0 {
        overviewDayMarks(for: point, scale: scale)
      }
    }
    ForEach(typingMinutesTrend) { point in
      LineMark(
        x: .value("日期", point.day),
        y: .value("练习分钟趋势", point.minutes),
        series: .value("曲线", "minutes-trend")
      )
      .foregroundStyle(.secondary.opacity(0.65))
      .lineStyle(.init(lineWidth: 2, dash: [4, 3]))
      .accessibilityLabel("练习分钟趋势")
    }
    if let selectedPoint {
      RuleMark(x: .value("所选日期", selectedPoint.day))
        .foregroundStyle(.secondary)
        .lineStyle(.init(lineWidth: 1, dash: [3, 3]))
    }
  }

  @ChartContentBuilder
  private func overviewDayMarks(
    for point: ActivityBarPoint, scale: DailyActivityOverviewScale
  ) -> some ChartContent {
    let minutes = point.typingSeconds / 60
    BarMark(
      x: .value("日期", point.day),
      y: .value("练习分钟", minutes)
    )
    .foregroundStyle(Color.accentColor.gradient)
    .accessibilityLabel(point.day.formatted(date: .abbreviated, time: .omitted))
    .accessibilityValue(
      minutes.formatted(.number.precision(.fractionLength(0...2))) + " 分钟练习；平均 "
        + formattedOverviewSpeed(
          scale.speed(atOrdinate: scale.ordinate(forAverageWPM: point.averageWPM)))
        + " " + speedUnit.displayName)

    LineMark(
      x: .value("日期", point.day),
      y: .value("平均速度（右轴）", scale.ordinate(forAverageWPM: point.averageWPM)),
      series: .value("曲线", "average-speed")
    )
    .foregroundStyle(.secondary)
    .lineStyle(.init(lineWidth: 2))
    PointMark(
      x: .value("日期", point.day),
      y: .value("平均速度（右轴）", scale.ordinate(forAverageWPM: point.averageWPM))
    )
    .foregroundStyle(.secondary)
    .symbol(.triangle)
  }

  private var includesZero: Bool {
    switch measure {
    case .completedTests, .typingMinutes, .restartsPerCompletedTest: true
    case .averageSpeed, .highestSpeed, .averageAccuracy, .averageConsistency: startsAtZero
    case .typingMinutesAndAverageSpeed: true
    }
  }

  private func value(for point: ActivityBarPoint) -> Double? {
    switch measure {
    case .completedTests: Double(point.completedTests)
    case .typingMinutes: point.typingSeconds / 60
    case .typingMinutesAndAverageSpeed: nil
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
    case .typingMinutesAndAverageSpeed:
      "\(Int((point.typingSeconds / 60).rounded())) 分钟练习；平均 \(formattedSpeed(point.averageWPM)) \(speedUnit.displayName)"
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

  private func formattedOverviewSpeed(_ speed: Double) -> String {
    speed.formatted(.number.precision(.fractionLength(0...2)))
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
  @State private var selectedPeriod: ActivityHeatmapPeriod = .rollingYear

  private var calendar: Calendar { .current }

  private var availablePeriods: [ActivityHeatmapPeriod] {
    let years = ActivityHeatmap.availableCalendarYears(
      activity: activity,
      dayBoundaryOffsetHours: dayBoundaryOffsetHours,
      calendar: calendar
    ).map(ActivityHeatmapPeriod.calendarYear)
    var periods = [.rollingYear] + years
    if !periods.contains(selectedPeriod) { periods.append(selectedPeriod) }
    return periods
  }

  private var cells: [ActivityHeatmapCell] {
    ActivityHeatmap.cells(
      activity: activity,
      period: selectedPeriod,
      dayBoundaryOffsetHours: dayBoundaryOffsetHours,
      calendar: calendar
    )
  }

  private var displayCells: [ActivityHeatmapDisplayCell] {
    ActivityHeatmap.displayCells(for: cells)
  }

  private let rows = Array(repeating: GridItem(.fixed(11), spacing: 3), count: 7)

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

  private func monthLabel(for column: Int) -> String {
    guard let month = monthByColumn[column] else { return "" }
    let index = calendar.component(.month, from: month) - 1
    guard calendar.shortMonthSymbols.indices.contains(index) else { return "" }
    return calendar.shortMonthSymbols[index]
  }

  private var completedTestCount: Int { ActivityHeatmap.completedTestCount(in: cells) }
  private var hasCompletedTests: Bool { cells.contains { $0.completedTests > 0 } }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("活动日历 · \(completedTestCount) 次完成").font(.caption.weight(.medium))
        Spacer()
        Picker("活动范围", selection: $selectedPeriod) {
          ForEach(availablePeriods) { period in
            Text(period.title).tag(period)
          }
        }
        .pickerStyle(.menu)
        .frame(width: 142)
        HStack(spacing: 3) {
          Text("少")
          ForEach(0...4, id: \.self) { intensity in
            RoundedRectangle(cornerRadius: 2)
              .fill(Color.accentColor.opacity(opacity(for: intensity)))
              .frame(width: 11, height: 11)
          }
          Text("多")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("完成次数强度图例")
        .accessibilityValue("由少到多；当前范围共 \(completedTestCount) 次完成")
      }
      HStack(alignment: .top, spacing: 6) {
        VStack(spacing: 3) {
          ForEach(weekdaySymbols, id: \.self) { symbol in
            Text(symbol)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .frame(width: 12, height: 11)
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
                  .frame(width: 11, height: 11, alignment: .leading)
              }
            }
            .accessibilityHidden(true)
            LazyHGrid(rows: rows, spacing: 3) {
              ForEach(0..<leadingFillerCount, id: \.self) { _ in
                Color.clear.frame(width: 11, height: 11)
              }
              ForEach(displayCells) { displayCell in
                RoundedRectangle(cornerRadius: 2)
                  .fill(Color.accentColor.opacity(opacity(for: displayCell.intensity)))
                  .frame(width: 11, height: 11)
                  .accessibilityLabel(
                    displayCell.cell.day.formatted(date: .abbreviated, time: .omitted))
                  .accessibilityValue(
                    displayCell.cell.completedTests == 0
                      ? "没有完成练习" : "\(displayCell.cell.completedTests) 次完成")
              }
              ForEach(0..<trailingFillerCount, id: \.self) { _ in
                Color.clear.frame(width: 11, height: 11)
              }
            }
            .frame(height: 95)
          }
        }
      }
      if !hasCompletedTests {
        Text("这个时间范围没有完成记录。")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Text("按这台 Mac 的统计日界聚合；范围切换不会修改本机成绩。")
        .font(.caption2)
        .foregroundStyle(.secondary)
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

private struct ResultWPMConsistencyRecordIdentity: Hashable {
  let id: UUID
  let prompt: String
  let startedAt: Date
  let finishedAt: Date
  let configurationData: Data
  let replayEventsData: Data?
  let targetWordDirectoryData: Data?
  let characterStatsData: Data?
  let terminalTimingData: Data?
  let elapsedTimeData: Data?
}

private struct ResultDetailView: View {
  @Environment(\.dismiss) private var dismiss
  let result: TestResultRecord
  let modeName: String
  let isPersonalBest: Bool
  let typingSpeedUnit: TypingSpeedUnit
  let settings: AppSettings
  @State private var showingPerformanceChart = false
  @State private var wpmConsistencyLoader = ResultWPMConsistencyLoader()

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
        if result.outcome == TestOutcome.bailedOut.rawValue {
          Label("中止", systemImage: "stop.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }
      HStack {
        Text(result.finishedAt, format: .dateTime.year().month().day().hour().minute())
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          showingPerformanceChart = true
        } label: {
          Label("查看速度图", systemImage: "chart.xyaxis.line")
        }
        .buttonStyle(.bordered)
        .disabled(!hasPerformanceChart)
        .accessibilityHint(performanceChartHelp)
        .help(performanceChartHelp)
      }
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
          Text(ResultMetricPresentation.accuracy(CompletedTestResult.normalizedAccuracyPrecision(result.preciseAccuracy, fallback: result.accuracy), alwaysShowDecimalPlaces: true))
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
          Text(ResultCharacterStatsPresentation.label(result.characterStats))
          Text(characterStatsText)
        }
        GridRow {
          Text("总用时")
          Text("\(Int(result.elapsedDuration)) 秒")
        }
        GridRow {
          Text("稳定度 / 按键稳定度")
          Text("\(consistencyText(consistency.typing))% / \(consistencyText(consistency.key))%")
        }
        GridRow {
          Text("WPM 稳定度")
          Text(wpmConsistencyText)
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
      if ResultReplayAvailability.isAvailable(prompt: result.prompt, events: result.replayEvents,
        configuration: result.configuration) {
        ReplayTimelineView(
          prompt: result.prompt, events: result.replayEvents, speedUnit: typingSpeedUnit,
          configuration: result.configuration,
          targetWordDirectory: result.targetWordDirectory,
          sourceScoringBasis: result.characterStats.sourceUnitBasis,
          soundConfiguration: .init(settings: settings))
          .id(result.id)
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
    .task(id: wpmConsistencyIdentity) {
      let input = ResultWPMConsistencyInput(prompt: result.prompt, duration: elapsedDuration,
        configurationData: result.configurationData, replayEventsData: result.replayEventsData,
        targetWordDirectoryData: result.targetWordDirectoryData,
        sourceScoringBasis: result.characterStats.sourceUnitBasis)
      await wpmConsistencyLoader.load(input)
    }
    .sheet(isPresented: $showingPerformanceChart) {
      HistoricalResultPerformanceChart(result: result, typingSpeedUnit: typingSpeedUnit, settings: settings)
    }
  }

  private var elapsedDuration: TimeInterval {
    result.chartDuration
  }

  private var hasPerformanceChart: Bool {
    ResultPerformanceChartAvailability.isAvailable(
      prompt: result.prompt, events: result.replayEvents, duration: elapsedDuration,
      configuration: result.configuration, targetWordDirectory: result.targetWordDirectory,
      sourceScoringBasis: result.characterStats.sourceUnitBasis)
  }

  private var performanceChartHelp: String {
    if hasPerformanceChart {
      return "从本机输入回放重建每秒 WPM、Raw、Burst 和错误轨迹"
    }
    if elapsedDuration > ResultPerformanceTrace.maximumChartDuration {
      return "超过 \(Int(ResultPerformanceTrace.maximumChartDuration)) 秒的记录不提供速度图"
    }
    return "此记录没有可用于重建速度图的本机输入回放"
  }

  private var consistency: ResultConsistency {
    ResultConsistencyPolicy.metrics(
      events: result.replayEvents,
      duration: result.chartDuration,
      configuration: result.configuration, keySpacingSamples: result.keySpacingSamples
    )
  }

  private func consistencyText(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
  }

  private var wpmConsistencyIdentity: ResultWPMConsistencyRecordIdentity {
    .init(id: result.id, prompt: result.prompt, startedAt: result.startedAt, finishedAt: result.finishedAt,
      configurationData: result.configurationData, replayEventsData: result.replayEventsData,
      targetWordDirectoryData: result.targetWordDirectoryData, characterStatsData: result.characterStatsData,
      terminalTimingData: result.terminalTimingData, elapsedTimeData: result.elapsedTimeData)
  }

  private var wpmConsistencyText: String {
    switch wpmConsistencyLoader.state {
    case .loading: "计算中…"
    case .unavailable: "不可用（无可用字段采样）"
    case .value(let value): "\(consistencyText(value))%"
    }
  }

  private var characterStatsText: String {
    ResultCharacterStatsPresentation.value(result.characterStats)
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

private struct HistoricalResultPerformanceChart: View {
  @Environment(\.dismiss) private var dismiss
  let result: TestResultRecord
  let typingSpeedUnit: TypingSpeedUnit
  let settings: AppSettings

  private var elapsedDuration: TimeInterval {
    result.chartDuration
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        Label("历史成绩速度图", systemImage: "chart.xyaxis.line")
          .font(.headline)
        Spacer()
        Button("完成") { dismiss() }
      }
      Text("按秒从本机输入回放重建；与当前结果页共用图表显示偏好。")
        .font(.caption)
        .foregroundStyle(.secondary)
      ResultPerformanceChart(
        prompt: result.prompt,
        events: result.replayEvents,
        duration: elapsedDuration,
        configuration: result.configuration,
        targetWordDirectory: result.targetWordDirectory,
        sourceScoringBasis: result.characterStats.sourceUnitBasis,
        reviews: [],
        typingSpeedUnit: typingSpeedUnit,
        startsAtZero: settings.startGraphsAtZero,
        visibility: settings.resultPerformanceVisibility,
        resultPersonalBestFeedback: nil,
        tagPersonalBestFeedback: [],
        onVisibilityChange: { settings.resultPerformanceVisibility = $0 },
        onScaleChange: { settings.startGraphsAtZero = $0 },
        onInspectionChange: { _ in },
        accent: .accentColor)
    }
    .padding(24)
    .frame(width: 680, height: 360)
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
