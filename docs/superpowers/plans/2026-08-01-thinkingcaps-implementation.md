# ThinkingCaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build ThinkingCaps, a macOS menu bar app that blinks the built-in CapsLock LED while Claude Code is processing a request in the terminal, packaged as an unsigned DMG and published to a public GitHub repo.

**Architecture:** A Swift Package Manager project with a small library (`ThinkingCapsCore`) holding all logic (session tracking, LED control, socket server, hook installer, launch-at-login, status bar UI), a thin `ThinkingCaps` executable that wires it into an `NSApplication`, and a separate `HookNotify` helper binary that Claude Code's hooks invoke to signal start/stop over a local unix socket. A standalone `LEDSpike` diagnostic tool validates the riskiest assumption (direct LED control) before the rest is built.

**Tech Stack:** Swift 5.9, Swift Package Manager, AppKit, IOKit (HID), ServiceManagement (`SMAppService`), Foundation/Darwin raw sockets, a small hand-rolled `MiniTest` assertion helper (see Global Constraints — this machine has no XCTest).

## Global Constraints

- Platform: macOS 13.0 (Ventura) or later — required for `SMAppService`.
- No Xcode project file — pure Swift Package Manager, no third-party dependencies.
- All source code, comments, UI strings, docs, and repo content are in English.
- Left-click on the menu bar icon only toggles On/Off — no dropdown menu on left-click. Right-click is the only place a menu appears, containing exactly "Launch at Login" and "Quit ThinkingCaps".
- The physical CapsLock key's real typing behavior (uppercase/lowercase) must never be affected by our code — we only ever set/read the LED value, never the modifier state.
- Every Claude Code hook command must exit 0 unconditionally and never block or slow down Claude Code, even if ThinkingCaps isn't running or errors internally.
- Distribution for v1: ad-hoc codesign only (unsigned), public GitHub repo, MIT license.
- **Testing:** this machine has only Command Line Tools installed, not full Xcode — `XCTest`/`swift test` do not work here (confirmed directly: `unable to resolve module dependency: 'XCTest'`). Every task that needs tests uses a plain `.executableTarget` and the small `MiniTest` helper (introduced in Task 2, `Sources/MiniTest/MiniTest.swift`) instead of `.testTarget`/`XCTest`. Tests are run with `swift run <TargetName>` (e.g. `swift run SessionTrackerTests`), not `swift test`. Because there's no `@testable import`, anything a test target needs to call on `ThinkingCapsCore` must be `public`, and shared test doubles (like `FakeCapsLockLEDDevice`) live in their own small library target (`ThinkingCapsTestSupport`) so more than one test executable can import them.

---

### Task 1: Repo scaffold + CapsLock LED diagnostic spike

This is the highest-risk task in the whole project: it determines whether direct LED control is even possible on this Mac before any other code is written.

**Files:**
- Create: `.gitignore`
- Create: `Package.swift`
- Create: `Sources/LEDSpike/main.swift`

**Interfaces:**
- Produces: nothing consumed by later tasks (this target is a standalone diagnostic, not linked into the app).

- [ ] **Step 1: Create `.gitignore`**

```
.build/
*.dmg
.DS_Store
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThinkingCaps",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LEDSpike"),
    ]
)
```

- [ ] **Step 3: Write the LED spike program**

Create `Sources/LEDSpike/main.swift`:

```swift
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
    IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
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
    guard let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, on ? 1 : 0) else {
        return false
    }
    return IOHIDDeviceSetValue(device, element, value) == kIOReturnSuccess
}

print("ThinkingCaps LED spike: looking for keyboards with a CapsLock LED...")
let devices = findKeyboardDevices()
print("Found \(devices.count) keyboard device(s).")

var found = false
for device in devices {
    guard let element = capsLockLEDElement(on: device) else { continue }
    found = true
    print("Found a CapsLock LED element. Blinking it 6 times (about 5 seconds).")
    print("While this runs: watch the physical CapsLock light. After it ends, press CapsLock once and type a letter to confirm normal typing still works.")
    for i in 0..<6 {
        let on = i % 2 == 0
        let success = setCapsLockLED(device, element: element, on: on)
        print(" toggle \(i + 1)/6 -> \(on ? "ON" : "OFF"): \(success ? "ok" : "FAILED")")
        Thread.sleep(forTimeInterval: 0.5)
    }
    setCapsLockLED(device, element: element, on: false)
}

if !found {
    print("No CapsLock LED element found on any matched keyboard device. This likely means direct LED control isn't available on this Mac — report this back so we can switch to the menu-bar-icon fallback.")
}
```

- [ ] **Step 4: Build and run it**

Run: `swift build && swift run LEDSpike`

Watch the physical CapsLock LED while it runs. After it finishes, press the physical CapsLock key once and type a letter to confirm case-typing still works normally.

- [ ] **Step 5: Report the result before continuing**

**STOP HERE and confirm with the user:**
- Did the LED visibly blink 6 times?
- Did any permission prompt appear (e.g. Input Monitoring)? If so, what happened when it was granted/denied?
- Did CapsLock's real typing behavior still work correctly afterward?

If the LED did **not** blink, or CapsLock typing broke, do not proceed to Task 3 (Blinker/IOKit device) as designed — pause and revisit the design's fallback (blink the menu bar icon instead of the physical LED) with the user before continuing.

- [ ] **Step 6: Commit**

```bash
git add .gitignore Package.swift Sources/LEDSpike/main.swift
git commit -m "Add CapsLock LED diagnostic spike"
```

---

### Task 2: MiniTest helper + SessionTracker (pure logic, TDD)

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MiniTest/MiniTest.swift`
- Create: `Sources/ThinkingCapsCore/SessionTracker.swift`
- Test: `Sources/SessionTrackerTests/main.swift`

**Interfaces:**
- Produces: `public final class MiniTest` with `public init()`, `public func check(_ condition: @autoclosure () -> Bool, _ description: String)`, `public func finish() -> Never`. Used by every later test executable (Tasks 3, 4, 5, 6).
- Produces: `struct SessionTracker` with `init(timeout: TimeInterval = 600)`, `var isEmpty: Bool`, `mutating func start(_ id: String, now: Date = Date())`, `mutating func stop(_ id: String)`, `mutating func purgeExpired(now: Date = Date())`. Used by Task 4 (`HookSocketServer`).

- [ ] **Step 1: Expand `Package.swift` to add the core library, the MiniTest helper, and the test executable**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThinkingCaps",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LEDSpike"),
        .target(name: "MiniTest"),
        .target(name: "ThinkingCapsCore"),
        .executableTarget(name: "SessionTrackerTests", dependencies: ["ThinkingCapsCore", "MiniTest"]),
    ]
)
```

