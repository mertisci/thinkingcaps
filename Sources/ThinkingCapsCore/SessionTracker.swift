import Foundation

public struct SessionTracker {
    private var startedAt: [String: Date] = [:]
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 600) {
        self.timeout = timeout
    }

    public var isEmpty: Bool { startedAt.isEmpty }

    public mutating func start(_ id: String, now: Date = Date()) {
        startedAt[id] = now
    }

    public mutating func stop(_ id: String) {
        startedAt.removeValue(forKey: id)
    }

    public mutating func purgeExpired(now: Date = Date()) {
        startedAt = startedAt.filter { now.timeIntervalSince($0.value) < timeout }
    }
}
