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
