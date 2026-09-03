import Vapor
import TypebarServerCore

@main
enum TypebarServer {
    static func main() async throws {
        let app = try await Application.make(.detect())

        try configure(app, passwordResetDelivery: try PasswordResetWebhookDelivery.fromEnvironment())

        do {
            try await app.execute()
            try await app.asyncShutdown()
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
    }
}
