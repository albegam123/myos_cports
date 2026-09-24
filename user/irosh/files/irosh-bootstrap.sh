#!/bin/sh

set -u

LOG=/var/log/irosh-connect-info.log
START_OUTPUT=
WORMHOLE_OUTPUT=
STATUS_OUTPUT=

mkdir -p /var/log

START_OUTPUT=$(/usr/bin/irosh --json system start 2>&1)
start_status=$?

attempt=0
while [ "$attempt" -lt 30 ]; do
    WORMHOLE_OUTPUT=$(/usr/bin/irosh --yes --json wormhole --persistent 2>&1)
    wormhole_status=$?
    [ "$wormhole_status" -eq 0 ] && break
    attempt=$((attempt + 1))
    sleep 1
done

STATUS_OUTPUT=$(/usr/bin/irosh --json system status 2>&1)
status_status=$?

{
    printf '\n============================================================\n'
    printf ' MyOS IROSH REMOTE ACCESS\n'
    printf ' Connection details are also saved in: %s\n' "$LOG"
    printf '============================================================\n'
    printf 'irosh system start (exit=%s):\n%s\n' "$start_status" "$START_OUTPUT"
    printf 'irosh wormhole --persistent (exit=%s):\n%s\n' \
        "${wormhole_status:-1}" "$WORMHOLE_OUTPUT"
    printf 'irosh system status (exit=%s):\n%s\n' "$status_status" "$STATUS_OUTPUT"
    printf '============================================================\n\n'
} | tee -a "$LOG" /dev/console

[ "$start_status" -eq 0 ] && [ "${wormhole_status:-1}" -eq 0 ]
