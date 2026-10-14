#!/bin/bash
# Sourced only from the root-owned installation directory by battery.sh.
# No code is loaded from the user's configuration directory.
fw_policy_file="$configfolder/firmware.policy"
fw_status_file="$configfolder/firmware.status"
fw_lock_dir="$configfolder/firmware.lock"
fw_period=60
fw_freshness=120

fw_log() {
    printf '%s [%s] firmware %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$$" "$*" | tee -a "$logfile" >&2
}

# Normalize before arithmetic: bash otherwise interprets leading zeroes as octal.
fw_decimal() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    while [[ ${#value} -gt 1 && "$value" == 0* ]]; do value=${value#0}; done
    [[ ${#value} -le 3 ]] || return 1
    (( 10#$value <= 100 )) || return 1
    printf '%d\n' "$((10#$value))"
}

fw_hex() { printf '%02x000000\n' "$1"; }

fw_read() {
    local key="$1" type="$2" length="$3" output bytes pattern
    output=$("$smc_binary" -k "$key" -r 2>&1) || return 1
    [[ "$output" != *Error* && "$output" != *'no data'* && "$output" == *"[$type"* ]] || return 1
    pattern='\(bytes ([0-9a-fA-F ]+)\)'
    [[ "$output" =~ $pattern ]] || return 1
    bytes=$(printf '%s' "${BASH_REMATCH[1]}" | tr -d ' ' | tr 'A-F' 'a-f')
    [[ ${#bytes} -eq $length ]] || return 1
    printf '%s\n' "$bytes"
}

fw_write() {
    local key="$1" value="$2" type=ui32 length=8 output actual
    [[ "$key" == bfF0 ]] && { type=ui8; length=2; }
    [[ "$key" == CHIE ]] && { type=hex_; length=2; }
    actual=$(fw_read "$key" "$type" "$length") || actual=unreadable
    [[ "$actual" != "$value" ]] || return 0
    output=$(sudo -n "$smc_binary" -k "$key" -w "$value" 2>&1)
    local rc=$?
    actual=$(fw_read "$key" "$type" "$length") || actual=unreadable
    if [[ $rc -ne 0 || "$output" == *Error* || "$actual" != "$value" ]]; then
        fw_log "event=write_failed key=$key wanted=$value observed=$actual exit=$rc"
        return 1
    fi
}

fw_selected() {
    [[ -f "$fw_policy_file" ]] || fw_read bfF0 ui8 2 >/dev/null
}

fw_snapshot() {
    fw_old_f=$(fw_read bfF0 ui8 2) && fw_old_u=$(fw_read bfD0 ui32 8) &&
        fw_old_l=$(fw_read bfE0 ui32 8) && fw_old_adapter=$(fw_read CHIE hex_ 2) || return 1
    [[ "$fw_old_f" == 00 || "$fw_old_f" == 02 ]] || return 1
    [[ "$fw_old_adapter" == 00 || "$fw_old_adapter" == 08 ]] || return 1
    # Rollback must be expressible with the same restricted sudo permissions.
    local key value valid n
    for value in "$fw_old_u" "$fw_old_l"; do
        valid=false
        for ((n=0;n<=100;n++)); do [[ "$value" == "$(fw_hex "$n")" ]] && { valid=true; break; }; done
        [[ "$valid" == true ]] || return 1
    done
}

fw_restore() {
    local failed=0
    if [[ "$(fw_read bfF0 ui8 2)" == "$fw_old_f" && "$(fw_read bfD0 ui32 8)" == "$fw_old_u" && "$(fw_read bfE0 ui32 8)" == "$fw_old_l" && "$(fw_read CHIE hex_ 2)" == "$fw_old_adapter" ]]; then return 0; fi
    fw_write bfF0 00 || failed=1
    fw_write bfD0 "$fw_old_u" || failed=1
    fw_write bfE0 "$fw_old_l" || failed=1
    fw_write bfF0 "$fw_old_f" || failed=1
    fw_write CHIE "$fw_old_adapter" || failed=1
    return "$failed"
}

fw_apply() {
    local target="$1" lower=$(( $1 > 2 ? $1 - 2 : 0 ))
    fw_matches "$target" && return 0
    fw_write bfF0 00 && fw_write bfD0 "$(fw_hex "$target")" &&
        fw_write bfE0 "$(fw_hex "$lower")" && fw_write bfF0 02
}

fw_matches() {
    local target="$1" lower=$(( $1 > 2 ? $1 - 2 : 0 ))
    [[ "$(fw_read bfF0 ui8 2)" == 02 &&
       "$(fw_read bfD0 ui32 8)" == "$(fw_hex "$target")" &&
       "$(fw_read bfE0 ui32 8)" == "$(fw_hex "$lower")" ]]
}

fw_load_policy() {
    fw_mode=unset; fw_target=; fw_force=0; fw_generation=none
    [[ -f "$fw_policy_file" ]] || return 1
    local extra normalized
    read -r fw_mode fw_target fw_force fw_generation extra < "$fw_policy_file"
    case "$fw_mode" in enabled|stopped|unlimited) ;; *) return 1 ;; esac
    normalized=$(fw_decimal "$fw_target") || return 1
    [[ "$normalized" == "$fw_target" && "$fw_target" -ge 1 &&
       "$fw_force" =~ ^[01]$ && "$fw_generation" =~ ^[0-9]+-[0-9]+$ && -z "$extra" ]] || return 1
    [[ "$fw_mode" != enabled || "$fw_target" -lt 100 ]] || return 1
}

fw_atomic() {
    local dest="$1" value="$2" tmp
    tmp=$(mktemp "$dest.XXXXXX") || return 1
    printf '%s\n' "$value" > "$tmp" && mv -f "$tmp" "$dest"
}

fw_pid_is_controller() {
    local pid="$1" cmd
    [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]] || return 1
    cmd=$(ps -p "$pid" -o command= 2>/dev/null)
    case "$cmd" in
        "/bin/bash $battery_binary firmware_synchronous "*|"/bin/bash $battery_binary maintain_synchronous "*|"/bin/bash $battery_binary discharge "*) return 0 ;;
        *) return 1 ;;
    esac
}

fw_acquire() {
    local owner i
    for ((i=0;i<50;i++)); do
        if mkdir "$fw_lock_dir" 2>/dev/null; then
            printf '%s\n' "$$" > "$fw_lock_dir/pid"
            return 0
        fi
        owner=$(cat "$fw_lock_dir/pid" 2>/dev/null)
        # An empty lock may still be being created. Never remove it on that basis.
        if [[ "$owner" =~ ^[0-9]+$ ]] && ! kill -0 "$owner" 2>/dev/null && mkdir "$fw_lock_dir.reap" 2>/dev/null; then
            owner=$(cat "$fw_lock_dir/pid" 2>/dev/null)
            if [[ "$owner" =~ ^[0-9]+$ ]] && ! kill -0 "$owner" 2>/dev/null; then
                rm -f "$fw_lock_dir/pid"; rmdir "$fw_lock_dir" 2>/dev/null
            fi
            rmdir "$fw_lock_dir.reap" 2>/dev/null
        fi
        sleep 0.1
    done
    return 1
}

fw_release() {
    [[ "$(cat "$fw_lock_dir/pid" 2>/dev/null)" == "$$" ]] || return 0
    rm -f "$fw_lock_dir/pid"; rmdir "$fw_lock_dir" 2>/dev/null
}

# Pause only this user's exact maintenance commands, including a legacy discharge
# child which is not represented in battery.pid. Do not kill by broad name match.
fw_pause_previous() {
    fw_paused=()
    local pid parent cmd stat rows
    rows=$(ps -U "$(id -u)" -o pid=,ppid=,stat=,command=) || return 1
    while read -r pid parent stat cmd; do
        # $$ remains the parent PID in a bash 3.2 subshell. Exclude its direct
        # children too, or a launchd recovery request could stop its own transaction.
        [[ "$pid" != "$$" && "$parent" != "$$" && "$stat" != *T* ]] || continue
        case "$cmd" in
            "/bin/bash $battery_binary firmware_synchronous "*|"/bin/bash $battery_binary maintain_synchronous "*|"/bin/bash $battery_binary discharge "*)
                kill -STOP "$pid" || return 1
                fw_paused+=("$pid") ;;
        esac
    done <<< "$rows"
}

fw_transaction_cleanup() {
    local pid
    if [[ "$fw_committed" != true ]]; then
        # Restore intent before signalling the tentative worker so its exit trap
        # cannot undo the hardware rollback belonging to the previous generation.
        if [[ "$fw_changed" == true ]]; then
            if [[ "$fw_had_policy" == true ]]; then fw_atomic "$fw_policy_file" "$fw_previous_policy"; else rm -f "$fw_policy_file"; fi
            if [[ "$fw_had_target" == true ]]; then fw_atomic "$maintain_percentage_tracker_file" "$fw_previous_target"; else rm -f "$maintain_percentage_tracker_file"; fi
            if [[ -n "$fw_previous_pid" ]]; then fw_atomic "$pidfile" "$fw_previous_pid"; else rm -f "$pidfile"; fi
            if [[ -n "$fw_new_pid" ]]; then kill -TERM "$fw_new_pid" 2>/dev/null; wait "$fw_new_pid" 2>/dev/null; fi
            if fw_restore; then fw_log 'event=rollback result=restored'; else fw_log 'event=rollback result=FAILED'; fi
        fi
        for pid in "${fw_paused[@]}"; do kill -CONT "$pid" 2>/dev/null; done
    fi
    fw_release
}

fw_request() {
    local request="$1" option="$2" target mode force=0 generation previous_mode
    if [[ "$request" == recover ]]; then
        if ! fw_load_policy; then
            if [[ -e "$fw_policy_file" ]]; then fw_log 'event=recover_failed reason=invalid_policy'; return 1; fi
            # Explicit migration from the previous installed CLI, if it was active.
            if [[ ! -e "$fw_policy_file" ]] && fw_pid_is_controller "$(cat "$pidfile" 2>/dev/null)"; then
                request=$(cat "$maintain_percentage_tracker_file" 2>/dev/null)
            else
                fw_log 'event=recover result=no_active_policy'; return 0
            fi
        elif [[ "$fw_mode" != enabled ]]; then
            fw_log "event=recover result=preserved mode=$fw_mode"; return 0
        else
            request=$fw_target; [[ "$fw_force" == 1 ]] && option=--force-discharge
        fi
    fi
    [[ -z "$option" || "$option" == --force-discharge ]] || { fw_log 'event=request_rejected reason=invalid_option'; return 1; }
    if [[ "$request" == stop ]]; then
        [[ -z "$option" ]] || { fw_log 'event=request_rejected reason=option_with_stop'; return 1; }
        # Never disable a firmware policy that this installation does not own.
        if fw_load_policy; then target=$fw_target; force=$fw_force
        elif [[ ! -e "$fw_policy_file" && "$(fw_read bfF0 ui8 2)" == 00 ]]; then
            target=$(fw_decimal "$(cat "$maintain_percentage_tracker_file" 2>/dev/null)")
            if [[ -z "$target" || "$target" == 0 ]]; then fw_log 'event=stop result=already_stopped'; return 0; fi
        else fw_log 'event=stop_rejected reason=no_owned_policy'; return 1
        fi
        mode=stopped
    else
        target=$(fw_decimal "$request") || { fw_log 'event=request_rejected reason=invalid_target'; return 1; }
        ((target>=1)) || { fw_log 'event=request_rejected reason=zero_target'; return 1; }
        mode=enabled; [[ "$target" == 100 ]] && mode=unlimited
        [[ "$option" == --force-discharge && "$mode" == enabled ]] && force=1
    fi
    if [[ -e "$fw_policy_file" ]] && ! fw_load_policy; then fw_log 'event=request_rejected reason=invalid_saved_policy'; return 1; fi
    fw_acquire || { fw_log 'event=request_rejected reason=controller_busy'; return 1; }
    # Run in a subshell so cleanup traps cannot leak into callers.
    (
        fw_committed=false; fw_changed=false; fw_new_pid=; fw_paused=()
        fw_had_policy=false; fw_had_target=false
        [[ ! -f "$fw_policy_file" ]] || fw_had_policy=true
        [[ ! -f "$maintain_percentage_tracker_file" ]] || fw_had_target=true
        fw_previous_policy=$(cat "$fw_policy_file" 2>/dev/null)
        fw_previous_target=$(cat "$maintain_percentage_tracker_file" 2>/dev/null)
        fw_previous_pid=$(cat "$pidfile" 2>/dev/null)
        trap fw_transaction_cleanup EXIT
        trap 'exit 130' INT TERM HUP
        fw_snapshot || { fw_log 'event=request_failed reason=unsupported_or_unreadable_keys'; exit 1; }
        # A readable but externally active policy must not be silently taken over.
        if [[ "$fw_old_f" == 02 && "$fw_had_policy" != true ]]; then
            fw_log 'event=request_failed reason=unowned_firmware_policy'; exit 1
        fi
        if [[ "$mode" == enabled ]] && fw_load_policy && [[ "$fw_mode" == enabled && "$fw_target" == "$target" && "$fw_force" == "$force" ]] && fw_matches "$target" && fw_pid_is_controller "$fw_previous_pid" && [[ "$(cat "$configfolder/firmware.ready" 2>/dev/null)" == "$fw_generation $fw_previous_pid ${BATTERY_CLI_VERSION:-test}" ]]; then
            fw_committed=true; fw_log "event=apply target=$target result=already_applied"; exit 0
        fi
        fw_pause_previous || exit 1
        fw_snapshot || { fw_log 'event=apply_failed reason=snapshot_after_pause'; exit 1; }
        fw_changed=true
        if [[ "$mode" == enabled ]]; then
            fw_apply "$target" || exit 1
        else
            fw_write bfF0 00 || exit 1
        fi
        fw_write CHIE 00 || exit 1
        generation="$(date +%s)-$$"
        fw_atomic "$fw_policy_file" "$mode $target $force $generation" &&
            fw_atomic "$maintain_percentage_tracker_file" "$target" || exit 1
        rm -f "$fw_status_file"
        if [[ "$mode" == enabled ]]; then
            nohup /bin/bash "$battery_binary" firmware_synchronous "$generation" </dev/null >/dev/null 2>&1 &
            fw_new_pid=$!
            fw_atomic "$pidfile" "$fw_new_pid" || exit 1
            local i ready=false
            for ((i=0;i<100;i++)); do
                if [[ "$(cat "$configfolder/firmware.ready" 2>/dev/null)" == "$generation $fw_new_pid ${BATTERY_CLI_VERSION:-test}" ]]; then ready=true; break; fi
                kill -0 "$fw_new_pid" 2>/dev/null || break
                sleep 0.1
            done
            [[ "$ready" == true ]] || { fw_log 'event=apply_failed reason=worker_start'; exit 1; }
            "$battery_binary" create_daemon >/dev/null 2>&1 || exit 1
        else
            rm -f "$pidfile"
            "$battery_binary" disable_daemon >/dev/null 2>&1 || exit 1
        fi
        fw_committed=true
        local pid
        for pid in "${fw_paused[@]}"; do kill -TERM "$pid" 2>/dev/null; kill -CONT "$pid" 2>/dev/null; done
        fw_log "event=apply target=$target lower=$((target>2?target-2:0)) mode=$mode force=$force result=verified"
    )
}

# Read one coherent plist per sample. Missing fields are not silently zeroed.
fw_telemetry() {
    local tmp key value
    tmp=$(mktemp "$configfolder/telemetry.XXXXXX") || return 1
    /usr/sbin/ioreg -a -r -c AppleSmartBattery > "$tmp" || { rm -f "$tmp"; return 1; }
    fw_percent=; fw_current=; fw_raw=; fw_max=; fw_stamp=; fw_external=; fw_charging=; fw_input=; fw_load=; fw_battery_power=
    for key in CurrentCapacity InstantAmperage AppleRawCurrentCapacity AppleRawMaxCapacity UpdateTime ExternalConnected IsCharging PowerTelemetryData.SystemPowerIn PowerTelemetryData.SystemLoad PowerTelemetryData.BatteryPower; do
        value=$(/usr/bin/plutil -extract "0.$key" raw -o - "$tmp" 2>/dev/null) || value=
        case "$key" in
            CurrentCapacity) fw_percent=$value ;;
            InstantAmperage) fw_current=$value ;;
            AppleRawCurrentCapacity) fw_raw=$value ;;
            AppleRawMaxCapacity) fw_max=$value ;;
            UpdateTime) fw_stamp=$value ;;
            ExternalConnected) fw_external=$value ;;
            IsCharging) fw_charging=$value ;;
            PowerTelemetryData.SystemPowerIn) fw_input=$value ;;
            PowerTelemetryData.SystemLoad) fw_load=$value ;;
            PowerTelemetryData.BatteryPower) fw_battery_power=$value ;;
        esac
    done
    rm -f "$tmp"
    for value in "$fw_percent" "$fw_current" "$fw_raw" "$fw_max" "$fw_stamp" "$fw_input" "$fw_load" "$fw_battery_power"; do
        [[ "$value" =~ ^-?[0-9]+$ && ${#value} -le 20 ]] || return 1
    done
    # ioreg may serialize signed battery values as unsigned 64-bit integers.
    fw_current=$((fw_current)); fw_battery_power=$((fw_battery_power))
    [[ "$fw_external" == true || "$fw_external" == false ]] || return 1
    [[ "$fw_charging" == true || "$fw_charging" == false ]] || return 1
    ((fw_percent>=0 && fw_percent<=100 && fw_raw>=0 && fw_max>0 && fw_input>=0 && fw_stamp>0))
}

fw_reset_window() { fw_stable_since=0; fw_stable_count=0; fw_last_stamp=0; fw_min_raw=0; fw_max_raw=0; }

fw_observe() {
    local now="$1" target="$2" age absolute tolerance power_absolute input_delta
    fw_power=unknown
    age=$((now-fw_stamp))
    ((age>=0 && age<=fw_freshness)) || { fw_reset_window; return; }
    if [[ "$fw_external" != true ]]; then fw_power=battery; fw_reset_window; return; fi
    if [[ "$fw_charging" == true ]]; then fw_power=charging; fw_reset_window; return; fi
    absolute=$fw_current; ((absolute<0)) && absolute=$((-absolute))
    power_absolute=$fw_battery_power; ((power_absolute<0)) && power_absolute=$((-power_absolute))
    input_delta=$((fw_input-fw_load)); ((input_delta<0)) && input_delta=$((-input_delta))
    if ((absolute>100 || power_absolute>2000 || input_delta>2000 || fw_input<=1000 || fw_percent<target-1 || fw_percent>target+1)); then
        fw_power=external_unconfirmed; fw_reset_window; return
    fi
    # Do not call an initial N-1 plateau 'target reached'. Remember a fresh N
    # sample within this controller session before evaluating the hold window.
    [[ "$fw_reached" == true ]] || { fw_power=external_unconfirmed; fw_reset_window; return; }
    if ((fw_stable_since==0)); then
        fw_stable_since=$now; fw_min_raw=$fw_raw; fw_max_raw=$fw_raw
    fi
    if [[ "$fw_stamp" != "$fw_last_stamp" ]]; then
        fw_stable_count=$((fw_stable_count+1)); fw_last_stamp=$fw_stamp
    fi
    ((fw_raw<fw_min_raw)) && fw_min_raw=$fw_raw
    ((fw_raw>fw_max_raw)) && fw_max_raw=$fw_raw
    tolerance=$((fw_max/1000)); ((tolerance<5)) && tolerance=5
    if ((fw_max_raw-fw_min_raw>tolerance)); then fw_reset_window; fw_power=external_unconfirmed; return; fi
    fw_power=external_verifying
    ((now-fw_stable_since>=300 && fw_stable_count>=4)) && fw_power=bypass_verified
    return 0
}

fw_worker_cleanup() {
    fw_release
    # Keep the firmware charge limit on ordinary worker termination. Only release
    # an adapter cut owned by this worker; a successor owns its own generation.
    if [[ "$fw_cut_owned" == true ]] && fw_load_policy && [[ "$fw_generation" == "$fw_worker_generation" ]]; then
        fw_write CHIE 00 || fw_log 'event=worker_exit adapter_restore=FAILED'
    fi
}

fw_worker() {
    fw_worker_generation="$1"
    local worker_generation="$1" now power_previous= heartbeat=0 applied stale failures=0 old_stamp=0 old_raw=0 over_count=0
    fw_load_policy && [[ "$fw_mode" == enabled && "$fw_generation" == "$worker_generation" ]] || return 1
    local target=$fw_target force=$fw_force initial=true repair_count=0
    fw_cut_owned=false; fw_reached=false; fw_reset_window
    trap fw_worker_cleanup EXIT
    trap 'exit 0' TERM INT HUP
    local ready_attempt
    for ((ready_attempt=0;ready_attempt<50;ready_attempt++)); do
        [[ "$(cat "$pidfile" 2>/dev/null)" != "$$" ]] || break
        sleep 0.1
    done
    [[ "$(cat "$pidfile" 2>/dev/null)" == "$$" ]] || return 1
    fw_atomic "$configfolder/firmware.ready" "$worker_generation $$ ${BATTERY_CLI_VERSION:-test}" || return 1
    while true; do
        [[ "$(cat "$pidfile" 2>/dev/null)" == "$$" ]] || return 0
        fw_load_policy && [[ "$fw_mode" == enabled && "$fw_generation" == "$worker_generation" ]] || return 0
        now=$(date +%s); applied=verified
        if fw_acquire; then
            # Recheck intent after obtaining the lock: never reapply a stopped or
            # replaced request based on a sample taken before it changed.
            if ! fw_load_policy || [[ "$fw_mode" != enabled || "$fw_generation" != "$worker_generation" ]]; then fw_release; return 0; fi
            if ! fw_matches "$target"; then
                applied=unknown
                # Restore only a reset/inactive policy, not a conflicting active
                # policy installed by another controller.
                if ((repair_count<1)) && fw_snapshot && [[ "$fw_old_f" == 00 ]]; then
                    repair_count=$((repair_count+1))
                    if fw_apply "$target"; then fw_log "event=policy_recovered target=$target"; applied=verified
                    else fw_restore || fw_log 'event=recovery_rollback result=FAILED'; applied=failed; fi
                else
                    applied=failed
                fi
                fw_reset_window
            fi
            if fw_telemetry && now=$(date +%s) && ((now-fw_stamp>=0 && now-fw_stamp<=fw_freshness && fw_stamp>=${worker_generation%-*})); then
                failures=0
                ((fw_percent>=target)) && fw_reached=true
                if [[ "$initial" == true ]]; then
                    if ((fw_percent<=target)); then
                        if fw_write CHIE 00; then initial=false; fw_cut_owned=false; fw_log "event=initial_phase_complete target=$target"; else applied=failed; fi
                    elif [[ "$force" == 1 ]]; then
                        # One controller handles the initial discharge. A fresh
                        # discharge already in progress needs no second action.
                        if [[ "$fw_external" == false && "$fw_current" -lt -100 ]]; then :
                        elif fw_write CHIE 08; then
                            [[ "$fw_cut_owned" == true ]] || fw_log "event=initial_discharge target=$target"
                            fw_cut_owned=true;
                        else applied=failed; fi
                    else initial=false
                    fi
                fi
                fw_observe "$now" "$target"
                if [[ "$initial" == true && "$force" == 1 ]]; then fw_power=initial_discharge; fw_reset_window; fi
                if [[ "$fw_stamp" != "$old_stamp" ]]; then
                    if [[ "$fw_reached" == true && "$fw_charging" == true ]] && ((fw_current>100 && fw_raw>old_raw)); then over_count=$((over_count+1)); else over_count=0; fi
                    old_stamp=$fw_stamp; old_raw=$fw_raw
                fi
                if ((over_count>=2)); then applied=failed; fw_power=limit_failed; fi
            else
                failures=$((failures+1)); fw_power=unknown; fw_percent=; fw_current=; fw_stamp=0; fw_reset_window
            fi
            [[ "$applied" == verified ]] || { fw_power=unknown; fw_reset_window; }
            fw_atomic "$fw_status_file" "$worker_generation $now $applied $fw_power ${fw_percent:-null} ${fw_current:-null} $fw_stamp"
            if [[ "$power_previous" != "$applied:$fw_power" ]] || ((now-heartbeat>=600)); then
                fw_log "event=observation target=$target applied=$applied power=$fw_power percent=${fw_percent:-unknown} current_mA=${fw_current:-unknown} raw_mAh=${fw_raw:-unknown} input_mW=${fw_input:-unknown} load_mW=${fw_load:-unknown} battery_mW=${fw_battery_power:-unknown} sensor_time=$fw_stamp window_samples=$fw_stable_count"
                power_previous="$applied:$fw_power"; heartbeat=$now
            fi
            fw_release
        fi
        sleep "$fw_period" & wait $!
    done
}

fw_status_json() {
    local mode=unset target=null lower=null applied=unknown power=unknown percent=null current=null stamp=0 observed=0 generation=none extra now force=false
    now=$(date +%s)
    if fw_load_policy; then mode=$fw_mode; target=$fw_target; generation=$fw_generation; lower=$((target>2?target-2:0)); [[ "$fw_force" != 1 ]] || force=true
    else
        local saved
        saved=$(fw_decimal "$(cat "$maintain_percentage_tracker_file" 2>/dev/null)")
        [[ -z "$saved" || "$saved" == 0 ]] || target=$saved
    fi
    if [[ "$mode" == enabled ]]; then
        local stored_gen saved_applied saved_power saved_percent saved_current sensor
        if read -r stored_gen observed saved_applied saved_power saved_percent saved_current sensor extra 2>/dev/null < "$fw_status_file" &&
           [[ "$stored_gen" == "$generation" && "$observed" =~ ^[0-9]+$ && "$sensor" =~ ^[0-9]+$ && -z "$extra" ]] &&
           ((now-observed>=0 && now-observed<=fw_freshness && now-sensor>=0 && now-sensor<=fw_freshness)); then
            case "$saved_applied" in verified|failed|unknown) applied=$saved_applied ;; esac
            case "$saved_power" in charging|battery|initial_discharge|external_unconfirmed|external_verifying|bypass_verified|limit_failed|unknown) power=$saved_power ;; esac
            [[ "$saved_percent" =~ ^[0-9]{1,3}$ ]] && percent=$saved_percent
            [[ "$saved_current" =~ ^-?[0-9]{1,8}$ ]] && current=$saved_current
        fi
        if ! fw_pid_is_controller "$(cat "$pidfile" 2>/dev/null)" || ! fw_matches "$target"; then applied=unknown; power=unknown
        elif [[ "$applied" == unknown ]]; then applied=verified
        fi
        # Fresh telemetry also invalidates a cached bypass after unplugging.
        if [[ "$power" == bypass_verified ]]; then
            if [[ "$(fw_read CHIE hex_ 2)" != 00 ]] || ! fw_telemetry || [[ "$fw_external" != true || "$fw_charging" != false ]] || ((now-fw_stamp<0 || now-fw_stamp>fw_freshness || fw_current>100 || fw_current < -100 || fw_input<=1000 || fw_battery_power>2000 || fw_battery_power < -2000)); then power=unknown
            else percent=$fw_percent; current=$fw_current
            fi
        fi
    elif [[ "$mode" == stopped || "$mode" == unlimited ]]; then
        lower=null
        [[ "$(fw_read bfF0 ui8 2)" != 00 ]] || applied=verified
    fi
    # Percentage is still useful before the first controller sample. It does not
    # promote an unknown power state to a verified one.
    if [[ "$percent" == null ]]; then
        local live
        live=$(get_battery_percentage)
        [[ "$live" =~ ^[0-9]{1,3}$ ]] && percent=$live
    fi
    printf '{"schema":1,"backend":"firmware","target":%s,"lower":%s,"mode":"%s","applied":"%s","power":"%s","percentage":%s,"current_mA":%s,"force_discharge":%s}\n' "$target" "$lower" "$mode" "$applied" "$power" "$percent" "$current" "$force"
}

fw_visudo() {
    local n key commands="$smc_binary -k bfF0 -w 00, $smc_binary -k bfF0 -w 02"
    for key in bfD0 bfE0; do
        for ((n=0;n<=100;n++)); do commands="$commands, $smc_binary -k $key -w $(fw_hex "$n")"; done
    done
    printf '\nCmnd_Alias FIRMWARE_LIMIT = %s\nALL ALL = NOPASSWD: FIRMWARE_LIMIT\n' "$commands"
}
