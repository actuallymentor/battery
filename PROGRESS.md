# PROGRESS: Swift port (v2), branch `v2/swift` (local, UNPUSHED)

Updated 2026-11-08 (late). Read with `.HANDOFF.md`, `AGENTS.md`, `.notes/` (esp. TRIAGE.md, RESEARCH.md).

## Rules
- No push (git/gh) until the user says so. No `Co-Authored-By`. Commits local, gitmoji.

## State: feature-complete beta, verified on a real Mac (MacBook Air, arm64, macOS 26.1)
- `macos/`: BatteryCore (47 tests, `swift test`), App (SwiftUI popover, tabbed Settings, menubar % / icon styles), Daemon (root helper: ChargeControl, Maintainer, Jobs, Scheduler, PowerEvents, Legacy cleanup), CLI (thin XPC), Shared.
- Verified E2E on hardware: SMAppService approval + Repair flow, popover/limit toggle driving the daemon, maintain / force-discharge / charge / discharge / calibrate start / recover, persistence across daemon restart, scheduler, v1 cleanup (real removal of fake v1 footprint), CLI link `/usr/local/bin/battery` from Settings, Sparkle embedded, release `scripts/release/build.sh` (version from tag, hardened runtime, no get-task-allow).
- Triage (`.notes/TRIAGE.md`): ladder by key probing implemented: CHTE, CH0B/CH0C, bfD0/bfE0/bfF0 firmware limit, CHIE adapter-cut compat. Range hysteresis (#475), manual override stops maintain (#460/#440), sleep/wake/plug reconcile, effect verification warning, health/cycles, low-battery alert, scheduled top-off, opt-in updates, no telemetry, safe uninstall.

## NOT verified on hardware (no such Mac available)
- bf* firmware backend and CHIE software-cut backend: only unit-tested with fixtures from issue reports.
- Legacy CH0B/CH0C, macOS 15.8.x / 27 behaviour.
- A full `discharge`/`calibrate` run to completion (hours); sleep/lid/clamshell behaviour; maintain across a real reboot.
- Release signing/notarization/Sparkle signing (needs CI secrets + a tag; user must allow push).
- macOS 27 PowerUI native limit backend (#480): not implemented (private API, untestable here).

## Dev workflow on the Mac (ArjunMacbook)
- `tar czf macos.tgz macos scripts` -> scp -> `/tmp/rebuild.sh` (xcodegen + xcodebuild, copies app to ~/Applications). Scripts live in the session scratchpad; recreate from .notes/RESEARCH.md.
- Rebuilding changes the ad-hoc signature: the SMAppService job then fails (EX_CONFIG). Use the app's "Repair helper", or the plain launchctl plist while iterating (`/tmp/devload.sh`, `devunload.sh`).
- GUI: Mac re-locks after each `babysit mac run` session; do everything in one chain (see RESEARCH.md).

## Open for the user (see .notes/HUMAN.md)
Appcast hosting (SUFeedURL is a placeholder: GitHub release asset), Homebrew cask owner, when to push / first beta tag, PowerUI backend, multi-Mac testers (15.8.x, 26.7, 27).
