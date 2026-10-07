import AppKit
import SwiftUI

enum ResultHistoryFilterChoice {
  @MainActor static func binding<Value: Hashable>(
    for value: Value, selection: Binding<Set<Value>>, allowsExclusiveSelection: Bool = true,
    modifierFlags: @escaping @MainActor () -> NSEvent.ModifierFlags = {
      NSApp?.currentEvent?.modifierFlags ?? []
    }
  ) -> Binding<Bool> {
    Binding(get: { selection.wrappedValue.contains(value) }, set: { selected in
      // Shift always keeps the activated choice on, including an already
      // checked checkbox whose proposed next value is false.
      if allowsExclusiveSelection && modifierFlags().contains(.shift) {
        selection.wrappedValue = [value]
      } else if selected { selection.wrappedValue.insert(value) }
      else { selection.wrappedValue.remove(value) }
    })
  }
}
