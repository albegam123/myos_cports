# Architecture decisions

## Package and libc baseline

MyOS follows Chimera's musl/LLVM/cports model. cports is intentionally used as
the source package graph rather than wrapped in another general-purpose build
framework. `scripts/build-packages.sh` passes `-N`, so missing dependencies are
built recursively instead of silently fetched as target binaries. The initial
cbuild bootstrap remains a trusted seed and should eventually be covered by a
stage-2 reproducibility comparison.

Architecture names are normalized at the boundary:

| Common name | cports/apk | Rust musl target |
| --- | --- | --- |
| amd64 | x86_64 | x86_64-unknown-linux-musl |
| arm64 | aarch64 | aarch64-unknown-linux-musl |

## Boot boundary

The kernel unpacks a zstd-compressed `newc` archive and starts `/init`.
`myos-initrd` performs only deterministic boot mechanics:

1. make mount propagation private;
2. mount devtmpfs, proc, sysfs and tmpfs;
3. parse the kernel command line and wait for the root device;
4. mount the root filesystem;
5. move the kernel filesystems, pivot the root, and release the initramfs;
6. `execve` dinit as PID 1.

Armybox is a recovery and diagnostics surface. It is not the normal PID 1 and
no shell script is in the successful boot path. If switching root fails,
`myos-initrd` starts Armybox's shell on the console so the failure remains
repairable.

The small first version has a deliberate kernel contract: block transport and
the selected root filesystem are built in. Loading an arbitrary modular
storage stack correctly requires firmware, modalias handling, module
dependencies and coldplug synchronization; pretending that a few copied `.ko`
files solve this would be fragile. A future hardware profile may add a Rust
coldplug/module loader without changing PID 1's interface.

## Service and bus boundary

dinit is the only service manager. The system bus has three distinct layers:

```text
dbus-daemon (transport) -> dinit-dbus (service-manager adapter)
                        -> Rust services using zbus (application API)
```

Calling `zbus` the daemon would blur an important reliability boundary: zbus
serializes and consumes D-Bus messages, while `dbus-daemon` owns routing,
policy and activation. The base profile uses Chimera's dinit-aware D-Bus
patches. New privileged services should be Rust binaries with narrow zbus
interfaces and explicit D-Bus policy files.

iwd manages Wi-Fi authentication. DHCP/address policy is intentionally absent
from the first profile: this milestone proves that iwd starts and is reachable
over the bus, not that the machine automatically reaches the Internet.

## Root filesystem profile

The minimal package list is in `config/packages.base` and contains one policy
metapackage. That package depends only on the requested components: the Chimera
bootstrap floor, dinit integration, D-Bus/dinit bridge, the Rust zbus service,
and iwd. Their package-manager dependencies remain unavoidable. Core new MyOS
components should be Rust by default; C++ is suitable where an established
native stack (including dinit) is the better engineering choice.

## Graphics boundary

Smithay is the preferred compositor toolkit, but it should enter as a separate
`myos-graphical` profile. That profile will own DRM/KMS, libinput, seatd,
PipeWire and portal policy. Keeping it out of `myos-base` makes headless images
small and prevents a provisional compositor from becoming an ABI promise.

## Security and reproducibility

- Upstream archives and crates are versioned and SHA-256 pinned in ports.
- Cargo builds use lock files and cports vendoring/offline build phases.
- initrd entries have normalized ownership and timestamps.
- generated files receive manifests and SHA-256 sidecars.
- package repositories are signed by cbuild; private keys never enter images.

Further hardening and graphical work stays out of this phase.
