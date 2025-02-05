#!/bin/bash

apt-get update
apt-get upgrade -y --only-upgrade
# Check if a reboot is required
if [ -f /var/run/reboot-required ]; then
		echo "Reboot is required."
		reboot
fi
