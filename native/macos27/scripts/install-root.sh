#!/bin/bash
# SPDX-License-Identifier: MIT
# All persistent executable paths and their ancestors must be root protected.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
[[ $EUID -eq 0 && $# -eq 3 ]] || { echo 'Use install.command.' >&2; exit 64; }
BINARY=$1; SOURCE=$2; ACCOUNT=$3
ROOT=/Library/PrivilegedHelperTools/co.palokaj.battery.macos27
LEGACY=/usr/local/co.palokaj.battery
RULE=/private/etc/sudoers.d/battery
PLIST=/Library/LaunchDaemons/local.battery.macos27.plist
STATE=/private/var/db/co.palokaj.battery.macos27/state.plist
[[ $ACCOUNT =~ ^[A-Za-z_][A-Za-z0-9._-]*$ ]] || exit 64
/usr/bin/id "$ACCOUNT" >/dev/null
[[ $BINARY = /* && -f $BINARY && ! -L $BINARY && $SOURCE = /* && -d $SOURCE && ! -L $SOURCE ]] || exit 64
protected_dir() {
    [[ -d $1 && ! -L $1 && $(/usr/bin/stat -f '%u' "$1") == 0 ]] || { echo "Unsafe directory: $1" >&2; exit 1; }
    local mode; mode=$(/usr/bin/stat -f '%Lp' "$1")
    (( (8#$mode & 0022) == 0 )) || { echo "Writable directory: $1" >&2; exit 1; }
    if /bin/ls -lde "$1" | /usr/bin/grep -E '^[[:space:]]*[0-9]+:.* allow .*(write|add_file|add_subdirectory|delete|append|chown)' >/dev/null; then
        echo "Writable ACL on $1; refusing installation." >&2; exit 1
    fi
}
protected_file() {
    [[ -f $1 && ! -L $1 && $(/usr/bin/stat -f '%u' "$1") == 0 ]] || { echo "Unsafe file: $1" >&2; exit 1; }
    local mode; mode=$(/usr/bin/stat -f '%Lp' "$1")
    (( (8#$mode & 0022) == 0 )) || { echo "Writable file: $1" >&2; exit 1; }
    if /bin/ls -le "$1" | /usr/bin/grep -E '^[[:space:]]*[0-9]+:.* allow .*(write|append|delete|chown)' >/dev/null; then
        echo "Writable ACL on $1; refusing installation." >&2; exit 1
    fi
}
protected_dir /Library
if [[ ! -e /Library/PrivilegedHelperTools && ! -L /Library/PrivilegedHelperTools ]]; then
    /bin/mkdir /Library/PrivilegedHelperTools; /bin/chmod 0755 /Library/PrivilegedHelperTools
fi
for d in /Library /Library/PrivilegedHelperTools /Library/LaunchDaemons /usr /usr/local "$LEGACY" /private /private/etc /private/etc/sudoers.d; do protected_dir "$d"; done
for f in "$LEGACY/battery" "$LEGACY/smc" "$RULE"; do protected_file "$f"; done
/usr/sbin/visudo -c >/dev/null
UPGRADE=0
if [[ -e $ROOT || -L $ROOT ]]; then
    protected_dir "$ROOT"; protected_dir "$ROOT/backup"
    for f in "$ROOT/native-charge" "$ROOT/backup/battery" "$ROOT/backup/sudoers" "$PLIST"; do protected_file "$f"; done
    /usr/bin/grep -Eq '^# BATTERY_MACOS27_(COMPAT |NATIVE_DISPATCH_BEGIN)' "$LEGACY/battery" || { echo 'An unknown installation replaced the native dispatcher; refusing.' >&2; exit 1; }
    UPGRADE=1
else
    [[ ! -e $PLIST && ! -L $PLIST ]] || { echo 'Unexpected launchd plist exists.' >&2; exit 1; }
    /usr/bin/grep -q '^BATTERY_CLI_VERSION="v1.3.4"' "$LEGACY/battery" || {
        echo 'Unrecognized upstream CLI; expected v1.3.4. No replacement performed.' >&2; exit 1;
    }
    /bin/mkdir "$ROOT"; /bin/chmod 0755 "$ROOT"
    /bin/mkdir "$ROOT/backup"; /bin/chmod 0700 "$ROOT/backup"
    /bin/cp -p "$LEGACY/battery" "$ROOT/backup/battery"
    /bin/cp -p "$RULE" "$ROOT/backup/sudoers"
fi
WORK=$(/usr/bin/mktemp -d "$ROOT/.install.XXXXXX")
/bin/chmod 0700 "$WORK"
# Snapshot active files before replacing anything. No state mutation in probe.
/bin/cp -p "$LEGACY/battery" "$WORK/previous-battery"
/bin/cp -p "$RULE" "$WORK/previous-sudoers"
for f in native-charge battery-native.sh uninstall-root.sh rollback-root.sh active; do
    [[ ! -e $ROOT/$f ]] || /bin/cp -p "$ROOT/$f" "$WORK/$f"
done
[[ ! -f $PLIST ]] || /bin/cp -p "$PLIST" "$WORK/previous-plist"
committed=0
cleanup() {
    if [[ $committed -eq 0 ]]; then
        echo 'Install failed; restoring previous executable and authorization files.' >&2
        /bin/launchctl bootout system/local.battery.macos27 >/dev/null 2>&1 || true
        /usr/bin/install -o root -g wheel -m 0755 "$WORK/previous-battery" "$LEGACY/battery"
        /usr/bin/install -o root -g wheel -m 0440 "$WORK/previous-sudoers" "$RULE"
        if [[ $UPGRADE -eq 1 ]]; then
            for f in native-charge battery-native.sh uninstall-root.sh rollback-root.sh active; do
                if [[ -f $WORK/$f ]]; then /bin/cp -p "$WORK/$f" "$ROOT/$f";
                else /bin/rm -f "$ROOT/$f"; fi
            done
            /bin/cp -p "$WORK/previous-plist" "$PLIST"
            /bin/launchctl bootstrap system "$PLIST" >/dev/null 2>&1 || true
        else
            /bin/rm -f "$PLIST"
        fi
    fi
    /bin/rm -rf "$WORK"
    if [[ $committed -eq 0 && $UPGRADE -eq 0 ]]; then /bin/rm -rf "$ROOT"; fi
}
trap cleanup EXIT
if /bin/launchctl print system/local.battery.macos27 >/dev/null 2>&1; then /bin/launchctl bootout system/local.battery.macos27; fi
if [[ -e $STATE ]]; then
    for d in /private/var /private/var/db /private/var/db/co.palokaj.battery.macos27; do protected_dir "$d"; done
    protected_file "$STATE"
    if [[ ! -e $ROOT/backup/state-before-fixed-0.1.1.plist ]]; then
        /bin/cp -p "$STATE" "$ROOT/backup/state-before-fixed-0.1.1.plist"
    fi
fi
# Insert a small dispatch hook into the exact original backed-up CLI. The rest
# of the upstream script is kept, rather than replaced with a standalone wrapper.
ORIGINAL="$ROOT/backup/battery"
if /usr/bin/grep -q '^# BATTERY_MACOS27_NATIVE_DISPATCH_BEGIN' "$ORIGINAL"; then
    /bin/cp "$ORIGINAL" "$WORK/battery"
else
    /usr/bin/awk -v snippet="$SOURCE/src/dispatch-snippet.sh" '
        { print }
        $0 == "PATH=/usr/bin:/bin:/usr/sbin:/sbin" && !inserted {
            print "";
            while ((getline line < snippet)>0) print line;
            close(snippet); inserted=1
        }
        END { if (!inserted) exit 1 }
    ' "$ORIGINAL" > "$WORK/battery"
fi
/bin/bash -n "$WORK/battery"
/usr/bin/install -o root -g wheel -m 0755 "$BINARY" "$ROOT/native-charge"
/usr/bin/install -o root -g wheel -m 0755 "$SOURCE/src/battery-native.sh" "$ROOT/battery-native.sh"
/usr/bin/install -o root -g wheel -m 0755 "$SOURCE/scripts/uninstall-root.sh" "$ROOT/uninstall-root.sh"
# Old rollback entry remains usable after upgrading from 0.1.0.
printf '#!/bin/bash\nexec /bin/bash %s/uninstall-root.sh --restore-upstream\n' "$ROOT" > "$ROOT/rollback-root.sh"
/bin/chmod 0755 "$ROOT/rollback-root.sh"
/bin/mkdir -p "$ROOT/src"; /bin/chmod 0755 "$ROOT/src"
for f in native-charge.m policy.h; do /usr/bin/install -o root -g wheel -m 0644 "$SOURCE/src/$f" "$ROOT/src/$f"; done
cat > "$WORK/sudoers" <<RULES
# Opt-in Battery native backend. The helper validates every argument before use.
$ACCOUNT ALL=(root) NOPASSWD: $LEGACY/battery update_silent
$ACCOUNT ALL=(root) NOPASSWD: $LEGACY/battery update_silent is_enabled
$ACCOUNT ALL=(root) NOPASSWD: $ROOT/native-charge probe
$ACCOUNT ALL=(root) NOPASSWD: $ROOT/native-charge status
$ACCOUNT ALL=(root) NOPASSWD: $ROOT/native-charge status_csv
$ACCOUNT ALL=(root) NOPASSWD: $ROOT/native-charge diagnose
$ACCOUNT ALL=(root) NOPASSWD: $ROOT/native-charge stop
$ACCOUNT ALL=(root) NOPASSWD: $ROOT/native-charge recover
RULES
# Exact argument allow-list: no arbitrary high-level maintenance invocation.
for ((ceiling=1; ceiling<=100; ceiling++)); do
    printf '%s ALL=(root) NOPASSWD: %s/native-charge maintain %s\n' "$ACCOUNT" "$ROOT" "$ceiling" >> "$WORK/sudoers"
done
/bin/chmod 0440 "$WORK/sudoers"
/usr/sbin/visudo -cf "$WORK/sudoers" >/dev/null
/usr/bin/install -o root -g wheel -m 0440 "$WORK/sudoers" "$RULE"
/usr/sbin/visudo -c >/dev/null
cat > "$WORK/job.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.battery.macos27</string>
<key>ProgramArguments</key><array><string>/Library/PrivilegedHelperTools/co.palokaj.battery.macos27/native-charge</string><string>tick</string></array>
<key>RunAtLoad</key><true/>
<key>StartInterval</key><integer>15</integer>
<key>ProcessType</key><string>Background</string>
<key>StandardOutPath</key><string>/var/log/battery-macos27.log</string>
<key>StandardErrorPath</key><string>/var/log/battery-macos27.log</string>
<key>EnvironmentVariables</key><dict><key>HOME</key><string>/var/root</string><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
</dict></plist>
PLIST
/usr/bin/plutil -lint "$WORK/job.plist" >/dev/null
/usr/bin/install -o root -g wheel -m 0644 "$WORK/job.plist" "$PLIST"
# launchd must not follow a caller-controlled log path.
if [[ -e /var/log/battery-macos27.log || -L /var/log/battery-macos27.log ]]; then protected_file /var/log/battery-macos27.log;
else /usr/bin/touch /var/log/battery-macos27.log; fi
/usr/sbin/chown root:wheel /var/log/battery-macos27.log
/bin/chmod 0644 /var/log/battery-macos27.log
"$ROOT/native-charge" probe
"$ROOT/native-charge" check-state
printf '0.1.1-ceiling\n' > "$ROOT/active"; /bin/chmod 0644 "$ROOT/active"
/usr/bin/install -o root -g wheel -m 0755 "$WORK/battery" "$LEGACY/battery"
/bin/launchctl enable system/local.battery.macos27
/bin/launchctl bootstrap system "$PLIST"
committed=1
printf 'Installed original CLI plus opt-in native dispatch; preserved recovery backups.\n'
