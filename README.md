## Make root file system

### Brief introduction

This is a simple root file system build script, based on Ubuntu, that allows
you to install the software via apt or overlay.

### Usage

```bash
$ ./make_rootfs.sh <options>

Options:
-a, --arch <x86_64/arm64/riscv64>  Specify the architecture
-i, --install <software>           Specify the software to be install
-m, --mount <directory>            Specifies the mount point for the root filesystem
-h, --help                         Display this help
```

If the `--arch` not specified, defalut target architecture is x86_64.

Currently only x86_64, arm64 and riscv64 are supported.

If the `--mount` not specified, defalut mount point is `/mnt`.

### Install software

There are three ways to install the software, as below:

1. apt by native system, specify the software name in `--install` parameters
2. apt by virtual machine system, run `apt install xxx` command in runtime
3. overlay, put the relevant software in the `overlay/` directory
   and rebuild the root file system.

### How do I boot root file system?

```bash
## x86_64
$ qemu-system-x86_64 -hda rootfs.ext4 -kernel bzImage -append "root=/dev/sda rw console=ttyS0" -nographic

## arm64
$ qemu-system-aarch64 -M virt -cpu cortex-a57 -hda rootfs.ext4 -kernel Image -append "root=/dev/vda rw console=ttyAMA0" -nographic

## riscv64
$ qemu-system-riscv64 -M virt -drive file=rootfs.ext4,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 -kernel Image -append "root=/dev/vda rw console=ttyS0" -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 -nographic
```

Optional parameters:

1. `-m` specifies the memory size of the virtual machine, in MB,
   the default is 95MB
2. `-smp` specifies the number of CPU cores of the virtual machine,
   which is one CPU core by default
