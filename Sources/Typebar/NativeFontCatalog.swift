import AppKit
import Foundation
import SwiftUI

enum NativeFontCatalog {
  private static let comparisonLocale = Locale(identifier: "en_US_POSIX")
  private static let comparisonOptions: String.CompareOptions = [
    .caseInsensitive, .diacriticInsensitive, .widthInsensitive,
  ]

  private static func comparisonKey(_ value: String) -> String {
    value
      .folding(options: comparisonOptions, locale: comparisonLocale)
      .lowercased(with: comparisonLocale)
  }

  static func normalizedFamilies(_ families: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []

    for family in families {
      let normalized = family.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalized.isEmpty else { continue }
      let identity = comparisonKey(normalized)
      guard seen.insert(identity).inserted else { continue }
      result.append(normalized)
    }

    return result.sorted { comparisonKey($0) < comparisonKey($1) }
  }

  static func filteredFamilies(_ families: [String], query: String) -> [String] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return families }
    let queryKey = comparisonKey(query)
    return families.filter { comparisonKey($0).contains(queryKey) }
  }

  static func containsFamily(_ family: String, in families: [String]) -> Bool {
    let identity = comparisonKey(family.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !identity.isEmpty else { return false }
    return families.contains { comparisonKey($0) == identity }
  }

  /// Finds the visible family row for a stored name. A name can be either a
  /// family or a PostScript name, so resolving the latter prevents the picker
  /// from losing its checkmark after a user typed it directly.
  static func selectedFamily(
    for selection: String, in families: [String], resolveFamily: (String) -> String?
  ) -> String? {
    if let directFamily = NativePracticeFont.matchingFamily(for: selection, in: families) {
      return directFamily
    }
    guard let resolvedFamily = resolveFamily(selection) else { return nil }
    return NativePracticeFont.matchingFamily(for: resolvedFamily, in: families)
  }

  static func selectedFamily(for selection: String, in families: [String]) -> String? {
    selectedFamily(for: selection, in: families) { requestedName in
      guard
        let postScriptName = NativePracticeFont.postScriptName(for: requestedName),
        let font = NSFont(name: postScriptName, size: 1)
      else { return nil }
      return font.familyName
    }
  }

  @MainActor
  static var installedFamilies: [String] {
    normalizedFamilies(NSFontManager.shared.availableFontFamilies)
  }
}

struct NativeFontFamilyPicker: View {
  @Binding var selection: String
  let families: [String]

  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  private var filteredFamilies: [String] {
    NativeFontCatalog.filteredFamilies(families, query: query)
  }

  private var selectedFamily: String? {
    NativeFontCatalog.selectedFamily(for: selection, in: families)
  }

  private func previewFont(for family: String) -> Font {
    guard let font = NativePracticeFont.nsFont(named: family, size: 15) else {
      return .system(size: 15)
    }
    return Font(font)
  }

  private func previewLabel(for family: String) -> some View {
    let font = previewFont(for: family)
    return VStack(alignment: .leading, spacing: 2) {
      Text(family)
        .font(font)
        .foregroundStyle(.primary)
      Text("Aa 123 · 字体预览")
        .font(font)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if filteredFamilies.isEmpty {
          ContentUnavailableView.search(text: query)
        } else {
          List(filteredFamilies, id: \.self) { family in
            Button {
              selection = family
              dismiss()
            } label: {
              HStack {
                previewLabel(for: family)
                Spacer()
                if family == selectedFamily {
                  Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
      .navigationTitle("选择本机字体")
      .searchable(text: $query, prompt: "搜索字体家族")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        if !selection.isEmpty {
          ToolbarItem(placement: .primaryAction) {
            Button("使用系统设计") {
              selection = ""
              dismiss()
            }
          }
        }
      }
    }
    .frame(minWidth: 420, minHeight: 480)
  }
}
