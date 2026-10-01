import AppKit
import SwiftUI
import XCTest
@testable import Typebar

final class BuiltInThemeCoverageTests: XCTestCase {
  func testOriginalNamedVariantsAreSelectableAndKeepReadableTypingColors() throws {
    let names = ["aurora", "beach", "diner"]
    let variants = names.compactMap(AppTheme.init(rawValue:))
    XCTAssertEqual(variants.count, names.count)

    for theme in variants {
      XCTAssertEqual(try JSONDecoder().decode(AppTheme.self, from: JSONEncoder().encode(theme)), theme)
      XCTAssertGreaterThanOrEqual(contrast(theme.resolvedTheme.text, theme.background), 4.5)
      XCTAssertGreaterThanOrEqual(contrast(theme.resolvedTheme.secondaryText, theme.background), 4.5)
      XCTAssertGreaterThanOrEqual(contrast(theme.accent, theme.background), 3.0)
    }
    for left in variants.indices {
      for right in variants.indices where left < right {
        XCTAssertNotEqual(
          ThemeColor(color: variants[left].background),
          ThemeColor(color: variants[right].background))
      }
    }
    XCTAssertEqual(variants.filter { $0.colorScheme == .light }.count, 1)
  }

  private func contrast(_ foreground: Color, _ background: Color) -> Double {
    let first = luminance(ThemeColor(color: foreground))
    let second = luminance(ThemeColor(color: background))
    return (max(first, second) + 0.05) / (min(first, second) + 0.05)
  }

  private func luminance(_ color: ThemeColor) -> Double {
    func linear(_ component: Double) -> Double {
      component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.red) + 0.7152 * linear(color.green)
      + 0.0722 * linear(color.blue)
  }
}
