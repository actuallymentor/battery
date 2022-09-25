#!/bin/bash

## ###############
## Variables
## ###############
binfolder=/usr/local/bin
visudo_path=/private/etc/sudoers.d/battery
configfolder=$HOME/.battery
pidfile=$configfolder/battery.pid
logfile=$configfolder/battery.log
maintain_percentage_tracker_file=$configfolder/maintain.percentage
daemon_path=$HOME/Library/LaunchAgents/battery.plist

## ###############
## Housekeeping
## ###############

# Create config folder if needed
mkdir -p $configfolder

# create logfile if needed
touch $logfile

# Trim logfile if needed
logsize=$(stat -f%z "$logfile")
max_logsize_bytes=5000000
if (( logsize > max_logsize_bytes )); then
	tail -n 100 $logfile > $logfile
fi

# CLI help message
helpmessage="
Battery CLI utility v1.0.0

Usage:

  battery status
    output battery SMC status, % and time remaining

  battery maintain LEVEL[1-100,stop]
    reboot-persistent battery level maintenance: turn off charging above, and on below a certain value
    eg: battery maintain 80
    eg: battery maintain stop

  battery charging SETTING[on/off]
    manually set the battery to (not) charge
    eg: battery charging on

  battery charge LEVEL[1-100]
    charge the battery to a certain percentage, and disable charging when that percentage is reached
    eg: battery charge 90

  battery visudo
    instructions on how to make which utility exempt from sudo, highly recommended

  battery update
    update the battery utility to the latest version

  battery reinstall
    reinstall the battery utility to the latest version (reruns the installation script)

  battery uninstall
    enable charging and remove the smc tool and the battery script

"

# Visudo instructions
visudoconfig="
# Visudo settings for the battery utility installed from https://github.com/actuallymentor/battery
# intended to be placed in $visudo_path on a mac
Cmnd_Alias      BATTERYOFF = $binfolder/smc -k CH0B -w 02, $binfolder/smc -k CH0C -w 02
Cmnd_Alias      BATTERYON = $binfolder/smc -k CH0B -w 00, $binfolder/smc -k CH0C -w 00
ALL ALL = NOPASSWD: BATTERYOFF
ALL ALL = NOPASSWD: BATTERYON
"

# Get parameters
action=$1
setting=$2

## ###############
## Helpers
## ###############

function log() {

	echo -e "$(date +%T) - $1"

}

# Re:charging, Aldente uses CH0B https://github.com/davidwernhart/AlDente/blob/0abfeafbd2232d16116c0fe5a6fbd0acb6f9826b/AlDente/Helper.swift#L227
# but @joelucid uses CH0C https://github.com/davidwernhart/AlDente/issues/52#issuecomment-1019933570
# so I'm using both since with only CH0B I noticed sometimes during sleep it does trigger charging
function enable_charging() {
	log "Enabling battery charging"
	sudo smc -k CH0B -w 00
	sudo smc -k CH0C -w 00
}

function disable_charging() {
	log "Disabling battery charging"
	sudo smc -k CH0B -w 02
	sudo smc -k CH0C -w 02
}

function get_smc_charging_status() {
	hex_status=$( smc -k CH0B -r | awk '{print $4}' | sed s:\):: )
	if [[ "$hex_status" == "00" ]]; then
		echo "enabled"
	else
		echo "disabled"
	fi
}

function get_battery_percentage() {
	battery_percentage=`pmset -g batt | tail -n1 | awk '{print $3}' | sed s:\%\;::`
	echo "$battery_percentage"
}

function get_remaining_time() {
	time_remaining=`pmset -g batt | tail -n1 | awk '{print $5}'`
	echo "$time_remaining"
}



## ###############
## Actions
## ###############

# Help message
if [ -z "$action" ]; then
	echo -e "$helpmessage"
	exit 0
fi

# Visudo message
if [[ "$action" == "visudo" ]]; then
	echo -e "$visudoconfig" >> $configfolder/visudo.tmp
	sudo visudo -c -f $configfolder/visudo.tmp 1> /dev/null
	if [ "$?" -eq "0" ]; then
		sudo cp $configfolder/visudo.tmp $visudo_path
		rm $configfolder/visudo.tmp
	fi
	sudo chmod 440 $visudo_path
	exit 0
fi

# Reinstall helper
if [[ "$action" == "reinstall" ]]; then
	echo "This will run curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash"
	if [[ ! "$setting" == "silent" ]]; then
		echo "Press any key to continue"
		read
	fi
	curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash
	exit 0
fi

# Update helper
if [[ "$action" == "update" ]]; then
	echo "This will run curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/update.sh | bash"
	if [[ ! "$setting" == "silent" ]]; then
		echo "Press any key to continue"
		read
	fi
	curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/update.sh | bash
	exit 0
