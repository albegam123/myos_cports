#!/bin/sh

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/scripts/lib.sh"

[ "$#" -ge 1 ] || die "usage: $0 KERNEL_CONFIG [amd64|arm64]"
CONFIG=$1
ARCH=$(normalize_arch "${2:-amd64}")
[ -f "$CONFIG" ] || die "kernel config not found: $CONFIG"

failed=0
for requirements in "$ROOT/config/kernel-required.common" "$ROOT/config/kernel-required.$ARCH"; do
    while IFS= read -r requirement; do
        case "$requirement" in ''|'#'*) continue ;; esac
        if ! grep -qxF "$requirement" "$CONFIG"; then
            printf 'missing: %s\n' "$requirement" >&2
            failed=1
        fi
    done <"$requirements"
done

[ "$failed" -eq 0 ] || die "kernel cannot satisfy the module-free initrd contract"
note "kernel config satisfies the $ARCH initrd contract"
