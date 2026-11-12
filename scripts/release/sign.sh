#!/bin/bash

#
# Signs the app bundle inside-out with the Developer ID Application identity.
#
# Every nested Mach-O and bundle (CLI, SMAppService daemon, Sparkle's XPC services,
# Autoupdate, Updater.app, frameworks) is signed deepest-first. `codesign --deep` is
# avoided on purpose, it drops nested entitlements, see Sparkle's sandboxing docs.
#

source "$(dirname "$0")/lib.sh"

[[ -d "$APP_PATH" ]] || fail "No app at $APP_PATH, run build.sh first"

function codesign_item() {
	# Entitlements come from Xcode's ad-hoc signature, the designated requirement is
	# deliberately regenerated so it pins our team instead of an ad-hoc cdhash
	codesign --force --sign "$APP_IDENTITY" --keychain "$KEYCHAIN" \
		--timestamp --options runtime --preserve-metadata=entitlements "$1"
}

# List signable items: bundles plus loose Mach-O files, symlinks excluded
function signable_items() {
	find "$APP_PATH" -mindepth 1 -type d \( -name '*.app' -o -name '*.xpc' -o -name '*.framework' \
		-o -name '*.appex' -o -name '*.bundle' -o -name '*.systemextension' \) -print
	find "$APP_PATH" -type f -print | while read -r file; do
		if [[ "$(file -b "$file")" == Mach-O* ]]; then echo "$file"; fi
	done
}

# Deepest paths first, so every bundle is sealed after its contents
items=$(signable_items | awk -F/ '{ print NF "\t" $0 }' | sort -rn -k1,1 | cut -f2-)

while read -r item; do
	[[ -n "$item" ]] || continue
	echo "  ✍️  ${item#"$OUT_DIR"/}"
	codesign_item "$item"
done <<<"$items"

codesign_item "$APP_PATH"

## ###############
## Verification
## ###############

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# Each component, plus the app itself, must carry our team, the hardened runtime, and no debug entitlement
all_items="$items"$'\n'"$APP_PATH"
while read -r item; do
	[[ -n "$item" ]] || continue
	details=$(codesign -dv --verbose=2 "$item" 2>&1)
	grep -q "^TeamIdentifier=$TEAM_ID$" <<<"$details" || fail "Wrong or missing team: $item"
	grep -q "flags=.*runtime" <<<"$details" || fail "Hardened runtime missing: $item"
	entitlements=$(codesign -d --entitlements - --xml "$item" 2>/dev/null || true)
	if grep -q "get-task-allow" <<<"$entitlements"; then
		fail "Debug entitlement com.apple.security.get-task-allow present: $item"
	fi
done <<<"$all_items"

## ###############
## Identity: the root daemon (Daemon/main.swift `requirement`) only accepts callers signed by the team in its own
## Info.plist with the identifiers derived from its mach name. Debug builds skip that check, so this is the only
## place a drift between project.yml, the daemon plist and the signatures shows up before users hit it.
## ###############

cli="$APP_PATH/Contents/Helpers/battery"
daemon="$APP_PATH/Contents/MacOS/batteryd"

# A key from a bundle's Info.plist, or from the __info_plist section of a bare Mach-O (CLI, daemon)
function info_key() {
	local item="$1" key="$2"
	if [[ -d "$item" ]]; then plutil -extract "$key" raw "$item/Contents/Info.plist"
	else otool -X -P "$item" | sed -n '/<?xml/,/<\/plist>/p' | plutil -extract "$key" raw -o - -
	fi
}

function assert_identifier() {
	local item="$1" expected="$2"
	[[ -e "$item" ]] || fail "Missing $item"
	local details   # captured first: `grep -q` closing the pipe early would fail the pipeline under pipefail
	details=$(codesign -dv "$item" 2>&1)
	grep -q "^Identifier=$expected$" <<<"$details" || fail "Wrong code-signing identifier on ${item#"$OUT_DIR"/}, expected $expected"
}

app_id=$(info_key "$APP_PATH" CFBundleIdentifier)
daemon_id=$(info_key "$daemon" CFBundleIdentifier)
daemon_team=$(info_key "$daemon" BatteryTeamID)
[[ -n "$app_id" && -n "$daemon_id" ]] || fail "Could not read bundle identifiers from the built binaries"

# What the daemon derives at runtime must hold: <app>.daemon, <app>.cli, and the team it was built with is ours
[[ "$daemon_id" == "$app_id.daemon" ]] || fail "Daemon identifier $daemon_id is not $app_id.daemon"
[[ "$daemon_team" == "$TEAM_ID" ]] || fail "Daemon Info.plist BatteryTeamID '$daemon_team' is not $TEAM_ID (BATTERY_TEAM_ID missing from the build?)"
assert_identifier "$APP_PATH" "$app_id"
assert_identifier "$cli" "$app_id.cli"
assert_identifier "$daemon" "$daemon_id"
[[ "$(info_key "$cli" CFBundleIdentifier)" == "$app_id.cli" ]] || fail "CLI Info.plist identifier is not $app_id.cli"

# The same requirement the daemon enforces must verify for the app and the CLI
for client in "$APP_PATH" "$cli"; do
	codesign --verify -R="anchor apple generic and certificate leaf[subject.OU] = \"$daemon_team\" and ( identifier \"$app_id\" or identifier \"$app_id.cli\" )" "$client" ||
		fail "Daemon caller requirement does not verify for ${client#"$OUT_DIR"/}"
done

# The launchd plist (named after the daemon id, the app registers it by file name) binds Label and the XPC mach name
# to the daemon id, on behalf of the app. Dotted keys can't go through plutil key paths, hence the xml greps.
daemon_plist="$APP_PATH/Contents/Library/LaunchDaemons/$daemon_id.plist"
[[ -f "$daemon_plist" ]] || fail "Missing $daemon_id.plist in the bundle"
[[ "$(plutil -extract Label raw "$daemon_plist")" == "$daemon_id" ]] || fail "Daemon plist Label is not $daemon_id"
mach_services=$(plutil -extract MachServices xml1 -o - "$daemon_plist")
grep -qF "<key>$daemon_id</key>" <<<"$mach_services" || fail "Daemon plist MachServices lacks $daemon_id"
associated=$(plutil -extract AssociatedBundleIdentifiers xml1 -o - "$daemon_plist")
grep -qF "<string>$app_id</string>" <<<"$associated" || fail "Daemon plist AssociatedBundleIdentifiers lacks $app_id"
grep -qxF "let batteryDaemonName = \"$daemon_id\"" "$REPO_ROOT/macos/Shared/BatteryXPC.swift" || fail "Shared/BatteryXPC.swift batteryDaemonName is not $daemon_id"

# Every SMAppService daemon plist must point at an executable inside the bundle
for plist in "$APP_PATH"/Contents/Library/LaunchDaemons/*.plist; do
	program=$(plutil -extract BundleProgram raw "$plist") || fail "No BundleProgram in $plist"
	[[ -x "$APP_PATH/$program" ]] || fail "Daemon executable $program from $(basename "$plist") not found"
done

log "Signed $APP_NAME.app and all nested components"
