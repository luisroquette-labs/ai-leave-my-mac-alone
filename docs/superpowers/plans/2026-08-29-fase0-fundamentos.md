# Fase 0 — Fundamentos: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Documentar a arquitetura real do AI, Leave My Mac Alone! (módulos + modelo de segurança) e fechar a única lacuna técnica real de "Fundamentos": `find`/`du` descartam candidatos silenciosamente quando falham, sem deixar rastro no log.

**Architecture:** Nenhuma mudança estrutural. Task 1 é documentação pura (`docs/ARCHITECTURE.md`), sourced diretamente do código existente. Task 2 é um fix cirúrgico em `Sources/CleanMyMac/SafeCleaner.swift`: extrai uma função pura `scanFailureLogMessage` para formar a mensagem de log, e passa a chamá-la nos dois pontos onde `find`/`du` hoje falham em silêncio.

**Tech Stack:** Swift 6 / SwiftUI / Foundation. Testes com Swift Testing (`import Testing`, `@Test`, `#expect`) no target `CleanMyMacCoreTests`, que já depende de `CleanMyMacCore` e `CleanMyMac`.

## Global Constraints

- Protocolo de Fix do usuário (CLAUDE.md): ler o arquivo antes de editar, grep pelo mesmo padrão em outros pontos, escrever o teste que reproduz o bug ANTES do fix (deve falhar sem o fix, passar com ele), aplicar o fix, rodar o preflight canônico, commitar fix + teste **no mesmo commit** (nunca separado).
- Preflight canônico é `./Scripts/preflight.sh` — zero falhas obrigatório antes de qualquer commit ser considerado pronto para push (push em si não é pedido nesta fase).
- Mudanças cirúrgicas: não tocar em código não relacionado ao escopo (ex.: a duplicata cosmética `"Arquivos Públicos"` em `SafeCleaner.swift:41,245` e também em `Sources/CleanMyMacCore/CleanupPolicy.swift:6` fica intocada — é um achado à parte, fora de escopo, reportado ao usuário ao final da fase).
- Reutilizar estruturas existentes: usar o `CleanupLog` e o padrão de mensagens `"ERROR ..."` já em uso no arquivo, não criar um sistema de log paralelo.
- Não fazer push/deploy sem pedido explícito do usuário.

---

### Task 1: `docs/ARCHITECTURE.md`

**Files:**
- Create: `docs/ARCHITECTURE.md`

**Interfaces:**
- Consumes: nada (documentação, não depende de código de outra task)
- Produces: nada consumido por outra task

- [ ] **Step 1: Escrever o documento**

Criar `docs/ARCHITECTURE.md` com exatamente este conteúdo:

```markdown
# Arquitetura

## Módulos

| Módulo | Tipo | Responsabilidade |
|---|---|---|
| `CleanMyMacCore` | Library (`Sources/CleanMyMacCore`) | Regras e políticas puras, testáveis sem I/O de UI ou processos externos: limiares e cooldowns de armazenamento (`StoragePolicy.swift`), verificação de backup externo com hash SHA-256 (`BackupVerifier.swift`), enum de destino de limpeza (`CleanupDestination.swift`), política de caminhos/artefatos elegíveis e rotação de log (`CleanupPolicy.swift`, que define os enums `CleanupPolicy` e `CleanupLogPolicy`). |
| `CleanMyMac` | Executable (`Sources/CleanMyMac`), depende de `CleanMyMacCore` | App/UI/orquestração: amostragem do disco e reação a limiares (`StorageMonitor.swift`), varredura e disposição segura de artefatos via `Process` (`SafeCleaner.swift`), interface SwiftUI da barra de menus e preferências (`MenuBarView.swift`, `PreferencesView.swift`), entrada da app e injeção do `StorageMonitor` (`CleanMyMacApp.swift`). |
| `CleanMyMacCoreTests` | Test target (`Tests/CleanMyMacCoreTests`), depende de `CleanMyMacCore` e `CleanMyMac` | Testes com Swift Testing (`@Test`, `#expect`) sobre os dois módulos acima. |

