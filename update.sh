#!/bin/bash

# Force-set path to include sbin
PATH="$PATH:/usr/sbin"

# Set environment variables
tempfolder=~/.battery-tmp
binfolder=/usr/local/bin
batteryfolder="$tempfolder/battery"
mkdir -p $batteryfolder

echo -e "🔋 Starting battery update\n"

# Write battery function as executable

echo "[ 1 ] Downloading latest battery version"
rm -rf $batteryfolder
mkdir -p $batteryfolder
curl -sS -o $batteryfolder/battery.sh https://raw.githubusercontent.com/actuallymentor/battery/main/battery.sh

echo "[ 2 ] Writing script to $binfolder/battery"
cp $batteryfolder/battery.sh $binfolder/battery
chown $USER $binfolder/battery
chmod 755 $binfolder/battery
chmod u+x $binfolder/battery

# Remove tempfiles
cd
rm -rf $tempfolder
echo "[ 3 ] Removed temporary folder"

echo -e "\n🎉 Battery tool updated.\n"
