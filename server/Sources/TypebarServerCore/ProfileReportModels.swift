import Foundation
import Vapor

/// A deliberately small, product-specific set of reasons for a report about a
/// public Typebar profile. Reports are held privately for later review.
public enum ProfileReportReason: String, CaseIterable, Content, Equatable {
    case misleadingProfile
    case abusiveName
    case suspiciousResults
    case other
}

public struct ProfileReportRequest: Content, Equatable {
    public let profileID: UUID
    public let reason: ProfileReportReason
    public let note: String?
}

public struct ProfileReportResponse: Content, Equatable {
    public let id: UUID
    public let submittedAt: Date
}

/// Review state is intentionally administrative metadata only. It never
/// changes the reported account or notifies either party.
public enum ProfileReportModerationStatus: String, CaseIterable, Content, Equatable {
    case open
    case resolved
    case dismissed
}

/// Deployment-only review material. The reported profile is already public;
/// reporter identity and account contact data deliberately remain private.
public struct ModerationProfileReportResponse: Content, Equatable {
    public let id: UUID
    public let profile: PublicProfileResponse
    public let reason: ProfileReportReason
    public let note: String?
    public let status: ProfileReportModerationStatus
    public let submittedAt: Date
}

public struct ModerationProfileReportListResponse: Content, Equatable {
    public let reports: [ModerationProfileReportResponse]
}

public struct ModerationProfileReportListQuery: Content, Equatable {
    public let status: ProfileReportModerationStatus?
    public let limit: Int?
}

public struct ProfileReportModerationRequest: Content, Equatable {
    public let status: ProfileReportModerationStatus
}
