#!/bin/bash

## ###############
## Update management
## variables are used by this binary as well at the update script
## ###############
BATTERY_CLI_VERSION="v1.1.6"

# Path fixes for unexpected environments
PATH=/bin:/usr/bin:/usr/local/bin:/usr/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/opt/homebrew

## ###############
## Variables
## ###############
binfolder=/usr/local/bin
visudo_folder=/private/etc/sudoers.d
visudo_file=${visudo_folder}/battery
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
if ((logsize > max_logsize_bytes)); then
	tail -n 100 $logfile >$logfile
fi

# CLI help message
helpmessage="
Battery CLI utility $BATTERY_CLI_VERSION

Usage:

  battery status
    output battery SMC status, % and time remaining

  battery logs LINES[integer, optional]
    output logs of the battery CLI and GUI
	eg: battery logs 100

  battery maintain LEVEL[1-100,stop]
    reboot-persistent battery level maintenance: turn off charging above, and on below a certain value
	it has the option of a --force-discharge flag that discharges even when plugged in (this does NOT work well with clamshell mode)
    eg: battery maintain 80
    eg: battery maintain stop

  battery charging SETTING[on/off]
    manually set the battery to (not) charge
    eg: battery charging on

  battery adapter SETTING[on/off]
    manually set the adapter to (not) charge even when plugged in
    eg: battery adapter off

  battery charge LEVEL[1-100]
    charge the battery to a certain percentage, and disable charging when that percentage is reached
    eg: battery charge 90

  battery discharge LEVEL[1-100]
    block power input from the adapter until battery falls to this level
    eg: battery discharge 90

  battery visudo
    ensure you don't need to call battery with sudo
    This is already used in the setup script, so you should't need it.

  battery update
    update the battery utility to the latest version

  battery reinstall
    reinstall the battery utility to the latest version (reruns the installation script)

  battery uninstall
    enable charging, remove the smc tool, and the battery script

"

# Visudo instructions
visudoconfig="
# Visudo settings for the battery utility installed from https://github.com/actuallymentor/battery
# intended to be placed in $visudo_file on a mac
Cmnd_Alias      BATTERYOFF = $binfolder/smc -k CH0B -w 02, $binfolder/smc -k CH0C -w 02, $binfolder/smc -k CH0B -r, $binfolder/smc -k CH0C -r
Cmnd_Alias      BATTERYON = $binfolder/smc -k CH0B -w 00, $binfolder/smc -k CH0C -w 00
Cmnd_Alias      DISCHARGEOFF = $binfolder/smc -k CH0I -w 00, $binfolder/smc -k CH0I -r
Cmnd_Alias      DISCHARGEON = $binfolder/smc -k CH0I -w 01
Cmnd_Alias      LEDCONTROL = $binfolder/smc -k ACLC -w 04, $binfolder/smc -k ACLC -w 03, $binfolder/smc -k ACLC -w 00, $binfolder/smc -k ACLC -r
ALL ALL = NOPASSWD: BATTERYOFF
ALL ALL = NOPASSWD: BATTERYON
ALL ALL = NOPASSWD: DISCHARGEOFF
ALL ALL = NOPASSWD: DISCHARGEON
ALL ALL = NOPASSWD: LEDCONTROL
"

# Get parameters
action=$1
setting=$2
subsetting=$3

## ###############
## Helpers
## ###############

function log() {
	echo -e "$(date +%D-%T) - $1"
}

## #################
## SMC Manipulation
## #################

# Change magsafe color
# see community sleuthing: https://github.com/actuallymentor/battery/issues/71
function change_magsafe_led_color() {
	color=$1

	# Check whether user can run color changes without password (required for backwards compatibility)
	if sudo -n smc -k ACLC -r &>/dev/null; then
		log "💡 Setting magsafe color to $color"
	else
		log "🚨 Your version of battery is using an old visudo file, please run 'battery visudo' to fix this, until you do battery cannot change magsafe led colors"
		return
	fi

	if [[ "$color" == "green" ]]; then
		sudo smc -k ACLC -w 03
	elif [[ "$color" == "orange" ]]; then
		sudo smc -k ACLC -w 04
	else
		# Default action: reset. Value 00 is a guess and needs confirmation
		sudo smc -k ACLC -w 00
	fi
}

# Re:discharging, we're using keys uncovered by @howie65: https://github.com/actuallymentor/battery/issues/20#issuecomment-1364540704
# CH0I seems to be the "disable the adapter" key
function enable_discharging() {
	log "🔽🪫 Enabling battery discharging"
	sudo smc -k CH0I -w 01
	sudo smc -k ACLC -w 01
}

