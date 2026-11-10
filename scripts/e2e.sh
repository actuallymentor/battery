#!/bin/bash

#
# End-to-end suites: the real signed Battery.app, the real root helper, the real SMC, on a real MacBook.
# No mocks, no stubs, never runs in CI. Needs a Mac registered with `babysit mac` (default: ArjunMacbook).
#
#   scripts/e2e.sh                 build + install fresh, then CLI and GUI suites
#   scripts/e2e.sh cli             CLI suite only (no screen needed)
#   scripts/e2e.sh gui             GUI suite only (holds the screen unlocked while it runs)
#   scripts/e2e.sh all --no-build  test whatever is installed in /Applications
#   scripts/e2e.sh gui --filter testSlider     only matching tests (swift test --filter)
#
# One-time Mac setup: grant Terminal.app Accessibility (System Settings -> Privacy & Security -> Accessibility).
# The GUI suite runs inside Terminal because that's the process holding the grant.
#

set -eu
cd "$(dirname "$0")/.."

MAC="${MAC:-ArjunMacbook}"; export MAC
suite=all; build=1; filter=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		cli|gui|all) suite="$1" ;;
		--no-build) build=0 ;;
		--filter) shift; filter="$1" ;;
		*) echo "unknown argument $1"; exit 2 ;;
	esac
	shift
done

mac() { babysit mac ssh "$MAC" "$@"; }
log() { echo "🧪 $*"; }

# Is the root helper answering `battery status`? Polls for up to $1 seconds.
helper_up() {
	local tries=$(( $1 / 3 + 1 ))
	mac "for i in \$(seq 1 $tries); do /Applications/Battery.app/Contents/Helpers/battery status 2>&1 | grep -q '^Battery at' && exit 0; sleep 3; done; exit 1"
}

# The Mac re-locks the moment a screen session ends: hold one open while GUI work runs
held=0
ensure_hold() {
	[[ $held == 1 ]] && return
	mac 'pgrep caffeinate >/dev/null || (nohup caffeinate -d -i -u -t 14400 >/dev/null 2>&1 &)'
	HOLD_MOVES=900 scripts/e2e/hold.sh start; held=1
	trap 'scripts/e2e/hold.sh stop' EXIT
}

babysit mac list 2>&1 | grep -q "$MAC" || { echo "No Mac named $MAC registered with babysit"; exit 1; }

log "Syncing sources"
scripts/e2e/sync.sh

if [[ $build == 1 ]]; then
	[[ -f .secrets/.env.release ]] || { echo "Signing credentials missing in .secrets/ (needed so the helper keeps its approval across builds). Use --no-build to skip."; exit 1; }
	log "Building and installing a signed app (credentials are copied over and deleted again)"
	mac 'rm -rf ~/e2e/sec && mkdir -p ~/e2e/sec && chmod 700 ~/e2e/sec'
	for f in .env.release AuthKey.p8 developer-id.p12; do babysit mac scp "$MAC" ".secrets/$f" "mac:e2e/sec/$f" > /dev/null; done
	mac 'bash ~/e2e/scripts/e2e/mac-build.sh' || { mac 'tail -30 ~/e2e/build.log'; exit 1; }
	mac 'open -a /Applications/Battery.app'
	# A replaced app leaves its registered helper "not answering" until the app's own Repair runs (needs no approval)
	if ! helper_up 15; then
		log "Helper not answering after the replace, pressing the app's Repair helper button"
		ensure_hold
		mac 'cd ~/e2e/macos/E2E && swift build --product axdump 2>&1 | grep error: ; bash ~/e2e/scripts/e2e/term.sh $PWD/.build/debug/axdump menu press:Repair >/dev/null'
		helper_up 45 || { echo "Helper still down after Repair: approve it in System Settings -> Login Items"; exit 1; }
	fi
fi

mac 'cd ~/e2e/macos/E2E && swift build --build-tests 2>&1 | grep -E "error|Compiling|Build" | tail -3'

status=0
args=(); [[ -n "$filter" ]] && args=(--filter "$filter")

if [[ $suite == cli || $suite == all ]]; then
	log "CLI suite"
	mac "set -o pipefail; cd ~/e2e/macos/E2E && swift test --filter CLITests ${filter:+--filter $filter} 2>&1 | grep -E 'error:|with [0-9]+ failure' | cut -c1-300 | uniq" || status=1
fi

if [[ $suite == gui || $suite == all ]]; then
	log "GUI suite (screen held unlocked)"
	ensure_hold
	mac "set -o pipefail; cd ~/e2e/macos/E2E && bash ~/e2e/scripts/e2e/term.sh swift test --filter GUITests ${filter:+--filter $filter} 2>&1 | grep -E 'error:|with [0-9]+ failure' | cut -c1-300 | uniq" || status=1
fi

# The GUI suite ran inside Terminal windows: close them all (no saved state either)
mac 'killall Terminal 2>/dev/null; rm -rf ~/Library/Saved\ Application\ State/com.apple.Terminal.savedState; true'

# Leave the Mac the way a user would want it
mac '/Applications/Battery.app/Contents/Helpers/battery maintain recover >/dev/null; /Applications/Battery.app/Contents/Helpers/battery status'
[[ $status == 0 ]] && log "All green" || log "FAILURES above"
exit $status
