const path = require( 'path' )
const { BrowserWindow, ipcMain, screen } = require( 'electron' )
const { log } = require( './helpers' )
const { get_maintenance_settings, set_maintenance_settings } = require( './settings' )

let limits_window = null
let apply_listener = null
let close_listener = null

const clamp = ( value, min, max ) => Math.max( min, Math.min( max, value ) )

const position_window = tray => {
    if( !tray || !limits_window ) return

    const tray_bounds = tray.getBounds()
    const window_bounds = limits_window.getBounds()
    const display = screen.getDisplayNearestPoint( {
        x: tray_bounds.x,
        y: tray_bounds.y
    } )

    const x = clamp(
        Math.round( tray_bounds.x + tray_bounds.width / 2 - window_bounds.width / 2 ),
        display.workArea.x + 8,
        display.workArea.x + display.workArea.width - window_bounds.width - 8
    )

    const y = clamp(
        Math.round( tray_bounds.y + tray_bounds.height + 8 ),
        display.workArea.y + 8,
        display.workArea.y + display.workArea.height - window_bounds.height - 8
    )

    limits_window.setPosition( x, y, false )
}

const cleanup_listeners = () => {
    if( apply_listener ) ipcMain.removeListener( 'battery-limits:apply', apply_listener )
    if( close_listener ) ipcMain.removeListener( 'battery-limits:close', close_listener )
    apply_listener = null
    close_listener = null
}

const open_limits_window = tray => {
    if( limits_window ) {
        limits_window.show()
        limits_window.focus()
        position_window( tray )
        return limits_window
    }

    limits_window = new BrowserWindow( {
        width: 360,
        height: 360,
        show: false,
        resizable: false,
        minimizable: false,
        maximizable: false,
        fullscreenable: false,
        skipTaskbar: true,
        alwaysOnTop: true,
        title: 'Battery Optimizer',
        backgroundColor: '#0f172a',
        webPreferences: {
            nodeIntegration: true,
            contextIsolation: false
        }
    } )

    limits_window.removeMenu()
    limits_window.loadFile( path.join( __dirname, '..', 'views', 'limits.html' ) )

    limits_window.once( 'ready-to-show', () => {
        if( !limits_window ) return
        limits_window.show()
        limits_window.focus()
        position_window( tray )
        limits_window.webContents.send( 'battery-limits:init', get_maintenance_settings() )
    } )

    apply_listener = ( event, settings ) => {
        if( !limits_window || event.sender.id !== limits_window.webContents.id ) return

        const updated_settings = set_maintenance_settings( settings )
        log( `Applied battery limits: ${ JSON.stringify( updated_settings ) }` )
        limits_window.webContents.send( 'battery-limits:applied', updated_settings )
        limits_window.close()
    }

    close_listener = ( event ) => {
        if( !limits_window || event.sender.id !== limits_window.webContents.id ) return
        limits_window.close()
    }

    ipcMain.on( 'battery-limits:apply', apply_listener )
    ipcMain.on( 'battery-limits:close', close_listener )

    limits_window.on( 'closed', () => {
        cleanup_listeners()
        limits_window = null
    } )

    return limits_window
}

module.exports = {
    open_limits_window
}
