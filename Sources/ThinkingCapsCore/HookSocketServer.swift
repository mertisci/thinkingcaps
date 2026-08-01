import Foundation
#if canImport(Darwin)
import Darwin
#endif

public final class HookSocketServer {
    public enum Message: Equatable {
        case start(String)
        case stop(String)
    }

    private let socketPath: String
    private let blinker: Blinker
    private var listenFD: Int32 = -1
    private var isRunning = false
    private var tracker = SessionTracker()
    private var isEnabled = true
    private var purgeTimer: DispatchSourceTimer?
    private let stateQueue = DispatchQueue(label: "com.thinkingcaps.hooksocketserver.state")

    public init(socketPath: String, blinker: Blinker) {
        self.socketPath = socketPath
        self.blinker = blinker
    }

    public var isBlinking: Bool {
        blinker.isRunning
    }

    public func start() throws {
        unlink(socketPath)

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuffer in
            let dest = rawBuffer.bindMemory(to: CChar.self)
            socketPath.withCString { src in
                strncpy(dest.baseAddress, src, dest.count - 1)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(listenFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        guard listen(listenFD, 8) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        isRunning = true
        DispatchQueue(label: "com.thinkingcaps.hooksocketserver.accept").async { [weak self] in
            self?.acceptLoop()
        }

        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak self] in
            self?.purgeExpiredSessions()
        }
        timer.resume()
        purgeTimer = timer
    }

    public func stop() {
        isRunning = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
        purgeTimer?.cancel()
        purgeTimer = nil
    }

    public func setEnabled(_ enabled: Bool) {
        stateQueue.sync {
            self.isEnabled = enabled
            if !enabled {
                self.tracker = SessionTracker()
                self.blinker.stop()
            }
        }
    }

    public func handle(_ message: Message) {
        stateQueue.sync {
            guard self.isEnabled else { return }
            switch message {
            case .start(let id):
                let wasEmpty = self.tracker.isEmpty
                self.tracker.start(id)
                if wasEmpty {
                    self.blinker.start()
                }
            case .stop(let id):
                self.tracker.stop(id)
                if self.tracker.isEmpty {
                    self.blinker.stop()
                }
            }
        }
    }

    private func purgeExpiredSessions() {
        tracker.purgeExpired()
        if tracker.isEmpty {
            blinker.stop()
        }
    }

    private func acceptLoop() {
        while isRunning {
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else {
                if isRunning { continue } else { return }
            }
            handleClient(clientFD)
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 256)
        var received = [UInt8]()
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            received.append(contentsOf: buffer[0..<n])
        }
        guard let text = String(bytes: received, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            if let message = Self.parse(String(line)) {
                handle(message)
            }
        }
    }

    public static func parse(_ line: String) -> Message? {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let id = String(parts[1])
        switch parts[0] {
        case "start": return .start(id)
        case "stop": return .stop(id)
        default: return nil
        }
    }
}
