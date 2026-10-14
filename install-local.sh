#!/bin/bash
# Install this reviewed checkout, never download or execute upstream code.
set -e
PATH=/usr/bin:/bin:/usr/sbin:/sbin
[[ $# -eq 0 && $EUID -ne 0 ]] || { echo 'Run ./install-local.sh as your normal user, without arguments.' >&2; exit 1; }
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
binfolder=/usr/local/co.palokaj.battery
for file in battery.sh firmware.sh dist/smc; do
    [[ -f "$source_dir/$file" ]] || { echo "Missing local file: $file" >&2; exit 1; }
done
/bin/bash -n "$source_dir/battery.sh"
/bin/bash -n "$source_dir/firmware.sh"
[[ ! -L "$binfolder" ]] || { echo 'Refusing a symlink installation directory.' >&2; exit 1; }
sudo -v
sudo install -d -m 755 -o root -g wheel "$binfolder"
sudo install -m 755 -o root -g wheel "$source_dir/dist/smc" "$binfolder/smc"
sudo install -m 644 -o root -g wheel "$source_dir/firmware.sh" "$binfolder/firmware.sh"
sudo install -m 755 -o root -g wheel "$source_dir/battery.sh" "$binfolder/battery"
sudo mkdir -p /usr/local/bin
sudo ln -sf "$binfolder/battery" /usr/local/bin/battery
sudo ln -sf "$binfolder/smc" /usr/local/bin/smc
sudo "$binfolder/battery" visudo
printf '\nInstalled local firmware build. No charge policy was started.\n'
printf 'Quit the old GUI, then apply your target with: battery maintain N\n'
printf 'Inspect with: battery status, battery logs 100\n'
