#!/bin/bash
# Read-only collection for the Battery PR #478 audit. No root required.
# Does NOT invoke Battery, alter limits, stop services, prevent sleep or install anything.
# Usage: bash read-only-power-check.command [sample-count] [interval-seconds]
# The raw amperage fields can be unsigned encodings of signed values on some Macs.
# Preserve the original numbers: do not infer charge direction from a large integer.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
if [[ $(uname -s) != Darwin ]]; then
    echo 'This read-only collector requires macOS; no commands were executed against hardware.' >&2
    exit 69
fi
samples=${1:-30}; interval=${2:-10}
[[ $# -le 2 && $samples =~ ^[1-9][0-9]{0,3}$ && $interval =~ ^[1-9][0-9]{0,2}$ ]] || {
    echo 'Usage: bash read-only-power-check.command [1..360 samples] [1..300 seconds]' >&2; exit 64;
}
((samples<=360 && interval<=300)) || { echo 'Sample count or interval too large.' >&2; exit 64; }
printf 'Read-only power observation. No settings will be changed. Ctrl+C stops collection.\n'
printf 'Keep the existing adapter attached. Do not deliberately cycle the battery for this check.\n'
printf 'Missing fields mean unknown. Current signs need interpretation, not a health verdict.\n'
/usr/bin/sw_vers
printf '\n--- Initial registered native limits ---\n'
/usr/bin/pmset -g battlimit || echo 'Native-limit diagnostic unavailable.'
for ((i=1; i<=samples; ++i)); do
    printf '\n--- Sample %d/%d: %s ---\n' "$i" "$samples" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    /usr/bin/pmset -g batt
    # Exact top-level keys only: do not log serial numbers, UUIDs or nested diagnostics.
    /usr/sbin/ioreg -r -c AppleSmartBattery -l -w 0 | /usr/bin/awk '
      /^[[:space:]|]*"(ExternalConnected|ExternalChargeCapable|IsCharging|Amperage|InstantAmperage|Voltage|CurrentCapacity|MaxCapacity|AppleRawCurrentCapacity|AppleRawMaxCapacity|CycleCount)"[[:space:]]*=/ { print; n++ }
      END { if (!n) print "Battery telemetry fields unavailable: unknown, not zero." }
    '
    ((i==samples)) || /bin/sleep "$interval"
done
printf '\n--- Final registered native limits ---\n'
/usr/bin/pmset -g battlimit || echo 'Native-limit diagnostic unavailable.'
printf '\nCollection complete. These samples do not prove long-term battery safety or feature parity.\n'
