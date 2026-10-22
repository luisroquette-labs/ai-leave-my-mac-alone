import Foundation

public enum CleanupPolicy {
    public static let archivedSessionMinimumAge: TimeInterval = 7 * 86_400
    public static let artifactDirectoryNames = Set([
        "node_modules", ".next", ".build", ".turbo", ".venv", "DerivedData", "dist",
    ])
    public static let regenerableIgnoredNames = Set([
        "tsconfig.tsbuildinfo", "next-env.d.ts", ".swc", "playwright-report", "test-results", "coverage",
    ])
    public static let aggressiveCacheCooldown: TimeInterval = 6 * 3_600
    public static let aggressiveCacheReclaimReserveBytes: UInt64 = 2 * 1_024 * 1_024 * 1_024
    public static let regenerableCacheRelativePaths = [
        ".npm/_npx",
        "Library/Caches/com.openai.codex/org.sparkle-project.Sparkle",
        "Library/Caches/ms-playwright",
        "Library/Caches/pip",
        "Library/Caches/colima",
        "Library/Caches/pnpm",
        "Library/Caches/node-gyp",
        "Library/Caches/ffmpeg-static-nodejs",
        "Library/Caches/org.swift.swiftpm",
        "Library/Caches/Homebrew",
        "Library/Caches/claude-cli-nodejs",
        "Library/Developer/Xcode/DerivedData",
        "Library/Developer/Xcode/DocumentationCache",
        "Library/Developer/Xcode/iOS DeviceSupport",
        ".cache/uv",
        ".cache/whisper",
        ".cache/huggingface",
        ".cache/swen-edge-deno",
        ".cache/gh",
        ".cache/codeburn",
        ".cache/cycles",
        ".cache/node",
        "Library/Caches/Codex/Playwright",
        "Library/Caches/Google/Chrome-headless",
        "Library/Caches/Comet/Default/Cache",
        "Library/Caches/Comet/Default/Code Cache",
        "Library/Caches/Codex/Default/Cache",
        "Library/Caches/Codex/Default/Code Cache",
        "Library/Caches/Codex/Default/Partitions/codex-browser-app/Cache",
        "Library/Caches/Codex/Default/Partitions/codex-browser-app/Code Cache",
    ]
    public static let lastResortCacheRelativePaths = [
        "Library/pnpm/store",
        ".cache/codex-runtimes",
    ]
    public static let emergencyDirectoryRelativePaths = [
        "Library/Application Support/Claude/vm_bundles",
    ]
    public static let browserCacheLeafNames = ["Cache", "Code Cache", "GPUCache", "image_cache"]
    private static let excludedDirectoryNames = Set([
        ".git", ".codex", ".npm", ".npm-global", ".9router", ".vscode",
        ".Trash", "Library", "Arquivos Públicos", "Arquivos Públicos",
    ])

