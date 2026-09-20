pkgname = "systing"
pkgver = "1.14.0"
pkgrel = 0
build_style = "cargo"
hostmakedepends = [
    "bpftool",
    "cargo",
    "clang",
    "cmake",
    "elfutils-devel",
    "libbpf-devel",
    "linux-headers",
    "pkgconf",
    "zlib-ng-compat-devel",
]
makedepends = [
    "elfutils-devel",
    "libbpf-devel",
    "linux-headers",
    "rust-std",
    "zlib-ng-compat-devel",
]
pkgdesc = "Libbpf tracer for what an application is doing"
license = "MIT"
url = "https://github.com/josefbacik/systing"
# Local tree from ~/dev/systing (upstream plus in-tree changes, 8fd0810).
# Vendor tarball is pre-populated so prepare does not need crates.io.
source = [
    f"{url}/archive/refs/tags/v{pkgver}.tar.gz>systing-{pkgver}.tar.gz",
    f"{url}/releases/download/v{pkgver}/systing-{pkgver}-vendor.tar.gz>systing-{pkgver}-vendor.tar.gz",
]
source_paths = [".", "vendor"]
sha256 = [
    "46f5836867ea4c6342bdc5b252c93f9702e02711f2eb499c79056ddff7f08670",
    "d26d367761f807b2a7eb3f8777e4965d21bf626e277968387d1d0e8d2402a1c9",
]
# Integration tests need root and a live BPF runtime.
options = ["!check"]


def prepare(self):
    # Sources already include vendor/; write the cargo config that
    # `cargo vendor` would have appended (offline, no network).
    self.mkdir(".cargo", parents=True)
    (self.cwd / ".cargo/config.toml").write_text(
        """[source.crates-io]
replace-with = "vendored-sources"

[source."git+https://github.com/libbpf/blazesym.git?rev=8705da0a8cec2bb27f897ac732e27121f9be7936"]
git = "https://github.com/libbpf/blazesym.git"
rev = "8705da0a8cec2bb27f897ac732e27121f9be7936"
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
"""
    )


def install(self):
    # cargo install re-resolves the git blazesym source and refuses the
    # vendored replacement unless it generated the lockfile itself.
    trip = self.profile().triplet
    for name in ("systing", "systing-analyze", "systing-util"):
        self.install_bin(f"target/{trip}/release/{name}")


def post_install(self):
    self.install_license("LICENSE")
