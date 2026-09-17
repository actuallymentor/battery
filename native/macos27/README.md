# Battery: opt-in native fixed ceiling, draft 0.1.1

An experimental, deliberately limited contribution to `actuallymentor/battery`.
This package is NOT an upstream Battery release and is NOT feature-complete.

## Build-tools correction (buildfix1)

This distribution corrects compiler/linker/SDK selection only. All files under
`src/`, both privileged install/remove scripts, rollback, and the eight-line
upstream dispatch hook are unchanged from fixed-ceiling 0.1.1. The runtime
version string remains `v1.3.4-macos27-local.0.1.1-ceiling`.

The old test runner started with bare `cc`; in an activated Conda environment
that can select an incompatible compiler/linker for the installed macOS 27 SDK.
Mac builds now resolve Apple clang, ld and the SDK through `/usr/bin/xcrun` in a
clean compiler-child environment, use an explicit sysroot and linker search
prefix, print the chosen tools, and link a minimal C program before proceeding.
The test runner and installer share this same build helper. Python and GitHub
CLI retain the caller's normal environment. No global Xcode/Conda setting is
modified, and no SDK stub is edited.

For build diagnostics only (no sudo or charge-setting access):

```bash
bash scripts/check-toolchain.command
```

For compiler verbosity, use `B27_BUILD_VERBOSE=1 bash tests/run-tests.sh`.
`install.command -v` is NOT a verbosity option; the optional installer argument
is a percentage. See `BUILD-FIX.md` for the failure and correction details.

## Scope

Preserve the existing Battery app, icon and menu while adding an explicitly
installed, native fixed-ceiling backend. A ceiling below 80% is requested through
Apple's charging agent. There is NO SMC adapter-cutoff fallback and NO ratcheting
of the target based on the current percentage. A 55% policy keeps requesting 55%.

Only `maintain PERCENT`, `maintain stop`, `maintain recover`, status, diagnostics,
and restoration are implemented. `100` means no native ceiling. Separate lower
restart thresholds, forced discharge, calibration, immediate charging/adapter
switches and voltage regulation are intentionally rejected without changing
settings. This is not a claim that they are impossible, only that they have not
been implemented with the required behaviour in this draft.

**Firmware still controls restart hysteresis and can drain toward a newly lowered
ceiling.** No claim is made that changing a ceiling can never cause battery use.
An explicit native drain is not substituted for an independent restart threshold.

## Evidence and limitations

`evidence/M3-Pro-27.0.md` contains the user's reported test of predecessor **0.1.0**:
M3 Pro / Mac15,6, macOS 27.0 / 26A428, firmware 20457.1.29, ceiling 55%.
The pasted 18 samples include 14 successive observations with AC power, charging
false, and both current readings zero. These span 131 seconds. This supports
battery rest during those observations; it is not long-term battery-life data,
a sleep/reboot test, or a hardware test of this exact 0.1.1 build.

The preference write/notification mechanism is retained from 0.1.0. The changes
remove the range state machine, add measured read-only current telemetry, retain
the original CLI plus an opt-in dispatch hook, and constrain installation rules.
This new Objective-C build must still be compiled and exercised on a Mac.

The native interface is private and can change. Below-80% targets are not promised
by Apple's public UI. A successful preference write is not proof of registration;
a registered limit is not proof of the physical power flow. Readback and observed
current are reported separately. Missing readings stay unknown.

## Upgrade from 0.1.0

1. Disable `Allow force-discharging` in the original Battery menu, then quit it.
2. Extract this package. Run without sudo:

   ```bash
   cd ~/Downloads/battery-macos27-fixed-0.1.1-buildfix1
   bash tests/run-tests.sh
   bash install.command
   battery version
   battery status
   open -b co.palokaj.battery
   ```

No rollback of 0.1.0 is required. The installer preserves an existing single
ceiling (including 55%) and the original native-settings recovery snapshot. It
builds locally before replacing executable files; Apple's Command Line Tools
are required. Its probe checks actual API availability, not a macOS major-version
gate. Only the stated Mac/OS combination has the supplied runtime evidence.

