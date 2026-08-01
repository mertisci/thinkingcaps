// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThinkingCaps",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LEDSpike"),
        .target(name: "MiniTest"),
        .target(name: "ThinkingCapsCore"),
        .executableTarget(name: "SessionTrackerTests", dependencies: ["ThinkingCapsCore", "MiniTest"]),
        .target(name: "ThinkingCapsTestSupport", dependencies: ["ThinkingCapsCore"]),
        .executableTarget(name: "BlinkerTests", dependencies: ["ThinkingCapsCore", "ThinkingCapsTestSupport", "MiniTest"]),
        .executableTarget(name: "HookSocketServerTests", dependencies: ["ThinkingCapsCore", "ThinkingCapsTestSupport", "MiniTest"]),
        .executableTarget(name: "ClaudeHookInstallerTests", dependencies: ["ThinkingCapsCore", "MiniTest"]),
        .target(name: "HookNotifyCore"),
        .executableTarget(name: "HookNotify", dependencies: ["HookNotifyCore"]),
        .executableTarget(name: "PayloadParsingTests", dependencies: ["HookNotifyCore", "MiniTest"]),
        .executableTarget(name: "ThinkingCaps", dependencies: ["ThinkingCapsCore"]),
    ]
)
