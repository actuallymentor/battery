#!/bin/bash

#
# Writes appcast.xml for the Sparkle updater: one item, the release being built.
# Sparkle reads SUFeedURL (Info.plist), currently releases/latest/download/appcast.xml, so this file is uploaded
# as a release asset by publish.sh. Note: GitHub's "latest" skips drafts and pre-releases (see .notes/HUMAN.md).
#

source "$(dirname "$0")/lib.sh"

attrs_file="$DMG_PATH.sparkle"
[[ -f "$attrs_file" ]] || fail "No Sparkle signature at $attrs_file, run sparkle.sh sign first"
[[ -f "$APP_PATH/Contents/Info.plist" ]] || fail "No app at $APP_PATH"

# Sparkle compares sparkle:version with the app's CFBundleVersion, read it from the built app instead of trusting a variable
build=$(plutil -extract CFBundleVersion raw "$APP_PATH/Contents/Info.plist")
url="https://github.com/actuallymentor/battery/releases/download/$TAG/$(basename "$DMG_PATH")"
min_os=$(plutil -extract LSMinimumSystemVersion raw "$APP_PATH/Contents/Info.plist")

cat >"$OUT_DIR/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
	<channel>
		<title>Battery</title>
		<item>
			<title>Version $VERSION</title>
			<sparkle:version>$build</sparkle:version>
			<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
			<sparkle:minimumSystemVersion>$min_os</sparkle:minimumSystemVersion>
			<enclosure url="$url" type="application/octet-stream" $(cat "$attrs_file") />
		</item>
	</channel>
</rss>
EOF

log "Wrote appcast.xml for $VERSION (build $build)"
