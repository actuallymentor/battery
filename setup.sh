#!/bin/bash

# User welcome message
echo -e "\n####################################################################"
echo '# 👋 Welcome, this is the setup script for the battery CLI tool.'
echo -e "# Note: this script will ask for your password once or multiple times."
echo -e "####################################################################\n\n"

# Ask for sudo once, in most systems this will cache the permissions for a bit
sudo echo "[ 1/8 ] Superuser permissions acquired."

# Get smc source and build it
tempfolder=~/.battery-tmp
binfolder=/usr/local/bin
mkdir -p $tempfolder

smcfolder="$tempfolder/smc"
echo "[ 2/8 ] Cloning fan control version of smc"
git clone --depth 1 https://github.com/hholtmann/smcFanControl.git $smcfolder &> /dev/null
cd $smcfolder/smc-command
echo "[ 3/8 ] Building smc from source"
make &> /dev/null

# Move built file to bin folder
echo "[ 4/8 ] Move smc to executable folder"
sudo mkdir -p $binfolder
sudo mv $smcfolder/smc-command/smc $binfolder
sudo chmod u+x $binfolder/smc

# Write battery function as executable
bateryfolder="$tempfolder/battery"
echo "[ 5/8 ] Cloning battery repository"
git clone --depth 1 https://github.com/actuallymentor/battery.git $bateryfolder &> /dev/null
echo "[ 6/8 ] Writing script to $binfolder/battery"
sudo cp $bateryfolder/battery.sh $binfolder/battery
sudo chmod 755 $binfolder/battery
sudo chmod u+x $binfolder/battery

# Remove tempfiles
cd ../..
echo "[ 7/8 ] Removing temp folder $tempfolder"
rm -rf $tempfolder
echo "[ 8/8 ] Removed temporary build files"

echo -e "\n🎉 Battery tool installed. Type \"battery\" for instructions.\n"
