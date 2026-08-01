import Foundation
import HookNotifyCore

let socketPath = NSHomeDirectory() + "/Library/Application Support/ThinkingCaps/ctl.sock"

let action = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
guard action == "start" || action == "stop" else {
    exit(0)
}

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
guard let sessionID = HookPayload.extractSessionID(from: stdinData) else {
    exit(0)
}

SocketSender.send("\(action) \(sessionID)", toUnixSocketPath: socketPath)
exit(0)
