import Foundation

public struct ClaudeHookInstaller {
    private static let notifierName = "hook-notify"

    public let settingsURL: URL

    public init(settingsURL: URL) {
        self.settingsURL = settingsURL
    }

    public func install(notifierPath: String) throws {
        var root = try readSettings()
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]

        hooks["UserPromptSubmit"] = mergedEntries(
            existing: hooks["UserPromptSubmit"],
            notifierPath: notifierPath,
            action: "start"
        )
        hooks["Stop"] = mergedEntries(
            existing: hooks["Stop"],
            notifierPath: notifierPath,
            action: "stop"
        )

        root["hooks"] = hooks
        try writeSettings(root)
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        let json = try JSONSerialization.jsonObject(with: data)
        return (json as? [String: Any]) ?? [:]
    }

    private func writeSettings(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    /// Merges our hook command into one Claude Code hook event's entry list.
    ///
    /// Ownership is decided by the command's *suffix*, not by an exact match:
    /// anything ending in `/hook-notify <action>` is ours whatever path it points
    /// at. That way moving the app (a source build → the DMG copy in
    /// `/Applications`) repoints the existing entry instead of appending a second
    /// one — a stale entry whose binary has since disappeared would make every
    /// Claude Code prompt run a failing hook command. Everything we don't own is
    /// passed through untouched.
    private func mergedEntries(existing: Any?, notifierPath: String, action: String) -> [[String: Any]] {
        let command = "\(notifierPath) \(action)"
        let ownedSuffix = "/\(Self.notifierName) \(action)"
        let entries = (existing as? [[String: Any]]) ?? []

        var merged = [[String: Any]]()
        var didReplace = false

        for var entry in entries {
            guard let innerHooks = entry["hooks"] as? [[String: Any]] else {
                merged.append(entry)
                continue
            }
            var keptHooks = [[String: Any]]()
            for var hook in innerHooks {
                guard let existingCommand = hook["command"] as? String,
                      existingCommand.hasSuffix(ownedSuffix) else {
                    keptHooks.append(hook)
                    continue
                }
                // Ours: keep the first one, repointed at the current binary. Extra
                // copies are leftovers from installs that predate this rule.
                if didReplace { continue }
                hook["command"] = command
                keptHooks.append(hook)
                didReplace = true
            }
            // An entry that held nothing but stale copies of ours goes away with them.
            if keptHooks.isEmpty && !innerHooks.isEmpty { continue }
            entry["hooks"] = keptHooks
            merged.append(entry)
        }

        if !didReplace {
            merged.append([
                "hooks": [
                    ["type": "command", "command": command]
                ]
            ])
        }
        return merged
    }
}
