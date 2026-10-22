import Foundation
import Testing
@testable import CleanMyMac
@testable import CleanMyMacCore

@Test func thresholdsAndCooldown() {
    #expect(StoragePolicy.level(for: 0.74) == .normal)
    #expect(StoragePolicy.level(for: 0.745) == .warning)
    #expect(StoragePolicy.level(for: 0.75) == .warning)
    #expect(StoragePolicy.level(for: 0.775) == .critical)
    #expect(StoragePolicy.level(for: 0.78) == .critical)
    #expect(StoragePolicy.hardLimit == 0.80)
    #expect(StoragePolicy.emergencyThreshold == 0.95)
    #expect(StoragePolicy.shouldResetWarning(for: 0.72))
    #expect(StoragePolicy.isAtOrAboveHardLimit(0.796))
    #expect(!StoragePolicy.isAtOrAboveHardLimit(0.794))

    let now = Date(timeIntervalSince1970: 100_000)
    #expect(StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.78,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: nil,
        now: now
    ))
    #expect(StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.79,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-60),
        now: now
    ))
    #expect(StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.79,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-61),
        now: now
    ))
    #expect(!StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.774,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: nil,
        now: now
    ))
    #expect(!StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.80,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-15),
        now: now
    ))
    #expect(!StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.80,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-299),
        now: now
    ))
    #expect(!StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.97,
        enabled: false,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-121),
        now: now
    ))
    #expect(StoragePolicy.monitoringInterval(for: 0.74) == 30)
    #expect(StoragePolicy.monitoringInterval(for: 0.75) == 5)
    #expect(!StoragePolicy.madeMeaningfulProgress(freedBytes: 1_376_256))
    #expect(!StoragePolicy.madeMeaningfulProgress(freedBytes: 0))
    #expect(StoragePolicy.madeMeaningfulProgress(freedBytes: StoragePolicy.meaningfulProgressBytes))
    #expect(StoragePolicy.restoredCleanupProgress(lastCleanupAt: nil, savedValue: nil))
    #expect(!StoragePolicy.restoredCleanupProgress(lastCleanupAt: now, savedValue: nil))
    #expect(StoragePolicy.restoredCleanupProgress(lastCleanupAt: now, savedValue: true))
    #expect(StoragePolicy.cleanupCooldown(for: 0.81, lastCleanupMadeProgress: true) == 300)
    #expect(!StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.81,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-299),
        now: now
    ))
    #expect(StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.81,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-300),
        now: now
    ))
    #expect(StoragePolicy.shouldCleanNativeCaches(
        requested: false,
        escalateAtHardLimit: true,
        usedFractionAfterArtifacts: 0.81
    ))
    #expect(!StoragePolicy.shouldCleanNativeCaches(
        requested: false,
        escalateAtHardLimit: true,
        usedFractionAfterArtifacts: 0.79
    ))
    #expect(!StoragePolicy.shouldCleanNativeCaches(
        requested: false,
        escalateAtHardLimit: true,
        usedFractionAfterArtifacts: 0.796
    ))
    #expect(!StoragePolicy.shouldCleanNativeCaches(
        requested: false,
        escalateAtHardLimit: true,
        usedFractionAfterArtifacts: nil
    ))
    #expect(StoragePolicy.cleanupLevel(
        requested: nil,
        automaticMaximum: .safe,
        isAutomatic: true,
        usedFraction: 0.80
    ) == .safe)
    #expect(StoragePolicy.cleanupLevel(
        requested: nil,
        automaticMaximum: .safe,
        isAutomatic: true,
        usedFraction: 0.79
    ) == .safe)
    #expect(StoragePolicy.cleanupLevel(
        requested: .safe,
        automaticMaximum: .emergency,
        isAutomatic: true,
        usedFraction: 0.95
    ) == .safe)
    #expect(StoragePolicy.cleanupLevel(
        requested: nil,
        automaticMaximum: .emergency,
        isAutomatic: true,
        usedFraction: 0.95
    ) == .emergency)
}

@Test func cleanupLevelsAreOrderedAndEmergencyTargetsRetainRecentArchives() {
    #expect(CleanupLevel.safe < .deep)
    #expect(CleanupLevel.deep < .emergency)
    #expect(!CleanupLevel.safe.includesDeepCleanup)
    #expect(CleanupLevel.deep.includesDeepCleanup)
    #expect(CleanupLevel.emergency.includesEmergencyCleanup)

    let now = Date(timeIntervalSince1970: 1_000_000)
    let oldArchive = "/Users/example/.codex/archives/2026/old.jsonl"
    #expect(CleanupPolicy.isEligibleArchivedSession(
        path: oldArchive,
        resolvedPath: oldArchive,
        homePath: "/Users/example",
        modificationDate: now.addingTimeInterval(-CleanupPolicy.archivedSessionMinimumAge),
        now: now
    ))
    #expect(!CleanupPolicy.isEligibleArchivedSession(
        path: oldArchive,
        resolvedPath: oldArchive,
        homePath: "/Users/example",
        modificationDate: now.addingTimeInterval(-(CleanupPolicy.archivedSessionMinimumAge - 1)),
        now: now
    ))
    #expect(!CleanupPolicy.isEligibleArchivedSession(
        path: "/Users/example/.codex/sessions/live.jsonl",
        resolvedPath: "/Users/example/.codex/sessions/live.jsonl",
        homePath: "/Users/example",
        modificationDate: now.addingTimeInterval(-CleanupPolicy.archivedSessionMinimumAge),
        now: now
    ))
    #expect(CleanupPolicy.emergencyDirectoryPaths(homePath: "/Users/example") == [
        "/Users/example/Library/Application Support/Claude/vm_bundles",
    ])
}

