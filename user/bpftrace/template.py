pkgname = "bpftrace"
pkgver = "0.26.1"
pkgrel = 2
build_style = "cmake"
configure_args = [
    # cant run them anyway
    "-DBUILD_TESTING=OFF",
    "-DUSE_SYSTEM_LIBBPF=ON",
    # man pages need asciidoctor → ruby → rust (yjit); skip under FULL_SOURCE
    "-DENABLE_MAN=OFF",
]
hostmakedepends = [
    "bison",
    "cmake",
    "flex",
    "ninja",
    "vim-xxd",
]
makedepends = [
    "bcc-devel",
    "cereal",
    "clang-devel",
    "elfutils-devel",
    "libbpf-devel",
    "libbpf-devel-static",
    "libedit-devel",
    "libffi8-devel",
    "libpcap-devel",
    "libxml2-devel",
    "linux-headers",
    "lldb-devel",
    "llvm-devel",
    "zlib-ng-compat-devel",
]
# Runtime probes are compiled by the embedded Clang. That needs libc
# headers (stdc-predef.h) and the kernel UAPI headers.
depends = ["linux-headers", "musl-devel"]
pkgdesc = "High-level eBPF tracing language"
license = "Apache-2.0"
url = "https://github.com/bpftrace/bpftrace"
source = f"{url}/archive/refs/tags/v{pkgver}.tar.gz"
sha256 = "555368f32f94bfcb74b119a3d9c67b68200be6375b8f452f794a2d3f6ebbcd16"
# NOTE: upstream kept !strip to preserve BEGIN/END_trigger symbols, but
# since 0.26 BEGIN/END are ProbeType::special attached as raw tracepoints
# and no such symbols exist in the binary; stripping is safe and shrinks
# the package from ~115 MiB (full DWARF) to ~10 MiB.

