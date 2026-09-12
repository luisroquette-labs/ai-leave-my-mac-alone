import Foundation

public struct MemorySnapshot: Equatable, Sendable {
    public let freeBytes: UInt64
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64

    public init(freeBytes: UInt64, swapUsedBytes: UInt64, swapTotalBytes: UInt64) {
        self.freeBytes = freeBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
    }

    public var swapUsedFraction: Double {
        guard swapTotalBytes > 0 else { return 0 }
        return Double(swapUsedBytes) / Double(swapTotalBytes)
    }
}

public enum MemoryLevel: String, Sendable {
    case normal
    case warning
    case critical
}

/// Limiares derivados do travamento real de 11/09/2026: dois builds Next.js órfãos
/// consumiram ~10GB de RAM, a livre caiu a ~19MB e o swap chegou a 95% de 20GB,
/// forçando o disco a fazer I/O constante de paginação e travando o Mac inteiro.
public enum MemoryPolicy {
    public static let freeBytesCriticalThreshold: UInt64 = 300 * 1_024 * 1_024
    public static let swapCriticalFraction = 0.90
    public static let swapWarningFraction = 0.75
    public static let reliefCooldown: TimeInterval = 60

    public static func isCritical(_ snapshot: MemorySnapshot) -> Bool {
        snapshot.freeBytes < freeBytesCriticalThreshold && snapshot.swapUsedFraction >= swapCriticalFraction
    }

    public static func level(for snapshot: MemorySnapshot) -> MemoryLevel {
        if isCritical(snapshot) { return .critical }
        if snapshot.swapUsedFraction >= swapWarningFraction { return .warning }
        return .normal
    }

    public static func shouldRunAutomaticRelief(
        snapshot: MemorySnapshot,
        enabled: Bool,
        isRelieving: Bool,
        lastReliefAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard enabled, !isRelieving, isCritical(snapshot) else { return false }
        guard let lastReliefAt else { return true }
        return now.timeIntervalSince(lastReliefAt) >= reliefCooldown
    }
}