// REGRESSÃO (21/10/2026): a varredura de worktrees levava até 8 minutos,
// encontrava zero candidatos e era repetida em toda rodada de emergência.
@Test func emptyWholeWorktreeScanGetsOneHourCooldown() {
    let now = Date(timeIntervalSince1970: 100_000)
    #expect(StoragePolicy.shouldScanWholeWorktrees(lastEmptyScanAt: nil, now: now))
    #expect(!StoragePolicy.shouldScanWholeWorktrees(
        lastEmptyScanAt: now.addingTimeInterval(-3_599),
        now: now
    ))
    #expect(StoragePolicy.shouldScanWholeWorktrees(
        lastEmptyScanAt: now.addingTimeInterval(-3_600),
        now: now
    ))
    #expect(StoragePolicy.shouldScanWholeWorktrees(
        lastEmptyScanAt: now.addingTimeInterval(1),
        now: now
    ))
}

@Test func cleanupReportsExactShortfallBelowHardLimit() {
    let alreadyBelow = StorageSnapshot(totalBytes: 1_000, availableBytes: 201)
    #expect(StoragePolicy.bytesRequiredToGetBelowHardLimit(alreadyBelow) == 0)
    #expect(!StoragePolicy.hasUnresolvedHardLimit(alreadyBelow))
    #expect(StoragePolicy.bytesRequiredToGetBelowHardLimit(
        StorageSnapshot(totalBytes: 1_000, availableBytes: 200)
    ) == 1)
    #expect(StoragePolicy.hasUnresolvedHardLimit(
        StorageSnapshot(totalBytes: 1_000, availableBytes: 200)
    ))
    #expect(StoragePolicy.bytesRequiredToGetBelowHardLimit(
        StorageSnapshot(totalBytes: 1_000, availableBytes: 150)
    ) == 51)
}

@Test func storageSnapshotNeverReportsNegativeUsage() {
    let snapshot = StorageSnapshot(totalBytes: 100, availableBytes: 120)
    #expect(snapshot.availableBytes == 100)
    #expect(snapshot.usedBytes == 0)
    #expect(snapshot.usedPercent == 0)
}

@Test func cleanupPolicyProtectsUnicodePathsAndRejectsUnsafeArtifacts() {
    let protected = ["/Users/example/Arquivos Públicos"]
    let decomposed = "/Users/example/Arquivos Públicos/Mac/Warning/Default"
    #expect(CleanupPolicy.isProtected(decomposed, protectedPaths: protected))
    #expect(CleanupPolicy.isProtected(
        "/Users/example/Projects/client/Warning/Default/node_modules",
        protectedPaths: []
    ))
    #expect(!CleanupPolicy.isProtected(
        "/Users/example/Projects/client/Warning/Preview/node_modules",
        protectedPaths: []
    ))
    #expect(CleanupPolicy.pathsOverlap("/project", "/project/worktree"))
    #expect(CleanupPolicy.isEligibleArtifact(
        name: "node_modules",
        sizeKiB: 102_400,
        isSymbolicLink: false,
        minimumKiB: 102_400
    ))
    #expect(!CleanupPolicy.isEligibleArtifact(
        name: "Downloads",
        sizeKiB: 1_000_000,
        isSymbolicLink: false,
        minimumKiB: 102_400
    ))
    #expect(!CleanupPolicy.isEligibleArtifact(
        name: ".next",
        sizeKiB: 200_000,
        isSymbolicLink: true,
        minimumKiB: 102_400
    ))
    #expect(!CleanupPolicy.shouldExcludeDirectory(named: ".claude"))
    #expect(CleanupPolicy.shouldExcludeDirectory(named: "claude-501"))
    #expect(!CleanupPolicy.shouldExcludeDirectory(named: "cfgauss-claude-site"))
    #expect(!CleanupPolicy.excludedDirectoryPatterns.contains(".claude"))
    #expect(CleanupPolicy.excludedDirectoryPatterns.contains("claude-*"))
    #expect(CleanupPolicy.isProtected(
        "/Users/example/.claude/memory/node_modules",
        protectedPaths: ["/Users/example/.claude"]
    ))
    #expect(!CleanupPolicy.isProtected(
        "/Users/example/Projects/app/.claude/worktrees/task/.next",
        protectedPaths: ["/Users/example/.claude"]
    ))
    #expect(CleanupPolicy.isProjectActive(
        "/project",
        activeDirectories: ["/project/app"]
    ))
    #expect(CleanupPolicy.isProjectActive(
        "/project",
        activeDirectories: ["/project"]
    ))
    #expect(!CleanupPolicy.isProjectActive(
        "/Users/example/Projects/app",
        activeDirectories: ["/Users/example"]
    ))
    #expect(!CleanupPolicy.isProjectActive(
        "/Users/example/Projects/app",
        activeDirectories: ["/"]
    ))
    #expect(!CleanupPolicy.isProjectActive(
        "/project",
        activeDirectories: ["/other/app"]
    ))
}

