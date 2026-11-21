import AppKit
import CleanMyMacCore
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var monitor: StorageMonitor

    var body: some View {
        Form {
            Section(InterfaceCopy.text("Memory relief", portuguese: "Alívio de memória")) {
                Toggle(InterfaceCopy.text("Automatic memory relief", portuguese: "Alívio automático de memória"), isOn: $monitor.automaticMemoryReliefEnabled)
                Text(InterfaceCopy.text(
                    "When free RAM drops below 300 MB and swap passes 90%, stuck Next.js, tsc, webpack, vite, and turbo builds left behind by old sessions are quit automatically. Comet, Terminal, Finder, and AI, Leave My Mac Alone! are never affected.",
                    portuguese: "Quando a RAM livre cai abaixo de 300 MB e o swap passa de 90%, encerra automaticamente builds Next.js/tsc/webpack/vite/turbo travados que ficaram órfãos de sessões antigas. Nunca afeta Comet, Terminal, Finder ou o próprio AI, Leave My Mac Alone!."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Chrome") {
                Text(InterfaceCopy.text(
                    "The app extension discards up to 8 inactive tabs every 30 seconds when less than 2 GB of RAM is free. The tabs stay open and reload when selected; unsaved content in them can be lost.",
                    portuguese: "A extensão do app descarta até 8 abas inativas a cada 30 segundos quando restam menos de 2 GB de RAM. As abas continuam abertas e recarregam ao voltar; conteúdo não salvo pode se perder."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(InterfaceCopy.text("Show extension folder…", portuguese: "Mostrar pasta da extensão…")) {
                    guard let folder = Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension"),
                          FileManager.default.fileExists(atPath: folder.path) else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
                Text(InterfaceCopy.text(
                    "In chrome://extensions, turn on Developer mode and use Load unpacked on the folder shown.",
                    portuguese: "Em chrome://extensions, ative Modo do desenvolvedor e use Carregar sem compactação na pasta mostrada."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(InterfaceCopy.text("Cleanup mode", portuguese: "Modo de limpeza")) {
                Picker(InterfaceCopy.text("Maximum automatic level", portuguese: "Nível automático máximo"), selection: Binding(
                    get: { monitor.automaticCleanupLevel },
                    set: { monitor.setAutomaticCleanupLevel($0) }
                )) {
                    Text(InterfaceCopy.text("Safe", portuguese: "Seguro")).tag(CleanupLevel.safe)
                    Text(InterfaceCopy.text("Deep", portuguese: "Profundo")).tag(CleanupLevel.deep)
                    Text(InterfaceCopy.text("Emergency", portuguese: "Emergência")).tag(CleanupLevel.emergency)
                }
                Text(InterfaceCopy.text(
                    "Safe cleans caches and builds. Deep adds inactive worktrees and temporary files. Emergency, after a specific authorization, can remove Codex files archived for 7 days and Claude VM bundles with no open files.",
                    portuguese: "Seguro limpa caches e builds. Profundo inclui worktrees inativas e temporários. Emergência, após autorização específica, pode remover arquivos do Codex arquivados há 7 dias e bundles de VM do Claude sem arquivos abertos."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(InterfaceCopy.text("Where files go", portuguese: "Destino dos arquivos")) {
                Picker(
                    InterfaceCopy.text("After the safe check", portuguese: "Depois da verificação segura"),
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
                    Text(InterfaceCopy.text("Move to the Trash", portuguese: "Mover para a Lixeira")).tag(CleanupDestination.trash)
                    Text(InterfaceCopy.text("Trash, then delete only this app's batch", portuguese: "Lixeira + apagar o lote do app")).tag(CleanupDestination.deleteBatch)
                    Text(InterfaceCopy.text("Back up to an external drive, then delete from the Mac", portuguese: "Backup em HD externo + apagar do Mac")).tag(CleanupDestination.externalBackup)
                }
                .pickerStyle(.radioGroup)

                Label(destinationDescription, systemImage: destinationIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if monitor.cleanupDestination == .externalBackup {
                Section(InterfaceCopy.text("External drive", portuguese: "HD externo")) {
                    LabeledContent(InterfaceCopy.text("Folder", portuguese: "Pasta")) {
                        Text(monitor.externalBackupPath ?? InterfaceCopy.text("None selected", portuguese: "Nenhuma selecionada"))
                            .foregroundStyle(monitor.externalBackupReady ? Color.secondary : Color.orange)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Label(
                        monitor.externalBackupReady
                            ? InterfaceCopy.text("External drive ready", portuguese: "HD externo pronto")
                            : InterfaceCopy.text("External drive disconnected or unavailable", portuguese: "HD externo desconectado ou indisponível"),
                        systemImage: monitor.externalBackupReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(monitor.externalBackupReady ? Color.green : Color.orange)
                    Button(InterfaceCopy.text("Choose folder…", portuguese: "Escolher pasta…")) {
                        monitor.chooseExternalBackupFolder()
                    }
                }
            }

            Section(InterfaceCopy.text("Permanent protections", portuguese: "Proteções permanentes")) {
                Text(InterfaceCopy.text(
                    "Personal files, profiles, credentials, current sessions, active projects, and older Trash items stay untouched at every level.",
                    portuguese: "Arquivos pessoais, perfis, credenciais, sessões atuais, projetos ativos e itens antigos da Lixeira permanecem intocados em todos os níveis."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 580, height: monitor.cleanupDestination == .externalBackup ? 900 : 800)
        .navigationTitle("AI, Leave My Mac Alone!")
    }

    private var destinationDescription: String {
        switch monitor.cleanupDestination {
        case .trash:
            InterfaceCopy.text(
                "Recoverable. Space comes back only after you empty the Trash.",
                portuguese: "Recuperável. O espaço só volta depois que você esvaziar a Lixeira."
            )
        case .deleteBatch:
            InterfaceCopy.text(
                "Deletes only the batch this app created and keeps everything that was already in the Trash.",
                portuguese: "Apaga somente o lote criado pelo app e preserva tudo que já estava na Lixeira."
            )
        case .externalBackup:
            InterfaceCopy.text(
                "Moves the original into a recoverable batch, writes a SHA-256 backup, and deletes only that batch.",
                portuguese: "Move o original para um lote recuperável, cria o backup com SHA-256 e apaga somente esse lote."
            )
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
