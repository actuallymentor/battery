# Dev scripts (macOS test machine)

Flow: `tar czf macos.tgz macos scripts` -> scp to `/tmp` on the Mac -> `mac-rebuild.sh` (xcodegen + xcodebuild, arm64, ad-hoc, app lands in `~/Applications`) -> `sudo bash mac-install-to-applications.sh`.
Rebuilds change the ad-hoc signature, so the `SMAppService` job fails until "Repair helper" + re-approval. While iterating use `sudo bash mac-dev-daemon.sh load|unload`.
Driving the GUI over `babysit mac run`: the Mac re-locks when each session ends, chain everything: `click 783 889; unlock; click ...; shot`. See `.notes/RESEARCH.md`.
