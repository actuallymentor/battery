// Import required modules
require('dotenv').config();
const { notarize } = require('@electron/notarize');

// Logging function for better readability
const log = (...messages) => console.log(...messages);

exports.default = async function notarizing(context) {
    log('\n\n🪝 afterSign hook triggered:');

    // Destructure necessary properties from context and environment variables
    const { appOutDir } = context;
    const { APPLEID, APPLEIDPASS, TEAMID } = process.env;

    // Ensure environment variables are set before proceeding
    if (!APPLEID || !APPLEIDPASS || !TEAMID) {
        log('Error: Missing environment variables. Please check APPLEID, APPLEIDPASS, and TEAMID.');
        throw new Error('Notarization failed due to missing environment variables.');
    }

    // Retrieve the app name
    const appName = context.packager.appInfo.productFilename;

    try {
        // Call notarize with the appropriate parameters
        await notarize({
            appBundleId: 'co.palokaj.battery',
            tool: 'notarytool',
            appPath: `${appOutDir}/${appName}.app`,
            appleId: APPLEID,
            appleIdPassword: APPLEIDPASS,
            teamId: TEAMID,
        });

        log('✅ Notarization completed successfully.');
    } catch (error) {
        log('❌ Notarization failed:', error);
        throw new Error('Notarization process encountered an error.');
    }
};
