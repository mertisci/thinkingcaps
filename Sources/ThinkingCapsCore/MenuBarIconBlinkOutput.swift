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
