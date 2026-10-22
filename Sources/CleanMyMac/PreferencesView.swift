import AppKit
import CleanMyMacCore
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var monitor: StorageMonitor

    var body: some View {
        Form {
            Section("Alívio de memória") {
                Toggle("Alívio automático de memória", isOn: $monitor.automaticMemoryReliefEnabled)
                Text("Quando a RAM livre cai abaixo de 300 MB e o swap passa de 90%, encerra automaticamente builds Next.js/tsc/webpack/vite/turbo travados que ficaram órfãos de sessões antigas. Nunca afeta Comet, Terminal, Finder ou o próprio AI, Leave My Mac Alone!.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Chrome") {
                Text("A extensão do app descarta até 8 abas inativas a cada 30 segundos quando restam menos de 2 GB de RAM. As abas continuam abertas e recarregam ao voltar; conteúdo não salvo pode se perder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Mostrar pasta da extensão…") {
                    guard let folder = Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension"),
                          FileManager.default.fileExists(atPath: folder.path) else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
                Text("Em chrome://extensions, ative Modo do desenvolvedor e use Carregar sem compactação na pasta mostrada.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Modo de limpeza") {
                Picker("Nível automático máximo", selection: Binding(
                    get: { monitor.automaticCleanupLevel },
                    set: { monitor.setAutomaticCleanupLevel($0) }
                )) {
                    Text("Seguro").tag(CleanupLevel.safe)
                    Text("Profundo").tag(CleanupLevel.deep)
                    Text("Emergência").tag(CleanupLevel.emergency)
                }
                Text("Seguro limpa caches e builds. Profundo inclui worktrees inativas e temporários. Emergência, após autorização específica, pode remover arquivos do Codex arquivados há 7 dias e bundles de VM do Claude sem arquivos abertos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Destino dos arquivos") {
                Picker(
                    "Depois da verificação segura",
                    selection: Binding(
                        get: { monitor.cleanupDestination },
                        set: { destination in
                            if destination == .externalBackup, !monitor.externalBackupReady {
                                monitor.chooseExternalBackupFolder()
                            } else {
                                monitor.setCleanupDestination(destination)
                            }
                        }
                    )
                ) {
                    Text("Mover para a Lixeira").tag(CleanupDestination.trash)
                    Text("Lixeira + apagar o lote do app").tag(CleanupDestination.deleteBatch)
                    Text("Backup em HD externo + apagar do Mac").tag(CleanupDestination.externalBackup)
                }
                .pickerStyle(.radioGroup)

                Label(destinationDescription, systemImage: destinationIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if monitor.cleanupDestination == .externalBackup {
                Section("HD externo") {
                    LabeledContent("Pasta") {
                        Text(monitor.externalBackupPath ?? "Nenhuma selecionada")
                            .foregroundStyle(monitor.externalBackupReady ? Color.secondary : Color.orange)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Label(
                        monitor.externalBackupReady ? "HD externo pronto" : "HD externo desconectado ou indisponível",
                        systemImage: monitor.externalBackupReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(monitor.externalBackupReady ? Color.green : Color.orange)
                    Button("Escolher pasta…") {
                        monitor.chooseExternalBackupFolder()
                    }
                }
            }

            Section("Proteções permanentes") {
                Text("Arquivos pessoais, perfis, credenciais, sessões atuais, projetos ativos e itens antigos da Lixeira permanecem intocados em todos os níveis.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: monitor.cleanupDestination == .externalBackup ? 760 : 690)
        .navigationTitle("AI, Leave My Mac Alone!")
    }

    private var destinationDescription: String {
        switch monitor.cleanupDestination {
        case .trash:
            "Recuperável. O espaço só volta depois que você esvaziar a Lixeira."
        case .deleteBatch:
            "Apaga somente o lote criado pelo app e preserva tudo que já estava na Lixeira."
        case .externalBackup:
            "Move o original para um lote recuperável, cria o backup com SHA-256 e apaga somente esse lote."
        }
    }

    private var destinationIcon: String {
        switch monitor.cleanupDestination {
        case .trash: "trash"
        case .deleteBatch: "trash.slash"
        case .externalBackup: "externaldrive.badge.checkmark"
        }
    }
}
