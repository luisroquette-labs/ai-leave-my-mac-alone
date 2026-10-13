import CleanMyMacCore
import Darwin
import Foundation

struct CleanupResult: Sendable {
    let destination: CleanupDestination
    let removedTargets: Int
    let blockedTargets: Int
    let failedTargets: Int
    let freedBytes: UInt64

    var summary: String {
        let freed = ByteCountFormatter.string(fromByteCount: Int64(freedBytes), countStyle: .file)
        let completed: String
        switch destination {
        case .trash:
            completed = "\(removedTargets) itens movidos para a Lixeira"
        case .deleteBatch:
            completed = "\(freed) liberados com segurança"
        case .externalBackup:
            completed = "\(freed) liberados após backup verificado"
        }
        if failedTargets > 0 {
            return "\(completed); \(failedTargets) falhas verificadas. Nova tentativa agendada."
        }
        if blockedTargets > 0 {
            return "\(completed); \(blockedTargets) projetos ativos preservados."
        }
        return "\(completed)."
    }
}

enum SafeCleaner {
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/CleanMyMac/clean-my-mac.log")

    static let home = FileManager.default.homeDirectoryForCurrentUser
    private static var protectedPaths: [String] {
        [
            "Applications", "Desktop", "Documents", "Downloads", "Library", "Movies",
            "Music", "Pictures", "Public", "Arquivos Públicos", "Arquivos Públicos", ".Trash",
            ".claude", ".codex",
        ].map { home.appending(path: $0).path }
    }
    private static let minimumArtifactKiB = 100 * 1024

    private static func isProtected(_ path: String) -> Bool {
        CleanupPolicy.isProtected(
            path,
            protectedPaths: protectedPaths,
            allowedSubtrees: CleanupPolicy.agentWorktreeSubtrees(homePath: home.path)
        )
    }

    static func run(
        includeNativeCaches: Bool = true,
        escalateNativeCachesAtHardLimit: Bool = false,
        deepCleanupEnabled: Bool = false,
        destination: CleanupDestination = .deleteBatch,
        externalBackupPath: String? = nil
    ) async -> CleanupResult {
        await Task.detached(priority: .utility) {
            runSynchronously(
                includeNativeCaches: includeNativeCaches,
                escalateNativeCachesAtHardLimit: escalateNativeCachesAtHardLimit,
                deepCleanupEnabled: deepCleanupEnabled,
                destination: destination,
                externalBackupPath: externalBackupPath
            )
        }.value
    }

    static func prepareLog() {
        CleanupLog(url: logURL).append("MONITOR app iniciado")
    }

    static func record(_ message: String) {
        CleanupLog(url: logURL).append(message)
    }

    private static let scanFailureReasonLimit = 200

    static func scanFailureLogMessage(operation: String, path: String, result: CommandResult) -> String? {
        guard result.code != 0 else { return nil }
        return "ERROR \(operation): \(withoutControlCharacters(path)) \(sanitizedScanFailureReason(result.output))"
    }

