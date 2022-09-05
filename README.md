# Battery charging manager

CLI for managing the battery charging status for M1 Macs. Can be used to enable/disable the Macbook from charging the battery when plugged into power.

The idea is to make it possible to keep a chronically plugged in Macbook at for example `80%` battery, since that will prolong the longevity of the battery.

After running `battery charging off` you can verify the change visually by looking at the battery icon:

![Battery not charging](./screenshots/not-charging-screenshot.png)

After running `battery charging on` you will see it change to this:

![Battery charging](./screenshots/charging-screenshot.png)

## Installation

One-line installation:

```bash
curl https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | sudo bash
````

This will:

1. Compile the `smc` tool from the [hholtmann/smcFanControl]( https://github.com/hholtmann/smcFanControl.git ) repository
2. Install `smc` to `/usr/local/bin`
3. Install `battery` to `/usr/local/bin`

## Usage

For help, run `battery` without parameters:

```
Battery CLI utility v0.0.4.

Usage:

  battery status
    output battery SMC status, % and time remaining

  battery charging SETTING
    on: sets CH0B to 00 (allow charging)
    off: sets CH0B to 02 (disallow charging)

  battery charge LEVEL
    LEVEL: percentage to charge to, charging is disabled when percentage is reached.

  battery maintain LEVEL
    LEVEL: percentage under which to charge, and above which to disable charging.

  battery visudo
    instructions on how to make which utility exempt from sudo

  battery update
    run the installation command again to pull latest version

  battery uninstall
    enable charging and remove the `smc` tool and the `battery` script

```
