TGZ=${1:-/tmp/macos.tgz}   # the tarball you scp'd: a stale one silently builds old code
cd ~/work && rm -rf macos && tar xzf "$TGZ" && cd macos && ~/bin/xcodegen >/dev/null 2>&1
xcodebuild -scheme Battery -derivedDataPath build -destination "platform=macOS,arch=arm64" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build > /tmp/build.log 2>&1
grep -E "error:|\*\* BUILD" /tmp/build.log | sort -u | head -30
grep -q "BUILD SUCCEEDED" /tmp/build.log && { rm -rf ~/Applications/Battery.app; cp -R build/Build/Products/Debug/Battery.app ~/Applications/; }
