#!/bin/bash

ARCH="x86_64"    ## default target
SOFTWARE=''      ##
MOUNT_POINT=/mnt ## default the mount point for the root filesystem
GUEST="ubuntu"   ## default guest os
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
SHORTOPTS="a:,i:,m:,g:,q,h"
LONGOPTS="arch:,install:,mount:,guest:,qcow2,help"
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
	-g|--guest)
		GUEST=$2
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
		echo "-a, --arch x86_64/aarch64/riscv64  Specify the architecture"
		echo "-i, --install 'software'           Specify the software to be install"
		echo "-m, --mount directory              Specifies the mount point for the root filesystem"
		echo "-g, --guest ubuntu/fedora          Specifies the guest os for the root filesystem"
		echo "-q, --qcow2                        Specifies create the root filesystem from qcow2 image"
		echo "-h, --help                         Display this help"
		exit
		;;
	--)
		shift
		break
		;;
	esac
done

if [[ $ARCH != "x86_64" && $ARCH != "aarch64" && $ARCH != "riscv64" ]]; then
	echo "Currently only x86_64, aarch64 and riscv64 are supported."
	exit
fi

if [[ $ARCH = "riscv64" && $GUEST = "fedora" ]]; then
	echo "guest fedora is only x86_64 and aarch64 are supported."
	exit
fi

if [[ $QCOW2 = "false" && $GUEST != "ubuntu" ]]; then
	echo "make rootfs.ext4 only support ubuntu guest os."
	exit
fi

if [[ $QCOW2 = "true" && $ARCH != $(uname -m) ]]; then
	echo "For qcow2 image, ARCH must be consistent with the local architecture."
	exit
fi

if [ $ARCH = "x86_64" ]; then
	ARCH_ALIAS=amd64
elif [ $ARCH = "aarch64" ]; then
	ARCH_ALIAS=arm64
elif [ $ARCH = "riscv64" ]; then
	ARCH_ALIAS=riscv64
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
	URL=https://cdimage.ubuntu.com/ubuntu-base/releases/${VERSION}/release/ubuntu-base-${VERSION}-base-${ARCH_ALIAS}.tar.gz

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

function rootfs_qcow2_common()
{
	color_echo "Install software by overlay"
	if [ ! -z $(find $OVERLAY -mindepth 1 -maxdepth 1) ]; then
		virt-copy-in -a $ROOTFS_TARGET_TYPE $OVERLAY/* /
	fi

	color_echo "Generate initramfs image"
	KV=$(find $OVERLAY/lib/modules -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2> /dev/null)
	if [ ! -z "$KV" ]; then
		sudo dracut -f -k $OVERLAY/lib/modules/$KV out/$GUEST-initramfs.img $KV 2> /dev/null
	fi
}

function rootfs_qcow2_ubuntu()
{
	color_echo "Get ubuntu-base qcow2 URL"
	VERSION=24.04
	URL=https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-${VERSION}-server-cloudimg-${ARCH_ALIAS}.img

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
			--upload $DEFAULT_SETTING:/root/$DEFAULT_SETTING	\
			--run-command "chmod +x /root/$DEFAULT_SETTING"		\
			--run-command "/root/$DEFAULT_SETTING"			\
			--delete /root/$DEFAULT_SETTING
	fi

	color_echo "Install software by apt"
	if [ ! -z "$SOFTWARE" ]; then
		virt-customize -a $ROOTFS_TARGET_TYPE --run-command "apt install -y $SOFTWARE"
	fi

	rootfs_qcow2_common

	ln -sf `pwd`/$ROOTFS_TARGET_TYPE $ROOTFS
}

function rootfs_qcow2_fedora()
{
	color_echo "Get fedora-base qcow2 URL"
	VERSION=42
	URL=https://download.fedoraproject.org/pub/fedora/linux/releases/${VERSION}/Server/${ARCH}/images/Fedora-Server-Guest-Generic-${VERSION}-1.1.${ARCH}.qcow2

	ROOTFS_NAME=fedora
	ROOTFS_TYPE=qcow2
	ROOTFS=$OUTPUT/${ROOTFS_NAME}.${ROOTFS_TYPE}
	ROOTFS_TARGET_TYPE=$OUTPUT/${ROOTFS_NAME}_${ARCH}.${ROOTFS_TYPE}
	UBUNTU_BASE_PACKAGE=`basename $URL`

	if [ ! -e $DOWNLOAD/$UBUNTU_BASE_PACKAGE ]; then
		color_echo "Download ubuntu base qcow2 package"
		wget $URL -P $DOWNLOAD
		exit
	fi

	if [ ! -e $ROOTFS_TARGET_TYPE ]; then
		cp $DOWNLOAD/$UBUNTU_BASE_PACKAGE $ROOTFS_TARGET_TYPE

		qemu-img resize $ROOTFS_TARGET_TYPE +10G
		virt-customize -a $ROOTFS_TARGET_TYPE				\
			--upload $DEFAULT_SETTING:/root/$DEFAULT_SETTING	\
			--run-command "chmod +x /root/$DEFAULT_SETTING"		\
			--run-command "/root/$DEFAULT_SETTING"			\
			--delete /root/$DEFAULT_SETTING
	fi

	color_echo "Install software by dnf"
	if [ ! -z "$SOFTWARE" ]; then
		virt-customize -a $ROOTFS_TARGET_TYPE --run-command "dnf install -y $SOFTWARE"
	fi

	rootfs_qcow2_common

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

	if [ $GUEST = "ubuntu" ]; then
		rootfs_qcow2_ubuntu
	elif [ $GUEST = "fedora" ]; then
		rootfs_qcow2_fedora
	else
		echo "Not supported by guest Linux distributions."
		exit
	fi
else
	color_echo "Install dependencies"
	if [ ! `which arch-chroot` ]; then
		sudo $PACKAGE_MANAGER install arch-install-scripts
	fi

	if [ ! `which samba` ]; then
		sudo $PACKAGE_MANAGER install samba
	fi

	if [[ $ARCH = "aarch64" && ! `which qemu-aarch64-static` ]]; then
		sudo $PACKAGE_MANAGER install qemu-user-static
	fi

	if [[ $ARCH = "riscv64" && ! `which qemu-riscv64-static` ]]; then
		sudo $PACKAGE_MANAGER install qemu-user-static
	fi

	rootfs_only
fi
