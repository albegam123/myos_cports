#!/bin/sh

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/scripts/lib.sh"

[ "$(id -u)" -ne 0 ] || die "cbuild must be bootstrapped by a non-root user"
if [ -r /proc/sys/kernel/apparmor_restrict_unprivileged_userns ] && \
    [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)" = 1 ]; then
    die "AppArmor blocks unprivileged user namespaces; run make doctor for the host setting"
fi
need_cmd python3
need_cmd git
if [ -n "${CBUILD_BWRAP_PATH:-}" ]; then
    [ -x "$CBUILD_BWRAP_PATH" ] || die "CBUILD_BWRAP_PATH is not executable: $CBUILD_BWRAP_PATH"
else
    need_cmd bwrap
fi
if [ -n "${CBUILD_APK_PATH:-}" ]; then
    [ -x "$CBUILD_APK_PATH" ] || die "CBUILD_APK_PATH is not executable: $CBUILD_APK_PATH"
elif ! command -v apk >/dev/null 2>&1; then
    die "host apk-tools 3.x is required for the first bootstrap; see cports/Usage.md"
fi

cd "$ROOT/cports"
if [ ! -f etc/config.ini ]; then
    cp etc/config.ini.example etc/config.ini
    note "created cports/etc/config.ini; generating a local signing key"
    ./cbuild keygen
fi

# cbuild creates this link before it writes the chroot completion marker. If a
# host policy (for example AppArmor userns restrictions) interrupts _prepare,
# the next bootstrap otherwise fails with FileExistsError instead of resuming.
if [ ! -f bldroot/.cbuild_chroot_init ] && \
    [ "$(readlink bldroot/etc/localtime 2>/dev/null || true)" = "../usr/share/zoneinfo/UTC" ]; then
    note "removing stale localtime link from an interrupted bootstrap"
    rm -f bldroot/etc/localtime
fi

./cbuild bootstrap
