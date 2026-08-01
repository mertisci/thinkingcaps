import Foundation
import MiniTest
import HookNotifyCore

let t = MiniTest()

func test_extractSessionID_fromValidPayload() {
    let json = #"{"session_id": "abc-123", "other_field": true}"#
    let data = json.data(using: .utf8)!
    t.check(HookPayload.extractSessionID(from: data) == "abc-123", "extracts session_id from valid payload")
}

func test_extractSessionID_returnsNilForMissingField() {
    let json = #"{"other_field": true}"#
    let data = json.data(using: .utf8)!
    t.check(HookPayload.extractSessionID(from: data) == nil, "returns nil for missing field")
}

func test_extractSessionID_returnsNilForInvalidJSON() {
    let data = "not json".data(using: .utf8)!
    t.check(HookPayload.extractSessionID(from: data) == nil, "returns nil for invalid JSON")
}

test_extractSessionID_fromValidPayload()
test_extractSessionID_returnsNilForMissingField()
test_extractSessionID_returnsNilForInvalidJSON()

t.finish()
