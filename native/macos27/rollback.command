#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
[[ $(uname -s) == Darwin && $EUID -ne 0 ]] || { echo 'Run on macOS without sudo.' >&2; exit 1; }
if /usr/bin/pgrep -f '/[Bb]attery.app/Contents/MacOS/' >/dev/null 2>&1; then echo 'Quit Battery before rollback.' >&2; exit 1; fi
ROOT=/Library/PrivilegedHelperTools/co.palokaj.battery.macos27
[[ -f $ROOT/uninstall-root.sh && ! -L $ROOT/uninstall-root.sh ]] || { echo 'The opt-in native backend is not installed.' >&2; exit 1; }
/usr/bin/sudo /bin/bash "$ROOT/uninstall-root.sh" --restore-upstream
# Do not restart the original, incompatible legacy worker.
if [[ -f $HOME/.battery/macos27-user-backup.path ]]; then
    IFS= read -r BACKUP < "$HOME/.battery/macos27-user-backup.path" || true
    case ${BACKUP:-} in
        "$HOME/.battery/macos27-user-backup-"*)
            if [[ -f $BACKUP/battery.plist && ! -e $HOME/Library/LaunchAgents/battery.plist ]]; then
                /bin/mkdir -p "$HOME/Library/LaunchAgents"
                /bin/cp "$BACKUP/battery.plist" "$HOME/Library/LaunchAgents/battery.plist"
            fi ;;
    esac
fi
echo 'Rollback complete. Existing percentage/range file retained; old worker not restarted.'
