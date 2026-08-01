import Foundation

public struct ClaudeHookInstaller {
    public let settingsURL: URL

    public init(settingsURL: URL) {
        self.settingsURL = settingsURL
    }

    public func install(notifierPath: String) throws {
        var root = try readSettings()
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]

        hooks["UserPromptSubmit"] = mergedEntries(
            existing: hooks["UserPromptSubmit"],
            command: "\(notifierPath) start"
        )
        hooks["Stop"] = mergedEntries(
            existing: hooks["Stop"],
            command: "\(notifierPath) stop"
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

    private func mergedEntries(existing: Any?, command: String) -> [[String: Any]] {
        var entries = (existing as? [[String: Any]]) ?? []

        let alreadyPresent = entries.contains { entry in
            guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return innerHooks.contains { ($0["command"] as? String) == command }
        }
        if alreadyPresent {
            return entries
        }

        entries.append([
            "hooks": [
                ["type": "command", "command": command]
            ]
        ])
        return entries
    }
}
