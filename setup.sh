#!/bin/bash

# Get smc source and build it
tempfolder=tmp
binfolder=/usr/local/bin

echo -e "\nCloning fan control version of smc"
git clone -–depth 1 https://github.com/hholtmann/smcFanControl.git $tempfolder
cd $tempfolder/smc-command
echo -e "\nMaking smc from source"
make &> /dev/null

# Move built file to bin folder
echo -e "\nMove smc to executable folder"
sudo mkdir -p $binfolder
sudo mv ./smc $binfolder
sudo chmod u+x $binfolder/smc

# Remove tempfiles
cd ../..
echo -e "\nRemoving temp folder $(pwd)/$tempfolder"
rm -rf $tempfolder
echo -e "\nSmc binary built"

# Write battery function as executable

echo "Writing script to $binfolder/battery"
sudo cp battery.sh $binfolder/battery
sudo chmod 755 $binfolder/battery
sudo chmod u+x $binfolder/battery

echo -e "\nBattery tool installed. Type \"battery\" for instructions."
