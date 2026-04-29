const Store = require( 'electron-store' )
const { log, confirm } = require( './helpers' )

const DEFAULT_FLOOR_PERCENTAGE = 50
const DEFAULT_CEILING_PERCENTAGE = 80

const clamp_percentage = value => Math.max( 1, Math.min( 100, value ) )
const normalize_percentage = ( value, fallback ) => {
    const parsed = Number( value )
    if( !Number.isFinite( parsed ) ) return fallback
    return clamp_percentage( Math.round( parsed ) )
}

const store = new Store( {
    force_discharge_if_needed: {
        type: 'boolean'
    },
    maintain_floor_enabled: {
        type: 'boolean',
        default: false
    },
    maintain_floor_percentage: {
        type: 'number',
        default: DEFAULT_FLOOR_PERCENTAGE
    },
    maintain_ceiling_percentage: {
        type: 'number',
        default: DEFAULT_CEILING_PERCENTAGE
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

const get_maintenance_settings = () => {
    const floor_enabled = store.get( 'maintain_floor_enabled' ) === true
    const floor_percentage = normalize_percentage(
        store.get( 'maintain_floor_percentage' ),
        DEFAULT_FLOOR_PERCENTAGE
    )
    const ceiling_percentage = normalize_percentage(
        store.get( 'maintain_ceiling_percentage' ),
        DEFAULT_CEILING_PERCENTAGE
    )

    return {
        floor_enabled,
        floor_percentage,
        ceiling_percentage
    }
}

const set_maintenance_settings = ( settings = {} ) => {
    const current_settings = get_maintenance_settings()
    const next_floor_enabled = typeof settings.floor_enabled === 'boolean'
        ? settings.floor_enabled
        : current_settings.floor_enabled
    const next_floor_percentage = normalize_percentage(
        settings.floor_percentage,
        current_settings.floor_percentage
    )
    const next_ceiling_percentage = normalize_percentage(
        settings.ceiling_percentage,
        current_settings.ceiling_percentage
    )

    const safe_floor_percentage = Math.min( next_floor_percentage, next_ceiling_percentage - 1 )
    const safe_ceiling_percentage = Math.max( next_ceiling_percentage, safe_floor_percentage + 1 )

    store.set( 'maintain_floor_enabled', next_floor_enabled )
    store.set( 'maintain_floor_percentage', next_floor_enabled ? Math.max( 1, safe_floor_percentage ) : next_floor_percentage )
    store.set( 'maintain_ceiling_percentage', safe_ceiling_percentage )

    const updated_settings = get_maintenance_settings()
    log( `Updated maintenance settings: ${ JSON.stringify( updated_settings ) }` )
    return updated_settings
}

const get_maintenance_command = () => {
    const { floor_enabled, floor_percentage, ceiling_percentage } = get_maintenance_settings()
    if( floor_enabled ) return `maintain ${ floor_percentage }-${ ceiling_percentage }`
    return `maintain ${ ceiling_percentage }`
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

module.exports = {
    get_force_discharge_setting,
    toggle_force_discharge,
    update_force_discharge_setting,
    get_maintenance_settings,
    set_maintenance_settings,
    get_maintenance_command
}
