import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum SocketSender {
    @discardableResult
    public static func send(_ message: String, toUnixSocketPath path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuffer in
            let dest = rawBuffer.bindMemory(to: CChar.self)
            path.withCString { src in
                strncpy(dest.baseAddress, src, dest.count - 1)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return false }

        let data = Array((message + "\n").utf8)
        let written = data.withUnsafeBufferPointer { buf -> Int in
            write(fd, buf.baseAddress, buf.count)
        }
        return written == data.count
    }
}
