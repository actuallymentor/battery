#!/bin/bash
# Local: keep the Mac's screen unlocked for the GUI suite. The Mac re-locks the moment a `babysit mac run`
# session ends, so hold one open (unlock, then a harmless pointer move every 2s) for HOLD_MOVES x ~1s.
#   e2e-hold.sh start   spawn in background, return once the screen reads unlocked
#   e2e-hold.sh stop    release it (kills the session)
MAC=${MAC:-ArjunMacbook}
case "${1:-start}" in
	start)
		# `unlock` types the password into whatever has focus: only do it when the screen really is locked
		script=""; babysit mac ssh "$MAC" '~/e2e/macos/E2E/.build/debug/axdump lockstate' 2>/dev/null | grep -q "locked: yes" && script="unlock"
		[ -z "$script" ] && script="move 300 300"
		for _ in $(seq 1 ${HOLD_MOVES:-400}); do script="$script; move 300 300; move 320 320"; done
		( babysit mac run "$MAC" "$script" > /tmp/e2e-hold.log 2>&1 & )
		for _ in $(seq 1 30); do
			babysit mac ssh "$MAC" '~/e2e/macos/E2E/.build/debug/axdump lockstate' 2>/dev/null | grep -q "locked: no" && exit 0
			sleep 2
		done
		echo "screen never unlocked, see /tmp/e2e-hold.log" >&2; exit 1 ;;
	stop) pgrep -f '^node /usr/local/bin/babysit mac run' | xargs -r kill ;;
esac
