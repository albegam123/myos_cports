pkgname = "irosh"
pkgver = "0.5.0"
pkgrel = 1
build_style = "cargo"
make_build_args = ["--package", "irosh-cli", "--bin", "irosh"]
hostmakedepends = ["cargo-auditable"]
makedepends = ["dinit-chimera", "rust-std"]
pkgdesc = "Secure P2P SSH and data transfer protocol"
license = "MIT OR Apache-2.0"
url = "https://github.com/shedrackgodstime/irosh"
# check: unit tests need live network/relay peers; skip debug builds for size
options = ["!check", "!debug"]


def post_extract(self):
    self.cp(self.files_path / "Cargo.toml", ".")
    self.cp(self.files_path / "Cargo.lock", ".")
    self.cp(self.files_path / "cli", ".", recursive=True)
    self.cp(self.files_path / "src", ".", recursive=True)
    self.cp(self.files_path / "fuzz", ".", recursive=True)


def install(self):
    self.install_bin(f"target/{self.profile().triplet}/release/irosh")
    self.install_service(self.files_path / "irosh")
    self.install_service(self.files_path / "irosh-bootstrap")
    self.install_file(self.files_path / "irosh-bootstrap.sh", "usr/lib", mode=0o755)
    self.install_license(self.files_path / "LICENSE-MIT", "LICENSE-MIT")
    self.install_license(self.files_path / "LICENSE-APACHE", "LICENSE-APACHE")
