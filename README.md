# Battery charging manager

CLI for managing the battery charging status for M1 Macs. Can be used to enable/disable the Macbook from charging the battery when plugged into power.

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
Battery CLI utility. Usage: 

  battery charging on/off
    on: sets CH0B to 00 (allow charging)
    off: sets CH0B to 02 (disallow charging)

  visudo: log out the contents for a Visudo file you can use to make sure this command doesn't need your sudo password every time.

```
