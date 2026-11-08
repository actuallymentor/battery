#!/bin/bash

#
# Fails when the identity constants that must agree across files have drifted:
# team id, bundle ids, mach service name, daemon plist, Sparkle key and version.
# A drift here only shows up in production (Debug builds skip the XPC peer check), so CI guards it.
#

set -Eeuo pipefail
cd "$(dirname "$0")/.."

errors=0
function expect() {
	local what="$1" a="$2" b="$3"
	if [[ -z "$a" || "$a" != "$b" ]]; then echo "❌ $what: '$a' vs '$b'"; errors=$((errors + 1)); else echo "✅ $what: $a"; fi
}

yml=macos/project.yml
lib=scripts/release/lib.sh
plist=macos/Daemon/co.palokaj.battery.daemon.plist
xpc=macos/Shared/BatteryXPC.swift
daemon=macos/Daemon/main.swift

team_yml=$(sed -n 's/^ *DEVELOPMENT_TEAM: *\([A-Z0-9]\{10\}\).*/\1/p' "$yml" | head -1)
team_lib=$(sed -n 's/^TEAM_ID="\([A-Z0-9]*\)"/\1/p' "$lib")
team_daemon=$(sed -n 's/.*subject.OU\] = "\([A-Z0-9]*\)".*/\1/p' "$daemon" | head -1)
expect "team id (project.yml vs lib.sh)" "$team_yml" "$team_lib"
expect "team id (daemon requirement vs lib.sh)" "$team_daemon" "$team_lib"

service_xpc=$(sed -n 's/^let batteryDaemonName = "\(.*\)"/\1/p' "$xpc")
label=$(plutil -extract Label raw "$plist" 2>/dev/null || sed -n '/<key>Label<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$plist")
mach=$(sed -n '/<key>MachServices<\/key>/,/<\/dict>/{s/.*<key>\(co\.[^<]*\)<\/key>.*/\1/p;}' "$plist")
daemon_id_yml=$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *\(co\.palokaj\.battery\.daemon\)$/\1/p' "$yml")
expect "mach service (XPC constant vs plist Label)" "$service_xpc" "$label"
expect "mach service (plist MachServices vs Label)" "$mach" "$label"
expect "daemon bundle id vs mach service" "$daemon_id_yml" "$service_xpc"

app_id=$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *\(co\.palokaj\.battery\)$/\1/p' "$yml")
assoc=$(sed -n '/AssociatedBundleIdentifiers/,/<\/array>/{s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$plist")
expect "app bundle id (project.yml vs plist AssociatedBundleIdentifiers)" "$app_id" "$assoc"
grep -q "identifier \"$app_id\"" "$daemon" && echo "✅ daemon requirement allows $app_id" || { echo "❌ daemon requirement does not allow $app_id"; errors=$((errors + 1)); }
cli_id=$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER: *\(co\.palokaj\.battery\.cli\)$/\1/p' "$yml")
grep -q "identifier \"$cli_id\"" "$daemon" && echo "✅ daemon requirement allows $cli_id" || { echo "❌ daemon requirement does not allow $cli_id"; errors=$((errors + 1)); }

key_yml=$(sed -n 's/^ *SUPublicEDKey: *\(.*\)$/\1/p' "$yml")
key_lib=$(sed -n 's/^SPARKLE_PUBLIC_ED_KEY="\(.*\)"/\1/p' "$lib")
expect "Sparkle public key (project.yml vs lib.sh)" "$key_yml" "$key_lib"

sparkle_yml=$(sed -n 's/.*Sparkle: *{.*exactVersion: *\([0-9.]*\).*/\1/p' "$yml")
sparkle_lib=$(sed -n 's/^SPARKLE_VERSION="\(.*\)"/\1/p' "$lib")
expect "Sparkle version (project.yml vs lib.sh)" "$sparkle_yml" "$sparkle_lib"

plist_name=$(sed -n 's/.*plistName: *"\(.*\)".*/\1/p' macos/App/AppModel.swift | head -1)
expect "daemon plist file name (AppModel vs file)" "$plist_name" "$(basename "$plist")"

(( errors == 0 )) || { echo "$errors drift error(s)"; exit 1; }
echo "identity constants agree"
