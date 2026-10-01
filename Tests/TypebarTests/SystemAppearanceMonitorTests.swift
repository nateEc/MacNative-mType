import AppKit
import Observation
import SwiftUI
import XCTest
@testable import Typebar

@MainActor
final class SystemAppearanceMonitorTests: XCTestCase {
  private func withApplicationAppearance(
    _ name: NSAppearance.Name, body: (NSApplication) throws -> Void
  ) rethrows {
    let application = NSApplication.shared
    let previous = application.appearance
    defer { application.appearance = previous }
    application.appearance = NSAppearance(named: name)
    try body(application)
  }

  private func waitForChange(_ monitor: SystemAppearanceMonitor, change: () -> Void) {
    let changed = expectation(description: "Application appearance observation")
    withObservationTracking { _ = monitor.colorScheme } onChange: { changed.fulfill() }
    change()
    wait(for: [changed], timeout: 1)
  }

  func testStandardAndHighContrastAppearancesResolveByBestMatch() throws {
    for name in [NSAppearance.Name.aqua, .accessibilityHighContrastAqua] {
      XCTAssertEqual(SystemAppearancePolicy.colorScheme(for: try XCTUnwrap(NSAppearance(named: name))), .light)
    }
    for name in [NSAppearance.Name.darkAqua, .accessibilityHighContrastDarkAqua] {
      XCTAssertEqual(SystemAppearancePolicy.colorScheme(for: try XCTUnwrap(NSAppearance(named: name))), .dark)
    }
  }

  func testInitialSystemSourceIsIndependentOfAnOppositeWindowAppearance() {
    withApplicationAppearance(.darkAqua) { application in
      let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
      window.appearance = NSAppearance(named: .aqua)
      let monitor = SystemAppearanceMonitor(application: application)
      XCTAssertEqual(SystemAppearancePolicy.colorScheme(for: window.effectiveAppearance), .light)
      XCTAssertEqual(monitor.colorScheme, .dark)
    }
  }

  func testApplicationAppearanceChangesUpdateTheObservableSource() {
    withApplicationAppearance(.darkAqua) { application in
      let monitor = SystemAppearanceMonitor(application: application)
      waitForChange(monitor) { application.appearance = NSAppearance(named: .aqua) }
      XCTAssertEqual(monitor.colorScheme, .light)
      waitForChange(monitor) { application.appearance = NSAppearance(named: .darkAqua) }
      XCTAssertEqual(monitor.colorScheme, .dark)
    }
  }

  func testPreviewWindowDoesNotMoveSystemFollowingCheckmarkOrWriteSettings() {
    withApplicationAppearance(.darkAqua) { application in
      let name = "TypebarTests.system-appearance.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: name)!
      defer { defaults.removePersistentDomain(forName: name) }
      let settings = AppSettings(defaults: defaults)
      settings.systemLightTheme = .paper
      settings.systemDarkTheme = .midnight
      settings.followSystemTheme = true
      let saved = defaults.dictionaryRepresentation() as NSDictionary
      let monitor = SystemAppearanceMonitor(application: application)
      let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
      window.appearance = NSAppearance(named: .aqua)
      let preview = ThemePreviewPresentation(
        settings: settings, systemColorScheme: monitor.colorScheme, previewTarget: .builtIn(.paper))
      XCTAssertEqual(preview.target, .builtIn(.paper))
      XCTAssertEqual(preview.preferredColorScheme, .light)
      XCTAssertEqual(SystemAppearancePolicy.colorScheme(for: window.effectiveAppearance), .light)
      XCTAssertEqual(settings.currentThemeQuickPickerTarget(for: monitor.colorScheme), .builtIn(.midnight))
      XCTAssertEqual(settings.currentBuiltInThemeForFavoriteCommand(for: monitor.colorScheme), .midnight)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, saved)
    }
  }

  func testSystemChangeDuringForcedWindowPreviewIsUsedWhenCancelling() {
    withApplicationAppearance(.darkAqua) { application in
      let name = "TypebarTests.system-appearance-cancel.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: name)!
      defer { defaults.removePersistentDomain(forName: name) }
      let settings = AppSettings(defaults: defaults)
      settings.systemLightTheme = .paper
      settings.systemDarkTheme = .grove
      settings.followSystemTheme = true
      let monitor = SystemAppearanceMonitor(application: application)
      let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
      window.appearance = NSAppearance(named: .darkAqua)
      waitForChange(monitor) { application.appearance = NSAppearance(named: .aqua) }
      XCTAssertEqual(SystemAppearancePolicy.colorScheme(for: window.effectiveAppearance), .dark)
      let preview = ThemePreviewPresentation(
        settings: settings, systemColorScheme: monitor.colorScheme, previewTarget: .builtIn(.midnight))
      XCTAssertEqual(preview.preferredColorScheme, .dark)
      let restored = ThemePreviewPresentation(
        settings: settings, systemColorScheme: monitor.colorScheme, previewTarget: nil)
      XCTAssertEqual(restored.target, .builtIn(.paper))
      XCTAssertNil(restored.preferredColorScheme)
      XCTAssertTrue(settings.followSystemTheme)
    }
  }

  func testObservationDoesNotRetainTheMonitorAfterItsOwnerReleasesIt() {
    withApplicationAppearance(.darkAqua) { application in
      var monitor: SystemAppearanceMonitor? = .init(application: application)
      weak var released: SystemAppearanceMonitor?
      released = monitor
      XCTAssertNotNil(released)
      monitor = nil
      XCTAssertNil(released)
      application.appearance = NSAppearance(named: .aqua)
    }
  }

  func testAutomaticRandomPoolUsesSystemAppearanceInsteadOfTheManualTheme() {
    withApplicationAppearance(.darkAqua) { application in
      let name = "TypebarTests.system-appearance-random.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: name)!
      defer { defaults.removePersistentDomain(forName: name) }
      let settings = AppSettings(defaults: defaults)
      settings.selectBuiltInTheme(.paper)
      settings.randomThemeMode = .auto
      let saved = defaults.dictionaryRepresentation() as NSDictionary
      let monitor = SystemAppearanceMonitor(application: application)
      settings.randomizeTheme(for: monitor.colorScheme, using: 0)
      XCTAssertEqual(settings.resolvedTheme(for: monitor.colorScheme).colorScheme, .dark)
      XCTAssertEqual(settings.theme, .paper)
      XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, saved)
    }
  }
}