- [ ] **Step 2: Write the MiniTest helper**

This machine has no XCTest (see Global Constraints), so every test in this plan is a plain executable using this tiny helper instead. Create `Sources/MiniTest/MiniTest.swift`:

```swift
import Foundation

public final class MiniTest {
    private var failureCount = 0
    private var totalCount = 0

    public init() {}

    public func check(_ condition: @autoclosure () -> Bool, _ description: String) {
        totalCount += 1
        if condition() {
            print("PASS: \(description)")
        } else {
            failureCount += 1
            print("FAIL: \(description)")
        }
    }

    public func finish() -> Never {
        print("\(totalCount - failureCount)/\(totalCount) passed")
        exit(failureCount == 0 ? 0 : 1)
    }
}
```

- [ ] **Step 3: Write the failing tests**

Create `Sources/SessionTrackerTests/main.swift`:

```swift
import Foundation
import MiniTest
import ThinkingCapsCore

let t = MiniTest()

func test_newTracker_isEmpty() {
    let tracker = SessionTracker()
    t.check(tracker.isEmpty, "new tracker is empty")
}

func test_start_makesTrackerNonEmpty() {
    var tracker = SessionTracker()
    tracker.start("session-1")
    t.check(!tracker.isEmpty, "start makes tracker non-empty")
}

func test_stop_removesSession() {
    var tracker = SessionTracker()
    tracker.start("session-1")
    tracker.stop("session-1")
    t.check(tracker.isEmpty, "stop removes session")
}

func test_stop_onlyRemovesMatchingSession() {
    var tracker = SessionTracker()
    tracker.start("session-1")
    tracker.start("session-2")
    tracker.stop("session-1")
    t.check(!tracker.isEmpty, "stop only removes matching session")
}

func test_purgeExpired_removesSessionsOlderThanTimeout() {
    var tracker = SessionTracker(timeout: 600)
    let start = Date(timeIntervalSince1970: 0)
    tracker.start("stale-session", now: start)
    tracker.purgeExpired(now: start.addingTimeInterval(601))
    t.check(tracker.isEmpty, "purgeExpired removes sessions older than timeout")
}

func test_purgeExpired_keepsSessionsWithinTimeout() {
    var tracker = SessionTracker(timeout: 600)
    let start = Date(timeIntervalSince1970: 0)
    tracker.start("fresh-session", now: start)
    tracker.purgeExpired(now: start.addingTimeInterval(300))
    t.check(!tracker.isEmpty, "purgeExpired keeps sessions within timeout")
}

test_newTracker_isEmpty()
test_start_makesTrackerNonEmpty()
test_stop_removesSession()
test_stop_onlyRemovesMatchingSession()
test_purgeExpired_removesSessionsOlderThanTimeout()
test_purgeExpired_keepsSessionsWithinTimeout()

t.finish()
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `swift run SessionTrackerTests`
Expected: FAIL to compile — `SessionTracker` doesn't exist yet.

- [ ] **Step 5: Implement `SessionTracker`**

Create `Sources/ThinkingCapsCore/SessionTracker.swift`:

```swift
import Foundation

