const { shell, app, Tray, Menu, powerMonitor, nativeTheme } = require('electron')
const { enable_battery_limiter, enable_battery_limiter_at, disable_battery_limiter, initialize_battery, is_limiter_enabled, get_battery_status, uninstall_battery } = require('./battery')
const { log } = require("./helpers")
const { get_logo_template } = require('./theme')
const { get_force_discharge_setting, update_force_discharge_setting, get_custom_percentage, set_custom_percentage } = require('./settings')

/* ///////////////////////////////
// Menu helpers
// /////////////////////////////*/
let tray = undefined

// Preset charge limit values available in the submenu
const charge_limit_presets = [60, 70, 75, 80, 90, 100]

// Set interface to usable
const generate_app_menu = async () => {

    try {
        // Get battery and daemon status
        const { battery_state, daemon_state, maintain_percentage = 80, percentage } = await get_battery_status()

        // Check if limiter is on
        const limiter_on = await is_limiter_enabled()

        // Check force discharge setting
        const allow_discharge = get_force_discharge_setting()

        // Get the user's custom charge limit percentage
        const custom_percent = get_custom_percentage()

        // Set tray icon
        log(`Generate app menu percentage: ${percentage} (discharge ${allow_discharge ? 'allowed' : 'disallowed'}, limited ${limiter_on ? 'on' : 'off'}, custom limit ${custom_percent}%)`)
        tray.setImage(get_logo_template(percentage, limiter_on))

        // Build the "Set charge limit" submenu with preset values
        const charge_limit_submenu = charge_limit_presets.map(preset => ({
            label: `${preset}%`,
            type: 'radio',
            checked: custom_percent === preset,
            click: async () => {
                set_custom_percentage(preset)
                // If the limiter is currently on, restart it with the new percentage
                if (limiter_on) await restart_limiter_at(preset)
                await refresh_tray()
            }
        }))

        // Build menu
        return Menu.buildFromTemplate([

            {
                label: `Enable battery limit at ${custom_percent}%`,
                type: 'radio',
                checked: limiter_on,
                click: enable_limiter
            },
            {
                label: `Disable battery limit`,
                type: 'radio',
                checked: !limiter_on,
                click: disable_limiter
            },
            {
                type: 'separator'
            },
            {
                label: `Set charge limit`,
                submenu: charge_limit_submenu
            },
            {
                type: 'separator'
            },
            {
                label: `Battery: ${battery_state}`,
                enabled: false
            },
            {
                label: `Power: ${daemon_state}`,
                enabled: false
            },
            {
                type: 'separator'
            },
            {
                label: `Advanced settings`,
                submenu: [
                    {
                        label: `Allow force-discharging`,
                        type: 'checkbox',
                        checked: allow_discharge,
                        click: async () => {
                            const success = await update_force_discharge_setting()
                            if (limiter_on && success) await restart_limiter()
                        }
                    }
                ]
            },
            {
                label: `About v${app.getVersion()}`,
                submenu: [
                    {
                        label: `Check for updates`,
                        click: () => shell.openExternal(`https://github.com/actuallymentor/battery/releases`)
                    },
                    {
                        type: 'normal',
                        label: `Uninstall Battery ${app.getVersion()}`,
                        click: async () => {
                            const uninstalled = await uninstall_battery()
                            if (!uninstalled) return
                            tray.destroy()
                            app.quit()
                        }
                    },
                    {
                        type: 'separator'
                    },
                    {
                        label: `User manual`,
                        click: () => shell.openExternal(`https://github.com/actuallymentor/battery#readme`)
                    },
                    {
                        type: 'normal',
                        label: 'Command-line usage',
                        click: () => shell.openExternal(`https://github.com/actuallymentor/battery#-command-line-version`)
                    },
                    {
                        type: 'normal',
                        label: 'Help and feature requests',
                        click: () => shell.openExternal(`https://github.com/actuallymentor/battery/issues`)
                    }
                ]
            },
            {
                label: 'Quit',
                click: () => {
                    tray.destroy()
                    app.quit()
                }
            }

        ])
    } catch (e) {
        log(`Error generating menu: `, e)
    }

}

