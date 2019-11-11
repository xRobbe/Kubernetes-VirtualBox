#!/usr/bin/env bash

# TODO: Move variables to separate file
VMNAME='KubeSlave01-OL7'
BASEDIR="E:/VM/${VMNAME}"
ISOPATH='C:/Users/Robin/Downloads/OL77.iso'
HONETWORK='VirtualBox Host-Only Ethernet Adapter'
#BNETWORK='Intel(R) Dual Band Wireless-AC 7260 #2'
BNETWORK='Intel(R) I211 Gigabit Network Connection'
VMUSER='kube'
VMPASSFILE='passwd.txt'
VMHOSTNAME='kube02.rodenhausen.dev'

# TODO: Ask if it should be deleted/Check if it exists
# Delete VM if it already exists
VBoxManage unregistervm --delete "${VMNAME}"

# Create storage
VBoxManage createmedium disk --filename "${BASEDIR}/${VMNAME}.vdi" --size 32768
# Create & Register VM
VBoxManage createvm --name "${VMNAME}" --ostype "Oracle_64" --register
# Add controller for storage
VBoxManage storagectl "${VMNAME}" --name "SATA Controller" --add sata --controller IntelAHCI
# Attach storage to controller
VBoxManage storageattach "${VMNAME}" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "${BASEDIR}/${VMNAME}.vdi"
# Add controller for disk
VBoxManage storagectl "${VMNAME}" --name "IDE Controller" --add ide
# Attach iso to controller
VBoxManage storageattach "${VMNAME}" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium "${ISOPATH}"

# Enable IO-APIC
VBoxManage modifyvm "${VMNAME}" --ioapic on
# Set boot order
VBoxManage modifyvm "${VMNAME}" --boot1 dvd --boot2 disk --boot3 none --boot4 none
# Set memory
VBoxManage modifyvm "${VMNAME}" --memory 4096 
# Set video memory
VBoxManage modifyvm "${VMNAME}" --vram 128
# Enable page fusion
VBoxManage modifyvm "${VMNAME}" --pagefusion on
# Set number ob CPUs
VBoxManage modifyvm "${VMNAME}" --cpus 2
# Enable PAE/NX
VBoxManage modifyvm "${VMNAME}" --pae on
# Enable nested paging
VBoxManage modifyvm "${VMNAME}" --nestedpaging on
# Set BIOS, EFI does not support unattended install
VBoxManage modifyvm "${VMNAME}" --firmware bios
# Disable audio
VBoxManage modifyvm "${VMNAME}" --audio none
# Use UTC system clock
VBoxManage modifyvm "${VMNAME}" --rtcuseutc on

# Create host only interface
VBoxManage modifyvm "${VMNAME}" --nic1 hostonly --nictype1 82540EM --hostonlyadapter1 "${HONETWORK}" --cableconnected1 on
# Create brdige adapter
VBoxManage modifyvm "${VMNAME}" --nic2 bridged --nictype2 82540EM --bridgeadapter2 "${BNETWORK}" --cableconnected2 on

# Configure unattended installation
VBoxManage unattended install "${VMNAME}" --iso "${ISOPATH}" --user "${VMUSER}" --full-user-name "${VMUSER}" --password-file "${VMPASSFILE}" \
	--install-additions --locale 'en_US' --country 'DE' --time-zone 'CET' --hostname "${VMHOSTNAME}" --package-selection-adjustment minimal

# Start VM
VBoxManage startvm "${VMNAME}" --type headless

# Wait until installation is done
until VBoxManage guestcontrol "${VMNAME}" run --username root --passwordfile "${VMPASSFILE}" --verbose /usr/bin/bash -- -c "exit 0"; do
	echo "Waiting for installation"
	sleep 10
done

# Set german keyboard layout
VBoxManage guestcontrol "${VMNAME}" run --username root --passwordfile "${VMPASSFILE}" -- /usr/bin/localectl set-keymap de
# Enable hostonly network interface
VBoxManage guestcontrol "${VMNAME}" run --username root --passwordfile "${VMPASSFILE}" -- /sbin/ifup enp0s3
# Enable bridge network interface
VBoxManage guestcontrol "${VMNAME}" run --username root --passwordfile "${VMPASSFILE}" -- /sbin/ifup enp0s8

