#!/bin/bash

## ###############
## Update management
## variables are used by this binary as well at the update script
## ###############
BATTERY_CLI_VERSION="v1.3.4"

# If a script may run as root:
#   - Reset PATH to safe defaults at the very beginning of the script.
#   - Never include user-owned directories in PATH.
PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Ensure Ctrl+C stops the entire script, not just the current command
trap 'exit 130' INT

## ###############
## Variables
## ###############
visudo_folder=/private/etc/sudoers.d
visudo_file=${visudo_folder}/battery
configfolder=$HOME/.battery
logfile=$configfolder/battery.log
calibration_progress_file=$configfolder/calibration.progress
maintain_percentage_tracker_file=$configfolder/maintain.percentage
maintain_voltage_tracker_file=$configfolder/maintain.voltage
maintain_force_discharge_file=$configfolder/maintain.force-discharge
daemon_path=$HOME/Library/LaunchAgents/battery.plist
launchd_job_label=com.actuallymentor.battery.app
launchd_job_domain="gui/$(id -u)"
launchd_job_service="$launchd_job_domain/$launchd_job_label"
path_configfile=/etc/paths.d/50-battery

# Percentage limits
percentage_min="20"

# Voltage limits
voltage_min="10.5"
voltage_max="12.6"
voltage_hyst_min="0.1"
voltage_hyst_max="2"

# SECURITY NOTES:
# - ALWAYS hardcode and use the absolute path to the battery executables to avoid PATH-based spoofing.
#   Think of the scenario where 'battery update_silent' running as root invokes 'battery visudo' as a
#   PATH spoofing opportunity example.
# - Ensure this script, smc binary and their parent folders are root-owned and not writable by
#   the user or others.
# - Ensure that you are not sourcing any user-writable scripts within this script to avoid overrides of
#   security critical variables.
binfolder="/usr/local/co.palokaj.battery"
battery_binary="$binfolder/battery"
smc_binary="$binfolder/smc"

# Fixed absolute paths to system tools.
sw_vers_binary="/usr/bin/sw_vers"
defaults_binary="/usr/bin/defaults"
notifyutil_binary="/usr/bin/notifyutil"
plutil_binary="/usr/bin/plutil"

# GitHub URLs for setup and updates.
# Temporarily set to your username and branch to test update functionality with your fork.
# Security note: Do NOT allow github_user or github_branch to be injected via environment
#                variables or any other means. Keep them hardcoded.
github_user="actuallymentor"
github_branch="main"
github_url_setup_sh="https://raw.githubusercontent.com/${github_user}/battery/${github_branch}/setup.sh"
github_url_update_sh="https://raw.githubusercontent.com/${github_user}/battery/${github_branch}/update.sh"
github_url_battery_sh="https://raw.githubusercontent.com/${github_user}/battery/${github_branch}/battery.sh"

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
	if log_tail=$(tail -n 1000 "$logfile"); then
		printf '%s\n' "$log_tail" >"$logfile"
	fi
	unset log_tail
fi

# CLI help message
helpmessage="
Battery CLI utility $BATTERY_CLI_VERSION

Usage:

  battery status
    output battery SMC status, % and time remaining

  battery stop
    terminate the current background job (maintenance, etc.), enable charging, and disable forced discharging
    the terminated job will not start automatically on the next reboot

  battery maintain PERCENTAGE[${percentage_min}-100] or RANGE[lower-upper]
    reboot-persistent battery charge level maintenance: keep the battery at a specified percentage or range
    eg: battery maintain 80           # maintain at 80%
    eg: battery maintain 70-80        # maintain between 70% and 80%
    use --force-discharge to discharge the battery to the target level first

  battery maintain VOLTAGE[${voltage_min}V-${voltage_max}V] (HYSTERESIS[${voltage_hyst_min}V-${voltage_hyst_max}V])
    reboot-persistent battery voltage maintenance: keep the battery voltage within a specified range
    default hysteresis: 0.1V
    eg: battery maintain 11.4V       # keeps battery between 11.3V and 11.5V
    eg: battery maintain 11.4V 0.3V  # keeps battery between 11.1V and 11.7V
    use --force-discharge to discharge the battery to the target voltage first, but never below 20% charge

  battery charging SETTING[on/off]
    manually disable or enable battery charging
    'battery charging off' still allows battery charging up to ${percentage_min}%
    eg: battery charging on

  battery adapter SETTING[on/off]
    manually set the adapter to (not) charge even when plugged in
    eg: battery adapter off

  battery charge LEVEL[${percentage_min}-100]
    charge the battery to a certain percentage; battery maintenance is restored upon completion
    eg: battery charge 90

  battery discharge LEVEL[1-100]
    block adapter power until the battery reaches the specified level; battery maintenance is restored upon completion
    eg: battery discharge 90

  battery discharge VOLTAGE[${voltage_min}V-${voltage_max}V]
    block adapter power until voltage is at or below the target; battery maintenance is restored upon completion
    eg: battery discharge 11.4V

  battery calibrate
    on macOS Sequoia and earlier, cycle the battery through discharge and recharge stages, giving the system a
    chance to recalibrate battery charge and capacity estimates; newer macOS versions may handle this automatically
    the command will discharge the battery to 15%, charge it to 100%, maintain charging for 1 hour, and then
    discharge it back to 80%.

  battery logs LINES[integer, optional]
    output logs of the battery CLI and GUI
    eg: battery logs 100

  battery dump_controls
    display SMC controls and, on macOS Tahoe 26 and later, native charge-limit preferences

  battery update
    update the battery utility to the latest version

  battery reinstall
    reinstall the battery utility to the latest version (reruns the installation script)

  battery uninstall
    enable charging, remove the smc tool, and the battery script

"

# Visudo instructions
# File location: /etc/sudoers.d/battery
# Purpose:
# - Allows this script to execute 'sudo smc -w' commands without requiring a user password.
# - Allows passwordless updates.
# - Allows passwordless mcl_smc and mcl_prefs charge-limit actions and scoped preference reads.
visudoconfig="
# Visudo settings for the battery utility installed from https://github.com/actuallymentor/battery
# intended to be placed in $visudo_file on a mac

# Allow passwordless update (All battery app executables are owned by root to prevent privilege escalation attacks)
ALL ALL = NOPASSWD: $battery_binary update_silent
ALL ALL = NOPASSWD: $battery_binary update_silent is_enabled

# Allow passwordless mcl_smc charge-limit actions
ALL ALL = NOPASSWD: $battery_binary _set_charge_limit_mcl_smc *
ALL ALL = NOPASSWD: $battery_binary _reset_charge_limit_mcl_smc

# Allow passwordless mcl_prefs charge-limit actions and root preference reads
ALL ALL = NOPASSWD: $battery_binary _set_charge_limit_mcl_prefs *
ALL ALL = NOPASSWD: $battery_binary _reset_charge_limit_mcl_prefs
ALL ALL = NOPASSWD: $defaults_binary read com.apple.smartcharging.topoffprotection MCLFeatureState
ALL ALL = NOPASSWD: $defaults_binary read com.apple.smartcharging.topoffprotection mclLimitValue

# Allow detection of forced battery gauging on macOS 27
ALL ALL = NOPASSWD: $plutil_binary -extract batteryGaugingMitigationInfo.lastFullChargeReq xml1 -o - /private/var/root/Library/Preferences/com.apple.powerd.batterygauging.plist

# Allow passwordless battery-charging-related SMC write commands
Cmnd_Alias    CHARGING_OFF = $smc_binary -k CH0B -w 02, $smc_binary -k CH0C -w 02, $smc_binary -k CHTE -w 01000000
Cmnd_Alias    CHARGING_ON = $smc_binary -k CH0B -w 00, $smc_binary -k CH0C -w 00, $smc_binary -k CHTE -w 00000000
Cmnd_Alias    FORCE_DISCHARGE_OFF = $smc_binary -k CH0I -w 00, $smc_binary -k CHIE -w 00, $smc_binary -k CH0J -w 00
Cmnd_Alias    FORCE_DISCHARGE_ON = $smc_binary -k CH0I -w 01, $smc_binary -k CHIE -w 08, $smc_binary -k CH0J -w 01
Cmnd_Alias    LED_CONTROL = $smc_binary -k ACLC -w 04, $smc_binary -k ACLC -w 03, $smc_binary -k ACLC -w 02, $smc_binary -k ACLC -w 01, $smc_binary -k ACLC -w 00
ALL ALL = NOPASSWD: CHARGING_OFF
ALL ALL = NOPASSWD: CHARGING_ON
ALL ALL = NOPASSWD: FORCE_DISCHARGE_OFF
ALL ALL = NOPASSWD: FORCE_DISCHARGE_ON
ALL ALL = NOPASSWD: LED_CONTROL
"

# Get parameters
action=$1
setting=$2
subsetting=$3

## ###############
## Helpers
## ###############

