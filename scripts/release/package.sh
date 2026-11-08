#!/bin/bash

#
# Wraps the signed and stapled app in a .pkg and a .dmg.
#
# - .pkg: installs into /Applications, signed with the Developer ID Installer identity
# - .dmg: drag-to-Applications image, signed with the Developer ID Application identity
#

source "$(dirname "$0")/lib.sh"

[[ -d "$APP_PATH" ]] || fail "No app at $APP_PATH, run build.sh and sign.sh first"

# Installer package
rm -f "$PKG_PATH"
productbuild --component "$APP_PATH" /Applications \
	--sign "$INSTALLER_IDENTITY" --keychain "$KEYCHAIN" --timestamp \
	"$PKG_PATH"
pkgutil --check-signature "$PKG_PATH"
log "Built $(basename "$PKG_PATH")"

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
