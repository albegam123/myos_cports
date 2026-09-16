#!/bin/sh

set -eu

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

note() {
    printf '==> %s\n' "$*" >&2
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

normalize_arch() {
    case "$1" in
        amd64|x86_64) printf '%s\n' x86_64 ;;
        arm64|aarch64) printf '%s\n' aarch64 ;;
        *) die "unsupported architecture '$1' (use amd64/x86_64 or arm64/aarch64)" ;;
    esac
}

rust_target() {
    case "$(normalize_arch "$1")" in
        x86_64) printf '%s\n' x86_64-unknown-linux-musl ;;
        aarch64) printf '%s\n' aarch64-unknown-linux-musl ;;
    esac
}

repo_root() {
    CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd
}

read_package_file() {
    sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$1"
}

sha_sidecar() {
    artifact=$1
    (cd "$(dirname "$artifact")" && sha256sum "$(basename "$artifact")" >"$(basename "$artifact").sha256")
}

is_static_elf() {
    readelf -l "$1" 2>/dev/null | grep -q 'INTERP' && return 1
    readelf -h "$1" >/dev/null 2>&1
}
