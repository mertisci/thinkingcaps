import Foundation

/// Blinks every attached output on a shared cadence.
///
/// Threading: all mutable state (`timer`, `interval`, `isLEDOn`) is owned by
/// `queue`, which must be serial. Public entry points hop onto it with
/// `queue.sync`; the timer's event handler already runs there, so it touches
/// state directly — calling `queue.sync` from inside the handler would
/// self-deadlock. Because the handler and the sync blocks are serialized on the
/// same queue, once `stop()` returns the timer is cancelled *and* no tick is
/// still in flight, so the restore write is the last thing the devices see
/// (including on the quit path, where a late tick used to be able to leave the
/// LED lit after exit).
///
/// The blocking dependency is one-way: callers (the main thread via the menu,
/// the hook server's state queue via hook messages) block on `queue`, and
/// nothing running on `queue` ever blocks on them — the device writes are
/// straight IOKit calls, and `MenuBarIconBlinkOutput` hops to the main thread
/// with `async`, not `sync`. So there is no cycle to deadlock on.
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

    public var isRunning: Bool { queue.sync { timer != nil } }

    public func start() {
        queue.sync {
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: interval)
            t.setEventHandler { [weak self] in
                guard let self else { return }
                // Already running on `queue` — touch the state directly.
                self.isLEDOn.toggle()
                for device in self.devices {
                    device.setLEDOn(self.isLEDOn)
                }
            }
            timer = t
            t.resume()
        }
    }

    public func setInterval(_ newInterval: TimeInterval) {
        queue.sync {
            interval = newInterval
            // Rescheduling an active DispatchSourceTimer updates its cadence live;
            // safe to call whether or not the blinker is currently running.
            timer?.schedule(deadline: .now() + newInterval, repeating: newInterval)
        }
    }

    public func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            // Forget the blink phase so the next session's first tick lights the
            // LED instead of starting on a dark frame.
            isLEDOn = false
            for device in devices {
                device.setLEDOn(device.realCapsLockIsOn())
            }
        }
    }
}
