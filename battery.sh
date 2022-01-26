#!/bin/bash

tempfolder=tmp
binfolder=/usr/local/bin

# Battery management function

helpmessage="
Battery CLI utility. Usage: 

  battery charging on/off
    on: sets CH0B to 00 (allow charging)
    off: sets CH0B to 02 (disallow charging)

  visudo: instructions on how to make which utility exempt from sudo

"

visudoconfig="
# Put this in /private/etc/sudoers.d/mentor_zshrc on a mac
# with sudo visudo /private/etc/sudoers.d/battery

Cmnd_Alias      BATTERYOFF = $binfolder/smc -k CH0B -w 02
Cmnd_Alias      BATTERYON = $binfolder/smc -k CH0B -w 00
$( whoami ) ALL = NOPASSWD: BATTERYOFF
$( whoami ) ALL = NOPASSWD: BATTERYON
"

action=$1
setting=$2

if [ -z "$action" ]; then
	echo -e "$helpmessage"
fi

if [[ "$action" == "visudo" ]]; then
	echo -e "$visudoconfig"
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
