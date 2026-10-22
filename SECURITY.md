# Security

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository. Do not
open a public issue with exploit details or personal filesystem paths.

## Safety boundary

AI, Leave My Mac Alone! removes supported package-manager caches and generated
artifacts only after path, Git and process checks. The optional Emergency level,
when explicitly selected or authorized for automation, additionally permits
Codex archive files older than seven days and Claude VM bundles with no open files.

It never uploads data, empties the existing Trash, removes source files, current
agent sessions, credentials, personal media, active projects, or Docker data.
Every protected-folder exception is an exact allowlisted subtree and remains
fail-closed when process inspection or path validation is inconclusive.
