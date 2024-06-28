/* ///////////////////////////////
// Notarization
// See https://kilianvalkhof.com/2019/electron/notarizing-your-electron-application/
// /////////////////////////////*/
require( 'dotenv' ).config()
const { notarize } = require( '@electron/notarize' )
const log = ( ...messages ) => console.log( ...messages )

exports.default = async function notarizing( context ) {
    
    log( '\n\n🪝 afterSign hook triggered: ' )
    const { appOutDir } = context 
    const { APPLEID, APPLEIDPASS, TEAMID } = process.env
    const appName = context.packager.appInfo.productFilename

    return await notarize( {
        appBundleId: 'co.palokaj.battery',
        tool: "notarytool",
        appPath: `${ appOutDir }/${ appName }.app`,
        appleId: APPLEID,
        appleIdPassword: APPLEIDPASS,
        teamId: TEAMID
    } )
}