// Periodic refreshing of icon and state
let refresh_timer = undefined
const set_interface_update_timer = async (disable_only = false) => {

    if (!disable_only) log(`Refreshing interface update timer`)
    else log(`Disabling interface update timer due to disable_only set to `, disable_only)

    // Calculate update speed
    const { maintain_percentage = 80, percentage, charging } = await get_battery_status()
    const percentage_delta = Math.floor(Math.abs(percentage - maintain_percentage))
    const slow_refresh_interval_in_ms = 1000 * 60 * 10
    const fast_refresh_interval_in_ms = 1000 * 60 * .5
    const battery_full_and_charging = charging && percentage == 100
    const refresh_speed = percentage_delta < 5 || powerMonitor.onBatteryPower || battery_full_and_charging ? slow_refresh_interval_in_ms : fast_refresh_interval_in_ms
    log(`Setting interface refresh speed to ${refresh_speed / 1000 / 60} minutes`)
    if (refresh_timer) clearInterval(refresh_timer)
    // eslint-disable-next-line no-use-before-define
    if (!disable_only) refresh_timer = setInterval(refresh_tray, refresh_speed)

}

// Refresh tray with battery status values
const refresh_tray = async (force_interactive_refresh = false) => {

    log("Refreshing tray icon...")
    const new_menu = await generate_app_menu()
    if (force_interactive_refresh) {
        log(`Forcing interactive refresh ${force_interactive_refresh}`)
        tray.closeContextMenu()
        tray.popUpContextMenu(new_menu)
    }
    tray.setContextMenu(new_menu)

    // Refresh timer 
    log(`Resetting interface timer speed`)
    set_interface_update_timer()

}

// Refresh app logo
const refresh_logo = async (percent = 80, force) => {

    log(`Refresh logo for percentage ${percent}, force ${force}`)
    if (force == 'active') return tray.setImage(get_logo_template(percent, true))
    if (force == 'inactive') return tray.setImage(get_logo_template(percent, false))

    const is_enabled = await is_limiter_enabled()
    return tray.setImage(get_logo_template(percent, is_enabled))
}


/* ///////////////////////////////
// Initialisation
// /////////////////////////////*/
async function set_initial_interface() {

    log("Starting tray app")
    tray = new Tray(get_logo_template(100, true))

    // Set "loading" context
    tray.setTitle('  updating...')

    log("Tray app boot complete")

    log("Triggering boot-time auto-update")
    await initialize_battery()
    log("App initialisation process complete")

    // Start battery handler
    await enable_battery_limiter()

    // Set tray styles
    tray.setTitle('')
    await refresh_tray()

    // Set tray open listener
    tray.on('mouse-enter', () => refresh_tray())
    tray.on('click', () => refresh_tray())
    nativeTheme.on('updated', () => refresh_tray())

    // Set refresh timer for the battery icon
    set_interface_update_timer()
    powerMonitor.on('lock-screen', () => set_interface_update_timer(true))
    powerMonitor.on('unlock-screen', () => set_interface_update_timer())
    powerMonitor.on('suspend', () => set_interface_update_timer(true))
    powerMonitor.on('resume', () => set_interface_update_timer())

}

/* ///////////////////////////////
// User interactions
// /////////////////////////////*/
async function enable_limiter() {

    try {
        const custom_percent = get_custom_percentage()
        log(`Enable limiter at ${custom_percent}%`)
        await refresh_logo(custom_percent, 'active')
        const percent_left = await enable_battery_limiter_at(custom_percent)
        log(`Interface enabled limiter at ${custom_percent}%, percentage remaining: ${percent_left}`)
        await refresh_logo(percent_left, 'active')
        await refresh_tray()
    } catch (e) {
        log(`Error in enable_limiter: `, e)
    }

}

async function disable_limiter() {

    try {
        log('Disable limiter')
        await refresh_logo(80, 'inactive')
        const percent_left = await disable_battery_limiter()
        log(`Interface disabled limiter, percentage remaining: ${percent_left}`)
        await refresh_logo(percent_left, 'inactive')
        await refresh_tray()
    } catch (e) {
        log(`Error in disable_limiter: `, e)
    }

}

async function restart_limiter() {

    try {
        log('Restart limiter')
        const custom_percent = get_custom_percentage()
        const percent_left = await disable_battery_limiter()
        await enable_battery_limiter_at(custom_percent)
        await refresh_logo(percent_left, 'active')
        await refresh_tray()
    } catch (e) {
        log(`Error in restart_limiter: `, e)
    }

}

async function restart_limiter_at(percent) {

    try {
        log(`Restart limiter at ${percent}%`)
        await disable_battery_limiter()
        const percent_left = await enable_battery_limiter_at(percent)
        await refresh_logo(percent_left, 'active')
        await refresh_tray()
    } catch (e) {
        log(`Error in restart_limiter_at: `, e)
    }

}


module.exports = {
    set_initial_interface
}