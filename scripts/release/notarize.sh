#!/bin/bash

#
# Notarizes and staples a signed artifact, then checks it with Gatekeeper.
#
# Usage: notarize.sh app|pkg|dmg
#
# Apps are zipped for submission and the ticket is stapled to the .app itself.
#

source "$(dirname "$0")/lib.sh"

case "${1:-}" in
	app) target="$APP_PATH" ;;
	pkg) target="$PKG_PATH" ;;
	dmg) target="$DMG_PATH" ;;
	*) fail "Usage: $0 app|pkg|dmg" ;;
esac
[[ -e "$target" ]] || fail "Nothing to notarize at $target"

# notarytool only accepts zip, pkg and dmg uploads
submission="$target"
if [[ "$target" == *.app ]]; then
	submission="$WORK_DIR/$(basename "$target").zip"
	ditto -c -k --keepParent "$target" "$submission"
fi

log "Notarizing $(basename "$target"), this usually takes a few minutes"
result=$(xcrun notarytool submit "$submission" \
	--keychain-profile "$NOTARY_PROFILE" --keychain "$KEYCHAIN" \
	--wait --timeout 1h --output-format json) || true

# Tolerate non-JSON output, e.g. a network error, so the failure branch can print it
submission_id=$(jq -r '.id // empty' <<<"$result" 2>/dev/null || true)
status=$(jq -r '.status // empty' <<<"$result" 2>/dev/null || true)

# Print Apple's log on rejection, it lists every offending file
if [[ "$status" != "Accepted" ]]; then
	echo "$result" >&2
	if [[ -n "$submission_id" ]]; then
		xcrun notarytool log "$submission_id" --keychain-profile "$NOTARY_PROFILE" --keychain "$KEYCHAIN" >&2 || true
	fi
	fail "Notarization of $(basename "$target") ended with status '${status:-unknown}'"
fi

[[ "$submission" == "$target" ]] || rm -f "$submission"

xcrun stapler staple "$target"
xcrun stapler validate "$target"

# Gatekeeper must accept the artifact the way a user would open it
case "$target" in
	*.app) spctl --assess --type execute --verbose=2 "$target" ;;
	*.pkg) spctl --assess --type install --verbose=2 "$target" ;;
	*.dmg) spctl --assess --type open --context context:primary-signature --verbose=2 "$target" ;;
esac

log "Notarized and stapled $(basename "$target") ($submission_id)"
