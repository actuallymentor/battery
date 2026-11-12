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

# Project layout
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_YML="$REPO_ROOT/macos/project.yml"
XCODE_PROJECT="${XCODE_PROJECT:-macos/Battery.xcodeproj}"
XCODE_SCHEME="${XCODE_SCHEME:-Battery}"
APP_NAME="${APP_NAME:-Battery}"

# Identity constants have ONE home, project.yml: the team the daemon pins its XPC callers to (through its own Info.plist),
# the Sparkle key baked into the app's Info.plist, and the Sparkle version Xcode links. Everything here reads them from there.
function project_setting() { sed -n "$1" "$PROJECT_YML" | head -1; }
TEAM_ID=$(project_setting 's/^ *BATTERY_TEAM_ID: *\([A-Z0-9]\{10\}\).*/\1/p')
SPARKLE_PUBLIC_ED_KEY=$(project_setting 's/^ *SUPublicEDKey: *\(.*\)$/\1/p')
SPARKLE_VERSION=$(project_setting 's/.*Sparkle: *{.*exactVersion: *\([0-9.]*\).*/\1/p')
[[ -n "$TEAM_ID" && -n "$SPARKLE_PUBLIC_ED_KEY" && -n "$SPARKLE_VERSION" ]] ||
	fail "Could not read DEVELOPMENT_TEAM / SUPublicEDKey / Sparkle exactVersion from $PROJECT_YML"

# Apple signing identities, see the "release" GitHub environment
APP_IDENTITY="Developer ID Application: Mentor Palokaj ($TEAM_ID)"
DEVELOPER_ID_G2_SHA256="f16cd3c54c7f83cea4bf1a3e6a0819c8aaa8e4a1528fd144715f350643d2df3a"   # Apple DeveloperIDG2CA.cer
APPLE_ROOT_SHA256="b0b1730ecbc7ff4505142c49f1295e6eda6bcaed7e2c68c5be91b5a11001f024"         # Apple AppleIncRootCertificate.cer

# Sparkle release archive, bump together with exactVersion in project.yml
SPARKLE_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"

# Version and artifact names follow the electron-builder convention: ${productName}-${version}-${os}-${arch}.${ext}
TAG="${TAG:-$(git describe --tags --exact-match 2>/dev/null || echo v0.0.0-local)}"
VERSION="${TAG#v}"

# Sparkle compares CFBundleVersion, so it must grow with every release (CI run number, 1 locally)
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
ARTIFACT_BASE="$APP_NAME-$VERSION-mac-arm64"

# Working folders, RUNNER_TEMP is wiped with the runner, .release/ is gitignored locally
WORK_DIR="${RUNNER_TEMP:-$PWD/.release}/battery-release"
OUT_DIR="$WORK_DIR/out"
SECRETS_DIR="$WORK_DIR/secrets"
APP_PATH="$OUT_DIR/$APP_NAME.app"
DMG_PATH="$OUT_DIR/$ARTIFACT_BASE.dmg"

# Temporary keychain holding both Developer ID identities and the notary credentials
KEYCHAIN="$WORK_DIR/battery-release.keychain-db"
NOTARY_PROFILE="battery-notary"
