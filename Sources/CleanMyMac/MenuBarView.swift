import AppKit
import CleanMyMacCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: StorageMonitor
    @State private var confirmingCleanup = false
    @State private var requestedDeepCleanup = false

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

            if confirmingCleanup && !monitor.isCleaning {
                cleanupConfirmation
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            hairline
            actions
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

    // MARK: - Header

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
        switch monitor.level {
        case .normal: "Armazenamento saudável"
        case .warning: "Armazenamento em atenção"
        case .critical: "Limpeza necessária"
        }
    }

    // MARK: - Instrumentos (disco + memória)

    private var instruments: some View {
        VStack(alignment: .leading, spacing: 16) {
            instrumentRow(
                eyebrow: "DISCO",
                readout: monitor.snapshot.map { "\($0.usedPercent)%" } ?? "—",
                readoutCaption: "usado",
                secondary: freeSpace,
                value: monitor.snapshot?.usedFraction ?? 0,
                thresholds: [StoragePolicy.warningThreshold, StoragePolicy.cleanupThreshold, StoragePolicy.hardLimit],
                tint: monitor.level.tone,
                accessibilityLabel: "Uso do armazenamento",
                accessibilityValue: monitor.snapshot.map { "\($0.usedPercent) por cento" } ?? "indisponível",
                footnote: monitor.lastAction
            )

            instrumentRow(
                eyebrow: "MEMÓRIA",
                readout: freeMemoryValue,
                readoutCaption: "\(freeMemoryUnit) livres",
                secondary: monitor.memorySnapshot.map { "swap \(Int(($0.swapUsedFraction * 100).rounded()))%" } ?? "—",
                value: monitor.memorySnapshot?.swapUsedFraction ?? 0,
                thresholds: [MemoryPolicy.swapWarningFraction, MemoryPolicy.swapCriticalFraction],
                tint: monitor.memoryLevel.tone,
                accessibilityLabel: "Uso de swap",
                accessibilityValue: monitor.memorySnapshot.map { "\(Int(($0.swapUsedFraction * 100).rounded())) por cento" } ?? "indisponível",
                footnote: monitor.lastMemoryAction,
                secondaryHelp: "O swap cai devagar mesmo depois que a RAM já foi liberada — o macOS só libera esse espaço em disco aos poucos."
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

    /// Divide "1,2 GB" em número e unidade para o número ficar do mesmo peso visual
    /// que o "87%" do disco — sem isso a unidade herdava o tamanho gigante do número.
    private var freeMemoryParts: (value: String, unit: String) {
        guard let snapshot = monitor.memorySnapshot else { return ("Lendo…", "") }
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(snapshot.freeBytes), countStyle: .memory)
        let components = formatted.split(separator: " ", maxSplits: 1)
        guard components.count == 2 else { return (formatted, "") }
        return (String(components[0]), String(components[1]))
    }

    private var freeMemoryValue: String { freeMemoryParts.value }
    private var freeMemoryUnit: String { freeMemoryParts.unit }

    private var freeSpace: String {
        guard let snapshot = monitor.snapshot else { return "Lendo…" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(snapshot.availableBytes), countStyle: .file)) livres"
    }

    // MARK: - Automação

    private var automation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AUTOMAÇÃO")
                .font(Typeface.eyebrow)
                .tracking(1.2)
                .foregroundStyle(.secondary)

            Toggle("Alívio automático de memória", isOn: $monitor.automaticMemoryReliefEnabled)
                .toggleStyle(.switch)
                .accessibilityHint("Encerra builds travados quando a RAM livre cai e o swap ultrapassa 90 por cento")

            Toggle("Limpeza automática", isOn: $monitor.automaticCleanupEnabled)
                .toggleStyle(.switch)
                .accessibilityHint("Executa a limpeza segura quando o armazenamento chega a 78 por cento")

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Automática em modo profundo", isOn: $monitor.deepCleanupEnabled)
                    .toggleStyle(.switch)
                    .accessibilityHint("Inclui artefatos regeneráveis de worktrees temporárias")
                Text("Inclui builds Xcode e caches npm/Deno reconhecíveis com mais de 24 h em /private/tmp. Acima de 80%, essa varredura segura é forçada; perfis, sessões, código e projetos ativos continuam protegidos.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Toggle(
                "Abrir ao iniciar sessão",
                isOn: Binding(
                    get: { monitor.launchAtLoginEnabled },
                    set: { monitor.setLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.switch)

            if monitor.launchAtLoginNeedsApproval {
                Label("Aguardando aprovação em Itens de Início", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Atividade e confirmação

    private var activity: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Limpeza em andamento…")
                    .font(.callout.weight(.semibold))
                Text("Verificando e removendo somente itens seguros.")
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
            Text(requestedDeepCleanup
                ? "Executar Limpeza Profunda agora?"
                : "Executar limpeza segura agora?")
                .font(.callout.weight(.semibold))
            Text(cleanupConfirmationMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancelar") { confirmingCleanup = false }
                Spacer()
                Button(cleanupConfirmationButton, role: .destructive) {
                    confirmingCleanup = false
                    monitor.cleanNow(deepCleanup: requestedDeepCleanup)
                }
            }
        }
        .padding(12)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirmação de limpeza segura")
    }

    private var cleanupConfirmationMessage: String {
        let deepScope = requestedDeepCleanup
            ? "Também serão examinados builds e caches temporários reconhecíveis com mais de 24 h em /private/tmp. "
            : ""
        switch monitor.cleanupDestination {
        case .trash:
            return deepScope + "Os artefatos seguros serão movidos para a Lixeira. Nada que já estava nela será apagado."
        case .deleteBatch:
            return deepScope + "Somente o novo lote seguro será movido para a Lixeira e apagado. Itens antigos serão preservados."
        case .externalBackup:
            return deepScope + "Os artefatos seguros irão para um lote recuperável, serão copiados e verificados por SHA-256; somente esse lote será apagado."
        }
    }

    private var cleanupConfirmationButton: String {
        switch monitor.cleanupDestination {
        case .trash: "Mover artefatos para a Lixeira"
        case .deleteBatch: "Limpar caches e artefatos"
        case .externalBackup: "Fazer backup e liberar espaço"
        }
    }

    // MARK: - Ações

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Verificar agora") {
                    Task { await monitor.sampleNow() }
                }
                .frame(maxWidth: .infinity)
                .disabled(monitor.isSampling || monitor.isCleaning)

                Button(monitor.isRelievingMemory ? "Aliviando memória…" : "Aliviar memória agora") {
                    monitor.relieveMemoryNow()
                }
                .frame(maxWidth: .infinity)
                .tint(monitor.memoryLevel == .normal ? nil : monitor.memoryLevel.tone)
                .disabled(monitor.isRelievingMemory)

                Menu {
                    SettingsLink {
                        Label("Preferências…", systemImage: "gearshape")
                    }
                    Button("Abrir log") {
                        NSWorkspace.shared.open(monitor.logURL.deletingLastPathComponent())
                    }
                    Divider()
                    Button("Sair") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Mais opções")
            }

            HStack(spacing: 8) {
                Button("Limpar agora") {
                    requestedDeepCleanup = false
                    confirmingCleanup = true
                }
                .frame(maxWidth: .infinity)
                .disabled(monitor.isCleaning || confirmingCleanup)

                Button("Limpeza Profunda") {
                    requestedDeepCleanup = true
                    confirmingCleanup = true
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .tint(monitor.level.tone)
                .disabled(monitor.isCleaning || confirmingCleanup)
            }
        }
    }

    private var hairline: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }
}
