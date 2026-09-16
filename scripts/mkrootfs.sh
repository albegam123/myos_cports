#!/bin/sh

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/scripts/lib.sh"

ARCH=$(normalize_arch "${1:-amd64}")
OUT=${2:-"$ROOT/out"}
DEST="$OUT/$ARCH/rootfs"
TARBALL="$OUT/$ARCH/myos-rootfs-$ARCH.tar.zst"
APK=${APK:-}

if [ -z "$APK" ]; then
    if [ -x "$ROOT/cports/bldroot/usr/bin/apk.static" ]; then
        APK="$ROOT/cports/bldroot/usr/bin/apk.static"
    elif command -v apk >/dev/null 2>&1; then
        APK=$(command -v apk)
    else
        die "apk not found; run make bootstrap or set APK=/path/to/apk.static"
    fi
fi

LOCAL_MAIN="$ROOT/cports/packages/main"
LOCAL_USER="$ROOT/cports/packages/user"
REMOTE_BASE=${CBUILD_REPO:-https://repo.chimera-linux.org/current}
REMOTE_MAIN="$REMOTE_BASE/main"
REMOTE_USER="$REMOTE_BASE/user"
[ -f "$LOCAL_USER/$ARCH/APKINDEX.tar.gz" ] || die "local user repository missing for $ARCH; run make packages ARCH=$ARCH"
[ -f "$LOCAL_MAIN/$ARCH/APKINDEX.tar.gz" ] || die "local main repository missing for $ARCH; run make packages ARCH=$ARCH"

rm -rf "$DEST"
mkdir -p "$DEST/etc/apk/keys" "$OUT/$ARCH"
cp "$ROOT"/cports/etc/apk/keys/*.pub "$DEST/etc/apk/keys/"
if find "$ROOT/cports/etc/keys" -maxdepth 1 -name '*.pub' -print -quit 2>/dev/null | grep -q .; then
    cp "$ROOT"/cports/etc/keys/*.pub "$DEST/etc/apk/keys/"
fi
packages=$(read_package_file "$ROOT/config/packages.base")
HOST_ARCH=$(normalize_arch "$(uname -m)")
APK_SCRIPT_OPTION=

if [ "$ARCH" != "$HOST_ARCH" ]; then
    # apk would chroot and execute target ELF package scripts.  That cannot
    # work without a host-wide binfmt_misc/qemu-user setup, and requiring one
    # would make cross rootfs assembly depend on mutable host configuration.
    APK_SCRIPT_OPTION=--no-scripts
    note "cross rootfs: deferring target-architecture package scripts"
fi

note "installing the source-built package set into $DEST"
# Prefer the source-built local packages. The signed Chimera repositories
# supply the low-level runtime closure that also seeds the cbuild build root.
# shellcheck disable=SC2086
"$APK" --root "$DEST" --arch "$ARCH" --initdb --usermode \
    $APK_SCRIPT_OPTION \
    --repository "$LOCAL_MAIN" --repository "$LOCAL_USER" \
    --repository "$REMOTE_MAIN" --repository "$REMOTE_USER" \
    --keys-dir "$DEST/etc/apk/keys" add $packages

if [ -n "$APK_SCRIPT_OPTION" ]; then
    note "creating architecture-independent state normally produced by package triggers"

    # sd-sysusers output for the deliberately small package set.  Keep the
    # dynamic dbus id stable across architectures and reproducible builds.
    printf '%s\n' \
        'root:x:0:0:root:/root:/bin/sh' \
        'nobody:x:65534:65534:Kernel Overflow User:/nonexistent:/usr/bin/nologin' \
        'dbus:x:999:999:dbus user:/var/empty:/usr/bin/nologin' \
        >"$DEST/etc/passwd"
    cp "$DEST/etc/passwd" "$DEST/etc/passwd-"
    chmod 0644 "$DEST/etc/passwd"
    chmod 0600 "$DEST/etc/passwd-"

    printf '%s\n' \
        'root:x:0:' 'nogroup:x:65534:' 'adm:x:1:' 'wheel:x:2:' \
        'audio:x:3:' 'bluetooth:x:4:' 'tty:x:5:' 'dialout:x:6:' \
        'disk:x:7:' 'floppy:x:8:' 'input:x:9:' 'kmem:x:10:' \
        'kvm:x:11:' 'lp:x:12:' 'plugdev:x:13:' 'render:x:14:' \
        'scanner:x:15:' 'sgx:x:16:' 'tape:x:17:' 'cdrom:x:18:' \
        'video:x:19:' 'network:x:20:' 'uinput:x:21:' 'mail:x:64:' \
        'utmp:x:65:' 'www-data:x:66:' 'users:x:100:' 'dbus:x:999:' \
        >"$DEST/etc/group"
    cp "$DEST/etc/group" "$DEST/etc/group-"
    sed 's/:x:[^:]*:.*$/:x::/' "$DEST/etc/group" >"$DEST/etc/gshadow"
    chmod 0644 "$DEST/etc/group" "$DEST/etc/group-"
    chmod 0400 "$DEST/etc/gshadow"

    shadow_day=$((${SOURCE_DATE_EPOCH:-0} / 86400))
    printf '%s\n' \
        "dbus:!*:$shadow_day::::::" \
        "root:x:$shadow_day:0:99999:7:::" \
        "nobody:x:$shadow_day:0:99999:7:::" \
        >"$DEST/etc/shadow"
    cp "$DEST/etc/shadow" "$DEST/etc/shadow-"
    chmod 000 "$DEST/etc/shadow" "$DEST/etc/shadow-"

    # The small subset of sd-tmpfiles/base-shells output required before the
    # first dinit boot.  Runtime-only paths under /run are created at boot.
    mkdir -p \
        "$DEST/etc/dinit.d/boot.d" "$DEST/etc/iwd" \
        "$DEST/etc/profile.d" "$DEST/etc/sysctl.d" \
        "$DEST/etc/udev/hwdb.d" "$DEST/etc/udev/rules.d" \
        "$DEST/etc/ssl/certs" "$DEST/etc/ca-certificates/update.d" \
        "$DEST/var/empty" "$DEST/var/lib/dbus" "$DEST/var/lib/ead" \
        "$DEST/var/lib/iwd" "$DEST/var/lib/swclock" "$DEST/var/log" \
        "$DEST/var/mail" "$DEST/var/spool" "$DEST/var/www"
    chmod 0700 "$DEST/var/lib/ead" "$DEST/var/lib/iwd"
    chmod 1777 "$DEST/tmp"

    for file in fstab hosts issue nsswitch.conf; do
        cp "$DEST/usr/share/base-files/$file" "$DEST/etc/$file"
    done
    for file in phones remote; do
        cp "$DEST/usr/share/chimerautils/$file" "$DEST/etc/$file"
    done
    ln -snf ../proc/self/mounts "$DEST/etc/mtab"
    ln -snf ../usr/lib/chimera-release "$DEST/etc/chimera-release"
    ln -snf ../usr/lib/os-release "$DEST/etc/os-release"
    ln -snf ../usr/share/base-files/profile "$DEST/etc/profile"
    ln -snf ../usr/share/netbase/protocols "$DEST/etc/protocols"
    ln -snf ../usr/share/netbase/services "$DEST/etc/services"
    ln -snf ../usr/share/zoneinfo/UTC "$DEST/etc/localtime"
    rm -rf "$DEST/var/lock" "$DEST/var/run" "$DEST/var/spool/mail"
    ln -snf ../run/lock "$DEST/var/lock"
    ln -snf ../run "$DEST/var/run"
    ln -snf ../mail "$DEST/var/spool/mail"
    ln -snf ../../../etc/machine-id "$DEST/var/lib/dbus/machine-id"
    printf '%s\n' '/usr/bin/sh' '/bin/sh' >"$DEST/etc/shells"

    # A bundle is enough for TLS clients; hashed OpenSSL compatibility links
    # can be regenerated by the target trigger after future package changes.
    ln -snf ../usr/share/ca-certificates/ca-certificates.conf \
        "$DEST/etc/ca-certificates.conf"
    : >"$DEST/etc/ssl/certs/ca-certificates.crt"
    while IFS= read -r cert; do
        case "$cert" in ''|'#'*|'!'*) continue ;; esac
        [ ! -f "$DEST/usr/share/ca-certificates/$cert" ] || \
            sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
                "$DEST/usr/share/ca-certificates/$cert" \
                >>"$DEST/etc/ssl/certs/ca-certificates.crt"
    done <"$DEST/usr/share/ca-certificates/ca-certificates.conf"
    ln -snf certs/ca-certificates.crt "$DEST/etc/ssl/certs.pem"
fi

printf '%s\n%s\n%s\n%s\n' \
    "$LOCAL_MAIN" "$LOCAL_USER" "$REMOTE_MAIN" "$REMOTE_USER" \
    >"$DEST/etc/apk/repositories"
printf 'myos\n' >"$DEST/etc/hostname"

note "packing deterministic rootfs"
need_cmd fakeroot
find "$DEST" -print0 | xargs -0 touch -h -d "@${SOURCE_DATE_EPOCH:-0}"
FILELIST="$OUT/$ARCH/.rootfs-files.$$"
TAR_TMP="$OUT/$ARCH/.rootfs.tar.$$"
ZST_TMP="$TARBALL.tmp.$$"
restore_protected() {
    for file in "$DEST/etc/shadow" "$DEST/etc/shadow-"; do
        [ ! -e "$file" ] || chmod 000 "$file"
    done
}
trap 'restore_protected; rm -f "$FILELIST" "$TAR_TMP" "$ZST_TMP"' EXIT HUP INT TERM
(cd "$DEST" && find . -mindepth 1 -print | LC_ALL=C sort) >"$FILELIST"
# apk --usermode protects files such as /etc/shadow with mode 000. Fakeroot
# records their intended mode while making their backing files readable to
# tar. Restore the physical tree even if tar or compression fails.
fakeroot sh -c '
    for file in "$1/etc/shadow" "$1/etc/shadow-"; do
        [ ! -e "$file" ] || chmod 000 "$file"
    done
    exec tar -C "$1" --no-recursion --numeric-owner \
        --owner=0 --group=0 --mtime="@$4" -cf "$2" -T "$3"
' sh "$DEST" "$TAR_TMP" "$FILELIST" "${SOURCE_DATE_EPOCH:-0}"
restore_protected
zstd --quiet --force --threads=1 -19 -o "$ZST_TMP" "$TAR_TMP"
mv -f "$ZST_TMP" "$TARBALL"
rm -f "$FILELIST" "$TAR_TMP"
trap - EXIT HUP INT TERM
sha_sidecar "$TARBALL"
"$APK" --root "$DEST" info -vv >"$TARBALL.packages"
note "wrote $TARBALL"
