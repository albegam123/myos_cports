# MyOS release builder

This repository is a small, source-first Linux distribution layer on top of
[Chimera Linux cports](https://github.com/chimera-linux/cports). It targets
`x86_64` (amd64) and `aarch64` (arm64), uses musl, dinit and apk, and keeps the
early userspace Rust-only.

The checked-out `cports/` tree is the package build engine and upstream ports
baseline. Distribution policy lives in this top-level tree and in
`cports/user/myos-*`; it does not require Buildroot or Yocto.

## Design in one minute

- `cbuild` builds the selected distribution components from source in an
  isolated build root. Signed Chimera packages seed compilers and the low-level
  dependency closure; `FULL_SOURCE=1` also rebuilds that complete closure.
- `/init` is `myos-initrd`, a small Rust PID 1. It mounts kernel filesystems,
  resolves `root=`, mounts the real root and switches to `/usr/bin/dinit`.
- Armybox 0.5.0 is built from its pinned crates.io source and is present as the
  recovery multicall binary. The normal boot path does not execute a shell.
- dinit owns service lifecycle. The D-Bus daemon provides the wire protocol;
  Rust system services use `zbus`. `zbus` is a library, not a bus daemon.
- iwd is the Wi-Fi control plane. This first profile intentionally stops before
  DHCP/address policy; its goal is to prove the boot and bus path.
- Smithay/Wayland is intentionally outside the base image. See
  `docs/ARCHITECTURE.md` for the future graphical profile boundary.

## Quick start

Run the host checks first:

```sh
make doctor
```

Build and test the native initrd tools (does not need root):

```sh
make initrd-tools ARCH=amd64
make test
```

Create an initrd:

```sh
make initrd ARCH=amd64
```

Build the selected runtime components from source, using the signed cports
bootstrap for compilers and low-level dependencies:

```sh
make bootstrap
make packages ARCH=amd64
```

`FULL_SOURCE=1 make packages ARCH=amd64` also rebuilds the entire compiler and
dependency closure. It is intentionally not the first-boot default because it
pulls in the LLVM/Rust/Python bootstrap graph before producing a tiny runtime.

`cbuild` refuses to run as root and needs user namespaces. The source build is
therefore expected to run as an ordinary user. `make packages ARCH=arm64`
selects cports' `aarch64` cross profile.

Recent Ubuntu hosts may additionally restrict unprivileged user namespaces
through AppArmor. `make doctor` detects this. On a dedicated build machine,
temporarily enable the namespace facility before running cbuild:

```sh
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
```

Create a root filesystem from the resulting signed local repository:

```sh
make rootfs ARCH=amd64
make disk ARCH=amd64
```

The local source-built repository is preferred for MyOS, Dinit, D-Bus and iwd;
signed Chimera repositories provide their low-level runtime dependencies.

For the first console-only QEMU milestone, boot the cports-generated ext4
image with `init=/usr/bin/sh`. This deliberately bypasses dinit only to prove
the initrd-to-rootfs handoff; remove the override when testing dinit services.

```sh
/home/deepthinker/dev/qemu-master/mybuild/qemu-system-x86_64 \
  -cpu Broadwell,avx=on,avx2=on -smp 1 -m 512 \
  -kernel /home/deepthinker/opt/datasets/aishell/aishell/kernel/build_linux_6.18/arch/x86_64/boot/bzImage \
  -initrd out/x86_64/myos-initrd-x86_64.img.zst \
  -drive file=out/x86_64/myos-rootfs-x86_64.ext4,format=raw,if=virtio \
  -append 'console=ttyS0 root=/dev/vda rootfstype=ext4 rw init=/usr/bin/sh' \
  -display none -serial stdio -monitor none -no-reboot
```

The equivalent ARM64 check with the 6.1.84 development kernel first installs
its modules, then puts only the `ext4` dependency closure in the initrd:

```sh
make ARCH=arm64 O=../build_qemu/ INSTALL_MOD_STRIP=1 \
  INSTALL_MOD_PATH=/home/deepthinker/qemu_mount/ubuntu_root_arm64/ \
  modules_install

MODULES_DIR=/home/deepthinker/qemu_mount/ubuntu_root_arm64/lib/modules/6.1.84 \
  MODULES=ext4 make initrd ARCH=arm64
make rootfs ARCH=arm64
make disk ARCH=arm64

/home/deepthinker/dev/qemu-master/mybuild/qemu-system-aarch64 \
  -machine virt -cpu cortex-a57 -m 2G -smp 1 \
  -kernel /home/deepthinker/kernel/RK3588C_UGSDK/build_qemu/arch/arm64/boot/Image \
  -initrd out/aarch64/myos-initrd-aarch64.img.zst \
  -drive file=out/aarch64/myos-rootfs-aarch64.ext4,format=raw,if=virtio,snapshot=on \
  -append 'console=ttyAMA0 root=/dev/vda rootfstype=ext4 rw init=/usr/bin/sh' \
  -nographic -monitor none -no-reboot
```

Remove `init=/usr/bin/sh` to exercise Dinit as PID 1. For iwd, the kernel must
also expose its AF_ALG primitives; in particular enable
`CONFIG_CRYPTO_USER_API_HASH`, `CONFIG_CRYPTO_USER_API_SKCIPHER`, and
`CONFIG_KEY_DH_OPERATIONS`. iwd reports the complete missing set at startup.

Build artifacts are written below `out/<cports-arch>/`. Every image receives a
SHA-256 sidecar and a text manifest. All commands accept `OUT=...` and
`SOURCE_DATE_EPOCH=...` overrides.

## Kernel command line

The initrd understands:

```text
root=/dev/vda2 rootfstype=ext4 rootflags=noatime rw
```

It also recognizes `UUID=`, `PARTUUID=`, `LABEL=` and `PARTLABEL=` via the
usual `/dev/disk/by-*` links. A device manager is not run in this deliberately
small initrd, so direct `/dev/...` roots are the portable baseline. `rootwait`,
`rootdelay=<seconds>`, `rd.timeout=<seconds>`, `ro`, `rw`, and
`init=<absolute-path>` are supported.

The first profile expects storage, root filesystem and devtmpfs support to be
built into the kernel. Validate a kernel config with:

```sh
scripts/check-kernel-config.sh /path/to/.config amd64
```

This keeps the initrd free of udev, a module dependency resolver, and a second
copy of the kernel module tree.

For development kernels whose storage/filesystem drivers are modules, provide
the installed module directory. The builder copies only the dependency closure
and the Rust init loads it before looking for `root=`:

```sh
MODULES_DIR=/lib/modules/6.18.15 MODULES='virtio_blk ext4' \
  make initrd ARCH=amd64
```

Compressed source modules are decompressed while packing because Armybox 0.5.0
`insmod` consumes an ELF `.ko`. No depmod database is required at runtime.

## Repository map

```text
cports/                     upstream cports + four small user ports
  user/armybox/             pinned Rust recovery multicall binary
  user/myos-base/           base-system policy package
  user/myos-initrd/         Rust early-userspace PID 1 package
  user/myos-system-bus/     minimal zbus service and Dinit unit
config/                     package and kernel contracts
scripts/                    reproducible assembly and validation
docs/ARCHITECTURE.md        decisions and extension boundaries
out/                        generated artifacts (ignored)
```

The project is currently only the minimal boot/bus/Wi-Fi foundation. There is
no installer, graphical stack, DHCP policy, SSH server, or general server
tooling in this phase.
