const assert = require( 'node:assert/strict' )
const { get_tray_display_state } = require( '../modules/tray-display' )

const icon_mode = get_tray_display_state( {
    percentage: 83,
    limiter_on: true,
    show_percentage_only: false
} )
assert.equal( icon_mode.title, '' )
assert.equal( icon_mode.show_percentage_only, false )
assert.equal( icon_mode.icon_percentage, 83 )
assert.equal( icon_mode.icon_active, true )

const percentage_mode = get_tray_display_state( {
    percentage: '46.2',
    limiter_on: false,
    show_percentage_only: true
} )
assert.equal( percentage_mode.title, '46%' )
assert.equal( percentage_mode.show_percentage_only, true )
assert.equal( percentage_mode.icon_percentage, 46 )
assert.equal( percentage_mode.icon_active, false )

const bounds_mode = get_tray_display_state( {
    percentage: 120,
    limiter_on: true,
    show_percentage_only: true
} )
assert.equal( bounds_mode.title, '100%' )
assert.equal( bounds_mode.icon_percentage, 100 )

const invalid_mode = get_tray_display_state( {
    percentage: 'not-a-number',
    limiter_on: true,
    show_percentage_only: true
} )
assert.equal( invalid_mode.title, '0%' )
assert.equal( invalid_mode.icon_percentage, 0 )

console.log( 'tray display tests passed' )
