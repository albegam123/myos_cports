#!/bin/sh

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/scripts/lib.sh"

ARCH=$(normalize_arch "${1:-amd64}")
[ "$(id -u)" -ne 0 ] || die "cbuild must run as a non-root user"
if [ -r /proc/sys/kernel/apparmor_restrict_unprivileged_userns ] && \
    [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)" = 1 ]; then
    die "AppArmor blocks unprivileged user namespaces; run make doctor for the host setting"
fi
[ -x "$ROOT/cports/cbuild" ] || die "missing cports/cbuild"
[ -x "$ROOT/cports/bldroot/usr/bin/apk.static" ] || die "run 'make bootstrap' first"
[ -f "$ROOT/cports/etc/config.ini" ] || die "run 'make bootstrap' first"

note "building the selected MyOS components from source for $ARCH"
cd "$ROOT/cports"
# The selected distribution components are always explicit source builds.
# Their compiler/toolchain dependencies use the signed cports bootstrap by
# default so the first minimal image does not rebuild LLVM, Rust and Python.
# FULL_SOURCE=1 retains the expensive bootstrap-every-dependency mode.
no_remote=
source_runtime=
if [ "${FULL_SOURCE:-0}" = 1 ]; then
    no_remote=-N
    # dinit-chimera records command/SONAME runtime dependencies.  When remote
    # repositories are disabled, their concrete providers must exist in the
    # local repository even if dinit-chimera itself was built by an earlier
    # non-FULL_SOURCE run.
    source_runtime="main/kmod main/shadow main/snooze main/util-linux"
fi
# shellcheck disable=SC2086
./cbuild -c ../config/cbuild.ini -a "$ARCH" $no_remote pkg \
    $source_runtime \
    main/dinit \
    main/dbus \
    main/dinit-chimera \
    main/dinit-dbus \
    main/iwd \
    user/armybox \
    user/myos-initrd \
    user/myos-system-bus \
    user/myos-base
