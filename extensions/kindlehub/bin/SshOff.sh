#!/bin/bash
# Name: SSH Off
# Author: repair
# DontUseFBInk

## Stops the SSH server and closes the firewall hole again.
## Mirrors KOReader's own stop path: TERM, wait, KILL if it will not go, then
## delete both iptables rules so the port is shut rather than merely unused.

PORT=2222
PIDF=/tmp/dropbear_koreader.pid
OUT=/mnt/us/kindlehub_ssh.txt

FBINK=""
for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
    [ -x "$d/fbink" ] && { FBINK="$d/fbink"; break; }
done
screen() {
    if [ -n "$FBINK" ]; then "$FBINK" -q -y "${2:-1}" "$1" 2>/dev/null
    else eips 1 "${2:-1}" "$1" 2>/dev/null; fi
}

main() {
    echo; echo "SSH off - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - stopping SSH" 2

    if [ -f "$PIDF" ]; then
        P=$(cat "$PIDF" 2>/dev/null)
        if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then
            kill -TERM "$P" 2>/dev/null
            for i in 1 2 3 4 5; do kill -0 "$P" 2>/dev/null || break; sleep 1; done
            kill -0 "$P" 2>/dev/null && { echo "  did not exit, forcing"; kill -KILL "$P" 2>/dev/null; sleep 1; }
        fi
        kill -0 "$P" 2>/dev/null || rm -f "$PIDF"
    fi
    ## belt and braces - any stray dropbear from an earlier run
    for p in $(ps 2>/dev/null | grep '[d]ropbear' | awk '{print $1}'); do
        kill -TERM "$p" 2>/dev/null
    done

    ## Release the wake lock SSH On took. Leaving it held is what stops the
    ## magnetic cover being able to sleep the device.
    lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
    lipc-set-prop com.lab126.wifid enableWifiPowerSave 1 2>/dev/null
    echo "  wake lock released (preventScreenSaver=$(lipc-get-prop com.lab126.powerd preventScreenSaver 2>/dev/null))"

    ## Delete EXACTLY the rules SSH On inserts. -D only removes a rule whose
    ## spec matches verbatim; an earlier version of this deleted a conntrack
    ## variant that was never inserted, so it silently removed nothing and the
    ## port stayed open. The tcp rules are looped in case repeated ON runs
    ## stacked copies. The icmp rule is deleted once: ours sits at the top of
    ## INPUT, so a single -D takes ours and leaves any stock rule alone.
    while iptables -D INPUT  -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; do :; done
    while iptables -D OUTPUT -p tcp --sport "$PORT" -j ACCEPT 2>/dev/null; do :; done
    iptables -D INPUT -p icmp -j ACCEPT 2>/dev/null
    echo "  firewall closed on $PORT"
    iptables -L INPUT -n 2>/dev/null | grep -q "dpt:$PORT" && echo "  WARNING a rule for $PORT is still present" || echo "  no rule for $PORT remains"

    if ps 2>/dev/null | grep -q '[d]ropbear'; then
        echo "  WARNING dropbear still present"
        screen "SSH may still be running - see log" 4
    else
        echo "  stopped"
        screen "                                        " 4
        screen "  SSH IS OFF                            " 3
        screen "  port $PORT closed                     " 5
    fi
    rm -f /mnt/us/kindlehub_ssh_ip.txt 2>/dev/null
    sync
}

{ main; sync; } >> "$OUT" 2>&1 &
exit 0
