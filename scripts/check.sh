#!/bin/sh

set -eu
ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/scripts/lib.sh"

note "checking shell syntax"
for file in "$ROOT"/scripts/*.sh; do
    sh -n "$file"
done

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$ROOT"/scripts/*.sh
else
    note "shellcheck unavailable; skipped lint"
fi

note "checking cports templates"
python3 -m py_compile "$ROOT"/cports/user/*/template.py

note "checking architecture mapping"
[ "$(normalize_arch amd64)" = x86_64 ]
[ "$(normalize_arch arm64)" = aarch64 ]
[ "$(rust_target x86_64)" = x86_64-unknown-linux-musl ]
[ "$(rust_target aarch64)" = aarch64-unknown-linux-musl ]

note "checking Rust formatting and tests"
cargo fmt --manifest-path "$ROOT/cports/user/myos-initrd/files/Cargo.toml" -- --check
CARGO_TARGET_DIR="$ROOT/out/check/myos-initrd" \
    cargo test --manifest-path "$ROOT/cports/user/myos-initrd/files/Cargo.toml" --quiet
cargo fmt --manifest-path "$ROOT/cports/user/myos-system-bus/files/Cargo.toml" -- --check
CARGO_TARGET_DIR="$ROOT/out/check/myos-system-bus" \
    cargo test --locked --manifest-path "$ROOT/cports/user/myos-system-bus/files/Cargo.toml" --quiet

if command -v dbus-run-session >/dev/null 2>&1 && command -v dbus-send >/dev/null 2>&1; then
    note "checking the zbus service over a private D-Bus"
    CARGO_TARGET_DIR="$ROOT/out/check/myos-system-bus" \
        cargo build --locked --manifest-path "$ROOT/cports/user/myos-system-bus/files/Cargo.toml" --quiet
    bus_binary="$ROOT/out/check/myos-system-bus/debug/myos-system-bus"
    # The variables below intentionally expand in the nested shell.
    # shellcheck disable=SC2016
    dbus-run-session -- sh -eu -c '
        export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
        "$1" & service_pid=$!
        trap '\''kill "$service_pid" 2>/dev/null || :'\'' EXIT
        attempts=0
        while ! dbus-send --system --print-reply \
            --dest=org.myos.System1 /org/myos/System1 \
            org.myos.System1.Ping 2>/dev/null | grep -q pong; do
            attempts=$((attempts + 1))
            [ "$attempts" -lt 50 ] || exit 1
            sleep 0.1
        done
    ' sh "$bus_binary"
fi
