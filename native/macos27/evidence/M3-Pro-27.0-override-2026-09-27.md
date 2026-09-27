# macOS 27: 55% limit overridden by battery-gauge maintenance

Observed on 27 September 2026, MacBook Pro M3 Pro (Mac15,6), macOS 27.0
build 26A428, firmware 20457.1.29. Adapter connected; saved target 55%.

## Result

The charging problem is reproduced, but a strict 55% cap has **not** been fixed.
The native 55% registrations exist while macOS suspends their enforcement.
This is distinct from a lost preference or a stopped Battery daemon.

The observed system override requests a full charge for battery-gauge maintenance.
Whether it clears after a full charge, and whether the original 55% policy then
resumes, has not yet been tested. The battery still charges above 55%.

## Evidence

Initial observation: 62%, external power connected, charging true,
Amperage and InstantAmperage both +3501 mA. `pmset -g battlimit` showed two
55% manualChargeLimit registrations, with Drain=1 and NoChargeToFull=0.
Reapplying `battery maintain 55` did not stop the charging.

System logs (local Europe/Berlin time):

```
2026-09-27 17:34:42 powerd: Last DOD0 change 11.9 days ago — charge to full
2026-09-27 17:34:42 powerd: [Pack 0 / <private>] Charge To Full Request: 1
2026-09-27 17:34:42 powerd: SOC limit policy suspend due to mitigation active:1
2026-09-27 17:34:42 PowerUIAgent: Battery mitigations are in place, MCL will be ignored
```

The read-only Darwin notification
`com.apple.system.powersources.chargingtofulloverride` returned state 1.
Apple also documents occasional charges to 100% to maintain the battery estimate:
https://support.apple.com/en-us/102338

## Bounded hardware tests

1. A standalone administrator-run helper attempted to register a native fixed
   55% request without draining and with the no-charge-to-full option. The
   registration itself returned `0xe00002c1` (not privileged), before a target
   could be set. Administrator access does not provide Apple's private
   entitlement. No custom native limit was registered. The two additional
   read-only private status calls were denied with the same code.
2. A separate 90-second administrator-run `ChargeInhibit` assertion was accepted
   (`rc=0`), but the battery continued charging from 66% to 67%, with positive
   current in all nine ten-second samples (+2521 to +2713 mA). The assertion
   was released successfully (`rc=0`). Its owning test process exited.
3. Legacy CHTE, CH0B and CH0C SMC reads returned no data. No SMC writes were made.

Neither experiment supplies a working cap on this Mac/firmware. No adapter
cutoff, forced discharge, protection bypass, calibration reset, or sleep-setting
change was performed. The installed 55% policy remains in place.

## Diagnostic correction 0.1.2

Prepared from PR #479 head `7c2eb31ea4669fa430585a452b4eecf756ef92c2`:

- Read the system full-charge-override notification without changing it.
- Warn when an override is active or telemetry shows charging at/above the limit.
- Keep the warning separate from a successful powerd registration.
- Include filtered macOS evidence in `battery diagnose`.
- Preserve the five-field CSV and legacy GUI policy-enabled token.
- Keep charging writes and restoration behavior unchanged.

The existing GUI still identifies a configured policy; its bundle is unchanged.
This patch improves diagnosis, not charge enforcement. It is not a solution to
an absolute cap while macOS overrides the native limit.

Validation: portable C tests with address/undefined-behavior sanitizers (including
13 new override/current cases); Python suite 39 passed, 1 intentionally skipped
(distributed publisher absent); Objective-C build passed with Apple clang 21,
Apple linker, and MacOSX26.5.sdk; shell syntax and diff whitespace checks passed.

The new helper was then run in read-only status mode against the actual Mac:

```
Battery at 70% (1:41 remaining), actual charging yes
Requested policy: battery being maintained at 55% (configuration only)
Policy: fixed ceiling; requested native ceiling: 55%
External power: yes
macOS charge-to-full override: active
Battery amperage: 2722 mA (reported)
Battery instant amperage: 2722 mA (reported)
Current readings are snapshots, not a guarantee of long-term battery rest.
powerd registered ceilings: 55, 55
WARNING: macOS charge-to-full override is active. The requested ceiling is not a hard cap; macOS may charge past it for battery-gauge maintenance. Run battery diagnose for system evidence.
```

The updated helper has not been installed or published. No sleep/wake, reboot,
reconnect, completed calibration, or restored enforcement is claimed.