function log() {
	local line="$(date +%D-%T) [$$]: $*"
	printf '%s\n' "$line" || return

	# Write also to the log file if stdout is not already redirected to the log file.
	{
		# Compare both descriptors: macOS may report different device for the pathname.
		if [[ ! /dev/fd/1 -ef /dev/fd/3 ]]; then
			printf '%s\n' "$line" >&3
		fi
	} 3>>"$logfile"
}

function smc_read_hex() {
	local key=$1 line
	line=$(echo $($smc_binary -k $key -r))
	if [[ $line =~ "no data" ]]; then
		echo
	else
		echo ${line#*bytes} | tr -d ' ' | tr -d ')'
	fi
}

function smc_write_hex() {
	local key=$1
	local hex_value=$2
	local actual expected
	if ! sudo $smc_binary -k "$key" -w "$hex_value" >/dev/null; then
		log "⚠️ Failed to write $hex_value to $key"
		return 1
	fi
	expected=$(printf '%s' "$hex_value" | tr '[:lower:]' '[:upper:]')
	actual=$(smc_read_hex "$key" | tr '[:lower:]' '[:upper:]')
	if [[ -z "$actual" ]]; then
		log "⚠️ Unable to verify $key after writing $hex_value"
	elif [[ "$actual" != "$expected" ]]; then
		log "⚠️ Failed to verify $key: wrote $expected, read $actual"
	fi
	return 0
}

## #########################
## Detect supported SMC keys
## #########################
function smc_key_available() {
	[[ $("$smc_binary" -k "$1" -r) == *"(bytes "* ]]
}
smc_key_available CHTE && smc_supports_CHTE=true || smc_supports_CHTE=false
smc_key_available CH0B && smc_supports_CH0B=true || smc_supports_CH0B=false
smc_key_available CHIE && smc_supports_adapter_chie=true || smc_supports_adapter_chie=false
smc_key_available CH0I && smc_supports_adapter_ch0i=true || smc_supports_adapter_ch0i=false
smc_key_available CH0J && smc_supports_adapter_ch0j=true || smc_supports_adapter_ch0j=false
smc_key_available ACLC && smc_supports_ACLC=true || smc_supports_ACLC=false
smc_key_available bfD0 &&
smc_key_available bfE0 &&
smc_key_available bfF0 && smc_supports_bfF0=true || smc_supports_bfF0=false

## ###############################
## Detect charging control backend
## ###############################

# On macOS Tahoe 26 and later:
#   - Try using mcl_smc and fall back to mcl_prefs if mcl_smc is unavailable.
# On macOS Sequoia 15 and earlier:
#   - Try using mcl_smc and fall back to legacy controls if mcl_smc is unavailable.
function detect_charging_backend() {
	local macos_version macos_major
	macos_version=$("$sw_vers_binary" -productVersion) || macos_version=""
	macos_major="${macos_version%%.*}"

	if [[ "$smc_supports_bfF0" == "true" ]]; then
		echo "mcl_smc"
	elif [[ "$macos_major" =~ ^[0-9]+$ ]] && [[ "$macos_major" -ge 26 ]]; then
		echo "mcl_prefs"
	elif [[ "$smc_supports_CHTE" == "true" ]]; then
		echo "CHTE"
	elif [[ "$smc_supports_CH0B" == "true" ]]; then
		echo "CH0B"
	fi
}

charging_backend="$(detect_charging_backend)"

function log_system_capabilities() {
	local script_hash=$(set -o pipefail; shasum -a 256 "$battery_binary" 2>/dev/null | cut -c1-8) || script_hash="not installed"
	log "Battery ${BATTERY_CLI_VERSION} (${script_hash}); macOS=$($sw_vers_binary -productVersion); Charging backend=$charging_backend"
	log "SMC capabilities: bfF0=$smc_supports_bfF0 CHTE=$smc_supports_CHTE CH0B=$smc_supports_CH0B CHIE=$smc_supports_adapter_chie CH0I=$smc_supports_adapter_ch0i CH0J=$smc_supports_adapter_ch0j ACLC=$smc_supports_ACLC"
}

## ####################################################
## Manual Charge Limit (MCL) helpers
##   mcl_smc - using bfF0 smc registers family
##   mcl_prefs - Using macOS defaults and notifications
## ####################################################

# With the "mcl_smc" and "mcl_prefs" backends, we disable charging by setting the charge limit
# to the current battery charge level. Setting the limit below the current charge level causes
# the firmware to discharge the battery, even when the power adapter is connected. To keep the
# battery in pass-through mode, we set the charge limit to the current charge level and adjust
# it whenever the charge level changes.
#
# By default, the Manual Charge Limit (MCL) is restricted to the range of ${percentage_min}% to 80%.
# The 80% upper bound can be explicitly overridden by setting a higher maintenance percentage.
# This default upper bound accounts for occasional macOS battery calibration, during which MCL
# temporarily stops working and the battery may charge to 100%. Once calibration is completed,
# the 80% upper bound allows the battery to discharge back to 80%, preventing it from remaining
# at a high charge level for an extended period without the user noticing. The downside is that
# the battery may be unnecessarily discharged to 80% after calibration. This is an intentional
# trade-off to minimize the risk of battery swelling.
#
# The limit follows the current charge level between the maintenance range's lower bound and its
# effective upper bound (at least 80%). Outside this range, the limit is clamped to the nearest
# bound, allowing the battery to charge or discharge toward it.
#
# The charge limit is calculated from the current charge level and the maintenance range using
# the following formula:
#
#   limit = max(range_lower, min(current_charge, max(80, range_upper)))
#
# When a single percentage is specified as the maintenance target, range_lower and range_upper
# are equal.
function calc_mcl_charge_limit() {
	local range_lower="$1"
	local range_upper="$2"
	local current_charge="$3"
	local limit

	limit=$((range_upper > 80 ? range_upper : 80))
	limit=$((current_charge < limit ? current_charge : limit))
	limit=$((limit > range_lower ? limit : range_lower))
	echo "$limit"
}

function apply_mcl_smc_charge_limit() {
	if ! sudo -n "$battery_binary" _set_charge_limit_mcl_smc "$1"; then
		log "⚠️ Action execution has failed: _set_charge_limit_mcl_smc $1; attempting recovery reset"
		if ! sudo -n "$battery_binary" _reset_charge_limit_mcl_smc; then
			log "⚠️ mcl_smc recovery reset failed; charging state may be partially applied"
		fi
		return 1
	fi
	return 0
}

function apply_mcl_prefs_charge_limit() {
	if ! sudo -n "$battery_binary" _set_charge_limit_mcl_prefs "$1"; then
		log "⚠️ Action execution has failed: _set_charge_limit_mcl_prefs $1"
		return 1
	fi
	return 0
}

# Maintain disabled charging using the caller's bounds and charge reading.
function mcl_maintain_disabled_charging() {
	if [[ "$charging_backend" != "mcl_smc" && "$charging_backend" != "mcl_prefs" ]]; then
		return 0
	fi

	local limit
	limit=$(calc_mcl_charge_limit "$1" "$2" "$3")

	if [[ "$charging_backend" == "mcl_prefs" ]]; then
		apply_mcl_prefs_charge_limit "$limit" || return 1
	elif [[ "$charging_backend" == "mcl_smc" ]]; then
		apply_mcl_smc_charge_limit "$limit" || return 1
	fi

	return 0
}

# Prints none, suspected, or detected; returns failure when the request cannot be read.
function mcl_prefs_get_macos_calibration_status() {
	[[ "$charging_backend" == "mcl_prefs" ]] || { echo none; return 0; }
	local request output
	if ! request=$(sudo -n "$plutil_binary" -extract batteryGaugingMitigationInfo.lastFullChargeReq xml1 -o - /private/var/root/Library/Preferences/com.apple.powerd.batterygauging.plist); then
		log "⚠️  macOS battery calibration detection: failed to read the plist${request:+: $request}" >&2
		return 1
	fi
	case "$request" in
		*'<true/>'*) ;;
		*'<false/>'*) echo none; return 0 ;; # the required condition is not satisfied
		*) log "⚠️  macOS battery calibration detection: unexpected plist value" >&2; return 1 ;;
	esac

	# Check whether the sufficient condition is met
	if ! output=$(/usr/bin/log show --last 6h --info --debug --style compact --predicate 'process == "PowerUIAgent"'); then
		log "⚠️  macOS battery calibration detection: failed to read PowerUIAgent logs" >&2
		echo suspected
	elif grep -Eiq 'ChargingUpForGauging|mitigations are in place' <<<"$output"; then
		echo detected
	else
		$battery_binary _notify_mcl_prefs_changed >&2 # Try triggering PowerUIAgent logs for a later check
		echo suspected
	fi
}

