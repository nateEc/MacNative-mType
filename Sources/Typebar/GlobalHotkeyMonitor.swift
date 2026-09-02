import AppKit
import ApplicationServices
import Observation

enum GlobalHotkeyStatus: Equatable {
    case disabled
    case active
    case permissionRequired

    var message: String {
        switch self {
        case .disabled: "已关闭"
        case .active: "已启用：按 ⌃⇧Space 可将 Typebar 带到前台。"
        case .permissionRequired: "需要在“系统设置 → 隐私与安全性 → 辅助功能”中允许 Typebar，才能监听全局热键。"
        }
    }
}

@MainActor
@Observable
final class GlobalHotkeyMonitor {
    @ObservationIgnored private var monitor: Any?
    private(set) var status: GlobalHotkeyStatus = .disabled

    func setEnabled(_ enabled: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard enabled else { status = .disabled; return }
        guard requestAccessibilityPermissionIfNeeded() else { status = .permissionRequired; return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.matches(keyCode: event.keyCode, modifiers: event.modifierFlags) else { return }
            Task { @MainActor in self?.activateTypebar() }
        }
        status = monitor == nil ? .permissionRequired : .active
    }

    static func matches(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        keyCode == 49 && modifiers.contains([.control, .shift])
    }

    private func requestAccessibilityPermissionIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        return false
    }

    private func activateTypebar() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
    }
}
