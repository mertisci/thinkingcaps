import XCTest
@testable import ThinkingCapsCore

final class SessionTrackerTests: XCTestCase {
    func test_newTracker_isEmpty() {
        let tracker = SessionTracker()
        XCTAssertTrue(tracker.isEmpty)
    }

    func test_start_makesTrackerNonEmpty() {
        var tracker = SessionTracker()
        tracker.start("session-1")
        XCTAssertFalse(tracker.isEmpty)
    }

    func test_stop_removesSession() {
        var tracker = SessionTracker()
        tracker.start("session-1")
        tracker.stop("session-1")
        XCTAssertTrue(tracker.isEmpty)
    }

    func test_stop_onlyRemovesMatchingSession() {
        var tracker = SessionTracker()
        tracker.start("session-1")
        tracker.start("session-2")
        tracker.stop("session-1")
        XCTAssertFalse(tracker.isEmpty)
    }

    func test_purgeExpired_removesSessionsOlderThanTimeout() {
        var tracker = SessionTracker(timeout: 600)
        let start = Date(timeIntervalSince1970: 0)
        tracker.start("stale-session", now: start)
        tracker.purgeExpired(now: start.addingTimeInterval(601))
        XCTAssertTrue(tracker.isEmpty)
    }

    func test_purgeExpired_keepsSessionsWithinTimeout() {
        var tracker = SessionTracker(timeout: 600)
        let start = Date(timeIntervalSince1970: 0)
        tracker.start("fresh-session", now: start)
        tracker.purgeExpired(now: start.addingTimeInterval(300))
        XCTAssertFalse(tracker.isEmpty)
    }
}
