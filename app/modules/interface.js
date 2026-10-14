const { shell, app, Tray, Menu, powerMonitor, nativeTheme } = require( 'electron' )
const { enable_battery_limiter, disable_battery_limiter, initialize_battery, is_limiter_enabled, get_battery_status, uninstall_battery } = require( './battery' )
const { log } = require( "./helpers" )
const { get_logo_template } = require( './theme' )
const { get_force_discharge_setting, update_force_discharge_setting } = require( './settings' )

/* ///////////////////////////////
// Menu helpers
// /////////////////////////////*/
let tray = undefined


// Set interface to usable
const generate_app_menu = async () => {

    try {
        // Get battery and daemon status
        const status = await get_battery_status()
        const { battery_state, daemon_state, maintain_percentage, percentage } = status
        const limiter_on = status.limiter_requested
        const allow_discharge = typeof status.force_discharge === 'boolean' ? status.force_discharge : get_force_discharge_setting()

        // Set tray icon
        log( `Generate app menu percentage: ${ percentage } (discharge ${ allow_discharge ? 'allowed' : 'disallowed' }, limited ${ limiter_on ? 'on' : 'off' })` )
        tray.setImage( get_logo_template( percentage, status.limiter_applied ) )

        // Build menu
        return Menu.buildFromTemplate( [

            {
                label: maintain_percentage ? ( maintain_percentage === '100' ? 'Allow full charging' : `Enable ${ maintain_percentage }% battery limit` ) : 'Set target with battery maintain N',
                enabled: Boolean( maintain_percentage ),
                type: 'radio',
                checked: limiter_on || status.mode === 'unlimited',
                click: enable_limiter
            },
            {
                label: 'Stop battery limit',
                enabled: Boolean( maintain_percentage ),
                type: 'radio',
                checked: !limiter_on && status.mode !== 'unlimited',
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
                label: `Advanced settings`,
                submenu: [
                    {
                        label: `Allow initial force-discharge`,
                        enabled: limiter_on,
                        type: 'checkbox',
                        checked: allow_discharge,
                        click: async () => {
                            const success = await update_force_discharge_setting( allow_discharge )
                            if( limiter_on && success ) await restart_limiter( !allow_discharge )
                        }
                    }
                ]
            },
            {
                label: `About v${ app.getVersion() }`,
                submenu: [
                    {
                        label: 'Local build updates are installed manually',
                        enabled: false
                    },
                    {
                        type: 'normal',
                        label: `Uninstall Battery ${ app.getVersion() }`,
                        click: async () => {
                            const uninstalled = await uninstall_battery()
                            if( !uninstalled ) return
                            tray.destroy()
                            app.quit()
                        }
                    },
                    {
                        type: 'separator'
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
    } catch ( e ) {
        log( `Error generating menu: `, e )
        tray.setImage( get_logo_template( 0, false ) )
        return Menu.buildFromTemplate( [
            { label: 'Battery status unavailable', enabled: false },
            { label: 'Retry status', click: () => refresh_tray() },
            { label: 'Quit', click: () => app.quit() }
        ] )
    }

}

// Periodic refreshing of icon and state
let refresh_timer = undefined
const set_interface_update_timer = async ( disable_only=false ) => {

    if( !disable_only ) log( `Refreshing interface update timer` )
    else log( `Disabling interface update timer due to disable_only set to `, disable_only )

    // Firmware control lives in the CLI worker, including while the screen is
    // locked. UI refresh never writes SMC and never delays near the target.
    if( refresh_timer ) clearInterval( refresh_timer )
    if( !disable_only ) refresh_timer = setInterval( refresh_tray, 60000 )

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

    // Refresh timer 
    log( `Resetting interface timer speed` )
    set_interface_update_timer()

}

// Refresh app logo
const refresh_logo = async ( percent=0, force ) => {

    log( `Refresh logo for percentage ${ percent }, force ${ force }` )
    if( force == 'active' ) return tray.setImage( get_logo_template( percent, true ) )
    if( force == 'inactive' ) return tray.setImage( get_logo_template( percent, false ) )

    const is_enabled = await is_limiter_enabled()
    return tray.setImage( get_logo_template( percent, is_enabled ) )
}


/* ///////////////////////////////
// Initialisation
// /////////////////////////////*/
async function set_initial_interface() {

    log('\n===\n=== Starting tray app\n===\n')
    tray = new Tray( get_logo_template( 100, true ) )

    // Set "loading" context
    tray.setTitle( '  connecting...' )
    
    log( "Tray app boot complete" )

    log( 'Connecting to local battery controller' )
    await initialize_battery()
    log( "App initialisation process complete" )

    // initialize_battery already attached to/recovered the existing policy.

    // Set tray styles
    tray.setTitle( '' )
    await refresh_tray()

    // Set tray open listener
    tray.on( 'mouse-enter', () => refresh_tray() )
    tray.on( 'click', () => refresh_tray() )
    nativeTheme.on( 'updated', () => refresh_tray() )

    // Set refresh timer for the battery icon
    set_interface_update_timer()
    powerMonitor.on( 'lock-screen', () => set_interface_update_timer( true ) )
    powerMonitor.on( 'unlock-screen', () => set_interface_update_timer() )
    powerMonitor.on( 'suspend', () => set_interface_update_timer( true ) )
    powerMonitor.on( 'resume', () => refresh_tray() )
    powerMonitor.on( 'on-ac', () => refresh_tray() )
    powerMonitor.on( 'on-battery', () => refresh_tray() )

}

/* ///////////////////////////////
// User interactions
// /////////////////////////////*/
async function enable_limiter() {

    try {
        log( 'Enable limiter' )
        const percent_left = await enable_battery_limiter()
        log( `Interface enabled limiter, percentage remaining: ${ percent_left }` )
        await refresh_logo( percent_left )
        await refresh_tray()
    } catch ( e ) {
        log( `Error in enable_limiter: `, e )
    }

}

async function disable_limiter() {

    try {
        log( 'Disable limiter' )
        const percent_left = await disable_battery_limiter()
        log( `Interface enabled limiter, percentage remaining: ${ percent_left }` )
        await refresh_logo( percent_left )
        await refresh_tray()
    } catch ( e ) {
        log( `Error in disable_limiter: `, e )
    }

}

async function restart_limiter( forceOverride ) {

    try {
        log( 'Restart limiter' )
        const percent_left = await enable_battery_limiter( forceOverride )
        await refresh_logo( percent_left )
        await refresh_tray()
    } catch ( e ) {
        log( `Error in restart_limiter: `, e )
    }

}


module.exports = {
    set_initial_interface
}