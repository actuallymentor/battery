This repository contains software that limits the battery charging level of Apple Silicon MacBooks.

## Project structure

- `./macos/` v2, native Swift. Source of truth.
  - `Sources/BatteryCore/` pure logic (SMC plans, controller, CLI parsing, formatting). `cd macos && swift test`
  - `App/` SwiftUI menu bar app, `Daemon/` root helper (SMC, maintain loop, jobs), `CLI/` thin XPC client, `Shared/` XPC protocol
  - `project.yml` XcodeGen spec; the `.xcodeproj` is generated and gitignored
- `./scripts/release/` + `.github/workflows/release.yml` signed release pipeline (tag `v*`)
- `./legacy/` v1 (shell + Electron). Frozen. `main` keeps serving v1 `update.sh` until the v1 to v2 handover release.

## Rules

- No push, tag or release unless asked. No `Co-Authored-By` lines.
- Charge control is chosen by probing SMC keys (`SMCCapabilities.backend`), never by OS version.
- All SMC writes go through `Daemon/ChargeControl.swift` (verified, rolled back on failure).
- New XPC methods: add to `Shared/BatteryXPC.swift`, implement in `Daemon/main.swift`, expose via `App/DaemonClient.swift` and/or `CLI/main.swift`.
- Logic that can be pure goes in `BatteryCore` with tests; fixtures come from `.notes/TRIAGE.md` key dumps.
- Version: `MARKETING_VERSION` in `macos/project.yml` (release builds override it from the tag).
- The `battery`/`Battery.app` names collide on case-insensitive disks: the CLI target is `BatteryCLI` (product `battery`).
- v1 rules (bump `battery.sh` version, `visudoconfig`) apply to `legacy/` only.

## Mandatory checks

Before finishing any task: sanity check for bugs, check comments still match the code, run `swift test`, and for UI/daemon changes verify on a real Mac (`babysit mac`), see `.notes/RESEARCH.md`.
