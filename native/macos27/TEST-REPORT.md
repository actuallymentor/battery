# Validation report: fixed-ceiling 0.1.1, buildfix1

Date: September 17, 2026. Build environment used here: Linux, not a Mac.

## Passed here

- Portable C fixed-target and argument/current parsing tests, compiled with
  address and undefined-behaviour sanitizers.
- 40 mocked/static Python checks in the distribution, all passed: the previous
  29 plus 11 build-tool selection tests. The new tests execute a real shell and
  clean child environments against **fake** Apple tool resolvers/compilers;
  they do not prove actual Apple linker/SDK compatibility.
- Shell syntax checks for installer, rollback, dispatcher, root scripts and
  publishing script and build-only diagnostic/helper scripts.
- Patch application and reverse-check against a **local fixture of the verified
  upstream battery.sh header context**. Removing the hook recovers that context
  byte-for-byte and leaves the upstream version string unchanged.
- Source review: no SMC adapter cutoff, no moving ceiling, no operations/calibration
  state machine, no fabricated 'not discharging' measurement in status_csv.

The new upstream source tree does not include the distribution-only publisher;
when run there, one publisher-specific test is intentionally skipped.

## Not performed here

- Native Objective-C compilation: no macOS SDK was available. The installer and
  publisher both require it to pass locally before replacing files or pushing.
- Full upstream repository checkout: this container could not resolve github.com.
  The GitHub connector verified upstream main as
  `f4e342f013e5e35d6c55f89a4f06917a118f993a`; the publisher clones the actual repo
  and checks patch application there before committing/pushing.
- End-to-end install, upgrade, restore, rollback, or native-framework tests on a Mac.
- Live GitHub authentication, fork, push, or PR creation. The publishing helper
  has only been syntax/static checked here; it has NOT been executed against
  the user's account.
- Long-duration power-flow, sleep/wake, reboot, reconnect or other models/firmware.

## Hardware evidence supplied by the user

Only predecessor 0.1.0 has the supplied device observations. In that version,
a single 55% request registered on the M3 Pro, and 14 successive supplied samples
showed AC power and both battery currents at 0 mA over 131 seconds. See
`evidence/M3-Pro-27.0.md`. This is not converted into an unperformed hardware
pass for the 0.1.1 revision.

## Remaining acceptance tests before release

1. Compile and inspect the exact new version, then observe its steady 55% state
   using independent read-only telemetry as well as helper status.
2. Confirm successful stop/restoration and recovery, including a failed request
   keeping its original-settings snapshot and a clean upgrade from 0.1.0.
3. Verify no sustained unintended discharge or repeated recharge on sufficient
   AC power during ordinary use, plus sleep/reconnect/reboot cases.
4. Privilege-boundary and source review by upstream maintainers, and an agreed
   production helper distribution/update strategy.

Ranges and advanced controls are excluded, not marked passed. The purpose is
one reviewable fixed-ceiling contribution, not an unsupported parity claim.

## Buildfix1 scope validation

All `src/` files, `scripts/install-root.sh`, `scripts/uninstall-root.sh` and
`rollback.command` were compared byte-for-byte with the prior fixed-ceiling
0.1.1 package and match. The existing `battery.sh` dispatch diff is unchanged.
No charging logic, privileged runtime policy, SMC calls, or release version was
modified by this build-only correction. The full regenerated PR payload was
applied/reversed against the same local header fixture, and every added file
was compared with its distribution counterpart.

The user's failure was at the old runner's initial link step, before its Python
tests and before installation. Neither it nor these mocked tests count as a
successful native compile of 0.1.1. No macOS SDK, macOS linker execution, battery
hardware test, installation, or live publishing occurred in this environment.
