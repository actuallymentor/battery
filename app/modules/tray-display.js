const get_tray_display_state = ( { percentage = 100, limiter_on = true, show_percentage_only = false } ) => {

    const parsed_percentage = Number( percentage )
    const safe_percentage = Number.isFinite( parsed_percentage )
        ? Math.min( 100, Math.max( 0, Math.round( parsed_percentage ) ) )
        : 0

    return {
        title: show_percentage_only ? `${ safe_percentage }%` : '',
        show_percentage_only,
        icon_percentage: safe_percentage,
        icon_active: limiter_on
    }

}

module.exports = {
    get_tray_display_state
}
