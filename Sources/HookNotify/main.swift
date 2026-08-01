import Foundation
import HookNotifyCore
#if canImport(Darwin)
import Darwin
#endif

// Never let a write to a closed socket kill this process with SIGPIPE.
// A Claude Code hook must always reach exit(0), no matter what.
signal(SIGPIPE, SIG_IGN)

let socketPath = NSHomeDirectory() + "/Library/Application Support/ThinkingCaps/ctl.sock"

let action = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
guard action == "start" || action == "stop" else {
    exit(0)
}

guard let stdinData = (try? FileHandle.standardInput.readToEnd()) ?? nil else {
    exit(0)
}
guard let sessionID = HookPayload.extractSessionID(from: stdinData) else {
    exit(0)
}

SocketSender.send("\(action) \(sessionID)", toUnixSocketPath: socketPath)
exit(0)
