import AppKit
import SwiftUI

/// Explicit practice-page ownership, independent of titles and close guards.
@MainActor
final class TypingMusicPracticeScopeRegistry: NSObject {
  static let shared = TypingMusicPracticeScopeRegistry()
  static let didChange = Notification.Name("Typebar.musicPracticeScopeChanged")

  private final class Entry {
    let identifier = UUID()
    weak var window: AnyObject?
    var owners: [UUID: Bool] = [:]
    init(window: AnyObject) { self.window = window }
  }
  private var entries: [ObjectIdentifier: Entry] = [:]
  private let center: NotificationCenter

  init(notificationCenter: NotificationCenter = .default) {
    center = notificationCenter
    super.init()
    center.addObserver(self, selector: #selector(windowWillClose(_:)),
      name: NSWindow.willCloseNotification, object: nil)
  }

  deinit { center.removeObserver(self) }

  func update(window: AnyObject, owner: UUID, isPracticePage: Bool) {
    let id = ObjectIdentifier(window)
    let entry = entries[id].flatMap { $0.window === window ? $0 : nil } ?? Entry(window: window)
    guard entry.owners[owner] != isPracticePage else { return }
    entry.owners[owner] = isPracticePage
    entries[id] = entry
    center.post(name: Self.didChange, object: self)
  }

  func remove(window: AnyObject, owner: UUID) {
    let id = ObjectIdentifier(window)
    guard let entry = entries[id], entry.window === window,
      entry.owners.removeValue(forKey: owner) != nil else { return }
    if entry.owners.isEmpty { entries[id] = nil }
    center.post(name: Self.didChange, object: self)
  }

  /// A sheet inherits its host's page unless it is explicitly registered.
  /// The injectable parent relation lets ownership be tested without windows.
  func identifier(for window: AnyObject?, parent: (AnyObject) -> AnyObject? = { _ in nil }) -> UUID? {
    entries = entries.filter { $0.value.window != nil }
    var candidate = window
    var visited: Set<ObjectIdentifier> = []
    while let current = candidate {
      let id = ObjectIdentifier(current)
      guard visited.insert(id).inserted else { return nil }
      if let entry = entries[id], entry.window === current {
        return entry.owners.values.contains(true) ? entry.identifier : nil
      }
      candidate = parent(current)
    }
    return nil
  }

  var currentIdentifier: UUID? {
    identifier(for: NSApp.keyWindow, parent: { ($0 as? NSWindow)?.sheetParent })
  }

  @objc private func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as AnyObject?,
      entries.removeValue(forKey: ObjectIdentifier(window)) != nil else { return }
    center.post(name: Self.didChange, object: self)
  }
}

/// Synchronous AppKit attachment avoids a deferred registration publishing a
/// stale SwiftUI page after the view has been dismantled or reparented.
struct TypingMusicPracticeScopeBridge: NSViewRepresentable {
  let isPracticePage: Bool

  func makeNSView(context: Context) -> TypingMusicPracticeScopeView {
    let view = TypingMusicPracticeScopeView(registry: .shared)
    view.configure(isPracticePage: isPracticePage)
    return view
  }

  func updateNSView(_ view: TypingMusicPracticeScopeView, context: Context) {
    view.configure(isPracticePage: isPracticePage)
  }

  static func dismantleNSView(_ view: TypingMusicPracticeScopeView, coordinator: ()) {
    view.dismantle()
  }
}

@MainActor
final class TypingMusicPracticeScopeView: NSView {
  private let registry: TypingMusicPracticeScopeRegistry
  private let owner = UUID()
  private var isPracticePage = true
  private var participates = true

  init(registry: TypingMusicPracticeScopeRegistry) {
    self.registry = registry
    super.init(frame: .zero)
  }
  required init?(coder: NSCoder) { nil }

  // This invisible marker must never become a new mouse target.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func configure(isPracticePage: Bool) {
    self.isPracticePage = isPracticePage
    publish()
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if window !== newWindow, let window { registry.remove(window: window, owner: owner) }
    super.viewWillMove(toWindow: newWindow)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    publish()
  }

  func dismantle() {
    participates = false
    if let window { registry.remove(window: window, owner: owner) }
  }

  private func publish() {
    guard participates, let window else { return }
    registry.update(window: window, owner: owner, isPracticePage: isPracticePage)
  }
}
