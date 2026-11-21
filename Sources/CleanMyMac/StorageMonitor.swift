import AppKit
import CleanMyMacCore
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class StorageMonitor: ObservableObject {
    @Published private(set) var snapshot: StorageSnapshot?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var lastAction = InterfaceCopy.text(
        "Starting monitoring…",
        portuguese: "Iniciando monitoramento…"
    )
    @Published private(set) var isSampling = false
    @Published private(set) var isCleaning = false
    @Published private(set) var unresolvedShortfallBytes: UInt64 = 0
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginNeedsApproval = false
    @Published private(set) var cleanupDestination: CleanupDestination
    @Published private(set) var externalBackupPath: String?

    @Published var automaticCleanupEnabled: Bool {
        didSet { defaults.set(automaticCleanupEnabled, forKey: Keys.automaticCleanup) }
    }

    @Published private(set) var automaticCleanupLevel: CleanupLevel {
        didSet {
            defaults.set(automaticCleanupLevel.rawValue, forKey: Keys.automaticCleanupLevel)
            SafeCleaner.record("MODE nível automático=\(automaticCleanupLevel.rawValue)")
        }
    }

    @Published private(set) var memorySnapshot: MemorySnapshot?
    @Published private(set) var isRelievingMemory = false
    @Published private(set) var lastMemoryAction = InterfaceCopy.text(
        "Waiting for the first memory reading…",
        portuguese: "Aguardando primeira leitura de memória…"
    )
    @Published var automaticMemoryReliefEnabled: Bool {
        didSet { defaults.set(automaticMemoryReliefEnabled, forKey: Keys.automaticMemoryRelief) }
    }

    private let defaults: UserDefaults
    private var monitoringTask: Task<Void, Never>?
    private var warningLatched: Bool
    private var lastCleanupAt: Date?
    private var lastCleanupMadeProgress: Bool
    private var noProgressStreak: Int
    private var lastMemoryReliefAt: Date?
    private var criticalAlertShown = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cleanupDestination = CleanupDestination(
            rawValue: defaults.string(forKey: Keys.cleanupDestination) ?? ""
        ) ?? .deleteBatch
        externalBackupPath = defaults.string(forKey: Keys.externalBackupPath)
        let cleanupEnabled = defaults.object(forKey: Keys.automaticCleanup) as? Bool ?? true
        automaticCleanupEnabled = cleanupEnabled
        automaticCleanupLevel = CleanupLevel(
            rawValue: defaults.string(forKey: Keys.automaticCleanupLevel) ?? ""
        ) ?? (defaults.bool(forKey: Keys.deepCleanup) ? .deep : .safe)
        automaticMemoryReliefEnabled = defaults.object(forKey: Keys.automaticMemoryRelief) as? Bool ?? true
        defaults.set(cleanupEnabled, forKey: Keys.automaticCleanup)
        warningLatched = defaults.bool(forKey: Keys.warningLatched)
        lastCleanupAt = defaults.object(forKey: Keys.lastCleanupAt) as? Date
        lastCleanupMadeProgress = StoragePolicy.restoredCleanupProgress(
            lastCleanupAt: lastCleanupAt,
            savedValue: defaults.object(forKey: Keys.lastCleanupMadeProgress) as? Bool
        )
        noProgressStreak = defaults.integer(forKey: Keys.noProgressStreak)
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

    var memoryLevel: MemoryLevel {
        memorySnapshot.map(MemoryPolicy.level(for:)) ?? .normal
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
        await sampleMemoryNow()
        Task { await requestNotificationAuthorization() }

        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = StoragePolicy.monitoringInterval(
                    for: self?.snapshot?.usedFraction ?? 0
                )
                try? await Task.sleep(for: .seconds(interval))
                await self?.sampleNow()
                await self?.sampleMemoryNow()
            }
        }
    }

    func sampleNow(allowAutomation: Bool = true, reportResult: Bool = false) async {
        guard !isSampling else { return }
        isSampling = true
        defer { isSampling = false }

        do {
            let isFirstSample = snapshot == nil
            let sample = try await Task.detached(priority: .utility) {
                try StorageReader.read()
            }.value
            snapshot = sample
            lastUpdatedAt = Date()
            if isFirstSample || reportResult {
                lastAction = InterfaceCopy.text(
                    "Disk checked: \(sample.usedPercent)% in use.",
                    portuguese: "Disco verificado: \(sample.usedPercent)% em uso."
                )
            }
            await react(to: sample, allowAutomation: allowAutomation)
        } catch {
            lastAction = InterfaceCopy.text(
                "Could not read the disk: \(error.localizedDescription)",
                portuguese: "Falha ao ler o disco: \(error.localizedDescription)"
            )
            SafeCleaner.record("ERROR leitura do disco: \(error.localizedDescription)")
        }
    }

    func cleanNow(isAutomatic: Bool = false, level requestedLevel: CleanupLevel? = nil) {
        guard !isCleaning else {
            lastAction = InterfaceCopy.text(
                "A cleanup is already running.",
                portuguese: "Uma limpeza já está em andamento."
            )
            return
        }
        let startingFraction = snapshot?.usedFraction ?? 0
        let cleanupLevel = StoragePolicy.cleanupLevel(
            requested: requestedLevel,
            automaticMaximum: automaticCleanupLevel,
            isAutomatic: isAutomatic,
            usedFraction: startingFraction
        )
        isCleaning = true
        lastAction = switch cleanupLevel {
        case .safe:
            isAutomatic
                ? InterfaceCopy.text("Automatic safe cleanup started…", portuguese: "Limpeza automática segura iniciada…")
                : InterfaceCopy.text("Safe cleanup started…", portuguese: "Limpeza segura iniciada…")
        case .deep:
            InterfaceCopy.text("Deep cleanup started…", portuguese: "Limpeza profunda iniciada…")
        case .emergency:
            InterfaceCopy.text("Emergency cleanup started…", portuguese: "Limpeza de emergência iniciada…")
        }

        Task {
            let result = await SafeCleaner.run(
                includeNativeCaches: !isAutomatic,
                escalateNativeCachesAtHardLimit: isAutomatic,
                cleanupLevel: cleanupLevel,
                destination: cleanupDestination,
                externalBackupPath: externalBackupPath
            )
            let now = Date()
            lastCleanupMadeProgress = StoragePolicy.madeMeaningfulProgress(freedBytes: result.freedBytes)
            noProgressStreak = lastCleanupMadeProgress ? 0 : noProgressStreak + 1
            lastCleanupAt = now
            defaults.set(now, forKey: Keys.lastCleanupAt)
            defaults.set(lastCleanupMadeProgress, forKey: Keys.lastCleanupMadeProgress)
            defaults.set(noProgressStreak, forKey: Keys.noProgressStreak)
            isCleaning = false
            await sampleNow(allowAutomation: false)
            let shortfall = snapshot.map(StoragePolicy.bytesRequiredToGetBelowHardLimit) ?? 0
            unresolvedShortfallBytes = shortfall
            let percent = snapshot?.usedPercent ?? 0
            if shortfall > 0 {
                let fraction = snapshot?.usedFraction ?? StoragePolicy.hardLimit
                let retrySeconds = Int(StoragePolicy.cleanupCooldown(
                    for: fraction,
                    lastCleanupMadeProgress: lastCleanupMadeProgress,
                    noProgressStreak: noProgressStreak
                ))
                let missing = ByteCountFormatter.string(fromByteCount: Int64(shortfall), countStyle: .file)
                let protected = result.blockedTargets == 1
                    ? InterfaceCopy.text("1 active target was preserved", portuguese: "1 alvo ativo foi preservado")
                    : InterfaceCopy.text(
                        "\(result.blockedTargets) active targets were preserved",
                        portuguese: "\(result.blockedTargets) alvos ativos foram preservados"
                    )
                let targetMessage = InterfaceCopy.text(
                    "Automatic cleanup cannot free \(missing) without touching protected data; \(protected).",
                    portuguese: "A limpeza automática não consegue liberar \(missing) sem tocar dados protegidos; \(protected)."
                )
                lastAction = InterfaceCopy.text(
                    "\(missing) still must be freed to get under 80%. \(result.summary)",
                    portuguese: "Faltam liberar \(missing) para ficar abaixo de 80%. \(result.summary)"
                )
                SafeCleaner.record("TARGET não atingida faltamBytes=\(shortfall) uso=\(percent)%")
                await notify(
                    title: InterfaceCopy.text(
                        "ACTION NEEDED: SSD at \(percent)%",
                        portuguese: "AÇÃO NECESSÁRIA: SSD em \(percent)%"
                    ),
                    body: InterfaceCopy.text(
                        "\(targetMessage) Next attempt in \(retryDescription(retrySeconds)).",
                        portuguese: "\(targetMessage) Nova tentativa em \(retryDescription(retrySeconds))."
                    ),
                    critical: true,
                    identifier: "storage-target-unresolved"
                )
            } else {
                UNUserNotificationCenter.current().removeDeliveredNotifications(
                    withIdentifiers: ["storage-target-unresolved"]
                )
                lastAction = result.summary
                SafeCleaner.record("TARGET atingida uso=\(percent)%")
                await notify(
                    title: InterfaceCopy.text(
                        "AI, Leave My Mac Alone! finished cleanup",
                        portuguese: "AI, Leave My Mac Alone! concluiu a limpeza"
                    ),
                    body: result.summary,
                    critical: false
                )
            }
        }
    }

    func sampleMemoryNow(allowAutomation: Bool = true) async {
        guard let sample = await Task.detached(priority: .utility, operation: {
            MemoryReliever.readSnapshot()
        }).value else {
            lastMemoryAction = InterfaceCopy.text(
                "Could not read memory.",
                portuguese: "Falha ao ler a memória."
            )
            return
        }
        memorySnapshot = sample

        guard allowAutomation, MemoryPolicy.shouldRunAutomaticRelief(
            snapshot: sample,
            enabled: automaticMemoryReliefEnabled,
            isRelieving: isRelievingMemory,
            lastReliefAt: lastMemoryReliefAt
        ) else { return }

        SafeCleaner.record("TRIGGER alívio automático de memória: swap=\(Int(sample.swapUsedFraction * 100))%")
        await notify(
            title: InterfaceCopy.text(
                "AI, Leave My Mac Alone! relieved memory",
                portuguese: "AI, Leave My Mac Alone! aliviou a memória"
            ),
            body: InterfaceCopy.text(
                "Critical RAM detected; quitting stuck builds.",
                portuguese: "RAM crítica detectada; encerrando builds travados."
            ),
            critical: true
        )
        relieveMemoryNow(isAutomatic: true)
    }

    func relieveMemoryNow(isAutomatic: Bool = false) {
        guard !isRelievingMemory else {
            lastMemoryAction = InterfaceCopy.text(
                "Memory relief is already running.",
                portuguese: "Um alívio de memória já está em andamento."
            )
            return
        }
        isRelievingMemory = true
        lastMemoryAction = isAutomatic
            ? InterfaceCopy.text("Automatic memory relief started…", portuguese: "Alívio automático de memória iniciado…")
            : InterfaceCopy.text("Relieving memory…", portuguese: "Aliviando memória…")

        Task {
            let result = await MemoryReliever.run()
            lastMemoryReliefAt = Date()
            isRelievingMemory = false
            await sampleMemoryNow(allowAutomation: false)
            lastMemoryAction = result.summary
            await notify(
                title: InterfaceCopy.text(
                    "AI, Leave My Mac Alone! finished memory relief",
                    portuguese: "AI, Leave My Mac Alone! concluiu o alívio de memória"
                ),
                body: result.summary,
                critical: false
            )
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
            lastAction = InterfaceCopy.text(
                "Login item failed: \(error.localizedDescription)",
                portuguese: "Falha no início automático: \(error.localizedDescription)"
            )
        }
    }

    func setCleanupDestination(_ destination: CleanupDestination) {
        guard destination != .externalBackup || externalBackupReady else {
            lastAction = InterfaceCopy.text(
                "Choose a folder on an external drive before using this destination.",
                portuguese: "Escolha uma pasta em um HD externo antes de ativar este destino."
            )
            return
        }
        cleanupDestination = destination
        defaults.set(destination.rawValue, forKey: Keys.cleanupDestination)
    }

    func setAutomaticCleanupLevel(_ level: CleanupLevel) {
        if level == .emergency, automaticCleanupLevel != .emergency {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = InterfaceCopy.text(
                "Authorize automatic emergency cleanup?",
                portuguese: "Autorizar limpeza automática de emergência?"
            )
            alert.informativeText = InterfaceCopy.text(
                "While the SSD stays above 80%, the app may delete Codex files archived for at least 7 days and Claude VM bundles with no open files. Current sessions, projects, and personal data stay protected.",
                portuguese: "Quando o SSD continuar acima de 80%, o app poderá apagar arquivos do Codex arquivados há pelo menos 7 dias e bundles de VM do Claude sem arquivos abertos. Sessões atuais, projetos e dados pessoais continuam protegidos."
            )
            alert.addButton(withTitle: InterfaceCopy.text("Authorize Emergency", portuguese: "Autorizar Emergência"))
            alert.addButton(withTitle: InterfaceCopy.text("Cancel", portuguese: "Cancelar"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        automaticCleanupLevel = level
    }

    func chooseExternalBackupFolder() {
        let panel = NSOpenPanel()
        panel.title = InterfaceCopy.text("Choose a backup folder", portuguese: "Escolher pasta de backup")
        panel.prompt = InterfaceCopy.text("Use this folder", portuguese: "Usar esta pasta")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(filePath: "/Volumes", directoryHint: .isDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard isWritableExternalFolder(url) else {
            lastAction = InterfaceCopy.text(
                "Choose a writable folder on an external drive.",
                portuguese: "Escolha uma pasta gravável em um HD externo."
            )
            return
        }
        externalBackupPath = url.standardizedFileURL.path
        defaults.set(externalBackupPath, forKey: Keys.externalBackupPath)
        setCleanupDestination(.externalBackup)
        lastAction = InterfaceCopy.text(
            "External backup configured.",
            portuguese: "Backup externo configurado."
        )
    }

    private func react(to sample: StorageSnapshot, allowAutomation: Bool) async {
        if StoragePolicy.shouldResetWarning(for: sample.usedFraction) {
            warningLatched = false
            unresolvedShortfallBytes = 0
            criticalAlertShown = false
            defaults.set(false, forKey: Keys.warningLatched)
        }

        if allowAutomation, StoragePolicy.shouldRunAutomaticCleanup(
            usedFraction: sample.usedFraction,
            enabled: automaticCleanupEnabled,
            isCleaning: isCleaning,
            lastCleanupAt: lastCleanupAt,
            lastCleanupMadeProgress: lastCleanupMadeProgress,
            noProgressStreak: noProgressStreak
        ) {
            SafeCleaner.record("TRIGGER automático uso=\(sample.usedPercent)%")
            await notify(
                title: InterfaceCopy.text(
                    "AI, Leave My Mac Alone! started cleanup",
                    portuguese: "AI, Leave My Mac Alone! iniciou a limpeza"
                ),
                body: InterfaceCopy.text(
                    "Storage reached \(sample.usedPercent)%.",
                    portuguese: "O armazenamento chegou a \(sample.usedPercent)%."
                ),
                critical: true
            )
            cleanNow(isAutomatic: true)
            return
        }

        if sample.usedFraction >= StoragePolicy.warningThreshold, !warningLatched {
            warningLatched = true
            defaults.set(true, forKey: Keys.warningLatched)
            await notify(
                title: InterfaceCopy.text("Storage is almost full", portuguese: "Armazenamento quase cheio"),
                body: InterfaceCopy.text(
                    "The disk is \(sample.usedPercent)% full. Automatic cleanup starts at 78% to protect the 80% ceiling.",
                    portuguese: "O disco está em \(sample.usedPercent)%. A limpeza automática começa em 78% para proteger o teto de 80%."
                ),
                critical: sample.usedFraction >= StoragePolicy.cleanupThreshold
            )
        }
    }

    private func requestNotificationAuthorization() async {
        guard BundleContext.isBundledApp else { return }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            if !granted {
                SafeCleaner.record("WARN notificações desativadas pelo macOS")
                showCriticalStorageAlertIfNeeded()
            }
        } catch {
            SafeCleaner.record("ERROR autorização de notificações: \(error.localizedDescription)")
            showCriticalStorageAlertIfNeeded()
        }
    }

    private func showCriticalStorageAlertIfNeeded() {
        guard !criticalAlertShown, let snapshot,
              StoragePolicy.hasUnresolvedHardLimit(snapshot) else { return }
        criticalAlertShown = true
        let shortfall = StoragePolicy.bytesRequiredToGetBelowHardLimit(snapshot)
        let missing = ByteCountFormatter.string(
            fromByteCount: Int64(shortfall),
            countStyle: .file
        )
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = InterfaceCopy.text(
            "SSD at \(snapshot.usedPercent)%: action needed",
            portuguese: "SSD em \(snapshot.usedPercent)%: ação necessária"
        )
        alert.informativeText = InterfaceCopy.text(
            "Automatic cleanup cannot guarantee the 80% ceiling. \(missing) still must be freed without touching active projects or protected data.",
            portuguese: "A limpeza automática não consegue garantir o teto de 80%. Ainda faltam liberar \(missing) sem tocar projetos ativos ou dados protegidos."
        )
        alert.addButton(withTitle: InterfaceCopy.text("Open monitor", portuguese: "Abrir monitor"))
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func notify(
        title: String,
        body: String,
        critical: Bool,
        identifier: String? = nil
    ) async {
        guard BundleContext.isBundledApp else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if critical {
            content.sound = .default
            content.interruptionLevel = .timeSensitive
        }
        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(
                    identifier: identifier ?? "storage-\(Int(Date().timeIntervalSince1970))",
                    content: content,
                    trigger: nil
                )
            )
        } catch {
            SafeCleaner.record("ERROR envio de notificação: \(error.localizedDescription)")
        }
    }

    private func retryDescription(_ seconds: Int) -> String {
        if seconds >= 60, seconds.isMultiple(of: 60) {
            let minutes = seconds / 60
            return minutes == 1
                ? InterfaceCopy.text("1 minute", portuguese: "1 minuto")
                : InterfaceCopy.text("\(minutes) minutes", portuguese: "\(minutes) minutos")
        }
        return InterfaceCopy.text("\(seconds) seconds", portuguese: "\(seconds) segundos")
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
                lastAction = InterfaceCopy.text(
                    "Open Login Items to authorize the monitor.",
                    portuguese: "Abra Itens de Início para autorizar o monitor."
                )
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
        static let automaticCleanupLevel = "automaticCleanupLevel"
        static let warningLatched = "warningLatched"
        static let lastCleanupAt = "lastCleanupAt"
        static let lastCleanupMadeProgress = "lastCleanupMadeProgress"
        static let noProgressStreak = "noProgressStreak"
        static let didConfigureLoginItem = "didConfigureLoginItem"
        static let cleanupDestination = "cleanupDestination"
        static let externalBackupPath = "externalBackupPath"
        static let automaticMemoryRelief = "automaticMemoryReliefEnabled"
    }
}

enum BundleContext {
    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
}
