const hide_dock = app => {

    if( app.dock && typeof app.dock.hide == 'function' ) app.dock.hide()

}

module.exports = {
    hide_dock
}
