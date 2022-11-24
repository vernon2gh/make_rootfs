#!/bin/bash

ROOTFS_NAME=rootfs
ROOTFS_TYPE=ext4
OUTPUT=out
DOWNLOAD=$OUTPUT/download

mkdir -p overlay $DOWNLOAD
echo "This is overlay root directory." > overlay/README

function color_echo() {
	echo -e "\e[32m[make_rootfs] $1\e[0m"
}

color_echo "Install dependencies"
if [ ! `which expect` ]; then
	sudo apt install expect
fi

if [ ! `which arch-chroot` ]; then
	sudo apt install arch-install-scripts
fi

if [[ $1 = "arm64" && ! `which qemu-aarch64-static` ]]; then
	sudo apt install qemu-user-static
fi

if [[ $1 = "riscv64" && ! `which qemu-riscv64-static` ]]; then
	sudo apt install qemu-user-static
fi

color_echo "Get target architecture and URL"
case $1 in
	"x86_64" | "")
		TARGET="x86_64" ## default target
		URL=http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-amd64.tar.gz
		;;
	"arm64")
		TARGET=$1
		URL=http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-arm64.tar.gz
		;;
	"riscv64")
		TARGET=$1
		URL=http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-riscv64.tar.gz
		;;
	*)
		echo "Currently only x86_64, arm64 and riscv64 are supported."
		exit
		;;
esac

color_echo "Get mount location"
if [ -z $2 ]; then
	MOUNT_POINT=/mnt
else
	MOUNT_POINT=$2
	mkdir -p $MOUNT_POINT
fi

ROOTFS=$OUTPUT/${ROOTFS_NAME}.${ROOTFS_TYPE}
ROOTFS_TARGET_TYPE=$OUTPUT/${ROOTFS_NAME}_${TARGET}.${ROOTFS_TYPE}
UBUNTU_BASE_PACKAGE=`basename $URL`

if [ ! -e $DOWNLOAD/$UBUNTU_BASE_PACKAGE ]; then
	color_echo "Download ubuntu base package"
	wget $URL -P $DOWNLOAD
fi

if [ ! -e $ROOTFS_TARGET_TYPE ]; then
	color_echo "Make root file system image"
	dd if=/dev/zero of=$ROOTFS_TARGET_TYPE bs=1G count=1
	mkfs.$ROOTFS_TYPE $ROOTFS_TARGET_TYPE
	sudo mount $ROOTFS_TARGET_TYPE $MOUNT_POINT

	color_echo "Decompression ubuntu base package"
	sudo tar -zxvf $DOWNLOAD/$UBUNTU_BASE_PACKAGE -C $MOUNT_POINT

	color_echo "Default setting"
	sudo /usr/bin/expect ./default_setting $MOUNT_POINT

	touch ./install_software
else
	sudo mount $ROOTFS_TARGET_TYPE $MOUNT_POINT
fi

color_echo "Install software by apt"
now_timestamp=`date +%s`
file_timestamp=`stat -c %Y ./install_software`
interval_timestamp=$[$now_timestamp - $file_timestamp]

if [ $interval_timestamp -lt 180 ]; then ## 3 minutes
	sudo /usr/bin/expect ./install_software $MOUNT_POINT
fi

color_echo "Install software by overlay"
sudo cp -r overlay/* $MOUNT_POINT

sudo umount $MOUNT_POINT

ln -sf `pwd`/$ROOTFS_TARGET_TYPE $ROOTFS
