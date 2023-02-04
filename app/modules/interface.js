const { shell, app, Tray, Menu } = require( 'electron' )
const { enable_battery_limiter, disable_battery_limiter, update_or_install_battery, is_limiter_enabled, get_battery_status } = require('./battery')
const { log } = require("./helpers")
const { get_inactive_logo, get_active_logo } = require('./theme')

/* ///////////////////////////////
// Menu helpers
// /////////////////////////////*/
let tray = undefined

// Set interface to usable
const generate_app_menu = async () => {

    // Get battery and daemon status
    const [ battery_state, daemon_state ] = await get_battery_status()

    // Check if limiter is on
    const limiter_on = await is_limiter_enabled()

    // Set tray icon
    tray.setImage( limiter_on ? get_active_logo() : get_inactive_logo() )

    // Build menu
    return Menu.buildFromTemplate( [

        {
            label: 'Enable 80% battery limit',
            type: 'radio',
            checked: limiter_on,
            click: enable_limiter
        },
        {
            sublabel: 'thing',
            label: 'Disable 80% battery limit',
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

}

// Refresh tray with battery status values
const refresh_tray = async () => tray.setContextMenu( await generate_app_menu() )


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
    log( "Update process complete" )


    // Set tray styles
    tray.setTitle('')
    await refresh_tray()

    // Set tray open listener
    tray.on( 'click', refresh_tray )


}

/* ///////////////////////////////
// User interactions
// /////////////////////////////*/
async function enable_limiter() {

    log( 'Enable limiter' )
    tray.setImage( get_active_logo() )
    await enable_battery_limiter()

}

async function disable_limiter() {

    log( 'Disable limiter' )
    tray.setImage( get_inactive_logo() )
    await disable_battery_limiter()

}

module.exports = {
    set_initial_interface
}