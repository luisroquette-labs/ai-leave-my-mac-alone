import CleanMyMacCore
import Foundation

// Descarte recuperável dos artefatos aprovados: lote na Lixeira, exclusão exata
// do lote ou backup externo verificado por SHA-256 antes de remover o original.
extension SafeCleaner {
    struct DisposalSession {
        let destination: CleanupDestination
        let externalBackupPath: String?
        private var batchRoot: URL?
        private var removalBatchRoot: URL?
        private var mustPreserveBatch = false
        private var successfulItems = 0

        init(destination: CleanupDestination, externalBackupPath: String?) {
            self.destination = destination
            self.externalBackupPath = externalBackupPath
        }

        func validate() throws {
            guard destination == .externalBackup else { return }
            guard let externalBackupPath,
                  CleanupDestinationPolicy.isExternalBackupPath(externalBackupPath),
                  FileManager.default.fileExists(atPath: externalBackupPath),
                  FileManager.default.isWritableFile(atPath: externalBackupPath) else {
                throw DisposalError.externalDriveUnavailable
            }
            let values = try URL(filePath: externalBackupPath).resourceValues(
                forKeys: [.volumeIsInternalKey, .volumeIsReadOnlyKey]
            )
            guard values.volumeIsInternal == false, values.volumeIsReadOnly != true else {
                throw DisposalError.externalDriveUnavailable
            }
        }

        mutating func stage(_ target: URL, expectedBytes: UInt64) throws -> ArtifactReceipt {
            let root = try ensureBatchRoot()
            let destinationURL = target.pathComponents.dropFirst().reduce(root) {
                $0.appending(path: $1, directoryHint: .inferFromPath)
            }
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            switch destination {
            case .trash, .deleteBatch:
                try FileManager.default.moveItem(at: target, to: destinationURL)
                successfulItems += 1
                return .staged(original: target, stored: destinationURL)
            case .externalBackup:
                let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                if let capacity = values.volumeAvailableCapacityForImportantUsage,
                   capacity < Int64(expectedBytes) {
                    throw DisposalError.insufficientExternalSpace
                }
                let removalRoot = try ensureRemovalBatchRoot()
                let stagedOriginal = target.pathComponents.dropFirst().reduce(removalRoot) {
                    $0.appending(path: $1, directoryHint: .inferFromPath)
                }
                do {
                    try BackupVerifier.copyVerifiedAndStageRemoval(
                        source: target,
                        backup: destinationURL,
                        removalStaging: stagedOriginal
                    )
                } catch {
                    if FileManager.default.fileExists(atPath: stagedOriginal.path)
                        || !FileManager.default.fileExists(atPath: target.path) {
                        mustPreserveBatch = true
                        throw DisposalError.originalUnavailable
                    }
                    throw error
                }
                successfulItems += 1
                return .backedUp(
                    original: target,
                    backup: destinationURL,
                    stagedOriginal: stagedOriginal
                )
            }
        }

        func restore(_ receipt: ArtifactReceipt) throws {
            try FileManager.default.createDirectory(
                at: receipt.original.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            switch receipt {
            case let .staged(original, stored):
                try FileManager.default.moveItem(at: stored, to: original)
            case let .backedUp(original, backup, stagedOriginal):
                try FileManager.default.moveItem(at: stagedOriginal, to: original)
                try BackupVerifier.verifyCopy(source: backup, destination: original)
            }
        }

        mutating func preserveBatch() {
            mustPreserveBatch = true
        }

        mutating func finalize(log: CleanupLog) -> Bool {
            guard let batchRoot else { return true }
            if mustPreserveBatch {
                log.append("ERROR lote mantido para recuperação: \(batchRoot.path)")
                if let removalBatchRoot {
                    log.append("ERROR original local preservado para recuperação: \(removalBatchRoot.path)")
                }
                return false
            }
            if successfulItems == 0 {
                try? FileManager.default.removeItem(at: batchRoot)
                if let removalBatchRoot {
                    try? FileManager.default.removeItem(at: removalBatchRoot)
                }
                guard !FileManager.default.fileExists(atPath: batchRoot.path),
                      removalBatchRoot.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true else {
                    log.append("ERROR lote sem itens confirmados não pôde ser descartado")
                    return false
                }
                log.append("CLEAN lote sem itens confirmados descartado")
                return true
            }
            switch destination {
            case .trash:
                log.append("TRASH lote recuperável: \(batchRoot.path)")
                return true
            case .externalBackup:
                log.append("BACKUP lote verificado: \(batchRoot.path)")
                guard let removalBatchRoot else { return true }
                return deleteExactTrashBatch(removalBatchRoot, log: log)
            case .deleteBatch:
                return deleteExactTrashBatch(batchRoot, log: log)
            }
        }

        private func deleteExactTrashBatch(_ root: URL, log: CleanupLog) -> Bool {
            let escapedPath = root.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            with timeout of 600 seconds
                tell application "Finder" to delete POSIX file "\(escapedPath)"
            end timeout
            """
            let result = SafeCleaner.runCommand("/usr/bin/osascript", ["-e", script], timeout: 620)
            guard result.code == 0, !FileManager.default.fileExists(atPath: root.path) else {
                log.append("ERROR lote mantido para recuperação: \(root.path) \(result.output)")
                return false
            }
            log.append("DELETE lote exato concluído: \(root.path)")
            return true
        }

        private mutating func ensureBatchRoot() throws -> URL {
            if let batchRoot { return batchRoot }
            let batchName = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
            let root: URL
            switch destination {
            case .trash, .deleteBatch:
                root = SafeCleaner.home
                    .appending(path: ".Trash", directoryHint: .isDirectory)
                    .appending(path: "CleanMyMac-\(batchName)", directoryHint: .isDirectory)
            case .externalBackup:
                guard let externalBackupPath else { throw DisposalError.externalDriveUnavailable }
                root = URL(filePath: externalBackupPath, directoryHint: .isDirectory)
                    .appending(path: "AI, Leave My Mac Alone! Backups", directoryHint: .isDirectory)
                    .appending(path: batchName, directoryHint: .isDirectory)
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            batchRoot = root
            return root
        }

        private mutating func ensureRemovalBatchRoot() throws -> URL {
            if let removalBatchRoot { return removalBatchRoot }
            let root = SafeCleaner.home
                .appending(path: ".Trash", directoryHint: .isDirectory)
                .appending(
                    path: "CleanMyMac-BackupRemoval-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)",
                    directoryHint: .isDirectory
                )
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            removalBatchRoot = root
            return root
        }
    }

    enum ArtifactReceipt {
        case staged(original: URL, stored: URL)
        case backedUp(original: URL, backup: URL, stagedOriginal: URL)

        var original: URL {
            switch self {
            case let .staged(original, _), let .backedUp(original, _, _): original
            }
        }
    }

    enum DisposalError: LocalizedError {
        case externalDriveUnavailable
        case insufficientExternalSpace
        case originalUnavailable

        var errorDescription: String? {
            switch self {
            case .externalDriveUnavailable:
                "O HD externo escolhido não está montado ou não permite gravação."
            case .insufficientExternalSpace:
                "O HD externo não tem espaço livre suficiente para verificar o backup."
            case .originalUnavailable:
                "O original não pôde ser confirmado nem restaurado; os lotes foram preservados."
            }
        }
    }
}