function disable_discharging() {
	log "🔼🪫 Disabling battery discharging"
	sudo smc -k CH0I -w 00
	# Keep track of status
	is_charging=$(get_smc_charging_status)

	if [[ "$battery_percentage" -ge "$setting" && "$is_charging" == "enabled" ]]; then

		log "Charge above $setting"
		disable_charging
		change_magsafe_led_color "green"

	elif [[ "$battery_percentage" -lt "$setting" && "$is_charging" == "disabled" ]]; then

		log "Charge below $setting"
		enable_charging
		change_magsafe_led_color "orange"

	fi

	battery_percentage=$(get_battery_percentage)
}

# Re:charging, Aldente uses CH0B https://github.com/davidwernhart/AlDente/blob/0abfeafbd2232d16116c0fe5a6fbd0acb6f9826b/AlDente/Helper.swift#L227
# but @joelucid uses CH0C https://github.com/davidwernhart/AlDente/issues/52#issuecomment-1019933570
# so I'm using both since with only CH0B I noticed sometimes during sleep it does trigger charging
function enable_charging() {
	log "🔌🔋 Enabling battery charging"
	sudo smc -k CH0B -w 00
	sudo smc -k CH0C -w 00
	disable_discharging
}

function disable_charging() {
	log "🔌🪫 Disabling battery charging"
	sudo smc -k CH0B -w 02
	sudo smc -k CH0C -w 02
}

function get_smc_charging_status() {
	hex_status=$(smc -k CH0B -r | awk '{print $4}' | sed s:\)::)
	if [[ "$hex_status" == "00" ]]; then
		echo "enabled"
	else
		echo "disabled"
	fi
}

function get_smc_discharging_status() {
	hex_status=$(smc -k CH0I -r | awk '{print $4}' | sed s:\)::)
	if [[ "$hex_status" == "0" ]]; then
		echo "not discharging"
	else
		echo "discharging"
	fi
}

## ###############
## Statistics
## ###############

function get_battery_percentage() {
	battery_percentage=$(pmset -g batt | tail -n1 | awk '{print $3}' | sed s:\%\;::)
	echo "$battery_percentage"
}

function get_remaining_time() {
	time_remaining=$(pmset -g batt | tail -n1 | awk '{print $5}')
	echo "$time_remaining"
}

function get_maintain_percentage() {
	maintain_percentage=$(cat $maintain_percentage_tracker_file 2>/dev/null)
	echo "$maintain_percentage"
}

## ###############
## Actions
## ###############

# Help message
if [ -z "$action" ] || [[ "$action" == "help" ]]; then
	echo -e "$helpmessage"
	exit 0
fi

# Visudo message
if [[ "$action" == "visudo" ]]; then

	# Write the visudo file to a tempfile
	visudo_tmpfile="$configfolder/visudo.tmp"
	echo -e "$visudoconfig" >$visudo_tmpfile

	# If the visudo file is the same (no error, exit code 0), set the permissions just
	if sudo cmp $visudo_file $visudo_tmpfile &>/dev/null; then

		echo "The existing battery visudo file is what it should be for version $BATTERY_CLI_VERSION"

		# Check if file permissions are correct, if not, set them
		current_visudo_file_permissions=$(stat -f "%Lp" $visudo_file)
		if [[ "$current_visudo_file_permissions" != "440" ]]; then
			sudo chmod 440 $visudo_file
		fi

		# exit because no changes are needed
		exit 0

	fi

	# Validate that the visudo tempfile is valid
	if sudo visudo -c -f $visudo_tmpfile &>/dev/null; then

		# If the visudo folder does not exist, make it
		if ! test -d "$visudo_folder"; then
			sudo mkdir -p "$visudo_folder"
		fi

		# Copy the visudo file from tempfile to live location
		sudo cp $visudo_tmpfile $visudo_file

		# Delete tempfile
		rm $visudo_tmpfile

		# Set correct permissions on visudo file
		sudo chmod 440 $visudo_file

		echo "Visudo file updated successfully"

	else
		echo "Error validating visudo file, this should never happen:"
		sudo visudo -c -f $visudo_tmpfile
	fi

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

	# Check if we have the most recent version
	if curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/battery.sh | grep -q "$BATTERY_CLI_VERSION"; then
		echo "No need to update, offline version number $BATTERY_CLI_VERSION matches remote version number"
	else
		echo "This will run curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/update.sh | bash"
		if [[ ! "$setting" == "silent" ]]; then
			echo "Press any key to continue"
			read
		fi
		curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/update.sh | bash
	fi
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
	disable_discharging
	battery remove_daemon
	sudo rm -v "$binfolder/smc" "$binfolder/battery" $visudo_file
	sudo rm -v -r "$configfolder"
	pkill -f "/usr/local/bin/battery.*"
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

