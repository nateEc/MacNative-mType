import AppKit
import XCTest
@testable import Typebar

@MainActor
final class MusicPracticeScopeTests: XCTestCase {
  func testOnlyExplicitlyMarkedPracticeWindowsHaveStableScope() throws {
    let registry = TypingMusicPracticeScopeRegistry(notificationCenter: NotificationCenter())
    let practice = NSObject(), settings = NSObject(), owner = UUID()
    XCTAssertNil(registry.identifier(for: nil))
    XCTAssertNil(registry.identifier(for: practice))
    registry.update(window: practice, owner: owner, isPracticePage: true)
    let id = try XCTUnwrap(registry.identifier(for: practice))
    registry.update(window: practice, owner: owner, isPracticePage: true)
    XCTAssertEqual(registry.identifier(for: practice), id)
    XCTAssertNil(registry.identifier(for: settings))
    registry.update(window: practice, owner: owner, isPracticePage: false)
    XCTAssertNil(registry.identifier(for: practice))
    registry.update(window: practice, owner: owner, isPracticePage: true)
    XCTAssertEqual(registry.identifier(for: practice), id)
  }

  func testRetiredOwnerCannotUnregisterAnotherOwnerOrAnotherPracticeWindow() throws {
    let registry = TypingMusicPracticeScopeRegistry(notificationCenter: NotificationCenter())
    let first = NSObject(), second = NSObject(), oldOwner = UUID(), newOwner = UUID()
    registry.update(window: first, owner: oldOwner, isPracticePage: true)
    registry.update(window: first, owner: newOwner, isPracticePage: true)
    registry.update(window: second, owner: oldOwner, isPracticePage: true)
    let firstID = try XCTUnwrap(registry.identifier(for: first))
    let secondID = try XCTUnwrap(registry.identifier(for: second))
    XCTAssertNotEqual(firstID, secondID)
    registry.remove(window: first, owner: oldOwner)
    registry.remove(window: first, owner: oldOwner)
    XCTAssertEqual(registry.identifier(for: first), firstID)
    registry.remove(window: first, owner: newOwner)
    XCTAssertNil(registry.identifier(for: first))
    XCTAssertEqual(registry.identifier(for: second), secondID)
    registry.update(window: first, owner: oldOwner, isPracticePage: true)
    XCTAssertNotEqual(registry.identifier(for: first), firstID)
  }

  func testPracticeSheetsInheritTheHostUnlessTheyExplicitlyRepresentAnotherPage() throws {
    let registry = TypingMusicPracticeScopeRegistry(notificationCenter: NotificationCenter())
    let practice = NSObject(), sheet = NSObject(), nested = NSObject(), owner = UUID()
    registry.update(window: practice, owner: owner, isPracticePage: true)
    let id = try XCTUnwrap(registry.identifier(for: practice))
    let parent: (AnyObject) -> AnyObject? = { object in
      if object === nested { return sheet }
      if object === sheet { return practice }
      return nil
    }
    XCTAssertEqual(registry.identifier(for: sheet, parent: parent), id)
    XCTAssertEqual(registry.identifier(for: nested, parent: parent), id)
    registry.update(window: sheet, owner: owner, isPracticePage: false)
    XCTAssertNil(registry.identifier(for: nested, parent: parent))
    registry.remove(window: sheet, owner: owner)
    XCTAssertEqual(registry.identifier(for: nested, parent: parent), id)
    registry.update(window: practice, owner: owner, isPracticePage: false)
    XCTAssertNil(registry.identifier(for: sheet, parent: parent))
  }

  func testCloseNotificationRetiresEveryOwnerButUnrelatedCloseDoesNotRetirePractice() {
    let center = NotificationCenter()
    let observed = TypingMusicPracticeScopeRegistry(notificationCenter: center)
    let practice = NSObject(), unrelated = NSObject()
    observed.update(window: practice, owner: UUID(), isPracticePage: true)
    observed.update(window: practice, owner: UUID(), isPracticePage: true)
    let id = observed.identifier(for: practice)
    center.post(name: NSWindow.willCloseNotification, object: unrelated)
    center.post(name: NSWindow.willCloseNotification, object: nil)
    XCTAssertEqual(observed.identifier(for: practice), id)
    center.post(name: NSWindow.willCloseNotification, object: practice)
    XCTAssertNil(observed.identifier(for: practice))
  }

  func testRegistryDoesNotRetainWindowsOrItselfThroughNotificationObservation() throws {
    let center = NotificationCenter()
    var registry: TypingMusicPracticeScopeRegistry? = .init(notificationCenter: center)
    weak var weakRegistry = registry
    var window: NSObject? = NSObject()
    weak var weakWindow = window
    registry?.update(window: try XCTUnwrap(window), owner: UUID(), isPracticePage: true)
    window = nil
    XCTAssertNil(weakWindow)
    registry = nil
    XCTAssertNil(weakRegistry)
    center.post(name: NSWindow.willCloseNotification, object: NSObject())
  }

  func testUnknownParentCyclesDoNotTurnIntoPracticeOrLoopIndefinitely() {
    let registry = TypingMusicPracticeScopeRegistry(notificationCenter: NotificationCenter())
    let first = NSObject(), second = NSObject()
    XCTAssertNil(registry.identifier(for: first, parent: { $0 === first ? second : first }))
  }

  func testMetadataViewIsNonInteractiveEvenWhenSizedAndDismantled() {
    let registry = TypingMusicPracticeScopeRegistry(notificationCenter: NotificationCenter())
    let view = TypingMusicPracticeScopeView(registry: registry)
    view.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
    XCTAssertNil(view.hitTest(NSPoint(x: 10, y: 10)))
    view.configure(isPracticePage: false)
    view.dismantle()
    view.configure(isPracticePage: true)
    XCTAssertNil(view.window)
    XCTAssertNil(view.hitTest(NSPoint(x: 10, y: 10)))
  }
}
