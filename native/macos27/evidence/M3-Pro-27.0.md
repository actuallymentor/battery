# User-reported hardware observation: predecessor 0.1.0

Recorded September 17, 2026. The user explicitly stated that they were running
**the first version, 0.1.0**, not 0.2.0 or this fixed-ceiling 0.1.1 draft.
This report is a transcription/summary of their pasted terminal output, not a
measurement performed by the package author. No serial number or home path is
included.

- MacBook Pro, Mac15,6, Apple M3 Pro
- macOS 27.0, build 26A428
- System firmware 20457.1.29 (from the user's preceding diagnose output)
- Single target 55%, not a 45–55% range
- Two registered native limits: 55 and 55; each with `chargeSocLimitDrain = 1`
- Supplied samples: 18 of a requested 30. Do not present this as a completed
  five-minute recording.

| Samples | UTC interval | Charge | Power source | IsCharging | Amperage / InstantAmperage | Cycle count |
|---|---|---|---|---|---|---|
| 1–4 | 19:46:06–19:46:36 | 55% | AC Power | Yes | 3911 / 3911 mA | 85 |
| 5–18 | 19:46:46–19:48:57 | 55% | AC Power | No | 0 / 0 mA | 85 |

All 18 samples also report `ExternalConnected = Yes` and
`ExternalChargeCapable = Yes`.

The zero-current interval spans 2 minutes 11 seconds (131 seconds). The complete
pasted interval spans 2 minutes 51 seconds (171 seconds). Polling frequency is
not necessarily the hardware sensor refresh frequency; the samples are not
independent physical measurements.

During samples 1–4 the reported battery voltage is 12192 mV. During the
zero-current interval it is 11763, then 11740, then 11733 mV. No inference about
battery health is made from that voltage change.

## Supported conclusion

The native 55% request was registered, and the supplied later readings are
consistent with the Mac drawing AC power while the battery reports no charge
or discharge current. The supplied interval does not exhibit the adapter-cutoff
recharge loop objected to in PR #478.

## Not established

- Long-term absence of cycling or effects on battery life.
- Behaviour between samples, during sleep, reboot, power-off or adapter reconnect.
- Whether the early charging report was a transition, stale sensor data, or part
  of a longer pattern; the log does not establish the cause.
- Independent lower restart thresholds (not configured in this test).
- Runtime behaviour of this exact 0.1.1 source/build.

An unchanged integer cycle count of 85 does not rule out small battery throughput.
`chargeSocLimitDrain = 1` is a policy flag, not a current measurement.

## New-build test record

After building/installing 0.1.1, a human tester should add their actual results
in a PR comment. This section is deliberately not marked passed in advance.
Record `battery version`, model/OS/firmware, the configured target, registration,
and measured external-power/current observations. Sanitize identifiers before
posting. No local logs are automatically uploaded by publish.command.
