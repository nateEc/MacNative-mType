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
        let expiresAt: Date
        var count: Int
    }

    private var buckets: [String: Bucket] = [:]
    private var nextExpiration: Date?

    public init() {}

    public func evaluate(policy: Policy, key: String, now: Date = .now) -> Decision {
        discardExpiredBuckets(now: now)
        let bucketKey = "\(policy.id):\(key)"
        let bucket = buckets[bucketKey] ?? .init(expiresAt: now.addingTimeInterval(policy.window), count: 0)
        let retryAfter = max(1, Int(ceil(bucket.expiresAt.timeIntervalSince(now))))
        guard bucket.count < policy.maximumRequests else {
            buckets[bucketKey] = bucket
            recordExpiration(bucket.expiresAt)
            return .init(allowed: false, retryAfter: retryAfter, remaining: 0)
        }
        let updatedBucket = Bucket(expiresAt: bucket.expiresAt, count: bucket.count + 1)
        buckets[bucketKey] = updatedBucket
        recordExpiration(updatedBucket.expiresAt)
        return .init(allowed: true, retryAfter: 0, remaining: policy.maximumRequests - updatedBucket.count)
    }

    /// Testable lifecycle observation for the in-memory limiter. This also
    /// clears expired buckets when an otherwise idle service is inspected.
    func activeBucketCount(now: Date = .now) -> Int {
        discardExpiredBuckets(now: now)
        return buckets.count
    }

    private func recordExpiration(_ expiration: Date) {
        guard let nextExpiration else {
            nextExpiration = expiration
            return
        }
        if expiration < nextExpiration {
            self.nextExpiration = expiration
        }
    }

    private func discardExpiredBuckets(now: Date) {
        guard let nextExpiration, nextExpiration <= now else { return }
        buckets = buckets.filter { $0.value.expiresAt > now }
        self.nextExpiration = buckets.values.map(\.expiresAt).min()
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
        if path == "/v1/auth/email-verification/request" {
            return .init(id: "email-verification", maximumRequests: 3, window: 15 * 60)
        }
        if path == "/v1/results" && request.method == .POST {
            return .init(id: "result-write", maximumRequests: 30, window: 60)
        }
        if path == "/v1/results" && request.method == .DELETE {
            return .init(id: "result-delete", maximumRequests: 10, window: 60 * 60)
        }
        guard request.method != .GET else { return .init(id: "read", maximumRequests: 180, window: 60) }
        return .init(id: "write", maximumRequests: 60, window: 60)
    }

    private func limiterKey(for request: Request) -> String {
        if let token = request.headers.bearerAuthorization?.token, !token.isEmpty {
            return "token:\(opaqueKey(token))"
        }
        if let key = request.headers.first(name: "X-Typebar-Access-Key"), !key.isEmpty {
            return "developer-key:\(opaqueKey(key))"
        }
        return "source:\(request.remoteAddress?.ipAddress ?? "unknown")"
    }

    private func opaqueKey(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
