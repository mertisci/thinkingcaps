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
