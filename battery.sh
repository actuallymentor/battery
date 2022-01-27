#!/bin/bash

## ###############
## Variables
## ###############
tempfolder=tmp
binfolder=/usr/local/bin

# CLI help message
helpmessage="
Battery CLI utility v0.0.1.

Usage: 

  battery charging SETTING
    on: sets CH0B to 00 (allow charging)
    off: sets CH0B to 02 (disallow charging)

  battery charge LEVEL
    LEVEL: percentage to charge to, charging is disabled when percentage is reached.

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

## ###############
## Helpers
## ###############
function enable_charging() {
	echo "$(date +%T) - Enabling battery charging"
	sudo smc -k CH0B -w 00
}

function disable_charging() {
	echo "$(date +%T) - Disabling battery charging"
	sudo smc -k CH0B -w 02
}


## ###############
## Actions
## ###############

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
		enable_charging
	elif [[ "$setting" == "off" ]]; then
		disable_charging
	fi

fi

# Charging on/off controller
if [[ "$action" == "charge" ]]; then

	# Start charging
	BATT_PERCENT=`pmset -g batt | tail -n1 | awk '{print $3}' | sed s:\%\;::`
	echo "$(date +%T) - Charging to $setting% from $BATT_PERCENT%"
	enable_charging

	# Loop until battery percent is exceeded
	while [[ "$BATT_PERCENT" -lt "$setting" ]]; do

		echo "$(date +%T) - Battery at $BATT_PERCENT%"
		sleep 60
		BATT_PERCENT=`pmset -g batt | tail -n1 | awk '{print $3}' | sed s:\%\;::`
		
	done

	disable_charging
	echo "$(date +%T) - Charging completed at $BATT_PERCENT%"

fi