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
Homebrew cask owner, when to push / first beta tag, PowerUI backend, multi-Mac testers (15.8.x, 26.7, 27).
Appcast: stays on GitHub `releases/latest` (decided): updates begin at the first stable release, betas are manual installs.

## Prefactor pass (2026-11-09)
Done: input limits enforced in the daemon, single main-queue owner, suspend/abort semantics between maintain and jobs, one adapter-cut flag, force-discharge no-flap, boot-safe adapter restore, LED wired (skipped without ACLC), status rendered CLI-side, pure `JobPlanner`/`Schedule`/`LimitSettings`/`Limits` + 24 new tests, app actions serialized + daemon-truth adoption, CI workflow, release test gate, signing identifier assertions, Sparkle build number + appcast, identity drift guard.
Deliberately NOT done: typed XPC request enum (large rewrite, no CI to catch regressions yet), xcconfig single identity source (guard script instead).

## Real-Mac test round 2 (2026-11-09)
Verified: CLI fuzz + 12 parallel clients, discharge job to completion (adapter restored, charging resumed), kill -9 daemon recovery (maintain + charging-off restored), `.dmg` layout/deep-verify, app Uninstall (found + fixed leftovers), fresh install after uninstall, Sparkle check/verify/install/relaunch via local appcast (throwaway key), helper-down warning + Repair UI.
Found + fixed: uninstall left state/log/prefs; updates leave the old daemon running; Repair did not recover a booted-out job (now points to Login Items); stale dev tarball trap.
NOT testable here: sleep/wake and reboot (FileVault, sleep blocked), Developer ID update behaviour, signing/notarization. See .notes/GOTCHAS.md.
OPEN RISK: a dead helper with an active limit leaves charging off (verified). Developer ID updates may avoid the dead helper, unverified: do the beta.1 -> beta.2 update test on a clean Mac.

## Signed pipeline + update test (local, Mac)

- Full pipeline run locally on the Mac with the real Developer ID/notary/Sparkle credentials: build, sign, notarize+staple app and dmg, Sparkle sign, appcast. spctl: "Notarized Developer ID".
- Bugs found and fixed: p12 holds only the leaf, so the temp keychain needs the Apple Developer ID G2 + Apple Root CA (sha256-pinned, imported AFTER the p12 or codesign fails with errSecInternalComponent); `grep -q` under pipefail failed the identifier check.
- Signed beta.1 -> beta.2 Sparkle update (local appcast via defaults SUFeedURL override): app swapped, daemon restarted as beta.2, 90% limit resumed, no re-approval. The ad-hoc "dead helper after update" problem does not occur with Developer ID.
- Sleep/wake verified: wake handler fires on full wake, limit holds.
- Reboot verified (FileVault on): the root daemon starts at boot before login, reloads the persisted 90% target and holds charging off.

## E2E suites (2026-11-10)
`macos/E2E` (own SwiftPM package, `scripts/e2e.sh`, README inside). 23 CLI + 19 GUI tests, all green on ArjunMacbook against the signed beta.2 build. No mocks: real helper, SMC, menu bar via Accessibility.
- Mac setup done: Terminal.app has Accessibility. Runs go through Terminal; a held `babysit mac run` session keeps the screen unlocked (`scripts/e2e/hold.sh`).
- Found by the suite: slider changes from keyboard/VoiceOver never reached the helper (fixed, `AppModel.limitChanged`); replacing the app leaves the helper "not answering" until Repair (e2e presses it).
- `babysit mac unlock` types the password into whatever has focus: it landed in a Terminal window once (never executed, Terminal state wiped). hold.sh now unlocks only when the screen is locked.
- Lifecycle suite added (2 tests, `scripts/e2e.sh lifecycle`): uninstall + set up again (no approval needed, macOS remembers it), Login Items switch revoked (password via `babysit mac unlock`, only after the test verifies the focused field) and granted again.
- Not automated: sleep/wake and reboot (need the screen/FileVault login). Mac left with `caffeinate` stopped.
