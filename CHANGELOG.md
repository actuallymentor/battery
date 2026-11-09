# Changelog

## 2.0.0-beta (unreleased)

Native Swift rewrite. v1 (Electron + shell) moved to `legacy/`.

**New**
- SwiftUI menu bar app: limit toggle, presets and custom limits (#462), resume-below, menu bar % (#470) and icon choice, launch at login (#425), low-battery alert, scheduled top-off, battery health and cycles.
- Root helper via `SMAppService` + XPC: no sudoers, no password prompts, applies the limit at boot.
- Charge-control backend chosen by SMC key probing: `CHTE`, `CH0B/CH0C`, firmware limit `bfD0/bfE0/bfF0` (#480, #469 groundwork), adapter-cut compat mode. Writes are verified; the app warns when the Mac ignores the limit.
- Opt-in Sparkle 2 updates (#412, #347). No telemetry (#188).
- First launch offers to remove v1.

**Fixed**
- Uninstall (Settings or `battery uninstall`) also removes helper state, the log and app preferences, not just the helper.
- A helper that stops answering while a limit is on now says charging may stay paused; Repair falls back to Login Items guidance; an outdated helper (after an update) is restarted automatically.
- Range maintain: plugged in inside the band no longer charges to the top (#475).
- Manual `charging on/off` stops the maintain loop instead of fighting it (#460, #440).
- Sleep: adapter cut is restored before sleep; limit re-evaluated on wake and on plug/unplug (#442, #356).
- Percentages and amperage from IOKit, not `pmset` text (#250, #461).
- CLI never hangs when the helper is missing.

**CLI**: `visudo` and `update_silent` removed. Added `schedule`. `update` / `reinstall` now point to the app. `status` is rendered by the CLI from one daemon snapshot.

**Safety**: the helper refuses `discharge` below 5%, `maintain` below 10% and out-of-range schedules whatever the client sends. Adapter is restored before sleep and at boot; a job replaced by a new target hands the adapter back.

**Release**: `CFBundleVersion` grows per CI run (Sparkle), appcast generated, signing identifiers asserted, tests gate the release.
