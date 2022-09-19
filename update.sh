#!/bin/bash

# Set environment variables
tempfolder=~/.battery-tmp
binfolder=/usr/local/bin
bateryfolder="$tempfolder/battery"
mkdir -p $bateryfolder

echo -e "🔋 Starting battery update\n"

# Write battery function as executable

echo "[ 1/3 ] Cloning battery repository"
rm -rf $bateryfolder
git clone --depth 1 https://github.com/actuallymentor/battery.git $bateryfolder &> /dev/null
echo "[ 2/3 ] Writing script to $binfolder/battery"
cp $bateryfolder/battery.sh $binfolder/battery
chown $USER $binfolder/battery
chmod 755 $binfolder/battery
chmod u+x $binfolder/battery

# Remove tempfiles
cd
rm -rf $tempfolder
echo "[ 3/3 ] Removed temporary folder"

echo -e "\n🎉 Battery tool updated.\n"
