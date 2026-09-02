import AppKit
import CleanMyMacCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: StorageMonitor
    @State private var confirmingCleanup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            storageCard

            Toggle("Limpeza automática", isOn: $monitor.automaticCleanupEnabled)
                .toggleStyle(.switch)
                .accessibilityHint("Executa a limpeza segura quando o armazenamento chega a 78 por cento")

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Limpeza Profunda", isOn: $monitor.deepCleanupEnabled)
                    .toggleStyle(.switch)
                    .accessibilityHint("Inclui artefatos regeneráveis de worktrees temporárias")
                Text("Inclui somente .next e node_modules ignorados pelo Git em /private/tmp. Sessões, código e projetos ativos continuam protegidos.")
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

            if monitor.isCleaning {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Limpeza em andamento…")
                            .font(.callout.weight(.semibold))
                        Text(monitor.deepCleanupEnabled
                            ? "Verificando também worktrees temporárias seguras."
                            : "Verificando e removendo somente itens seguros.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(monitor.lastAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if confirmingCleanup && !monitor.isCleaning {
                cleanupConfirmation
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Divider()

            HStack(spacing: 8) {
                Button("Verificar agora") {
                    Task { await monitor.sampleNow() }
                }
                .disabled(monitor.isSampling || monitor.isCleaning)

                Button(monitor.isCleaning ? "Limpando…" : cleanupActionTitle) {
                    confirmingCleanup = true
                }
                .buttonStyle(.borderedProminent)
                .tint(statusColor)
                .disabled(monitor.isCleaning || confirmingCleanup)

                Spacer()

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

    private var cleanupConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(monitor.deepCleanupEnabled
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
                    monitor.cleanNow()
                }
            }
        }
        .padding(12)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirmação de limpeza segura")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: monitor.menuBarSymbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 44, height: 44)
                .background(statusColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text("Clean My Mac")
                    .font(.headline)
                Text(statusTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if monitor.isCleaning {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(monitor.snapshot.map { "\($0.usedPercent)%" } ?? "—")
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                Text("usado")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(freeSpace)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: monitor.snapshot?.usedFraction ?? 0)
                .tint(statusColor)
                .accessibilityLabel("Uso do armazenamento")
                .accessibilityValue(monitor.snapshot.map { "\($0.usedPercent) por cento" } ?? "indisponível")

            HStack {
                Label("Alerta em 75%", systemImage: "bell")
                Spacer()
                Label("Limpeza em 78%", systemImage: "sparkles")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusTitle: String {
        switch monitor.level {
        case .normal: "Armazenamento saudável"
        case .warning: "Armazenamento em atenção"
        case .critical: "Limpeza necessária"
        }
    }

    private var statusColor: Color {
        switch monitor.level {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private var freeSpace: String {
        guard let snapshot = monitor.snapshot else { return "Lendo…" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(snapshot.availableBytes), countStyle: .file)) livres"
    }

    private var cleanupConfirmationMessage: String {
        let deepScope = monitor.deepCleanupEnabled
            ? "Também serão examinadas worktrees temporárias em /private/tmp. "
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

    private var cleanupActionTitle: String {
        monitor.deepCleanupEnabled ? "Limpeza Profunda" : "Limpar agora"
    }

    private var cleanupConfirmationButton: String {
        switch monitor.cleanupDestination {
        case .trash: "Mover artefatos para a Lixeira"
        case .deleteBatch: "Limpar caches e artefatos"
        case .externalBackup: "Fazer backup e liberar espaço"
        }
    }
}
