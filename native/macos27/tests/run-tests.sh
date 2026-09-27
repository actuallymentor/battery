#!/bin/bash
# SPDX-License-Identifier: MIT
# Compile tests only; never installs or executes the native backend.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
if [[ $(uname -s) == Darwin ]]; then
    source scripts/apple-toolchain.sh
    b27_select_apple_toolchain
    b27_toolchain_preflight "$BUILD"
    echo 'Building portable policy tests with the selected Apple toolchain...'
    b27_apple_clang -arch arm64 -std=c11 -Wall -Wextra -Werror -fsanitize=undefined,address \
        tests/test_policy.c -o "$BUILD/test-policy"
    "${B27_BUILD_ENV[@]}" "$BUILD/test-policy"
else
    cc -std=c11 -Wall -Wextra -Werror -fsanitize=undefined,address tests/test_policy.c -o "$BUILD/test-policy"
    "$BUILD/test-policy"
fi
for f in install.command rollback.command scripts/*.sh scripts/*.command src/*.sh; do bash -n "$f"; done
[[ ! -f publish.command ]] || bash -n publish.command
python3 -m unittest discover -s tests -p 'test_*.py' -v
if [[ $(uname -s) == Darwin ]]; then
    b27_apple_clang -arch arm64 -std=c11 -fobjc-arc -O2 -Wall -Wextra -Werror \
        -framework Foundation -framework IOKit src/native-charge.m -o "$BUILD/native-charge"
    echo 'PASS: Objective-C native compilation on this Mac. Native binary NOT executed.'
    b27_apple_clang -arch arm64 -std=c11 -fobjc-arc -Wall -Wextra -Werror -fsanitize=address,undefined \
        -framework Foundation tests/test_native_policy.m -o "$BUILD/test-native-policy"
    "${B27_BUILD_ENV[@]}" "$BUILD/test-native-policy"
else
    echo 'SKIP: native Objective-C compilation needs the macOS SDK.'
fi