sleep 30

# Get hostonly IP
VMIP=$(VBoxManage guestproperty get "${VMNAME}" "/VirtualBox/GuestInfo/Net/0/V4/IP" | awk '{ print $2 }')

# Generate new SSH key
# yes y | ssh-keygen -t rsa -N '' -f vm.key
VBoxManage guestcontrol "${VMNAME}" run --username root --passwordfile "${VMPASSFILE}" -- /usr/bin/mkdir -p /root/.ssh/
sshpass -f passwd.txt scp vm.key.pub root@${VMIP}:/root/.ssh/authorized_keys

# Update packages
ssh root@${VMIP} -i vm.key -o "StrictHostKeyChecking no" yum update -y
# Install Docker
ssh root@${VMIP} -i vm.key -o "StrictHostKeyChecking no" <<EOF
yum-config-manager --enable ol7_optional_latest
yum-config-manager --enable ol7_addons

yum install -y docker-engine
systemctl enable --now docker
EOF

# Install Kubernetes
ssh root@${VMIP} -i vm.key -o "StrictHostKeyChecking no" <<EOF
cat <<EOF2 > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF2

setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

cat <<EOF2 >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF2
sysctl --system
EOF

# Prepare Kubernetes
ssh root@${VMIP} -i vm.key -o "StrictHostKeyChecking no" <<EOF 
yum install -y iproute-tc

cat > /etc/docker/daemon.json <<EOF2
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF2

systemctl daemon-reload
systemctl restart docker
swapoff -a
sed -ie '/swap/s/^/#/' /etc/fstab
EOF

# Network settings
ssh root@${VMIP} -i vm.key -o "StrictHostKeyChecking no" <<EOF 
sed -ie 's|ONBOOT=no|ONBOOT=yes|' /etc/sysconfig/network-scripts/ifcfg-enp0s3
sed -ie 's|BOOTPROTO=dhcp|BOOTPROTO=none|' /etc/sysconfig/network-scripts/ifcfg-enp0s3
echo "IPADDR=10.0.0.3" >> /etc/sysconfig/network-scripts/ifcfg-enp0s3
echo "NETMASK=255.255.255.0" >> /etc/sysconfig/network-scripts/ifcfg-enp0s3

sed -ie 's|ONBOOT=no|ONBOOT=yes|' /etc/sysconfig/network-scripts/ifcfg-enp0s8

echo "10.0.0.2 kube01 kube01.rodenhausen.dev" >> /etc/hosts
echo "10.0.0.3 kube02 kube02.rodenhausen.dev" >> /etc/hosts
echo "10.0.0.4 kube03 kube03.rodenhausen.dev" >> /etc/hosts

shutdown -r now 
EOF

# Wait for shutdown
sleep 60

# Wait until machine is back up
until VBoxManage guestcontrol "${VMNAME}" run --username root --passwordfile "${VMPASSFILE}" --verbose /usr/bin/bash -- -c "exit 0"; do
	echo "Waiting for reboot"
	sleep 10
done

# Wait some time to allow all services to start up
sleep 180

# Get IP again in case it changed
VMIP=$(VBoxManage guestproperty get "${VMNAME}" "/VirtualBox/GuestInfo/Net/0/V4/IP" | awk '{ print $2 }')

JOINCOMMAND=$(ssh -o "StrictHostKeyChecking no" -i vm.key root@10.0.0.2 kubeadm token create --print-join-command)
ssh -o "StrictHostKeyChecking no" -i vm.key root@10.0.0.3 ${JOINCOMMAND}

scp -r .kube root@10.0.0.3:/root/.kube

# Enable USB 1.1
## VBoxManage modifyvm "${VMNAME}" --usbohci on
# Enable USB 3.0
## VBoxManage modifyvm "${VMNAME}" --usbxhci on
# Eject disk
# VBoxManage storageattach "${VMNAME}" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium none