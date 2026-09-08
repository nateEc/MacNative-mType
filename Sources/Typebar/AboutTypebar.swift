import SwiftUI

struct TypebarAboutMetadata: Equatable, Sendable {
  let version: String?
  let build: String?

  init(info: [String: Any]) {
    version = Self.nonempty(info["CFBundleShortVersionString"] as? String)
    build = Self.nonempty(info["CFBundleVersion"] as? String)
  }

  static var current: Self {
    .init(info: Bundle.main.infoDictionary ?? [:])
  }

  var versionLabel: String {
    switch (version, build) {
    case (.some(let version), .some(let build)): "版本 \(version) · 构建 \(build)"
    case (.some(let version), nil): "版本 \(version)"
    case (nil, .some(let build)): "构建 \(build)"
    case (nil, nil): "开发构建"
    }
  }

  private static func nonempty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return nil }
    return value
  }
}

enum AboutCommand {
  static let identifier = "about"
  static let item = CommandPaletteItem(
    id: identifier,
    title: "关于 Typebar",
    subtitle: "查看版本、指标说明、隐私边界和项目源码",
    systemImage: "info.circle",
    keywords: ["about", "version", "privacy", "source", "关于", "版本", "隐私", "源码"],
    group: .settings)
}

struct TypebarAboutCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("关于 Typebar") { openWindow(id: "about") }
    }
  }
}

struct AboutTypebarView: View {
  let metadata: TypebarAboutMetadata

  private let sourceURL = URL(string: "https://github.com/nateEc/MacNative-mType")!
  private let issuesURL = URL(string: "https://github.com/nateEc/MacNative-mType/issues")!
  private let referenceURL = URL(string: "https://github.com/monkeytypegame/monkeytype")!

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        identity
        principles
        metrics
        compatibility
        links
      }
      .padding(32)
    }
    .frame(width: 560, height: 620)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text("type")
        Text("/").foregroundStyle(.orange)
        Text("bar")
        Rectangle()
          .fill(.orange)
          .frame(width: 3, height: 34)
          .accessibilityHidden(true)
      }
      .font(.system(size: 42, weight: .semibold, design: .rounded))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Typebar")

      Text("为 macOS 独立编写的原生打字练习工具")
        .font(.title3.weight(.medium))
      Text(metadata.versionLabel)
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
    }
  }

  private var principles: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("本机优先", systemImage: "macbook")
      HStack(alignment: .top, spacing: 12) {
        principle("无广告", detail: "练习界面不显示广告，也不靠广告追踪换取功能。", icon: "rectangle.slash")
        principle("数据在手", detail: "成绩默认保存在本机，可由你主动备份或同步。", icon: "externaldrive")
        principle("网络可见", detail: "练习无需联网；账户、社区内容和远程背景使用清晰标注的网络路径。", icon: "network")
      }
    }
  }

  private var metrics: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("练习指标", systemImage: "chart.bar")
      metric("WPM", detail: "正确字符数（含正确提交的分隔符）÷ 5，再换算为每分钟。")
      metric("Raw", detail: "按最终保留的全部输入字符数计算原始速度，错误字符也会计入。")
      metric("准确率", detail: "最终保留输入中的正确字符占全部输入字符的比例。")
      metric("稳定度", detail: "由本机输入回放中的速度离散程度映射为 0–100%。")
    }
  }

  private var compatibility: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionTitle("兼容性研究", systemImage: "checklist")
      Text("Typebar 以固定版本的 Monkeytype 开源源码盘点用户可见行为，再用 SwiftUI、SwiftData 和 AppKit 独立实现。应用不包含 Monkeytype 的代码、品牌资产、词表、引语、主题或布局文件。")
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Link("查看参考项目", destination: referenceURL)
    }
  }

  private var links: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionTitle("项目", systemImage: "chevron.left.forwardslash.chevron.right")
      HStack(spacing: 18) {
        Link("查看 Typebar 源码", destination: sourceURL)
        Link("报告问题或建议功能", destination: issuesURL)
      }
      Text("源码可见不自动代表特定授权；再分发或贡献前请以仓库中的许可文件为准。")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func sectionTitle(_ title: String, systemImage: String) -> some View {
    Label(title, systemImage: systemImage)
      .font(.headline)
  }

  private func principle(_ title: String, detail: String, icon: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(.orange)
      Text(title).font(.subheadline.weight(.semibold))
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
  }

  private func metric(_ name: String, detail: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(name)
        .font(.callout.monospaced().weight(.semibold))
        .foregroundStyle(.orange)
        .frame(width: 58, alignment: .leading)
      Text(detail)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
