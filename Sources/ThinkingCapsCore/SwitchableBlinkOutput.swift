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
