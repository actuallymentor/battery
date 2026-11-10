#!/bin/bash
# ON the Mac: build the tree in ~/e2e with the real Developer ID signing pipeline (no notarization), replace
# /Applications/Battery.app, then launch it so it restarts the helper. Credentials are copied in by e2e.sh and
# removed again here, success or not.
set -eu
export PATH=$HOME/bin:$PATH
cd ~/e2e
trap 'rm -rf ~/e2e/sec' EXIT

rm -rf work && mkdir work && rsync -a --exclude .build --exclude '*.xcodeproj' macos scripts work/ && cd work
set -a; . ~/e2e/sec/.env.release; set +a
export DEVELOPER_ID_APPLICATION_P12_BASE64=$(base64 < ~/e2e/sec/developer-id.p12 | tr -d '\n')
export NOTARY_API_KEY_P8_BASE64=$(base64 < ~/e2e/sec/AuthKey.p8 | tr -d '\n')
export TAG="${E2E_TAG:-v2.0.0-beta.2}" BUILD_NUMBER="$(date +%s)"
R=scripts/release

$R/build.sh > ~/e2e/build.log 2>&1
$R/keychain.sh setup >> ~/e2e/build.log 2>&1
trap '$R/keychain.sh cleanup >> ~/e2e/build.log 2>&1 || true; rm -rf ~/e2e/sec' EXIT
$R/sign.sh >> ~/e2e/build.log 2>&1

pkill -x Battery 2>/dev/null || true
rm -rf /Applications/Battery.app
ditto .release/battery-release/out/Battery.app /Applications/Battery.app
codesign --verify --deep --strict /Applications/Battery.app
echo "installed $(/Applications/Battery.app/Contents/Helpers/battery version 2>/dev/null) build $BUILD_NUMBER"
