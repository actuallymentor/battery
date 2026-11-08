# PROGRESS: Swift port (v2), branch `v2/swift` (local, UNPUSHED)

Updated 2026-11-08. Read with `.HANDOFF.md` (plan, decisions), `AGENTS.md`, `.notes/`.

## Rules
- No push (git/gh) until the user says so. No `Co-Authored-By`.
- Commits are local, gitmoji.

## Done
- Branch `v2/swift`; v1 moved to `legacy/`; release pipeline (`scripts/release/`, `.github/workflows/release.yml`) committed. (`c2a4b9f`)
- `macos/` SwiftPM `BatteryCore` (`d3f633a`): maintain parsing (level/range/voltage), `Controller.decide`, `SMCPlan` (CHTE/CH0B/CH0C/CHIE/CH0I/CH0J/ACLC, v1 values), `Calibration` state machine, `Command` CLI parser, `PowerSnapshot`/`Report` (status, CSV, help). 32 tests pass: `cd macos && swift test`.

## Environment
- Linux container: Swift 6.4.2 at `~/swift-tc/usr/bin` (re-download from download.swift.org, debian13; needs apt `libncurses6 libxml2 libcurl4 libedit2 libstdc++-14-dev libgcc-14-dev binutils gcc libc6-dev zlib1g-dev`).
- Mac (spare, sudo ok): `babysit mac ssh ArjunMacbook '...'`. macOS 26.1, arm64, MacBook Air, 32 GB free disk. Only Command Line Tools (Swift 5.4.2, too old). No brew, no signing identities, no `gh`.
- On the Mac: `~/bin/xcodes` (2.46.0), `~/bin/xcodegen`, `~/Applications/` (empty).
- Creds: env `APPLE_ID`, `APPLE_ID_PASSWORD` (also `GMAIL_*`), Olivia's account. Never print them; pass as `"$APPLE_ID_PASSWORD"` in double quotes.

## BLOCKER: Xcode install needs Apple 2FA
- `xcodes install 26.1.1 --experimental-unxip --no-superuser --directory ~/Applications` (26.1.1 matches macOS 26.1; list: `xcodes list`) reaches the 2FA prompt, then fails without a tty.
- The code goes to a trusted device/phone, not Gmail. The user must supply it.
- Plan: run xcodes with stdin from a fifo (`mkfifo /tmp/xin; ... < /tmp/xin &`), ask the user for the code, `echo CODE > /tmp/xin`. Codes expire fast, so ask right after triggering.
- Disk: Xcode needs ~40 GB, 32 GB free. Check; free space or use `--experimental-unxip` and delete the xip.
- Then: `sudo xcode-select -s ~/Applications/Xcode-26.1.1.app`, accept the license (`babysit mac sudo ArjunMacbook xcodebuild -license accept`).

## Next
1. Xcode (above).
2. `macos/project.yml` (XcodeGen; targets App, Daemon, CLI, Core). Release contract: `macos/Battery.xcodeproj`, scheme `Battery`, product `Battery.app`, daemon plist in `Contents/Library/LaunchDaemons/`, bundle `co.palokaj.battery`, daemon `co.palokaj.battery.daemon`, min macOS 14.
3. IOKit SMC layer (daemon only). Probe keys on the Mac, record per-OS results in `.notes/RESEARCH.md`. Unknown: `bfD0/bfE0/bfF0`.
4. Daemon + XPC + caller code-signature check (team `CAWM399GFD`) + `SMAppService.daemon` registration.
5. Menubar UI (`MenuBarExtra`), CLI as thin XPC client, parity with v1 commands (`legacy/battery.sh`).
6. Triage fixes: #480/#469 Apple charge limit, #475 range bottom-bound, #470 menubar %, #462 custom limits popup, #425 launch at login. Sparkle 2, v1 cleanup on first launch, telemetry removed.
7. Test like a user on the Mac: real daemon, real charging changes (`pmset -g batt`, `ioreg -rn AppleSmartBattery`), screenshots via `babysit mac shot`.

## Open questions (user: "get to it later")
Appcast hosting, Homebrew formula owner, when to push for first CI run.

## Notes
- `.notes/` and other dotfiles are gitignored (`.*`); `.github` is whitelisted. Pre-existing deleted `assets/node_modules/*` in the working tree: leave alone.
- Post-milestone checklist in CLAUDE.md (reflect, style, changelog, test, cleanup, commit) not yet run for the Core commit.
