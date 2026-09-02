import Vapor

/// Startup-only maintenance configuration for a self-hosted Typebar service.
/// Keeping this state immutable makes the mode predictable across requests and
/// avoids accepting a write partway through an operational change.
public enum TypebarMaintenanceMode {
    public static var environmentEnabled: Bool {
        isEnabled(value: Environment.get("TYPEBAR_MAINTENANCE_MODE"))
    }

    public static func isEnabled(value: String?) -> Bool {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": true
        default: false
        }
    }
}

/// Allows status and read-only requests during planned maintenance while
/// preventing every operation that can mutate service-owned data.
public struct TypebarMaintenanceMiddleware: AsyncMiddleware {
    private let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard isEnabled, request.method != .GET, request.method != .HEAD, request.method != .OPTIONS else {
            return try await next.respond(to: request)
        }
        var headers = HTTPHeaders()
        headers.add(name: .retryAfter, value: "300")
        headers.add(name: "X-Typebar-Maintenance", value: "true")
        return Response(
            status: .serviceUnavailable,
            headers: headers,
            body: .init(string: #"{"error":true,"reason":"Typebar service is under maintenance. Local practice remains available; please try again later."}"#)
        )
    }
}
