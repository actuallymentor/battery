// Command line interactors
const { app } = require( 'electron' )
const { exec } = require( 'node:child_process' )
const { log, alert, wait, confirm } = require( './helpers' )
const { get_force_discharge_setting } = require( './settings' )
const { USER } = process.env
const path_fix = 'PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
const battery = `${ path_fix } battery`
const shell_options = {
    shell: '/bin/bash',
    env: { ...process.env, PATH: `${ process.env.PATH }:/usr/local/bin` }
}

// Execute without sudo
const exec_async_no_timeout = command => new Promise( ( resolve, reject ) => {

    log( `Executing ${ command }` )

    exec( command, shell_options, ( error, stdout, stderr ) => {

        if( error ) return reject( error, stderr, stdout )
        if( stderr ) return reject( stderr )
        if( stdout ) return resolve( stdout )

    } )

} )

const exec_async = ( command, timeout_in_ms=2000, throw_on_timeout=false ) => Promise.race( [
    exec_async_no_timeout( command ),
    wait( timeout_in_ms ).then( () => {
        if( throw_on_timeout ) throw new Error( `${ command } timed out` )
    } )
] )

// Execute with sudo
const exec_sudo_async = command => new Promise( ( resolve, reject ) => {

    log( `Executing ${ command } by running:` )
    log( `osascript -e "do shell script \\"${ command }\\" with administrator privileges"` )

    exec( `osascript -e "do shell script \\"${ command }\\" with administrator privileges"`, shell_options, ( error, stdout, stderr ) => {

        if( error ) return reject( error, stderr, stdout )
        if( stderr ) return reject( stderr )
        if( stdout ) return resolve( stdout )

    } )

} )

// Battery status checker
const get_battery_status = async () => {

    try {
        const message = await exec_async( `${ battery } status_csv` )
        let [ percentage='??', remaining='', charging='', discharging='', maintain_percentage='' ] = message?.split( ',' ) || []
        maintain_percentage = maintain_percentage.trim()
        maintain_percentage = maintain_percentage.length ? maintain_percentage : undefined
        charging = charging == 'enabled'
        discharging = discharging == 'discharging'
        remaining = remaining.match( /\d{1,2}:\d{1,2}/ ) ? remaining : 'unknown'

        let battery_state = `${ percentage }% (${ remaining } remaining)`
        let daemon_state = ``
        if( discharging ) daemon_state += `forcing discharge to ${ maintain_percentage || 80 }%`
        else daemon_state += `smc charging ${ charging ? 'enabled' : 'disabled' }`

        const status_object = { percentage, remaining, charging, discharging, maintain_percentage, battery_state, daemon_state }
        log( 'Battery status: ', JSON.stringify( status_object ) )
        return status_object

    } catch ( e ) {
        log( `Error getting battery status: `, e )
        alert( `Battery limiter error: ${ e.message }` )
    }

}

/* ///////////////////////////////
// Battery cli functions
// /////////////////////////////*/
const enable_battery_limiter = async () => {


    try {
        // Start battery maintainer
        const status = await get_battery_status()
        const allow_force_discharge = get_force_discharge_setting()
        await exec_async( `${ battery } maintain ${ status?.maintain_percentage || 80 }${ allow_force_discharge ? ' --force-discharge' : '' }` )
        log( `enable_battery_limiter exec complete` )
        return status?.percentage
    } catch ( e ) {
        log( 'Error enabling battery: ', e )
        alert( e.message )
    }

}

const disable_battery_limiter = async () => {

    try {
        await exec_async( `${ battery } maintain stop` )
        const status = await get_battery_status()
        return status?.percentage
    } catch ( e ) {
        log( 'Error enabling battery: ', e )
        alert( e.message )
    }

}

