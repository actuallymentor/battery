const { promises: fs } = require( 'fs' )
const { HOME, XDG_CONFIG_HOME } = process.env
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
        if( XDG_CONFIG_HOME ) {
            await fs.mkdir( `${ XDG_CONFIG_HOME }/battery/`, { recursive: true } )
            await fs.appendFile( `${ XDG_CONFIG_HOME }/battery/gui.log`, `${ messages.join( '\n' ) }\n`, 'utf8' )
        } else if( HOME ) {
            await fs.mkdir( `${ HOME }/.battery/`, { recursive: true } )
            await fs.appendFile( `${ HOME }/.battery/gui.log`, `${ messages.join( '\n' ) }\n`, 'utf8' )
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