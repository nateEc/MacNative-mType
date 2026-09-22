import Foundation
import Vapor

public struct QuoteSubmissionRequest: Content, Equatable {
    public let language: String
    public let text: String
    public let attribution: String?
    public let humanVerification: HumanVerificationProof?

    public init(
        language: String, text: String, attribution: String?,
        humanVerification: HumanVerificationProof? = nil
    ) {
        self.language = language
        self.text = text
        self.attribution = attribution
        self.humanVerification = humanVerification
    }
}

public struct QuoteSubmissionResponse: Content, Equatable {
    public let id: UUID
    public let status: String
    public let submittedAt: Date
}

public struct QuoteSubmissionListResponse: Content, Equatable {
    public let submissions: [QuoteSubmissionResponse]
}

public struct QuoteModerationRequest: Content, Equatable {
    public let status: String
    /// Optional replacement values are accepted only when approving. Omitted
    /// fields preserve the submitted content; an empty attribution removes it.
    public let text: String?
    public let attribution: String?

    public init(status: String, text: String? = nil, attribution: String? = nil) {
        self.status = status
        self.text = text
        self.attribution = attribution
    }
}

/// Deployment-only moderation data. It deliberately excludes reporter IDs and
/// any account contact details, so a reviewer only receives the context needed
/// to assess a submission.
public struct ModerationQuoteReportResponse: Content, Equatable {
    public let reason: QuoteReportReason
    public let note: String?
    public let submittedAt: Date
}

public struct ModerationQuoteResponse: Content, Equatable {
    public let id: UUID
    public let language: String
    public let text: String
    public let attribution: String?
    public let status: String
    public let submittedAt: Date
    public let reports: [ModerationQuoteReportResponse]
}

public struct ModerationQuoteListResponse: Content, Equatable {
    public let quotes: [ModerationQuoteResponse]
}

public struct ModerationQuoteListQuery: Content, Equatable {
    public let status: String?
    public let limit: Int?
}

public struct PublicQuoteResponse: Content, Equatable {
    public let id: UUID
    public let language: String
    public let text: String
    public let attribution: String?
    public let submittedAt: Date
    public let upvotes: Int
    public let downvotes: Int
    public let viewerRating: Int?
}

public struct PublicQuoteListResponse: Content, Equatable {
    public let quotes: [PublicQuoteResponse]
}

public struct QuoteListQuery: Content, Equatable {
    public let language: String?
    public let limit: Int?
}

public struct QuoteRatingRequest: Content, Equatable {
    public let value: Int
}

public struct QuoteRatingResponse: Content, Equatable {
    public let quoteID: UUID
    public let upvotes: Int
    public let downvotes: Int
    public let viewerRating: Int?
}