public struct SessionTracker {
    private var startedAt: [String: Date] = [:]
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 600) {
        self.timeout = timeout
    }

    public var isEmpty: Bool { startedAt.isEmpty }

    public mutating func start(_ id: String, now: Date = Date()) {
        startedAt[id] = now
    }

    public mutating func stop(_ id: String) {
        startedAt.removeValue(forKey: id)
    }

    public mutating func purgeExpired(now: Date = Date()) {
        startedAt = startedAt.filter { now.timeIntervalSince($0.value) < timeout }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift run SessionTrackerTests`
Expected: prints six `PASS:` lines, then `6/6 passed`, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/MiniTest/MiniTest.swift Sources/ThinkingCapsCore/SessionTracker.swift Sources/SessionTrackerTests/main.swift
git commit -m "Add MiniTest helper and SessionTracker with expiry"
```

---

### Task 3: CapsLockLEDDevice protocol + Blinker + IOKitCapsLockLEDDevice

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ThinkingCapsCore/CapsLockLEDDevice.swift`
- Create: `Sources/ThinkingCapsCore/Blinker.swift`
- Create: `Sources/ThinkingCapsTestSupport/FakeCapsLockLEDDevice.swift`
- Test: `Sources/BlinkerTests/main.swift`

**Interfaces:**
- Consumes: the IOKit HID pattern validated in Task 1's `LEDSpike`. Consumes `MiniTest` (Task 2).
- Produces: `public protocol CapsLockLEDDevice { func setLEDOn(_ on: Bool); func realCapsLockIsOn() -> Bool }`; `public final class IOKitCapsLockLEDDevice: CapsLockLEDDevice` with `public init()`; `public final class Blinker` with `init(device: CapsLockLEDDevice, interval: TimeInterval = 0.45, queue: DispatchQueue = DispatchQueue(label: "com.thinkingcaps.blinker"))`, `var isRunning: Bool`, `func start()`, `func stop()`. Used by Task 4 (`HookSocketServer`) and Task 9 (`AppDelegate`).
- Produces: `public final class FakeCapsLockLEDDevice: CapsLockLEDDevice` (in the new `ThinkingCapsTestSupport` target) with `public init()`, `public private(set) var calls: [Bool]`, `public var realStateToReturn: Bool`. This is a shared test double — Task 4's `HookSocketServerTests` also imports `ThinkingCapsTestSupport` and reuses it; do not redefine it there.

- [ ] **Step 1: Expand `Package.swift` to add `ThinkingCapsTestSupport` and the `BlinkerTests` executable**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThinkingCaps",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LEDSpike"),
        .target(name: "MiniTest"),
        .target(name: "ThinkingCapsCore"),
        .executableTarget(name: "SessionTrackerTests", dependencies: ["ThinkingCapsCore", "MiniTest"]),
        .target(name: "ThinkingCapsTestSupport", dependencies: ["ThinkingCapsCore"]),
        .executableTarget(name: "BlinkerTests", dependencies: ["ThinkingCapsCore", "ThinkingCapsTestSupport", "MiniTest"]),
    ]
)
```

- [ ] **Step 2: Write the shared fake LED device**

Create `Sources/ThinkingCapsTestSupport/FakeCapsLockLEDDevice.swift`:

```swift
import ThinkingCapsCore

public final class FakeCapsLockLEDDevice: CapsLockLEDDevice {
    public private(set) var calls: [Bool] = []
    public var realStateToReturn = false

    public init() {}

    public func setLEDOn(_ on: Bool) {
        calls.append(on)
    }

    public func realCapsLockIsOn() -> Bool {
        realStateToReturn
    }
}
```

- [ ] **Step 3: Write the failing tests**

Create `Sources/BlinkerTests/main.swift`:

```swift
import Foundation
import MiniTest
import ThinkingCapsCore
import ThinkingCapsTestSupport

let t = MiniTest()

func test_start_beginsTogglingLED() {
    let device = FakeCapsLockLEDDevice()
    let blinker = Blinker(device: device, interval: 0.02)
    blinker.start()
    Thread.sleep(forTimeInterval: 0.15)
    blinker.stop()
    t.check(device.calls.count >= 2, "start begins toggling LED")
}

func test_stop_setsLEDToRealCapsLockState() {
    let device = FakeCapsLockLEDDevice()
    device.realStateToReturn = true
    let blinker = Blinker(device: device, interval: 0.02)
    blinker.start()
    blinker.stop()
    t.check(device.calls.last == true, "stop sets LED to real CapsLock state")
}

func test_isRunning_reflectsState() {
    let device = FakeCapsLockLEDDevice()
    let blinker = Blinker(device: device, interval: 0.02)
    t.check(!blinker.isRunning, "not running before start")
    blinker.start()
    t.check(blinker.isRunning, "running after start")
    blinker.stop()
    t.check(!blinker.isRunning, "not running after stop")
}

func test_start_isIdempotent() {
    let device = FakeCapsLockLEDDevice()
    let blinker = Blinker(device: device, interval: 0.02)
    blinker.start()
    blinker.start()
    t.check(blinker.isRunning, "still running after double start")
    blinker.stop()
}

test_start_beginsTogglingLED()
test_stop_setsLEDToRealCapsLockState()
test_isRunning_reflectsState()
test_start_isIdempotent()

t.finish()
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `swift run BlinkerTests`
Expected: FAIL to compile — `CapsLockLEDDevice` and `Blinker` don't exist yet.

- [ ] **Step 5: Implement the protocol and the real IOKit-backed device**

Create `Sources/ThinkingCapsCore/CapsLockLEDDevice.swift`:

```swift
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
        var valueRef: Unmanaged<IOHIDValue>?
        guard IOHIDDeviceGetValue(device, element, &valueRef) == kIOReturnSuccess,
              let value = valueRef?.takeRetainedValue() else {
            return false
        }
        return IOHIDValueGetIntegerValue(value) != 0
    }
}
```

**Note:** `IOHIDManagerOpen` above discards its return value, same as the very first version of Task 1's `LEDSpike` did before its fix round. This is deliberate here, not a repeat of that bug: `IOKitCapsLockLEDDevice` fails silently (no element found → `setLEDOn`/`realCapsLockIsOn` become no-ops) if Input Monitoring permission isn't granted, which is exactly the safe, non-crashing degradation this class needs in production — there's no user to print a diagnostic message to. The README (Task 12) documents the permission requirement instead.

- [ ] **Step 6: Implement `Blinker`**

Create `Sources/ThinkingCapsCore/Blinker.swift`:

```swift
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
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift run BlinkerTests`
Expected: prints four `PASS:` lines, then `4/4 passed`, exit code 0.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/ThinkingCapsCore/CapsLockLEDDevice.swift Sources/ThinkingCapsCore/Blinker.swift Sources/ThinkingCapsTestSupport/FakeCapsLockLEDDevice.swift Sources/BlinkerTests/main.swift
git commit -m "Add CapsLockLEDDevice protocol, IOKit implementation, and Blinker"
```

---

### Task 4: HookSocketServer

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ThinkingCapsCore/HookSocketServer.swift`
- Test: `Sources/HookSocketServerTests/main.swift`

**Interfaces:**
- Consumes: `SessionTracker` (Task 2), `Blinker` (Task 3) — exact signatures as produced there. Also reuses `FakeCapsLockLEDDevice` from the `ThinkingCapsTestSupport` target (Task 3) — do not redefine it, just `import ThinkingCapsTestSupport`.
- Produces: `public final class HookSocketServer` with `init(socketPath: String, blinker: Blinker)`, `func start() throws`, `func stop()`, `func setEnabled(_ enabled: Bool)`, `var isBlinking: Bool { get }`. `public enum Message: Equatable { case start(String); case stop(String) }`, `public static func parse(_ line: String) -> Message?`, `public func handle(_ message: Message)` — these three are `public` (not merely internal) specifically because there's no `@testable import` available in this project (see Global Constraints); the test executable calls them directly via a normal `import ThinkingCapsCore`. Used by Task 8 (`StatusItemController`) and Task 9 (`AppDelegate`).

- [ ] **Step 1: Expand `Package.swift` to add the `HookSocketServerTests` executable**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThinkingCaps",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LEDSpike"),
        .target(name: "MiniTest"),
        .target(name: "ThinkingCapsCore"),
        .executableTarget(name: "SessionTrackerTests", dependencies: ["ThinkingCapsCore", "MiniTest"]),
        .target(name: "ThinkingCapsTestSupport", dependencies: ["ThinkingCapsCore"]),
        .executableTarget(name: "BlinkerTests", dependencies: ["ThinkingCapsCore", "ThinkingCapsTestSupport", "MiniTest"]),
        .executableTarget(name: "HookSocketServerTests", dependencies: ["ThinkingCapsCore", "ThinkingCapsTestSupport", "MiniTest"]),
    ]
)
```

