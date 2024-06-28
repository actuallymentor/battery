// const { eslint_config } = require( './index.cjs' )
const { eslint_config } = require( 'airier' )

// Export the default eslint config
module.exports = {
    ...eslint_config
}
