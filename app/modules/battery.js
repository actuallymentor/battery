// Command line interactors
const { exec } = require('node:child_process')
const sudo = require( 'sudo-prompt' )
const { log, alert } = require( './helpers' )

const path_fix = 'PATH=$PATH:/usr/local/bin/battery'
const battery = `${ path_fix } battery`
const shell_options = {
    shell: '/bin/bash',
    env: { ...process.env, PATH: `${ process.env.PATH }:/usr/local/bin` }
}

// Execute without sudo
const exec_async = command => new Promise( ( resolve, reject ) => {

    exec( command, shell_options, ( error, stdout, stderr ) => {

        if( error ) return reject( error )
        if( stderr ) return reject( stderr )
        if( stdout ) return resolve( stdout )

    } )

} )

// Execute with sudo
const exec_sudo_async = async command => new Promise( async ( resolve, reject ) => {

    const options = { name: 'Battery limiting utility', ...shell_options }

    sudo.exec( command, options, ( error, stdout, stderr ) => {

        if( error ) return reject( error )
        if( stderr ) return reject( stderr )
        if( stdout ) return resolve( stdout )

    } )

} )

/* ///////////////////////////////
// Battery cli functions
// /////////////////////////////*/
const enable_battery_limiter = async () => {

    try {
        await exec_async( `${ battery } maintain 80` )
    } catch( e ) {
        log( 'Error enabling battery: ', e )
        alert( e.message )
    }

}

const disable_battery_limiter = async () => {

    try {
        await exec_async( `${ battery } maintain stop` )
    } catch( e ) {
        log( 'Error enabling battery: ', e )
        alert( e.message )
    }

}

const update_or_install_battery = async () => {

    try {

        // Check if battery is installed
        const is_installed = await exec_async( `${ path_fix } which battery` ).catch( () => false )
        log( 'Is installed? ', is_installed )

        // If installed, update
        if( is_installed ) {
            log( `Updating battery...` )
            const result = await exec_async( `${ battery } update silent` )
            log( `Update result: `, result )
        }

        // If not installed, run install script
        if( !is_installed ) {
            log( `Installing battery...` )
            const result = await exec_sudo_async( `curl -s https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash -l` )
            log( `Install result: `, result )
        }


    } catch( e ) {
        log( `Update/install error: `, e )
        alert( `Error installing battery limiter: ${ e.message }` )
    }

}

const is_limiter_enabled = async () => {

    try {
        const message = await exec_async( `${ battery } status` )
        return message.includes( 'being maintained at' )
    } catch( e ) {
        log( `Error getting battery status: `, e )
        alert( `Battery limiter error: ${ e.message }` )
    }

}

module.exports = {
    enable_battery_limiter,
    disable_battery_limiter,
    update_or_install_battery,
    is_limiter_enabled
}