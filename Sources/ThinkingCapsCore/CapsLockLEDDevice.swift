import Foundation
import IOKit
import IOKit.hid

public protocol CapsLockLEDDevice {
    func setLEDOn(_ on: Bool)
    func realCapsLockIsOn() -> Bool
}

public final class IOKitCapsLockLEDDevice: CapsLockLEDDevice {
    private var device: IOHIDDevice?
    private var element: IOHIDElement?

    public init() {
        locateCapsLockElement()
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
            guard let elements = IOHIDDeviceCopyMatchingElements(candidate, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
                continue
            }
            if let capsElement = elements.first(where: {
                IOHIDElementGetUsagePage($0) == kHIDPage_LEDs && IOHIDElementGetUsage($0) == kHIDUsage_LED_CapsLock
            }) {
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
        guard let device, let element else { return false }
        let valuePointer = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
        defer { valuePointer.deallocate() }
        guard IOHIDDeviceGetValue(device, element, valuePointer) == kIOReturnSuccess else {
            return false
        }
        let value = valuePointer.pointee.takeUnretainedValue()
        return IOHIDValueGetIntegerValue(value) != 0
    }
}
