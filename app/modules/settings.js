const Store = require( 'electron-store' )
const { log, confirm } = require( './helpers' )
const store = new Store( {
    force_discharge_if_needed: {
        type: 'boolean'
    },
    telemetry: {
        type: 'boolean',
        default: true
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

const get_telemetry_setting = () => {
    let telemetry = store.get('telemetry');
    if (typeof telemetry === 'undefined') {
        telemetry = true;
        store.set('telemetry', true);
        log('Telemetry was undefined, set to enabled by default.');
    } else {
        log(`Telemetry is ${telemetry === true ? 'enabled' : 'disabled'}`);
    }
    return telemetry === true;
};

const toggle_telemetry = () => {
    const status = get_telemetry_setting()
    log( `Setting telemetry to ${ !status }` )
    store.set( 'telemetry', !status )
}

module.exports = {
    get_force_discharge_setting,
    toggle_force_discharge,
    update_force_discharge_setting,
    get_telemetry_setting,
    toggle_telemetry
}