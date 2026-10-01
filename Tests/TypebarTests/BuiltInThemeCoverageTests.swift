import AppKit
import SwiftUI
import XCTest
@testable import Typebar

final class BuiltInThemeCoverageTests: XCTestCase {
  func testEighteenNewMaterialThemesAreSelectableReadableAndDistinctFromTheExistingCatalog() throws {
    let names = [
      "blue_dolphin", "earthsong", "fleuriste", "froyo", "fruit_chew", "hedge",
      "lilac_mist", "lime", "luna", "matcha_moccha", "menthol", "mizu", "nautilus",
      "peach_blossom", "peaches", "tangerine", "tiramisu", "terra",
    ]
    let variants = names.compactMap(AppTheme.init(rawValue:))
    XCTAssertEqual(variants.count, names.count)
    XCTAssertEqual(variants.filter { $0.colorScheme == .light }.count, 9)
    XCTAssertEqual(variants.filter { $0.colorScheme == .dark }.count, 9)
    for theme in variants {
      XCTAssertEqual(try JSONDecoder().decode(AppTheme.self, from: JSONEncoder().encode(theme)), theme)
      XCTAssertTrue(theme.displayName.hasSuffix(" · Typebar"))
      for surface in [theme.background, theme.panel] {
        let resolved = theme.resolvedTheme
        XCTAssertGreaterThanOrEqual(contrast(resolved.text, surface), 4.5, theme.rawValue)
        XCTAssertGreaterThanOrEqual(contrast(resolved.secondaryText, surface), 4.5, theme.rawValue)
        for mark in [resolved.accent, resolved.caret, resolved.error, resolved.extraInput,
          resolved.colorfulError, resolved.colorfulExtraInput] {
          XCTAssertGreaterThanOrEqual(contrast(mark, surface), 3.0, theme.rawValue)
        }
      }
      for other in AppTheme.allCases where other != theme {
        XCTAssertNotEqual(ThemeColor(color: theme.background), ThemeColor(color: other.background),
          "Duplicate background: \(theme.rawValue), \(other.rawValue)")
      }
    }
  }

  func testTwelveFurtherOriginalThemesAreSelectableReadableAndDistinct() throws {
    let names = [
      "blueberry_dark", "blueberry_light", "cafe", "cheesecake", "creamsicle", "fire",
      "iceberg_light", "mountain", "mint", "nebula", "olive", "strawberry",
    ]
    let variants = names.compactMap(AppTheme.init(rawValue:))
    XCTAssertEqual(variants.count, names.count)
    XCTAssertEqual(variants.filter { $0.colorScheme == .light }.count, 6)
    XCTAssertEqual(variants.filter { $0.colorScheme == .dark }.count, 6)
    for theme in variants {
      XCTAssertEqual(try JSONDecoder().decode(AppTheme.self, from: JSONEncoder().encode(theme)), theme)
      XCTAssertFalse(theme.displayName.isEmpty)
      for surface in [theme.background, theme.panel] {
        XCTAssertGreaterThanOrEqual(contrast(theme.resolvedTheme.text, surface), 4.5, theme.rawValue)
        XCTAssertGreaterThanOrEqual(
          contrast(theme.resolvedTheme.secondaryText, surface), 4.5, theme.rawValue)
        XCTAssertGreaterThanOrEqual(contrast(theme.accent, surface), 3.0, theme.rawValue)
      }
    }
    for left in variants.indices {
      for right in variants.indices where left < right {
        XCTAssertNotEqual(
          ThemeColor(color: variants[left].background),
          ThemeColor(color: variants[right].background))
      }
    }
  }

