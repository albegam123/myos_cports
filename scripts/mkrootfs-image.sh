#!/bin/sh

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/scripts/lib.sh"

ARCH=$(normalize_arch "${1:-amd64}")
OUT=${2:-"$ROOT/out"}
ROOTFS="$OUT/$ARCH/rootfs"
IMAGE="$OUT/$ARCH/myos-rootfs-$ARCH.ext4"
DISK_SIZE=${DISK_SIZE:-1G}
IMAGE_TMP="$IMAGE.tmp.$$"

case "$ARCH" in
    x86_64) FS_UUID=00000000-0000-0000-0000-000000000001 ;;
    aarch64) FS_UUID=00000000-0000-0000-0000-000000000002 ;;
esac

need_cmd mke2fs
need_cmd truncate
need_cmd sha256sum
[ -x "$ROOTFS/usr/bin/dinit" ] || die "cports rootfs is absent or incomplete; run make packages and make rootfs first"
[ -x "$ROOTFS/usr/bin/sh" ] || die "cports rootfs has no /usr/bin/sh"

note "creating $DISK_SIZE ext4 image from the cports rootfs"
restore_protected() {
    for file in "$ROOTFS/etc/shadow" "$ROOTFS/etc/shadow-"; do
        [ ! -e "$file" ] || chmod 000 "$file"
    done
}
trap 'restore_protected; rm -f "$IMAGE_TMP"' EXIT HUP INT TERM
rm -f "$IMAGE_TMP"
truncate -s "$DISK_SIZE" "$IMAGE_TMP"
fakeroot sh -c '
    for file in "$1/etc/shadow" "$1/etc/shadow-"; do
        [ ! -e "$file" ] || chmod 000 "$file"
    done
    chown -hR 0:0 "$1"
    E2FSPROGS_FAKE_TIME="$5" exec mke2fs -q -F -t ext4 \
        -U "$4" -L myos-root -m 0 -d "$1" "$2"
' sh "$ROOTFS" "$IMAGE_TMP" "$DISK_SIZE" "$FS_UUID" "${SOURCE_DATE_EPOCH:-0}"
restore_protected
mv -f "$IMAGE_TMP" "$IMAGE"
trap - EXIT HUP INT TERM
sha_sidecar "$IMAGE"
note "wrote $IMAGE"
