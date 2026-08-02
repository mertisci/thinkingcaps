import Foundation

public final class Blinker {
    private let devices: [CapsLockLEDDevice]
    private var interval: TimeInterval
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var isLEDOn = false

    public convenience init(device: CapsLockLEDDevice, interval: TimeInterval = 0.45, queue: DispatchQueue = DispatchQueue(label: "com.thinkingcaps.blinker")) {
        self.init(devices: [device], interval: interval, queue: queue)
    }

    public init(devices: [CapsLockLEDDevice], interval: TimeInterval = 0.45, queue: DispatchQueue = DispatchQueue(label: "com.thinkingcaps.blinker")) {
        self.devices = devices
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
            for device in self.devices {
                device.setLEDOn(self.isLEDOn)
            }
        }
        timer = t
        t.resume()
    }

    public func setInterval(_ newInterval: TimeInterval) {
        interval = newInterval
        // Rescheduling an active DispatchSourceTimer updates its cadence live;
        // safe to call whether or not the blinker is currently running.
        timer?.schedule(deadline: .now() + newInterval, repeating: newInterval)
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        for device in devices {
            device.setLEDOn(device.realCapsLockIsOn())
        }
    }
}
