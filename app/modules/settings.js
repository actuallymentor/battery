const Store = require( 'electron-store' )
const { log, confirm } = require( './helpers' )
const store = new Store( {
    force_discharge_if_needed: {
        type: 'boolean'
    },
    custom_percentage: {
        type: 'number'
    }
} )

const get_force_discharge_setting = () => {
    // Check if force discharge is on
    const force_discharge_if_needed = store.get( 'force_discharge_if_needed' )
    log( `Force discharge setting: ${ typeof force_discharge_if_needed } ${ force_discharge_if_needed }` )
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
            if( !proceed ) return false
        }

        // Toggle setting and refresh tray
        toggle_force_discharge()
        return true


    } catch ( e ) {
        log( `Error updating force discharge: `, e )
    }

}

// Get the custom charge percentage (defaults to 80)
const get_custom_percentage = () => {
    const custom_percentage = store.get( 'custom_percentage' )
    log( `Custom percentage setting: ${ custom_percentage }` )
    return typeof custom_percentage === 'number' ? custom_percentage : 80
}

// Set the custom charge percentage (clamped between 20 and 100)
const set_custom_percentage = ( value ) => {
    const clamped = Math.max( 20, Math.min( 100, Math.round( value ) ) )
    log( `Setting custom percentage to ${ clamped }` )
    store.set( 'custom_percentage', clamped )
    return clamped
}

module.exports = {
    get_force_discharge_setting,
    toggle_force_discharge,
    update_force_discharge_setting,
    get_custom_percentage,
    set_custom_percentage
}