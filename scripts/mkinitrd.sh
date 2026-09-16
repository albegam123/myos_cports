#!/bin/sh

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/scripts/lib.sh"

ARCH=$(normalize_arch "${1:-amd64}")
OUT=${2:-"$ROOT/out"}
TOOLS="$OUT/$ARCH/initrd-tools"
STAGE="$OUT/$ARCH/initrd-root"
IMAGE="$OUT/$ARCH/myos-initrd-$ARCH.img.zst"
EPOCH=${SOURCE_DATE_EPOCH:-0}
MODULES_DIR=${MODULES_DIR:-}
MODULES=${MODULES:-"virtio_blk ext4"}

need_cmd cpio
need_cmd zstd
need_cmd sha256sum
[ -x "$TOOLS/init" ] || die "missing $TOOLS/init; run make initrd-tools ARCH=$ARCH"
[ -x "$TOOLS/armybox" ] || die "missing $TOOLS/armybox; run make initrd-tools ARCH=$ARCH"

rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/dev" "$STAGE/newroot" "$STAGE/proc" "$STAGE/run" "$STAGE/sys"
chmod 0755 "$STAGE" "$STAGE/bin" "$STAGE/dev" "$STAGE/newroot" "$STAGE/proc" "$STAGE/run" "$STAGE/sys"
cp "$TOOLS/init" "$STAGE/init"
cp "$TOOLS/armybox" "$STAGE/bin/armybox"
ln -s armybox "$STAGE/bin/sh"
chmod 0755 "$STAGE/init" "$STAGE/bin/armybox"

if [ -n "$MODULES_DIR" ]; then
    [ -d "$MODULES_DIR" ] || die "kernel modules directory not found: $MODULES_DIR"
    need_cmd python3
    release=$(basename "$MODULES_DIR")
    load_file="$STAGE/etc/modules.load"
    mkdir -p "$STAGE/etc" "$STAGE/lib/modules/$release"
    : >"$load_file"
    # shellcheck disable=SC2086
    "$ROOT/scripts/resolve-modules.py" "$MODULES_DIR" $MODULES | while IFS= read -r module; do
        [ -n "$module" ] || continue
        source_module="$MODULES_DIR/$module"
        [ -f "$source_module" ] || die "module listed in modules.dep is absent: $source_module"
        case "$module" in
            *.zst) target_module=${module%.zst}; need_cmd zstd ;;
            *.xz) target_module=${module%.xz}; need_cmd xz ;;
            *.gz) target_module=${module%.gz}; need_cmd gzip ;;
            *) target_module=$module ;;
        esac
        destination="$STAGE/lib/modules/$release/$target_module"
        mkdir -p "$(dirname "$destination")"
        case "$module" in
            *.zst) zstd -qdc "$source_module" >"$destination" ;;
            *.xz) xz -dc "$source_module" >"$destination" ;;
            *.gz) gzip -dc "$source_module" >"$destination" ;;
            *) cp "$source_module" "$destination" ;;
        esac
        printf '/lib/modules/%s/%s\n' "$release" "$target_module" >>"$load_file"
    done
    note "included module closure for:$MODULES"
fi

# newc stores mtimes, so normalize all entries before sorting the archive list.
find "$STAGE" -print0 | xargs -0 touch -h -d "@$EPOCH"
note "packing deterministic initrd $IMAGE"
(cd "$STAGE" && find . -mindepth 1 -print | LC_ALL=C sort | \
    cpio --quiet --create --format=newc --reproducible --owner=0:0) | \
    zstd --quiet --force --threads=1 -19 -o "$IMAGE"

sha_sidecar "$IMAGE"
{
    printf 'architecture=%s\n' "$ARCH"
    printf 'format=newc+zstd\n'
    printf 'source_date_epoch=%s\n' "$EPOCH"
    printf 'normal_boot_shell=false\n'
    sha256sum "$STAGE/init" "$STAGE/bin/armybox" "$IMAGE"
} >"$IMAGE.manifest"
note "wrote $IMAGE"
