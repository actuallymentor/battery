#!/bin/bash
# SPDX-License-Identifier: MIT
# Local build + opt-in install/upgrade. Never downloads or replaces the app.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
ROOT=/Library/PrivilegedHelperTools/co.palokaj.battery.macos27
LEGACY=/usr/local/co.palokaj.battery
[[ $EUID -ne 0 && $(uname -s) == Darwin ]] || { echo 'Run on macOS, WITHOUT sudo.' >&2; exit 1; }
[[ $(/usr/sbin/sysctl -n hw.optional.arm64) == 1 ]] || { echo 'This opt-in build requires Apple Silicon.' >&2; exit 1; }
# Capability probe below is authoritative, not the macOS major version.
# Observed hardware evidence currently covers only macOS 27.0 / M3 Pro.
[[ $# -le 1 ]] || { echo 'Usage: bash install.command [55]' >&2; exit 64; }
if /usr/bin/pgrep -f '/[Bb]attery.app/Contents/MacOS/' >/dev/null 2>&1; then
    echo 'Quit the Battery menu-bar application, then rerun. Its bundle will not be changed.' >&2; exit 1
fi
[[ -f $LEGACY/battery && -f $LEGACY/smc ]] || { echo 'Install and launch upstream Battery once before installing this backend.' >&2; exit 1; }
SETTING=${1:-}
validate_setting() {
    [[ $1 =~ ^[0-9]{1,3}$ ]] || { echo 'This build accepts one ceiling, not a lower-upper range.' >&2; return 1; }
    local n=$((10#$1)); ((n>=1 && n<=100)) || { echo 'Expected ceiling 1..100.' >&2; return 1; }
}
if [[ -n $SETTING ]]; then validate_setting "$SETTING" || exit 64; fi
# Fresh installs must validate the recovered setting BEFORE disabling old jobs.
if [[ ! -e $ROOT && -z $SETTING && -f $HOME/.battery/maintain.percentage ]]; then
    IFS= read -r SETTING < "$HOME/.battery/maintain.percentage" || true
    [[ -z $SETTING ]] || validate_setting "$SETTING" || exit 64
fi
source "$DIR/scripts/apple-toolchain.sh"
b27_select_apple_toolchain
BUILD=$(/usr/bin/mktemp -d)
trap '/bin/rm -rf "$BUILD"' EXIT
b27_toolchain_preflight "$BUILD"
printf 'Building and compile-checking the native backend locally...\n'
b27_apple_clang -arch arm64 -std=c11 -fobjc-arc -O2 -Wall -Wextra -Werror \
    -framework Foundation -framework IOKit "$DIR/src/native-charge.m" -o "$BUILD/native-charge"
/usr/bin/codesign --force --sign - "$BUILD/native-charge"
/usr/bin/sudo -v
/usr/bin/sudo "$BUILD/native-charge" probe
# Refuse to replace a range policy or pending recovery without resolving it first.
/usr/bin/sudo "$BUILD/native-charge" check-state
UPGRADE=0
[[ ! -e $ROOT ]] || UPGRADE=1
BACKUP=''
OLD_PLIST="$HOME/Library/LaunchAgents/battery.plist"
if [[ $UPGRADE -eq 0 ]]; then
    BACKUP="$HOME/.battery/macos27-user-backup-$(date +%Y%m%d-%H%M%S)"
    /bin/mkdir -p "$BACKUP"; /bin/chmod 0700 "$BACKUP"
    if [[ -f $HOME/.battery/maintain.percentage ]]; then
        /bin/cp "$HOME/.battery/maintain.percentage" "$BACKUP/maintain.percentage"
        if [[ -z $SETTING ]]; then IFS= read -r SETTING < "$HOME/.battery/maintain.percentage" || true; fi
    fi
    if [[ -f $OLD_PLIST ]]; then
        /bin/launchctl bootout "gui/$(id -u)" "$OLD_PLIST" >/dev/null 2>&1 || true
        /bin/mv "$OLD_PLIST" "$BACKUP/battery.plist"
    fi
    /usr/bin/pkill -u "$(id -u)" -f '/usr/local/(bin/battery|co\.palokaj\.battery/battery) (maintain_synchronous|maintain_voltage_synchronous|calibrate|charge|discharge)( |$)' 2>/dev/null || true
fi
if ! /usr/bin/sudo /bin/bash "$DIR/scripts/install-root.sh" "$BUILD/native-charge" "$DIR" "$(id -un)"; then
    if [[ -n $BACKUP && -f $BACKUP/battery.plist ]]; then /bin/mv "$BACKUP/battery.plist" "$OLD_PLIST"; fi
    echo 'Installation failed; previous files restored. Check the error above.' >&2; exit 1
fi
if [[ -n $BACKUP ]]; then printf '%s\n' "$BACKUP" > "$HOME/.battery/macos27-user-backup.path"; fi
if [[ -n $SETTING || $UPGRADE -eq 0 ]]; then
    "$LEGACY/battery" maintain "${SETTING:-80}"
else
    echo 'Upgrade preserved the active native policy and original Apple recovery snapshot.'
fi
"$LEGACY/battery" status
printf '\nInstalled fixed-ceiling 0.1.1. Original Battery app and its icon are unchanged.\n'
printf 'Reopen it with: open -b co.palokaj.battery\n'
printf 'Keep Allow force-discharging OFF; ranges and advanced controls are intentionally unsupported.\n'
printf 'Rollback: bash "%s/rollback.command"\n' "$DIR"
