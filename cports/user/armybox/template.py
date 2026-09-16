pkgname = "armybox"
pkgver = "0.5.0"
pkgrel = 0
build_style = "cargo"
make_build_args = [
    "--no-default-features",
    "--features",
    "alloc,sh,cat,echo,ls,mount,umount,blkid,modprobe,insmod,dmesg,reboot,poweroff,sleep,sync,ps,kill,env,uname",
]
make_install_args = make_build_args
hostmakedepends = ["cargo-auditable"]
makedepends = [
    "libatomic-chimera-devel-static",
    "libunwind-devel-static",
    "musl-devel-static",
    "rust-std",
]
pkgdesc = "Small no_std Rust multicall binary for the MyOS initrd"
license = "MIT OR Apache-2.0"
url = "https://github.com/quinnjr/armybox"
source = f"https://crates.io/api/v1/crates/armybox/{pkgver}/download>armybox-{pkgver}.crate"
sha256 = "6c7e1b18fef8e4798d5cf92e888c7e86e8780561d1cc14e60a50cb1048360b46"
# Armybox is no_std but calls libc directly; its 0.5.0 binary target does not
# emit the native link directive itself.
tool_flags = {
    "RUSTFLAGS": ["-Ctarget-feature=+crt-static", "-Clink-arg=-lc"]
}
# Upstream tests exercise host utilities and are not valid for the static
# cross-target initrd subset.
options = ["!check", "!debug"]


def post_install(self):
    self.install_license("LICENSE-APACHE")
    self.install_license("LICENSE-MIT")
