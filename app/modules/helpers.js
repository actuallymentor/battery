const { promises: fs } = require( 'fs' )
const { HOME } = process.env
const util = require( 'util' )

let has_alerted_user_no_home = false

const { dialog } = require( 'electron' )
const { t } = require( './i18n' )
const alert = ( message ) => dialog.showMessageBox( { message } )
const confirm = ( message ) => dialog.showMessageBox( { message, buttons: [ t( 'dialog.confirm_button' ), t( 'dialog.cancel_button' ) ] } ).then( ( { response } ) => {
    if( response == 0 ) return true
    return false
} )
const wait = time_in_ms => new Promise( resolve => {
    setTimeout( resolve, time_in_ms )
} )

const log = async ( ...messages ) => {

    // Log to console
    console.log( ...messages )

    // Log to file if possible
    try {
        if( HOME ) {
            await fs.mkdir( `${ HOME }/.battery/`, { recursive: true } )
            const line = util.format(...messages) + "\n";
            await fs.appendFile( `${ HOME }/.battery/gui.log`, line, 'utf8' )
        } else if( !has_alerted_user_no_home ) {
            alert( t( 'dialog.no_home' ) )
            has_alerted_user_no_home = true
        }
    } catch ( e ) {
        console.log( `Unable to write logs to file: `, e )
    }
}

module.exports = {
    log,
    alert,
    wait,
    confirm
}