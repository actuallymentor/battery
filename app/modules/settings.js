const Store = require('electron-store')
const { app } = require('electron')
const { log, confirm } = require('./helpers')
const store = new Store({
    force_discharge_if_needed: {
        type: 'boolean'
    },
    launch_at_login: {
        type: 'boolean'
    }
})

const get_force_discharge_setting = () => {
    // Check if force discharge is on
    const force_discharge_if_needed = store.get('force_discharge_if_needed')
    log(`Force discharge setting: ${typeof force_discharge_if_needed} ${force_discharge_if_needed}`)
    return force_discharge_if_needed === true
}

const toggle_force_discharge = () => {
    const status = get_force_discharge_setting()
    log(`Setting force discharge to ${!status}`)
    store.set('force_discharge_if_needed', !status)
}

// Update the force discharge setting
const update_force_discharge_setting = async () => {

    try {

        const currently_allowed = get_force_discharge_setting()
        if (!currently_allowed) {
            const proceed = await confirm(`This setting allows your battery to drain to the desired maintenance level while plugged in. This does not work well in Clamshell mode (laptop closed with an external monitor).\n\nAllow force-discharging?`)
            if (!proceed) return false
        }

        // Toggle setting and refresh tray
        toggle_force_discharge()
        return true


    } catch (e) {
        log(`Error updating force discharge: `, e)
    }

}

const get_launch_at_login_setting = () => {
    const launch_at_login = store.get('launch_at_login')
    log(`Launch at login setting: ${typeof launch_at_login} ${launch_at_login}`)
    return launch_at_login === true
}

const set_login_item_settings = (openAtLogin) => {
    let appPath = process.execPath
    if (process.platform === 'darwin' && appPath.includes('.app/Contents/MacOS/')) {
        appPath = appPath.substring(0, appPath.indexOf('.app/') + 5) + 'app'
    }

    const loginItemSettings = {
        openAtLogin,
        openAsHidden: false,
        name: app.getName(),
        path: appPath
    }

    app.setLoginItemSettings(loginItemSettings)
}

const update_launch_at_login_setting = async () => {
    try {
        const currently_enabled = get_launch_at_login_setting()
        const new_setting = !currently_enabled

        log(`Setting launch at login to ${new_setting}`)
        store.set('launch_at_login', new_setting)

        set_login_item_settings(new_setting)

        return true
    } catch (e) {
        log(`Error updating launch at login: `, e)
        return false
    }
}

const apply_launch_at_login_setting = () => {
    try {
        const launch_at_login = get_launch_at_login_setting()
        log(`Applying launch at login setting: ${launch_at_login}`)

        set_login_item_settings(launch_at_login)
    } catch (e) {
        log(`Error applying launch at login: `, e)
    }
}

module.exports = {
    get_force_discharge_setting,
    toggle_force_discharge,
    update_force_discharge_setting,
    get_launch_at_login_setting,
    update_launch_at_login_setting,
    apply_launch_at_login_setting
}