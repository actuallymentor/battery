# Native policy 0.1.4: live evidence

Tested September 27, 2026 on Mac15,6 / M3 Pro, macOS 27.0 (26A428),
firmware 20457.1.29. All timestamps below are UTC; Berlin local time was UTC+2.
Requested ceiling: 55%. The battery was already above the ceiling.

## Measured charging control

The earlier installed-policy observation has 43 samples from 18:56:45 to
19:03:55. It intentionally includes the control tests below; changes in the
middle are test transitions, not steady-state measurements.

- Repeating `maintain 55` and `maintain recover` retained powerd PID 53910 and
  the existing native lease.
- `maintain stop` restored the saved 80% PowerUI limit and its original flags.
- Re-enabling 55% recreated the independently owned native policy.
- `maintain 100` removed the limit. At 18:59:42, fresh telemetry showed actual
  charging at +2017 mA. The independent observer also recorded positive current.
- Returning to 55% registered both the owned and effective policies with
  `drain=0` and `noChargeToFull=1`. Telemetry took time to reflect the change.
- From 19:00:22 through 19:03:55, all 22 samples showed 87%, AC connected,
  charging off, and both battery-current measurements at zero. Remaining charge
  stayed at 4901 mAh. This is 213 seconds and four distinct telemetry updates.

The real resident helper PID owned the policy. A controlled launchd restart
changed the owner from 53834 to 53899, and the policy recovered. Owner zero in
`pmset` is macOS's effective policy entry, not a fabricated owner for our lease.

## Final correction and installed build

After the earlier observation, a final check found unnecessary repair attempts
despite subsequently correct live registrations. The final build treats
unavailable or malformed read-back as unknown, leaves the existing policy in
place, and rechecks before a repair. The warning had cleared before the upgrade.
This avoids treating a failed observation as proof that a policy is missing.

The corrected build was compiled and its complete automated suite rerun. Its
installation changed the daemon owner to 59798 and retained the original 80%
recovery snapshot. The source, archive header, policy header and CLI dispatcher
were compared with the installed files.

Installed helper SHA-256: `4000e12e67927033ebb9a7d2d8120bd6e603476becab3325455b9237620945dc`.

Final bounded observation: **2026-09-27T19:14:32+00:00 through 2026-09-27T19:18:42+00:00** (250 seconds).
All 25 samples showed:

- Battery 87%, remaining charge 4901 mAh, adapter connected.
- Charging off; average and instantaneous battery current both 0 mA.
- Both native registrations at 55%, with no-charge-to-full=1 and drain=0.
- Powerd PID 59806 unchanged: no repair restart during this window.
- Charge-to-full override state zero.

There were 5 distinct telemetry timestamps. Repeated cached measurements
are not counted as independent hardware updates. A separate fresh read at
19:11:49 also showed 87%, 4901 mAh and zero current. The user confirmed seeing
87% during this period. These observations support adapter-only operation during
the measured windows, rather than deliberate discharge to the selected ceiling.

## Limits of this result

The charge-to-full override had cleared after the user's physical reconnect
before these tests. Suppression of a newly active Apple calibration request is
not physically tested. Neither is charging from below 55% up to the ceiling,
sleep/wake, reboot, shutdown, other Macs or future macOS versions.

This is an experimental private-interface implementation. A short successful
hold does not establish indefinite behavior. The device was left maintaining
55%, with the adapter connected and the original Battery app in place.

Raw selected telemetry (no device serial numbers):
- `owned-control-tests.jsonl`
- `owned-policy-installed-observation.jsonl` (earlier control-test build)
- `owned-policy-final-observation.jsonl` (final installed build)
