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

The Mac builds and tests itself (`scripts/e2e/sync.sh` ships the tree to `~/e2e`). Signing credentials come from `.secrets/`, are copied over for the build and deleted again.
Tests restore a neutral Mac (no limit, no job, no schedule, charging and adapter on) in `setUp` and `tearDown`. Tests skip themselves on Macs that can't cut the adapter or are too low on charge.

## One-time Mac setup

- Terminal.app needs Accessibility (System Settings -> Privacy & Security -> Accessibility). The GUI suite runs inside Terminal because that is the process holding the grant.
- `babysit mac` registered for the Mac. `MAC=name scripts/e2e.sh` for another one.

## Gotchas

- A locked screen hides every window from Accessibility, and the Mac re-locks when a `babysit mac run` session ends. `scripts/e2e/hold.sh` holds one open (only types the password if the screen is really locked, `unlock` types into whatever has focus). `caffeinate -d -u` stops idle-lock.
- Replacing `/Applications/Battery.app` leaves the registered helper "not answering" (launchd EX_CONFIG) until the app's own Repair helper button is pressed. `e2e.sh` presses it, no approval needed.
- The app adopts limits set from the CLI, so GUI tests wait for the status poll before acting on the slider.
- SwiftUI Form toggles are unlabeled in the AX tree: `GUI.toggle("Label")` finds the checkbox after the label text. Sliders refuse a value set; step them with AXIncrement/AXDecrement (`AX.slide`).
- Lifecycle suite (`LifecycleTests`, opt-in via `E2E_LIFECYCLE=1`, which e2e.sh sets): Settings -> Uninstall, set up again, Login Items switch off/on in System Settings (driven by Accessibility). Switching off needs the admin password unless macOS still has a recent authorization cached. The test only asks once System Settings is frontmost with its Password field focused (drops `/tmp/e2e/password-wanted`); e2e.sh answers with `babysit mac unlock`. The password never passes through test code. Switching on needs none.
- Not covered (needs a human or a reboot): sleep/wake, reboot. See PROGRESS.md for the manual runs.
