# Arquitetura

## Módulos

| Módulo | Tipo | Responsabilidade |
|---|---|---|
| `CleanMyMacCore` | Library (`Sources/CleanMyMacCore`) | Regras e políticas puras, testáveis sem I/O de UI ou processos externos: limiares e cooldowns de armazenamento (`StoragePolicy.swift`), verificação de backup externo com hash SHA-256 (`BackupVerifier.swift`), enum de destino de limpeza (`CleanupDestination.swift`), política de caminhos/artefatos elegíveis e rotação de log (`CleanupPolicy.swift`, que define os enums `CleanupPolicy` e `CleanupLogPolicy`). |
| `CleanMyMac` | Executable (`Sources/CleanMyMac`), depende de `CleanMyMacCore` | App/UI/orquestração: amostragem do disco e reação a limiares (`StorageMonitor.swift`), varredura de artefatos via `Process` (`SafeCleaner.swift`) e descarte recuperável em lote/backup (`SafeCleanerDisposal.swift`), interface SwiftUI da barra de menus e preferências (`MenuBarView.swift`, `PreferencesView.swift`), entrada da app e injeção do `StorageMonitor` (`CleanMyMacApp.swift`). |
| `CleanMyMacCoreTests` | Test target (`Tests/CleanMyMacCoreTests`), depende de `CleanMyMacCore` e `CleanMyMac` | Testes com Swift Testing (`@Test`, `#expect`) sobre os dois módulos acima. |

Fluxo principal: `StorageMonitor` amostra o disco a cada 30s (5s sob pressão), aplica `StoragePolicy` para decidir alertar ou limpar, e quando aciona a limpeza chama `SafeCleaner.run()`. Internamente, `SafeCleaner` usa `DisposalSession` (em `SafeCleanerDisposal.swift`) para mover/copiar/apagar cada artefato conforme o `CleanupDestination` escolhido pelo usuário, delegando a `BackupVerifier` a verificação byte-a-byte quando o destino é backup externo.

**Regra de fronteira:** `CleanMyMacCore` não importa `AppKit`/`SwiftUI` nem dispara processos externos — só regras determinísticas e I/O de arquivo (hash, comparação de árvore). Qualquer código que rode `Process`, abra `NSOpenPanel` ou publique estado para a UI pertence a `CleanMyMac`.

## Modelo de segurança

Todo comando externo em `SafeCleaner.runCommand` recebe `executable` e `arguments` como um array Swift — nunca como string interpolada em shell — o que elimina injeção de comando pela composição de argumentos (caminhos com espaços, aspas ou `;` não escapam para o shell). O único ponto do arquivo onde um caminho é interpolado dentro de uma string executável é `DisposalSession.deleteExactTrashBatch` (`Sources/CleanMyMac/SafeCleaner.swift`), que monta um script AppleScript para mover um lote exato para a Lixeira via `osascript`; o caminho é escapado (`\` e `"` substituídos por `\\` e `\"`) antes da interpolação.

## Privacidade

Ver a seção "Privacidade" do `README.md`: o app não tem cliente de rede, conta, analytics de terceiros ou backend remoto — todas as amostras de armazenamento, preferências e logs permanecem no Mac.