    /// Replaces control characters (including NUL and newlines) with spaces so a string of
    /// unknown origin — command output or a filesystem path — can't split a log entry across
    /// multiple lines or embed unreadable bytes. A path can't contain NUL (it's a
    /// null-terminated C string at the OS level) but it can legitimately contain a newline or
    /// tab, so both path and command output go through this before being logged.
    private static func withoutControlCharacters(_ raw: String) -> String {
        String(raw.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : Character($0)
        })
    }

    /// Collapses and caps `withoutControlCharacters` output so one command failure can't dump
    /// an entire find/du result set into the log.
    private static func sanitizedScanFailureReason(_ raw: String) -> String {
        let collapsed = withoutControlCharacters(raw)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard collapsed.count > scanFailureReasonLimit else { return collapsed }
        return "\(collapsed.prefix(scanFailureReasonLimit))…"
    }

    /// Parses the leading whitespace-separated field of `du -sk` output as kibibytes.
    /// Returns nil when the output doesn't start with a number, distinguishing a genuine
    /// parse failure (log-worthy) from a legitimately small/ineligible artifact.
    static func parseDuSizeKiB(_ output: String) -> Int? {
        guard let first = output.split(whereSeparator: { $0.isWhitespace }).first else { return nil }
        return Int(first)
    }

    private static func runSynchronously(
        includeNativeCaches: Bool,
        escalateNativeCachesAtHardLimit: Bool,
        deepCleanupEnabled: Bool,
        destination: CleanupDestination,
        externalBackupPath: String?
    ) -> CleanupResult {
        let startingSnapshot = try? StorageReader.read()
        let before = startingSnapshot?.availableBytes ?? 0
        var removedTargets = 0
        var blockedTargets = 0
        var failedTargets = 0
        let log = CleanupLog(url: logURL)
        log.append("START armazenamento seguro destino=\(destination.rawValue) profunda=\(deepCleanupEnabled)")

        var disposal = DisposalSession(
            destination: destination,
            externalBackupPath: externalBackupPath
        )
        let artifactResult = cleanGeneratedArtifacts(
            deepCleanupEnabled: deepCleanupEnabled,
            bytesRequired: startingSnapshot.map(StoragePolicy.bytesRequiredToGetBelowHardLimit) ?? 0,
            destination: destination,
            log: log,
            disposal: &disposal
        )
        removedTargets += artifactResult.removed
        blockedTargets += artifactResult.blocked
        failedTargets += artifactResult.failed
        let finalized = disposal.finalize(log: log)
        if !finalized {
            failedTargets += 1
        } else if destination == .deleteBatch {
            failedTargets += pruneWorktreeMetadata(artifactResult.gitDirectoriesToPrune, log: log)
        }

        // Artefatos ignorados podem ser a única razão para uma worktree limpa não
        // entrar na primeira seleção. Depois que o lote acima é finalizado, reavaliar
        // uma vez fecha a mesma rodada sem criar um ciclo apagar/reconstruir.
        if finalized, deepCleanupEnabled, destination == .deleteBatch,
           let snapshot = try? StorageReader.read(),
           StoragePolicy.bytesRequiredToGetBelowHardLimit(snapshot) > 0,
           let activeDirectories = activeWorkingDirectories() {
            var recheckDisposal = DisposalSession(destination: .deleteBatch, externalBackupPath: nil)
            let recheck = cleanReclaimableWorktrees(
                bytesRequired: StoragePolicy.bytesRequiredToGetBelowHardLimit(snapshot),
                activeDirectories: activeDirectories,
                log: log,
                disposal: &recheckDisposal
            )
            removedTargets += recheck.removed
            blockedTargets += recheck.blocked
            failedTargets += recheck.failed
            log.append("RECHECK worktrees recuperadas=\(recheck.removed)")
            if recheckDisposal.finalize(log: log) {
                failedTargets += pruneWorktreeMetadata(recheck.gitDirectoriesToPrune, log: log)
            } else {
                failedTargets += 1
            }
        }

        if deepCleanupEnabled, destination == .deleteBatch,
           let snapshot = try? StorageReader.read(),
           CleanupPolicy.shouldCleanAggressiveCaches(
               usedFraction: snapshot.usedFraction,
               lastCleanedAt: UserDefaults.standard.object(forKey: aggressiveCacheCleanupKey) as? Date
           ) {
            let cacheResult = cleanRegenerableCaches(
                bytesRequired: CleanupPolicy.bytesToStageFromAggressiveCaches(
                    shortfall: StoragePolicy.bytesRequiredToGetBelowHardLimit(snapshot)
                ),
                log: log
            )
            removedTargets += cacheResult.removed
            failedTargets += cacheResult.failed
        } else if deepCleanupEnabled, destination == .deleteBatch,
                  let snapshot = try? StorageReader.read(),
                  StoragePolicy.isAtOrAboveHardLimit(snapshot.usedFraction) {
            log.append("CACHE agressivo em cooldown para impedir ciclo de reconstrução")
        }
        let fractionAfterArtifacts = try? StorageReader.read().usedFraction
        let shouldCleanNativeCaches = StoragePolicy.shouldCleanNativeCaches(
            requested: includeNativeCaches,
            escalateAtHardLimit: escalateNativeCachesAtHardLimit,
            usedFractionAfterArtifacts: fractionAfterArtifacts
        )
        if shouldCleanNativeCaches, destination == .deleteBatch {
            failedTargets += cleanNativeCaches(log: log)
        } else if shouldCleanNativeCaches {
            log.append("CACHE limpeza nativa ignorada para respeitar o destino escolhido")
        } else {
            log.append("CACHE limpeza nativa dispensada: uso abaixo do limite de 80%")
        }
        let after = (try? StorageReader.read().availableBytes) ?? before
        let freed = after > before ? after - before : 0
        log.append("END liberados=\(freed) removidos=\(removedTargets) bloqueados=\(blockedTargets) falhas=\(failedTargets)")
        return CleanupResult(
            destination: destination,
            removedTargets: removedTargets,
            blockedTargets: blockedTargets,
            failedTargets: failedTargets,
            freedBytes: freed
        )
    }

    private static let aggressiveCacheCleanupKey = "lastAggressiveCacheCleanupAt"
    private static let minimumCacheKiB = 10 * 1_024

    private static func pruneWorktreeMetadata(_ gitDirectories: Set<String>, log: CleanupLog) -> Int {
        var failures = 0
        for gitDirectory in gitDirectories {
            let prune = runCommand(
                "/usr/bin/git",
                ["--git-dir", gitDirectory, "worktree", "prune", "--expire", "now"]
            )
            if prune.code != 0 {
                failures += 1
                log.append("ERROR metadados de worktree: \(gitDirectory) \(prune.output)")
            }
        }
        return failures
    }

    private static func cleanRegenerableCaches(
        bytesRequired: UInt64,
        log: CleanupLog
    ) -> (removed: Int, failed: Int) {
        guard bytesRequired > 0 else { return (0, 0) }
        var disposal = DisposalSession(destination: .deleteBatch, externalBackupPath: nil)
        var removed = 0
        var failed = 0
        var stagedBytes: UInt64 = 0
        var candidates = CleanupPolicy.regenerableCachePaths(homePath: home.path).map {
            URL(filePath: $0, directoryHint: .isDirectory)
        }
        candidates += browserCacheCandidates()
        candidates += agentCacheArtifactCandidates()
        candidates += CleanupPolicy.lastResortCachePaths(homePath: home.path).map {
            URL(filePath: $0, directoryHint: .isDirectory)
        }

        var seen = Set<String>()
        for target in candidates where stagedBytes < bytesRequired {
            let path = target.standardizedFileURL.path
            guard seen.insert(path).inserted,
                  !CleanupPolicy.isProtected(path, protectedPaths: []),
                  let values = try? target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let sizeResult = runCommand("/usr/bin/du", ["-sk", path])
            guard sizeResult.code == 0, let sizeKiB = parseDuSizeKiB(sizeResult.output),
                  sizeKiB >= minimumCacheKiB else { continue }
            do {
                _ = try disposal.stage(target, expectedBytes: UInt64(sizeKiB) * 1_024)
                removed += 1
                stagedBytes += UInt64(sizeKiB) * 1_024
                log.append("CACHE REMOVED regenerável \(path) sizeKiB=\(sizeKiB)")
            } catch {
                failed += 1
                log.append("ERROR cache regenerável: \(path) \(error.localizedDescription)")
            }
        }
        guard disposal.finalize(log: log) else { return (removed, failed + 1) }
        if removed > 0 {
            UserDefaults.standard.set(Date(), forKey: aggressiveCacheCleanupKey)
        }
        log.append("CACHE agressivo removidos=\(removed) estimadoBytes=\(stagedBytes)")
        return (removed, failed)
    }

    private static func browserCacheCandidates() -> [URL] {
        let chromeRoot = home.appending(path: "Library/Caches/Google/Chrome", directoryHint: .isDirectory)
        let profiles = (try? FileManager.default.contentsOfDirectory(
            at: chromeRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return profiles.flatMap { profile in
            CleanupPolicy.browserCacheLeafNames.map {
                profile.appending(path: $0, directoryHint: .isDirectory)
            }
        }
    }

    private static func agentCacheArtifactCandidates() -> [URL] {
        let root = home.appending(path: ".cache/codex", directoryHint: .isDirectory)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var candidates: [URL] = []
        let rootDepth = root.pathComponents.count
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - rootDepth
            if depth > 5 {
                enumerator.skipDescendants()
                continue
            }
            guard CleanupPolicy.artifactDirectoryNames.contains(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            candidates.append(url)
            enumerator.skipDescendants()
        }
        return candidates
    }

    private static func cleanNativeCaches(log: CleanupLog) -> Int {
        let bunWorkspace = FileManager.default.temporaryDirectory
            .appending(path: "CleanMyMac-bun-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        var bunWorkingDirectory: URL?
        var failures = 0
        do {
            try FileManager.default.createDirectory(at: bunWorkspace, withIntermediateDirectories: true)
            try Data("{\"private\":true}\n".utf8).write(to: bunWorkspace.appending(path: "package.json"))
            bunWorkingDirectory = bunWorkspace
        } catch {
            failures += 1
            log.append("CACHE Bun workspace exit=-1 \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: bunWorkspace) }

        let pnpmLocations = nvmBinaryLocations(named: "pnpm")
        let commands: [([String], [String], URL?, TimeInterval)] = [
            (["/opt/homebrew/bin/npm", "/usr/local/bin/npm"], ["cache", "clean", "--force"], nil, 120),
            ([home.appending(path: ".bun/bin/bun").path, "/opt/homebrew/bin/bun", "/usr/local/bin/bun"], ["pm", "cache", "rm"], bunWorkingDirectory, 120),
            (["/opt/homebrew/bin/deno", "/usr/local/bin/deno"], ["clean"], nil, 120),
            ([home.appending(path: ".local/bin/uv").path, "/opt/homebrew/bin/uv", "/usr/local/bin/uv"], ["cache", "prune"], nil, 120),
            (pnpmLocations + ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm"], ["store", "prune"], bunWorkingDirectory, 120),
            (["/opt/homebrew/bin/brew", "/usr/local/bin/brew"], ["cleanup", "-s", "--prune=all"], nil, 120),
        ]

        for (locations, arguments, workingDirectory, timeout) in commands {
            guard let executable = locations.first(where: FileManager.default.isExecutableFile(atPath:)) else { continue }
            guard arguments != ["pm", "cache", "rm"] || workingDirectory != nil else { continue }
            let result = runCommand(executable, arguments, timeout: timeout, currentDirectoryURL: workingDirectory)
            if result.code != 0 { failures += 1 }
            log.append("CACHE \(executable) exit=\(result.code) \(result.output)")
        }
        return failures
    }

    private static func nvmBinaryLocations(named name: String) -> [String] {
        let versions = home.appending(path: ".nvm/versions/node", directoryHint: .isDirectory)
        return ((try? FileManager.default.contentsOfDirectory(
            at: versions,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []).map { $0.appending(path: "bin/\(name)").path }
    }

    private static func cleanGeneratedArtifacts(
        deepCleanupEnabled: Bool,
        bytesRequired: UInt64,
        destination: CleanupDestination,
        log: CleanupLog,
        disposal: inout DisposalSession
    ) -> (removed: Int, blocked: Int, failed: Int, gitDirectoriesToPrune: Set<String>) {
        var removed = 0
        var blocked = 0
        var failed = 0
        var gitDirectoriesToPrune = Set<String>()
        do {
            try disposal.validate()
        } catch {
            log.append("ERROR destino indisponível: \(error.localizedDescription)")
            return (0, 0, 1, [])
        }
        guard let activeDirectories = activeWorkingDirectories() else {
            log.append("BLOCK inspeção de processos indisponível")
            return (0, 0, 0, [])
        }
        var stagedBytes: UInt64 = 0
        if deepCleanupEnabled, destination == .deleteBatch, bytesRequired > 0 {
            let worktreeResult = cleanReclaimableWorktrees(
                bytesRequired: bytesRequired,
                activeDirectories: activeDirectories,
                log: log,
                disposal: &disposal
            )
            removed += worktreeResult.removed
            blocked += worktreeResult.blocked
            failed += worktreeResult.failed
            stagedBytes += worktreeResult.stagedBytes
            gitDirectoriesToPrune.formUnion(worktreeResult.gitDirectoriesToPrune)
        }
        if stagedBytes >= bytesRequired {
            log.append("SCAN artefatos dispensada: worktrees recuperam o déficit estimado")
            return (removed, blocked, failed, gitDirectoriesToPrune)
        }
        let scanStartedAt = Date()
        let scanResult = artifactCandidates(deepCleanupEnabled: deepCleanupEnabled, log: log)
        let candidates = scanResult.candidates
        failed += scanResult.scanFailures
        let scanMilliseconds = Int(Date().timeIntervalSince(scanStartedAt) * 1_000)
        log.append("SCAN candidatos=\(candidates.count) duracaoMs=\(scanMilliseconds) falhas=\(scanResult.scanFailures)")

        for target in candidates {
            guard let gitRoot = gitRoot(for: target) else {
                log.append("SKIP sem Git: \(target.path)")
                continue
            }
            if CleanupPolicy.isLinkedWorktree(gitRoot.path), !isIdleWorktree(gitRoot) {
                log.append("SKIP worktree em uso: \(target.path)")
                continue
            }
            if hasNonIdleSymlinkReference(
                to: target,
                references: scanResult.symlinkReferences,
                activeDirectories: activeDirectories
            ) {
                log.append("SKIP referenciado por symlink de outra worktree: \(target.path)")
                continue
            }
            guard runCommand("/usr/bin/git", ["-C", gitRoot.path, "check-ignore", "-q", "--", target.path]).code == 0 else {
                log.append("SKIP alvo não ignorado pelo Git: \(target.path)")
                continue
            }
            if CleanupPolicy.isProjectActive(gitRoot.path, activeDirectories: activeDirectories) {
                blocked += 1
                log.append("BLOCK processo ativo: \(target.path)")
                continue
            }
            guard !isProtected(target.path),
                  CleanupPolicy.pathsOverlap(target.path, gitRoot.path) else {
                blocked += 1
                log.append("BLOCK limite protegido: \(target.path)")
                continue
            }

            let sizeResult = runCommand("/usr/bin/du", ["-sk", target.path])
            if let message = scanFailureLogMessage(operation: "medição de tamanho", path: target.path, result: sizeResult) {
                log.append(message)
                failed += 1
            }
            let sizeKiB = sizeResult.code == 0 ? parseDuSizeKiB(sizeResult.output) : nil
            if sizeResult.code == 0, sizeKiB == nil {
                log.append("ERROR medição de tamanho: saída inesperada de du: \(withoutControlCharacters(target.path))")
                failed += 1
            }
            guard let sizeKiB,
                  CleanupPolicy.isEligibleArtifact(
                      name: target.lastPathComponent,
                      sizeKiB: sizeKiB,
                      isSymbolicLink: false,
                      minimumKiB: minimumArtifactKiB
                  ) else { continue }

            guard let currentActiveDirectories = activeWorkingDirectories() else {
                blocked += 1
                log.append("BLOCK rechecagem de processos indisponível: \(target.path)")
                continue
            }
            if CleanupPolicy.isProjectActive(gitRoot.path, activeDirectories: currentActiveDirectories) {
                blocked += 1
                log.append("BLOCK processo iniciou durante a varredura: \(target.path)")
                continue
            }

            let statusBefore = runCommand(
                "/usr/bin/git",
                ["--no-optional-locks", "-C", gitRoot.path, "status", "--porcelain=v1", "-z"]
            )
            guard statusBefore.code == 0 else {
                blocked += 1
                log.append("BLOCK Git indisponível antes da limpeza: \(target.path)")
                continue
            }

            let receipt: ArtifactReceipt
            do {
                receipt = try disposal.stage(
                    target,
                    expectedBytes: UInt64(sizeKiB) * 1_024
                )
            } catch {
                failed += 1
                log.append("ERROR destino: \(target.path) \(error.localizedDescription)")
                continue
            }

            let statusAfter = runCommand(
                "/usr/bin/git",
                ["--no-optional-locks", "-C", gitRoot.path, "status", "--porcelain=v1", "-z"]
            )
            guard CleanupPolicy.isVerifiedAfterCleanup(
                statusBefore: statusBefore.output,
                statusAfter: statusAfter.output,
                statusAfterExitCode: statusAfter.code,
                targetStillExists: FileManager.default.fileExists(atPath: target.path)
            ) else {
                do {
                    try disposal.restore(receipt)
                } catch {
                    disposal.preserveBatch()
                    log.append("ERROR restauração; lote preservado: \(target.path) \(error.localizedDescription)")
                }
                failed += 1
                log.append("ERROR verificação pós-limpeza: \(target.path)")
                continue
            }
            removed += 1
            log.append("REMOVED \(target.path) sizeKiB=\(sizeKiB)")
        }

        if deepCleanupEnabled {
            let temporaryResult = cleanTemporaryArtifacts(
                activeDirectories: activeDirectories,
                log: log,
                disposal: &disposal
            )
            removed += temporaryResult.removed
            blocked += temporaryResult.blocked
            failed += temporaryResult.failed
        }
        return (removed, blocked, failed, gitDirectoriesToPrune)
    }

    private struct ReclaimableWorktree {
        let root: URL
        let branch: String
        let head: String
        let commonGitDirectory: String
        let lastActivity: Date
        let sizeKiB: Int
    }

    private static func cleanReclaimableWorktrees(
        bytesRequired: UInt64,
        activeDirectories: [String],
        log: CleanupLog,
        disposal: inout DisposalSession
    ) -> (removed: Int, blocked: Int, failed: Int, stagedBytes: UInt64, gitDirectoriesToPrune: Set<String>) {
        let scanStartedAt = Date()
        let candidates = reclaimableWorktrees(activeDirectories: activeDirectories)
            .sorted {
                $0.lastActivity == $1.lastActivity
                    ? $0.sizeKiB > $1.sizeKiB
                    : $0.lastActivity < $1.lastActivity
            }
        log.append("SCAN worktrees recuperáveis=\(candidates.count) duracaoMs=\(Int(Date().timeIntervalSince(scanStartedAt) * 1_000))")

        var removed = 0
        var blocked = 0
        var failed = 0
        var stagedBytes: UInt64 = 0
        var gitDirectoriesToPrune = Set<String>()
        for candidate in candidates where stagedBytes < bytesRequired {
            guard let currentActiveDirectories = activeWorkingDirectories(),
                  !CleanupPolicy.isProjectActive(candidate.root.path, activeDirectories: currentActiveDirectories) else {
                blocked += 1
                log.append("BLOCK worktree iniciou durante a limpeza: \(candidate.root.path)")
                continue
            }
            let status = runCommand(
                "/usr/bin/git",
                ["--no-optional-locks", "-C", candidate.root.path, "status", "--porcelain=v1", "-z"]
            )
            let ignoredPaths = worktreeIgnoredPaths(candidate.root)
            let head = runCommand("/usr/bin/git", ["-C", candidate.root.path, "rev-parse", "HEAD"])
            let branch = runCommand("/usr/bin/git", ["-C", candidate.root.path, "symbolic-ref", "-q", "HEAD"])
            guard status.code == 0, status.output.isEmpty,
                  ignoredPaths.map(CleanupPolicy.hasOnlyRegenerableIgnoredPaths) == true,
                  head.code == 0, head.output.trimmingCharacters(in: .whitespacesAndNewlines) == candidate.head,
                  branch.code == 0, branch.output.trimmingCharacters(in: .whitespacesAndNewlines) == candidate.branch,
                  !containsTrackedProtectedPath(in: candidate.root) else {
                blocked += 1
                log.append("BLOCK worktree mudou durante a limpeza: \(candidate.root.path)")
                continue
            }

            let receipt: ArtifactReceipt
            do {
                receipt = try disposal.stage(candidate.root, expectedBytes: UInt64(candidate.sizeKiB) * 1_024)
            } catch {
                failed += 1
                log.append("ERROR destino da worktree: \(candidate.root.path) \(error.localizedDescription)")
                continue
            }
            let savedHead = runCommand(
                "/usr/bin/git",
                ["--git-dir", candidate.commonGitDirectory, "rev-parse", candidate.branch]
            )
            guard savedHead.code == 0,
                  savedHead.output.trimmingCharacters(in: .whitespacesAndNewlines) == candidate.head,
                  !FileManager.default.fileExists(atPath: candidate.root.path) else {
                do {
                    try disposal.restore(receipt)
                } catch {
                    disposal.preserveBatch()
                    log.append("ERROR restauração da worktree; lote preservado: \(candidate.root.path) \(error.localizedDescription)")
                }
                failed += 1
                log.append("ERROR verificação da branch preservada: \(candidate.root.path)")
                continue
            }
            let bytes = UInt64(candidate.sizeKiB) * 1_024
            stagedBytes += bytes
            removed += 1
            gitDirectoriesToPrune.insert(candidate.commonGitDirectory)
            log.append("REMOVED worktree limpa \(candidate.root.path) sizeKiB=\(candidate.sizeKiB) branch=\(candidate.branch)")
        }
        return (removed, blocked, failed, stagedBytes, gitDirectoriesToPrune)
    }

    private static func reclaimableWorktrees(activeDirectories: [String]) -> [ReclaimableWorktree] {
        var seen = Set<String>()
        var worktrees: [ReclaimableWorktree] = []
        for containerPath in CleanupPolicy.worktreeContainerRoots(homePath: home.path) {
            guard FileManager.default.fileExists(atPath: containerPath), !isProtected(containerPath) else { continue }
            let result = runCommand("/usr/bin/find", [
                containerPath, "-mindepth", "1", "-maxdepth", "4",
                "-name", ".git", "-type", "f", "-print0",
            ])
            guard result.code == 0 else { continue }
            for rawPath in result.output.split(separator: "\0") {
                let root = URL(filePath: String(rawPath)).deletingLastPathComponent()
                guard seen.insert(root.path).inserted, !isProtected(root.path) else { continue }
                let resolvedRoot = runCommand("/usr/bin/git", ["-C", root.path, "rev-parse", "--show-toplevel"])
                guard resolvedRoot.code == 0,
                      URL(filePath: resolvedRoot.output.trimmingCharacters(in: .whitespacesAndNewlines)).standardizedFileURL.path
                        == root.standardizedFileURL.path else { continue }
                let gitDirectoryResult = runCommand("/usr/bin/git", ["-C", root.path, "rev-parse", "--absolute-git-dir"])
                let commonGitResult = runCommand("/usr/bin/git", ["-C", root.path, "rev-parse", "--path-format=absolute", "--git-common-dir"])
                let branchResult = runCommand("/usr/bin/git", ["-C", root.path, "symbolic-ref", "-q", "HEAD"])
                let headResult = runCommand("/usr/bin/git", ["-C", root.path, "rev-parse", "HEAD"])
                let statusResult = runCommand(
                    "/usr/bin/git",
                    ["--no-optional-locks", "-C", root.path, "status", "--porcelain=v1", "-z"]
                )
                let ignoredPaths = worktreeIgnoredPaths(root)
                guard gitDirectoryResult.code == 0, commonGitResult.code == 0,
                      branchResult.code == 0, headResult.code == 0, statusResult.code == 0,
                      ignoredPaths.map(CleanupPolicy.hasOnlyRegenerableIgnoredPaths) == true,
                      !containsTrackedProtectedPath(in: root) else { continue }
                let gitDirectory = gitDirectoryResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let commonGitDirectory = commonGitResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let branch = branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let head = headResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let lastActivity = worktreeLastActivity(gitDirectory: gitDirectory)
                guard CleanupPolicy.isReclaimableWorktree(
                    isLinkedWorktree: gitDirectory.hasPrefix(commonGitDirectory + "/worktrees/"),
                    hasBranch: !branch.isEmpty,
                    isClean: statusResult.output.isEmpty,
                    isActive: CleanupPolicy.isProjectActive(root.path, activeDirectories: activeDirectories),
                    lastActivity: lastActivity
                ) else { continue }
                let sizeResult = runCommand("/usr/bin/du", ["-sk", root.path])
                guard sizeResult.code == 0, let sizeKiB = parseDuSizeKiB(sizeResult.output),
                      sizeKiB >= minimumArtifactKiB, let lastActivity else { continue }
                worktrees.append(ReclaimableWorktree(
                    root: root,
                    branch: branch,
                    head: head,
                    commonGitDirectory: commonGitDirectory,
                    lastActivity: lastActivity,
                    sizeKiB: sizeKiB
                ))
            }
        }
        return worktrees
    }

    static func worktreeIgnoredPaths(_ root: URL) -> [String]? {
        let result = runCommand(
            "/usr/bin/git",
            ["--no-optional-locks", "-C", root.path, "status", "--porcelain=v1", "-z", "--ignored=matching"]
        )
        guard result.code == 0 else { return nil }
        return result.output.split(separator: "\0").compactMap { record in
            record.hasPrefix("!! ") ? String(record.dropFirst(3)) : nil
        }
    }

    static func containsTrackedProtectedPath(in root: URL) -> Bool {
        let result = runCommand("/usr/bin/git", [
            "-C", root.path, "ls-files", "-z", "--", ":(glob)**/Warning/Default/**",
        ])
        return result.code != 0 || !result.output.isEmpty
    }

    private static func artifactCandidates(
        deepCleanupEnabled: Bool,
        log: CleanupLog
    ) -> (candidates: [URL], symlinkReferences: [ArtifactSymlinkReference], scanFailures: Int) {
        let fileManager = FileManager.default
        var roots = CleanupPolicy.artifactScanRoots(homePath: home.path)
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
        if deepCleanupEnabled {
            roots += temporaryWorktreeRoots()
        }
        let excludedTopLevel = Set([
            "Applications", "Desktop", "Documents", "Downloads", "Library", "Movies", "Music",
            "Pictures", "Public", "Arquivos Públicos", "Arquivos Públicos",
        ])

        if let children = try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children where !excludedTopLevel.contains(child.lastPathComponent) {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                if fileManager.fileExists(atPath: child.appending(path: "package.json").path)
                    || fileManager.fileExists(atPath: child.appending(path: ".git").path) {
                    roots.append(child)
                }
            }
        }

        var seen = Set<String>()
        var candidates: [URL] = []
        var symlinkReferences: [ArtifactSymlinkReference] = []
        var scanFailures = 0
        for root in roots {
            let scanned = enumerateArtifacts(in: root, log: log)
            scanFailures += scanned.scanFailures
            symlinkReferences += scanned.symlinkReferences
            for url in scanned.urls where seen.insert(url.path).inserted {
                candidates.append(url)
            }
        }
        return (candidates, symlinkReferences, scanFailures)
    }

    private static func enumerateArtifacts(
        in root: URL,
        log: CleanupLog
    ) -> (urls: [URL], symlinkReferences: [ArtifactSymlinkReference], scanFailures: Int) {
        guard !isProtected(root.path) else { return ([], [], 0) }
        guard FileManager.default.fileExists(atPath: root.path) else { return ([], [], 0) }

        var arguments = [root.path, "-type", "d", "("]
        for (index, pattern) in CleanupPolicy.excludedDirectoryPatterns.enumerated() {
            if index > 0 { arguments.append("-o") }
            arguments += ["-name", pattern]
        }
        arguments += ["-o", "-path", "*/Warning/Default"]
        arguments += [")", "-prune", "-o", "-type", "d", "("]
        for (index, name) in CleanupPolicy.artifactDirectoryNames.sorted().enumerated() {
            if index > 0 { arguments.append("-o") }
            arguments += ["-name", name]
        }
        arguments += [")", "-print0", "-prune", "-o", "-type", "l", "("]
        for (index, name) in CleanupPolicy.artifactDirectoryNames.sorted().enumerated() {
            if index > 0 { arguments.append("-o") }
            arguments += ["-name", name]
        }
        arguments += [")", "-print0"]

        let result = runCommand("/usr/bin/find", arguments)
        if let message = scanFailureLogMessage(operation: "varredura de artefatos", path: root.path, result: result) {
            log.append(message)
            return ([], [], 1)
        }
        var urls: [URL] = []
        var symlinkReferences: [ArtifactSymlinkReference] = []
        for rawPath in result.output.split(separator: "\0") {
            let url = URL(filePath: String(rawPath), directoryHint: .isDirectory)
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                symlinkReferences.append(ArtifactSymlinkReference(
                    sourcePath: url.path,
                    destinationPath: url.resolvingSymlinksInPath().path
                ))
            } else if !isProtected(url.path) {
                urls.append(url)
            }
        }
        return (urls, symlinkReferences, 0)
    }

    private static func temporaryWorktreeRoots() -> [URL] {
        let temporary = URL(filePath: "/private/tmp", directoryHint: .isDirectory)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: temporary,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return children.filter {
            let values = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true
                && values?.isSymbolicLink != true
                && FileManager.default.fileExists(atPath: $0.appending(path: ".git").path)
        }
    }

    private static func hasNonIdleSymlinkReference(
        to target: URL,
        references: [ArtifactSymlinkReference],
        activeDirectories: [String]
    ) -> Bool {
        CleanupPolicy.matchingSymlinkSources(
            target: target.resolvingSymlinksInPath().path,
            references: references
        ).contains { sourcePath in
            guard let root = gitRoot(for: URL(filePath: sourcePath)) else { return true }
            return CleanupPolicy.shouldProtectSymlinkReference(
                isLinkedWorktree: CleanupPolicy.isLinkedWorktree(root.path),
                isActive: CleanupPolicy.isProjectActive(root.path, activeDirectories: activeDirectories),
                isIdle: isIdleWorktree(root)
            )
        }
    }

    private static func cleanTemporaryArtifacts(
        activeDirectories: [String],
        log: CleanupLog,
        disposal: inout DisposalSession
    ) -> (removed: Int, blocked: Int, failed: Int) {
        var removed = 0
        var blocked = 0
        var failed = 0
        let fileManager = FileManager.default
        let temporary = URL(filePath: "/private/tmp", directoryHint: .isDirectory)
        let children = (try? fileManager.contentsOfDirectory(
            at: temporary,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for target in children {
            let values = try? target.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey,
            ])
            guard values?.isDirectory == true, values?.isSymbolicLink != true,
                  let contents = try? fileManager.contentsOfDirectory(atPath: target.path),
                  CleanupPolicy.isEligibleTemporaryArtifact(
                      name: target.lastPathComponent,
                      childNames: Set(contents),
                      modificationDate: values?.contentModificationDate
                  ) else { continue }
            if CleanupPolicy.isProjectActive(target.path, activeDirectories: activeDirectories) {
                blocked += 1
                log.append("BLOCK temporário em uso: \(target.path)")
                continue
            }
            guard !fileManager.fileExists(atPath: target.appending(path: ".git").path) else {
                blocked += 1
                log.append("BLOCK temporário contém Git: \(target.path)")
                continue
            }
            let sizeResult = runCommand("/usr/bin/du", ["-sk", target.path])
            guard sizeResult.code == 0,
                  let sizeKiB = parseDuSizeKiB(sizeResult.output),
                  sizeKiB >= minimumArtifactKiB else { continue }
            guard let currentActiveDirectories = activeWorkingDirectories(),
                  !CleanupPolicy.isProjectActive(target.path, activeDirectories: currentActiveDirectories) else {
                blocked += 1
                log.append("BLOCK temporário iniciou durante a varredura: \(target.path)")
                continue
            }
            do {
                _ = try disposal.stage(target, expectedBytes: UInt64(sizeKiB) * 1_024)
                guard !fileManager.fileExists(atPath: target.path) else {
                    failed += 1
                    log.append("ERROR verificação pós-limpeza temporária: \(target.path)")
                    continue
                }
                removed += 1
                log.append("REMOVED temporário \(target.path) sizeKiB=\(sizeKiB)")
            } catch {
                failed += 1
                log.append("ERROR destino temporário: \(target.path) \(error.localizedDescription)")
            }
        }
        return (removed, blocked, failed)
    }

    /// Ociosa = sem commit/checkout/stage nem arquivo modificado (fora de artefatos)
    /// dentro da janela. Qualquer falha de leitura conta como em uso.
    private static func isIdleWorktree(_ gitRoot: URL) -> Bool {
        let gitDirResult = runCommand("/usr/bin/git", ["-C", gitRoot.path, "rev-parse", "--absolute-git-dir"])
        guard gitDirResult.code == 0 else { return false }
        let gitDir = URL(filePath: gitDirResult.output.trimmingCharacters(in: .whitespacesAndNewlines))
        let lastGitActivity = worktreeLastActivity(gitDirectory: gitDir.path)

        var upstreamGone = false
        let headRef = runCommand("/usr/bin/git", ["-C", gitRoot.path, "symbolic-ref", "-q", "HEAD"])
        if headRef.code == 0 {
            let track = runCommand("/usr/bin/git", [
                "-C", gitRoot.path, "for-each-ref", "--format=%(upstream:track)",
                headRef.output.trimmingCharacters(in: .whitespacesAndNewlines),
            ])
            upstreamGone = track.code == 0 && track.output.contains("[gone]")
        }
        guard CleanupPolicy.isWorktreeIdle(lastActivity: lastGitActivity, now: Date(), upstreamGone: upstreamGone) else {
            return false
        }

        let minutes = Int(CleanupPolicy.worktreeIdleThreshold(upstreamGone: upstreamGone) / 60)
        let recentFile = runCommand("/usr/bin/find", [
            gitRoot.path, "(", "-name", "node_modules", "-o", "-name", ".next", "-o", "-name", ".git", ")", "-prune",
            "-o", "-mmin", "-\(minutes)", "-print", "-quit",
        ])
        return recentFile.code == 0 && recentFile.output.isEmpty
    }

    private static func worktreeLastActivity(gitDirectory: String) -> Date? {
        let gitDir = URL(filePath: gitDirectory)
        return ["HEAD", "index", "logs/HEAD"]
            .compactMap { try? FileManager.default.attributesOfItem(atPath: gitDir.appending(path: $0).path)[.modificationDate] as? Date }
            .max()
    }

    private static func activeWorkingDirectories() -> [String]? {
        let result = runCommand("/usr/sbin/lsof", [
            "-a", "-u", NSUserName(), "-d", "cwd", "-Fn",
        ])
        guard result.code == 0 else { return nil }
        return result.output.split(separator: "\n").compactMap { line in
            line.first == "n" ? String(line.dropFirst()) : nil
        }
    }

    private static func gitRoot(for target: URL) -> URL? {
        let result = runCommand("/usr/bin/git", ["-C", target.deletingLastPathComponent().path, "rev-parse", "--show-toplevel"])
        guard result.code == 0 else { return nil }
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(filePath: path)
    }

    static func runCommand(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 60,
        currentDirectoryURL: URL? = nil
    ) -> CommandResult {
        let fileManager = FileManager.default
        let outputURL = fileManager.temporaryDirectory
            .appending(path: "CleanMyMac-command-\(UUID().uuidString).log")
        guard fileManager.createFile(atPath: outputURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return CommandResult(code: -1, output: "não foi possível criar a saída temporária")
        }
        defer {
            try? outputHandle.close()
            try? fileManager.removeItem(at: outputURL)
        }

        let process = Process()
        let terminated = DispatchSemaphore(value: 0)
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        process.terminationHandler = { _ in terminated.signal() }
        do {
            try process.run()
            let timedOut = terminated.wait(timeout: .now() + timeout) == .timedOut
            if timedOut {
                process.terminate()
                if terminated.wait(timeout: .now() + 5) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    _ = terminated.wait(timeout: .now() + 2)
                }
            } else {
                process.waitUntilExit()
            }
            try? outputHandle.synchronize()
            let data = (try? Data(contentsOf: outputURL)) ?? Data()
            let output = String(decoding: data, as: UTF8.self)
            return timedOut
                ? CommandResult(code: 124, output: "tempo limite de \(Int(timeout)) segundos excedido")
                : CommandResult(code: process.terminationStatus, output: output)
        } catch {
            return CommandResult(code: -1, output: error.localizedDescription)
        }
    }
}

struct CommandResult: Sendable {
    let code: Int32
    let output: String
}

struct CleanupLog: Sendable {
    let url: URL
    private static let lock = NSLock()

    func append(_ message: String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           CleanupLogPolicy.shouldRotate(size: UInt64(size)) {
            let previous = url.deletingLastPathComponent().appending(path: "clean-my-mac.previous.log")
            try? fileManager.removeItem(at: previous)
            try? fileManager.moveItem(at: url, to: previous)
        }
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? handle.write(contentsOf: Data("\(stamp) \(message)\n".utf8))
    }
}
