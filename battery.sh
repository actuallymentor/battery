#!/bin/bash

## ###############
## Variables
## ###############
tempfolder=tmp
binfolder=/usr/local/bin

# CLI help message
helpmessage="
Battery CLI utility v0.0.2.

Usage: 

  battery status
    output battery SMC status, % and time remaining

  battery charging SETTING
    on: sets CH0B to 00 (allow charging)
    off: sets CH0B to 02 (disallow charging)

  battery charge LEVEL
    LEVEL: percentage to charge to, charging is disabled when percentage is reached.

  battery visudo
    instructions on how to make which utility exempt from sudo

  battery update
    run the installation command again to pull latest version

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

function get_smc_charging_status() {
	hex_status=$( smc -k CH0B -r | awk '{print $4}' | sed s:\):: )
	if [[ "$hex_status" == "02" ]]; then
		echo "disabled"
	else
		echo "enabled"
	fi
}

function get_charging_status() {
	battery_percentage=`pmset -g batt | tail -n1 | awk '{print $3}' | sed s:\%\;::`
	echo "$battery_percentage"
}

function get_remaining_time() {
	time_remaining=`pmset -g batt | tail -n1 | awk '{print $5}'`
	echo "$time_remaining"
}

function log() {

	echo -e "$(date +%T) - $1"

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
	echo "This will run curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | sudo bash"
	echo "Press any key to continue"
	read
	curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | sudo bash
fi


# Charging on/off controller
if [[ "$action" == "charging" ]]; then

	log "Setting $action to $setting"
	
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
	battery_percentage=$( get_battery_percentage )
	log "Charging to $setting% from $battery_percentage%"
	enable_charging

	# Loop until battery percent is exceeded
	while [[ "$BATT_PERCENT" -lt "$setting" ]]; do

		log "Battery at $battery_percentage%"
		sleep 60
		battery_percentage=$( get_battery_percentage )
		
	done

	disable_charging
	log "Charging completed at $battery_percentage%"

fi


# Status logget
if [[ "$action" == "status" ]]; then

	log "Battery at $( get_battery_percentage  ) ($( get_remaining_time ) remaining), smc charging $( get_smc_charging_status )"

fi
