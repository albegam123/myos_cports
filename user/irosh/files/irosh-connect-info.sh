# Show the remote-access coordinates on every console login. The bootstrap
# writes this file atomically, so readers see either INITIALIZING or a complete
# READY/DEGRADED record.
if [ -t 1 ]; then
    if [ -r /var/log/irosh-connect-info.log ]; then
        cat /var/log/irosh-connect-info.log
    else
        printf '\nIrosh remote access is initializing. Details will be saved in:\n'
        printf '  /var/log/irosh-connect-info.log\n\n'
    fi
fi
