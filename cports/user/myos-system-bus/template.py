pkgname = "myos-system-bus"
pkgver = "0.1.0"
pkgrel = 0
build_style = "cargo"
hostmakedepends = ["cargo-auditable"]
makedepends = ["dinit-chimera", "dinit-dbus", "rust-std"]
depends = ["dbus"]
pkgdesc = "Minimal MyOS system service implemented with Rust zbus"
license = "MIT"
url = "https://example.invalid/myos"
options = ["!debug"]


def post_extract(self):
    self.cp(self.files_path / "Cargo.toml", ".")
    self.cp(self.files_path / "Cargo.lock", ".")
    self.cp(self.files_path / "src", ".", recursive=True)


def post_install(self):
    self.install_service(self.files_path / "myos-system-bus")
    self.install_file(
        self.files_path / "org.myos.System1.conf",
        "usr/share/dbus-1/system.d",
    )
    self.install_license(self.files_path / "LICENSE")
