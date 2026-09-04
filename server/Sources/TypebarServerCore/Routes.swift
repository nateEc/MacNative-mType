import Foundation
import Vapor

private struct OAuthCallbackQuery: Content {
    let code: String?
    let state: String?
    let error: String?
}

private struct OAuthCompletionQuery: Content {
    let state: String
}

private func nativeOAuthCallbackRedirect(state: String) -> Response {
    var components = URLComponents()
    components.scheme = "typebar"
    components.host = "oauth"
    components.path = "/callback"
    components.queryItems = [.init(name: "state", value: state)]
    guard let callbackURL = components.url else { return Response(status: .internalServerError) }
    var headers = HTTPHeaders()
    headers.replaceOrAdd(name: "Location", value: callbackURL.absoluteString)
    return Response(status: .found, headers: headers)
}

public func configure(
    _ app: Application,
    authStore: AuthStore? = nil,
    moderationKey: String? = Environment.get("TYPEBAR_MODERATION_TOKEN"),
    passwordResetDelivery: PasswordResetDeliveryHandler? = nil,
    emailVerificationDelivery: EmailVerificationDeliveryHandler? = nil,
    oauthProviderClient: OAuthProviderClient? = nil,
    maintenanceMode: Bool = TypebarMaintenanceMode.environmentEnabled
) throws {
    let authStore = try authStore ?? AuthStore(fileURL: TypebarServerStorage.defaultUserStoreURL(for: app))
    app.middleware.use(TypebarMaintenanceMiddleware(isEnabled: maintenanceMode))
    app.middleware.use(TypebarRateLimitMiddleware(limiter: RequestRateLimiter()))

    app.get("health") { _ in
        HealthResponse(status: "ok", service: "typebar", maintenanceMode: maintenanceMode)
    }

    app.get("v1", "capabilities") { _ in
        ServiceCapabilitiesResponse(
            apiVersion: "v1",
            service: "typebar",
            capabilities: [
                "health": .available,
                "rateLimiting": .partial,
                "authentication": .available,
                "developerAccessKeys": .partial,
                "passwordReset": passwordResetDelivery == nil ? .planned : .available,
                "emailVerification": emailVerificationDelivery == nil ? .planned : .available,
                "githubOAuth": oauthProviderClient?.isConfigured(for: .github) == true ? .available : .planned,
                "googleOAuth": oauthProviderClient?.isConfigured(for: .google) == true ? .available : .planned,
                "synchronization": .partial,
                "resultSubmission": .partial,
                "resultHistory": .partial,
                "leaderboards": .partial,
                "profiles": .partial,
                "connections": .partial,
                "notifications": .partial,
                "profileReports": .partial,
                "directMessages": .partial,
                "experience": .partial,
                "quotes": .partial
            ]
        )
    }

    app.post("v1", "auth", "register") { request async throws -> AuthSessionResponse in
        do {
            let session = try await authStore.register(request.content.decode(RegisterRequest.self))
            if let emailVerificationDelivery,
                let delivery = try await authStore.requestEmailVerification(accessToken: session.accessToken)
            {
                do {
                    try await emailVerificationDelivery(delivery)
                } catch {
                    try? await authStore.cancelEmailVerification(token: delivery.token)
                    request.logger.warning("Typebar could not deliver a registration verification email.")
                }
            }
            return session
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "auth", "login") { request async throws -> AuthSessionResponse in
        do {
            return try await authStore.login(request.content.decode(LoginRequest.self))
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "auth", "password-reset", "request") { request async throws -> PasswordResetRequestResponse in
        guard let passwordResetDelivery else {
            throw Abort(
                .serviceUnavailable,
                reason: "Password reset email delivery is not configured for this Typebar service."
            )
        }
        let reset = try request.content.decode(PasswordResetRequest.self)
        do {
            if let delivery = try await authStore.requestPasswordReset(for: reset.email) {
                do {
                    try await passwordResetDelivery(delivery)
                } catch {
                    try? await authStore.cancelPasswordReset(token: delivery.token)
                    throw Abort(
                        .serviceUnavailable,
                        reason: "Typebar could not deliver the password reset email. Please try again later."
                    )
                }
            }
            return .init(accepted: true)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "auth", "password-reset", "complete") { request async throws -> PasswordResetCompletionResponse in
        do {
            try await authStore.completePasswordReset(
                request.content.decode(CompletePasswordResetRequest.self))
            return .init(reset: true)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "auth", "email-verification", "request") { request async throws -> EmailVerificationRequestResponse in
        guard let emailVerificationDelivery else {
            throw Abort(
                .serviceUnavailable,
                reason: "Email verification delivery is not configured for this Typebar service."
            )
        }
        do {
            let accessToken = try request.accessToken()
            if let delivery = try await authStore.requestEmailVerification(accessToken: accessToken) {
                do {
                    try await emailVerificationDelivery(delivery)
                } catch {
                    try? await authStore.cancelEmailVerification(token: delivery.token)
                    throw Abort(
                        .serviceUnavailable,
                        reason: "Typebar could not deliver the verification email. Please try again later."
                    )
                }
            }
            return .init(accepted: true)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "auth", "email-verification", "complete") { request async throws -> EmailVerificationCompletionResponse in
        do {
            try await authStore.completeEmailVerification(
                request.content.decode(CompleteEmailVerificationRequest.self))
            return .init(verified: true)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "auth", "oauth", ":provider", "start") { request async throws -> OAuthStartResponse in
        guard let rawProvider = request.parameters.get("provider"),
              let provider = OAuthProvider(rawValue: rawProvider),
              let oauthProviderClient,
              oauthProviderClient.isConfigured(for: provider) else {
            throw Abort(.serviceUnavailable, reason: "That OAuth provider is not configured for this Typebar service.")
        }
        do {
            let start = try request.content.decode(OAuthStartRequest.self)
            let transaction = try await authStore.beginOAuth(
                provider: provider, purpose: start.purpose,
                accessToken: request.headers.bearerAuthorization?.token)
            return try .init(authorizationURL: oauthProviderClient.authorizationURL(for: transaction).absoluteString)
        } catch let error as AuthStoreError {
            throw error.abort
        } catch {
            throw Abort(.badRequest, reason: "The OAuth authorization could not be started.")
        }
    }

    app.get("v1", "auth", "oauth", ":provider", "callback") { request async throws -> Response in
        guard let rawProvider = request.parameters.get("provider"),
              let provider = OAuthProvider(rawValue: rawProvider),
              let oauthProviderClient,
              oauthProviderClient.isConfigured(for: provider) else {
            throw Abort(.serviceUnavailable, reason: "That OAuth provider is not configured for this Typebar service.")
        }
        let callback = try request.query.decode(OAuthCallbackQuery.self)
        guard let state = callback.state, !state.isEmpty else {
            throw Abort(.badRequest, reason: "The OAuth callback did not include state.")
        }
        do {
            let exchange = try await authStore.beginOAuthCallback(provider: provider, stateToken: state)
            if callback.error != nil || callback.code == nil {
                try await authStore.failOAuthCallback(stateToken: state)
            } else if let code = callback.code {
                do {
                    let identity = try await oauthProviderClient.resolveIdentity(
                        provider: provider, authorizationCode: code, codeVerifier: exchange.codeVerifier)
                    try await authStore.completeOAuthCallback(stateToken: state, identity: identity)
                } catch {
                    try? await authStore.failOAuthCallback(stateToken: state)
                }
            }
            return nativeOAuthCallbackRedirect(state: state)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.get("v1", "auth", "oauth", "completion") { request async throws -> OAuthCompletionResponse in
        let query = try request.query.decode(OAuthCompletionQuery.self)
        do {
            return try await authStore.oauthCompletion(stateToken: query.state)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "auth", "oauth", "registration") { request async throws -> AuthSessionResponse in
        do {
            let registration = try request.content.decode(OAuthRegistrationRequest.self)
            return try await authStore.completeOAuthRegistration(
                stateToken: registration.state, displayName: registration.displayName)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.delete("v1", "auth", "oauth", ":provider") { request async throws -> AuthUserResponse in
        guard let rawProvider = request.parameters.get("provider"),
              let provider = OAuthProvider(rawValue: rawProvider) else {
            throw Abort(.badRequest, reason: "The OAuth provider is invalid.")
        }
        do {
            return try await authStore.unlinkOAuth(
                provider,
                accessToken: try request.accessToken(),
                reauthenticationToken: try request.reauthenticationToken())
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "auth", "password") { request async throws -> AuthSessionResponse in
        do {
            let accessToken = try request.accessToken()
            let change = try request.content.decode(ChangePasswordRequest.self)
            return try await authStore.changePassword(change, accessToken: accessToken)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "auth", "password", "add") { request async throws -> AuthUserResponse in
        do {
            return try await authStore.addPasswordAuthentication(
                request.content.decode(AddPasswordAuthenticationRequest.self),
                accessToken: request.accessToken(),
                reauthenticationToken: request.reauthenticationToken()
            )
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "auth", "reauthentication", "password") { request async throws -> ReauthenticationResponse in
        do {
            return try await authStore.reauthenticateWithPassword(
                request.content.decode(PasswordReauthenticationRequest.self),
                accessToken: request.accessToken()
            )
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.delete("v1", "auth", "password") { request async throws -> AuthUserResponse in
        do {
            return try await authStore.removePasswordAuthentication(
                request.content.decode(RemovePasswordAuthenticationRequest.self),
                accessToken: request.accessToken()
            )
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "auth", "email") { request async throws -> AuthSessionResponse in
        do {
            let accessToken = try request.accessToken()
            let change = try request.content.decode(ChangeEmailRequest.self)
            let session = try await authStore.changeEmail(change, accessToken: accessToken)
            if let emailVerificationDelivery,
                let delivery = try await authStore.requestEmailVerification(accessToken: session.accessToken)
            {
                do {
                    try await emailVerificationDelivery(delivery)
                } catch {
                    try? await authStore.cancelEmailVerification(token: delivery.token)
                    request.logger.warning("Typebar could not deliver an email-change verification email.")
                }
            }
            return session
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.delete("v1", "auth", "account") { request async throws -> AccountDeletionResponse in
        do {
            let accessToken = try request.accessToken()
            let deletion = try request.content.decode(DeleteAccountRequest.self)
            try await authStore.deleteAccount(
                deletion,
                accessToken: accessToken,
                reauthenticationToken: request.headers.first(name: "X-Typebar-Reauthentication")
            )
            return .init(deleted: true)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "auth", "sessions", "revoke") { request async throws -> SessionsRevocationResponse in
        do {
            try await authStore.revokeAllSessions(
                request.content.decode(RevokeSessionsRequest.self),
                accessToken: request.accessToken(),
                reauthenticationToken: request.headers.first(name: "X-Typebar-Reauthentication")
            )
            return .init(revoked: true)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.get("v1", "profiles", "me") { request async throws -> AuthUserResponse in
        do {
            return try await authStore.authenticatedUser(for: try request.accessToken())
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.patch("v1", "profiles", "me") { request async throws -> AuthUserResponse in
        do {
            return try await authStore.updateProfile(
                request.content.decode(UpdateProfileRequest.self),
                accessToken: try request.accessToken()
            )
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.get("v1", "profiles") { request async throws -> PublicProfileSearchResponse in
        do {
            let query = try request.query.decode(ProfileSearchQuery.self)
            return try await authStore.searchPublicProfiles(query: query.query, limit: query.limit)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.get("v1", "profiles", ":id") { request async throws -> PublicProfileResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else {
            throw Abort(.badRequest, reason: "The profile identifier was invalid.")
        }
        do {
            return try await authStore.publicProfile(id: id)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.get("v1", "connections") { request async throws -> ConnectionsResponse in
        do {
            return try await authStore.connections(accessToken: try request.accessToken())
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "connections") { request async throws -> ConnectionResponse in
        do {
            let accessToken = try request.accessToken()
            return try await authStore.sendConnection(request.content.decode(ConnectionRequest.self), accessToken: accessToken)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "connections", ":id", "accept") { request async throws -> ConnectionResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else {
            throw Abort(.badRequest, reason: "The connection identifier was invalid.")
        }
        do {
            return try await authStore.acceptConnection(requesterID: id, accessToken: try request.accessToken())
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.delete("v1", "connections", ":id") { request async throws -> ConnectionRemovalResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else {
            throw Abort(.badRequest, reason: "The connection identifier was invalid.")
        }
        do {
            try await authStore.removeConnection(otherUserID: id, accessToken: try request.accessToken())
            return .init(removed: true)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "blocks", ":id") { request async throws -> ConnectionRemovalResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else { throw Abort(.badRequest, reason: "The profile identifier was invalid.") }
        do {
            try await authStore.blockUser(id, accessToken: try request.accessToken())
            return .init(removed: true)
        } catch let error as AuthStoreError { throw error.abort }
    }

    app.get("v1", "blocks") { request async throws -> BlockedUsersResponse in
        do { return try await authStore.blockedUsers(accessToken: try request.accessToken()) }
        catch let error as AuthStoreError { throw error.abort }
    }

    app.delete("v1", "blocks", ":id") { request async throws -> ConnectionRemovalResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else { throw Abort(.badRequest, reason: "The profile identifier was invalid.") }
        do {
            try await authStore.unblockUser(id, accessToken: try request.accessToken())
            return .init(removed: true)
        } catch let error as AuthStoreError { throw error.abort }
    }

    app.get("v1", "notifications") { request async throws -> TypebarNotificationsResponse in
        do { return try await authStore.notifications(accessToken: try request.accessToken()) }
        catch let error as AuthStoreError { throw error.abort }
    }

    app.post("v1", "notifications", ":id", "read") { request async throws -> TypebarNotificationResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else {
            throw Abort(.badRequest, reason: "The notification identifier was invalid.")
        }
        do { return try await authStore.markNotificationRead(id, accessToken: try request.accessToken()) }
        catch let error as AuthStoreError { throw error.abort }
    }

    app.post("v1", "reports", "profiles") { request async throws -> ProfileReportResponse in
        do {
            return try await authStore.submitProfileReport(
                request.content.decode(ProfileReportRequest.self), accessToken: try request.accessToken()
            )
        } catch let error as AuthStoreError { throw error.abort }
    }

    app.post("v1", "reports", "quotes") { request async throws -> QuoteReportResponse in
        do { return try await authStore.submitQuoteReport(try request.content.decode(QuoteReportRequest.self), accessToken: try request.accessToken()) }
        catch let error as AuthStoreError { throw error.abort }
    }

    app.get("v1", "moderation", "profile-reports") { request async throws -> ModerationProfileReportListResponse in
        guard let expectedKey = moderationKey, !expectedKey.isEmpty,
              request.headers.first(name: "X-Typebar-Moderation-Key") == expectedKey else {
            throw Abort(.forbidden, reason: "A configured Typebar moderation key is required.")
        }
        let query = try request.query.decode(ModerationProfileReportListQuery.self)
        return await authStore.moderationProfileReports(status: query.status, limit: query.limit)
    }

    app.patch("v1", "moderation", "profile-reports", ":id") { request async throws -> ModerationProfileReportResponse in
        guard let expectedKey = moderationKey, !expectedKey.isEmpty,
              request.headers.first(name: "X-Typebar-Moderation-Key") == expectedKey else {
            throw Abort(.forbidden, reason: "A configured Typebar moderation key is required.")
        }
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else { throw Abort(.badRequest, reason: "The profile report identifier was invalid.") }
        do { return try await authStore.moderateProfileReport(id, status: try request.content.decode(ProfileReportModerationRequest.self).status) }
        catch let error as AuthStoreError { throw error.abort }
    }

    app.get("v1", "messages", ":id") { request async throws -> DirectConversationResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else { throw Abort(.badRequest, reason: "The profile identifier was invalid.") }
        do { return try await authStore.directConversation(with: id, accessToken: try request.accessToken()) }
        catch let error as AuthStoreError { throw error.abort }
    }

    app.post("v1", "messages") { request async throws -> DirectMessageResponse in
        do { return try await authStore.sendDirectMessage(request.content.decode(DirectMessageRequest.self), accessToken: try request.accessToken()) }
        catch let error as AuthStoreError { throw error.abort }
    }

    app.post("v1", "messages", ":id", "read") { request async throws -> ConnectionRemovalResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else { throw Abort(.badRequest, reason: "The profile identifier was invalid.") }
        do { try await authStore.markDirectConversationRead(with: id, accessToken: try request.accessToken()); return .init(removed: true) }
        catch let error as AuthStoreError { throw error.abort }
    }

    app.post("v1", "quotes") { request async throws -> QuoteSubmissionResponse in
        do {
            let token = try request.accessToken()
            return try await authStore.submitQuote(try request.content.decode(QuoteSubmissionRequest.self), accessToken: token)
        } catch let error as AuthStoreError { throw error.abort }
    }

    app.get("v1", "quotes", "mine") { request async throws -> QuoteSubmissionListResponse in
        do { return try await authStore.quoteSubmissions(accessToken: try request.accessToken()) }
        catch let error as AuthStoreError { throw error.abort }
    }

    app.get("v1", "quotes") { request async throws -> PublicQuoteListResponse in
        do {
            let query = try request.query.decode(QuoteListQuery.self)
            return try await authStore.publicQuotes(language: query.language, limit: query.limit, accessToken: request.headers.bearerAuthorization?.token)
        } catch let error as AuthStoreError { throw error.abort }
    }

    app.put("v1", "quotes", ":id", "rating") { request async throws -> QuoteRatingResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else { throw Abort(.badRequest, reason: "The quote identifier was invalid.") }
        do { return try await authStore.rateQuote(id, request: try request.content.decode(QuoteRatingRequest.self), accessToken: try request.accessToken()) }
        catch let error as AuthStoreError { throw error.abort }
    }

    app.get("v1", "moderation", "quotes") { request async throws -> ModerationQuoteListResponse in
        guard let expectedKey = moderationKey, !expectedKey.isEmpty,
              request.headers.first(name: "X-Typebar-Moderation-Key") == expectedKey else {
            throw Abort(.forbidden, reason: "A configured Typebar moderation key is required.")
        }
        do {
            let query = try request.query.decode(ModerationQuoteListQuery.self)
            return try await authStore.moderationQuotes(status: query.status, limit: query.limit)
        } catch let error as AuthStoreError { throw error.abort }
    }

    app.patch("v1", "moderation", "quotes", ":id") { request async throws -> QuoteSubmissionResponse in
        guard let expectedKey = moderationKey, !expectedKey.isEmpty,
              request.headers.first(name: "X-Typebar-Moderation-Key") == expectedKey else {
            throw Abort(.forbidden, reason: "A configured Typebar moderation key is required.")
        }
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else { throw Abort(.badRequest, reason: "The quote identifier was invalid.") }
        do { return try await authStore.moderateQuote(id, status: try request.content.decode(QuoteModerationRequest.self).status) }
        catch let error as AuthStoreError { throw error.abort }
    }

    app.delete("v1", "quotes", ":id") { request async throws -> ConnectionRemovalResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else { throw Abort(.badRequest, reason: "The quote identifier was invalid.") }
        do {
            try await authStore.withdrawQuoteSubmission(id, accessToken: try request.accessToken())
            return .init(removed: true)
        } catch let error as AuthStoreError { throw error.abort }
    }

    app.post("v1", "sync") { request async throws -> SyncPushResponse in
        do {
            return try await authStore.pushSync(
                request.content.decode(SyncPushRequest.self),
                accessToken: try request.accessToken()
            )
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.get("v1", "sync") { request async throws -> SyncPullResponse in
        do {
            let query = try request.query.decode(SyncCursorQuery.self)
            return try await authStore.pullSync(
                after: max(0, query.cursor ?? 0), accessToken: try request.accessToken(),
                limit: query.limit
            )
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.get("v1", "developer-keys") { request async throws -> DeveloperAccessKeyListResponse in
        do {
            return try await authStore.developerAccessKeys(accessToken: try request.accessToken())
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "developer-keys") { request async throws -> CreateDeveloperAccessKeyResponse in
        do {
            return try await authStore.createDeveloperAccessKey(
                request.content.decode(CreateDeveloperAccessKeyRequest.self),
                accessToken: try request.accessToken())
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.patch("v1", "developer-keys", ":id") { request async throws -> DeveloperAccessKey in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else {
            throw Abort(.badRequest, reason: "The developer key identifier was invalid.")
        }
        do {
            return try await authStore.updateDeveloperAccessKey(
                id: id, request: request.content.decode(UpdateDeveloperAccessKeyRequest.self),
                accessToken: try request.accessToken())
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.delete("v1", "developer-keys", ":id") { request async throws -> DeveloperAccessKeyDeletionResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else {
            throw Abort(.badRequest, reason: "The developer key identifier was invalid.")
        }
        do {
            try await authStore.deleteDeveloperAccessKey(id: id, accessToken: try request.accessToken())
            return .init(deleted: true)
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.delete("v1", "results") { request async throws -> ResultDeletionResponse in
        do {
            let accessToken = try request.accessToken()
            let deletion = try request.content.decode(DeleteResultsRequest.self)
            return try await authStore.deleteResults(
                deletion,
                accessToken: accessToken,
                reauthenticationToken: request.headers.first(name: "X-Typebar-Reauthentication")
            )
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.patch("v1", "results", ":id", "tags") { request async throws -> AccountResultResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else {
            throw Abort(.badRequest, reason: "The result identifier was invalid.")
        }
        do {
            let accessToken = try request.accessToken()
            return try await authStore.updateResultTags(
                id: id,
                request: request.content.decode(UpdateResultTagsRequest.self),
                accessToken: accessToken
            )
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.get("v1", "results") { request async throws -> ResultListResponse in
        do {
            return try await authStore.results(
                request.query.decode(ResultListQuery.self),
                credential: try request.resultCredential()
            )
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.get("v1", "results", ":id") { request async throws -> AccountResultResponse in
        guard let rawID = request.parameters.get("id"), let id = UUID(uuidString: rawID) else {
            throw Abort(.badRequest, reason: "The result identifier was invalid.")
        }
        do {
            return try await authStore.result(id: id, credential: try request.resultCredential())
        } catch let error as AuthStoreError {
            throw error.abort
        }
    }

    app.post("v1", "results") { request async throws -> ResultSubmissionResponse in
        do {
            let credential = try request.resultCredential()
            let submission = try request.content.decode(ResultSubmissionRequest.self)
            return try await authStore.submitResult(
                submission,
                credential: credential
            )
        } catch let error as AuthStoreError {
            throw error.abort
        } catch is ResultStoreError {
            throw Abort(.badRequest, reason: "The submitted result was outside Typebar's accepted bounds.")
        }
    }

    app.get("v1", "leaderboards", "rank") { request async throws -> LeaderboardRankResponse in
        do {
            return try await authStore.leaderboardRank(
                request.query.decode(LeaderboardQuery.self), accessToken: try request.accessToken()
            )
        } catch let error as AuthStoreError {
            throw error.abort
        } catch is ResultStoreError {
            throw Abort(.badRequest, reason: "The leaderboard filters were invalid.")
        }
    }

    app.get("v1", "leaderboards", "friends", "rank") { request async throws -> LeaderboardRankResponse in
        do {
            return try await authStore.friendLeaderboardRank(
                request.query.decode(LeaderboardQuery.self), accessToken: try request.accessToken()
            )
        } catch let error as AuthStoreError {
            throw error.abort
        } catch is ResultStoreError {
            throw Abort(.badRequest, reason: "The leaderboard filters were invalid.")
        }
    }

    app.get("v1", "leaderboards", "friends") { request async throws -> LeaderboardResponse in
        do {
            return try await authStore.friendLeaderboard(
                request.query.decode(LeaderboardQuery.self),
                accessToken: try request.accessToken()
            )
        } catch let error as AuthStoreError {
            throw error.abort
        } catch is ResultStoreError {
            throw Abort(.badRequest, reason: "The leaderboard filters were invalid.")
        }
    }

    app.get("v1", "leaderboards") { request async throws -> LeaderboardResponse in
        do {
            return try await authStore.leaderboard(request.query.decode(LeaderboardQuery.self))
        } catch is ResultStoreError {
            throw Abort(.badRequest, reason: "The leaderboard filters were invalid.")
        }
    }

    app.get("v1", "leaderboards", "experience", "rank") { request async throws -> ExperienceLeaderboardRankResponse in
        do {
            return try await authStore.experienceLeaderboardRank(
                period: try request.query.decode(ExperienceLeaderboardQuery.self).period,
                accessToken: try request.accessToken()
            )
        } catch let error as AuthStoreError {
            throw error.abort
        } catch is ResultStoreError {
            throw Abort(.badRequest, reason: "The experience leaderboard period was invalid.")
        }
    }

    app.get("v1", "leaderboards", "experience", "friends", "rank") { request async throws -> ExperienceLeaderboardRankResponse in
        do {
            return try await authStore.friendExperienceLeaderboardRank(
                period: try request.query.decode(ExperienceLeaderboardQuery.self).period,
                accessToken: try request.accessToken()
            )
        } catch let error as AuthStoreError {
            throw error.abort
        } catch is ResultStoreError {
            throw Abort(.badRequest, reason: "The experience leaderboard period was invalid.")
        }
    }

    app.get("v1", "leaderboards", "experience") { request async throws -> ExperienceLeaderboardResponse in
        do {
            return try await authStore.experienceLeaderboard(
                period: try request.query.decode(ExperienceLeaderboardQuery.self).period
            )
        } catch is ResultStoreError {
            throw Abort(.badRequest, reason: "The experience leaderboard period was invalid.")
        }
    }

    app.get("v1", "leaderboards", "experience", "friends") { request async throws -> ExperienceLeaderboardResponse in
        do {
            return try await authStore.friendExperienceLeaderboard(
                period: try request.query.decode(ExperienceLeaderboardQuery.self).period,
                accessToken: try request.accessToken()
            )
        } catch let error as AuthStoreError {
            throw error.abort
        } catch is ResultStoreError {
            throw Abort(.badRequest, reason: "The experience leaderboard period was invalid.")
        }
    }
}

public enum TypebarServerStorage {
    public static func defaultUserStoreURL(for app: Application) -> URL {
        let path = ProcessInfo.processInfo.environment["TYPEBAR_DATA_DIRECTORY"] ?? app.directory.workingDirectory + "typebar-server-data"
        return URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("users.json")
    }
}

public struct HealthResponse: Content, Equatable {
    public let status: String
    public let service: String
    public let maintenanceMode: Bool

    public init(status: String, service: String, maintenanceMode: Bool) {
        self.status = status
        self.service = service
        self.maintenanceMode = maintenanceMode
    }
}

public struct ServiceCapabilitiesResponse: Content, Equatable {
    public let apiVersion: String
    public let service: String
    public let capabilities: [String: ServiceCapabilityStatus]

    public init(apiVersion: String, service: String, capabilities: [String: ServiceCapabilityStatus]) {
        self.apiVersion = apiVersion
        self.service = service
        self.capabilities = capabilities
    }
}

public enum ServiceCapabilityStatus: String, Content, Equatable {
    case available
    case partial
    case planned
}

private extension AuthStoreError {
    var abort: Abort {
        switch self {
        case .invalidEmail, .invalidDisplayName, .weakPassword, .invalidOAuthIdentity, .invalidQuoteSubmission, .cannotReportSelf, .invalidProfileReport, .invalidDirectMessage:
            Abort(.badRequest, reason: "The request did not meet Typebar account requirements.")
        case .emailAlreadyRegistered:
            Abort(.conflict, reason: "An account already exists for this email address.")
        case .oauthIdentityAlreadyLinked:
            Abort(.conflict, reason: "That OAuth identity is already linked to a Typebar account.")
        case .passwordAuthenticationAlreadyLinked:
            Abort(.conflict, reason: "Password authentication is already linked to this Typebar account.")
        case .cannotRemoveLastAuthentication:
            Abort(.conflict, reason: "A Typebar account must retain at least one authentication method.")
        case .oauthRegistrationNotRequired:
            Abort(.conflict, reason: "This OAuth authorization does not require account registration.")
        case .invalidCredentials, .invalidAccessToken:
            Abort(.unauthorized, reason: "Invalid email or password.")
        case .invalidDeveloperAccessKey:
            Abort(.unauthorized, reason: "The Typebar developer key is invalid.")
        case .inactiveDeveloperAccessKey:
            Abort(.forbidden, reason: "The Typebar developer key is disabled.")
        case .invalidOAuthTransaction:
            Abort(.unauthorized, reason: "This OAuth authorization is invalid or has expired.")
        case .invalidReauthenticationToken:
            Abort(.unauthorized, reason: "A recent Typebar reauthentication is required for this action.")
        case .invalidPasswordResetToken:
            Abort(.unauthorized, reason: "This password reset code is invalid or has expired.")
        case .invalidEmailVerificationToken:
            Abort(.unauthorized, reason: "This email verification code is invalid or has expired.")
        case .oauthIdentityNotLinked:
            Abort(.notFound, reason: "The requested OAuth identity is not linked to this Typebar account.")
        case .passwordAuthenticationNotLinked:
            Abort(.notFound, reason: "Password authentication is not linked to this Typebar account.")
        case .profileNotFound:
            Abort(.notFound, reason: "The requested Typebar profile does not exist.")
        case .cannotConnectToSelf, .connectionNotPending:
            Abort(.badRequest, reason: "The requested connection change was invalid.")
        case .connectionAlreadyExists:
            Abort(.conflict, reason: "A Typebar connection already exists for these users.")
        case .connectionNotFound:
            Abort(.notFound, reason: "The requested Typebar connection does not exist.")
        case .notificationNotFound:
            Abort(.notFound, reason: "The requested Typebar notification does not exist.")
        case .reportAlreadySubmitted:
            Abort(.conflict, reason: "A matching report has already been submitted by this account.")
        case .invalidProfileSearch:
            Abort(.badRequest, reason: "A public profile search requires 2 to 40 display-name characters.")
        case .invalidProfileDetails:
            Abort(.badRequest, reason: "The public profile details are invalid.")
        case .invalidDeveloperAccessKeyName:
            Abort(.badRequest, reason: "A developer key name must be 1 to 20 ASCII letters, numbers, hyphens, or underscores and begin with a letter or number.")
        case .developerAccessKeyNotFound:
            Abort(.notFound, reason: "The requested Typebar developer key does not exist.")
        case .developerAccessKeyLimitReached:
            Abort(.conflict, reason: "A Typebar account can have at most five developer keys.")
        case .invalidResultQuery:
            Abort(.badRequest, reason: "The requested result range was invalid.")
        case .resultNotFound:
            Abort(.notFound, reason: "The requested Typebar result does not exist.")
        case .invalidResultTags:
            Abort(.badRequest, reason: "Result tags must be unique, non-empty, and no longer than 24 characters.")
        case .directMessageNotAllowed:
            Abort(.forbidden, reason: "Direct messages are only available between accepted Typebar friends.")
        }
    }
}

private extension Request {
    func accessToken() throws -> String {
        guard let token = headers.bearerAuthorization?.token, !token.isEmpty else {
            throw Abort(.unauthorized, reason: "A Typebar access token is required.")
        }
        return token
    }

    func resultCredential() throws -> ResultServiceCredential {
        if let key = headers.first(name: "X-Typebar-Access-Key") {
            guard !key.isEmpty else {
                throw Abort(.unauthorized, reason: "A Typebar developer key is required.")
            }
            return .developerAccessKey(key)
        }
        return .accessToken(try accessToken())
    }

    func reauthenticationToken() throws -> String {
        guard let token = headers.first(name: "X-Typebar-Reauthentication"), !token.isEmpty else {
            throw Abort(.unauthorized, reason: "A recent Typebar reauthentication is required for this action.")
        }
        return token
    }
}
