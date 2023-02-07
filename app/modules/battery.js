// Command line interactors
const { exec } = require('node:child_process')
const sudo = require( 'sudo-prompt' )
const { log, alert, wait } = require( './helpers' )
const { USER } = process.env
const path_fix = 'PATH=$PATH:/bin:/usr/bin:/usr/local/bin:/usr/sbin:/opt/homebrew:/usr/bin/'
const battery = `${ path_fix } battery`
const { app } = require( 'electron' )
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
const exec_sudo_async = async command => new Promise( async ( resolve, reject ) => {

    const options = { name: 'Battery limiting utility', ...shell_options }
    log( `Sudo executing command: ${ command }` )
    sudo.exec( command, options, ( error, stdout, stderr ) => {

        if( error ) return reject( !!error )
        if( stderr ) return reject( !!stderr )
        if( stdout ) return resolve( !!stdout )

    } )

} )

/* ///////////////////////////////
// Battery cli functions
// /////////////////////////////*/
const enable_battery_limiter = async () => {

    try {
        // Start battery maintainer
        const status = await get_battery_status()
        await exec_async( `${ battery } maintain ${ status?.maintain_percentage || 80 }` )
        log( `enable_battery_limiter exec complete` )
        return status?.percentage
    } catch( e ) {
        log( 'Error enabling battery: ', e )
        alert( e.message )
    }

}

const disable_battery_limiter = async () => {

    try {
        await exec_async( `${ battery } maintain stop` )
        const status = await get_battery_status()
        return status?.percentage
    } catch( e ) {
        log( 'Error enabling battery: ', e )
        alert( e.message )
    }

}

const update_or_install_battery = async () => {

    try {

        // Check for network
        const online = await Promise.race( [
            exec_async( `${ path_fix } curl icanhasip.com &> /dev/null` ).then( () => true ).catch( () => false ),
            exec_async( `${ path_fix } curl github.com &> /dev/null` ).then( () => true ).catch( () => false )
        ] )
        log( `Internet online: ${ online }` )

        // Check if xcode build tools are installed
        const xcode_installed = await exec_async( `${ path_fix } which git` ).catch( () => false )
        if( !xcode_installed ) {
            alert( `The Battery tool needs Xcode to be installed, please accept the terms and conditions for installation` )
            await exec_async( `${ path_fix } xcode-select --install` )
            alert( `Please restart the Battery app after Xcode finished installing` )
            app.exit()
        }

        // Check if battery is installed
        const [
            battery_installed,
            smc_installed,
            charging_in_visudo,
            discharging_in_visudo
        ] = await Promise.all( [
            exec_async( `${ path_fix } which battery` ).catch( () => false ),
            exec_async( `${ path_fix } which smc` ).catch( () => false ),
            exec_async( `${ path_fix } sudo -n /usr/local/bin/smc -k CH0C -r` ).catch( () => false ),
            exec_async( `${ path_fix } sudo -n /usr/local/bin/smc -k CH0I -r` ).catch( () => false )
        ] )

        const visudo_complete = charging_in_visudo && discharging_in_visudo
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
            log( `Updating battery...` )
            const result = await exec_async( `${ battery } update silent` )
            log( `Update result: `, result )
        }

        // If not installed, run install script
        if( !is_installed || !visudo_complete ) {
            log( `Installing battery for ${ USER }...` )
            if( !online ) return alert( `Battery needs an internet connection to download the latest version, please connect to the internet and open the app again.` )
            await alert( `Welcome to the Battery limiting tool. The app needs to install/update some components, so it will ask for your password. This should only be needed once.` )
            const result = await exec_sudo_async( `curl -s https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash -s -- $USER` )
            log( `Install result: `, result )
            await alert( `Battery background components installed successfully. You can find the battery limiter icon in the top right of your menu bar.` )
        }


    } catch( e ) {
        log( `Update/install error: `, e )
        alert( `Error installing battery limiter: ${ e.message }` )
    }

}


const is_limiter_enabled = async () => {

    try {
        const message = await exec_async( `${ battery } status` )
        log( `Limiter status message: `, message )
        return message.includes( 'being maintained at' )
    } catch( e ) {
        log( `Error getting battery status: `, e )
        alert( `Battery limiter error: ${ e.message }` )
    }

}

const get_battery_status = async () => {

    try {
        const message = await exec_async( `${ battery } status_csv` )
        let [ percentage, remaining, charging, discharging, maintain_percentage ] = message.split( ',' )
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

    } catch( e ) {
        log( `Error getting battery status: `, e )
        alert( `Battery limiter error: ${ e.message }` )
    }

}

module.exports = {
    enable_battery_limiter,
    disable_battery_limiter,
    update_or_install_battery,
    is_limiter_enabled,
    get_battery_status
}