Existing range state, an operation from 0.2.0, or a pending restore must be resolved
with the installed version before upgrading. The installer refuses to silently
convert those states. Do not install the withdrawn 0.2.0 package.

For a fresh install over upstream Battery, pass the target explicitly:

```bash
bash install.command 55
```

The app bundle is NOT replaced or re-signed. On the machine, the original
`/usr/local/co.palokaj.battery/battery` is recovered from the original backup and
gets the small hook in `src/dispatch-snippet.sh`. `BATTERY_CLI_VERSION` remains
`v1.3.4`; the opt-in dispatcher reports a separate local build string.

Without the opt-in marker, the upstream CLI continues on its original code path.
Legacy SMC commands are not modified or called by the active native backend.
Source files are retained alongside the installed helper for inspection.

## Verify the NEW build

After reopening the original app, observe it again with:

```bash
battery version
battery status
bash evidence/read-only-power-check.command
```

Look at actual external power, charging state, and both current readings as well
as the target. Reopening the original GUI can stop/restart maintenance as part
of its existing initialization. A transient charge report is not the same as a
repeated discharge/recharge pattern. Do not deliberately cycle the battery just
to test this contribution. Negative sustained battery current on AC needs
investigation, including whether the adapter is sufficient for the workload.

`status_csv` retains five fields. Its fourth field is **unknown**: the legacy
forced-discharge state must not masquerade as a measured current. The old GUI
does not display detailed current; `battery status` and the read-only script do.
The unchanged GUI's labels do not constitute an independent verification.

The launchd helper runs every 15 seconds and exits; `not running` with exit code
0 between invocations is expected. It does not block normal sleep. Sleep-time
behaviour and power-off/reconnect cases remain unverified.

## Stop or roll back

```bash
battery maintain stop
```

Requests restoration of the original native preferences via the agent and
retains recovery data on failure. Verify the result in status and System Settings.
To remove this native backend and restore the upstream CLI, quit Battery and run:

```bash
bash rollback.command
```

This is rollback to upstream, not a downgrade to 0.1.0; upstream itself still has
the macOS 27 limitation. Installation failure attempts to restore the prior
executables/rules. A failure after a target request must be inspected; don't
assume the policy is enforced or restored merely because files were installed.

## Draft pull request

The separate `publish.command` is included in the download, not added to the
upstream project. It uses the user's GitHub CLI authentication and never handles
a pasted token. `contribution/upstream.patch` and `contribution/PR.md` are also
included in the download. See `PR-INSTRUCTIONS.md`.

The first PR is for **fixed native ceilings**, not full feature parity. It leaves
upstream release versions and automatic rollout unchanged. The old app's CLI
update calls are intercepted only on machines that explicitly installed this
backend, so they do not silently replace the experimental component.

## Privileged operations

The installed helper has fixed paths, argument validation before state access,
a root-owned recovery state and locking. The installer validates executable and
parent path ownership/modes/ACLs and checks sudoers syntax. Maintenance is exposed
as 100 exact `maintain N` sudo rules, not a wildcard or unrestricted shell.
This remains privileged software requiring security review; those checks are
not a claim of a completed independent security audit.

## Upstream feedback addressed

- PR #478: do not disconnect the adapter to imitate a resting charge limit.
- PR #469: leave release version control to the maintainer and detect usable
  native capabilities rather than relying only on a macOS version label.
- Do not describe a saved setting, synthetic test, or absent current reading as
  a successful physical hardware test.
- Do not claim a validated wrapper is categorically disallowed: the reviewer
  later accepted that principle, while preferring a small reviewable surface.

References:
- https://github.com/actuallymentor/battery/pull/478
- https://github.com/actuallymentor/battery/pull/469
- https://github.com/actuallymentor/battery/blob/main/CONTRIBUTING
- https://github.com/az-code-lab/ampere/blob/v0.0.65/Sources/Shared/NativeChargeLimit.swift
- https://github.com/az-code-lab/ampere/blob/v0.0.65/Sources/SMCWriter/main.swift

See `THIRD-PARTY-NOTICES.md` for attribution and licensing.