  func testOriginalThreeThemeIDsAndColorsRemainCompatibleWithSavedSettings() throws {
    let legacy: [(AppTheme, [Double], [Double], [Double], ColorScheme)] = [
      (.paper, [0.96, 0.95, 0.91], [0.88, 0.86, 0.80], [0.66, 0.28, 0.14], .light),
      (.midnight, [0.07, 0.09, 0.13], [0.13, 0.16, 0.22], [0.38, 0.73, 1.00], .dark),
      (.grove, [0.09, 0.16, 0.13], [0.14, 0.25, 0.19], [0.48, 0.78, 0.52], .dark),
    ]
    for (theme, background, panel, accent, scheme) in legacy {
      let stored = try JSONEncoder().encode(theme)
      XCTAssertEqual(String(decoding: stored, as: UTF8.self), "\"\(theme.rawValue)\"")
      XCTAssertEqual(try JSONDecoder().decode(AppTheme.self, from: stored), theme)
      XCTAssertEqual(theme.colorScheme, scheme)
      assertRGB(theme.background, matches: background)
      assertRGB(theme.panel, matches: panel)
      assertRGB(theme.accent, matches: accent)
    }
  }

  func testFurtherOriginalThemesHaveReadableDistinctPalettesAndStableIDs() throws {
    let names = ["breeze", "camping", "cherry_blossom", "desert_oasis", "grape", "moonlight"]
    let variants = names.compactMap(AppTheme.init(rawValue:))
    XCTAssertEqual(variants.count, names.count)
    XCTAssertEqual(variants.filter { $0.colorScheme == .light }.count, 3)
    XCTAssertEqual(variants.filter { $0.colorScheme == .dark }.count, 3)
    for theme in variants {
      XCTAssertEqual(try JSONDecoder().decode(AppTheme.self, from: JSONEncoder().encode(theme)), theme)
      for surface in [theme.background, theme.panel] {
        XCTAssertGreaterThanOrEqual(contrast(theme.resolvedTheme.text, surface), 4.5, theme.rawValue)
        XCTAssertGreaterThanOrEqual(
          contrast(theme.resolvedTheme.secondaryText, surface), 4.5, theme.rawValue)
        XCTAssertGreaterThanOrEqual(contrast(theme.accent, surface), 3.0, theme.rawValue)
      }
    }
    for left in variants.indices {
      for right in variants.indices where left < right {
        XCTAssertNotEqual(
          ThemeColor(color: variants[left].background),
          ThemeColor(color: variants[right].background))
      }
    }
  }

  func testNextOriginalThemeSetIsSelectableReadableAndBalancedAcrossAppearances() throws {
    let names = [
      "alpine", "botanical", "copper", "honey", "iceberg_dark", "lavender", "sunset",
      "watermelon",
    ]
    let variants = names.compactMap(AppTheme.init(rawValue:))
    XCTAssertEqual(variants.count, names.count)
    XCTAssertEqual(variants.filter { $0.colorScheme == .light }.count, 4)
    XCTAssertEqual(variants.filter { $0.colorScheme == .dark }.count, 4)

    for theme in variants {
      XCTAssertEqual(try JSONDecoder().decode(AppTheme.self, from: JSONEncoder().encode(theme)), theme)
      for surface in [theme.background, theme.panel] {
        XCTAssertGreaterThanOrEqual(contrast(theme.resolvedTheme.text, surface), 4.5, theme.rawValue)
        XCTAssertGreaterThanOrEqual(
          contrast(theme.resolvedTheme.secondaryText, surface), 4.5, theme.rawValue)
        XCTAssertGreaterThanOrEqual(contrast(theme.accent, surface), 3.0, theme.rawValue)
      }
    }
    for left in variants.indices {
      for right in variants.indices where left < right {
        XCTAssertNotEqual(
          ThemeColor(color: variants[left].background),
          ThemeColor(color: variants[right].background))
      }
    }
  }

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

  private func assertRGB(_ color: Color, matches channels: [Double], file: StaticString = #filePath,
                         line: UInt = #line) {
    let actual = ThemeColor(color: color)
    XCTAssertEqual(actual.red, channels[0], accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.green, channels[1], accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(actual.blue, channels[2], accuracy: 0.001, file: file, line: line)
  }

  private func luminance(_ color: ThemeColor) -> Double {
    func linear(_ component: Double) -> Double {
      component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.red) + 0.7152 * linear(color.green)
      + 0.0722 * linear(color.blue)
  }
}
