const Store = require( 'electron-store' )
const { log, confirm } = require( './helpers' )
const store = new Store( {
    force_discharge_if_needed: {
        type: 'boolean'
    },
    percentage_only_menubar: {
        type: 'boolean'
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

const get_percentage_only_setting = () => {
    const percentage_only_menubar = store.get( 'percentage_only_menubar' )
    log( `Percentage only menubar setting: ${ typeof percentage_only_menubar } ${ percentage_only_menubar }` )
    return percentage_only_menubar === true
}

const toggle_percentage_only_setting = () => {
    const status = get_percentage_only_setting()
    log( `Setting percentage-only menubar mode to ${ !status }` )
    store.set( 'percentage_only_menubar', !status )
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

const update_percentage_only_setting = async () => {

    try {
        toggle_percentage_only_setting()
        return true
    } catch ( e ) {
        log( `Error updating percentage-only mode: `, e )
    }

}

module.exports = {
    get_force_discharge_setting,
    toggle_force_discharge,
    update_force_discharge_setting,
    get_percentage_only_setting,
    toggle_percentage_only_setting,
    update_percentage_only_setting
}
