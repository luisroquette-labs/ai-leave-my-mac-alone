import CleanMyMacCore
import Darwin
import Foundation

struct MemoryReliefResult: Sendable {
    let killedProcesses: Int
    let freedBytes: UInt64
    let stoppedIdleVM: Bool

    var summary: String {
        var parts: [String] = []
        if killedProcesses > 0 {
            let freed = ByteCountFormatter.string(fromByteCount: Int64(freedBytes), countStyle: .memory)
            parts.append("\(killedProcesses) processo(s) de build encerrados, ~\(freed) de RAM liberados.")
        }
        if stoppedIdleVM {
            parts.append("VM Docker (colima) ociosa desligada.")
        }
        guard !parts.isEmpty else { return "Nenhum build travado encontrado; a memória já está saudável." }
        return parts.joined(separator: " ")
    }
}

/// Mata processos de build órfãos que estouram RAM/swap — mesma causa raiz identificada
/// no travamento de 11/09/2026 (dois `next-build` paralelos esquecidos de sessões antigas
/// consumiram ~10GB e forçaram o swap a 95%). Nunca toca no que está fora da lista de alvos.
/// A decisão de alvo vive em MemoryReliefTargetPolicy (Core), coberta por regressão.
enum MemoryReliever {
    static func readSnapshot() -> MemorySnapshot? {
        guard let freeBytes = freePhysicalBytes(), let swap = swapUsage() else { return nil }
        return MemorySnapshot(freeBytes: freeBytes, swapUsedBytes: swap.used, swapTotalBytes: swap.total)
    }

    static func run() async -> MemoryReliefResult {
        await Task.detached(priority: .utility) {
            runSynchronously()
        }.value
    }

    private static func runSynchronously() -> MemoryReliefResult {
        let listing = SafeCleaner.runCommand("/bin/ps", ["-Ao", "pid,rss,etime,command"])
        guard listing.code == 0 else {
            SafeCleaner.record("ERROR memória: falha ao listar processos")
            return MemoryReliefResult(killedProcesses: 0, freedBytes: 0, stoppedIdleVM: false)
        }

        var killed = 0
        var freedKiB: UInt64 = 0
        for line in listing.output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = Int32(fields[0]), let rss = UInt64(fields[1]) else { continue }
            let uptime = MemoryReliefTargetPolicy.parseEtime(String(fields[2]))
            let command = String(fields[3])
            guard MemoryReliefTargetPolicy.shouldKill(command: command, rssKiB: rss, uptimeSeconds: uptime) else { continue }

            _ = SafeCleaner.runCommand("/usr/bin/pkill", ["-TERM", "-P", "\(pid)"])
            kill(pid, SIGTERM)
            Thread.sleep(forTimeInterval: 1)
            kill(pid, SIGKILL)
            killed += 1
            freedKiB += rss
            SafeCleaner.record("MEMORY matou PID \(pid) (\(rss)KiB, uptime \(fields[2])): \(command)")
        }
        let stoppedVM = stopIdleColimaVM(processListing: listing.output)
        return MemoryReliefResult(killedProcesses: killed, freedBytes: freedKiB * 1_024, stoppedIdleVM: stoppedVM)
    }

    /// VM do colima ligada sem nenhum container ativo = sala vazia com a luz acesa
    /// (caso real de 14/09/2026: 18 dias ociosa, ~6GB de RAM/swap). Só desliga via
    /// `colima stop` gracioso e apenas com `docker ps` comprovadamente vazio; nunca
    /// mata o processo da VM diretamente.
    private static func stopIdleColimaVM(processListing: String) -> Bool {
        guard processListing.contains("com.apple.Virtualization.VirtualMachine") else { return false }
        guard let colima = firstExistingBinary(["/opt/homebrew/bin/colima", "/usr/local/bin/colima"]),
              let docker = firstExistingBinary(["/opt/homebrew/bin/docker", "/usr/local/bin/docker"]) else { return false }
        guard SafeCleaner.runCommand(colima, ["status"]).code == 0 else { return false }
        let containers = SafeCleaner.runCommand(docker, ["ps", "-q"])
        guard containers.code == 0,
              containers.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            SafeCleaner.record("MEMORY VM colima tem containers ativos; mantida ligada")
            return false
        }
        let stop = SafeCleaner.runCommand(colima, ["stop"], timeout: 120)
        guard stop.code == 0 else {
            SafeCleaner.record("ERROR memória: colima stop falhou (código \(stop.code))")
            return false
        }
        SafeCleaner.record("MEMORY desligou VM colima ociosa (zero containers)")
        return true
    }

    private static func firstExistingBinary(_ candidates: [String]) -> String? {
        candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private static func freePhysicalBytes() -> UInt64? {
        let result = SafeCleaner.runCommand("/usr/bin/vm_stat", [])
        guard result.code == 0 else { return nil }
        let lines = result.output.split(separator: "\n")
        guard let header = lines.first.map(String.init),
              let ofRange = header.range(of: "of "),
              let bytesRange = header.range(of: " bytes", range: ofRange.upperBound..<header.endIndex),
              let pageSize = UInt64(header[ofRange.upperBound..<bytesRange.lowerBound]),
              let freeLine = lines.first(where: { $0.contains("Pages free") }),
              let numberPart = freeLine.split(separator: ":").last else { return nil }
        let digits = numberPart.trimmingCharacters(in: CharacterSet(charactersIn: ". \n"))
        guard let pages = UInt64(digits) else { return nil }
        return pages * pageSize
    }

    private static func swapUsage() -> (used: UInt64, total: UInt64)? {
        let result = SafeCleaner.runCommand("/usr/sbin/sysctl", ["-n", "vm.swapusage"])
        guard result.code == 0 else { return nil }
        func megabytes(matching label: String) -> Double? {
            guard let range = result.output.range(of: "\(label) = ") else { return nil }
            let digits = result.output[range.upperBound...].prefix(while: { $0.isNumber || $0 == "," || $0 == "." })
            return Double(digits.replacingOccurrences(of: ",", with: "."))
        }
        guard let usedMB = megabytes(matching: "used"), let totalMB = megabytes(matching: "total") else { return nil }
        return (UInt64(usedMB * 1_024 * 1_024), UInt64(totalMB * 1_024 * 1_024))
    }
}
