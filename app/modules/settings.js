const Store = require( 'electron-store' )
const { is_limiter_enabled, disable_battery_limiter, enable_battery_limiter } = require( './battery' )
const { log } = require( './helpers' )
const { refresh_tray } = require( './interface' )
const store = new Store( {
    force_discharge_if_needed: {
        type: 'boolean'
    }
} )

const get_force_discharge_setting = () => {
    // Check if force discharge is on
    const force_discharge_if_needed = store.get( 'force_discharge_if_needed' )
    log( `🔥 Force discharge setting: ${ typeof force_discharge_if_needed } ${ force_discharge_if_needed }` )
    return force_discharge_if_needed === true
}

const toggle_force_discharge = () => {
    const status = get_force_discharge_setting()
    log( `Setting force discharge to ${ !status }` )
    store.set( 'force_discharge_if_needed', !status )
}

// Update the force discharge setting
const update_force_discharge_setting = async () => {

    try {

        const currently_allowed = get_force_discharge_setting()
        if( !currently_allowed ) {
            const proceed = await confirm( `This setting allows your battery to drain to the desired maintenance level while plugged in. This does not work well in Clamshell mode (laptop closed with an external monitor).\n\nAllow force-discharging?` )
            if( !proceed ) return
        }

        // Toggle setting and refresh tray
        toggle_force_discharge()
        await refresh_tray()

        // Restart battery if needed
        const limiter_on = await is_limiter_enabled()
        if( limiter_on ) {
            await disable_battery_limiter()
            await enable_battery_limiter()
        }

    } catch ( e ) {
        log( `Error updating force discharge: `, e )
    }

}

module.exports = {
    get_force_discharge_setting,
    toggle_force_discharge,
    update_force_discharge_setting
}