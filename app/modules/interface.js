const { shell, app, Tray, Menu } = require( 'electron' )
const { enable_battery_limiter, disable_battery_limiter, update_or_install_battery, is_limiter_enabled, get_battery_status } = require('./battery')
const { log, wait } = require("./helpers")
const { get_inactive_logo, get_active_logo } = require('./theme')

/* ///////////////////////////////
// Menu helpers
// /////////////////////////////*/
let tray = undefined

// Set interface to usable
const generate_app_menu = async () => {

    try {
        // Get battery and daemon status
        const [ battery_state, daemon_state, maintain_percentage=80 ] = await get_battery_status()

        // Check if limiter is on
        const limiter_on = await is_limiter_enabled()

        // Set tray icon
        tray.setImage( limiter_on ? get_active_logo() : get_inactive_logo() )

        // Build menu
        return Menu.buildFromTemplate( [

            {
                label: `Enable ${ maintain_percentage }% battery limit`,
                type: 'radio',
                checked: limiter_on,
                click: enable_limiter
            },
            {
                sublabel: 'thing',
                label: `Disable ${ maintain_percentage }% battery limit`,
                type: 'radio',
                checked: !limiter_on,
                click: disable_limiter
            },
            {
                type: 'separator'
            },
            {
                label: `Battery: ${ battery_state }`,
                enabled: false
            },
            {
                label: `Power: ${ daemon_state }`,
                enabled: false
            },
            {
                type: 'separator'
            },
            {
                label: `About v${ app.getVersion() }`,
                submenu: [
                    {
                        label: `Check for updates`,
                        click: () => shell.openExternal( `https://github.com/actuallymentor/battery/releases` )
                    },
                    {
                        label: `User manual`,
                        click: () => shell.openExternal( `https://github.com/actuallymentor/battery#readme` )
                    },
                    {
                        type: 'normal',
                        label: 'Command-line usage',
                        click: () => shell.openExternal( `https://github.com/actuallymentor/battery#-command-line-version` )
                    },
                    {
                        type: 'normal',
                        label: 'Help and feature requests',
                        click: () => shell.openExternal( `https://github.com/actuallymentor/battery/issues` )
                    }
                ]
            },
            {
                label: 'Quit',
                click: () => {
                    tray.destroy()
                    app.quit()
                }
            }
            
        ] )
    } catch( e ) {
        log( `Error generating menu: `, e )
    }

}

// Refresh tray with battery status values
const refresh_tray = async ( force_interactive_refresh = false ) => {
    log( "Refreshing tray icon..." )
    const new_menu = await generate_app_menu()
    if( force_interactive_refresh ) {
        log( `Forcing interactive refresh ${ force_interactive_refresh }` )
        tray.closeContextMenu()
        tray.popUpContextMenu( new_menu )
    }
    tray.setContextMenu( new_menu )
}

// Refresh app logo
const refresh_logo = async ( force ) => {

    if( force == 'active' ) return tray.setImage( get_active_logo() )
    if( force == 'inactive' ) return tray.setImage( get_inactive_logo() )

    const is_enabled = await is_limiter_enabled()
    if( is_enabled ) return tray.setImage( get_active_logo() )
    return tray.setImage( get_inactive_logo() )
}


/* ///////////////////////////////
// Initialisation
// /////////////////////////////*/
async function set_initial_interface() {

    log( "Starting tray app" )
    tray = new Tray( get_inactive_logo() )

    // Set "loading" context
    tray.setTitle( '  updating...' )
    
    log( "Tray app boot complete" )

    log( "Triggering boot-time auto-update" )
    await update_or_install_battery()
    log( "App initialisation process complete" )

    // Start battery handler
    await enable_battery_limiter()


    // Set tray styles
    tray.setTitle('')
    await refresh_tray()

    // Set tray open listener
    tray.on( 'mouse-enter', () => refresh_tray() )
    tray.on( 'click', () => refresh_tray() )


}

/* ///////////////////////////////
// User interactions
// /////////////////////////////*/
async function enable_limiter() {

    try {
        log( 'Enable limiter' )
        await refresh_logo( 'active' )
        await enable_battery_limiter()
        await refresh_tray()
    } catch( e ) {
        log( `Error in enable_limiter: `, e )
    }

}

async function disable_limiter() {

    try {
        log( 'Disable limiter' )
        await refresh_logo( 'inactive' )
        await disable_battery_limiter()
        await refresh_tray()
    } catch( e ) {
        log( `Error in disable_limiter: `, e )
    }

}

module.exports = {
    set_initial_interface
}