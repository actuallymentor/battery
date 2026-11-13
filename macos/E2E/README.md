# E2E suites

Real signed `Battery.app`, real root helper, real SMC, real menu bar. No mocks, no stubs. Needs a MacBook, never runs in CI.

```
scripts/e2e.sh                       build + install fresh (signed), CLI then GUI
scripts/e2e.sh cli | gui             one suite
scripts/e2e.sh all --no-build        test what is installed in /Applications
scripts/e2e.sh lifecycle             helper uninstall/setup/approval revoke+grant (part of `all`)
scripts/e2e.sh gui --filter testSlider
```

- `Tests/E2ETests/CLITests.swift` the shipped `battery` binary against the helper (status, maintain, charging, adapter, jobs, schedule, validation, concurrency)
- `Tests/E2ETests/GUITests.swift` the app through macOS Accessibility (menu bar item, popover, gear menu, Settings tabs), asserted against the helper via the CLI
- `Sources/E2EKit` process runner, CLI wrapper, `AX` (AXUIElement), `GUI` (how a user navigates the app)
- `axdump` debug aid: `axdump menu press:Repair slide:70` prints the live accessibility tree after the steps

## How it runs

The Mac builds and tests itself. `scripts/e2e.sh` (local) is babysit plumbing only: ships `macos/` + `scripts/` to `~/e2e`, copies the signing credentials from `.secrets/` (`.env.release`, `developer-id.p12`, deleted again after the build), holds the screen, answers the lifecycle password request, runs the `sudo launchctl bootout`. On the Mac:

- `scripts/e2e/mac-build.sh` real release pipeline (`build.sh`, `keychain.sh setup --no-notary`, `sign.sh`), replaces `/Applications/Battery.app`, launches it
- `scripts/e2e/mac-run.sh build-tests | cli | gui | lifecycle [filter] | helper-up SECS | repair | quit-app | heal-check | finish` one step each; `gui`/`lifecycle` run inside Terminal.app (the Accessibility grant), output is reduced to `error:` and pass/fail lines
- `scripts/e2e/hold.sh` (local) keeps the screen unlocked while GUI work runs

Tests restore a neutral Mac (no limit, no job, no schedule, charging and adapter on) in `setUp` and `tearDown`. Tests skip themselves on Macs that can't cut the adapter or are too low on charge.

## One-time Mac setup

- Terminal.app needs Accessibility (System Settings -> Privacy & Security -> Accessibility). The GUI suite runs inside Terminal because that is the process holding the grant.
- `babysit mac` registered for the Mac. `MAC=name scripts/e2e.sh` for another one.

## Gotchas

- The uninstall test moves Battery.app to the Trash (that is what the button does). `~/.Trash` is TCC-protected for ssh-spawned processes, so the test copies the installed bundle aside first and reinstalls that copy rather than restoring from the Trash; one trashed copy per run stays until emptied in Finder.

- A locked screen hides every window from Accessibility, and the Mac re-locks when a `babysit mac run` session ends. `scripts/e2e/hold.sh` holds one open (only types the password if the screen is really locked, `unlock` types into whatever has focus). `caffeinate -d -u` stops idle-lock.
- Replacing `/Applications/Battery.app` with a signed build: the app notices the new build and restarts the helper, no click. If it does not answer within 60s `e2e.sh` presses Repair (`mac-run.sh repair`), no approval needed.
- The app adopts limits set from the CLI, so GUI tests wait for the status poll before acting on the slider.
- SwiftUI Form toggles are unlabeled in the AX tree: `GUI.toggle("Label")` finds the checkbox after the label text. Sliders refuse a value set; step them with AXIncrement/AXDecrement (`AX.slide`).
- Helper healing (in `e2e.sh`): after the replace the helper must answer without a click (the app restarts it for the new build); after the lifecycle suite, `launchctl bootout` via `babysit mac sudo` kills the job and the app must bring it back on launch.
- Lifecycle suite (`LifecycleTests`, opt-in via `E2E_LIFECYCLE=1`, which e2e.sh sets): Settings -> Uninstall, set up again, Login Items switch off/on in System Settings (driven by Accessibility). Switching off needs the admin password unless macOS still has a recent authorization cached. The test only asks once System Settings is frontmost with its Password field focused (drops `/tmp/e2e/password-wanted`); e2e.sh re-checks System Settings is frontmost right before answering with `babysit mac unlock` (else `password-refused`). The password never passes through test code. `unlock` also clicks where the lock screen arrow would be, harmless so far. The sheet appears unless macOS has a recent authorization cached; `e2e.sh` logs which path ran. Switching on needs none.
- Not covered (needs a human or a reboot): sleep/wake, reboot. See PROGRESS.md for the manual runs.
