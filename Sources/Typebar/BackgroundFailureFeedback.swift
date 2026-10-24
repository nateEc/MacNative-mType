import Foundation

@MainActor
final class BackgroundFailureFeedback {
  enum Kind: Equatable {
    case remote, local, resourceLimit, render, playback
    var message: String {
      switch self {
      case .remote: "背景链接暂时不可用或已失效，请检查链接或更换图片。"
      case .local: "无法读取本地背景，请重新选择图片。"
      case .resourceLimit: "背景超过资源限额，请使用更小的图片或动画。"
      case .render: "背景无法绘制，请降低模糊强度、缩小窗口或更换图片。"
      case .playback: "背景动画无法播放，请更换图片。"
      }
    }
  }
  typealias Sink = @MainActor (Kind) -> Void
  private struct Candidate {
    let kind: Kind
    let isCurrent: @MainActor () -> Bool
  }
  private var identity: UUID?
  private var generation = UUID()
  private var sink: Sink?
  private var delivered = false
  private var candidate: Candidate?
  private var delivery: Task<Void, Never>?
  deinit { delivery?.cancel() }

  func begin(identity: UUID, sink: @escaping Sink) {
    cancel(); self.identity = identity; self.sink = sink
  }
  func report(_ kind: Kind, identity: UUID, isCurrent: @escaping @MainActor () -> Bool = { true }) {
    guard self.identity == identity, !delivered else { return }
    candidate = .init(kind: kind, isCurrent: isCurrent)
    guard delivery == nil else { return }
    let token = generation
    delivery = Task { @MainActor [weak self] in
      guard !Task.isCancelled else { return }
      self?.deliver(token: token, identity: identity)
    }
  }
  private func deliver(token: UUID, identity: UUID) {
    guard generation == token, self.identity == identity, !delivered else { return }
    delivery = nil
    guard let candidate else { return }
    self.candidate = nil
    let current = candidate.isCurrent()
    guard generation == token, self.identity == identity, current else { return }
    delivered = true
    // Retire the pending delivery before user code can start another image.
    sink?(candidate.kind)
  }
  func cancel() {
    generation = UUID(); delivery?.cancel(); delivery = nil
    candidate = nil; identity = nil; sink = nil; delivered = false
  }
}

extension LocalNoticeCenter {
  /// Captures the current account/server lifetime, never an Error, URL or file path.
  func backgroundFailureSink() -> BackgroundFailureFeedback.Sink {
    let expected = deliveryGeneration
    return { [weak self] kind in
      guard let self, self.deliveryGeneration == expected else { return }
      self.post(kind.message, level: .notice, options: .init(durationMilliseconds: 5000))
    }
  }
}
