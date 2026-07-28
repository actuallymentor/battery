const { app } = require( 'electron' )
const { alert, log } = require( './modules/helpers' )
const { set_initial_interface } = require( './modules/interface' )
const { hide_dock } = require( './modules/app-visibility' )

// Enable auto-updates
require( 'update-electron-app' )( {
    logger: {
        log: ( ...data ) => log( `[ update-electron-app ] `, ...data )
    }
} )

/* ///////////////////////////////
// Event listeners
// /////////////////////////////*/

app.whenReady().then( async () => {

    // LSUIElement handles packaged builds; this remains as a runtime fallback.
    hide_dock( app )
    await set_initial_interface()

} )

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
