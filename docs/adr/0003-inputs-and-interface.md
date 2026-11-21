# Input handling and interface choices

## Context

Filesystem paths and command output can contain newlines or tabs, which would split log records. Failure output can also be large. The menu bar interface has limited space and needs visible thresholds and status. The Chrome extension must choose a tab without interrupting the active one.

## Decision

The cleaner replaces control characters before logging, caps collapsed failure output, and treats an unparseable leading `du -sk` field as a parsing failure rather than a small artifact. The interface uses a compact instrument-panel palette, separates the numeric magnitude from its unit, and places threshold marks above a neutral track. When a tab ID is absent, the extension lets Chrome choose a less important tab so the active tab stays in place.

## Consequences

Logs remain single-record and bounded. The interface exposes policy thresholds without hiding marks in the filled bar. Extension fallback avoids displacing the user's active tab.