Fluxo principal: `StorageMonitor` amostra o disco a cada 30s (5s sob pressão), aplica `StoragePolicy` para decidir alertar ou limpar, e quando aciona a limpeza chama `SafeCleaner.run()`. Internamente, `SafeCleaner` usa `DisposalSession` (privado ao arquivo) para mover/copiar/apagar cada artefato conforme o `CleanupDestination` escolhido pelo usuário, delegando a `BackupVerifier` a verificação byte-a-byte quando o destino é backup externo.

**Regra de fronteira:** `CleanMyMacCore` não importa `AppKit`/`SwiftUI` nem dispara processos externos — só regras determinísticas e I/O de arquivo (hash, comparação de árvore). Qualquer código que rode `Process`, abra `NSOpenPanel` ou publique estado para a UI pertence a `CleanMyMac`.

## Modelo de segurança

Todo comando externo em `SafeCleaner.runCommand` recebe `executable` e `arguments` como um array Swift — nunca como string interpolada em shell — o que elimina injeção de comando pela composição de argumentos (caminhos com espaços, aspas ou `;` não escapam para o shell). O único ponto do arquivo onde um caminho é interpolado dentro de uma string executável é `DisposalSession.deleteExactTrashBatch` (`Sources/CleanMyMac/SafeCleaner.swift`), que monta um script AppleScript para mover um lote exato para a Lixeira via `osascript`; o caminho é escapado (`\` e `"` substituídos por `\\` e `\"`) antes da interpolação.

## Privacidade

Ver a seção "Privacidade" do `README.md`: o app não tem cliente de rede, conta, analytics de terceiros ou backend remoto — todas as amostras de armazenamento, preferências e logs permanecem no Mac.
```

- [ ] **Step 2: Conferir contra a fonte**

Rodar:

```bash
for f in StoragePolicy.swift BackupVerifier.swift CleanupDestination.swift CleanupPolicy.swift \
         StorageMonitor.swift SafeCleaner.swift MenuBarView.swift PreferencesView.swift CleanMyMacApp.swift; do
  find Sources -name "$f" | grep -q . || { echo "MISSING: $f"; exit 1; }
done
echo "all files verified"
```

Expected: imprime `all files verified` e sai com código 0 — todo nome de arquivo citado em `docs/ARCHITECTURE.md` existe de fato em `Sources/`, sem nome inventado.

- [ ] **Step 3: Commit**

```bash
git add docs/ARCHITECTURE.md
git commit -m "docs: document module boundaries and security model in ARCHITECTURE.md"
```

---

### Task 2: Logar falhas de `find`/`du` em vez de descartar candidatos em silêncio

**Files:**
- Modify: `Sources/CleanMyMac/SafeCleaner.swift:64-66` (depois de `record`, adicionar `scanFailureLogMessage`)
- Modify: `Sources/CleanMyMac/SafeCleaner.swift:169-178` (chamada de `du` dentro de `cleanGeneratedArtifacts`)
- Modify: `Sources/CleanMyMac/SafeCleaner.swift:239-265` (`artifactCandidates`)
- Modify: `Sources/CleanMyMac/SafeCleaner.swift:267-289` (`enumerateArtifacts`)
- Test: `Tests/CleanMyMacCoreTests/StoragePolicyTests.swift` (append no final do arquivo, linha 303 — o projeto usa um único arquivo de teste para `CleanMyMacCore` e `CleanMyMac`; `nativeCacheCommandStopsAtTimeout`/`commandRunnerCapturesOutput`, já no fim desse arquivo, testam `SafeCleaner.runCommand` do mesmo jeito, então os novos testes seguem o padrão existente em vez de criar um arquivo novo)

**Interfaces:**
- Consumes: nada da Task 1 (independe do documento; parte apenas do código já existente em `SafeCleaner.swift`)
- Produces: `SafeCleaner.scanFailureLogMessage(operation: String, path: String, result: CommandResult) -> String?` — retorna `nil` quando `result.code == 0`, senão `"ERROR \(operation): \(path) \(result.output)"`. Não-privado (acessível via `@testable import CleanMyMac`).

**Nota de escopo do teste:** `find`/`du` reais rodam via `Process` contra caminhos do disco do usuário; forçar uma falha real de forma determinística exigiria manipular permissões de arquivos reais, o que a regra de segurança do projeto proíbe em testes automatizados. O teste cobre a lógica de decisão (`scanFailureLogMessage`) de forma isolada — que é exatamente o trecho que hoje não existe e causa o descarte silencioso — e cada um dos dois call-sites vira uma chamada de uma linha para essa função já testada, sem lógica condicional própria para testar separadamente.

- [ ] **Step 1: Ler o arquivo antes de editar**

Ler `Sources/CleanMyMac/SafeCleaner.swift` (já lido nesta sessão; reconfirmar linhas 64-66, 169-178, 239-289 antes de editar, pois é exatamente o que os steps seguintes tocam).

- [ ] **Step 2: Grep pelo mesmo padrão de descarte silencioso em todo o projeto**

```bash
grep -rn "runCommand(\|\.code == 0" --include="*.swift" Sources/ Tests/ | grep -v "Sources/CleanMyMac/SafeCleaner.swift"
grep -n "\.code == 0" Sources/CleanMyMac/SafeCleaner.swift
```

Expected: o primeiro comando não retorna nenhum uso de `runCommand`/`.code == 0` fora de `SafeCleaner.swift` em código de produção (só há usos em `StoragePolicyTests.swift`, que são chamadas de teste, não candidatos ao fix) — confirma que o padrão está confinado a esse arquivo. O segundo comando lista as 7 ocorrências dentro dele: linhas 153, 170, 195, 284, 431, 505, 513. Das sete, quatro já logam a falha antes de retornar/continuar (153 `SKIP alvo não ignorado pelo Git`, 195 `BLOCK Git indisponível`, 431 `ERROR lote mantido`, e as duas chamadas de `activeWorkingDirectories()` em 505/513 já são logadas pelos call-sites em `BLOCK inspeção de processos indisponível` / `BLOCK rechecagem de processos indisponível`). Só as linhas 170 (`du`) e 284 (`find`) descartam sem logar — são as duas únicas tocadas neste fix.

- [ ] **Step 3: Escrever o teste que reproduz o bug (falha antes do fix)**

No fim de `Tests/CleanMyMacCoreTests/StoragePolicyTests.swift` (depois de `commandRunnerCapturesOutput`, que termina na linha 303), acrescentar:

```swift

@Test func scanFailureLogMessageReportsCommandFailure() {
    let failure = CommandResult(code: 1, output: "Permission denied")
    let message = SafeCleaner.scanFailureLogMessage(
        operation: "varredura de artefatos",
        path: "/tmp/example",
        result: failure
    )
    #expect(message == "ERROR varredura de artefatos: /tmp/example Permission denied")
}

@Test func scanFailureLogMessageIsNilOnSuccess() {
    let success = CommandResult(code: 0, output: "")
    #expect(SafeCleaner.scanFailureLogMessage(
        operation: "varredura de artefatos",
        path: "/tmp/example",
        result: success
    ) == nil)
}
```

- [ ] **Step 4: Rodar o teste e confirmar que falha**

Run: `swift test --filter scanFailureLogMessage`
Expected: FAIL — erro de compilação `type 'SafeCleaner' has no member 'scanFailureLogMessage'` (a função ainda não existe).

- [ ] **Step 5: Adicionar a função pura de log**

Em `Sources/CleanMyMac/SafeCleaner.swift`, logo depois de:

```swift
    static func record(_ message: String) {
        CleanupLog(url: logURL).append(message)
    }
