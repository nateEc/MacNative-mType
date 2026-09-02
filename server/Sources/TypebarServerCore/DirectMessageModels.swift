import Foundation
import Vapor

public struct DirectMessageRequest: Content, Equatable {
    public let recipientID: UUID
    public let body: String
}

public struct DirectMessageResponse: Content, Equatable, Identifiable {
    public let id: UUID
    public let senderID: UUID
    public let recipientID: UUID
    public let body: String
    public let createdAt: Date
    public let readAt: Date?
}

public struct DirectConversationResponse: Content, Equatable {
    public let messages: [DirectMessageResponse]
}
