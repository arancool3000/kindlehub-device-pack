#!/bin/bash
# Name: Uninstall Everything
# Author: KindleHub
# DontUseFBInk

## Removes every KindleHub change and puts the device back to stock.
##
## WHY IT WAITS BETWEEN STEPS
##   Each Undo script backgrounds itself and returns immediately, and most of
##   them remount / read-write. Run back to back they would overlap, and the
##   first one to finish would remount / read-only underneath the others --
##   which is exactly how / was once left mounted rw by a half-finished script.
##   So this waits for / to be read-only again before starting the next step,
##   and gives up on that step rather than racing it.
##
## WHAT IT DOES NOT TOUCH
##   * /mnt/us/kindlehub_theme_backup   the originals. Deleting these would
##     make a later Undo impossible, so they stay until you remove them.
##   * /mnt/us/extensions/kindlehub     this menu. Removing it mid-run would
##     delete the script that is running.
##   Both are yours to delete over USB once you are happy with the result.

BIN=/mnt/us/extensions/kindlehub/bin
BAK=/mnt/us/kindlehub_theme_backup
LOG=/mnt/us/kindlehub_uninstall.log

FBINK=""
for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
    [ -x "$d/fbink" ] && { FBINK="$d/fbink"; break; }
done
screen() {
    if [ -n "$FBINK" ]; then "$FBINK" -q -y "${2:-1}" "$1" 2>/dev/null
    else eips 1 "${2:-1}" "$1" 2>/dev/null; fi
}
log() { echo "$(date '+%H:%M:%S') $*"; sync; }

root_is_ro() { mount 2>/dev/null | grep ' / ' | grep -q '(ro'; }

wait_ro() {  # wait_ro <seconds>
    i=0
    while [ "$i" -lt "${1:-40}" ]; do
        root_is_ro && return 0
        sleep 1; i=$((i+1))
    done
    return 1
}

OK=0; FAIL=0
undo() {  # undo <label> <script> <settle-seconds>
    if [ ! -f "$BIN/$2" ]; then
        log "SKIP $1 (no $2)"; FAIL=$((FAIL+1)); return 1
    fi
    if ! wait_ro 40; then
        log "SKIP $1 (/ still read-write after 40s - refusing to race it)"
        FAIL=$((FAIL+1)); return 1
    fi
    log "--- $1 ---"
    sh "$BIN/$2" >/dev/null 2>&1
    sleep "${3:-6}"
    OK=$((OK+1))
    return 0
}

main() {
    echo "KindleHub Uninstall - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "                                        " 2
    screen "  KINDLEHUB UNINSTALL                   " 2
    screen "  this takes a couple of minutes        " 4

    mount 2>/dev/null | grep -q " /mnt/us " || {
        log "ABORT eject the USB cable first"; screen "Eject the cable first" 6; return 1; }

    if [ ! -d "$BAK" ]; then
        log "WARN no backup folder at $BAK"
        log "     the Undo steps restore from it, so most will find nothing to do"
    else
        log "backups present: $(find "$BAK" -type f 2>/dev/null | wc -l) file(s)"
    fi

    ## Order matters. Stop the daemon first so nothing is watching the button
    ## while the rest changes underneath it, and leave the icons until last
    ## because that step touches the most files and takes the longest.
    screen "1/6  browser controls off            " 6
    undo "browser controls off" BrowserDaemonOff.sh 4

    screen "2/6  swipe-back on                   " 6
    undo "swipe-back back on" SwipeBackOn.sh 8

    screen "3/6  restoring /sbin/reboot          " 6
    undo "Amazon's restart back" RestartDivertUndo.sh 8

    screen "4/6  restart artwork off             " 6
    undo "restart artwork off" CustomRestartUndo.sh 8

    screen "5/6  fullscreen off                  " 6
    undo "fullscreen off" FullscreenOff.sh 10

    screen "6/6  restoring icons                 " 6
    undo "icons off" IconsUndo.sh 20

    ## ---- leftover state ----
    log "--- clearing flags and logs ---"
    rm -f /mnt/us/kindlehub_fullscreen 2>/dev/null
    rm -f /mnt/us/kindlehub_browserd_on 2>/dev/null
    rm -f /mnt/us/kindlehub_reboot.sh 2>/dev/null
    rm -rf /mnt/us/kindlehub_theme 2>/dev/null
    for f in /mnt/us/kindlehub_*.log; do [ -f "$f" ] && [ "$f" != "$LOG" ] && rm -f "$f"; done
    log "flags, staged payload and old logs removed"

    ## ---- report ----
    wait_ro 40 || log "WARN / is STILL read-write - run Health Check before restarting"
    echo; echo "===== RESULT ====="
    log "$OK step(s) ran, $FAIL skipped"
    echo
    echo "  / is: $(mount | grep ' / ' | grep -o '(r[ow]')"
    echo "  window manager: $(md5sum /etc/xdg/awesome/lab126_application_layer.lua 2>/dev/null | awk '{print $1}')"
    if [ -s "$BAK/lab126_application_layer.lua.orig.md5" ]; then
        echo "    ($(head -1 "$BAK/lab126_application_layer.lua.orig.md5") is Amazon's original on this device)"
    else
        echo "    (27ab0e2ec6519eb0428418493bd783f8 is Amazon's original on a Paperwhite 11 / 5.19.2)"
    fi
    grep -q 'KindleHub' /etc/xdg/awesome/lab126_application_layer.lua 2>/dev/null \
        && echo "    STILL PATCHED - run Undo > Fullscreen OFF again" \
        || echo "    no KindleHub lines remain in it"
    echo "  /sbin/reboot:   $(head -1 /sbin/reboot 2>/dev/null | cut -c1-40)"
    echo
    echo "  Still on the device, on purpose:"
    echo "    $BAK"
    echo "      the original files. Delete this over USB once you are happy."
    echo "    /mnt/us/extensions/kindlehub"
    echo "      this menu. Delete it over USB to remove KindleHub from KUAL."
    echo
    echo "  RESTART to finish."

    screen "                                        " 4
    screen "                                        " 6
    screen "  UNINSTALL COMPLETE                    " 2
    screen "  $OK steps ran, $FAIL skipped           " 4
    screen "                                        " 6
    screen "  RESTART NOW                           " 6
    sync
}

: > "$LOG" 2>/dev/null
{ main; sync; } >> "$LOG" 2>&1 &
exit 0
