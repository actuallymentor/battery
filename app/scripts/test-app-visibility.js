const assert = require( 'node:assert/strict' )
const package_config = require( '../package.json' )
const { hide_dock } = require( '../modules/app-visibility' )

assert.equal(
    package_config.build?.mac?.extendInfo?.LSUIElement,
    true,
    'Packaged app must set LSUIElement so macOS treats it as menu-bar-only'
)

let hide_calls = 0
hide_dock( { dock: { hide: () => hide_calls++ } } )
assert.equal( hide_calls, 1, 'Runtime fallback must hide the Dock icon' )

assert.doesNotThrow( () => hide_dock( {} ), 'Non-macOS runtimes must be safe' )

console.log( 'app visibility tests passed' )
