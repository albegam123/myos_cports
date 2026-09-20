pkgname = "perf"
pkgver = "6.18.4"
pkgrel = 3
build_wrksrc = "tools/perf"
build_style = "makefile"
make_build_args = [
    "-f",
    "Makefile.perf",
    "LIBBPF_DYNAMIC=1",
    "LLVM=1",
    "NO_DEBUGINFOD=1",
    "NO_LIBAUDIT=1",
    "NO_LIBBABELTRACE=1",
    "NO_LIBPFM4=1",
    "NO_LIBUNWIND=1",
    "NO_SDT=1",
    "STRIP=/bin/true",
    "V=1",
    "WERROR=0",
    "libdir=/usr/lib",
    "perfexecdir=/usr/lib/perf-core",
    "mandir=/usr/share/man",
    "prefix=/usr",
    "sbindir=/usr/bin",
    "tipdir=/usr/share/doc/perf-tip",
]
make_install_args = [
    "install-python_ext",
    *make_build_args,
]
make_use_env = True
hostmakedepends = [
    "asciidoc",
    "bash",
    "bison",
    "elfutils-devel",
    "flex",
    "linux-headers",
    "openssl3-devel",
    "pkgconf",
    "python",
    "python-setuptools",
    "xmlto",
    "zlib-ng-compat-devel",
    "zstd-devel",
]
makedepends = [
    "audit-devel",  # for archs without syscall_table like riscv
    "capstone-devel",
    "elfutils-devel",
    "libbpf-devel",
    "libtraceevent-devel",
    "linux-headers",
    "numactl-devel",
    "openssl3-devel",
    "perl",
    "python-devel",
    "slang-devel",
    "xz-devel",
    "zlib-ng-compat-devel",
    "zstd-devel",
]
pkgdesc = "Linux performance analyzer"
license = "GPL-2.0-only"
url = "https://perf.wiki.kernel.org/index.php/Main_Page"
source = f"https://cdn.kernel.org/pub/linux/kernel/v{pkgver[: pkgver.find('.')]}.x/linux-{pkgver}.tar.xz"
sha256 = "f850139ca5f79c1bf6bb8b32f92e212aadca97bdaef8a83a7cf4ac4d6a525fab"
# nope
# docs are a single tips file that gets displayed in the TUI
options = ["!check", "!splitdoc"]

if self.profile().arch == "ppc":
    broken = "segfaults during build"


def init_build(self):
    from cbuild.util import linux

    self.make_build_args += [f"EXTRA_CFLAGS={self.get_cflags(shell=True)}"]
    self.make_install_args += [f"EXTRA_CFLAGS={self.get_cflags(shell=True)}"]

    if self.profile().cross:
        # perf detects clang and rewrites CC := $(CLANG) ..., dropping the
        # aarch64-*-clang wrapper. Without CROSS_COMPILE the feature checks
        # look at host headers, fail to find libelf.h, and misreport that as
        # a missing glibc gnu/libc-version.h.
        # Do not pass --sysroot=.../usr here: clang needs the triplet root
        # (profile.sysroot), which the *-clang argv0 wrapper already sets.
        #
        # PYTHON detection goes through python*-config, which lives only in
        # the target sysroot when cross-building; point at it explicitly and
        # keep a host interpreter for jevents generation.
        trip = self.profile().triplet
        pyconf = self.profile().sysroot / "usr/bin/python3-config"
        # LIBBPF_DYNAMIC never sets LIBBPF_INCLUDE; native builds find
        # bpf/bpf_helpers.h via clang's default -idirafter /usr/include.
        # Cross BPF compiles use --target=bpf and need the sysroot path.
        bpfinc = self.profile().sysroot / "usr/include"
        cross = [
            f"ARCH={linux.get_arch(self)}",
            f"CROSS_COMPILE={trip}-",
            f"CLANG={trip}-clang",
            f"CXX={trip}-clang++",
            "PYTHON=python3",
            f"PYTHON_CONFIG={pyconf}",
            f"LIBBPF_INCLUDE={bpfinc}",
        ]
        self.make_build_args += cross
        self.make_install_args += cross


def post_install(self):
    # relink hardlink
    self.uninstall("usr/bin/trace")
    self.install_link("usr/bin/trace", "perf")
    # valid as both
    self.uninstall("etc/bash_completion.d")
    self.install_completion("perf-completion.sh", "bash")
    self.install_completion("perf-completion.sh", "zsh")
    # pointless tests
    self.uninstall("usr/lib/perf-core/tests")
