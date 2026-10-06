import Foundation

public enum CleanupPolicy {
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
            && (name == "node_modules" || name == ".next")
            && sizeKiB >= minimumKiB
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
