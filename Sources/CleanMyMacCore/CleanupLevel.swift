import Foundation

public enum CleanupLevel: String, CaseIterable, Comparable, Sendable {
    case safe
    case deep
    case emergency

    public static func < (lhs: CleanupLevel, rhs: CleanupLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    public var includesDeepCleanup: Bool { self >= .deep }
    public var includesEmergencyCleanup: Bool { self >= .emergency }

    private var rank: Int {
        switch self {
        case .safe: 0
        case .deep: 1
        case .emergency: 2
        }
    }
}
