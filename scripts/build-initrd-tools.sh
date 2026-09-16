#!/bin/sh

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/scripts/lib.sh"

ARCH=$(normalize_arch "${1:-amd64}")
OUT=${2:-"$ROOT/out"}
TARGET=$(rust_target "$ARCH")
DEST="$OUT/$ARCH/initrd-tools"
FEATURES='alloc,sh,cat,echo,ls,mount,umount,blkid,modprobe,insmod,dmesg,reboot,poweroff,sleep,sync,ps,kill,env,uname'
LINKER_FLAG=

need_cmd cargo
need_cmd rustc
need_cmd readelf
mkdir -p "$DEST"

if ! rustc --print target-list | grep -qx "$TARGET"; then
    die "Rust compiler does not know target $TARGET"
fi

if ! rustup target list --installed 2>/dev/null | grep -qx "$TARGET"; then
    die "Rust standard library target $TARGET is not installed (rustup target add $TARGET)"
fi

if [ "$ARCH" = aarch64 ]; then
    RUST_LLD="$(rustc --print sysroot)/lib/rustlib/$(rustc -vV | sed -n 's/^host: //p')/bin/rust-lld"
    [ -x "$RUST_LLD" ] || die "cross linker not found: $RUST_LLD"
    LINKER_FLAG="-Clinker=$RUST_LLD"
fi

note "building Rust init for $TARGET"
RUSTFLAGS="$LINKER_FLAG" \
CARGO_TARGET_DIR="$OUT/$ARCH/myos-initrd-target" \
cargo build --locked --release --target "$TARGET" \
    --manifest-path "$ROOT/cports/user/myos-initrd/files/Cargo.toml"
cp "$OUT/$ARCH/myos-initrd-target/$TARGET/release/myos-initrd" "$DEST/init"

note "building pinned Armybox 0.5.0 recovery binary for $TARGET"
RUSTFLAGS="$LINKER_FLAG -Ctarget-feature=+crt-static -Clink-arg=-lc" \
CARGO_TARGET_DIR="$OUT/$ARCH/armybox-target" \
cargo install --locked --force --root "$OUT/$ARCH/armybox-install" \
    --target "$TARGET" --version 0.5.0 armybox \
    --no-default-features --features "$FEATURES"
cp "$OUT/$ARCH/armybox-install/bin/armybox" "$DEST/armybox"

is_static_elf "$DEST/init" || die "myos-initrd is not a static ELF"
is_static_elf "$DEST/armybox" || die "armybox is not a static ELF"
chmod 0755 "$DEST/init" "$DEST/armybox"

{
    printf 'architecture=%s\n' "$ARCH"
    printf 'rust_target=%s\n' "$TARGET"
    printf 'armybox_version=0.5.0\n'
    sha256sum "$DEST/init" "$DEST/armybox"
} >"$DEST/manifest.txt"
