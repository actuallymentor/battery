#!/bin/bash

#
# Shared configuration and helpers for the macOS release pipeline.
# Sourced by every script in this folder, never executed directly.
#
# 📐 Project contract (override through the environment if the Swift project moves):
# - XCODE_PROJECT / XCODE_SCHEME archive a Release build of $APP_NAME.app
# - The SMAppService root daemon plist lives in $APP_NAME.app/Contents/Library/LaunchDaemons
# - The CLI, daemon and Sparkle components are nested somewhere inside $APP_NAME.app
#
# ‼️ Never enable `set -x` in these scripts, several steps handle secrets.
#

# Variables below are consumed by the scripts that source this file
# shellcheck disable=SC2034

set -Eeuo pipefail

# Project layout
XCODE_PROJECT="${XCODE_PROJECT:-macos/Battery.xcodeproj}"
XCODE_SCHEME="${XCODE_SCHEME:-Battery}"
APP_NAME="${APP_NAME:-Battery}"

# Apple signing identities, see the "release" GitHub environment
TEAM_ID="CAWM399GFD"
APP_IDENTITY="Developer ID Application: Mentor Palokaj ($TEAM_ID)"
INSTALLER_IDENTITY="Developer ID Installer: MMOH (Netherlands) ($TEAM_ID)"

# Sparkle, the public key is baked into Info.plist as SUPublicEDKey
SPARKLE_PUBLIC_ED_KEY="xmO49bUIPl43rec5rtC1NoTg5LAFEnVwqnToYuz+NZ0="
SPARKLE_VERSION="2.10.1"
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"

# Version and artifact names follow the electron-builder convention: ${productName}-${version}-${os}-${arch}.${ext}
TAG="${TAG:-$(git describe --tags --exact-match 2>/dev/null || echo v0.0.0-local)}"
VERSION="${TAG#v}"
ARTIFACT_BASE="$APP_NAME-$VERSION-mac-arm64"

# Working folders, RUNNER_TEMP is wiped with the runner, .release/ is gitignored locally
WORK_DIR="${RUNNER_TEMP:-$PWD/.release}/battery-release"
OUT_DIR="$WORK_DIR/out"
SECRETS_DIR="$WORK_DIR/secrets"
APP_PATH="$OUT_DIR/$APP_NAME.app"
PKG_PATH="$OUT_DIR/$ARTIFACT_BASE.pkg"
DMG_PATH="$OUT_DIR/$ARTIFACT_BASE.dmg"

# Temporary keychain holding both Developer ID identities and the notary credentials
KEYCHAIN="$WORK_DIR/battery-release.keychain-db"
NOTARY_PROFILE="battery-notary"

function log() {
	echo -e "🔋 $*"
}

function fail() {
	echo "❌ $*" >&2
	exit 1
}

# Fail early with a readable message instead of an unbound variable error
function require_env() {
	local name
	for name in "$@"; do
		[[ -n "${!name:-}" ]] || fail "Missing environment variable $name"
	done
}
