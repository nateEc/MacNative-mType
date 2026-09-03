import Foundation
import Vapor

/// Typebar-owned fixed-window limiter. It intentionally keeps only opaque
/// bucket keys in memory; no request bodies, emails, or tokens are persisted.
public actor RequestRateLimiter {
    public struct Policy: Sendable, Equatable {
        public let id: String
        public let maximumRequests: Int
        public let window: TimeInterval

        public init(id: String, maximumRequests: Int, window: TimeInterval) {
            self.id = id
            self.maximumRequests = maximumRequests
            self.window = window
        }
    }

    public struct Decision: Sendable, Equatable {
        public let allowed: Bool
        public let retryAfter: Int
        public let remaining: Int
    }

    private struct Bucket: Sendable {
        var startedAt: Date
        var count: Int
    }

    private var buckets: [String: Bucket] = [:]

    public init() {}

    public func evaluate(policy: Policy, key: String, now: Date = .now) -> Decision {
        let bucketKey = "\(policy.id):\(key)"
        var bucket = buckets[bucketKey] ?? .init(startedAt: now, count: 0)
        if now.timeIntervalSince(bucket.startedAt) >= policy.window {
            bucket = .init(startedAt: now, count: 0)
        }
        let retryAfter = max(1, Int(ceil(policy.window - now.timeIntervalSince(bucket.startedAt))))
        guard bucket.count < policy.maximumRequests else {
            buckets[bucketKey] = bucket
            return .init(allowed: false, retryAfter: retryAfter, remaining: 0)
        }
        bucket.count += 1
        buckets[bucketKey] = bucket
        return .init(allowed: true, retryAfter: 0, remaining: policy.maximumRequests - bucket.count)
    }
}

public struct TypebarRateLimitMiddleware: AsyncMiddleware {
    private let limiter: RequestRateLimiter

    public init(limiter: RequestRateLimiter) {
        self.limiter = limiter
    }

    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let policy = policy(for: request) else {
            return try await next.respond(to: request)
        }
        let decision = await limiter.evaluate(policy: policy, key: limiterKey(for: request))
        guard !decision.allowed else {
            return try await next.respond(to: request)
        }
        request.logger.warning("Typebar request rate limit exceeded for \(policy.id).")
        var headers = HTTPHeaders()
        headers.add(name: .retryAfter, value: String(decision.retryAfter))
        headers.add(name: "X-RateLimit-Remaining", value: "0")
        return Response(
            status: .tooManyRequests,
            headers: headers,
            body: .init(string: #"{"error":true,"reason":"Too many Typebar requests. Please try again later."}"#)
        )
    }

    private func policy(for request: Request) -> RequestRateLimiter.Policy? {
        let path = request.url.path
        if path == "/health" || path == "/v1/capabilities" { return nil }
        if path == "/v1/auth/login" || path == "/v1/auth/register" {
            return .init(id: "authentication", maximumRequests: 10, window: 60)
        }
        if path == "/v1/auth/password-reset/request" {
            return .init(id: "password-reset", maximumRequests: 3, window: 15 * 60)
        }
        if path == "/v1/results" && request.method == .POST {
            return .init(id: "result-write", maximumRequests: 30, window: 60)
        }
        guard request.method != .GET else { return .init(id: "read", maximumRequests: 180, window: 60) }
        return .init(id: "write", maximumRequests: 60, window: 60)
    }

    private func limiterKey(for request: Request) -> String {
        if let token = request.headers.bearerAuthorization?.token, !token.isEmpty {
            return "token:\(token)"
        }
        return "source:\(request.remoteAddress?.ipAddress ?? "unknown")"
    }
}
