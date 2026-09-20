pkgname = "lldb"
pkgver = "22.1.8"
pkgrel = 0
archs = ["aarch64", "loongarch64", "ppc64le", "ppc64", "riscv64", "x86_64"]
build_style = "cmake"
configure_args = [
    "-DCMAKE_BUILD_TYPE=Release",
    "-DLLDB_ENABLE_LUA=OFF",  # maybe later
    "-DLLDB_ENABLE_PYTHON=ON",
    "-DLLDB_ENABLE_LIBEDIT=ON",
]
# Cross builds a host lldb-tblgen first. That configure is a standalone
# LLVM/Clang consumer and looks in /usr (NO_CMAKE_FIND_ROOT_PATH), so the
# devel packages must be host dependencies, not only target makedepends.
hostmakedepends = [
    "clang-devel",
    "cmake",
    "libedit-devel",
    "libffi8-devel",
    "libxml2-devel",
    "llvm-devel",
    "ncurses-devel",
    "ninja",
    "pkgconf",
    "python-devel",
    "swig",
    "xz-devel",
    "zlib-ng-compat-devel",
]
makedepends = [
    "clang-devel",
    "libedit-devel",
    "libffi8-devel",
    "libxml2-devel",
    "linux-headers",
    "llvm-devel",
    "ncurses-devel",
    "python-devel",
    "xz-devel",
    "zlib-ng-compat-devel",
]
pkgdesc = "LLVM debugger"
license = "Apache-2.0 WITH LLVM-exception AND NCSA"
url = "https://llvm.org"
source = f"https://github.com/llvm/llvm-project/releases/download/llvmorg-{pkgver}/llvm-project-{pkgver}.src.tar.xz"
sha256 = "922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888"
# tests are not enabled
options = ["!check"]

cmake_dir = "lldb"


def init_configure(self):
    if not self.profile().cross:
        return

    # LLDBStandalone uses find_package(... NO_CMAKE_FIND_ROOT_PATH), so the
    # target build must be pointed at the sysroot explicitly. Host
    # llvm-devel/clang-devel exist only so the host lldb-tblgen can be built.
    sroot = self.profile().sysroot
    self.configure_args += [
        "-DLLDB_TABLEGEN_EXE="
        + str(self.chroot_cwd / "build_host/bin/lldb-tblgen"),
        "-DLLVM_TABLEGEN=/usr/bin/llvm-tblgen",
        f"-DLLVM_DIR={sroot}/usr/lib/cmake/llvm",
        f"-DClang_DIR={sroot}/usr/lib/cmake/clang",
    ]


def pre_configure(self):
    if not self.profile().cross:
        return

    from cbuild.util import cmake

    self.log("building host tblgen...")

    with self.profile("host"):
        with self.stamp("host_lldb_configure"):
            cmake.configure(
                self,
                "build_host",
                self.cmake_dir,
                [
                    "-DLLVM_DIR=/usr/lib/cmake/llvm",
                    "-DClang_DIR=/usr/lib/cmake/clang",
                ],
            )

        with self.stamp("host_lldb_tblgen") as s:
            s.check()
            cmake.build(self, "build_host", ["--target", "bin/lldb-tblgen"])


def post_install(self):
    from cbuild.util import python

    self.install_license("LICENSE.TXT")

    # fix up python liblldb symlink so it points to versioned one
    # unversioned one is in devel package so we cannot point to it
    for f in (self.destdir / "usr/lib").glob("python3*"):
        fp = f / "site-packages/lldb"
        if not fp.is_dir():
            continue
        for s in fp.glob("_lldb.*.so"):
            if s.is_symlink():
                s.unlink()
                s.with_name("_lldb.so").symlink_to(
                    f"../../../liblldb.so.{pkgver}"
                )
    # also precompile bytecode
    python.precompile(self, "usr/lib")


@subpackage("lldb-devel")
def _(self):
    return self.default_devel()
