import AppKit
import CleanMyMacCore
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class StorageMonitor: ObservableObject {
    @Published private(set) var snapshot: StorageSnapshot?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var lastAction = "Iniciando monitoramento…"
    @Published private(set) var isSampling = false
    @Published private(set) var isCleaning = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginNeedsApproval = false
    @Published private(set) var cleanupDestination: CleanupDestination
    @Published private(set) var externalBackupPath: String?

    @Published var automaticCleanupEnabled: Bool {
        didSet { defaults.set(automaticCleanupEnabled, forKey: Keys.automaticCleanup) }
    }

    @Published var deepCleanupEnabled: Bool {
        didSet {
            defaults.set(deepCleanupEnabled, forKey: Keys.deepCleanup)
            SafeCleaner.record("MODE limpeza profunda=\(deepCleanupEnabled)")
        }
    }

    private let defaults: UserDefaults
    private var monitoringTask: Task<Void, Never>?
    private var warningLatched: Bool
    private var lastCleanupAt: Date?
    private var lastCleanupMadeProgress: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cleanupDestination = CleanupDestination(
            rawValue: defaults.string(forKey: Keys.cleanupDestination) ?? ""
        ) ?? .deleteBatch
        externalBackupPath = defaults.string(forKey: Keys.externalBackupPath)
        let cleanupEnabled = defaults.object(forKey: Keys.automaticCleanup) as? Bool ?? true
        automaticCleanupEnabled = cleanupEnabled
        deepCleanupEnabled = defaults.bool(forKey: Keys.deepCleanup)
        defaults.set(cleanupEnabled, forKey: Keys.automaticCleanup)
        warningLatched = defaults.bool(forKey: Keys.warningLatched)
        lastCleanupAt = defaults.object(forKey: Keys.lastCleanupAt) as? Date
        lastCleanupMadeProgress = StoragePolicy.restoredCleanupProgress(
            lastCleanupAt: lastCleanupAt,
            savedValue: defaults.object(forKey: Keys.lastCleanupMadeProgress) as? Bool
        )
        defaults.set(cleanupDestination.rawValue, forKey: Keys.cleanupDestination)

        Task { [weak self] in
            await self?.start()
        }
    }

    deinit {
        monitoringTask?.cancel()
    }

    var level: StorageLevel {
        StoragePolicy.level(for: snapshot?.usedFraction ?? 0)
    }

    var menuBarSymbol: String {
        switch level {
        case .normal: "externaldrive.fill"
        case .warning: "externaldrive.badge.exclamationmark"
        case .critical: "exclamationmark.triangle.fill"
        }
    }

    var menuBarTitle: String {
        snapshot.map { "\($0.usedPercent)%" } ?? "—"
    }

    var logURL: URL { SafeCleaner.logURL }

    var externalBackupReady: Bool {
        guard let externalBackupPath else { return false }
        return isWritableExternalFolder(URL(filePath: externalBackupPath, directoryHint: .isDirectory))
    }

    func start() async {
        guard monitoringTask == nil else { return }
        SafeCleaner.prepareLog()
        configureLoginItemOnFirstLaunch()
        await sampleNow()
        Task { await requestNotificationAuthorization() }

        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = StoragePolicy.monitoringInterval(
                    for: self?.snapshot?.usedFraction ?? 0
                )
                try? await Task.sleep(for: .seconds(interval))
                await self?.sampleNow()
            }
        }
    }

    func sampleNow(allowAutomation: Bool = true) async {
        guard !isSampling else { return }
        isSampling = true
        defer { isSampling = false }

        do {
            let sample = try await Task.detached(priority: .utility) {
                try StorageReader.read()
            }.value
            snapshot = sample
            lastUpdatedAt = Date()
            lastAction = "Disco verificado: \(sample.usedPercent)% em uso."
            await react(to: sample, allowAutomation: allowAutomation)
        } catch {
            lastAction = "Falha ao ler o disco: \(error.localizedDescription)"
            SafeCleaner.record("ERROR leitura do disco: \(error.localizedDescription)")
        }
    }

    func cleanNow(isAutomatic: Bool = false, deepCleanup: Bool? = nil) {
        guard !isCleaning else {
            lastAction = "Uma limpeza já está em andamento."
            return
        }
        let useDeepCleanup = deepCleanup ?? deepCleanupEnabled
        isCleaning = true
        lastAction = useDeepCleanup
            ? "Limpeza profunda iniciada…"
            : (isAutomatic ? "Limpeza automática iniciada…" : "Limpeza segura iniciada…")

        Task {
            let startingFraction = snapshot?.usedFraction ?? 0
            let result = await SafeCleaner.run(
                includeNativeCaches: !isAutomatic || !StoragePolicy.isAtOrAboveHardLimit(startingFraction),
                escalateNativeCachesAtHardLimit: isAutomatic,
                deepCleanupEnabled: useDeepCleanup,
                destination: cleanupDestination,
                externalBackupPath: externalBackupPath
            )
            let now = Date()
            lastCleanupMadeProgress = StoragePolicy.madeMeaningfulProgress(
                removedTargets: result.removedTargets,
                freedBytes: result.freedBytes
            )
            lastCleanupAt = now
            defaults.set(now, forKey: Keys.lastCleanupAt)
            defaults.set(lastCleanupMadeProgress, forKey: Keys.lastCleanupMadeProgress)
            isCleaning = false
            await sampleNow(allowAutomation: false)
            lastAction = result.summary

            let percent = snapshot?.usedPercent ?? 0
            if percent >= Int(StoragePolicy.hardLimit * 100) {
                let fraction = snapshot?.usedFraction ?? StoragePolicy.hardLimit
                let retrySeconds = Int(StoragePolicy.cleanupCooldown(
                    for: fraction,
                    lastCleanupMadeProgress: lastCleanupMadeProgress
                ))
                await notify(
                    title: "SSD acima do limite seguro",
                    body: "A limpeza segura terminou, mas o disco continua em \(percent)%. Nova tentativa em \(retryDescription(retrySeconds)).",
                    critical: true
                )
            } else {
                await notify(
                    title: "Clean My Mac concluiu a limpeza",
                    body: result.summary,
                    critical: false
                )
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard BundleContext.isBundledApp else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItemState()
        } catch {
            lastAction = "Falha no início automático: \(error.localizedDescription)"
        }
    }

    func setCleanupDestination(_ destination: CleanupDestination) {
        guard destination != .externalBackup || externalBackupReady else {
            lastAction = "Escolha uma pasta em um HD externo antes de ativar este destino."
            return
        }
        cleanupDestination = destination
        defaults.set(destination.rawValue, forKey: Keys.cleanupDestination)
    }

    func chooseExternalBackupFolder() {
        let panel = NSOpenPanel()
        panel.title = "Escolher pasta de backup"
        panel.prompt = "Usar esta pasta"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(filePath: "/Volumes", directoryHint: .isDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard isWritableExternalFolder(url) else {
            lastAction = "Escolha uma pasta gravável em um HD externo."
            return
        }
        externalBackupPath = url.standardizedFileURL.path
        defaults.set(externalBackupPath, forKey: Keys.externalBackupPath)
        setCleanupDestination(.externalBackup)
        lastAction = "Backup externo configurado."
    }

    private func react(to sample: StorageSnapshot, allowAutomation: Bool) async {
        if StoragePolicy.shouldResetWarning(for: sample.usedFraction) {
            warningLatched = false
            defaults.set(false, forKey: Keys.warningLatched)
        }

        if allowAutomation, StoragePolicy.shouldRunAutomaticCleanup(
            usedFraction: sample.usedFraction,
            enabled: automaticCleanupEnabled,
            isCleaning: isCleaning,
            lastCleanupAt: lastCleanupAt,
            lastCleanupMadeProgress: lastCleanupMadeProgress
        ) {
            SafeCleaner.record("TRIGGER automático uso=\(sample.usedPercent)%")
            await notify(
                title: "Clean My Mac iniciou a limpeza",
                body: "O armazenamento chegou a \(sample.usedPercent)%.",
                critical: true
            )
            cleanNow(isAutomatic: true)
            return
        }

        if sample.usedFraction >= StoragePolicy.warningThreshold, !warningLatched {
            warningLatched = true
            defaults.set(true, forKey: Keys.warningLatched)
            await notify(
                title: "Armazenamento quase cheio",
                body: "O disco está em \(sample.usedPercent)%. A limpeza automática começa em 78% para proteger o teto de 80%.",
                critical: sample.usedFraction >= StoragePolicy.cleanupThreshold
            )
        }
    }

    private func requestNotificationAuthorization() async {
        guard BundleContext.isBundledApp else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func notify(title: String, body: String, critical: Bool) async {
        guard BundleContext.isBundledApp else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if critical { content.sound = .default }
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "storage-\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: nil
            )
        )
    }

    private func retryDescription(_ seconds: Int) -> String {
        seconds >= 60 && seconds.isMultiple(of: 60)
            ? "\(seconds / 60) minutos"
            : "\(seconds) segundos"
    }

    private func isWritableExternalFolder(_ url: URL) -> Bool {
        guard CleanupDestinationPolicy.isExternalBackupPath(url.path),
              FileManager.default.fileExists(atPath: url.path),
              FileManager.default.isWritableFile(atPath: url.path),
              let values = try? url.resourceValues(
                forKeys: [.volumeIsInternalKey, .volumeIsReadOnlyKey]
              ) else { return false }
        return values.volumeIsInternal == false && values.volumeIsReadOnly != true
    }

    private func configureLoginItemOnFirstLaunch() {
        guard BundleContext.isBundledApp else { return }
        if !defaults.bool(forKey: Keys.didConfigureLoginItem) {
            do {
                try SMAppService.mainApp.register()
                defaults.set(true, forKey: Keys.didConfigureLoginItem)
            } catch {
                lastAction = "Abra Itens de Início para autorizar o monitor."
            }
        }
        refreshLoginItemState()
    }

    private func refreshLoginItemState() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginEnabled = true
            launchAtLoginNeedsApproval = false
        case .requiresApproval:
            launchAtLoginEnabled = false
            launchAtLoginNeedsApproval = true
        default:
            launchAtLoginEnabled = false
            launchAtLoginNeedsApproval = false
        }
    }

    private enum Keys {
        static let automaticCleanup = "automaticCleanupEnabled"
        static let deepCleanup = "deepCleanupEnabled"
        static let warningLatched = "warningLatched"
        static let lastCleanupAt = "lastCleanupAt"
        static let lastCleanupMadeProgress = "lastCleanupMadeProgress"
        static let didConfigureLoginItem = "didConfigureLoginItem"
        static let cleanupDestination = "cleanupDestination"
        static let externalBackupPath = "externalBackupPath"
    }
}

enum BundleContext {
    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
}
