# Changelog

## Unreleased

### Changed
- First launch opens a setup window ("One-time setup required" → **Open Login Items**) instead of waiting for a click on the menu bar icon. It also opens when approval is switched off later, and says "All set" once the helper runs.

### Fixed
- Settings → Helper → "Use `battery` in Terminal" flips on the click and is locked until done. Before, it lagged a few seconds and looked broken, inviting repeat clicks.
- Raising the limit while charging is held now charges up to the new limit. Before, a battery inside the new 5% band stayed held (82% held at 80, raised to 85: no charging).

## 2.0.0-beta.1 (2026-11-12)

Native Swift rewrite. v1 (Electron + shell) moved to `legacy/`.

**New**
- SwiftUI menu bar app: limit toggle, custom limits (#462), menu bar % (#470) and icon choice, launch at login (#425), low-battery alert, scheduled top-off, battery health and cycles.
- Root helper via `SMAppService` + XPC: no sudoers, no password prompts, applies the limit at boot.
- Charge-control backend chosen by SMC key probing: `CHTE`, `CH0B/CH0C`, firmware limit `bfD0/bfE0/bfF0` (#480, #469 groundwork), adapter-cut compat mode. Writes are verified; the app warns when the Mac ignores the limit.
- Opt-in Sparkle 2 updates (#412, #347). No telemetry (#188).
- First launch offers to remove v1.

**Changed**
- Charge state and time remaining, without cluttering the popover: a status line at the top of the gear menu ("Holding at limit", "On battery · 2:10 left"), the same text as the menu bar tooltip, a pause mark on the menu bar battery while plugged in with charging held off, and *Charging* / *Time remaining* rows in Settings → Charging.
- Menu bar battery fills continuously with the charge level (was five fixed steps, and always full while charging); a bolt is carved into it while charging.
- Dark mode: follows the system theme; Settings → General → Appearance can force Light or Dark.
- The popover is a single line: the charge limit switch and a gear. The limit slider and *Allow discharge* moved to Settings → Charging. *Open at login* and *Allow discharge* are on by default.
- (Earlier in this beta) The popover no longer repeats the charge level, status and voltage (the menu bar icon shows it); it opens straight on the limit controls (no presets, no resume-below stepper: the band is a fixed 5 points, ranges stay on the CLI), the one-off actions, Settings and Quit moved behind a gear at the top right, and it shows the running job's progress when there is one.

**Fixed**
- Charge limit slider: changes made with the keyboard or VoiceOver now apply to the helper (it only applied after a mouse drag was released). A mouse drag still applies only on release, so pausing mid-drag no longer sends the values in between.
- A helper that is approved but not answering (job gone from launchd, dead after the app was replaced) is repaired automatically within ~10 s (at most every 10 minutes), instead of leaving charging unlimited until someone clicks Repair. The app also restarts a helper left over from a different build of the same version (the helper now reports version and build).
- *Allow discharge* never cuts the adapter while the lid is closed: clamshell mode needs it (external displays dropped, or the Mac slept and woke into another cut, #417, #179, #121). Charging stays held off.
- Beta builds don't run the updater: the update feed follows stable releases only, so *Check now* could only fail. Settings links to GitHub Releases instead.
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