@Test func cleanupPolicyRecognizesOnlyRegenerableBuildDirectories() {
    for name in ["node_modules", ".next", ".build", ".turbo", ".venv", "DerivedData", "dist"] {
        #expect(CleanupPolicy.isEligibleArtifact(
            name: name, sizeKiB: 100, isSymbolicLink: false, minimumKiB: 100
        ))
    }
    #expect(!CleanupPolicy.isEligibleArtifact(
        name: "build", sizeKiB: 100, isSymbolicLink: false, minimumKiB: 100
    ))
    #expect(!CleanupPolicy.isEligibleArtifact(
        name: "dist", sizeKiB: 99, isSymbolicLink: false, minimumKiB: 100
    ))
    #expect(!CleanupPolicy.isEligibleArtifact(
        name: ".venv", sizeKiB: 100, isSymbolicLink: true, minimumKiB: 100
    ))
    #expect(CleanupPolicy.hasOnlyRegenerableIgnoredPaths([
        "node_modules/", "apps/web/.next/", ".build/", "tsconfig.tsbuildinfo",
        "next-env.d.ts", ".swc/", "playwright-report/", "test-results/", "coverage/",
    ]))
    for protectedPath in [".env", ".env.local", ".vercel/", ".qlaude/", "graphify-out/", "outputs/"] {
        #expect(!CleanupPolicy.hasOnlyRegenerableIgnoredPaths([protectedPath]))
    }
}

@Test func aggressiveCacheCleanupIsBoundedAndNeverTargetsProfilesOrSessions() {
    let paths = CleanupPolicy.regenerableCachePaths(homePath: "/Users/example")
    #expect(paths.contains("/Users/example/.npm/_npx"))
    #expect(paths.contains("/Users/example/Library/Developer/Xcode/DerivedData"))
    #expect(CleanupPolicy.lastResortCachePaths(homePath: "/Users/example") == [
        "/Users/example/Library/pnpm/store",
        "/Users/example/.cache/codex-runtimes",
    ])
    #expect(!paths.contains { $0.contains("Library/Application Support") })
    #expect(!paths.contains { $0.contains("/.codex/") || $0.contains("/.claude/") })
    #expect(!paths.contains { $0.hasSuffix("/Default") })
    #expect(CleanupPolicy.browserCacheLeafNames.contains("Cache"))
    #expect(!CleanupPolicy.browserCacheLeafNames.contains("Storage"))
    #expect(!CleanupPolicy.browserCacheLeafNames.contains("Default"))

    let now = Date(timeIntervalSince1970: 100_000)
    #expect(CleanupPolicy.shouldCleanAggressiveCachePath(lastCleanedAt: nil, now: now))
    #expect(!CleanupPolicy.shouldCleanAggressiveCachePath(
        lastCleanedAt: now.addingTimeInterval(-3_600), now: now
    ))
    #expect(CleanupPolicy.shouldCleanAggressiveCachePath(
        lastCleanedAt: now.addingTimeInterval(-CleanupPolicy.aggressiveCacheCooldown),
        now: now
    ))
    #expect(CleanupPolicy.shouldCleanAggressiveCachePath(
        lastCleanedAt: now.addingTimeInterval(3_600),
        now: now
    ))
    #expect(CleanupPolicy.isSafeCacheCandidate(
        path: "/Users/example/Library/Caches/Codex/Default/Cache",
        resolvedPath: "/Users/example/Library/Caches/Codex/Default/Cache"
    ))
    #expect(!CleanupPolicy.isSafeCacheCandidate(
        path: "/Users/example/Library/Caches/Codex/Default/Cache",
        resolvedPath: "/Users/example/Pictures/Warning/Default/Cache"
    ))
    #expect(CleanupPolicy.isOwnedDeleteBatch(
        path: "/Users/example/.Trash/CleanMyMac-DeleteBatch-123-uuid",
        trashRoot: "/Users/example/.Trash"
    ))
    #expect(!CleanupPolicy.isOwnedDeleteBatch(
        path: "/Users/example/.Trash/CleanMyMac-123-uuid",
        trashRoot: "/Users/example/.Trash"
    ))
    #expect(!CleanupPolicy.isOwnedDeleteBatch(
        path: "/Users/example/.Trash/nested/CleanMyMac-DeleteBatch-123-uuid",
        trashRoot: "/Users/example/.Trash"
    ))
    #expect(!CleanupPolicy.isOwnedDeleteBatch(
        path: "/Users/example/.Trash/CleanMyMac-DeleteBatch-123-\"bad",
        trashRoot: "/Users/example/.Trash"
    ))
    #expect(CleanupPolicy.bytesToStageFromAggressiveCaches(shortfall: 1_000) ==
        1_000 + CleanupPolicy.aggressiveCacheReclaimReserveBytes)
    #expect(CleanupPolicy.bytesToStageFromAggressiveCaches(shortfall: UInt64.max) == UInt64.max)
    #expect(!CleanupPolicy.reachedCleanupTarget(bytesRequired: 0, stagedBytes: 0))
    #expect(!CleanupPolicy.reachedCleanupTarget(bytesRequired: 100, stagedBytes: 99))
    #expect(CleanupPolicy.reachedCleanupTarget(bytesRequired: 100, stagedBytes: 100))
}

