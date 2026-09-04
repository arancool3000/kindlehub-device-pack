#!/bin/bash
# Name: WiFi Fix
# Author: repair
# DontUseFBInk

## Fast reconnect for WPA2-Enterprise (802.1X / EAP) networks -- the ones with a
## username AND password.
##
## WHY THOSE ARE THE SLOW ONES
##   A personal (PSK) network re-joins in seconds. An enterprise network has to
##   run a full EAP exchange with the RADIUS server, and when that fails
##   wpa_supplicant backs off before retrying -- the backoff grows each time.
##   That waiting is almost all of your three minutes: roughly two before the
##   error dialog, then another minute after "try again".
##
##   Cycling the radio -- what the WiFi menu does, and what the first version of
##   this script did -- makes it WORSE: it throws away the association and
##   forces the whole EAP exchange again from scratch. The right move is to tell
##   the supplicant to retry NOW, skipping its backoff timer, and only escalate
##   if that genuinely fails.
##
## ORDER, cheapest first
##   1. wpa_cli reassociate   retry EAP immediately, keeping the config
##   2. wpa_cli reconnect     if it had given up entirely
##   3. DHCP renew            association fine, no address
##   4. radio cycle           last resort, the slow full path
##
## It verifies with real traffic, not wpa_state: the supplicant reports
## COMPLETED before the link actually carries packets.
##
## Nothing is installed and nothing persists.

LOG=/mnt/us/kindlehub_wifi.log
IFACE=wlan0

FBINK=""
for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
    [ -x "$d/fbink" ] && { FBINK="$d/fbink"; break; }
done
screen() {
    if [ -n "$FBINK" ]; then "$FBINK" -q -y "${2:-1}" "$1" 2>/dev/null
    else eips 1 "${2:-1}" "$1" 2>/dev/null; fi
}
log() { echo "$(date '+%H:%M:%S') $*"; sync; }

ip_of()    { ifconfig "$IFACE" 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p'; }
gw_of()    { route -n 2>/dev/null | awk '/^0.0.0.0/{print $2; exit}'; }
essid_of() { iwconfig "$IFACE" 2>/dev/null | sed -n 's/.*ESSID:"\([^"]*\)".*/\1/p'; }

## wpa_cli needs the control socket wpa_supplicant is actually using; the path
## differs between builds, so find it rather than assume /var/run/wpa_supplicant.
WPA=""
WPADIR=""
find_wpa() {
    command -v wpa_cli >/dev/null 2>&1 || return 1
    for d in /var/run/wpa_supplicant /var/run/wpa_supplicant0 /tmp/wpa_supplicant \
             /var/local/wpa_supplicant /var/run; do
        [ -S "$d/$IFACE" ] && { WPADIR="$d"; WPA="wpa_cli -p $d -i $IFACE"; return 0; }
    done
    ## last chance: let wpa_cli use its own default
    wpa_cli -i "$IFACE" status >/dev/null 2>&1 && { WPA="wpa_cli -i $IFACE"; return 0; }
    return 1
}
wstate() { [ -n "$WPA" ] && $WPA status 2>/dev/null | sed -n 's/^wpa_state=//p'; }

works() {
    g=$(gw_of); [ -z "$g" ] && return 1
    ping -c 1 -W 2 "$g" >/dev/null 2>&1
}
wait_up() {
    i=0
    while [ "$i" -lt "$1" ]; do works && return 0; i=$((i+1)); sleep 1; done
    return 1
}

renew_dhcp() {
    killall -q -USR1 udhcpc 2>/dev/null && log "  udhcpc renew signalled"
    if command -v dhclient >/dev/null 2>&1; then
        dhclient -r "$IFACE" >/dev/null 2>&1; dhclient "$IFACE" >/dev/null 2>&1
        log "  dhclient renew run"
    fi
}

main() {
    echo "WiFi fix (enterprise) - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - fixing WiFi" 2
    START=$(cut -d. -f1 /proc/uptime)
    elapsed() { echo $(( $(cut -d. -f1 /proc/uptime) - START )); }

    echo; echo "===== BEFORE ====="
    log "essid   : $(essid_of)"
    log "ip      : $(ip_of)"
    log "gateway : $(gw_of)"
    if find_wpa; then
        log "wpa_cli : yes (socket dir ${WPADIR:-default})"
        log "wpa_state: $(wstate)"
        echo "  --- supplicant status ---"
        $WPA status 2>/dev/null | sed 's/^/    /'
        echo "  --- configured networks ---"
        $WPA list_networks 2>/dev/null | sed 's/^/    /'
    else
        log "wpa_cli : NOT USABLE - falling back to the slow path only"
    fi

    if works; then
        log "already working"
        screen "  WIFI IS ALREADY WORKING               " 3
        return 0
    fi

    ## ---- 1. immediate EAP retry, skipping the backoff ----
    if [ -n "$WPA" ]; then
        screen "1/4  retrying authentication        " 4
        log "wpa_cli reassociate"
        $WPA reassociate 2>/dev/null | sed 's/^/    /'
        if wait_up 20; then
            log "FIXED by reassociate in $(elapsed)s"
            screen "                                        " 4
            screen "  WIFI FIXED  ($(elapsed)s)             " 3
            screen "  forced an immediate re-auth           " 5
            return 0
        fi
        log "  state now: $(wstate)"

        ## ---- 2. it had given up entirely ----
        screen "2/4  reconnecting                   " 4
        log "wpa_cli reconnect"
        $WPA reconnect 2>/dev/null | sed 's/^/    /'
        if wait_up 20; then
            log "FIXED by reconnect in $(elapsed)s"
            screen "                                        " 4
            screen "  WIFI FIXED  ($(elapsed)s)             " 3
            return 0
        fi
        log "  state now: $(wstate)"
    fi

    ## ---- 3. authenticated but no address ----
    if [ -n "$(essid_of)" ] && [ -z "$(ip_of)" ]; then
        screen "3/4  renewing address               " 4
        log "associated but no IP -> DHCP"
        renew_dhcp
        if wait_up 15; then
            log "FIXED by DHCP renew in $(elapsed)s"
            screen "                                        " 4
            screen "  WIFI FIXED  ($(elapsed)s)             " 3
            return 0
        fi
    fi

    ## ---- 4. the slow full path, only now ----
    screen "4/4  full reconnect (slow)          " 4
    log "cycling the radio - this is the slow full EAP path"
    lipc-set-prop com.lab126.cmd wirelessEnable 0 2>/dev/null
    sleep 3
    lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null
    if wait_up 60; then
        log "FIXED by radio cycle in $(elapsed)s"
        screen "                                        " 4
        screen "  WIFI FIXED  ($(elapsed)s)             " 3
        return 0
    fi

    echo; echo "===== STILL DOWN ====="
    log "wpa_state: $(wstate)"
    log "essid    : $(essid_of)"
    log "ip       : $(ip_of)"
    [ -n "$WPA" ] && $WPA status 2>/dev/null | sed 's/^/    /'
    log "GAVE UP after $(elapsed)s"
    screen "                                        " 4
    screen "  COULD NOT RECONNECT                   " 3
    screen "  see kindlehub_wifi.log                " 5
    echo
    echo "  On an enterprise network this usually means the credentials were"
    echo "  rejected or the RADIUS server refused us - the log's wpa_state and"
    echo "  status lines say which. That is not something the device can fix."
    return 1
}

: > "$LOG" 2>/dev/null
{ main; sync; } >> "$LOG" 2>&1 &
exit 0
