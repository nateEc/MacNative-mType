import AppKit

/// A display-only cache. Tokens never replace a publication or authorize a
/// save/input action, and never retain or read an imported font file.
@MainActor final class WebsiteConfigFontPreview {
  @MainActor struct Prepared {
    fileprivate let window: UUID
    fileprivate let resource: WebsiteConfigFontResource
    var owner: UUID { window }
    var font: NSFont { resource.renderingFont }
    var chAdvance: Double { resource.chAdvance }
    var candidates: [WebsiteConfigFontResource.Candidate] { resource.candidates }
  }
  private struct Key: Equatable {
    let owner: UUID
    let target: FontFamilyCommandTarget
    let size: UInt64
  }
  private var cached: (Key, Prepared)?
  func prepare(_ state: FontFamilyCommandPreviewState,
    publication: WebsiteConfigCommitCoordinator.Publication, owner: UUID) -> Prepared? {
    guard publication.owner == owner, publication.font != nil, let target = state.target else {
      cached = nil; return nil
    }
    let family: String
    switch target {
    case .systemDesign(let design): family = NativeSystemPracticeFont.identifier(for: design)
    case .knownIdentifier(let name):
      guard FontFamilyCommandCatalog.fixedKnownFontIDs.contains(name) else { cached = nil; return nil }
      family = name
    case .installedName(let name): family = name
    default: cached = nil; return nil
    }
    let size = publication.draft.keyboardTypography.fontSize
    let key = Key(owner: owner, target: target, size: size.bitPattern)
    if let cached, cached.0 == key { return cached.1 }
    guard let resource = try? WebsiteConfigFontResource.preview(family: family, size: size) else { cached = nil; return nil }
    let prepared = Prepared(window: owner, resource: resource)
    cached = (key, prepared)
    return prepared
  }
}
