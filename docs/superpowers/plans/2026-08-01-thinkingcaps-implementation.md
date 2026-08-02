# ThinkingCaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Execution Status: PROJECT COMPLETE (2026-08-03)

All tasks (1–17), the final whole-branch review, and its fix wave are done.
v1.0.0 is published at https://github.com/mertisci/thinkingcaps with the
DMG (app icon included) attached as a release asset, and the full chain —
DMG install → Gatekeeper "Open Anyway" → onboarding wizard → Input
Monitoring grant → hook → socket → CapsLock LED blinking — was verified
live on real hardware from `/Applications`. The per-task SDD ledger was
retired after completion; `git log` is the history now.

**Late additions beyond the original plan:**
- Task 17 (2026-08-03): app icon — `Scripts/make_icon.swift` generates
  `Resources/AppIcon.icns` (capslock glyph on a graphite tile with a green
  LED accent), bundled via `build_app.sh`.
- Final-review fix wave: HID-handle recovery (re-locate the CapsLock LED
  device when writes start failing, e.g. after sleep/wake), Blinker state
  serialized on its own queue, hook-socket hardening (per-client workers +
  `SO_RCVTIMEO` + accept backoff), hook installer now replaces its own
  stale entries instead of appending, README Gatekeeper instructions
  corrected for macOS 15+ ("Open Anyway" flow), onboarding copy updated.

**Known deferred minors (accepted for v1, in rough priority order):**
settings.json is rewritten on every launch even when unchanged;
`SwitchableBlinkOutput.isEnabled` is a bare cross-thread Bool (explicit
design directive); `HookSocketServer.isRunning` is an unsynchronized Bool;
a newline-less client can grow the read buffer unboundedly (local-only
surface); ctrl+left-click toggles instead of opening the menu; `codesign
--deep` and `hdiutil create` deprecation warnings; the icon glyph reads
soft at 16 px.

**Ad-hoc signing / permission trap (applies to every update):** each
rebuild or app update changes the ad-hoc code signature, and macOS then
shows the old Input Monitoring entry as enabled while silently not
applying it (stale TCC records accumulate; toggling or removing the row is
NOT reliable). Reliable procedure: quit the app, `tccutil reset
ListenEvent com.mertisci.thinkingcaps`, relaunch, grant via the wizard,
then quit and reopen the app once more (macOS does not always show its
"quit & reopen" prompt, and the grant only applies to a fresh process).

**Goal:** Build ThinkingCaps, a macOS menu bar app that blinks the built-in CapsLock LED while Claude Code is processing a request in the terminal, packaged as an unsigned DMG and published to a public GitHub repo.

**Architecture:** A Swift Package Manager project with a small library (`ThinkingCapsCore`) holding all logic (session tracking, LED control, socket server, hook installer, launch-at-login, status bar UI), a thin `ThinkingCaps` executable that wires it into an `NSApplication`, and a separate `HookNotify` helper binary that Claude Code's hooks invoke to signal start/stop over a local unix socket. A standalone `LEDSpike` diagnostic tool validates the riskiest assumption (direct LED control) before the rest is built.

**Tech Stack:** Swift 5.9, Swift Package Manager, AppKit, IOKit (HID), ServiceManagement (`SMAppService`), Foundation/Darwin raw sockets, a small hand-rolled `MiniTest` assertion helper (see Global Constraints — this machine has no XCTest).

## Global Constraints

