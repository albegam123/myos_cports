pkgname = "myos-base"
pkgver = "0.1.0"
pkgrel = 5
depends = [
    "base-bootstrap",
    "dinit-chimera",
    "dinit-chimera-udev",
    "dinit-dbus",
    "iwd",
    "myos-system-bus",
    "nyagetty",
]
pkgdesc = "Minimal MyOS boot, bus and Wi-Fi policy"
license = "custom:meta"
url = "https://example.invalid/myos"
broken_symlinks = ["usr/lib/dinit.d/boot.d/*"]
options = ["!splitdinit", "etcfiles"]


def install(self):
    self.install_dir("usr/lib/dinit.d/boot.d")
    self.install_link("usr/lib/dinit.d/boot.d/irosh-bootstrap", "../irosh-bootstrap")
    self.install_link("usr/lib/dinit.d/boot.d/iwd", "../iwd")
    self.install_link(
        "usr/lib/dinit.d/boot.d/myos-system-bus", "../myos-system-bus"
    )
    self.install_file(self.files_path / "agetty", "etc/default", name="agetty")
