#!/bin/bash

#
# Wraps the signed and stapled app in a .dmg (drag-to-Applications, Developer ID Application identity).
# No .pkg: nothing needs one yet, see git history if MDM/Homebrew ask for it.
#

source "$(dirname "$0")/lib.sh"

[[ -d "$APP_PATH" ]] || fail "No app at $APP_PATH, run build.sh and sign.sh first"

# Disk image with an Applications shortcut
staging="$WORK_DIR/dmg"
rm -rf "$staging" "$DMG_PATH"
mkdir -p "$staging"
ditto "$APP_PATH" "$staging/$APP_NAME.app"
ln -s /Applications "$staging/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$DMG_PATH"
rm -rf "$staging"

codesign --force --sign "$APP_IDENTITY" --keychain "$KEYCHAIN" --timestamp "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"
log "Built $(basename "$DMG_PATH")"
