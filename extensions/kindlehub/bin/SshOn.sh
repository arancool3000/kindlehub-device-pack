#!/bin/bash
# Name: SSH On (WiFi)
# Author: repair
# DontUseFBInk

## Starts an SSH server over WiFi, using KOReader's bundled dropbear.
##
## FIXES OVER THE FIRST VERSION, both of which actually bit us
##
##   1. iptables -A APPENDS to the end of the chain. If INPUT already contains a
##      blanket REJECT above ours, the ACCEPT is never reached -- and a REJECT
##      with icmp-host-prohibited is reported by the client as exactly
##      "No route to host", which is what we saw. Now uses -I to INSERT at the
##      top so it is evaluated first. (KOReader's own plugin uses -A; that is a
##      latent bug there too.)
##
##   2. The old version printed the address once and the framework's next redraw
##      wiped it. It now redraws periodically, and -- more reliably -- writes
##      the address to /mnt/us/kindlehub_ssh_ip.txt to be read over USB.
##
##   It also reports progress at every step, so a hang can be located instead of
##      sitting on "starting ssh" with no idea which line is stuck, and it
##      verifies dropbear is genuinely LISTENING rather than assuming it started.
##
## SECURITY
##   -s: public key only, no password logins. Only the key in
##   koreader/settings/SSH/authorized_keys can connect. Turn it off with
##   "SSH Off" when done; do not leave it running on public wifi.

PORT=2222
KO=/mnt/us/koreader
PIDF=/tmp/dropbear_koreader.pid
OUT=/mnt/us/kindlehub_ssh.txt
IPF=/mnt/us/kindlehub_ssh_ip.txt

FBINK=""
for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
    [ -x "$d/fbink" ] && { FBINK="$d/fbink"; break; }
done
screen() {
    if [ -n "$FBINK" ]; then "$FBINK" -q -y "${2:-1}" "$1" 2>/dev/null
    else eips 1 "${2:-1}" "$1" 2>/dev/null; fi
}

main() {
    log() { echo "$(date '+%H:%M:%S') $*"; sync; }
    echo "SSH on v2 - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - starting SSH" 2
    screen "step 1/6  checking dropbear         " 4

    [ -x "$KO/dropbear" ] || { log "ABORT no dropbear at $KO"; screen "No dropbear found." 6; return 1; }
    log "dropbear: $(wc -c < "$KO/dropbear") bytes"
    if [ ! -s "$KO/settings/SSH/authorized_keys" ]; then
        log "ABORT no authorized_keys - nothing could log in anyway"
        screen "No key installed - see log" 6; return 1
    fi
    log "authorized_keys: $(wc -l < "$KO/settings/SSH/authorized_keys") key(s)"

    ## ---- keep the device awake ----
    ## This is the thing that actually stopped connections working. The device
    ## was listening on 2222 with the firewall open and the right MAC on the
    ## LAN, but the radio powers down when the screen is off: ARP resolved
    ## during a brief wake, then every ICMP and TCP packet timed out.
    ## SSH is useless on a sleeping station, so hold it awake for the session.
    ## "SSH Off" releases this again -- do not leave it held, it is also what
    ## stops the magnetic cover being able to sleep the device.
    screen "step 2/6  holding device awake       " 4
    lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null
    log "preventScreenSaver = $(lipc-get-prop com.lab126.powerd preventScreenSaver 2>/dev/null)"

    ## ---- wifi ----
    lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null
    ## Ask wifid not to power-save the radio down under us, if it exposes it.
    lipc-set-prop com.lab126.wifid enableWifiPowerSave 0 2>/dev/null
    IP=""
    for i in 1 2 3 4 5 6 7 8 9 10; do
        IP=$(ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p')
        [ -n "$IP" ] && break
        sleep 3
    done
    [ -n "$IP" ] || { log "ABORT no wifi address"; screen "No WiFi. Connect first." 6; return 1; }
    log "address: $IP"

    ## The network details that decide whether the Mac can reach us at all.
    echo; echo "=== NETWORK ==="
    ifconfig wlan0 2>/dev/null | head -4
    echo "  --- routes ---"; route -n 2>/dev/null | head -8 || ip route 2>/dev/null | head -8
    echo "  --- ssid ---";   lipc-get-prop com.lab126.wifid currentEssid 2>/dev/null
    echo "  --- state ---";  lipc-get-prop com.lab126.wifid cmState 2>/dev/null

    ## ---- firewall: INSERT, do not append ----
    screen "step 3/6  opening the firewall      " 4
    echo; echo "=== IPTABLES BEFORE ==="
    iptables -L INPUT -n --line-numbers 2>/dev/null | head -25
    ## remove any stale copies of our own rules first, so repeats do not stack
    while iptables -D INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; do :; done
    while iptables -D OUTPUT -p tcp --sport "$PORT" -j ACCEPT 2>/dev/null; do :; done
    iptables -I INPUT  1 -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null
    iptables -I OUTPUT 1 -p tcp --sport "$PORT" -j ACCEPT 2>/dev/null
    ## ICMP too, so the host is pingable and ARP/diagnostics behave. Remove our
    ## previous copy first so repeated runs do not stack rules SSH Off then has
    ## to peel off one at a time.
    iptables -D INPUT -p icmp -j ACCEPT 2>/dev/null
    iptables -I INPUT  1 -p icmp -j ACCEPT 2>/dev/null
    echo; echo "=== IPTABLES AFTER ==="
    iptables -L INPUT -n --line-numbers 2>/dev/null | head -25
    log "firewall rules inserted at the TOP of INPUT"

    ## ---- dropbear ----
    screen "step 4/6  starting dropbear         " 4
    if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null; then
        log "already running (pid $(cat "$PIDF"))"
    else
        rm -f "$PIDF" 2>/dev/null
        cd "$KO" || return 1
        ./dropbear -E -R -s -p "$PORT" -P "$PIDF" 2>>"$OUT"
        log "dropbear invoked (rc=$?)"
        sleep 3
    fi

    ## ---- prove it is listening ----
    screen "step 5/6  verifying the listener    " 4
    echo; echo "=== LISTENERS ==="
    netstat -ltn 2>/dev/null | grep -E "$PORT|Proto" | head -5
    LISTENING=0
    netstat -ltn 2>/dev/null | grep -q ":$PORT" && LISTENING=1
    ps 2>/dev/null | grep '[d]ropbear' | head -3
    log "listening on $PORT: $LISTENING"

    ## ---- report ----
    screen "step 6/6  done                      " 4
    echo "$IP" > "$IPF"; sync
    if [ "$LISTENING" = "1" ]; then
        log "READY  ssh -p $PORT root@$IP"
        ## Redraw a few times: the framework repaints over fbink output, which
        ## is why the address vanished before it could be read.
        for n in 1 2 3 4 5 6 7 8 9 10; do
            screen "                                        " 3
            screen "  SSH IS ON                             " 3
            screen "  ssh -p $PORT root@$IP" 5
            screen "  key only. run SSH Off when done.      " 7
            screen "  also saved to kindlehub_ssh_ip.txt    " 9
            sleep 6
        done
    else
        log "FAILED not listening - see the dropbear stderr above"
        for n in 1 2 3 4 5; do
            screen "  SSH FAILED TO START                   " 3
            screen "  plug in and send kindlehub_ssh.txt    " 5
            sleep 6
        done
    fi
    sync
}

: > "$OUT" 2>/dev/null
{ main; sync; } >> "$OUT" 2>&1 &
exit 0
