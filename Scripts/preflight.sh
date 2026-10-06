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
/usr/bin/env node Scripts/test-web-demo.mjs
/usr/bin/env python3 Scripts/test-web-demo-e2e.py
swift test
./Scripts/make-app.sh
./Scripts/check-public-release.sh
/usr/bin/codesign --verify --deep --strict "dist/AI, Leave My Mac Alone!.app"
