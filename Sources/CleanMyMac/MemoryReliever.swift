import CleanMyMacCore
import Darwin
import Foundation

struct MemoryReliefResult: Sendable {
    let killedProcesses: Int
    let freedBytes: UInt64

    var summary: String {
        guard killedProcesses > 0 else { return "Nenhum build travado encontrado; a memória já está saudável." }
        let freed = ByteCountFormatter.string(fromByteCount: Int64(freedBytes), countStyle: .memory)
        return "\(killedProcesses) processo(s) de build encerrados, ~\(freed) de RAM liberados."
    }
}

/// Mata processos de build órfãos que estouram RAM/swap — mesma causa raiz identificada
/// no travamento de 11/09/2026 (dois `next-build` paralelos esquecidos de sessões antigas
/// consumiram ~10GB e forçaram o swap a 95%). Nunca toca no que está fora da lista de alvos.
enum MemoryReliever {
    private static let targetPatterns = [
        "next-build", "tsc --", "webpack", "vite build",
        "turbo run", "turbo build", "esbuild", "rollup", "jest ", "vitest run", "next-server",
    ]
    private static let neverKill = [
        "Comet", "Terminal", "claude.exe", "Finder", "WindowServer",
        "loginwindow", "kernel_task", "Dock", "SystemUIServer", "iTerm",
    ]
    private static let minimumRSSKiB: UInt64 = 1_000_000 // 1GB

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
        let listing = SafeCleaner.runCommand("/bin/ps", ["-Ao", "pid,rss,command"])
        guard listing.code == 0 else {
            SafeCleaner.record("ERROR memória: falha ao listar processos")
            return MemoryReliefResult(killedProcesses: 0, freedBytes: 0)
        }

        var killed = 0
        var freedKiB: UInt64 = 0
        for line in listing.output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int32(fields[0]), let rss = UInt64(fields[1]) else { continue }
            let command = String(fields[2])
            guard rss >= minimumRSSKiB,
                  targetPatterns.contains(where: { command.contains($0) }),
                  !neverKill.contains(where: { command.contains($0) }) else { continue }

            _ = SafeCleaner.runCommand("/usr/bin/pkill", ["-TERM", "-P", "\(pid)"])
            kill(pid, SIGTERM)
            Thread.sleep(forTimeInterval: 1)
            kill(pid, SIGKILL)
            killed += 1
            freedKiB += rss
            SafeCleaner.record("MEMORY matou PID \(pid) (\(rss)KiB): \(command)")
        }
        return MemoryReliefResult(killedProcesses: killed, freedBytes: freedKiB * 1_024)
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