- [ ] **Step 2: Write the failing tests**

Create `Sources/HookSocketServerTests/main.swift`:

```swift
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
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift run HookSocketServerTests`
Expected: FAIL to compile — `HookSocketServer` doesn't exist yet.

- [ ] **Step 4: Implement `HookSocketServer`**

Create `Sources/ThinkingCapsCore/HookSocketServer.swift`:

```swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift run HookSocketServerTests`
Expected: prints six `PASS:` lines, then `6/6 passed`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ThinkingCapsCore/HookSocketServer.swift Sources/HookSocketServerTests/main.swift
git commit -m "Add HookSocketServer with session tracking and blink orchestration"
```

---

### Task 5: ClaudeHookInstaller

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ThinkingCapsCore/ClaudeHookInstaller.swift`
- Test: `Sources/ClaudeHookInstallerTests/main.swift`

**Interfaces:**
- Produces: `public struct ClaudeHookInstaller { public let settingsURL: URL; public init(settingsURL: URL); public func install(notifierPath: String) throws }`. Used by Task 9 (`AppDelegate`).

- [ ] **Step 1: Expand `Package.swift` to add the `ClaudeHookInstallerTests` executable**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThinkingCaps",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LEDSpike"),
        .target(name: "MiniTest"),
        .target(name: "ThinkingCapsCore"),
        .executableTarget(name: "SessionTrackerTests", dependencies: ["ThinkingCapsCore", "MiniTest"]),
        .target(name: "ThinkingCapsTestSupport", dependencies: ["ThinkingCapsCore"]),
        .executableTarget(name: "BlinkerTests", dependencies: ["ThinkingCapsCore", "ThinkingCapsTestSupport", "MiniTest"]),
        .executableTarget(name: "HookSocketServerTests", dependencies: ["ThinkingCapsCore", "ThinkingCapsTestSupport", "MiniTest"]),
        .executableTarget(name: "ClaudeHookInstallerTests", dependencies: ["ThinkingCapsCore", "MiniTest"]),
    ]
)
```

- [ ] **Step 2: Write the failing tests**

Create `Sources/ClaudeHookInstallerTests/main.swift`:

```swift
import Foundation
import MiniTest
import ThinkingCapsCore

let t = MiniTest()

func withTempSettingsURL(_ body: (URL) -> Void) {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    body(tempURL)
    try? FileManager.default.removeItem(at: tempURL)
}

