import Foundation

public final class BlinkSettings {
    public static let ledKey = "blinkCapsLockLED"
    public static let iconKey = "blinkMenuBarIcon"
    public static let speedKey = "blinkSpeed"

    private let defaults: UserDefaults
    public let ledOutput: SwitchableBlinkOutput
    public let iconOutput: SwitchableBlinkOutput

    /// Called with the new interval whenever the blink speed changes.
    public var applyInterval: ((TimeInterval) -> Void)?

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
}
