#!/bin/sh

set -u

LOG=/var/log/irosh-connect-info.log
TMP_LOG="${LOG}.tmp.$$"
CMD_OUTPUT="/run/irosh-bootstrap.$$.out"
STATUS_OUTPUT=
WORMHOLE_OUTPUT=

# Dinit's boot environment does not necessarily define HOME. Pin both the
# daemon and every management command to the state path that root's login CLI
# resolves by default, so post-login `irosh system status` reaches the same IPC
# socket created at boot.
IROSH_STATE=/root/.irosh/server
export IROSH_STATE

cleanup() {
    rm -f "$TMP_LOG" "$CMD_OUTPUT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p /var/log

publish() {
    # stdout is retained by dinit in irosh-bootstrap.log; /dev/console makes
    # progress visible before a user logs in.
    printf '%s\n' "$1" | tee /dev/console
}

publish_file() {
    tee /dev/console <"$1"
}

run_irosh() {
    _timeout=$1
    shift
    /usr/bin/timeout "$_timeout" /usr/bin/irosh "$@" >"$CMD_OUTPUT" 2>&1
    command_status=$?
    command_output=$(cat "$CMD_OUTPUT")
}

json_succeeded() {
    printf '%s\n' "$1" | grep -q '"success"[[:space:]]*:[[:space:]]*true'
}

json_value() {
    _key=$1
    printf '%s\n' "$2" |
        sed -n "s/.*\"${_key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" |
        sed -n '1p'
}

write_initial_log() {
    {
        printf '\n============================================================\n'
        printf ' MyOS IROSH REMOTE ACCESS: INITIALIZING\n'
        printf '============================================================\n'
        printf 'The dinit service is starting. Connection details will replace\n'
        printf 'this message automatically when the daemon IPC is ready.\n\n'
        printf 'Status: dinitctl status irosh\n'
        printf 'Logs:   /var/log/irosh.log\n'
        printf '        /var/log/irosh-bootstrap.log\n'
        printf '        %s\n' "$LOG"
        printf '============================================================\n\n'
    } >"$TMP_LOG"
    chmod 0644 "$TMP_LOG"
    mv -f "$TMP_LOG" "$LOG"
    publish_file "$LOG"
}

write_final_log() {
    _result=$1
    _endpoint=$2
    _ticket=$3
    _wormhole=$4

    {
        printf '\n============================================================\n'
        printf ' MyOS IROSH REMOTE ACCESS: %s\n' "$_result"
        printf '============================================================\n'
        printf 'Endpoint ID : %s\n' "${_endpoint:-unavailable}"
        printf 'Ticket      : %s\n' "${_ticket:-unavailable}"
        printf 'Wormhole    : %s\n' "${_wormhole:-unavailable}"
        if [ -n "$_wormhole" ]; then
            printf 'Connect     : irosh connect --code %s\n' "$_wormhole"
        fi
        printf '\nConnection details: %s\n' "$LOG"
        printf 'Service log:       /var/log/irosh.log\n'
        printf 'Bootstrap log:     /var/log/irosh-bootstrap.log\n'
        printf '============================================================\n\n'
    } >"$TMP_LOG"
    chmod 0644 "$TMP_LOG"
    mv -f "$TMP_LOG" "$LOG"
    publish_file "$LOG"
}

write_initial_log

publish 'Starting irosh through dinit (irosh system start)...'
run_irosh 20 --json system start
start_status=$command_status
if [ -n "$command_output" ]; then
    publish "$command_output"
fi
if [ "$start_status" -ne 0 ]; then
    publish "irosh system start exited with status $start_status; checking daemon IPC anyway."
fi

# A dinit process service is STARTED as soon as the process is launched, while
# irosh still needs time to initialize its endpoint and IPC socket. Poll status
# before invoking `wormhole`; otherwise the CLI can fall back to a competing
# foreground server when daemon IPC is not ready yet.
daemon_ready=0
attempt=1
while [ "$attempt" -le 30 ]; do
    run_irosh 5 --json system status
    STATUS_OUTPUT=$command_output
    if [ "$command_status" -eq 0 ] && json_succeeded "$STATUS_OUTPUT" &&
        printf '%s\n' "$STATUS_OUTPUT" | grep -q '"endpoint_id"'; then
        daemon_ready=1
        publish "irosh daemon IPC is ready (attempt $attempt/30)."
        break
    fi
    publish "Waiting for irosh daemon IPC (attempt $attempt/30, exit=$command_status)..."
    attempt=$((attempt + 1))
    sleep 1
done

wormhole_ready=0
if [ "$daemon_ready" -eq 1 ]; then
    attempt=1
    while [ "$attempt" -le 5 ]; do
        run_irosh 15 --yes --json wormhole --persistent
        WORMHOLE_OUTPUT=$command_output
        if [ "$command_status" -eq 0 ] && json_succeeded "$WORMHOLE_OUTPUT" &&
            printf '%s\n' "$WORMHOLE_OUTPUT" | grep -q '"mode"[[:space:]]*:[[:space:]]*"daemon"'; then
            wormhole_ready=1
            publish "Persistent wormhole is enabled (attempt $attempt/5)."
            break
        fi
        publish "Could not enable the persistent wormhole (attempt $attempt/5, exit=$command_status)."
        [ -z "$WORMHOLE_OUTPUT" ] || publish "$WORMHOLE_OUTPUT"
        attempt=$((attempt + 1))
        sleep 1
    done
else
    publish 'irosh daemon IPC did not become ready; wormhole activation was skipped.'
fi

# Always query status after the wormhole attempt. Even if discovery setup
# fails, this response still contains the direct Endpoint ID and Ticket.
run_irosh 15 --json system status
final_status=$command_status
if [ "$final_status" -eq 0 ] && json_succeeded "$command_output" &&
    printf '%s\n' "$command_output" | grep -q '"endpoint_id"'; then
    STATUS_OUTPUT=$command_output
fi

endpoint_id=$(json_value endpoint_id "$STATUS_OUTPUT")
ticket=$(json_value ticket "$STATUS_OUTPUT")
wormhole_code=$(json_value wormhole_code "$STATUS_OUTPUT")
[ -n "$wormhole_code" ] || wormhole_code=$(json_value code "$WORMHOLE_OUTPUT")

if [ -n "$endpoint_id" ] && [ -n "$ticket" ] &&
    [ "$wormhole_ready" -eq 1 ] && [ -n "$wormhole_code" ]; then
    write_final_log READY "$endpoint_id" "$ticket" "$wormhole_code"
    exit 0
fi

write_final_log DEGRADED "$endpoint_id" "$ticket" "$wormhole_code"
publish 'Irosh did not become fully ready. Diagnostic command responses follow.'
if [ -n "$STATUS_OUTPUT" ]; then
    publish 'system status:'
    publish "$STATUS_OUTPUT"
fi
if [ -n "$WORMHOLE_OUTPUT" ]; then
    publish 'wormhole:'
    publish "$WORMHOLE_OUTPUT"
fi
exit 1
