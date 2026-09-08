#!/bin/bash
# Name: KindleHub Browser
# Author: repair
# DontUseFBInk

## One tap: fullscreen browser on kindlehub.pro, WITH a way back out.
##
## The order here is the whole point. An earlier version handed over a
## fullscreen browser before the escape gestures existed, which left no way to
## reach KUAL again. So this starts the controls daemon FIRST, confirms it is
## running, and only then goes fullscreen. If the daemon will not start, it
## refuses to hide the bar rather than trapping you.
##
##   1 tap   sleep, exactly as closing the cover does
##   2 taps  show/hide the browser bar
##   3 taps  toggle fullscreen: leave to Home, or bring the browser back
##   cover   closing the magnetic cover sleeps the device
##
## Escape hatch that needs no device access at all: delete
## /mnt/us/kindlehub_fullscreen over USB and the bar comes straight back.

SITE=kindlehub.pro
FSFLAG=/mnt/us/kindlehub_fullscreen
DFLAG=/mnt/us/kindlehub_browserd_on
DAEMON=/mnt/us/extensions/kindlehub/bin/BrowserDaemon.sh
LOG=/mnt/us/kindlehub_browser.log

FBINK=""
for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
    [ -x "$d/fbink" ] && { FBINK="$d/fbink"; break; }
done
screen() {
    if [ -n "$FBINK" ]; then "$FBINK" -q -y "${2:-1}" "$1" 2>/dev/null
    else eips 1 "${2:-1}" "$1" 2>/dev/null; fi
}
log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG" 2>/dev/null; sync; }

main() {
    : > "$LOG" 2>/dev/null
    log "KindleHub Browser starting"
    screen "KindleHub - opening browser" 2

    ## ---- 1. controls first, always ----
    ## Check the PID, not just the flag. A stale flag left by a killed daemon
    ## previously made this think controls were up when they were not, so the
    ## browser went fullscreen with no gestures and no way back.
    ## Look for a live daemon process, not a pid in a file. A recorded pid was
    ## the parent shell's, which exits immediately; once reused, the check said
    ## "already running" and the daemon was never started.
    ALIVE=0
    ps 2>/dev/null | grep -q '[B]rowserDaemon\.sh' && ALIVE=1
    if [ "$ALIVE" = "1" ]; then
        log "controls already running"
    else
        rm -f "$DFLAG" 2>/dev/null
        if [ -x "$DAEMON" ]; then
            screen "starting controls...              " 4
            sh "$DAEMON" >/dev/null 2>&1
            sleep 3
        else
            log "ABORT daemon missing at $DAEMON"
        fi
    fi

    if [ ! -f "$DFLAG" ]; then
        ## Refuse to go fullscreen without an escape route.
        log "controls did not start - NOT hiding the bar"
        screen "                                        " 4
        screen "  Controls did not start.               " 3
        screen "  Opening WITH the bar so you are       " 5
        screen "  not stuck. See kindlehub_browserd.log " 6
        rm -f "$FSFLAG" 2>/dev/null; sync
        lipc-set-prop com.lab126.appmgrd start "app://com.lab126.browser?view=$SITE" 2>/dev/null
        return 1
    fi
    log "controls running"

    ## ---- 2. now it is safe to hide the bar ----
    touch "$FSFLAG"; sync
    log "fullscreen flag set"
    screen "                                        " 4
    screen "  2 taps = bar   3 taps = in/out        " 4

    ## ---- 3. open ----
    lipc-set-prop com.lab126.appmgrd start "app://com.lab126.browser?view=$SITE" 2>/dev/null
    log "browser launched at $SITE"
    sync
}

{ main; sync; } >> "$LOG" 2>&1 &
exit 0
