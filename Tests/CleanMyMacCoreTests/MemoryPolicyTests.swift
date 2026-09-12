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

@Test func memorySnapshotSwapFraction() {
    let zeroTotal = MemorySnapshot(freeBytes: 0, swapUsedBytes: 0, swapTotalBytes: 0)
    #expect(zeroTotal.swapUsedFraction == 0)

    let half = MemorySnapshot(freeBytes: 0, swapUsedBytes: 10, swapTotalBytes: 20)
    #expect(half.swapUsedFraction == 0.5)
}
