This repository contains software that limits the battery charging level of Apple Silicon MacBooks.

## Project structure

- `./macos/` v2, native Swift. Source of truth.
  - `Sources/BatteryCore/` pure logic (SMC plans, controller, CLI parsing, formatting). `cd macos && swift test`
  - `App/` SwiftUI menu bar app, `Daemon/` root helper (SMC, maintain loop, jobs), `CLI/` thin XPC client, `Shared/` XPC protocol
  - `project.yml` XcodeGen spec; the `.xcodeproj` is generated and gitignored
- `./macos/E2E/` end-to-end suites (CLI + GUI via Accessibility), real Mac only, `scripts/e2e.sh`
- `./scripts/release/` + `.github/workflows/release.yml` signed release pipeline (tag `v*`)
- `./legacy/` v1 (shell + Electron). Frozen. `main` keeps serving v1 `update.sh` until the v1 to v2 handover release.

## Rules

- No push, tag or release unless asked. No `Co-Authored-By` lines.
- Charge control is chosen by probing SMC keys (`SMCCapabilities.backend`), never by OS version.
- All SMC writes go through `Daemon/ChargeControl.swift` (verified, rolled back on failure).
- XPC is two calls: `snapshot` and `run( Command JSON )`. A new action is a `Command` case (`Sources/BatteryCore/Command.swift`), its gate in `Limits.refusal`, and its branch in `Service.run` (`Daemon/main.swift`). The app sends it with `client.send( .x )`.
- Logic that can be pure goes in `BatteryCore` with tests; fixtures come from `.notes/TRIAGE.md` key dumps.
- Version: `MARKETING_VERSION` in `macos/project.yml` (release builds override it from the tag; `CFBundleVersion` = CI run number for Sparkle).
- Identity constants live in `macos/project.yml` (`BATTERY_TEAM_ID`, bundle ids, `SUPublicEDKey`, Sparkle `exactVersion`): `scripts/release/lib.sh` parses them, the daemon reads its team from its own Info.plist and derives the caller ids from `batteryDaemonName`. `scripts/release/sign.sh` verifies the built binaries and the daemon plist agree, so a drift only surfaces in a signed build (`scripts/e2e.sh` or a tag).
- Daemon state is main-queue only (`Service.onMain`). Rules that can be pure live in BatteryCore (`MaintainState`, `JobPlanner`, `Schedule`, `Limits`, `Controller`); the daemon only runs their `Intent`s (`ChargeControl.run`).
- The daemon owns every setting (limit, force, enabled, schedule, CLI link); the app shows `BatteryStatus` and never keeps its own copy. A control the daemon owns goes through `AppModel.Knob` (`flip`/`shown`), never a raw `Binding`.
- The daemon validates every command (`Limits.refusal`); never rely on the CLI/app having parsed it.
- The `battery`/`Battery.app` names collide on case-insensitive disks: the CLI target is `BatteryCLI` (product `battery`).
- v1 rules (bump `battery.sh` version, `visudoconfig`) apply to `legacy/` only.

## Mandatory checks

Before finishing any task: sanity check for bugs, check comments still match the code, run `swift test`, and for UI/daemon changes verify on a real Mac (`babysit mac`), see `.notes/RESEARCH.md`.

For UI/daemon/CLI changes also run `scripts/e2e.sh` (real signed app + helper on the Mac, see `macos/E2E/README.md`) and add a test there for new behavior. No mocks in e2e.