function detect_and_report_macos27_calibration() {
	[[ "$charging_backend" == "mcl_prefs" ]] || return 0
	local status message now last_notification
	status=$(mcl_prefs_get_macos_calibration_status) || return 1
	if [[ "$status" == "none" ]]; then
		macos_calibration_last_suspected_notification=0
		macos_calibration_last_detected_notification=0
		return 0
	fi
	message="⚠️  macOS battery calibration $status. macOS may temporarily override the MCL and charge the battery to 100%."
	log "$message"
	[[ "$1" == "show_system_notification" ]] || return 0

	case "$status" in
		suspected) last_notification=${macos_calibration_last_suspected_notification:-0} ;;
		detected) last_notification=${macos_calibration_last_detected_notification:-0} ;;
		*) return 0 ;;
	esac
	now=$(date +%s)
	if [[ "$last_notification" -ne 0 ]] && ((now - last_notification < 86400)); then return 0; fi

	message+=$'\n'"Use 'battery status' to see when it ends."
	if ! /usr/bin/osascript \
		-e 'on run {message}' \
		-e 'display notification message with title "actuallymentor/battery"' \
		-e 'end run' \
		"$message" ; then
		log "⚠️ Failed to send the macOS battery calibration desktop notification" >&2
		return 1
	fi
	case "$status" in
		suspected) macos_calibration_last_suspected_notification=$now ;;
		detected) macos_calibration_last_detected_notification=$now ;;
	esac
}

## ###########################################
## Charging/Discharging Controls Manipulations
## ###########################################

# Synchronize MagSafe LED state with the current state of charging and discharging controls.
# see community sleuthing: https://github.com/actuallymentor/battery/issues/71
function update_magsafe_led_color() {
	[[ "$smc_supports_ACLC" == "true" ]] || return 0

	if [[ "$(get_discharging_control_status)" == "discharging" ]]; then
		# Turn the LED off if forced discharging is enabled.
		smc_write_hex ACLC 01
	else
		case "$(get_charging_control_status)" in
			disabled)
				# Show green if charging is disabled
				smc_write_hex ACLC 03 ;;
			enabled)
				# Show orange if charging is enabled
				smc_write_hex ACLC 04 ;;
			*)
				# Reset the LED if charging status is unknown
				smc_write_hex ACLC 00 ;;
		esac
	fi
}

# Re:discharging, we're using keys uncovered by @howie65: https://github.com/actuallymentor/battery/issues/20#issuecomment-1364540704
# CH0I seems to be the "disable the adapter" key
function enable_discharging() {
	log "🔽🪫 Enabling battery discharging"
	if [[ "$smc_supports_adapter_chie" == "true" ]]; then
		smc_write_hex CHIE 08
	elif [[ "$smc_supports_adapter_ch0j" == "true" ]]; then
		smc_write_hex CH0J 01
	else
		smc_write_hex CH0I 01
	fi
	update_magsafe_led_color
}

function disable_discharging() {
	log "🔼🪫 Disabling battery discharging"
	if [[ "$smc_supports_adapter_chie" == "true" ]]; then
		smc_write_hex CHIE 00
	elif [[ "$smc_supports_adapter_ch0j" == "true" ]]; then
		smc_write_hex CH0J 00
	elif [[ "$smc_supports_adapter_ch0i" == "true" ]]; then
		smc_write_hex CH0I 00
	else
		smc_write_hex CH0I 00
	fi
	update_magsafe_led_color
}

function enable_charging() {
	log "🔌🔋 Enabling battery charging"
	if [[ "$charging_backend" == "mcl_smc" ]]; then
		sudo -n "$battery_binary" _reset_charge_limit_mcl_smc
	elif [[ "$charging_backend" == "mcl_prefs" ]]; then
		sudo -n "$battery_binary" _reset_charge_limit_mcl_prefs
	elif [[ "$charging_backend" == "CHTE" ]]; then
		smc_write_hex CHTE 00000000
	elif [[ "$charging_backend" == "CH0B" ]]; then
		# Re:charging, Aldente uses CH0B https://github.com/davidwernhart/AlDente/blob/0abfeafbd2232d16116c0fe5a6fbd0acb6f9826b/AlDente/Helper.swift#L227
		# but @joelucid uses CH0C https://github.com/davidwernhart/AlDente/issues/52#issuecomment-1019933570
		# so I'm using both since with only CH0B I noticed sometimes during sleep it does trigger charging
		smc_write_hex CH0B 00
		smc_write_hex CH0C 00
	else
		log "⚠️ Unable to reset charging state"
	fi
	disable_discharging
	update_magsafe_led_color
}

function disable_charging() {
	log "🔌🪫 Disabling battery charging"
	if [[ "$charging_backend" == "mcl_smc" ]]; then
		apply_mcl_smc_charge_limit "$(calc_mcl_charge_limit "$percentage_min" 80 "$(get_battery_percentage)")"
	elif [[ "$charging_backend" == "mcl_prefs" ]]; then
		apply_mcl_prefs_charge_limit "$(calc_mcl_charge_limit "$percentage_min" 80 "$(get_battery_percentage)")"
	elif [[ "$charging_backend" == "CHTE" ]]; then
		smc_write_hex CHTE 01000000
	elif [[ "$charging_backend" == "CH0B" ]]; then
		smc_write_hex CH0B 02
		smc_write_hex CH0C 02
	else
		log "⚠️ Unable to determine a backend for disabling charging"
		return 1
	fi
	update_magsafe_led_color
}

# Reports configured charging-control intent, not observed charging activity.
function get_charging_control_status() {
	local hex_status
	if [[ "$charging_backend" == "mcl_prefs" ]]; then
		local state
		state=$(sudo -n "$defaults_binary" read "com.apple.smartcharging.topoffprotection" MCLFeatureState 2>/dev/null) || state=""
		case "$state" in
			0) echo "enabled" ;;
			1) echo "disabled" ;;
			*) echo "unknown" ;;
		esac
	elif [[ "$charging_backend" == "mcl_smc" ]]; then
		hex_status=$(smc_read_hex bfF0)
		case "$hex_status" in
			00) echo "enabled" ;;
			02) echo "disabled" ;;
			*) echo "unknown" ;;
		esac
	elif [[ "$charging_backend" == "CHTE" ]]; then
		hex_status=$(smc_read_hex CHTE)
		case "$hex_status" in
			"") echo "unknown" ;;
			00000000) echo "enabled" ;;
			*) echo "disabled" ;;
		esac
	elif [[ "$charging_backend" == "CH0B" ]]; then
		hex_status=$(smc_read_hex CH0B)
		case "$hex_status" in
			"") echo "unknown" ;;
			00) echo "enabled" ;;
			*) echo "disabled" ;;
		esac
	else
		echo "unknown"
	fi
}

function get_discharging_control_status() {
	local status_key="CH0I"
	if [[ "$smc_supports_adapter_chie" == "true" ]]; then
		status_key="CHIE"
	elif [[ "$smc_supports_adapter_ch0j" == "true" ]]; then
		status_key="CH0J"
	fi
	hex_status=$(smc_read_hex "$status_key")
	if [[ -z "$hex_status" ]]; then
		echo "unknown"
		return
	fi
	if [[ "$hex_status" == "0" || "$hex_status" == "00" ]]; then
		echo "not discharging"
	else
		echo "discharging"
	fi
}

## ###############
## launchd helpers
## ###############

# Print whether the job is absent, registered but stopped, or running. No arguments.
function launchd_job_get_state() {
	assert_not_running_as_root >&2
	local jobs
	jobs=$(launchctl list) || {
		log "❌ 'launchctl list' failed (exit $?) ${jobs:+: $jobs}" >>"$logfile"
		return 1
	}
	printf '%s\n' "$jobs" | awk -v label="$launchd_job_label" '
		$3 == label {
			print ($1 == "-" ? "registered_and_not_running" : "registered_and_running")
			found = 1
			exit
		}
		END { if (!found) print "not_registered_and_not_running" }' || {
			log "❌ awk failed while reading 'launchctl list' output (exit $?)" >>"$logfile"
			return 1
		}
} 2>>"$logfile"

# Print the running job's Battery action. No arguments; the plist must describe the loaded job.
# Return 1 when not running and 2 on query or extraction failure.
function launchd_job_get_running_action() {
	local state definition action_pattern='<string>([a-z0-9_]+)</string>'
	state=$(launchd_job_get_state) || return 2
	[[ "$state" == "registered_and_running" ]] || return 1
	# XML extraction works on Big Sur; plutil's raw format requires macOS 12.
	definition=$("$plutil_binary" -extract ProgramArguments.1 xml1 -o - "$daemon_path") || {
		log "❌ plutil extract ProgramArguments.1 failed for LaunchAgent plist (exit $?)${definition:+: $definition}" >>"$logfile"
		return 2
	}
	if [[ "$definition" =~ $action_pattern ]]; then
		printf '%s\n' "${BASH_REMATCH[1]}"
	else
		log "❌ Unable to read the Battery background action from the LaunchAgent plist" >>"$logfile"
		return 2
	fi
} 2>>"$logfile"

