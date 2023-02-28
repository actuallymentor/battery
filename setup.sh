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
echo -e "[ 1 ] Superuser permissions acquired."

batteryfolder="$tempfolder/battery"
echo "[ 2 ] Downloading latest version of battery CLI"
rm -rf $batteryfolder
mkdir -p $batteryfolder
curl -sSL -o $batteryfolder/main.zip https://github.com/actuallymentor/battery/archive/refs/heads/main.zip
unzip $batteryfolder/main.zip -d $batteryfolder
cp -r $batteryfolder/battery-main/* $batteryfolder
rm $batteryfolder/main.zip

## ###############
## OLD APPROACH
## ###############
# # Get smc source and build it
# smcfolder="$tempfolder/smc"
# echo "[ 3/10 ] Cloning fan control version of smc"
# rm -rf $smcfolder
# git clone --depth 1 https://github.com/hholtmann/smcFanControl.git $smcfolder &> /dev/null
# cd $smcfolder/smc-command
# echo "[ 4/10 ] Building smc from source"
# make &> /dev/null

# Move built file to bin folder
echo "[ 3 ] Move smc to executable folder"
sudo mkdir -p $binfolder
sudo mv dist/smc $binfolder
sudo chmod u+x $binfolder/smc

echo "[ 4 ] Writing script to $binfolder/battery for user $calling_user"
sudo cp $batteryfolder/battery.sh $binfolder/battery

echo "[ 5 ] Setting correct file permissions"
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

echo "[ 6 ] Setting up visudo declarations"
sudo bash $batteryfolder/battery.sh visudo

# Remove tempfiles
cd ../..
echo "[ 7 ] Removing temp folder $tempfolder"
rm -rf $tempfolder

echo -e "\n🎉 Battery tool installed. Type \"battery help\" for instructions.\n"
