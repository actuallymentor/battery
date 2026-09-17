#!/bin/bash
# SPDX-License-Identifier: MIT
# Build-only helpers. Bash 3.2 compatible. No sudo, install, power APIs, or
# global xcode-select changes. Source this file, then select once per build.
# Conda/Homebrew remain available to the caller; only compiler children receive
# a minimal environment. Respect an explicit DEVELOPER_DIR, not TOOLCHAINS or
# SDKROOT from an activated environment.

b27_select_apple_toolchain() {
    local developer compiler_version
    B27_BUILD_ENV=(/usr/bin/env -i "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
        "HOME=${HOME:?HOME must be set}" "TMPDIR=${TMPDIR:-/tmp}" "LC_ALL=C")
    developer=${DEVELOPER_DIR:-}
    if [[ -z $developer ]]; then
        developer=$("${B27_BUILD_ENV[@]}" /usr/bin/xcode-select --print-path) || {
            echo 'Cannot resolve Apple developer tools. Install/select Command Line Tools or Xcode.' >&2
            return 1
        }
    fi
    B27_BUILD_ENV+=("DEVELOPER_DIR=$developer")
    B27_APPLE_CC=$("${B27_BUILD_ENV[@]}" /usr/bin/xcrun --no-cache --sdk macosx --find clang) || return 1
    B27_APPLE_LD=$("${B27_BUILD_ENV[@]}" /usr/bin/xcrun --no-cache --sdk macosx --find ld) || return 1
    B27_APPLE_SDK=$("${B27_BUILD_ENV[@]}" /usr/bin/xcrun --no-cache --sdk macosx --show-sdk-path) || return 1
    [[ $B27_APPLE_CC == /* && -x $B27_APPLE_CC &&
       $B27_APPLE_LD == /*/ld && -x $B27_APPLE_LD &&
       $B27_APPLE_SDK == /* && -d $B27_APPLE_SDK ]] || {
        echo 'Apple compiler, linker, or SDK path is unavailable. No install attempted.' >&2
        return 1
    }
    compiler_version=$("${B27_BUILD_ENV[@]}" "$B27_APPLE_CC" --version) || return 1
    [[ $compiler_version == *'Apple clang'* ]] || {
        echo 'Selected compiler is not Apple clang; select an Apple Command Line Tools/Xcode installation.' >&2
        return 1
    }
    printf 'Apple developer directory: %s\nCompiler: %s\nLinker: %s\nSDK: %s\n' \
        "$developer" "$B27_APPLE_CC" "$B27_APPLE_LD" "$B27_APPLE_SDK"
    printf '%s\n' "$compiler_version"
}

b27_apple_clang() {
    [[ -n ${B27_APPLE_CC:-} && -n ${B27_APPLE_SDK:-} && -n ${B27_APPLE_LD:-} ]] || {
        echo 'Call b27_select_apple_toolchain before compilation.' >&2; return 1;
    }
    # -B gives this developer installation's ld priority, including when the
    # invoking shell has another ld/clang/cc in PATH. An explicit sysroot avoids
    # pairing Xcode's older linker with a newer separately installed CLT SDK.
    if [[ ${B27_BUILD_VERBOSE:-0} == 1 ]]; then
        "${B27_BUILD_ENV[@]}" "SDKROOT=$B27_APPLE_SDK" "$B27_APPLE_CC" \
            -isysroot "$B27_APPLE_SDK" -B "${B27_APPLE_LD%/*}/" -v "$@"
    else
        "${B27_BUILD_ENV[@]}" "SDKROOT=$B27_APPLE_SDK" "$B27_APPLE_CC" \
            -isysroot "$B27_APPLE_SDK" -B "${B27_APPLE_LD%/*}/" "$@"
    fi
}

b27_toolchain_preflight() {
    local folder=${1:?supply an existing temporary build directory}
    # Compile and link only. Do not execute this file or the native helper.
    printf 'int main(void) { return 0; }\n' > "$folder/toolchain-smoke.c"
    if ! b27_apple_clang -arch arm64 "$folder/toolchain-smoke.c" -o "$folder/toolchain-smoke"; then
        cat >&2 <<'MSG'
Apple toolchain preflight failed; no installation or battery-setting change occurred.
If the error still mentions arm64e.x1 / a malformed .tbd, the selected Apple
compiler/linker and SDK are still incompatible. Update Command Line Tools/Xcode
as one installation, or select an already installed matching developer directory.
Do not edit SDK .tbd files, disable protections, or bypass the test failure.
Rerun with B27_BUILD_VERBOSE=1 for compiler/linker diagnostics.
MSG
        return 1
    fi
    echo 'PASS: Apple compiler/linker/SDK can link an arm64 C program (not executed).'
}