const initialize_battery = async () => {

    try {

        // Check if dev mode
        const { development, skipupdate } = process.env
        if( development ) log( `Dev mode on, skip updates: ${ skipupdate }` )

        // Check for network
        const online = await Promise.race( [
            exec_async( `${ path_fix } curl -I https://icanhazip.com &> /dev/null` ).then( () => true ).catch( () => false ),
            exec_async( `${ path_fix } curl -I https://github.com &> /dev/null` ).then( () => true ).catch( () => false )
        ] )
        log( `Internet online: ${ online }` )

        // Check if battery is installed and visudo entries are complete. New visudo entries are added when we do new `sudo` stuff in battery.sh
        const [
            battery_installed,
            smc_installed,
            charging_in_visudo,
            discharging_in_visudo,
            magsafe_led_in_visudo,
            additional_magsafe_led_in_visudo
        ] = await Promise.all( [
            exec_async( `${ path_fix } which battery` ).catch( () => false ),
            exec_async( `${ path_fix } which smc` ).catch( () => false ),
            exec_async( `${ path_fix } sudo -n /usr/local/bin/smc -k CH0C -r` ).catch( () => false ),
            exec_async( `${ path_fix } sudo -n /usr/local/bin/smc -k CH0I -r` ).catch( () => false ),
            exec_async( `${ path_fix } sudo -n /usr/local/bin/smc -k ACLC -r` ).catch( () => false ),
            exec_async( `${ path_fix } sudo -n /usr/local/bin/smc -k ACLC -w 02` ).catch( () => false )
        ] )

        const visudo_complete = charging_in_visudo && discharging_in_visudo && magsafe_led_in_visudo && additional_magsafe_led_in_visudo
        const is_installed = battery_installed && smc_installed
        log( 'Is installed? ', is_installed )

        // Kill running instances of battery
        const processes = await exec_async( `ps aux | grep "/usr/local/bin/battery " | wc -l | grep -Eo "\\d*"` )
        log( `Found ${ `${ processes }`.replace( /\n/, '' ) } battery related processed to kill` )
        if( is_installed ) await exec_async( `${ battery } maintain stop` )
        await exec_async( `pkill -f "/usr/local/bin/battery.*"` ).catch( e => log( `Error killing existing battery progesses, usually means no running processes` ) )

        // If installed, update
        if( is_installed && visudo_complete ) {
            if( !online ) return log( `Skipping battery update because we are offline` )
            if( skipupdate ) return log( `Skipping update due to environment variable` )
            log( `Updating battery...` )
            const result = await exec_async( `${ battery } update silent` ).catch( e => e )
            log( `Update result: `, result )
        }

        // If not installed, run install script
        if( !is_installed || !visudo_complete ) {
            log( `Installing battery for ${ USER }...` )
            if( !online ) return alert( `Battery needs an internet connection to download the latest version, please connect to the internet and open the app again.` )
            if( !is_installed ) await alert( `Welcome to the Battery limiting tool. The app needs to install/update some components, so it will ask for your password. This should only be needed once.` )
            if( !visudo_complete ) await alert( `Battery needs to apply a backwards incompatible update, to do this it will ask for your password. This should not happen frequently.` )
            const result = await exec_sudo_async( `curl -s https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash -s -- $USER` )
            log( `Install result success `, result )
            await alert( `Battery background components installed successfully. You can find the battery limiter icon in the top right of your menu bar.` )
        }

        // Recover old battery setting on boot (as we killed all old processes above)
        await exec_async( `${ battery } maintain recover` )

        // Basic user tracking on app open, run it in the background so it does not cause any delay for the user
        if( online ) exec_async( `nohup curl "https://unidentifiedanalytics.web.app/touch/?namespace=battery" > /dev/null 2>&1` )


    } catch ( e ) {
        log( `Update/install error: `, e )
        await alert( `Error installing battery limiter: ${ e.message }` )
        app.quit()
        app.exit()
    }

}

const uninstall_battery = async () => {

    try {
        const confirmed = await confirm( `Are you sure you want to uninstall Battery?` )
        if( !confirmed ) return false
        await exec_sudo_async( `${ path_fix } sudo battery uninstall silent` )
        await alert( `Battery is now uninstalled!` )
        return true
    } catch ( e ) {
        log( 'Error uninstalling battery: ', e )
        alert( `Error uninstalling battery: ${ e.message }` )
        return false
    }

}


const is_limiter_enabled = async () => {

    try {
        const message = await exec_async( `${ battery } status` )
        log( `Limiter status message: `, message )
        return message.includes( 'being maintained at' )
    } catch ( e ) {
        log( `Error getting battery status: `, e )
        alert( `Battery limiter error: ${ e.message }` )
    }

}


module.exports = {
    enable_battery_limiter,
    disable_battery_limiter,
    initialize_battery,
    is_limiter_enabled,
    get_battery_status,
    uninstall_battery
}