func readJSON(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

func test_install_onMissingFile_createsHooksSection() {
    withTempSettingsURL { tempURL in
        let installer = ClaudeHookInstaller(settingsURL: tempURL)
        do {
            try installer.install(notifierPath: "/Applications/ThinkingCaps.app/Contents/MacOS/hook-notify")
        } catch {
            t.check(false, "install threw: \(error)")
            return
        }
        let root = readJSON(tempURL)
        let hooks = root?["hooks"] as? [String: Any]
        t.check(hooks?["UserPromptSubmit"] != nil, "creates UserPromptSubmit hooks section")
        t.check(hooks?["Stop"] != nil, "creates Stop hooks section")
    }
}

func test_install_isIdempotent() {
    withTempSettingsURL { tempURL in
        let installer = ClaudeHookInstaller(settingsURL: tempURL)
        try? installer.install(notifierPath: "/Applications/ThinkingCaps.app/Contents/MacOS/hook-notify")
        try? installer.install(notifierPath: "/Applications/ThinkingCaps.app/Contents/MacOS/hook-notify")

        let root = readJSON(tempURL)
        let hooks = root?["hooks"] as? [String: Any]
        let userPromptEntries = hooks?["UserPromptSubmit"] as? [[String: Any]]
        t.check(userPromptEntries?.count == 1, "install is idempotent (no duplicate entries)")
    }
}

func test_install_preservesUnrelatedExistingSettings() {
    withTempSettingsURL { tempURL in
        let existing: [String: Any] = [
            "someOtherSetting": true,
            "hooks": [
                "PreToolUse": [
                    ["hooks": [["type": "command", "command": "echo hi"]]]
                ]
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: existing) {
            try? data.write(to: tempURL)
        }

        let installer = ClaudeHookInstaller(settingsURL: tempURL)
        try? installer.install(notifierPath: "/Applications/ThinkingCaps.app/Contents/MacOS/hook-notify")

        let root = readJSON(tempURL)
        t.check(root?["someOtherSetting"] as? Bool == true, "preserves unrelated top-level settings")
        let hooks = root?["hooks"] as? [String: Any]
        t.check(hooks?["PreToolUse"] != nil, "preserves existing PreToolUse hooks")
        t.check(hooks?["UserPromptSubmit"] != nil, "adds UserPromptSubmit hooks")
    }
}

test_install_onMissingFile_createsHooksSection()
test_install_isIdempotent()
test_install_preservesUnrelatedExistingSettings()

t.finish()
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift run ClaudeHookInstallerTests`
Expected: FAIL to compile — `ClaudeHookInstaller` doesn't exist yet.

- [ ] **Step 4: Implement `ClaudeHookInstaller`**

Create `Sources/ThinkingCapsCore/ClaudeHookInstaller.swift`:

```swift
import Foundation

public struct ClaudeHookInstaller {
    public let settingsURL: URL

    public init(settingsURL: URL) {
        self.settingsURL = settingsURL
    }

    public func install(notifierPath: String) throws {
        var root = try readSettings()
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]

        hooks["UserPromptSubmit"] = mergedEntries(
            existing: hooks["UserPromptSubmit"],
            command: "\(notifierPath) start"
        )
        hooks["Stop"] = mergedEntries(
            existing: hooks["Stop"],
            command: "\(notifierPath) stop"
        )

        root["hooks"] = hooks
        try writeSettings(root)
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        let json = try JSONSerialization.jsonObject(with: data)
        return (json as? [String: Any]) ?? [:]
    }

    private func writeSettings(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    private func mergedEntries(existing: Any?, command: String) -> [[String: Any]] {
        var entries = (existing as? [[String: Any]]) ?? []

        let alreadyPresent = entries.contains { entry in
            guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return innerHooks.contains { ($0["command"] as? String) == command }
        }
        if alreadyPresent {
            return entries
        }

        entries.append([
            "hooks": [
                ["type": "command", "command": command]
            ]
        ])
        return entries
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift run ClaudeHookInstallerTests`
Expected: prints six `PASS:` lines, then `6/6 passed`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ThinkingCapsCore/ClaudeHookInstaller.swift Sources/ClaudeHookInstallerTests/main.swift
git commit -m "Add ClaudeHookInstaller with idempotent JSON merge"
```

---

### Task 6: HookNotify helper binary

This is the small compiled program the Claude Code hooks actually invoke. It reads the hook's JSON payload from stdin, pulls out `session_id`, and writes `start <id>`/`stop <id>` to ThinkingCaps' unix socket.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/HookNotifyCore/PayloadParsing.swift`
- Create: `Sources/HookNotifyCore/SocketSender.swift`
- Create: `Sources/HookNotify/main.swift`
- Test: `Sources/PayloadParsingTests/main.swift`

**Interfaces:**
- Produces: `public enum HookPayload { public static func extractSessionID(from data: Data) -> String? }`; `public enum SocketSender { @discardableResult public static func send(_ message: String, toUnixSocketPath path: String) -> Bool }`. Not consumed by other Swift code — invoked as a subprocess by the Claude Code hook command that Task 5's `ClaudeHookInstaller` writes, and must write to the same socket path Task 9's `AppDelegate` gives to `HookSocketServer`.

- [ ] **Step 1: Expand `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThinkingCaps",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LEDSpike"),
        .target(name: "MiniTest"),
        .target(name: "ThinkingCapsCore"),
        .executableTarget(name: "SessionTrackerTests", dependencies: ["ThinkingCapsCore", "MiniTest"]),
        .target(name: "ThinkingCapsTestSupport", dependencies: ["ThinkingCapsCore"]),
        .executableTarget(name: "BlinkerTests", dependencies: ["ThinkingCapsCore", "ThinkingCapsTestSupport", "MiniTest"]),
        .executableTarget(name: "HookSocketServerTests", dependencies: ["ThinkingCapsCore", "ThinkingCapsTestSupport", "MiniTest"]),
        .executableTarget(name: "ClaudeHookInstallerTests", dependencies: ["ThinkingCapsCore", "MiniTest"]),
        .target(name: "HookNotifyCore"),
        .executableTarget(name: "HookNotify", dependencies: ["HookNotifyCore"]),
        .executableTarget(name: "PayloadParsingTests", dependencies: ["HookNotifyCore", "MiniTest"]),
    ]
)
```

- [ ] **Step 2: Write the failing tests**

Create `Sources/PayloadParsingTests/main.swift`:

```swift
import Foundation
import MiniTest
import HookNotifyCore

let t = MiniTest()

func test_extractSessionID_fromValidPayload() {
    let json = #"{"session_id": "abc-123", "other_field": true}"#
    let data = json.data(using: .utf8)!
    t.check(HookPayload.extractSessionID(from: data) == "abc-123", "extracts session_id from valid payload")
}

func test_extractSessionID_returnsNilForMissingField() {
    let json = #"{"other_field": true}"#
    let data = json.data(using: .utf8)!
    t.check(HookPayload.extractSessionID(from: data) == nil, "returns nil for missing field")
}

func test_extractSessionID_returnsNilForInvalidJSON() {
    let data = "not json".data(using: .utf8)!
    t.check(HookPayload.extractSessionID(from: data) == nil, "returns nil for invalid JSON")
}

test_extractSessionID_fromValidPayload()
test_extractSessionID_returnsNilForMissingField()
test_extractSessionID_returnsNilForInvalidJSON()

t.finish()
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift run PayloadParsingTests`
Expected: FAIL to compile — `HookPayload` doesn't exist yet.

- [ ] **Step 4: Implement `PayloadParsing` and `SocketSender`**

Create `Sources/HookNotifyCore/PayloadParsing.swift`:

```swift
import Foundation

public enum HookPayload {
    public static func extractSessionID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["session_id"] as? String
    }
}
```

Create `Sources/HookNotifyCore/SocketSender.swift`:

```swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift run PayloadParsingTests`
Expected: prints three `PASS:` lines, then `3/3 passed`, exit code 0.

- [ ] **Step 6: Write the executable entry point**

Create `Sources/HookNotify/main.swift`:

```swift
import Foundation
import HookNotifyCore

let socketPath = NSHomeDirectory() + "/Library/Application Support/ThinkingCaps/ctl.sock"

let action = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
guard action == "start" || action == "stop" else {
    exit(0)
}

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
guard let sessionID = HookPayload.extractSessionID(from: stdinData) else {
    exit(0)
}

SocketSender.send("\(action) \(sessionID)", toUnixSocketPath: socketPath)
exit(0)
```

- [ ] **Step 7: Build it and manually verify against a listening socket**

Run: `swift build`

In one terminal: `nc -lU /tmp/thinkingcaps-test.sock`
In another terminal:

```bash
echo '{"session_id": "manual-test-1"}' | .build/debug/HookNotify start
```

Expected: the `nc -lU` terminal prints `start manual-test-1`, and the `HookNotify` command exits immediately with no output and exit code 0. (This test uses `/tmp/thinkingcaps-test.sock` for convenience — it won't match `HookNotify`'s hardcoded path, so instead run `nc -lU "$HOME/Library/Application Support/ThinkingCaps/ctl.sock"` — create that directory first with `mkdir -p "$HOME/Library/Application Support/ThinkingCaps"` — then repeat the `echo | HookNotify start` command and confirm the message arrives.)

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/HookNotifyCore Sources/HookNotify Sources/PayloadParsingTests
git commit -m "Add HookNotify helper binary"
```

---

### Task 7: LaunchAtLogin

**Files:**
- Create: `Sources/ThinkingCapsCore/LaunchAtLogin.swift`

