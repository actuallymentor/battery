const { promises: fs } = require( 'fs' )
const { HOME } = process.env
const util = require( 'util' )

let has_alerted_user_no_home = false

const { dialog } = require( 'electron' )
const alert = ( message ) => dialog.showMessageBox( { message } )
const confirm = ( message ) => dialog.showMessageBox( { message, buttons: [ "Confirm", "Cancel" ] } ).then( ( { response } ) => {
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
            alert( `No HOME variable set, this should never happen` )
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