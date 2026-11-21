import AppKit
import CleanMyMacCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: StorageMonitor
    @State private var confirmingCleanup = false
    @State private var requestedCleanupLevel = CleanupLevel.safe

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            hairline
            instruments
            hairline
            automation

            if monitor.isCleaning {
                activity
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            hairline
            if confirmingCleanup && !monitor.isCleaning {
                cleanupConfirmation
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                actions
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: confirmingCleanup)
        .animation(.easeInOut(duration: 0.2), value: monitor.isCleaning)
        .onChange(of: monitor.isCleaning) { _, isCleaning in
            if isCleaning { confirmingCleanup = false }
        }
    }


    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(monitor.level.tone.opacity(0.12))
                Circle()
                    .strokeBorder(monitor.level.tone.opacity(0.55), lineWidth: 1.5)
                Image(systemName: monitor.menuBarSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(monitor.level.tone)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("AI, Leave My Mac Alone!").font(.headline).lineLimit(1)
                Text(statusTitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if monitor.isCleaning {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var statusTitle: String {
        if monitor.unresolvedShortfallBytes > 0 {
            return InterfaceCopy.text("80% ceiling not protected", portuguese: "Teto de 80% não protegido")
        }
        return switch monitor.level {
        case .normal:
            InterfaceCopy.text("Storage looks healthy", portuguese: "Armazenamento saudável")
        case .warning:
            InterfaceCopy.text("Storage needs attention", portuguese: "Armazenamento em atenção")
        case .critical:
            InterfaceCopy.text("Cleanup needed", portuguese: "Limpeza necessária")
        }
    }

    private var instruments: some View {
        VStack(alignment: .leading, spacing: 16) {
            instrumentRow(
                eyebrow: InterfaceCopy.text("DISK", portuguese: "DISCO"),
                readout: monitor.snapshot.map { "\($0.usedPercent)%" } ?? "—",
                readoutCaption: InterfaceCopy.text("used", portuguese: "usado"),
                secondary: freeSpace,
                value: monitor.snapshot?.usedFraction ?? 0,
                thresholds: [StoragePolicy.warningThreshold, StoragePolicy.cleanupThreshold, StoragePolicy.hardLimit],
                tint: monitor.level.tone,
                accessibilityLabel: InterfaceCopy.text("Storage used", portuguese: "Uso do armazenamento"),
                accessibilityValue: monitor.snapshot.map {
                    InterfaceCopy.text("\($0.usedPercent) percent", portuguese: "\($0.usedPercent) por cento")
                } ?? InterfaceCopy.text("unavailable", portuguese: "indisponível"),
                footnote: monitor.lastAction
            )

            instrumentRow(
                eyebrow: InterfaceCopy.text("MEMORY", portuguese: "MEMÓRIA"),
                readout: freeMemoryValue,
                readoutCaption: freeMemoryCaption,
                secondary: monitor.memorySnapshot.map { "swap \(Int(($0.swapUsedFraction * 100).rounded()))%" } ?? "—",
                value: monitor.memorySnapshot?.swapUsedFraction ?? 0,
                thresholds: [MemoryPolicy.swapWarningFraction, MemoryPolicy.swapCriticalFraction],
                tint: monitor.memoryLevel.tone,
                accessibilityLabel: InterfaceCopy.text("Swap used", portuguese: "Uso de swap"),
                accessibilityValue: monitor.memorySnapshot.map {
                    let percent = Int(($0.swapUsedFraction * 100).rounded())
                    return InterfaceCopy.text("\(percent) percent", portuguese: "\(percent) por cento")
                } ?? InterfaceCopy.text("unavailable", portuguese: "indisponível"),
                footnote: monitor.lastMemoryAction,
                secondaryHelp: InterfaceCopy.text(
                    "Swap falls slowly after RAM is already free. macOS releases that disk space gradually.",
                    portuguese: "O swap cai devagar mesmo depois que a RAM já foi liberada — o macOS só libera esse espaço em disco aos poucos."
                )
            )
        }
    }

    private func instrumentRow(
        eyebrow: String,
        readout: String,
        readoutCaption: String,
        secondary: String,
        value: Double,
        thresholds: [Double],
        tint: Color,
        accessibilityLabel: String,
        accessibilityValue: String,
        footnote: String,
        secondaryHelp: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(Typeface.eyebrow)
                .tracking(1.2)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text(readout).font(Typeface.readout(24))
                Text(readoutCaption).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(secondary)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help(secondaryHelp ?? "")
            }

            ThresholdGauge(value: value, thresholds: thresholds, tint: tint)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)

            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var freeMemoryParts: (value: String, unit: String) {
        guard let snapshot = monitor.memorySnapshot else {
            return (InterfaceCopy.text("Reading…", portuguese: "Lendo…"), "")
        }
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(snapshot.freeBytes), countStyle: .memory)
        let components = formatted.split(separator: " ", maxSplits: 1)
        guard components.count == 2 else { return (formatted, "") }
        return (String(components[0]), String(components[1]))
    }

    private var freeMemoryValue: String { freeMemoryParts.value }
    private var freeMemoryUnit: String { freeMemoryParts.unit }
    private var freeMemoryCaption: String {
        guard !freeMemoryUnit.isEmpty else { return "" }
        return "\(freeMemoryUnit) \(InterfaceCopy.text("free", portuguese: "livres"))"
    }

    private var freeSpace: String {
        guard let snapshot = monitor.snapshot else {
            return InterfaceCopy.text("Reading…", portuguese: "Lendo…")
        }
        let amount = ByteCountFormatter.string(fromByteCount: Int64(snapshot.availableBytes), countStyle: .file)
        return InterfaceCopy.text("\(amount) free", portuguese: "\(amount) livres")
    }

    private var automation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(InterfaceCopy.text("AUTOMATION", portuguese: "AUTOMAÇÃO"))
                .font(Typeface.eyebrow)
                .tracking(1.2)
                .foregroundStyle(.secondary)

            Toggle(InterfaceCopy.text("Automatic memory relief", portuguese: "Alívio automático de memória"), isOn: $monitor.automaticMemoryReliefEnabled)
                .toggleStyle(.switch)
                .accessibilityHint(InterfaceCopy.text(
                    "Quits stuck builds when free RAM drops and swap passes 90 percent",
                    portuguese: "Encerra builds travados quando a RAM livre cai e o swap ultrapassa 90 por cento"
                ))

            Toggle(InterfaceCopy.text("Automatic cleanup", portuguese: "Limpeza automática"), isOn: $monitor.automaticCleanupEnabled)
                .toggleStyle(.switch)
                .accessibilityHint(InterfaceCopy.text(
                    "Runs cleanup when storage reaches 78 percent",
                    portuguese: "Executa a limpeza segura quando o armazenamento chega a 78 por cento"
                ))

            Picker(InterfaceCopy.text("Automatic level", portuguese: "Nível automático"), selection: Binding(
                get: { monitor.automaticCleanupLevel },
                set: { monitor.setAutomaticCleanupLevel($0) }
            )) {
                Text(InterfaceCopy.text("Safe", portuguese: "Seguro")).tag(CleanupLevel.safe)
                Text(InterfaceCopy.text("Deep", portuguese: "Profundo")).tag(CleanupLevel.deep)
                Text(InterfaceCopy.text("Emergency", portuguese: "Emergência")).tag(CleanupLevel.emergency)
            }
            .pickerStyle(.segmented)
            .accessibilityHint(InterfaceCopy.text(
                "Sets the highest level automatic cleanup may use",
                portuguese: "Define o maior nível que a limpeza automática pode usar"
            ))

            Text(automaticLevelDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle(
                InterfaceCopy.text("Open at login", portuguese: "Abrir ao iniciar sessão"),
                isOn: Binding(
                    get: { monitor.launchAtLoginEnabled },
                    set: { monitor.setLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.switch)

            if monitor.launchAtLoginNeedsApproval {
                Label(
                    InterfaceCopy.text("Waiting for approval in Login Items", portuguese: "Aguardando aprovação em Itens de Início"),
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private var activity: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(InterfaceCopy.text("Cleaning in progress…", portuguese: "Limpeza em andamento…"))
                    .font(.callout.weight(.semibold))
                Text(InterfaceCopy.text(
                    "Checking and removing safe items only.",
                    portuguese: "Verificando e removendo somente itens seguros."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(monitor.level.tone.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private var cleanupConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(cleanupConfirmationTitle)
                .font(.callout.weight(.semibold))
            Text(cleanupConfirmationMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(InterfaceCopy.text("Cancel", portuguese: "Cancelar")) { confirmingCleanup = false }
                Spacer()
                Button(cleanupConfirmationButton, role: .destructive) {
                    confirmingCleanup = false
                    monitor.cleanNow(level: requestedCleanupLevel)
                }
            }
        }
        .padding(12)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(InterfaceCopy.text("Safe cleanup confirmation", portuguese: "Confirmação de limpeza segura"))
    }

    private var cleanupConfirmationMessage: String {
        let levelScope = switch requestedCleanupLevel {
        case .safe:
            ""
        case .deep:
            InterfaceCopy.text(
                "Regenerable builds, inactive worktrees, and recognized temporary caches will also be examined. ",
                portuguese: "Também serão examinados builds, worktrees e caches temporários regeneráveis. "
            )
        case .emergency:
            InterfaceCopy.text(
                "Codex files archived for 7 days and Claude VM bundles with no open files may also be removed. ",
                portuguese: "Também poderão ser removidos arquivos do Codex arquivados há 7 dias e bundles de VM do Claude sem arquivos abertos. "
            )
        }
        switch monitor.cleanupDestination {
        case .trash:
            return levelScope + InterfaceCopy.text(
                "Safe artifacts will be moved to the Trash. Nothing already in it will be deleted.",
                portuguese: "Os artefatos seguros serão movidos para a Lixeira. Nada que já estava nela será apagado."
            )
        case .deleteBatch:
            return levelScope + InterfaceCopy.text(
                "Only the new safe batch will be moved to the Trash and deleted. Older Trash items stay.",
                portuguese: "Somente o novo lote seguro será movido para a Lixeira e apagado. Itens antigos serão preservados."
            )
        case .externalBackup:
            return levelScope + InterfaceCopy.text(
                "Safe artifacts go to a recoverable batch, are copied, and are checked with SHA-256. Only that batch is deleted.",
                portuguese: "Os artefatos seguros irão para um lote recuperável, serão copiados e verificados por SHA-256; somente esse lote será apagado."
            )
        }
    }

    private var cleanupConfirmationTitle: String {
        switch requestedCleanupLevel {
        case .safe:
            InterfaceCopy.text("Run safe cleanup now?", portuguese: "Executar limpeza segura agora?")
        case .deep:
            InterfaceCopy.text("Run deep cleanup now?", portuguese: "Executar limpeza profunda agora?")
        case .emergency:
            InterfaceCopy.text("Run emergency cleanup now?", portuguese: "Executar limpeza de emergência agora?")
        }
    }

    private var automaticLevelDescription: String {
        switch monitor.automaticCleanupLevel {
        case .safe:
            InterfaceCopy.text(
                "Automation stays limited to regenerable caches and builds.",
                portuguese: "Automação limitada a caches e builds regeneráveis."
            )
        case .deep:
            InterfaceCopy.text(
                "Also includes inactive worktrees and recognized temporary files.",
                portuguese: "Também inclui worktrees inativas e temporários reconhecíveis."
            )
        case .emergency:
            InterfaceCopy.text(
                "With a persistent authorization, includes archived files and regenerable VMs when space is still short.",
                portuguese: "Com autorização persistente, inclui arquivos arquivados e VMs regeneráveis quando ainda faltar espaço."
            )
        }
    }

    private var cleanupConfirmationButton: String {
        switch monitor.cleanupDestination {
        case .trash:
            InterfaceCopy.text("Move artifacts to the Trash", portuguese: "Mover artefatos para a Lixeira")
        case .deleteBatch:
            InterfaceCopy.text("Clean caches and artifacts", portuguese: "Limpar caches e artefatos")
        case .externalBackup:
            InterfaceCopy.text("Back up and free space", portuguese: "Fazer backup e liberar espaço")
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(InterfaceCopy.text("Check now", portuguese: "Verificar agora")) {
                    Task { await monitor.sampleNow(reportResult: true) }
                }
                .frame(maxWidth: .infinity)
                .disabled(monitor.isSampling || monitor.isCleaning)

                Button(monitor.isRelievingMemory
                    ? InterfaceCopy.text("Relieving memory…", portuguese: "Aliviando memória…")
                    : InterfaceCopy.text("Relieve memory now", portuguese: "Aliviar memória agora")) {
                    monitor.relieveMemoryNow()
                }
                .frame(maxWidth: .infinity)
                .tint(monitor.memoryLevel == .normal ? nil : monitor.memoryLevel.tone)
                .disabled(monitor.isRelievingMemory)

                Menu {
                    SettingsLink {
                        Label(InterfaceCopy.text("Settings…", portuguese: "Preferências…"), systemImage: "gearshape")
                    }
                    Button(InterfaceCopy.text("Open log", portuguese: "Abrir log")) {
                        NSWorkspace.shared.open(monitor.logURL.deletingLastPathComponent())
                    }
                    Divider()
                    Button(InterfaceCopy.text("Quit", portuguese: "Sair")) { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel(InterfaceCopy.text("More options", portuguese: "Mais opções"))
            }

            HStack(spacing: 8) {
                Button(InterfaceCopy.text("Clean now", portuguese: "Limpar agora")) {
                    requestedCleanupLevel = .safe
                    confirmingCleanup = true
                }
                .frame(maxWidth: .infinity)
                .disabled(monitor.isCleaning || confirmingCleanup)

                Button(InterfaceCopy.text("Deep Clean", portuguese: "Limpeza Profunda")) {
                    requestedCleanupLevel = .deep
                    confirmingCleanup = true
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .tint(monitor.level.tone)
                .disabled(monitor.isCleaning || confirmingCleanup)
            }
            Button(InterfaceCopy.text("Emergency Clean", portuguese: "Limpeza de Emergência")) {
                requestedCleanupLevel = .emergency
                confirmingCleanup = true
            }
            .frame(maxWidth: .infinity)
            .tint(.red)
            .disabled(monitor.isCleaning || confirmingCleanup)
        }
    }

    private var hairline: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }
}