@Test func agentCacheArtifactsResolveToTheirTopLevelProject() {
    let root = URL(filePath: "/Users/example/.cache/codex", directoryHint: .isDirectory)
    let nested = root.appending(path: "active-project/apps/web/node_modules", directoryHint: .isDirectory)
    #expect(SafeCleaner.agentCacheProjectRoot(for: nested, under: root)?.path ==
        "/Users/example/.cache/codex/active-project")
    #expect(SafeCleaner.agentCacheProjectRoot(
        for: URL(filePath: "/Users/example/Projects/app/node_modules"),
        under: root
    ) == nil)
}

@Test func lastResortCacheRequiresConclusiveOpenFileInspection() {
    #expect(SafeCleaner.confirmsNoOpenFiles(CommandResult(code: 1, output: "")))
    #expect(!SafeCleaner.confirmsNoOpenFiles(CommandResult(code: 0, output: "COMMAND PID")))
    #expect(!SafeCleaner.confirmsNoOpenFiles(CommandResult(code: 124, output: "tempo limite")))
}

@Test func worktreeMetadataSearchPrunesRegenerableTrees() {
    let arguments = SafeCleaner.worktreeMetadataSearchArguments(containerPath: "/worktrees")
    #expect(arguments.prefix(5) == ["/worktrees", "-mindepth", "1", "-maxdepth", "4"])
    for name in ["node_modules", ".next", ".build", ".git"] {
        #expect(arguments.contains(name))
    }
    #expect(Array(arguments.suffix(6)) == ["-o", "-name", ".git", "-type", "f", "-print0"])
}

@Test func pnpmCleanupRejectsCorepackShimsThatMayDownloadPackages() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let corepack = root.appending(path: "lib/node_modules/corepack/dist", directoryHint: .isDirectory)
    let shim = root.appending(path: "bin/pnpm")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: corepack, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: shim.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: corepack.appending(path: "pnpm.js"))
    try FileManager.default.createSymbolicLink(
        atPath: shim.path,
        withDestinationPath: "../lib/node_modules/corepack/dist/pnpm.js"
    )

    #expect(SafeCleaner.isCorepackShim(shim.path))
    #expect(!SafeCleaner.isCorepackShim("/bin/echo"))
}

@Test func cleanupPolicyKeepsArtifactsInsideTheirGitRoot() {
    let roots = CleanupPolicy.artifactScanRoots(homePath: "/Users/example")
    #expect(roots.contains("/Users/example/Projects"))
    #expect(!roots.contains("/private/tmp"))
    #expect(CleanupPolicy.shouldExcludeDirectory(named: "claude-501"))
    #expect(CleanupPolicy.pathsOverlap("/Users/example/Projects/app/node_modules", "/Users/example/Projects/app"))
    #expect(!CleanupPolicy.pathsOverlap("/Users/example/Other/node_modules", "/Users/example/Projects/app"))
    #expect(CleanupPolicy.isProtected(
        "/Users/example/Documents/client/node_modules",
        protectedPaths: ["/Users/example/Documents"]
    ))
}

@Test func cleanupVerificationFailsClosedWhenGitFailsOrTargetReturns() {
    #expect(CleanupPolicy.isVerifiedAfterCleanup(
        statusBefore: " M source.swift",
        statusAfter: " M source.swift",
        statusAfterExitCode: 0,
        targetStillExists: false
    ))
    #expect(!CleanupPolicy.isVerifiedAfterCleanup(
        statusBefore: "fatal: repository unavailable",
        statusAfter: "fatal: repository unavailable",
        statusAfterExitCode: 128,
        targetStillExists: false
    ))
    #expect(!CleanupPolicy.isVerifiedAfterCleanup(
        statusBefore: "",
        statusAfter: " M source.swift",
        statusAfterExitCode: 0,
        targetStillExists: false
    ))
    #expect(!CleanupPolicy.isVerifiedAfterCleanup(
        statusBefore: "",
        statusAfter: "",
        statusAfterExitCode: 0,
        targetStillExists: true
    ))
}

@Test func cleanupDestinationRequiresExternalVolume() {
    #expect(CleanupDestinationPolicy.isExternalBackupPath("/Volumes/ESPACO/Backups"))
    #expect(!CleanupDestinationPolicy.isExternalBackupPath("/Users/example/Backups"))
    #expect(!CleanupDestinationPolicy.isExternalBackupPath("/Volumes"))
}