- Platform: macOS 13.0 (Ventura) or later — required for `SMAppService`.
- No Xcode project file — pure Swift Package Manager, no third-party dependencies.
- All source code, comments, UI strings, docs, and repo content are in English.
- Left-click on the menu bar icon only toggles On/Off — no dropdown menu on left-click. Right-click is the only place a menu appears. (Original menu: exactly "Launch at Login" and "Quit ThinkingCaps"; amended 2026-08-02 by Task 15: two checkable blink-output items — "Blink Caps Lock Light" default ON, "Blink Menu Bar Icon" default OFF; amended again by Task 16: a "Blink Speed" submenu — Slow 0.8s / Normal 0.45s default / Fast 0.25s radio group — after the two toggles. Then a separator, then "Launch at Login" and "Quit ThinkingCaps".)
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
        let valuePointer = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
        defer { valuePointer.deallocate() }
        guard IOHIDDeviceGetValue(device, element, valuePointer) == kIOReturnSuccess else {
            return false
        }
        let value = valuePointer.pointee.takeUnretainedValue()
        return IOHIDValueGetIntegerValue(value) != 0
    }
}
```

**Note:** `IOHIDDeviceGetValue`'s third parameter is `IOHIDValueRef _Nonnull * _Nonnull` in the real SDK header — a non-optional pointer to a non-optional `Unmanaged<IOHIDValue>`, not the doubly-optional `Unmanaged<IOHIDValue>?` an earlier draft of this code used (which doesn't compile against that signature). The version above was verified directly against `IOHIDDevice.h` on this machine.

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
Expected: prints six `PASS:` lines, then `6/6 passed`, exit code 0 (four test functions, six `t.check(...)` calls total — `test_isRunning_reflectsState` alone has three).

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
Expected: prints eight `PASS:` lines, then `8/8 passed`, exit code 0 (six test functions; `test_parse_recognizesStartAndStop` alone has three checks).

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
Expected: each prints its own `N/N passed` line and exits 0; the `&&` chain only completes if every one of them passes (6 + 6 + 8 + 6 + 3 = 29 checks total across Tasks 2, 3, 4, 5, 6).

- [ ] **Step 5: Manually run the app and verify the UI**

Run: `swift run ThinkingCaps`

Verify:
- A CapsLock icon appears in the menu bar (no Dock icon).
- Left-clicking it toggles the icon between the filled and outline CapsLock symbol.
- Right-clicking it shows a menu with "Launch at Login" (checked, since this is first run) and "Quit ThinkingCaps".
- Clicking "Quit ThinkingCaps" ends the process cleanly.

Note: `Bundle.main.bundlePath` won't resolve to a real `hook-notify` path when run via `swift run` (there's no `.app` bundle yet), so end-to-end hook testing with a real `claude` command happens after Task 10, not here.

**Warning, confirmed the hard way during this task's own verification:** `applicationDidFinishLaunching` calls `installClaudeHookIfNeeded()` unconditionally, on every launch — including a bare `swift run ThinkingCaps` smoke test. It writes into the REAL, global `~/.claude/settings.json` (not anything scoped to this project's worktree), with a broken `hook-notify` path since there's no real `.app` bundle yet. Running this step *will* add that broken entry to the live settings file every time. Before/after running this step, check whether `~/.claude/settings.json` already had a user-configured `"hooks"` section: if it didn't, remove the whole `"hooks"` key afterward to restore the pre-test state; if it did, remove only the two entries this run added (matching the broken `.build/.../hook-notify` path) and leave everything else untouched. Do this cleanup after every `swift run ThinkingCaps` test cycle until Task 10 packages a real `.app` bundle, at which point a correct hook install becomes the intended, permanent behavior.

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
4. On first launch, ThinkingCaps shows a short **setup window**: controlling
   the CapsLock LED requires macOS's **Input Monitoring** permission. Click
   **Grant Permission** and enable ThinkingCaps in the System Settings list
   that opens. macOS may ask to quit and reopen the app — that's expected;
   setup continues automatically after the relaunch.

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

If the LED never blinks, first re-check the Input Monitoring permission
(System Settings > Privacy & Security > Input Monitoring) — the setup window
reappears on launch whenever the permission is missing. If it's enabled and
the LED still doesn't blink, build and run the diagnostic tool from source:

```bash
git clone <this-repo-url>
cd thinkingcaps
swift run LEDSpike
```

It reports whether your keyboard exposes a controllable CapsLock LED, whether
Input Monitoring permission is available to it, and whether each LED write is
accepted (`ok`) or rejected (`FAILED`). `FAILED` toggles usually mean Input
Monitoring permission is missing for your terminal (the permission applies to
whatever app runs the command). Please open an issue with the full output and
mention whether the installed ThinkingCaps app's LED blinks for you.

Note for people building from source: rebuilding the app changes its ad-hoc
code signature, which makes macOS silently forget the Input Monitoring grant
for the previous build — the setup window will simply reappear; re-grant and
continue. DMG users are unaffected.

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

---

### Task 14: First-run onboarding wizard (added 2026-08-02 — executes BEFORE Task 11)

Added after Task 10's end-to-end verification: the user must grant Input
Monitoring for the LED to work, and discovering that buried in System Settings
is bad UX. This task adds a small native setup window guiding it. Execution
order note: this task runs after Task 10 and BEFORE Task 11 (the DMG must ship
the wizard-enabled app). All UI text is English.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ThinkingCapsCore/InputMonitoringPermission.swift`
- Create: `Sources/ThinkingCapsCore/OnboardingFlow.swift`
- Create: `Sources/ThinkingCapsCore/OnboardingWindowController.swift`
- Modify: `Sources/ThinkingCapsCore/AppDelegate.swift`
- Test: `Sources/OnboardingFlowTests/main.swift`

**Interfaces:**
- Consumes: `AppDelegate` wiring from Task 9; the MiniTest pattern from Task 2.
- Produces: `public enum InputMonitoringPermission { public static func isGranted() -> Bool; @discardableResult public static func request() -> Bool }`; `public enum OnboardingScreen: Equatable { case permission, success }`; `public enum OnboardingFlow { public static func initialScreen(permissionGranted: Bool, hasCompletedOnboarding: Bool) -> OnboardingScreen? }`; `public final class OnboardingWindowController: NSWindowController, NSWindowDelegate` with `public init(initialScreen: OnboardingScreen, onCompleted: @escaping () -> Void)`. Consumed only by `AppDelegate`.

- [ ] **Step 1: Expand `Package.swift` to add the `OnboardingFlowTests` executable**

Add this line after the `PayloadParsingTests` entry (keep every existing target unchanged):

```swift
        .executableTarget(name: "OnboardingFlowTests", dependencies: ["ThinkingCapsCore", "MiniTest"]),
```

- [ ] **Step 2: Write the failing tests**

Create `Sources/OnboardingFlowTests/main.swift`:

```swift
import Foundation
import MiniTest
import ThinkingCapsCore

let t = MiniTest()

func test_noPermission_showsPermissionScreen() {
    t.check(OnboardingFlow.initialScreen(permissionGranted: false, hasCompletedOnboarding: false) == .permission,
            "no permission, never onboarded -> permission screen")
}

func test_noPermission_afterOnboarding_stillShowsPermissionScreen() {
    t.check(OnboardingFlow.initialScreen(permissionGranted: false, hasCompletedOnboarding: true) == .permission,
            "permission revoked after onboarding -> permission screen again")
}

func test_granted_firstTime_showsSuccessScreen() {
    t.check(OnboardingFlow.initialScreen(permissionGranted: true, hasCompletedOnboarding: false) == .success,
            "granted but onboarding not completed -> success screen")
}

func test_granted_alreadyOnboarded_showsNothing() {
    t.check(OnboardingFlow.initialScreen(permissionGranted: true, hasCompletedOnboarding: true) == nil,
            "granted and already onboarded -> no window")
}

test_noPermission_showsPermissionScreen()
test_noPermission_afterOnboarding_stillShowsPermissionScreen()
test_granted_firstTime_showsSuccessScreen()
test_granted_alreadyOnboarded_showsNothing()

t.finish()
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift run OnboardingFlowTests`
Expected: FAIL to compile — `OnboardingFlow` doesn't exist yet.

- [ ] **Step 4: Implement `InputMonitoringPermission` and `OnboardingFlow`**

