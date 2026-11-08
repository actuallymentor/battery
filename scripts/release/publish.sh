#!/bin/bash

#
# Uploads the release artifacts to a DRAFT GitHub release for $TAG.
#
# Nothing becomes public here, the maintainer reviews and publishes the draft by hand.
# Tags with a suffix (v2.0.0-beta.1) are marked as pre-release.
#

source "$(dirname "$0")/lib.sh"

require_env GH_TOKEN

artifacts=("$PKG_PATH" "$DMG_PATH" "$DMG_PATH.sparkle")
for artifact in "${artifacts[@]}"; do
	[[ -f "$artifact" ]] || fail "Missing artifact $artifact"
done

# Checksums for people installing by hand
checksums="$OUT_DIR/SHA256SUMS"
(cd "$OUT_DIR" && shasum -a 256 "${artifacts[@]##*/}" >"$checksums")
artifacts+=("$checksums")

if gh release view "$TAG" >/dev/null 2>&1; then

	# Re-runs may only replace files on a draft, a published release is immutable
	[[ "$(gh release view "$TAG" --json isDraft --jq .isDraft)" == "true" ]] || fail "Release $TAG is already published"
	gh release upload "$TAG" "${artifacts[@]}" --clobber
	log "Replaced artifacts on draft release $TAG"

else

	flags=(--draft --verify-tag --generate-notes --title "$APP_NAME $VERSION")
	if [[ "$VERSION" == *-* ]]; then flags+=(--prerelease); fi

	gh release create "$TAG" "${artifacts[@]}" "${flags[@]}"
	log "Created draft release $TAG, review and publish it on GitHub"

fi
