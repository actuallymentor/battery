const { shell, app, Tray, Menu } = require( 'electron' )
const { enable_battery_limiter, disable_battery_limiter, update_or_install_battery, is_limiter_enabled } = require('./battery')
const { log } = require("./helpers")
const { get_inactive_logo, get_active_logo } = require('./theme')


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

    // Check if limiter is on
    const limiter_on = await is_limiter_enabled()

    // Set interface to usable
    const app_menu = Menu.buildFromTemplate( [

        {
            label: 'Enable 80% battery limit',
            type: 'radio',
            checked: limiter_on,
            click: enable_limiter
        },
        {
            label: 'Disable 80% battery limit',
            type: 'radio',
            checked: !limiter_on,
            click: disable_limiter
        },
        {
            label: 'About',
            click: () => shell.openExternal( `https://github.com/actuallymentor/battery` )
        },
        {
            label: 'Quit',
            click: () => {
                tray.destroy()
                app.quit()
            }
        }
        
    ] )

    tray.setImage( limiter_on ? get_active_logo() : get_inactive_logo() )
    tray.setTitle('')
    tray.setContextMenu( app_menu )

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