Create `Sources/ThinkingCapsCore/InputMonitoringPermission.swift`:

```swift
import Foundation
import IOKit.hid

public enum InputMonitoringPermission {
    public static func isGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    public static func request() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}
```

Create `Sources/ThinkingCapsCore/OnboardingFlow.swift`:

```swift
public enum OnboardingScreen: Equatable {
    case permission
    case success
}

public enum OnboardingFlow {
    public static func initialScreen(permissionGranted: Bool, hasCompletedOnboarding: Bool) -> OnboardingScreen? {
        if !permissionGranted { return .permission }
        if !hasCompletedOnboarding { return .success }
        return nil
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift run OnboardingFlowTests`
Expected: prints four `PASS:` lines, then `4/4 passed`, exit code 0.

- [ ] **Step 6: Implement `OnboardingWindowController`**

Create `Sources/ThinkingCapsCore/OnboardingWindowController.swift`:

```swift
import AppKit

public final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onCompleted: () -> Void
    private var pollTimer: Timer?
    private var currentScreen: OnboardingScreen
    private let statusLabel = NSTextField(labelWithString: "Status: waiting for permission…")

    public init(initialScreen: OnboardingScreen, onCompleted: @escaping () -> Void) {
        self.onCompleted = onCompleted
        self.currentScreen = initialScreen
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ThinkingCaps Setup"
        super.init(window: window)
        window.delegate = self
        showScreen(initialScreen)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        pollTimer?.invalidate()
    }

    private func showScreen(_ screen: OnboardingScreen) {
        currentScreen = screen
        pollTimer?.invalidate()
        pollTimer = nil
        switch screen {
        case .permission:
            window?.contentView = makePermissionView()
            startPollingForGrant()
        case .success:
            window?.contentView = makeSuccessView()
        }
    }

    // MARK: - Permission screen

    private func makePermissionView() -> NSView {
        let icon = makeIconView()

        let title = NSTextField(labelWithString: "Welcome to ThinkingCaps")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString:
            "ThinkingCaps blinks your keyboard's Caps Lock light while Claude Code is thinking. "
            + "To control the light, macOS requires the Input Monitoring permission.\n\n"
            + "Click Grant Permission, then enable ThinkingCaps in the System Settings list that opens. "
            + "macOS may ask to quit and reopen the app — that's expected, setup continues automatically."
        )
        body.alignment = .center
        body.preferredMaxLayoutWidth = 400

        statusLabel.stringValue = "Status: waiting for permission…"
        statusLabel.textColor = .secondaryLabelColor

        let grantButton = NSButton(title: "Grant Permission", target: self, action: #selector(grantTapped))
        grantButton.keyEquivalent = "\r"

        let settingsButton = NSButton(title: "Open System Settings", target: self, action: #selector(openSettingsTapped))

        return makeStack([icon, title, body, statusLabel, grantButton, settingsButton])
    }

    @objc private func grantTapped() {
        InputMonitoringPermission.request()
        openInputMonitoringSettings()
    }

    @objc private func openSettingsTapped() {
        openInputMonitoringSettings()
    }

    private func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPollingForGrant() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if InputMonitoringPermission.isGranted() {
                self.showScreen(.success)
            }
        }
    }

    // MARK: - Success screen

    private func makeSuccessView() -> NSView {
        let icon = makeIconView()

        let title = NSTextField(labelWithString: "You're all set!")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let body = NSTextField(wrappingLabelWithString:
            "The Caps Lock light will blink while Claude Code is thinking, and stop when it's done.\n\n"
            + "Left-click the menu bar icon to turn ThinkingCaps on or off.\n"
            + "Right-click it for Launch at Login and Quit.\n\n"
            + "Claude Code integration was set up automatically."
        )
        body.alignment = .center
        body.preferredMaxLayoutWidth = 400

        let doneButton = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        doneButton.keyEquivalent = "\r"

        return makeStack([icon, title, body, doneButton])
    }

    @objc private func doneTapped() {
        onCompleted()
        close()
    }

    // MARK: - Shared

    private func makeIconView() -> NSImageView {
        let imageView = NSImageView()
        if let image = NSImage(systemSymbolName: "capslock.fill", accessibilityDescription: "ThinkingCaps") {
            image.isTemplate = true
            imageView.image = image
            imageView.symbolConfiguration = .init(pointSize: 44, weight: .regular)
        }
        return imageView
    }

    private func makeStack(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 14
        stack.alignment = .centerX
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 36, bottom: 28, right: 36)
        return stack
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
        if currentScreen == .success {
            onCompleted()
        }
    }
}
```

- [ ] **Step 7: Wire it into `AppDelegate`**

Modify `Sources/ThinkingCapsCore/AppDelegate.swift`. Add a stored property and a key constant alongside the existing properties:

```swift
    private var onboardingController: OnboardingWindowController?
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
```

At the END of `applicationDidFinishLaunching` (after `installClaudeHookIfNeeded()`), add:

```swift
        let initialScreen = OnboardingFlow.initialScreen(
            permissionGranted: InputMonitoringPermission.isGranted(),
            hasCompletedOnboarding: UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey)
        )
        if let initialScreen {
            presentOnboarding(initialScreen)
        }
```

And add this method to the class:

```swift
    private func presentOnboarding(_ screen: OnboardingScreen) {
        let controller = OnboardingWindowController(initialScreen: screen) {
            UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        }
        onboardingController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.window?.makeKeyAndOrderFront(nil)
    }
```

- [ ] **Step 8: Build and run the full test suite**