@Test func backupVerifierRejectsChangedCopies() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    let source = root.appending(path: "source")
    let destination = root.appending(path: "destination")
    defer { try? fileManager.removeItem(at: root) }

    try fileManager.createDirectory(at: source.appending(path: "nested"), withIntermediateDirectories: true)
    try Data("conteúdo verificado".utf8).write(to: source.appending(path: "nested/file.txt"))
    try fileManager.createSymbolicLink(
        atPath: source.appending(path: "link.txt").path,
        withDestinationPath: "nested/file.txt"
    )
    try fileManager.copyItem(at: source, to: destination)
    try BackupVerifier.verifyCopy(source: source, destination: destination)

    try Data("conteúdo alterado".utf8).write(to: destination.appending(path: "nested/file.txt"))
    #expect(throws: BackupVerificationError.self) {
        try BackupVerifier.verifyCopy(source: source, destination: destination)
    }
}

@Test func verifiedBackupStagesOriginalBeforeDeletion() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    let source = root.appending(path: "source")
    let backup = root.appending(path: "external/backup")
    let removalStaging = root.appending(path: "trash/source")
    defer { try? fileManager.removeItem(at: root) }

    try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("backup seguro".utf8).write(to: source.appending(path: "artifact.txt"))

    try BackupVerifier.copyVerifiedAndStageRemoval(
        source: source,
        backup: backup,
        removalStaging: removalStaging
    )

    #expect(!fileManager.fileExists(atPath: source.path))
    #expect(fileManager.fileExists(atPath: backup.path))
    #expect(fileManager.fileExists(atPath: removalStaging.path))
    try BackupVerifier.verifyCopy(source: backup, destination: removalStaging)
}

@Test func failedBackupRestoresOriginalPath() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    let source = root.appending(path: "source")
    let blockedParent = root.appending(path: "not-a-directory")
    let backup = blockedParent.appending(path: "backup")
    let removalStaging = root.appending(path: "trash/source")
    defer { try? fileManager.removeItem(at: root) }

    try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("original preservado".utf8).write(to: source.appending(path: "artifact.txt"))
    try Data("arquivo".utf8).write(to: blockedParent)

    #expect(throws: Error.self) {
        try BackupVerifier.copyVerifiedAndStageRemoval(
            source: source,
            backup: backup,
            removalStaging: removalStaging
        )
    }
    #expect(fileManager.fileExists(atPath: source.path))
    #expect(!fileManager.fileExists(atPath: removalStaging.path))
}

@Test func backupVerifierFailsClosedOnUnreadableTree() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    let source = root.appending(path: "source")
    let destination = root.appending(path: "destination")
    let sourceLocked = source.appending(path: "locked")
    let destinationLocked = destination.appending(path: "locked")
    defer { try? fileManager.removeItem(at: root) }

    try fileManager.createDirectory(at: sourceLocked, withIntermediateDirectories: true)
    try Data("segredo".utf8).write(to: sourceLocked.appending(path: "file.txt"))
    try fileManager.copyItem(at: source, to: destination)
    try fileManager.setAttributes([.posixPermissions: 0], ofItemAtPath: sourceLocked.path)
    try fileManager.setAttributes([.posixPermissions: 0], ofItemAtPath: destinationLocked.path)
    defer {
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sourceLocked.path)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destinationLocked.path)
    }

    #expect(throws: BackupVerificationError.self) {
        try BackupVerifier.verifyCopy(source: source, destination: destination)
    }
}

@Test func cleanupLogRotationIsBounded() {
    #expect(!CleanupLogPolicy.shouldRotate(size: CleanupLogPolicy.maximumBytes - 1))
    #expect(CleanupLogPolicy.shouldRotate(size: CleanupLogPolicy.maximumBytes))
}

@Test func nativeCacheCommandStopsAtTimeout() {
    let startedAt = Date()
    let result = SafeCleaner.runCommand("/bin/sleep", ["5"], timeout: 0.05)
    #expect(result.code == 124)
    #expect(Date().timeIntervalSince(startedAt) < 1)
}

@Test func commandRunnerCapturesOutput() {
    let result = SafeCleaner.runCommand("/bin/echo", ["capturado"], timeout: 1)
    #expect(result.code == 0)
    #expect(result.output == "capturado\n")
}

@Test func commandRunnerUsesRequestedWorkingDirectory() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let result = SafeCleaner.runCommand("/bin/pwd", [], currentDirectoryURL: directory)
    #expect(result.code == 0)
    let reportedDirectory = URL(
        filePath: result.output.trimmingCharacters(in: .whitespacesAndNewlines),
        directoryHint: .isDirectory
    )
    #expect(reportedDirectory.resolvingSymlinksInPath() == directory.resolvingSymlinksInPath())
}

@Test func scanFailureLogMessageReportsCommandFailure() {
    let failure = CommandResult(code: 1, output: "Permission denied")
    let message = SafeCleaner.scanFailureLogMessage(
        operation: "varredura de artefatos",
        path: "/tmp/example",
        result: failure
    )
    #expect(message == "ERROR varredura de artefatos: /tmp/example Permission denied")
}

