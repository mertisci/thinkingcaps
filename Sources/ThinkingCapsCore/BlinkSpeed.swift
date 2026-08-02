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
