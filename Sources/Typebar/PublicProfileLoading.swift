import SwiftUI

struct PublicProfileLoadID: Equatable {
  let profileID: UUID
  let sessionRevision: UInt64
  let retryRevision: UUID

  @MainActor init(profileID: UUID, account: AccountSession, retryRevision: UUID) {
    self.profileID = profileID
    sessionRevision = account.accountPersonalBestSessionRevision
    self.retryRevision = retryRevision
  }
}

/// The sheet's actual load state; an older request cannot replace a newer one,
/// even if its transport ignores cancellation. No lightweight-summary fallback.
@MainActor @Observable final class PublicProfileLoadState {
  private(set) var request: PublicProfileLoadID?
  private(set) var profile: RemotePublicProfile?
  private(set) var message: String?

  func load(request: PublicProfileLoadID,
    fetch: () async throws -> RemotePublicProfile) async {
    guard !Task.isCancelled else { return }
    self.request = request; profile = nil; message = nil
    do {
      let result = try await fetch()
      guard !Task.isCancelled, self.request == request else { return }
      guard result.id == request.profileID else { throw RemoteAccountError.unexpectedResponse }
      profile = result
    } catch {
      guard !Task.isCancelled, self.request == request else { return }
      message = "资料读取失败，请重试：" + error.localizedDescription
    }
  }
}

struct PublicProfileLoadingView: View {
  let profileID: UUID
  let account: AccountSession
  let settings: AppSettings
  @Environment(\.dismiss) private var dismiss
  @State private var retryRevision = UUID()
  @State private var state = PublicProfileLoadState()
  private var loadID: PublicProfileLoadID {
    .init(profileID: profileID, account: account, retryRevision: retryRevision)
  }

  var body: some View {
    Group {
      if state.request == loadID, let profile = state.profile {
        PublicProfileView(profile: profile, account: account, settings: settings)
      } else {
        PublicProfileLoadPlaceholder(message: state.request == loadID ? state.message : nil,
          retry: { retryRevision = UUID() }, close: { dismiss() })
      }
    }
    .task(id: loadID) {
      let request = loadID
      await state.load(request: request) { try await account.publicProfile(id: request.profileID) }
    }
  }
}

/// Shared production placeholder, separately mountable without starting a request.
struct PublicProfileLoadPlaceholder: View {
  let message: String?
  let retry: () -> Void
  let close: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      if let message {
        ScrollView {
          ContentUnavailableView("无法读取公开资料", systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text(message))
        }
        Button("重试", action: retry).buttonStyle(.borderedProminent)
      } else {
        ProgressView("正在读取公开资料…")
      }
      Button("关闭", action: close).keyboardShortcut(.cancelAction)
    }
    .padding(32)
    .frame(width: 420, height: 620)
  }
}
