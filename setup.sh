# Get smc source and build it
tempfolder=tmp
binfolder=/usr/local/bin
echo -e "\nCloning fam control version of smc"
git clone https://github.com/hholtmann/smcFanControl.git $tempfolder
cd $tempfolder/smc-command
echo -e "\nMaking smc from source"
make

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


# Battery management function
function battery() {

	helpmessage="
Battery CLI utility. Usage: 

  battery charging on/off
    on: sets CH0B to 00 (allow charging)
    off: sets CH0B to 02 (disallow charging)

  visudo: log out the contents for a Visudo file you can use to make sure this command doesn't need your sudo password every time.

"

	visudoconfig="
# Put this in /private/etc/sudoers.d/mentor_zshrc on a mac
# with sudo visudo /private/etc/sudoers.d/battery

Cmnd_Alias      BATTERYOFF = $binfolder/smc -k CH0B -w 02
Cmnd_Alias      BATTERYON = $binfolder/smc -k CH0B -w 00
$( whoami ) ALL = NOPASSWD: BATTERYOFF
$( whoami ) ALL = NOPASSWD: BATTERYON
"

	action=$1
	setting=$2

	if [ -z "$action" ]; then
		echo -e $helpmessage
	fi

	if [[ "$action" == "visudo" ]]; then
		echo $visudoconfig
	fi
	

	# Charging on/off controller
	if [[ "$action" == "charging" ]]; then

		echo "Setting $action to $setting"
		
		# Set charging to on and off
		if [[ "$setting" == "on" ]]; then
			echo "Enabling battery charging"
			sudo smc -k CH0B -w 00
		elif [[ "$setting" == "off" ]]; then
			echo "Disabling battery charging"
			sudo smc -k CH0B -w 02
		fi

	fi

}

# Write battery function as executable
script="
#!/bin/bash
$( declare -f battery )
"
echo "Writing script to $binfolder/battery"
echo $script
echo $script > battery
sudo mv battery $binfolder
sudo chmod u+x $binfolder/battery

echo -e "\nBattery tool installed. Type \"battery\" for instructions."