**Interfaces:**
- Produces: `public protocol LaunchAtLoginControlling: AnyObject { var isEnabled: Bool { get }; func setEnabled(_ enabled: Bool) }`; `public final class LaunchAtLogin: LaunchAtLoginControlling` with `public init()`. Used by Task 8 (`StatusItemController`) and Task 9 (`AppDelegate`).

This wraps `SMAppService`, which registers a real login item — there's no safe way to unit test it without actually changing the user's login items, so this task is verified manually once the full app is running (Task 9's manual check covers it: confirm the checkbox in the right-click menu reflects System Settings > General > Login Items).

- [ ] **Step 1: Implement `LaunchAtLogin`**

Create `Sources/ThinkingCapsCore/LaunchAtLogin.swift`:

```swift
import Foundation
import ServiceManagement

public protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}

public final class LaunchAtLogin: LaunchAtLoginControlling {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Best-effort: the menu checkbox reflects `isEnabled` on next read regardless.
        }
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `swift build`
Expected: builds with no errors. (No behavior to test yet — this class only does something meaningful once running inside a real, launchable `.app` bundle, which doesn't exist until Task 10.)

- [ ] **Step 3: Commit**

```bash
git add Sources/ThinkingCapsCore/LaunchAtLogin.swift
git commit -m "Add LaunchAtLogin wrapper around SMAppService"
```

---

### Task 8: StatusItemController

**Files:**
- Create: `Sources/ThinkingCapsCore/StatusItemController.swift`

**Interfaces:**
- Consumes: `HookSocketServer.setEnabled(_ enabled: Bool)` (Task 4), `LaunchAtLoginControlling` (Task 7) — exact signatures as produced there.
- Produces: `public final class StatusItemController: NSObject` with `public init(socketServer: HookSocketServer, launchAtLogin: LaunchAtLoginControlling)`. Used by Task 9 (`AppDelegate`).

AppKit status bar UI needs a running `NSApplication` to behave correctly, so this is verified manually in Task 9 rather than with XCTest here.

- [ ] **Step 1: Implement `StatusItemController`**

Create `Sources/ThinkingCapsCore/StatusItemController.swift`:

```swift
import AppKit

public final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let socketServer: HookSocketServer
    private let launchAtLogin: LaunchAtLoginControlling
    private var isOn = true

    private let rightClickMenu = NSMenu()
    private let launchAtLoginMenuItem = NSMenuItem()

    public init(socketServer: HookSocketServer, launchAtLogin: LaunchAtLoginControlling) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.socketServer = socketServer
        self.launchAtLogin = launchAtLogin
        super.init()

        configureButton()
        configureMenu()
        updateIcon()
        socketServer.setEnabled(isOn)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.image(for: isOn)
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        launchAtLoginMenuItem.title = "Launch at Login"
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.action = #selector(toggleLaunchAtLogin)
        launchAtLoginMenuItem.state = launchAtLogin.isEnabled ? .on : .off
        rightClickMenu.addItem(launchAtLoginMenuItem)

        let quitItem = NSMenuItem(title: "Quit ThinkingCaps", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        rightClickMenu.addItem(quitItem)
    }

    @objc private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem.menu = rightClickMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            isOn.toggle()
            socketServer.setEnabled(isOn)
            updateIcon()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let newValue = !launchAtLogin.isEnabled
        launchAtLogin.setEnabled(newValue)
        launchAtLoginMenuItem.state = newValue ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateIcon() {
        statusItem.button?.image = Self.image(for: isOn)
    }

    private static func image(for isOn: Bool) -> NSImage? {
        let symbolName = isOn ? "capslock.fill" : "capslock"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isOn ? "ThinkingCaps On" : "ThinkingCaps Off")
        image?.isTemplate = true
        return image
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `swift build`
Expected: builds with no errors. Full behavior is verified manually in Task 9 once it's wired into a running app.

- [ ] **Step 3: Commit**

```bash
git add Sources/ThinkingCapsCore/StatusItemController.swift
git commit -m "Add StatusItemController with click-to-toggle and right-click menu"
```

---

### Task 9: AppDelegate + main.swift (full app wiring)

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ThinkingCapsCore/AppDelegate.swift`
- Create: `Sources/ThinkingCaps/main.swift`

**Interfaces:**
- Consumes: `IOKitCapsLockLEDDevice` (Task 3), `Blinker` (Task 3), `HookSocketServer` (Task 4), `ClaudeHookInstaller` (Task 5), `LaunchAtLogin` (Task 7), `StatusItemController` (Task 8) — exact signatures as produced there.
- Produces: `public final class AppDelegate: NSObject, NSApplicationDelegate`. Used only by `main.swift` — this is the top of the dependency graph; no later task consumes it.

- [ ] **Step 1: Expand `Package.swift` to add the app executable**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThinkingCaps",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "LEDSpike"),
        .target(name: "MiniTest"),
        .target(name: "ThinkingCapsCore"),
        .executableTarget(name: "SessionTrackerTests", dependencies: ["ThinkingCapsCore", "MiniTest"]),
        .target(name: "ThinkingCapsTestSupport", dependencies: ["ThinkingCapsCore"]),
        .executableTarget(name: "BlinkerTests", dependencies: ["ThinkingCapsCore", "ThinkingCapsTestSupport", "MiniTest"]),
        .executableTarget(name: "HookSocketServerTests", dependencies: ["ThinkingCapsCore", "ThinkingCapsTestSupport", "MiniTest"]),
        .executableTarget(name: "ClaudeHookInstallerTests", dependencies: ["ThinkingCapsCore", "MiniTest"]),
        .target(name: "HookNotifyCore"),
        .executableTarget(name: "HookNotify", dependencies: ["HookNotifyCore"]),
        .executableTarget(name: "PayloadParsingTests", dependencies: ["HookNotifyCore", "MiniTest"]),
        .executableTarget(name: "ThinkingCaps", dependencies: ["ThinkingCapsCore"]),
    ]
)
```

- [ ] **Step 2: Implement `AppDelegate`**

Create `Sources/ThinkingCapsCore/AppDelegate.swift`:

```swift
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var socketServer: HookSocketServer?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let appSupportDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThinkingCaps")
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        let socketPath = appSupportDir.appendingPathComponent("ctl.sock").path

        let ledDevice = IOKitCapsLockLEDDevice()
        let blinker = Blinker(device: ledDevice)
        let server = HookSocketServer(socketPath: socketPath, blinker: blinker)
        self.socketServer = server
        do {
            try server.start()
        } catch {
            NSLog("ThinkingCaps: failed to start hook socket server: \(error)")
        }

        let launchAtLogin = LaunchAtLogin()
        if !UserDefaults.standard.bool(forKey: "hasRunBefore") {
            launchAtLogin.setEnabled(true)
            UserDefaults.standard.set(true, forKey: "hasRunBefore")
        }

        statusItemController = StatusItemController(socketServer: server, launchAtLogin: launchAtLogin)

        installClaudeHookIfNeeded()
    }

    private func installClaudeHookIfNeeded() {
        let settingsURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        let notifierPath = Bundle.main.bundlePath + "/Contents/MacOS/hook-notify"
        let installer = ClaudeHookInstaller(settingsURL: settingsURL)
        do {
            try installer.install(notifierPath: notifierPath)
        } catch {
            NSLog("ThinkingCaps: failed to install Claude Code hooks: \(error)")
        }
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        socketServer?.stop()
        return .terminateNow
    }
}
```

- [ ] **Step 3: Write the executable entry point**

Create `Sources/ThinkingCaps/main.swift`:

```swift
import AppKit
import ThinkingCapsCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 4: Run the full test suite**

Run: `swift run SessionTrackerTests && swift run BlinkerTests && swift run HookSocketServerTests && swift run ClaudeHookInstallerTests && swift run PayloadParsingTests`
Expected: each prints its own `N/N passed` line and exits 0; the `&&` chain only completes if every one of them passes (6 + 4 + 6 + 6 + 3 = 25 checks total across Tasks 2, 3, 4, 5, 6).

- [ ] **Step 5: Manually run the app and verify the UI**

Run: `swift run ThinkingCaps`

Verify:
- A CapsLock icon appears in the menu bar (no Dock icon).
- Left-clicking it toggles the icon between the filled and outline CapsLock symbol.
- Right-clicking it shows a menu with "Launch at Login" (checked, since this is first run) and "Quit ThinkingCaps".
- Clicking "Quit ThinkingCaps" ends the process cleanly.

Note: `Bundle.main.bundlePath` won't resolve to a real `hook-notify` path when run via `swift run` (there's no `.app` bundle yet), so end-to-end hook testing with a real `claude` command happens after Task 10, not here.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ThinkingCapsCore/AppDelegate.swift Sources/ThinkingCaps/main.swift
git commit -m "Wire AppDelegate and main.swift into a runnable menu bar app"
```

---

### Task 10: App Bundle Assembly

**Files:**
- Create: `Resources/Info.plist`
- Create: `Scripts/build_app.sh`

**Interfaces:**
- Consumes: the `ThinkingCaps` and `HookNotify` executable targets built by Task 6 and Task 9.
- Produces: `.build/ThinkingCaps.app`, a real double-clickable app bundle. Consumed by Task 11 (DMG creation).

- [ ] **Step 1: Write `Info.plist`**

Create `Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ThinkingCaps</string>
    <key>CFBundleDisplayName</key>
    <string>ThinkingCaps</string>
    <key>CFBundleIdentifier</key>
    <string>com.mertisci.thinkingcaps</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>ThinkingCaps</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License</string>
</dict>
</plist>
```

- [ ] **Step 2: Write the build script**

Create `Scripts/build_app.sh`:

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release

APP_NAME="ThinkingCaps"
BUILD_DIR=".build/release"
APP_BUNDLE=".build/${APP_NAME}.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$BUILD_DIR/HookNotify" "$APP_BUNDLE/Contents/MacOS/hook-notify"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
```

- [ ] **Step 3: Make it executable and run it**

Run:
```bash
chmod +x Scripts/build_app.sh
./Scripts/build_app.sh
```
Expected: ends with `Built .build/ThinkingCaps.app` and no errors.

- [ ] **Step 4: Manually verify the packaged app end-to-end**

1. If a previous `swift run ThinkingCaps` process is still running, quit it first (right-click icon > Quit ThinkingCaps).
2. Double-click `.build/ThinkingCaps.app` in Finder to launch it.
3. Confirm the menu bar icon appears.
4. Open `~/.claude/settings.json` and confirm it now contains `UserPromptSubmit` and `Stop` hooks pointing at `.../ThinkingCaps.app/Contents/MacOS/hook-notify`.
5. If the LED doesn't blink in step 6 below, check System Settings > Privacy & Security > Input Monitoring — this specific app bundle may need to be enabled there the first time (confirmed necessary during Task 1's spike; macOS does not always prompt for this automatically).
6. Open a terminal and run a real Claude Code request: `claude -p "say hello"` (or interactively type a prompt to `claude`).
7. Watch the physical CapsLock LED while Claude is processing — confirm it blinks — and confirm it stops blinking once Claude's response finishes.
8. Open two terminal windows and run a `claude` request in each at roughly the same time; confirm the LED keeps blinking after the first one finishes, and only stops once both have finished.
9. Toggle the menu bar icon Off (left-click) and run another `claude` request — confirm the LED does **not** blink this time. Toggle it back On.
10. Quit the app (right-click > Quit), run a `claude` request with the app not running at all, and confirm the command completes normally with no errors or noticeable delay.
11. Relaunch `.build/ThinkingCaps.app` and repeat step 6 — confirm it still works after a quit/relaunch cycle.

- [ ] **Step 5: Commit**

```bash
git add Resources/Info.plist Scripts/build_app.sh
git commit -m "Add Info.plist and app bundle build script"
```

---

### Task 11: DMG creation

**Files:**
- Create: `Scripts/build_dmg.sh`

**Interfaces:**
- Consumes: `.build/ThinkingCaps.app` produced by Task 10.
- Produces: `.build/ThinkingCaps.dmg`. Consumed by Task 13 (GitHub release upload).

- [ ] **Step 1: Write the DMG build script**

Create `Scripts/build_dmg.sh`:

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_BUNDLE=".build/ThinkingCaps.app"
DMG_STAGING=".build/dmg-staging"
DMG_PATH=".build/ThinkingCaps.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "App bundle not found at $APP_BUNDLE. Run build_app.sh first." >&2
    exit 1
fi

rm -rf "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "ThinkingCaps" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

echo "Built $DMG_PATH"
```

- [ ] **Step 2: Make it executable and run it**

Run:
```bash
chmod +x Scripts/build_dmg.sh
./Scripts/build_dmg.sh
```
Expected: ends with `Built .build/ThinkingCaps.dmg`.

- [ ] **Step 3: Manually verify the DMG**

1. Double-click `.build/ThinkingCaps.dmg` to mount it.
2. Confirm a window opens showing `ThinkingCaps.app` and an `Applications` shortcut side by side.
3. Drag `ThinkingCaps.app` onto `Applications`.
4. Eject the DMG.
5. In `/Applications`, right-click `ThinkingCaps.app` and choose "Open" (not double-click) — confirm the Gatekeeper "unidentified developer" dialog appears with an "Open" button, and that clicking it launches the app successfully. This is the exact flow anyone downloading the DMG from GitHub will need to follow — write it down verbatim for the README in Task 12.

- [ ] **Step 4: Commit**

```bash
git add Scripts/build_dmg.sh
git commit -m "Add DMG packaging script"
```

---

### Task 12: README + LICENSE

**Files:**
- Create: `README.md`
- Create: `LICENSE`

**Interfaces:**
- None — this is documentation only.

- [ ] **Step 1: Confirm the copyright name with the user**

Before writing `LICENSE`, ask the user what name (or GitHub handle) they want on the MIT copyright line — do not guess or fabricate one.

- [ ] **Step 2: Write `LICENSE`**

Create `LICENSE` (replace `<NAME>` with the answer from Step 1):

```
MIT License

Copyright (c) 2026 <NAME>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Write `README.md`**

Create `README.md`:

```markdown
# ThinkingCaps

A tiny macOS menu bar app that blinks your MacBook's built-in CapsLock LED
while [Claude Code](https://claude.com/claude-code) is thinking in the
terminal, and stops as soon as it's done. Your CapsLock key keeps working
normally the whole time.

## Install

1. Download the latest `ThinkingCaps.dmg` from the
   [Releases](../../releases) page.
2. Open the DMG and drag `ThinkingCaps.app` into `Applications`.
3. Because this app isn't signed with an Apple Developer certificate, the
   first time you open it macOS will refuse with an "unidentified developer"
   warning. To get past it: **right-click `ThinkingCaps.app` in
   `Applications` and choose "Open"**, then click "Open" again in the dialog
   that appears. You only need to do this once.
4. Controlling the CapsLock LED requires **Input Monitoring** permission.
   macOS does not always show a permission prompt automatically for this —
   if the LED doesn't blink, open **System Settings > Privacy & Security >
   Input Monitoring**, find ThinkingCaps in the list, and enable it. You do
   not need to relaunch the app afterward.

## Usage

- A CapsLock icon appears in your menu bar. There's no dock icon.
- **Left-click** the icon to turn ThinkingCaps on or off. The icon fills in
  when it's on.
- **Right-click** the icon for "Launch at Login" and "Quit ThinkingCaps".
- The first time it runs, ThinkingCaps automatically adds two small hooks to
  `~/.claude/settings.json` so Claude Code can tell it when a request starts
  and finishes. It merges into your existing hooks — it won't remove
  anything you've already configured.

## How it works

When you send a prompt to `claude` in the terminal, a Claude Code hook
notifies ThinkingCaps over a local socket. ThinkingCaps then blinks the
CapsLock LED via IOKit until Claude Code reports it's finished. If more than
one terminal is running `claude` at once, the light keeps blinking until all
of them are done.

## Troubleshooting

If the LED never blinks, first double-check the Input Monitoring permission
above — that's the most common cause. If it's already enabled and it still
doesn't work, build and run the diagnostic tool from source:

```bash
git clone <this-repo-url>
cd thinkingcaps
swift run LEDSpike
```

It reports whether your keyboard exposes a controllable CapsLock LED and
whether Input Monitoring permission is granted. Note: because this command
runs an unbundled binary (not a proper signed `.app`), the "toggle" step at
the end may report `FAILED` even when permission is granted and everything
is otherwise fine — macOS appears to require a properly bundled, signed app
(like the real ThinkingCaps.app) to actually write the LED value, not just a
bare command-line executable. A `FAILED` toggle from this tool while the
element was found and permission is granted is not by itself proof of a
broken setup — please open an issue with the full output either way and
mention whether the real app's LED blinks for you.

## Uninstalling

Quitting or deleting the app does not remove the hooks it added to
`~/.claude/settings.json`. If you want those gone too, open that file and
remove the `hook-notify` entries under `UserPromptSubmit` and `Stop`.

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 4: Commit**

```bash
git add README.md LICENSE
git commit -m "Add README and MIT license"
```

---

### Task 13: Publish to GitHub

**Files:** none (this task only runs commands).

**Interfaces:** none — this is the final, terminal task.

- [ ] **Step 1: Confirm before publishing**

Before running anything in this task, confirm with the user: their GitHub username/organization to publish under, and that they're ready for the repo to go public now (this is a visible, hard-to-fully-reverse action once others can see or clone it).

- [ ] **Step 2: Check GitHub CLI auth**

Run: `gh auth status`
If not authenticated, stop and ask the user to run `gh auth login` themselves.

- [ ] **Step 3: Create the public repo and push**

```bash
gh repo create thinkingcaps --public --source=. --remote=origin --push
```

- [ ] **Step 4: Verify**

Run: `gh repo view --web`
Confirm the repo shows up with the README rendered and all files present.

- [ ] **Step 5: Attach the DMG as a release**

```bash
gh release create v1.0.0 .build/ThinkingCaps.dmg --title "ThinkingCaps 1.0.0" --notes "First release."
```

Confirm the release page shows the DMG as a downloadable asset, and that the README's `../../releases` link resolves to it.
