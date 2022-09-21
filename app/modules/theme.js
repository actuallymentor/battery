const { ipcMain, nativeTheme, nativeImage, app } = require('electron')
const path = require('path')
const { development } = process.env
const { resourcesPath } = process

// Logo assets
const asset_path = app.isPackaged ? resourcesPath : './assets'
const active_logo_light = nativeImage.createFromPath( path.join( asset_path, `/battery-active.png` ) )
const active_logo_dark = nativeImage.createFromPath( path.join( asset_path, `/battery-active-darkmode.png` ) )
const inactive_logo_light = nativeImage.createFromPath( path.join( asset_path, `/battery-inactive.png` ) )
const inactive_logo_dark = nativeImage.createFromPath( path.join( asset_path, `/battery-inactive-darkmode.png` ) )

/* ///////////////////////////////
// Logo handlers
// /////////////////////////////*/
const get_active_logo = () => nativeTheme.shouldUseDarkColors ? active_logo_dark : active_logo_light
const get_inactive_logo = () => nativeTheme.shouldUseDarkColors ? inactive_logo_dark : inactive_logo_light

/* ///////////////////////////////
// Handle dark theme switching
// /////////////////////////////*/
ipcMain.handle('dark-mode:toggle', () => {

    if ( nativeTheme.shouldUseDarkColors ) {
        nativeTheme.themeSource = 'light'
    } else {
        nativeTheme.themeSource = 'dark'
    }

    return nativeTheme.shouldUseDarkColors
} )

ipcMain.handle( 'dark-mode:system', () => {
    nativeTheme.themeSource = 'system'
} )

module.exports = {
    get_active_logo,
    get_inactive_logo
}
