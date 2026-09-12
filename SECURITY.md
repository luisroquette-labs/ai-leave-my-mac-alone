# Security

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting for this repository. Do not
open a public issue with exploit details or personal filesystem paths.

## Safety boundary

AI, Leave My Mac Alone! only removes supported package-manager caches and generated
`node_modules`/`.next` directories that are at least 100 MB, inside a Git
repository, ignored by Git, outside protected personal folders, and not part of
an active development process.

It never uploads data, empties Trash, scans protected personal folders, removes
source files, or deletes Docker data.
