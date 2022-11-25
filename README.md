## Make root file system

### Brief introduction

This is a simple root file system build script, based on Ubuntu, that allows
you to install the software via apt or overlay.

### Usage

```bash
$ ./make_rootfs.sh [arch] [mount_location]
```

If the `[arch]` not specified, defalut target architecture is x86_64.

Currently only x86_64, arm64 and riscv64 are supported.

If the `[mount_location]` not specified, defalut mount location is `/mnt`.

### Install software

There are two ways to install the software, apt and overlay.

If you want to install the software through apt, enter the software name directly
in `install_software` file and rebuild the root file system.

If you want to install software via overlay, put the relevant software in
the `overlay/` directory and rebuild the root file system.

### How do I boot root file system?

```bash
## x86_64
$ qemu-system-x86_64 -hda rootfs.ext4 -kernel bzImage -append "root=/dev/sda console=ttyS0" -nographic

## arm64
$ qemu-system-aarch64 -M virt -cpu cortex-a57 -hda rootfs.ext4 -kernel Image -append "root=/dev/vda console=ttyAMA0" -nographic

## riscv64
$ qemu-system-riscv64 -M virt -drive file=rootfs.ext4,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 -kernel Image -append "root=/dev/vda console=ttyS0" -nographic
```
