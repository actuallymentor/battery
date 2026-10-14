// Command line interactors
const { app } = require( 'electron' )
const { exec } = require( 'node:child_process' )
const { log, alert, wait, confirm } = require( './helpers' )
const { get_force_discharge_setting } = require( './settings' )
const { parseStatus } = require( './status' )
// Key families required by the CLI's centrally generated visudoconfig.
// The GUI does not duplicate percentage encoding or allowed write values.
const smc_commands = [ 'bfF0', 'bfD0', 'bfE0', 'CHIE' ]
const binfolder = '/usr/local/co.palokaj.battery'
const battery = `${ binfolder }/battery`

/* ///////////////////////////////
// Shell-execution helpers
// ///////////////////////////////
//
// exec_async_no_timeout(), exec_async() and exec_sudo_async() are async helper functions
// which run bash-shell commands.
//
// They provide a unified output contract:
//      Fulfilled result: { stdout: string, stderr: string }
//      Rejected result: 'Error' object having the following extra properties:
//          - 'cmd':    shell command string
//          - 'code':   shell exit code, 'ETIMEDOUT', 'SIGNAL' or 'UNKNOWN'
//          - 'output': { stdout: string, stderr: string }
//
// /////////////////////////////*/

const shell_options = {
    shell: '/bin/bash',
    env: { ...process.env, PATH: '/usr/bin:/bin:/usr/sbin:/sbin' }
}

// Execute without sudo
const exec_async_no_timeout = command => new Promise( ( resolve, reject ) => {

    log( `Executing ${ command }` )

    exec( command, shell_options, ( error, stdout, stderr ) => {

        const output = { stdout: stdout ?? '', stderr: stderr ?? '' }
        if (error) {
            error.code ??= (error.signal ? 'SIGNAL' : 'UNKNOWN')
            error.cmd ??= command
            error.output = output
            return reject( error )
        } else {
            return resolve( output )
        }

    } )

} )

const exec_async = ( command, timeout_in_ms=0 ) => {

    const workers = [ exec_async_no_timeout( command ) ]
    if ( timeout_in_ms > 0 ) {
        workers.push(
            wait(timeout_in_ms).then( () => {
                const error = new Error( `${ command } timed out` )
                error.code = 'ETIMEDOUT'
                error.cmd = command
                error.output = { stdout: '', stderr: '' }
                throw error;
            })
        );
    }

    return Promise.race( workers )
}

// Execute with sudo
const exec_sudo_async = command => new Promise( ( resolve, reject ) => {

    log( `Executing ${ command } by running:` )
    log( `osascript -e "do shell script \\"${ command }\\" with administrator privileges"` )

    exec( `osascript -e "do shell script \\"${ command }\\" with administrator privileges"`, shell_options, ( error, stdout, stderr ) => {

        const output = { stdout: stdout ?? '', stderr: stderr ?? '' }
        if (error) {
            error.code ??= (error.signal ? 'SIGNAL' : 'UNKNOWN')
            error.cmd ??= command
            error.output = output
            return reject(error)
        } else {
            return resolve(output)
        }

    } )

} )

/* ///////////////////////////////
// Battery cli functions
// /////////////////////////////*/

// Battery status checker
const get_battery_status = async () => {
    const result = await exec_async( `${ battery } status_json` )
    return parseStatus( result.stdout )
}

const enable_battery_limiter = async forceOverride => {
    try {
        const status = await get_battery_status()
        const target = status.target
        if( !Number.isInteger( target ) || target < 1 || target > 100 ) {
            throw new Error( 'No saved target. Set one with battery maintain N in Terminal.' )
        }
        const force = typeof forceOverride === 'boolean' ? forceOverride :
            typeof status.force_discharge === 'boolean' ? status.force_discharge : get_force_discharge_setting()
        // The CLI acknowledges verified application and a ready worker. A
        // timeout or launched process is never treated as successful application.
        await exec_async( `${ battery } maintain ${ target }${ force && target < 100 ? ' --force-discharge' : '' }` )
        return ( await get_battery_status() ).percentage
    } catch( e ) {
        log( 'Error enabling battery:', e )
        await alert( e.message )
        throw e
    }
}

const disable_battery_limiter = async () => {
    try {
        await exec_async( `${ battery } maintain stop` )
        return ( await get_battery_status() ).percentage
    } catch( e ) {
        log( 'Error stopping battery:', e )
        await alert( e.message )
        throw e
    }
}

const initialize_battery = async () => {
    try {
        const version = ( await exec_async( `${ battery } version` ) ).stdout.trim()
        if( !version.includes( 'local-firmware' ) ) {
            throw new Error( `This local app requires the matching CLI (${ smc_commands.join( ', ' ) }). Run ./install-local.sh from the checkout.` )
        }
        // Recover is idempotent and preserves an explicitly stopped policy.
        // Do not stop/pkill the controller or replace this build from upstream.
        await exec_async( `${ battery } maintain recover` )
        await get_battery_status()
    } catch( e ) {
        log( 'Battery initialization failed:', e )
        await alert( e.message )
        throw e
    }
}

const uninstall_battery = async () => {

    try {
        const confirmed = await confirm( `Are you sure you want to uninstall Battery?` )
        if( !confirmed ) return false
        // Restore the caller's policy before the privileged removal process.
        await exec_async( `${ battery } maintain stop` )
        await exec_sudo_async( `sudo ${ battery } uninstall silent` ).catch( e => {
            // Being killed is an expected successful completion for 'battery uninstall' and the osascript running it.
            // If you need to change this, check whether 'pkill -f <process cmd pattern>' is still used by 'battery uninstall'.
            if ( e.code !== 'SIGNAL' ) throw e;
        })
        await alert( `Battery is now uninstalled!` )
        return true
    } catch ( e ) {
        log( 'Error uninstalling battery: ', e )
        alert( `Error uninstalling battery: ${ e.message }` )
        return false
    }

}

const is_limiter_enabled = async () => ( await get_battery_status() ).limiter_applied

module.exports = {
    enable_battery_limiter,
    disable_battery_limiter,
    initialize_battery,
    is_limiter_enabled,
    get_battery_status,
    uninstall_battery
}
