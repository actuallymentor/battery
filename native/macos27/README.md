# Battery: opt-in native charge policy 0.1.4

Experimental compatibility backend for `actuallymentor/battery` 1.3.4 on macOS
27. The existing Battery app and its menu remain in use. This is a local build,
not an upstream release.

## Behavior

`battery maintain 55` requests a fixed 55% ceiling with native `drain=0` and
`noChargeToFull=1` flags. The Mac can run on its adapter with the battery resting.
If the battery is already above 55%, it is held there until normal unplugged use
lowers it. The backend does not deliberately discharge it to the new ceiling.
Firmware controls restart hysteresis.

The original preference-only patch could register 55% while Apple's battery
maintenance overrode enforcement and charged to 100%. Editing the flags on
PowerUI's own policy also proved unstable: PowerUI rewrote them. This version
uses a separate policy owned by the resident Battery helper. PowerUI's manual
limit is disabled during maintenance; its original settings are saved and
restored on stop. Other clients' native policies are preserved.

The helper imports its policy through the current boot's
`com.apple.powerd.charging` archive and restarts Apple's power service once to
apply it. It does not restart the service on ordinary 15-second checks. The
helper's real process ID owns the policy; macOS releases that policy when the
process exits. Launchd keeps the helper running and it recreates its policy when
restarted. A root-owned journal records the token and boot session before writes.
Only that token with the backend's reason can be changed or removed.

Automatic repair is bounded to three restart attempts per ten minutes, with a
one-minute cooldown in the same daemon instance. Explicit target changes reset
the repair budget. Repeating a confirmed unchanged target does not reload the
power service. Unavailable or malformed registration readings leave the current
policy unchanged; repair requires a readable policy list and a second check.
No adapter-cutoff or sleep-prevention mechanism is installed.

## Evidence and limitations

Tested on Mac15,6 / M3 Pro, macOS 27.0 (26A428), firmware 20457.1.29. Live tests
cover current measurements, stop/restoration, unlimited charging and returning
to 55%, repeated requests, and restarting the resident helper. See
`TEST-REPORT.md` and `evidence/M3-Pro-27.0-owned-2026-09-27.md` for exact results.

This is a private, undocumented interface. The no-charge-to-full flag requests
an exception to Apple's automatic full-charge maintenance; Apple's power service
checks that flag before suspending the limit. However, the system's full-charge
override had cleared before these tests. A newly active calibration request,
charging from below 55% to exactly 55%, sleep/wake, reboot, shutdown, other Macs,
and future OS versions remain unverified. Apple normally allows occasional
charges to full to maintain charge estimates:
https://support.apple.com/en-us/102338 . Stop maintenance to restore the original
native behavior.

## Install or upgrade

Requires upstream Battery 1.3.4, Apple Silicon, and Apple Command Line Tools or
Xcode. Quit Battery first and turn off its `Allow force-discharging` option.

```bash
bash tests/run-tests.sh
bash install.command 55
battery version
battery status
open -b co.palokaj.battery
```

An upgrade without a percentage preserves an existing single target and original
settings snapshot. A range, pending restoration, withdrawn 0.2.0 operation, or
unfinished 0.1.3 experimental flag journal must be resolved with that version
before upgrading. No app bundle is replaced or re-signed.

The compiler, linker and SDK are selected together in a clean child environment.
No SDK files or global developer-tool settings change. For build diagnostics,
use `bash scripts/check-toolchain.command`; `BUILD-FIX.md` is historical context.

## Controls and verification

```bash
battery maintain 55       # Fixed native ceiling
battery maintain 100      # Release the ceiling and allow charging
battery maintain stop     # Restore the original native settings
battery maintain recover  # Re-enable the saved single ceiling
battery status
battery diagnose
```

Requests wake the resident daemon and are asynchronous. Its launchd service is
normally `running`. Status distinguishes the requested target, live registrations
and measured battery current. Look for a confirmed no-charge-to-full/no-drain
policy, AC connected, charging off, and both current readings at zero. Telemetry
may lag a change by about one minute; check fresh readings over time.

The original GUI's five-field status format is preserved. Its enabled indicator
means the policy is configured, not a separate hardware verification. Independent
restart thresholds, force discharge, calibration, voltage regulation, and
immediate adapter switches remain unsupported and return an error.

## Recovery

Stopping removes only this helper's journaled native policy, reloads the power
service if required, and restores the original PowerUI settings. Recovery data
is retained if any step fails. To remove the backend and restore the upstream
CLI, quit Battery and run `bash rollback.command`. Restoration must succeed
before removal. Upstream itself retains its macOS 27 limitation.

Root commands and percentage arguments are explicitly restricted; the journal
is protected and locked. Archive parsing is bounded and does not instantiate
archived classes. Its tests cover token isolation, changed owners, cancellation,
malformed references, and preservation of unrelated policies. Shared system
preferences are not transactional: optimistic readback checks reduce, but do
not eliminate, concurrent-write risks. This is not an independent security audit.

## Contribution

Only explicitly opted-in machines use this backend. Upstream release versions,
legacy SMC commands and the app bundle stay unchanged. Automatic upstream CLI
replacement is paused while the experimental backend is active.

BattOpt's public macOS 27 support provided a research lead; the native mechanism
was then examined on the test Mac and independently implemented here. No vendor
binary or disassembly is distributed in this package.

References:
- https://github.com/actuallymentor/battery/pull/479
- https://github.com/js4jiang5/BattOpt
- https://github.com/AppHouseKitchen/AlDente-Battery_Care_and_Monitoring/discussions/1814
- https://support.apple.com/en-us/102338

See `THIRD-PARTY-NOTICES.md` for the earlier native preference mechanism's
attribution and licensing.
