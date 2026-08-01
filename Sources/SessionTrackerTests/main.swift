import Foundation
import MiniTest
import ThinkingCapsCore

let t = MiniTest()

func test_newTracker_isEmpty() {
    let tracker = SessionTracker()
    t.check(tracker.isEmpty, "new tracker is empty")
}

func test_start_makesTrackerNonEmpty() {
    var tracker = SessionTracker()
    tracker.start("session-1")
    t.check(!tracker.isEmpty, "start makes tracker non-empty")
}

func test_stop_removesSession() {
    var tracker = SessionTracker()
    tracker.start("session-1")
    tracker.stop("session-1")
    t.check(tracker.isEmpty, "stop removes session")
}

func test_stop_onlyRemovesMatchingSession() {
    var tracker = SessionTracker()
    tracker.start("session-1")
    tracker.start("session-2")
    tracker.stop("session-1")
    t.check(!tracker.isEmpty, "stop only removes matching session")
}

func test_purgeExpired_removesSessionsOlderThanTimeout() {
    var tracker = SessionTracker(timeout: 600)
    let start = Date(timeIntervalSince1970: 0)
    tracker.start("stale-session", now: start)
    tracker.purgeExpired(now: start.addingTimeInterval(601))
    t.check(tracker.isEmpty, "purgeExpired removes sessions older than timeout")
}

func test_purgeExpired_keepsSessionsWithinTimeout() {
    var tracker = SessionTracker(timeout: 600)
    let start = Date(timeIntervalSince1970: 0)
    tracker.start("fresh-session", now: start)
    tracker.purgeExpired(now: start.addingTimeInterval(300))
    t.check(!tracker.isEmpty, "purgeExpired keeps sessions within timeout")
}

test_newTracker_isEmpty()
test_start_makesTrackerNonEmpty()
test_stop_removesSession()
test_stop_onlyRemovesMatchingSession()
test_purgeExpired_removesSessionsOlderThanTimeout()
test_purgeExpired_keepsSessionsWithinTimeout()

t.finish()
