import Foundation
import MiniTest
import ThinkingCapsCore
import ThinkingCapsTestSupport

let t = MiniTest()

func makeServer(interval: TimeInterval = 0.02) -> (HookSocketServer, String) {
    let device = FakeCapsLockLEDDevice()
    let blinker = Blinker(device: device, interval: interval)
    let socketPath = NSTemporaryDirectory() + UUID().uuidString + ".sock"
    let server = HookSocketServer(socketPath: socketPath, blinker: blinker)
    return (server, socketPath)
}

func test_startMessage_startsBlinkerWhenFirstSession() {
    let (server, _) = makeServer()
    server.setEnabled(true)
    server.handle(.start("session-1"))
    t.check(server.isBlinking, "start message starts blinker when first session")
}

func test_stopMessage_stopsBlinkerWhenLastSessionEnds() {
    let (server, _) = makeServer()
    server.setEnabled(true)
    server.handle(.start("session-1"))
    server.handle(.stop("session-1"))
    t.check(!server.isBlinking, "stop message stops blinker when last session ends")
}

func test_secondSessionKeepsBlinkingAfterFirstStops() {
    let (server, _) = makeServer()
    server.setEnabled(true)
    server.handle(.start("session-1"))
    server.handle(.start("session-2"))
    server.handle(.stop("session-1"))
    t.check(server.isBlinking, "second session keeps blinking after first stops")
}

func test_disabled_ignoresMessages() {
    let (server, _) = makeServer()
    server.setEnabled(false)
    server.handle(.start("session-1"))
    t.check(!server.isBlinking, "disabled server ignores messages")
}

func test_parse_recognizesStartAndStop() {
    t.check(HookSocketServer.parse("start abc") == .start("abc"), "parse recognizes start")
    t.check(HookSocketServer.parse("stop abc") == .stop("abc"), "parse recognizes stop")
    t.check(HookSocketServer.parse("garbage") == nil, "parse rejects garbage")
}

/// Sends one line over the server's socket from a separate process, the way a
/// real hook invocation does, and waits for that process to exit.
func sendLine(_ line: String, to socketPath: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
    process.arguments = ["-U", "-w", "1", socketPath]
    let input = Pipe()
    process.standardInput = input
    do {
        try process.run()
    } catch {
        return false
    }
    input.fileHandleForWriting.write(line.data(using: .utf8)!)
    input.fileHandleForWriting.closeFile()
    process.waitUntilExit()
    return true
}

func test_realSocket_deliversStartMessageFromExternalProcess() {
    let (server, socketPath) = makeServer()
    server.setEnabled(true)
    do {
        try server.start()
    } catch {
        t.check(false, "server.start() threw: \(error)")
        return
    }
    defer { server.stop() }

    guard sendLine("start session-1\n", to: socketPath) else {
        t.check(false, "failed to launch nc")
        return
    }

    Thread.sleep(forTimeInterval: 0.2)
    t.check(server.isBlinking, "real socket delivers start message from external process")
}

func test_idleClient_doesNotWedgeTheAcceptLoop() {
    let (server, socketPath) = makeServer()
    server.setEnabled(true)
    do {
        try server.start()
    } catch {
        t.check(false, "server.start() threw: \(error)")
        return
    }
    defer { server.stop() }

    // A client that connects and then says nothing, holding the connection open.
    let idleClient = Process()
    idleClient.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
    idleClient.arguments = ["-U", socketPath]
    let idleInput = Pipe()
    idleClient.standardInput = idleInput
    do {
        try idleClient.run()
    } catch {
        t.check(false, "failed to launch idle nc: \(error)")
        return
    }
    defer {
        idleClient.terminate()
        idleInput.fileHandleForWriting.closeFile()
    }
    Thread.sleep(forTimeInterval: 0.2)

    guard sendLine("start session-1\n", to: socketPath) else {
        t.check(false, "failed to launch nc")
        return
    }

    Thread.sleep(forTimeInterval: 0.2)
    t.check(server.isBlinking, "a silent client does not block later clients from being served")
}

test_startMessage_startsBlinkerWhenFirstSession()
test_stopMessage_stopsBlinkerWhenLastSessionEnds()
test_secondSessionKeepsBlinkingAfterFirstStops()
test_disabled_ignoresMessages()
test_parse_recognizesStartAndStop()
test_realSocket_deliversStartMessageFromExternalProcess()
test_idleClient_doesNotWedgeTheAcceptLoop()

t.finish()