Run: `swift build && swift run SessionTrackerTests && swift run BlinkerTests && swift run HookSocketServerTests && swift run ClaudeHookInstallerTests && swift run PayloadParsingTests && swift run OnboardingFlowTests`
Expected: clean build; all suites green (6 + 6 + 8 + 6 + 3 + 4 = 33 checks).

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/ThinkingCapsCore/InputMonitoringPermission.swift Sources/ThinkingCapsCore/OnboardingFlow.swift Sources/ThinkingCapsCore/OnboardingWindowController.swift Sources/ThinkingCapsCore/AppDelegate.swift Sources/OnboardingFlowTests/main.swift
git commit -m "Add first-run onboarding wizard with Input Monitoring permission flow"
```

- [ ] **Step 10: Manual end-to-end wizard verification (controller + user, after rebuild)**

1. `tccutil reset ListenEvent com.mertisci.thinkingcaps` (start from a clean permission state; also needed anyway since the rebuild invalidates the old grant).
2. `defaults delete com.mertisci.thinkingcaps hasCompletedOnboarding` (simulate first run; ignore error if the key doesn't exist). Note: `defaults` keys on an unbundled `swift run` won't match — this app runs from the bundle, domain `com.mertisci.thinkingcaps`.
3. Rebuild + launch: `./Scripts/build_app.sh && open .build/ThinkingCaps.app`.
4. Confirm the Setup window appears showing the Permission screen, and the menu bar icon is ALSO already present.
5. Click "Grant Permission" — confirm System Settings opens at Input Monitoring; enable ThinkingCaps; accept macOS's quit-and-reopen prompt if shown (relaunch manually otherwise).
6. Confirm the relaunched app shows the Success screen directly.
7. Click "Done" — window closes, app stays in the menu bar.
8. Quit and relaunch the app — confirm NO window appears this time (steady state).
9. Run a real `claude` request — confirm the LED blinks while it processes and stops when done.

---

### Task 15: Independent blink outputs — LED + menu bar icon (added 2026-08-02 — executes BEFORE Task 11)

User request after Task 14's verification: the right-click menu gets two
independent, persisted, checkable outputs — "Blink Caps Lock Light" (default
ON) and "Blink Menu Bar Icon" (default OFF). Users may enable either, both,
or neither. All UI text English.

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/ThinkingCapsCore/Blinker.swift`
- Create: `Sources/ThinkingCapsCore/SwitchableBlinkOutput.swift`
- Create: `Sources/ThinkingCapsCore/MenuBarIconBlinkOutput.swift`
- Create: `Sources/ThinkingCapsCore/BlinkSettings.swift`
- Modify: `Sources/ThinkingCapsCore/StatusItemController.swift`
- Modify: `Sources/ThinkingCapsCore/AppDelegate.swift`
- Test: `Sources/BlinkRoutingTests/main.swift`

**Interfaces:**
- Consumes: `CapsLockLEDDevice` protocol, `Blinker`, `FakeCapsLockLEDDevice` (ThinkingCapsTestSupport), `StatusItemController`, `AppDelegate` wiring.
- Produces: `Blinker.init(devices: [CapsLockLEDDevice], interval:, queue:)` (new designated init; existing single-`device` init becomes a convenience forwarding to it, so `HookSocketServer` and `BlinkerTests` are untouched); `public final class SwitchableBlinkOutput: CapsLockLEDDevice` with `init(wrapping: CapsLockLEDDevice, isEnabled: Bool)` and `var isEnabled: Bool` (disabling mid-blink restores the wrapped output's resting state); `public final class MenuBarIconBlinkOutput: CapsLockLEDDevice` with `var setIconVisible: ((Bool) -> Void)?` (main-thread dispatch; `realCapsLockIsOn()` returns `true` — an icon's resting state is "visible"); `public final class BlinkSettings` with `init(defaults: UserDefaults = .standard, led: CapsLockLEDDevice, icon: CapsLockLEDDevice)`, `let ledOutput/iconOutput: SwitchableBlinkOutput`, `var isLEDBlinkEnabled/isIconBlinkEnabled: Bool { get }`, `func setLEDBlinkEnabled(_:)/setIconBlinkEnabled(_:)` (persists to keys `blinkCapsLockLED`/`blinkMenuBarIcon`; LED defaults true when key absent, icon defaults false); `StatusItemController.init(socketServer:launchAtLogin:blinkSettings:)` (new param) and `public func setIconBlinkFrame(visible: Bool)`.

- [ ] **Step 1: Expand `Package.swift`**

Add after the `OnboardingFlowTests` entry:

```swift
        .executableTarget(name: "BlinkRoutingTests", dependencies: ["ThinkingCapsCore", "ThinkingCapsTestSupport", "MiniTest"]),
```

- [ ] **Step 2: Write the failing tests**

Create `Sources/BlinkRoutingTests/main.swift`:

```swift
import Foundation
import MiniTest
import ThinkingCapsCore
import ThinkingCapsTestSupport

let t = MiniTest()

func withTempDefaults(_ body: (UserDefaults) -> Void) {
    let suiteName = "com.thinkingcaps.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        t.check(false, "could not create test UserDefaults suite")
        return
    }
    body(defaults)
    defaults.removePersistentDomain(forName: suiteName)
}

func test_defaults_ledOnIconOff() {
    withTempDefaults { defaults in
        let settings = BlinkSettings(defaults: defaults, led: FakeCapsLockLEDDevice(), icon: FakeCapsLockLEDDevice())
        t.check(settings.isLEDBlinkEnabled, "LED blink defaults to enabled")
        t.check(!settings.isIconBlinkEnabled, "icon blink defaults to disabled")
    }
}

func test_persistedValues_areHonored() {
    withTempDefaults { defaults in
        defaults.set(false, forKey: BlinkSettings.ledKey)
        defaults.set(true, forKey: BlinkSettings.iconKey)
        let settings = BlinkSettings(defaults: defaults, led: FakeCapsLockLEDDevice(), icon: FakeCapsLockLEDDevice())
        t.check(!settings.isLEDBlinkEnabled, "persisted LED=false honored")
        t.check(settings.isIconBlinkEnabled, "persisted icon=true honored")
    }
}

func test_disabledOutput_blocksWrites() {
    let fake = FakeCapsLockLEDDevice()
    let output = SwitchableBlinkOutput(wrapping: fake, isEnabled: false)
    output.setLEDOn(true)
    t.check(fake.calls.isEmpty, "disabled output blocks writes")
}

func test_enabledOutput_passesWritesThrough() {
    let fake = FakeCapsLockLEDDevice()
    let output = SwitchableBlinkOutput(wrapping: fake, isEnabled: true)
    output.setLEDOn(true)
    t.check(fake.calls.last == true, "enabled output passes writes through")
}

func test_disablingMidBlink_restoresRestingState() {
    let fake = FakeCapsLockLEDDevice()
    fake.realStateToReturn = true
    let output = SwitchableBlinkOutput(wrapping: fake, isEnabled: true)
    output.setLEDOn(false)
    output.isEnabled = false
    t.check(fake.calls.last == true, "disabling mid-blink restores resting state")
}

func test_setters_persistAndApply() {
    withTempDefaults { defaults in
        let ledFake = FakeCapsLockLEDDevice()
        let settings = BlinkSettings(defaults: defaults, led: ledFake, icon: FakeCapsLockLEDDevice())
        settings.setLEDBlinkEnabled(false)
        t.check(defaults.bool(forKey: BlinkSettings.ledKey) == false, "setter persists to defaults")
        settings.ledOutput.setLEDOn(true)
        t.check(!ledFake.calls.contains(true) || settings.isLEDBlinkEnabled == false, "setter applies to output gating")
    }
}

func test_blinker_fansOutToMultipleDevices() {
    let fake1 = FakeCapsLockLEDDevice()
    let fake2 = FakeCapsLockLEDDevice()
    let blinker = Blinker(devices: [fake1, fake2], interval: 0.02)
    blinker.start()
    Thread.sleep(forTimeInterval: 0.15)
    blinker.stop()
    t.check(fake1.calls.count >= 2, "first device receives blink ticks")
    t.check(fake2.calls.count >= 2, "second device receives blink ticks")
}

func test_blinkerStop_restoresEachDeviceToItsOwnRestingState() {
    let fake1 = FakeCapsLockLEDDevice()
    fake1.realStateToReturn = true
    let fake2 = FakeCapsLockLEDDevice()
    fake2.realStateToReturn = false
    let blinker = Blinker(devices: [fake1, fake2], interval: 0.02)
    blinker.start()
    blinker.stop()
    t.check(fake1.calls.last == true, "stop restores first device to its own resting state")
    t.check(fake2.calls.last == false, "stop restores second device to its own resting state")
}

test_defaults_ledOnIconOff()
test_persistedValues_areHonored()
test_disabledOutput_blocksWrites()
test_enabledOutput_passesWritesThrough()
test_disablingMidBlink_restoresRestingState()
test_setters_persistAndApply()
test_blinker_fansOutToMultipleDevices()
test_blinkerStop_restoresEachDeviceToItsOwnRestingState()

t.finish()
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift run BlinkRoutingTests`
Expected: FAIL to compile — `SwitchableBlinkOutput`, `BlinkSettings`, and `Blinker(devices:)` don't exist yet.

- [ ] **Step 4: Implement the routing types and multi-device `Blinker`**

Replace the `init` in `Sources/ThinkingCapsCore/Blinker.swift` and generalize to devices (the rest of the class keeps its structure; full new content):

```swift
import Foundation

public final class Blinker {
    private let devices: [CapsLockLEDDevice]
    private let interval: TimeInterval
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

    public func stop() {
        timer?.cancel()
        timer = nil
        for device in devices {
            device.setLEDOn(device.realCapsLockIsOn())
        }
    }
}
```

Create `Sources/ThinkingCapsCore/SwitchableBlinkOutput.swift`:

```swift
import Foundation

public final class SwitchableBlinkOutput: CapsLockLEDDevice {
    private let wrapped: CapsLockLEDDevice

    public var isEnabled: Bool {
        didSet {
            if !isEnabled && oldValue {
                // Restore the wrapped output's resting state so a mid-blink
                // disable can't freeze it on a lit frame.
                wrapped.setLEDOn(wrapped.realCapsLockIsOn())
            }
        }
    }

    public init(wrapping wrapped: CapsLockLEDDevice, isEnabled: Bool) {
        self.wrapped = wrapped
        self.isEnabled = isEnabled
    }

    public func setLEDOn(_ on: Bool) {
        guard isEnabled else { return }
        wrapped.setLEDOn(on)
    }

    public func realCapsLockIsOn() -> Bool {
        wrapped.realCapsLockIsOn()
    }
}
```

Create `Sources/ThinkingCapsCore/MenuBarIconBlinkOutput.swift`:

```swift
import Foundation

public final class MenuBarIconBlinkOutput: CapsLockLEDDevice {
    /// Called on the main thread with `false` for the blink's "hidden" frame
    /// and `true` for the visible/restored frame.
    public var setIconVisible: ((Bool) -> Void)?

    public init() {}

    public func setLEDOn(_ on: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.setIconVisible?(on)
        }
    }

    // The icon's resting state is always "visible"; restoring after a blink
    // session means showing the normal icon again.
    public func realCapsLockIsOn() -> Bool { true }
}
```

Create `Sources/ThinkingCapsCore/BlinkSettings.swift`:

