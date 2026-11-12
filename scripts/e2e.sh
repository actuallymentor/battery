#!/bin/bash

#
# End-to-end suites: the real signed Battery.app, the real root helper, the real SMC, on a real MacBook.
# No mocks, no stubs, never runs in CI. Needs a Mac registered with `babysit mac` (default: ArjunMacbook).
#
#   scripts/e2e.sh                 build + install fresh, then CLI and GUI suites
#   scripts/e2e.sh cli             CLI suite only (no screen needed)
#   scripts/e2e.sh gui             GUI suite only (holds the screen unlocked while it runs)
#   scripts/e2e.sh lifecycle       helper uninstall / set up again / approval revoked + granted (types the admin password once, see below)
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
		cli|gui|lifecycle|all) suite="$1" ;;
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
	# The old helper keeps running across the replace; the app notices the new build and restarts it, no click
	if helper_up 60; then
		log "Helper answering after the replace"
	else
		log "FAIL: helper not answering after the replace, pressing Repair to carry on"; heal_failed=1
		ensure_hold
		mac 'cd ~/e2e/macos/E2E && swift build --product axdump 2>&1 | grep error: ; bash ~/e2e/scripts/e2e/term.sh $PWD/.build/debug/axdump menu press:Repair >/dev/null'
		helper_up 45 || { echo "Helper still down after Repair: approve it in System Settings -> Login Items"; exit 1; }
	fi
fi

mac 'cd ~/e2e/macos/E2E && swift build --build-tests 2>&1 | grep -E "error|Compiling|Build" | tail -3'

status=${heal_failed:-0}

if [[ $suite == cli || $suite == all ]]; then
	log "CLI suite"
	mac "set -o pipefail; cd ~/e2e/macos/E2E && swift test --filter \"CLITests${filter:+/.*$filter}\" 2>&1 | grep -E 'error:|with [0-9]+ failure' | cut -c1-300 | uniq" || status=1
fi

if [[ $suite == gui || $suite == all ]]; then
	log "GUI suite (screen held unlocked)"
	ensure_hold
	mac "set -o pipefail; cd ~/e2e/macos/E2E && bash ~/e2e/scripts/e2e/term.sh swift test --filter \"GUITests${filter:+/.*$filter}\" 2>&1 | grep -E 'error:|with [0-9]+ failure' | cut -c1-300 | uniq" || status=1
fi

if [[ $suite == lifecycle || $suite == all ]]; then
	log "Lifecycle suite (really uninstalls the helper; the admin password is typed once, into System Settings, when the test has verified its field is focused)"
	ensure_hold
	mac 'rm -f /tmp/e2e/password-wanted /tmp/e2e/password-typed /tmp/e2e/password-refused'
	# Answer the test's password request. The test asks only once System Settings is frontmost with its Password field focused;
	# check System Settings is still frontmost right before typing (`unlock` types into whatever has focus), else refuse.
	( until mac 'test -f /tmp/e2e/password-wanted'; do sleep 1; done
	  if mac 'rm -f /tmp/e2e/password-wanted; lsappinfo info -only name "$(lsappinfo front)" | grep -q "\"System Settings\""'; then
		babysit mac unlock "$MAC" > /dev/null; mac 'touch /tmp/e2e/password-typed'; log "typed the admin password into System Settings"
	  else
		mac 'touch /tmp/e2e/password-refused'; log "System Settings was not frontmost, refused to type"
	  fi ) &
	watcher=$!
	mac "set -o pipefail; cd ~/e2e/macos/E2E && bash ~/e2e/scripts/e2e/term.sh env E2E_LIFECYCLE=1 swift test --filter \"LifecycleTests${filter:+/.*$filter}\" 2>&1 | grep -E 'error:|with [0-9]+ failure|^lifecycle:' | cut -c1-300 | uniq" || status=1
	kill $watcher 2>/dev/null || true
	helper_up 30 || { log "Helper is down after the lifecycle suite"; status=1; }

	# A dead helper job (registered + approved, gone from launchd) stays dead without the app, and the app heals it on launch, no click.
	# Needs root to kill the job: babysit's stored sudo password, never typed by us.
	log "Dead helper is healed by the app on launch"
	mac 'osascript -e "quit app \"Battery\""; sleep 2'
	babysit mac sudo "$MAC" launchctl bootout system/co.palokaj.battery.daemon > /dev/null 2>&1 || true
	if helper_up 3; then log "FAIL: bootout left the helper running"; status=1
	else
		mac 'open -a /Applications/Battery.app'
		helper_up 30 && log "healed" || { log "FAIL: the app did not heal a dead helper"; status=1; }
	fi
fi

# The GUI suite ran inside Terminal windows: close them all (no saved state either)
mac 'killall Terminal 2>/dev/null; rm -rf ~/Library/Saved\ Application\ State/com.apple.Terminal.savedState; true'

# Leave the Mac the way a user would want it
mac '/Applications/Battery.app/Contents/Helpers/battery maintain recover >/dev/null; /Applications/Battery.app/Contents/Helpers/battery status'
[[ $status == 0 ]] && log "All green" || log "FAILURES above"
exit $status
