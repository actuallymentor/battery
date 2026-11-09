# macOS release pipeline

Tag → build → Developer ID sign → notarize + staple → Sparkle sign → **draft** GitHub release.

## Cut a release

```bash
git tag v2.0.0-beta.1 && git push origin v2.0.0-beta.1   # suffix => pre-release
```

1. `.github/workflows/release.yml` starts on `v*` tags only
2. Approve the `release` environment deployment (required reviewer)
3. Review the draft release, then publish it by hand

## Scripts

| Script | Does | Secrets |
| --- | --- | --- |
| `build.sh` | `xcodebuild archive`, ad-hoc signed, enforces `SUPublicEDKey`, tag == `CFBundleShortVersionString` | none |
| `sparkle.sh check` | fail fast if the private EdDSA key ≠ `SUPublicEDKey` | `SPARKLE_ED_PRIVATE_KEY` |
| `keychain.sh setup` | temp keychain, app P12, notarytool profile | P12s, notary key, keychain pw |
| `sign.sh` | inside-out Developer ID signing, hardened runtime, verifies team/runtime/no `get-task-allow` | keychain |
| `notarize.sh app\|dmg` | submit, wait, staple, `spctl` | keychain |
| `package.sh` | `.dmg` (Application identity) | keychain |
| `sparkle.sh sign` | EdDSA-signs the stapled `.dmg` → `<dmg>.sparkle` enclosure attributes | `SPARKLE_ED_PRIVATE_KEY` |
| `publish.sh` | draft release + `SHA256SUMS`, re-runs only touch drafts | `GH_TOKEN` |
| `keychain.sh cleanup` | deletes keychain + decoded credentials, runs on failure too | none |

## Contract with the Swift project

Defaults in `lib.sh`, override via env:

- `XCODE_PROJECT=macos/Battery.xcodeproj`, `XCODE_SCHEME=Battery`, product `Battery.app`
- SMAppService daemon plist in `Battery.app/Contents/Library/LaunchDaemons/`, `BundleProgram` inside the bundle
- CLI, daemon, Sparkle: nested anywhere in the bundle, `sign.sh` finds every Mach-O
- Entitlements: set them in Xcode, signing preserves them

## Gotchas

- Scripts run on macOS `/bin/bash` 3.2: no `${arr[@]}` on empty arrays, no `mapfile`, no `${var,,}`
- Never `set -x`, secrets pass through env
- Sparkle key mismatch = no user can update, never change `SPARKLE_PUBLIC_ED_KEY` casually
- Bump `SPARKLE_VERSION` together with `SPARKLE_SHA256`
