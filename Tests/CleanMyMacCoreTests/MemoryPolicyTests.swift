import Foundation
import Testing
@testable import CleanMyMac
@testable import CleanMyMacCore

@Test func memoryThresholdsAndCooldown() {
    let healthy = MemorySnapshot(freeBytes: 2 * 1_024 * 1_024 * 1_024, swapUsedBytes: 1, swapTotalBytes: 20 * 1_024 * 1_024 * 1_024)
    #expect(MemoryPolicy.level(for: healthy) == .normal)
    #expect(!MemoryPolicy.isCritical(healthy))

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

@Test func memoryReliefKillsSwappedOutOrphansByAge() {
    #expect(MemoryReliefTargetPolicy.shouldKill(
        command: "next-server (v16.3.0)", parentPID: 1, uptimeSeconds: 13 * 86_400
    ))
    #expect(!MemoryReliefTargetPolicy.shouldKill(
        command: "next-server (v16.3.4)", parentPID: 1, uptimeSeconds: 600
    ))
    #expect(!MemoryReliefTargetPolicy.shouldKill(
        command: "next-build (v16.3.4)", parentPID: 44, uptimeSeconds: 300
    ))
    #expect(!MemoryReliefTargetPolicy.shouldKill(
        command: "tsc --noEmit", parentPID: 44, uptimeSeconds: 13 * 86_400
    ))
    #expect(!MemoryReliefTargetPolicy.shouldKill(
        command: "next-server (v16.3.4)", parentPID: 1, uptimeSeconds: nil
    ))
    #expect(MemoryReliefTargetPolicy.shouldKill(
        command: "/usr/local/bin/node /x/node_modules/next/dist/telemetry/detached-flush.js dev /x",
        parentPID: 44, uptimeSeconds: 30
    ))
    #expect(!MemoryReliefTargetPolicy.shouldKill(
        command: "claude.exe next-server", parentPID: 1, uptimeSeconds: 90_000
    ))
    #expect(!MemoryReliefTargetPolicy.shouldKill(
        command: "/usr/sbin/fseventsd", parentPID: 1, uptimeSeconds: 900_000
    ))
}

@Test func memoryReliefParsesPsEtime() {
    let almostAnHour: TimeInterval = 2_922
    let longSession: TimeInterval = 64_318
    let thirteenDays: TimeInterval = 1_206_236
    #expect(MemoryReliefTargetPolicy.parseEtime("00:06") == 6)
    #expect(MemoryReliefTargetPolicy.parseEtime("48:42") == almostAnHour)
    #expect(MemoryReliefTargetPolicy.parseEtime("17:51:58") == longSession)
    #expect(MemoryReliefTargetPolicy.parseEtime("13-23:03:56") == thirteenDays)
    #expect(MemoryReliefTargetPolicy.parseEtime("  02:00 ") == 120)
    #expect(MemoryReliefTargetPolicy.parseEtime("") == nil)
    #expect(MemoryReliefTargetPolicy.parseEtime("abc") == nil)
    #expect(MemoryReliefTargetPolicy.parseEtime("1:2:3:4") == nil)
}

@Test func memoryReliefRevalidatesProcessIdentityBeforeSignals() {
    #expect(MemoryReliever.processIdentityOutputMatches(
        "  1 node /tmp/app/node_modules/.bin/tsc --noEmit\n",
        parentPID: 1,
        command: "node /tmp/app/node_modules/.bin/tsc --noEmit"
    ))
    #expect(!MemoryReliever.processIdentityOutputMatches(
        " 44 node /tmp/app/node_modules/.bin/tsc --noEmit\n",
        parentPID: 1,
        command: "node /tmp/app/node_modules/.bin/tsc --noEmit"
    ))
    #expect(!MemoryReliever.processIdentityOutputMatches(
        "  1 node /tmp/other.js\n",
        parentPID: 1,
        command: "node /tmp/app/node_modules/.bin/tsc --noEmit"
    ))
}

@Test func memorySnapshotSwapFraction() {
    let zeroTotal = MemorySnapshot(freeBytes: 0, swapUsedBytes: 0, swapTotalBytes: 0)
    #expect(zeroTotal.swapUsedFraction == 0)

    let half = MemorySnapshot(freeBytes: 0, swapUsedBytes: 10, swapTotalBytes: 20)
    #expect(half.swapUsedFraction == 0.5)
}
