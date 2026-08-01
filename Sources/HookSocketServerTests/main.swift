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

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
    process.arguments = ["-U", "-w", "1", socketPath]
    let input = Pipe()
    process.standardInput = input
    do {
        try process.run()
    } catch {
        t.check(false, "failed to launch nc: \(error)")
        return
    }
    input.fileHandleForWriting.write("start session-1\n".data(using: .utf8)!)
    input.fileHandleForWriting.closeFile()
    process.waitUntilExit()

    Thread.sleep(forTimeInterval: 0.2)
    t.check(server.isBlinking, "real socket delivers start message from external process")
}

test_startMessage_startsBlinkerWhenFirstSession()
test_stopMessage_stopsBlinkerWhenLastSessionEnds()
test_secondSessionKeepsBlinkingAfterFirstStops()
test_disabled_ignoresMessages()
test_parse_recognizesStartAndStop()
test_realSocket_deliversStartMessageFromExternalProcess()

t.finish()
