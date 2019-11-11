#!/usr/bin/env bash

NETWORK='VirtualBox Host-Only Ethernet Adapter'

if VBoxManage list hostonlyifs | grep -ve 'VirtualBox Host-Only Ethernet Adapter #' | grep -qe '^Name:.*VirtualBox Host-Only Ethernet Adapter'; then
	echo "Interface already exists. Removing..."
    VBoxManage hostonlyif remove "${NETWORK}"
fi
echo "Creating Interface..."
VBoxManage hostonlyif create
VBoxManage hostonlyif ipconfig "${NETWORK}" --ip 10.0.0.1 --netmask 255.255.255.0

if VBoxManage list dhcpservers | grep -ve 'HostInterfaceNetworking-VirtualBox Host-Only Ethernet Adapter #' | grep -qe '^NetworkName:.*HostInterfaceNetworking-VirtualBox Host-Only Ethernet Adapter'; then 
	echo "DHCP server already exists. Removing..."
    VBoxManage dhcpserver remove --netname "HostInterfaceNetworking-${NETWORK}"
fi
echo "Creating DHCP server..."
VBoxManage dhcpserver add --netname "HostInterfaceNetworking-${NETWORK}" --ip 10.0.0.254 --netmask 255.255.255.0 --lowerip 10.0.0.10 --upperip 10.0.0.250 --enable
