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
