import AppKit
import SwiftUI

struct PracticeLanguagePicker: View {
  let languages: [TypingLanguage]
  @Binding var selection: TypingLanguage

  var body: some View {
    HStack {
      Text("语言")
      PracticeLanguageMenu(languages: languages, selection: $selection)
    }
  }
}

private struct PracticeLanguageMenu: NSViewRepresentable {
  let languages: [TypingLanguage]
  @Binding var selection: TypingLanguage
  @Environment(\.isEnabled) private var isEnabled

  func makeNSView(context: Context) -> PracticeLanguagePopUp { PracticeLanguagePopUp(frame: .zero, pullsDown: false) }
  func updateNSView(_ view: PracticeLanguagePopUp, context: Context) {
    view.configure(languages: languages, selection: selection, enabled: isEnabled) { [weak view] language in
      selection = language
      // The parent may reject a locked configuration change without updating.
      view?.synchronizeSelection(selection)
    }
  }
  static func dismantleNSView(_ view: PracticeLanguagePopUp, coordinator: ()) { view.stop() }
}

final class PracticeLanguagePopUp: NSPopUpButton {
  private var languages: [TypingLanguage] = []
  private var onSelection: ((TypingLanguage) -> Void)?

  func configure(languages: [TypingLanguage], selection: TypingLanguage, enabled: Bool,
    onSelection: @escaping (TypingLanguage) -> Void) {
    self.onSelection = onSelection
    // Ordinary typing changes the session, not the available language menu.
    if self.languages != languages {
      self.languages = languages
      removeAllItems()
      for language in languages {
        addItem(withTitle: language.displayName)
        lastItem?.representedObject = language.rawValue
      }
    }
    autoenablesItems = false
    isEnabled = enabled
    target = self
    action = #selector(changed)
    setAccessibilityLabel("语言")
    synchronizeSelection(selection)
  }

  func synchronizeSelection(_ selection: TypingLanguage) {
    if let index = languages.firstIndex(of: selection) {
      if indexOfSelectedItem != index { selectItem(at: index) }
    } else { select(nil) }
  }

  func stop() {
    onSelection = nil
    target = nil
    action = nil
  }

  override func viewWillMove(toSuperview newSuperview: NSView?) {
    if newSuperview == nil { stop() }
    super.viewWillMove(toSuperview: newSuperview)
  }

  @objc private func changed() {
    guard isEnabled, let raw = selectedItem?.representedObject as? String,
      let language = TypingLanguage(rawValue: raw), languages.contains(language) else { return }
    onSelection?(language)
  }
}