```swift
import Foundation

public final class BlinkSettings {
    public static let ledKey = "blinkCapsLockLED"
    public static let iconKey = "blinkMenuBarIcon"

    private let defaults: UserDefaults
    public let ledOutput: SwitchableBlinkOutput
    public let iconOutput: SwitchableBlinkOutput

    public init(defaults: UserDefaults = .standard, led: CapsLockLEDDevice, icon: CapsLockLEDDevice) {
        self.defaults = defaults
        let ledEnabled = defaults.object(forKey: Self.ledKey) == nil ? true : defaults.bool(forKey: Self.ledKey)
        let iconEnabled = defaults.bool(forKey: Self.iconKey)
        self.ledOutput = SwitchableBlinkOutput(wrapping: led, isEnabled: ledEnabled)
        self.iconOutput = SwitchableBlinkOutput(wrapping: icon, isEnabled: iconEnabled)
    }

    public var isLEDBlinkEnabled: Bool { ledOutput.isEnabled }
    public var isIconBlinkEnabled: Bool { iconOutput.isEnabled }

    public func setLEDBlinkEnabled(_ enabled: Bool) {
        ledOutput.isEnabled = enabled
        defaults.set(enabled, forKey: Self.ledKey)
    }

    public func setIconBlinkEnabled(_ enabled: Bool) {
        iconOutput.isEnabled = enabled
        defaults.set(enabled, forKey: Self.iconKey)
    }
}
```

Concurrency note (accepted, documented): `SwitchableBlinkOutput.isEnabled` is written from the main thread (menu clicks) and read on the blink queue. This is the same pragmatic single-writer/bool-reader pattern the reviewed `Blinker`/`HookSocketServer` already use for comparable flags; do not add locking here.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift run BlinkRoutingTests`
Expected: prints twelve `PASS:` lines, then `12/12 passed`, exit code 0. Also run `swift run BlinkerTests` — the existing 6/6 must still pass via the convenience init (its file is untouched).

- [ ] **Step 6: Add the menu items and icon-frame API to `StatusItemController`**

Modify `Sources/ThinkingCapsCore/StatusItemController.swift`:

1. Add stored properties alongside the existing menu items:

```swift
    private let blinkSettings: BlinkSettings
    private let blinkLEDMenuItem = NSMenuItem()
    private let blinkIconMenuItem = NSMenuItem()
```

2. Change the initializer signature and store the new dependency (everything else in `init` stays):

```swift
    public init(socketServer: HookSocketServer, launchAtLogin: LaunchAtLoginControlling, blinkSettings: BlinkSettings) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.socketServer = socketServer
        self.launchAtLogin = launchAtLogin
        self.blinkSettings = blinkSettings
        super.init()

        configureButton()
        configureMenu()
        updateIcon()
        socketServer.setEnabled(isOn)
    }
```

3. Replace `configureMenu()` so the two blink toggles come first, then a separator, then the existing items:

```swift
    private func configureMenu() {
        blinkLEDMenuItem.title = "Blink Caps Lock Light"
        blinkLEDMenuItem.target = self
        blinkLEDMenuItem.action = #selector(toggleBlinkLED)
        blinkLEDMenuItem.state = blinkSettings.isLEDBlinkEnabled ? .on : .off
        rightClickMenu.addItem(blinkLEDMenuItem)

        blinkIconMenuItem.title = "Blink Menu Bar Icon"
        blinkIconMenuItem.target = self
        blinkIconMenuItem.action = #selector(toggleBlinkIcon)
        blinkIconMenuItem.state = blinkSettings.isIconBlinkEnabled ? .on : .off
        rightClickMenu.addItem(blinkIconMenuItem)

        rightClickMenu.addItem(.separator())

        launchAtLoginMenuItem.title = "Launch at Login"
        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.action = #selector(toggleLaunchAtLogin)
        launchAtLoginMenuItem.state = launchAtLogin.isEnabled ? .on : .off
        rightClickMenu.addItem(launchAtLoginMenuItem)

        let quitItem = NSMenuItem(title: "Quit ThinkingCaps", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        rightClickMenu.addItem(quitItem)
    }
```

4. Add the two toggle actions next to `toggleLaunchAtLogin`:

```swift
    @objc private func toggleBlinkLED() {
        blinkSettings.setLEDBlinkEnabled(!blinkSettings.isLEDBlinkEnabled)
        blinkLEDMenuItem.state = blinkSettings.isLEDBlinkEnabled ? .on : .off
    }

    @objc private func toggleBlinkIcon() {
        blinkSettings.setIconBlinkEnabled(!blinkSettings.isIconBlinkEnabled)
        blinkIconMenuItem.state = blinkSettings.isIconBlinkEnabled ? .on : .off
    }
```

5. Add the icon-frame API (used by `MenuBarIconBlinkOutput` via AppDelegate wiring):

```swift
    public func setIconBlinkFrame(visible: Bool) {
        if visible {
            updateIcon()
        } else {
            statusItem.button?.image = Self.image(for: false)
        }
    }
```

**Amended 2026-08-02 (user feedback after live testing):** the "hidden" frame is the
outline CapsLock symbol (`Self.image(for: false)`), not `nil` — the icon blinks
filled ↔ outline rather than appearing/disappearing. The `visible` branch stays
`updateIcon()` (not a hardcoded filled image) deliberately: the same `true` call is
also the restore path when a blink session ends, and routing it through
`updateIcon()` keeps the final frame correct even if the user toggled the app Off
mid-blink (the queued restore lands after the click handler and must reflect the
new Off state, not assume On).

- [ ] **Step 7: Wire it in `AppDelegate`**

In `applicationDidFinishLaunching`, replace the device/blinker/controller construction so the blinker drives both switchable outputs and the icon output calls back into the status item controller:

```swift
        let ledDevice = IOKitCapsLockLEDDevice()
        let iconBlinkOutput = MenuBarIconBlinkOutput()
        let blinkSettings = BlinkSettings(led: ledDevice, icon: iconBlinkOutput)
        let blinker = Blinker(devices: [blinkSettings.ledOutput, blinkSettings.iconOutput])
        let server = HookSocketServer(socketPath: socketPath, blinker: blinker)
```

and after `statusItemController` is created (now passing `blinkSettings:`):

```swift
        statusItemController = StatusItemController(socketServer: server, launchAtLogin: launchAtLogin, blinkSettings: blinkSettings)
        iconBlinkOutput.setIconVisible = { [weak self] visible in
            self?.statusItemController?.setIconBlinkFrame(visible: visible)
        }
```

- [ ] **Step 8: Build and run the full test suite**

Run: `swift build && swift run SessionTrackerTests && swift run BlinkerTests && swift run HookSocketServerTests && swift run ClaudeHookInstallerTests && swift run PayloadParsingTests && swift run OnboardingFlowTests && swift run BlinkRoutingTests`
Expected: clean build; all suites green (6 + 6 + 8 + 6 + 3 + 4 + 12 = 45 checks).

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/ThinkingCapsCore/Blinker.swift Sources/ThinkingCapsCore/SwitchableBlinkOutput.swift Sources/ThinkingCapsCore/MenuBarIconBlinkOutput.swift Sources/ThinkingCapsCore/BlinkSettings.swift Sources/ThinkingCapsCore/StatusItemController.swift Sources/ThinkingCapsCore/AppDelegate.swift Sources/BlinkRoutingTests/main.swift
git commit -m "Add independent blink outputs: Caps Lock LED and menu bar icon, toggleable from the right-click menu"
```

- [ ] **Step 10: Manual verification (controller + user, after rebuild)**

1. Rebuild + relaunch (`./Scripts/build_app.sh && open .build/ThinkingCaps.app`). The rebuild invalidates the ad-hoc TCC grant — the onboarding wizard's Permission screen will reappear; re-grant (this also re-validates Task 14's wizard on a stale-grant machine).
2. Right-click the icon: confirm the menu shows Blink Caps Lock Light (checked), Blink Menu Bar Icon (unchecked), separator, Launch at Login, Quit.
3. Drive a blink session (real `claude` prompt or `hook-notify start`): LED blinks, icon does NOT.
4. Enable Blink Menu Bar Icon; drive a session: LED AND icon both blink; confirm the icon returns to normal when the session ends.
5. Disable Blink Caps Lock Light mid-session: LED stops immediately (restored to real state), icon keeps blinking.
6. Disable both; drive a session: nothing blinks (menu-only silence), and the app still tracks sessions (re-enable mid-session → blinking resumes on the next ticks).
7. Quit and relaunch: confirm both preferences survived.

