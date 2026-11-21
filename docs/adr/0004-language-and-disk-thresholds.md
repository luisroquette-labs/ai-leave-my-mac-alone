# Public language and disk thresholds

## Context

The menu, Settings, and website need one public language for a global launch, with Portuguese still available. Older public text described disk warnings at 90% and cleanup at 95%. The running policy uses rounded disk percent for warning, cleanup, and the ceiling. `StoragePolicy.emergencyThreshold` remains 0.95 because a test pins the constant. No production path reads it.

## Decision

English is the default. Portuguese is selected only when a Portuguese language identifier appears before any English identifier in the preferred list. When the app bundle declares both English and Portuguese, that list is the bundle's preferred localizations; otherwise it is the system list. The website starts in English and switches to Portuguese from the language control or `?lang=pt`.

Disk behavior stays: warning at 75%, automatic cleanup at 78%, ceiling at 80%. Swap warning stays at 75%, and memory relief stays at under 300 MB free RAM with swap at 90% or higher. Emergency remains a user-authorized cleanup level. The unused 95% constant is not a disk trigger.

## Consequences

A Mac set to Portuguese still shows Portuguese. Everyone else sees English. Public docs describe 75/78/80 for disk and 75/90 for swap. Removing or rewiring the 95% constant would be a separate change.
