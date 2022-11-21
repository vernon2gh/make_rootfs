#!/bin/bash

ROOTFS_NAME=rootfs
ROOTFS_TYPE=ext4
OUTPUT=out
CONFIG=$OUTPUT/.config
DOWNLOAD=$OUTPUT/download
UBUNTU_BASE_DIR=$OUTPUT/ubuntu_base

mkdir -p overlay $DOWNLOAD $UBUNTU_BASE_DIR
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

color_echo "Source default configure"
if [ ! -f $CONFIG ]; then
	echo "TARGET=" > $CONFIG
fi

source $CONFIG

color_echo "Get target architecture and URL"
case $1 in
	"x86_64" | "")
		TARGET_SET="x86_64" ## default target
		URL=http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-amd64.tar.gz
		;;
	"arm64")
		TARGET_SET=$1
		URL=http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-arm64.tar.gz
		;;
	"riscv64")
		TARGET_SET=$1
		URL=http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-riscv64.tar.gz
		;;
	*)
		echo "Currently only x86_64, arm64 and riscv64 are supported."
		exit
		;;
esac

if [ "$TARGET_SET" = "$TARGET" ]; then
	RECOVER="false"
else
	RECOVER="true"
	sed -i "s/^TARGET=.*/TARGET=$TARGET_SET/" $CONFIG
fi

TARGET=$TARGET_SET
ROOTFS=$OUTPUT/${ROOTFS_NAME}.${ROOTFS_TYPE}
ROOTFS_TARGET_TYPE=$OUTPUT/${ROOTFS_NAME}_${TARGET}.${ROOTFS_TYPE}
UBUNTU_BASE_PACKAGE=`basename $URL`

color_echo "Download ubuntu base package"
if [ ! -e $DOWNLOAD/$UBUNTU_BASE_PACKAGE ]; then
	wget $URL -P $DOWNLOAD
fi

if [ ! -e $ROOTFS_TARGET_TYPE ]; then
	color_echo "Decompression ubuntu base package"

	sudo rm -fr $UBUNTU_BASE_DIR/*
	tar -zxvf $DOWNLOAD/$UBUNTU_BASE_PACKAGE -C $UBUNTU_BASE_DIR

	touch ./install_software
elif [ $RECOVER = "true" ]; then
	color_echo "Recover ubuntu base package"

	sudo mount $ROOTFS_TARGET_TYPE /mnt
	sudo cp -r /mnt/* $UBUNTU_BASE_DIR
	sudo umount /mnt
fi

color_echo "Install software by apt"
now_timestamp=`date +%s`
file_timestamp=`stat -c %Y ./install_software`
interval_timestamp=$[$now_timestamp - $file_timestamp]

if [ $interval_timestamp -lt 180 ]; then ## 3 minutes
	sudo /usr/bin/expect ./install_software $UBUNTU_BASE_DIR
fi

color_echo "Install software by overlay"
cp overlay/* $UBUNTU_BASE_DIR

color_echo "Make root file system image"
ROOTFS_ZISE_MB=`sudo du -s -BM $UBUNTU_BASE_DIR | awk '{print $1}' | tr -cd "[0-9]"`

dd if=/dev/zero of=$ROOTFS_TARGET_TYPE bs=100M count=`echo "($ROOTFS_ZISE_MB + 200)/100" | bc`
mkfs.$ROOTFS_TYPE $ROOTFS_TARGET_TYPE
sudo mount $ROOTFS_TARGET_TYPE /mnt
sudo cp -r $UBUNTU_BASE_DIR/* /mnt
sudo umount /mnt

ln -sf `pwd`/$ROOTFS_TARGET_TYPE $ROOTFS
