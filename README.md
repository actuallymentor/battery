# Battery charging manager

CLI for managing the battery charging status for M1 Macs. Can be used to enable/disable the Macbook from charging the battery when plugged into power.

The idea is to make it possible to keep a chronically plugged in Macbook at for example `80%` battery, since that will prolong the longevity of the battery.

Example usage:

```shell
# This will enable charging when your battery dips under 80, and disable it when it exceeds 80
battery maintain 80
```

After running a command like `battery charging off` you can verify the change visually by looking at the battery icon:

![Battery not charging](./screenshots/not-charging-screenshot.png)

After running `battery charging on` you will see it change to this:

![Battery charging](./screenshots/charging-screenshot.png)

## Installation

One-line installation:

```bash
curl -s https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash
````

This will:

1. Compile the `smc` tool from the [hholtmann/smcFanControl]( https://github.com/hholtmann/smcFanControl.git ) repository
2. Install `smc` to `/usr/local/bin`
3. Install `battery` to `/usr/local/bin`

## Usage

For help, run `battery` without parameters:

```
Battery CLI utility v0.0.5.

Usage:

  battery status
    output battery SMC status, % and time remaining

  battery maintain LEVEL[1-100]
    turn off charging above, and off below a certain value
    eg: battery maintain 80

  battery charging SETTING[on/off]
    manually set the battery to (not) charge
    eg: battery charging on

  battery charge LEVEL[1-100]
    charge the battery to a certain percentage, and disable charging when that percentage is reached
    eg: battery charge 90

  battery visudo
    instructions on how to make which utility exempt from sudo, highly recommended

  battery update
    update the battery utility to the latest version (reruns the installation script)

  battery uninstall
    enable charging and remove the smc tool and the battery script
```