```

adicionar:

```swift

    static func scanFailureLogMessage(operation: String, path: String, result: CommandResult) -> String? {
        guard result.code != 0 else { return nil }
        return "ERROR \(operation): \(path) \(result.output)"
    }
```

- [ ] **Step 6: Rodar o teste e confirmar que passa**

Run: `swift test --filter scanFailureLogMessage`
Expected: PASS (2 testes).

- [ ] **Step 7: Ligar a função no ponto de falha do `du`**

Em `cleanGeneratedArtifacts`, substituir:

```swift
            let sizeResult = runCommand("/usr/bin/du", ["-sk", target.path])
            guard sizeResult.code == 0,
                  let first = sizeResult.output.split(whereSeparator: { $0.isWhitespace }).first,
                  let sizeKiB = Int(first),
                  CleanupPolicy.isEligibleArtifact(
                      name: target.lastPathComponent,
                      sizeKiB: sizeKiB,
                      isSymbolicLink: false,
                      minimumKiB: minimumArtifactKiB
                  ) else { continue }
```

por:

```swift
            let sizeResult = runCommand("/usr/bin/du", ["-sk", target.path])
            if let message = scanFailureLogMessage(operation: "medição de tamanho", path: target.path, result: sizeResult) {
                log.append(message)
            }
            guard sizeResult.code == 0,
                  let first = sizeResult.output.split(whereSeparator: { $0.isWhitespace }).first,
                  let sizeKiB = Int(first),
                  CleanupPolicy.isEligibleArtifact(
                      name: target.lastPathComponent,
                      sizeKiB: sizeKiB,
                      isSymbolicLink: false,
                      minimumKiB: minimumArtifactKiB
                  ) else { continue }