---

### Task 16: Blink speed setting + quit-time blink restore (added 2026-08-02 — executes BEFORE Task 11)

User request after Task 15: a per-user blink speed (Slow / Normal / Fast) in
the right-click menu, applied live even mid-session. Also folds in a small
correctness fix observed during testing: quitting the app mid-blink left the
LED frozen at whatever frame was last written, because nothing stopped the
Blinker on termination — `applicationShouldTerminate` must stop it so both
outputs get restored to resting state before exit.

**Files:**
- Modify: `Sources/ThinkingCapsCore/Blinker.swift`
- Create: `Sources/ThinkingCapsCore/BlinkSpeed.swift`
- Modify: `Sources/ThinkingCapsCore/BlinkSettings.swift`
- Modify: `Sources/ThinkingCapsCore/StatusItemController.swift`
- Modify: `Sources/ThinkingCapsCore/AppDelegate.swift`
- Test: Modify `Sources/BlinkRoutingTests/main.swift` (no `Package.swift` change — same target)

**Interfaces:**
- Consumes: everything Task 15 produced.
- Produces: `public enum BlinkSpeed: String, CaseIterable { case slow, normal, fast }` with `var interval: TimeInterval` (0.8 / 0.45 / 0.25) and `var displayName: String` ("Slow"/"Normal"/"Fast"); `Blinker.setInterval(_ newInterval: TimeInterval)` (reschedules a running timer live); `BlinkSettings.speedKey`, `var blinkSpeed: BlinkSpeed { get }` (default `.normal` when key absent/invalid), `func setBlinkSpeed(_:)` (persists + calls `applyInterval`), `var applyInterval: ((TimeInterval) -> Void)?`; `AppDelegate` retains the `Blinker` and stops it in `applicationShouldTerminate`.

- [ ] **Step 1: Extend the failing tests**

Append to `Sources/BlinkRoutingTests/main.swift`, before the existing call list at the bottom (and add the new call lines to the call list, keeping its order matching definition order):

```swift
func test_blinkSpeed_defaultsToNormal() {
    withTempDefaults { defaults in
        let settings = BlinkSettings(defaults: defaults, led: FakeCapsLockLEDDevice(), icon: FakeCapsLockLEDDevice())
        t.check(settings.blinkSpeed == .normal, "blink speed defaults to normal")
    }
}

func test_blinkSpeed_persistedValueHonored() {
    withTempDefaults { defaults in
        defaults.set(BlinkSpeed.fast.rawValue, forKey: BlinkSettings.speedKey)
        let settings = BlinkSettings(defaults: defaults, led: FakeCapsLockLEDDevice(), icon: FakeCapsLockLEDDevice())
        t.check(settings.blinkSpeed == .fast, "persisted blink speed honored")
    }
}

func test_setBlinkSpeed_persistsAndApplies() {
    withTempDefaults { defaults in
        let settings = BlinkSettings(defaults: defaults, led: FakeCapsLockLEDDevice(), icon: FakeCapsLockLEDDevice())
        var applied: TimeInterval?
        settings.applyInterval = { applied = $0 }
        settings.setBlinkSpeed(.slow)
        t.check(defaults.string(forKey: BlinkSettings.speedKey) == BlinkSpeed.slow.rawValue, "setBlinkSpeed persists raw value")
        t.check(applied == BlinkSpeed.slow.interval, "setBlinkSpeed applies interval via closure")
        t.check(settings.blinkSpeed == .slow, "getter reflects new speed")
    }
}

func test_speedIntervals_areOrdered() {
    t.check(BlinkSpeed.fast.interval < BlinkSpeed.normal.interval && BlinkSpeed.normal.interval < BlinkSpeed.slow.interval,
            "fast < normal < slow intervals")
}

func test_blinker_setIntervalWhileRunning_keepsTicking() {
    let fake = FakeCapsLockLEDDevice()
    let blinker = Blinker(devices: [fake], interval: 0.5)
    blinker.start()
    blinker.setInterval(0.02)
    Thread.sleep(forTimeInterval: 0.15)
    blinker.stop()
    t.check(fake.calls.count >= 3, "setInterval while running keeps ticking at the new cadence")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift run BlinkRoutingTests`
