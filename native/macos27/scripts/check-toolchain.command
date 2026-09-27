#!/bin/bash
# Build diagnostics only. Never installs/runs the Battery backend or uses sudo.
set -euo pipefail
[[ $(/usr/bin/uname -s) == Darwin ]] || { echo 'Run this check on macOS.' >&2; exit 1; }
DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
printf 'Tools visible in your current shell (for comparison):\n'
type -a cc clang ld 2>/dev/null || true
printf '\nSelected clean Apple toolchain:\n'
source "$DIR/apple-toolchain.sh"
b27_select_apple_toolchain
BUILD=$(/usr/bin/mktemp -d)
trap '/bin/rm -rf "$BUILD"' EXIT
b27_toolchain_preflight "$BUILD"