# Discharge on/off controller
if [[ "$action" == "adapter" ]]; then

	log "Setting $action to $setting"

	# Disable running daemon
	battery maintain stop

	# Set charging to on and off
	if [[ "$setting" == "on" ]]; then
		disable_discharging
	elif [[ "$setting" == "off" ]]; then
		enable_discharging
	fi

	exit 0

fi

# Charging on/off controller
if [[ "$action" == "charge" ]]; then

	# Check if percentage is an integer [1-100]
	if ! [[ $setting =~ ^[1-9][0-9]?$|^100$ ]]; then
		log "Specified percentage ($setting) is not valid. Please specify an integer [1-100]."
		exit 1
	fi

	# Disable running daemon
	battery maintain stop

	# Disable charge blocker if enabled
	battery adapter on

	# Start charging
	battery_percentage=$(get_battery_percentage)
	log "Charging to $setting% from $battery_percentage%"
	enable_charging

	# Loop until battery percent is exceeded
	while [[ "$battery_percentage" -lt "$setting" ]]; do

		log "Battery at $battery_percentage%"
		caffeinate -is sleep 60
		battery_percentage=$(get_battery_percentage)

	done

	disable_charging
	log "Charging completed at $battery_percentage%"

	exit 0

fi

# Discharging on/off controller
if [[ "$action" == "discharge" ]]; then

	# Start charging
	battery_percentage=$(get_battery_percentage)
	log "Discharging to $setting% from $battery_percentage%"
	enable_discharging

	# Loop until battery percent is exceeded
	while [[ "$battery_percentage" -gt "$setting" ]]; do

		log "Battery at $battery_percentage% (target $setting%)"
		caffeinate -is sleep 60
		battery_percentage=$(get_battery_percentage)

	done

	disable_discharging
	log "Discharging completed at $battery_percentage%"

fi

# Maintain at level
if [[ "$action" == "maintain_synchronous" ]]; then

	# Recover old maintain status if old setting is found
	if [[ "$setting" == "recover" ]]; then

		# Before doing anything, log out environment details as a debugging trail
		log "Debug trail. User: $USER, config folder: $configfolder, logfile: $logfile, file called with 1: $1, 2: $2"

		maintain_percentage=$(cat $maintain_percentage_tracker_file 2>/dev/null)
		if [[ $maintain_percentage ]]; then
			log "Recovering maintenance percentage $maintain_percentage"
			setting=$(echo $maintain_percentage)
		else
			log "No setting to recover, exiting"
			exit 0
		fi
	fi

	# Check if the user requested that the battery maintenance first discharge to the desired level
	if [[ "$subsetting" == "--force-discharge" ]]; then
		# Before we start maintaining the battery level, first discharge to the target level
		log "Triggering discharge to $setting before enabling charging limiter"
		battery discharge "$setting"
		log "Discharge pre battery-maintenance complete, continuing to battery maintenance loop"
	else
		log "Not triggering discharge as it is not requested"
	fi

	# Start charging
	battery_percentage=$(get_battery_percentage)

	log "Charging to and maintaining at $setting% from $battery_percentage%"

	# Loop until battery percent is exceeded
	while true; do

		# Keep track of status
		is_charging=$(get_smc_charging_status)

		if [[ "$battery_percentage" -ge "$setting" && "$is_charging" == "enabled" ]]; then

			log "Charge above $setting"
			disable_charging
			change_magsafe_led_color "green"

		elif [[ "$battery_percentage" -lt "$setting" && "$is_charging" == "disabled" ]]; then

			log "Charge below $setting"
			enable_charging
			change_magsafe_led_color "orange"

		fi

		sleep 60

		battery_percentage=$(get_battery_percentage)

	done

	exit 0

fi

