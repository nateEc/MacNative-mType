import AppKit
import SwiftUI

struct ProfileShareCopyButton: View {
  let profileID: UUID
  let account: AccountSession
  @State private var state = ProfileShareCopyState()
  private var target: SharedProfileTarget? {
    guard account.currentUser?.id == profileID else { return nil }
    return try? SharedProfileTarget(server: account.endpoint, profileID: profileID)
  }
  var body: some View {
    VStack(spacing: 6) {
      Button("复制公开资料链接", systemImage: "link") {
        guard let target else { return }
        state.copy(target: target) { link in
          NSPasteboard.general.clearContents()
          return NSPasteboard.general.setString(link, forType: .string)
        }
      }
      .disabled(target == nil)
      if target == nil { Text("当前服务地址不能用于分享。").font(.caption).foregroundStyle(.secondary) }
      if let message = state.message { Text(message).font(.caption).foregroundStyle(.secondary) }
      if let link = state.fallbackLink { Text(link).font(.caption).textSelection(.enabled) }
    }
    .onChange(of: account.accountPersonalBestSessionRevision) { state.clear() }
  }
}

/// Mountable confirmation; simply presenting a URL must not contact its server.
struct SharedProfileConfirmation: View {
  let target: SharedProfileTarget
  let confirm: () -> Void
  let close: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Label("查看分享的公开资料", systemImage: "person.crop.circle").font(.title2)
          Text("确认后才会匿名请求下面的服务器。不会切换登录，也不会发送当前账户的令牌或 Cookie。")
          Text(target.server.absoluteString).font(.body.monospaced()).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
          Text(target.profileID.uuidString.lowercased()).font(.caption.monospaced()).textSelection(.enabled)
          Text("分享页只读；好友和举报操作需返回已连接的服务。").font(.caption).foregroundStyle(.secondary)
          Text("资料若带 Discord 头像，会另行匿名读取 Discord CDN；同样不跟随重定向。").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      if target.usesPlainHTTP {
        Label("此服务器使用未加密 HTTP，网络中的其他人可能看到请求和资料。", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
      }
      HStack {
        Button("取消", action: close).keyboardShortcut(.cancelAction)
        Spacer()
        Button("匿名查看", action: confirm).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
      }
    }
    .padding(24).frame(width: 500, height: 420)
  }
}

struct SharedProfileLinkView: View {
  let route: SharedProfileRoute
  let account: AccountSession
  let settings: AppSettings
  @Environment(\.dismiss) private var dismiss
  @State private var state = SharedProfileLoadState()
  @State private var loadTask: Task<Void, Never>?
  var body: some View {
    Group {
      if let target = route.target {
        if let profile = state.profile {
          VStack(spacing: 8) {
            Text("分享的公开资料 · 只读").font(.headline)
            ScrollView { Text(target.server.absoluteString).font(.caption).textSelection(.enabled) }.frame(maxHeight: 55)
            PublicProfileView(profile: profile, account: account, settings: settings, allowsAccountActions: false, usesAnonymousMedia: true)
          }.padding(.top, 16).frame(width: 420)
        } else if state.isConfirmed {
          PublicProfileLoadPlaceholder(message: state.message, retry: { read(target) }, close: { dismiss() })
        } else {
          SharedProfileConfirmation(target: target, confirm: { read(target) }, close: { dismiss() })
        }
      } else {
        VStack {
          ContentUnavailableView("无法打开资料链接", systemImage: "link", description: Text(route.message ?? "链接无效。"))
          Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
        }.padding(24).frame(width: 500, height: 320)
      }
    }
    .onDisappear { loadTask?.cancel(); state.cancel() }
  }
  private func read(_ target: SharedProfileTarget) {
    guard loadTask == nil else { return }
    loadTask = Task { @MainActor in
      defer { loadTask = nil }
      await state.load(target: target) { try await SharedProfileReadClient().load(target) }
    }
  }
}

/// Preserve public avatars without falling back to AsyncImage's shared session.
struct SharedProfileAvatarImage: View {
  let url: URL
  @State private var image: NSImage?
  var body: some View {
    Group {
      if let image { Image(nsImage: image).resizable().scaledToFill() }
      else { Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary) }
    }
    .task(id: url) {
      image = nil
      do {
        let data = try await SharedProfileReadClient(maximumResponseBytes: 256_000).data(from: url, accept: "image/png")
        try Task.checkCancellation()
        image = NSImage(data: data)
      } catch { /* Optional avatar: keep the normal placeholder, never retry with credentials. */ }
    }
  }
}

struct SharedProfileImportView: View {
  let account: AccountSession
  let settings: AppSettings
  @Environment(\.dismiss) private var dismiss
  @State private var link = ""
  @State private var route: SharedProfileRoute?
  @State private var message: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("打开分享的资料链接").font(.title2)
      TextField("粘贴 typebar://profile 链接", text: $link)
      Text("检查链接不会联网；随后会先显示服务器地址供你确认。").font(.caption).foregroundStyle(.secondary)
      if let message { Text(message).foregroundStyle(.red) }
      HStack {
        Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("检查链接") {
          let candidate = SharedProfileRoute(link: link)
          if candidate.target != nil { message = nil; route = candidate } else { message = candidate.message }
        }.disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.padding(24).frame(width: 500)
    .sheet(item: $route) { SharedProfileLinkView(route: $0, account: account, settings: settings) }
  }
}

@MainActor final class SharedProfileWindowHost {
  weak var window: NSWindow?
  var canPresent: Bool { window != nil && window?.attachedSheet == nil }
}

/// Observes only our containing window. Never activates or creates an app window.
struct SharedProfileWindowProbe: NSViewRepresentable {
  let host: SharedProfileWindowHost
  let didAttach: () -> Void
  func makeNSView(context: Context) -> Probe {
    let view = Probe(); view.host = host; view.didAttach = didAttach
    view.setAccessibilityElement(false)
    return view
  }
  func updateNSView(_ view: Probe, context: Context) { view.host = host; view.didAttach = didAttach }
  static func dismantleNSView(_ view: Probe, coordinator: ()) {
    if view.host?.window === view.window { view.host?.window = nil }
    view.didAttach = nil; view.host = nil
  }
  final class Probe: NSView {
    weak var host: SharedProfileWindowHost?
    var didAttach: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      host?.window = window
      let expected = window
      Task { @MainActor [weak self] in
        guard let self, self.window === expected, expected != nil else { return }
        self.didAttach?()
      }
    }
  }
}
