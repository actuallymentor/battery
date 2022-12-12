#!/bin/bash

# User welcome message
echo -e "\n####################################################################"
echo '# 👋 Welcome, this is the setup script for the battery CLI tool.'
echo -e "# Note: this script will ask for your password once or multiple times."
echo -e "####################################################################\n\n"

# Set environment variables
tempfolder=~/.battery-tmp
binfolder=/usr/local/bin
mkdir -p $tempfolder

# Set script value
calling_user=${1:-"$USER"}
configfolder=/Users/$calling_user/.battery
pidfile=$configfolder/battery.pid
logfile=$configfolder/battery.log

# Ask for sudo once, in most systems this will cache the permissions for a bit
sudo echo "🔋 Starting battery installation"

echo -e "\n[ 1/9 ] Superuser permissions acquired."

# Get smc source and build it
smcfolder="$tempfolder/smc"
echo "[ 2/9 ] Cloning fan control version of smc"
rm -rf $smcfolder
git clone --depth 1 https://github.com/hholtmann/smcFanControl.git $smcfolder &> /dev/null
cd $smcfolder/smc-command
echo "[ 3/9 ] Building smc from source"
make &> /dev/null

# Move built file to bin folder
echo "[ 4/9 ] Move smc to executable folder"
sudo mkdir -p $binfolder
sudo mv $smcfolder/smc-command/smc $binfolder
sudo chmod u+x $binfolder/smc

# Write battery function as executable
batteryfolder="$tempfolder/battery"
echo "[ 5/9 ] Cloning battery repository"
git clone --depth 1 https://github.com/actuallymentor/battery.git $batteryfolder &> /dev/null

echo "[ 6/9 ] Writing script to $binfolder/battery for user $calling_user"
sudo cp $batteryfolder/battery.sh $binfolder/battery

# Set permissions for battery executables
sudo chown $calling_user $binfolder/battery
sudo chmod 755 $binfolder/battery
sudo chmod u+x $binfolder/battery

# Set permissions for logfiles
mkdir -p $configfolder
sudo chown $calling_user $configfolder

touch $logfile
sudo chown $calling_user $logfile
sudo chmod 755 $logfile

touch $pidfile
sudo chown $calling_user $pidfile
sudo chmod 755 $pidfile

sudo chown $calling_user $binfolder/battery

sudo bash $batteryfolder/battery.sh visudo
echo "[ 7/9 ] Set up visudo declarations"

# Remove tempfiles
cd ../..
echo "[ 8/9 ] Removing temp folder $tempfolder"
rm -rf $tempfolder
echo "[ 9/9 ] Removed temporary build files"

echo -e "\n🎉 Battery tool installed. Type \"battery help\" for instructions.\n"