# Asynchronous battery level maintenance
if [[ "$action" == "maintain" ]]; then

	# Kill old process silently
	if test -f "$pidfile"; then
		pid=$(cat "$pidfile" 2>/dev/null)
		kill $pid &>/dev/null
	fi

	if [[ "$setting" == "stop" ]]; then
		log "Killing running maintain daemons & enabling charging as default state"
		rm $pidfile 2>/dev/null
		battery disable_daemon
		enable_charging
		change_magsafe_led_color
		battery status
		exit 0
	fi

	# Check if setting is value between 0 and 100
	if ! [[ "$setting" =~ ^[0-9]+$ ]] || [[ "$setting" -lt 0 ]] || [[ "$setting" -gt 100 ]]; then

		log "Called with $setting $action"
		# If non 0-100 setting is not a special keyword, exit with an error.
		if ! { [[ "$setting" == "stop" ]] || [[ "$setting" == "recover" ]]; }; then
			log "Error: $setting is not a valid setting for battery maintain. Please use a number between 0 and 100, or an action keyword like 'stop' or 'recover'."
			exit 1
		fi

	fi

	# Start maintenance script
	log "Starting battery maintenance at $setting% $subsetting"
	nohup battery maintain_synchronous $setting $subsetting >>$logfile &

	# Store pid of maintenance process and setting
	echo $! >$pidfile
	pid=$(cat "$pidfile" 2>/dev/null)

	if ! [[ "$setting" == "recover" ]]; then
		log "Writing new setting $setting to $maintain_percentage_tracker_file"
		echo $setting >$maintain_percentage_tracker_file
		log "Maintaining battery at $setting%"
	fi

	# Enable the daemon that continues maintaining after reboot
	battery create_daemon

	exit 0

fi

# Status logger
if [[ "$action" == "status" ]]; then

	log "Battery at $(get_battery_percentage)% ($(get_remaining_time) remaining), smc charging $(get_smc_charging_status)"
	if test -f $pidfile; then
		maintain_percentage=$(cat $maintain_percentage_tracker_file 2>/dev/null)
		log "Your battery is currently being maintained at $maintain_percentage%"
	fi
	exit 0

fi

# Status logger in csv format
if [[ "$action" == "status_csv" ]]; then

	echo "$(get_battery_percentage),$(get_remaining_time),$(get_smc_charging_status),$(get_smc_discharging_status),$(get_maintain_percentage)"

fi

# launchd daemon creator, inspiration: https://www.launchd.info/
if [[ "$action" == "create_daemon" ]]; then

	daemon_definition="
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
	<dict>
		<key>Label</key>
		<string>com.battery.app</string>
		<key>ProgramArguments</key>
		<array>
			<string>$binfolder/battery</string>
			<string>maintain_synchronous</string>
			<string>recover</string>
		</array>
		<key>StandardOutPath</key>
		<string>$logfile</string>
		<key>StandardErrorPath</key>
		<string>$logfile</string>
		<key>RunAtLoad</key>
		<true/>
	</dict>
</plist>
"

	mkdir -p "${daemon_path%/*}"

	# check if daemon already exists
	if test -f "$daemon_path"; then

		log "Daemon already exists, checking for differences"
		daemon_definition_difference=$(diff --brief --ignore-space-change --strip-trailing-cr --ignore-blank-lines <(cat "$daemon_path" 2>/dev/null) <(echo "$daemon_definition"))

		# remove leading and trailing whitespaces
		daemon_definition_difference=$(echo "$daemon_definition_difference" | xargs)
		if [[ "$daemon_definition_difference" != "" ]]; then

			log "daemon_definition changed: replace with new definitions"
			echo "$daemon_definition" >"$daemon_path"

		fi
	else

		# daemon not available, create new launch deamon
		log "Daemon does not yet exist, creating daemon file at $daemon_path"
		echo "$daemon_definition" >"$daemon_path"

	fi

	# enable daemon
	launchctl enable "gui/$(id -u $USER)/com.battery.app"
	exit 0

fi

# Disable daemon
if [[ "$action" == "disable_daemon" ]]; then

	log "Disabling daemon at gui/$(id -u $USER)/com.battery.app"
	launchctl disable "gui/$(id -u $USER)/com.battery.app"
	exit 0

fi

# Remove daemon
if [[ "$action" == "remove_daemon" ]]; then

	rm $daemon_path 2>/dev/null
	exit 0

fi

# Display logs
if [[ "$action" == "logs" ]]; then

	amount="${2:-100}"

	echo -e "👾 Battery CLI logs:\n"
	tail -n $amount $logfile

	echo -e "\n🖥️  Battery GUI logs:\n"
	tail -n $amount "$configfolder/gui.log"

	echo -e "\n📁 Config folder details:\n"
	ls -lah $configfolder

	echo -e "\n⚙️  Battery data:\n"
	battery status
	battery | grep -E "v\d.*"

	exit 0

fi
