import Foundation
import Vapor

public enum TypebarNotificationKind: String, Content, Equatable, Hashable {
    case connectionRequest
    case connectionAccepted
    case directMessage
}

public struct TypebarNotificationResponse: Content, Equatable, Identifiable {
    public let id: UUID
    public let kind: TypebarNotificationKind
    public let actor: PublicProfileResponse
    public let createdAt: Date
    public let readAt: Date?
}

public struct TypebarNotificationsResponse: Content, Equatable {
    public let notifications: [TypebarNotificationResponse]
}
