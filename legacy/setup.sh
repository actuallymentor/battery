#!/bin/bash

#
# ‼️ SECURITY NOTES FOR MAINTAINERS:
#
# This app uses a visudo configuration that allows a background script running as
# an unprivileged user to execute battery management commands without requiring a
# user password. This requires careful installation and design to avoid potential
# privilege-escalation vulnerabilities.
#
# Rule of thumb:
# - Unprivileged users must not be able to modify, replace, or inject any code
#   that can be executed with root privileges.
#
# For this reason:
# - All battery-related binaries and scripts that can be executed via sudo,
#   including those that prompt for a user password, must be owned by root.
# - They must not be writable by group or others.
# - Their parent directories must also be owned by root and not be writable by
#   unprivileged users, to prevent the replacement of executables.
#

# Reset PATH to minimal safe defaults
PATH=/usr/bin:/bin:/usr/sbin:/sbin

# User welcome message
echo -e "\n####################################################################"
echo '# 👋 Welcome, this is the setup script for the battery CLI tool.'
echo -e "# Note: this script may ask for your password."
echo -e "####################################################################\n\n"

# Determine unprivileged user name
if [[ -n "$1" ]]; then
	calling_user="$1"
else
	if [[ -n "$SUDO_USER" ]]; then
		calling_user=$SUDO_USER
	else
		calling_user=$USER
	fi
fi
if [[ "$calling_user" == "root" ]]; then
	echo "❌ Failed to determine unprivileged username"
	exit 1
fi

# Set variables
binfolder=/usr/local/co.palokaj.battery
configfolder=/Users/$calling_user/.battery
pidfile=$configfolder/battery.pid
logfile=$configfolder/battery.log
launch_agent_plist=/Users/$calling_user/Library/LaunchAgents/battery.plist
path_configfile=/etc/paths.d/50-battery

# Ask for sudo once, in most systems this will cache the permissions for a bit
sudo echo "🔋 Starting battery installation"
echo "[  1 ] Superuser permissions acquired."

# Cleanup after versions 1_3_2 and below
sudo rm -f /usr/local/bin/battery
sudo rm -f /usr/local/bin/smc

echo "[  2 ] Allocate temp folder"
tempfolder="$(mktemp -d)"
function cleanup() { rm -rf "$tempfolder"; }
trap cleanup EXIT

echo "[  3 ] Downloading latest version of battery CLI"
# Note: github names zips by <reponame>-<branchname>.replace( '/', '-' )
update_branch="main"
in_zip_folder_name="battery-$update_branch"
batteryfolder="$tempfolder/battery"
rm -rf $batteryfolder
mkdir -p $batteryfolder
curl -sSL -o $batteryfolder/repo.zip "https://github.com/actuallymentor/battery/archive/refs/heads/$update_branch.zip"
unzip -qq $batteryfolder/repo.zip -d $batteryfolder
cp -r $batteryfolder/$in_zip_folder_name/* $batteryfolder
rm $batteryfolder/repo.zip

echo "[  4 ] Make sure $binfolder is recreated and owned by root"
sudo rm -rf "$binfolder" # start with an empty $binfolder and ensure there is no symlink or file at the path
sudo install -d -m 755 -o root -g wheel "$binfolder"

echo "[  5 ] Install prebuilt smc binary into $binfolder"
sudo install -m 755 -o root -g wheel "$batteryfolder/dist/smc" "$binfolder/smc"

echo "[  6 ] Install battery script into $binfolder"
sudo install -m 755 -o root -g wheel "$batteryfolder/battery.sh" "$binfolder/battery"

echo "[  7 ] Make sure the PATH environment variable includes '$binfolder'"
if ! grep -qF "$binfolder" $path_configfile 2>/dev/null; then
	printf '%s\n' "$binfolder" | sudo tee "$path_configfile" >/dev/null
fi
sudo chown -h root:wheel $path_configfile
sudo chmod -h 644 $path_configfile
# Create a symlink for rare shells that do not initialize PATH from /etc/paths.d (including the current one)
sudo mkdir -p /usr/local/bin
sudo ln -sf "$binfolder/battery" /usr/local/bin/battery
sudo chown -h root:wheel /usr/local/bin/battery
# Create a link to smc as well to silence older GUI apps running with updated background executables
# (consider removing in the next releases)
sudo ln -sf "$binfolder/smc" /usr/local/bin/smc
sudo chown -h root:wheel /usr/local/bin/smc

echo "[  8 ] Set ownership and permissions for $configfolder"
mkdir -p $configfolder
sudo chown -hRP $calling_user $configfolder
sudo chmod -h 755 $configfolder

touch $logfile
sudo chown -h $calling_user $logfile
sudo chmod -h 644 $logfile

touch $pidfile
sudo chown -h $calling_user $pidfile
sudo chmod -h 644 $pidfile

# Fix permissions for 'create_daemon' action
echo "[  9 ] Fix ownership and permissions for $(dirname "$launch_agent_plist")"
sudo chown -h $calling_user "$(dirname "$launch_agent_plist")"
sudo chmod -h 755 "$(dirname "$launch_agent_plist")"
sudo chown -hf $calling_user "$launch_agent_plist" 2>/dev/null

echo "[ 10 ] Setup visudo configuration"
sudo $binfolder/battery visudo

echo "[ 11 ] Remove temp folder $tempfolder"
rm -rf $tempfolder

echo -e "\n🎉 Battery tool installed. Type \"battery help\" for instructions.\n"

exit 0
