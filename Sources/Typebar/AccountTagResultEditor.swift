import Foundation

/// The picker display is separate from its deliberately empty initial draft.
struct AccountTagAssociationPresentation: Equatable {
  let displayedIDs: [UUID]
  let summary: String
  let emptyMessage: String?

  init(ids: [UUID]?, knownIDs: Set<UUID>) {
    displayedIDs = (ids ?? []).filter { knownIDs.contains($0) }
    summary = ids == nil ? "关联未知" : "\(Set(displayedIDs).count) 个"
    emptyMessage = ids == nil ? "账户标签关联未知" : displayedIDs.isEmpty ? "无账户标签" : nil
  }
}

/// An ephemeral editor, never an immutable completion receipt or posting selection.
struct AccountTagResultEditDraft: Equatable {
  let scope: ResultPublicationScope
  let revision: UInt64
  let resultID: UUID
  let originalIDs: [UUID]
  let knownIDs: Set<UUID>
  private(set) var selectedIDs: [UUID]

  init(scope: ResultPublicationScope, revision: UInt64, result: RemoteAccountResult, knownIDs: Set<UUID>) {
    self.scope = scope; self.revision = revision; resultID = result.id
    originalIDs = result.accountTagIDs ?? []; self.knownIDs = knownIDs
    selectedIDs = originalIDs.filter { knownIDs.contains($0) }
  }
  var isChanged: Bool { Set(originalIDs) != Set(selectedIDs) }
  mutating func set(_ id: UUID, enabled: Bool) {
    guard knownIDs.contains(id) else { return }
    if enabled, !selectedIDs.contains(id) { selectedIDs.append(id) }
    if !enabled { selectedIDs.removeAll { $0 == id } }
  }
}

enum AccountTagResultEditDisposition: Equatable { case unchanged, saved }

/// Result-page display order and crowns are not the most recent server award list.
struct AccountTagResultEditFeedback: Equatable {
  private(set) var displayedIDs: [UUID]
  private(set) var crownedIDs: Set<UUID>
  init(ids: [UUID], crownedIDs: Set<UUID> = []) {
    displayedIDs = ids; self.crownedIDs = crownedIDs.intersection(ids)
  }
  mutating func apply(ids: [UUID], awards: [UUID]) {
    displayedIDs.removeAll { !ids.contains($0) }
    crownedIDs.formIntersection(displayedIDs)
    for id in ids where !displayedIDs.contains(id) {
      displayedIDs.append(id)
      if awards.contains(id) { crownedIDs.insert(id) }
    }
  }
  mutating func retain(knownIDs: Set<UUID>) {
    displayedIDs.removeAll { !knownIDs.contains($0) }; crownedIDs.formIntersection(displayedIDs)
  }
}

extension AccountSession {
  func accountTagResultEditDraft(id: UUID) throws -> AccountTagResultEditDraft {
    guard !isEditingAccountTags, let scope = resultPublicationScope,
      let result = editableAccountTagResult(id: id) else { throw RemoteAccountError.accountScopeChanged }
    return .init(scope: scope, revision: accountTagRevision, result: result, knownIDs: Set(accountTags.map(\.id)))
  }
  func validateAccountTagResultEditDraft(_ draft: AccountTagResultEditDraft) throws {
    guard resultPublicationScope == draft.scope, accountTagRevision == draft.revision,
      !isEditingAccountTags, let current = editableAccountTagResult(id: draft.resultID),
      Set(current.accountTagIDs ?? []) == Set(draft.originalIDs),
      Set(accountTags.map(\.id)) == draft.knownIDs else { throw RemoteAccountError.accountScopeChanged }
    try RemoteAccountTagPolicy.validateIDs(draft.selectedIDs)
  }
  func saveAccountTagResultEdit(_ draft: AccountTagResultEditDraft,
    fromResultPage: Bool = false) async throws -> AccountTagResultEditDisposition {
    try validateAccountTagResultEditDraft(draft)
    guard draft.isChanged else { return .unchanged }
    try await updateRemoteAccountResultTagIDs(id: draft.resultID, tagIDs: draft.selectedIDs,
      expectedRevision: draft.revision, fromResultPage: fromResultPage)
    return .saved
  }
}
