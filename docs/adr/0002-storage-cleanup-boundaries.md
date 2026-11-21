# Storage cleanup boundaries

## Context

Earlier cleanup missed inactive worktrees and repeatedly scanned without progress. Other runs removed active worktree dependencies or a shared symlink target. Worktrees under `~/.codex` need special treatment because adjacent configuration, sessions, and credentials must stay protected.

## Decision

Only recognized regenerable artifacts are eligible. A Git worktree is eligible when it is clean and inactive for the configured window; unknown activity counts as in use. An upstream deleted after merge shortens that window. A whole worktree needs a longer idle window and a branch; a target shared through another worktree's symlink is protected. Scanning stops on the hard no-progress limit. Only the worktree subtree under protected agent directories can be considered. Approved artifacts go to a recoverable disposal batch, or a verified external backup precedes removal.

## Consequences

Some stale files remain until the evidence and idle windows are met. The policy prevents cleanup from destroying active work or protected agent data, and prevents emergency mode from repeating unproductive I/O indefinitely.
