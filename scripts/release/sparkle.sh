#!/bin/bash

#
# Signs Sparkle updates with the EdDSA private key.
#
# Usage:
#   sparkle.sh check   fail fast: proves SPARKLE_ED_PRIVATE_KEY matches SPARKLE_PUBLIC_ED_KEY
#   sparkle.sh sign    signs the final, stapled .dmg and writes <dmg>.sparkle for the appcast
#
# The private key is piped to sign_update on stdin and never written to disk.
# Signatures are verified against the public key that ships in Info.plist, with OpenSSL 3,
# so a key mismatch fails the release instead of breaking updates for every user.
#

source "$(dirname "$0")/lib.sh"

require_env SPARKLE_ED_PRIVATE_KEY

sparkle_dir="$WORK_DIR/sparkle-$SPARKLE_VERSION"
sign_update="$sparkle_dir/bin/sign_update"

# Download the pinned Sparkle release and check its checksum before running anything from it
function install_sparkle() {

	[[ -x "$sign_update" ]] && return

	local archive="$WORK_DIR/sparkle-$SPARKLE_VERSION.tar.xz"
	mkdir -p "$WORK_DIR"
	curl -fsSL -o "$archive" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
	echo "$SPARKLE_SHA256  $archive" | shasum -a 256 -c - >/dev/null || fail "Sparkle $SPARKLE_VERSION checksum mismatch"

	mkdir -p "$sparkle_dir"
	tar -xJf "$archive" -C "$sparkle_dir"
	rm -f "$archive"

}

# Ed25519 needs OpenSSL 3, macOS ships LibreSSL, GitHub runners have openssl@3 from Homebrew
function find_openssl() {
	local candidate
	for candidate in "$(brew --prefix openssl@3 2>/dev/null)/bin/openssl" openssl; do
		if "$candidate" version 2>/dev/null | grep -q '^OpenSSL 3'; then
			echo "$candidate"
			return
		fi
	done
	fail "OpenSSL 3 not found, install it with: brew install openssl@3"
}

# Prints the base64 EdDSA signature of a file
function sign_file() {
	printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$sign_update" --ed-key-file - -p "$1"
}

# Verifies a base64 signature over a file against SPARKLE_PUBLIC_ED_KEY
function verify_signature() {

	local file="$1" signature="$2" openssl
	openssl=$(find_openssl)

	local public_der="$WORK_DIR/sparkle-public.der" signature_bin="$WORK_DIR/sparkle-signature.bin"

	# Wrap the raw 32 byte key in an Ed25519 SubjectPublicKeyInfo header
	{
		printf '\x30\x2a\x30\x05\x06\x03\x2b\x65\x70\x03\x21\x00'
		printf '%s' "$SPARKLE_PUBLIC_ED_KEY" | base64 --decode
	} >"$public_der"
	printf '%s' "$signature" | base64 --decode >"$signature_bin"

	local verified=0
	"$openssl" pkeyutl -verify -pubin -inkey "$public_der" -keyform DER \
		-rawin -in "$file" -sigfile "$signature_bin" >/dev/null 2>&1 || verified=$?

	rm -f "$public_der" "$signature_bin"
	return $verified

}

function check() {

	local probe="$WORK_DIR/sparkle-probe.txt"
	echo "battery $TAG sparkle key probe" >"$probe"

	local signature
	signature=$(sign_file "$probe")
	verify_signature "$probe" "$signature" || fail "SPARKLE_ED_PRIVATE_KEY does not match SUPublicEDKey $SPARKLE_PUBLIC_ED_KEY"

	rm -f "$probe"
	log "Sparkle private key matches SUPublicEDKey"

}

function sign() {

	[[ -f "$DMG_PATH" ]] || fail "No disk image at $DMG_PATH, run package.sh first"

	# Stapling rewrites the image, so this must run on the final file
	xcrun stapler validate "$DMG_PATH" >/dev/null || fail "Sign the update only after notarize.sh stapled it"

	local signature length
	signature=$(sign_file "$DMG_PATH")
	verify_signature "$DMG_PATH" "$signature" || fail "Sparkle signature of $(basename "$DMG_PATH") does not verify"
	length=$(stat -f %z "$DMG_PATH")

	# Attributes for the appcast <enclosure>
	echo "sparkle:edSignature=\"$signature\" length=\"$length\"" >"$DMG_PATH.sparkle"
	log "Signed Sparkle update $(basename "$DMG_PATH")"

}

install_sparkle

case "${1:-}" in
	check) check ;;
	sign) sign ;;
	*) fail "Usage: $0 check|sign" ;;
esac
