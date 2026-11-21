# Sign and notarize AI, Leave My Mac Alone!

Run these commands on the Mac that owns the Developer ID certificate. The GitHub Actions build stays ad-hoc (`codesign --sign -`). Notarization replaces that signature; it does not change cleanup behavior.

Use a **Developer ID Application** certificate. A Mac App Store, Apple Development, or Apple Distribution certificate will not notarize a direct download.

Leave `CFBundleIdentifier` as `com.luisroquette.clean-my-mac`. Changing it drops Login Items, notifications, and other macOS permissions already granted. The executable file inside the bundle is `Contents/MacOS/CleanMyMac`. The name in the menu bar and Finder is **AI, Leave My Mac Alone!**

## Scripted path

```bash
cd /path/to/ai-leave-my-mac-alone
AILMMA_SIGN_IDENTITY="Developer ID Application: luis roquette (S3YCFYY8SC)" ./Scripts/make-app.sh
./Scripts/preflight.sh
AILMMA_NOTARY_PROFILE="notchagent-notary" ./Scripts/notarize-app.sh
```

`make-app.sh` signs the executable and the bundle with the hardened runtime and a secure timestamp when `AILMMA_SIGN_IDENTITY` is set. Without it the build stays ad-hoc, which is what CI and the tag workflow use. `notarize-app.sh` checks the Developer ID authority, the bundle identifier, the hardened runtime, and that `Info.plist` matches `VERSION`, then submits a zip with `notarytool`, staples, runs `stapler validate` and `spctl`, and writes `release/AI-Leave-My-Mac-Alone-<version>.zip`, the stable `AI-Leave-My-Mac-Alone.zip`, and the `.sha256`. Any existing `notarytool` Keychain profile for team S3YCFYY8SC works. If the Keychain holds more than one certificate with the same Developer ID name, `codesign` reports the name as ambiguous; pass the 40-character SHA-1 hash from `security find-identity -v -p codesigning` as `AILMMA_SIGN_IDENTITY` instead.

The manual steps below do the same thing by hand.

## 1. Find the certificate

```bash
security find-identity -v -p codesigning
```

Copy the identity whose prefix is `Developer ID Application:`. Example shape, with your own name and team id:

```text
Developer ID Application: Luis Roquette (TEAMID)
```

## 2. Store notary credentials once

Create an app-specific password at [appleid.apple.com](https://appleid.apple.com) under Sign-In and Security. Do not use the Apple ID password.

```bash
xcrun notarytool store-credentials "leave-my-mac-alone-notary" \
  --apple-id "YOU@EMAIL" \
  --team-id "TEAMID" \
  --password "APP_SPECIFIC_PASSWORD"
```

## 3. Build, then replace the ad-hoc signature

```bash
cd /path/to/ai-leave-my-mac-alone
./Scripts/preflight.sh

APP="dist/AI, Leave My Mac Alone!.app"
IDENTITY="Developer ID Application: Luis Roquette (TEAMID)"

codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/MacOS/CleanMyMac"
codesign --force --options runtime --timestamp --sign "$IDENTITY" --deep "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
```

`--options runtime` is the hardened runtime. `--timestamp` needs a network connection. Both are required for notarization. The app is not sandboxed and does not need an entitlements file for the current binary.

## 4. Submit and wait

```bash
mkdir -p release
ditto -c -k --keepParent "$APP" "release/AI-Leave-My-Mac-Alone-notarize.zip"

xcrun notarytool submit "release/AI-Leave-My-Mac-Alone-notarize.zip" \
  --keychain-profile "leave-my-mac-alone-notary" \
  --wait
```

If the submission is rejected, copy the submission id from the output and read the log:

```bash
xcrun notarytool log "SUBMISSION_ID" \
  --keychain-profile "leave-my-mac-alone-notary"
```

Fix the reported issue and repeat from the codesign step. Do not add entitlements until that log asks for one.

## 5. Staple the ticket to the app

```bash
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
```

`spctl` should report that the app is accepted. Gatekeeper then opens it without `xattr -dr com.apple.quarantine`.

## 6. Zip the stapled app for the release

```bash
VERSION="$(cat VERSION)"
ditto -c -k --sequesterRsrc --keepParent "$APP" "release/AI-Leave-My-Mac-Alone-${VERSION}.zip"
cp "release/AI-Leave-My-Mac-Alone-${VERSION}.zip" "release/AI-Leave-My-Mac-Alone.zip"
shasum -a 256 "release/AI-Leave-My-Mac-Alone-${VERSION}.zip" \
  > "release/AI-Leave-My-Mac-Alone-${VERSION}.zip.sha256"
```

Do not tag or run `gh release create` until the English menu-bar screenshots and the new demo video in [RELEASE_NOTES_NEXT.md](RELEASE_NOTES_NEXT.md) are ready. Pushing a `v*` tag publishes a release from GitHub Actions, and that workflow signs ad-hoc again. For a notarized Product Hunt download, attach the stapled zip yourself, or change the release workflow to use the Developer ID identity before tagging.
