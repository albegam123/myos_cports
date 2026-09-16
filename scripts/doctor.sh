#!/bin/sh

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/scripts/lib.sh"

failed=0
for cmd in python3 git cargo rustc cpio zstd tar sha256sum readelf; do
    if command -v "$cmd" >/dev/null 2>&1; then
        printf 'ok   %-12s %s\n' "$cmd" "$(command -v "$cmd")"
    else
        printf 'MISS %-12s required\n' "$cmd"
        failed=1
    fi
done

for cmd in apk bwrap; do
    case "$cmd" in
        apk) override=${CBUILD_APK_PATH:-} ;;
        bwrap) override=${CBUILD_BWRAP_PATH:-} ;;
    esac
    if [ -n "$override" ] && [ -x "$override" ]; then
        printf 'ok   %-12s %s\n' "$cmd" "$override"
    elif command -v "$cmd" >/dev/null 2>&1; then
        printf 'ok   %-12s %s\n' "$cmd" "$(command -v "$cmd")"
    else
        printf 'WARN %-12s needed for cports bootstrap/package builds\n' "$cmd"
    fi
done

pyver=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || printf 0)
python3 -c 'import sys; raise SystemExit(sys.version_info < (3, 12))' 2>/dev/null || {
    printf 'MISS python       cbuild requires Python >= 3.12 (found %s)\n' "$pyver"
    failed=1
}

[ -x "$ROOT/cports/cbuild" ] || {
    printf 'MISS cports       cports/cbuild is absent or not executable\n'
    failed=1
}

if [ "$(id -u)" -eq 0 ]; then
    printf 'WARN user         cbuild intentionally refuses to build as root\n'
else
    printf 'ok   user         non-root cbuild execution\n'
fi

if [ -r /proc/sys/kernel/apparmor_restrict_unprivileged_userns ] && \
    [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)" = 1 ]; then
    printf 'WARN apparmor     unprivileged user namespaces are restricted; cbuild bwrap may be blocked\n'
    printf '                  Ubuntu build hosts need: sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0\n'
fi

[ "$failed" -eq 0 ] || exit 1
