const { promises: fs } = require( 'fs' )
const { HOME } = process.env
let has_alerted_user_no_home = false

const log = ( ...messages ) => {
    console.log( ...messages )
    if( HOME ) fs.appendFile( `${ HOME }/.battery/gui.log`, `${ messages.join( '\n' ) }\n`, 'utf8' )
    else if( !has_alerted_user_no_home ) {
        alert( `No HOME variable set` )
        has_alerted_user_no_home = true
    }
}

const { dialog } = require('electron')
const alert = ( message ) => dialog.showMessageBox( { message } )

module.exports = {
    log,
    alert
}