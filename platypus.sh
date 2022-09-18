#!/bin/sh
binfolder=/usr/local/bin

# Ask the user what we are doing
response=$( osascript -e \
    'tell app "System Events" to display dialog "🔋 Do you want to disable or enable the battery utility?\n\nEnable: maintain a battery percentage of 80%.\nDisable: charge your macbook as usual (to max 100%)." buttons {"Enable", "Disable"} default button 1'
)

# Install/update on application open
bash ./setup.sh "true"

# Run battery maintain at default percentage

if [[ "$response" == *"Enable"* ]]; then
    $binfolder/battery maintain 80 "true"
    echo "✅ Maintaining battery at 80%, you may quit this window safely"
else
    $binfolder/battery maintain stop "true"
    $binfolder/battery charging on
    echo "✅ Disabled battery utility, you may quit this window safely"
fi
