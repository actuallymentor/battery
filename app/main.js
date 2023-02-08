const { app } = require( 'electron' )
const { alert } = require( './modules/helpers' )
const { set_initial_interface } = require( './modules/interface' )

// Enable auto-updates
require( 'update-electron-app' )()

/* ///////////////////////////////
// Event listeners
// /////////////////////////////*/

app.whenReady().then( set_initial_interface )

/* ///////////////////////////////
// Global config
// /////////////////////////////*/

// Hide dock entry
app.dock.hide()

/* ///////////////////////////////
// Debugging
// /////////////////////////////*/
const debug = false
if( debug ) app.whenReady().then( async () => {

    await alert( __dirname )

    await alert( Object.keys( process.env ).join( '\n' ) )

    const { HOME, PATH, USER } = process.env
    await alert( `HOME: ${ HOME }\n\nPATH: ${ PATH }\n\nUSER: ${ USER }` )

} )
