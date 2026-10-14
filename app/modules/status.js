// A status read must never turn missing or stale telemetry into 'charging off'.
const powerLabels = {
    charging: 'Charging',
    battery: 'Using battery power',
    initial_discharge: 'Initial discharge to target',
    external_unconfirmed: 'External power; battery use not verified',
    external_verifying: 'External power; verifying bypass',
    bypass_verified: 'Bypass verified',
    limit_failed: 'Charge limit failed',
    unknown: 'Power state unknown'
}
const appliedLabels = {
    verified: 'applied', failed: 'failed', unknown: 'unconfirmed'
}
const parseStatus = text => {
    const s = JSON.parse( text )
    if( s.schema !== 1 || ![ 'firmware', 'legacy' ].includes( s.backend ) ||
        ![ 'enabled', 'stopped', 'unlimited', 'unset' ].includes( s.mode ) ||
        !Object.hasOwn( appliedLabels, s.applied ) || !Object.hasOwn( powerLabels, s.power ) ||
        !( s.target === null || Number.isInteger( s.target ) && s.target >= 1 && s.target <= 100 ) ||
        !( s.percentage === null || Number.isInteger( s.percentage ) && s.percentage >= 0 && s.percentage <= 100 ) ) {
        throw new Error( 'Unsupported or invalid battery status response' )
    }
    const percentage = s.percentage ?? '??'
    const request = s.mode === 'unlimited' ? 'Full charging allowed' :
        s.mode === 'stopped' ? `Limit stopped (saved ${ s.target }%)` :
        s.mode === 'unset' ? 'Limit not configured' : `${ s.target }% limit ${ appliedLabels[s.applied] }`
    return {
        ...s, percentage,
        maintain_percentage: s.target === null ? undefined : String( s.target ),
        charging: s.power === 'charging' ? true : [ 'bypass_verified', 'external_verifying', 'battery' ].includes( s.power ) ? false : null,
        discharging: [ 'battery', 'initial_discharge' ].includes( s.power ),
        battery_state: `${ percentage }%`,
        daemon_state: `${ request }; ${ powerLabels[s.power] }`,
        limiter_requested: s.mode === 'enabled',
        limiter_applied: s.mode === 'enabled' && s.applied === 'verified'
    }
}
module.exports = { parseStatus }