@Test func scanFailureLogMessageIsNilOnSuccess() {
    let success = CommandResult(code: 0, output: "")
    #expect(SafeCleaner.scanFailureLogMessage(
        operation: "varredura de artefatos",
        path: "/tmp/example",
        result: success
    ) == nil)
}

@Test func scanFailureLogMessageSanitizesControlCharacters() {
    let failure = CommandResult(code: 1, output: "line1\0line2\nline3\ttrailing")
    let message = SafeCleaner.scanFailureLogMessage(
        operation: "varredura de artefatos",
        path: "/tmp/example",
        result: failure
    )
    #expect(message == "ERROR varredura de artefatos: /tmp/example line1 line2 line3 trailing")
    #expect(message?.contains("\0") == false)
    #expect(message?.contains("\n") == false)
}

@Test func scanFailureLogMessageCapsReasonLength() {
    let longOutput = String(repeating: "x", count: 5_000)
    let failure = CommandResult(code: 1, output: longOutput)
    let message = SafeCleaner.scanFailureLogMessage(
        operation: "varredura de artefatos",
        path: "/tmp/example",
        result: failure
    )
    let prefix = "ERROR varredura de artefatos: /tmp/example "
    #expect(message?.hasPrefix(prefix) == true)
    let reason = message!.dropFirst(prefix.count)
    #expect(reason.count <= 201)
}

@Test func parseDuSizeKiBParsesLeadingNumber() {
    #expect(SafeCleaner.parseDuSizeKiB("1024\t/tmp/example") == 1024)
}

@Test func parseDuSizeKiBReturnsNilOnUnparseableOutput() {
    #expect(SafeCleaner.parseDuSizeKiB("not-a-number") == nil)
    #expect(SafeCleaner.parseDuSizeKiB("") == nil)
}

@Test func scanFailureLogMessageSanitizesControlCharactersInPath() {
    // A POSIX path can't contain NUL (it's a null-terminated C string), but it can
    // legitimately contain a newline or tab — APFS/HFS+ only forbid "/" and NUL.
    let failure = CommandResult(code: 1, output: "boom")
    let message = SafeCleaner.scanFailureLogMessage(
        operation: "varredura de artefatos",
        path: "/tmp/weird\nname\there",
        result: failure
    )
    #expect(message == "ERROR varredura de artefatos: /tmp/weird name here boom")
    #expect(message?.contains("\n") == false)
    #expect(message?.contains("\t") == false)
}

// REGRESSÃO (28/09/2026): a limpeza automática apagou 47 node_modules, inclusive
// de worktrees em uso por sessões de agente (~8x numa sessão em 15/09) — o
// detector de processo ativo não vê agentes sem cwd na worktree. Worktree
// (.git é arquivo) só entra no lote quando ociosa; clone normal continua elegível.
@Test func linkedWorktreesAreDetected() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let worktree = root.appending(path: "worktree")
    let clone = root.appending(path: "clone")
    try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: clone.appending(path: ".git"), withIntermediateDirectories: true)
    try Data("gitdir: /repo/.git/worktrees/x\n".utf8).write(to: worktree.appending(path: ".git"))
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(CleanupPolicy.isLinkedWorktree(worktree.path))
    #expect(!CleanupPolicy.isLinkedWorktree(clone.path))
    #expect(!CleanupPolicy.isLinkedWorktree(root.appending(path: "missing").path))
}

// REGRESSÃO (02/10/2026): pular TODA worktree deixou 55 GB de node_modules de
// trabalho já terminado acumularem até 97,6% do SSD — o terminal do agente fica
// aberto por dias, mas a worktree em si estava parada. Ociosa >= 4h (ou 1h com
// upstream apagado) entra no lote; atividade recente ou desconhecida, não.
@Test func idleWorktreesBecomeEligibleButActiveOnesStayProtected() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(CleanupPolicy.worktreeIdleThreshold == 4 * 3_600)
    #expect(!CleanupPolicy.isWorktreeIdle(lastActivity: nil, now: now, upstreamGone: false))
    #expect(!CleanupPolicy.isWorktreeIdle(lastActivity: nil, now: now, upstreamGone: true))
    #expect(!CleanupPolicy.isWorktreeIdle(lastActivity: now.addingTimeInterval(-(4 * 3_600 - 1)), now: now, upstreamGone: false))
    #expect(CleanupPolicy.isWorktreeIdle(lastActivity: now.addingTimeInterval(-4 * 3_600), now: now, upstreamGone: false))
    #expect(CleanupPolicy.isWorktreeIdle(lastActivity: now.addingTimeInterval(-5 * 86_400), now: now, upstreamGone: false))
    #expect(!CleanupPolicy.isWorktreeIdle(lastActivity: now.addingTimeInterval(-3_599), now: now, upstreamGone: true))
    #expect(CleanupPolicy.isWorktreeIdle(lastActivity: now.addingTimeInterval(-3_600), now: now, upstreamGone: true))
    #expect(!CleanupPolicy.isWorktreeIdle(lastActivity: now.addingTimeInterval(60), now: now, upstreamGone: false))
}

