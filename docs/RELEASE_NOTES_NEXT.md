# AI, Leave My Mac Alone! — next release (not published)

Version: **2.4.0**. This file is the draft. Do not create a GitHub release or push a `v*` tag until the Developer ID build in [SIGNING.md](SIGNING.md) is stapled and the screenshots below exist.

`VERSION`, `Info.plist` (build 26), and the Chrome extension manifest report **2.4.0** so the signed build carries the right version. The README badge and the website still say **2.3.1** until the stapled 2.4.0 zip is published. The ZIP on the current GitHub release is that build: Portuguese UI, ad-hoc signature. Product Hunt should wait until the download is this next build.

## Suggested title

AI, Leave My Mac Alone! 2.4.0

## Suggested GitHub About description

Replace the current About text. It says the app warns at 90% and cleans at 95%. The code does not.

```text
Native macOS menu-bar SSD guard for people building with AI. Warns at 75% disk, cleans regenerable developer artifacts at 78%, and keeps trying to get back under the 80% ceiling. Local-first and open source.
```

## Notes

- English is the default language in the menu bar, Settings, notifications, and on the website. Portuguese is used when it is ahead of English in the Mac language list, or when the site language control is set to PT.
- Public pages and the README no longer present the previous product name. The bundle identifier, the log directory, and the Swift module names are unchanged, so Login Items and notification permission already granted stay valid.
- Docs now match the disk policy in `StoragePolicy`: warning at 75%, automatic cleanup at 78%, ceiling at 80%. Swap relief is separate (warning at 75% swap, action when free RAM is under 300 MB and swap is at 90% or higher). `emergencyThreshold` (95%) is still unused by the running app. Cleanup behavior was not changed.
- `./Scripts/report-freed.sh` totals the free space recorded in the local cleanup log.
- Signing and notarization steps for Developer ID, `notarytool`, and `stapler` are in `docs/SIGNING.md`.

## Before you tag 2.4.0

1. When the stapled zip is published, bump the README badge and `softwareVersion` / `vX.Y.Z · Apple silicon` on the website (and `Scripts/test-web-demo.mjs`). `VERSION`, `Info.plist`, and the extension manifest are already 2.4.0.
2. Sign and staple with the scripted path in `docs/SIGNING.md` (`make-app.sh` with `AILMMA_SIGN_IDENTITY`, then `notarize-app.sh`).
3. Replace the assets listed in `branding/needs-regeneration/README.md`.
4. Capture the English menu-bar screens listed in that same file.
5. Only then tag. Tagging `v*` runs `.github/workflows/release.yml`, which publishes a release. That workflow still ad-hoc signs. For Product Hunt, ship the stapled zip, not the ad-hoc artifact from the tag workflow, unless the workflow is updated first.
