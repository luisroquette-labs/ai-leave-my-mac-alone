#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

app="${1:-dist/AI, Leave My Mac Alone!.app}"
profile="${AILMMA_NOTARY_PROFILE:-}"
version="$(tr -d '[:space:]' < VERSION)"
release_dir="release"
archive="$release_dir/AI-Leave-My-Mac-Alone-$version.zip"
stable_archive="$release_dir/AI-Leave-My-Mac-Alone.zip"

[[ -d "$app" && -x "$app/Contents/MacOS/CleanMyMac" ]] || {
    print -u2 "Usage: AILMMA_NOTARY_PROFILE=<keychain-profile> $0 [app-path]"
    exit 2
}
[[ -n "$profile" ]] || {
    print -u2 "NOT READY: set AILMMA_NOTARY_PROFILE to an existing notarytool Keychain profile."
    exit 2
}
[[ ! -e "$archive" ]] || {
    print -u2 "NOT READY: $archive already exists; move it before notarizing again."
    exit 2
}

authority=$(codesign -dv --verbose=4 "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)
[[ "$authority" == "Developer ID Application:"* ]] || {
    print -u2 "NOT READY: app must be signed with Developer ID Application; found ${authority:-none}."
    exit 1
}
codesign --verify --deep --strict --verbose=2 "$app"
signature_details=$(codesign -d --verbose=4 "$app" 2>&1)
print -r -- "$signature_details" | grep -q '^Identifier=com.luisroquette.clean-my-mac$' || {
    print -u2 "NOT READY: bundle identifier must stay com.luisroquette.clean-my-mac."
    exit 1
}
print -r -- "$signature_details" | grep -q 'flags=.*runtime' || {
    print -u2 "NOT READY: hardened runtime is missing."
    exit 1
}
app_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$app_version" == "$version" ]] || {
    print -u2 "NOT READY: app version $app_version does not match VERSION $version."
    exit 1
}

notary_dir=$(mktemp -d -t ailmma-notary)
trap '[[ -d "$notary_dir" ]] && rm -r -- "$notary_dir"' EXIT
submission="$notary_dir/AI-Leave-My-Mac-Alone-notarize.zip"
notary_result="$notary_dir/notary-result.json"
ditto -c -k --keepParent "$app" "$submission"

xcrun notarytool submit "$submission" --keychain-profile "$profile" --wait \
    --output-format json > "$notary_result"
notary_status=$(/usr/bin/plutil -extract status raw -o - "$notary_result" 2>/dev/null || true)
[[ "$notary_status" == "Accepted" ]] || {
    submission_id=$(/usr/bin/plutil -extract id raw -o - "$notary_result" 2>/dev/null || true)
    print -u2 "FAIL: Apple notarization returned ${notary_status:-no status} (submission ${submission_id:-unknown})."
    [[ -z "$submission_id" ]] || xcrun notarytool log "$submission_id" --keychain-profile "$profile" >&2 || true
    exit 1
}

xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

mkdir -p "$release_dir"
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
cp "$archive" "$stable_archive"
(cd "$release_dir" && shasum -a 256 "${archive:t}" > "${archive:t}.sha256")
print "PASS: Developer ID signature, notarization, staple, and Gatekeeper assessment validated."
print "Release asset: $archive"
