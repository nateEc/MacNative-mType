import Foundation
import Vapor

public enum QuoteReportReason: String, CaseIterable, Content, Equatable {
    case copyright
    case abusiveContent
    case inaccurateAttribution
    case other
}

public struct QuoteReportRequest: Content, Equatable {
    public let quoteID: UUID
    public let reason: QuoteReportReason
    public let note: String?
}

public struct QuoteReportResponse: Content, Equatable {
    public let id: UUID
    public let submittedAt: Date
}
