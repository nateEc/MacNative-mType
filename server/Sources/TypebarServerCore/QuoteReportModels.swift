import Foundation
import Vapor

public enum QuoteReportReason: String, CaseIterable, Content, Equatable {
    case grammaticalError
    case duplicateQuote
    case lowQualityContent
    case copyright
    case abusiveContent
    case inaccurateAttribution
    case other
}

public struct QuoteReportRequest: Content, Equatable {
    public let quoteID: UUID
    public let reason: QuoteReportReason
    public let note: String?
    public let humanVerification: HumanVerificationProof?

    public init(
        quoteID: UUID, reason: QuoteReportReason, note: String?,
        humanVerification: HumanVerificationProof? = nil
    ) {
        self.quoteID = quoteID
        self.reason = reason
        self.note = note
        self.humanVerification = humanVerification
    }
}

public struct QuoteReportResponse: Content, Equatable {
    public let id: UUID
    public let submittedAt: Date
}
