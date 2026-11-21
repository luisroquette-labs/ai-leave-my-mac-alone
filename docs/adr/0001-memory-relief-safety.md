# Memory relief targets and thresholds

## Context

On 11 September 2026, two abandoned Next.js builds used about 10 GB of memory, left roughly 19 MB free, and pushed swap to 95% of 20 GB. A later incident showed that swap can make a culprit's resident memory look small; a 1 GB RSS threshold missed old `next-server` processes. A Colima VM can also use several gigabytes while its own Docker context has no containers.

## Decision

The app limits process relief to known build and telemetry patterns. It treats an old process adopted by launchd (PPID 1) as abandoned, preserves young or parented builds and explicit `neverKill` targets, and always preserves unknown processes. It stops Colima gracefully only after checking the Colima Docker context and proving its container list empty. Missing process age or a failed context check preserves the process or VM.

## Consequences

The app can leave some memory in use when evidence is incomplete. This favors active work over aggressive relief. The target policy lives in the Core module so tests can exercise the actual decision without terminating processes.
