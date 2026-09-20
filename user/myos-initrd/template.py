pkgname = "myos-initrd"
pkgver = "0.1.0"
pkgrel = 1
build_style = "cargo"
hostmakedepends = ["cargo-auditable"]
makedepends = [
    "libatomic-chimera-devel-static",
    "libunwind-devel-static",
    "musl-devel-static",
    "rust-std",
]
pkgdesc = "Minimal Rust PID 1 for the MyOS initrd"
license = "MIT"
url = "https://example.invalid/myos"
tool_flags = {"RUSTFLAGS": ["-Ctarget-feature=+crt-static"]}
options = ["!debug"]


def post_extract(self):
    self.cp(self.files_path / "Cargo.toml", ".")
    self.cp(self.files_path / "Cargo.lock", ".")
    self.cp(self.files_path / "src", ".", recursive=True)


def post_install(self):
    self.install_license(self.files_path / "LICENSE")
