#!/bin/bash

ARCH="x86_64"    ## default target
SOFTWARE=''      ##
MOUNT_POINT=/mnt ## default the mount point for the root filesystem
QCOW2="false"

ROOTDIR=`dirname $0`
OVERLAY=$ROOTDIR/overlay
OUTPUT=$ROOTDIR/out
DOWNLOAD=$OUTPUT/download
DEFAULT_SETTING=default_setting

mkdir -p $OVERLAY $OUTPUT $DOWNLOAD share

function color_echo() {
	echo -e "\e[32m[make_rootfs] $1\e[0m"
}

## Parsing parameters
SHORTOPTS="a:,i:,m:,q,h"
LONGOPTS="arch:,install:,mount:,qcow2,help"
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
	-q|--qcow2)
		QCOW2="true"
		shift
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
		echo "-q, --qcow2                      Specifies create the root filesystem from qcow2 image"
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

if [ -f /etc/debian_version ]; then
	PACKAGE_MANAGER=apt
elif [ -f /etc/redhat-release ] || [ -f /etc/fedora-release ]; then
	PACKAGE_MANAGER=dnf
	if [ $QCOW2 = "false" ]; then
		echo "Please use the --qcow2 option."
		exit
	fi
else
	echo "Not supported by current Linux distributions."
	exit
fi

function rootfs_only()
{
	color_echo "Get ubuntu-base URL"
	VERSION=24.04.2
	URL=https://cdimage.ubuntu.com/ubuntu-base/releases/${VERSION}/release/ubuntu-base-${VERSION}-base-${ARCH}.tar.gz

	ROOTFS_NAME=rootfs
	ROOTFS_TYPE=ext4
	ROOTFS=$OUTPUT/${ROOTFS_NAME}.${ROOTFS_TYPE}
	ROOTFS_TARGET_TYPE=$OUTPUT/${ROOTFS_NAME}_${ARCH}.${ROOTFS_TYPE}
	UBUNTU_BASE_PACKAGE=`basename $URL`

	if [ ! -e $DOWNLOAD/$UBUNTU_BASE_PACKAGE ]; then
		color_echo "Download ubuntu base package"
		wget $URL -P $DOWNLOAD
	fi

	if [ ! -e $ROOTFS_TARGET_TYPE ]; then
		color_echo "Make root file system image"
		dd if=/dev/zero of=$ROOTFS_TARGET_TYPE bs=1G count=10
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
	if [ ! -z $(find $OVERLAY -mindepth 1 -maxdepth 1) ]; then
		sudo cp -r $OVERLAY/* $MOUNT_POINT
	fi

	sudo umount $MOUNT_POINT

	ln -sf `pwd`/$ROOTFS_TARGET_TYPE $ROOTFS
}

function rootfs_qcow2()
{
	color_echo "Get ubuntu-base qcow2 URL"
	VERSION=24.04
	URL=https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-${VERSION}-server-cloudimg-${ARCH}.img

	ROOTFS_NAME=ubuntu
	ROOTFS_TYPE=qcow2
	ROOTFS=$OUTPUT/${ROOTFS_NAME}.${ROOTFS_TYPE}
	ROOTFS_TARGET_TYPE=$OUTPUT/${ROOTFS_NAME}_${ARCH}.${ROOTFS_TYPE}
	UBUNTU_BASE_PACKAGE=`basename $URL`

	if [ ! -e $DOWNLOAD/$UBUNTU_BASE_PACKAGE ]; then
		color_echo "Download ubuntu base qcow2 package"
		wget $URL -P $DOWNLOAD
	fi

	if [ ! -e $ROOTFS_TARGET_TYPE ]; then
		cp $DOWNLOAD/$UBUNTU_BASE_PACKAGE $ROOTFS_TARGET_TYPE

		qemu-img resize $ROOTFS_TARGET_TYPE +10G
		virt-customize -a $ROOTFS_TARGET_TYPE				\
			--root-password password:root				\
			--run-command "growpart /dev/sda 1"			\
			--run-command "resize2fs /dev/sda1"			\
			--run-command "apt update"				\
			--upload $DEFAULT_SETTING:/root/$DEFAULT_SETTING	\
			--run-command "chmod +x /root/$DEFAULT_SETTING"		\
			--run-command "/root/$DEFAULT_SETTING"			\
			--delete /root/$DEFAULT_SETTING
	fi

	color_echo "Install software by apt"
	if [ ! -z "$SOFTWARE" ]; then
		virt-customize -a $ROOTFS_TARGET_TYPE --run-command "apt install -y $SOFTWARE"
	fi

	color_echo "Install software by overlay"
	if [ ! -z $(find $OVERLAY -mindepth 1 -maxdepth 1) ]; then
		tar -zcf $OVERLAY.tar.gz -C $OVERLAY .
		virt-customize -a $ROOTFS_TARGET_TYPE			\
			--upload $OVERLAY.tar.gz:/overlay.tar.gz	\
			--run-command "tar -zxf /overlay.tar.gz -C /"	\
			--delete /overlay.tar.gz
		rm -fr $OVERLAY.tar.gz
	fi

	color_echo "Generate initramfs image"
	KV=$(find $OVERLAY/lib/modules -maxdepth 1 -mindepth 1 -type d -printf '%f\n')
	if [ ! -z "$KV" ]; then
		sudo dracut -f -k $OVERLAY/lib/modules/$KV out/initramfs.img $KV
		rm -fr $OVERLAY/lib/modules/$KV
	fi

	ln -sf `pwd`/$ROOTFS_TARGET_TYPE $ROOTFS
}

if [ $QCOW2 = "true" ]; then
	color_echo "Install dependencies"
	if [ ! `which qemu-img` ]; then
		sudo $PACKAGE_MANAGER install qemu-img
	fi

	if [ ! `which virt-customize` ]; then
		sudo $PACKAGE_MANAGER install guestfs-tools
	fi

	if [ ! `which dracut` ]; then
		sudo $PACKAGE_MANAGER install dracut
	fi

	rootfs_qcow2
else
	color_echo "Install dependencies"
	if [ ! `which arch-chroot` ]; then
		sudo $PACKAGE_MANAGER install arch-install-scripts
	fi

	if [ ! `which samba` ]; then
		sudo $PACKAGE_MANAGER install samba
	fi

	if [[ $ARCH = "arm64" && ! `which qemu-aarch64-static` ]]; then
		sudo $PACKAGE_MANAGER install qemu-user-static
	fi

	if [[ $ARCH = "riscv64" && ! `which qemu-riscv64-static` ]]; then
		sudo $PACKAGE_MANAGER install qemu-user-static
	fi

	rootfs_only
fi
