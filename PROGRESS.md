# PROGRESS: Swift port (v2), branch `v2/swift` (local, UNPUSHED)

Updated 2026-11-09. Read with `AGENTS.md`, `.notes/` (TRIAGE.md, RESEARCH.md, HUMAN.md) and `scripts/dev/README.md`.

## Rules
- No push (git/gh) until the user says so. No `Co-Authored-By`. Commits local, gitmoji.

## State: feature-complete beta, verified on a real Mac (MacBook Air, arm64, macOS 26.1)
- `macos/`: BatteryCore (71 tests, `swift test`), App (SwiftUI popover, tabbed Settings, menubar % / icon styles), Daemon (root helper: ChargeControl, Maintainer, Jobs, Scheduler, PowerEvents, Legacy cleanup), CLI (thin XPC), Shared.
- Verified E2E on hardware: SMAppService approval + Repair flow, popover/limit toggle driving the daemon, maintain / force-discharge / charge / discharge / calibrate start / recover, persistence across daemon restart, scheduler, v1 cleanup (real removal of fake v1 footprint), CLI link `/usr/local/bin/battery` from Settings, Sparkle embedded, release `scripts/release/build.sh` (version from tag, hardened runtime, no get-task-allow).
- Triage (`.notes/TRIAGE.md`): ladder by key probing implemented: CHTE, CH0B/CH0C, bfD0/bfE0/bfF0 firmware limit, CHIE adapter-cut compat. Range hysteresis (#475), manual override stops maintain (#460/#440), sleep/wake/plug reconcile, effect verification warning, health/cycles, low-battery alert, scheduled top-off, opt-in updates, no telemetry, safe uninstall.

## NOT verified on hardware (no such Mac available)
- bf* firmware backend and CHIE software-cut backend: only unit-tested with fixtures from issue reports.
- Legacy CH0B/CH0C, macOS 15.8.x / 27 behaviour.
- A full `discharge`/`calibrate` run to completion (hours); sleep/lid/clamshell behaviour; maintain across a real reboot.
- Release signing/notarization/Sparkle signing (needs CI secrets + a tag; user must allow push).
- macOS 27 PowerUI native limit backend (#480): not implemented (private API, untestable here).

## Dev workflow on the Mac (ArjunMacbook)
- See `scripts/dev/README.md` (rebuild, install to /Applications, dev daemon). Copy those scripts to the Mac's /tmp.
- Rebuilding changes the ad-hoc signature: the SMAppService job then fails (EX_CONFIG). "Repair helper" in the app fixes it (works while the Login Items toggle is on), or use `scripts/dev/mac-dev-daemon.sh load|unload` while iterating.
- GUI: Mac re-locks after each `babysit mac run` session; do everything in one chain (see RESEARCH.md).

## Open for the user (see .notes/HUMAN.md)
Appcast hosting (SUFeedURL is a placeholder: GitHub release asset), Homebrew cask owner, when to push / first beta tag, PowerUI backend, multi-Mac testers (15.8.x, 26.7, 27).

## Prefactor pass (2026-11-09)
Done: input limits enforced in the daemon, single main-queue owner, suspend/abort semantics between maintain and jobs, one adapter-cut flag, force-discharge no-flap, boot-safe adapter restore, LED wired (skipped without ACLC), status rendered CLI-side, pure `JobPlanner`/`Schedule`/`LimitSettings`/`Limits` + 24 new tests, app actions serialized + daemon-truth adoption, CI workflow, release test gate, signing identifier assertions, Sparkle build number + appcast, identity drift guard.
Deliberately NOT done: typed XPC request enum (large rewrite, no CI to catch regressions yet), xcconfig single identity source (guard script instead).