fi

# Uninstall helper
if [[ "$action" == "uninstall" ]]; then

	if [[ ! "$setting" == "silent" ]]; then
		echo "This will enable charging, and remove the smc tool and battery script"
		echo "Press any key to continue"
		read
	fi
    enable_charging
	battery remove_daemon
    sudo rm -v "$binfolder/smc" "$binfolder/battery"
    exit 0
fi

# Charging on/off controller
if [[ "$action" == "charging" ]]; then

	log "Setting $action to $setting"

	# Disable running daemon
	battery maintain stop

	# Set charging to on and off
	if [[ "$setting" == "on" ]]; then
		enable_charging
	elif [[ "$setting" == "off" ]]; then
		disable_charging
	fi

	exit 0

fi

# Charging on/off controller
if [[ "$action" == "charge" ]]; then

	# Disable running daemon
	battery maintain stop

	# Start charging
	battery_percentage=$( get_battery_percentage )
	log "Charging to $setting% from $battery_percentage%"
	enable_charging

	# Loop until battery percent is exceeded
	while [[ "$battery_percentage" -lt "$setting" ]]; do

		log "Battery at $battery_percentage%"
		caffeinate -i sleep 60
		battery_percentage=$( get_battery_percentage )

	done

	disable_charging
	log "Charging completed at $battery_percentage%"

	exit 0

fi

# Maintain at level
if [[ "$action" == "maintain_synchronous" ]]; then

	# Start charging
	battery_percentage=$( get_battery_percentage )

	log "Charging to and maintaining at $setting% from $battery_percentage%"

	# Loop until battery percent is exceeded
	while true; do

		# Keep track of status
		is_charging=$( get_smc_charging_status )

		if [[ "$battery_percentage" -gt "$setting" && "$is_charging" == "enabled" ]]; then

			log "Charge above $setting"
			disable_charging

		elif [[ "$battery_percentage" -lt "$setting" && "$is_charging" == "disabled" ]]; then

			log "Charge below $setting"
			enable_charging

		fi

		sleep 60

		battery_percentage=$( get_battery_percentage )

	done

	exit 0

fi

# Asynchronous battery level maintenance
if [[ "$action" == "maintain" ]]; then

	# Kill old process silently
	if test -f "$pidfile"; then
		pid=$( cat "$pidfile" 2> /dev/null )
		kill $pid &> /dev/null
	fi

	# Recover old maintain status if old setting is found
	if [[ "$setting" == "recover" ]]; then
		maintain_percentage=$( cat $maintain_percentage_tracker_file 2> /dev/null )
		if [[ $maintain_percentage ]]; then
			log "Recovering maintenance percentage $maintain_percentage"
			battery maintain $maintain_percentage
		else
			log "No setting to recover, exiting"
		fi
		exit 0
	fi

	if [[ "$setting" == "stop" ]]; then
		rm $pidfile 2> /dev/null
		rm $maintain_percentage_tracker_file 2> /dev/null
		battery remove_daemon
		enable_charging
		battery status
		exit 0
	fi

	# Start maintenance script
	log "Starting battery maintenance at $setting%"
	nohup battery maintain_synchronous $setting >> $logfile &

	# Store pid of maintenance process and setting
	echo $! > $pidfile
	pid=$( cat "$pidfile" 2> /dev/null )
	echo $setting > $maintain_percentage_tracker_file
	log "Maintaining battery at $setting%"

	# Enable the daemon that continues maintaining after reboot
	battery create_daemon

	exit 0
	
fi


# Status logger
if [[ "$action" == "status" ]]; then

	log "Battery at $( get_battery_percentage  )% ($( get_remaining_time ) remaining), smc charging $( get_smc_charging_status )"
	if test -f $pidfile; then
		maintain_percentage=$( cat $maintain_percentage_tracker_file 2> /dev/null )
		log "Your battery is currently being maintained at $maintain_percentage%"
	fi
	exit 0

fi

# launchd daemon creator, inspiration: https://www.launchd.info/
if [[ "$action" == "create_daemon" ]];then

	daemon_definition="
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
	<dict>

		<key>Label</key>
		<string>com.battery.app</string>

		<key>PATH</key>
		<string>/bin:/usr/bin:$binfolder</string>		

		<key>ProgramArguments</key>
		<array>
			<string>$binfolder/battery</string>
			<string>maintain</string>
			<string>recover</string>
		</array>

		<key>RunAtLoad</key>
		<true/>
	</dict>
</plist>
"

	echo "$daemon_definition" > "$daemon_path"

	exit 0

fi

# Remove daemon
if [[ "$action" == "remove_daemon" ]];then

	rm $daemon_path 2> /dev/null
	exit 0

fi