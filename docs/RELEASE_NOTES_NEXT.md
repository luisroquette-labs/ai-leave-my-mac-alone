# AI, Leave My Mac Alone! — next release (not published)

Suggested version: **2.4.0**. This file is the draft. Do not create a GitHub release, do not push a `v*` tag, and do not bump `VERSION` until the Developer ID build in [SIGNING.md](SIGNING.md) is stapled and the screenshots below exist.

The source tree still reports **2.3.1**. The ZIP on the current GitHub release is that build: Portuguese UI, ad-hoc signature. Product Hunt should wait until the download is this next build.

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

1. Bump `VERSION`, `Resources/Info.plist` (`CFBundleShortVersionString` and `CFBundleVersion`), `ChromeExtension/manifest.json`, the README badge, and `softwareVersion` / `vX.Y.Z · Apple silicon` on the website together.
2. Sign and staple using `docs/SIGNING.md`.
3. Replace the assets listed in `branding/needs-regeneration/README.md`.
4. Capture the English menu-bar screens listed in that same file.
5. Only then tag. Tagging `v*` runs `.github/workflows/release.yml`, which publishes a release. That workflow still ad-hoc signs. For Product Hunt, ship the stapled zip, not the ad-hoc artifact from the tag workflow, unless the workflow is updated first.
