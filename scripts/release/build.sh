#!/bin/bash

#
# Archives a Release build of the Swift app, without any Developer ID credentials.
#
# Xcode signs ad-hoc here so every nested component keeps its entitlements,
# sign.sh then re-signs the whole bundle inside-out with the Developer ID identity.
#

source "$(dirname "$0")/lib.sh"

# The project is generated (gitignored): build it from project.yml
if [[ ! -d "$XCODE_PROJECT" && -f "$(dirname "$XCODE_PROJECT")/project.yml" ]]; then
	command -v xcodegen >/dev/null || brew install xcodegen
	( cd "$(dirname "$XCODE_PROJECT")" && xcodegen generate )
fi

[[ -d "$XCODE_PROJECT" ]] || fail "Xcode project not found at $XCODE_PROJECT, set XCODE_PROJECT to its location"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

archive="$WORK_DIR/$APP_NAME.xcarchive"
rm -rf "$archive"

log "Archiving $XCODE_SCHEME $VERSION"
xcodebuild archive \
	-project "$XCODE_PROJECT" \
	-scheme "$XCODE_SCHEME" \
	-configuration Release \
	-destination 'generic/platform=macOS' \
	-archivePath "$archive" \
	ARCHS=arm64 \
	MARKETING_VERSION="$VERSION" \
	CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
	ONLY_ACTIVE_ARCH=NO \
	CODE_SIGN_STYLE=Manual \
	CODE_SIGN_IDENTITY=- \
	DEVELOPMENT_TEAM= \
	ENABLE_HARDENED_RUNTIME=YES \
	CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

ditto "$archive/Products/Applications/$APP_NAME.app" "$APP_PATH"
info_plist="$APP_PATH/Contents/Info.plist"

# The tag is the source of truth, a mismatch would break Sparkle's version comparison
app_version=$(plutil -extract CFBundleShortVersionString raw "$info_plist")
[[ "$app_version" == "$VERSION" ]] || fail "App version $app_version does not match tag $TAG"

# The built app must carry the key project.yml declares (a stale .xcodeproj would not), a wrong SUPublicEDKey silently breaks every future update
current_key=$(plutil -extract SUPublicEDKey raw "$info_plist" 2>/dev/null || true)
[[ "$current_key" == "$SPARKLE_PUBLIC_ED_KEY" ]] || fail "Info.plist SUPublicEDKey '$current_key' does not match project.yml"
plutil -extract SUFeedURL raw "$info_plist" >/dev/null 2>&1 || log "⚠️ Info.plist has no SUFeedURL, Sparkle will not find updates"

# The SMAppService root daemon must ship inside the bundle
compgen -G "$APP_PATH/Contents/Library/LaunchDaemons/*.plist" >/dev/null ||
	fail "No LaunchDaemon plist in $APP_NAME.app/Contents/Library/LaunchDaemons"

log "Built $APP_PATH"