# Create/overwrite the LaunchAgent plist; requires an unloaded job and removes the plist on failure.
# Arguments: RUN_AT_LOAD (true/false) LOGFILE (output file path) ACTION [ARGUMENTS...].
function launchd_job_write_plist() {
	assert_not_running_as_root
	local run_at_load="$1" job_log="$2" argument state result=0 index=1
	shift 2 || return

	state=$(launchd_job_get_state) || return
	if [[ "$state" != "not_registered_and_not_running" ]]; then
		log "❌ LaunchAgent must be unloaded before writing its plist"
		exit 1
	fi

	mkdir -p "${daemon_path%/*}" || result=1
	"$plutil_binary" -convert xml1 -o "$daemon_path" - <<< '{}' || result=1
	"$plutil_binary" -insert Label -string "$launchd_job_label" "$daemon_path" || result=1
	"$plutil_binary" -insert ProgramArguments -array "$daemon_path" || result=1
	"$plutil_binary" -insert ProgramArguments.0 -string "$battery_binary" "$daemon_path" || result=1
	for argument in "$@"; do
		"$plutil_binary" -insert "ProgramArguments.$index" -string "$argument" "$daemon_path" || result=1
		index=$((index + 1))
	done
	"$plutil_binary" -insert StandardInPath -string /dev/null "$daemon_path" || result=1
	"$plutil_binary" -insert StandardOutPath -string "$job_log" "$daemon_path" || result=1
	"$plutil_binary" -insert StandardErrorPath -string "$job_log" "$daemon_path" || result=1
	"$plutil_binary" -insert RunAtLoad -bool "$run_at_load" "$daemon_path" || result=1
	"$plutil_binary" -insert KeepAlive -bool false "$daemon_path" || result=1
	"$plutil_binary" -lint -s "$daemon_path" || result=1
	if [[ "$result" -ne 0 ]]; then
		log "❌ Failed to create LaunchAgent plist"
		rm -f "$daemon_path" || log "❌ Failed to remove incomplete LaunchAgent plist (exit $?)"
	fi
	return "$result"
}

# Remove the job's registration from the user's GUI launchd domain, stopping it if running.
# No arguments; an absent job succeeds. Leaves the plist file on disk.
function launchd_job_bootout() {
	assert_not_running_as_root
	local state
	state=$(launchd_job_get_state) || return
	[[ "$state" == "not_registered_and_not_running" ]] && return 0
	launchctl bootout "$launchd_job_service" || {
		log "❌ launchctl bootout failed (exit $?)"
		return 1
	}
}

# Remove the previous job from launchd, write its replacement plist, then enable, register, and start it.
# Arguments: RUN_AT_LOAD (true/false) LOGFILE (output file path) ACTION [ARGUMENTS...].
function launchd_job_start_new() {
	launchd_job_bootout || return
	launchd_job_write_plist "$@" || return
	launchctl enable "$launchd_job_service" || { log "❌ launchctl enable failed (exit $?)"; return 1; }
	launchctl bootstrap "$launchd_job_domain" "$daemon_path" || { log "❌ launchctl bootstrap failed (exit $?)"; return 1; }
	# Jobs without RunAtLoad need an explicit start after registration.
	if [[ "$1" == "false" ]]; then
		launchctl kickstart "$launchd_job_service" || { log "❌ launchctl kickstart failed (exit $?)"; return 1; }
	fi
	return 0
}

# Disable the job, remove it from launchd, and delete its plist, attempting every step after failures.
# No arguments; return 1 if any cleanup step fails.
function launchd_job_stop_and_remove() {
	assert_not_running_as_root
	local result=0
	launchctl disable "$launchd_job_service" || { log "❌ launchctl disable failed (exit $?)"; result=1; }
	launchd_job_bootout || result=1
	rm -f "$daemon_path" || { log "❌ Failed to remove LaunchAgent plist (exit $?)"; result=1; }
	return "$result"
}

## ###############
## Statistics
## ###############

function get_battery_percentage() {
	battery_percentage=$(pmset -g batt | tail -n1 | awk '{print $3}' | sed s:\%\;::)
	echo "$battery_percentage"
}

function get_remaining_time() {
	pmset -g batt | awk '{
			for (i = 1; i < NF; i++) if ($i ~ /^[0-9]+:[0-5][0-9]$/ && $(i + 1) == "remaining") remaining = $i
		} END { print (remaining == "" ? "unknown" : remaining) }'
}

function get_charger_state() {
	ac_attached=$(pmset -g batt | tail -n1 | awk '{ x=match($0, /AC attached/) > 0; print x }')
	echo "$ac_attached"
}

function get_maintain_percentage() {
	maintain_percentage=$(cat $maintain_percentage_tracker_file 2>/dev/null)
	echo "$maintain_percentage"
}

function get_voltage() {
	voltage=$(ioreg -l -n AppleSmartBattery -r | LC_ALL=C awk -F= '/^[[:space:]|]*"Voltage"[[:space:]]*=/ { print $2 / 1000 }')
	echo "$voltage"
}

## ########################################
## Maintenance arguments and config helpers
## ########################################

function valid_percentage() {
	[[ "$1" =~ ^[0-9]+$ && "$1" -ge 0 && "$1" -le 100 ]]
}

function valid_maintenance_percentage() {
	valid_percentage "$1" && [[ "$1" -ge "$percentage_min" ]]
}

function valid_maintenance_percentage_range() {
	local lower="${1%-*}"
	local upper="${1#*-}"
	valid_maintenance_percentage "$lower" && valid_maintenance_percentage "$upper" && [[ "$lower" -lt "$upper" ]]
}

function valid_voltage() {
	[[ "$1" =~ ^[0-9]+(\.[0-9]+)?V$ ]]
}

function valid_maintenance_voltage() {
	local voltage="${1%V}" hysteresis="${2%V}"
	valid_voltage "$1" && valid_voltage "$2" &&
		[[ "$(echo "$voltage >= $voltage_min && $voltage <= $voltage_max && $hysteresis >= $voltage_hyst_min && $hysteresis <= $voltage_hyst_max" | bc -l)" == "1" ]]
}

# Save a validated true/false pending flag. Example: maintenance_force_discharge_config_save true
function maintenance_force_discharge_config_save() {
	printf '%s\n' "$1" >"$maintain_force_discharge_file" || {
		log "❌ Failed to save force-discharge request"
		return 1
	}
}

# Load and validate cfg_force_discharge
function maintenance_force_discharge_config_load() {
	cfg_force_discharge=false
	if [[ -e "$maintain_force_discharge_file" ]]; then
		cfg_force_discharge=$(cat "$maintain_force_discharge_file") &&
			[[ "$cfg_force_discharge" == "true" || "$cfg_force_discharge" == "false" ]] || {
			log "❌ Invalid force-discharge config value; expected true or false"
			return 1
		}
	fi
	return 0
}

# Save maintenance percentage and '--force-discharge' flag
# Examples: percentage_maintenance_config_save 80 false; percentage_maintenance_config_save 70-80 true
function percentage_maintenance_config_save() {
	rm -f "$maintain_voltage_tracker_file" && printf '%s\n' "$1" >"$maintain_percentage_tracker_file" || {
		log "❌ Failed to save percentage maintenance target"
		return 1
	}
	maintenance_force_discharge_config_save "$2"
}

# Load and validate cfg_percentage and cfg_force_discharge
function percentage_maintenance_config_load() {
	cfg_percentage=$(cat "$maintain_percentage_tracker_file") &&
		{ valid_maintenance_percentage "$cfg_percentage" || valid_maintenance_percentage_range "$cfg_percentage"; } || {
		log "❌ Invalid maintenance percentage config value"
		return 1
	}
	maintenance_force_discharge_config_load
}

# Save validated voltage, hysteresis and '--force-discharge' flag
# Example: voltage_maintenance_config_save 11.4V 0.1V true; target values are saved without V.
function voltage_maintenance_config_save() {
	rm -f "$maintain_percentage_tracker_file" && printf '%s %s\n' "${1%V}" "${2%V}" >"$maintain_voltage_tracker_file" || {
		log "❌ Failed to save voltage maintenance target."
		return 1
	}
	maintenance_force_discharge_config_save "$3"
}

# Load and validate cfg_voltage, cfg_voltage_hysteresis, and cfg_force_discharge
function voltage_maintenance_config_load() {
	read -r cfg_voltage cfg_voltage_hysteresis < "$maintain_voltage_tracker_file" &&
		valid_maintenance_voltage "${cfg_voltage}V" "${cfg_voltage_hysteresis}V" || {
		log "❌ Invalid maintenance voltage or hysteresis config values"
		return 1
	}
	maintenance_force_discharge_config_load
}

## ##################
## Miscellany helpers
## ##################