    public static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        return left == right || left.hasPrefix(right + "/") || right.hasPrefix(left + "/")
    }

    public static func artifactScanRoots(homePath: String) -> [String] {
        var roots = ["Projects", "Projetos", "Developer", "Code", ".worktrees"]
            .map { URL(filePath: homePath).appending(path: $0).path }
        roots += agentWorktreeSubtrees(homePath: homePath)
        return roots
    }

    public static func worktreeContainerRoots(homePath: String) -> [String] {
        let home = URL(filePath: homePath)
        let projects = home.appending(path: "Projects")
        var roots = [
            projects.appending(path: ".worktrees").path,
            home.appending(path: ".worktrees").path,
            home.appending(path: ".codex/worktrees").path,
        ]
        for parent in [home, projects] {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for child in children {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                if child.lastPathComponent.hasSuffix("-worktrees") {
                    roots.append(child.path)
                }
                let nested = child.appending(path: ".worktrees")
                if FileManager.default.fileExists(atPath: nested.path) {
                    roots.append(nested.path)
                }
            }
        }
        return Array(Set(roots)).sorted()
    }

    public static let temporaryArtifactMinimumAge: TimeInterval = 24 * 3_600

    /// Somente formatos inequivocamente regeneráveis em filhos diretos de
    /// /private/tmp. Perfis de navegador e diretórios de agentes não casam.
    public static func isEligibleTemporaryArtifact(
        name: String,
        childNames: Set<String>,
        modificationDate: Date?,
        now: Date = Date()
    ) -> Bool {
        guard !name.hasPrefix("claude-"),
              let modificationDate,
              now.timeIntervalSince(modificationDate) >= temporaryArtifactMinimumAge else {
            return false
        }
        let isXcodeOutput = childNames.contains("Build")
            && (childNames.contains("Index.noindex") || childNames.contains("ModuleCache.noindex"))
        let isNPMCache = childNames.contains("_cacache")
        let isDenoCache = childNames.contains("dep_analysis_cache_v2")
            && childNames.contains("npm")
        return isXcodeOutput || isNPMCache || isDenoCache
    }

    /// Worktrees de agente dentro de pasta protegida (`~/.codex`): só esta subárvore
    /// é varrida; config, sessões e credenciais do Codex continuam protegidas.
    public static func agentWorktreeSubtrees(homePath: String) -> [String] {
        [URL(filePath: homePath).appending(path: ".codex/worktrees").path]
    }

    public static func isProtected(
        _ path: String,
        protectedPaths: [String],
        allowedSubtrees: [String] = []
    ) -> Bool {
        if isInsideWarningDefault(path) { return true }
        let carveOut = allowedSubtrees.first { isInside(path, $0) }
        return protectedPaths.contains { protectedPath in
            guard pathsOverlap(path, protectedPath) else { return false }
            if let carveOut, isInside(carveOut, protectedPath) { return false }
            return true
        }
    }

    private static func isInside(_ path: String, _ ancestor: String) -> Bool {
        let child = normalized(path)
        let parent = normalized(ancestor)
        return child == parent || child.hasPrefix(parent + "/")
    }

    public static func isEligibleArtifact(
        name: String,
        sizeKiB: Int,
        isSymbolicLink: Bool,
        minimumKiB: Int
    ) -> Bool {
        !isSymbolicLink
            && artifactDirectoryNames.contains(name)
            && sizeKiB >= minimumKiB
    }

    public static func hasOnlyRegenerableIgnoredPaths(_ paths: [String]) -> Bool {
        paths.allSatisfy { path in
            path.split(separator: "/").contains {
                let component = String($0)
                return artifactDirectoryNames.contains(component) || regenerableIgnoredNames.contains(component)
            }
        }
    }

    public static func regenerableCachePaths(homePath: String) -> [String] {
        regenerableCacheRelativePaths.map {
            URL(filePath: homePath, directoryHint: .isDirectory).appending(path: $0).standardizedFileURL.path
        }
    }

    public static func lastResortCachePaths(homePath: String) -> [String] {
        lastResortCacheRelativePaths.map {
            URL(filePath: homePath, directoryHint: .isDirectory).appending(path: $0).standardizedFileURL.path
        }
    }

    public static func emergencyDirectoryPaths(homePath: String) -> [String] {
        emergencyDirectoryRelativePaths.map {
            URL(filePath: homePath, directoryHint: .isDirectory).appending(path: $0).standardizedFileURL.path
        }
    }

    public static func isEligibleArchivedSession(
        path: String,
        resolvedPath: String,
        homePath: String,
        modificationDate: Date?,
        now: Date = Date()
    ) -> Bool {
        let root = URL(filePath: homePath, directoryHint: .isDirectory)
            .appending(path: ".codex/archives", directoryHint: .isDirectory)
            .standardizedFileURL.path
        guard normalized(path) == normalized(resolvedPath),
              isInside(path, root), normalized(path) != normalized(root),
              !isInsideWarningDefault(path), let modificationDate else { return false }
        return now.timeIntervalSince(modificationDate) >= archivedSessionMinimumAge
    }

    public static func shouldCleanAggressiveCachePath(
        lastCleanedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let lastCleanedAt else { return true }
        let elapsed = now.timeIntervalSince(lastCleanedAt)
        return elapsed < 0 || elapsed >= aggressiveCacheCooldown
    }

    public static func isSafeCacheCandidate(path: String, resolvedPath: String) -> Bool {
        normalized(path) == normalized(resolvedPath)
            && !isInsideWarningDefault(path)
            && !isInsideWarningDefault(resolvedPath)
    }

    public static func isOwnedDeleteBatch(path: String, trashRoot: String) -> Bool {
        let candidate = URL(filePath: path).standardizedFileURL
        let trash = URL(filePath: trashRoot, directoryHint: .isDirectory).standardizedFileURL
        let prefix = "CleanMyMac-DeleteBatch-"
        let name = candidate.lastPathComponent
        let suffix = name.hasPrefix(prefix) ? name.dropFirst(prefix.count) : ""
        return candidate.deletingLastPathComponent().path == trash.path
            && !suffix.isEmpty
            && suffix.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-"
            }
    }

    public static func bytesToStageFromAggressiveCaches(shortfall: UInt64) -> UInt64 {
        let (total, overflow) = shortfall.addingReportingOverflow(aggressiveCacheReclaimReserveBytes)
        return overflow ? UInt64.max : total
    }

    public static func reachedCleanupTarget(bytesRequired: UInt64, stagedBytes: UInt64) -> Bool {
        bytesRequired > 0 && stagedBytes >= bytesRequired
    }

    public static func shouldExcludeDirectory(named name: String) -> Bool {
        excludedDirectoryNames.contains(name) || name.hasPrefix("claude-")
    }

    public static var excludedDirectoryPatterns: [String] {
        excludedDirectoryNames.sorted() + ["claude-*"]
    }

    /// Worktree do Git (`.git` é arquivo, não pasta): agentes trabalham nelas sem
    /// deixar processo com cwd lá dentro, então só entram na limpeza quando ociosas.
    public static func isLinkedWorktree(_ gitRoot: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: gitRoot + "/.git", isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    /// Janela de ociosidade da worktree: o terminal do agente pode seguir aberto
    /// por dias, mas trabalho sem atividade na própria worktree já terminou.
    public static let worktreeIdleThreshold: TimeInterval = 4 * 3_600
    public static let reclaimableWorktreeIdleThreshold: TimeInterval = 24 * 3_600
    /// Branch cujo upstream sumiu (PR mergeado e branch apagada) já terminou.
    public static let finishedWorktreeIdleThreshold: TimeInterval = 3_600

    public static func worktreeIdleThreshold(upstreamGone: Bool) -> TimeInterval {
        upstreamGone ? finishedWorktreeIdleThreshold : worktreeIdleThreshold
    }

    /// Atividade desconhecida conta como em uso: na dúvida, não apaga.
    public static func isWorktreeIdle(lastActivity: Date?, now: Date, upstreamGone: Bool) -> Bool {
        guard let lastActivity else { return false }
        return now.timeIntervalSince(lastActivity) >= worktreeIdleThreshold(upstreamGone: upstreamGone)
    }

    public static func isReclaimableWorktree(
        isLinkedWorktree: Bool,
        hasBranch: Bool,
        isClean: Bool,
        isActive: Bool,
        lastActivity: Date?,
        now: Date = Date()
    ) -> Bool {
        isLinkedWorktree && hasBranch && isClean && !isActive
            && isReclaimableWorktreeOldEnough(lastActivity: lastActivity, now: now)
    }

    public static func isReclaimableWorktreeOldEnough(lastActivity: Date?, now: Date = Date()) -> Bool {
        guard let lastActivity else { return false }
        return now.timeIntervalSince(lastActivity) >= reclaimableWorktreeIdleThreshold
    }

    /// Outra worktree aponta o próprio node_modules/.next para este alvo:
    /// apagar quebraria a irmã silenciosamente.
    public static func matchingSymlinkSources(
        target: String,
        references: [ArtifactSymlinkReference]
    ) -> [String] {
        let resolvedTarget = normalized(target)
        return references.compactMap {
            normalized($0.destinationPath) == resolvedTarget ? $0.sourcePath : nil
        }
    }

    public static func shouldProtectSymlinkReference(
        isLinkedWorktree: Bool,
        isActive: Bool,
        isIdle: Bool
    ) -> Bool {
        isActive || !isLinkedWorktree || !isIdle
    }

    public static func isProjectActive(_ gitRoot: String, activeDirectories: [String]) -> Bool {
        let root = normalized(gitRoot)
        return activeDirectories.contains {
            let activeDirectory = normalized($0)
            return activeDirectory == root || activeDirectory.hasPrefix(root + "/")
        }
    }

    public static func isVerifiedAfterCleanup(
        statusBefore: String,
        statusAfter: String,
        statusAfterExitCode: Int32,
        targetStillExists: Bool
    ) -> Bool {
        statusAfterExitCode == 0 && statusBefore == statusAfter && !targetStillExists
    }

    private static func normalized(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func isInsideWarningDefault(_ path: String) -> Bool {
        let components = normalized(path).split(separator: "/")
        return components.indices.dropLast().contains {
            components[$0] == "Warning" && components[components.index(after: $0)] == "Default"
        }
    }
}

public struct ArtifactSymlinkReference: Equatable, Sendable {
    public let sourcePath: String
    public let destinationPath: String

    public init(sourcePath: String, destinationPath: String) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
    }
}

public enum CleanupLogPolicy {
    public static let maximumBytes: UInt64 = 5 * 1_024 * 1_024

    public static func shouldRotate(size: UInt64) -> Bool {
        size >= maximumBytes
    }
}
