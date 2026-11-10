#!/bin/bash
# Local: ship macos/ + scripts/ to the Mac's ~/e2e (the Mac builds and runs everything itself)
set -eu
cd "$(dirname "$0")/../.."
tar czf /tmp/e2e.tgz --exclude=.build --exclude='*.xcodeproj' macos scripts
babysit mac scp "${MAC:-ArjunMacbook}" /tmp/e2e.tgz mac:/tmp/e2e.tgz >/dev/null
babysit mac ssh "${MAC:-ArjunMacbook}" 'mkdir -p ~/e2e && cd ~/e2e && rm -rf macos/E2E/Sources macos/E2E/Tests scripts && tar xzf /tmp/e2e.tgz'
