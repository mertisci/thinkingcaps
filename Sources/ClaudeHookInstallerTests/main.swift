import Foundation
import MiniTest
import ThinkingCapsCore

let t = MiniTest()

func withTempSettingsURL(_ body: (URL) -> Void) {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    body(tempURL)
    try? FileManager.default.removeItem(at: tempURL)
}

func readJSON(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

func test_install_onMissingFile_createsHooksSection() {
    withTempSettingsURL { tempURL in
        let installer = ClaudeHookInstaller(settingsURL: tempURL)
        do {
            try installer.install(notifierPath: "/Applications/ThinkingCaps.app/Contents/MacOS/hook-notify")
        } catch {
            t.check(false, "install threw: \(error)")
            return
        }
        let root = readJSON(tempURL)
        let hooks = root?["hooks"] as? [String: Any]
        t.check(hooks?["UserPromptSubmit"] != nil, "creates UserPromptSubmit hooks section")
        t.check(hooks?["Stop"] != nil, "creates Stop hooks section")
    }
}

func test_install_isIdempotent() {
    withTempSettingsURL { tempURL in
        let installer = ClaudeHookInstaller(settingsURL: tempURL)
        try? installer.install(notifierPath: "/Applications/ThinkingCaps.app/Contents/MacOS/hook-notify")
        try? installer.install(notifierPath: "/Applications/ThinkingCaps.app/Contents/MacOS/hook-notify")

        let root = readJSON(tempURL)
        let hooks = root?["hooks"] as? [String: Any]
        let userPromptEntries = hooks?["UserPromptSubmit"] as? [[String: Any]]
        t.check(userPromptEntries?.count == 1, "install is idempotent (no duplicate entries)")
    }
}

func test_install_preservesUnrelatedExistingSettings() {
    withTempSettingsURL { tempURL in
        let existing: [String: Any] = [
            "someOtherSetting": true,
            "hooks": [
                "PreToolUse": [
                    ["hooks": [["type": "command", "command": "echo hi"]]]
                ]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: existing) {
            try? data.write(to: tempURL)
        }

        let installer = ClaudeHookInstaller(settingsURL: tempURL)
        try? installer.install(notifierPath: "/Applications/ThinkingCaps.app/Contents/MacOS/hook-notify")

        let root = readJSON(tempURL)
        t.check(root?["someOtherSetting"] as? Bool == true, "preserves unrelated top-level settings")
        let hooks = root?["hooks"] as? [String: Any]
        t.check(hooks?["PreToolUse"] != nil, "preserves existing PreToolUse hooks")
        t.check(hooks?["UserPromptSubmit"] != nil, "adds UserPromptSubmit hooks")
    }
}

func commands(in entries: [[String: Any]]?) -> [String] {
    (entries ?? []).flatMap { entry -> [String] in
        let innerHooks = entry["hooks"] as? [[String: Any]] ?? []
        return innerHooks.compactMap { $0["command"] as? String }
    }
}

func test_install_replacesOurEntryWhenNotifierPathChanges() {
    withTempSettingsURL { tempURL in
        let oldPath = "/Users/someone/thinkingcaps/.build/debug/hook-notify"
        let newPath = "/Applications/ThinkingCaps.app/Contents/MacOS/hook-notify"
        let installer = ClaudeHookInstaller(settingsURL: tempURL)
        try? installer.install(notifierPath: oldPath)
        try? installer.install(notifierPath: newPath)

        let hooks = readJSON(tempURL)?["hooks"] as? [String: Any]
        let startCommands = commands(in: hooks?["UserPromptSubmit"] as? [[String: Any]])
        let stopCommands = commands(in: hooks?["Stop"] as? [[String: Any]])
        t.check(startCommands == ["\(newPath) start"], "path change replaces the start hook instead of appending")
        t.check(stopCommands == ["\(newPath) stop"], "path change replaces the stop hook instead of appending")
    }
}

func test_install_leavesForeignHooksUntouchedWhenReplacing() {
    withTempSettingsURL { tempURL in
        let oldPath = "/Volumes/ThinkingCaps/ThinkingCaps.app/Contents/MacOS/hook-notify"
        let newPath = "/Applications/ThinkingCaps.app/Contents/MacOS/hook-notify"
        let existing: [String: Any] = [
            "hooks": [
                "UserPromptSubmit": [
                    ["hooks": [["type": "command", "command": "echo before"]]],
                    ["hooks": [["type": "command", "command": "\(oldPath) start"]]],
                    ["matcher": "*", "hooks": [["type": "command", "command": "echo after"]]]
                ]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: existing) {
            try? data.write(to: tempURL)
        }

        let installer = ClaudeHookInstaller(settingsURL: tempURL)
        try? installer.install(notifierPath: newPath)

        let hooks = readJSON(tempURL)?["hooks"] as? [String: Any]
        let entries = hooks?["UserPromptSubmit"] as? [[String: Any]]
        t.check(commands(in: entries) == ["echo before", "\(newPath) start", "echo after"],
                "replacing our stale entry leaves foreign hooks untouched and in place")
        t.check(entries?.last?["matcher"] as? String == "*", "preserves unrelated keys on foreign entries")
    }
}

test_install_onMissingFile_createsHooksSection()
test_install_isIdempotent()
test_install_preservesUnrelatedExistingSettings()
test_install_replacesOurEntryWhenNotifierPathChanges()
test_install_leavesForeignHooksUntouchedWhenReplacing()

t.finish()
