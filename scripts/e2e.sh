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
# This side is babysit plumbing only: ship sources and secrets, hold the screen, answer the password request, sudo.
# The Mac does the rest itself: scripts/e2e/mac-build.sh (signed build + install) and scripts/e2e/mac-run.sh (suites, helper checks).
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
run() { mac "bash ~/e2e/scripts/e2e/mac-run.sh $*"; }
log() { echo "🧪 $*"; }

# Ship macos/ + scripts/ to the Mac's ~/e2e (the Mac builds and runs everything itself)
ship_sources() {
	tar czf /tmp/e2e.tgz --exclude=.build --exclude='*.xcodeproj' macos scripts
	babysit mac scp "$MAC" /tmp/e2e.tgz mac:/tmp/e2e.tgz > /dev/null
	mac 'mkdir -p ~/e2e && cd ~/e2e && rm -rf macos/E2E/Sources macos/E2E/Tests scripts && tar xzf /tmp/e2e.tgz'
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
ship_sources

if [[ $build == 1 ]]; then
	[[ -f .secrets/.env.release ]] || { echo "Signing credentials missing in .secrets/ (needed so the helper keeps its approval across builds). Use --no-build to skip."; exit 1; }
	log "Building and installing a signed app (credentials are copied over and deleted again)"
	mac 'rm -rf ~/e2e/sec && mkdir -p ~/e2e/sec && chmod 700 ~/e2e/sec'
	for f in .env.release developer-id.p12; do babysit mac scp "$MAC" ".secrets/$f" "mac:e2e/sec/$f" > /dev/null; done
	mac 'bash ~/e2e/scripts/e2e/mac-build.sh' || { mac 'tail -30 ~/e2e/build.log'; exit 1; }
	# The old helper keeps running across the replace; the app notices the new build and restarts it, no click
	if run helper-up 60; then
		log "Helper answering after the replace"
	else
		log "FAIL: helper not answering after the replace, pressing Repair to carry on"; heal_failed=1
		ensure_hold
		run repair
		run helper-up 45 || { echo "Helper still down after Repair: approve it in System Settings -> Login Items"; exit 1; }
	fi
fi

run build-tests || exit 1

status=${heal_failed:-0}

if [[ $suite == cli || $suite == all ]]; then
	log "CLI suite"
	run cli "$filter" || status=1
fi

if [[ $suite == gui || $suite == all ]]; then
	log "GUI suite (screen held unlocked)"
	ensure_hold
	run gui "$filter" || status=1
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
	run lifecycle "$filter" || status=1
	kill $watcher 2>/dev/null || true

	# A dead helper job (registered + approved, gone from launchd) stays dead without the app, and the app heals it on launch, no click.
	# Needs root to kill the job: babysit's stored sudo password, never typed by us.
	log "Dead helper is healed by the app on launch"
	run quit-app
	babysit mac sudo "$MAC" launchctl bootout system/co.palokaj.battery.daemon > /dev/null 2>&1 || true
	run heal-check || status=1
fi

run finish
[[ $status == 0 ]] && log "All green" || log "FAILURES above"
exit $status
