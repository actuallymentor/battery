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

# Every SMAppService daemon plist must point at an executable inside the bundle
for plist in "$APP_PATH"/Contents/Library/LaunchDaemons/*.plist; do
	program=$(plutil -extract BundleProgram raw "$plist") || fail "No BundleProgram in $plist"
	[[ -x "$APP_PATH/$program" ]] || fail "Daemon executable $program from $(basename "$plist") not found"
done

log "Signed $APP_NAME.app and all nested components"
