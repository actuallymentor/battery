const { log } = require( "./helpers" )
const bake_logo = require( './logo' )
const { promises: fs } = require( 'fs' )
const { Resvg } = require( '@resvg/resvg-js' )

const export_directory = `${ __dirname }/../../app/assets`
const render_and_write_png = async ( svg_string, filename, size=1 ) => {

    const resvg = new Resvg( svg_string, {
        fitTo: {
            mode: 'zoom',
            value: Number( size )
        }
    } )
    const png_data = resvg.render()
    const png_buffer = png_data.asPng()
    return fs.writeFile( `${ export_directory }/${ filename }.png`, png_buffer )

}

module.exports = async function render_and_write_template_files() {

    log( `Starting render process` )

    const percentage_increment_to_render = 5
    const percentages_to_render = []

    // For supported DPis see https://www.electronjs.org/docs/latest/api/native-image#high-resolution-image
    const template_sizes_to_render = [ '1.25', '1.33', '1.4', '1.5', '1.8', '2', '2.5', '3', '4', '5' ]
    for ( let percentage = 0; percentage <= 100; percentage+=percentage_increment_to_render ) {
        percentages_to_render.push( percentage )
    }
    log( `Rendering percentages: `, percentages_to_render )

    log( `Generating SVG strings` )
    const svg_strings = percentages_to_render.map( percentage => {
        return [

            // active icons
            {
                postfix: '',
                percentage,
                prefix: 'active',
                svg_string: bake_logo( percentage, 1 )
            },
            ...template_sizes_to_render.map( size => ( {
                prefix: 'active',
                percentage,
                size,
                postfix: `@${ size }x`,
                svg_string: bake_logo( percentage, 1 )
            } ) ),

            // inactive icons
            {
                postfix: '',
                percentage,
                prefix: 'inactive',
                svg_string: bake_logo( percentage, .5 )
            },
            ...template_sizes_to_render.map( size => ( {
                prefix: 'inactive',
                percentage,
                size,
                postfix: `@${ size }x`,
                svg_string: bake_logo( percentage, .5 )
            } ) )

        ]
    } ).flat()

    log( `Generate ${ svg_strings.length } PNG images from svgs` )
    await Promise.all( svg_strings.map( ( { percentage, svg_string, prefix, postfix, size } ) => {
        return render_and_write_png( svg_string, `battery-${ prefix }-${ percentage }-Template${ postfix }`, size )
    } ) )

}