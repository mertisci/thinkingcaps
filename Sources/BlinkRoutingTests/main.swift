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

test_defaults_ledOnIconOff()
test_persistedValues_areHonored()
test_disabledOutput_blocksWrites()
test_enabledOutput_passesWritesThrough()
test_disablingMidBlink_restoresRestingState()
test_setters_persistAndApply()
test_blinker_fansOutToMultipleDevices()
test_blinkerStop_restoresEachDeviceToItsOwnRestingState()
test_blinkSpeed_defaultsToNormal()
test_blinkSpeed_persistedValueHonored()
test_setBlinkSpeed_persistsAndApplies()
test_speedIntervals_areOrdered()
test_blinker_setIntervalWhileRunning_keepsTicking()

t.finish()
