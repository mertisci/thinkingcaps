import Foundation
import IOKit
import IOKit.hid
import CoreGraphics

public protocol CapsLockLEDDevice {
    func setLEDOn(_ on: Bool)
    func realCapsLockIsOn() -> Bool
}

public final class IOKitCapsLockLEDDevice: CapsLockLEDDevice {
    /// How long to wait before another re-locate attempt, so a permanently
    /// missing permission (or a machine with no controllable LED) can't make
    /// every blink tick re-enumerate the HID bus.
    private static let relocateThrottle: TimeInterval = 5

    // Must be retained for as long as `device`/`element` are used: releasing it closes the HID
    // connections it opened (via its deinit calling IOHIDManagerClose below), which silently
    // makes every later IOHIDDeviceSetValue call fail with kIOReturnNotOpen.
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var element: IOHIDElement?
    private var lastRelocateAttempt: Date?

    // The blinker queue writes on every tick and the menu bar's enable/disable
    // toggle writes from the main thread; both mutate the cached handles below
    // when a write fails, so serialize the whole write/re-locate path.
    private let lock = NSLock()

    public init() {
        // No lock needed: nothing else can hold a reference yet.
        locateCapsLockElement()
    }

    deinit {
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    private func locateCapsLockElement() {
        releaseManager()
        guard let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone)) as IOHIDManager? else {
            return
        }
        let matchingDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        // Without a successfully opened manager every IOHIDDeviceSetValue below
        // fails with kIOReturnNotOpen, so fail the locate instead of caching
        // handles that can never work.
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return
        }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return
        }
        for candidate in devices {
            let product = IOHIDDeviceGetProperty(candidate, kIOHIDProductKey as CFString) as? String ?? ""
            guard product.localizedCaseInsensitiveContains("Internal Keyboard") else { continue }
            guard let elements = IOHIDDeviceCopyMatchingElements(candidate, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
                continue
            }
            if let capsElement = elements.first(where: {
                IOHIDElementGetUsagePage($0) == kHIDPage_LEDs && IOHIDElementGetUsage($0) == kHIDUsage_LED_CapsLock
            }) {
                self.manager = manager
                device = candidate
                element = capsElement
                return
            }
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func releaseManager() {
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        device = nil
        element = nil
    }

    public func setLEDOn(_ on: Bool) {
        lock.lock()
        defer { lock.unlock() }

        if write(on) { return }
        // The HID connection can be invalidated underneath us — sleep/wake
        // re-enumeration, a HID reset, or Input Monitoring granted after the
        // handles were cached at launch. Every write then fails silently and the
        // LED never blinks again until the app is relaunched, so re-locate the
        // device and retry the write once (throttled by relocateIfDue).
        guard relocateIfDue() else { return }
        _ = write(on)
    }

    /// Returns true when the LED write was accepted by IOKit.
    private func write(_ on: Bool) -> Bool {
        guard let device, let element else { return false }
        let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, on ? 1 : 0)
        return IOHIDDeviceSetValue(device, element, value) == kIOReturnSuccess
    }

    /// Re-runs the locate routine unless one was attempted too recently.
    /// Returns true when usable handles are cached afterwards.
    private func relocateIfDue() -> Bool {
        let now = Date()
        if let lastRelocateAttempt, now.timeIntervalSince(lastRelocateAttempt) < Self.relocateThrottle {
            return false
        }
        lastRelocateAttempt = now
        locateCapsLockElement()
        return element != nil
    }

    public func realCapsLockIsOn() -> Bool {
        CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
    }
}
