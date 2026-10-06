import Darwin
import Foundation

public enum StorageLevel: String, Sendable {
    case normal
    case warning
    case critical
}

public struct StorageSnapshot: Equatable, Sendable {
    public let totalBytes: UInt64
    public let availableBytes: UInt64

    public init(totalBytes: UInt64, availableBytes: UInt64) {
        self.totalBytes = totalBytes
        self.availableBytes = min(availableBytes, totalBytes)
    }

    public var usedBytes: UInt64 { totalBytes - availableBytes }
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
    public var usedPercent: Int { Int((usedFraction * 100).rounded()) }
}

public enum StoragePolicy {
    public static let warningThreshold = 0.75
    public static let cleanupThreshold = 0.78
    public static let hardLimit = 0.80
    public static let emergencyThreshold = 0.95
    public static let warningResetThreshold = 0.73
    public static let cleanupCooldown: TimeInterval = 60
    public static let hardLimitCleanupCooldown: TimeInterval = 300
    public static let noProgressCleanupCooldown: TimeInterval = 300
    public static let maximumNoProgressCleanupCooldown: TimeInterval = 1_800
    public static let normalMonitoringInterval: TimeInterval = 30
    public static let pressureMonitoringInterval: TimeInterval = 5
    public static let meaningfulProgressBytes: UInt64 = 100 * 1_024 * 1_024

    public static func level(for usedFraction: Double) -> StorageLevel {
        if reaches(usedFraction, threshold: cleanupThreshold) { return .critical }
        if reaches(usedFraction, threshold: warningThreshold) { return .warning }
        return .normal
    }

    public static func shouldResetWarning(for usedFraction: Double) -> Bool {
        !reaches(usedFraction, threshold: warningResetThreshold)
    }

    public static func shouldRunAutomaticCleanup(
        usedFraction: Double,
        enabled: Bool,
        isCleaning: Bool,
        lastCleanupAt: Date?,
        lastCleanupMadeProgress: Bool = true,
        noProgressStreak: Int = 1,
        now: Date = Date()
    ) -> Bool {
        guard enabled, !isCleaning, reaches(usedFraction, threshold: cleanupThreshold) else { return false }
        guard let lastCleanupAt else { return true }
        return now.timeIntervalSince(lastCleanupAt) >= cleanupCooldown(
            for: usedFraction,
            lastCleanupMadeProgress: lastCleanupMadeProgress,
            noProgressStreak: noProgressStreak
        )
    }

    public static func cleanupCooldown(
        for usedFraction: Double,
        lastCleanupMadeProgress: Bool = true,
        noProgressStreak: Int = 1
    ) -> TimeInterval {
        // Sem progresso vence o limite rígido: repetir uma varredura que não acha
        // nada só ocupa I/O (195 rodadas inúteis em 02/10/2026).
        if !lastCleanupMadeProgress {
            let doublings = Double(min(max(noProgressStreak, 1), 8) - 1)
            return min(noProgressCleanupCooldown * pow(2, doublings), maximumNoProgressCleanupCooldown)
        }
        if isAtOrAboveHardLimit(usedFraction) {
            return hardLimitCleanupCooldown
        }
        return cleanupCooldown
    }

    public static func shouldCleanNativeCaches(
        requested: Bool,
        escalateAtHardLimit: Bool,
        usedFractionAfterArtifacts: Double?
    ) -> Bool {
        if requested { return true }
        guard escalateAtHardLimit else { return false }
        guard let usedFractionAfterArtifacts else { return true }
        return isAtOrAboveHardLimit(usedFractionAfterArtifacts)
    }

    public static func monitoringInterval(for usedFraction: Double) -> TimeInterval {
        reaches(usedFraction, threshold: warningThreshold)
            ? pressureMonitoringInterval
            : normalMonitoringInterval
    }

    public static func isAtOrAboveHardLimit(_ usedFraction: Double) -> Bool {
        reaches(usedFraction, threshold: hardLimit)
    }

    public static func madeMeaningfulProgress(removedTargets: Int, freedBytes: UInt64) -> Bool {
        removedTargets > 0 || freedBytes >= meaningfulProgressBytes
    }

    public static func restoredCleanupProgress(lastCleanupAt: Date?, savedValue: Bool?) -> Bool {
        savedValue ?? (lastCleanupAt == nil)
    }

    private static func reaches(_ usedFraction: Double, threshold: Double) -> Bool {
        Int((usedFraction * 100).rounded()) >= Int((threshold * 100).rounded())
    }
}

public enum StorageReader {
    public static func read(path: String = "/System/Volumes/Data") throws -> StorageSnapshot {
        var statistics = statfs()
        guard statfs(path, &statistics) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        let blockSize = UInt64(statistics.f_bsize)
        return StorageSnapshot(
            totalBytes: UInt64(statistics.f_blocks) * blockSize,
            availableBytes: UInt64(statistics.f_bavail) * blockSize
        )
    }
}
