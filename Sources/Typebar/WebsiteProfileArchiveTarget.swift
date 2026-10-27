import Foundation

struct WebsiteProfileArchiveImportFailure: LocalizedError {
  let underlying: Error
  var errorDescription: String? {
    "本机记录、普通设置和测试选择已导入，但完整配置尚未恢复完成。" + underlying.localizedDescription
  }
}

@MainActor enum WebsiteProfileArchiveTarget {
  @MainActor struct Plan {
    let register: WebsiteConfigFileRegister
    let prepared: WebsiteConfigFileRegister.ArchivePreparation
    let owner: PreferenceConfigurationSaveRouter.Lease?
    let wasRecovered: Bool
    func validate(settings: AppSettings) throws {
      guard settings.allowsRestartingConfigurationChange,
        settings.preferenceConfigurationSaves.captureLease() == owner else { throw WebsiteProfileArchiveError.conflict }
      guard prepared.isUnchanged || settings.preferenceConfigurationSaves.allowsWebsiteProfileArchiveRestore
      else { throw WebsiteConfigImportWorkflowError.activeAttempt }
      guard settings.preferenceConfigurationSaves.captureLease() == owner else { throw WebsiteProfileArchiveError.conflict }
      try register.validateArchiveRestore(prepared, customStore: settings.websiteCustomArchiveStore)
    }
    func commit(settings: AppSettings) throws -> Bool {
      try validate(settings: settings)
      if prepared.isUnchanged { return wasRecovered }
      let revision = try register.restoreArchive(prepared, customStore: settings.websiteCustomArchiveStore)
      settings.websiteProfileArchiveWasRestored(revision: revision)
      return true
    }
  }

  static func captureSaved(settings: AppSettings, applicationSupport: URL? = nil) throws -> WebsiteProfileArchive? {
    guard let directory = try WebsiteConfigStorageDirectory.existing(applicationSupport: applicationSupport) else { return nil }
    let register = WebsiteConfigFileRegister(directory: directory), snapshot = try register.read()
    switch snapshot.state {
    case .missing: return nil
    case .unavailable: throw WebsiteProfileArchiveError.unavailable
    case .available(let runtime):
      let custom = try settings.websiteCustomArchiveStore.recordForArchive()
      let fallback = try settings.websiteCustomArchiveStore.fallbackRecordForArchive()
      let result = try WebsiteProfileArchive(runtime: runtime, lazyMemory: snapshot.lazyMemory,
        customTextData: custom, fallbackCustomTextData: fallback)
      guard try register.read().revision == snapshot.revision,
        try settings.websiteCustomArchiveStore.recordForArchive() == custom,
        try settings.websiteCustomArchiveStore.fallbackRecordForArchive() == fallback else { throw WebsiteProfileArchiveError.conflict }
      return result
    }
  }

  static func prepare(_ profile: WebsiteProfileArchive, settings: AppSettings, applicationSupport: URL? = nil) throws -> Plan {
    guard settings.allowsRestartingConfigurationChange else { throw LocalArchiveImportError.noQuitConfigurationLocked }
    let directory = try WebsiteConfigStorageDirectory.prepare(applicationSupport: applicationSupport)
    let register = WebsiteConfigFileRegister(directory: directory)
    let owner = settings.preferenceConfigurationSaves.captureLease()
    var recovered = false
    // Only a retry of the same saved intent may complete its pending journal.
    if try register.read().state == .unavailable {
      guard settings.preferenceConfigurationSaves.allowsWebsiteProfileArchiveRestore else { throw WebsiteConfigImportWorkflowError.activeAttempt }
      recovered = try register.recoverArchiveRestore(customStore: settings.websiteCustomArchiveStore, expectedProfile: profile)
      if recovered, let revision = try register.read().revision { settings.websiteProfileArchiveWasRestored(revision: revision) }
    }
    guard settings.preferenceConfigurationSaves.captureLease() == owner else { throw WebsiteProfileArchiveError.conflict }
    let plan = try Plan(register: register, prepared: register.prepareArchiveRestore(profile, customStore: settings.websiteCustomArchiveStore),
      owner: owner, wasRecovered: recovered)
    try plan.validate(settings: settings)
    return plan
  }
}
