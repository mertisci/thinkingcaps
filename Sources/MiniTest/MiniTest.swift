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
