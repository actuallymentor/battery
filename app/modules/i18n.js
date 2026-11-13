// Localization support
// The UI language follows the system language, with English as fallback.
// Add a new language by adding a locale file in ./locales and registering it below.
const { app } = require( 'electron' )
const locales = {
    'en': require( './locales/en.json' ),
    'zh-CN': require( './locales/zh-CN.json' )
}

const get_locale = () => {
    // An explicit locale always wins, e.g. BATTERY_LOCALE=zh-CN
    const requested = process.env.BATTERY_LOCALE
    if( requested && locales[ requested ] ) return requested

    const system_locale = ( app.getLocale() || 'en' ).replace( '_', '-' )
    const parts = system_locale.split( '-' )
    const language = parts[0].toLowerCase()
    const script = parts.find( part => part.length === 4 )
    const region = parts.slice( 1 ).find( part => part.length === 2 || part.length === 3 )

    // macOS reports simplified Chinese as zh-Hans-CN, so map the script to the matching locale
    const candidates = []
    if( language === 'zh' ) {
        if( script?.toLowerCase() === 'hant' ) candidates.push( 'zh-TW' )
        else if( [ 'tw', 'hk', 'mo' ].includes( region?.toLowerCase() ) ) candidates.push( 'zh-TW' )
        else candidates.push( 'zh-CN' )
    } else {
        if( region ) candidates.push( `${ language }-${ region.toLowerCase() }` )
    }
    candidates.push( language )

    return candidates.find( candidate => locales[ candidate ] ) || 'en'
}

let current_locale = undefined

const set_locale = () => {
    current_locale = get_locale()
    return current_locale
}

const lookup = ( object, key ) => key.split( '.' ).reduce( ( value, part ) => value?.[ part ], object )

// Translate a key, e.g. t( 'menu.quit' ) or t( 'menu.battery', { state: '50%' } )
// Falls back to English, and to the key itself when a translation is missing.
const t = ( key, params = {} ) => {
    if( !current_locale ) set_locale()
    const template = lookup( locales[ current_locale ], key ) ?? lookup( locales['en'], key ) ?? key
    return template.replace( /\{(\w+)\}/g, ( match, name ) => params[ name ] ?? match )
}

module.exports = {
    t,
    set_locale,
    get_locale
}
