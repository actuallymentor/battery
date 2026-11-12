#!/bin/bash
# ON the Mac: one step of an e2e run. scripts/e2e.sh drives these over babysit and keeps only what needs babysit
# (sync, secrets, screen hold, the password watcher, sudo). Everything the Mac can do by itself lives here.
#
#   mac-run.sh build-tests                  compile the E2E package
#   mac-run.sh cli|gui|lifecycle [filter]   one suite (swift test --filter CLASS/.*filter), summarised to errors + pass/fail lines
#   mac-run.sh helper-up SECS               poll `battery status` for up to SECS seconds
#   mac-run.sh repair                       press Repair in the app's menu (screen must be held unlocked)
#   mac-run.sh quit-app                     quit Battery.app, so a `launchctl bootout` leaves the helper really dead
#   mac-run.sh heal-check                   after that bootout: helper must be down, then come back once the app launches
#   mac-run.sh finish                       close Terminal windows, leave the Mac neutral, print status
#
# gui and lifecycle run inside Terminal.app: it is the only process holding the Accessibility grant.
cd ~/e2e/macos/E2E || exit 1
app=/Applications/Battery.app
bat=$app/Contents/Helpers/battery

log() { echo "🧪 $*"; }

# Is the root helper answering `battery status`? Polls for up to $1 seconds.
helper_up() {
	for _ in $(seq 1 $(( $1 / 3 + 1 ))); do
		$bat status 2>&1 | grep -q '^Battery at' && return 0
		sleep 3
	done
	return 1
}

# Runs "$@" inside Terminal.app and waits. Output lands in /tmp/e2e/out, the exit code is propagated.
in_terminal() {
	local d=/tmp/e2e; mkdir -p $d; rm -f $d/out $d/done
	printf '#!/bin/bash\ncd %q\n%s > %s/out 2>&1\necho $? > %s/done\n' "$PWD" "$(printf '%q ' "$@")" $d $d > $d/run.sh
	chmod +x $d/run.sh
	open -a Terminal $d/run.sh
	until [ -f $d/done ]; do sleep 1; done
	cat $d/out
	return "$(cat $d/done)"
}

# suite CLASS FILTER RUNNER...: swift test through RUNNER (env = plain, in_terminal = via Terminal), only the lines worth reading
suite() {
	local class="$1" filter="$2"; shift 2
	set -o pipefail
	"$@" swift test --filter "$class${filter:+/.*$filter}" 2>&1 | grep -E 'error:|with [0-9]+ failure|^lifecycle:' | cut -c1-300 | uniq
}

case "${1:-}" in
	build-tests)
		set -o pipefail
		swift build --build-tests 2>&1 | grep -E "error|Compiling|Build" | tail -3 ;;

	cli)       suite CLITests "${2:-}" env ;;
	gui)       suite GUITests "${2:-}" in_terminal ;;
	lifecycle)
		suite LifecycleTests "${2:-}" in_terminal env E2E_LIFECYCLE=1; rc=$?
		helper_up 30 || { log "Helper is down after the lifecycle suite"; rc=1; }
		exit $rc ;;

	helper-up) helper_up "$2" ;;
	repair)
		swift build --product axdump 2>&1 | grep error:
		in_terminal "$PWD/.build/debug/axdump" menu press:Repair > /dev/null ;;

	quit-app)  osascript -e 'quit app "Battery"'; sleep 2 ;;
	heal-check)
		if helper_up 3; then log "FAIL: bootout left the helper running"; exit 1; fi
		open -a $app
		helper_up 30 && log "healed" || { log "FAIL: the app did not heal a dead helper"; exit 1; } ;;

	finish)
		# The GUI suite ran inside Terminal windows: close them all (no saved state either), then leave the Mac the way a user would want it
		killall Terminal 2>/dev/null; rm -rf ~/Library/Saved\ Application\ State/com.apple.Terminal.savedState
		$bat maintain recover > /dev/null; $bat status ;;

	*) echo "usage: mac-run.sh build-tests|cli|gui|lifecycle [filter]|helper-up SECS|repair|quit-app|heal-check|finish" >&2; exit 2 ;;
esac
