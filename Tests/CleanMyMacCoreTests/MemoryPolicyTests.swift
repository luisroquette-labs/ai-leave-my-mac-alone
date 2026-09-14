import Foundation
import Testing
@testable import CleanMyMac
@testable import CleanMyMacCore

@Test func memoryThresholdsAndCooldown() {
    let healthy = MemorySnapshot(freeBytes: 2 * 1_024 * 1_024 * 1_024, swapUsedBytes: 1, swapTotalBytes: 20 * 1_024 * 1_024 * 1_024)
    #expect(MemoryPolicy.level(for: healthy) == .normal)
    #expect(!MemoryPolicy.isCritical(healthy))

    // reproduz o travamento real de 11/09/2026: ~19MB livres, swap em 95% de 20GB
    let crashState = MemorySnapshot(
        freeBytes: 19 * 1_024 * 1_024,
        swapUsedBytes: UInt64(Double(20 * 1_024 * 1_024 * 1_024) * 0.95),
        swapTotalBytes: 20 * 1_024 * 1_024 * 1_024
    )
    #expect(MemoryPolicy.isCritical(crashState))
    #expect(MemoryPolicy.level(for: crashState) == .critical)

    let warningState = MemorySnapshot(freeBytes: 500 * 1_024 * 1_024, swapUsedBytes: 16 * 1_024 * 1_024 * 1_024, swapTotalBytes: 20 * 1_024 * 1_024 * 1_024)
    #expect(MemoryPolicy.level(for: warningState) == .warning)
    #expect(!MemoryPolicy.isCritical(warningState))

    let now = Date(timeIntervalSince1970: 100_000)
    #expect(MemoryPolicy.shouldRunAutomaticRelief(
        snapshot: crashState, enabled: true, isRelieving: false, lastReliefAt: nil, now: now
    ))
    #expect(!MemoryPolicy.shouldRunAutomaticRelief(
        snapshot: crashState, enabled: false, isRelieving: false, lastReliefAt: nil, now: now
    ))
    #expect(!MemoryPolicy.shouldRunAutomaticRelief(
        snapshot: crashState, enabled: true, isRelieving: true, lastReliefAt: nil, now: now
    ))
    #expect(!MemoryPolicy.shouldRunAutomaticRelief(
        snapshot: healthy, enabled: true, isRelieving: false, lastReliefAt: nil, now: now
    ))
    #expect(!MemoryPolicy.shouldRunAutomaticRelief(
        snapshot: crashState, enabled: true, isRelieving: false, lastReliefAt: now.addingTimeInterval(-59), now: now
    ))
    #expect(MemoryPolicy.shouldRunAutomaticRelief(
        snapshot: crashState, enabled: true, isRelieving: false, lastReliefAt: now.addingTimeInterval(-60), now: now
    ))
}

// REGRESSÃO 14/09/2026: swap a 96% num Mac de 16GB; o alívio disparou 1.278 vezes sem
// matar os culpados porque o filtro de RSS ≥ 1GB não enxerga processo paginado pro swap.
@Test func memoryReliefKillsSwappedOutOrphansByAge() {
    // caso real: next-server com 13 dias de uptime e RSS desinflado a ~300MB pelo swap
    #expect(MemoryReliefTargetPolicy.shouldKill(
        command: "next-server (v16.3.0)", rssKiB: 300_000, uptimeSeconds: 13 * 86_400
    ))
    // dev server jovem e leve segue vivo (sessão ativa de trabalho)
    #expect(!MemoryReliefTargetPolicy.shouldKill(
        command: "next-server (v16.3.4)", rssKiB: 300_000, uptimeSeconds: 600
    ))
    // comportamento antigo preservado: build jovem que estoura 1GB morre
    #expect(MemoryReliefTargetPolicy.shouldKill(
        command: "next-build (v16.3.4)", rssKiB: 1_200_000, uptimeSeconds: 300
    ))
    // sem etime legível, só o critério de RSS decide (comportamento antigo)
    #expect(!MemoryReliefTargetPolicy.shouldKill(
        command: "next-server (v16.3.4)", rssKiB: 300_000, uptimeSeconds: nil
    ))
    // órfão de telemetria do Next.js morre sempre, mesmo pequeno e jovem
    #expect(MemoryReliefTargetPolicy.shouldKill(
        command: "/usr/local/bin/node /x/node_modules/next/dist/telemetry/detached-flush.js dev /x",
        rssKiB: 10_000, uptimeSeconds: 30
    ))
    // neverKill vence qualquer critério
    #expect(!MemoryReliefTargetPolicy.shouldKill(
        command: "claude.exe next-server", rssKiB: 9_000_000, uptimeSeconds: 90_000
    ))
    // processo fora dos padrões nunca é alvo, por maior e mais velho que seja
    #expect(!MemoryReliefTargetPolicy.shouldKill(
        command: "/usr/sbin/fseventsd", rssKiB: 5_000_000, uptimeSeconds: 900_000
    ))
}

@Test func memoryReliefParsesPsEtime() {
    let almostAnHour: TimeInterval = 2_922 // 48:42
    let longSession: TimeInterval = 64_318 // 17:51:58
    let thirteenDays: TimeInterval = 1_206_236 // 13-23:03:56
    #expect(MemoryReliefTargetPolicy.parseEtime("00:06") == 6)
    #expect(MemoryReliefTargetPolicy.parseEtime("48:42") == almostAnHour)
    #expect(MemoryReliefTargetPolicy.parseEtime("17:51:58") == longSession)
    #expect(MemoryReliefTargetPolicy.parseEtime("13-23:03:56") == thirteenDays)
    #expect(MemoryReliefTargetPolicy.parseEtime("  02:00 ") == 120)
    #expect(MemoryReliefTargetPolicy.parseEtime("") == nil)
    #expect(MemoryReliefTargetPolicy.parseEtime("abc") == nil)
    #expect(MemoryReliefTargetPolicy.parseEtime("1:2:3:4") == nil)
}

@Test func memorySnapshotSwapFraction() {
    let zeroTotal = MemorySnapshot(freeBytes: 0, swapUsedBytes: 0, swapTotalBytes: 0)
    #expect(zeroTotal.swapUsedFraction == 0)

    let half = MemorySnapshot(freeBytes: 0, swapUsedBytes: 10, swapTotalBytes: 20)
    #expect(half.swapUsedFraction == 0.5)
}
