#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
[[ $EUID -eq 0 && $# -eq 1 ]] || exit 64
[[ $1 == --restore-upstream || $1 == --remove-cli ]] || exit 64
MODE=$1
ROOT=/Library/PrivilegedHelperTools/co.palokaj.battery.macos27
LEGACY=/usr/local/co.palokaj.battery
RULE=/private/etc/sudoers.d/battery
PLIST=/Library/LaunchDaemons/local.battery.macos27.plist
for d in /Library /Library/PrivilegedHelperTools "$ROOT" "$ROOT/backup" /usr /usr/local "$LEGACY" /private /private/etc /private/etc/sudoers.d; do
    [[ -d $d && ! -L $d && $(stat -f '%u' "$d") == 0 ]] || { echo "Unsafe path: $d" >&2; exit 1; }
    mode=$(stat -f '%Lp' "$d"); (( (8#$mode & 0022)==0 )) || exit 1
done
[[ -f $ROOT/backup/battery && ! -L $ROOT/backup/battery && -f $ROOT/backup/sudoers && ! -L $ROOT/backup/sudoers ]] || { echo 'Recovery files missing; nothing removed.' >&2; exit 1; }
/usr/bin/grep -Eq '^# BATTERY_MACOS27_(COMPAT |NATIVE_DISPATCH_BEGIN)' "$LEGACY/battery" || { echo 'CLI changed since this patch; refusing to overwrite it.' >&2; exit 1; }
# Failure retains the helper, service, and recovery snapshot for another retry.
"$ROOT/native-charge" stop
if /bin/launchctl print system/local.battery.macos27 >/dev/null 2>&1; then /bin/launchctl bootout system/local.battery.macos27; fi
if [[ $MODE == --restore-upstream ]]; then
    /usr/sbin/visudo -cf "$ROOT/backup/sudoers" >/dev/null
    /usr/bin/install -o root -g wheel -m 0755 "$ROOT/backup/battery" "$LEGACY/battery"
    /usr/bin/install -o root -g wheel -m 0440 "$ROOT/backup/sudoers" "$RULE"
    /usr/sbin/visudo -c >/dev/null
else
    /bin/rm -f "$RULE" "$LEGACY/battery" "$LEGACY/smc"
    # Remove only aliases that point to this installation, not unrelated tools.
    for f in battery smc; do
        if [[ -L /usr/local/bin/$f && $(readlink "/usr/local/bin/$f") == "$LEGACY/$f" ]]; then /bin/rm "/usr/local/bin/$f"; fi
    done
    /bin/rmdir "$LEGACY" 2>/dev/null || true
    /bin/rm -f /private/etc/paths.d/50-battery
fi
/bin/rm -f "$PLIST"
/bin/rm -rf "$ROOT"
echo 'Native backend removed; native preferences restored. Logs and recovery state retained.'
if [[ $MODE == --restore-upstream ]]; then echo 'Original upstream CLI restored. Its macOS 27 incompatibility is not repaired by rollback.';
else echo 'Battery CLI removed. The app bundle and user configuration were not deleted.'; fi
