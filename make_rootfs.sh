#!/bin/bash

ARCH="x86_64"    ## default target
SOFTWARE=' '     ##
MOUNT_POINT=/mnt ## default the mount point for the root filesystem

ROOTFS_NAME=rootfs
ROOTFS_TYPE=ext4
ROOTDIR=`dirname $0`
OVERLAY=$ROOTDIR/overlay
OUTPUT=$ROOTDIR/out
DOWNLOAD=$OUTPUT/download
DEFAULT_SETTING=default_setting

function color_echo() {
	echo -e "\e[32m[make_rootfs] $1\e[0m"
}

## Parsing parameters
SHORTOPTS="a:,i:,m:,h"
LONGOPTS="arch:,install:,mount:,help"
ARGS=$(getopt --options $SHORTOPTS	\
	--longoptions $LONGOPTS -- "$@" )

eval set -- "$ARGS"

while true;
do
	case $1 in
	-a|--arch)
		ARCH=$2
		shift 2
		;;
	-i|--install)
		SOFTWARE=$2
		shift 2
		;;
	-m|--mount)
		MOUNT_POINT=$2
		mkdir -p $MOUNT_POINT
		shift 2
		;;
	-h|--help)
		echo "Usage:"
		echo "$0 <options>"
		echo ""
		echo "make a simple root file system"
		echo ""
		echo "Options:"
		echo "-a, --arch x86_64/arm64/riscv64  Specify the architecture"
		echo "-i, --install 'software'         Specify the software to be install"
		echo "-m, --mount directory            Specifies the mount point for the root filesystem"
		echo "-h, --help                       Display this help"
		exit
		;;
	--)
		shift
		break
		;;
	esac
done

if [[ $ARCH != "x86_64" && $ARCH != "arm64" && $ARCH != "riscv64" ]]; then
	echo "Currently only x86_64, arm64 and riscv64 are supported."
	exit
fi

if [ $ARCH = "x86_64" ]; then
	ARCH=amd64
fi

color_echo "Install dependencies"
if [ ! `which arch-chroot` ]; then
	sudo apt install arch-install-scripts
fi

if [[ $ARCH = "arm64" && ! `which qemu-aarch64-static` ]]; then
	sudo apt install qemu-user-static
fi

if [[ $ARCH = "riscv64" && ! `which qemu-riscv64-static` ]]; then
	sudo apt install qemu-user-static
fi

color_echo "Get ubuntu-base URL"
VERSION=23.04
URL=https://cdimage.ubuntu.com/ubuntu-base/releases/${VERSION}/release/ubuntu-base-${VERSION}-base-${ARCH}.tar.gz

ROOTFS=$OUTPUT/${ROOTFS_NAME}.${ROOTFS_TYPE}
ROOTFS_TARGET_TYPE=$OUTPUT/${ROOTFS_NAME}_${ARCH}.${ROOTFS_TYPE}
UBUNTU_BASE_PACKAGE=`basename $URL`

mkdir -p $DOWNLOAD

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
	sudo cp $ROOTDIR/$DEFAULT_SETTING $MOUNT_POINT
	sudo arch-chroot $MOUNT_POINT /bin/bash /$DEFAULT_SETTING
	sudo rm -fr $MOUNT_POINT/$DEFAULT_SETTING
	sudo rm -fr $MOUNT_POINT/etc/resolv.conf
	sudo ln -s /run/systemd/resolve/resolv.conf $MOUNT_POINT/etc/resolv.conf
else
	sudo mount $ROOTFS_TARGET_TYPE $MOUNT_POINT
fi

color_echo "Install software by apt"
if [ ! -z "$SOFTWARE" ]; then
	sudo arch-chroot $MOUNT_POINT /bin/bash -c "apt install -y $SOFTWARE"
fi


color_echo "Install software by overlay"
mkdir -p $OVERLAY
echo "This is overlay root directory." > $OVERLAY/README
sudo cp -r $OVERLAY/* $MOUNT_POINT

sudo umount $MOUNT_POINT

ln -sf `pwd`/$ROOTFS_TARGET_TYPE $ROOTFS