```

- [ ] **Step 8: Ligar a função no ponto de falha do `find`, roteando o log através de `artifactCandidates`**

Em `enumerateArtifacts`, substituir a assinatura e o guard do `find`:

```swift
    private static func enumerateArtifacts(in root: URL) -> [URL] {
```

por:

```swift
    private static func enumerateArtifacts(in root: URL, log: CleanupLog) -> [URL] {
```

e substituir:

```swift
        let result = runCommand("/usr/bin/find", arguments)
        guard result.code == 0 else { return [] }
```

por:

```swift
        let result = runCommand("/usr/bin/find", arguments)
        if let message = scanFailureLogMessage(operation: "varredura de artefatos", path: root.path, result: result) {
            log.append(message)
        }
        guard result.code == 0 else { return [] }
```

Em `artifactCandidates`, substituir a assinatura e a última linha:

```swift
    private static func artifactCandidates() -> [URL] {
```

por:

```swift
    private static func artifactCandidates(log: CleanupLog) -> [URL] {
```

e substituir:

```swift
        var seen = Set<String>()
        return roots.flatMap(enumerateArtifacts).filter { seen.insert($0.path).inserted }
```

por:

```swift
        var seen = Set<String>()
        return roots.flatMap { enumerateArtifacts(in: $0, log: log) }.filter { seen.insert($0.path).inserted }
```

Em `cleanGeneratedArtifacts`, substituir:

```swift
        let candidates = artifactCandidates()
```

por:

```swift
        let candidates = artifactCandidates(log: log)
```

- [ ] **Step 9: Build e teste completos**

Run: `swift build && swift test`
Expected: build sem erros; todos os testes (incluindo os 2 novos e os já existentes em `StoragePolicyTests.swift`) passam.

- [ ] **Step 10: Preflight canônico**

Run: `./Scripts/preflight.sh`
Expected: exit code 0, sem etapa pulada (`test-preflight-parity.sh`, lint do `Info.plist`, testes web, E2E, `swift test`, build de produção, verificação de release pública, verificação de assinatura).

- [ ] **Step 11: Commit fix + teste juntos**

```bash
git add Sources/CleanMyMac/SafeCleaner.swift Tests/CleanMyMacCoreTests/StoragePolicyTests.swift
git commit -m "fix: log find/du scan failures instead of discarding silently"
```

---

## Verificação final da Fase 0

- [ ] `docs/ARCHITECTURE.md` existe e reflete a separação real dos módulos (critério d do usuário).
- [ ] Falha de `find`/`du` gera linha `ERROR` no log com o motivo (critério a).
- [ ] Teste de regressão cobrindo esse caminho passa (critério b).
- [ ] `./Scripts/preflight.sh` 100% verde (critério c).
- [ ] Nenhum código fora do escopo foi tocado (`"Arquivos Públicos"` duplicado permanece intocado).
