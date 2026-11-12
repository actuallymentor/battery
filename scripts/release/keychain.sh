#!/bin/bash

#
# Creates or destroys the temporary CI keychain.
#
# Usage:
#   keychain.sh setup                imports the Developer ID identity and stores the notary API key
#   keychain.sh setup --no-notary    signing only, no notary credentials needed (local e2e builds)
#   keychain.sh cleanup              deletes the keychain and every decoded credential, safe to run twice
#
# Decoded secrets only ever exist in $SECRETS_DIR (mode 700) and are removed as soon as
# they are imported. Nothing in here prints a secret value.
#

source "$(dirname "$0")/lib.sh"

function cleanup() {

	# Deleting a keychain also removes it from the user search list
	if [[ -f "$KEYCHAIN" ]]; then
		security delete-keychain "$KEYCHAIN" || true
	fi

	rm -rf "$SECRETS_DIR"
	log "Temporary keychain and credentials removed"

}

function import_p12() {

	local name="$1" base64_value="$2" password="$3"
	local p12="$SECRETS_DIR/$name.p12"

	printf '%s' "$base64_value" | base64 --decode >"$p12"

	# Only Apple's signing tools may use the private keys without a prompt
	security import "$p12" -k "$KEYCHAIN" -f pkcs12 -P "$password" \
		-T /usr/bin/codesign -T /usr/bin/productsign -T /usr/bin/productbuild >/dev/null

	rm -f "$p12"

}

function import_apple_ca() {

	local name="$1" sha256="$2" url="$3" cer="$SECRETS_DIR/$1.cer"

	curl -fsSL -o "$cer" "$url"
	echo "$sha256  $cer" | shasum -a 256 -c - >/dev/null || fail "$name checksum mismatch"
	security import "$cer" -k "$KEYCHAIN" >/dev/null 2>&1 || true   # the .p12 may already carry it
	rm -f "$cer"

}

function setup() {

	local notary="$1"

	require_env CI_KEYCHAIN_PASSWORD DEVELOPER_ID_APPLICATION_P12_BASE64 DEVELOPER_ID_APPLICATION_P12_PASSWORD APPLE_TEAM_ID
	[[ $notary == 0 ]] || require_env NOTARY_API_KEY_P8_BASE64 NOTARY_API_KEY_ID NOTARY_API_ISSUER_ID

	[[ "$APPLE_TEAM_ID" == "$TEAM_ID" ]] || fail "APPLE_TEAM_ID does not match BATTERY_TEAM_ID in project.yml"

	# A half-finished setup must not leave credentials behind, EXIT also covers fail()
	trap 'cleanup' EXIT

	# Start from a clean slate in case of a re-run on the same machine
	cleanup >/dev/null
	mkdir -p "$SECRETS_DIR"
	chmod 700 "$SECRETS_DIR"
	umask 077

	# Create an unlocked keychain that relocks after 6 hours, longer than any release run
	security create-keychain -p "$CI_KEYCHAIN_PASSWORD" "$KEYCHAIN"
	security set-keychain-settings -lut 21600 "$KEYCHAIN"
	security unlock-keychain -p "$CI_KEYCHAIN_PASSWORD" "$KEYCHAIN"

	import_p12 application "$DEVELOPER_ID_APPLICATION_P12_BASE64" "$DEVELOPER_ID_APPLICATION_P12_PASSWORD"

	# codesign needs the whole chain inside the keychain it signs with (Developer ID G2 intermediate + Apple Root CA),
	# else: "unable to build chain", errSecInternalComponent. Import them AFTER the .p12: the other order breaks signing (observed on macOS 26)
	import_apple_ca DeveloperIDG2CA "$DEVELOPER_ID_G2_SHA256" https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
	import_apple_ca AppleRootCA "$APPLE_ROOT_SHA256" https://www.apple.com/appleca/AppleIncRootCertificate.cer

	# Allow codesign to use the keys non-interactively
	security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$CI_KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

	# Put the keychain first in the search list, keep the existing ones after it
	local existing
	existing=$(security list-keychains -d user | tr -d '"')
	# shellcheck disable=SC2086
	security list-keychains -d user -s "$KEYCHAIN" $existing

	# The identity must be present and valid before anything gets signed
	local identities
	identities=$(security find-identity -v "$KEYCHAIN")
	grep -qF "\"$APP_IDENTITY\"" <<<"$identities" || fail "Identity not found in keychain: $APP_IDENTITY"
	log "Imported signing identities"

	# Store the App Store Connect API key as a notarytool profile, then drop the key file
	if [[ $notary == 1 ]]; then
		local p8="$SECRETS_DIR/notary.p8"
		printf '%s' "$NOTARY_API_KEY_P8_BASE64" | base64 --decode >"$p8"
		xcrun notarytool store-credentials "$NOTARY_PROFILE" \
			--key "$p8" --key-id "$NOTARY_API_KEY_ID" --issuer "$NOTARY_API_ISSUER_ID" \
			--keychain "$KEYCHAIN" >/dev/null
		rm -f "$p8"
		log "Stored notarization credentials"
	fi

	trap - EXIT

}

case "${1:-}:${2:-}" in
	setup:) setup 1 ;;
	setup:--no-notary) setup 0 ;;
	cleanup:) cleanup ;;
	*) fail "Usage: $0 setup [--no-notary] | cleanup" ;;
esac
