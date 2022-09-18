#!/bin/sh
binfolder=/usr/local/bin

# Install/update on application open
bash ./setup.sh "true"

# Run battery maintain at default percentage
$binfolder/battery maintain 80 "true"
