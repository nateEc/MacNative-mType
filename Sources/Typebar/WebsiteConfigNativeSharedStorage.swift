import Foundation

struct WebsiteNativeSharedStorageError: LocalizedError {
  let recovered: Bool
  var errorDescription: String? {
    recovered ? "已恢复上次中断的配置，请重新应用此链接。"
      : "配置转换尚未完成，已保存的部分已保留。请重新打开配置面板继续恢复。"
  }
}

/// Conversion writes are distinct from the URL receiver's nosave setters.
/// Preserve an existing complete saved profile; only a missing profile adopts
/// the native baseline. Copy the current native buffer through the same
/// durable two-store journal used by explicit archive recovery.
@MainActor enum WebsiteConfigNativeSharedStorage {
  struct Saved {
    let draft: WebsiteConfigNativeDraft
    let revision: WebsiteConfigFileRegister.Revision
  }
  static func adopt(_ baseline: WebsiteConfigNativeBaseline.Capture, settings: AppSettings,
    register: WebsiteConfigFileRegister, pointsPerRem: Double, whileCurrent: @MainActor () -> Bool) throws -> Saved {
    let store = settings.websiteCustomArchiveStore
    let snapshot = try register.read()
    if snapshot.state == .unavailable {
      guard whileCurrent() else { throw WebsiteConfigCommitCoordinatorError.stale }
      let recovered: Bool
      do { recovered = try register.recoverArchiveRestore(customStore: store) }
      catch { throw WebsiteNativeSharedStorageError(recovered: false) }
      if recovered {
        settings.websiteArchiveCustomStateWasRestored()
        throw WebsiteNativeSharedStorageError(recovered: true)
      }
      throw WebsiteConfigCommitCoordinatorError.unavailable
    }
    guard let initialRevision = snapshot.revision, let custom = baseline.scope.websiteCustomText,
      let customData = WebsiteCustomTextStateStore.encodeDocument(custom) else { throw WebsiteConfigCommitCoordinatorError.unavailable }
    let savedRuntime: [String: WebsiteConfigValue], memory: WebsiteConfigLazyModeMemory
    switch snapshot.state {
    case .available(let existing):
      guard snapshot.lazyMemory == baseline.lazyMemory else { throw WebsiteConfigNativeBaseline.Failure.unrepresentable("lazyModeMemory") }
      savedRuntime = existing; memory = snapshot.lazyMemory
    case .missing: savedRuntime = baseline.runtime; memory = baseline.lazyMemory
    case .unavailable: throw WebsiteConfigCommitCoordinatorError.unavailable
    }
    let draft = try WebsiteConfigNativeDraft(received: .init(state: .init(runtime: savedRuntime,
      settingsStore: savedRuntime, custom: custom, active: false, lazyMemory: memory)), pointsPerRem: pointsPerRem)
    let profile = try WebsiteProfileArchive(runtime: savedRuntime, lazyMemory: memory,
      customTextData: customData, fallbackCustomTextData: store.fallbackRecordForArchive())
    let plan = try register.prepareArchiveRestore(profile, customStore: store)
    guard whileCurrent(), try register.read().revision == initialRevision else { throw WebsiteConfigCommitCoordinatorError.stale }
    let revision: WebsiteConfigFileRegister.Revision
    if plan.isUnchanged { revision = initialRevision }
    else {
      do { revision = try register.restoreArchive(plan, customStore: store) }
      catch { throw WebsiteNativeSharedStorageError(recovered: false) }
      // The journal already read back the bytes. Notify only the independent
      // website cache; the native fallback and archive UI owner did not change.
      guard settings.saveWebsiteCustomTextState(custom) else { throw WebsiteNativeSharedStorageError(recovered: false) }
    }
    guard whileCurrent() else { throw WebsiteConfigCommitCoordinatorError.stale }
    return .init(draft: draft, revision: revision)
  }
}
