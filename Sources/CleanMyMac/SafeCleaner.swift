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
        let before = (try? StorageReader.read().availableBytes) ?? 0
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
            log: log,
            disposal: &disposal
        )
        removedTargets += artifactResult.removed
        blockedTargets += artifactResult.blocked
        failedTargets += artifactResult.failed
        if !disposal.finalize(log: log) {
            failedTargets += 1
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

        let commands: [([String], [String], URL?, TimeInterval)] = [
            ([home.appending(path: ".local/bin/uv").path, "/opt/homebrew/bin/uv", "/usr/local/bin/uv"], ["cache", "prune"], nil, 30),
            (["/opt/homebrew/bin/npm", "/usr/local/bin/npm"], ["cache", "clean", "--force"], nil, 120),
            ([home.appending(path: ".bun/bin/bun").path, "/opt/homebrew/bin/bun", "/usr/local/bin/bun"], ["pm", "cache", "rm"], bunWorkingDirectory, 120),
            (["/opt/homebrew/bin/deno", "/usr/local/bin/deno"], ["clean"], nil, 120),
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

    private static func cleanGeneratedArtifacts(
        deepCleanupEnabled: Bool,
        log: CleanupLog,
        disposal: inout DisposalSession
    ) -> (removed: Int, blocked: Int, failed: Int) {
        var removed = 0
        var blocked = 0
        var failed = 0
        do {
            try disposal.validate()
        } catch {
            log.append("ERROR destino indisponível: \(error.localizedDescription)")
            return (0, 0, 1)
        }
        let scanStartedAt = Date()
        let scanResult = artifactCandidates(deepCleanupEnabled: deepCleanupEnabled, log: log)
        let candidates = scanResult.candidates
        failed += scanResult.scanFailures
        let scanMilliseconds = Int(Date().timeIntervalSince(scanStartedAt) * 1_000)
        log.append("SCAN candidatos=\(candidates.count) duracaoMs=\(scanMilliseconds) falhas=\(scanResult.scanFailures)")

        guard let activeDirectories = activeWorkingDirectories() else {
            log.append("BLOCK inspeção de processos indisponível")
            return (0, candidates.count, failed)
        }
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
                ["-C", gitRoot.path, "status", "--porcelain=v1", "-z"]
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
                ["-C", gitRoot.path, "status", "--porcelain=v1", "-z"]
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
        return (removed, blocked, failed)
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
        arguments += [
            ")", "-prune", "-o", "-type", "d", "(",
            "-name", "node_modules", "-o", "-name", ".next",
            ")", "-print0", "-prune",
            "-o", "-type", "l", "(", "-name", "node_modules", "-o", "-name", ".next", ")", "-print0",
        ]

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
        let lastGitActivity = ["HEAD", "index", "logs/HEAD"]
            .compactMap { try? FileManager.default.attributesOfItem(atPath: gitDir.appending(path: $0).path)[.modificationDate] as? Date }
            .max()

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
