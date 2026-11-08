#!/bin/bash
# Run ON the Mac as root (babysit mac sudo NAME bash scripts/dev/mac-dev-daemon.sh load|unload).
# Loads the daemon from /Applications/Battery.app through a plain launchd plist, so rebuilds don't need
# SMAppService re-approval. Not for end users.
label=co.palokaj.battery.daemon
plist=/Library/LaunchDaemons/$label.plist
case "${1:-load}" in
	load)
		cat > $plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array><string>/Applications/Battery.app/Contents/MacOS/batteryd</string></array>
<key>MachServices</key><dict><key>$label</key><true/></dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
</dict></plist>
EOF
		chown root:wheel $plist
		launchctl bootout system/$label 2>/dev/null
		launchctl bootstrap system $plist ;;
	unload)
		launchctl bootout system/$label 2>/dev/null
		rm -f $plist ;;
esac
