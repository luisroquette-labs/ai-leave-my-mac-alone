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
    #expect(StoragePolicy.shouldRunAutomaticCleanup(
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
        lastCleanupAt: now.addingTimeInterval(-14),
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
    #expect(!StoragePolicy.madeMeaningfulProgress(removedTargets: 0, freedBytes: 1_376_256))
    #expect(StoragePolicy.madeMeaningfulProgress(removedTargets: 1, freedBytes: 0))
    #expect(StoragePolicy.madeMeaningfulProgress(
        removedTargets: 0,
        freedBytes: StoragePolicy.meaningfulProgressBytes
    ))
    #expect(StoragePolicy.restoredCleanupProgress(lastCleanupAt: nil, savedValue: nil))
    #expect(!StoragePolicy.restoredCleanupProgress(lastCleanupAt: now, savedValue: nil))
    #expect(StoragePolicy.restoredCleanupProgress(lastCleanupAt: now, savedValue: true))
    #expect(StoragePolicy.cleanupCooldown(for: 0.81, lastCleanupMadeProgress: true) == 15)
    #expect(!StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.81,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-14),
        now: now
    ))
    #expect(StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.81,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-15),
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
    #expect(StoragePolicy.shouldCleanNativeCaches(
        requested: false,
        escalateAtHardLimit: true,
        usedFractionAfterArtifacts: nil
    ))
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

@Test func cleanupPolicyKeepsArtifactsInsideTheirGitRoot() {
    let roots = CleanupPolicy.artifactScanRoots(homePath: "/Users/example")
    #expect(roots.contains("/Users/example/Projects"))
    #expect(!roots.contains("/private/tmp"))
    let deepRoots = CleanupPolicy.artifactScanRoots(
        homePath: "/Users/example",
        includeTemporaryWorktrees: true
    )
    #expect(deepRoots.contains("/private/tmp"))
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

// REGRESSÃO (06/09/2026): apagar o node_modules real de uma worktree quebrou a
// irmã cujo node_modules era symlink para ele.
@Test func symlinkReferencedArtifactsAreProtected() {
    let target = "/Users/x/Projects/.worktrees/a/node_modules"
    #expect(CleanupPolicy.isReferencedBySymlink(target, symlinkDestinations: [target]))
    #expect(CleanupPolicy.isReferencedBySymlink(target + "/", symlinkDestinations: [target]))
    #expect(!CleanupPolicy.isReferencedBySymlink(target, symlinkDestinations: ["/Users/x/Projects/.worktrees/b/node_modules"]))
    #expect(!CleanupPolicy.isReferencedBySymlink(target, symlinkDestinations: []))
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
    #expect(StoragePolicy.cleanupCooldown(for: 0.95, lastCleanupMadeProgress: true) == 15)
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
