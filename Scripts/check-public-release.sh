#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

required=(README.md LICENSE SECURITY.md VERSION docs/index.html docs/styles.css docs/polish.css docs/script.js docs/img/app-popover-current.png docs/img/og-card.png docs/video/clean-my-mac-demo.mp4)
for path in "${required[@]}"; do
    [[ -f "$path" ]] || { print -u2 "Missing public file: $path"; exit 1; }
done
[[ -s docs/video/clean-my-mac-demo.mp4 ]] || { print -u2 "Demo video is empty"; exit 1; }

if command -v rg >/dev/null 2>&1; then
    if rg -n -g '!check-public-release.sh' '/Users/luisroquette/' Sources Scripts Resources Tests Package.swift; then
        print -u2 "Absolute user path found in public source"
        exit 1
    fi
elif /usr/bin/grep -R -n '/Users/luisroquette/' Sources Resources Tests Package.swift Scripts/make-app.sh Scripts/preflight.sh Scripts/package-release.sh; then
    print -u2 "Absolute user path found in public source"
    exit 1
fi

[[ "$(<VERSION)" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)" ]] || {
    print -u2 "VERSION and Info.plist disagree"
    exit 1
}

version="$(<VERSION)"
/usr/bin/grep -Fq "\"version\": \"$version\"" ChromeExtension/manifest.json || {
    print -u2 "Chrome extension version is stale"
    exit 1
}
/usr/bin/grep -Fq "v$version" README.md || { print -u2 "README version is stale"; exit 1; }
/usr/bin/grep -Fq "\"softwareVersion\":\"$version\"" docs/index.html || {
    print -u2 "Landing page version is stale"
    exit 1
}
/usr/bin/grep -Fq "v$version · Apple silicon" docs/index.html || {
    print -u2 "Landing page download version is stale"
    exit 1
}
