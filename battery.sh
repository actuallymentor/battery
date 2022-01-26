#!/bin/bash

tempfolder=tmp
binfolder=/usr/local/bin

# CLI help message
helpmessage="
Battery CLI utility v0.0.1.

Usage: 

  battery charging SETTING
    on: sets CH0B to 00 (allow charging)
    off: sets CH0B to 02 (disallow charging)

  battery visudo: instructions on how to make which utility exempt from sudo

  battery update: run the installation command again to pull latest version

"

# Visudo instructions
visudoconfig="
# Put this in /private/etc/sudoers.d/battery on a mac
# with sudo visudo /private/etc/sudoers.d/battery

Cmnd_Alias      BATTERYOFF = $binfolder/smc -k CH0B -w 02
Cmnd_Alias      BATTERYON = $binfolder/smc -k CH0B -w 00
$( whoami ) ALL = NOPASSWD: BATTERYOFF
$( whoami ) ALL = NOPASSWD: BATTERYON
"

# Get parameters
action=$1
setting=$2

# Help message 
if [ -z "$action" ]; then
	echo -e "$helpmessage"
fi

# Visudo message
if [[ "$action" == "visudo" ]]; then
	echo -e "$visudoconfig"
fi

# Update helper
if [[ "$action" == "update" ]]; then
	echo "This will run curl https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | sudo bash"
	echo "Press any key to continue"
	read
	curl https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | sudo bash
fi


# Charging on/off controller
if [[ "$action" == "charging" ]]; then

	echo "Setting $action to $setting"
	
	# Set charging to on and off
	if [[ "$setting" == "on" ]]; then
		echo "Enabling battery charging"
		sudo smc -k CH0B -w 00
	elif [[ "$setting" == "off" ]]; then
		echo "Disabling battery charging"
		sudo smc -k CH0B -w 02
	fi

fi
