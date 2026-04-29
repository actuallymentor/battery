const { ipcRenderer } = require( 'electron' )

const floorEnabledInput = document.getElementById( 'floor-enabled' )
const floorGroup = document.getElementById( 'floor-group' )
const floorInput = document.getElementById( 'floor' )
const ceilingInput = document.getElementById( 'ceiling' )
const floorValue = document.getElementById( 'floor-value' )
const ceilingValue = document.getElementById( 'ceiling-value' )
const applyButton = document.getElementById( 'apply' )
const cancelButton = document.getElementById( 'cancel' )

const clamp = ( value, min, max ) => Math.max( min, Math.min( max, value ) )

const renderFloorState = () => {
    const enabled = floorEnabledInput.checked
    floorGroup.setAttribute( 'aria-hidden', String( !enabled ) )
}

const syncLabels = () => {
    floorValue.textContent = `${ floorInput.value }%`
    ceilingValue.textContent = `${ ceilingInput.value }%`
}

const syncBounds = () => {
    const floor = Number( floorInput.value )
    const ceiling = Number( ceilingInput.value )

    if( floorEnabledInput.checked ) {
        if( floor >= ceiling ) {
            ceilingInput.value = String( clamp( floor + 1, 2, 100 ) )
        }
        if( Number( floorInput.value ) >= Number( ceilingInput.value ) ) {
            floorInput.value = String( clamp( Number( ceilingInput.value ) - 1, 1, 99 ) )
        }
    }

    syncLabels()
}

floorEnabledInput.addEventListener( 'change', () => {
    renderFloorState()
    syncBounds()
} )

floorInput.addEventListener( 'input', syncBounds )
ceilingInput.addEventListener( 'input', syncBounds )

applyButton.addEventListener( 'click', () => {
    ipcRenderer.send( 'battery-limits:apply', {
        floor_enabled: floorEnabledInput.checked,
        floor_percentage: Number( floorInput.value ),
        ceiling_percentage: Number( ceilingInput.value )
    } )
} )

cancelButton.addEventListener( 'click', () => {
    ipcRenderer.send( 'battery-limits:close' )
} )

ipcRenderer.on( 'battery-limits:init', ( _event, settings ) => {
    floorEnabledInput.checked = settings.floor_enabled === true
    floorInput.value = String( settings.floor_percentage ?? 50 )
    ceilingInput.value = String( settings.ceiling_percentage ?? 80 )
    renderFloorState()
    syncBounds()
} )

ipcRenderer.on( 'battery-limits:applied', ( _event, settings ) => {
    floorEnabledInput.checked = settings.floor_enabled === true
    floorInput.value = String( settings.floor_percentage )
    ceilingInput.value = String( settings.ceiling_percentage )
    renderFloorState()
    syncBounds()
} )

renderFloorState()
syncLabels()
