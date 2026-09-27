# Validation report: native policy 0.1.4

September 27, 2026. Mac15,6 / M3 Pro; macOS 27.0 (26A428); firmware 20457.1.29.

## Automated validation

- Apple clang 21.0.0 with the matching Xcode macOS 26.5 SDK compiled the native
  Objective-C helper with `-Wall -Wextra -Werror`.
- Portable C policy, warning and signed-current tests passed with address and
  undefined-behavior sanitizers.
- Native policy-archive tests passed with both sanitizers. These exercise
  creation, exact ceiling changes, changed process owners, idempotence,
  cancellation, token/reason isolation, unrelated-policy preservation, malformed
  fields, nested UID rejection, and owned/effective registration checks.
- Python suite: 40 tests, 39 passed and one skipped because the standalone
  publishing helper is not present in the upstream source tree.
- Shell syntax and `git diff --check` passed.
- Runtime comments and user-facing instructions were reviewed against the
  resident-daemon behavior. The unchanged upstream CLI keeps version 1.3.4.

## Live integration

- Installed 0.1.4 over the local experimental backend and retained original
  executable/settings backups. The original menu-bar app remains running.
- Verified the native policy owner is the real resident helper PID, with an
  effective 55% policy, no-charge-to-full=1, and drain=0.
- Restarted the resident helper through launchd. Its owner PID changed from
  53834 to 53899; the 55% policy and both flags were recreated successfully.
- Repeated `maintain 55` and `maintain recover`: powerd PID and policy stayed
  unchanged. No redundant service restart occurred.
- `maintain stop` restored the original 80% PowerUI policy with its original
  default flags. Re-enabling 55% restored the separate Battery-owned policy.
- `maintain 100` removed the native ceiling. Battery telemetry subsequently
  showed charging=true and +2017 mA. Returning to 55% registered the correct
  policy immediately in the control test, then fresh telemetry showed charging
  off and both currents zero while the adapter remained connected.
- A subsequent check exposed unnecessary repair attempts. The final correction
  preserves the current policy when read-back is unavailable and rechecks before
  repairing. The complete automated suite passed again after this change.
- The final installed daemon owns the policy as PID 59798. Its separate final
  observation recorded 25 samples over 250 seconds, with 87%, 4901 mAh,
  AC connected and both battery currents zero throughout. Powerd PID stayed
  unchanged. Exact timestamps and fresh-telemetry counts are in the evidence report.

Installed helper SHA-256:
`4000e12e67927033ebb9a7d2d8120bd6e603476becab3325455b9237620945dc`.
Installed native source, archive header, and CLI dispatcher were compared with
the delivered source. A local rebuild/signature may produce a different hash.

## What remains unverified

The final test started above the ceiling, around 87%. It verifies stopping
charging above the target and holding on AC, not a fresh charge from below 55%
to exactly 55%. Telemetry refreshes about once per minute; duplicate readings
between refreshes are not independent hardware samples.

The system charge-to-full override had cleared after the user's physical
reconnect before the new native-policy tests. Apple's handling of the exception
flag was inspected, but suppression during a newly active calibration request
has not been physically demonstrated. Sleep/wake, reboot, shutdown, other Macs,
future OS releases, and long-term battery-health effects remain unverified.

The intermediate 0.1.3 approach was rejected because PowerUI rewrote its own
policy flags. It is not the delivered solution. Older exploratory errors remain
in the machine's historical log; current status and the 0.1.4 evidence distinguish
them from the installed result.

See `evidence/M3-Pro-27.0-owned-2026-09-27.md` and its JSONL traces.