function determine_unprivileged_user() {
	local username="$1"
	if [[ "$username" == "root" ]]; then
		log "⚠️ 'battery $action $setting $subsetting': argument user is root, trying to recover" >&2
		username=""
	fi
	if [[ -z "$username" && -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
		username="$SUDO_USER"
	fi
	if [[ -z "$username" ]]; then
		username=$(stat -f '%Su' /dev/console) || username=""
		if [[ "$username" == "root" ]]; then username=""; fi
	fi
	if [[ -z "$username" && -n "$USER" && "$USER" != "root" ]]; then
		username="$USER"
	fi
	if [[ -z "$username" && "$HOME" == /Users/* ]]; then
		username="$(basename "$HOME")";
	fi
	if [[ -z "$username" ]]; then
		log "⚠️ 'battery $action $setting $subsetting': unable to determine unprivileged user; falling back to 'logname'" >&2
		username="$(logname 2>/dev/null || true)"
	fi
	echo "$username"
}

function run_as_unprivileged_user() (
	if [[ $EUID -ne 0 ]]; then "$@"; return; fi
	local username
	username=$(determine_unprivileged_user "$SUDO_USER") || return
	assert_unprivileged_user "$username"
	sudo -H -u "$username" "$@"
)

function exit_on_error() {
	[[ "$1" -eq 0 ]] && return 0
	log "❌ $2"
	exit 1
}

function assert_unprivileged_user() {
	local username="$1"
	if [[ -z "$username" || "$username" == "root" ]]; then
		log "❌ 'battery $action $setting $subsetting': failed to determine unprivileged user"
		exit 11
	fi
}

function assert_not_running_as_root() {
	if [[ $EUID -eq 0 ]]; then
		echo " ❌ The following command should not be executed with root privileges:"
		echo "        battery $action $setting $subsetting"
		echo "    Please, try running without 'sudo'"
		exit 1
	fi
}

function assert_running_as_root() {
	if [[ $EUID -ne 0 ]]; then
		log "❌ battery $action $setting $subsetting: must be executed with root privileges"
		exit 1
	fi
}

function ensure_owner() {
	local owner="$1" group="$2" path="$3"
	[[ -e $path ]] || { return 1; }
	local cur_owner=$(stat -f '%Su' "$path")
	local cur_group=$(stat -f '%Sg' "$path")
	if [[ $cur_owner != "$owner" || $cur_group != "$group" ]]; then
		sudo chown -h "${owner}:${group}" "$path"
	fi
}

function ensure_owner_mode() {
	local owner="$1" group="$2" mode="$3" path="$4"
	ensure_owner "$owner" "$group" "$path" || return
	local cur_mode=$(stat -f '%Lp' "$path")
	if [[ $cur_mode != "${mode#0}" ]]; then
		sudo chmod -h "$mode" "$path"
	fi
}

# Use the following function to apply any setup related fixes which require root permissions.
# This function is executed by 'update_silent' action with EUID==0.
function fixup_installation_owner_mode() {
	local username=$1

	ensure_owner_mode $username staff 755 "$(dirname "$daemon_path")"
	ensure_owner_mode $username staff 644 "$daemon_path"

	ensure_owner_mode $username staff 755 "$configfolder"
	ensure_owner_mode $username staff 644 "$logfile"
	ensure_owner_mode $username staff 644 "$calibration_progress_file"
	ensure_owner_mode $username staff 644 "$maintain_percentage_tracker_file"
	ensure_owner_mode $username staff 644 "$maintain_voltage_tracker_file"
	ensure_owner_mode $username staff 644 "$maintain_force_discharge_file"

	ensure_owner_mode root wheel 755 "$visudo_folder"
	ensure_owner_mode root wheel 440 "$visudo_file"

	ensure_owner_mode root wheel 755 "$binfolder"
	ensure_owner_mode root wheel 755 "$battery_binary"
	ensure_owner_mode root wheel 755 "$smc_binary"

	# Do some cleanup after previous versions
	sudo rm -f "$configfolder/visudo.tmp"
}

function is_latest_version_installed() {
	# Check if content is reachable first with HEAD request
	curl -sSI "$github_url_battery_sh" &>/dev/null || return 0

	# Download the remote script then check if our version string is present.
	# Note: piping curl directly into grep -q causes a broken-pipe error (curl error 56)
	# because grep -q exits on first match while curl is still writing.
	local remote_script
	remote_script="$(curl -sS "$github_url_battery_sh" 2>/dev/null)"
	echo "$remote_script" | grep -q "$BATTERY_CLI_VERSION"
}

## ###############
## Actions
## ###############

case "$action" in
	status_csv) ;;
	*) log "🔋 Running '$(basename "$0") $*'" >>"$logfile" ;;
esac

case "$action" in
	maintain|charging|adapter|charge|discharge|calibrate) detect_and_report_macos27_calibration ;;
esac

# If the config folder or log file were just created by the code above while
# running as root, set the correct ownership and permissions.
if [[ $EUID -eq 0 ]]; then
	username="$(determine_unprivileged_user "$SUDO_USER")"
	if [[ -n "$username" && "$username" != "root" ]]; then
		fixup_installation_owner_mode "$username"
	fi
fi

# Version message
if [[ "$action" == "version" ]] || [[ "$action" == "--version" ]]; then
	echo "$BATTERY_CLI_VERSION"
	exit 0
fi

# Help message
if [ -z "$action" ] || [[ "$action" == "help" ]] || [[ "$action" == "--help" ]]; then
	echo -e "$helpmessage"
	exit 0
fi

# Update '/etc/sudoers.d/battery' config if needed
if [[ "$action" == "visudo" ]]; then

	# Allocate temp folder
	tempfolder="$(mktemp -d)"
	function cleanup() { rm -rf "$tempfolder"; }
	trap cleanup EXIT

	# Write the visudo file to a tempfile
	visudo_tmpfile="$tempfolder/visudo.tmp"
	echo -e "$visudoconfig" >$visudo_tmpfile

	# If the visudo folder does not exist, make it
	if ! test -d "$visudo_folder"; then
		sudo mkdir -p "$visudo_folder"
	fi
	ensure_owner_mode root wheel 755 "$visudo_folder"

	# If the visudo file is the same (no error, exit code 0), set the permissions just
	if sudo cmp $visudo_file $visudo_tmpfile &>/dev/null; then

		echo "☑️  The existing battery visudo file is what it should be for version $BATTERY_CLI_VERSION"

		# Check if file permissions are correct, if not, set them
		ensure_owner_mode root wheel 440 "$visudo_file"

		# Delete tempfolder
		rm -rf "$tempfolder"

		# exit because no changes are needed
		exit 0

	fi

	# Validate that the visudo tempfile is valid
	if sudo visudo -c -f $visudo_tmpfile &>/dev/null; then

		# Copy the visudo file from tempfile to live location
		sudo cp $visudo_tmpfile $visudo_file

		# Set correct permissions on visudo file
		ensure_owner_mode root wheel 440 "$visudo_file"

		# Delete tempfolder
		rm -rf "$tempfolder"

		echo "✅ Visudo file updated successfully"

	else
		echo "❌ Error validating visudo file, this should never happen:"
		sudo visudo -c -f $visudo_tmpfile
	fi

	exit 0
fi

# Reinstall helper
if [[ "$action" == "reinstall" ]]; then
	echo "This will run curl -sS ${github_url_setup_sh} | bash"
	if [[ ! "$setting" == "silent" ]]; then
		echo "Press any key to continue"
		read
	fi
	curl -sS "$github_url_setup_sh" | bash
	exit 0
fi

# Update helper for GUI app
if [[ "$action" == "update_silent" ]]; then

	assert_running_as_root

	# Exit with success when the GUI app just checks if passwordless updates are enabled
	if [[ "$setting" == "is_enabled" ]]; then
		exit 0
	fi

	# Try updating
	if ! is_latest_version_installed; then
		curl -sS "$github_url_update_sh" | bash
		echo "✅ battery background script was updated to the latest version."
	else
		echo "☑️  No updates found"
	fi

	# Update the visudo configuration on each update ensuring that the latest version
	# is always installed.
	# Note: this will overwrite the visudo configuration file only if it is outdated.
	$battery_binary visudo

	# Determine the name of unprivileged user
	username="$(determine_unprivileged_user "")"
	assert_unprivileged_user "$username"

	# Use opportunity to fixup installation
	fixup_installation_owner_mode "$username"

	exit 0
fi

# Update helper for Terminal users
if [[ "$action" == "update" ]]; then

	assert_not_running_as_root

	# The older GUI versions 1_3_2 and below can not run silent passwordless update and
	# will complain with alert. Just exit with success and let them update themselves.
	# Remove this condition in future versions when you believe the old UI is not used anymore.
	if [[ "$setting" == "silent" ]]; then
		exit 0
	fi

	if ! curl -fsI "$github_url_battery_sh" &>/dev/null; then
		echo "❌ Can't check for updates: no internet connection (or GitHub unreachable)."
		exit 1
	fi

	# The code below repeats integrity checks from GUI app, specifically from
	# app/modules/battery.js: 'initialize_battery'. Try keeping it consistent.

	function check_installation_integrity() (
		function not_link_and_root_owned() {
			[[ ! -L "$1" ]] && [[ $(stat -f '%u' "$1") -eq 0 ]]
		}

		not_link_and_root_owned "$binfolder" && \
		not_link_and_root_owned "$battery_binary" && \
		not_link_and_root_owned "$smc_binary" && \
		sudo -n "$battery_binary" update_silent is_enabled >/dev/null 2>&1
	)

	if ! check_installation_integrity; then
		version_before="0" # Force restart maintenance process
		echo -e "‼️ The battery installation seems to be broken. Forcing reinstall...\n"
		$battery_binary reinstall silent
	else
		version_before="$($battery_binary version)"
		sudo $battery_binary update_silent
	fi

	# Restart background maintenance process if update was installed
	if [[ -x $battery_binary ]] && [[ "$($battery_binary version)" != "$version_before" ]]; then
		printf "\n%s\n" "🛠️  Restarting 'battery maintain' ..."
		$battery_binary maintain recover
	fi

	exit 0
fi

# Stop the shared background job and restore normal charging controls.
if [[ "$action" == "stop" ]]; then

	stop_result=0
	launchd_job_stop_and_remove || {
		stop_result=1
		log "❌ Battery background job cleanup failed; continuing with charging control restoration"
	}
	disable_discharging
	enable_charging
	if [[ "$(get_charging_control_status)" != "enabled" ||
	      "$(get_discharging_control_status)" != "not discharging" ]]; then
		log "❌ Unable to confirm normal charging controls after stopping the background job"
	fi

	exit "$stop_result"
fi

# Uninstall helper
if [[ "$action" == "uninstall" ]]; then

	if [[ ! "$setting" == "silent" ]]; then
		echo "This will enable charging, and remove the smc tool and battery script"
		echo "Press any key to continue"
		read
	fi

	# Battery menubar UI app calls this action as root
	run_as_unprivileged_user "$battery_binary" stop || log "❌ Failed to stop Battery cleanly; continuing uninstall and final process cleanup"

	disable_discharging
	enable_charging

	sudo rm -fv /usr/local/bin/battery
	sudo rm -fv /usr/local/bin/smc

	sudo rm -fv "$visudo_file"
	sudo rm -frv "$binfolder"
	sudo rm -frv "$configfolder"
	sudo rm -fv "$path_configfile"

	# Ensure no dangling battery processes are left running
	pkill -f "/usr/local/bin/battery.*|/usr/local/co\.palokaj\.battery/battery.*"

	exit 0
fi

# Set an explicit mcl_smc charge limit.
if [[ "$action" == "_set_charge_limit_mcl_smc" ]]; then

	assert_running_as_root

	if [[ $# -ne 2 ]] || ! [[ "$setting" =~ ^(0|[1-9][0-9]?|100)$ ]] || [[ "$setting" -lt "$percentage_min" ]]; then
		log " ❌ Error: battery $action requires exactly one integer from ${percentage_min} to 100"
		exit 2
	fi

	upper="$setting"
	lower=$((upper - 2))
	printf -v upper_hex '%02x000000' "$upper"
	printf -v lower_hex '%02x000000' "$lower"

	# Do nothing if the same limits are already set.
	applied_state=$(smc_read_hex bfF0)
	applied_upper=$(smc_read_hex bfD0 | tr '[:upper:]' '[:lower:]')
	applied_lower=$(smc_read_hex bfE0 | tr '[:upper:]' '[:lower:]')
	if [[ "$applied_state" =~ ^[[:xdigit:]]{2}$ &&
		  "$applied_upper" =~ ^[[:xdigit:]]{8}$ &&
		  "$applied_lower" =~ ^[[:xdigit:]]{8}$ ]]; then
		if [[ "$applied_state" == "02" && "$applied_upper" == "$upper_hex" && "$applied_lower" == "$lower_hex" ]]; then
			log "☑️ Requested charge limit ("$setting") is already set. Do nothing."
			exit 0
		fi
	else
		log "⚠️ Unable to read mcl_smc charge-control settings; attempting to apply desired limits"
	fi

	if smc_write_hex bfF0 00 &&
	   smc_write_hex bfE0 "$lower_hex" &&
	   smc_write_hex bfD0 "$upper_hex" &&
	   smc_write_hex bfF0 02; then
		log "✅ MCL charge limit is set to $setting%."
		exit 0
	fi
	log "❌ Failed to set MCL charge limit to $setting%. Write sequence stopped."
	exit 1
fi

# Reset mcl_smc charge-limit control and threshold registers.
if [[ "$action" == "_reset_charge_limit_mcl_smc" ]]; then

	assert_running_as_root

	if smc_write_hex bfF0 00 &&
	   smc_write_hex bfD0 00000000 &&
	   smc_write_hex bfE0 00000000; then
		log "✅ MCL charge limit is disabled. Charging requested."
		exit 0
	fi
	log "❌ Failed to disable MCL charge limit. Write sequence stopped."
	exit 1
fi

if [[ "$action" == "_set_charge_limit_mcl_prefs" || "$action" == "_reset_charge_limit_mcl_prefs" ]]; then

	assert_running_as_root

	function mcl_prefs_limit_is_already_set() {
		local applied_state applied_limit
		applied_state=$("$defaults_binary" read "com.apple.smartcharging.topoffprotection" MCLFeatureState)
		applied_limit=$("$defaults_binary" read "com.apple.smartcharging.topoffprotection" mclLimitValue)
		[[ "$applied_state" == "$1" && "$applied_limit" == "$2" ]]
	}

	function mcl_prefs_write_integer() {
		local key="$1" value="$2"
		if ! "$defaults_binary" write "com.apple.smartcharging.topoffprotection" "$key" -int "$value"; then
			log "⚠️ Failed to write mcl_prefs preference $key=$value"
		fi
		return 0
	}

	# Set an explicit mcl_prefs charge limit in the root preference scope.
	if [[ "$action" == "_set_charge_limit_mcl_prefs" ]]; then
		if [[ $# -ne 2 ]] || ! [[ "$setting" =~ ^(0|[1-9][0-9]?|100)$ ]] || [[ "$setting" -lt "$percentage_min" ]]; then
			log " ❌ Error: battery $action requires exactly one integer from ${percentage_min} to 100"
			exit 2
		fi
		if mcl_prefs_limit_is_already_set 1 "$setting"; then
			log "☑️ Requested charge limit ("$setting") is already set. Do nothing."
			exit 0
		fi
		mcl_prefs_write_integer mclLimitValue "$setting"
		mcl_prefs_write_integer MCLFeatureState 1
		"$battery_binary" _notify_mcl_prefs_changed 0.5
		log "✅ MCL charge limit is set to ("$setting")."
		exit 0
	fi

	# Disable MCL and set its percentage setting to 100 (System Settings app does the same when limit is set to 100%)
	if [[ "$action" == "_reset_charge_limit_mcl_prefs" ]]; then
		if mcl_prefs_limit_is_already_set 0 100; then
			log "☑️ Requested reset settings are already set. Do nothing."
			exit 0
		fi
		mcl_prefs_write_integer MCLFeatureState 0
		mcl_prefs_write_integer mclLimitValue 100
		"$battery_binary" _notify_mcl_prefs_changed 0.5
		log "✅ MCL charge limit is dissabled. Charging requested."
		exit 0
	fi
fi

# Post the MCL preference change notification
if [[ "$action" == "_notify_mcl_prefs_changed" ]]; then
	sleep "${setting:-0}"
	output=$("$notifyutil_binary" -p "com.apple.smartcharging.defaultschanged" 2>&1)
	result=$?
	if [[ "$result" -ne 0 || -n "$output" ]]; then
		# Apple's notifyutil can report a posting error on stdout and still exit 0.
		log "❌ Failed to send the charge limit notification (exit status $result): $output" >&2
		exit 1
	fi
	exit 0
fi

# Charging on/off controller
if [[ "$action" == "charging" ]]; then

	log "Setting $action to $setting"

	# Stop the current background job before changing controls.
	$battery_binary stop

	# Set charging to on and off
	if [[ "$setting" == "on" ]]; then
		enable_charging
	elif [[ "$setting" == "off" ]]; then
		disable_charging
	else
		log "Error: $setting is not \"on\" or \"off\"."
		exit 1
	fi

	update_magsafe_led_color
	exit 0

fi

# Discharge on/off controller
if [[ "$action" == "adapter" ]]; then

	log "Setting $action to $setting"

	# Stop the current background job before changing controls.
	$battery_binary stop

	# Set charging to on and off
	if [[ "$setting" == "on" ]]; then
		disable_discharging
	elif [[ "$setting" == "off" ]]; then
		enable_discharging
	else
		log "Error: $setting is not \"on\" or \"off\"."
		exit 1
	fi

	update_magsafe_led_color
	exit 0

fi

# Charging on/off controller
if [[ "$action" == "charge" ]]; then

	if ! valid_percentage "$setting"; then
		log "Error: $setting is not a valid setting for battery charge. Please use a number between 0 and 100"
		exit 1
	fi

	# Stop battery maintenance if invoked by user from Terminal
	if [[ "$BATTERY_HELPER_MODE" != "1" ]]; then
		$battery_binary stop
	fi

	# Start charging
	battery_percentage=$(get_battery_percentage)
	log "Charging to $setting% from $battery_percentage%"
	enable_charging # also disables discharging

	# Loop until battery charging level is reached
	while [[ "$battery_percentage" -lt "$setting" ]]; do

		log "Battery at $battery_percentage% (target $setting%)"
		update_magsafe_led_color
		if [[ "$battery_percentage" -ge "$((setting - 3))" ]]; then
			sleep 20
		else
			caffeinate -is sleep 60
		fi
		exit_on_error "$?" "Error: Charging wait failed; charging stopped."

		battery_percentage=$(get_battery_percentage)

	done

	disable_charging
	update_magsafe_led_color
	log "Charging completed at $battery_percentage%"

	# Try restoring maintenance if invoked by user from Terminal
	if [[ "$BATTERY_HELPER_MODE" != "1" ]]; then
		$battery_binary maintain recover
	fi

	exit 0

fi

# Discharging on/off controller
if [[ "$action" == "discharge" ]]; then

	if valid_percentage "$setting"; then
		discharge_target="$setting"
		discharge_unit="%"
	elif valid_voltage "$setting"; then
		discharge_unit=V
		discharge_target="${setting%V}"
		if [[ "$(echo "$discharge_target >= $voltage_min && $discharge_target <= $voltage_max" | bc -l)" != "1" ]]; then
			log "❌ Discharge voltage must be between ${voltage_min}V and ${voltage_max}V"
			exit 1
		fi
	else
		log "❌ Invalid discharge target; use a percentage between 0 and 100 or a voltage between ${voltage_min}V and ${voltage_max}V"
		exit 1
	fi

	# Stop existing battery background job if invoked by user from Terminal
	if [[ "$BATTERY_HELPER_MODE" != "1" ]]; then
		$battery_binary stop || exit 1
	fi

	log "Discharging to $discharge_target$discharge_unit"
	enable_discharging

	# Both target types complete when the measured value is at or below the target.
	while true; do
		if [[ "$discharge_unit" == "V" ]]; then
			discharge_level=$(get_voltage)
		else
			discharge_level=$(get_battery_percentage)
		fi
		above_target=$(echo "$discharge_level > $discharge_target" | bc -l) || exit 1
		[[ "$above_target" == "1" ]] || break

		log "Battery at $discharge_level$discharge_unit (target $discharge_target$discharge_unit)"
		update_magsafe_led_color
		caffeinate -is sleep 60
		exit_on_error "$?" "Error: Discharging wait failed; Interrupted."

	done

	disable_charging
	disable_discharging
	update_magsafe_led_color
	log "Discharging completed at $discharge_level$discharge_unit"

	# Try restoring maintenance if invoked by user from Terminal
	if [[ "$BATTERY_HELPER_MODE" != "1" ]]; then
		$battery_binary maintain recover
	fi

	exit 0

fi

# Maintain at level using saved configuration
if [[ "$action" == "maintain_synchronous" ]]; then

	assert_not_running_as_root
	log_system_capabilities

	percentage_maintenance_config_load || exit 1
	# A single percentage supplies both bounds; the loader already validated them.
	lower_bound="${cfg_percentage%-*}"
	upper_bound="${cfg_percentage#*-}"

	if [[ "$cfg_force_discharge" == "true" ]]; then
		log "Triggering initial discharge to $lower_bound before maintenance"
		BATTERY_HELPER_MODE=1 "$battery_binary" discharge "$lower_bound"
		printf '%s\n' false >"$maintain_force_discharge_file" || { log "❌ Failed to clear completed force-discharge request"; }
		log "Initial discharge completed; continuing to maintenance"
	fi

	# Read the initial charge level
	battery_percentage=$(get_battery_percentage)

	if [[ "$lower_bound" != "$upper_bound" ]]; then
		log "Maintaining battery between $lower_bound% and $upper_bound% (currently ${battery_percentage}%)"
	else
		log "Maintaining battery at $cfg_percentage% (currently ${battery_percentage}%)"
	fi

	# Stop charging if current charge level is within specified range
	if [[ "$battery_percentage" -ge "$lower_bound" && "$battery_percentage" -lt "$upper_bound" ]]; then
		disable_charging
	fi

	# Maintenance Loop
	while true; do

		# Keep track of status
		is_charging=$(get_charging_control_status)

		if [[ "$battery_percentage" -ge "$upper_bound" ]]; then

			log "Charge level ($battery_percentage%) is at or above upper bound ($upper_bound%)"
			if [[ "$is_charging" == "enabled" ]]; then
				disable_charging
			fi
			mcl_maintain_disabled_charging "$lower_bound" "$upper_bound" "$battery_percentage"

		elif [[ "$battery_percentage" -ge "$lower_bound"  ]]; then

			log "Charge level ($battery_percentage%) is in betweeen $lower_bound% and $upper_bound%"
			if [[ "$is_charging" == "disabled" ]]; then
				mcl_maintain_disabled_charging "$lower_bound" "$upper_bound" "$battery_percentage"
			fi

		else

			log "Charge level ($battery_percentage%) is below lower bound ($lower_bound%)"
			if [[ "$is_charging" == "disabled" ]]; then
				enable_charging
			fi

		fi

		update_magsafe_led_color
		detect_and_report_macos27_calibration show_system_notification
		sleep 60

		battery_percentage=$(get_battery_percentage)

	done

	exit 0

fi

# Maintain at voltage using saved configuration
if [[ "$action" == "maintain_voltage_synchronous" ]]; then

	assert_not_running_as_root
	log_system_capabilities

	voltage_maintenance_config_load || exit 1
	if [[ "$cfg_force_discharge" == "true" ]]; then
		log "Triggering initial discharge to ${cfg_voltage}V before maintenance"
		BATTERY_HELPER_MODE=1 "$battery_binary" discharge "${cfg_voltage}V"
		printf '%s\n' false >"$maintain_force_discharge_file" || { log "❌ Failed to clear completed force-discharge request"; }
		log "Initial discharge completed; continuing to maintenance"
	fi

	voltage=$(get_voltage)
	lower_voltage=$(echo "$cfg_voltage - $cfg_voltage_hysteresis" | bc -l)
	upper_voltage=$(echo "$cfg_voltage + $cfg_voltage_hysteresis" | bc -l)
	log "Keeping voltage between ${lower_voltage}V and ${upper_voltage}V"

	# Stop charging if current voltage is already within specified range
	if (($(echo "$voltage >= $lower_voltage && $voltage < $upper_voltage" | bc -l))); then
		disable_charging
	fi

	# Loop
	while true; do
		is_charging=$(get_charging_control_status)

		if (($(echo "$voltage >= $upper_voltage" | bc -l))); then

			log "Battery voltage (${voltage}V) is at or above upper bound (${upper_voltage}V)"
			if [[ "$is_charging" == "enabled" ]]; then
				disable_charging
			fi
			mcl_maintain_disabled_charging "$percentage_min" "80" "$(get_battery_percentage)"

		elif (($(echo "$voltage >= $lower_voltage" | bc -l))); then

			log "Battery voltage (${voltage}V) is in betweeen ${lower_voltage}V and ${upper_voltage}V"
			if [[ "$is_charging" == "disabled" ]]; then
				mcl_maintain_disabled_charging "$percentage_min" "80" "$(get_battery_percentage)"
			fi

		else

			log "Battery voltage (${voltage}V) is below lower bound (${lower_voltage}V)"
			if [[ "$is_charging" == "disabled" ]]; then
				enable_charging
			fi

		fi

		update_magsafe_led_color
		detect_and_report_macos27_calibration show_system_notification
		sleep 60

		voltage=$(get_voltage)

	done

	exit 0

fi

# Start or recover a battery maintenance job using saved configuration
if [[ "$action" == "maintain" ]]; then

	assert_not_running_as_root

	# Deprecated compatibility alias; internal callers use stop directly.
	if [[ "$setting" == "stop" ]]; then
		$battery_binary stop || exit 1
		$battery_binary status
		exit 0
	fi

	if [[ "$setting" == "recover" ]]; then
		if percentage_maintenance_config_load; then
			maintenance_action=maintain_synchronous
			log "Recovering percentage maintenance: $cfg_percentage%"
		elif voltage_maintenance_config_load; then
			maintenance_action=maintain_voltage_synchronous
			log "Recovering voltage maintenance: ${cfg_voltage}V ±${cfg_voltage_hysteresis}V"
		else
			log "No usable maintenance configuration to recover, exiting"
			exit 0
		fi

		launchd_job_bootout || exit 1
		disable_discharging

		launchd_job_start_new true "$logfile" "$maintenance_action"
		log "Maintenance job recovered: $maintenance_action"
		exit $?
	fi

	if valid_voltage "$setting"; then
		shift 2
		arg_voltage="$setting"
		arg_hysteresis=0.1V
		arg_force_discharge=false
		if [[ $# -gt 0 && "$1" != "--force-discharge" ]]; then
			arg_hysteresis="$1"
			shift
		fi
		valid_maintenance_voltage "$arg_voltage" "$arg_hysteresis" || {
			log "❌ Maintenance voltage must be ${voltage_min}V-${voltage_max}V and hysteresis ${voltage_hyst_min}V-${voltage_hyst_max}V"
			exit 1
		}
		if [[ "$1" == "--force-discharge" ]]; then arg_force_discharge=true; shift; fi

		# Stop the previous writer before saving a new target or pending discharge request.
		launchd_job_bootout || exit 1
		disable_discharging

		voltage_maintenance_config_save "$arg_voltage" "$arg_hysteresis" "$arg_force_discharge" || exit 1

		launchd_job_start_new true "$logfile" maintain_voltage_synchronous || exit 1
		log "Maintenance job started: maintain_voltage_synchronous"
		exit 0
	fi

	if valid_maintenance_percentage "$setting" || valid_maintenance_percentage_range "$setting"; then
		shift 2
		arg_force_discharge=false
		if [[ "$1" == "--force-discharge" ]]; then arg_force_discharge=true; shift; fi

		# Stop the previous writer before saving a new target or pending discharge request.
		launchd_job_bootout || exit 1
		disable_discharging

		percentage_maintenance_config_save "$setting" "$arg_force_discharge" || exit 1

		launchd_job_start_new true "$logfile" maintain_synchronous || exit 1
		log "Maintenance job started: maintain_synchronous"
		exit 0
	fi

	log "❌ A maintenance target or recover argument is required; use 'battery help' for details"
	exit 1

fi

# Start calibration in the shared job, or display progress from the current or previous run.
if [[ "$action" == "calibrate" ]]; then

	assert_not_running_as_root
	[[ $# -eq 1 ]] || { log "❌ battery calibrate takes no arguments; use 'battery stop' to interrupt calibration"; exit 1; }

	if running_action=$(launchd_job_get_running_action); then
		if [[ "$running_action" == "calibrate_synchronous" ]]; then
			cat "$calibration_progress_file"
			printf "\n====\n\033[93mCalibration is in progress.\033[0m\n"
            printf "Use 'battery stop' or 'battery maintain' to interrupt it.\n\n"
			exit 0
		fi
	else
		[[ $? -eq 1 ]] || { log "❌ Unable to determine the running background job before calibration"; exit 1; }
	fi

	if [[ -e "$calibration_progress_file" ]]; then
		cat "$calibration_progress_file"
        printf "\n====\n"
		grep -F '✅ Calibration completed.' "$calibration_progress_file" >/dev/null || {
			[[ $? -eq 1 ]] || exit 1
			printf '\033[91mCalibration ended without completing.\033[0m\n'
		}
		rm "$calibration_progress_file" || { log "❌ Failed to remove the previous calibration progress file"; exit 1; }
		printf "Run 'battery calibrate' again to start a new calibration.\n"
        printf "Run 'battery maintain recover' to restore the maintenance.\n"
		exit 0
	fi

	$battery_binary stop || exit 1
	: >"$calibration_progress_file" || { log "❌ Failed to create the calibration progress file"; }
	launchd_job_start_new false "$logfile" calibrate_synchronous || exit 1
	printf "Calibration started in the background.\n"
    printf "\033[93mRun 'battery calibrate' to check the progress; use 'battery stop' to interrupt.\033[0m\n"
    printf "Saved maintenance stays inactive; run 'battery maintain recover' after calibration to restore it.\n"
	exit 0

fi

# All calibration phases stay in the shared job's process group for launchd cleanup.
if [[ "$action" == "calibrate_synchronous" ]]; then

	function record_calibration_progress() {
		log "$1"
		printf '%s %s\n' "$(date +%D-%T)" "$1" >>"$calibration_progress_file"
	}

	assert_not_running_as_root
	log_system_capabilities
	log "🛠️ Starting battery calibration"

	record_calibration_progress "[ 1 of 4 ] Discharging battery to 15%"
	BATTERY_HELPER_MODE=1 $battery_binary discharge 15
	exit_on_error "$?" "Calibration stopped: discharging to 15% failed."

	record_calibration_progress "[ 2 of 4 ] Charging to 100%"
	BATTERY_HELPER_MODE=1 $battery_binary charge 100
	exit_on_error "$?" "Calibration stopped: charging to 100% failed."

	record_calibration_progress "[ 3 of 4 ] Reached 100%, waiting for 1 hour"
	enable_charging
	disable_discharging
	sleep 3600
	exit_on_error "$?" "Calibration stopped: one-hour wait failed."

	record_calibration_progress "[ 4 of 4 ] Discharging battery to 80%"
	BATTERY_HELPER_MODE=1 $battery_binary discharge 80
	exit_on_error "$?" "Calibration stopped: discharging to 80% failed."

	# Keep this completion message in sync with the match in the calibrate action.
	record_calibration_progress "✅ Calibration completed."
	log "Saved maintenance stays inactive; run battery maintain recover to restore it."
	exit 0

fi

# Status logger
if [[ "$action" == "status" ]]; then

	log "Battery at $(get_battery_percentage)% ($(get_remaining_time) remaining), $(get_voltage)V, charging set to '$(get_charging_control_status)'"

	if running_action=$(launchd_job_get_running_action); then
		maintenance_level=""
		case "$running_action" in
			calibrate_synchronous)
				log "Battery calibration using 'battery calibrate' is in progress."
				;;
			maintain_synchronous)
				maintenance_level="(failed to determine the percentage maintenance level)"
				if percentage_maintenance_config_load; then
					maintenance_level="at $cfg_percentage%."
					[[ "$cfg_percentage" == *-* ]] && maintenance_level="between ${cfg_percentage/-/% and }%."
				fi
				;;
			maintain_voltage_synchronous)
				maintenance_level="(failed to determine the voltage maintenance level)"
				voltage_maintenance_config_load && maintenance_level="at ${cfg_voltage}V ±${cfg_voltage_hysteresis}V."
				;;
			*) log "Running background job: $running_action" ;;
		esac
		[[ -n "$maintenance_level" ]] && log "Your battery is being maintained $maintenance_level"
	else
		case "$?" in
			1) log "Your battery is not being maintained." ;;
			*) log "❌ Unable to determine the running background job" ;;
		esac
	fi

	detect_and_report_macos27_calibration

	exit 0

fi

# Status logger in csv format
if [[ "$action" == "status_csv" ]]; then

	echo "$(get_battery_percentage),$(get_remaining_time),$(get_charging_control_status),$(get_discharging_control_status),$(get_maintain_percentage)"
	exit 0

fi

# Display logs
if [[ "$action" == "logs" ]]; then

	amount="${2:-100}"

	echo -e "👾 Battery CLI logs:\n"
	tail -n $amount $logfile

	echo -e "\n🖥️	Battery GUI logs:\n"
	tail -n $amount "$configfolder/gui.log"

	echo -e "\n📁 Config folder details:\n"
	ls -lahn "$configfolder"

	echo -e "\n⚙️	Battery data:\n"
	$battery_binary status
	$battery_binary | grep -E "v\d.*"

	exit 0

fi

# Display SMC controls and native charge-limit preferences.
if [[ "$action" == "dump_controls" ]]; then

	function print_smc_control() {
		local key="$1" description="$2" output byte hex=""
		output=$("$smc_binary" -k "$key" -r 2>&1)
		if [[ "$output" =~ \(bytes\ ([[:xdigit:]]{2}(\ [[:xdigit:]]{2})*)\) ]]; then
			for byte in ${BASH_REMATCH[1]}; do hex="$byte$hex"; done    # Reverse the little-endian
			description="$description, current decimal value: $((16#$hex))"
		fi
		output=${output//$'\n'/ }
		printf '  %-4s  %-48s  %s\n' "$key" "${output:-(no output)}" "$description"
	}

	printf 'SMC state:\n'
	print_smc_control bfD0 "Upper charge limit value (stop charging)"
	print_smc_control bfE0 "Lower charge limit value (resume charging)"
	print_smc_control bfF0 "Charge limit control (00: limit disabled; 02: limit enabled)"
	print_smc_control CHTE "Legacy charging control (00000000: enabled; 01000000: disabled)"
	print_smc_control CH0B "Legacy charging control (00: enabled; 02: disabled)"
	print_smc_control CH0C "Legacy charging control (00: enabled; 02: disabled)"
	print_smc_control CHIE "Forced discharge control (00: adapter enabled; 08: adapter disabled)"
	print_smc_control CH0I "Forced discharge control (00: adapter enabled; 01: adapter disabled)"
	print_smc_control CH0J "Forced discharge control (00: adapter enabled; 01: adapter disabled)"
	print_smc_control ACLC "MagSafe LED control (00: reset; 01: off; 03: green; 04: orange)"

	function print_mcl_prefs_control() {
		local key="$1" description="$2" value
		value=$(sudo -n "$defaults_binary" read com.apple.smartcharging.topoffprotection "$key" 2>/dev/null) || value="failed to read the key"
		printf '  %-16s  %-36s  %s\n' "$key" "$value" "$description"
	}

	printf '\nPreferences: com.apple.smartcharging.topoffprotection.plist (root scope)\n'
	print_mcl_prefs_control MCLFeatureState "Charge limit feature state (0: disabled; 1: enabled)"
	print_mcl_prefs_control mclLimitValue "Charge limit percentage"

	printf '\n'
	detect_and_report_macos27_calibration
	printf '\n'

	exit 0

fi
