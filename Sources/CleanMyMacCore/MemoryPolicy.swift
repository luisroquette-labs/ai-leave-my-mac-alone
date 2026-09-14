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

/// Decisão pura de alvo do alívio de memória, extraída do MemoryReliever para teste.
///
/// REGRESSÃO 14/09/2026: com o swap a 96%, o macOS pagina os processos culpados e o
/// RSS deles desinfla (next-servers de 13 dias apareciam com ~300MB residentes e 2–3GB
/// no swap). O filtro antigo de RSS ≥ 1GB ficava cego exatamente na hora crítica —
/// o alívio disparou 1.278 vezes sem matar os órfãos. A idade do processo é o sinal
/// que sobrevive à paginação: alvo de build/dev com horas de uptime é órfão.
public enum MemoryReliefTargetPolicy {
    public static let targetPatterns = [
        "next-build", "tsc --", "webpack", "vite build",
        "turbo run", "turbo build", "esbuild", "rollup", "jest ", "vitest run", "next-server",
    ]
    public static let neverKill = [
        "Comet", "Terminal", "claude.exe", "Finder", "WindowServer",
        "loginwindow", "kernel_task", "Dock", "SystemUIServer", "iTerm",
    ]
    /// Lixo puro: telemetria do Next.js que deveria durar segundos e fica órfã aos montes.
    public static let alwaysKillPatterns = ["next/dist/telemetry/detached-flush.js"]
    public static let minimumRSSKiB: UInt64 = 1_000_000 // 1GB
    public static let orphanUptimeSeconds: TimeInterval = 2 * 3_600

    public static func shouldKill(command: String, rssKiB: UInt64, uptimeSeconds: TimeInterval?) -> Bool {
        guard !neverKill.contains(where: { command.contains($0) }) else { return false }
        if alwaysKillPatterns.contains(where: { command.contains($0) }) { return true }
        guard targetPatterns.contains(where: { command.contains($0) }) else { return false }
        if rssKiB >= minimumRSSKiB { return true }
        guard let uptimeSeconds else { return false }
        return uptimeSeconds >= orphanUptimeSeconds
    }

    /// Converte o formato etime do ps ([[dd-]hh:]mm:ss) em segundos.
    public static func parseEtime(_ raw: String) -> TimeInterval? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let dayParts = trimmed.split(separator: "-", maxSplits: 1)
        var days = 0.0
        let clock: Substring
        if dayParts.count == 2 {
            guard let parsed = Double(dayParts[0]) else { return nil }
            days = parsed
            clock = dayParts[1]
        } else {
            clock = dayParts[0]
        }
        let components = clock.split(separator: ":")
        guard (1...3).contains(components.count) else { return nil }
        var seconds = 0.0
        for component in components {
            guard let value = Double(component) else { return nil }
            seconds = seconds * 60 + value
        }
        return days * 86_400 + seconds
    }
}
