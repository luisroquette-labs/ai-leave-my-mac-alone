#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

./Scripts/test-preflight-parity.sh
/usr/bin/plutil -lint Resources/Info.plist
! /usr/bin/grep -Fq '.confirmationDialog(' Sources/CleanMyMac/MenuBarView.swift || {
    print -u2 "Native cleanup confirmation breaks inside MenuBarExtra"
    exit 1
}
/usr/bin/grep -Fq 'Text("Limpeza em andamento…")' Sources/CleanMyMac/MenuBarView.swift || {
    print -u2 "Visible cleanup progress is missing"
    exit 1
}
/usr/bin/grep -Fq 'monitor.cleanNow(deepCleanup: requestedDeepCleanup)' Sources/CleanMyMac/MenuBarView.swift \
    && /usr/bin/grep -Fq 'Button("Limpar agora")' Sources/CleanMyMac/MenuBarView.swift \
    && /usr/bin/grep -Fq 'Button("Limpeza Profunda")' Sources/CleanMyMac/MenuBarView.swift || {
    print -u2 "Independent normal and deep cleanup actions are missing"
    exit 1
}

/usr/bin/perl -0ne 'exit !/hairline\s+if confirmingCleanup && !monitor\.isCleaning \{\s+cleanupConfirmation.*?\}\s+else \{\s+actions\s+\}/s' \
    Sources/CleanMyMac/MenuBarView.swift || {
    print -u2 "Cleanup confirmation must replace the action buttons"
    exit 1
}

/usr/bin/perl -0ne 'exit !/if isFirstSample \|\| reportResult \{\s+lastAction = "Disco verificado:/s' \
    Sources/CleanMyMac/StorageMonitor.swift \
    && /usr/bin/grep -Fq 'sampleNow(reportResult: true)' Sources/CleanMyMac/MenuBarView.swift || {
    print -u2 "Routine sampling must not overwrite the last cleanup result"
    exit 1
}

! /usr/bin/grep -Fq '["cache", "npx", "rm"]' Sources/CleanMyMac/SafeCleaner.swift \
    && /usr/bin/grep -Fq '["store", "prune"], bunWorkingDirectory' Sources/CleanMyMac/SafeCleaner.swift \
    && /usr/bin/grep -Fq 'arguments == ["store", "prune"]' Sources/CleanMyMac/SafeCleaner.swift || {
    print -u2 "Native cache cleanup contains a known-invalid command or unsafe pnpm working directory"
    exit 1
}

/usr/bin/grep -Fq 'includeNativeCaches: !isAutomatic,' Sources/CleanMyMac/StorageMonitor.swift || {
    print -u2 "Automatic cleanup must reserve native cache pruning for the hard-limit escalation"
    exit 1
}

/usr/bin/grep -Fq '["-Ao", "pid,ppid,rss,etime,command"]' Sources/CleanMyMac/MemoryReliever.swift \
    && /usr/bin/grep -Fq 'guard parentPID == 1,' Sources/CleanMyMacCore/MemoryPolicy.swift \
    && [[ $(/usr/bin/grep -Fc 'processIdentityMatches(pid: pid, parentPID: parentPID, command: command)' Sources/CleanMyMac/MemoryReliever.swift) -eq 2 ]] || {
    print -u2 "Memory relief must never infer an orphan from RSS alone"
    exit 1
}

/usr/bin/grep -Fq 'if destructivePipelineReady, deepCleanupEnabled, destination == .deleteBatch,' Sources/CleanMyMac/SafeCleaner.swift \
    && ! /usr/bin/grep -Fq 'RECHECK worktrees' Sources/CleanMyMac/SafeCleaner.swift \
    && /usr/bin/grep -Fq 'private static let aggressiveCacheCleanupKey = "aggressiveCacheCleanupDatesByPath"' Sources/CleanMyMac/SafeCleaner.swift \
    && /usr/bin/grep -Fq 'BLOCK cache de agente em uso' Sources/CleanMyMac/SafeCleaner.swift \
    && /usr/bin/grep -Fq ').filter { !isCorepackShim($0) }' Sources/CleanMyMac/SafeCleaner.swift \
    && /usr/bin/grep -Fq 'worktreeMetadataSearchArguments(containerPath: containerPath)' Sources/CleanMyMac/SafeCleaner.swift \
    && /usr/bin/grep -Fq 'if candidate.stopAfterStaging { break }' Sources/CleanMyMac/SafeCleaner.swift \
    && /usr/bin/grep -Fq 'let openFiles = runCommand("/usr/sbin/lsof", ["+D", path], timeout: 5)' Sources/CleanMyMac/SafeCleaner.swift \
    && /usr/bin/grep -Fq 'DisposalSession.recoverPendingDeleteBatch(log: log)' Sources/CleanMyMac/SafeCleaner.swift \
    && /usr/bin/grep -Fq 'ERROR leitura inicial do disco; limpeza bloqueada' Sources/CleanMyMac/SafeCleaner.swift \
    && [[ $(/usr/bin/grep -Fc 'CleanupPolicy.reachedCleanupTarget(bytesRequired: bytesRequired, stagedBytes: stagedBytes)' Sources/CleanMyMac/SafeCleaner.swift) -eq 3 ]] \
    && /usr/bin/perl -0ne 'exit !/private static func gitRoot.*?"rev-parse", "--show-toplevel"\],\s+timeout: 5/s' Sources/CleanMyMac/SafeCleaner.swift || {
    print -u2 "Closed-loop cleanup safety guards are missing"
    exit 1
}

[[ $(/usr/bin/grep -Fc '["--no-optional-locks", "-C", gitRoot.path, "status"' Sources/CleanMyMac/SafeCleaner.swift) -eq 2 ]] || {
    print -u2 "Cleanup verification must not refresh Git indexes and mark its own worktree active"
    exit 1
}
/usr/bin/env node Scripts/test-web-demo.mjs
/usr/bin/env node Scripts/test-chrome-extension.mjs
/usr/bin/env python3 Scripts/test-web-demo-e2e.py
swift test
./Scripts/make-app.sh
./Scripts/check-public-release.sh
/usr/bin/codesign --verify --deep --strict "dist/AI, Leave My Mac Alone!.app"
[[ -f "dist/AI, Leave My Mac Alone!.app/Contents/Resources/ChromeExtension/manifest.json" ]] || {
    print -u2 "Chrome extension is missing from app bundle"
    exit 1
}
