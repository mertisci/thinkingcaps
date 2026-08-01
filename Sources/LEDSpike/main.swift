import Foundation
import IOKit
import IOKit.hid

func findKeyboardDevices() -> [IOHIDDevice] {
    guard let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone)) as IOHIDManager? else {
        return []
    }
    let matchingDict: [String: Any] = [
        kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard
    ]
    IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)
    let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
        print("IOHIDManagerOpen failed (IOReturn \(openResult)). This usually means Input Monitoring permission hasn't been granted.")
        print("Open System Settings > Privacy & Security > Input Monitoring, enable this program, then run this again.")
        return []
    }
    guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
        return []
    }
    return Array(deviceSet)
}

func capsLockLEDElement(on device: IOHIDDevice) -> IOHIDElement? {
    guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
        return nil
    }
    return elements.first {
        IOHIDElementGetUsagePage($0) == kHIDPage_LEDs &&
        IOHIDElementGetUsage($0) == kHIDUsage_LED_CapsLock
    }
}

@discardableResult
func setCapsLockLED(_ device: IOHIDDevice, element: IOHIDElement, on: Bool) -> Bool {
    let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, on ? 1 : 0)
    return IOHIDDeviceSetValue(device, element, value) == kIOReturnSuccess
}

print("ThinkingCaps LED spike: looking for keyboards with a CapsLock LED...")
let devices = findKeyboardDevices()
print("Found \(devices.count) keyboard device(s).")

var found = false
for device in devices {
    guard let element = capsLockLEDElement(on: device) else { continue }
    found = true
    print("Found a CapsLock LED element. Blinking it 6 times (about 3 seconds).")
    print("While this runs: watch the physical CapsLock light. After it ends, press CapsLock once and type a letter to confirm normal typing still works.")
    for i in 0..<6 {
        let on = i % 2 == 0
        let success = setCapsLockLED(device, element: element, on: on)
        print(" toggle \(i + 1)/6 -> \(on ? "ON" : "OFF"): \(success ? "ok" : "FAILED")")
        Thread.sleep(forTimeInterval: 0.5)
    }
    setCapsLockLED(device, element: element, on: false)
}

if !found && devices.count > 0 {
    print("No CapsLock LED element found on any matched keyboard device.")
}