// REGRESSÃO (13/10/2026): limitar a limpeza a node_modules/.next deixou 43 GB
// de checkouts limpos e encerrados ocupando o SSD, enquanto o uso ficou em 92%.
// A worktree inteira só é recuperável após 24 h, com branch, limpa e sem processo.
@Test func onlyCleanInactiveBranchedWorktreesBecomeReclaimable() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let old = now.addingTimeInterval(-CleanupPolicy.reclaimableWorktreeIdleThreshold)
    #expect(CleanupPolicy.reclaimableWorktreeIdleThreshold == 24 * 3_600)
    #expect(CleanupPolicy.isReclaimableWorktree(
        isLinkedWorktree: true, hasBranch: true, isClean: true,
        isActive: false, lastActivity: old, now: now
    ))
    #expect(!CleanupPolicy.isReclaimableWorktree(
        isLinkedWorktree: true, hasBranch: true, isClean: false,
        isActive: false, lastActivity: old, now: now
    ))
    #expect(!CleanupPolicy.isReclaimableWorktree(
        isLinkedWorktree: true, hasBranch: true, isClean: true,
        isActive: true, lastActivity: old, now: now
    ))
    #expect(!CleanupPolicy.isReclaimableWorktree(
        isLinkedWorktree: true, hasBranch: false, isClean: true,
        isActive: false, lastActivity: old, now: now
    ))
    #expect(!CleanupPolicy.isReclaimableWorktree(
        isLinkedWorktree: true, hasBranch: true, isClean: true,
        isActive: false, lastActivity: now.addingTimeInterval(-86_399), now: now
    ))
}

@Test func worktreeContainersCoverAgentAndProjectLayouts() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let projects = root.appending(path: "Projects")
    try FileManager.default.createDirectory(at: projects.appending(path: "site/.worktrees"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: projects.appending(path: "site-worktrees"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appending(path: "other-worktrees"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let roots = Set(CleanupPolicy.worktreeContainerRoots(homePath: root.path).map {
        URL(filePath: $0).resolvingSymlinksInPath().path
    })
    #expect(roots.contains(projects.appending(path: ".worktrees").resolvingSymlinksInPath().path))
    #expect(roots.contains(root.appending(path: ".codex/worktrees").resolvingSymlinksInPath().path))
    #expect(roots.contains(projects.appending(path: "site/.worktrees").resolvingSymlinksInPath().path))
    #expect(roots.contains(projects.appending(path: "site-worktrees").resolvingSymlinksInPath().path))
    #expect(roots.contains(root.appending(path: "other-worktrees").resolvingSymlinksInPath().path))
}

@Test func wholeWorktreeCleanupRejectsIgnoredCredentialsAndProtectedMedia() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(SafeCleaner.runCommand("/usr/bin/git", ["init", root.path]).code == 0)
    try Data(".env\n".utf8).write(to: root.appending(path: ".gitignore"))
    try Data("secret\n".utf8).write(to: root.appending(path: ".env"))
    #expect(SafeCleaner.worktreeIgnoredPaths(root) == [".env"])

    try FileManager.default.removeItem(at: root.appending(path: ".env"))
    #expect(SafeCleaner.worktreeIgnoredPaths(root) == [])
    let protected = root.appending(path: "media/Warning/Default/photo.jpg")
    try FileManager.default.createDirectory(at: protected.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("photo\n".utf8).write(to: protected)
    #expect(SafeCleaner.runCommand("/usr/bin/git", ["-C", root.path, "add", ".gitignore", "media/Warning/Default/photo.jpg"]).code == 0)
    #expect(SafeCleaner.containsTrackedProtectedPath(in: root))
}

// REGRESSÃO (06/09/2026): apagar o node_modules real de uma worktree quebrou a
// irmã cujo node_modules era symlink para ele.
@Test func symlinkReferencesOnlyProtectActiveOrNonIdleWorktrees() {
    let target = "/Users/x/Projects/.worktrees/a/node_modules"
    let references = [ArtifactSymlinkReference(
        sourcePath: "/Users/x/Projects/.worktrees/b/node_modules",
        destinationPath: target
    )]
    #expect(CleanupPolicy.matchingSymlinkSources(target: target, references: references) == [
        "/Users/x/Projects/.worktrees/b/node_modules",
    ])
    #expect(CleanupPolicy.matchingSymlinkSources(target: "/other/node_modules", references: references).isEmpty)
    #expect(CleanupPolicy.shouldProtectSymlinkReference(
        isLinkedWorktree: true,
        isActive: true,
        isIdle: true
    ))
    #expect(CleanupPolicy.shouldProtectSymlinkReference(
        isLinkedWorktree: true,
        isActive: false,
        isIdle: false
    ))
    #expect(CleanupPolicy.shouldProtectSymlinkReference(
        isLinkedWorktree: false,
        isActive: false,
        isIdle: true
    ))
    #expect(!CleanupPolicy.shouldProtectSymlinkReference(
        isLinkedWorktree: true,
        isActive: false,
        isIdle: true
    ))
}

