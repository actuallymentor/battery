const { ipcMain, nativeTheme, nativeImage, app } = require('electron')
const path = require('path')
const { log } = require('./helpers')
const { development } = process.env
const { resourcesPath } = process

// Logo assets
const asset_path = app.isPackaged ? resourcesPath : './assets'
const active_logo_light = percent => nativeImage.createFromPath( path.join( asset_path, `/battery-active${ percent && `-${ percent }` }.png` ) )
const active_logo_dark = percent => nativeImage.createFromPath( path.join( asset_path, `/battery-active-darkmode${ percent && `-${ percent }` }.png` ) )
const inactive_logo_light = percent => nativeImage.createFromPath( path.join( asset_path, `/battery-inactive${ percent && `-${ percent }` }.png` ) )
const inactive_logo_dark = percent => nativeImage.createFromPath( path.join( asset_path, `/battery-inactive-darkmode${ percent && `-${ percent }` }.png` ) )

/* ///////////////////////////////
// Logo handlers
// /////////////////////////////*/
const get_active_logo = ( percent = 100 ) => {

    // Image sizes available in /assets/
    log( `Get active logo for ${ percent }` )
    percent = Number( percent )
    const image_percentages = [ 20, 50, 80 ].sort()

    // Find which image size is the highest that is still under the current percentage
    let display_percentage = undefined
    image_percentages.map( percent_option => {
        if( percent_option < percent ) display_percentage = percent_option
    } )
    log( `Display percentage ${ display_percentage } based on ${ percent }` )

    return nativeTheme.shouldUseDarkColors ? active_logo_dark( display_percentage ) : active_logo_light( display_percentage )
}

const get_inactive_logo = ( percent = 100 ) => {

    // Image sizes available in /assets/
    log( `Get inactive logo for ${ percent }` )
    percent = Number( percent )
    const image_percentages = [ 20, 50, 80 ].sort()

    // Find which image size is the highest that is still under the current percentage
    let display_percentage = undefined
    image_percentages.map( percent_option => {
        if( percent_option < percent ) display_percentage = percent_option
    } )
    log( `Display percentage ${ display_percentage } based on ${ percent }` )

    return nativeTheme.shouldUseDarkColors ? inactive_logo_dark( display_percentage ) : inactive_logo_light( display_percentage )
}

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