Expected: FAIL to compile — `BlinkSpeed`, `BlinkSettings.speedKey`, `applyInterval`, and `Blinker.setInterval` don't exist yet.

- [ ] **Step 3: Implement**

Create `Sources/ThinkingCapsCore/BlinkSpeed.swift`:

```swift
import Foundation

public enum BlinkSpeed: String, CaseIterable {
    case slow
    case normal
    case fast

    public var interval: TimeInterval {
        switch self {
        case .slow: return 0.8
        case .normal: return 0.45
        case .fast: return 0.25
        }
    }

    public var displayName: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }
}
```

In `Sources/ThinkingCapsCore/Blinker.swift`, change `private let interval` to `private var interval` and add:

```swift
    public func setInterval(_ newInterval: TimeInterval) {
        interval = newInterval
        // Rescheduling an active DispatchSourceTimer updates its cadence live;
        // safe to call whether or not the blinker is currently running.
        timer?.schedule(deadline: .now() + newInterval, repeating: newInterval)
    }
```

In `Sources/ThinkingCapsCore/BlinkSettings.swift`, add:

```swift
    public static let speedKey = "blinkSpeed"

    /// Called with the new interval whenever the blink speed changes.
    public var applyInterval: ((TimeInterval) -> Void)?

    public var blinkSpeed: BlinkSpeed {
        guard let raw = defaults.string(forKey: Self.speedKey),
              let speed = BlinkSpeed(rawValue: raw) else {
            return .normal
        }
        return speed
    }

    public func setBlinkSpeed(_ speed: BlinkSpeed) {
        defaults.set(speed.rawValue, forKey: Self.speedKey)
        applyInterval?(speed.interval)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift run BlinkRoutingTests`
Expected: 13 previous + 7 new = twenty `PASS:` lines, `20/20 passed`, exit 0. (Count carefully: `test_setBlinkSpeed_persistsAndApplies` alone contributes three checks.) Also `swift run BlinkerTests` still 6/6 (file untouched).

- [ ] **Step 5: Add the Blink Speed submenu to `StatusItemController`**

Add stored properties:

```swift
    private let blinkSpeedMenu = NSMenu()
    private let blinkSpeedMenuItem = NSMenuItem()
```

In `configureMenu()`, after `rightClickMenu.addItem(blinkIconMenuItem)` and before the separator:

```swift
        blinkSpeedMenuItem.title = "Blink Speed"
        rightClickMenu.addItem(blinkSpeedMenuItem)
        for speed in BlinkSpeed.allCases {
            let item = NSMenuItem(title: speed.displayName, action: #selector(selectBlinkSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = speed.rawValue
            item.state = blinkSettings.blinkSpeed == speed ? .on : .off
            blinkSpeedMenu.addItem(item)
        }
        rightClickMenu.setSubmenu(blinkSpeedMenu, for: blinkSpeedMenuItem)
```

Add the action:

```swift
    @objc private func selectBlinkSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let speed = BlinkSpeed(rawValue: raw) else { return }
        blinkSettings.setBlinkSpeed(speed)
        for item in blinkSpeedMenu.items {
            item.state = (item.representedObject as? String) == speed.rawValue ? .on : .off
        }
    }
```

- [ ] **Step 6: Wire `AppDelegate`**

Add a stored property `private var blinker: Blinker?`. In `applicationDidFinishLaunching`, construct the blinker with the persisted speed and keep a reference, and wire `applyInterval`:

```swift
        let blinker = Blinker(devices: [blinkSettings.ledOutput, blinkSettings.iconOutput], interval: blinkSettings.blinkSpeed.interval)
        self.blinker = blinker
        blinkSettings.applyInterval = { [weak blinker] interval in
            blinker?.setInterval(interval)
        }
```

In `applicationShouldTerminate`, stop the blinker BEFORE stopping the socket server, so both outputs are restored to resting state on quit:

```swift
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        blinker?.stop()
        socketServer?.stop()
        return .terminateNow
    }
```

- [ ] **Step 7: Build and run the full test suite**

Run: `swift build && swift run SessionTrackerTests && swift run BlinkerTests && swift run HookSocketServerTests && swift run ClaudeHookInstallerTests && swift run PayloadParsingTests && swift run OnboardingFlowTests && swift run BlinkRoutingTests`
Expected: clean build; 6 + 6 + 8 + 6 + 3 + 4 + 20 = 53 checks, all green.

- [ ] **Step 8: Commit**

```bash
git add Sources/ThinkingCapsCore/Blinker.swift Sources/ThinkingCapsCore/BlinkSpeed.swift Sources/ThinkingCapsCore/BlinkSettings.swift Sources/ThinkingCapsCore/StatusItemController.swift Sources/ThinkingCapsCore/AppDelegate.swift Sources/BlinkRoutingTests/main.swift
git commit -m "Add blink speed setting (Slow/Normal/Fast) and restore blink outputs on quit"
```

- [ ] **Step 9: Manual verification (controller + user, after rebuild)**

1. Rebuild + relaunch; wizard reappears (rebuild invalidated the grant); user re-grants; success screen; Done.
2. Right-click: confirm Blink Speed submenu shows Slow/Normal/Fast with Normal checked.
3. Drive a session; switch speed to Fast mid-session — cadence visibly speeds up immediately; switch to Slow — visibly slows.
4. Quit the app mid-session (right-click > Quit while blinking) — the LED must NOT stay frozen lit; it returns to the real CapsLock state.
5. Relaunch; confirm the chosen speed persisted (submenu checkmark + observed cadence).
