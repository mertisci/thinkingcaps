import Foundation
import IOKit
import IOKit.hid
import CoreGraphics

public protocol CapsLockLEDDevice {
    func setLEDOn(_ on: Bool)
    func realCapsLockIsOn() -> Bool
}

public final class IOKitCapsLockLEDDevice: CapsLockLEDDevice {
    // Must be retained for as long as `device`/`element` are used: releasing it closes the HID
    // connections it opened (via its deinit calling IOHIDManagerClose below), which silently
    // makes every later IOHIDDeviceSetValue call fail with kIOReturnNotOpen.
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var element: IOHIDElement?

    public init() {
        locateCapsLockElement()
    }

    deinit {
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    private func locateCapsLockElement() {
        guard let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone)) as IOHIDManager? else {
            return
        }
        let matchingDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
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
    }

    public func setLEDOn(_ on: Bool) {
        guard let device, let element else { return }
        let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, on ? 1 : 0)
        IOHIDDeviceSetValue(device, element, value)
    }

    public func realCapsLockIsOn() -> Bool {
        CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
    }
}