// REGRESSÃO (02/10/2026): acima de 80% o cooldown fixo de 15s ignorava "sem
// progresso" e o app rodou 195 varreduras seguidas com removidos=0.
@Test func noProgressBacksOffEvenAtHardLimit() {
    let now = Date(timeIntervalSince1970: 100_000)
    #expect(StoragePolicy.cleanupCooldown(for: 0.95, lastCleanupMadeProgress: false, noProgressStreak: 1) == 300)
    #expect(StoragePolicy.cleanupCooldown(for: 0.95, lastCleanupMadeProgress: false, noProgressStreak: 2) == 600)
    #expect(StoragePolicy.cleanupCooldown(for: 0.95, lastCleanupMadeProgress: false, noProgressStreak: 3) == 1_200)
    #expect(StoragePolicy.cleanupCooldown(for: 0.95, lastCleanupMadeProgress: false, noProgressStreak: 4) == 1_800)
    #expect(StoragePolicy.cleanupCooldown(for: 0.95, lastCleanupMadeProgress: false, noProgressStreak: 50) == 1_800)
    #expect(StoragePolicy.cleanupCooldown(for: 0.95, lastCleanupMadeProgress: false, noProgressStreak: 0) == 300)
    #expect(StoragePolicy.cleanupCooldown(for: 0.79, lastCleanupMadeProgress: false) == 300)
    #expect(StoragePolicy.cleanupCooldown(for: 0.95, lastCleanupMadeProgress: true) == 300)
    #expect(!StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.97,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-15),
        lastCleanupMadeProgress: false,
        noProgressStreak: 1,
        now: now
    ))
    #expect(StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.97,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-300),
        lastCleanupMadeProgress: false,
        noProgressStreak: 1,
        now: now
    ))
}

@Test func deepCleanupOnlyAcceptsOldRecognizableTemporaryArtifacts() {
    let now = Date(timeIntervalSince1970: 100_000)
    let old = now.addingTimeInterval(-CleanupPolicy.temporaryArtifactMinimumAge)
    #expect(CleanupPolicy.isEligibleTemporaryArtifact(
        name: "resenha-derived-data",
        childNames: ["Build", "Index.noindex"],
        modificationDate: old,
        now: now
    ))
    #expect(CleanupPolicy.isEligibleTemporaryArtifact(
        name: "project-npm-cache",
        childNames: ["_cacache", "_logs"],
        modificationDate: old,
        now: now
    ))
    #expect(CleanupPolicy.isEligibleTemporaryArtifact(
        name: "deno-cache",
        childNames: ["dep_analysis_cache_v2", "npm"],
        modificationDate: old,
        now: now
    ))
    #expect(!CleanupPolicy.isEligibleTemporaryArtifact(
        name: "resenha-playwright-profile",
        childNames: ["BrowserMetrics", "Default"],
        modificationDate: old,
        now: now
    ))
    #expect(!CleanupPolicy.isEligibleTemporaryArtifact(
        name: "claude-501",
        childNames: ["Build", "Index.noindex"],
        modificationDate: old,
        now: now
    ))
    #expect(!CleanupPolicy.isEligibleTemporaryArtifact(
        name: "fresh-npm-cache",
        childNames: ["_cacache"],
        modificationDate: now.addingTimeInterval(-(CleanupPolicy.temporaryArtifactMinimumAge - 1)),
        now: now
    ))
}

// REGRESSÃO (02/10/2026): ~/.codex/worktrees e ~/.worktrees ficavam fora da
// varredura (pasta oculta / ~/.codex protegido) e acumularam dezenas de GB de
// node_modules de worktrees de agente. Só a subárvore de worktrees é liberada;
// o resto do ~/.codex continua protegido.
@Test func agentWorktreeFoldersAreScannedButCodexStaysProtected() {
    let home = "/Users/example"
    let roots = CleanupPolicy.artifactScanRoots(homePath: home)
    #expect(roots.contains("/Users/example/.codex/worktrees"))
    #expect(roots.contains("/Users/example/.worktrees"))

    let protected = ["/Users/example/.codex", "/Users/example/.claude"]
    let allowed = CleanupPolicy.agentWorktreeSubtrees(homePath: home)
    func isProtected(_ path: String) -> Bool {
        CleanupPolicy.isProtected(path, protectedPaths: protected, allowedSubtrees: allowed)
    }
    #expect(!isProtected("/Users/example/.codex/worktrees"))
    #expect(!isProtected("/Users/example/.codex/worktrees/swen-x/node_modules"))
    #expect(isProtected("/Users/example/.codex"))
    #expect(isProtected("/Users/example/.codex/sessions/node_modules"))
    #expect(isProtected("/Users/example/.codex/worktrees-backup/node_modules"))
    #expect(isProtected("/Users/example/.claude/worktrees/x/node_modules"))
    #expect(isProtected("/Users/example/.codex/worktrees/a/Warning/Default/node_modules"))
    #expect(!isProtected("/Users/example/.worktrees/sentinel/node_modules"))
    #expect(CleanupPolicy.isProtected("/Users/example/.codex/worktrees/x", protectedPaths: protected))
}
