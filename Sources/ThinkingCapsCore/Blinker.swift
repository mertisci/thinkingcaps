import Foundation

public final class Blinker {
    private let device: CapsLockLEDDevice
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var isLEDOn = false

    public init(device: CapsLockLEDDevice, interval: TimeInterval = 0.45, queue: DispatchQueue = DispatchQueue(label: "com.thinkingcaps.blinker")) {
        self.device = device
        self.interval = interval
        self.queue = queue
    }

    public var isRunning: Bool { timer != nil }

    public func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.isLEDOn.toggle()
            self.device.setLEDOn(self.isLEDOn)
        }
        timer = t
        t.resume()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        device.setLEDOn(device.realCapsLockIsOn())
    }
}
