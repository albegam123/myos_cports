pkgname = "myos-base"
pkgver = "0.1.0"
pkgrel = 0
depends = [
    "base-bootstrap",
    "dinit-chimera",
    "dinit-dbus",
    "iwd",
    "myos-system-bus",
]
pkgdesc = "Minimal MyOS boot, bus and Wi-Fi policy"
license = "custom:meta"
url = "https://example.invalid/myos"
broken_symlinks = ["usr/lib/dinit.d/boot.d/*"]
options = ["!splitdinit"]


def install(self):
    self.install_dir("usr/lib/dinit.d/boot.d")
    self.install_link("usr/lib/dinit.d/boot.d/iwd", "../iwd")
    self.install_link(
        "usr/lib/dinit.d/boot.d/myos-system-bus", "../myos-system-bus"
    )
