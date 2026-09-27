#!/bin/bash
# SPDX-License-Identifier: MIT
# BATTERY_MACOS27_NATIVE 0.1.4-ceiling
# Opt-in fixed-ceiling dispatcher; keep the original menu-bar application.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
ROOT=/Library/PrivilegedHelperTools/co.palokaj.battery.macos27
HELPER="$ROOT/native-charge"
action=${1:-help}
native() {
    if [[ $EUID -eq 0 ]]; then "$HELPER" "$@";
    else /usr/bin/sudo -n "$HELPER" "$@"; fi
}
argc() { [[ $1 -eq $2 ]] || { echo 'Wrong number of arguments.' >&2; exit 64; }; }
case "$action" in
    version|--version)
        argc "$#" 1; echo 'v1.3.4-macos27-local.0.1.4-ceiling' ;;
    update_silent)
        [[ $# -eq 1 || ( $# -eq 2 && $2 == is_enabled ) ]] || exit 64
        [[ ${2:-} == is_enabled ]] || echo 'Opt-in native backend installed; upstream CLI auto-updates are paused.' ;;
    update)
        [[ $# -eq 1 || ( $# -eq 2 && $2 == silent ) ]] || exit 64
        echo 'Native backend updates are explicit. Roll back before installing an upstream CLI update.' ;;
    visudo)
        argc "$#" 1; echo 'Native helper authorization is managed by the opt-in installer.' ;;
    status|status_csv|recover|probe)
        argc "$#" 1; native "$action" ;;
    maintain)
        [[ $# -eq 2 ]] || {
            echo 'Usage: battery maintain PERCENT | stop | recover' >&2
            echo 'Force discharge and independent restart thresholds are not implemented; no settings changed.' >&2
            exit 64
        }
        case "$2" in
            stop) native stop ;;
            recover) native recover ;;
            *)
                value=$2
                [[ $value =~ ^[0-9]{1,3}$ ]] || {
                    echo 'Use ONE percentage. Ranges and voltage limits are unsupported; no settings changed.' >&2; exit 64;
                }
                n=$((10#$value))
                ((n>=1 && n<=100)) || { echo 'Expected 1..100; no settings changed.' >&2; exit 64; }
                native maintain "$n"
                if [[ $EUID -ne 0 ]]; then
                    /bin/mkdir -p "$HOME/.battery"
                    printf '%s\n' "$n" > "$HOME/.battery/maintain.percentage"
                fi ;;
        esac ;;
    charging|adapter|charge|discharge|calibrate|cancel|operation|maintain_synchronous|maintain_voltage_synchronous)
        echo "'$action' is not implemented in this fixed-ceiling draft. No settings changed." >&2
        echo 'Use battery maintain PERCENT, or battery maintain stop to restore the original native settings.' >&2
        exit 69 ;;
    diagnose)
        argc "$#" 1
        echo '=== Battery native fixed-ceiling backend 0.1.4 ==='
        /usr/bin/sw_vers
        /usr/sbin/system_profiler SPHardwareDataType 2>/dev/null | /usr/bin/grep -E 'Model Name:|Model Identifier:|Chip:|Firmware Version:' || true
        native diagnose
        echo '--- recent macOS charge-override evidence (read-only) ---'
        /usr/bin/log show --last 15m --style compact --predicate \
            '(process == "powerd" OR process == "PowerUIAgent") AND (eventMessage CONTAINS "SOC limit policy suspend" OR eventMessage CONTAINS "Battery mitigations are in place" OR eventMessage CONTAINS "Last DOD0 change" OR eventMessage CONTAINS "Charge To Full Request")' \
            2>/dev/null | /usr/bin/tail -n 25 || true
        echo '--- service ---'
        /bin/launchctl print system/local.battery.macos27 2>/dev/null | /usr/bin/grep -E 'state =|runs =|last exit code =|program =' || true
        echo '--- recent backend logs ---'
        /usr/bin/tail -n 60 /var/log/battery-macos27.log 2>/dev/null || true ;;
    logs)
        [[ $# -le 2 ]] || exit 64
        count=${2:-80}; [[ $count =~ ^[0-9]{1,4}$ ]] || exit 64
        /usr/bin/tail -n "$count" /var/log/battery-macos27.log ;;
    enable_daemon)
        argc "$#" 1; native recover ;;
    disable_daemon|remove_daemon)
        argc "$#" 1; native stop ;;
    rollback)
        argc "$#" 1
        echo 'Quit Battery, then run rollback.command from this package.' >&2; exit 64 ;;
    uninstall)
        [[ $# -eq 1 || ( $# -eq 2 && $2 == silent ) ]] || exit 64
        if [[ ${2:-} != silent ]]; then
            printf 'Remove the Battery CLI and native helper? The app bundle is retained. [y/N] '
            IFS= read -r answer
            [[ $answer == y || $answer == Y ]] || exit 0
        fi
        if [[ $EUID -eq 0 ]]; then /bin/bash "$ROOT/uninstall-root.sh" --remove-cli;
        else /usr/bin/sudo /bin/bash "$ROOT/uninstall-root.sh" --remove-cli; fi ;;
    reinstall)
        echo 'Use this package install.command, or roll back before reinstalling upstream Battery.' >&2; exit 64 ;;
    help|--help)
        cat <<'HELP'
Battery native fixed-ceiling draft 0.1.4 (opt-in, experimental)

  battery maintain 55            Fixed native ceiling, including below 80%.
  battery maintain 100           Disable the native limit (no ceiling).
  battery maintain stop          Stop and restore original native settings.
  battery maintain recover       Re-enable the last saved single ceiling.
  battery status                 Requested limit plus measured power snapshots.
  battery status_csv             Original GUI's five-field status contract.
  battery diagnose               Diagnostics without serial numbers.
  battery uninstall              Remove the native helper and Battery CLI.

The original Battery menu-bar app is retained. Turn OFF its Allow force-discharging
setting. Independent lower thresholds/ranges, discharge, calibration, immediate
charging/adapter switches, and voltage regulation are intentionally unsupported.
They return errors without changing settings. There is no adapter-cutoff fallback
and no moving target based on the observed percentage. Firmware controls restart
hysteresis and sleep-time enforcement. Native no-drain and no-charge-to-full flags
are applied through Apple's power service; application requires a service restart.
Native requests are asynchronous. Registration is not a power-flow measurement.
This private interface is experimental. Check the flags and measured current;
a future macOS change or full-charge event still requires hardware verification.
Field four of status_csv is 'unknown': legacy forced discharge cannot be inferred.
Use battery status or the read-only observation script for measured current.
HELP
        ;;
    *) echo "Unknown command: $action. Run battery help." >&2; exit 64 ;;
esac
